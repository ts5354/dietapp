from datetime import date, datetime

from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError, SQLAlchemyError
from sqlalchemy.orm import Session

from app.db.models import InjectionRecord
from app.schemas.injection import InjectionCreate, InjectionUpdate


class InjectionAlreadyExistsError(Exception):
    pass


class InjectionNotFoundError(Exception):
    pass


class InjectionDateMismatchError(Exception):
    pass


def _commit(session: Session) -> None:
    try:
        session.commit()
    except SQLAlchemyError:
        session.rollback()
        raise


def _find_by_date(session: Session, record_date: date) -> InjectionRecord | None:
    return session.scalar(
        select(InjectionRecord).where(InjectionRecord.record_date == record_date)
    )


def _validate_date(record_date: date, injected_at: datetime) -> None:
    if injected_at.date() != record_date:
        raise InjectionDateMismatchError


def create_injection(session: Session, payload: InjectionCreate) -> InjectionRecord:
    _validate_date(payload.record_date, payload.injected_at)
    if _find_by_date(session, payload.record_date) is not None:
        raise InjectionAlreadyExistsError

    injection = InjectionRecord(**payload.model_dump())
    session.add(injection)
    try:
        session.commit()
    except IntegrityError as error:
        session.rollback()
        constraint_name = getattr(
            getattr(error.orig, "diag", None), "constraint_name", None
        )
        if constraint_name == "uq_injection_records_record_date":
            raise InjectionAlreadyExistsError from error
        raise
    except SQLAlchemyError:
        session.rollback()
        raise
    session.refresh(injection)
    return injection


def get_injection(session: Session, record_date: date) -> InjectionRecord:
    injection = _find_by_date(session, record_date)
    if injection is None:
        raise InjectionNotFoundError
    return injection


def update_injection(
    session: Session, record_date: date, payload: InjectionUpdate
) -> InjectionRecord:
    injection = get_injection(session, record_date)
    _validate_date(record_date, payload.injected_at)
    for field, value in payload.model_dump().items():
        setattr(injection, field, value)
    _commit(session)
    session.refresh(injection)
    return injection


def delete_injection(session: Session, record_date: date) -> None:
    injection = get_injection(session, record_date)
    session.delete(injection)
    _commit(session)


def list_injections(
    session: Session,
    *,
    from_date: date | None,
    to_date: date | None,
    limit: int,
    offset: int,
) -> tuple[list[InjectionRecord], int]:
    filters = []
    if from_date is not None:
        filters.append(InjectionRecord.record_date >= from_date)
    if to_date is not None:
        filters.append(InjectionRecord.record_date <= to_date)

    total = session.scalar(
        select(func.count()).select_from(InjectionRecord).where(*filters)
    )
    items = list(
        session.scalars(
            select(InjectionRecord)
            .where(*filters)
            .order_by(InjectionRecord.injected_at.desc(), InjectionRecord.id.desc())
            .limit(limit)
            .offset(offset)
        )
    )
    return items, total or 0
