# Spec 004 — Symptom API

## 1. 目的

MVP の体調記録機能に必要な Symptom API を実装する。

本 Spec では、既存の `symptom_logs` テーブルを利用して以下を提供する。

- 体調記録の作成
- ID による単一記録取得
- 体調記録の完全更新
- 体調記録の削除
- 体調履歴の取得
- IANA timezone を用いたローカル日付範囲検索
- pagination
- 共通 API エラー形式への統一
- PostgreSQL を用いた API テスト

この API はユーザーが入力した症状・状態を記録するためのものであり、診断、重症度判定、危険度判定、治療判断、薬剤調整などは行わない。

---

## 2. 実装前に読むもの

Codex は実装開始前に、少なくとも以下を読むこと。

1. `/AGENTS.md`
2. `/docs/database-design.md`
3. `/docs/api-design.md`
4. `/specs/004-symptom-api.md`
5. 既存の Weight API / Nutrition API 実装とテスト

既存の共通 API 契約、エラー形式、SQLAlchemy Session 管理、timestamp 正規化、テスト方針を再利用すること。

仕様間に矛盾を発見した場合、独自判断で解決せず報告すること。

---

## 3. Scope

### In scope

- Symptom API 5 endpoint
- request / response schema
- service layer
- router 登録
- validation
- IANA timezone に基づく日付 filter
- pagination
- stable error code
- PostgreSQL API test

### Out of scope

- DB schema 変更
- Alembic migration 追加
- Flutter 実装
- Dashboard API
- Injection API
- 通知
- 症状の医学的評価
- 診断
- 重症度・危険度の自動分類
- 症状値に基づく治療提案
- 薬剤や投与量の変更提案
- symptom aggregate / analytics API

本 Spec のために `symptom_logs` の DB モデルや migration を変更してはならない。

---

## 4. 使用する既存 DB

既存の `symptom_logs` テーブルを使用する。

```text
id                BIGINT PRIMARY KEY
recorded_at       TIMESTAMPTZ NOT NULL
nausea            SMALLINT NOT NULL CHECK 1 <= nausea <= 10
abdominal_pain    SMALLINT NOT NULL CHECK 1 <= abdominal_pain <= 10
fatigue           SMALLINT NOT NULL CHECK 1 <= fatigue <= 10
appetite          SMALLINT NOT NULL CHECK 1 <= appetite <= 10
bowel_condition   VARCHAR NULL
memo              VARCHAR(500) NULL
created_at        TIMESTAMPTZ NOT NULL
updated_at        TIMESTAMPTZ NOT NULL
```

`bowel_condition` の許可値は以下。

```text
NORMAL
CONSTIPATION
DIARRHEA
OTHER
null
```

既存 DB 制約を authoritative としつつ、API 層でも入力を検証する。

### 記録数

- 1 日に複数件登録可能
- 同一 `recorded_at` の複数レコードも許可
- 日付単位の UNIQUE 制約を追加しない

---

## 5. 症状尺度の意味

以下の 4 項目はすべて integer `1..10` とする。

- `nausea`: 1 = 弱い、10 = 強い
- `abdominal_pain`: 1 = 弱い、10 = 強い
- `fatigue`: 1 = 弱い、10 = 強い
- `appetite`: 1 = 食欲が弱い、10 = 食欲が強い

API は入力値を保存・返却するだけとする。数値から診断的・医学的分類や危険度を生成してはならない。

---

## 6. Endpoint 一覧

```http
POST   /api/v1/symptoms
GET    /api/v1/symptoms/{id}
PUT    /api/v1/symptoms/{id}
DELETE /api/v1/symptoms/{id}
GET    /api/v1/symptoms
```

CRUD は ID ベースとする。

---

## 7. POST /api/v1/symptoms

### Request

```json
{
  "recorded_at": "2026-09-05T09:30:00+09:00",
  "nausea": 3,
  "abdominal_pain": 1,
  "fatigue": 6,
  "appetite": 4,
  "bowel_condition": "NORMAL",
  "memo": "朝の記録"
}
```

