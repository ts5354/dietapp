from datetime import date, datetime, time, timedelta, timezone
from decimal import Decimal
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.db.models import FoodLog, InjectionRecord, NutritionDay, SymptomLog, WeightLog
from app.schemas.dashboard import (
    DashboardInjectionRecord,
    DashboardInjectionSection,
    DashboardNutritionRecord,
    DashboardNutritionSection,
    DashboardResponse,
    DashboardSymptomRecord,
    DashboardSymptomSection,
    DashboardWeightRecord,
    DashboardWeightSection,
)


class InvalidDashboardTimezoneError(Exception):
    pass


def _local_day_boundaries(
    dashboard_date: date, timezone_name: str
) -> tuple[datetime, datetime, str]:
    normalized_name = timezone_name.strip()
    if (
        not normalized_name
        or normalized_name == "JST"
        or normalized_name.startswith(("+", "-"))
    ):
        raise InvalidDashboardTimezoneError
    try:
        zone = ZoneInfo(normalized_name)
    except (ZoneInfoNotFoundError, ValueError) as error:
        raise InvalidDashboardTimezoneError from error

    lower = datetime.combine(dashboard_date, time.min, tzinfo=zone).astimezone(
        timezone.utc
    )
    upper = datetime.combine(
        dashboard_date + timedelta(days=1), time.min, tzinfo=zone
    ).astimezone(timezone.utc)
    return lower, upper, normalized_name


def _weight_section(session: Session, dashboard_date: date) -> DashboardWeightSection:
    weight = session.scalar(
        select(WeightLog)
        .where(WeightLog.record_date <= dashboard_date)
        .order_by(WeightLog.record_date.desc())
        .limit(1)
    )
    if weight is None:
        return DashboardWeightSection(status="UNRECORDED", record=None)
    return DashboardWeightSection(
        status="RECORDED",
        record=DashboardWeightRecord(
            record_date=weight.record_date, weight_kg=weight.weight_kg
        ),
    )


def _nutrition_section(
    session: Session, dashboard_date: date
) -> DashboardNutritionSection:
    day = session.scalar(
        select(NutritionDay).where(NutritionDay.date == dashboard_date)
    )
    if day is None:
        return DashboardNutritionSection(status="UNRECORDED", record=None)
    if day.mode == "FREE_DAY":
        return DashboardNutritionSection(
            status="RECORDED",
            record=DashboardNutritionRecord(
                mode="FREE_DAY", total_calories=None, total_protein_g=None
            ),
        )

    total_calories, total_protein = session.execute(
        select(
            func.coalesce(func.sum(FoodLog.calories), 0),
            func.coalesce(func.sum(FoodLog.protein_g), Decimal("0.0")),
        ).where(FoodLog.nutrition_day_id == day.id)
    ).one()
    return DashboardNutritionSection(
        status="RECORDED",
        record=DashboardNutritionRecord(
            mode="NORMAL",
            total_calories=total_calories,
            total_protein_g=total_protein,
        ),
    )


def _symptom_section(
    session: Session, lower: datetime, upper: datetime
) -> DashboardSymptomSection:
    symptom = session.scalar(
        select(SymptomLog)
        .where(SymptomLog.recorded_at >= lower, SymptomLog.recorded_at < upper)
        .order_by(SymptomLog.recorded_at.desc(), SymptomLog.id.desc())
        .limit(1)
    )
    if symptom is None:
        return DashboardSymptomSection(status="UNRECORDED", record=None)
    return DashboardSymptomSection(
        status="RECORDED",
        record=DashboardSymptomRecord(
            recorded_at=symptom.recorded_at,
            nausea=symptom.nausea,
            abdominal_pain=symptom.abdominal_pain,
            fatigue=symptom.fatigue,
            appetite=symptom.appetite,
            bowel_condition=symptom.bowel_condition,
        ),
    )


def _injection_section(
    session: Session, dashboard_date: date
) -> DashboardInjectionSection:
    injection = session.scalar(
        select(InjectionRecord)
        .where(InjectionRecord.record_date <= dashboard_date)
        .order_by(InjectionRecord.record_date.desc())
        .limit(1)
    )
    if injection is None:
        return DashboardInjectionSection(
            status="UNRECORDED", record=None, next_scheduled_date=None
        )
    return DashboardInjectionSection(
        status="RECORDED",
        record=DashboardInjectionRecord(record_date=injection.record_date),
        next_scheduled_date=injection.record_date + timedelta(days=7),
    )


def get_dashboard(
    session: Session, *, dashboard_date: date, timezone_name: str
) -> DashboardResponse:
    lower, upper, normalized_timezone = _local_day_boundaries(
        dashboard_date, timezone_name
    )
    return DashboardResponse(
        date=dashboard_date,
        timezone=normalized_timezone,
        weight=_weight_section(session, dashboard_date),
        nutrition=_nutrition_section(session, dashboard_date),
        symptom=_symptom_section(session, lower, upper),
        injection=_injection_section(session, dashboard_date),
    )
