# Spec 002: Common API Foundation + Weight API

## Status

Ready for implementation.

## Goal

Implement the shared REST API foundation defined in `docs/api-design.md` and the complete Weight API only.

This spec establishes reusable API conventions for later Nutrition/Food, Symptoms, and Injection specs without implementing those domains yet.

Do not implement future endpoints merely because they are already documented in `docs/api-design.md`.

---

## 1. Required Reading

Before implementation, read:

1. `AGENTS.md`
2. `docs/database-design.md`
3. `docs/api-design.md`
4. `specs/001-initial-database-migration.md`
5. existing backend code and tests

The active implementation scope is this file.

If this spec conflicts with `AGENTS.md` or `docs/api-design.md`, stop and report the conflict rather than silently choosing one.

---

## 2. Scope

Implement:

- reusable API error response structure
- reusable validation error handling
- common pagination request/response foundations where useful
- common date-range validation utilities where useful
- Weight request/response Pydantic schemas
- Weight application/service logic
- Weight routes
- Weight database queries
- Weight API tests
- any narrowly necessary backend refactoring to preserve separation of concerns

Weight endpoints:

```text
POST   /api/v1/weights
GET    /api/v1/weights/{date}
PUT    /api/v1/weights/{date}
DELETE /api/v1/weights/{date}
GET    /api/v1/weights
```

Keep the existing health endpoint working:

```text
GET /api/v1/health
```

---

## 3. Explicitly Out of Scope

Do not implement:

- Nutrition/Food endpoints
- Symptoms endpoints
- Injection endpoints
- Dashboard endpoints
- authentication
- multi-user behavior
- Flutter UI changes
- Flutter API integration
- notifications
- next injection API
- water logging
- AI features
- additional migrations
- schema changes
- PostgreSQL ENUMs
- database triggers
- PATCH endpoints

Spec 001 database schema must remain unchanged.

---

## 4. Suggested Backend Structure

Preserve the architecture rules from `AGENTS.md`.

A structure similar to the following is appropriate:

```text
backend/app/
├── main.py
├── api/
│   ├── __init__.py
│   ├── errors.py
│   ├── dependencies.py        # only if genuinely needed
│   └── v1/
│       ├── __init__.py
│       ├── router.py
│       └── weights.py
├── schemas/
│   ├── __init__.py
│   ├── common.py
│   └── weight.py
├── services/
│   ├── __init__.py
│   └── weight.py
└── db/
    ├── models.py
    └── session.py
```

Equivalent organization is acceptable if responsibilities remain clearly separated.

Do not place all Weight business logic directly in route handlers.

---

## 5. Common API Error Contract

Implement the public error structure documented in `docs/api-design.md`.

Base shape:

```json
{
  "error": {
    "code": "ERROR_CODE",
    "message": "Human-readable fallback message.",
    "details": []
  }
}
```

`details` may be omitted when unnecessary.

At minimum, implement stable handling for:

```text
VALIDATION_ERROR
WEIGHT_ALREADY_EXISTS
WEIGHT_NOT_FOUND
```

### Validation errors

FastAPI/Pydantic raw validation payloads must not leak as the public API contract.

Invalid request example:

```json
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "The request contains invalid values.",
    "details": [
      {
        "field": "weight_kg",
        "message": "Value must be greater than 0."
      }
    ]
  }
}
```

Field paths should be stable enough for Flutter to consume.

Do not make Flutter depend on Pydantic's internal error representation.

---

## 6. Common Query Validation

Implement or prepare narrowly reusable validation for list endpoints.

### Pagination

Supported query parameters:

```text
limit
offset
```

Defaults:

```text
limit = 50
offset = 0
```

Maximum:

```text
limit = 100
```

Invalid values return:

```text
422 VALIDATION_ERROR
```

Examples of invalid values:

- `limit <= 0`
- `limit > 100`
- `offset < 0`

### Date range

Supported query parameters:

