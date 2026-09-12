FROM ghcr.io/astral-sh/uv:python3.12-bookworm-slim

WORKDIR /app

ENV UV_LINK_MODE=copy \
    UV_NO_DEV=1 \
    UV_PROJECT_ENVIRONMENT=/opt/venv

COPY pyproject.toml uv.lock ./
RUN uv sync --locked --no-install-project

COPY alembic.ini ./
COPY alembic ./alembic
COPY app ./app

CMD ["sh", "-c", "exec uv run uvicorn app.main:app --host 0.0.0.0 --port \"${PORT:-8000}\" --log-level info"]
