Status: Approved (Retroactive Baseline — documents behavior as implemented, dated 2026-09-10)
Owner: Engineering team (retroactive)
Related: n/a

## Summary

FORMA's auth-identity module covers account registration, email/password login, session persistence across app restarts, logout, password reset (request + confirm), and in-app change-password / change-email. It is implemented as a Flutter feature (`app/lib/features/auth`) backed by a FastAPI router (`backend/app/api/v1/endpoints/auth.py`) and the shared `/users/me/*` endpoints (`backend/app/api/v1/endpoints/users.py`). Sessions use a bearer JWT stored in the device's secure storage. There is no social sign-in (Apple/Google) — no such packages are declared and no such UI exists.

## Background / Problem

FORMA needs every user to have an identified, persistent account so their training profile, workout history, and AI-generated plan are private and reattachable across sessions and devices. Because there is no SMTP provider configured in this environment, the password-reset flow was built to degrade gracefully to a "dev mode" token-echo path rather than silently failing.

## User Stories

- As a new user, I can create an account with an email and password so I can start using FORMA.
- As a returning user, I can sign in with my email and password so I can access my existing plan and history.
- As a signed-in user, I stay signed in across app restarts without re-entering my credentials, until I explicitly sign out or my token becomes invalid.
- As a user who forgot my password, I can request a reset code by email and use it to set a new password without contacting support.
- As a signed-in user, I can change my password (given my current password) and change my account email (given my current password), from within the app.
- As a user who deleted and reinstalled the app, I do not get silently signed back in with a stale session.

## Acceptance Criteria (EARS format: "WHEN/IF ... THE SYSTEM SHALL ...")

**Registration**
- WHEN a user submits the sign-up form with a syntactically valid email and a password of at least 8 characters, THE SYSTEM SHALL call `POST /auth/register`, create a `User` row with a bcrypt-hashed password, and then automatically log the user in (`AuthRepository.register` → `login`, `app/lib/features/auth/data/auth_repository.dart:14-24`).
- IF the submitted email is already registered, THE SYSTEM SHALL reject the request with HTTP 400 "Email already registered" (`backend/app/api/v1/endpoints/auth.py:37-39`).
- WHEN the client-side password field contains fewer than 8 characters, THE SYSTEM SHALL block submission in the UI with a validation message ("At least 8 characters") before any network call is made (`app/lib/features/auth/presentation/auth_screen.dart:151-154`).

**Login**
- WHEN a user submits valid credentials, THE SYSTEM SHALL call `POST /auth/login` (OAuth2 password form), verify the password with bcrypt, issue a JWT access token, persist it to secure storage, and fetch/display the user's profile (`auth_repository.dart:26-38`, `backend/app/api/v1/endpoints/auth.py:52-66`).
- IF the email is unknown or the password does not match, THE SYSTEM SHALL respond with HTTP 401 "Incorrect email or password" and THE SYSTEM SHALL display a "Sign-in failed" banner in the UI (`auth.py:57-63`, `auth_screen.dart:173-176`).
- WHILE a login or register call is in flight, THE SYSTEM SHALL show a loading spinner on the submit button and disable further router redirects away from the auth screen (`auth_controller.dart:35-47`, `app_router.dart:126-137`).

**Session persistence**
- WHEN the app starts, THE SYSTEM SHALL first run `clearStaleTokenOnFreshInstall()`, then check for a stored token, and IF one exists, THE SYSTEM SHALL call `GET /users/me` to validate it and restore the session (`auth_controller.dart:16-33`).
- IF the stored token is invalid or the validation call fails, THE SYSTEM SHALL clear the token and treat the user as signed out (`auth_controller.dart:27-32`).
- IF any API response returns HTTP 401, THE SYSTEM SHALL clear the stored token and reset in-app auth state to signed-out (`app/lib/core/network/api_client.dart:32-38`, `onUnauthorized` callback wired in `auth_controller.dart:19`).
- IF this is the first launch since install (no `SharedPreferences` install marker present), THE SYSTEM SHALL proactively clear any token left in secure storage before it is ever read, so a stale Keychain-persisted token from a prior install cannot auto-sign-in the user (`api_client.dart:56-71`, called from `auth_controller.dart:24`).

**Logout**
- WHEN a signed-in user logs out, THE SYSTEM SHALL delete the stored token and reset in-app state to signed-out (`auth_controller.dart:89-92`, `auth_repository.dart:132`).

