Status: Approved (Retroactive Baseline — documents behavior as implemented, dated 2026-09-10)
Owner: Engineering team (retroactive)
Related: n/a

## Approach

FORMA's infrastructure follows a conventional feature-first Flutter + FastAPI split: a thin `core/` layer in the Flutter app supplies networking, routing, persistence primitives, and a design-system token set that every `features/*` module consumes via Riverpod providers; the backend mirrors this with a single `Settings`/`get_settings()` config object, a `security.py` module for password/JWT handling, and a SQLAlchemy `Base`/async-session pair that every `app/models/*.py` and `app/api/v1/*` module builds on. Deployment is container-based end to end (Docker Compose for local dev, the same `Dockerfile` deployed to Render via `render.yaml`), with Alembic migrations as the only sanctioned path to schema change.

## Architecture / Data Flow

### 1. DI / state-management wiring (Riverpod)

FORMA uses `flutter_riverpod` (`^2.6.1`, `app/pubspec.yaml:39`) exclusively for DI and state. The composition pattern is a strict layered chain of `Provider`/`AsyncNotifierProvider` declarations, each `ref.watch`-ing the layer below it:

1. `apiClientProvider` (`app/lib/core/network/providers.dart:5`) — `Provider<ApiClient>((ref) => ApiClient())` — the single root dependency, constructed once per `ProviderScope`.
2. Feature repository providers watch it directly, e.g. `authRepositoryProvider` in `app/lib/features/auth/presentation/auth_controller.dart:7-9`: `Provider<AuthRepository>((ref) => AuthRepository(ref.watch(apiClientProvider)))`.
3. Feature controllers (`AsyncNotifier` subclasses, e.g. `AuthController` at `auth_controller.dart:14`) watch the repository provider and expose UI-facing async state.
4. `routerProvider` (`app/lib/core/router/app_router.dart:109`) watches `authControllerProvider` indirectly through `_AuthRefreshNotifier` (see §3) to drive redirects without rebuilding the router.

The app root wires exactly one `ProviderScope` at `runApp` (`app/lib/main.dart:11`), and `FormaApp` (a `ConsumerWidget`) watches `routerProvider` and `localeControllerProvider` (`app/lib/main.dart:18-20`) to build `MaterialApp.router`. There is no service-locator or manual singleton pattern anywhere in `core/` — every cross-cutting dependency is a Riverpod provider, confirmed by 8 call sites of `apiClientProvider` across `features/`.

### 2. Networking layer (`ApiClient`)

`ApiClient` (`app/lib/core/network/api_client.dart`) wraps a single `Dio` instance:
- **Base URL resolution**: `Env.apiBaseUrl` (`app/lib/core/config/env.dart:23-27`) checks `String.fromEnvironment('API_BASE_URL')` first (settable via `flutter run --dart-define=API_BASE_URL=...`); if unset, it branches on `!kIsWeb && Platform.isAndroid` → `http://10.0.2.2:8000/api/v1` (the documented Android-emulator host alias), else `http://localhost:8000/api/v1` (iOS simulator, macOS, web).
- **Timeouts**: `connectTimeout`/`receiveTimeout` both 15s (`api_client.dart:19-20`).
- **Auth-token attach**: an `InterceptorsWrapper.onRequest` reads the token from `FlutterSecureStorage` (key `auth_token`) and sets `Authorization: Bearer $token` if present (`api_client.dart:25-30`).
- **401 handling**: `onError` checks `error.response?.statusCode == 401`, calls `clearToken()`, then invokes the injectable `onUnauthorized` callback (`api_client.dart:32-37`). This callback is wired exactly once, by `AuthController.build()` (`auth_controller.dart:19`): `client.onUnauthorized = () => state = const AsyncData(null)` — i.e., a 401 anywhere in the app signs the user out reactively.
- **Error mapping**: `ApiException.fromDioException` (`app/lib/core/network/api_exception.dart:13-27`) prefers the backend's `detail` string from the JSON error body, falls back to a connection-specific message for timeout/connection-error `DioExceptionType`s, and otherwise a generic "Something went wrong" message. `ApiException` also exposes `isUnauthorized` (401) and `isPaymentRequired` (402) convenience getters for UI branching.
- **Fresh-install token safety**: `clearStaleTokenOnFreshInstall()` (`api_client.dart:66-71`) uses `SharedPreferences`'s `forma_install_marker` boolean as a "this install is fresh" signal (SharedPreferences is wiped on uninstall; iOS Keychain, which `flutter_secure_storage` uses, is not) — proactively clearing any orphaned Keychain token before a fresh install can silently auto-login. Called from `AuthController.build()` before the stored-token check.

