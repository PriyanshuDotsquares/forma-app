"""AI-driven exercise selection and programming for a user's workout
program, layered on top of `plan_generator`'s deterministic split/day
skeleton (see that module's docstring — the skeleton logic already encodes
sound programming rules like valid split/day-count pairings and rest
spacing, and stays untouched here; this module only decides *which
exercises* and *how they're programmed* for each day, which is where
per-user personalization — goal, equipment, injuries — actually shows up).

`generate_program_smart` is the only function callers should use. It never
raises for AI-specific reasons: any failure (Groq API error, invalid or
truncated structured output, a referenced exercise slug that doesn't exist)
falls back to `plan_generator.generate_program`, so `POST /programs/generate`
— the single most fragile, most user-visible path in the app (onboarding) —
keeps working exactly as it always has even when the AI path is unavailable
or misbehaves. Skips the AI attempt entirely (no network call) when
`GROQ_API_KEY` isn't configured, so any environment without that key behaves
identically to before this module existed.
"""

import json
import logging
from typing import Any, Literal

from groq import AsyncGroq
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.config import get_settings
from app.models.exercise import Exercise
from app.models.program import Program, ProgramDay, ProgramExercise
from app.models.user import User
from app.services import plan_generator
from app.services.ai_utils import generate_structured, max_tokens_for, strict_schema

logger = logging.getLogger(__name__)

LoadType = Literal["weight", "percent_1rm", "rpe"]


class ProgramExerciseGen(BaseModel):
    exercise_slug: str = Field(description="must be exactly one of the provided exercise slugs")
    sets: int = Field(ge=1, le=6)
    # Upper bound covers duration-based holds (e.g. a plank) represented as
    # "reps" in seconds, not just rep counts — confirmed necessary on a real
    # run where the model picked "plank" and wanted a 30-60 range for it.
    rep_range_low: int = Field(ge=1, le=60)
    rep_range_high: int = Field(ge=1, le=90)
    load_type: LoadType
    tempo: str | None = Field(default=None, description="e.g. '3-1-1' eccentric-pause-concentric seconds, or null")
    superset_group: str | None = Field(default=None, description="short label shared by exercises supersetted together, or null")
    notes: str | None = Field(default=None, description="a short coaching note, e.g. an injury caution — or null")


class ProgramDayGen(BaseModel):
    label: str = Field(description="must exactly match one of the provided day labels")
    exercises: list[ProgramExerciseGen] = Field(min_length=1, max_length=10)


class ProgramBatch(BaseModel):
    days: list[ProgramDayGen]


_PROMPT = """You are programming a {days_per_week}-day/week strength-training week for a FORMA app user.

User profile:
- Goal: {goal}
- Experience level: {experience_level}
- Session length: ~{session_minutes} minutes ({per_day_count} exercises/day is a good target)
- Equipment available: {equipment}
{injuries_block}
The week's day structure is already decided — do NOT change the days, their labels, or their target muscle groups. There are exactly {days_per_week} days listed below, numbered in order, and your response MUST contain exactly {days_per_week} entries in `days`, **in the same order** (position 1 in your response = day 1 below, etc.) — the `label` is not a unique key, some days below intentionally reuse the same label (e.g. "Push" can appear twice in a 6-day push/pull/legs split, or "Upper A"/"Upper B" share the same target muscles) — each numbered occurrence is still a SEPARATE required entry, never merge same-label days into one, and give each its own distinct exercise selection so the week doesn't just repeat itself. For EACH day below, choose exercises from the provided catalog and program them (sets, rep range, load type, optional tempo/superset/notes):

{days_block}

Exercise catalog (choose `exercise_slug` ONLY from these — you cannot invent exercises):
{catalog}

Rules:
- Prioritize each day's target muscle groups; a compound exercise covering multiple target muscles is a good pick.
- Vary exercise choices across days — don't repeat the same exercise twice in the week unless the catalog genuinely has nothing else for a muscle group.
- `sets`/`rep_range_low`/`rep_range_high` should suit the user's goal (e.g. lower reps/heavier for strength goals, higher reps for general health/fat loss).
- `load_type` is "weight" for anything with external load, "rpe" only if the user should work by feel instead of a fixed target, "percent_1rm" only for a clear strength-focused compound lift.
- If two exercises are meant to be done back-to-back as a superset, give them the same short `superset_group` value (e.g. "A"); leave it null otherwise.
- Set `notes` on an exercise only when there's something genuinely useful to say (e.g. an injury caution) — null otherwise.
{injuries_rule}
Return exactly one entry in `days` per numbered day above, in that same order.
"""

