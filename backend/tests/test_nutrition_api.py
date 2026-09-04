from collections.abc import Iterator
from datetime import date

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import Engine, text
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from app.api.dependencies import get_session
from app.main import app
from app.schemas.nutrition import FoodCreate
from app.services.nutrition import create_food


@pytest.fixture
def client(migrated_database: Engine) -> Iterator[TestClient]:
    def override_session() -> Iterator[Session]:
        with Session(migrated_database) as session:
            yield session

    app.dependency_overrides[get_session] = override_session
    with migrated_database.begin() as connection:
        connection.execute(text("DELETE FROM food_logs"))
        connection.execute(text("DELETE FROM nutrition_days"))
    try:
        with TestClient(app) as test_client:
            yield test_client
    finally:
        app.dependency_overrides.pop(get_session, None)
        with migrated_database.begin() as connection:
            connection.execute(text("DELETE FROM food_logs"))
            connection.execute(text("DELETE FROM nutrition_days"))


def _food_payload(
    *,
    name: str = "Breakfast",
    calories: int = 350,
    protein_g: float = 20.0,
    eaten_at: str = "2026-09-04T08:30:00+09:00",
) -> dict[str, object]:
    return {
        "name": name,
        "calories": calories,
        "protein_g": protein_g,
        "eaten_at": eaten_at,
        "memo": None,
    }


def _set_day(
    client: TestClient, day: str, mode: str = "NORMAL", memo: str | None = None
) -> object:
    return client.put(
        f"/api/v1/nutrition/days/{day}", json={"mode": mode, "memo": memo}
    )


def _create_food(
    client: TestClient, day: str = "2026-09-04", **overrides: object
) -> object:
    payload = _food_payload(**overrides)
    return client.post(f"/api/v1/nutrition/days/{day}/foods", json=payload)


def _assert_error(response: object, status_code: int, code: str) -> None:
    assert response.status_code == status_code
    body = response.json()
    assert set(body) == {"error"}
    assert body["error"]["code"] == code
    assert isinstance(body["error"]["message"], str)
    assert "detail" not in body


def test_unrecorded_detail_is_virtual_and_does_not_create_row(
    client: TestClient, migrated_database: Engine
) -> None:
    response = client.get("/api/v1/nutrition/days/2026-09-04")

    assert response.status_code == 200
    assert response.json() == {
        "date": "2026-09-04",
        "mode": "UNRECORDED",
        "memo": None,
        "total_calories": None,
        "total_protein_g": None,
        "foods": [],
    }
    with migrated_database.connect() as connection:
        assert connection.scalar(text("SELECT count(*) FROM nutrition_days")) == 0


def test_normal_detail_aggregates_and_orders_food(client: TestClient) -> None:
    assert _set_day(client, "2026-09-04").status_code == 200
    later = _create_food(
        client,
        name="Lunch",
        calories=500,
        protein_g=25.5,
        eaten_at="2026-09-04T12:00:00+09:00",
    )
    earlier = _create_food(
        client,
        name="Breakfast",
        calories=300,
        protein_g=15.25,
        eaten_at="2026-09-04T08:00:00+09:00",
    )

    response = client.get("/api/v1/nutrition/days/2026-09-04")

    assert later.status_code == earlier.status_code == 201
    body = response.json()
    assert body["mode"] == "NORMAL"
    assert body["total_calories"] == 800
    assert body["total_protein_g"] == 40.75
    assert [food["name"] for food in body["foods"]] == ["Breakfast", "Lunch"]
    assert body["foods"][0]["eaten_at"] == "2026-09-03T23:00:00Z"
    assert isinstance(body["foods"][0]["protein_g"], float)


def test_empty_normal_and_free_day_have_distinct_totals(client: TestClient) -> None:
    normal = _set_day(client, "2026-09-04", "NORMAL")
    free_day = _set_day(client, "2026-09-05", "FREE_DAY")

    assert normal.json()["total_calories"] == 0
    assert normal.json()["total_protein_g"] == 0.0
    assert normal.json()["foods"] == []
    assert free_day.json()["total_calories"] is None
    assert free_day.json()["total_protein_g"] is None
    assert free_day.json()["foods"] == []


def test_day_state_transitions_and_same_mode_memo_update(client: TestClient) -> None:
    normal = _set_day(client, "2026-09-04", "NORMAL")
    free_day = _set_day(client, "2026-09-04", "FREE_DAY", "rest")
    same_mode = _set_day(client, "2026-09-04", "FREE_DAY", "updated")
    back_to_normal = _set_day(client, "2026-09-04", "NORMAL", None)
    new_free_day = _set_day(client, "2026-09-05", "FREE_DAY")

    assert normal.status_code == 200
    assert free_day.json()["mode"] == "FREE_DAY"
    assert same_mode.json()["memo"] == "updated"
    assert back_to_normal.json()["mode"] == "NORMAL"
    assert back_to_normal.json()["total_calories"] == 0
    assert new_free_day.json()["mode"] == "FREE_DAY"