必須: `recorded_at`, `nausea`, `abdominal_pain`, `fatigue`, `appetite`

任意: `bowel_condition`, `memo`。省略時は `null`。

成功: `201 Created`

Response は DB 採番 `id`、全記録 field、`created_at`, `updated_at` を含む。timestamp は UTC `Z` に正規化する。

client は `id`, `created_at`, `updated_at` を送信してはならない。その他の未定義 extra field も拒否する。

---

## 8. GET /api/v1/symptoms/{id}

ID により単一記録を取得する。

成功: `200 OK`

存在しない場合:

```text
404 Not Found
SYMPTOM_NOT_FOUND
```

共通 error envelope を使用する。

---

## 9. PUT /api/v1/symptoms/{id}

既存記録を完全更新する。PUT は upsert ではない。

POST と同じ editable fields を使用し、`recorded_at`, `nausea`, `abdominal_pain`, `fatigue`, `appetite` は必須。

`bowel_condition` と `memo` は省略可能で、省略した場合は `null` として更新する。

- `created_at` は変更しない
- `updated_at` は backend が更新
- missing ID は `404 SYMPTOM_NOT_FOUND`
- 存在しない ID に新規作成しない

---

## 10. DELETE /api/v1/symptoms/{id}

hard delete。

成功: `204 No Content`、body なし。

missing ID:

```text
404 Not Found
SYMPTOM_NOT_FOUND
```

---

## 11. GET /api/v1/symptoms

Query parameters:

```text
from
to
timezone
limit
offset
```

Pagination:

```text
limit:  default 50, min 1, max 100
offset: default 0, min 0
```

不正値は `422 VALIDATION_ERROR`。

Response:

```json
{
  "items": [],
  "total": 0,
  "limit": 50,
  "offset": 0
}
```

`total` は filter 適用後・pagination 適用前の総件数。

---

## 12. 履歴の並び順

必ず:

```sql
ORDER BY recorded_at DESC, id DESC
```

同一 `recorded_at` では `id DESC` を tie-breaker とする。

---

## 13. from / to と timezone

`from` / `to` は `YYYY-MM-DD`。

両端を含む「指定 timezone 上のローカルカレンダー日付」として解釈する。

例:

```http
GET /api/v1/symptoms?from=2026-09-05&to=2026-09-05&timezone=Asia%2FTokyo
```

概念上:

```text
recorded_at >= 2026-09-05 00:00:00 Asia/Tokyo
recorded_at <  2026-09-06 00:00:00 Asia/Tokyo
```

上限は `23:59:59.999999` ではなく、翌日の開始時刻を用いた半開区間にする。

### from のみ

```text
recorded_at >= from のローカル 00:00
```

### to のみ

```text
recorded_at < to の翌日のローカル 00:00
```

### from + to

```text
recorded_at >= from のローカル 00:00
AND
recorded_at < to の翌日のローカル 00:00
```

`from > to` は `422 VALIDATION_ERROR`。

---

## 14. timezone 契約

`timezone` は `from` / `to` の日付解釈のためだけに使用する。

IANA timezone 名を受け付ける。

Valid examples:

```text
Asia/Tokyo
America/New_York
Europe/London
```

query parameter の timezone 契約として `JST` や `+09:00` を採用しない。

以下を厳密に守る。

```text
from/to なし + timezone なし
=> valid

from または to あり + timezone あり
=> valid

from または to あり + timezone なし
=> 422 VALIDATION_ERROR

from/to なし + timezone あり
=> 422 VALIDATION_ERROR
```

無効な IANA timezone は `422 VALIDATION_ERROR`。

Python 標準の `zoneinfo.ZoneInfo` を利用してよい。

---

## 15. DST

DST のある timezone を正しく扱う。

