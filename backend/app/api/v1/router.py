from fastapi import APIRouter

from app.api.v1.endpoints import (
    achievements,
    auth,
    challenges,
    exercises,
    health,
    onboarding,
    programs,
    progress,
    uploads,
    users,
    workouts,
)

api_router = APIRouter()
api_router.include_router(health.router)
api_router.include_router(auth.router)
api_router.include_router(users.router)
api_router.include_router(onboarding.router)
api_router.include_router(exercises.router)
api_router.include_router(programs.router)
api_router.include_router(workouts.router)
api_router.include_router(progress.router)
api_router.include_router(achievements.router)
api_router.include_router(challenges.router)
api_router.include_router(uploads.router)
