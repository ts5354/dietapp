# API Design

## Status
Accepted MVP API design.

Base path: `/api/v1`

The FastAPI backend is authoritative for validation and domain rules. Flutter may duplicate validation for UX but must not replace backend validation.

## 1. Common conventions

Resources use plural names and JSON uses `snake_case`.

- `/api/v1/weights`
- `/api/v1/nutrition/days`
- `/api/v1/symptoms`
- `/api/v1/injections`

Database-generated BIGINT IDs are exposed as JSON integers. Clients must not generate IDs.

### HTTP status codes

| Status | Meaning |
|---|---|
| 200 | successful read/update |
| 201 | created |
| 204 | deleted, no response body |
| 404 | persisted resource not found |
| 409 | valid request conflicts with current domain/resource state |
| 422 | request/cross-field validation failed |
| 500 | unexpected server error |

## 2. Error contract

Do not expose raw FastAPI/Pydantic validation responses as the Flutter contract.

```json
{
  "error": {
    "code": "ERROR_CODE",
    "message": "Human-readable fallback message.",
    "details": []
  }
}
```

`details` may be omitted when unnecessary. Flutter should primarily use `error.code` for localized UI messages.

Validation example:

```json
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "The request contains invalid values.",
    "details": [
      {"field": "weight_kg", "message": "Value must be greater than 0."}
    ]
  }
}
```

Stable MVP domain codes:

- `VALIDATION_ERROR`
- `WEIGHT_ALREADY_EXISTS`
- `WEIGHT_NOT_FOUND`
- `FOOD_NOT_ALLOWED_ON_FREE_DAY`
- `FOOD_DATE_MISMATCH`
- `FOOD_NOT_FOUND`
- `FREE_DAY_HAS_FOOD_LOGS`
- `SYMPTOM_NOT_FOUND`
- `INJECTION_ALREADY_EXISTS`
- `INJECTION_NOT_FOUND`
- `INJECTION_DATE_MISMATCH`

## 3. Date and timezone contract

Date-only values use ISO 8601 `YYYY-MM-DD` and map to PostgreSQL `DATE`.

Event timestamps use timezone-aware ISO 8601/RFC 3339 values, e.g. `2026-09-04T08:30:00+09:00`. Naive timestamps are rejected. They map to PostgreSQL `TIMESTAMPTZ`.

Backend timestamp responses are normalized to UTC, e.g. `2026-09-03T23:30:00Z`. Flutter converts timestamps to the device/user timezone for display. `DATE` fields are never timezone-converted.

When a request combines a date resource and event timestamp, the backend validates the calendar date represented by the timestamp's supplied offset.

- food URL date must match local date of `eaten_at`; otherwise `422 FOOD_DATE_MISMATCH`
- injection `record_date` must match local date of `injected_at`; otherwise `422 INJECTION_DATE_MISMATCH`

Resources backed by a `DATE` column (`weights`, `nutrition`, `injections`) use that date directly for `from`/`to` filtering.

Symptoms have no `DATE` column. Calendar-date symptom filters therefore require an IANA timezone:

```http
GET /api/v1/symptoms?from=2026-09-04&to=2026-09-04&timezone=Asia%2FTokyo
```

Future endpoints whose meaning depends on “today” or local-day boundaries must likewise use an explicit IANA timezone unless they operate directly on a stored `DATE`. Backend logic must not hard-code JST.

## 4. Numeric JSON representation

Numbers are JSON numbers, not strings.

```json
{
  "id": 42,
  "weight_kg": 65.5,
  "calories": 180,
  "protein_g": 4.5,
  "dose_mg": 2.5
}
```

Database precision remains authoritative:

- `weight_kg NUMERIC(4,1)`
- `protein_g NUMERIC(6,2)`
- `dose_mg NUMERIC(5,2)`

Clients must not depend on insignificant trailing zeroes (`4.50` vs `4.5`). Flutter handles display formatting.

## 5. Pagination

