import pytest

from app.core.config import Settings, get_settings


@pytest.mark.parametrize(
    ("configured_url", "expected_url"),
    [
        (
            "postgresql://user:password@db.example.test:5432/dietapp",
            "postgresql+psycopg://user:password@db.example.test:5432/dietapp",
        ),
        (
            "postgresql+psycopg://user:password@db.example.test:5432/dietapp",
            "postgresql+psycopg://user:password@db.example.test:5432/dietapp",
        ),
        (
            "postgresql+asyncpg://user:password@db.example.test:5432/dietapp",
            "postgresql+asyncpg://user:password@db.example.test:5432/dietapp",
        ),
        ("sqlite:///local.db", "sqlite:///local.db"),
        (
            "mysql+pymysql://user:password@db.example.test/dietapp",
            "mysql+pymysql://user:password@db.example.test/dietapp",
        ),
    ],
)
def test_database_url_normalization(
    configured_url: str,
    expected_url: str,
) -> None:
    assert Settings(database_url=configured_url).database_url == expected_url


def test_database_url_environment_uses_psycopg3(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv(
        "DATABASE_URL", "postgresql://user:password@railway.internal:5432/dietapp"
    )
    get_settings.cache_clear()

    try:
        assert get_settings().database_url == (
            "postgresql+psycopg://user:password@railway.internal:5432/dietapp"
        )
    finally:
        get_settings.cache_clear()
