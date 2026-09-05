from datetime import date, datetime, time, timedelta, timezone
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from sqlalchemy import func, select
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from app.db.models import SymptomLog
from app.schemas.symptom import SymptomCreate, SymptomUpdate


class SymptomNotFoundError(Exception):
    pass


class InvalidSymptomFilterError(Exception):
    def __init__(self, field: str, message: str) -> None:
        self.field = field
        self.message = message


def _commit(session: Session) -> None:
    try:
        session.commit()
    except SQLAlchemyError:
        session.rollback()
        raise


def create_symptom(session: Session, payload: SymptomCreate) -> SymptomLog:
    symptom = SymptomLog(**payload.model_dump())
    session.add(symptom)
    _commit(session)
    session.refresh(symptom)
    return symptom


def get_symptom(session: Session, symptom_id: int) -> SymptomLog:
    symptom = session.get(SymptomLog, symptom_id)
    if symptom is None:
        raise SymptomNotFoundError
    return symptom


def update_symptom(
    session: Session, symptom_id: int, payload: SymptomUpdate
) -> SymptomLog:
    symptom = get_symptom(session, symptom_id)
    for field, value in payload.model_dump().items():
        setattr(symptom, field, value)
    _commit(session)
    session.refresh(symptom)
    return symptom


def delete_symptom(session: Session, symptom_id: int) -> None:
    symptom = get_symptom(session, symptom_id)
    session.delete(symptom)
    _commit(session)


def utc_date_boundaries(
    *,
    from_date: date | None,
    to_date: date | None,
    timezone_name: str | None,
) -> tuple[datetime | None, datetime | None]:
    has_date_filter = from_date is not None or to_date is not None
    if has_date_filter and timezone_name is None:
        raise InvalidSymptomFilterError(
            "timezone", "Timezone is required when from or to is provided."
        )
    if not has_date_filter and timezone_name is not None:
        raise InvalidSymptomFilterError(
            "timezone", "Timezone requires a from or to date."
        )
    if from_date is not None and to_date is not None and from_date > to_date:
        raise InvalidSymptomFilterError("from", "Value must be before or equal to to.")
    if timezone_name is None:
        return None, None
    if timezone_name == "JST" or timezone_name.startswith(("+", "-")):
        raise InvalidSymptomFilterError(
            "timezone", "Timezone must be a valid IANA name."
        )

    try:
        zone = ZoneInfo(timezone_name)
    except (ZoneInfoNotFoundError, ValueError) as error:
        raise InvalidSymptomFilterError(
            "timezone", "Timezone must be a valid IANA name."
        ) from error

    lower = (
        datetime.combine(from_date, time.min, tzinfo=zone).astimezone(timezone.utc)
        if from_date is not None
        else None
    )
    upper = (
        datetime.combine(to_date + timedelta(days=1), time.min, tzinfo=zone).astimezone(
            timezone.utc
        )
        if to_date is not None
        else None
    )
    return lower, upper


def list_symptoms(
    session: Session,
    *,
    from_date: date | None,
    to_date: date | None,
    timezone_name: str | None,
    limit: int,
    offset: int,
) -> tuple[list[SymptomLog], int]:
    lower, upper = utc_date_boundaries(
        from_date=from_date, to_date=to_date, timezone_name=timezone_name
    )
    filters = []
    if lower is not None:
        filters.append(SymptomLog.recorded_at >= lower)
    if upper is not None:
        filters.append(SymptomLog.recorded_at < upper)

    total = session.scalar(select(func.count()).select_from(SymptomLog).where(*filters))
    items = list(
        session.scalars(
            select(SymptomLog)
            .where(*filters)
            .order_by(SymptomLog.recorded_at.desc(), SymptomLog.id.desc())
            .limit(limit)
            .offset(offset)
        )
    )
    return items, total or 0
