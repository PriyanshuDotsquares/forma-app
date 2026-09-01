"""Deterministic, rule-based program builder.

This is NOT a call to a language model — it's a heuristic that picks a
weekly split, distributes it across the week, and fills each day from the
seeded exercise library based on the trainee's goal/equipment/experience.
Described here explicitly so nobody mistakes it for a trained fitness AI.
"""

import uuid
from dataclasses import dataclass

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.exercise import Exercise
from app.models.program import Program, ProgramDay, ProgramExercise
from app.models.user import User

# Weekday distribution for a given days/week — mirrors the "U L _ U L _ _"
# pattern shown in the design for a 4-day split.
_WEEKDAY_DISTRIBUTION: dict[int, list[int]] = {
    1: [0],
    2: [0, 3],
    3: [0, 2, 4],
    4: [0, 1, 3, 4],
    5: [0, 1, 2, 3, 4],
    6: [0, 1, 2, 3, 4, 5],
    7: [0, 1, 2, 3, 4, 5, 6],
}

_FULL_BODY_TAGS = ["chest", "back", "quads", "hamstrings", "shoulders", "core"]
_UPPER_TAGS = ["chest", "back", "shoulders", "biceps", "triceps"]
_LOWER_TAGS = ["quads", "hamstrings", "glutes", "calves"]
_PUSH_TAGS = ["chest", "shoulders", "triceps"]
_PULL_TAGS = ["back", "biceps"]
_LEGS_TAGS = ["quads", "hamstrings", "glutes", "calves"]
_BODY_PART_ROTATION = [
    ("Chest", ["chest"]),
    ("Back", ["back"]),
    ("Shoulders", ["shoulders"]),
    ("Legs", _LEGS_TAGS),
    ("Arms", ["biceps", "triceps"]),
]

_VALID_SPLITS_FOR_DAYS: dict[str, set[int]] = {
    "push_pull_legs": {3, 6},
    "body_part": {5, 6, 7},
}


@dataclass
class _DayPlan:
    label: str
    muscle_tags: list[str]
    weekday: int


def _resolve_split(split_preference: str | None, days_per_week: int) -> str:
    if split_preference and split_preference != "auto":
        allowed = _VALID_SPLITS_FOR_DAYS.get(split_preference)
        if allowed is None or days_per_week in allowed:
            return split_preference
    # auto-pick based on days/week, same logic the "FORMA decides" option uses
    if days_per_week <= 3:
        return "full_body"
    if days_per_week == 4:
        return "upper_lower"
    if days_per_week in (5,):
        return "body_part"
    return "push_pull_legs"


def _build_day_plans(split_type: str, days_per_week: int) -> list[_DayPlan]:
    weekdays = _WEEKDAY_DISTRIBUTION[days_per_week]
    plans: list[_DayPlan] = []

    if split_type == "full_body":
        for i, wd in enumerate(weekdays):
            plans.append(_DayPlan(f"Full Body {chr(65 + i)}", _FULL_BODY_TAGS, wd))
    elif split_type == "upper_lower":
        cycle = [("Upper", _UPPER_TAGS), ("Lower", _LOWER_TAGS)]
        letter_counts: dict[str, int] = {}
        for i, wd in enumerate(weekdays):
            base_label, tags = cycle[i % 2]
            letter_counts[base_label] = letter_counts.get(base_label, 0) + 1
            letter = chr(64 + letter_counts[base_label])  # A, B, C...
            plans.append(_DayPlan(f"{base_label} {letter}", tags, wd))
    elif split_type == "push_pull_legs":
        cycle = [("Push", _PUSH_TAGS), ("Pull", _PULL_TAGS), ("Legs", _LEGS_TAGS)]
        for i, wd in enumerate(weekdays):
            plans.append(_DayPlan(cycle[i % 3][0], cycle[i % 3][1], wd))
    else:  # body_part
        for i, wd in enumerate(weekdays):
            label, tags = _BODY_PART_ROTATION[i % len(_BODY_PART_ROTATION)]
            plans.append(_DayPlan(label, tags, wd))

    return plans


def _reps_scheme(goal: str | None) -> tuple[int, int, int]:
    """(sets, rep_low, rep_high) by training goal."""
    return {
        "build_muscle": (4, 8, 12),
        "get_stronger": (4, 6, 8),
        "lose_fat": (3, 10, 15),
        "general_health": (3, 10, 15),
        "athletic_performance": (4, 5, 8),
        "move_better": (3, 10, 15),
    }.get(goal or "general_health", (3, 8, 12))


def _exercises_per_day(session_minutes: int | None) -> int:
    minutes = session_minutes or 60
    if minutes <= 30:
        return 4
    if minutes <= 45:
        return 5
    if minutes <= 60:
        return 6
    return 7


