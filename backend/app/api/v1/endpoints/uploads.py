import uuid
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException, UploadFile, status

from app.api.deps import get_current_user
from app.models.user import User
from app.schemas.upload import UploadResponse

router = APIRouter(prefix="/uploads", tags=["uploads"])

ALLOWED_CONTENT_TYPES = {
    "image/jpeg": ".jpg",
    "image/png": ".png",
    "image/webp": ".webp",
}
MAX_UPLOAD_SIZE = 10 * 1024 * 1024  # 10 MB

UPLOAD_DIR = Path("static/uploads")


@router.post("", response_model=UploadResponse, status_code=status.HTTP_201_CREATED)
async def upload_file(
    file: UploadFile,
    current_user: User = Depends(get_current_user),
) -> UploadResponse:
    if file.content_type not in ALLOWED_CONTENT_TYPES:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Unsupported file type. Allowed types: image/jpeg, image/png, image/webp",
        )

    contents = await file.read()
    if len(contents) > MAX_UPLOAD_SIZE:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="File too large")

    original_ext = Path(file.filename).suffix.lower() if file.filename else ""
    valid_exts = {".jpg", ".jpeg", ".png", ".webp"}
    ext = original_ext if original_ext in valid_exts else ALLOWED_CONTENT_TYPES[file.content_type]

    filename = f"{uuid.uuid4()}{ext}"
    UPLOAD_DIR.mkdir(parents=True, exist_ok=True)
    (UPLOAD_DIR / filename).write_bytes(contents)

    return UploadResponse(url=f"/static/uploads/{filename}")
