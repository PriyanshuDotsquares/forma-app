# FORMA

An AI-coached strength-training app. Flutter frontend + Python (FastAPI) backend.

```
FORMA/
  app/       Flutter client (iOS, Android, Web)
  backend/   FastAPI + PostgreSQL API
```

## Status

Full working app, styled to match FORMA's real Figma screens ("Cast Iron &
Chalk Dust" design system — near-black surfaces, IWF-plate accent colors,
no shadows/gradients/emoji; theme in `app/lib/core/design_system/`).

**App:** a 9-step onboarding quiz that generates a personalized weekly
training program (deterministic rule-based generation, optionally
LLM-personalized via Groq with an automatic fallback); active-workout set
logging with real on-device camera form coaching (MediaPipe pose
detection, rep counting, spoken coaching cues); progress analytics
(volume, recovery, personal records, form-quality trend); achievements and
weekly/monthly challenges; a Profile tab and Settings (notification
preferences, voice-coach tuning, English/Hindi localization); a Premium
screen with real (but store-unconfigured) in-app-purchase plumbing.

**Backend:** JWT auth with password reset, a curated 47-exercise library,
program/workout/progress/achievement/challenge domain models and
endpoints, and an AI plan-generation service (Groq-hosted LLM with a
deterministic fallback so plan generation never hard-fails).

## Documentation

FORMA follows Spec-Driven Development. [SPEC_DRIVEN_DEVELOPMENT.md](SPEC_DRIVEN_DEVELOPMENT.md)
covers the process, architecture, tech stack, and a full module catalog;
[specs/INDEX.md](specs/INDEX.md) is the per-module spec catalog with
notable findings. Start there before making a behavior change to any
existing feature.

## Backend — run locally

```
cd backend
docker compose up --build
```

This starts Postgres and the API on `http://localhost:8000`
(`/docs` for Swagger UI, `/health` for a liveness check).

Without Docker: create a venv, `pip install -r requirements-dev.txt`,
point `DATABASE_URL` (see `.env.example`) at a Postgres instance you run
yourself (e.g. `brew services start postgresql@15`), then:

```
alembic upgrade head
uvicorn app.main:app --reload
```

## App — run locally

```
cd app
flutter pub get
flutter run
```

Defaults to `http://localhost:8000/api/v1` as the API base URL. Override with:

```
flutter run --dart-define=API_BASE_URL=http://<host>:8000/api/v1
```

(Use your machine's LAN IP instead of `localhost` when running on a
physical device or an Android emulator — the emulator maps
`10.0.2.2` to the host.)
