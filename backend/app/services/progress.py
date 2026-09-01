"""Aggregate read-side queries backing the Progress tab.

Datasets here are one person's training log, not big data — so aggregation
is done in Python over a bounded, period-filtered fetch rather than pushed
into complex SQL, favoring clarity/correctness over micro-optimization.
"""

import uuid
from collections import defaultdict
from datetime import date, datetime, timedelta, timezone

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.record import PersonalRecord
from app.models.workout import WorkoutSession, WorkoutSet
from app.schemas.progress import (
    ConsistencyDay,
    FormQualityPoint,
    ProgressSummary,
    RecoveryItem,
    StrengthPoint,
    VolumeByMuscle,
    VolumeTrendPoint,
)
from app.services.achievements import compute_streak_days  # reuse the same streak definition

_RECOVERY_WINDOW_HOURS = {
    "chest": 48,
    "back": 48,
    "quads": 48,
    "hamstrings": 48,
    "glutes": 48,
    "shoulders": 36,
    "calves": 36,
    "biceps": 24,
    "triceps": 24,
    "core": 24,
}


def _period_start(period: str) -> date | None:
    today = datetime.now(timezone.utc).date()
    return {
        "week": today - timedelta(days=7),
        "month": today - timedelta(days=30),
        "3month": today - timedelta(days=90),
        "year": today - timedelta(days=365),
        "all": None,
    }.get(period, today - timedelta(days=30))


async def _fetch_sessions(
    db: AsyncSession, user_id: uuid.UUID, period: str, *, only_finished: bool = True
) -> list[WorkoutSession]:
    stmt = (
        select(WorkoutSession)
        .where(WorkoutSession.user_id == user_id)
        .options(selectinload(WorkoutSession.sets).selectinload(WorkoutSet.exercise))
        .order_by(WorkoutSession.started_at.asc())
    )
    if only_finished:
        stmt = stmt.where(WorkoutSession.ended_at.is_not(None))
    start = _period_start(period)
    if start is not None:
        stmt = stmt.where(WorkoutSession.started_at >= start)
    return list((await db.scalars(stmt)).all())


def _set_volume(s: WorkoutSet) -> float:
    if s.actual_weight_kg is None or s.actual_reps is None:
        return 0.0
    return s.actual_weight_kg * s.actual_reps


async def summary(db: AsyncSession, user_id: uuid.UUID, period: str) -> ProgressSummary:
    sessions = await _fetch_sessions(db, user_id, period)
    volume = sum(_set_volume(s) for sess in sessions for s in sess.sets)
    time_s = sum(sess.duration_s or 0 for sess in sessions)
    form_scores = [sess.avg_form_score for sess in sessions if sess.avg_form_score is not None]
    avg_form = round(sum(form_scores) / len(form_scores), 1) if form_scores else None
    streak = await compute_streak_days(db, user_id)

    return ProgressSummary(
        period=period,
        workouts=len(sessions),
        volume_kg=round(volume, 1),
        time_s=time_s,
        avg_form_score=avg_form,
        streak_days=streak,
    )


async def volume_by_muscle(db: AsyncSession, user_id: uuid.UUID, period: str) -> list[VolumeByMuscle]:
    sessions = await _fetch_sessions(db, user_id, period)
    sets_by_muscle: dict[str, int] = defaultdict(int)
    volume_by_muscle_kg: dict[str, float] = defaultdict(float)

    for sess in sessions:
        for s in sess.sets:
            if not s.exercise.primary_muscles:
                continue
            muscle = s.exercise.primary_muscles[0]
            sets_by_muscle[muscle] += 1
            volume_by_muscle_kg[muscle] += _set_volume(s)

    return [
        VolumeByMuscle(muscle=muscle, sets=sets_by_muscle[muscle], volume_kg=round(volume_by_muscle_kg[muscle], 1))
        for muscle in sorted(sets_by_muscle, key=lambda m: -sets_by_muscle[m])
    ]


async def volume_trend(db: AsyncSession, user_id: uuid.UUID, period: str) -> list[VolumeTrendPoint]:
    sessions = await _fetch_sessions(db, user_id, period)
    monthly = period in ("year", "all")

    buckets: dict[str, float] = defaultdict(float)
    order: list[str] = []
    for sess in sessions:
        started = sess.started_at
        if monthly:
            label = started.strftime("%b")
        else:
            iso_year, iso_week, _ = started.isocalendar()
            label = f"W{iso_week}"
        if label not in buckets:
            order.append(label)
        buckets[label] += sum(_set_volume(s) for s in sess.sets)

    points: list[VolumeTrendPoint] = []
    prev_volume: float | None = None
    for label in order:
        vol = round(buckets[label], 1)
        is_deload = prev_volume is not None and prev_volume > 0 and vol < prev_volume * 0.5
        points.append(VolumeTrendPoint(period_label=label, volume_kg=vol, is_deload=is_deload))
        prev_volume = vol
    return points


