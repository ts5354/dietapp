from datetime import date
from typing import Annotated

from fastapi import APIRouter, Depends, Query, Response, status
from sqlalchemy.orm import Session

from app.api.dependencies import get_session
from app.api.errors import ApiError, validation_error
from app.schemas.nutrition import (
    FoodCreate,
    FoodResponse,
    FoodUpdate,
    NutritionDayDetail,
    NutritionDayListResponse,
    NutritionDayUpdate,
)
from app.services import nutrition as nutrition_service
from app.services.nutrition import (
    FoodDateMismatchError,
    FoodNotAllowedOnFreeDayError,
    FoodNotFoundError,
    FreeDayHasFoodLogsError,
)

router = APIRouter(prefix="/nutrition/days", tags=["nutrition"])
SessionDependency = Annotated[Session, Depends(get_session)]


def _domain_error(code: str) -> ApiError:
    errors = {
        "FOOD_NOT_ALLOWED_ON_FREE_DAY": (
            status.HTTP_409_CONFLICT,
            "Food cannot be added to a free day.",
        ),
        "FOOD_DATE_MISMATCH": (
            status.HTTP_422_UNPROCESSABLE_CONTENT,
            "The food timestamp does not match the requested date.",
        ),
        "FOOD_NOT_FOUND": (
            status.HTTP_404_NOT_FOUND,
            "The food record was not found.",
        ),
        "FREE_DAY_HAS_FOOD_LOGS": (
            status.HTTP_409_CONFLICT,
            "A day with food records cannot be changed to a free day.",
        ),
    }
    status_code, message = errors[code]
    return ApiError(status_code=status_code, code=code, message=message)


@router.get("", response_model=NutritionDayListResponse)
def list_days(
    session: SessionDependency,
    from_date: Annotated[date | None, Query(alias="from")] = None,
    to_date: Annotated[date | None, Query(alias="to")] = None,
    limit: Annotated[int, Query(ge=1, le=100)] = 50,
    offset: Annotated[int, Query(ge=0)] = 0,
) -> NutritionDayListResponse:
    if from_date is not None and to_date is not None and from_date > to_date:
        raise validation_error(
            field="from", message="Value must be before or equal to to."
        )
    items, total = nutrition_service.list_days(
        session,
        from_date=from_date,
        to_date=to_date,
        limit=limit,
        offset=offset,
    )
    return NutritionDayListResponse(
        items=items, total=total, limit=limit, offset=offset
    )


@router.get("/{day_date}", response_model=NutritionDayDetail)
def get_day(day_date: date, session: SessionDependency) -> NutritionDayDetail:
    return nutrition_service.get_day(session, day_date)


@router.put("/{day_date}", response_model=NutritionDayDetail)
def set_day(
    day_date: date, payload: NutritionDayUpdate, session: SessionDependency
) -> NutritionDayDetail:
    try:
        return nutrition_service.set_day(session, day_date, payload)
    except FreeDayHasFoodLogsError as error:
        raise _domain_error("FREE_DAY_HAS_FOOD_LOGS") from error


@router.post(
    "/{day_date}/foods",
    response_model=FoodResponse,
    status_code=status.HTTP_201_CREATED,
)
def create_food(
    day_date: date, payload: FoodCreate, session: SessionDependency
) -> FoodResponse:
    try:
        return nutrition_service.create_food(session, day_date, payload)
    except FoodNotAllowedOnFreeDayError as error:
        raise _domain_error("FOOD_NOT_ALLOWED_ON_FREE_DAY") from error
    except FoodDateMismatchError as error:
        raise _domain_error("FOOD_DATE_MISMATCH") from error


@router.put("/{day_date}/foods/{food_id}", response_model=FoodResponse)
def update_food(
    day_date: date,
    food_id: int,
    payload: FoodUpdate,
    session: SessionDependency,
) -> FoodResponse:
    try:
        return nutrition_service.update_food(session, day_date, food_id, payload)
    except FoodNotFoundError as error:
        raise _domain_error("FOOD_NOT_FOUND") from error
    except FoodDateMismatchError as error:
        raise _domain_error("FOOD_DATE_MISMATCH") from error


@router.delete("/{day_date}/foods/{food_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_food(day_date: date, food_id: int, session: SessionDependency) -> Response:
    try:
        nutrition_service.delete_food(session, day_date, food_id)
    except FoodNotFoundError as error:
        raise _domain_error("FOOD_NOT_FOUND") from error
    return Response(status_code=status.HTTP_204_NO_CONTENT)
