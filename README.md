# FORMA

A personal memory-keeping app. Flutter frontend + Python (FastAPI) backend.

```
FORMA/
  app/       Flutter client (iOS, Android, Web)
  backend/   FastAPI + PostgreSQL API
```

## Status

Full working app, built without the Figma design (the connector could not
be reached from this session — see below), using original UI/UX judgment
for a warm, nostalgic "memory keeper" aesthetic (theme in
`app/lib/core/theme/app_theme.dart`). Once Figma access works, ask again
to pull the real screens/tokens and restyle to match.

**App:** email/password auth (register, login, persisted session, logout),
profile editing, a searchable/filterable keepsake grid, create/edit with
photo upload (camera or gallery) and a memory date, favoriting, and delete.

**Backend:** JWT auth, user profile endpoints, keepsakes CRUD (search,
favorite filter, pagination), image upload served over `/static`.
Verified end-to-end (Flutter web → FastAPI → Postgres) during setup —
every flow above was exercised against a live server, not just written.

Figma file (pending access):
https://www.figma.com/design/aUcWsto79BraPlypKaW6Hr/Untitled

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
