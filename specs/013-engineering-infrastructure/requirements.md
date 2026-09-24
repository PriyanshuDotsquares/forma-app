Status: Approved (Retroactive Baseline — documents behavior as implemented, dated 2026-09-10)
Owner: Engineering team (retroactive)
Related: n/a

## Summary

This module documents the cross-cutting engineering infrastructure that every FORMA feature module (001–012) is built on top of, rather than any user-facing behavior. It covers: the Flutter client's dependency-injection/state-management wiring (Riverpod), the shared networking layer (`ApiClient`), the routing/navigation shell (`go_router`), local persistence primitives (`flutter_secure_storage`, `shared_preferences`), the shared design system ("Cast Iron & Chalk Dust"), build/environment configuration, the FastAPI backend's core config and security module, the SQLAlchemy/Alembic database layer, and deployment (Docker + Render). Localization/i18n is its own module (013→011: `specs/011-localization-i18n/`) and is only cross-referenced here as a `core/` subsystem, not duplicated.

## Background / Problem

FORMA is a Flutter client (iOS/Android/Web) backed by a FastAPI/Postgres API. Without a shared foundation, every one of the ~12 feature modules (auth, onboarding, programs, dashboard, workout tracking, camera coach, progress analytics, achievements, challenges, settings, i18n, uploads) would independently reimplement HTTP calls, token storage, navigation guards, and visual styling — leading to inconsistent auth handling, duplicated theme code, and divergent error handling. This module exists to give every feature module one shared `ApiClient`, one `GoRouter` instance with one redirect/guard policy, one design-system token set, and one backend settings/security/DB-session layer to depend on.

## User Stories

- As a developer adding a new feature module, I need a single shared `ApiClient` (`app/lib/core/network/api_client.dart`) so I don't reimplement auth-token attach/refresh/clear or base-URL resolution per feature.
- As a developer wiring a new screen, I need one `routerProvider` (`app/lib/core/router/app_router.dart`) with a centralized `redirect` callback so auth/onboarding gating logic lives in exactly one place instead of being re-derived per screen.
- As a developer building a new screen's UI, I need a shared design-system token set (`AppColors`, `AppSpacing`, `AppTypography`, `AppTheme`) and a small library of shared widgets (`StatTile`, `FormaEmptyState`, `BadgePill`, `InfoBanner`, `LoadStrip`, `SectionLabel`, `PlaceholderScreen`, `FormaWordmark`) so new UI is visually consistent without re-deriving colors/spacing/type by hand.
- As a developer running the app locally against a physical device or emulator, I need `Env.apiBaseUrl` to resolve the right backend host per platform (Android emulator vs. iOS simulator/web/macOS) without editing source, so `flutter run` works out of the box and can still be overridden via `--dart-define=API_BASE_URL=...`.
- As a developer adding a new backend endpoint, I need a single `Settings` object (`backend/app/core/config.py`) loaded once via `get_settings()` so config (DB URL, JWT secret, CORS origins, SMTP, Groq key) is read from `.env`/environment variables in exactly one place.
- As a developer adding a new authenticated backend endpoint, I need the existing `hash_password`/`verify_password`/`create_access_token` helpers in `backend/app/core/security.py` so password hashing and JWT issuance follow one consistent scheme app-wide.
- As a developer adding a new database model, I need the existing `Base` declarative class (`backend/app/db/base.py`) and Alembic environment (`backend/alembic/env.py`) so new tables are picked up by autogeneration and migrated consistently.
- As a developer deploying the backend, I need the existing `Dockerfile`/`docker-compose.yml`/`render.yaml` so local dev and the Render production deploy both run `alembic upgrade head` before serving, without hand-crafted deploy steps per environment.
- As a developer building for iOS, I need the existing `Podfile` deployment target and `post_install` hook so pod-level build settings (deployment target, camera-permission macro) are applied consistently to every native dependency instead of per-plugin.

## Acceptance Criteria (EARS format: "WHEN/IF ... THE SYSTEM SHALL ...")

**Networking**
- WHEN any outgoing `Dio` request is dispatched through `ApiClient`, THE SYSTEM SHALL read the stored auth token from `FlutterSecureStorage` and attach it as an `Authorization: Bearer <token>` header if present (`app/lib/core/network/api_client.dart:23-31`).
- WHEN a response comes back with HTTP 401, THE SYSTEM SHALL clear the stored token and invoke the registered `onUnauthorized` callback (`app/lib/core/network/api_client.dart:32-37`).
- WHEN `Env.apiBaseUrl` is resolved and `API_BASE_URL` was supplied via `--dart-define`, THE SYSTEM SHALL use that override; OTHERWISE IF running on Android (non-web), THE SYSTEM SHALL default to `http://10.0.2.2:8000/api/v1`; OTHERWISE THE SYSTEM SHALL default to `http://localhost:8000/api/v1` (`app/lib/core/config/env.dart:23-27`).
- WHEN a `DioException` is caught, THE SYSTEM SHALL normalize it into an `ApiException` using the response body's `detail` string if present, or a connection-specific message for timeout/connection errors, or a generic fallback message otherwise (`app/lib/core/network/api_exception.dart:13-27`).
- WHEN the app launches for the first time after install (no `forma_install_marker` in `SharedPreferences`), THE SYSTEM SHALL clear any pre-existing Keychain-persisted auth token before it is ever read, to prevent a stale token from a previous install surviving app deletion (`app/lib/core/network/api_client.dart:66-71`).