_INJURIES_BLOCK_TEMPLATE = "\nInjuries/limitations to account for: {injuries}\n"
_INJURIES_RULE = (
    '- The user has flagged injuries above. For any body part marked "avoid", do NOT pick an exercise whose '
    'primary mover loads that joint/region. For "moderate" or "mild", you may still pick related exercises but '
    "prefer lighter/controlled variants and set `notes` with a short caution.\n"
)

# The prompt rule above is a request, not a guarantee — confirmed on a real
# run where the model picked a knee-loading exercise for an "avoid knee"
# injury anyway (adding a caution note instead of excluding it, which is the
# "moderate"/"mild" behavior, not "avoid"). Injury avoidance is safety-
# relevant, not just a quality nicety, so it gets a deterministic backstop:
# any `severity: "avoid"` body part hard-excludes exercises whose primary
# mover is in the mapped tag set below, enforced as a validation failure
# (→ triggers the same fallback as any other bad AI output) rather than
# trusted to prompt-following alone. Coach-heuristic level, same spirit as
# `form_heuristics.dart`'s disclaimed "not a biomechanical assessment"
# approach — not a claim of medical/PT-level accuracy, and deliberately
# scoped to the 6 body zones `step7_injuries.dart` actually lets a user tap.
_INJURY_AVOID_MUSCLE_MAP: dict[str, set[str]] = {
    "knee": {"quads"},
    "hip": {"quads", "hamstrings", "glutes"},
    "back": {"back"},
    "shoulder": {"shoulders"},
    "chest": {"chest"},
    "elbow": {"biceps", "triceps"},
}


def _avoided_muscles(injuries: list[dict[str, Any]]) -> set[str]:
    avoided: set[str] = set()
    for injury in injuries:
        if injury.get("severity") == "avoid":
            avoided |= _INJURY_AVOID_MUSCLE_MAP.get(injury.get("part", ""), set())
    return avoided


def _format_exercise_catalog(exercises: list[Exercise]) -> str:
    # Only slug/name/primary_muscles/equipment — secondary_muscles and
    # difficulty aren't referenced by any prompt rule, and every token here
    # is pure overhead: this whole catalog is resent on every call, and
    # Groq's on-demand tier rate-limits on tokens/minute (prompt + requested
    # output combined) — confirmed hitting an 8000 TPM cap on a real 4-day
    # request with the fuller catalog + pretty-printed JSON. Compact JSON
    # (no `indent=`) trims further; both matter more as the seeded exercise
    # library grows (e.g. via `app.db.ai_seed`).
    catalog = [{"slug": e.slug, "name": e.name, "primary_muscles": e.primary_muscles, "equipment": e.equipment} for e in exercises]
    return json.dumps(catalog)


def _build_prompt(
    day_plans: list[plan_generator._DayPlan],
    exercises: list[Exercise],
    *,
    goal: str | None,
    experience_level: str | None,
    session_minutes: int | None,
    per_day_count: int,
    equipment: list[str],
    injuries: list[dict[str, Any]],
) -> str:
    days_block = "\n".join(f'{i}. "{p.label}": target muscles {p.muscle_tags}' for i, p in enumerate(day_plans, start=1))
    injuries_block = _INJURIES_BLOCK_TEMPLATE.format(injuries=json.dumps(injuries)) if injuries else ""
    injuries_rule = _INJURIES_RULE if injuries else ""
    return _PROMPT.format(
        days_per_week=len(day_plans),
        goal=goal or "general_health",
        experience_level=experience_level or "new",
        session_minutes=session_minutes or 60,
        per_day_count=per_day_count,
        equipment=equipment or ["bodyweight"],
        injuries_block=injuries_block,
        days_block=days_block,
        catalog=_format_exercise_catalog(exercises),
        injuries_rule=injuries_rule,
    )