List endpoints use offset pagination where applicable:

- default `limit=50`
- default `offset=0`
- maximum `limit=100`
- negative values or limit > 100 => `422`

Response:

```json
{
  "items": [],
  "total": 0,
  "limit": 50,
  "offset": 0
}
```

`total` is the count after filters but before pagination. Pagination never changes defined sort order. Cursor pagination is out of scope for MVP.

## 6. Date ranges

List filters use inclusive `from` and `to` dates.

```text
?from=2026-08-01&to=2026-09-04
```

Either may be omitted. If both exist, `from <= to`; invalid ranges return `422`. Symptoms additionally require `timezone` when calendar-date filtering is used.

## 7. Weight API

One record maximum per calendar date.

- `POST /api/v1/weights` — create; duplicate date => `409 WEIGHT_ALREADY_EXISTS`
- `GET /api/v1/weights/{date}` — get one; missing => `404 WEIGHT_NOT_FOUND`
- `PUT /api/v1/weights/{date}` — update existing; not an upsert
- `DELETE /api/v1/weights/{date}` — hard delete
- `GET /api/v1/weights?from=&to=&limit=&offset=` — history

Create body:

```json
{
  "record_date": "2026-09-04",
  "weight_kg": 65.5,
  "recorded_at": "2026-09-04T08:30:00+09:00",
  "memo": "朝"
}
```

Update body omits `record_date`. History order: `record_date DESC`. POST never silently overwrites.

## 8. Nutrition / Food API

API-level states:

- `NORMAL`
- `FREE_DAY`
- `UNRECORDED`

Database stores only `NORMAL` and `FREE_DAY`. `UNRECORDED` means no `nutrition_days` row exists.

### Read one day

`GET /api/v1/nutrition/days/{date}`

UNRECORDED is a normal state and returns 200:

```json
{
  "date": "2026-09-04",
  "mode": "UNRECORDED",
  "memo": null,
  "total_calories": null,
  "total_protein_g": null,
  "foods": []
}
```

FREE_DAY always has null totals and an empty foods list. NORMAL totals are calculated from food records, never stored separately.

Food order: `eaten_at ASC, id ASC`.

### Set day state

`PUT /api/v1/nutrition/days/{date}`

Allowed:

- UNRECORDED -> NORMAL
- UNRECORDED -> FREE_DAY
- NORMAL with zero foods -> FREE_DAY
- FREE_DAY -> NORMAL

NORMAL with existing foods -> FREE_DAY is rejected with `409 FREE_DAY_HAS_FOOD_LOGS`. Existing foods must never be silently deleted.

### Food operations

- `POST /api/v1/nutrition/days/{date}/foods`
- `PUT /api/v1/nutrition/days/{date}/foods/{id}`
- `DELETE /api/v1/nutrition/days/{date}/foods/{id}`

Adding food to UNRECORDED atomically creates a NORMAL nutrition day and the food. Adding food to FREE_DAY => `409 FOOD_NOT_ALLOWED_ON_FREE_DAY`.

`eaten_at` must match the URL date => otherwise `422 FOOD_DATE_MISMATCH`.

Food update/delete must target a food belonging to the URL's nutrition day. Missing => `404 FOOD_NOT_FOUND`.

Deleting the final food does not delete the NORMAL nutrition day. There is no MVP endpoint to delete an entire nutrition day.

History:

`GET /api/v1/nutrition/days?from=&to=&limit=&offset=`

Order: `date DESC`. UNRECORDED dates are not synthesized into history.

## 9. Symptoms API

Symptoms use ID-based CRUD because multiple records per day are allowed.

Required integer scales, all 1–10:

- nausea
- abdominal_pain
- fatigue
- appetite

Higher means stronger state.

Optional `bowel_condition` values: `NORMAL`, `CONSTIPATION`, `DIARRHEA`, `OTHER`, or null.

Endpoints:

