"""Transactional email delivery.

Sends via SMTP when `settings.smtp_host` is configured; otherwise logs the
message instead of failing, so flows that depend on email (password reset)
stay usable in an environment with no mail server wired up. `smtplib` is
synchronous — routed through a thread so it doesn't block the event loop.
"""

import asyncio
import logging
import smtplib
from email.message import EmailMessage

from app.core.config import get_settings

logger = logging.getLogger("forma.email")
settings = get_settings()


def _send_sync(to: str, subject: str, body: str) -> None:
    message = EmailMessage()
    message["Subject"] = subject
    message["From"] = settings.smtp_from
    message["To"] = to
    message.set_content(body)

    with smtplib.SMTP(settings.smtp_host, settings.smtp_port, timeout=10) as smtp:
        smtp.starttls()
        if settings.smtp_username and settings.smtp_password:
            smtp.login(settings.smtp_username, settings.smtp_password)
        smtp.send_message(message)


async def send_email(to: str, subject: str, body: str) -> None:
    if not settings.smtp_host:
        logger.info("No SMTP configured — would send email to %s:\nSubject: %s\n%s", to, subject, body)
        return
    await asyncio.to_thread(_send_sync, to, subject, body)
