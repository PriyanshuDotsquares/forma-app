import uuid

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.record import PersonalRecord
from app.models.workout import WorkoutSet


def estimate_1rm_kg(weight_kg: float, reps: int) -> float:
    """Epley formula — the industry-standard estimate, and the one implied
    by the design's "Est 1RM" readouts."""

    if reps <= 1:
        return weight_kg
    return round(weight_kg * (1 + reps / 30), 1)


async def maybe_record_pr(
    db: AsyncSession,
    *,
    user_id: uuid.UUID,
    exercise_id: uuid.UUID,
    workout_set: WorkoutSet,
) -> bool:
    """Compares a just-logged set's estimated 1RM against the user's best for
    that exercise; writes a new PersonalRecord and flags the set if it wins."""

    if workout_set.actual_weight_kg is None or not workout_set.actual_reps:
        return False

    est_1rm = estimate_1rm_kg(workout_set.actual_weight_kg, workout_set.actual_reps)

    best = await db.scalar(
        select(PersonalRecord)
        .where(PersonalRecord.user_id == user_id, PersonalRecord.exercise_id == exercise_id)
        .order_by(PersonalRecord.est_1rm_kg.desc())
        .limit(1)
    )
    if best is not None and best.est_1rm_kg >= est_1rm:
        return False

    db.add(
        PersonalRecord(
            user_id=user_id,
            exercise_id=exercise_id,
            weight_kg=workout_set.actual_weight_kg,
            reps=workout_set.actual_reps,
            est_1rm_kg=est_1rm,
            workout_set_id=workout_set.id,
        )
    )
    workout_set.is_pr = True
    return True
