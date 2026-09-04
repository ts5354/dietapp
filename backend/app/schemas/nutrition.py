from datetime import date, datetime, timezone
from decimal import Decimal
from typing import Annotated, Literal

from pydantic import (
    BaseModel,
    ConfigDict,
    Field,
    PlainSerializer,
    StringConstraints,
    field_serializer,
    field_validator,
)

NutritionMode = Literal["NORMAL", "FREE_DAY"]
NutritionResponseMode = Literal["NORMAL", "FREE_DAY", "UNRECORDED"]
ProteinValue = Annotated[
    Decimal,
    PlainSerializer(float, return_type=float, when_used="json"),
]
FoodProteinValue = Annotated[
    Decimal,
    Field(ge=0, max_digits=6, decimal_places=2),
    PlainSerializer(float, return_type=float, when_used="json"),
]
FoodName = Annotated[
    str,
    StringConstraints(strip_whitespace=True, min_length=1, max_length=100),
]


class NutritionDayUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    mode: NutritionMode
    memo: str | None = Field(default=None, max_length=500)


class FoodWrite(BaseModel):
    model_config = ConfigDict(extra="forbid")

    name: FoodName
    calories: int = Field(ge=0)
    protein_g: FoodProteinValue
    eaten_at: datetime
    memo: str | None = Field(default=None, max_length=500)

    @field_validator("eaten_at")
    @classmethod
    def require_timezone(cls, value: datetime) -> datetime:
        if value.tzinfo is None or value.utcoffset() is None:
            raise ValueError("eaten_at must include a timezone offset")
        return value


class FoodCreate(FoodWrite):
    pass


class FoodUpdate(FoodWrite):
    pass


class FoodResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    name: str
    calories: int
    protein_g: ProteinValue
    eaten_at: datetime
    memo: str | None
    created_at: datetime
    updated_at: datetime

    @field_serializer("eaten_at", "created_at", "updated_at")
    def serialize_utc(self, value: datetime) -> datetime:
        return value.astimezone(timezone.utc)


class NutritionDaySummary(BaseModel):
    date: date
    mode: NutritionResponseMode
    memo: str | None
    total_calories: int | None
    total_protein_g: ProteinValue | None


class NutritionDayDetail(NutritionDaySummary):
    foods: list[FoodResponse]


class NutritionDayListResponse(BaseModel):
    items: list[NutritionDaySummary]
    total: int
    limit: int
    offset: int
