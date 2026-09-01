import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.db.session import get_db
from app.models.exercise import Exercise
from app.models.user import User
from app.schemas.exercise import ExerciseRead

router = APIRouter(prefix="/exercises", tags=["exercises"])


@router.get("", response_model=list[ExerciseRead])
async def list_exercises(
    search: str | None = None,
    muscle: str | None = None,
    equipment: str | None = None,
    skip: int = 0,
    limit: int = 50,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> list[Exercise]:
    limit = min(limit, 100)
    stmt = select(Exercise)
    if search:
        stmt = stmt.where(Exercise.name.ilike(f"%{search}%"))
    if muscle:
        stmt = stmt.where(Exercise.primary_muscles.contains([muscle]))
    if equipment:
        stmt = stmt.where(Exercise.equipment.contains([equipment]))
    stmt = stmt.order_by(Exercise.name.asc()).offset(skip).limit(limit)

    result = await db.scalars(stmt)
    return list(result)


@router.get("/{exercise_id}", response_model=ExerciseRead)
async def get_exercise(
    exercise_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> Exercise:
    exercise = await db.get(Exercise, exercise_id)
    if exercise is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Exercise not found")
    return exercise
