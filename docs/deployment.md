# Production deployment

This document describes a provider-neutral production deployment for the dietapp
FastAPI backend and PostgreSQL database. Production and development databases
must be separate.

## Requirements

The hosting platform must provide:

- a container runtime with a public HTTPS endpoint;
- environment-variable or secret management;
- an isolated PostgreSQL database;
- a one-shot or manual command for Alembic migrations.

Do not commit production credentials, private database hostnames, API tokens, or
production `.env` files.

## Environment variables

Configure these in the provider's secret/environment settings:

| Name | Required | Description |
| --- | --- | --- |
| `DATABASE_URL` | Yes | `postgresql+psycopg://` URL for the production database |
| `PORT` | Usually | HTTP port assigned by the container platform; defaults to `8000` |

`DATABASE_URL` must reference the production database, never the development
Compose database. Providers that supply the standard `postgresql://` scheme are
accepted; the backend selects SQLAlchemy's installed psycopg 3 driver for that
scheme. Explicit driver schemes and non-PostgreSQL URLs are left unchanged. The
application does not print this value.

## Build and start

Build the backend image from the repository root:

```sh
docker build -t dietapp-backend ./backend
```

The image listens on `0.0.0.0`, uses the provider's `PORT`, and starts without
development reload:

```sh
uv run uvicorn app.main:app --host 0.0.0.0 --port "$PORT" --log-level info
```

TLS should terminate at the hosting platform or its managed proxy. Do not expose
PostgreSQL publicly merely to make the application reachable.

## Database migration

Run migrations as an explicit release or one-shot step before switching traffic:

```sh
uv run alembic upgrade head
uv run alembic current
```

The expected revision for this repository is `20260904_0001 (head)`. Migration
is intentionally not part of the application startup command, avoiding races
between multiple instances.

Before deployment, validate model and migration agreement against a disposable
PostgreSQL test database:

```sh
uv run alembic check
```

Rollback the application image independently where possible. Do not drop the
database, delete production volumes, rewrite migration history, or use
`alembic stamp` to conceal a failed deployment. Review any database downgrade
separately before running it against production data.

## Health check and smoke test

Configure the platform health probe to call:

```text
GET /health
```

It runs a lightweight `SELECT 1`. A reachable database returns HTTP 200 with:

```json
{"status":"ok"}
```

A database connection failure returns HTTP 503 without connection details.
After deployment, verify the public HTTPS endpoint:

```sh
curl --fail-with-body https://<production-host>/health
curl -i https://<production-host>/api/v1/weights/2099-01-01
```

The second request should return HTTP 404 with `WEIGHT_NOT_FOUND` when that date
has no record. Never place a URL containing database credentials in these
commands or application configuration.

## Flutter production connection

Keep the production URL outside source control and inject it at build/run time:

```sh
cd mobile
flutter run --dart-define=API_BASE_URL=https://<production-host>
```

Use the HTTPS origin without appending `/api/v1`; repositories already include
their `/api/v1/...` paths. Confirm Dashboard and Weight load from an iOS
Simulator or physical iPhone after deployment. Do not add an unrestricted iOS
ATS exception for an HTTP production endpoint.

## Development remains separate

Local development continues to use the root `docker-compose.yml` and its local
PostgreSQL volume. Production credentials and data must never be inserted into
that Compose file. Likewise, local Compose credentials must not be reused for
production.
