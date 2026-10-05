import logging
from functools import lru_cache

from pydantic import field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

logger = logging.getLogger(__name__)


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

    # Used by `app.db.ai_seed` (a manually-run script) to generate new
    # exercises/achievements/challenges, AND by `ai_plan_generator.
    # generate_program_smart` at request time to produce each user's
    # AI-personalized program. The app *runs* without it, but silently and
    # permanently: every `/programs/generate` call falls back to
    # `plan_generator`'s deterministic heuristic instead, with no error
    # surfaced anywhere — see `get_settings()`'s startup check below, which
    # exists specifically to catch this in logs before it looks like "the
    # AI feature doesn't work" for every user.
    groq_api_key: str | None = None


@lru_cache
def get_settings() -> Settings:
    settings = Settings()
    if not settings.groq_api_key:
        # Not fatal — `generate_program_smart` degrades to a deterministic
        # plan on purpose so onboarding never hard-fails — but that
        # degradation is otherwise completely silent (no warning, no error
        # response), so every user would get the same non-AI plan with
        # nothing in the logs to explain why. This is the one place that
        # runs unconditionally at startup, so it's the right place to make
        # the misconfiguration visible instead of only discoverable by
        # reading code.
        logger.warning(
            "GROQ_API_KEY is not set — AI-personalized program generation is disabled; "
            "every /programs/generate call will silently fall back to the deterministic generator."
        )
    return settings