### 3. Routing (`go_router` `StatefulShellRoute`)

`routerProvider` (`app/lib/core/router/app_router.dart:109-247`) builds a single `GoRouter` with:
- **`refreshListenable`**: `_AuthRefreshNotifier` (`app_router.dart:93-97`), a `ChangeNotifier` that internally does `ref.listen(authControllerProvider, ...)`. This indirection exists specifically so `routerProvider`'s own body never `ref.watch`es auth state directly — doing so would rebuild the `GoRouter` instance on every auth change, resetting navigation to `initialLocation` (documented regression avoided: plan-generation success previously bounced to `/today` instead of showing plan-preview/save-plan).
- **`redirect` guard** (`app_router.dart:113-143`), evaluated as an ordered if-chain against `authControllerProvider`'s `AsyncValue` and `onboardingPostFlowActiveProvider`:
  1. Auth state loading → stay on splash/auth/auth-adjacent, else force `/splash` (prevents a mid-submit loading state from bouncing the auth screen away, which would otherwise swallow login-error banners).
  2. Not logged in → force `/intro` unless on intro/auth/auth-adjacent.
  3. Logged in, not onboarded → force `/onboarding` unless already there.
  4. Logged in, onboarded, on splash/intro/auth → force `/today`.
  5. Logged in, onboarded, on `/onboarding` with `onboardingPostFlowActiveProvider == false` → force `/today` (this flag is flipped true for the window between quiz submission and the plan-preview/save-plan hand-off, so the redirect doesn't short-circuit that sequence).
- **Route tree**: standalone routes for `/splash`, `/intro`, `/auth`, `/auth/forgot-password`, `/auth/reset-password`, `/onboarding`, `/onboarding/plan-preview`, `/onboarding/save-plan`, and full-screen workout flows (`/workout/camera-precheck/:sessionId`, `/workout/active/:sessionId`, `/workout/summary/:sessionId`, `/workout/form-report/:sessionId`) that render outside the bottom-nav shell.
- **`StatefulShellRoute.indexedStack`** (`app_router.dart:179-244`) with `AppShell` (`app_shell.dart`) as its builder, wrapping exactly 5 `StatefulShellBranch`es — Today, Plan (with nested `day/:dayId`, `exercises`, `exercises/:exerciseId`, `session/:dayId`, `history` routes), Progress (nested `volume`, `recovery`, `form-quality`, `consistency`), Coach, Profile (nested `achievements`, `challenges`, `settings` → `voice-coach`/`language`, `premium`). `AppShell` renders a `BottomNavigationBar` keyed to `navigationShell.currentIndex`; each branch's own stack persists across tab switches (the `indexedStack` behavior). `AppRoutes` (`app_router.dart:42-83`) centralizes every path as a typed constant/helper so screens never hand-type route strings.

### 4. Local persistence

- **`flutter_secure_storage` (`^11.0.0`)** — used exclusively for the single auth JWT (key `auth_token`) via `ApiClient.saveToken`/`readToken`/`clearToken` (`api_client.dart:50-54`). Backed by iOS Keychain / Android Keystore.
- **`shared_preferences` (`^2.5.5`)** — used in `core/` for exactly one thing: the `forma_install_marker` boolean flag that detects a fresh install (`api_client.dart:8,67-70`). Feature modules may use it independently for their own local flags (not audited here — owned by those modules).

### 5. Design system ("Cast Iron & Chalk Dust")

A token-based dark-only design system under `app/lib/core/design_system/`, exported as one barrel file `design_system.dart`:
- **`AppColors`** (`app_colors.dart`) — layered near-black surfaces (`surfaceLowest`/`surfaceBase`/`surfaceHigh`/`surfaceHighest`), two border tones, three text tones, and IWF competition-plate-inspired accents (`accentBlue` = primary/links, `accentRed` = PR/destructive, `accentGreen` = positive/success, `accentWhite` = neutral, `accentAmber` = warning). Explicitly documented as sampled from Figma screenshots, "there is no token export" (`app_colors.dart:4-5`).
- **`AppSpacing`/`AppRadius`** (`app_spacing.dart`) — an xs–xxl (4–48) spacing scale and named radii (`card`=16, `field`=12, `button`/`chip`=100 fully-rounded, `sheet`=20).
- **`AppTypography`** (`app_typography.dart`) — three Google Fonts families via the `google_fonts` package: Archivo Narrow for display/headers, IBM Plex Sans for body, IBM Plex Mono for numeric/data (weights, percentages, timers), plus Playfair Display reserved for the "FORMA" wordmark only. Exposes a full `TextTheme` mapping.
- **`AppTheme.dark`** (`app_theme.dart`) — the single `ThemeData` the app ships (no light theme; `MaterialApp.router` sets both `theme` and `darkTheme` to it in `main.dart:24-25`). Configures `ColorScheme.dark`, zero-elevation cards/app-bars ("anti-pattern: no drop shadows" per inline comment), pill-shaped buttons, and per-component themes (inputs, chips, switches, sliders, snackbars, bottom sheets, dialogs) all derived from the token files above.
- **Shared widgets** (`design_system/widgets/`) — small, composable, stateless presentational widgets used across feature screens: `StatTile` (labeled numeric stat card, e.g. "WORKOUTS 148"), `FormaEmptyState` (unified empty/error-state card covering "No plan yet," offline, camera-denied, and generic-error cases), `BadgePill` (small uppercase status chip), `InfoBanner` (left-accent-bordered callout for coaching tips/form flags), `LoadStrip` (segmented set-completion progress bar colored like competition plates), `SectionLabel` (uppercase muted section heading), `PlaceholderScreen` (scaffold stand-in for unbuilt screens, used during incremental navigation build-out), `FormaWordmark` (the "FORMA" logo text).

### 6. Backend core (config, security, DB session)

- **Config** (`backend/app/core/config.py`): a single Pydantic `Settings(BaseSettings)` class loaded from `.env` (`SettingsConfigDict(env_file=".env", extra="ignore")`), memoized via `@lru_cache` `get_settings()` so it's read once per process. Fields: `project_name`, `api_v1_prefix` (`/api/v1`), `database_url` (with a `field_validator` that rewrites bare `postgres://`/`postgresql://` URLs from managed hosts to `postgresql+asyncpg://`), `secret_key`, `algorithm` (`HS256`), `access_token_expire_minutes` (default 1440 = 24h), `cors_origins` (default `["*"]`), optional SMTP settings (unset in dev — `email_service.send_email` logs instead of sending), and `groq_api_key` (used only by the manually-invoked `ai_seed.py`, not at request time).
- **Security** (`backend/app/core/security.py`): `passlib.CryptContext(schemes=["bcrypt"], deprecated="auto")` for `hash_password`/`verify_password`; `create_access_token(subject, expires_delta=None)` builds a JWT payload `{"sub": subject, "exp": expire}` and signs it with `python-jose`'s `jwt.encode` using `settings.secret_key`/`settings.algorithm`. No refresh-token mechanism exists — tokens are long-lived (24h default) bearer JWTs with no server-side revocation list; a 401 on the client is handled purely by clearing the local token (see §2).
- **CORS** (`backend/app/main.py:14-20`): `CORSMiddleware` is configured with `allow_origins=settings.cors_origins` (defaults to `["*"]`, and is explicitly pinned to `'["*"]'` in `render.yaml:23-24` for the deployed environment too), **and** `allow_credentials=True`, `allow_methods=["*"]`, `allow_headers=["*"]`. This is a real, currently-live configuration, not a hypothetical — see Backlog/Known Gaps.
- **DB session** (`backend/app/db/session.py`): one async SQLAlchemy engine (`create_async_engine(settings.database_url, echo=False, future=True)`) and one `async_sessionmaker` (`expire_on_commit=False`); `get_db()` is an `AsyncGenerator` dependency yielding a session per request, used via FastAPI `Depends`.
- **DB base** (`backend/app/db/base.py`): a bare `class Base(DeclarativeBase): pass` — every model in `app/models/*.py` inherits from it; `Base.metadata` is what Alembic's `env.py` targets for autogeneration.
- **Seeding orchestration**: `backend/app/db/seed_data.py` defines static Python literals (`EXERCISES`, and by convention `ACHIEVEMENTS`/`CHALLENGES`) that are baked directly into the initial Alembic migration's `upgrade()` (i.e., seed data ships as part of schema migration, not a separate seed step) — ownership of the seeded content itself belongs to modules 003/008/009. `backend/app/db/ai_seed.py` is a separate, manually-invoked script (`python -m app.db.ai_seed`) that additively generates more rows via the Groq API, matched against existing rows by natural key (`slug` for exercises, `key` for achievements/challenges) so it never overwrites curated content. It is deliberately **not** wired into `alembic upgrade head` or app startup — a live LLM call inside a migration would make `alembic upgrade head` non-deterministic and would break fresh-environment bootstrapping (new dev machine, CI, disaster recovery) if the Groq API key were missing or the API were down (rationale documented in `ai_seed.py:9-21`).

### 7. Migrations (oldest → newest)

Four Alembic revisions exist in `backend/alembic/versions/`, forming a single linear chain:

1. `c2a32e92d88f` — "initial tables" (`down_revision=None`, the root revision).
2. `e5654ef0a8e7` — "add keepsake fields, users/uploads" (`down_revision='c2a32e92d88f'`).
3. `561d62621de3` — "fitness domain rewrite: drop keepsakes, add programs/exercises/workouts/achievements" (`down_revision='e5654ef0a8e7'`) — the pivot from an earlier "keepsakes" domain model to FORMA's current strength-training domain.
4. `ad6d3bbe2fa0` — "add password reset, notification prefs, locale, and challenges" (`down_revision='561d62621de3'`, the current head).

`backend/alembic/env.py` sets `sqlalchemy.url` from `get_settings().database_url` at runtime (so migrations always target whatever `DATABASE_URL` the environment provides), imports every model class explicitly to register them on `Base.metadata` for autogeneration, and supports both offline (`--sql`) and online (async engine, `NullPool`) migration modes.

### 8. Deployment

- **`backend/Dockerfile`**: `python:3.12-slim` base; installs `gcc`/`libpq-dev` (needed for `psycopg`/native builds), installs `requirements.txt`, copies the app, and runs (shell form, for `$PORT` env-var substitution) `alembic upgrade head && uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}` — migrations always run immediately before the server starts, in both dev and prod.
- **`backend/docker-compose.yml`** (local dev shape): a `postgres:16-alpine` `db` service (user/password/db all `forma`, with a `pg_isready` healthcheck) plus an `api` service built from the local `Dockerfile`, given a plaintext dev `DATABASE_URL`/`SECRET_KEY` (`change-me-in-.env`), depending on `db`'s healthcheck, with the whole repo bind-mounted (`.:/app`) for live-reload-style local iteration.
- **`render.yaml`** (prod shape): a single Render Blueprint `web` service (`forma-api`), `runtime: docker`, `rootDir: backend`, built from the same `Dockerfile`, `plan: starter`, `healthCheckPath: /health` (served by `main.py`'s `GET /health` → `{"status": "ok"}`). `DATABASE_URL` and `SECRET_KEY` are declared but `sync: false` (must be set manually in the Render dashboard, not committed); `ACCESS_TOKEN_EXPIRE_MINUTES` is pinned to `"1440"`; `CORS_ORIGINS` is pinned to `'["*"]'` directly in the committed blueprint.
- Static file serving: `main.py` mounts `static/uploads` (created on startup via `Path.mkdir(parents=True, exist_ok=True)`) at `/static` — relevant to module 012 (uploads/media), noted here only as core wiring.

## Data / Schema

High-level entity relationships across `backend/app/models/*.py` (field-level detail owned by the feature modules that introduced each table):

- **`User`** (`user.py`, table `users`) is the root entity. It holds auth fields (`email`, `hashed_password`) and an onboarding/training profile (`dob`, `gender`, `height_cm`, `weight_kg`, `goal`, `experience_level`, `days_per_week`, `session_minutes`, `split_preference`, `gym_location`, ...). One `User` has-many, all with `cascade="all, delete-orphan"`:
  - `programs` → `Program`
  - `workout_sessions` → `WorkoutSession`
  - `personal_records` → `PersonalRecord`
  - `achievements` → `UserAchievement`
  - `body_metrics` → `BodyMetric`
  - `challenge_entries` → `UserChallenge`
- **`Program` → `ProgramDay` → `ProgramExercise`** (`program.py`): a strict three-level owned hierarchy. `Program.owner_id` FKs to `users.id`; `ProgramDay.program_id` FKs to `programs.id`; `ProgramExercise.program_day_id` FKs to `program_days.id` and `ProgramExercise.exercise_id` FKs to `exercises.id` (a plain, non-cascading reference into the shared exercise library).
- **`Exercise`** (`exercise.py`, table `exercises`): a standalone, seed-populated library table (slug-keyed, JSONB columns for `primary_muscles`/`secondary_muscles`/`equipment`/`execution_steps`/`pro_cues`/`mistakes`). Referenced (never owned) by `ProgramExercise`, `WorkoutSet`, and `PersonalRecord`.
- **`WorkoutSession` → `WorkoutSet`** (`workout.py`): `WorkoutSession.user_id` FKs to `users.id`; `WorkoutSession.program_day_id` optionally FKs to `program_days.id` (nullable — a session need not originate from a plan day). `WorkoutSet.session_id` FKs to `workout_sessions.id` (cascade delete) and `WorkoutSet.exercise_id` FKs to `exercises.id`.
- **`PersonalRecord`** (`record.py`, table `personal_records`): `user_id` → `users.id`, `exercise_id` → `exercises.id`, and an optional `workout_set_id` → `workout_sets.id` linking the record back to the set that produced it.
- **`BodyMetric`** (`body_metric.py`): `user_id` → `users.id`; simple per-date body-measurement rows.
- **`Achievement` / `UserAchievement`** (`achievement.py`): `Achievement` is a shared, seed-populated catalog; `UserAchievement` is the join/progress table (`user_id` → `users.id`, `achievement_id` → `achievements.id`).
- **`Challenge` / `UserChallenge`** (`challenge.py`): same shape as achievements — `Challenge` is the shared catalog, `UserChallenge` (`user_id` → `users.id`, `challenge_id` → `challenges.id`) is the per-user participation/progress row.

All primary keys are `UUID` (`uuid.uuid4()` default), and all cross-table references use Postgres `UUID` foreign keys. `User`-owned collections cascade-delete; catalog tables (`Exercise`, `Achievement`, `Challenge`) are referenced, not owned, by user data.

## Alternatives Considered

N/A — retroactive baseline.

## Testing Strategy

Automated test coverage is minimal and does not extend beyond scaffolding:
- `app/test/widget_test.dart` — one real Flutter widget test: pumps `FormaApp` with `authControllerProvider` overridden to a signed-out state and asserts the login screen ("Welcome back") renders. This is the only automated test found anywhere in the Flutter app.
- `app/ios/RunnerTests/RunnerTests.swift` — the default Flutter/Xcode-generated `XCTestCase` stub (`testExample()` is empty, contains only a comment placeholder). Not a real test.
- **Backend**: no test files, no `pytest` configuration, and no test directory exist anywhere under `backend/` (`requirements.txt` does not list `pytest` or any test dependency).
- **No CI configuration**: no `.github/workflows/`, no other CI pipeline definition found in the repo.

This is a genuine, repo-wide gap: outside of the single Flutter widget test above, FORMA has no automated test coverage for either the Flutter client or the FastAPI backend, and no CI to run any tests automatically. This module is the natural place to record it since it applies uniformly across every feature module, not to any one of them.

## Risks / Edge Cases

- **Permissive CORS + credentials** (`backend/app/main.py:14-20`, `render.yaml:23-24`, `backend/app/core/config.py:30`): `cors_origins` defaults to `["*"]` in both the `Settings` default and the committed `render.yaml` blueprint, combined with `allow_credentials=True`. Starlette's `CORSMiddleware` handles a wildcard-plus-credentials combination by reflecting the request's actual `Origin` header back (rather than sending a literal `*`) so browsers accept it — the practical effect is that any origin can make credentialed requests against the deployed API. This is a real, currently-deployed configuration, not a hypothetical.
- **No refresh-token / revocation mechanism**: `create_access_token` (`backend/app/core/security.py:20-25`) issues a single long-lived (24h default) bearer JWT with no refresh flow and no server-side blocklist — a leaked token remains valid until it naturally expires; the client's only defense is clearing its local copy on a 401.
- **Dev-mode secrets committed in `docker-compose.yml`**: `SECRET_KEY: change-me-in-.env` and Postgres credentials `forma`/`forma` are plaintext in `backend/docker-compose.yml:6-7,22` — acceptable for local dev only, and the Dockerfile's default `Settings.secret_key` ("change-me-in-.env") would silently be used in any real deployment that forgets to set `SECRET_KEY` (Render's blueprint does correctly mark it `sync: false`, forcing a manual set, but nothing enforces this at the `Settings` level — an unset `SECRET_KEY` in a misconfigured non-Render environment falls back to the insecure literal default rather than failing fast).
- **iOS deployment-target coupling**: the Podfile's `post_install` hook (`app/ios/Podfile:46-62`) hardcodes `IPHONEOS_DEPLOYMENT_TARGET = '15.5'` for every pod target; the file itself documents that this must stay in sync with `IPHONEOS_DEPLOYMENT_TARGET` in `Runner.xcodeproj/project.pbxproj` or Xcode will reject embedding frameworks built for a higher target — a manual, easy-to-drift invariant across two separate files.
- **`GCC_PREPROCESSOR_DEFINITIONS` permission macro scope**: only `PERMISSION_CAMERA=1` is enabled (`Podfile:59-60`); the inline comment notes this was derived from grepping `lib/` for `Permission\.[a-zA-Z]+` usage — if a future feature module adds a new `permission_handler` permission (e.g. microphone, photos) without also updating this Podfile hook, that permission will silently return "denied" at runtime rather than prompting, exactly as camera did before this fix.
- **Router redirect ordering fragility**: the `redirect` callback in `app_router.dart` is a linear if-chain with several bespoke exceptions (loading-state passthrough, `onboardingPostFlowActiveProvider`) explicitly added to fix prior real regressions (documented inline at `app_router.dart:85-141`) — the logic is correct as-implemented but dense; a new route added without considering every branch of this chain could reintroduce a bounce-to-wrong-screen bug of the same shape as the ones already fixed.

## Backlog / Known Gaps

- No automated backend tests and no CI pipeline (see Testing Strategy) — the single largest gap in this module's scope.
- Permissive CORS (`allow_origins=["*"]` + `allow_credentials=True`) is live in both the code default and the committed `render.yaml` — flagged above as a security-relevant fact, not remediated as part of this retroactive baseline.
- No refresh-token/token-revocation mechanism in `backend/app/core/security.py` — sessions rely entirely on JWT natural expiry (24h).
- Local dev secrets (`SECRET_KEY`, DB credentials) are plaintext in `backend/docker-compose.yml` — acceptable for local-only use but worth noting as a pattern to not carry into any other environment.
- `Settings.secret_key` has an insecure literal default (`"change-me-in-.env"`) with no startup validation that a real value was provided outside of Render's `sync: false` mechanism — a misconfigured non-Render deployment would boot successfully with a known, guessable JWT signing key rather than failing fast.
