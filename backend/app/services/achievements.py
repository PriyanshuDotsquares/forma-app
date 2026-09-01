import uuid
from collections import Counter
from datetime import datetime, timedelta, timezone

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.achievement import Achievement, UserAchievement
from app.models.record import PersonalRecord
from app.models.user import User
from app.models.workout import WorkoutSession, WorkoutSet


async def compute_streak_days(db: AsyncSession, user_id: uuid.UUID) -> int:
    session_dates = await db.scalars(
        select(func.date(WorkoutSession.started_at)).where(WorkoutSession.user_id == user_id).distinct()
    )
    dates = sorted({d for d in session_dates}, reverse=True)
    if not dates:
        return 0

    today = datetime.now(timezone.utc).date()
    if dates[0] not in (today, today - timedelta(days=1)):
        return 0

    streak = 1
    for i in range(1, len(dates)):
        if (dates[i - 1] - dates[i]) == timedelta(days=1):
            streak += 1
        else:
            break
    return streak


async def _compute_stats(db: AsyncSession, user_id: uuid.UUID) -> dict[str, float]:
    session_count = await db.scalar(select(func.count()).select_from(WorkoutSession).where(WorkoutSession.user_id == user_id)) or 0

    volume_kg = (
        await db.scalar(
            select(func.coalesce(func.sum(WorkoutSet.actual_weight_kg * WorkoutSet.actual_reps), 0))
            .select_from(WorkoutSet)
            .join(WorkoutSession, WorkoutSet.session_id == WorkoutSession.id)
            .where(WorkoutSession.user_id == user_id)
        )
        or 0
    )

    pr_count = await db.scalar(select(func.count()).select_from(PersonalRecord).where(PersonalRecord.user_id == user_id)) or 0

    high_form_sets = (
        await db.scalar(
            select(func.count())
            .select_from(WorkoutSet)
            .join(WorkoutSession, WorkoutSet.session_id == WorkoutSession.id)
            .where(WorkoutSession.user_id == user_id, WorkoutSet.form_score >= 85)
        )
        or 0
    )

    streak_days = await compute_streak_days(db, user_id)

    session_starts = list(
        await db.scalars(select(WorkoutSession.started_at).where(WorkoutSession.user_id == user_id))
    )
    sessions_in_best_week = 0
    early_sessions = 0
    if session_starts:
        week_counts = Counter(started.isocalendar()[:2] for started in session_starts)
        sessions_in_best_week = max(week_counts.values())
        early_sessions = sum(1 for started in session_starts if started.hour < 7)

    best_pr = await db.scalar(
        select(func.max(PersonalRecord.est_1rm_kg)).where(PersonalRecord.user_id == user_id)
    )
    max_est_1rm_kg = float(best_pr or 0)

    user = await db.get(User, user_id)
    max_bodyweight_ratio = max_est_1rm_kg / user.weight_kg if user and user.weight_kg else 0.0

    return {
        "session_count": float(session_count),
        "volume_kg_total": float(volume_kg),
        "pr_count": float(pr_count),
        "high_form_sets": float(high_form_sets),
        "streak_days": float(streak_days),
        "sessions_in_best_week": float(sessions_in_best_week),
        "early_sessions": float(early_sessions),
        "max_est_1rm_kg": max_est_1rm_kg,
        "max_bodyweight_ratio": max_bodyweight_ratio,
    }


async def evaluate_achievements(db: AsyncSession, user_id: uuid.UUID) -> list[UserAchievement]:
    """Recomputes progress against every achievement definition and upserts
    the user's progress rows. Called after a workout session is finished."""

    stats = await _compute_stats(db, user_id)

    definitions = list((await db.scalars(select(Achievement))).all())
    existing = {
        ua.achievement_id: ua
        for ua in (await db.scalars(select(UserAchievement).where(UserAchievement.user_id == user_id))).all()
    }

    touched: list[UserAchievement] = []
    now = datetime.now(timezone.utc)
    for achievement in definitions:
        criteria_type = achievement.criteria.get("type")
        target = float(achievement.criteria.get("target", 1))
        progress = stats.get(criteria_type, 0.0)

        row = existing.get(achievement.id)
        if row is None:
            row = UserAchievement(user_id=user_id, achievement_id=achievement.id, progress_value=0, target_value=target)
            db.add(row)

        row.target_value = target
        row.progress_value = min(progress, target)
        if row.unlocked_at is None and progress >= target:
            row.unlocked_at = now
        touched.append(row)

    await db.commit()
    return touched