境界計算で単純な `UTC + 24 hours` を使用してはならない。

指定 IANA timezone 上で対象日または翌日の `00:00` を作成してから UTC 境界へ変換する。

これにより 23 時間または 25 時間となるローカル日でも正しい calendar-day filter を行う。

---

## 16. recorded_at

timezone-aware な ISO 8601 / RFC 3339 datetime 必須。

Valid:

```text
2026-09-05T09:30:00+09:00
```

Naive:

```text
2026-09-05T09:30:00
```

は `422 VALIDATION_ERROR`。

### Future datetime

現在時刻より未来の `recorded_at` も許可する。backend は未来であることを理由に拒否しない。

### Response normalization

`recorded_at`, `created_at`, `updated_at` は既存 API 契約どおり UTC `Z` に正規化する。

---

## 17. Field validation

- `nausea`: integer, required, 1..10
- `abdominal_pain`: integer, required, 1..10
- `fatigue`: integer, required, 1..10
- `appetite`: integer, required, 1..10
- `bowel_condition`: optional / nullable, `NORMAL|CONSTIPATION|DIARRHEA|OTHER|null`
- `memo`: optional / nullable, max 500
- extra fields: reject

未知の `bowel_condition`、空文字、whitespace-only は拒否する。

Validation failure は `422 VALIDATION_ERROR`。

---

## 18. Error contract

既存の共通 error envelope を使用する。

```json
{
  "error": {
    "code": "SYMPTOM_NOT_FOUND",
    "message": "Symptom record was not found."
  }
}
```

Stable codes:

```text
VALIDATION_ERROR
SYMPTOM_NOT_FOUND
```

少なくとも、範囲外の尺度、必須 field 不足、invalid bowel condition、naive timestamp、invalid date/range/timezone、timezone 組合せ違反、invalid pagination、extra field、memo 超過は `VALIDATION_ERROR`。

---

## 19. Transaction / timestamp

POST / PUT / DELETE は既存 service layer の transaction 方針に従う。

DB failure 時は rollback し、中途半端な状態を残さない。予期しない DB error を domain validation error に偽装しない。

Create:

```text
created_at = backend generated
updated_at = backend generated
```

Update:

```text
created_at = unchanged
updated_at = backend updated
```

client は timestamps を指定しない。DB trigger は追加しない。

---

## 20. 推奨コード構成

既存構成に合わせ、必要に応じて:

```text
backend/app/api/v1/symptoms.py
backend/app/schemas/symptom.py
backend/app/services/symptom.py
backend/app/api/v1/router.py
backend/tests/test_symptom_api.py
```

実際の命名は既存 Weight / Nutrition 実装との整合性を優先する。

不必要な abstraction や依存ライブラリを追加しない。

---

## 21. Service responsibilities

service layer は少なくとも以下を担当する。

- create / get / update / hard delete
- history query
- filter 後 total count
- `recorded_at DESC, id DESC`
- IANA timezone から UTC query boundary を生成
- transaction rollback
- not-found domain handling

router に SQLAlchemy query や複雑な timezone 計算を集中させない。

---

## 22. 必須テスト

PostgreSQL 16 の実 DB を利用する既存テスト方針に従う。

### Create

1. valid record を作成できる
2. response timestamp が UTC `Z`
3. 同日複数件を作成できる
4. 同一 `recorded_at` でも複数件作成できる
5. optional fields 省略時 null
6. 未来の `recorded_at` を作成できる

### Validation

7. 各 1..10 field の下限・上限違反を拒否
8. 必須 field 不足を拒否
9. invalid / empty / whitespace-only bowel condition を拒否
10. naive recorded_at を拒否
11. memo > 500 を拒否
12. extra field を拒否

### GET / PUT / DELETE

13. existing ID を取得
14. missing ID は `404 SYMPTOM_NOT_FOUND`
15. 全 editable fields を更新
16. PUT で `created_at` 維持・`updated_at` 更新
17. PUT missing ID は 404、upsert しない
18. PUT invalid payload は 422
19. optional field 省略で null に更新
20. hard delete
21. delete 後 GET は 404
22. DELETE missing ID は 404

