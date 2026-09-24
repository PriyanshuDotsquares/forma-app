Status: Approved (Retroactive Baseline — documents behavior as implemented, dated 2026-09-10)
Owner: Engineering team (retroactive)
Related: n/a

## Approach

Standard email/password auth with a stateless bearer JWT. Flutter's `AuthController` (a Riverpod `AsyncNotifier<User?>`) is the single source of truth for signed-in state; `null` means signed out, and any state is one of `AsyncLoading` / `AsyncData` / `AsyncError`. The router (`go_router`) reads this state on every navigation via a `redirect` callback and a `ChangeNotifier` bridge, so auth state and navigation state never drift apart. The backend is a conventional FastAPI + SQLAlchemy async setup: bcrypt-hashed passwords, HS256 JWTs with a `sub` claim of the user's UUID, and a `get_current_user` dependency that decodes the bearer token on every protected request. Password reset avoids a second credential type by reusing the `User` row itself (a nullable hashed-token + expiry pair) rather than a separate token table.

## Architecture / Data Flow

**Login flow (numbered call chain):**
1. UI: `AuthScreen._submit()` (`app/lib/features/auth/presentation/auth_screen.dart:45-63`) validates the form, then calls `ref.read(authControllerProvider.notifier).login(email:, password:)`.
2. Controller: `AuthController.login` (`app/lib/features/auth/presentation/auth_controller.dart:35-39`) sets state to `AsyncLoading()`, then wraps `AuthRepository.login` in `AsyncValue.guard`.
3. Repository: `AuthRepository.login` (`app/lib/features/auth/data/auth_repository.dart:26-38`) POSTs `FormData({'username': email, 'password': password})` to `/auth/login` via `ApiClient.dio`.
4. Network: `ApiClient`'s request interceptor (`app/lib/core/network/api_client.dart:23-31`) attaches no token here (none stored yet); the request goes out over `Env.apiBaseUrl`.
5. Backend routing: `POST /auth/login` is handled by `login()` in `backend/app/api/v1/endpoints/auth.py:52-66`, parsed as `OAuth2PasswordRequestForm`.
6. Backend logic: looks up the `User` by email (`select(User).where(User.email == form_data.username)`), calls `verify_password` (`backend/app/core/security.py:16-17`, bcrypt compare via `passlib`). On mismatch, raises HTTP 401.
7. On success: `create_access_token(subject=str(user.id))` (`security.py:20-25`) signs a JWT (`HS256`, `sub`=user id, `exp` = now + `access_token_expire_minutes`) and the endpoint returns `Token(access_token=...)`.
8. Response path back: `AuthRepository.login` reads `response.data['access_token']`, calls `_client.saveToken(token)` which writes it to `flutter_secure_storage` (`api_client.dart:50`), then calls `fetchMe()`.
9. `AuthRepository.fetchMe` (`auth_repository.dart:40-47`) GETs `/users/me`; the request interceptor now attaches `Authorization: Bearer <token>` (`api_client.dart:26-30`). Backend `read_current_user` (`backend/app/api/v1/endpoints/users.py:14-16`) is gated by `get_current_user` (`backend/app/api/deps.py:18-38`), which decodes the JWT and loads the `User` row by UUID.
10. The `User` row serializes through `UserRead` (`backend/app/schemas/user.py:47-73`) back to JSON; the Flutter side parses it via `User.fromJson` (`app/lib/features/auth/domain/user.dart:172-205`).
11. Controller: `AsyncValue.guard` resolves to `AsyncData(user)`, updating `authControllerProvider` state.
12. Router: `_AuthRefreshNotifier` (`app/lib/core/router/app_router.dart:93-97`) is listening to `authControllerProvider` and calls `notifyListeners()`, which re-runs the `redirect` callback (`app_router.dart:113-142`); with `loggedIn = true` and `onboarded` reflecting `user.onboardingCompleted`, the user lands on `/today` (if onboarded) or `/onboarding`.

