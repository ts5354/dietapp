# Spec 005 --- Injection API

## 1. 目的

MVP の注射記録機能に必要な Injection API を実装する。

本 Spec では、既存の `injection_records`
テーブルを利用して、注射記録の作成・単一取得・完全更新・削除・履歴取得・日付範囲検索・pagination・共通
API エラー・PostgreSQL API テストを提供する。

この API
は、ユーザーが医療者から指示された内容に基づいて実際の注射記録を保存するためのものである。API
は、投与量の増減、次回投与量の決定、注射部位の推奨、治療判断、その他の医学的判断を行わない。

次回注射予定日の計算は本 Spec
では扱わない。`latest injection record_date + 7 calendar days`
というアプリ固有の派生表示ルールは Spec 006 Dashboard API で扱う。

------------------------------------------------------------------------

## 2. 実装前に読むもの

Codex は実装開始前に、少なくとも以下を読むこと。

1.  `/AGENTS.md`
2.  `/docs/database-design.md`
3.  `/docs/api-design.md`
4.  `/specs/005-injection-api.md`
5.  既存の Weight API / Nutrition API / Symptom API 実装とテスト

既存の共通 API 契約、エラー形式、SQLAlchemy Session 管理、timestamp
正規化、Decimal
の扱い、テスト方針を再利用すること。仕様間に矛盾を発見した場合、独自判断で解決せず報告すること。

------------------------------------------------------------------------

## 3. Scope

### In scope

-   Injection API 5 endpoint
-   request / response schema
-   service layer
-   router 登録
-   validation
-   `record_date` と `injected_at` の日付整合性検証
-   `record_date` に基づく history filter
-   pagination
-   stable error code
-   PostgreSQL API test

### Out of scope

-   DB schema 変更
-   Alembic migration 追加
-   Flutter 実装
-   Dashboard API
-   次回注射予定日の計算・返却
-   notification / auth
-   注射履歴 analytics
-   投与量の推奨・変更判断
-   注射部位の推奨・ローテーション判断
-   治療判断
-   medication recommendation / dose adjustment

本 Spec のために `injection_records` の DB モデルや migration
を変更してはならない。

------------------------------------------------------------------------

## 4. 使用する既存 DB

``` text
id                BIGINT PRIMARY KEY
record_date       DATE UNIQUE NOT NULL
injected_at       TIMESTAMPTZ NOT NULL
dose_mg           NUMERIC(5,2) NOT NULL CHECK dose_mg > 0
injection_site    VARCHAR NOT NULL
memo              VARCHAR(500) NULL
created_at        TIMESTAMPTZ NOT NULL
updated_at        TIMESTAMPTZ NOT NULL
```

`injection_site` の許可値:

``` text
ABDOMEN_UPPER_RIGHT
ABDOMEN_LOWER_RIGHT
ABDOMEN_UPPER_LEFT
ABDOMEN_LOWER_LEFT
THIGH_RIGHT
THIGH_LEFT
```

既存 DB 制約を authoritative としつつ API
層でも入力を検証する。`record_date` ごとに最大 1 件。同日 POST
は上書きせず、修正は PUT を使用する。

------------------------------------------------------------------------

## 5. Endpoint 一覧

``` http
POST   /api/v1/injections
GET    /api/v1/injections/{date}
PUT    /api/v1/injections/{date}
DELETE /api/v1/injections/{date}
GET    /api/v1/injections
```

単一リソース CRUD は `record_date` ベースとする。

------------------------------------------------------------------------

## 6. POST /api/v1/injections

Request:

``` json
{
  "record_date": "2026-09-07",
  "injected_at": "2026-09-07T20:30:00+09:00",
  "dose_mg": 2.5,
  "injection_site": "ABDOMEN_LOWER_RIGHT",
  "memo": "夜"
}
```

必須: `record_date`, `injected_at`, `dose_mg`, `injection_site`。

任意: `memo`。省略時 `null`。

成功: `201 Created`。

Response は DB 採番 `id`、全記録 field、`created_at`, `updated_at`
を含む。`injected_at`, `created_at`, `updated_at` は UTC `Z`
に正規化する。

