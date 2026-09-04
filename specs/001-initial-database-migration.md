# Spec: Initial Database Migration

## Status

Ready for implementation.

## Goal

Create the initial PostgreSQL schema for the MVP using Alembic and SQLAlchemy 2.x.

The migration must implement the database design defined in:

```text
docs/database-design.md
```

No tables or columns outside this specification should be added.

---

## 1. Migration Scope

Create these five tables:

1. `nutrition_days`
2. `food_logs`
3. `weight_logs`
4. `symptom_logs`
5. `injection_records`

Create their:

- primary keys
- foreign keys
- unique constraints
- check constraints
- indexes

The migration must support both `upgrade()` and `downgrade()`.

---

## 2. General Requirements

- Database: PostgreSQL
- Migration tool: Alembic
- ORM conventions: SQLAlchemy 2.x
- All primary keys: `BIGINT`
- All event/audit timestamps: timezone-aware `TIMESTAMPTZ`
- All day-only values: `DATE`
- Hard delete only
- No `user_id`
- No PostgreSQL ENUM types
- Enum-like values use `VARCHAR` + `CHECK`
- Do not add application-only validation as triggers or stored procedures

---

## 3. Table Definitions

## 3.1 nutrition_days

Create:

```text
id BIGINT PRIMARY KEY
date DATE NOT NULL UNIQUE
mode VARCHAR NOT NULL
memo VARCHAR(500) NULL
created_at TIMESTAMPTZ NOT NULL
updated_at TIMESTAMPTZ NOT NULL
```

Add check constraint:

```sql
mode IN ('NORMAL', 'FREE_DAY')
```

Suggested constraint name:

```text
ck_nutrition_days_mode
```

Suggested unique constraint name:

```text
uq_nutrition_days_date
```

---

## 3.2 food_logs

Create:

```text
id BIGINT PRIMARY KEY
nutrition_day_id BIGINT NOT NULL
name VARCHAR(100) NOT NULL
calories INTEGER NOT NULL
protein_g NUMERIC(6,2) NOT NULL
eaten_at TIMESTAMPTZ NOT NULL
memo VARCHAR(500) NULL
created_at TIMESTAMPTZ NOT NULL
updated_at TIMESTAMPTZ NOT NULL
```

Foreign key:

```text
food_logs.nutrition_day_id
    -> nutrition_days.id
    ON DELETE CASCADE
```

Suggested foreign-key name:

```text
fk_food_logs_nutrition_day_id_nutrition_days
```

Check constraints:

```sql
calories >= 0
protein_g >= 0
```

Suggested names:

```text
ck_food_logs_calories_nonnegative
ck_food_logs_protein_g_nonnegative
```

Create index:

```text
ix_food_logs_nutrition_day_eaten_at
(nutrition_day_id, eaten_at)
```

---

## 3.3 weight_logs

Create:

```text
id BIGINT PRIMARY KEY
record_date DATE NOT NULL UNIQUE
weight_kg NUMERIC(4,1) NOT NULL
recorded_at TIMESTAMPTZ NOT NULL
memo VARCHAR(500) NULL
created_at TIMESTAMPTZ NOT NULL
updated_at TIMESTAMPTZ NOT NULL
```

Check constraint:

```sql
weight_kg > 0
```

Suggested names:

```text
uq_weight_logs_record_date
ck_weight_logs_weight_kg_positive
```

Create index:

```text
ix_weight_logs_recorded_at
(recorded_at)
```

---

## 3.4 symptom_logs

Create:

```text
id BIGINT PRIMARY KEY
recorded_at TIMESTAMPTZ NOT NULL
nausea SMALLINT NOT NULL
abdominal_pain SMALLINT NOT NULL
fatigue SMALLINT NOT NULL
appetite SMALLINT NOT NULL
bowel_condition VARCHAR NULL
memo VARCHAR(500) NULL
created_at TIMESTAMPTZ NOT NULL
updated_at TIMESTAMPTZ NOT NULL
```

Check constraints:

```sql
nausea BETWEEN 1 AND 10
abdominal_pain BETWEEN 1 AND 10
fatigue BETWEEN 1 AND 10
appetite BETWEEN 1 AND 10
```

Suggested names:

```text
ck_symptom_logs_nausea_range
ck_symptom_logs_abdominal_pain_range
ck_symptom_logs_fatigue_range
ck_symptom_logs_appetite_range
```

Add bowel condition check:

```sql
bowel_condition IS NULL
OR bowel_condition IN (
  'NORMAL',
  'CONSTIPATION',
  'DIARRHEA',
  'OTHER'
)
```

Suggested name:

```text
ck_symptom_logs_bowel_condition
```

Create index:

```text
ix_symptom_logs_recorded_at
(recorded_at)
```

---

## 3.5 injection_records

Create:

```text
id BIGINT PRIMARY KEY
record_date DATE NOT NULL UNIQUE
injected_at TIMESTAMPTZ NOT NULL
dose_mg NUMERIC(5,2) NOT NULL
injection_site VARCHAR NOT NULL
memo VARCHAR(500) NULL
created_at TIMESTAMPTZ NOT NULL
updated_at TIMESTAMPTZ NOT NULL
```

