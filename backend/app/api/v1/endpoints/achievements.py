from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.api.deps import get_current_user
from app.db.session import get_db
from app.models.achievement import UserAchievement
from app.models.user import User
from app.schemas.achievement import RecordRead, UserAchievementRead
from app.services.achievements import evaluate_achievements
from app.services.progress import current_records

router = APIRouter(tags=["achievements"])


@router.get("/achievements", response_model=list[UserAchievementRead])
async def list_achievements(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> list[UserAchievement]:
    stmt = (
        select(UserAchievement)
        .where(UserAchievement.user_id == current_user.id)
        .options(selectinload(UserAchievement.achievement))
    )
    existing = list(await db.scalars(stmt))
    if not existing:
        # First call for a brand-new user — seed their progress rows, then re-fetch with the relationship loaded.
        await evaluate_achievements(db, current_user.id)
        existing = list(await db.scalars(stmt))
    return existing


@router.get("/records", response_model=list[RecordRead])
async def list_records(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    return await current_records(db, current_user.id)
