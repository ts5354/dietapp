from fastapi import FastAPI

from app.api.errors import register_exception_handlers
from app.api.v1.router import api_router

app = FastAPI(title="dietapp API")
register_exception_handlers(app)
app.include_router(api_router, prefix="/api/v1")


@app.get("/api/v1/health")
def health() -> dict[str, str]:
    return {"status": "ok"}
