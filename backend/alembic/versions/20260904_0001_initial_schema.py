"""Create the initial MVP schema.

Revision ID: 20260904_0001
Revises:
Create Date: 2026-09-04
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "20260904_0001"
down_revision: str | None = None
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "nutrition_days",
        sa.Column("id", sa.BigInteger(), sa.Identity(), nullable=False),
        sa.Column("date", sa.Date(), nullable=False),
        sa.Column("mode", sa.String(), nullable=False),
        sa.Column("memo", sa.String(length=500), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint(
            "mode IN ('NORMAL', 'FREE_DAY')", name="ck_nutrition_days_mode"
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("date", name="uq_nutrition_days_date"),
    )

    op.create_table(
        "food_logs",
        sa.Column("id", sa.BigInteger(), sa.Identity(), nullable=False),
        sa.Column("nutrition_day_id", sa.BigInteger(), nullable=False),
        sa.Column("name", sa.String(length=100), nullable=False),
        sa.Column("calories", sa.Integer(), nullable=False),
        sa.Column("protein_g", sa.Numeric(precision=6, scale=2), nullable=False),
        sa.Column("eaten_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("memo", sa.String(length=500), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint("calories >= 0", name="ck_food_logs_calories_nonnegative"),
        sa.CheckConstraint("protein_g >= 0", name="ck_food_logs_protein_g_nonnegative"),
        sa.ForeignKeyConstraint(
            ["nutrition_day_id"],
            ["nutrition_days.id"],
            name="fk_food_logs_nutrition_day_id_nutrition_days",
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_food_logs_nutrition_day_eaten_at",
        "food_logs",
        ["nutrition_day_id", "eaten_at"],
    )

    op.create_table(
        "weight_logs",
        sa.Column("id", sa.BigInteger(), sa.Identity(), nullable=False),
        sa.Column("record_date", sa.Date(), nullable=False),
        sa.Column("weight_kg", sa.Numeric(precision=4, scale=1), nullable=False),
        sa.Column("recorded_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("memo", sa.String(length=500), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint("weight_kg > 0", name="ck_weight_logs_weight_kg_positive"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("record_date", name="uq_weight_logs_record_date"),
    )
    op.create_index("ix_weight_logs_recorded_at", "weight_logs", ["recorded_at"])

    op.create_table(
        "symptom_logs",
        sa.Column("id", sa.BigInteger(), sa.Identity(), nullable=False),
        sa.Column("recorded_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("nausea", sa.SmallInteger(), nullable=False),
        sa.Column("abdominal_pain", sa.SmallInteger(), nullable=False),
        sa.Column("fatigue", sa.SmallInteger(), nullable=False),
        sa.Column("appetite", sa.SmallInteger(), nullable=False),
        sa.Column("bowel_condition", sa.String(), nullable=True),
        sa.Column("memo", sa.String(length=500), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint(
            "nausea BETWEEN 1 AND 10", name="ck_symptom_logs_nausea_range"
        ),
        sa.CheckConstraint(
            "abdominal_pain BETWEEN 1 AND 10",
            name="ck_symptom_logs_abdominal_pain_range",
        ),
        sa.CheckConstraint(
            "fatigue BETWEEN 1 AND 10", name="ck_symptom_logs_fatigue_range"
        ),
        sa.CheckConstraint(
            "appetite BETWEEN 1 AND 10", name="ck_symptom_logs_appetite_range"
        ),
        sa.CheckConstraint(
            "bowel_condition IS NULL OR bowel_condition IN "
            "('NORMAL', 'CONSTIPATION', 'DIARRHEA', 'OTHER')",
            name="ck_symptom_logs_bowel_condition",
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_symptom_logs_recorded_at", "symptom_logs", ["recorded_at"])

    op.create_table(
        "injection_records",
        sa.Column("id", sa.BigInteger(), sa.Identity(), nullable=False),
        sa.Column("record_date", sa.Date(), nullable=False),
        sa.Column("injected_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("dose_mg", sa.Numeric(precision=5, scale=2), nullable=False),
        sa.Column("injection_site", sa.String(), nullable=False),
        sa.Column("memo", sa.String(length=500), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint("dose_mg > 0", name="ck_injection_records_dose_mg_positive"),
        sa.CheckConstraint(
            "injection_site IN "
            "('ABDOMEN_UPPER_RIGHT', 'ABDOMEN_LOWER_RIGHT', "
            "'ABDOMEN_UPPER_LEFT', 'ABDOMEN_LOWER_LEFT', "
            "'THIGH_RIGHT', 'THIGH_LEFT')",
            name="ck_injection_records_injection_site",
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("record_date", name="uq_injection_records_record_date"),
    )
    op.create_index(
        "ix_injection_records_injected_at", "injection_records", ["injected_at"]
    )


def downgrade() -> None:
    op.drop_index("ix_injection_records_injected_at", table_name="injection_records")
    op.drop_table("injection_records")
    op.drop_index("ix_symptom_logs_recorded_at", table_name="symptom_logs")
    op.drop_table("symptom_logs")
    op.drop_index("ix_weight_logs_recorded_at", table_name="weight_logs")
    op.drop_table("weight_logs")
    op.drop_index("ix_food_logs_nutrition_day_eaten_at", table_name="food_logs")
    op.drop_table("food_logs")
    op.drop_table("nutrition_days")
