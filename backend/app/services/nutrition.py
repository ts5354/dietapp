from datetime import date
from decimal import Decimal

from sqlalchemy import func, select
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from app.db.models import FoodLog, NutritionDay
from app.schemas.nutrition import (
    FoodCreate,
    FoodResponse,
    FoodUpdate,
    NutritionDayDetail,
    NutritionDaySummary,
    NutritionDayUpdate,
)


class FoodNotAllowedOnFreeDayError(Exception):
    pass


class FoodDateMismatchError(Exception):
    pass


class FoodNotFoundError(Exception):
    pass


class FreeDayHasFoodLogsError(Exception):
    pass


def _commit(session: Session) -> None:
    try:
        session.commit()
    except SQLAlchemyError:
        session.rollback()
        raise


def _persisted_day(session: Session, day_date: date) -> NutritionDay | None:
    return session.scalar(select(NutritionDay).where(NutritionDay.date == day_date))


def _day_foods(session: Session, nutrition_day_id: int) -> list[FoodLog]:
    return list(
        session.scalars(
            select(FoodLog)
            .where(FoodLog.nutrition_day_id == nutrition_day_id)
            .order_by(FoodLog.eaten_at.asc(), FoodLog.id.asc())
        )
    )


def _detail(day: NutritionDay, foods: list[FoodLog]) -> NutritionDayDetail:
    if day.mode == "FREE_DAY":
        return NutritionDayDetail(
            date=day.date,
            mode="FREE_DAY",
            memo=day.memo,
            total_calories=None,
            total_protein_g=None,
            foods=[],
        )
    return NutritionDayDetail(
        date=day.date,
        mode="NORMAL",
        memo=day.memo,
        total_calories=sum(food.calories for food in foods),
        total_protein_g=sum((food.protein_g for food in foods), start=Decimal("0.0")),
        foods=[FoodResponse.model_validate(food) for food in foods],
    )


def get_day(session: Session, day_date: date) -> NutritionDayDetail:
    day = _persisted_day(session, day_date)
    if day is None:
        return NutritionDayDetail(
            date=day_date,
            mode="UNRECORDED",
            memo=None,
            total_calories=None,
            total_protein_g=None,
            foods=[],
        )
    return _detail(day, _day_foods(session, day.id))


def set_day(
    session: Session, day_date: date, payload: NutritionDayUpdate
) -> NutritionDayDetail:
    day = _persisted_day(session, day_date)
    if day is None:
        day = NutritionDay(date=day_date, **payload.model_dump())
        session.add(day)
    else:
        if day.mode == "NORMAL" and payload.mode == "FREE_DAY":
            has_food = session.scalar(
                select(FoodLog.id).where(FoodLog.nutrition_day_id == day.id).limit(1)
            )
            if has_food is not None:
                raise FreeDayHasFoodLogsError
        day.mode = payload.mode
        day.memo = payload.memo

    _commit(session)
    session.refresh(day)
    return _detail(day, _day_foods(session, day.id))


def _validate_food_date(day_date: date, eaten_at: object) -> None:
    if eaten_at.date() != day_date:
        raise FoodDateMismatchError


def create_food(session: Session, day_date: date, payload: FoodCreate) -> FoodResponse:
    _validate_food_date(day_date, payload.eaten_at)
    day = _persisted_day(session, day_date)
    if day is not None and day.mode == "FREE_DAY":
        raise FoodNotAllowedOnFreeDayError

    try:
        if day is None:
            day = NutritionDay(date=day_date, mode="NORMAL", memo=None)
            session.add(day)
            session.flush()
        food = FoodLog(nutrition_day_id=day.id, **payload.model_dump())
        session.add(food)
        session.commit()
    except SQLAlchemyError:
        session.rollback()
        raise
    session.refresh(food)
    return FoodResponse.model_validate(food)


def _nested_food(session: Session, day_date: date, food_id: int) -> FoodLog:
    food = session.scalar(
        select(FoodLog)
        .join(NutritionDay, NutritionDay.id == FoodLog.nutrition_day_id)
        .where(FoodLog.id == food_id, NutritionDay.date == day_date)
    )
    if food is None:
        raise FoodNotFoundError
    return food


def update_food(
    session: Session, day_date: date, food_id: int, payload: FoodUpdate
) -> FoodResponse:
    food = _nested_food(session, day_date, food_id)
    _validate_food_date(day_date, payload.eaten_at)
    for field, value in payload.model_dump().items():
        setattr(food, field, value)
    _commit(session)
    session.refresh(food)
    return FoodResponse.model_validate(food)


def delete_food(session: Session, day_date: date, food_id: int) -> None:
    food = _nested_food(session, day_date, food_id)
    session.delete(food)
    _commit(session)


def list_days(
    session: Session,
    *,
    from_date: date | None,
    to_date: date | None,
    limit: int,
    offset: int,
) -> tuple[list[NutritionDaySummary], int]:
    filters = []
    if from_date is not None:
        filters.append(NutritionDay.date >= from_date)
    if to_date is not None:
        filters.append(NutritionDay.date <= to_date)

    total = session.scalar(
        select(func.count()).select_from(NutritionDay).where(*filters)
    )
    days = list(
        session.scalars(
            select(NutritionDay)
            .where(*filters)
            .order_by(NutritionDay.date.desc())
            .limit(limit)
            .offset(offset)
        )
    )

    items = []
    for day in days:
        detail = _detail(day, _day_foods(session, day.id))
        items.append(
            NutritionDaySummary(
                date=detail.date,
                mode=detail.mode,
                memo=detail.memo,
                total_calories=detail.total_calories,
                total_protein_g=detail.total_protein_g,
            )
        )
    return items, total or 0
