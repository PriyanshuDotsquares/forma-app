import uuid
from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import Boolean, DateTime, Float, ForeignKey, String, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base

if TYPE_CHECKING:
    from app.models.user import User


class Challenge(Base):
    """Global challenge definitions, seeded via migration — same shape as
    `Achievement`, but time-boxed (weekly/monthly) rather than lifetime."""

    __tablename__ = "challenges"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    key: Mapped[str] = mapped_column(String(64), unique=True, index=True, nullable=False)
    title: Mapped[str] = mapped_column(String(255), nullable=False)
    description: Mapped[str] = mapped_column(String(500), nullable=False)
    metric: Mapped[str] = mapped_column(String(32), nullable=False)  # volume_kg | session_count | streak_days
    period: Mapped[str] = mapped_column(String(16), nullable=False)  # weekly | monthly | ongoing
    target_value: Mapped[float] = mapped_column(Float, nullable=False)
    icon: Mapped[str] = mapped_column(String(32), nullable=False, default="flag")
    is_group: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default="true")
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default="true")


class UserChallenge(Base):
    __tablename__ = "user_challenges"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    challenge_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("challenges.id"), nullable=False, index=True)
    joined_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    period_start: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    progress_value: Mapped[float] = mapped_column(Float, nullable=False, default=0)
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    user: Mapped["User"] = relationship(back_populates="challenge_entries")
    challenge: Mapped["Challenge"] = relationship()
