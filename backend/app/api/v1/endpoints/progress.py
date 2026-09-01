import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.db.session import get_db
from app.models.user import User
from app.schemas.progress import (
    ConsistencyDay,
    FormQualityPoint,
    ProgressSummary,
    RecoveryItem,
    StrengthPoint,
    VolumeByMuscle,
    VolumeTrendPoint,
)
from app.services import progress as progress_service

router = APIRouter(prefix="/progress", tags=["progress"])

_VALID_PERIODS = {"week", "month", "3month", "year", "all"}


def _check_period(period: str) -> None:
    if period not in _VALID_PERIODS:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"period must be one of {sorted(_VALID_PERIODS)}")


@router.get("/summary", response_model=ProgressSummary)
async def get_summary(
    period: str = "month",
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> ProgressSummary:
    _check_period(period)
    return await progress_service.summary(db, current_user.id, period)


@router.get("/volume/by-muscle", response_model=list[VolumeByMuscle])
async def get_volume_by_muscle(
    period: str = "month",
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> list[VolumeByMuscle]:
    _check_period(period)
    return await progress_service.volume_by_muscle(db, current_user.id, period)


@router.get("/volume/trend", response_model=list[VolumeTrendPoint])
async def get_volume_trend(
    period: str = "month",
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> list[VolumeTrendPoint]:
    _check_period(period)
    return await progress_service.volume_trend(db, current_user.id, period)


@router.get("/recovery", response_model=list[RecoveryItem])
async def get_recovery(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> list[RecoveryItem]:
    return await progress_service.recovery(db, current_user.id)


@router.get("/strength", response_model=list[StrengthPoint])
async def get_strength_trend(
    exercise_id: uuid.UUID,
    period: str = "year",
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> list[StrengthPoint]:
    _check_period(period)
    return await progress_service.strength_trend(db, current_user.id, exercise_id, period)


@router.get("/form-quality", response_model=list[FormQualityPoint])
async def get_form_quality_trend(
    period: str = "3month",
    exercise_id: uuid.UUID | None = None,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> list[FormQualityPoint]:
    _check_period(period)
    if current_user.subscription_tier != "pro":
        raise HTTPException(
            status_code=status.HTTP_402_PAYMENT_REQUIRED,
            detail="Form quality trends are a FORMA Pro feature",
        )
    return await progress_service.form_quality_trend(db, current_user.id, period, exercise_id)


@router.get("/consistency", response_model=list[ConsistencyDay])
async def get_consistency_calendar(
    year: int,
    month: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> list[ConsistencyDay]:
    if not (1 <= month <= 12):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="month must be 1-12")
    return await progress_service.consistency_calendar(db, current_user.id, year, month)