client は `id`, `created_at`, `updated_at` を送信してはならない。未定義
extra field も拒否する。

------------------------------------------------------------------------

## 7. POST の重複とエラー優先順位

同じ `record_date` が既に存在する場合:

``` text
409 INJECTION_ALREADY_EXISTS
```

既存記録を暗黙に上書きしない。

schema validation 通過後の domain validation 順序:

``` text
1. record_date / injected_at の日付整合性
2. record_date duplicate
3. create
```

duplicate と date mismatch が同時に成立する場合は
`422 INJECTION_DATE_MISMATCH` を `409 INJECTION_ALREADY_EXISTS`
より優先する。

Pydantic / FastAPI の schema validation failure は domain validation
より前に `422 VALIDATION_ERROR`。

------------------------------------------------------------------------

## 8. GET /api/v1/injections/{date}

例:

``` http
GET /api/v1/injections/2026-09-07
```

成功 `200 OK`。正しい date だが存在しない場合
`404 INJECTION_NOT_FOUND`。

path は有効な ISO date `YYYY-MM-DD`
として解釈できる必要があり、不正形式または存在しない calendar date は
`422 VALIDATION_ERROR`。

------------------------------------------------------------------------

## 9. PUT /api/v1/injections/{date}

既存記録を完全更新する。upsert ではない。

``` json
{
  "injected_at": "2026-09-07T21:00:00+09:00",
  "dose_mg": 2.5,
  "injection_site": "THIGH_LEFT",
  "memo": null
}
```

必須: `injected_at`, `dose_mg`, `injection_site`。

`memo` は省略可能で、省略時 `null` として更新する。

`record_date` は body に含めない。URL `{date}` が既存 record の
`record_date` であり、PUT で変更不可。

-   `created_at` は変更しない
-   `updated_at` は backend が更新
-   missing date は `404 INJECTION_NOT_FOUND`
-   upsert しない

domain validation 順序:

``` text
1. URL record_date の既存 record を検索
2. なければ 404 INJECTION_NOT_FOUND
3. URL record_date / injected_at の日付整合性検証
4. 不一致なら 422 INJECTION_DATE_MISMATCH
5. update
```

したがって、schema-valid request で missing record と domain-level date
mismatch が同時成立する場合は `404 INJECTION_NOT_FOUND`
を優先する。request body 自体が schema-invalid なら service 到達前に
`422 VALIDATION_ERROR`。

------------------------------------------------------------------------

## 10. DELETE /api/v1/injections/{date}

hard delete。成功 `204 No Content`、body なし。

valid date だが missing: `404 INJECTION_NOT_FOUND`。

invalid path date: `422 VALIDATION_ERROR`。

------------------------------------------------------------------------

## 11. record_date / injected_at 整合性

比較には UTC 正規化後の日付や server timezone を使用せず、**request
で入力された `injected_at` 自身の UTC offset 上の calendar date**
を使用する。

Valid:

``` text
record_date = 2026-09-07
injected_at = 2026-09-07T23:30:00+09:00
```

Invalid:

``` text
record_date = 2026-09-07
injected_at = 2026-09-08T00:30:00+09:00
=> 422 INJECTION_DATE_MISMATCH
```

また、

``` text
record_date = 2026-09-08
injected_at = 2026-09-07T15:30:00Z
```

も mismatch。日本時間へ変換すると翌日でも API が勝手に `Asia/Tokyo`
として解釈しない。

PUT では URL `{date}` と `injected_at` の入力 offset
上の日付を比較する。

------------------------------------------------------------------------

## 12. injected_at

timezone-aware ISO 8601 / RFC 3339 datetime 必須。

Valid:

``` text
2026-09-07T20:30:00+09:00
2026-09-07T11:30:00Z
```

Naive datetime は `422 VALIDATION_ERROR`。

未来の `injected_at` は許可する。backend
は未来であることを理由に拒否しない。

Response の `injected_at`, `created_at`, `updated_at` は UTC `Z`
に正規化する。

------------------------------------------------------------------------

## 13. dose_mg

