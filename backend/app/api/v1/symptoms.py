from datetime import date
from typing import Annotated

from fastapi import APIRouter, Depends, Query, Response, status
from sqlalchemy.orm import Session

from app.api.dependencies import get_session
from app.api.errors import ApiError, validation_error
from app.schemas.symptom import (
    SymptomCreate,
    SymptomListResponse,
    SymptomResponse,
    SymptomUpdate,
)
from app.services import symptom as symptom_service
from app.services.symptom import InvalidSymptomFilterError, SymptomNotFoundError

router = APIRouter(prefix="/symptoms", tags=["symptoms"])
SessionDependency = Annotated[Session, Depends(get_session)]


def _not_found_error() -> ApiError:
    return ApiError(
        status_code=status.HTTP_404_NOT_FOUND,
        code="SYMPTOM_NOT_FOUND",
        message="Symptom record was not found.",
    )


@router.post("", response_model=SymptomResponse, status_code=status.HTTP_201_CREATED)
def create_symptom(
    payload: SymptomCreate, session: SessionDependency
) -> SymptomResponse:
    symptom = symptom_service.create_symptom(session, payload)
    return SymptomResponse.model_validate(symptom)


@router.get("", response_model=SymptomListResponse)
def list_symptoms(
    session: SessionDependency,
    from_date: Annotated[date | None, Query(alias="from")] = None,
    to_date: Annotated[date | None, Query(alias="to")] = None,
    timezone_name: Annotated[str | None, Query(alias="timezone")] = None,
    limit: Annotated[int, Query(ge=1, le=100)] = 50,
    offset: Annotated[int, Query(ge=0)] = 0,
) -> SymptomListResponse:
    try:
        items, total = symptom_service.list_symptoms(
            session,
            from_date=from_date,
            to_date=to_date,
            timezone_name=timezone_name,
            limit=limit,
            offset=offset,
        )
    except InvalidSymptomFilterError as error:
        raise validation_error(field=error.field, message=error.message) from error
    return SymptomListResponse(
        items=[SymptomResponse.model_validate(item) for item in items],
        total=total,
        limit=limit,
        offset=offset,
    )


@router.get("/{symptom_id}", response_model=SymptomResponse)
def get_symptom(symptom_id: int, session: SessionDependency) -> SymptomResponse:
    try:
        symptom = symptom_service.get_symptom(session, symptom_id)
    except SymptomNotFoundError as error:
        raise _not_found_error() from error
    return SymptomResponse.model_validate(symptom)


@router.put("/{symptom_id}", response_model=SymptomResponse)
def update_symptom(
    symptom_id: int, payload: SymptomUpdate, session: SessionDependency
) -> SymptomResponse:
    try:
        symptom = symptom_service.update_symptom(session, symptom_id, payload)
    except SymptomNotFoundError as error:
        raise _not_found_error() from error
    return SymptomResponse.model_validate(symptom)


@router.delete("/{symptom_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_symptom(symptom_id: int, session: SessionDependency) -> Response:
    try:
        symptom_service.delete_symptom(session, symptom_id)
    except SymptomNotFoundError as error:
        raise _not_found_error() from error
    return Response(status_code=status.HTTP_204_NO_CONTENT)
