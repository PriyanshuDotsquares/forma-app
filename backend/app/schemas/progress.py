from datetime import date

from pydantic import BaseModel


class ProgressSummary(BaseModel):
    period: str
    workouts: int
    volume_kg: float
    time_s: int
    avg_form_score: float | None = None
    streak_days: int


class VolumeByMuscle(BaseModel):
    muscle: str
    sets: int
    volume_kg: float


class VolumeTrendPoint(BaseModel):
    period_label: str
    volume_kg: float
    is_deload: bool = False


class RecoveryItem(BaseModel):
    muscle_group: str
    last_trained: date | None = None
    sets_last_session: int
    recovered_pct: float
    fresh_in_hours: float | None = None


class StrengthPoint(BaseModel):
    date: date
    est_1rm_kg: float


class FormQualityPoint(BaseModel):
    week_label: str
    form_score: float


class ConsistencyDay(BaseModel):
    date: date
    sessions: int
    volume_kg: float
    has_pr: bool
