from functools import lru_cache

from pydantic import field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    project_name: str = "FORMA API"
    api_v1_prefix: str = "/api/v1"

    database_url: str = "postgresql+asyncpg://forma:forma@localhost:5432/forma"

    @field_validator("database_url")
    @classmethod
    def _use_asyncpg_driver(cls, v: str) -> str:
        # Managed Postgres hosts (Render, Railway, Heroku, ...) hand out a
        # plain postgres:// or postgresql:// connection string — the async
        # engine needs the asyncpg driver named explicitly in the scheme.
        for prefix in ("postgres://", "postgresql://"):
            if v.startswith(prefix):
                return f"postgresql+asyncpg://{v[len(prefix):]}"
        return v

    secret_key: str = "change-me-in-.env"
    algorithm: str = "HS256"
    access_token_expire_minutes: int = 60 * 24

    cors_origins: list[str] = ["*"]

    # Optional SMTP delivery for transactional email (password reset, etc).
    # Left unset in dev — `email_service.send_email` falls back to logging
    # the message instead of failing, and password-reset echoes the token
    # in its API response so the flow stays testable without a real inbox.
    smtp_host: str | None = None
    smtp_port: int = 587
    smtp_username: str | None = None
    smtp_password: str | None = None
    smtp_from: str = "noreply@forma.app"

    # Used only by `app.db.ai_seed` (a manually-run script, not called at
    # request time or during `alembic upgrade`) to generate new exercises/
    # achievements/challenges via the Groq API. Unset in most
    # environments — the app runs fine without it.
    groq_api_key: str | None = None


@lru_cache
def get_settings() -> Settings:
    return Settings()
