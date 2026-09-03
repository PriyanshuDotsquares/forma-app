"""Generates new exercises/achievements/challenges via the Groq API and
adds them to the database — additively, never overwriting or deleting
existing rows. The original curated content in `seed_data.py` was already
baked into the initial Alembic migrations and is live in every deployed
database; this script doesn't touch it, it only inserts new rows alongside
it (skipping anything whose natural key — `slug` for exercises, `key` for
achievements/challenges — already exists).

Run manually:

    python -m app.db.ai_seed [--exercises N] [--achievements N] [--challenges N]

Requires `GROQ_API_KEY` (see `.env.example`). Deliberately NOT wired into
Alembic migrations or app startup: a migration is supposed to be a
deterministic, offline-replayable step — a live network call to an LLM
inside `upgrade()` would make `alembic upgrade head` non-reproducible
(different environments could get different generated content) and would
make every fresh `alembic upgrade head` (a new dev machine, CI, disaster
recovery) fail or hang if the API key is missing or the API is briefly
down. Same reasoning against app-startup seeding — it would add a paid
external dependency to every boot. This is an explicit, opt-in step.

Uses Groq's OpenAI-compatible `response_format: {"type": "json_schema", ...,
"strict": True}` structured-output mode, only supported by a handful of
Groq-hosted models (GPT-OSS 20B/120B, Qwen3(.6/.8) 27B as of writing) — see
`MODEL` below. `strict_schema()` post-processes Pydantic's JSON Schema
output because strict mode requires every property to be listed in
`required` and every object to set `additionalProperties: false`, which
Pydantic doesn't do by default for fields that have a Python-side default.
"""

import argparse
import asyncio
import json
from typing import Any, Literal

from groq import AsyncGroq
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.db.seed_data import ACHIEVEMENTS, CHALLENGES, EXERCISES
from app.db.session import async_session_factory
from app.models.achievement import Achievement
from app.models.challenge import Challenge
from app.models.exercise import Exercise

MODEL = "openai/gpt-oss-120b"

# --- Schemas -------------------------------------------------------------
# Every enum below mirrors a vocabulary another part of the app reads by
# exact string match, not just "plausible" strength-training terms.
# Generating outside these sets wouldn't error — it would just make the
# row functionally inert. Two examples: `app.services.plan_generator.
# select_exercises_for_day` filters `tag in exercise.primary_muscles`
# against exactly PrimaryMuscle's ten values, so an exercise tagged outside
# that set can never be selected into a generated program; and
# `app.services.achievements.evaluate_achievements` looks up
# `stats.get(criteria_type, 0.0)`, so an achievement whose `criteria.type`
# isn't one of CriteriaType's values is permanently stuck at 0 progress —
# it can never unlock.

PrimaryMuscle = Literal[
    "chest", "back", "quads", "hamstrings", "shoulders", "core", "biceps", "triceps", "glutes", "calves"
]
SecondaryMuscle = Literal[
    "chest",
    "back",
    "quads",
    "hamstrings",
    "shoulders",
    "core",
    "biceps",
    "triceps",
    "glutes",
    "calves",
    "forearms",
    "front_delts",
    "lats",
]
Equipment = Literal["barbell", "dumbbell", "cable", "machine", "kettlebell", "bodyweight"]
Difficulty = Literal["beginner", "intermediate", "advanced"]
CameraView = Literal["side", "front"]


class MistakeGen(BaseModel):
    title: str
    why: str
    fix: str


class ExerciseGen(BaseModel):
    slug: str = Field(description="lowercase-hyphenated unique id, e.g. 'barbell-bench-press'")
    name: str
    primary_muscles: list[PrimaryMuscle] = Field(min_length=1, max_length=3)
    secondary_muscles: list[SecondaryMuscle] = Field(default_factory=list, max_length=4)
    equipment: list[Equipment] = Field(min_length=1, max_length=2)
    difficulty: Difficulty
    execution_steps: list[str] = Field(min_length=2, max_length=6)
    pro_cues: list[str] = Field(default_factory=list, max_length=4)
    mistakes: list[MistakeGen] = Field(default_factory=list, max_length=4)
    supports_camera: bool
    camera_view: CameraView | None = None


