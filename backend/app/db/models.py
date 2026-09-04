from datetime import date, datetime, timezone
from decimal import Decimal

from sqlalchemy import (
    BigInteger,
    CheckConstraint,
    Date,
    DateTime,
    ForeignKey,
    Identity,
    Index,
    Integer,
    Numeric,
    SmallInteger,
    String,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


class TimestampMixin:
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=utc_now, nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=utc_now, onupdate=utc_now, nullable=False
    )


class NutritionDay(TimestampMixin, Base):
    __tablename__ = "nutrition_days"
    __table_args__ = (
        UniqueConstraint("date", name="uq_nutrition_days_date"),
        CheckConstraint(
            "mode IN ('NORMAL', 'FREE_DAY')", name="ck_nutrition_days_mode"
        ),
    )

    id: Mapped[int] = mapped_column(BigInteger, Identity(), primary_key=True)
    date: Mapped[date] = mapped_column(Date, nullable=False)
    mode: Mapped[str] = mapped_column(String, nullable=False)
    memo: Mapped[str | None] = mapped_column(String(500), nullable=True)


class FoodLog(TimestampMixin, Base):
    __tablename__ = "food_logs"
    __table_args__ = (
        CheckConstraint("calories >= 0", name="ck_food_logs_calories_nonnegative"),
        CheckConstraint("protein_g >= 0", name="ck_food_logs_protein_g_nonnegative"),
        Index("ix_food_logs_nutrition_day_eaten_at", "nutrition_day_id", "eaten_at"),
    )

    id: Mapped[int] = mapped_column(BigInteger, Identity(), primary_key=True)
    nutrition_day_id: Mapped[int] = mapped_column(
        BigInteger,
        ForeignKey(
            "nutrition_days.id",
            name="fk_food_logs_nutrition_day_id_nutrition_days",
            ondelete="CASCADE",
        ),
        nullable=False,
    )
    name: Mapped[str] = mapped_column(String(100), nullable=False)
    calories: Mapped[int] = mapped_column(Integer, nullable=False)
    protein_g: Mapped[Decimal] = mapped_column(Numeric(6, 2), nullable=False)
    eaten_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    memo: Mapped[str | None] = mapped_column(String(500), nullable=True)


class WeightLog(TimestampMixin, Base):
    __tablename__ = "weight_logs"
    __table_args__ = (
        UniqueConstraint("record_date", name="uq_weight_logs_record_date"),
        CheckConstraint("weight_kg > 0", name="ck_weight_logs_weight_kg_positive"),
        Index("ix_weight_logs_recorded_at", "recorded_at"),
    )

    id: Mapped[int] = mapped_column(BigInteger, Identity(), primary_key=True)
    record_date: Mapped[date] = mapped_column(Date, nullable=False)
    weight_kg: Mapped[Decimal] = mapped_column(Numeric(4, 1), nullable=False)
    recorded_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )
    memo: Mapped[str | None] = mapped_column(String(500), nullable=True)


class SymptomLog(TimestampMixin, Base):
    __tablename__ = "symptom_logs"
    __table_args__ = (
        CheckConstraint("nausea BETWEEN 1 AND 10", name="ck_symptom_logs_nausea_range"),
        CheckConstraint(
            "abdominal_pain BETWEEN 1 AND 10",
            name="ck_symptom_logs_abdominal_pain_range",
        ),
        CheckConstraint(
            "fatigue BETWEEN 1 AND 10", name="ck_symptom_logs_fatigue_range"
        ),
        CheckConstraint(
            "appetite BETWEEN 1 AND 10", name="ck_symptom_logs_appetite_range"
        ),
        CheckConstraint(
            "bowel_condition IS NULL OR bowel_condition IN "
            "('NORMAL', 'CONSTIPATION', 'DIARRHEA', 'OTHER')",
            name="ck_symptom_logs_bowel_condition",
        ),
        Index("ix_symptom_logs_recorded_at", "recorded_at"),
    )

    id: Mapped[int] = mapped_column(BigInteger, Identity(), primary_key=True)
    recorded_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )
    nausea: Mapped[int] = mapped_column(SmallInteger, nullable=False)
    abdominal_pain: Mapped[int] = mapped_column(SmallInteger, nullable=False)
    fatigue: Mapped[int] = mapped_column(SmallInteger, nullable=False)
    appetite: Mapped[int] = mapped_column(SmallInteger, nullable=False)
    bowel_condition: Mapped[str | None] = mapped_column(String, nullable=True)
    memo: Mapped[str | None] = mapped_column(String(500), nullable=True)


class InjectionRecord(TimestampMixin, Base):
    __tablename__ = "injection_records"
    __table_args__ = (
        UniqueConstraint("record_date", name="uq_injection_records_record_date"),
        CheckConstraint("dose_mg > 0", name="ck_injection_records_dose_mg_positive"),
        CheckConstraint(
            "injection_site IN "
            "('ABDOMEN_UPPER_RIGHT', 'ABDOMEN_LOWER_RIGHT', "
            "'ABDOMEN_UPPER_LEFT', 'ABDOMEN_LOWER_LEFT', "
            "'THIGH_RIGHT', 'THIGH_LEFT')",
            name="ck_injection_records_injection_site",
        ),
        Index("ix_injection_records_injected_at", "injected_at"),
    )

    id: Mapped[int] = mapped_column(BigInteger, Identity(), primary_key=True)
    record_date: Mapped[date] = mapped_column(Date, nullable=False)
    injected_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )
    dose_mg: Mapped[Decimal] = mapped_column(Numeric(5, 2), nullable=False)
    injection_site: Mapped[str] = mapped_column(String, nullable=False)
    memo: Mapped[str | None] = mapped_column(String(500), nullable=True)