def test_day_update_rejects_unrecorded_extra_and_long_memo(client: TestClient) -> None:
    for payload in [
        {"mode": "UNRECORDED", "memo": None},
        {"mode": "NORMAL", "memo": None, "id": 1},
        {"mode": "NORMAL", "memo": "x" * 501},
    ]:
        response = client.put("/api/v1/nutrition/days/2026-09-04", json=payload)
        _assert_error(response, 422, "VALIDATION_ERROR")


def test_day_with_food_cannot_become_free_day_and_remains_unchanged(
    client: TestClient,
) -> None:
    food = _create_food(client)
    assert food.status_code == 201

    response = _set_day(client, "2026-09-04", "FREE_DAY", "must not persist")

    _assert_error(response, 409, "FREE_DAY_HAS_FOOD_LOGS")
    detail = client.get("/api/v1/nutrition/days/2026-09-04").json()
    assert detail["mode"] == "NORMAL"
    assert detail["memo"] is None
    assert [item["id"] for item in detail["foods"]] == [food.json()["id"]]


def test_create_food_on_unrecorded_atomically_creates_normal_day(
    client: TestClient,
) -> None:
    response = _create_food(client)

    assert response.status_code == 201
    assert "nutrition_day_id" not in response.json()
    detail = client.get("/api/v1/nutrition/days/2026-09-04").json()
    assert detail["mode"] == "NORMAL"
    assert detail["total_calories"] == 350
    assert len(detail["foods"]) == 1


def test_free_day_rejects_food_and_remains_unchanged(client: TestClient) -> None:
    _set_day(client, "2026-09-04", "FREE_DAY", "intentional")

    response = _create_food(client)

    _assert_error(response, 409, "FOOD_NOT_ALLOWED_ON_FREE_DAY")
    detail = client.get("/api/v1/nutrition/days/2026-09-04").json()
    assert detail["mode"] == "FREE_DAY"
    assert detail["memo"] == "intentional"
    assert detail["foods"] == []


def test_food_date_uses_supplied_offset_before_utc_conversion(
    client: TestClient,
) -> None:
    valid = _create_food(
        client, eaten_at="2026-09-04T00:30:00+09:00", name="Midnight snack"
    )
    invalid = _create_food(
        client, eaten_at="2026-09-05T00:30:00+09:00", name="Wrong day"
    )

    assert valid.status_code == 201
    assert valid.json()["eaten_at"] == "2026-09-03T15:30:00Z"
    _assert_error(invalid, 422, "FOOD_DATE_MISMATCH")
    assert len(client.get("/api/v1/nutrition/days/2026-09-04").json()["foods"]) == 1


def test_failed_food_create_does_not_leave_automatic_normal_day(
    client: TestClient,
) -> None:
    response = _create_food(client, eaten_at="2026-09-05T08:30:00+09:00")

    _assert_error(response, 422, "FOOD_DATE_MISMATCH")
    assert (
        client.get("/api/v1/nutrition/days/2026-09-04").json()["mode"] == "UNRECORDED"
    )


def test_database_failure_rolls_back_automatic_normal_day(
    migrated_database: Engine,
) -> None:
    payload = FoodCreate.model_validate(
        _food_payload(calories=2**40, eaten_at="2026-09-06T08:30:00+09:00")
    )

    with Session(migrated_database) as session, pytest.raises(SQLAlchemyError):
        create_food(session, date.fromisoformat("2026-09-06"), payload)

    with migrated_database.connect() as connection:
        remaining = connection.scalar(
            text("SELECT count(*) FROM nutrition_days WHERE date = '2026-09-06'")
        )
        assert remaining == 0


@pytest.mark.parametrize(
    "overrides",
    [
        {"eaten_at": "2026-09-04T08:30:00"},
        {"calories": -1},
        {"protein_g": -0.01},
        {"name": ""},
        {"name": "   "},
        {"name": "x" * 101},
        {"id": 1},
        {"nutrition_day_id": 1},
    ],
)
def test_invalid_food_create_uses_validation_contract(
    client: TestClient, overrides: dict[str, object]
) -> None:
    payload = {**_food_payload(), **overrides}
    response = client.post("/api/v1/nutrition/days/2026-09-04/foods", json=payload)

    _assert_error(response, 422, "VALIDATION_ERROR")


def test_food_update_changes_values_and_preserves_created_at(
    client: TestClient,
) -> None:
    created = _create_food(client).json()
    payload = _food_payload(
        name=" Updated breakfast ",
        calories=400,
        protein_g=21.25,
        eaten_at="2026-09-04T09:00:00+09:00",
    )

    response = client.put(
        f"/api/v1/nutrition/days/2026-09-04/foods/{created['id']}", json=payload
    )

    assert response.status_code == 200
    updated = response.json()
    assert updated["name"] == "Updated breakfast"
    assert updated["calories"] == 400
    assert updated["protein_g"] == 21.25
    assert updated["created_at"] == created["created_at"]
    assert updated["updated_at"] > created["updated_at"]


