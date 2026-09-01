import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.db.session import get_db
from app.models.challenge import Challenge
from app.models.user import User
from app.schemas.challenge import LeaderboardEntryRead, UserChallengeRead
from app.services import challenges as challenges_service

router = APIRouter(prefix="/challenges", tags=["challenges"])


async def _get_challenge(db: AsyncSession, challenge_id: uuid.UUID) -> Challenge:
    challenge = await db.get(Challenge, challenge_id)
    if challenge is None or not challenge.is_active:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Challenge not found")
    return challenge


@router.get("", response_model=list[UserChallengeRead])
async def list_challenges(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> list[UserChallengeRead]:
    pairs = await challenges_service.list_for_user(db, current_user)
    return [
        UserChallengeRead(
            challenge=challenge,
            joined=entry is not None,
            progress_value=entry.progress_value if entry else 0.0,
            period_start=entry.period_start if entry else None,
            completed_at=entry.completed_at if entry else None,
        )
        for challenge, entry in pairs
    ]


@router.post("/{challenge_id}/join", response_model=UserChallengeRead)
async def join_challenge(
    challenge_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> UserChallengeRead:
    challenge = await _get_challenge(db, challenge_id)
    entry = await challenges_service.join(db, current_user, challenge)
    return UserChallengeRead(
        challenge=challenge,
        joined=True,
        progress_value=entry.progress_value,
        period_start=entry.period_start,
        completed_at=entry.completed_at,
    )


@router.post("/{challenge_id}/leave", status_code=status.HTTP_204_NO_CONTENT)
async def leave_challenge(
    challenge_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> None:
    challenge = await _get_challenge(db, challenge_id)
    await challenges_service.leave(db, current_user, challenge)


@router.get("/{challenge_id}/leaderboard", response_model=list[LeaderboardEntryRead])
async def get_leaderboard(
    challenge_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> list[LeaderboardEntryRead]:
    challenge = await _get_challenge(db, challenge_id)
    entries = await challenges_service.leaderboard(db, challenge, current_user.id)
    return [LeaderboardEntryRead(**entry) for entry in entries]
