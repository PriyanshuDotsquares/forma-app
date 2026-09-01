import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict

from app.schemas.exercise import ExerciseRead


class WorkoutSetCreate(BaseModel):
    exercise_id: uuid.UUID
    set_index: int
    set_type: str = "normal"
    target_weight_kg: float | None = None
    target_reps: int | None = None
    actual_weight_kg: float | None = None
    actual_reps: int | None = None
    rpe: float | None = None
    form_score: int | None = None
    depth_pct: float | None = None


class WorkoutSetRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    exercise_id: uuid.UUID
    exercise: ExerciseRead
    set_index: int
    set_type: str
    target_weight_kg: float | None = None
    target_reps: int | None = None
    actual_weight_kg: float | None = None
    actual_reps: int | None = None
    rpe: float | None = None
    form_score: int | None = None
    depth_pct: float | None = None
    is_pr: bool
    completed_at: datetime


class WorkoutSessionCreate(BaseModel):
    program_day_id: uuid.UUID | None = None
    label: str = "Workout"


class WorkoutSessionFinish(BaseModel):
    duration_s: int | None = None
    calories: int | None = None
    rpe: float | None = None
    mood: int | None = None
    notes: str | None = None


class WorkoutSessionRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    program_day_id: uuid.UUID | None = None
    label: str
    started_at: datetime
    ended_at: datetime | None = None
    duration_s: int | None = None
    calories: int | None = None
    avg_form_score: float | None = None
    rpe: float | None = None
    mood: int | None = None
    notes: str | None = None
    sets: list[WorkoutSetRead] = []
