from datetime import date, datetime, timezone
from decimal import Decimal
from typing import Annotated, Literal

from pydantic import BaseModel, PlainSerializer, field_serializer

JsonDecimal = Annotated[
    Decimal,
    PlainSerializer(float, return_type=float, when_used="json"),
]
SectionStatus = Literal["RECORDED", "UNRECORDED"]


class DashboardWeightRecord(BaseModel):
    record_date: date
    weight_kg: JsonDecimal


class DashboardWeightSection(BaseModel):
    status: SectionStatus
    record: DashboardWeightRecord | None


class DashboardNutritionRecord(BaseModel):
    mode: Literal["NORMAL", "FREE_DAY"]
    total_calories: int | None
    total_protein_g: JsonDecimal | None


class DashboardNutritionSection(BaseModel):
    status: SectionStatus
    record: DashboardNutritionRecord | None


class DashboardSymptomRecord(BaseModel):
    recorded_at: datetime
    nausea: int
    abdominal_pain: int
    fatigue: int
    appetite: int
    bowel_condition: Literal["NORMAL", "CONSTIPATION", "DIARRHEA", "OTHER"] | None

    @field_serializer("recorded_at")
    def serialize_utc(self, value: datetime) -> datetime:
        return value.astimezone(timezone.utc)


class DashboardSymptomSection(BaseModel):
    status: SectionStatus
    record: DashboardSymptomRecord | None


class DashboardInjectionRecord(BaseModel):
    record_date: date


class DashboardInjectionSection(BaseModel):
    status: SectionStatus
    record: DashboardInjectionRecord | None
    next_scheduled_date: date | None


class DashboardResponse(BaseModel):
    date: date
    timezone: str
    weight: DashboardWeightSection
    nutrition: DashboardNutritionSection
    symptom: DashboardSymptomSection
    injection: DashboardInjectionSection
