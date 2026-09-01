import uuid
from datetime import datetime
from typing import Any

from sqlalchemy import Boolean, DateTime, String, func
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class Exercise(Base):
    """A library exercise. Seeded via the initial-schema migration —
    FORMA's own curated library, not a copy of a third-party database."""

    __tablename__ = "exercises"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    slug: Mapped[str] = mapped_column(String(128), unique=True, index=True, nullable=False)
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    primary_muscles: Mapped[list[str]] = mapped_column(JSONB, nullable=False, default=list)
    secondary_muscles: Mapped[list[str]] = mapped_column(JSONB, nullable=False, default=list)
    equipment: Mapped[list[str]] = mapped_column(JSONB, nullable=False, default=list)
    difficulty: Mapped[str] = mapped_column(String(16), nullable=False, default="intermediate")
    execution_steps: Mapped[list[str]] = mapped_column(JSONB, nullable=False, default=list)
    pro_cues: Mapped[list[str]] = mapped_column(JSONB, nullable=False, default=list)
    mistakes: Mapped[list[dict[str, Any]]] = mapped_column(JSONB, nullable=False, default=list)
    supports_camera: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False, server_default="false")
    camera_view: Mapped[str | None] = mapped_column(String(16), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