def test_food_update_rejects_missing_other_day_mismatch_and_extra(
    client: TestClient,
) -> None:
    food = _create_food(client).json()

    missing = client.put(
        "/api/v1/nutrition/days/2026-09-04/foods/999999", json=_food_payload()
    )
    other_day = client.put(
        f"/api/v1/nutrition/days/2026-09-05/foods/{food['id']}",
        json={
            **_food_payload(),
            "eaten_at": "2026-09-05T08:30:00+09:00",
        },
    )
    mismatch = client.put(
        f"/api/v1/nutrition/days/2026-09-04/foods/{food['id']}",
        json={
            **_food_payload(),
            "eaten_at": "2026-09-05T08:30:00+09:00",
        },
    )
    extra = client.put(
        f"/api/v1/nutrition/days/2026-09-04/foods/{food['id']}",
        json={**_food_payload(), "nutrition_day_id": 100},
    )

    _assert_error(missing, 404, "FOOD_NOT_FOUND")
    _assert_error(other_day, 404, "FOOD_NOT_FOUND")
    _assert_error(mismatch, 422, "FOOD_DATE_MISMATCH")
    _assert_error(extra, 422, "VALIDATION_ERROR")


def test_food_update_prioritizes_missing_over_date_mismatch(client: TestClient) -> None:
    payload = {
        **_food_payload(),
        "eaten_at": "2026-09-05T08:30:00+09:00",
    }

    response = client.put(
        "/api/v1/nutrition/days/2026-09-04/foods/999999", json=payload
    )

    _assert_error(response, 404, "FOOD_NOT_FOUND")


def test_food_delete_is_hard_delete_and_keeps_empty_normal_day(
    client: TestClient,
) -> None:
    food = _create_food(client).json()

    response = client.delete(f"/api/v1/nutrition/days/2026-09-04/foods/{food['id']}")

    assert response.status_code == 204
    assert response.content == b""
    detail = client.get("/api/v1/nutrition/days/2026-09-04").json()
    assert detail["mode"] == "NORMAL"
    assert detail["total_calories"] == 0
    assert detail["foods"] == []
    _assert_error(
        client.delete(f"/api/v1/nutrition/days/2026-09-04/foods/{food['id']}"),
        404,
        "FOOD_NOT_FOUND",
    )


def test_food_delete_rejects_food_from_other_day(client: TestClient) -> None:
    food = _create_food(client).json()

    response = client.delete(f"/api/v1/nutrition/days/2026-09-05/foods/{food['id']}")

    _assert_error(response, 404, "FOOD_NOT_FOUND")
    assert len(client.get("/api/v1/nutrition/days/2026-09-04").json()["foods"]) == 1


def test_history_contains_persisted_days_with_totals_filters_and_pagination(
    client: TestClient,
) -> None:
    _create_food(
        client,
        day="2026-09-01",
        calories=100,
        protein_g=10.5,
        eaten_at="2026-09-01T08:00:00+09:00",
    )
    _set_day(client, "2026-09-02", "FREE_DAY")
    _set_day(client, "2026-09-03", "NORMAL")
    client.get("/api/v1/nutrition/days/2026-09-04")

    default = client.get("/api/v1/nutrition/days").json()
    assert default["limit"] == 50
    assert default["offset"] == 0
    assert default["total"] == 3
    assert [item["date"] for item in default["items"]] == [
        "2026-09-03",
        "2026-09-02",
        "2026-09-01",
    ]
    assert default["items"][0]["total_calories"] == 0
    assert default["items"][1]["total_calories"] is None
    assert default["items"][2]["total_calories"] == 100
    assert default["items"][2]["total_protein_g"] == 10.5
    assert all("foods" not in item for item in default["items"])

    filtered = client.get(
        "/api/v1/nutrition/days?from=2026-09-01&to=2026-09-03&limit=1&offset=1"
    ).json()
    assert filtered["total"] == 3
    assert filtered["limit"] == 1
    assert filtered["offset"] == 1
    assert [item["date"] for item in filtered["items"]] == ["2026-09-02"]


@pytest.mark.parametrize(
    "query",
    [
        "limit=0",
        "limit=101",
        "offset=-1",
        "from=invalid",
        "to=invalid",
        "from=2026-09-05&to=2026-09-04",
    ],
)
def test_history_invalid_query_uses_validation_contract(
    client: TestClient, query: str
) -> None:
    response = client.get(f"/api/v1/nutrition/days?{query}")

    _assert_error(response, 422, "VALIDATION_ERROR")