**Password-reset flow (numbered call chain):**
1. UI (request step): `ForgotPasswordScreen._submit()` (`app/lib/features/auth/presentation/forgot_password_screen.dart:37-58`) calls `AuthRepository.requestPasswordReset(email)`.
2. Repository: POSTs `{'email': email}` to `/auth/password-reset/request` (`auth_repository.dart:81-89`).
3. Backend: `request_password_reset()` (`backend/app/api/v1/endpoints/auth.py:69-93`) looks up the user; if none, returns the generic message immediately (no token generated, no enumeration signal).
4. If found: generates `token = secrets.token_urlsafe(32)`, stores `_hash_token(token)` (SHA-256 hex digest, `auth.py:31-32`) in `user.password_reset_token_hash`, sets `password_reset_expires_at = now + 30min`, commits.
5. Calls `send_email(user.email, subject, body_with_raw_token)` (`backend/app/services/email_service.py:34-38`); since `settings.smtp_host` is unset by default, this only logs the message (`email_service.py:35-37`) — no real email is sent in this environment.
6. Response: because `settings.smtp_host` is falsy, `debug_token = token` is included in the JSON response (`auth.py:90-93`) alongside the same generic `message`.
7. Response path back: `AuthRepository.requestPasswordReset` returns `(message, debugToken)` (`auth_repository.dart:81-89`); `ForgotPasswordScreen` renders the generic success banner and, only when `debugToken != null`, an amber "DEV MODE — NO EMAIL SERVICE CONFIGURED" panel showing the raw token with a button that pushes `/auth/reset-password?token=<token>` (`forgot_password_screen.dart:101-134`).
8. UI (confirm step): `ResetPasswordScreen` (`app/lib/features/auth/presentation/reset_password_screen.dart`) pre-fills the token field from the `token` query param (read by the router at `app_router.dart:149-152`) and, on submit, calls `AuthRepository.confirmPasswordReset(token:, newPassword:)` (`reset_password_screen.dart:34-57`).
9. Repository: POSTs `{'token', 'new_password'}` to `/auth/password-reset/confirm` (`auth_repository.dart:91-97`).
10. Backend: `confirm_password_reset()` (`auth.py:96-115`) validates `new_password` length >= 8, hashes the submitted token, looks up a user by `password_reset_token_hash`, checks `password_reset_expires_at` is set and in the future; on failure raises HTTP 400. On success, sets `hashed_password = hash_password(new_password)` (bcrypt) and clears both reset fields, then commits.
11. Response path back: on success the Flutter screen navigates to `/auth` (`context.go(AppRoutes.auth)`) and shows a snackbar telling the user to sign in with the new password (`reset_password_screen.dart:45-49`); on failure it shows an inline error banner ("That reset code is invalid or has expired" fallback text, `reset_password_screen.dart:54`).

## Data / Schema

- `users` table (`backend/app/models/user.py:20-90`): `id` (UUID PK), `email` (unique, indexed), `hashed_password`, plus profile/onboarding/gamification columns unrelated to auth. Auth-specific columns: `password_reset_token_hash: str | None` (String(64)) and `password_reset_expires_at: datetime | None`, added by migration `backend/alembic/versions/ad6d3bbe2fa0_add_password_reset_notifications_.py`.
- No separate sessions/tokens table — the JWT itself is the session artifact (stateless; nothing server-side to revoke short of rotating `secret_key`).
- Pydantic schemas (`backend/app/schemas/user.py`): `UserCreate`, `UserLogin` (declared but login actually uses `OAuth2PasswordRequestForm`, not `UserLogin` — see Backlog), `UserRead`, `Token`, `PasswordResetRequest`, `PasswordResetRequestResponse` (with optional `debug_token`), `PasswordResetConfirm`, `ChangePasswordRequest`, `ChangeEmailRequest`.
- Flutter domain model: `User` (`app/lib/features/auth/domain/user.dart:117-206`), constructed from the same JSON shape as `UserRead`.

## Alternatives Considered

N/A — retroactive baseline

## Testing Strategy

- `app/test/widget_test.dart` is the only test file in the Flutter app (confirmed via `find` — no other test files exist under `app/test`). It is not the default Flutter counter-app template: it overrides `authControllerProvider` with a signed-out `AuthController` and pumps `FormaApp`, asserting `find.text('Welcome back')` renders. However, the string `"Welcome back"` does not appear anywhere in `app/lib` (verified by repo-wide grep, including both `app/lib/l10n/app_en.arb` and `app/lib/l10n/app_hi.arb`) — nor does a signed-out cold start even land on `AuthScreen`: the router's redirect sends a signed-out user from `/splash` to `/intro` (`app_router.dart:138`), not `/auth`. This test's assertion cannot currently pass against the app's real UI/routing — see Backlog.
- No backend test directory exists anywhere under `backend/` (verified by repo-wide `find ... -iname "*test*"` — zero matches). There are no automated tests for `auth.py`, `users.py`, `security.py`, or `email_service.py`.
- Net: no automated tests meaningfully cover registration, login, session persistence, logout, password reset, change-password, or change-email — gap.

