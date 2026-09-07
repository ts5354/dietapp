from collections.abc import Iterator
from datetime import date, datetime, timezone
from decimal import Decimal

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import Engine, func, select, text
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from app.api.dependencies import get_session
from app.db.models import FoodLog, InjectionRecord, NutritionDay, SymptomLog, WeightLog
from app.main import app
from app.services import dashboard as dashboard_service


@pytest.fixture
def client(migrated_database: Engine) -> Iterator[TestClient]:
    def override_session() -> Iterator[Session]:
        with Session(migrated_database) as session:
            yield session

    app.dependency_overrides[get_session] = override_session
    with migrated_database.begin() as connection:
        connection.execute(text("DELETE FROM food_logs"))
        connection.execute(text("DELETE FROM nutrition_days"))
        connection.execute(text("DELETE FROM weight_logs"))
        connection.execute(text("DELETE FROM symptom_logs"))
        connection.execute(text("DELETE FROM injection_records"))
    try:
        with TestClient(app) as test_client:
            yield test_client
    finally:
        app.dependency_overrides.pop(get_session, None)
        with migrated_database.begin() as connection:
            connection.execute(text("DELETE FROM food_logs"))
            connection.execute(text("DELETE FROM nutrition_days"))
            connection.execute(text("DELETE FROM weight_logs"))
            connection.execute(text("DELETE FROM symptom_logs"))
            connection.execute(text("DELETE FROM injection_records"))


def _get(client: TestClient, day: str = "2026-09-07", zone: str = "Asia/Tokyo"):
    return client.get("/api/v1/dashboard", params={"date": day, "timezone": zone})


def _assert_error(response: object) -> None:
    assert response.status_code == 422
    body = response.json()
    assert set(body) == {"error"}
    assert body["error"]["code"] == "VALIDATION_ERROR"
    assert "detail" not in body


def _weight(session: Session, day: date, value: str = "65.5") -> WeightLog:
    row = WeightLog(
        record_date=day,
        weight_kg=Decimal(value),
        recorded_at=datetime.combine(day, datetime.min.time(), tzinfo=timezone.utc),
        memo=None,
    )
    session.add(row)
    session.flush()
    return row


def _nutrition(session: Session, day: date, mode: str = "NORMAL") -> NutritionDay:
    row = NutritionDay(date=day, mode=mode, memo=None)
    session.add(row)
    session.flush()
    return row


def _food(
    session: Session,
    nutrition_day_id: int,
    *,
    calories: int,
    protein: str,
) -> FoodLog:
    row = FoodLog(
        nutrition_day_id=nutrition_day_id,
        name="food",
        calories=calories,
        protein_g=Decimal(protein),
        eaten_at=datetime(2026, 9, 7, 3, tzinfo=timezone.utc),
        memo=None,
    )
    session.add(row)
    session.flush()
    return row


def _symptom(
    session: Session,
    recorded_at: datetime,
    *,
    nausea: int = 2,
    bowel_condition: str | None = "NORMAL",
) -> SymptomLog:
    row = SymptomLog(
        recorded_at=recorded_at,
        nausea=nausea,
        abdominal_pain=1,
        fatigue=4,
        appetite=6,
        bowel_condition=bowel_condition,
        memo="not exposed",
    )
    session.add(row)
    session.flush()
    return row


def _injection(session: Session, day: date) -> InjectionRecord:
    row = InjectionRecord(
        record_date=day,
        injected_at=datetime.combine(day, datetime.min.time(), tzinfo=timezone.utc),
        dose_mg=Decimal("2.5"),
        injection_site="THIGH_LEFT",
        memo="not exposed",
    )
    session.add(row)
    session.flush()
    return row


def test_all_unrecorded_response_has_every_section(client: TestClient) -> None:
    response = _get(client)

    assert response.status_code == 200
    body = response.json()
    assert body["date"] == "2026-09-07"
    assert body["timezone"] == "Asia/Tokyo"
    assert set(body) == {
        "date",
        "timezone",
        "weight",
        "nutrition",
        "symptom",
        "injection",
    }
    for name in ("weight", "nutrition", "symptom"):
        assert body[name] == {"status": "UNRECORDED", "record": None}
    assert body["injection"] == {
        "status": "UNRECORDED",
        "record": None,
        "next_scheduled_date": None,
    }


def test_weight_selects_latest_not_after_snapshot_and_is_lightweight(
    client: TestClient, migrated_database: Engine
) -> None:
    with Session(migrated_database) as session:
        _weight(session, date(2026, 9, 3), "66.0")
        _weight(session, date(2026, 9, 5), "65.5")
        _weight(session, date(2026, 9, 8), "64.0")
        session.commit()

    section = _get(client).json()["weight"]

    assert section == {
        "status": "RECORDED",
        "record": {"record_date": "2026-09-05", "weight_kg": 65.5},
    }
    assert isinstance(section["record"]["weight_kg"], float)