- `POST /api/v1/symptoms`
- `GET /api/v1/symptoms/{id}`
- `PUT /api/v1/symptoms/{id}`
- `DELETE /api/v1/symptoms/{id}`
- `GET /api/v1/symptoms?from=&to=&timezone=&limit=&offset=`

History order: `recorded_at DESC, id DESC`. Same-timestamp records are allowed.

PUT sends all editable fields and is not an upsert. Missing record => `404 SYMPTOM_NOT_FOUND`.

The API records symptom values but does not infer diagnoses or generate medical severity classifications from them.

## 10. Injection API

One record maximum per calendar date.

Endpoints:

- `POST /api/v1/injections`
- `GET /api/v1/injections/{date}`
- `PUT /api/v1/injections/{date}`
- `DELETE /api/v1/injections/{date}`
- `GET /api/v1/injections?from=&to=&limit=&offset=`

Create body:

```json
{
  "record_date": "2026-09-04",
  "injected_at": "2026-09-04T20:30:00+09:00",
  "dose_mg": 2.5,
  "injection_site": "ABDOMEN_LOWER_RIGHT",
  "memo": null
}
```

Duplicate date => `409 INJECTION_ALREADY_EXISTS`. POST never silently overwrites. PUT is not an upsert. Missing => `404 INJECTION_NOT_FOUND`.

Allowed injection sites:

- `ABDOMEN_UPPER_RIGHT`
- `ABDOMEN_LOWER_RIGHT`
- `ABDOMEN_UPPER_LEFT`
- `ABDOMEN_LOWER_LEFT`
- `THIGH_RIGHT`
- `THIGH_LEFT`

Flutter maps stable API values to localized labels.

History order: `injected_at DESC, id DESC`.

### Next scheduled injection date

For this Mounjaro-specific application, the displayed weekly next scheduled date is derived as:

```text
latest injection record_date + 7 calendar days
```

Example: `2026-09-04 -> 2026-09-11`.

This value is derived, not persisted. Do not add `next_injection_at` or `next_injection_date` database columns. The endpoint exposing dashboard-derived data will be defined separately.

This scheduling display must not be used to recommend or automatically alter prescription dosage.

## 11. Backend-managed fields

Clients do not provide `id`, `created_at`, or `updated_at`.

On create, backend sets both timestamps. On update, `created_at` remains unchanged and `updated_at` changes.

## 12. String validation

FastAPI/Pydantic trims/validates strings where appropriate.

`food_logs.name`:
- required
- max 100 chars
- empty/whitespace-only rejected

Memo:
- optional
- max 500 chars

Enum-like request strings reject empty/whitespace-only values.

## 13. PUT semantics

MVP uses PUT rather than PATCH.

Weight, Food, Symptoms, and Injection PUT endpoints update existing resources and do not upsert.

`PUT /nutrition/days/{date}` is the explicit exception: it may create the day because setting day state is itself the resource operation.

PATCH is out of scope.

## 14. Ordering summary

- Weight: `record_date DESC`
- Nutrition days: `date DESC`
- Foods within day: `eaten_at ASC, id ASC`
- Symptoms: `recorded_at DESC, id DESC`
- Injections: `injected_at DESC, id DESC`

Ordering must be deterministic.

## 15. Safety boundaries

The API is a record-keeping system. It must not:

- recommend or automatically alter prescription dosage
- calculate prescription dosage from weight, food, appetite, or symptoms
- infer diagnoses from symptom values
- introduce weight-loss scoring or judgmental labels
- generate calorie/protein restriction targets

## 16. Out of scope

Not part of the current MVP API contract:

- authentication/multi-user
- notifications
- water logging
- food database search/barcodes
- meal photo analysis
- AI health analysis
- clinician sharing/PDF reports
- Apple Health / Health Connect
- offline synchronization
- production deployment APIs

## 17. Implementation rule

This document defines the API contract. It does not authorize implementing every endpoint at once.

Each implementation spec must explicitly define its scope. Codex must not implement later API areas merely because they are documented here.
