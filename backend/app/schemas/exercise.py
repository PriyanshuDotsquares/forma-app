import uuid
from typing import Any

from pydantic import BaseModel, ConfigDict


class ExerciseRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    slug: str
    name: str
    primary_muscles: list[str]
    secondary_muscles: list[str]
    equipment: list[str]
    difficulty: str
    execution_steps: list[str]
    pro_cues: list[str]
    mistakes: list[dict[str, Any]]
    supports_camera: bool
    camera_view: str | None = None