async def recovery(db: AsyncSession, user_id: uuid.UUID) -> list[RecoveryItem]:
    sessions = await _fetch_sessions(db, user_id, "3month")
    last_trained: dict[str, datetime] = {}
    sets_last_session: dict[str, int] = defaultdict(int)

    for sess in sessions:
        for s in sess.sets:
            for muscle in s.exercise.primary_muscles:
                if muscle not in last_trained or sess.started_at > last_trained[muscle]:
                    last_trained[muscle] = sess.started_at
                    sets_last_session[muscle] = 0
                if sess.started_at == last_trained[muscle]:
                    sets_last_session[muscle] += 1

    now = datetime.now(timezone.utc)
    items: list[RecoveryItem] = []
    for muscle, window_hours in _RECOVERY_WINDOW_HOURS.items():
        trained_at = last_trained.get(muscle)
        if trained_at is None:
            items.append(RecoveryItem(muscle_group=muscle, last_trained=None, sets_last_session=0, recovered_pct=100.0, fresh_in_hours=0))
            continue
        hours_since = (now - trained_at).total_seconds() / 3600
        recovered_pct = min(100.0, round((hours_since / window_hours) * 100, 0))
        fresh_in = max(0.0, round(window_hours - hours_since, 1))
        items.append(
            RecoveryItem(
                muscle_group=muscle,
                last_trained=trained_at.date(),
                sets_last_session=sets_last_session[muscle],
                recovered_pct=recovered_pct,
                fresh_in_hours=fresh_in if fresh_in > 0 else None,
            )
        )
    return items


async def strength_trend(db: AsyncSession, user_id: uuid.UUID, exercise_id: uuid.UUID, period: str) -> list[StrengthPoint]:
    stmt = select(PersonalRecord).where(PersonalRecord.user_id == user_id, PersonalRecord.exercise_id == exercise_id)
    start = _period_start(period)
    if start is not None:
        stmt = stmt.where(PersonalRecord.achieved_at >= start)
    stmt = stmt.order_by(PersonalRecord.achieved_at.asc())
    records = list((await db.scalars(stmt)).all())
    return [StrengthPoint(date=r.achieved_at.date(), est_1rm_kg=r.est_1rm_kg) for r in records]


async def form_quality_trend(
    db: AsyncSession, user_id: uuid.UUID, period: str, exercise_id: uuid.UUID | None
) -> list[FormQualityPoint]:
    """Week-over-week average form score. Per-rep breakdowns (which rep had
    flared elbows, a box plot of depth per set) are computed client-side in
    real time during the camera session — they aren't reconstructable from
    the set-level `form_score`/`depth_pct` this backend stores."""

    sessions = await _fetch_sessions(db, user_id, period)
    buckets: dict[str, list[int]] = defaultdict(list)
    order: list[str] = []
    for sess in sessions:
        for s in sess.sets:
            if s.form_score is None:
                continue
            if exercise_id is not None and s.exercise_id != exercise_id:
                continue
            iso_year, iso_week, _ = sess.started_at.isocalendar()
            label = f"W{iso_week}"
            if label not in buckets:
                order.append(label)
            buckets[label].append(s.form_score)

    return [FormQualityPoint(week_label=label, form_score=round(sum(buckets[label]) / len(buckets[label]), 1)) for label in order]


async def consistency_calendar(db: AsyncSession, user_id: uuid.UUID, year: int, month: int) -> list[ConsistencyDay]:
    stmt = (
        select(WorkoutSession)
        .where(WorkoutSession.user_id == user_id)
        .options(selectinload(WorkoutSession.sets))
        .order_by(WorkoutSession.started_at.asc())
    )
    sessions = list((await db.scalars(stmt)).all())

    by_day: dict[date, list[WorkoutSession]] = defaultdict(list)
    for sess in sessions:
        d = sess.started_at.date()
        if d.year == year and d.month == month:
            by_day[d].append(sess)

    days: list[ConsistencyDay] = []
    for d, day_sessions in sorted(by_day.items()):
        volume = sum(_set_volume(s) for sess in day_sessions for s in sess.sets)
        has_pr = any(s.is_pr for sess in day_sessions for s in sess.sets)
        days.append(ConsistencyDay(date=d, sessions=len(day_sessions), volume_kg=round(volume, 1), has_pr=has_pr))
    return days


async def current_records(db: AsyncSession, user_id: uuid.UUID) -> list[PersonalRecord]:
    stmt = (
        select(PersonalRecord)
        .where(PersonalRecord.user_id == user_id)
        .order_by(PersonalRecord.achieved_at.asc())
    )
    records = list((await db.scalars(stmt)).all())
    latest_by_exercise: dict[uuid.UUID, PersonalRecord] = {}
    for r in records:
        latest_by_exercise[r.exercise_id] = r  # ascending order => last write is the current best
    return sorted(latest_by_exercise.values(), key=lambda r: r.achieved_at, reverse=True)
