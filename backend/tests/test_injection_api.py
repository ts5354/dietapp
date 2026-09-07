from collections.abc import Iterator
from datetime import date

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import Engine, select, text
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from app.api.dependencies import get_session
from app.db.models import InjectionRecord
from app.main import app
from app.schemas.injection import InjectionCreate, InjectionUpdate
from app.services import injection as injection_service
from app.services.injection import InjectionAlreadyExistsError

SITES = [
    "ABDOMEN_UPPER_RIGHT",
    "ABDOMEN_LOWER_RIGHT",
    "ABDOMEN_UPPER_LEFT",
    "ABDOMEN_LOWER_LEFT",
    "THIGH_RIGHT",
    "THIGH_LEFT",
]


@pytest.fixture
def client(migrated_database: Engine) -> Iterator[TestClient]:
    def override_session() -> Iterator[Session]:
        with Session(migrated_database) as session:
            yield session

    app.dependency_overrides[get_session] = override_session
    with migrated_database.begin() as connection:
        connection.execute(text("DELETE FROM injection_records"))
    try:
        with TestClient(app) as test_client:
            yield test_client
    finally:
        app.dependency_overrides.pop(get_session, None)
        with migrated_database.begin() as connection:
            connection.execute(text("DELETE FROM injection_records"))


def _payload(
    *,
    record_date: str = "2026-09-05",
    injected_at: str = "2026-09-05T09:30:00+09:00",
    dose_mg: object = 2.5,
    injection_site: str = "ABDOMEN_UPPER_RIGHT",
    memo: str | None = "weekly record",
) -> dict[str, object]:
    return {
        "record_date": record_date,
        "injected_at": injected_at,
        "dose_mg": dose_mg,
        "injection_site": injection_site,
        "memo": memo,
    }


def _update_payload(**overrides: object) -> dict[str, object]:
    payload = _payload(**overrides)
    payload.pop("record_date")
    return payload


def _create(client: TestClient, **overrides: object):
    return client.post("/api/v1/injections", json=_payload(**overrides))


def _assert_error(response: object, status_code: int, code: str) -> None:
    assert response.status_code == status_code
    body = response.json()
    assert set(body) == {"error"}
    assert body["error"]["code"] == code
    assert isinstance(body["error"]["message"], str)
    assert "detail" not in body


def test_create_returns_complete_response_with_utc_and_numeric_dose(
    client: TestClient,
) -> None:
    response = _create(client, injection_site="  THIGH_LEFT  ")

    assert response.status_code == 201
    body = response.json()
    assert body["record_date"] == "2026-09-05"
    assert body["injected_at"] == "2026-09-05T00:30:00Z"
    assert body["dose_mg"] == 2.5
    assert isinstance(body["dose_mg"], float)
    assert body["injection_site"] == "THIGH_LEFT"
    assert body["created_at"].endswith("Z")
    assert body["updated_at"].endswith("Z")
    assert set(body) == {
        "id",
        "record_date",
        "injected_at",
        "dose_mg",
        "injection_site",
        "memo",
        "created_at",
        "updated_at",
    }


def test_create_defaults_memo_to_null_and_allows_future(client: TestClient) -> None:
    payload = _payload(record_date="2099-01-01", injected_at="2099-01-01T12:00:00Z")
    payload.pop("memo")

    response = client.post("/api/v1/injections", json=payload)

    assert response.status_code == 201
    assert response.json()["memo"] is None


def test_duplicate_conflict_does_not_overwrite_existing(client: TestClient) -> None:
    original = _create(client).json()
    duplicate = _create(client, dose_mg=7.5, memo="replacement")

    _assert_error(duplicate, 409, "INJECTION_ALREADY_EXISTS")
    found = client.get("/api/v1/injections/2026-09-05").json()
    assert found["id"] == original["id"]
    assert found["dose_mg"] == original["dose_mg"]
    assert found["memo"] == original["memo"]


def test_create_date_mismatch_uses_input_offset_and_precedes_duplicate(
    client: TestClient,
) -> None:
    standalone = _create(
        client,
        record_date="2026-09-04",
        injected_at="2026-09-05T00:30:00+09:00",
    )
    _assert_error(standalone, 422, "INJECTION_DATE_MISMATCH")

    _create(client)

    # This instant is Sep 5 UTC, but Sep 6 in the supplied +09:00 offset.
    mismatch = _create(client, injected_at="2026-09-06T00:30:00+09:00")

    _assert_error(mismatch, 422, "INJECTION_DATE_MISMATCH")


@pytest.mark.parametrize(
    "payload",
    [
        _payload(injected_at="2026-09-05T09:30:00"),
        _payload(dose_mg=0),
        _payload(dose_mg=-1),
        _payload(dose_mg=2.555),
        _payload(dose_mg=1000),
        _payload(injection_site="UNKNOWN"),
        _payload(injection_site=""),
        _payload(injection_site="   "),
        _payload(injection_site="thigh_left"),
        _payload(memo="x" * 501),
        {key: value for key, value in _payload().items() if key != "dose_mg"},
        {**_payload(), "next_injection_date": "2026-09-12"},
    ],
)
def test_create_rejects_invalid_payload(
    client: TestClient, payload: dict[str, object]
) -> None:
    _assert_error(
        client.post("/api/v1/injections", json=payload), 422, "VALIDATION_ERROR"
    )