async def generate_program_ai(
    db: AsyncSession,
    *,
    user: User,
    goal: str | None,
    experience_level: str | None,
    days_per_week: int,
    session_minutes: int | None,
    split_preference: str | None,
    equipment: list[str],
    injuries: list[dict[str, Any]],
) -> Program:
    settings = get_settings()
    client = AsyncGroq(api_key=settings.groq_api_key)

    split_type = plan_generator._resolve_split(split_preference, days_per_week)
    day_plans = plan_generator._build_day_plans(split_type, days_per_week)
    per_day_count = plan_generator._exercises_per_day(session_minutes)
    available_equipment = set(equipment) | {"bodyweight"}

    all_exercises = list((await db.scalars(select(Exercise))).all())
    candidate_exercises = [e for e in all_exercises if (set(e.equipment) & available_equipment) or not e.equipment]
    exercise_by_slug = {e.slug: e for e in candidate_exercises}

    prompt = _build_prompt(
        day_plans,
        candidate_exercises,
        goal=goal,
        experience_level=experience_level,
        session_minutes=session_minutes,
        per_day_count=per_day_count,
        equipment=equipment,
        injuries=injuries,
    )
    tokens = max_tokens_for(len(day_plans) * per_day_count, per_item=120, base=800)

    # Force exactly one `days` entry per skeleton day at the JSON-schema
    # level — without this, the model can decide two same-muscle days (an
    # "Upper A"/"Upper B" pair) are redundant and only emit one, which still
    # passes basic schema validation but silently drops a day (confirmed:
    # this happened on a real run before this constraint was added).
    program_schema = strict_schema(ProgramBatch)
    program_schema["properties"]["days"]["minItems"] = len(day_plans)
    program_schema["properties"]["days"]["maxItems"] = len(day_plans)

    # Everything above/here can fail (Groq API error, schema-validate 400,
    # an invalid/missing day or exercise slug) *before* any DB mutation —
    # deliberately structured so a failure never leaves a half-written
    # program: nothing below this point can run unless generation and
    # validation both fully succeeded.
    batch = await generate_structured(client, ProgramBatch, "program_batch", prompt, tokens, schema=program_schema)
    assert isinstance(batch, ProgramBatch)

    # Correlate `batch.days` with `day_plans` *positionally*, not by a
    # label lookup: push_pull_legs/body_part splits reuse the same label
    # twice or more with no A/B suffix (unlike upper_lower's "Upper A"/
    # "Upper B") — a label->day dict silently collapses repeated labels to
    # one entry, so every occurrence of e.g. "Push" ends up pointing at the
    # exact same generated exercises. Confirmed on a real 6-day PPL run:
    # both Push days, both Pull days, and both Legs days came back with
    # byte-for-byte identical exercise lists because of exactly this.
    if len(batch.days) != len(day_plans):
        raise ValueError(f"AI returned {len(batch.days)} days, expected {len(day_plans)}")

    avoided_muscles = _avoided_muscles(injuries)
    for plan, gen_day in zip(day_plans, batch.days):
        if gen_day.label != plan.label:
            raise ValueError(f"AI day order mismatch at this position: expected {plan.label!r}, got {gen_day.label!r}")
        if not gen_day.exercises:
            raise ValueError(f"AI response missing exercises for day {plan.label!r}")
        for item in gen_day.exercises:
            exercise = exercise_by_slug.get(item.exercise_slug)
            if exercise is None:
                raise ValueError(f"AI referenced unknown exercise slug {item.exercise_slug!r}")
            if avoided_muscles & set(exercise.primary_muscles):
                raise ValueError(
                    f"AI picked {item.exercise_slug!r} (primary_muscles={exercise.primary_muscles}) despite an "
                    f"'avoid' injury covering {avoided_muscles} — deterministic safety check, not trusting the prompt alone"
                )

    # Deactivate any previously-active generated program so there's one
    # current plan at a time — same rule `generate_program` follows.
    existing_active = await db.scalars(select(Program).where(Program.owner_id == user.id, Program.is_active == True))  # noqa: E712
    for p in existing_active:
        p.is_active = False

    program = Program(
        owner_id=user.id,
        name="Built for Strength" if (goal or "") == "get_stronger" else "Your Program",
        split_type=split_type,
        days_per_week=days_per_week,
        duration_weeks=8,
        source="ai_generated",
        is_active=True,
    )
    db.add(program)
    await db.flush()  # assigns program.id; avoids lazy-loading program.days under asyncio

    for order_index, (plan, gen_day) in enumerate(zip(day_plans, batch.days)):
        day = ProgramDay(
            program_id=program.id,
            order_index=order_index,
            weekday=plan.weekday,
            label=plan.label,
            muscle_tags=plan.muscle_tags,
            is_rest=False,
            estimated_minutes=session_minutes,
        )
        db.add(day)
        await db.flush()  # assigns day.id; avoids lazy-loading day.exercises under asyncio

        for i, item in enumerate(gen_day.exercises):
            exercise = exercise_by_slug[item.exercise_slug]
            db.add(
                ProgramExercise(
                    program_day_id=day.id,
                    exercise_id=exercise.id,
                    order_index=i,
                    sets=item.sets,
                    rep_range_low=item.rep_range_low,
                    rep_range_high=item.rep_range_high,
                    load_type=item.load_type,
                    tempo=item.tempo,
                    superset_group=item.superset_group,
                    notes=item.notes,
                    coach_with_camera=exercise.supports_camera and i == 0,
                )
            )

    await db.commit()

    result = await db.scalars(
        select(Program)
        .where(Program.id == program.id)
        .options(selectinload(Program.days).selectinload(ProgramDay.exercises).selectinload(ProgramExercise.exercise))
    )
    return result.one()