Check constraint:

```sql
dose_mg > 0
```

Injection-site constraint:

```sql
injection_site IN (
  'ABDOMEN_UPPER_RIGHT',
  'ABDOMEN_LOWER_RIGHT',
  'ABDOMEN_UPPER_LEFT',
  'ABDOMEN_LOWER_LEFT',
  'THIGH_RIGHT',
  'THIGH_LEFT'
)
```

Suggested names:

```text
uq_injection_records_record_date
ck_injection_records_dose_mg_positive
ck_injection_records_injection_site
```

Create index:

```text
ix_injection_records_injected_at
(injected_at)
```

---

## 4. Primary Key Generation

Use PostgreSQL-compatible automatic BIGINT primary-key generation.

The implementation may use SQLAlchemy/Alembic identity/autoincrement semantics appropriate for PostgreSQL.

Do not expose primary-key generation to Flutter.

---

## 5. Timestamp Behavior

The schema defines:

```text
created_at TIMESTAMPTZ NOT NULL
updated_at TIMESTAMPTZ NOT NULL
```

The migration is responsible for schema shape only.

FastAPI/SQLAlchemy application code is responsible for:

- assigning `created_at`
- assigning `updated_at`
- updating `updated_at` on mutation

Do not implement database triggers for timestamp updates in this migration.

---

## 6. Application Rules Not Implemented in Migration

Do not add triggers or database procedures for these rules.

They belong to FastAPI/application logic:

### Free Day

- A food log cannot be inserted when its parent `nutrition_days.mode` is `FREE_DAY`.
- A nutrition day cannot change from `NORMAL` to `FREE_DAY` if it already has one or more `food_logs`.

### Food date consistency

The local calendar date of `food_logs.eaten_at` must match `nutrition_days.date`.

This must be validated using the application's timezone handling, not a database check constraint.

### Empty food names

`food_logs.name` must not be empty or whitespace-only.

Validate this through Pydantic/FastAPI.

### Next injection date

Do not create:

```text
next_injection_at
```

The next scheduled injection date is calculated from the latest injection record.

---

## 7. Upgrade Order

Recommended `upgrade()` order:

```text
1. nutrition_days
2. food_logs
3. weight_logs
4. symptom_logs
5. injection_records
6. indexes
```

Indexes may also be created immediately after each table.

`nutrition_days` must exist before `food_logs` because of the foreign key.

---

## 8. Downgrade Order

Drop objects in reverse dependency order.

Recommended `downgrade()` order:

```text
1. indexes where explicit removal is required
2. injection_records
3. symptom_logs
4. weight_logs
5. food_logs
6. nutrition_days
```

`food_logs` must be dropped before `nutrition_days`.

The downgrade must leave the database in the state before this initial migration.

---

## 9. Acceptance Criteria

The implementation is complete when all of the following are true:

- Alembic migration upgrades an empty PostgreSQL database successfully.
- All five tables exist.
- All primary keys are BIGINT.
- All required unique constraints exist.
- `food_logs.nutrition_day_id` has `ON DELETE CASCADE`.
- Invalid nutrition modes are rejected by PostgreSQL.
- Negative calories are rejected.
- Negative protein values are rejected.
- Non-positive weight values are rejected.
- Symptom values outside 1-10 are rejected.
- Invalid bowel-condition values are rejected.
- Non-positive injection doses are rejected.
- Invalid injection-site values are rejected.
- Duplicate `nutrition_days.date` values are rejected.
- Duplicate `weight_logs.record_date` values are rejected.
- Duplicate `injection_records.record_date` values are rejected.
- All specified indexes exist.
- `alembic downgrade -1` succeeds.
- A subsequent `alembic upgrade head` succeeds again.

---

## 10. Tests

At minimum, add migration/schema tests that verify:

- migration upgrade succeeds
- migration downgrade succeeds
- unique constraints reject duplicates
- check constraints reject invalid values
- cascade deletion removes child `food_logs`
- valid rows can be inserted into all five tables

If the project already has an integration-test PostgreSQL environment, use it rather than mocking database constraints.

---

## 11. Codex Implementation Instructions

Before implementation:

1. Read `AGENTS.md`.
2. Read `docs/database-design.md`.
3. Read this spec completely.
4. Inspect the existing FastAPI/Alembic project structure.

During implementation:

- Implement only this migration scope.
- Do not add authentication.
- Do not add notification tables.
- Do not add water logging.
- Do not add `next_injection_at`.
- Do not add PostgreSQL ENUM types.
- Do not add database triggers for domain rules.
- Use clear constraint/index names.
- Keep generated migration code readable.

After implementation:

1. Run formatting/linting required by the repository.
2. Run Alembic upgrade on a clean PostgreSQL database.
3. Run tests.
4. Run downgrade and upgrade again if the test workflow does not already cover it.
5. Report changed files.
6. Report commands executed and results.
7. Report any unresolved issues without silently changing the specification.
