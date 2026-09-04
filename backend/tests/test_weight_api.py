from collections.abc import Iterator

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import Engine, text
from sqlalchemy.orm import Session

from app.api.dependencies import get_session
from app.main import app


@pytest.fixture
def client(migrated_database: Engine) -> Iterator[TestClient]:
    def override_session() -> Iterator[Session]:
        with Session(migrated_database) as session:
            yield session

    app.dependency_overrides[get_session] = override_session
    with migrated_database.begin() as connection:
        connection.execute(text("DELETE FROM weight_logs"))
    try:
        with TestClient(app) as test_client:
            yield test_client
    finally:
        app.dependency_overrides.pop(get_session, None)
        with migrated_database.begin() as connection:
            connection.execute(text("DELETE FROM weight_logs"))


def _weight_payload(
    record_date: str = "2026-09-04", weight_kg: float = 65.5
) -> dict[str, object]:
    return {
        "record_date": record_date,
        "weight_kg": weight_kg,
        "recorded_at": f"{record_date}T08:30:00+09:00",
        "memo": "morning",
    }


def _assert_error(response: object, status_code: int, code: str) -> None:
    assert response.status_code == status_code
    body = response.json()
    assert set(body) == {"error"}
    assert body["error"]["code"] == code
    assert isinstance(body["error"]["message"], str)
    assert "detail" not in body


def test_create_weight_returns_managed_fields_and_normalized_values(
    client: TestClient,
) -> None:
    response = client.post("/api/v1/weights", json=_weight_payload())

    assert response.status_code == 201
    body = response.json()
    assert isinstance(body["id"], int)
    assert body["record_date"] == "2026-09-04"
    assert body["weight_kg"] == 65.5
    assert isinstance(body["weight_kg"], float)
    assert body["recorded_at"] == "2026-09-03T23:30:00Z"
    assert body["created_at"].endswith("Z")
    assert body["updated_at"].endswith("Z")


def test_duplicate_weight_returns_domain_conflict(client: TestClient) -> None:
    assert client.post("/api/v1/weights", json=_weight_payload()).status_code == 201

    response = client.post("/api/v1/weights", json=_weight_payload(weight_kg=66.0))

    _assert_error(response, 409, "WEIGHT_ALREADY_EXISTS")


@pytest.mark.parametrize(
    ("payload", "field"),
    [
        (_weight_payload(weight_kg=0), "weight_kg"),
        ({**_weight_payload(), "recorded_at": "2026-09-04T08:30:00"}, "recorded_at"),
        ({**_weight_payload(), "memo": "x" * 501}, "memo"),
        ({**_weight_payload(), "id": 10}, "id"),
    ],
)
def test_invalid_create_uses_public_validation_contract(
    client: TestClient, payload: dict[str, object], field: str
) -> None:
    response = client.post("/api/v1/weights", json=payload)

    _assert_error(response, 422, "VALIDATION_ERROR")
    details = response.json()["error"]["details"]
    assert any(item["field"] == field for item in details)
    assert all(set(item) == {"field", "message"} for item in details)


def test_malformed_json_does_not_expose_fastapi_validation_payload(
    client: TestClient,
) -> None:
    response = client.post(
        "/api/v1/weights",
        content="{not-json",
        headers={"content-type": "application/json"},
    )

    _assert_error(response, 422, "VALIDATION_ERROR")


def test_get_existing_and_missing_weight(client: TestClient) -> None:
    client.post("/api/v1/weights", json=_weight_payload())

    found = client.get("/api/v1/weights/2026-09-04")
    missing = client.get("/api/v1/weights/2026-09-05")

    assert found.status_code == 200
    assert found.json()["record_date"] == "2026-09-04"
    _assert_error(missing, 404, "WEIGHT_NOT_FOUND")


