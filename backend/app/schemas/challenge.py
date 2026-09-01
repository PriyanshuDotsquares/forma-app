import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict


class ChallengeRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    key: str
    title: str
    description: str
    metric: str
    period: str
    target_value: float
    icon: str
    is_group: bool


class UserChallengeRead(BaseModel):
    challenge: ChallengeRead
    joined: bool
    progress_value: float
    period_start: datetime | None = None
    completed_at: datetime | None = None


class LeaderboardEntryRead(BaseModel):
    rank: int
    display_name: str
    progress_value: float
    is_me: bool
