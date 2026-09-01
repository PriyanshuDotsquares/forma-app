import uuid
from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import Boolean, DateTime, Float, ForeignKey, Integer, String, func
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base

if TYPE_CHECKING:
    from app.models.exercise import Exercise
    from app.models.user import User


class Program(Base):
    __tablename__ = "programs"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    owner_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    split_type: Mapped[str] = mapped_column(String(32), nullable=False)
    days_per_week: Mapped[int] = mapped_column(Integer, nullable=False)
    duration_weeks: Mapped[int] = mapped_column(Integer, nullable=False, default=8)
    source: Mapped[str] = mapped_column(String(16), nullable=False, default="generated")
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default="true")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    owner: Mapped["User"] = relationship(back_populates="programs")
    days: Mapped[list["ProgramDay"]] = relationship(
        back_populates="program", cascade="all, delete-orphan", order_by="ProgramDay.order_index"
    )


class ProgramDay(Base):
    __tablename__ = "program_days"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    program_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("programs.id"), nullable=False, index=True)
    order_index: Mapped[int] = mapped_column(Integer, nullable=False)
    weekday: Mapped[int | None] = mapped_column(Integer, nullable=True)  # 0=Mon .. 6=Sun, null = unscheduled
    label: Mapped[str] = mapped_column(String(255), nullable=False)
    muscle_tags: Mapped[list[str]] = mapped_column(JSONB, nullable=False, default=list)
    is_rest: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False, server_default="false")
    estimated_minutes: Mapped[int | None] = mapped_column(Integer, nullable=True)

    program: Mapped["Program"] = relationship(back_populates="days")
    exercises: Mapped[list["ProgramExercise"]] = relationship(
        back_populates="day", cascade="all, delete-orphan", order_by="ProgramExercise.order_index"
    )


class ProgramExercise(Base):
    __tablename__ = "program_exercises"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    program_day_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("program_days.id"), nullable=False, index=True)
    exercise_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("exercises.id"), nullable=False)
    order_index: Mapped[int] = mapped_column(Integer, nullable=False)
    sets: Mapped[int] = mapped_column(Integer, nullable=False, default=3)
    rep_range_low: Mapped[int] = mapped_column(Integer, nullable=False, default=8)
    rep_range_high: Mapped[int] = mapped_column(Integer, nullable=False, default=12)
    load_type: Mapped[str] = mapped_column(String(16), nullable=False, default="weight")  # weight | percent_1rm | rpe
    target_value: Mapped[float | None] = mapped_column(Float, nullable=True)
    tempo: Mapped[str | None] = mapped_column(String(16), nullable=True)
    superset_group: Mapped[str | None] = mapped_column(String(8), nullable=True)
    notes: Mapped[str | None] = mapped_column(String(500), nullable=True)
    coach_with_camera: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False, server_default="false")

    day: Mapped["ProgramDay"] = relationship(back_populates="exercises")
    exercise: Mapped["Exercise"] = relationship()
