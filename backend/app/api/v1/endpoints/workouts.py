import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.api.deps import get_current_user
from app.db.session import get_db
from app.models.exercise import Exercise
from app.models.user import User
from app.models.workout import WorkoutSession, WorkoutSet
from app.schemas.workout import (
    WorkoutSessionCreate,
    WorkoutSessionFinish,
    WorkoutSessionRead,
    WorkoutSetCreate,
    WorkoutSetRead,
)
from app.services.achievements import evaluate_achievements
from app.services.records import maybe_record_pr

router = APIRouter(prefix="/workouts", tags=["workouts"])

_SESSION_LOAD_OPTIONS = (selectinload(WorkoutSession.sets).selectinload(WorkoutSet.exercise),)


async def _get_owned_session(db: AsyncSession, session_id: uuid.UUID, user: User) -> WorkoutSession:
    session = await db.scalar(
        select(WorkoutSession).where(WorkoutSession.id == session_id).options(*_SESSION_LOAD_OPTIONS)
    )
    if session is None or session.user_id != user.id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Workout session not found")
    return session


@router.post("/sessions", response_model=WorkoutSessionRead, status_code=status.HTTP_201_CREATED)
async def start_session(
    payload: WorkoutSessionCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> WorkoutSession:
    session = WorkoutSession(user_id=current_user.id, program_day_id=payload.program_day_id, label=payload.label)
    db.add(session)
    await db.commit()
    await db.refresh(session, attribute_names=["sets"])
    return session


@router.get("/sessions", response_model=list[WorkoutSessionRead])
async def list_sessions(
    skip: int = 0,
    limit: int = 20,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> list[WorkoutSession]:
    limit = min(limit, 100)
    stmt = (
        select(WorkoutSession)
        .where(WorkoutSession.user_id == current_user.id)
        .options(*_SESSION_LOAD_OPTIONS)
        .order_by(WorkoutSession.started_at.desc())
        .offset(skip)
        .limit(limit)
    )
    return list(await db.scalars(stmt))


@router.get("/sessions/{session_id}", response_model=WorkoutSessionRead)
async def get_session(
    session_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> WorkoutSession:
    return await _get_owned_session(db, session_id, current_user)


@router.delete("/sessions/{session_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_session(
    session_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> None:
    session = await _get_owned_session(db, session_id, current_user)
    await db.delete(session)
    await db.commit()


@router.post("/sessions/{session_id}/sets", response_model=WorkoutSetRead, status_code=status.HTTP_201_CREATED)
async def log_set(
    session_id: uuid.UUID,
    payload: WorkoutSetCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> WorkoutSet:
    session = await _get_owned_session(db, session_id, current_user)
    exercise = await db.get(Exercise, payload.exercise_id)
    if exercise is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Exercise not found")

    workout_set = WorkoutSet(session_id=session.id, **payload.model_dump())
    db.add(workout_set)
    await db.flush()  # assigns workout_set.id before PR comparison

    await maybe_record_pr(db, user_id=current_user.id, exercise_id=payload.exercise_id, workout_set=workout_set)

    await db.commit()
    await db.refresh(workout_set, attribute_names=["exercise"])
    return workout_set


@router.delete("/sets/{set_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_set(
    set_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> None:
    workout_set = await db.scalar(
        select(WorkoutSet).where(WorkoutSet.id == set_id).options(selectinload(WorkoutSet.session))
    )
    if workout_set is None or workout_set.session.user_id != current_user.id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Set not found")
    await db.delete(workout_set)
    await db.commit()


@router.post("/sessions/{session_id}/finish", response_model=WorkoutSessionRead)
async def finish_session(
    session_id: uuid.UUID,
    payload: WorkoutSessionFinish,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> WorkoutSession:
    session = await _get_owned_session(db, session_id, current_user)

    now = datetime.now(timezone.utc)
    session.ended_at = now
    session.duration_s = payload.duration_s or int((now - session.started_at).total_seconds())
    session.calories = payload.calories
    session.rpe = payload.rpe
    session.mood = payload.mood
    session.notes = payload.notes

    form_scores = [s.form_score for s in session.sets if s.form_score is not None]
    session.avg_form_score = round(sum(form_scores) / len(form_scores), 1) if form_scores else None

    pr_count = sum(1 for s in session.sets if s.is_pr)
    current_user.xp += 50 + 5 * len(session.sets) + 20 * pr_count

    await db.commit()
    await evaluate_achievements(db, current_user.id)
    await db.refresh(session, attribute_names=["sets"])
    return session
