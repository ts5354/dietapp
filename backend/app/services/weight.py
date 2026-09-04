from datetime import date

from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError, SQLAlchemyError
from sqlalchemy.orm import Session

from app.db.models import WeightLog
from app.schemas.weight import WeightCreate, WeightUpdate


class WeightAlreadyExistsError(Exception):
    pass


class WeightNotFoundError(Exception):
    pass


def _commit(session: Session) -> None:
    try:
        session.commit()
    except SQLAlchemyError:
        session.rollback()
        raise


def create_weight(session: Session, payload: WeightCreate) -> WeightLog:
    weight = WeightLog(**payload.model_dump())
    session.add(weight)
    try:
        session.commit()
    except IntegrityError as error:
        session.rollback()
        constraint_name = getattr(
            getattr(error.orig, "diag", None), "constraint_name", None
        )
        if constraint_name == "uq_weight_logs_record_date":
            raise WeightAlreadyExistsError from error
        raise
    session.refresh(weight)
    return weight


def get_weight(session: Session, record_date: date) -> WeightLog:
    weight = session.scalar(
        select(WeightLog).where(WeightLog.record_date == record_date)
    )
    if weight is None:
        raise WeightNotFoundError
    return weight


def update_weight(
    session: Session, record_date: date, payload: WeightUpdate
) -> WeightLog:
    weight = get_weight(session, record_date)
    for field, value in payload.model_dump().items():
        setattr(weight, field, value)
    _commit(session)
    session.refresh(weight)
    return weight


def delete_weight(session: Session, record_date: date) -> None:
    weight = get_weight(session, record_date)
    session.delete(weight)
    _commit(session)


def list_weights(
    session: Session,
    *,
    from_date: date | None,
    to_date: date | None,
    limit: int,
    offset: int,
) -> tuple[list[WeightLog], int]:
    filters = []
    if from_date is not None:
        filters.append(WeightLog.record_date >= from_date)
    if to_date is not None:
        filters.append(WeightLog.record_date <= to_date)

    total = session.scalar(select(func.count()).select_from(WeightLog).where(*filters))
    items = list(
        session.scalars(
            select(WeightLog)
            .where(*filters)
            .order_by(WeightLog.record_date.desc())
            .limit(limit)
            .offset(offset)
        )
    )
    return items, total or 0
