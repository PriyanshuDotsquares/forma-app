import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.api.deps import get_current_user
from app.db.session import get_db
from app.models.exercise import Exercise
from app.models.program import Program, ProgramDay, ProgramExercise
from app.models.user import User
from app.schemas.program import (
    GenerateProgramRequest,
    ProgramDayCreate,
    ProgramDayRead,
    ProgramDayUpdate,
    ProgramExerciseCreate,
    ProgramExerciseRead,
    ProgramExerciseUpdate,
    ProgramRead,
)
from app.services.plan_generator import fill_day_exercises, generate_program

router = APIRouter(prefix="/programs", tags=["programs"])

_PROGRAM_LOAD_OPTIONS = (
    selectinload(Program.days).selectinload(ProgramDay.exercises).selectinload(ProgramExercise.exercise),
)


async def _get_owned_program(db: AsyncSession, program_id: uuid.UUID, user: User) -> Program:
    program = await db.scalar(select(Program).where(Program.id == program_id).options(*_PROGRAM_LOAD_OPTIONS))
    if program is None or program.owner_id != user.id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Program not found")
    return program


async def _get_owned_day(db: AsyncSession, day_id: uuid.UUID, user: User) -> ProgramDay:
    day = await db.scalar(
        select(ProgramDay)
        .where(ProgramDay.id == day_id)
        .options(
            selectinload(ProgramDay.program),
            selectinload(ProgramDay.exercises).selectinload(ProgramExercise.exercise),
        )
    )
    if day is None or day.program.owner_id != user.id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Program day not found")
    return day


@router.post("/generate", response_model=ProgramRead, status_code=status.HTTP_201_CREATED)
async def generate(
    payload: GenerateProgramRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> Program:
    days_per_week = payload.days_per_week or current_user.days_per_week
    if not days_per_week:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="days_per_week is required (set it during onboarding or pass it explicitly)",
        )

    return await generate_program(
        db,
        user=current_user,
        goal=payload.goal or current_user.goal,
        experience_level=payload.experience_level or current_user.experience_level,
        days_per_week=days_per_week,
        session_minutes=payload.session_minutes or current_user.session_minutes,
        split_preference=payload.split_preference or current_user.split_preference,
        equipment=payload.equipment or current_user.equipment,
    )


@router.get("", response_model=list[ProgramRead])
async def list_programs(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> list[Program]:
    stmt = select(Program).where(Program.owner_id == current_user.id).options(*_PROGRAM_LOAD_OPTIONS).order_by(Program.created_at.desc())
    return list(await db.scalars(stmt))


@router.get("/active", response_model=ProgramRead)
async def get_active_program(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> Program:
    program = await db.scalar(
        select(Program)
        .where(Program.owner_id == current_user.id, Program.is_active == True)  # noqa: E712
        .options(*_PROGRAM_LOAD_OPTIONS)
    )
    if program is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="No active program")
    return program


@router.get("/{program_id}", response_model=ProgramRead)
async def get_program(
    program_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> Program:
    return await _get_owned_program(db, program_id, current_user)


@router.delete("/{program_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_program(
    program_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> None:
    program = await _get_owned_program(db, program_id, current_user)
    await db.delete(program)
    await db.commit()


@router.post("/{program_id}/days", response_model=ProgramDayRead, status_code=status.HTTP_201_CREATED)
async def add_day(
    program_id: uuid.UUID,
    payload: ProgramDayCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> ProgramDay:
    program = await _get_owned_program(db, program_id, current_user)
    day = ProgramDay(program_id=program.id, **payload.model_dump())
    db.add(day)
    await db.commit()
    await db.refresh(day)
    return day


@router.patch("/days/{day_id}", response_model=ProgramDayRead)
async def update_day(
    day_id: uuid.UUID,
    payload: ProgramDayUpdate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> ProgramDay:
    day = await _get_owned_day(db, day_id, current_user)
    for field, value in payload.model_dump(exclude_unset=True).items():
        setattr(day, field, value)
    await db.commit()
    # `db.refresh()` only reloads column attributes, not relationships — a
    # plain refresh leaves `exercises`/`exercises.exercise` expired, and
    # accessing them during response serialization then tries an implicit
    # lazy-load outside the request's greenlet context (MissingGreenlet).
    # Re-querying with explicit eager-loading avoids that, same as
    # `fill_day_exercises`/`generate_program` already do. `expire_all()`
    # first so the identity map doesn't hand back `day`'s already-loaded
    # (now stale) collection instead of re-running the selectinload; using
    # the `day_id` path param rather than `day.id` avoids touching the
    # (now expired) ORM object directly, which would itself trigger an
    # implicit lazy-load outside the async context.
    db.expire_all()
    result = await db.scalars(
        select(ProgramDay)
        .where(ProgramDay.id == day_id)
        .options(selectinload(ProgramDay.exercises).selectinload(ProgramExercise.exercise))
    )
    return result.one()


@router.post("/days/{day_id}/fill", response_model=ProgramDayRead)
async def fill_day(
    day_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> ProgramDay:
    day = await _get_owned_day(db, day_id, current_user)
    return await fill_day_exercises(db, day, current_user)


@router.delete("/days/{day_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_day(
    day_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> None:
    day = await _get_owned_day(db, day_id, current_user)
    await db.delete(day)
    await db.commit()


@router.post("/days/{day_id}/exercises", response_model=ProgramExerciseRead, status_code=status.HTTP_201_CREATED)
async def add_exercise_to_day(
    day_id: uuid.UUID,
    payload: ProgramExerciseCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> ProgramExercise:
    await _get_owned_day(db, day_id, current_user)
    exercise = await db.get(Exercise, payload.exercise_id)
    if exercise is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Exercise not found")

    program_exercise = ProgramExercise(program_day_id=day_id, **payload.model_dump())
    db.add(program_exercise)
    await db.commit()
    await db.refresh(program_exercise, attribute_names=["exercise"])
    return program_exercise


@router.patch("/exercises/{program_exercise_id}", response_model=ProgramExerciseRead)
async def update_program_exercise(
    program_exercise_id: uuid.UUID,
    payload: ProgramExerciseUpdate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> ProgramExercise:
    program_exercise = await db.scalar(
        select(ProgramExercise)
        .where(ProgramExercise.id == program_exercise_id)
        .options(selectinload(ProgramExercise.day).selectinload(ProgramDay.program), selectinload(ProgramExercise.exercise))
    )
    if program_exercise is None or program_exercise.day.program.owner_id != current_user.id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Program exercise not found")

    for field, value in payload.model_dump(exclude_unset=True).items():
        setattr(program_exercise, field, value)
    await db.commit()
    await db.refresh(program_exercise)
    return program_exercise


@router.delete("/exercises/{program_exercise_id}", status_code=status.HTTP_204_NO_CONTENT)
async def remove_program_exercise(
    program_exercise_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> None:
    program_exercise = await db.scalar(
        select(ProgramExercise)
        .where(ProgramExercise.id == program_exercise_id)
        .options(selectinload(ProgramExercise.day).selectinload(ProgramDay.program))
    )
    if program_exercise is None or program_exercise.day.program.owner_id != current_user.id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Program exercise not found")
    await db.delete(program_exercise)
    await db.commit()