def test_weight_accepts_snapshot_day_and_has_unrecorded_before_first(
    client: TestClient, migrated_database: Engine
) -> None:
    with Session(migrated_database) as session:
        _weight(session, date(2026, 9, 7))
        session.commit()

    assert _get(client).json()["weight"]["status"] == "RECORDED"
    assert _get(client, "2026-09-06").json()["weight"]["status"] == "UNRECORDED"


def test_normal_nutrition_sums_food_and_omits_food_list(
    client: TestClient, migrated_database: Engine
) -> None:
    with Session(migrated_database) as session:
        day = _nutrition(session, date(2026, 9, 7))
        _food(session, day.id, calories=300, protein="12.25")
        _food(session, day.id, calories=450, protein="20.50")
        session.commit()

    section = _get(client).json()["nutrition"]

    assert section == {
        "status": "RECORDED",
        "record": {
            "mode": "NORMAL",
            "total_calories": 750,
            "total_protein_g": 32.75,
        },
    }
    assert isinstance(section["record"]["total_protein_g"], float)
    assert "foods" not in section["record"]


def test_empty_normal_has_zero_totals(
    client: TestClient, migrated_database: Engine
) -> None:
    with Session(migrated_database) as session:
        _nutrition(session, date(2026, 9, 7))
        session.commit()

    record = _get(client).json()["nutrition"]["record"]

    assert record == {"mode": "NORMAL", "total_calories": 0, "total_protein_g": 0.0}


def test_free_day_has_null_totals(
    client: TestClient, migrated_database: Engine
) -> None:
    with Session(migrated_database) as session:
        _nutrition(session, date(2026, 9, 7), "FREE_DAY")
        session.commit()

    assert _get(client).json()["nutrition"] == {
        "status": "RECORDED",
        "record": {
            "mode": "FREE_DAY",
            "total_calories": None,
            "total_protein_g": None,
        },
    }


def test_nutrition_does_not_backfill_previous_day(
    client: TestClient, migrated_database: Engine
) -> None:
    with Session(migrated_database) as session:
        _nutrition(session, date(2026, 9, 6))
        session.commit()

    assert _get(client).json()["nutrition"] == {"status": "UNRECORDED", "record": None}


def test_symptom_selects_latest_with_id_tie_breaker_and_utc_response(
    client: TestClient, migrated_database: Engine
) -> None:
    with Session(migrated_database) as session:
        _symptom(
            session, datetime(2026, 9, 6, 14, 59, 59, tzinfo=timezone.utc), nausea=1
        )
        _symptom(session, datetime(2026, 9, 7, 3, 30, tzinfo=timezone.utc), nausea=2)
        tied = _symptom(
            session,
            datetime(2026, 9, 7, 14, 59, 59, tzinfo=timezone.utc),
            nausea=8,
            bowel_condition=None,
        )
        winner = _symptom(
            session,
            datetime(2026, 9, 7, 14, 59, 59, tzinfo=timezone.utc),
            nausea=9,
            bowel_condition=None,
        )
        tied_id = tied.id
        winner_id = winner.id
        _symptom(session, datetime(2026, 9, 7, 15, tzinfo=timezone.utc), nausea=10)
        session.commit()

    section = _get(client).json()["symptom"]

    assert winner_id > tied_id
    assert section == {
        "status": "RECORDED",
        "record": {
            "recorded_at": "2026-09-07T14:59:59Z",
            "nausea": 9,
            "abdominal_pain": 1,
            "fatigue": 4,
            "appetite": 6,
            "bowel_condition": None,
        },
    }


def test_symptom_does_not_backfill_previous_local_day(
    client: TestClient, migrated_database: Engine
) -> None:
    with Session(migrated_database) as session:
        _symptom(session, datetime(2026, 9, 6, 14, 59, 59, tzinfo=timezone.utc))
        session.commit()

    assert _get(client).json()["symptom"] == {"status": "UNRECORDED", "record": None}


@pytest.mark.parametrize(
    ("day", "lower", "inside", "upper"),
    [
        (
            "2026-03-08",
            datetime(2026, 3, 8, 5, tzinfo=timezone.utc),
            datetime(2026, 3, 9, 3, 59, 59, tzinfo=timezone.utc),
            datetime(2026, 3, 9, 4, tzinfo=timezone.utc),
        ),
        (
            "2026-11-01",
            datetime(2026, 11, 1, 4, tzinfo=timezone.utc),
            datetime(2026, 11, 2, 4, 59, 59, tzinfo=timezone.utc),
            datetime(2026, 11, 2, 5, tzinfo=timezone.utc),
        ),
    ],
)
def test_symptom_dst_boundaries_use_local_midnights(
    client: TestClient,
    migrated_database: Engine,
    day: str,
    lower: datetime,
    inside: datetime,
    upper: datetime,
) -> None:
    with Session(migrated_database) as session:
        _symptom(session, lower, nausea=2)
        _symptom(session, inside, nausea=8)
        _symptom(session, upper, nausea=10)
        session.commit()

    section = _get(client, day, "America/New_York").json()["symptom"]

    assert section["status"] == "RECORDED"
    assert section["record"]["nausea"] == 8