`dose_mg` は clinician-directed / user-entered record
として保存する値であり、API は適否、増減、次回投与量を判断・提案しない。

入力契約:

``` text
required
JSON number
> 0
小数点以下 最大 2 桁
NUMERIC(5,2) に収まる
```

backend では Decimal を用いて精度を保持する。

Valid: `2`, `2.5`, `2.50`, `12.25`。

Invalid: `0`, `-2.5`, `2.555`。

小数 2 桁超過を DB 側で暗黙に丸めてはならない。`2.555` を `2.56`
と保存せず `422 VALIDATION_ERROR`。`NUMERIC(5,2)` に収まらない値も API
validation で拒否する。

Response は JSON number。client は末尾ゼロ表現に依存しない。

------------------------------------------------------------------------

## 14. injection_site

6 許可値のみ受け付ける。request 文字列の前後空白を trim
してから検証する。

``` text
"THIGH_LEFT"   -> THIGH_LEFT
" THIGH_LEFT " -> THIGH_LEFT
"UNKNOWN"      -> 422
""             -> 422
"   "          -> 422
```

case-insensitive 変換は行わない。`thigh_left` を `THIGH_LEFT`
に自動変換しない。

API は部位を記録するだけで、推奨やローテーション判断を行わない。

------------------------------------------------------------------------

## 15. memo

optional / nullable / max 500。POST省略時
`null`、PUT省略時も完全更新として `null`。500文字超過は
`422 VALIDATION_ERROR`。

------------------------------------------------------------------------

## 16. GET /api/v1/injections --- History

Query:

``` text
from
to
limit
offset
```

`from/to` は `record_date` filter。Symptom API と異なり timezone query
は不要。

Pagination:

``` text
limit:  default 50, min 1, max 100
offset: default 0, min 0
```

invalid は `422 VALIDATION_ERROR`。

Response:

``` json
{
  "items": [],
  "total": 0,
  "limit": 50,
  "offset": 0
}
```

`total` は filter 後・pagination 前。

------------------------------------------------------------------------

## 17. History date filter

`from/to` は ISO `YYYY-MM-DD`、両端 inclusive。

``` text
from のみ: record_date >= from
to のみ:   record_date <= to
両方:      record_date >= from AND record_date <= to
```

`from > to` および invalid date query は
`422 VALIDATION_ERROR`。timezone conversion は行わない。

------------------------------------------------------------------------

## 18. 履歴の並び順

必ず:

``` sql
ORDER BY injected_at DESC, id DESC
```

同一 `injected_at` は `id DESC` tie-breaker。

------------------------------------------------------------------------

## 19. Field validation

POST:

-   `record_date`: date, required
-   `injected_at`: timezone-aware datetime, required
-   `dose_mg`: Decimal-compatible JSON number, required, `> 0`, scale
    \<= 2, `NUMERIC(5,2)` に収まる
-   `injection_site`: required, trim 後に 6 許可値
-   `memo`: optional / nullable, max 500
-   extra fields: reject

PUT:

-   `injected_at`: timezone-aware datetime, required
-   `dose_mg`: 同上
-   `injection_site`: 同上
-   `memo`: optional / nullable, max 500
-   `record_date`: body では受け付けない
-   extra fields: reject

一般 validation failure は `422 VALIDATION_ERROR`。日付整合性は
`422 INJECTION_DATE_MISMATCH`。

------------------------------------------------------------------------

## 20. Error contract

既存の共通 error envelope を使用する。

Stable codes:

``` text
VALIDATION_ERROR
INJECTION_ALREADY_EXISTS
INJECTION_NOT_FOUND
INJECTION_DATE_MISMATCH
```

`VALIDATION_ERROR`: invalid path/query date、`from > to`、naive
timestamp、invalid dose precision/range、invalid
site、memo超過、required不足、extra field等。

`INJECTION_DATE_MISMATCH`: POST の `record_date` または PUT の URL date
と、`injected_at` の入力 offset 上の日付が不一致。

`INJECTION_ALREADY_EXISTS`: POST 同日重複。ただし mismatch 同時成立時は
mismatch 優先。

