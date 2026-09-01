import uuid
from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import Boolean, DateTime, Float, ForeignKey, Integer, String, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base

if TYPE_CHECKING:
    from app.models.exercise import Exercise
    from app.models.user import User


class WorkoutSession(Base):
    __tablename__ = "workout_sessions"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    program_day_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), ForeignKey("program_days.id"), nullable=True)
    label: Mapped[str] = mapped_column(String(255), nullable=False, default="Workout")
    started_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    ended_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    duration_s: Mapped[int | None] = mapped_column(Integer, nullable=True)
    calories: Mapped[int | None] = mapped_column(Integer, nullable=True)
    avg_form_score: Mapped[float | None] = mapped_column(Float, nullable=True)
    rpe: Mapped[float | None] = mapped_column(Float, nullable=True)
    mood: Mapped[int | None] = mapped_column(Integer, nullable=True)  # 1..5
    notes: Mapped[str | None] = mapped_column(String(2000), nullable=True)

    user: Mapped["User"] = relationship(back_populates="workout_sessions")
    sets: Mapped[list["WorkoutSet"]] = relationship(
        back_populates="session", cascade="all, delete-orphan", order_by="WorkoutSet.set_index"
    )


class WorkoutSet(Base):
    __tablename__ = "workout_sets"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    session_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("workout_sessions.id"), nullable=False, index=True)
    exercise_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("exercises.id"), nullable=False)
    set_index: Mapped[int] = mapped_column(Integer, nullable=False)
    set_type: Mapped[str] = mapped_column(String(16), nullable=False, default="normal")  # normal | warmup | drop
    target_weight_kg: Mapped[float | None] = mapped_column(Float, nullable=True)
    target_reps: Mapped[int | None] = mapped_column(Integer, nullable=True)
    actual_weight_kg: Mapped[float | None] = mapped_column(Float, nullable=True)
    actual_reps: Mapped[int | None] = mapped_column(Integer, nullable=True)
    rpe: Mapped[float | None] = mapped_column(Float, nullable=True)
    form_score: Mapped[int | None] = mapped_column(Integer, nullable=True)  # 0..100, from on-device coaching
    depth_pct: Mapped[float | None] = mapped_column(Float, nullable=True)
    is_pr: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False, server_default="false")
    completed_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    session: Mapped["WorkoutSession"] = relationship(back_populates="sets")
    exercise: Mapped["Exercise"] = relationship()
