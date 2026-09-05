from collections.abc import Iterator

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import Engine, text
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from app.api.dependencies import get_session
from app.main import app
from app.schemas.symptom import SymptomCreate
from app.services.symptom import create_symptom


@pytest.fixture
def client(migrated_database: Engine) -> Iterator[TestClient]:
    def override_session() -> Iterator[Session]:
        with Session(migrated_database) as session:
            yield session

    app.dependency_overrides[get_session] = override_session
    with migrated_database.begin() as connection:
        connection.execute(text("DELETE FROM symptom_logs"))
    try:
        with TestClient(app) as test_client:
            yield test_client
    finally:
        app.dependency_overrides.pop(get_session, None)
        with migrated_database.begin() as connection:
            connection.execute(text("DELETE FROM symptom_logs"))


def _payload(
    *,
    recorded_at: str = "2026-09-05T09:30:00+09:00",
    nausea: int = 3,
    abdominal_pain: int = 1,
    fatigue: int = 6,
    appetite: int = 4,
    bowel_condition: str | None = "NORMAL",
    memo: str | None = "morning",
) -> dict[str, object]:
    return {
        "recorded_at": recorded_at,
        "nausea": nausea,
        "abdominal_pain": abdominal_pain,
        "fatigue": fatigue,
        "appetite": appetite,
        "bowel_condition": bowel_condition,
        "memo": memo,
    }


def _create(client: TestClient, **overrides: object) -> object:
    return client.post("/api/v1/symptoms", json=_payload(**overrides))


def _assert_error(response: object, status_code: int, code: str) -> None:
    assert response.status_code == status_code
    body = response.json()
    assert set(body) == {"error"}
    assert body["error"]["code"] == code
    assert isinstance(body["error"]["message"], str)
    assert "detail" not in body


def test_create_returns_managed_fields_and_utc_timestamp(client: TestClient) -> None:
    response = _create(client)

    assert response.status_code == 201
    body = response.json()
    assert isinstance(body["id"], int)
    assert body["recorded_at"] == "2026-09-05T00:30:00Z"
    assert body["created_at"].endswith("Z")
    assert body["updated_at"].endswith("Z")
    assert set(body) == {
        "id",
        "recorded_at",
        "nausea",
        "abdominal_pain",
        "fatigue",
        "appetite",
        "bowel_condition",
        "memo",
        "created_at",
        "updated_at",
    }


def test_create_allows_same_day_and_same_timestamp(client: TestClient) -> None:
    first = _create(client)
    second = _create(client)

    assert first.status_code == second.status_code == 201
    assert first.json()["id"] != second.json()["id"]
    assert first.json()["recorded_at"] == second.json()["recorded_at"]


def test_create_defaults_optional_fields_to_null(client: TestClient) -> None:
    payload = _payload()
    payload.pop("bowel_condition")
    payload.pop("memo")

    response = client.post("/api/v1/symptoms", json=payload)

    assert response.status_code == 201
    assert response.json()["bowel_condition"] is None
    assert response.json()["memo"] is None


def test_create_allows_future_recorded_at(client: TestClient) -> None:
    response = _create(client, recorded_at="2099-01-01T00:00:00Z")

    assert response.status_code == 201
    assert response.json()["recorded_at"] == "2099-01-01T00:00:00Z"


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("nausea", 0),
        ("nausea", 11),
        ("abdominal_pain", 0),
        ("abdominal_pain", 11),
        ("fatigue", 0),
        ("fatigue", 11),
        ("appetite", 0),
        ("appetite", 11),
        ("nausea", 3.5),
    ],
)
def test_create_rejects_invalid_scale(
    client: TestClient, field: str, value: object
) -> None:
    response = client.post("/api/v1/symptoms", json={**_payload(), field: value})

    _assert_error(response, 422, "VALIDATION_ERROR")


@pytest.mark.parametrize(
    "payload",
    [
        {key: value for key, value in _payload().items() if key != "nausea"},
        {**_payload(), "bowel_condition": "INVALID"},
        {**_payload(), "bowel_condition": ""},
        {**_payload(), "bowel_condition": "   "},
        {**_payload(), "recorded_at": "2026-09-05T09:30:00"},
        {**_payload(), "memo": "x" * 501},
        {**_payload(), "id": 1},
        {**_payload(), "created_at": "2026-09-05T00:00:00Z"},
    ],
)
def test_create_rejects_invalid_payload(
    client: TestClient, payload: dict[str, object]
) -> None:
    response = client.post("/api/v1/symptoms", json=payload)

    _assert_error(response, 422, "VALIDATION_ERROR")