@pytest.mark.parametrize("dose_mg", ["2.5", True, False])
@pytest.mark.parametrize("method", ["post", "put"])
def test_write_rejects_non_json_number_dose(
    client: TestClient, method: str, dose_mg: object
) -> None:
    if method == "post":
        response = client.post("/api/v1/injections", json=_payload(dose_mg=dose_mg))
    else:
        original = _create(client).json()
        response = client.put(
            "/api/v1/injections/2026-09-05",
            json=_update_payload(dose_mg=dose_mg),
        )

    _assert_error(response, 422, "VALIDATION_ERROR")
    if method == "put":
        assert (
            client.get("/api/v1/injections/2026-09-05").json()["dose_mg"]
            == original["dose_mg"]
        )


@pytest.mark.parametrize("site", SITES)
def test_create_accepts_every_site_and_exact_two_decimal_dose(
    client: TestClient, site: str
) -> None:
    day = 10 + SITES.index(site)
    response = _create(
        client,
        record_date=f"2026-09-{day}",
        injected_at=f"2026-09-{day}T01:00:00Z",
        dose_mg=2.55,
        injection_site=site,
    )

    assert response.status_code == 201
    assert response.json()["injection_site"] == site


def test_get_existing_missing_and_invalid_date(client: TestClient) -> None:
    created = _create(client).json()

    assert client.get("/api/v1/injections/2026-09-05").json()["id"] == created["id"]
    _assert_error(
        client.get("/api/v1/injections/2026-09-06"), 404, "INJECTION_NOT_FOUND"
    )
    _assert_error(client.get("/api/v1/injections/not-a-date"), 422, "VALIDATION_ERROR")


def test_update_replaces_editable_fields_and_preserves_identity(
    client: TestClient,
) -> None:
    created = _create(client).json()
    response = client.put(
        "/api/v1/injections/2026-09-05",
        json=_update_payload(
            injected_at="2026-09-05T23:00:00-04:00",
            dose_mg=9.75,
            injection_site=" THIGH_RIGHT ",
            memo="updated",
        ),
    )

    assert response.status_code == 200
    body = response.json()
    assert body["id"] == created["id"]
    assert body["record_date"] == created["record_date"]
    assert body["created_at"] == created["created_at"]
    assert body["updated_at"] > created["updated_at"]
    assert body["injected_at"] == "2026-09-06T03:00:00Z"
    assert body["dose_mg"] == 9.75
    assert body["injection_site"] == "THIGH_RIGHT"
    assert body["memo"] == "updated"


def test_update_omitted_memo_becomes_null(client: TestClient) -> None:
    _create(client)
    payload = _update_payload()
    payload.pop("memo")

    response = client.put("/api/v1/injections/2026-09-05", json=payload)

    assert response.status_code == 200
    assert response.json()["memo"] is None


def test_update_error_priority_and_schema_validation(client: TestClient) -> None:
    _create(client)
    mismatch = _update_payload(injected_at="2026-09-06T00:00:00+09:00")

    _assert_error(
        client.put("/api/v1/injections/2026-09-05", json=mismatch),
        422,
        "INJECTION_DATE_MISMATCH",
    )
    _assert_error(
        client.put(
            "/api/v1/injections/2026-09-06",
            json=_update_payload(injected_at="2026-09-06T09:30:00+09:00"),
        ),
        404,
        "INJECTION_NOT_FOUND",
    )
    _assert_error(
        client.put("/api/v1/injections/2026-09-07", json=mismatch),
        404,
        "INJECTION_NOT_FOUND",
    )
    _assert_error(
        client.put(
            "/api/v1/injections/2026-09-05",
            json={**_update_payload(), "record_date": "2026-09-05"},
        ),
        422,
        "VALIDATION_ERROR",
    )
    _assert_error(
        client.put(
            "/api/v1/injections/2026-09-06", json={**_update_payload(), "dose_mg": 0}
        ),
        422,
        "VALIDATION_ERROR",
    )
    assert client.get("/api/v1/injections").json()["total"] == 1


def test_delete_is_hard_delete_and_validates_path(client: TestClient) -> None:
    _create(client)

    deleted = client.delete("/api/v1/injections/2026-09-05")

    assert deleted.status_code == 204
    assert deleted.content == b""
    _assert_error(
        client.get("/api/v1/injections/2026-09-05"), 404, "INJECTION_NOT_FOUND"
    )
    _assert_error(
        client.delete("/api/v1/injections/2026-09-05"), 404, "INJECTION_NOT_FOUND"
    )
    _assert_error(
        client.delete("/api/v1/injections/not-a-date"), 422, "VALIDATION_ERROR"
    )


