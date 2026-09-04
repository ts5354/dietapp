# Spec: Repository Bootstrap

## Status

Ready for implementation.

## Goal

Initialize the monorepo structure and development environment for the MVP health logging application.

This spec is only for repository/bootstrap setup. Do not implement product features or database tables yet.

---

## 1. Source of Truth

Before implementation, read:

1. `AGENTS.md`
2. `docs/database-design.md`
3. `specs/001-initial-database-migration.md`

Follow `AGENTS.md` if this spec does not explicitly override something.

---

## 2. Target Repository Structure

Create or normalize the repository to:

```text
dietapp/
├── AGENTS.md
├── README.md
├── .gitignore
├── docker-compose.yml
├── docs/
│   └── database-design.md
├── specs/
│   ├── 000-repository-bootstrap.md
│   └── 001-initial-database-migration.md
├── backend/
└── mobile/
```

Do not rename or move the existing documentation/specification files unless needed to match this structure.

---

## 3. Backend Bootstrap

Create a FastAPI backend under `backend/`.

Target stack:

- Python
- FastAPI
- SQLAlchemy 2.x
- Alembic
- Pydantic
- PostgreSQL
- pytest
- uv

Create a minimal, maintainable structure such as:

```text
backend/
├── pyproject.toml
├── alembic.ini
├── alembic/
│   ├── env.py
│   ├── script.py.mako
│   └── versions/
├── app/
│   ├── __init__.py
│   ├── main.py
│   ├── core/
│   │   ├── __init__.py
│   │   └── config.py
│   └── db/
│       ├── __init__.py
│       ├── base.py
│       └── session.py
└── tests/
    ├── __init__.py
    └── test_health.py
```

Equivalent structure is acceptable if it clearly preserves separation of concerns and follows `AGENTS.md`.

### Required backend behavior

Implement only:

```http
GET /api/v1/health
```

Response:

```json
{
  "status": "ok"
}
```

Do not create product CRUD endpoints yet.

### Configuration

Use environment-based configuration.

Expected database variables may be represented through a single:

```text
DATABASE_URL
```

or equivalent structured settings.

Do not hard-code credentials in source files.

Provide an example environment file such as:

```text
backend/.env.example
```

Do not commit real secrets.

### SQLAlchemy

Initialize SQLAlchemy 2.x infrastructure so later specs can add models.

Do not create the five product tables in this bootstrap spec.

### Alembic

Initialize Alembic and connect it to the backend metadata/configuration.

Do not generate the initial product schema migration in this bootstrap spec. That belongs to `specs/001-initial-database-migration.md`.

---

## 4. Flutter Bootstrap

Create a Flutter app under `mobile/`.

Use the existing local Flutter installation.

Target technologies:

- Flutter
- Dart
- Riverpod
- GoRouter
- Dio
- Freezed where useful later
- fl_chart later

For bootstrap, add only dependencies needed for the minimal app/navigation/API foundation.

Do not add dependencies only because they may be useful in future specs.

### Minimal app

Create a minimal app that:

- launches successfully
- has a basic app shell
- is ready for GoRouter-based navigation
- is ready for Riverpod-based state management
- has a simple placeholder home screen

Do not implement weight, food, symptom, injection, history, or settings features yet.

### Networking foundation

Create a minimal Dio client abstraction/configuration suitable for future API calls.

Do not implement production networking behavior or domain API clients yet.

---

## 5. Docker Compose

Create root:

```text
docker-compose.yml
```

It should provide development services for:

- PostgreSQL
- FastAPI backend

Flutter runs on the host and is not containerized.

### PostgreSQL

Use a current stable PostgreSQL image compatible with the project.

Configure:

- database name
- username
- password
- persistent named volume
- healthcheck

Development credentials may be defined through Docker Compose environment defaults or an example env file, but must not be treated as production secrets.

### Backend service

Build/run the FastAPI backend.

Requirements:

- depends on healthy PostgreSQL
- exposes the API to the host
- supports local development
- uses the same database URL convention as the backend configuration

Avoid adding Nginx or other unnecessary infrastructure.

---

## 6. README

Create or update root `README.md` with concise development instructions.

Include:

- project structure
- prerequisites
- backend setup
- Flutter setup
- Docker Compose startup
- health endpoint test
- how to run backend tests
- how to run Flutter analysis/tests
- note that feature implementation is spec-driven under `specs/`

Do not document features that are not implemented.

---

## 7. Git Ignore

Create or update `.gitignore`.

Include appropriate exclusions for:

- Python caches and virtual environments
- `.env` files, while keeping `.env.example`
- Flutter/Dart generated local/build files
- IDE/editor local files where appropriate
- OS metadata
- test caches
- build artifacts

Do not ignore source-controlled generated files that Flutter requires.

---

## 8. Quality Checks

Backend:

- formatting/linting configured in a simple way appropriate for the project
- pytest works
- health endpoint test passes

Flutter:

- `dart format` passes
- `flutter analyze` passes
- default/minimal tests pass

Docker:

- `docker compose config` succeeds
- if Docker is available, verify PostgreSQL and backend can start and health endpoint responds

If a required local tool is unavailable, report it rather than silently skipping without explanation.

---

## 9. Out of Scope

Do not implement:

- database product tables
- initial Alembic product migration
- authentication
- user accounts
- CRUD for product records
- dashboard
- weight UI
- food UI
- symptom UI
- injection UI
- history UI
- settings UI
- notifications
- water logging
- food search
- barcode scanning
- AI analysis
- cloud deployment

Those belong to later specs.

---

## 10. Acceptance Criteria

The bootstrap is complete when:

- repository structure matches the intended monorepo shape
- `backend/` is a runnable FastAPI project
- `GET /api/v1/health` returns `{"status":"ok"}`
- SQLAlchemy infrastructure exists but product tables do not
- Alembic is initialized but the product schema migration is not implemented
- `mobile/` is a runnable Flutter app
- Riverpod/GoRouter/Dio foundation is present as needed for the minimal app
- Docker Compose defines PostgreSQL and backend services
- README contains working local setup instructions
- `.gitignore` is appropriate
- backend tests pass
- Flutter analysis/tests pass
- no feature outside this spec was added

---

## 11. Codex Completion Report

After implementation, report:

1. changed/created files
2. important architecture decisions
3. commands executed
4. formatter/linter/test results
5. Docker verification result
6. anything not completed and why

Do not begin `001-initial-database-migration.md` automatically after finishing this spec.