def test_get_existing_and_missing(client: TestClient) -> None:
    symptom_id = _create(client).json()["id"]

    found = client.get(f"/api/v1/symptoms/{symptom_id}")
    missing = client.get("/api/v1/symptoms/999999")

    assert found.status_code == 200
    assert found.json()["id"] == symptom_id
    _assert_error(missing, 404, "SYMPTOM_NOT_FOUND")


def test_update_all_fields_and_preserve_created_at(client: TestClient) -> None:
    created = _create(client).json()
    payload = _payload(
        recorded_at="2026-09-06T18:00:00-04:00",
        nausea=10,
        abdominal_pain=9,
        fatigue=8,
        appetite=7,
        bowel_condition="DIARRHEA",
        memo="updated",
    )

    response = client.put(f"/api/v1/symptoms/{created['id']}", json=payload)

    assert response.status_code == 200
    updated = response.json()
    assert updated["recorded_at"] == "2026-09-06T22:00:00Z"
    assert updated["nausea"] == 10
    assert updated["abdominal_pain"] == 9
    assert updated["fatigue"] == 8
    assert updated["appetite"] == 7
    assert updated["bowel_condition"] == "DIARRHEA"
    assert updated["memo"] == "updated"
    assert updated["created_at"] == created["created_at"]
    assert updated["updated_at"] > created["updated_at"]


def test_update_omitted_optional_fields_to_null(client: TestClient) -> None:
    symptom_id = _create(client).json()["id"]
    payload = _payload()
    payload.pop("bowel_condition")
    payload.pop("memo")

    response = client.put(f"/api/v1/symptoms/{symptom_id}", json=payload)

    assert response.status_code == 200
    assert response.json()["bowel_condition"] is None
    assert response.json()["memo"] is None


def test_update_missing_is_not_upsert_and_invalid_payload_is_rejected(
    client: TestClient,
) -> None:
    missing = client.put("/api/v1/symptoms/999999", json=_payload())
    invalid = client.put("/api/v1/symptoms/999999", json={**_payload(), "fatigue": 0})

    _assert_error(missing, 404, "SYMPTOM_NOT_FOUND")
    _assert_error(invalid, 422, "VALIDATION_ERROR")
    assert client.get("/api/v1/symptoms").json()["total"] == 0


def test_delete_is_hard_delete(client: TestClient) -> None:
    symptom_id = _create(client).json()["id"]

    deleted = client.delete(f"/api/v1/symptoms/{symptom_id}")
    missing_get = client.get(f"/api/v1/symptoms/{symptom_id}")
    missing_delete = client.delete("/api/v1/symptoms/999999")

    assert deleted.status_code == 204
    assert deleted.content == b""
    _assert_error(missing_get, 404, "SYMPTOM_NOT_FOUND")
    _assert_error(missing_delete, 404, "SYMPTOM_NOT_FOUND")


def test_history_orders_with_id_tie_breaker_and_paginates(client: TestClient) -> None:
    oldest = _create(client, recorded_at="2026-09-01T00:00:00Z").json()
    tied_first = _create(client, recorded_at="2026-09-02T00:00:00Z").json()
    tied_second = _create(client, recorded_at="2026-09-02T00:00:00Z").json()

    default = client.get("/api/v1/symptoms").json()
    assert default["limit"] == 50
    assert default["offset"] == 0
    assert [item["id"] for item in default["items"]] == [
        tied_second["id"],
        tied_first["id"],
        oldest["id"],
    ]

    paged = client.get("/api/v1/symptoms?limit=1&offset=1").json()
    assert paged["total"] == 3
    assert paged["limit"] == 1
    assert paged["offset"] == 1
    assert [item["id"] for item in paged["items"]] == [tied_first["id"]]


