Status: Approved (Retroactive Baseline — documents behavior as implemented, dated 2026-09-10)
Owner: Engineering team (retroactive)
Related: n/a

## Summary
A generic, authenticated image-upload endpoint (`POST /api/v1/uploads`) exists in the FastAPI backend. It accepts a single JPEG/PNG/WebP file, stores it on local disk under `backend/static/uploads/`, and returns a public URL served via the app's `/static` mount. The endpoint is fully implemented and wired into the API router, but investigation found **no caller anywhere in the current Flutter client** — it appears to be dead/unused code.

## Background / Problem
FORMA was originally a different app — a "memory-keeping" app with photo-upload keepsakes — before being pivoted to the current AI strength-coaching app around 2026-08-27. This generic upload endpoint (`backend/app/api/v1/endpoints/uploads.py`, `backend/app/schemas/upload.py`) is consistent with that earlier product: a simple, feature-agnostic "upload an image, get back a URL" primitive with no linkage to any domain model (no `user_id` foreign key, no association to a workout, exercise, or progress record). It most plausibly predates the pivot and was never removed.

The Flutter client declares `image_picker: ^1.2.3` in `app/pubspec.yaml`, but a full-tree search of `app/lib` found zero imports or usages of the `image_picker` package, and zero references to `/uploads`, `UploadResponse`, or any multipart/file-upload network call. The only file present in `backend/static/uploads/` is a single 4x4 pixel, 107-byte test PNG (untracked by git, since `backend/.gitignore` excludes `static/`), consistent with a one-off manual/developer test (e.g. via curl or the FastAPI `/docs` Swagger UI) rather than genuine use through the app's UI.

## User Stories
- As an API client (authenticated), I can POST an image file to `/api/v1/uploads` and receive back a URL where that image is now publicly retrievable, so that I can attach the URL to some other resource.
- As an authenticated user of the FastAPI backend, I cannot upload a file without a valid bearer token — the endpoint enforces authentication even though the stored file is not associated with my user ID in any way.

## Acceptance Criteria (EARS format: "WHEN/IF ... THE SYSTEM SHALL ...")
- WHEN a client sends `POST /api/v1/uploads` with a valid bearer token and a file whose `content_type` is `image/jpeg`, `image/png`, or `image/webp`, THE SYSTEM SHALL store the file under `backend/static/uploads/` with a newly generated UUID filename and SHALL respond `201 Created` with a JSON body `{"url": "/static/uploads/<uuid>.<ext>"}`.
- IF the request has no valid bearer token, THEN THE SYSTEM SHALL reject the request with `401 Unauthorized` (via the shared `get_current_user` dependency) before processing the file.
- IF the uploaded file's `content_type` is not one of `image/jpeg`, `image/png`, `image/webp`, THEN THE SYSTEM SHALL reject the request with `400 Bad Request` and an "Unsupported file type" message.
- IF the uploaded file's byte size exceeds 10 MB, THEN THE SYSTEM SHALL reject the request with `400 Bad Request` and a "File too large" message.
- WHEN determining the stored file's extension, THE SYSTEM SHALL prefer the original filename's extension if it is one of `.jpg`, `.jpeg`, `.png`, `.webp`, and SHALL otherwise fall back to the extension implied by the validated `content_type`.
- WHEN a file is successfully stored, THE SYSTEM SHALL make it retrievable at `/static/uploads/<filename>` via the app's static file mount, with no additional authentication required to read it back.

## Out of Scope
- Associating an uploaded file with a specific user, workout, exercise, or any other domain record — the endpoint has no such linkage (no `user_id`, no foreign key, no owning-resource concept).
- Deleting or replacing previously uploaded files — no delete/update endpoint exists.
- Client-side integration (image picking, cropping, upload UI) — no such code exists in `app/lib` as of this baseline.
- Cloud/object storage (S3, GCS, etc.) — storage is local disk only.
- Image processing (resizing, thumbnailing, EXIF stripping, compression).

## Non-Functional Requirements
- Max upload size is enforced in-application at 10 MB (`MAX_UPLOAD_SIZE` in `uploads.py`); this is read into memory in full (`await file.read()`) before the size check, not streamed.
- Only three image MIME types are accepted; no video, PDF, or other file types.
- Storage is local filesystem (`static/uploads/`, relative to the backend process's working directory), not durable/replicated cloud storage — files are lost if the backend's disk/container is not persistent.
- Filenames are randomized (UUID4) to avoid collisions and avoid trusting client-supplied filenames beyond their extension.

## Open Questions
- **Is this endpoint dead code?** Verified: no Flutter client code anywhere in `app/lib` references `/uploads`, `UploadResponse`, or the `image_picker` package (declared as a pubspec dependency but never imported). The only artifact in `backend/static/uploads/` is a trivial 4x4 test PNG, not a real user photo, and it is git-untracked. The endpoint remains mounted (`backend/app/api/v1/router.py`) and fully functional, but has no known current caller.
- Should this endpoint be removed as leftover pre-pivot code, or is it reserved/intended for a future feature (e.g. profile photos, exercise reference photos, progress/before-after photos) that would plausibly reuse `image_picker` and this same storage primitive?
- If kept, should it gain domain association (e.g. tie an upload to a user or progress-photo record) rather than remaining a bare, unowned "URL in, URL out" primitive?