class ExerciseBatch(BaseModel):
    exercises: list[ExerciseGen]


AchievementCategory = Literal["consistency", "strength", "volume", "secret"]
CriteriaType = Literal[
    "session_count",
    "volume_kg_total",
    "pr_count",
    "high_form_sets",
    "streak_days",
    "sessions_in_best_week",
    "early_sessions",
    "max_est_1rm_kg",
    "max_bodyweight_ratio",
]


class AchievementCriteriaGen(BaseModel):
    type: CriteriaType
    target: float


class AchievementGen(BaseModel):
    key: str = Field(description="lowercase_snake_case unique id")
    category: AchievementCategory
    title: str
    description: str
    icon: str = Field(description="a Material Icons name, e.g. 'emoji_events'")
    criteria: AchievementCriteriaGen
    is_secret: bool = False


class AchievementBatch(BaseModel):
    achievements: list[AchievementGen]


ChallengeMetric = Literal["volume_kg", "session_count", "streak_days"]
ChallengePeriod = Literal["weekly", "monthly", "ongoing"]


class ChallengeGen(BaseModel):
    key: str = Field(description="lowercase_snake_case unique id")
    title: str
    description: str
    metric: ChallengeMetric
    period: ChallengePeriod
    target_value: float
    icon: str = Field(description="a Material Icons name, e.g. 'flag'")
    is_group: bool = True


class ChallengeBatch(BaseModel):
    challenges: list[ChallengeGen]


def strict_schema(model: type[BaseModel]) -> dict[str, Any]:
    """Pydantic's `model_json_schema()` only marks a field `required` when
    it has no Python-side default — Groq's strict mode requires *every*
    property to be listed in `required` (a nullable/optional field is
    expressed by its type accepting `null`, not by omitting it from
    `required`) and every object to set `additionalProperties: false`.
    Walks the schema (including `$defs`, array `items`, and `anyOf`/
    `allOf`/`oneOf` branches) and forces both, recursively.
    """
    schema = model.model_json_schema()

    def _tighten(node: Any) -> None:
        if not isinstance(node, dict):
            return
        if node.get("type") == "object" and "properties" in node:
            node["required"] = list(node["properties"].keys())
            node["additionalProperties"] = False
        for key in ("properties", "$defs"):
            for v in node.get(key, {}).values():
                _tighten(v)
        if isinstance(node.get("items"), dict):
            _tighten(node["items"])
        for key in ("anyOf", "allOf", "oneOf"):
            for v in node.get(key, []):
                _tighten(v)

    _tighten(schema)
    return schema


# --- Prompts ---------------------------------------------------------------

_EXERCISE_PROMPT = """Generate {count} new strength-training exercises for FORMA, a strength-coaching app, as a JSON object matching the schema.

Rules:
- Every exercise must be real, safe, and commonly performed in a gym or at home.
- `primary_muscles` and `secondary_muscles` MUST use only the exact tag values the schema's enum allows — this is the app's fixed muscle-tag vocabulary, matched literally elsewhere in the codebase. Do not invent new muscle names.
- `equipment` MUST use only the schema's enum values — this is the app's fixed equipment vocabulary.
- `execution_steps` are short imperative instructions, in performance order.
- `pro_cues` are short, punchy coaching cues.
- Each entry in `mistakes` has a `title` (short, e.g. "Elbows flared"), `why` (one sentence on the consequence), and `fix` (one short imperative sentence).
- `supports_camera` is true only for exercises where a side-view or front-view camera could meaningfully track joint angles for rep counting (mainly free-weight compound lifts); set `camera_view` accordingly, or null when `supports_camera` is false.
- Do NOT reuse any of these slugs, which already exist: {existing_keys}
- Cover a good spread across muscle groups and equipment types — don't cluster on one muscle or one equipment type.

Match this tone and level of detail (from the app's own existing exercises) exactly:
{examples}
"""

