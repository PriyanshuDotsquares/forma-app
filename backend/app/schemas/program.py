import uuid
from typing import Any

from pydantic import BaseModel, ConfigDict

from app.schemas.exercise import ExerciseRead


class GenerateProgramRequest(BaseModel):
    """Explicit overrides for /programs/generate — falls back to the
    caller's saved onboarding profile for any field left unset.

    `injuries` exists here (as well as on the `User` row, set separately via
    `PATCH /onboarding`) because during first-time onboarding the frontend
    calls `/programs/generate` *before* it saves the onboarding profile —
    `current_user.injuries` wouldn't be populated yet at generation time
    otherwise. Same `{part, side, severity, note?}` shape as `User.injuries`.
    """

    goal: str | None = None
    experience_level: str | None = None
    days_per_week: int | None = None
    session_minutes: int | None = None
    split_preference: str | None = None
    equipment: list[str] | None = None
    injuries: list[dict[str, Any]] | None = None


class ProgramExerciseCreate(BaseModel):
    exercise_id: uuid.UUID
    order_index: int
    sets: int = 3
    rep_range_low: int = 8
    rep_range_high: int = 12
    load_type: str = "weight"
    target_value: float | None = None
    tempo: str | None = None
    superset_group: str | None = None
    notes: str | None = None
    coach_with_camera: bool = False


class ProgramExerciseUpdate(BaseModel):
    order_index: int | None = None
    sets: int | None = None
    rep_range_low: int | None = None
    rep_range_high: int | None = None
    load_type: str | None = None
    target_value: float | None = None
    tempo: str | None = None
    superset_group: str | None = None
    notes: str | None = None
    coach_with_camera: bool | None = None


class ProgramExerciseRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    exercise_id: uuid.UUID
    exercise: ExerciseRead
    order_index: int
    sets: int
    rep_range_low: int
    rep_range_high: int
    load_type: str
    target_value: float | None = None
    tempo: str | None = None
    superset_group: str | None = None
    notes: str | None = None
    coach_with_camera: bool


class ProgramDayCreate(BaseModel):
    order_index: int
    weekday: int | None = None
    label: str
    muscle_tags: list[str] = []
    is_rest: bool = False
    estimated_minutes: int | None = None


class ProgramDayUpdate(BaseModel):
    order_index: int | None = None
    weekday: int | None = None
    label: str | None = None
    muscle_tags: list[str] | None = None
    is_rest: bool | None = None
    estimated_minutes: int | None = None


class ProgramDayRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    order_index: int
    weekday: int | None = None
    label: str
    muscle_tags: list[str]
    is_rest: bool
    estimated_minutes: int | None = None
    exercises: list[ProgramExerciseRead] = []


class ProgramCreate(BaseModel):
    name: str
    split_type: str
    days_per_week: int
    duration_weeks: int = 8


class ProgramRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    name: str
    split_type: str
    days_per_week: int
    duration_weeks: int
    source: str
    is_active: bool
    days: list[ProgramDayRead] = []