### History

23. `recorded_at DESC, id DESC`
24. 同一時刻では `id DESC`
25. pagination
26. total は pagination 前
27. default limit 50
28. invalid limit / offset を拒否

### Date / timezone

29. from + timezone
30. to + timezone
31. from + to + timezone
32. inclusive calendar-date semantics
33. from > to を拒否
34. from/to あり + timezone なしを拒否
35. timezone 単独を拒否
36. invalid IANA timezone を拒否
37. 指定 timezone のローカル日付で判定
38. DST 開始日の boundary
39. DST 終了日の boundary

### Transaction

40. DB failure 時 rollback
41. failure 後も後続 request / Session が正常

必要に応じて parameterize してよい。テスト件数自体ではなく契約保証を目的とする。

---

## 23. DST テスト方針

DST のある IANA timezone（例 `America/New_York`）を使用する。

Spring forward / fall back の双方について、

```text
local date
-> local midnight boundaries
-> UTC
```

の変換が正しいことを保証する。

テストを `UTC + 24h` 前提にしない。

---

## 24. Acceptance Criteria

- AC01: valid Symptom を POST できる
- AC02: 4尺度は integer 1..10
- AC03: recorded_at は timezone-aware 必須
- AC04: 未来 recorded_at を許可
- AC05: 同日・同一時刻を含め複数記録可能
- AC06: ID ベース GET が可能
- AC07: missing ID は `404 SYMPTOM_NOT_FOUND`
- AC08: PUT は完全更新・update-only
- AC09: DELETE は hard delete
- AC10: 履歴は `recorded_at DESC, id DESC`
- AC11: pagination は既存 API 契約準拠
- AC12: total は filter 後・pagination 前
- AC13: from/to は IANA timezone 上の inclusive calendar-date filter
- AC14: 上限は翌日 00:00 の半開区間
- AC15: DST の 23/25 時間日でも正しく filter
- AC16: from/to 指定時 timezone 必須
- AC17: timezone 単独は `422 VALIDATION_ERROR`
- AC18: invalid IANA timezone は `422 VALIDATION_ERROR`
- AC19: response timestamp は UTC `Z`
- AC20: API は診断・重症度・危険度を生成しない
- AC21: DB schema / migration 変更なし
- AC22: Weight / Nutrition / Flutter に不要な変更なし
- AC23: 既存を含む全 backend test 成功

---

## 25. Verification

実装完了後、少なくとも:

```bash
cd backend

uv run ruff format .
uv run ruff format --check .
uv run ruff check .
uv run pytest
uv run alembic check

cd ..
git diff --check
git status --short
```

PostgreSQL 16 検証 container が必要なら既存方針に従い、終了後に不要な container を削除する。

Alembic は既存 head のままとし:

```text
No new upgrade operations detected
```

を確認する。本 Spec 用 migration は作成しない。

---

## 26. Scope guardrail

実装しないもの:

- Injection API
- Dashboard API
- Flutter screen
- notification
- auth
- symptom analytics
- symptom diagnosis / severity classification
- treatment recommendation
- medication recommendation / dose adjustment
- DB schema redesign
- unrelated refactor

既存コードの別問題を発見しても、本 Spec に不要なら大規模修正せず completion report で報告する。

---

## 27. Completion report

Codex は実装完了後、以下を報告する。

1. 変更・追加 file 一覧
2. 実装 endpoint 一覧
3. validation / timezone / DST 処理概要
4. 追加 test の概要と件数
5. 実行した verification command
6. 各 command の結果
7. Alembic migration が追加されていないこと
8. scope 外変更がないこと
9. warning / unresolved issue
10. commit / push を実行していないこと

ユーザーから明示的な指示がない限り commit / push しない。