```text
from
to
```

Both are inclusive.

Either may be omitted.

If both exist:

```text
from <= to
```

Otherwise return:

```text
422 VALIDATION_ERROR
```

Do not implement timezone query behavior yet because Weight filtering uses `record_date DATE` directly.

---

## 7. Weight API Data Contract

Use the existing `weight_logs` table from Spec 001.

Relevant fields:

```text
id
record_date
weight_kg
recorded_at
memo
created_at
updated_at
```

Do not alter the table.

### Numeric handling

`weight_kg` is a JSON number.

Database precision remains:

```text
NUMERIC(4,1)
```

The backend should serialize it as a JSON number, not a string.

### Timestamp handling

Input `recorded_at` must be timezone-aware.

Naive timestamps are rejected with:

```text
422 VALIDATION_ERROR
```

Timestamp responses are normalized to UTC.

`record_date` remains a date string and is not timezone-converted.

---

## 8. Create Weight

Endpoint:

```http
POST /api/v1/weights
```

Request:

```json
{
  "record_date": "2026-09-04",
  "weight_kg": 65.5,
  "recorded_at": "2026-09-04T08:30:00+09:00",
  "memo": "朝"
}
```

Validation:

- `record_date` required
- `weight_kg` required and > 0
- `recorded_at` required and timezone-aware
- `memo` optional, max 500 chars

Success:

```text
201 Created
```

Response includes:

```text
id
record_date
weight_kg
recorded_at
memo
created_at
updated_at
```

If `record_date` already exists:

```text
409 Conflict
WEIGHT_ALREADY_EXISTS
```

POST must never silently update or overwrite an existing day.

The application should convert the database uniqueness conflict into the documented domain error rather than leaking a database exception.

---

## 9. Get Weight by Date

Endpoint:

```http
GET /api/v1/weights/{date}
```

Example:

```http
GET /api/v1/weights/2026-09-04
```

Success:

```text
200 OK
```

Missing resource:

```text
404 Not Found
WEIGHT_NOT_FOUND
```

Invalid date path input returns the common validation contract.

---

## 10. Update Weight

Endpoint:

```http
PUT /api/v1/weights/{date}
```

Request:

```json
{
  "weight_kg": 65.3,
  "recorded_at": "2026-09-04T08:35:00+09:00",
  "memo": "入力を修正"
}
```

The URL date identifies the persisted record.

The body must not accept `record_date`.

Validation:

- `weight_kg` required and > 0
- `recorded_at` required and timezone-aware
- `memo` optional, max 500 chars

Success:

```text
200 OK
```

Missing resource:

```text
404 WEIGHT_NOT_FOUND
```

PUT is not an upsert.

`created_at` must remain unchanged.

`updated_at` must change according to the existing backend-managed timestamp policy.

---

## 11. Delete Weight

Endpoint:

```http
DELETE /api/v1/weights/{date}
```

Success:

```text
204 No Content
```

Response body must be empty.

Missing resource:

```text
404 WEIGHT_NOT_FOUND
```

Deletion is hard delete.

---

## 12. Weight History

Endpoint:

```http
GET /api/v1/weights
```

Supported filters:

```text
from
to
limit
offset
```

Example:

```http
GET /api/v1/weights?from=2026-08-01&to=2026-09-04&limit=50&offset=0
```

Date filtering uses `weight_logs.record_date`.

Both `from` and `to` are inclusive.

Order:

```text
record_date DESC
```

Response:

```json
{
  "items": [
    {
      "id": 12,
      "record_date": "2026-09-04",
      "weight_kg": 65.5,
      "recorded_at": "2026-09-03T23:30:00Z",
      "memo": null,
      "created_at": "2026-09-03T23:30:05Z",
      "updated_at": "2026-09-03T23:30:05Z"
    }
  ],
  "total": 1,
  "limit": 50,
  "offset": 0
}
```