def test_invalid_path_date_uses_public_validation_contract(client: TestClient) -> None:
    response = client.get("/api/v1/weights/not-a-date")

    _assert_error(response, 422, "VALIDATION_ERROR")
    assert response.json()["error"]["details"][0]["field"] == "record_date"


def test_update_changes_values_and_preserves_creation_time(client: TestClient) -> None:
    created = client.post("/api/v1/weights", json=_weight_payload()).json()
    update_payload = {
        "weight_kg": 65.3,
        "recorded_at": "2026-09-04T08:35:00+09:00",
        "memo": "corrected",
    }

    response = client.put("/api/v1/weights/2026-09-04", json=update_payload)

    assert response.status_code == 200
    updated = response.json()
    assert updated["weight_kg"] == 65.3
    assert updated["recorded_at"] == "2026-09-03T23:35:00Z"
    assert updated["memo"] == "corrected"
    assert updated["created_at"] == created["created_at"]
    assert updated["updated_at"] > created["updated_at"]
    assert client.get("/api/v1/weights/2026-09-04").json()["weight_kg"] == 65.3


def test_update_missing_weight_is_not_an_upsert(client: TestClient) -> None:
    payload = {
        "weight_kg": 65.3,
        "recorded_at": "2026-09-04T08:35:00+09:00",
        "memo": None,
    }

    response = client.put("/api/v1/weights/2026-09-04", json=payload)

    _assert_error(response, 404, "WEIGHT_NOT_FOUND")
    assert client.get("/api/v1/weights").json()["total"] == 0


def test_update_rejects_record_date_in_body(client: TestClient) -> None:
    client.post("/api/v1/weights", json=_weight_payload())
    payload = {
        "record_date": "2026-09-05",
        "weight_kg": 65.3,
        "recorded_at": "2026-09-04T08:35:00+09:00",
        "memo": None,
    }

    response = client.put("/api/v1/weights/2026-09-04", json=payload)

    _assert_error(response, 422, "VALIDATION_ERROR")


def test_delete_is_hard_delete_and_missing_returns_not_found(
    client: TestClient,
) -> None:
    client.post("/api/v1/weights", json=_weight_payload())

    deleted = client.delete("/api/v1/weights/2026-09-04")
    missing = client.delete("/api/v1/weights/2026-09-04")

    assert deleted.status_code == 204
    assert deleted.content == b""
    _assert_error(missing, 404, "WEIGHT_NOT_FOUND")
    _assert_error(client.get("/api/v1/weights/2026-09-04"), 404, "WEIGHT_NOT_FOUND")


def test_history_filters_orders_and_paginates(client: TestClient) -> None:
    for day, weight in [
        ("2026-09-01", 65.1),
        ("2026-09-02", 65.2),
        ("2026-09-03", 65.3),
        ("2026-09-04", 65.4),
    ]:
        assert (
            client.post(
                "/api/v1/weights", json=_weight_payload(day, weight)
            ).status_code
            == 201
        )

    default_response = client.get("/api/v1/weights").json()
    assert default_response["limit"] == 50
    assert default_response["offset"] == 0
    assert [item["record_date"] for item in default_response["items"]] == [
        "2026-09-04",
        "2026-09-03",
        "2026-09-02",
        "2026-09-01",
    ]

    response = client.get(
        "/api/v1/weights?from=2026-09-02&to=2026-09-04&limit=1&offset=1"
    )
    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 3
    assert body["limit"] == 1
    assert body["offset"] == 1
    assert [item["record_date"] for item in body["items"]] == ["2026-09-03"]


@pytest.mark.parametrize(
    "query",
    [
        "from=2026-09-05&to=2026-09-04",
        "limit=0",
        "limit=101",
        "offset=-1",
        "from=invalid",
    ],
)
def test_history_invalid_queries_use_validation_contract(
    client: TestClient, query: str
) -> None:
    response = client.get(f"/api/v1/weights?{query}")

    _assert_error(response, 422, "VALIDATION_ERROR")
