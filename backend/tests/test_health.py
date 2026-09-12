from fastapi.testclient import TestClient
from sqlalchemy.exc import OperationalError

from app.api.dependencies import get_session
from app.main import app

client = TestClient(app)


def test_health() -> None:
    class AvailableSession:
        def execute(self, _statement: object) -> None:
            return None

    app.dependency_overrides[get_session] = lambda: AvailableSession()
    response = client.get("/health")
    app.dependency_overrides.clear()

    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_health_reports_database_failure_without_internal_details() -> None:
    class UnavailableSession:
        def execute(self, _statement: object) -> None:
            raise OperationalError("SELECT 1", {}, ConnectionError("private-db:5432"))

    app.dependency_overrides[get_session] = lambda: UnavailableSession()
    response = client.get("/health")
    app.dependency_overrides.clear()

    assert response.status_code == 503
    assert response.json() == {
        "error": {
            "code": "SERVICE_UNAVAILABLE",
            "message": "The service is temporarily unavailable.",
        }
    }
    assert "private-db" not in response.text


def test_legacy_health_alias_has_the_same_database_check() -> None:
    class AvailableSession:
        def execute(self, _statement: object) -> None:
            return None

    app.dependency_overrides[get_session] = lambda: AvailableSession()
    response = client.get("/api/v1/health")
    app.dependency_overrides.clear()

    assert response.status_code == 200
    assert response.json() == {"status": "ok"}
