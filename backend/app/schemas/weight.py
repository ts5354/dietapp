from datetime import date, datetime, timezone
from decimal import Decimal
from typing import Annotated

from pydantic import (
    BaseModel,
    ConfigDict,
    Field,
    PlainSerializer,
    field_serializer,
    field_validator,
)

WeightValue = Annotated[
    Decimal,
    Field(gt=0, max_digits=4, decimal_places=1),
    PlainSerializer(float, return_type=float, when_used="json"),
]


class WeightWriteBase(BaseModel):
    model_config = ConfigDict(extra="forbid")

    weight_kg: WeightValue
    recorded_at: datetime
    memo: str | None = Field(default=None, max_length=500)

    @field_validator("recorded_at")
    @classmethod
    def require_timezone(cls, value: datetime) -> datetime:
        if value.tzinfo is None or value.utcoffset() is None:
            raise ValueError("recorded_at must include a timezone offset")
        return value


class WeightCreate(WeightWriteBase):
    record_date: date


class WeightUpdate(WeightWriteBase):
    pass


class WeightResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    record_date: date
    weight_kg: WeightValue
    recorded_at: datetime
    memo: str | None
    created_at: datetime
    updated_at: datetime

    @field_serializer("recorded_at", "created_at", "updated_at")
    def serialize_utc(self, value: datetime) -> datetime:
        return value.astimezone(timezone.utc)


class WeightListResponse(BaseModel):
    items: list[WeightResponse]
    total: int
    limit: int
    offset: int