def test_history_orders_paginates_and_uses_id_tie_breaker(client: TestClient) -> None:
    oldest = _create(
        client, record_date="2026-09-01", injected_at="2026-09-01T00:00:00Z"
    ).json()
    tied_first = _create(
        client,
        record_date="2026-09-02",
        injected_at="2026-09-02T23:00:00-01:00",
    ).json()
    tied_second = _create(
        client, record_date="2026-09-03", injected_at="2026-09-03T09:00:00+09:00"
    ).json()

    default = client.get("/api/v1/injections").json()
    assert default["limit"] == 50
    assert default["offset"] == 0
    assert [item["id"] for item in default["items"]] == [
        tied_second["id"],
        tied_first["id"],
        oldest["id"],
    ]
    paged = client.get("/api/v1/injections?limit=1&offset=1").json()
    assert paged["total"] == 3
    assert paged["limit"] == 1
    assert paged["offset"] == 1
    assert [item["id"] for item in paged["items"]] == [tied_first["id"]]


def test_history_filters_inclusive_record_date_without_timezone(
    client: TestClient,
) -> None:
    _create(client, record_date="2026-09-04", injected_at="2026-09-04T23:30:00-10:00")
    inside = _create(
        client, record_date="2026-09-05", injected_at="2026-09-05T00:30:00+14:00"
    ).json()
    _create(client, record_date="2026-09-06", injected_at="2026-09-06T00:00:00Z")

    both = client.get("/api/v1/injections?from=2026-09-05&to=2026-09-05").json()
    from_only = client.get("/api/v1/injections?from=2026-09-05").json()
    to_only = client.get("/api/v1/injections?to=2026-09-05").json()

    assert both["total"] == 1
    assert both["items"][0]["id"] == inside["id"]
    assert from_only["total"] == 2
    assert to_only["total"] == 2


@pytest.mark.parametrize(
    "query",
    [
        "limit=0",
        "limit=101",
        "offset=-1",
        "from=invalid",
        "to=invalid",
        "from=2026-09-06&to=2026-09-05",
    ],
)
def test_history_rejects_invalid_query(client: TestClient, query: str) -> None:
    _assert_error(client.get(f"/api/v1/injections?{query}"), 422, "VALIDATION_ERROR")


def test_post_failure_rolls_back_and_next_request_succeeds(
    client: TestClient, migrated_database: Engine, monkeypatch: pytest.MonkeyPatch
) -> None:
    payload = InjectionCreate.model_validate(_payload(memo="must roll back"))
    with Session(migrated_database) as session:
        monkeypatch.setattr(
            session, "commit", lambda: (_ for _ in ()).throw(SQLAlchemyError("forced"))
        )
        with pytest.raises(SQLAlchemyError):
            injection_service.create_injection(session, payload)

    with migrated_database.connect() as connection:
        assert connection.scalar(text("SELECT count(*) FROM injection_records")) == 0
    assert _create(client, memo="after failure").status_code == 201


@pytest.mark.parametrize("operation", ["update", "delete"])
def test_write_failure_rolls_back(
    client: TestClient,
    migrated_database: Engine,
    monkeypatch: pytest.MonkeyPatch,
    operation: str,
) -> None:
    original = _create(client).json()
    with Session(migrated_database) as session:
        monkeypatch.setattr(
            session, "commit", lambda: (_ for _ in ()).throw(SQLAlchemyError("forced"))
        )
        with pytest.raises(SQLAlchemyError):
            if operation == "update":
                injection_service.update_injection(
                    session,
                    date(2026, 9, 5),
                    InjectionUpdate.model_validate(_update_payload(dose_mg=8.5)),
                )
            else:
                injection_service.delete_injection(session, date(2026, 9, 5))
        assert (
            session.scalar(
                select(InjectionRecord).where(
                    InjectionRecord.record_date == date(2026, 9, 5)
                )
            )
            is not None
        )

    found = client.get("/api/v1/injections/2026-09-05")
    assert found.status_code == 200
    assert found.json()["dose_mg"] == original["dose_mg"]


def test_unique_race_rolls_back_and_keeps_session_usable(
    client: TestClient, migrated_database: Engine, monkeypatch: pytest.MonkeyPatch
) -> None:
    _create(client)
    payload = InjectionCreate.model_validate(_payload(memo="race loser"))

    with Session(migrated_database) as session:
        with monkeypatch.context() as patch:
            patch.setattr(injection_service, "_find_by_date", lambda *_: None)
            with pytest.raises(InjectionAlreadyExistsError):
                injection_service.create_injection(session, payload)
        assert (
            session.scalar(
                select(InjectionRecord).where(
                    InjectionRecord.record_date == date(2026, 9, 5)
                )
            )
            is not None
        )

    assert (
        _create(
            client, record_date="2026-09-06", injected_at="2026-09-06T10:00:00Z"
        ).status_code
        == 201
    )