**Password reset**
- WHEN a user requests a password reset for an email, THE SYSTEM SHALL respond with the same generic message regardless of whether the email is registered, to avoid leaking account existence (`auth.py:69-93`, `_GENERIC_RESET_MESSAGE`).
- IF the email is registered, THE SYSTEM SHALL generate a random 32-byte URL-safe token, store only its SHA-256 hash plus a 30-minute expiry on the user row, and attempt to email the raw token via `send_email` (`auth.py:27,31-32,79-88`).
- IF no SMTP host is configured, THE SYSTEM SHALL log the email instead of sending it, and additionally echo the raw token back in the API response as `debug_token` so the flow remains testable (`email_service.py:34-38`, `auth.py:90-93`, `schemas/user.py:85-89`).
- WHEN a user submits a reset token and a new password of at least 8 characters to confirm, THE SYSTEM SHALL hash the submitted token, look up a user whose stored hash matches and whose expiry has not passed, set the new bcrypt-hashed password, and clear the token/expiry fields (`auth.py:96-115`).
- IF the token does not match any user or has expired, THE SYSTEM SHALL reject with HTTP 400 "That reset code is invalid or has expired" (`auth.py:107-108`).

**Change password / change email**
- WHEN a signed-in user submits a current password and new password (>=8 chars) to change password, THE SYSTEM SHALL verify the current password, then set the new bcrypt-hashed password (`backend/app/api/v1/endpoints/users.py:33-47`).
- IF the current password does not verify, THE SYSTEM SHALL reject with HTTP 400 "Current password is incorrect" (`users.py:39-40`).
- WHEN a signed-in user submits a new email and their current password to change email, THE SYSTEM SHALL verify the password, check the new email is not already taken by another user (case-insensitive), and update the email (`users.py:50-67`).
- IF the password does not verify, THE SYSTEM SHALL reject with HTTP 400 "Password is incorrect"; IF the new email is already registered to a different account, THE SYSTEM SHALL reject with HTTP 400 "That email is already registered" (`users.py:56-62`).

**Routing / access control**
- IF the user is not signed in, THE SYSTEM SHALL redirect any route other than `/intro`, `/auth`, `/auth/forgot-password`, or `/auth/reset-password` to `/intro` (`app_router.dart:138`).
- IF the user is signed in but has not completed onboarding, THE SYSTEM SHALL redirect any route other than `/onboarding` to `/onboarding` (`app_router.dart:139`).

## Out of Scope

- Apple Sign-In / Google Sign-In: not implemented. No `sign_in_with_apple` or `google_sign_in` package is declared in `app/pubspec.yaml`, and no such UI element exists in `auth_screen.dart` — verified by full-repo grep across `app/lib`, not merely assumed absent. There is no stub button, functional or otherwise.
- Real transactional email delivery is out of scope for the current dev/staging environment — see `smtp_host` unset by default (`backend/app/core/config.py:36`) and the dev-mode token-echo fallback.
- Multi-factor authentication, magic links, refresh tokens / token rotation: not implemented (single long-lived access token only — see Non-Functional Requirements).
- Account deletion: not part of this module (not present in the files reviewed).
- Onboarding-quiz data collection (`/onboarding` endpoint, `submitOnboarding`) belongs to a separate onboarding module and is only referenced here for router redirect context.
- Full network-layer design (interceptors, retry, base `ApiClient` beyond auth-token handling) belongs to module 013-engineering-infrastructure.

## Non-Functional Requirements

- Passwords are hashed with bcrypt via `passlib.context.CryptContext(schemes=["bcrypt"])` (`backend/app/core/security.py:9,12-13`); plaintext passwords are never stored.
- Access tokens are JWTs signed with HS256 using `settings.secret_key`, with a default 24-hour expiry (`access_token_expire_minutes = 60 * 24`, `backend/app/core/config.py:26-28`, `security.py:20-25`). There is no refresh-token mechanism — the token is a flat bearer credential valid until it expires or the user logs out.
- `settings.secret_key` defaults to the literal string `"change-me-in-.env"` if not overridden by environment configuration (`config.py:26`) — this is a deployment-configuration concern, not a code defect, but it means an unconfigured deployment would sign tokens with a publicly-known key.
- Password-reset tokens are single-use, hashed at rest (SHA-256, not bcrypt — a lighter-weight scheme deemed acceptable for a short-lived, high-entropy, single-use secret vs. bcrypt for long-lived user passwords), and expire after 30 minutes (`auth.py:27,31-32,79-81`).
- The client stores the access token in `flutter_secure_storage` (iOS Keychain / Android Keystore), not `SharedPreferences` (`api_client.dart:12-13,50-54`).
- The password-reset request endpoint returns an identical response regardless of account existence, mitigating email enumeration (`auth.py:74-77`).
- Backend password-length minimum (8 chars) is enforced server-side only for password-reset-confirm and change-password (`auth.py:101-102`, `users.py:41-42`); registration does not enforce a server-side minimum length (see Open Questions).

## Open Questions

- Registration (`POST /auth/register`, `backend/app/schemas/user.py:8-11` `UserCreate`, `auth.py:35-49`) has no server-side password-length (or complexity) validation — only the Flutter client enforces the 8-character minimum (`auth_screen.dart:151-154`). Whether this is an intentional trust-the-client decision or an oversight is not evidenced in the code.
- Whether `debug_token` is disabled/removed before any real production deployment (i.e. whether `smtp_host` is guaranteed to be set in prod) is a deployment/ops concern not evidenced in this repository.