## Risks / Edge Cases

- **Stale Keychain token on reinstall (mitigated)**: iOS Keychain entries survive full app deletion, unlike `SharedPreferences`. `ApiClient.clearStaleTokenOnFreshInstall()` (`app/lib/core/network/api_client.dart:66-71`) uses the absence of a `SharedPreferences` boolean marker as a fresh-install signal and proactively clears any leftover secure-storage token before it's read. This is called once, first, at the top of `AuthController.build()` (`auth_controller.dart:20-24`), before the stored-token check — confirmed as the sole call site via repo-wide grep.
- **No server-side password length/complexity check on registration**: `UserCreate` (`backend/app/schemas/user.py:8-11`) has no `min_length` constraint and `register()` (`auth.py:35-49`) performs no length check, unlike `confirm_password_reset` and `change_password` which both explicitly check `len(payload.new_password) < 8`. Only the Flutter client enforces a minimum (`auth_screen.dart:151-154`), so any non-app client (or a modified app) could register with a 1-character password.
- **`secret_key` default**: `Settings.secret_key` defaults to the literal `"change-me-in-.env"` (`backend/app/core/config.py:26`) if no environment override is provided — an unconfigured deployment would sign/verify JWTs with a widely-known key.
- **No token revocation / refresh**: access tokens are valid for 24 hours (`access_token_expire_minutes = 60 * 24`) with no server-side revocation list and no refresh-token rotation; logout is purely client-side (deletes the local token) and does not invalidate the JWT on the backend, so a captured token remains valid until it expires on its own.
- **Password-reset token entropy/expiry**: `secrets.token_urlsafe(32)` (256 bits) hashed with SHA-256 and a 30-minute expiry is a reasonable single-use-secret design; using SHA-256 instead of bcrypt for this specific value is appropriate given the token is already high-entropy and single-use (unlike a user-chosen password).
- **Dev-mode token echo (`debug_token`)**: whenever `smtp_host` is unset, the raw reset token is returned directly in the API response body and rendered in the UI. This is by design for an environment without SMTP, but it means password reset provides no real protection in that configuration — anyone able to observe the API response (not just the target's inbox) can complete a reset. This is only inert once `smtp_host` is configured.
- **Generic reset-request response**: correctly implemented — same message and HTTP 200 regardless of whether the email exists (`auth.py:74-77`), preventing account-existence enumeration via this endpoint.

## Backlog / Known Gaps

- No automated test coverage for any auth flow: `app/test/widget_test.dart`'s single test asserts on text (`'Welcome back'`) that does not exist anywhere in the current app and targets a screen (`AuthScreen`) that a signed-out cold start does not actually route to (it lands on `IntroScreen` per `app_router.dart:138`). The test as currently written cannot pass. No backend test suite exists at all (no `tests/` directory under `backend/`).
- `UserLogin` schema is defined (`backend/app/schemas/user.py:14-16`) but unused by the actual `/auth/login` endpoint, which takes `OAuth2PasswordRequestForm` instead (`auth.py:52-56`) — dead schema.
- No server-side minimum-length/complexity validation on the registration password (`auth.py:35-49`, `schemas/user.py:8-11`) — inconsistent with `password-reset/confirm` and `change-password`, which both enforce >=8 characters server-side.
- No TODO/FIXME/HACK/XXX comments found in any of the reviewed auth files (`auth_repository.dart`, `auth_controller.dart`, `auth_screen.dart`, `forgot_password_screen.dart`, `reset_password_screen.dart`, `auth.py`, `users.py`, `security.py`, `email_service.py`) — verified by grep.
- No Apple/Google Sign-In implementation or stub exists (verified: no `sign_in_with_apple` / `google_sign_in` in `app/pubspec.yaml`, no matching references anywhere in `app/lib`) — not a gap relative to this codebase's actual scope, just confirming absence rather than assuming it.