_ACHIEVEMENT_PROMPT = """Generate {count} new achievement definitions for FORMA, a strength-coaching app, as a JSON object matching the schema.

Rules:
- `criteria.type` MUST be one of the schema's enum values — these are the ONLY stats the app actually computes per user. An achievement using any other criteria type can never unlock (it would be permanently stuck at 0 progress). Do not invent new criteria types.
- `criteria.target` must be a realistic, meaningfully-different threshold from existing achievements of the same `criteria.type` (see the existing list below) — add new tiers (e.g. a bigger streak, a bigger PR count) rather than duplicating an existing target.
- `category` should be "consistency" for session_count/streak_days/sessions_in_best_week/early_sessions achievements, "strength" for pr_count/high_form_sets/max_est_1rm_kg/max_bodyweight_ratio, "volume" for volume_kg_total, or "secret" (pair with `is_secret: true`) for a surprise one.
- `title` is short (2-3 words). `description` is one plain sentence stating exactly what to do to unlock it.
- `icon` is a Material Icons name (snake_case), thematically fitting.
- Do NOT reuse any of these keys, which already exist: {existing_keys}

Match this tone (from the app's own existing achievements):
{examples}
"""

_CHALLENGE_PROMPT = """Generate {count} new time-boxed challenges for FORMA, a strength-coaching app, as a JSON object matching the schema.

Rules:
- `metric` MUST be one of the schema's enum values (volume_kg, session_count, streak_days) — the ONLY metrics the app actually computes. Do not invent new metrics.
- `period` MUST be "weekly", "monthly", or "ongoing" — "ongoing" is for streak-type challenges only (no time window); pair it with `metric: streak_days` and `is_group: false`.
- `target_value` should be a realistic, meaningfully-different threshold from existing challenges of the same metric+period (see below).
- `title` is short and punchy. `description` is one plain sentence.
- `icon` is a Material Icons name (snake_case).
- Do NOT reuse any of these keys, which already exist: {existing_keys}

Match this tone (from the app's own existing challenges):
{examples}
"""


def _examples_json(items: list[dict[str, Any]], n: int, keys: list[str]) -> str:
    sample = [{k: item[k] for k in keys if k in item} for item in items[:n]]
    return json.dumps(sample, indent=2, default=str)


async def _generate_batch(client: AsyncGroq, batch_model: type[BaseModel], schema_name: str, prompt: str) -> BaseModel:
    response = await client.chat.completions.create(
        model=MODEL,
        messages=[{"role": "user", "content": prompt}],
        response_format={"type": "json_schema", "json_schema": {"name": schema_name, "strict": True, "schema": strict_schema(batch_model)}},
    )
    content = response.choices[0].message.content
    return batch_model.model_validate_json(content)


# --- Generation --------------------------------------------------------------


async def _generate_exercises(client: AsyncGroq, count: int, existing_slugs: set[str]) -> list[ExerciseGen]:
    examples = _examples_json(
        EXERCISES,
        3,
        [
            "slug",
            "name",
            "primary_muscles",
            "secondary_muscles",
            "equipment",
            "difficulty",
            "execution_steps",
            "pro_cues",
            "mistakes",
            "supports_camera",
            "camera_view",
        ],
    )
    prompt = _EXERCISE_PROMPT.format(count=count, existing_keys=sorted(existing_slugs), examples=examples)
    batch = await _generate_batch(client, ExerciseBatch, "exercise_batch", prompt)
    assert isinstance(batch, ExerciseBatch)
    return batch.exercises


async def _generate_achievements(client: AsyncGroq, count: int, existing_keys: set[str]) -> list[AchievementGen]:
    examples = _examples_json(ACHIEVEMENTS, 6, ["key", "category", "title", "description", "icon", "criteria", "is_secret"])
    prompt = _ACHIEVEMENT_PROMPT.format(count=count, existing_keys=sorted(existing_keys), examples=examples)
    batch = await _generate_batch(client, AchievementBatch, "achievement_batch", prompt)
    assert isinstance(batch, AchievementBatch)
    return batch.achievements


