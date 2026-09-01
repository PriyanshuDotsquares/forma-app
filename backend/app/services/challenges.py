import uuid
from datetime import datetime, timedelta, timezone

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.challenge import Challenge, UserChallenge
from app.models.user import User
from app.models.workout import WorkoutSession, WorkoutSet
from app.services.achievements import compute_streak_days


def _period_bounds(period: str, now: datetime | None = None) -> tuple[datetime, datetime]:
    now = now or datetime.now(timezone.utc)
    if period == "weekly":
        start = (now - timedelta(days=now.weekday())).replace(hour=0, minute=0, second=0, microsecond=0)
        return start, start + timedelta(days=7)
    if period == "monthly":
        start = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
        next_month = (start.replace(day=28) + timedelta(days=4)).replace(day=1)
        return start, next_month
    # "ongoing" — no window; streak-type challenges use this and ignore the bounds.
    return datetime.min.replace(tzinfo=timezone.utc), datetime.max.replace(tzinfo=timezone.utc)


async def _compute_progress(db: AsyncSession, user_id: uuid.UUID, metric: str, start: datetime, end: datetime) -> float:
    if metric == "volume_kg":
        volume = await db.scalar(
            select(func.coalesce(func.sum(WorkoutSet.actual_weight_kg * WorkoutSet.actual_reps), 0))
            .select_from(WorkoutSet)
            .join(WorkoutSession, WorkoutSet.session_id == WorkoutSession.id)
            .where(WorkoutSession.user_id == user_id, WorkoutSession.started_at >= start, WorkoutSession.started_at < end)
        )
        return float(volume or 0)
    if metric == "session_count":
        count = await db.scalar(
            select(func.count())
            .select_from(WorkoutSession)
            .where(WorkoutSession.user_id == user_id, WorkoutSession.started_at >= start, WorkoutSession.started_at < end)
        )
        return float(count or 0)
    if metric == "streak_days":
        # Inherently "current," not windowed — reuse the achievements definition
        # so the number shown here always agrees with the Profile tab's streak.
        return float(await compute_streak_days(db, user_id))
    return 0.0


async def _refresh(db: AsyncSession, entry: UserChallenge, challenge: Challenge) -> UserChallenge:
    start, end = _period_bounds(challenge.period)
    entry.progress_value = await _compute_progress(db, entry.user_id, challenge.metric, start, end)
    if entry.completed_at is None and entry.progress_value >= challenge.target_value:
        entry.completed_at = datetime.now(timezone.utc)
    return entry


async def list_for_user(db: AsyncSession, user: User) -> list[tuple[Challenge, UserChallenge | None]]:
    challenges = list((await db.scalars(select(Challenge).where(Challenge.is_active == True))).all())  # noqa: E712
    entries = {
        e.challenge_id: e
        for e in await db.scalars(select(UserChallenge).where(UserChallenge.user_id == user.id))
    }
    results: list[tuple[Challenge, UserChallenge | None]] = []
    dirty = False
    for challenge in challenges:
        entry = entries.get(challenge.id)
        if entry is not None:
            await _refresh(db, entry, challenge)
            dirty = True
        results.append((challenge, entry))
    if dirty:
        await db.commit()
    return results


async def join(db: AsyncSession, user: User, challenge: Challenge) -> UserChallenge:
    existing = await db.scalar(
        select(UserChallenge).where(UserChallenge.user_id == user.id, UserChallenge.challenge_id == challenge.id)
    )
    if existing is not None:
        await _refresh(db, existing, challenge)
        await db.commit()
        return existing

    start, _ = _period_bounds(challenge.period)
    entry = UserChallenge(user_id=user.id, challenge_id=challenge.id, period_start=start, progress_value=0)
    db.add(entry)
    await db.flush()
    await _refresh(db, entry, challenge)
    await db.commit()
    await db.refresh(entry)
    return entry


async def leave(db: AsyncSession, user: User, challenge: Challenge) -> None:
    existing = await db.scalar(
        select(UserChallenge).where(UserChallenge.user_id == user.id, UserChallenge.challenge_id == challenge.id)
    )
    if existing is not None:
        await db.delete(existing)
        await db.commit()


def _display_name(user: User) -> str:
    if user.full_name and user.full_name.strip():
        return user.full_name
    return user.email.split("@")[0]


async def leaderboard(db: AsyncSession, challenge: Challenge, requesting_user_id: uuid.UUID) -> list[dict]:
    entries = list(await db.scalars(select(UserChallenge).where(UserChallenge.challenge_id == challenge.id)))
    for entry in entries:
        await _refresh(db, entry, challenge)
    await db.commit()

    users_by_id = {
        u.id: u
        for u in await db.scalars(select(User).where(User.id.in_([e.user_id for e in entries])))
    } if entries else {}

    ranked = sorted(entries, key=lambda e: e.progress_value, reverse=True)
    return [
        {
            "rank": i + 1,
            "display_name": _display_name(users_by_id[e.user_id]) if e.user_id in users_by_id else "Anonymous",
            "progress_value": e.progress_value,
            "is_me": e.user_id == requesting_user_id,
        }
        for i, e in enumerate(ranked)
    ]
