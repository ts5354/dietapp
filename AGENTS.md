# AGENTS.md

## 1. Purpose

This repository contains a mobile-first health logging application.

The MVP allows a single user to record and review:

- clinician-directed injection records
- symptoms
- food intake with calories and protein
- daily weight
- daily nutrition state, including `FREE_DAY`

Codex should implement the application from the repository specifications. Do not invent product requirements that are not documented.

---

## 2. Source of Truth

Before making changes, read the relevant repository documents.

Priority:

1. `AGENTS.md`
2. the active file under `specs/`
3. relevant files under `docs/`
4. existing code and tests

For database work, always read:

- `docs/database-design.md`
- the relevant migration/database spec

If documents conflict, do not silently choose one. Stop and report the conflict.

---

## 3. Development Workflow

Work on one spec at a time.

For every implementation task:

1. Read this file.
2. Read the requested spec completely.
3. Read all documents referenced by that spec.
4. Inspect the existing implementation before editing.
5. Make a short implementation plan.
6. Implement only the requested scope.
7. Format the changed code.
8. Run static analysis/linting.
9. Run relevant tests.
10. Report:
   - changed files
   - commands executed
   - test/lint results
   - unresolved issues or assumptions

Do not begin unrelated future specs while implementing the current spec.

---

## 4. Repository Structure

Target monorepo structure:

```text
dietapp/
├── AGENTS.md
├── README.md
├── docs/
├── specs/
├── mobile/
├── backend/
└── docker-compose.yml
```

### `mobile/`

Flutter application.

Target technologies:

- Flutter
- Dart
- Riverpod
- GoRouter
- Dio
- Freezed where useful
- fl_chart

### `backend/`

Backend API.

Target technologies:

- Python
- FastAPI
- SQLAlchemy 2.x
- Alembic
- Pydantic
- PostgreSQL
- pytest
- uv

### Development infrastructure

Use Docker Compose for backend development services, especially:

- FastAPI
- PostgreSQL

Flutter runs on the host machine during local development unless a spec explicitly changes this.

---

## 5. Architecture Rules

Keep responsibilities separated.

### Flutter

Prefer separation between:

- presentation/UI
- application/state
- domain models/rules
- data/API access

Widgets should not directly contain HTTP or persistence logic.

Do not place large amounts of unrelated logic in one file.

### FastAPI

Prefer separation between:

- API/routes
- schemas
- services/application logic
- domain rules
- database models/repositories
- infrastructure/configuration

Routes should not become the primary location for business logic.

### Database

Database constraints should protect straightforward data integrity.

Cross-record or timezone-dependent business rules should generally live in FastAPI unless the specification explicitly requires a database-level mechanism.

Do not introduce database triggers or stored procedures without an explicit specification.

---

## 6. API Rules

The mobile app communicates with FastAPI through REST.

General rules:

- use `/api/v1` for MVP API routes unless a spec says otherwise
- use Pydantic for request/response validation
- use clear HTTP status codes
- return structured errors suitable for Flutter
- do not expose internal stack traces to the client
- timestamps crossing the API boundary use ISO 8601
- backend validation is authoritative even when Flutter performs equivalent validation

Do not add GraphQL, gRPC, or another API style unless explicitly specified.

---

## 7. Database Rules

The canonical database design is:

`docs/database-design.md`

Current MVP tables:

- `nutrition_days`
- `food_logs`
- `weight_logs`
- `symptom_logs`
- `injection_records`

General rules:

- primary keys are `BIGINT`
- no `user_id` in MVP
- event timestamps use timezone-aware timestamps
- day-only fields use `DATE`
- hard delete only
- `created_at` and `updated_at` are backend-managed
- enum-like database values use `VARCHAR` + `CHECK`, not PostgreSQL ENUM
- migrations are managed by Alembic

Do not modify the database design merely because another schema seems more convenient. A schema change requires an explicit spec/document update.

---

## 8. Nutrition Domain Rules

Nutrition has three conceptual states:

### NORMAL

A `nutrition_days` row exists with:

```text
mode = NORMAL
```

Food records may be added.

### FREE_DAY

A `nutrition_days` row exists with:

```text
mode = FREE_DAY
```

This means nutrition calculation is intentionally not performed for that day.

It does **not** mean:

```text
0 kcal
0 g protein
```

Daily calorie/protein totals are not applicable for `FREE_DAY`.

Do not create food logs for a `FREE_DAY`.

