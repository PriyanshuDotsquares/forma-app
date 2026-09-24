Status: Approved (Retroactive Baseline — documents behavior as implemented, dated 2026-09-10)
Owner: Engineering team (retroactive)
Related: n/a

## Approach
A single, minimal FastAPI route accepts a `multipart/form-data` file upload, validates its content type and size, writes it to a local directory with a randomized filename, and returns the public path it will be served from. No database record is created — the "media" being managed is purely a file on disk plus the URL string returned to the caller.

## Architecture / Data Flow
- **Router registration**: `backend/app/api/v1/router.py` imports `uploads` and calls `api_router.include_router(uploads.router)`, so the endpoint is live at `POST /api/v1/uploads` (prefix `/uploads` defined on the router itself, mounted under the versioned `/api/v1` prefix — confirm exact combination via `backend/app/main.py`'s inclusion of `api_router`).
- **Endpoint**: `backend/app/api/v1/endpoints/uploads.py`
  - `router = APIRouter(prefix="/uploads", tags=["uploads"])`
  - `POST /` handler `upload_file(file: UploadFile, current_user: User = Depends(get_current_user))`:
    1. Auth: `get_current_user` (from `app.api.deps`) decodes and validates the bearer JWT; unauthenticated/invalid requests get `401` before any file handling.
    2. Content-type check: `file.content_type` must be a key in `ALLOWED_CONTENT_TYPES = {"image/jpeg": ".jpg", "image/png": ".png", "image/webp": ".webp"}`; otherwise `400`.
    3. Size check: full file contents are read via `await file.read()`, then compared against `MAX_UPLOAD_SIZE = 10 * 1024 * 1024` (10 MB); over the limit → `400`.
    4. Extension resolution: takes `Path(file.filename).suffix.lower()` if present and in `{".jpg", ".jpeg", ".png", ".webp"}`, else falls back to the extension mapped from the validated content type.
    5. Storage: `UPLOAD_DIR = Path("static/uploads")` (relative path — resolved against the backend process's CWD); `UPLOAD_DIR.mkdir(parents=True, exist_ok=True)` then `(UPLOAD_DIR / filename).write_bytes(contents)` where `filename = f"{uuid.uuid4()}{ext}"`. This is synchronous blocking disk I/O inside an `async def` handler.
    6. Response: `UploadResponse(url=f"/static/uploads/{filename}")`, HTTP `201 Created`.
- **Schema**: `backend/app/schemas/upload.py` — `UploadResponse(BaseModel)` with a single field `url: str`. No request schema needed (FastAPI derives the multipart form from the `UploadFile` parameter).
- **Static serving**: `backend/app/main.py` creates the directory (`Path("static/uploads").mkdir(parents=True, exist_ok=True)`) at startup and mounts `app.mount("/static", StaticFiles(directory="static"), name="static")`, so any file written by the upload handler becomes immediately and publicly (unauthenticated) readable at `/static/uploads/<filename>`.
- **Client side**: No corresponding code found. See Backlog/Known Gaps.

## Data / Schema
No database table or ORM model backs this feature — nothing in `backend/app/models` represents an "upload" or "media" entity. The only persisted state is the file itself on the local filesystem (`backend/static/uploads/<uuid>.<ext>`) and the transient `UploadResponse.url` string returned to the caller. There is no join to `User` or any other row beyond the auth check at request time (the uploader's identity is not recorded).

## Alternatives Considered
N/A — retroactive baseline.

## Testing Strategy
No automated tests — gap. There is no `backend/tests/` directory in the repository at all (checked via `find`), so this endpoint (like the rest of the backend) has zero automated test coverage. The single file present in `backend/static/uploads/` (`bd72946d-1a56-4cde-bfdd-7b19af610f3c.png`, a 4x4 pixel, 107-byte PNG, git-untracked since `backend/.gitignore` excludes `static/`) is consistent with one manual, ad hoc exercise of the endpoint (e.g. via curl or the FastAPI Swagger UI at `/docs`) rather than a test fixture or real app usage.

## Risks / Edge Cases
- **Unbounded disk growth**: uploaded files are never deleted or garbage-collected; every successful call adds a permanent file with no owner or expiry.
- **Full in-memory read**: `await file.read()` loads the entire file into memory before the size check, so the 10 MB cap bounds memory use but the check happens after the read rather than streaming/rejecting early.
- **Blocking I/O in async handler**: `Path.write_bytes` and `Path.mkdir` are synchronous calls made directly inside an `async def` route, which can block the event loop under load (minor at this file's scale, but a real pattern risk if reused elsewhere).
- **No ownership/authorization on read**: once stored, a file is publicly readable by anyone with the URL — the write path requires auth, the read path does not, and there is no linkage recorded between the uploading user and the file.
- **Relative path dependence**: `UPLOAD_DIR = Path("static/uploads")` is relative to the process's working directory rather than anchored to the project/package root; behavior depends on how/where the backend process is launched.
- **Orphaned dependency**: `image_picker` is declared in `app/pubspec.yaml` but has zero usages anywhere in `app/lib`, adding an unused native dependency (and associated iOS/Android permission surface) to the client build.

## Backlog / Known Gaps
- **Dead code (verified)**: This endpoint has no known caller in the current Flutter client.
  - `backend/app/api/v1/endpoints/uploads.py` and `backend/app/schemas/upload.py` are fully implemented and the router IS mounted (`backend/app/api/v1/router.py`: `api_router.include_router(uploads.router)`), so the endpoint is live and reachable if called.
  - A full-tree search of `app/lib` (not just `app/lib/features`) for `"/uploads"`, `"UploadResponse"`, and any Dio/http multipart call — including `app/lib/core/network/{api_client,providers,api_exception}.dart` — returned no matches.
  - A full-tree search of `app/lib` for `"image_picker"` (import or symbol usage: `ImagePicker`, `pickImage`, `getImage`) returned no matches, despite `image_picker: ^1.2.3` being declared in `app/pubspec.yaml:47`.
  - The two Flutter files that matched a generic `"upload"` grep are unrelated: `app/lib/features/settings/presentation/settings_screen.dart:777` and `app/lib/features/workout/presentation/camera_precheck_screen.dart:191` both contain only privacy-copy strings ("Nothing is uploaded") about the live camera-coaching feature, not calls to this endpoint.
  - `backend/static/uploads/` contains exactly one file, a 4x4 pixel/107-byte test PNG, untracked by git — evidence of a single manual test call, not real historical feature usage.
  - There is no `backend/tests/` directory, so nothing in the backend's own test suite exercises this endpoint either.
  - **Conclusion**: this module is dead/unused from the current app's perspective — most likely a leftover from the pre-pivot "memory-keeping" photo-keepsake app — but it is technically functional and still mounted, so it is "dead" in the sense of "unreferenced by any known caller," not "broken" or "unreachable."
- Follow-up decision needed (see requirements.md Open Questions): remove this module, or repurpose it for a future feature (profile photo, exercise photo, progress photo) and wire up `image_picker` + a client-side caller against it.
