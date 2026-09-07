from datetime import date
from typing import Annotated

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.api.dependencies import get_session
from app.api.errors import validation_error
from app.schemas.dashboard import DashboardResponse
from app.services import dashboard as dashboard_service
from app.services.dashboard import InvalidDashboardTimezoneError

router = APIRouter(prefix="/dashboard", tags=["dashboard"])
SessionDependency = Annotated[Session, Depends(get_session)]


@router.get("", response_model=DashboardResponse)
def get_dashboard(
    session: SessionDependency,
    dashboard_date: Annotated[date, Query(alias="date")],
    timezone_name: Annotated[str, Query(alias="timezone")],
) -> DashboardResponse:
    try:
        return dashboard_service.get_dashboard(
            session,
            dashboard_date=dashboard_date,
            timezone_name=timezone_name,
        )
    except InvalidDashboardTimezoneError as error:
        raise validation_error(
            field="timezone", message="Timezone must be a valid IANA name."
        ) from error