A `NORMAL` day that already contains food logs cannot be changed to `FREE_DAY`.

Never silently delete food records to perform this transition.

### UNRECORDED

No `nutrition_days` row exists for that date.

`UNRECORDED` is not stored as a database mode.

Do not treat `UNRECORDED` and `FREE_DAY` as equivalent.

### Food logging

Every eating event is one independent `food_logs` record.

Do not introduce a meal/meal-item hierarchy for the MVP.

Breakfast, lunch, dinner, and snacks do not require separate database entities.

---

## 9. Weight Rules

Weight is recorded at most once per calendar day.

If the user corrects an incorrect value, update the existing record instead of inserting a second record for that day.

Do not add weight-loss scoring, judgmental labels, or automatic target recommendations.

---

## 10. Symptom Rules

Symptom logs may be recorded multiple times per day.

The following fields use a required 1-10 scale:

- nausea
- abdominal pain
- fatigue
- appetite

Higher values mean a stronger state.

`bowel_condition` is optional and follows the values documented in the database design.

Do not infer diagnoses from symptom logs.

---

## 11. Injection and Medical Safety Rules

The application is a record-keeping tool, not a medication decision system.

Injection dose values represent information entered from clinician-directed treatment.

The application must never:

- recommend increasing or decreasing a prescription dose
- automatically change a prescription dose
- determine a dose based on weight, appetite, food intake, or symptoms
- present generated medication instructions as medical advice

The dose unit is fixed to mg in the current design.

The injection site values are defined in `docs/database-design.md`.

Only one injection record is allowed per calendar day. Corrections update the existing record.

The next injection date is calculated from the latest injection record according to the product specification; do not add `next_injection_at` to the database unless a later spec explicitly changes this.

When the UI handles concerning or severe symptoms, it may direct the user to appropriate medical care or their clinician. It must not respond by recommending a medication dose change.

---

## 12. MVP Scope Guardrails

Do not add these features unless a later spec explicitly requests them:

- authentication
- multi-user support
- water logging
- push/local notifications
- food database search
- barcode scanning
- meal photo analysis
- AI health analysis
- medical PDF reports
- clinician sharing
- Apple Health integration
- Health Connect integration
- offline synchronization
- production cloud deployment
- `next_injection_at`
- soft delete

Avoid speculative abstractions for future features.

Build the simplest maintainable implementation that satisfies the current specification.

---

## 13. Testing

Add tests for meaningful domain behavior, not only happy paths.

### Backend

Use pytest.

For database behavior, test against PostgreSQL when database-specific constraints are relevant.

Important areas include:

- validation
- CRUD behavior
- unique constraints
- check constraints
- foreign-key behavior
- `ON DELETE CASCADE`
- `FREE_DAY` rules
- date consistency rules
- update/correction behavior

### Flutter

Add unit/widget tests where they provide meaningful coverage.

Prioritize:

- state/domain logic
- validation
- important navigation
- critical record forms

Do not create brittle tests that only mirror implementation details.

---

## 14. Code Quality

Prefer:

- small focused modules
- explicit names
- typed interfaces/models
- straightforward control flow
- reusable domain logic where reuse is real

Avoid:

- giant files
- duplicated validation rules when they can be centralized
- hidden side effects
- unnecessary dependencies
- premature abstractions
- broad refactors unrelated to the active spec

Comments should explain why something exists, not restate obvious code.

---

## 15. Dependencies

Before adding a new dependency:

1. confirm the existing stack cannot reasonably handle the requirement
2. ensure the dependency directly supports the active spec
3. use a maintained and appropriate package
4. report the dependency addition in the implementation summary

Do not replace an already selected core technology without explicit approval.

---

## 16. Migration Safety

Never rewrite an already-applied migration merely to make later work easier.

Create a new migration for schema changes after the initial migration has become part of normal development history.

For migration tasks:

- verify `upgrade`
- verify `downgrade` when required by the spec
- verify constraints
- do not silently drop data
- report destructive changes before implementing them if they were not explicitly specified

---

## 17. Definition of Done

A spec is complete only when:

- requested behavior is implemented
- relevant documentation and code agree
- formatter passes
- static analysis/linting passes
- relevant tests pass
- migrations work when the spec includes schema changes
- no unrelated requirements were added
- changed files and verification results are reported

If something cannot be completed, clearly report what remains and why.

Do not claim completion when tests or required checks are failing.
