import uuid
from datetime import date
from typing import Any

from pydantic import BaseModel, ConfigDict, EmailStr


class UserCreate(BaseModel):
    email: EmailStr
    password: str
    full_name: str | None = None


class UserLogin(BaseModel):
    email: EmailStr
    password: str


class UserUpdate(BaseModel):
    full_name: str | None = None
    avatar_url: str | None = None
    units: str | None = None
    rest_timer_default_s: int | None = None
    voice_coach: dict[str, Any] | None = None
    notification_prefs: dict[str, bool] | None = None
    locale: str | None = None


class OnboardingUpdate(BaseModel):
    """Written in one call at the end of the onboarding quiz."""

    dob: date | None = None
    gender: str | None = None
    height_cm: float | None = None
    weight_kg: float | None = None
    goal: str | None = None
    experience_level: str | None = None
    days_per_week: int | None = None
    session_minutes: int | None = None
    split_preference: str | None = None
    gym_location: str | None = None
    equipment: list[str] | None = None
    injuries: list[dict[str, Any]] | None = None
    onboarding_completed: bool = True


class UserRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    email: EmailStr
    full_name: str | None = None
    avatar_url: str | None = None
    dob: date | None = None
    gender: str | None = None
    height_cm: float | None = None
    weight_kg: float | None = None
    goal: str | None = None
    experience_level: str | None = None
    days_per_week: int | None = None
    session_minutes: int | None = None
    split_preference: str | None = None
    gym_location: str | None = None
    equipment: list[str] = []
    injuries: list[dict[str, Any]] = []
    units: str
    onboarding_completed: bool
    voice_coach: dict[str, Any]
    rest_timer_default_s: int
    xp: int
    subscription_tier: str
    notification_prefs: dict[str, Any]
    locale: str


class Token(BaseModel):
    access_token: str
    token_type: str = "bearer"


class PasswordResetRequest(BaseModel):
    email: EmailStr


class PasswordResetRequestResponse(BaseModel):
    message: str
    # Only populated when no SMTP is configured — a dev-mode substitute for
    # emailing the link. See `app/services/email_service.py`.
    debug_token: str | None = None


class PasswordResetConfirm(BaseModel):
    token: str
    new_password: str


class ChangePasswordRequest(BaseModel):
    current_password: str
    new_password: str


class ChangeEmailRequest(BaseModel):
    new_email: EmailStr
    password: str
