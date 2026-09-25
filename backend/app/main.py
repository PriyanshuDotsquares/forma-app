from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from app.api.v1.router import api_router
from app.core.config import get_settings

settings = get_settings()

app = FastAPI(title=settings.project_name)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    # The client authenticates with a bearer JWT (Authorization header), never
    # cookies, so allow_credentials is not needed here — and combined with a
    # wildcard allow_origins it lets any origin make credentialed requests
    # (Starlette reflects the request's Origin whenever credentials are
    # allowed). Leaving it False closes that hole without affecting the app.
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(api_router, prefix=settings.api_v1_prefix)

Path("static/uploads").mkdir(parents=True, exist_ok=True)
app.mount("/static", StaticFiles(directory="static"), name="static")


@app.get("/health", tags=["health"])
async def root_health_check() -> dict[str, str]:
    return {"status": "ok"}
