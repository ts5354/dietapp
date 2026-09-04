from fastapi import APIRouter

from app.api.v1.weights import router as weights_router

api_router = APIRouter()
api_router.include_router(weights_router)
