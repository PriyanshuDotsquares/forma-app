import uuid
from datetime import date, datetime
from typing import TYPE_CHECKING, Any

from sqlalchemy import Boolean, Date, DateTime, Float, Integer, String, func
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base

if TYPE_CHECKING:
    from app.models.body_metric import BodyMetric
    from app.models.program import Program
    from app.models.record import PersonalRecord
    from app.models.achievement import UserAchievement
    from app.models.challenge import UserChallenge
    from app.models.workout import WorkoutSession


class User(Base):
    __tablename__ = "users"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    email: Mapped[str] = mapped_column(String(255), unique=True, index=True, nullable=False)
    hashed_password: Mapped[str] = mapped_column(String(255), nullable=False)
    full_name: Mapped[str | None] = mapped_column(String(255), nullable=True)
    avatar_url: Mapped[str | None] = mapped_column(String(1024), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    # Onboarding / training profile — gathered by the quiz, editable in Settings.
    dob: Mapped[date | None] = mapped_column(Date, nullable=True)
    gender: Mapped[str | None] = mapped_column(String(32), nullable=True)
    height_cm: Mapped[float | None] = mapped_column(Float, nullable=True)
    weight_kg: Mapped[float | None] = mapped_column(Float, nullable=True)
    goal: Mapped[str | None] = mapped_column(String(32), nullable=True)
    experience_level: Mapped[str | None] = mapped_column(String(32), nullable=True)
    days_per_week: Mapped[int | None] = mapped_column(Integer, nullable=True)
    session_minutes: Mapped[int | None] = mapped_column(Integer, nullable=True)
    split_preference: Mapped[str | None] = mapped_column(String(32), nullable=True)
    gym_location: Mapped[str | None] = mapped_column(String(32), nullable=True)
    equipment: Mapped[list[str]] = mapped_column(JSONB, nullable=False, default=list, server_default="[]")
    injuries: Mapped[list[dict[str, Any]]] = mapped_column(JSONB, nullable=False, default=list, server_default="[]")
    units: Mapped[str] = mapped_column(String(16), nullable=False, default="metric", server_default="metric")
    onboarding_completed: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False, server_default="false")
    locale: Mapped[str] = mapped_column(String(8), nullable=False, default="en", server_default="en")

    # Password reset — a short-lived hashed token + expiry, cleared on use.
    password_reset_token_hash: Mapped[str | None] = mapped_column(String(64), nullable=True)
    password_reset_expires_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    notification_prefs: Mapped[dict[str, Any]] = mapped_column(
        JSONB,
        nullable=False,
        default=lambda: {
            "workout_reminders": True,
            "achievement_alerts": True,
            "weekly_summary": True,
            "challenge_updates": True,
        },
        server_default='{"workout_reminders": true, "achievement_alerts": true, "weekly_summary": true, "challenge_updates": true}',
    )

    # Coaching preferences.
    voice_coach: Mapped[dict[str, Any]] = mapped_column(
        JSONB,
        nullable=False,
        default=lambda: {
            "enabled": True,
            "verbosity": "standard",
            "voice": "alex_en_gb",
            "count_reps": False,
            "encouragement": True,
            "volume": 0.7,
            "duck_music": True,
        },
        server_default='{"enabled": true, "verbosity": "standard", "voice": "alex_en_gb", "count_reps": false, "encouragement": true, "volume": 0.7, "duck_music": true}',
    )
    rest_timer_default_s: Mapped[int] = mapped_column(Integer, nullable=False, default=90, server_default="90")

    # Gamification + monetization.
    xp: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")
    subscription_tier: Mapped[str] = mapped_column(String(16), nullable=False, default="free", server_default="free")

    programs: Mapped[list["Program"]] = relationship(back_populates="owner", cascade="all, delete-orphan")
    workout_sessions: Mapped[list["WorkoutSession"]] = relationship(back_populates="user", cascade="all, delete-orphan")
    personal_records: Mapped[list["PersonalRecord"]] = relationship(back_populates="user", cascade="all, delete-orphan")
    achievements: Mapped[list["UserAchievement"]] = relationship(back_populates="user", cascade="all, delete-orphan")
    body_metrics: Mapped[list["BodyMetric"]] = relationship(back_populates="user", cascade="all, delete-orphan")
    challenge_entries: Mapped[list["UserChallenge"]] = relationship(back_populates="user", cascade="all, delete-orphan")
