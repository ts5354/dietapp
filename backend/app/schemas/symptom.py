from datetime import datetime, timezone
from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field, field_serializer, field_validator

SymptomScale = Annotated[int, Field(strict=True, ge=1, le=10)]
BowelCondition = Literal["NORMAL", "CONSTIPATION", "DIARRHEA", "OTHER"]


class SymptomWrite(BaseModel):
    model_config = ConfigDict(extra="forbid")

    recorded_at: datetime
    nausea: SymptomScale
    abdominal_pain: SymptomScale
    fatigue: SymptomScale
    appetite: SymptomScale
    bowel_condition: BowelCondition | None = None
    memo: str | None = Field(default=None, max_length=500)

    @field_validator("recorded_at")
    @classmethod
    def require_timezone(cls, value: datetime) -> datetime:
        if value.tzinfo is None or value.utcoffset() is None:
            raise ValueError("recorded_at must include a timezone offset")
        return value


class SymptomCreate(SymptomWrite):
    pass


class SymptomUpdate(SymptomWrite):
    pass


class SymptomResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    recorded_at: datetime
    nausea: int
    abdominal_pain: int
    fatigue: int
    appetite: int
    bowel_condition: BowelCondition | None
    memo: str | None
    created_at: datetime
    updated_at: datetime

    @field_serializer("recorded_at", "created_at", "updated_at")
    def serialize_utc(self, value: datetime) -> datetime:
        return value.astimezone(timezone.utc)


class SymptomListResponse(BaseModel):
    items: list[SymptomResponse]
    total: int
    limit: int
    offset: int
