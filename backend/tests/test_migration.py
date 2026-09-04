from datetime import date, datetime, timezone
from decimal import Decimal

import pytest
from sqlalchemy import Engine, inspect, select, text
from sqlalchemy.exc import IntegrityError

TABLES = {
    "nutrition_days",
    "food_logs",
    "weight_logs",
    "symptom_logs",
    "injection_records",
}

NOW = datetime(2026, 9, 4, 12, 0, tzinfo=timezone.utc)


def _nutrition_day(**overrides: object) -> dict[str, object]:
    values: dict[str, object] = {
        "date": date(2026, 9, 1),
        "mode": "NORMAL",
        "memo": None,
        "created_at": NOW,
        "updated_at": NOW,
    }
    values.update(overrides)
    return values


def _food_log(nutrition_day_id: int, **overrides: object) -> dict[str, object]:
    values: dict[str, object] = {
        "nutrition_day_id": nutrition_day_id,
        "name": "Lunch",
        "calories": 500,
        "protein_g": Decimal("25.50"),
        "eaten_at": NOW,
        "memo": None,
        "created_at": NOW,
        "updated_at": NOW,
    }
    values.update(overrides)
    return values


def _weight_log(**overrides: object) -> dict[str, object]:
    values: dict[str, object] = {
        "record_date": date(2026, 9, 1),
        "weight_kg": Decimal("70.5"),
        "recorded_at": NOW,
        "memo": None,
        "created_at": NOW,
        "updated_at": NOW,
    }
    values.update(overrides)
    return values


def _symptom_log(**overrides: object) -> dict[str, object]:
    values: dict[str, object] = {
        "recorded_at": NOW,
        "nausea": 1,
        "abdominal_pain": 2,
        "fatigue": 3,
        "appetite": 4,
        "bowel_condition": "NORMAL",
        "memo": None,
        "created_at": NOW,
        "updated_at": NOW,
    }
    values.update(overrides)
    return values


def _injection_record(**overrides: object) -> dict[str, object]:
    values: dict[str, object] = {
        "record_date": date(2026, 9, 1),
        "injected_at": NOW,
        "dose_mg": Decimal("2.50"),
        "injection_site": "THIGH_RIGHT",
        "memo": None,
        "created_at": NOW,
        "updated_at": NOW,
    }
    values.update(overrides)
    return values


def _insert(connection: object, table: str, values: dict[str, object]) -> int:
    result = connection.execute(
        text(
            f"INSERT INTO {table} ({', '.join(values)}) "
            f"VALUES ({', '.join(f':{column}' for column in values)}) RETURNING id"
        ),
        values,
    )
    return result.scalar_one()


def test_schema_shape(migrated_database: Engine) -> None:
    inspector = inspect(migrated_database)

    assert TABLES <= set(inspector.get_table_names())
    for table in TABLES:
        columns = {column["name"]: column for column in inspector.get_columns(table)}
        assert str(columns["id"]["type"]) == "BIGINT"
        assert columns["id"]["identity"] is not None

    unique_constraints = {
        table: {
            constraint["name"] for constraint in inspector.get_unique_constraints(table)
        }
        for table in TABLES
    }
    assert "uq_nutrition_days_date" in unique_constraints["nutrition_days"]
    assert "uq_weight_logs_record_date" in unique_constraints["weight_logs"]
    assert "uq_injection_records_record_date" in unique_constraints["injection_records"]

    foreign_keys = inspector.get_foreign_keys("food_logs")
    assert foreign_keys == [
        {
            "name": "fk_food_logs_nutrition_day_id_nutrition_days",
            "constrained_columns": ["nutrition_day_id"],
            "referred_schema": None,
            "referred_table": "nutrition_days",
            "referred_columns": ["id"],
            "options": {"ondelete": "CASCADE"},
            "comment": None,
        }
    ]

    indexes = {
        table: {index["name"] for index in inspector.get_indexes(table)}
        for table in TABLES
    }
    assert "ix_food_logs_nutrition_day_eaten_at" in indexes["food_logs"]
    assert "ix_weight_logs_recorded_at" in indexes["weight_logs"]
    assert "ix_symptom_logs_recorded_at" in indexes["symptom_logs"]
    assert "ix_injection_records_injected_at" in indexes["injection_records"]


def test_valid_rows_and_food_log_cascade(migrated_database: Engine) -> None:
    with migrated_database.begin() as connection:
        nutrition_day_id = _insert(connection, "nutrition_days", _nutrition_day())
        food_log_id = _insert(connection, "food_logs", _food_log(nutrition_day_id))
        _insert(connection, "weight_logs", _weight_log())
        _insert(connection, "symptom_logs", _symptom_log())
        _insert(connection, "injection_records", _injection_record())

        connection.execute(
            text("DELETE FROM nutrition_days WHERE id = :id"),
            {"id": nutrition_day_id},
        )
        remaining = connection.scalar(
            select(text("count(*)"))
            .select_from(text("food_logs"))
            .where(text("id = :id")),
            {"id": food_log_id},
        )
        assert remaining == 0


@pytest.mark.parametrize(
    ("table", "first", "second"),
    [
        ("nutrition_days", _nutrition_day(), _nutrition_day(mode="FREE_DAY")),
        ("weight_logs", _weight_log(), _weight_log(weight_kg=Decimal("71.0"))),
        (
            "injection_records",
            _injection_record(),
            _injection_record(dose_mg=Decimal("5.00")),
        ),
    ],
)
def test_unique_constraints_reject_duplicates(
    migrated_database: Engine,
    table: str,
    first: dict[str, object],
    second: dict[str, object],
) -> None:
    with pytest.raises(IntegrityError), migrated_database.begin() as connection:
        _insert(connection, table, first)
        _insert(connection, table, second)


@pytest.mark.parametrize(
    ("table", "values"),
    [
        ("nutrition_days", _nutrition_day(mode="UNRECORDED")),
        ("weight_logs", _weight_log(weight_kg=Decimal("0"))),
        ("symptom_logs", _symptom_log(nausea=0)),
        ("symptom_logs", _symptom_log(abdominal_pain=11)),
        ("symptom_logs", _symptom_log(fatigue=0)),
        ("symptom_logs", _symptom_log(appetite=11)),
        ("symptom_logs", _symptom_log(bowel_condition="INVALID")),
        ("injection_records", _injection_record(dose_mg=Decimal("0"))),
        ("injection_records", _injection_record(injection_site="ARM_RIGHT")),
    ],
)
def test_check_constraints_reject_invalid_values(
    migrated_database: Engine, table: str, values: dict[str, object]
) -> None:
    with pytest.raises(IntegrityError), migrated_database.begin() as connection:
        _insert(connection, table, values)


@pytest.mark.parametrize(
    ("field", "value"),
    [("calories", -1), ("protein_g", Decimal("-0.01"))],
)
def test_food_check_constraints_reject_invalid_values(
    migrated_database: Engine, field: str, value: object
) -> None:
    with pytest.raises(IntegrityError), migrated_database.begin() as connection:
        nutrition_day_id = _insert(connection, "nutrition_days", _nutrition_day())
        _insert(connection, "food_logs", _food_log(nutrition_day_id, **{field: value}))


def test_food_log_foreign_key_rejects_missing_parent(
    migrated_database: Engine,
) -> None:
    with pytest.raises(IntegrityError), migrated_database.begin() as connection:
        _insert(connection, "food_logs", _food_log(999_999))