async def _generate_challenges(client: AsyncGroq, count: int, existing_keys: set[str]) -> list[ChallengeGen]:
    examples = _examples_json(CHALLENGES, 6, ["key", "title", "description", "metric", "period", "target_value", "icon", "is_group"])
    prompt = _CHALLENGE_PROMPT.format(count=count, existing_keys=sorted(existing_keys), examples=examples)
    batch = await _generate_batch(client, ChallengeBatch, "challenge_batch", prompt)
    assert isinstance(batch, ChallengeBatch)
    return batch.challenges


# --- Seeding (additive upsert-by-natural-key) -------------------------------


async def seed_exercises(session: AsyncSession, client: AsyncGroq, count: int) -> int:
    existing = set((await session.scalars(select(Exercise.slug))).all())
    generated = await _generate_exercises(client, count, existing)
    seen = set(existing)
    added = 0
    for item in generated:
        if item.slug in seen:
            continue
        seen.add(item.slug)
        session.add(
            Exercise(
                slug=item.slug,
                name=item.name,
                primary_muscles=list(item.primary_muscles),
                secondary_muscles=list(item.secondary_muscles),
                equipment=list(item.equipment),
                difficulty=item.difficulty,
                execution_steps=list(item.execution_steps),
                pro_cues=list(item.pro_cues),
                mistakes=[m.model_dump() for m in item.mistakes],
                supports_camera=item.supports_camera,
                camera_view=item.camera_view,
            )
        )
        added += 1
    await session.commit()
    return added


async def seed_achievements(session: AsyncSession, client: AsyncGroq, count: int) -> int:
    existing = set((await session.scalars(select(Achievement.key))).all())
    generated = await _generate_achievements(client, count, existing)
    seen = set(existing)
    added = 0
    for item in generated:
        if item.key in seen:
            continue
        seen.add(item.key)
        session.add(
            Achievement(
                key=item.key,
                category=item.category,
                title=item.title,
                description=item.description,
                icon=item.icon,
                criteria=item.criteria.model_dump(),
                is_secret=item.is_secret,
            )
        )
        added += 1
    await session.commit()
    return added


async def seed_challenges(session: AsyncSession, client: AsyncGroq, count: int) -> int:
    existing = set((await session.scalars(select(Challenge.key))).all())
    generated = await _generate_challenges(client, count, existing)
    seen = set(existing)
    added = 0
    for item in generated:
        if item.key in seen:
            continue
        seen.add(item.key)
        session.add(
            Challenge(
                key=item.key,
                title=item.title,
                description=item.description,
                metric=item.metric,
                period=item.period,
                target_value=item.target_value,
                icon=item.icon,
                is_group=item.is_group,
                is_active=True,
            )
        )
        added += 1
    await session.commit()
    return added


async def main() -> None:
    parser = argparse.ArgumentParser(description="Generate and add AI-created exercises/achievements/challenges via the Groq API.")
    parser.add_argument("--exercises", type=int, default=40, help="How many new exercises to generate (default 40, 0 to skip).")
    parser.add_argument("--achievements", type=int, default=20, help="How many new achievements to generate (default 20, 0 to skip).")
    parser.add_argument("--challenges", type=int, default=6, help="How many new challenges to generate (default 6, 0 to skip).")
    args = parser.parse_args()

    settings = get_settings()
    if not settings.groq_api_key:
        raise SystemExit("GROQ_API_KEY is not set — add it to backend/.env before running this script.")

    client = AsyncGroq(api_key=settings.groq_api_key)

    async with async_session_factory() as session:
        added_exercises = await seed_exercises(session, client, args.exercises) if args.exercises > 0 else 0
        added_achievements = await seed_achievements(session, client, args.achievements) if args.achievements > 0 else 0
        added_challenges = await seed_challenges(session, client, args.challenges) if args.challenges > 0 else 0

    print(f"Added {added_exercises} exercises, {added_achievements} achievements, {added_challenges} challenges.")


if __name__ == "__main__":
    asyncio.run(main())