def select_exercises_for_day(
    all_exercises: list[Exercise],
    muscle_tags: list[str],
    available_equipment: set[str],
    per_day_count: int,
    exclude_ids: set[uuid.UUID] | None = None,
) -> list[Exercise]:
    """One exercise per muscle tag (compound-ish first), skipping anything
    in `exclude_ids`, until `per_day_count` is reached. Shared by
    `generate_program` (a fresh day) and `fill_day_exercises` (an existing
    one) so both pick exercises the same way."""
    used_ids: set[uuid.UUID] = set(exclude_ids or set())
    chosen: list[Exercise] = []
    for tag in muscle_tags:
        if len(chosen) >= per_day_count:
            break
        candidates = [
            e
            for e in all_exercises
            if e.id not in used_ids
            and tag in e.primary_muscles
            and (set(e.equipment) & available_equipment or not e.equipment)
        ]
        # Compound-ish first: prefer exercises hitting more than one primary muscle.
        candidates.sort(key=lambda e: -len(e.primary_muscles))
        if candidates:
            pick = candidates[0]
            chosen.append(pick)
            used_ids.add(pick.id)
    return chosen


async def generate_program(
    db: AsyncSession,
    *,
    user: User,
    goal: str | None,
    experience_level: str | None,
    days_per_week: int,
    session_minutes: int | None,
    split_preference: str | None,
    equipment: list[str],
) -> Program:
    split_type = _resolve_split(split_preference, days_per_week)
    day_plans = _build_day_plans(split_type, days_per_week)
    sets, rep_low, rep_high = _reps_scheme(goal)
    per_day_count = _exercises_per_day(session_minutes)
    available_equipment = set(equipment) | {"bodyweight"}

    # Deactivate any previously-active generated program so there's one
    # current plan at a time (mirrors the design's single "Your plan" view).
    existing_active = await db.scalars(
        select(Program).where(Program.owner_id == user.id, Program.is_active == True)  # noqa: E712
    )
    for p in existing_active:
        p.is_active = False

    program = Program(
        owner_id=user.id,
        name="Built for Strength" if (goal or "") == "get_stronger" else "Your Program",
        split_type=split_type,
        days_per_week=days_per_week,
        duration_weeks=8,
        source="generated",
        is_active=True,
    )
    db.add(program)
    await db.flush()  # assigns program.id; avoids lazy-loading program.days under asyncio

    all_exercises = list((await db.scalars(select(Exercise))).all())

    for order_index, plan in enumerate(day_plans):
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

        chosen = select_exercises_for_day(all_exercises, plan.muscle_tags, available_equipment, per_day_count)

        for i, exercise in enumerate(chosen):
            db.add(
                ProgramExercise(
                    program_day_id=day.id,
                    exercise_id=exercise.id,
                    order_index=i,
                    sets=sets,
                    rep_range_low=rep_low,
                    rep_range_high=rep_high,
                    load_type="weight",
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


async def fill_day_exercises(db: AsyncSession, day: ProgramDay, user: User) -> ProgramDay:
    """"Let AI fill this day" — appends exercises picked by the same
    heuristic `generate_program` uses, on top of whatever's already on the
    day (never replaces existing exercises). A no-op if the day is already
    at the target exercise count for the user's session length."""
    # Captured before any commit/expire below — `day` (loaded by the caller
    # earlier in this session) gets expired once we commit, and touching an
    # expired ORM attribute triggers an implicit lazy-load that crashes
    # outside the driver's async/greenlet context. Plain local variables
    # sidestep that entirely.
    day_id = day.id
    sets, rep_low, rep_high = _reps_scheme(user.goal)
    per_day_count = _exercises_per_day(user.session_minutes or day.estimated_minutes)
    available_equipment = set(user.equipment) | {"bodyweight"}
    muscle_tags = day.muscle_tags or _FULL_BODY_TAGS

    remaining_slots = per_day_count - len(day.exercises)
    if remaining_slots > 0:
        all_exercises = list((await db.scalars(select(Exercise))).all())
        existing_ids = {pe.exercise_id for pe in day.exercises}
        chosen = select_exercises_for_day(all_exercises, muscle_tags, available_equipment, remaining_slots, exclude_ids=existing_ids)

        next_index = len(day.exercises)
        for i, exercise in enumerate(chosen):
            db.add(
                ProgramExercise(
                    program_day_id=day_id,
                    exercise_id=exercise.id,
                    order_index=next_index + i,
                    sets=sets,
                    rep_range_low=rep_low,
                    rep_range_high=rep_high,
                    load_type="weight",
                    coach_with_camera=exercise.supports_camera and next_index == 0 and i == 0,
                )
            )
        await db.commit()
        # The pre-fetched `day`'s `exercises` collection won't reflect the
        # rows just inserted unless the identity map is invalidated first —
        # `generate_program`'s equivalent re-query works without this only
        # because its `Program` is freshly created in the same call, not
        # loaded earlier and reused like this one.
        db.expire_all()

    result = await db.scalars(
        select(ProgramDay)
        .where(ProgramDay.id == day_id)
        .options(selectinload(ProgramDay.exercises).selectinload(ProgramExercise.exercise))
    )
    return result.one()