@pytest.mark.parametrize("query", ["limit=0", "limit=101", "offset=-1"])
def test_history_rejects_invalid_pagination(client: TestClient, query: str) -> None:
    response = client.get(f"/api/v1/symptoms?{query}")

    _assert_error(response, 422, "VALIDATION_ERROR")


def test_history_filters_local_calendar_date_in_timezone(client: TestClient) -> None:
    before = _create(client, recorded_at="2026-09-04T14:59:59Z").json()
    first = _create(client, recorded_at="2026-09-04T15:00:00Z").json()
    last = _create(client, recorded_at="2026-09-05T14:59:59Z").json()
    after = _create(client, recorded_at="2026-09-05T15:00:00Z").json()

    response = client.get(
        "/api/v1/symptoms?from=2026-09-05&to=2026-09-05&timezone=Asia%2FTokyo"
    )

    assert response.status_code == 200
    assert response.json()["total"] == 2
    assert [item["id"] for item in response.json()["items"]] == [
        last["id"],
        first["id"],
    ]
    assert before["id"] not in [item["id"] for item in response.json()["items"]]
    assert after["id"] not in [item["id"] for item in response.json()["items"]]


def test_history_supports_from_only_and_to_only(client: TestClient) -> None:
    _create(client, recorded_at="2026-09-04T12:00:00Z")
    _create(client, recorded_at="2026-09-05T12:00:00Z")
    _create(client, recorded_at="2026-09-06T12:00:00Z")

    from_response = client.get("/api/v1/symptoms?from=2026-09-05&timezone=UTC").json()
    to_response = client.get("/api/v1/symptoms?to=2026-09-05&timezone=UTC").json()

    assert from_response["total"] == 2
    assert to_response["total"] == 2


@pytest.mark.parametrize(
    "query",
    [
        "from=2026-09-05",
        "to=2026-09-05",
        "timezone=Asia%2FTokyo",
        "from=2026-09-06&to=2026-09-05&timezone=UTC",
        "from=invalid&timezone=UTC",
        "from=2026-09-05&timezone=Invalid%2FZone",
        "from=2026-09-05&timezone=JST",
        "from=2026-09-05&timezone=%2B09%3A00",
    ],
)
def test_history_rejects_invalid_date_timezone_contract(
    client: TestClient, query: str
) -> None:
    response = client.get(f"/api/v1/symptoms?{query}")

    _assert_error(response, 422, "VALIDATION_ERROR")


@pytest.mark.parametrize(
    ("day", "lower", "inside", "upper"),
    [
        (
            "2026-03-08",
            "2026-03-08T05:00:00Z",
            "2026-03-09T03:59:59Z",
            "2026-03-09T04:00:00Z",
        ),
        (
            "2026-11-01",
            "2026-11-01T04:00:00Z",
            "2026-11-02T04:30:00Z",
            "2026-11-02T05:00:00Z",
        ),
    ],
)
def test_history_handles_dst_calendar_day_boundaries(
    client: TestClient, day: str, lower: str, inside: str, upper: str
) -> None:
    lower_id = _create(client, recorded_at=lower).json()["id"]
    inside_id = _create(client, recorded_at=inside).json()["id"]
    upper_id = _create(client, recorded_at=upper).json()["id"]

    response = client.get(
        f"/api/v1/symptoms?from={day}&to={day}&timezone=America%2FNew_York"
    )

    assert response.status_code == 200
    assert response.json()["total"] == 2
    assert [item["id"] for item in response.json()["items"]] == [
        inside_id,
        lower_id,
    ]
    assert upper_id not in [item["id"] for item in response.json()["items"]]


def test_database_failure_rolls_back_and_next_request_succeeds(
    client: TestClient, migrated_database: Engine, monkeypatch: pytest.MonkeyPatch
) -> None:
    payload = SymptomCreate.model_validate(_payload(memo="must roll back"))
    with Session(migrated_database) as session:
        monkeypatch.setattr(
            session, "commit", lambda: (_ for _ in ()).throw(SQLAlchemyError("forced"))
        )
        with pytest.raises(SQLAlchemyError):
            create_symptom(session, payload)

    with migrated_database.connect() as connection:
        assert connection.scalar(text("SELECT count(*) FROM symptom_logs")) == 0

    response = _create(client, memo="after failure")
    assert response.status_code == 201
