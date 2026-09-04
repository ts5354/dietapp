from datetime import date
from typing import Annotated

from fastapi import APIRouter, Depends, Query, Response, status
from sqlalchemy.orm import Session

from app.api.dependencies import get_session
from app.api.errors import ApiError, validation_error
from app.schemas.weight import (
    WeightCreate,
    WeightListResponse,
    WeightResponse,
    WeightUpdate,
)
from app.services import weight as weight_service
from app.services.weight import WeightAlreadyExistsError, WeightNotFoundError

router = APIRouter(prefix="/weights", tags=["weights"])
SessionDependency = Annotated[Session, Depends(get_session)]


def _not_found_error() -> ApiError:
    return ApiError(
        status_code=status.HTTP_404_NOT_FOUND,
        code="WEIGHT_NOT_FOUND",
        message="The weight record was not found.",
    )


@router.post("", response_model=WeightResponse, status_code=status.HTTP_201_CREATED)
def create_weight(payload: WeightCreate, session: SessionDependency) -> WeightResponse:
    try:
        weight = weight_service.create_weight(session, payload)
    except WeightAlreadyExistsError as error:
        raise ApiError(
            status_code=status.HTTP_409_CONFLICT,
            code="WEIGHT_ALREADY_EXISTS",
            message="A weight record already exists for this date.",
        ) from error
    return WeightResponse.model_validate(weight)


@router.get("", response_model=WeightListResponse)
def list_weights(
    session: SessionDependency,
    from_date: Annotated[date | None, Query(alias="from")] = None,
    to_date: Annotated[date | None, Query(alias="to")] = None,
    limit: Annotated[int, Query(ge=1, le=100)] = 50,
    offset: Annotated[int, Query(ge=0)] = 0,
) -> WeightListResponse:
    if from_date is not None and to_date is not None and from_date > to_date:
        raise validation_error(
            field="from", message="Value must be before or equal to to."
        )

    items, total = weight_service.list_weights(
        session,
        from_date=from_date,
        to_date=to_date,
        limit=limit,
        offset=offset,
    )
    return WeightListResponse(
        items=[WeightResponse.model_validate(item) for item in items],
        total=total,
        limit=limit,
        offset=offset,
    )


@router.get("/{record_date}", response_model=WeightResponse)
def get_weight(record_date: date, session: SessionDependency) -> WeightResponse:
    try:
        weight = weight_service.get_weight(session, record_date)
    except WeightNotFoundError as error:
        raise _not_found_error() from error
    return WeightResponse.model_validate(weight)


@router.put("/{record_date}", response_model=WeightResponse)
def update_weight(
    record_date: date, payload: WeightUpdate, session: SessionDependency
) -> WeightResponse:
    try:
        weight = weight_service.update_weight(session, record_date, payload)
    except WeightNotFoundError as error:
        raise _not_found_error() from error
    return WeightResponse.model_validate(weight)


@router.delete("/{record_date}", status_code=status.HTTP_204_NO_CONTENT)
def delete_weight(record_date: date, session: SessionDependency) -> Response:
    try:
        weight_service.delete_weight(session, record_date)
    except WeightNotFoundError as error:
        raise _not_found_error() from error
    return Response(status_code=status.HTTP_204_NO_CONTENT)
