# dietapp

A mobile-first health logging application. Implementation is driven one step at a time by the specifications in [`specs/`](specs/).

## Project structure

- `backend/`: FastAPI, SQLAlchemy, and Alembic
- `mobile/`: Flutter application
- `docs/`: canonical design documentation
- `specs/`: implementation specifications
- `docker-compose.yml`: PostgreSQL and backend development services

## Prerequisites

- Docker with Docker Compose
- Python 3.10+ and [uv](https://docs.astral.sh/uv/) for host-side backend development
- Flutter SDK with Dart 3.3+ for mobile development

## Backend development

```sh
cd backend
cp .env.example .env
uv sync --dev
uv run uvicorn app.main:app --reload
```

Run formatting, linting, and tests:

```sh
cd backend
uv run ruff format .
uv run ruff check .
uv run pytest
```

## Flutter development

```sh
cd mobile
flutter pub get
flutter run
```

Run formatting, analysis, and tests:

```sh
cd mobile
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

The API base URL is required at build/run time and is injected with
`API_BASE_URL`:

```sh
flutter run --dart-define=API_BASE_URL=http://localhost:8000
```

## Docker Compose

Start PostgreSQL and the FastAPI development server:

```sh
docker compose up --build
```

Once healthy, verify the API:

```sh
curl http://localhost:8000/health
```

The expected response is `{"status":"ok"}`. Development database credentials in Compose are local defaults, not production secrets.

Production deployment, migration, health-check, and Flutter HTTPS connection
procedures are documented in [`docs/deployment.md`](docs/deployment.md).
