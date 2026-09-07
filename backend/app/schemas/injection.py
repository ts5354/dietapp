from datetime import date, datetime, timezone
from decimal import Decimal
from typing import Annotated, Literal

from pydantic import (
    BaseModel,
    BeforeValidator,
    ConfigDict,
    Field,
    PlainSerializer,
    field_serializer,
    field_validator,
)

InjectionSite = Annotated[
    Literal[
        "ABDOMEN_UPPER_RIGHT",
        "ABDOMEN_LOWER_RIGHT",
        "ABDOMEN_UPPER_LEFT",
        "ABDOMEN_LOWER_LEFT",
        "THIGH_RIGHT",
        "THIGH_LEFT",
    ],
    BeforeValidator(lambda value: value.strip() if isinstance(value, str) else value),
]


def require_numeric_dose(value: object) -> object:
    if type(value) not in (int, float, Decimal):
        raise ValueError("dose_mg must be a JSON number")
    return value


DoseValue = Annotated[
    Decimal,
    Field(gt=0, max_digits=5, decimal_places=2),
    BeforeValidator(require_numeric_dose),
    PlainSerializer(float, return_type=float, when_used="json"),
]


class InjectionWrite(BaseModel):
    model_config = ConfigDict(extra="forbid")

    injected_at: datetime
    dose_mg: DoseValue
    injection_site: InjectionSite
    memo: str | None = Field(default=None, max_length=500)

    @field_validator("injected_at")
    @classmethod
    def require_timezone(cls, value: datetime) -> datetime:
        if value.tzinfo is None or value.utcoffset() is None:
            raise ValueError("injected_at must include a timezone offset")
        return value


class InjectionCreate(InjectionWrite):
    record_date: date


class InjectionUpdate(InjectionWrite):
    pass


class InjectionResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    record_date: date
    injected_at: datetime
    dose_mg: DoseValue
    injection_site: InjectionSite
    memo: str | None
    created_at: datetime
    updated_at: datetime

    @field_serializer("injected_at", "created_at", "updated_at")
    def serialize_utc(self, value: datetime) -> datetime:
        return value.astimezone(timezone.utc)


class InjectionListResponse(BaseModel):
    items: list[InjectionResponse]
    total: int
    limit: int
    offset: int