`INJECTION_NOT_FOUND`: valid date の GET/PUT/DELETE missing。PUTでは
schema validation後、domain-level mismatchより存在確認優先。

------------------------------------------------------------------------

## 21. Transaction / timestamp

POST / PUT / DELETE は既存 service layer の transaction 方針に従う。DB
failure 時 rollback し、中途半端な状態を残さない。予期しない DB error を
domain validation error に偽装しない。

同日 POST の通常 duplicate は
`409 INJECTION_ALREADY_EXISTS`。application-level duplicate check
後の競合による UNIQUE constraint violation も考慮し、transaction
を壊さない安全な実装にする。

Create: `created_at` / `updated_at` は backend generated。

Update: `created_at` unchanged、`updated_at` backend updated。

DB trigger は追加しない。

------------------------------------------------------------------------

## 22. 次回注射予定日

本 Spec では計算・保存・返却しない。

以下を DB / request / response に追加しない。

``` text
next_injection_date
next_injection_at
```

`latest injection record_date + 7 calendar days` は Spec 006 Dashboard
API で扱う。

------------------------------------------------------------------------

## 23. 医療上の責務境界

実装しない:

-   `dose_mg` の適否判定
-   増量・減量・次回投与量の提案
-   注射間隔の医学的推奨
-   injection site / rotation の推奨
-   症状と dose の因果推定
-   治療判断・診断
-   medication recommendation

------------------------------------------------------------------------

## 24. 推奨コード構成

``` text
backend/app/api/v1/injections.py
backend/app/schemas/injection.py
backend/app/services/injection.py
backend/app/api/v1/router.py
backend/tests/test_injection_api.py
```

既存 Weight / Nutrition / Symptom 実装との整合性を優先し、不必要な
abstraction や依存追加をしない。

------------------------------------------------------------------------

## 25. Service responsibilities

-   create / get / update / hard delete
-   history query
-   filter 後 total count
-   `injected_at DESC, id DESC`
-   POST duplicate handling
-   入力 offset 基準の日付整合性
-   POST / PUT error priority
-   transaction rollback
-   not-found domain handling

router に SQLAlchemy query や複雑な domain validation を集中させない。

------------------------------------------------------------------------

## 26. 必須テスト

PostgreSQL 16 の実 DB を利用する既存テスト方針に従う。

### Create

1.  valid injection 作成
2.  response timestamps UTC `Z`
3.  memo省略→null
4.  future `injected_at` 許可
5.  `dose_mg` JSON number response
6.  injection_site trim

### Conflict / mismatch

7.  duplicate→409
8.  duplicateで既存record非上書き
9.  mismatch→422 `INJECTION_DATE_MISMATCH`
10. POST duplicate+mismatchでは mismatch優先

### Validation

11. naive timestamp拒否
12. dose=0拒否
13. negative dose拒否
14. 小数2桁許可
15. 小数3桁以上拒否・非丸め
16. `NUMERIC(5,2)`超過拒否
17. 6 site全て受理
18. unknown site拒否
19. empty site拒否
20. whitespace-only site拒否
21. lowercaseを自動uppercaseしない
22. memo\>500拒否
23. required不足拒否
24. extra field拒否

### GET

25. existing date取得
26. missing valid date→404
27. invalid path date→422

### PUT

28. 全editable fields更新
29. body record_date拒否
30. created_at維持 / updated_at更新
31. missing→404・非upsert
32. memo省略→null
33. existing+mismatch→422 mismatch
34. missing+mismatch→404優先
35. schema invalid→422 validation

### DELETE

36. hard delete
37. delete後GET→404
38. missing valid date→404
39. invalid path date→422

### History

40. `injected_at DESC, id DESC`
41. same timestamp `id DESC`
42. pagination
43. totalはpagination前
44. default limit50/offset0
45. invalid pagination拒否
46. from inclusive
47. to inclusive
48. from+to inclusive
49. from\>to拒否
50. invalid from/to拒否
51. filterがrecord_date基準
52. timezone不要

### Transaction / Scope

