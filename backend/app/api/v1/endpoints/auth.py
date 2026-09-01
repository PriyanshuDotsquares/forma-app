import hashlib
import secrets
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.core.security import create_access_token, hash_password, verify_password
from app.db.session import get_db
from app.models.user import User
from app.schemas.user import (
    PasswordResetConfirm,
    PasswordResetRequest,
    PasswordResetRequestResponse,
    Token,
    UserCreate,
    UserRead,
)
from app.services.email_service import send_email

router = APIRouter(prefix="/auth", tags=["auth"])
settings = get_settings()

_RESET_TOKEN_TTL = timedelta(minutes=30)
_GENERIC_RESET_MESSAGE = "If that email is registered, we've sent a password reset link."


def _hash_token(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


@router.post("/register", response_model=UserRead, status_code=status.HTTP_201_CREATED)
async def register(payload: UserCreate, db: AsyncSession = Depends(get_db)) -> User:
    existing = await db.scalar(select(User).where(User.email == payload.email))
    if existing is not None:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Email already registered")

    user = User(
        email=payload.email,
        hashed_password=hash_password(payload.password),
        full_name=payload.full_name,
    )
    db.add(user)
    await db.commit()
    await db.refresh(user)
    return user


@router.post("/login", response_model=Token)
async def login(
    form_data: OAuth2PasswordRequestForm = Depends(),
    db: AsyncSession = Depends(get_db),
) -> Token:
    user = await db.scalar(select(User).where(User.email == form_data.username))
    if user is None or not verify_password(form_data.password, user.hashed_password):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect email or password",
            headers={"WWW-Authenticate": "Bearer"},
        )

    access_token = create_access_token(subject=str(user.id))
    return Token(access_token=access_token)


@router.post("/password-reset/request", response_model=PasswordResetRequestResponse)
async def request_password_reset(
    payload: PasswordResetRequest,
    db: AsyncSession = Depends(get_db),
) -> PasswordResetRequestResponse:
    user = await db.scalar(select(User).where(User.email == payload.email))
    if user is None:
        # Same response whether or not the email exists — don't leak account existence.
        return PasswordResetRequestResponse(message=_GENERIC_RESET_MESSAGE)

    token = secrets.token_urlsafe(32)
    user.password_reset_token_hash = _hash_token(token)
    user.password_reset_expires_at = datetime.now(timezone.utc) + _RESET_TOKEN_TTL
    await db.commit()

    await send_email(
        user.email,
        "Reset your FORMA password",
        f"Use this code to reset your password (expires in 30 minutes): {token}",
    )

    # No SMTP configured — echo the token so the flow is testable without a
    # real inbox. Once `smtp_host` is set, this stops automatically.
    debug_token = token if not settings.smtp_host else None
    return PasswordResetRequestResponse(message=_GENERIC_RESET_MESSAGE, debug_token=debug_token)


@router.post("/password-reset/confirm", response_model=UserRead)
async def confirm_password_reset(
    payload: PasswordResetConfirm,
    db: AsyncSession = Depends(get_db),
) -> User:
    if len(payload.new_password) < 8:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Password must be at least 8 characters")

    token_hash = _hash_token(payload.token)
    user = await db.scalar(select(User).where(User.password_reset_token_hash == token_hash))
    now = datetime.now(timezone.utc)
    if user is None or user.password_reset_expires_at is None or user.password_reset_expires_at < now:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="That reset code is invalid or has expired")

    user.hashed_password = hash_password(payload.new_password)
    user.password_reset_token_hash = None
    user.password_reset_expires_at = None
    await db.commit()
    await db.refresh(user)
    return user