`total` is the number of rows matching the date filters before pagination.

Ordering must remain deterministic.

---

## 13. Pydantic Schema Expectations

Create explicit schemas rather than exposing SQLAlchemy models directly.

At minimum, separate concepts equivalent to:

```text
WeightCreate
WeightUpdate
WeightResponse
WeightListResponse
```

Use modern Pydantic patterns compatible with the project's installed version.

Reject client attempts to provide backend-managed fields such as:

```text
id
created_at
updated_at
```

Do not accept undocumented extra fields silently if doing so weakens the API contract.

---

## 14. Database / Transaction Behavior

Use SQLAlchemy 2.x patterns consistent with the current project.

Requirements:

- sessions are properly scoped/closed
- create/update/delete operations commit deliberately
- errors roll back appropriately
- database-specific exceptions are not leaked to clients
- duplicate `record_date` becomes `WEIGHT_ALREADY_EXISTS`
- no migration is created

Avoid unnecessary repository abstractions if they add complexity without value, but keep route handlers thin.

---

## 15. Tests

Use pytest.

Tests must run against PostgreSQL when validating actual persistence behavior.

At minimum test:

### Common error handling

- invalid JSON/request field returns `VALIDATION_ERROR`
- raw FastAPI/Pydantic validation response is not exposed
- error shape matches the documented contract

### Create

- valid weight creates successfully
- response status is 201
- backend-managed fields are present
- duplicate `record_date` returns 409 `WEIGHT_ALREADY_EXISTS`
- invalid/non-positive weight returns 422
- naive `recorded_at` returns 422
- memo over 500 chars returns 422

### Read

- existing date returns 200
- missing date returns 404 `WEIGHT_NOT_FOUND`

### Update

- valid update succeeds
- persisted value changes
- `created_at` remains unchanged
- `updated_at` changes
- missing date returns 404
- PUT does not create a missing resource

### Delete

- existing record deletes with 204 and no body
- record is actually gone
- missing record returns 404

### History

- sorted by `record_date DESC`
- inclusive `from`
- inclusive `to`
- pagination defaults
- limit/offset work
- `total` is pre-pagination count
- invalid range returns 422
- invalid pagination values return 422

### Serialization

- `weight_kg` is returned as JSON number, not string
- timestamps returned by API are UTC/timezone-aware

Do not weaken existing Spec 001 migration tests.

---

## 16. Verification Commands

Run the relevant existing and new checks.

At minimum:

```sh
cd backend

uv sync --dev
uv run ruff format .
uv run ruff format --check .
uv run ruff check .
uv run pytest
```

Use PostgreSQL for API/database tests.

Also verify the existing Alembic state has not changed unexpectedly:

```sh
uv run alembic heads
uv run alembic check
```

Expected migration head remains:

```text
20260904_0001
```

If Docker is used for the test database, clean up temporary test containers afterward.

---

## 17. Acceptance Criteria

Spec 002 is complete when:

- the shared public error format is implemented
- validation failures use the shared error contract
- Weight create/read/update/delete/history endpoints exist
- duplicate day behavior returns 409 instead of leaking DB errors
- Weight PUT is not an upsert
- pagination and date filtering follow `docs/api-design.md`
- timestamp input must be timezone-aware
- timestamp output is normalized to UTC
- decimal weight values are JSON numbers
- all required tests pass against PostgreSQL
- existing health endpoint still works
- no database migration/schema change was added
- Nutrition/Food, Symptoms, Injection, Dashboard, and Flutter work were not implemented
- Ruff passes
- Alembic remains at revision `20260904_0001`

---

## 18. Codex Completion Report

After implementation, report:

1. changed/created files
2. API endpoints implemented
3. common API/error infrastructure added
4. important implementation decisions
5. commands executed
6. test/lint/Alembic results
7. any warnings or unresolved issues

Do not commit or push unless explicitly instructed after review.

Do not begin Spec 003 automatically.