def test_injection_snapshot_and_derived_date_ignore_future_record(
    client: TestClient, migrated_database: Engine
) -> None:
    with Session(migrated_database) as session:
        _injection(session, date(2026, 8, 20))
        _injection(session, date(2026, 9, 1))
        _injection(session, date(2026, 9, 8))
        session.commit()

    section = _get(client).json()["injection"]

    assert section == {
        "status": "RECORDED",
        "record": {"record_date": "2026-09-01"},
        "next_scheduled_date": "2026-09-08",
    }
    assert set(section["record"]) == {"record_date"}


@pytest.mark.parametrize(
    ("record_day", "expected"),
    [(date(2026, 1, 28), "2026-02-04"), (date(2026, 12, 28), "2027-01-04")],
)
def test_injection_calendar_day_addition_crosses_boundaries(
    client: TestClient,
    migrated_database: Engine,
    record_day: date,
    expected: str,
) -> None:
    with Session(migrated_database) as session:
        _injection(session, record_day)
        session.commit()

    section = _get(client, record_day.isoformat()).json()["injection"]

    assert section["record"]["record_date"] == record_day.isoformat()
    assert section["next_scheduled_date"] == expected


def test_integrated_snapshot_changes_with_dashboard_date(
    client: TestClient, migrated_database: Engine
) -> None:
    with Session(migrated_database) as session:
        _weight(session, date(2026, 9, 5), "66.0")
        _weight(session, date(2026, 9, 8), "65.0")
        day = _nutrition(session, date(2026, 9, 7))
        _food(session, day.id, calories=500, protein="30.0")
        _symptom(session, datetime(2026, 9, 7, 3, tzinfo=timezone.utc))
        _injection(session, date(2026, 9, 1))
        _injection(session, date(2026, 9, 8))
        session.commit()

    past = _get(client, "2026-09-07").json()
    future = _get(client, "2026-09-08").json()

    assert all(
        past[name]["status"] == "RECORDED"
        for name in past
        if name in {"weight", "nutrition", "symptom", "injection"}
    )
    assert past["weight"]["record"]["record_date"] == "2026-09-05"
    assert past["injection"]["record"]["record_date"] == "2026-09-01"
    assert future["weight"]["record"]["record_date"] == "2026-09-08"
    assert future["injection"]["record"]["record_date"] == "2026-09-08"
    assert future["nutrition"]["status"] == "UNRECORDED"
    assert future["symptom"]["status"] == "UNRECORDED"


@pytest.mark.parametrize(
    "zone",
    ["Invalid/Zone", "JST", "+09:00", "-05:00", "", "   "],
)
def test_invalid_timezone_returns_validation_error(
    client: TestClient, zone: str
) -> None:
    _assert_error(_get(client, zone=zone))


def test_valid_timezones_and_trimmed_response(client: TestClient) -> None:
    assert _get(client, zone="  Asia/Tokyo  ").json()["timezone"] == "Asia/Tokyo"
    assert _get(client, zone="America/New_York").status_code == 200
    assert _get(client, zone="Europe/London").status_code == 200


@pytest.mark.parametrize(
    "params",
    [
        {"timezone": "Asia/Tokyo"},
        {"date": "invalid", "timezone": "Asia/Tokyo"},
        {"date": "2026-02-30", "timezone": "Asia/Tokyo"},
        {"date": "2026-09-07"},
    ],
)
def test_required_and_date_validation_use_common_error(
    client: TestClient, params: dict[str, str]
) -> None:
    _assert_error(client.get("/api/v1/dashboard", params=params))


def test_get_has_no_side_effects_or_commit(
    client: TestClient, migrated_database: Engine, monkeypatch: pytest.MonkeyPatch
) -> None:
    with Session(migrated_database) as session:
        _weight(session, date(2026, 9, 7))
        counts_before = {
            model.__tablename__: session.scalar(select(func.count()).select_from(model))
            for model in (WeightLog, NutritionDay, FoodLog, SymptomLog, InjectionRecord)
        }
        session.commit()

    monkeypatch.setattr(Session, "commit", lambda *_: pytest.fail("GET committed"))
    assert _get(client).status_code == 200

    with Session(migrated_database) as session:
        counts_after = {
            model.__tablename__: session.scalar(select(func.count()).select_from(model))
            for model in (WeightLog, NutritionDay, FoodLog, SymptomLog, InjectionRecord)
        }
    assert counts_after == counts_before


def test_database_error_is_not_hidden_as_unrecorded(
    client: TestClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(
        dashboard_service,
        "_weight_section",
        lambda *_: (_ for _ in ()).throw(SQLAlchemyError("forced")),
    )

    with pytest.raises(SQLAlchemyError):
        _get(client)
