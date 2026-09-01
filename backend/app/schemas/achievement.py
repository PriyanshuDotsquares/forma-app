import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict


class AchievementRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    key: str
    category: str
    title: str
    description: str
    icon: str
    is_secret: bool


class UserAchievementRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    achievement: AchievementRead
    progress_value: float
    target_value: float
    unlocked_at: datetime | None = None


class RecordRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    exercise_id: uuid.UUID
    weight_kg: float
    reps: int
    est_1rm_kg: float
    achieved_at: datetime