**Routing**
- WHEN `authControllerProvider`'s auth state is loading, THE SYSTEM SHALL remain on `/splash`, `/auth`, or the auth-adjacent routes rather than redirecting elsewhere (`app/lib/core/router/app_router.dart:137`).
- IF the user is not logged in, THE SYSTEM SHALL redirect to `/intro` unless already on `/intro`, `/auth`, or an auth-adjacent route (`app/lib/core/router/app_router.dart:138`).
- IF the user is logged in but has not completed onboarding, THE SYSTEM SHALL redirect to `/onboarding` unless already there (`app/lib/core/router/app_router.dart:139`).
- IF the user is logged in, onboarded, and sitting on `/splash`, `/intro`, or `/auth`, THE SYSTEM SHALL redirect to `/today` (`app/lib/core/router/app_router.dart:140`).
- IF the user is logged in, onboarded, still on `/onboarding`, and the post-onboarding flow flag (`onboardingPostFlowActiveProvider`) is not active, THE SYSTEM SHALL redirect to `/today` (`app/lib/core/router/app_router.dart:141`).
- WHEN the bottom-nav tabs are shown, THE SYSTEM SHALL present exactly five `StatefulShellRoute.indexedStack` branches (Today, Plan, Progress, Coach, Profile), each retaining its own navigation stack across tab switches (`app/lib/core/router/app_router.dart:179-244`, `app/lib/core/router/app_shell.dart`).

**Design system**
- WHEN any screen renders, THE SYSTEM SHALL use the single dark `AppTheme.dark` ThemeData (no light theme is defined) (`app/lib/core/design_system/app_theme.dart:13`).

**Backend config/security**
- WHEN the backend process starts, THE SYSTEM SHALL load configuration once via `get_settings()` (`@lru_cache`) from environment variables / `.env`, including `database_url`, `secret_key`, `algorithm`, `access_token_expire_minutes`, and `cors_origins` (`backend/app/core/config.py:49-51`).
- WHEN `database_url` is provided in `postgres://` or `postgresql://` form (as managed Postgres hosts emit), THE SYSTEM SHALL rewrite it to the `postgresql+asyncpg://` scheme before use (`backend/app/core/config.py:15-24`).
- WHEN a password is stored, THE SYSTEM SHALL hash it with `passlib`'s `bcrypt` scheme via `pwd_context.hash` (`backend/app/core/security.py:9,12-13`).
- WHEN an access token is issued, THE SYSTEM SHALL encode a JWT with `sub` (subject) and `exp` claims using `python-jose`, the configured `secret_key`, and `algorithm` (default `HS256`), expiring after `access_token_expire_minutes` (default 1440 = 24h) (`backend/app/core/security.py:20-25`).
- WHEN the FastAPI app is constructed, THE SYSTEM SHALL attach `CORSMiddleware` configured from `settings.cors_origins` with `allow_credentials=True`, `allow_methods=["*"]`, and `allow_headers=["*"]` (`backend/app/main.py:14-20`).

**Migrations / deployment**
- WHEN the backend container starts (locally via `docker-compose` or on Render), THE SYSTEM SHALL run `alembic upgrade head` before starting `uvicorn` (`backend/Dockerfile:18`).
- WHEN `render.yaml` is applied, THE SYSTEM SHALL deploy the backend as a Docker-runtime web service rooted at `backend/`, with `DATABASE_URL` and `SECRET_KEY` marked `sync: false` (set manually in the Render dashboard) and `CORS_ORIGINS` defaulted to `'["*"]'` (`render.yaml:16-24`).

**iOS build**
- WHEN CocoaPods installs iOS dependencies, THE SYSTEM SHALL set `IPHONEOS_DEPLOYMENT_TARGET` to `15.5` for every pod target and set the `PERMISSION_CAMERA=1` preprocessor macro so `permission_handler`'s camera API is compiled in (it is stubbed out otherwise) (`app/ios/Podfile:46-62`).

## Out of Scope

- Feature-specific redirect logic owned by individual modules (e.g., password-reset deep-link handling) — covered by module 001.
- Localization/i18n implementation — covered by module 011 (`specs/011-localization-i18n/`).
- Full field-level schema documentation for `Program`/`Exercise`/`WorkoutSession`/etc. — owned by the feature modules that introduced them (003, 005, 007, 008, 009).
- OAuth and in-app-purchase credential wiring — noted elsewhere in project memory as needing real credentials; not implemented in this infrastructure layer beyond the `in_app_purchase` dependency being present in `pubspec.yaml`.
- CI/CD pipeline definitions — none exist in the repo (see design.md Backlog/Known Gaps).

## Non-Functional Requirements

- **Consistency**: All HTTP calls from the Flutter client must go through the shared `ApiClient` / `apiClientProvider` so auth-token attach/clear behavior is uniform (verified: `apiClientProvider` is consumed by feature repositories such as `AuthRepository` via `ref.watch(apiClientProvider)`).
- **Single source of truth for navigation state**: The router is constructed exactly once per app lifetime; auth-state changes flow through `_AuthRefreshNotifier`/`refreshListenable` rather than rebuilding `GoRouter`, to avoid resetting navigation stacks (documented rationale in `app/lib/core/router/app_router.dart:85-97`).
- **Config via environment, not hardcoding**: Backend settings are sourced from `.env`/env vars via `pydantic_settings.BaseSettings`; secrets (`SECRET_KEY`, `DATABASE_URL`) are marked `sync: false` in `render.yaml` rather than committed.
- **Deterministic migrations**: Database schema changes are only ever applied via Alembic revisions; AI-generated seed content (`ai_seed.py`) is explicitly excluded from the migration/startup path to keep `alembic upgrade head` deterministic and offline-replayable (rationale documented in `backend/app/db/ai_seed.py:9-21`).
- **Platform-aware defaults**: Local development must work without manual config on Android emulator, iOS simulator, web, and macOS via `Env.apiBaseUrl`'s platform branching.

## Open Questions

- None — this is a retroactive baseline documenting only what is demonstrably implemented in the current codebase as of 2026-09-10.
