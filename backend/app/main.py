from typing import Annotated

from fastapi import Depends, FastAPI, status
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from app.api.dependencies import get_session
from app.api.errors import ApiError, register_exception_handlers
from app.api.v1.router import api_router

app = FastAPI(title="dietapp API")
register_exception_handlers(app)
app.include_router(api_router, prefix="/api/v1")

SessionDependency = Annotated[Session, Depends(get_session)]


def health(session: SessionDependency) -> dict[str, str]:
    try:
        session.execute(text("SELECT 1"))
    except SQLAlchemyError as error:
        raise ApiError(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            code="SERVICE_UNAVAILABLE",
            message="The service is temporarily unavailable.",
        ) from error
    return {"status": "ok"}


app.add_api_route("/health", health, methods=["GET"])
# Preserve the development endpoint used before the platform health route existed.
app.add_api_route("/api/v1/health", health, methods=["GET"], include_in_schema=False)