async def generate_program_smart(
    db: AsyncSession,
    *,
    user: User,
    goal: str | None,
    experience_level: str | None,
    days_per_week: int,
    session_minutes: int | None,
    split_preference: str | None,
    equipment: list[str],
    injuries: list[dict[str, Any]],
) -> Program:
    settings = get_settings()
    deterministic_kwargs: dict[str, Any] = dict(
        user=user,
        goal=goal,
        experience_level=experience_level,
        days_per_week=days_per_week,
        session_minutes=session_minutes,
        split_preference=split_preference,
        equipment=equipment,
    )

    if not settings.groq_api_key:
        return await plan_generator.generate_program(db, **deterministic_kwargs)

    user_id = user.id  # captured now — `db.rollback()` below expires every ORM object in the
    # session (independent of `expire_on_commit`, which only governs commit), and the plain
    # deterministic `generate_program` accesses `user.id` synchronously while building a query
    # (`Program.owner_id == user.id`, before anything is awaited) — on an expired instance that
    # triggers an implicit lazy-load outside async context and crashes with `MissingGreenlet`.
    # Confirmed the hard way: this is the fallback path, the one thing that must never break.
    try:
        return await generate_program_ai(db, injuries=injuries, **deterministic_kwargs)
    except Exception:
        logger.warning("AI program generation failed, falling back to the deterministic generator", exc_info=True)
        await db.rollback()  # discard any partial writes from the failed AI attempt before retrying
        deterministic_kwargs["user"] = await db.get(User, user_id)  # awaited refetch, not a bare attribute access
        return await plan_generator.generate_program(db, **deterministic_kwargs)
