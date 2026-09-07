from fastapi import APIRouter

from app.api.v1.dashboard import router as dashboard_router
from app.api.v1.injections import router as injections_router
from app.api.v1.nutrition import router as nutrition_router
from app.api.v1.symptoms import router as symptoms_router
from app.api.v1.weights import router as weights_router

api_router = APIRouter()
api_router.include_router(dashboard_router)
api_router.include_router(weights_router)
api_router.include_router(nutrition_router)
api_router.include_router(symptoms_router)
api_router.include_router(injections_router)
