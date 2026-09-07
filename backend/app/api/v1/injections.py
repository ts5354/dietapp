from datetime import date
from typing import Annotated

from fastapi import APIRouter, Depends, Query, Response, status
from sqlalchemy.orm import Session

from app.api.dependencies import get_session
from app.api.errors import ApiError, validation_error
from app.schemas.injection import (
    InjectionCreate,
    InjectionListResponse,
    InjectionResponse,
    InjectionUpdate,
)
from app.services import injection as injection_service
from app.services.injection import (
    InjectionAlreadyExistsError,
    InjectionDateMismatchError,
    InjectionNotFoundError,
)

router = APIRouter(prefix="/injections", tags=["injections"])
SessionDependency = Annotated[Session, Depends(get_session)]


def _domain_error(code: str) -> ApiError:
    errors = {
        "INJECTION_ALREADY_EXISTS": (
            status.HTTP_409_CONFLICT,
            "An injection record already exists for this date.",
        ),
        "INJECTION_NOT_FOUND": (
            status.HTTP_404_NOT_FOUND,
            "Injection record was not found.",
        ),
        "INJECTION_DATE_MISMATCH": (
            status.HTTP_422_UNPROCESSABLE_CONTENT,
            "The injection timestamp does not match the record date.",
        ),
    }
    status_code, message = errors[code]
    return ApiError(status_code=status_code, code=code, message=message)


@router.post("", response_model=InjectionResponse, status_code=status.HTTP_201_CREATED)
def create_injection(
    payload: InjectionCreate, session: SessionDependency
) -> InjectionResponse:
    try:
        injection = injection_service.create_injection(session, payload)
    except InjectionDateMismatchError as error:
        raise _domain_error("INJECTION_DATE_MISMATCH") from error
    except InjectionAlreadyExistsError as error:
        raise _domain_error("INJECTION_ALREADY_EXISTS") from error
    return InjectionResponse.model_validate(injection)


@router.get("", response_model=InjectionListResponse)
def list_injections(
    session: SessionDependency,
    from_date: Annotated[date | None, Query(alias="from")] = None,
    to_date: Annotated[date | None, Query(alias="to")] = None,
    limit: Annotated[int, Query(ge=1, le=100)] = 50,
    offset: Annotated[int, Query(ge=0)] = 0,
) -> InjectionListResponse:
    if from_date is not None and to_date is not None and from_date > to_date:
        raise validation_error(
            field="from", message="Value must be before or equal to to."
        )
    items, total = injection_service.list_injections(
        session,
        from_date=from_date,
        to_date=to_date,
        limit=limit,
        offset=offset,
    )
    return InjectionListResponse(
        items=[InjectionResponse.model_validate(item) for item in items],
        total=total,
        limit=limit,
        offset=offset,
    )


@router.get("/{record_date}", response_model=InjectionResponse)
def get_injection(record_date: date, session: SessionDependency) -> InjectionResponse:
    try:
        injection = injection_service.get_injection(session, record_date)
    except InjectionNotFoundError as error:
        raise _domain_error("INJECTION_NOT_FOUND") from error
    return InjectionResponse.model_validate(injection)


@router.put("/{record_date}", response_model=InjectionResponse)
def update_injection(
    record_date: date, payload: InjectionUpdate, session: SessionDependency
) -> InjectionResponse:
    try:
        injection = injection_service.update_injection(session, record_date, payload)
    except InjectionNotFoundError as error:
        raise _domain_error("INJECTION_NOT_FOUND") from error
    except InjectionDateMismatchError as error:
        raise _domain_error("INJECTION_DATE_MISMATCH") from error
    return InjectionResponse.model_validate(injection)


@router.delete("/{record_date}", status_code=status.HTTP_204_NO_CONTENT)
def delete_injection(record_date: date, session: SessionDependency) -> Response:
    try:
        injection_service.delete_injection(session, record_date)
    except InjectionNotFoundError as error:
        raise _domain_error("INJECTION_NOT_FOUND") from error
    return Response(status_code=status.HTTP_204_NO_CONTENT)