53. POST failure rollback
54. PUT failure rollback
55. DELETE failure rollback
56. failure後のrequest/session正常
57. duplicate race UNIQUE conflictでtransactionを壊さない
58. next injection fieldsを返さない
59. DB/migration変更なし
60. Weight/Nutrition/Symptom/Flutterに不要変更なし
61. 全backend test成功

parameterize可。件数より契約保証を目的とする。

------------------------------------------------------------------------

## 27. Error priority test matrix

### POST

  状態                        Expected
  --------------------------- --------------------------------
  schema invalid              `422 VALIDATION_ERROR`
  date mismatch only          `422 INJECTION_DATE_MISMATCH`
  duplicate only              `409 INJECTION_ALREADY_EXISTS`
  date mismatch + duplicate   `422 INJECTION_DATE_MISMATCH`

### PUT

  状態                                   Expected
  -------------------------------------- -------------------------------
  schema invalid                         `422 VALIDATION_ERROR`
  existing + date mismatch               `422 INJECTION_DATE_MISMATCH`
  missing + date match                   `404 INJECTION_NOT_FOUND`
  missing + domain-level date mismatch   `404 INJECTION_NOT_FOUND`

schema-invalid request で404を優先させる特殊処理は実装しない。

------------------------------------------------------------------------

## 28. Acceptance Criteria

-   AC01: valid Injection POST
-   AC02: `record_date` ごと最大1件
-   AC03: duplicate→409
-   AC04: mismatch→422 domain code
-   AC05: POST mismatch \> duplicate
-   AC06: timezone-aware `injected_at`
-   AC07: future timestamp許可
-   AC08: input offset基準の日付比較
-   AC09: `dose_mg > 0`
-   AC10: dose小数最大2桁、超過時非丸め422
-   AC11: `NUMERIC(5,2)`範囲内
-   AC12: site trim後6値のみ
-   AC13: dateベース GET/PUT/DELETE
-   AC14: invalid path date→422
-   AC15: missing valid date→404
-   AC16: PUT完全更新・update-only
-   AC17: PUT existence \> domain mismatch
-   AC18: hard delete
-   AC19: history record_date inclusive filter
-   AC20: `injected_at DESC, id DESC`
-   AC21: pagination共通契約
-   AC22: totalはfilter後pagination前
-   AC23: response timestamps UTC Z
-   AC24: numeric response JSON number
-   AC25: DB failure rollback
-   AC26: next injection date非実装
-   AC27: 医学的推奨非生成
-   AC28: DB schema/migration変更なし
-   AC29: unrelated scope変更なし
-   AC30: 全backend test成功

------------------------------------------------------------------------

## 29. Verification

``` bash
cd backend

uv run ruff format .
uv run ruff format --check .
uv run ruff check .
uv run pytest
uv run alembic heads
uv run alembic upgrade head
uv run alembic check

cd ..
git diff --check
git status --short
```

PostgreSQL 16 検証 container は既存方針に従い、終了後不要 container
を削除。

Alembic は既存 head `20260904_0001` のまま。本 Spec migration
は作成しない。

`uv run alembic check` で `No new upgrade operations detected`
を確認する。

------------------------------------------------------------------------

## 30. Scope guardrail

実装しない:

-   Dashboard API
-   next injection date calculation
-   Flutter screen
-   notification / auth
-   injection analytics
-   dose recommendation / adjustment
-   injection-site recommendation
-   treatment / medication recommendation
-   DB schema redesign
-   unrelated refactor

特に `next_injection_date` / `next_injection_at` を Injection API や DB
に先行追加しない。

------------------------------------------------------------------------

## 31. Completion report

Codex は実装完了後、以下を報告する。

1.  変更・追加 file 一覧
2.  実装 endpoint 一覧
3.  `record_date` / `injected_at` validation 概要
4.  Decimal / `dose_mg` validation 概要
5.  injection_site trim / enum validation 概要
6.  POST / PUT error priority 概要
7.  追加 test 概要と件数
8.  verification command
9.  各 command 結果
10. Alembic migration 非追加
11. next injection date 非実装
12. scope 外変更なし
13. warning / unresolved issue
14. commit / push 未実行

ユーザーから明示的な指示がない限り commit / push しない。
