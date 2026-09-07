# Spec 006 --- Dashboard API

## 1. 目的

MVP の Home / Dashboard 画面向けに、既存の Weight / Nutrition / Symptom
/ Injection データを read-only で集約する Dashboard API を実装する。

Dashboard は「現在の最新状態」を無条件に返す API
ではなく、クライアントが指定した `date` と `timezone` に基づく
**指定日時点のスナップショット** とする。

この Spec では Dashboard API のバックエンド実装のみを対象とする。

------------------------------------------------------------------------

## 2. 実装前に読むもの

実装前に以下を読むこと。

1.  `AGENTS.md`
2.  `docs/database-design.md`
3.  `docs/api-design.md`
4.  `specs/002-common-api-and-weight.md`
5.  `specs/003-nutrition-and-food-api.md`
6.  `specs/004-symptom-api.md`
7.  `specs/005-injection-api.md`
8.  関連する既存 router / schema / service / test

既存仕様と本 Spec が矛盾する場合は、勝手に解釈して変更せず報告すること。

------------------------------------------------------------------------

## 3. Scope

### 3.1 IN

以下を実装する。

-   `GET /api/v1/dashboard`
-   Dashboard 専用 response schema
-   Weight のスナップショット取得
-   Nutrition の指定日集計
-   Symptom の指定日最新記録取得
-   Injection のスナップショット取得
-   Injection 記録からの `next_scheduled_date` 派生計算
-   `date` / `timezone` validation
-   Dashboard API のテスト
-   必要最小限の router 登録
-   必要であれば既存 DST / timezone 境界ロジックの最小限の共通化

### 3.2 OUT

以下は実装しない。

-   Flutter / Dashboard UI
-   DB schema 変更
-   SQLAlchemy DB model 変更
-   Alembic migration
-   Weight / Nutrition / Symptom / Injection の既存 CRUD 契約変更
-   Dashboard からの作成・更新・削除
-   History UI / API の追加
-   グラフ
-   通知
-   認証 / multi-user
-   栄養目標値
-   体重評価
-   症状の診断・severity 判定
-   投与量の提案・変更
-   注射部位の推奨
-   医学的な投与日の判断
-   `next_scheduled_date` の DB 保存

------------------------------------------------------------------------

## 4. Endpoint

``` http
GET /api/v1/dashboard?date=2026-09-07&timezone=Asia/Tokyo
```

query parameter:

  parameter      required meaning
  ------------ ---------- -------------------------------------------------
  `date`              yes Dashboard が表すローカル日付。ISO `YYYY-MM-DD`
  `timezone`          yes `date` のローカル日境界を解釈する IANA timezone

成功時:

``` http
200 OK
```

記録が存在しないことはエラーではない。各 section を `UNRECORDED` として
200 を返す。

------------------------------------------------------------------------

## 5. Dashboard の基本原則 --- Snapshot Semantics

Dashboard は指定された `date` 時点のスナップショットである。

未来の記録を過去の Dashboard に混ぜてはいけない。

例:

``` text
Dashboard date = 2026-09-07

Weight:
2026-09-05
2026-09-08

Injection:
2026-09-01
2026-09-08
```

この場合:

``` text
Weight    -> 2026-09-05
Injection -> 2026-09-01
next_scheduled_date -> 2026-09-08
```

`2026-09-08` の Weight / Injection record は Dashboard の `date`
より未来なので参照しない。

一方、`next_scheduled_date` が Dashboard date
より未来になることは正常である。これは未来の record
を読んでいるのではなく、スナップショット時点で利用可能な Injection
record から派生計算しているためである。

------------------------------------------------------------------------

## 6. Response 全体

Dashboard は詳細 API のレスポンスをそのまま詰め込まず、Home
表示に必要な軽量 read model を返す。

例:

``` json
{
  "date": "2026-09-07",
  "timezone": "Asia/Tokyo",
  "weight": {
    "status": "RECORDED",
    "record": {
      "record_date": "2026-09-05",
      "weight_kg": 65.5
    }
  },
  "nutrition": {
    "status": "RECORDED",
    "record": {
      "mode": "NORMAL",
      "total_calories": 1850,
      "total_protein_g": 82.5
    }
  },
  "symptom": {
    "status": "RECORDED",
    "record": {
      "recorded_at": "2026-09-07T03:30:00Z",
      "nausea": 2,
      "abdominal_pain": 1,
      "fatigue": 4,
      "appetite": 6,
      "bowel_condition": "NORMAL"
    }
  },
  "injection": {
    "status": "RECORDED",
    "record": {
      "record_date": "2026-09-01"
    },
    "next_scheduled_date": "2026-09-08"
  }
}
```

JSON numeric values は number として返し、文字列化しない。

日時 response は既存 API 契約と同様に UTC `Z` へ正規化する。

------------------------------------------------------------------------

## 7. 共通 Section Status

Weight / Nutrition / Symptom / Injection の全 section で、存在状態を次の
2 値に統一する。

``` text
RECORDED
UNRECORDED
```

不変条件:

``` text
status == RECORDED   -> record != null
status == UNRECORDED -> record == null
```

取得失敗・DB 障害などを `UNRECORDED` として隠してはいけない。

`UNRECORDED` は「その section の契約上、対象となる persisted record
が存在しない」という正常状態だけを意味する。

------------------------------------------------------------------------

## 8. 全データ未記録時の Response

``` json
{
  "date": "2026-09-07",
  "timezone": "Asia/Tokyo",
  "weight": {
    "status": "UNRECORDED",
    "record": null
  },
  "nutrition": {
    "status": "UNRECORDED",
    "record": null
  },
  "symptom": {
    "status": "UNRECORDED",
    "record": null
  },
  "injection": {
    "status": "UNRECORDED",
    "record": null,
    "next_scheduled_date": null
  }
}
```

HTTP status は 200。

------------------------------------------------------------------------

## 9. Weight Section

### 9.1 選択ルール

以下を満たす Weight record のうち最新 1 件を返す。

``` text
weight_logs.record_date <= dashboard.date
```

order:

``` text
record_date DESC
```

`record_date` は UNIQUE なので追加 tie-breaker は不要。

### 9.2 RECORDED

``` json
{
  "status": "RECORDED",
  "record": {
    "record_date": "2026-09-05",
    "weight_kg": 65.5
  }
}
```

Dashboard response では以下を返さない。

-   id
-   recorded_at
-   memo
-   created_at
-   updated_at

### 9.3 UNRECORDED

対象 record がなければ:

``` json
{
  "status": "UNRECORDED",
  "record": null
}
```

### 9.4 Safety

Dashboard API は体重値を評価・採点・比較しない。

増減に対する肯定・否定、目標体重、減量提案などを生成しない。

------------------------------------------------------------------------

## 10. Nutrition Section

### 10.1 選択ルール

Nutrition は Dashboard の `date` 当日の `nutrition_days` だけを見る。

過去日の Nutrition を「最新」として補完しない。

`nutrition_days` row が存在しなければ `UNRECORDED`。

### 10.2 NORMAL

``` json
{
  "status": "RECORDED",
  "record": {
    "mode": "NORMAL",
    "total_calories": 1850,
    "total_protein_g": 82.5
  }
}
```

`total_calories` と `total_protein_g` は関連する `food_logs`
から算出する。

DB に集計値を保存しない。

food 一覧は Dashboard response に含めない。

### 10.3 空の NORMAL day

NORMAL の `nutrition_days` row が存在し、food が 0 件なら:

``` json
{
  "status": "RECORDED",
  "record": {
    "mode": "NORMAL",
    "total_calories": 0,
    "total_protein_g": 0.0
  }
}
```

既存 Spec 003 の契約と一致させる。

### 10.4 FREE_DAY

``` json
{
  "status": "RECORDED",
  "record": {
    "mode": "FREE_DAY",
    "total_calories": null,
    "total_protein_g": null
  }
}
```

FREE_DAY を 0 kcal / 0 protein として扱ってはいけない。

FREE_DAY は意図的に栄養計算をしない日であり、過食・補償行動等の意味を
API が推論してはいけない。

### 10.5 UNRECORDED

``` json
{
  "status": "UNRECORDED",
  "record": null
}
```

### 10.6 Nutrition mode と Dashboard status

Dashboard section の存在状態と Nutrition mode を混同しない。

``` text
nutrition.status
  RECORDED | UNRECORDED

nutrition.record.mode
  NORMAL | FREE_DAY
```

`UNRECORDED` を `record.mode` として返してはいけない。

------------------------------------------------------------------------

## 11. Symptom Section

### 11.1 選択ルール

Symptom は DATE column を持たないため、Dashboard の `date` と `timezone`
からローカル日の半開区間を作る。

概念:

``` text
lower = date     00:00:00 in requested timezone
upper = next day 00:00:00 in requested timezone
```

対象:

``` text
recorded_at >= lower
recorded_at < upper
```

その範囲内で:

``` text
recorded_at DESC, id DESC
```

の先頭 1 件を返す。

過去日の Symptom を「最新」として補完しない。

### 11.2 RECORDED

``` json
{
  "status": "RECORDED",
  "record": {
    "recorded_at": "2026-09-07T03:30:00Z",
    "nausea": 2,
    "abdominal_pain": 1,
    "fatigue": 4,
    "appetite": 6,
    "bowel_condition": "NORMAL"
  }
}
```

`bowel_condition` は既存契約通り nullable。

Dashboard response では以下を返さない。

-   id
-   memo
-   created_at
-   updated_at

### 11.3 UNRECORDED

指定ローカル日に Symptom が 1 件もなければ:

``` json
{
  "status": "UNRECORDED",
  "record": null
}
```

### 11.4 DST

Spec 004 と同じ timezone / DST semantics を使用する。

必ずローカル timezone 上で、

``` text
date 00:00
翌日 00:00
```

をそれぞれ構築してから UTC に変換する。

禁止:

-   UTC の lower boundary に単純に 24 時間を加えて upper boundary を作る
-   hard-coded JST
-   fixed offset を timezone の代わりに使う

spring-forward / fall-back の日でも正しいローカル日範囲になること。

### 11.5 Safety

Dashboard API は symptom scale
から診断、危険度、severity、治療判断等を推論しない。

保存された値を read model として返すだけとする。

------------------------------------------------------------------------

## 12. Injection Section

### 12.1 選択ルール

以下を満たす Injection record のうち最新 1 件を返す。

``` text
injection_records.record_date <= dashboard.date
```

order:

``` text
record_date DESC
```

`record_date` は UNIQUE。

未来の Injection record は過去 Dashboard に混ぜない。

### 12.2 RECORDED

``` json
{
  "status": "RECORDED",
  "record": {
    "record_date": "2026-09-01"
  },
  "next_scheduled_date": "2026-09-08"
}
```

Dashboard response では Injection 詳細を重複して返さない。

以下は含めない。

-   id
-   injected_at
-   dose_mg
-   injection_site
-   memo
-   created_at
-   updated_at

詳細は既存 Injection API の責務とする。

### 12.3 UNRECORDED

``` json
{
  "status": "UNRECORDED",
  "record": null,
  "next_scheduled_date": null
}
```

次の状態は禁止:

``` text
record == null
next_scheduled_date != null
```

------------------------------------------------------------------------

## 13. next_scheduled_date

### 13.1 計算

対象となった Injection record の:

``` text
record_date + 7 calendar days
```

で計算する。

例:

``` text
record_date = 2026-09-01
next_scheduled_date = 2026-09-08
```

DATE に対する暦日加算とする。

TIMESTAMPTZ に 168 時間を足して計算してはいけない。

### 13.2 Persistence

`next_scheduled_date` は派生値であり DB に保存しない。

DB schema / model / migration を変更しない。

### 13.3 Snapshot

未来に persisted Injection record が存在していても、その record の
`record_date` が Dashboard date より後なら計算元として使用しない。

例:

``` text
Dashboard date: 2026-09-07

Injection:
2026-09-01
2026-09-08
```

結果:

``` text
record.record_date = 2026-09-01
next_scheduled_date = 2026-09-08
```

### 13.4 Medical boundary

この値は医学的な投与日推奨ではない。

「選択された Injection record の record_date から機械的に 7
暦日後を表示する派生値」である。

API は以下を行わない。

-   dose の変更提案
-   投与可否判断
-   投与間隔の医学的調整
-   injection site の推奨
-   症状に応じた投与判断

------------------------------------------------------------------------

## 14. date Query Validation

`date` は必須。

有効な ISO date:

``` text
YYYY-MM-DD
```

として解釈する。

以下は 422:

-   `date` なし
-   invalid format
-   impossible date

error:

``` text
VALIDATION_ERROR
```

FastAPI / Pydantic の validation error も既存共通 error envelope
に統一されること。

------------------------------------------------------------------------

## 15. timezone Query Validation

`timezone` は必須。

IANA timezone のみ受理する。

有効例:

``` text
Asia/Tokyo
America/New_York
Europe/London
```

leading / trailing whitespace は trim してよい。

以下は 422 `VALIDATION_ERROR`:

-   timezone なし
-   empty string
-   whitespace only
-   invalid IANA timezone
-   `JST`
-   `+09:00`
-   `-05:00` 等の fixed offset

Spec 004 と同じ timezone contract を維持する。

Dashboard の `timezone` response には validation 後の timezone
名を返す。

------------------------------------------------------------------------

## 16. Extra Query Parameters

Dashboard のためだけに新しい strict-query 基盤を追加しない。

既存 FastAPI / プロジェクトの query parameter behavior に従う。

本 Spec のために無関係な共通 validation infrastructure を変更しない。

------------------------------------------------------------------------

## 17. Error Contract

Dashboard 固有の 404 / 409 domain error は追加しない。

記録なしは正常な 200 response。

主に使用する stable error code:

``` text
VALIDATION_ERROR
```

例:

``` json
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "The request contains invalid values.",
    "details": [
      {
        "field": "timezone",
        "message": "Invalid timezone."
      }
    ]
  }
}
```

具体的な fallback message / details の形式は既存 common API contract
に合わせる。

予期しない DB / server error は既存 500 handling に従う。

DB failure を `UNRECORDED` として隠してはいけない。

------------------------------------------------------------------------

## 18. Read-only / Side Effects

Dashboard GET は完全に read-only とする。

禁止:

-   commit
-   persisted row の create
-   persisted row の update
-   persisted row の delete
-   UNRECORDED Nutrition のために NORMAL row を自動生成すること
-   derived value の保存

Dashboard を呼ぶ前後で DB の persisted data が変化しないこと。

------------------------------------------------------------------------

## 19. 実装構成

基本構成:

``` text
backend/app/api/v1/dashboard.py
backend/app/schemas/dashboard.py
backend/app/services/dashboard.py
backend/tests/test_dashboard_api.py
```

変更:

``` text
backend/app/api/v1/router.py
```

必要であれば timezone / local-date boundary helper
の最小限の共通化を許可する。

ただし:

-   Spec 004 の Symptom API behavior を変更しない
-   unrelated refactor を行わない
-   Dashboard 実装のためだけに大規模 architecture 変更をしない

------------------------------------------------------------------------

## 20. Dashboard Service の責務

Dashboard service は Dashboard read model の query / aggregation
を担当する。

概念的な責務:

1.  Weight snapshot を取得
2.  Nutrition day を取得し totals を計算
3.  requested timezone の local-day boundary を構築
4.  指定日の最新 Symptom を取得
5.  Injection snapshot を取得
6.  Injection から `next_scheduled_date` を計算
7.  Dashboard schema に必要な値を返す

既存 CRUD endpoint を HTTP 経由で内部呼び出ししてはいけない。

既存 service の public function を無理に組み合わせて N+1
的な処理にする必要もない。

Dashboard 用 read query は `services/dashboard.py` にまとめてよい。

------------------------------------------------------------------------

## 21. Query Semantics 詳細

### Weight

``` sql
WHERE record_date <= :dashboard_date
ORDER BY record_date DESC
LIMIT 1
```

### Nutrition

``` sql
WHERE date = :dashboard_date
```

NORMAL の totals は関連 food_logs の SUM。

FREE_DAY は totals null。

### Symptom

``` text
WHERE recorded_at >= local_day_lower_utc
  AND recorded_at <  local_day_upper_utc
ORDER BY recorded_at DESC, id DESC
LIMIT 1
```

### Injection

``` sql
WHERE record_date <= :dashboard_date
ORDER BY record_date DESC
LIMIT 1
```

SQL の具体的実装は SQLAlchemy 2.x の既存 style に合わせる。

------------------------------------------------------------------------

## 22. Numeric Serialization

既存 API contract と同様に JSON numeric values は JSON number とする。

例:

``` json
{
  "weight_kg": 65.5,
  "total_calories": 1850,
  "total_protein_g": 82.5
}
```

文字列:

``` json
{
  "weight_kg": "65.5"
}
```

のようには返さない。

DB の Decimal precision を authoritative とする。

------------------------------------------------------------------------

## 23. Timestamp Serialization

Dashboard 内で timestamp を返すのは Symptom の `recorded_at`。

response は UTC `Z` へ正規化する。

例:

input / DB instant が:

``` text
2026-09-07T12:30:00+09:00
```

なら response は:

``` text
2026-09-07T03:30:00Z
```

DATE field は timezone conversion しない。

------------------------------------------------------------------------

## 24. Test Contract

最低限、以下を自動テストすること。

### 24.1 Basic response

1.  valid `date` + `timezone` で 200
2.  response に `date` と validation 後の `timezone` がある
3.  Weight / Nutrition / Symptom / Injection の全 section が常に存在する
4.  全 section が `status` と `record` を持つ
5.  Injection は常に `next_scheduled_date` key を持つ

### 24.2 All unrecorded

6.  DB に対象データがない場合すべて `UNRECORDED`
7.  各 `record` は null
8.  Injection の `next_scheduled_date` は null
9.  response は 200

### 24.3 Status invariants

10. RECORDED section の record は null ではない
11. UNRECORDED section の record は null
12. DB error を UNRECORDED として扱わない

### 24.4 Weight

13. date 当日の Weight を取得
14. date より前の最新 Weight を取得
15. date より未来の Weight を除外
16. 複数過去 Weight から record_date 最大を選択
17. 対象なしで UNRECORDED
18. response は Dashboard 用軽量 field のみ
19. weight_kg は JSON number

### 24.5 Nutrition

20. date 当日の NORMAL を取得
21. NORMAL totals を food_logs から計算
22. 複数 food の calories / protein を正しく SUM
23. 空 NORMAL は calories 0
24. 空 NORMAL は protein 0.0
25. FREE_DAY は RECORDED
26. FREE_DAY の mode は FREE_DAY
27. FREE_DAY totals は両方 null
28. nutrition_days row なしは UNRECORDED
29. 過去日の Nutrition を補完しない
30. food 一覧を response に含めない
31. UNRECORDED を record.mode として返さない

### 24.6 Symptom

32. requested local date 内の Symptom を取得
33. 同日に複数ある場合 recorded_at 最新を選択
34. recorded_at 同値なら id DESC を選択
35. 前日の Symptom を除外
36. 翌日の Symptom を除外
37. UTC 日付と requested local date が異なるケースを正しく処理
38. response recorded_at は UTC Z
39. 対象なしで UNRECORDED
40. 過去日の最新 Symptom を補完しない
41. bowel_condition null を許容
42. Dashboard 用軽量 field のみ

### 24.7 Timezone / DST

43. `Asia/Tokyo` を受理
44. `America/New_York` を受理
45. spring-forward 日の local-day boundary が正しい
46. fall-back 日の local-day boundary が正しい
47. UTC に 24h 加算する実装になっていないことを behavior で確認
48. invalid IANA timezone -\> 422 VALIDATION_ERROR
49. `JST` -\> 422 VALIDATION_ERROR
50. `+09:00` -\> 422 VALIDATION_ERROR
51. fixed negative offset -\> 422 VALIDATION_ERROR
52. empty timezone -\> 422
53. whitespace-only timezone -\> 422
54. leading/trailing whitespace を trim した有効 IANA timezone を受理

### 24.8 date validation

55. date missing -\> 422 VALIDATION_ERROR
56. invalid date format -\> 422
57. impossible date -\> 422
58. timezone missing -\> 422 VALIDATION_ERROR

### 24.9 Injection

59. date 当日の Injection を取得
60. date より前の最新 Injection を取得
61. date より未来の Injection を除外
62. 複数過去 Injection から record_date 最大を選択
63. Injection なしで UNRECORDED
64. Injection なしで next_scheduled_date null
65. Injection ありで next_scheduled_date = record_date + 7 calendar days
66. month boundary をまたぐ +7 日が正しい
67. year boundary をまたぐ +7 日が正しい
68. 未来 Injection record を next_scheduled_date の計算元にしない
69. Dashboard date より next_scheduled_date が未来でも正常
70. record null / next non-null の不整合が発生しない
71. Injection 詳細 field（dose/site 等）を Dashboard response に含めない

### 24.10 Snapshot integration

72. Weight の未来 record と Injection の未来 record
    が同時に存在しても両方除外
73. Weight / Nutrition / Symptom / Injection が同時に存在する response
    が正しい
74. Dashboard date を過去へ動かすと、その時点で利用可能だった record
    のみになる
75. Dashboard date を未来へ動かすと、その日までの persisted record
    が選択対象になる

### 24.11 Side effects

76. Dashboard GET で row count が変わらない
77. Nutrition UNRECORDED でも nutrition_days を作らない
78. next_scheduled_date を DB に保存しない
79. GET 内で commit しない
80. 既存 CRUD behavior を壊さない

テストの個数は 80 functions に分割する必要はない。parameterize
等を使用してよい。

ただし上記の契約点を意味的に網羅すること。

------------------------------------------------------------------------

## 25. Error Priority

Dashboard は read-only で domain conflict がないため、主な優先順位は
request validation。

概念:

``` text
1. FastAPI / Pydantic query schema validation
2. timezone contract validation
3. Dashboard query
4. response serialization
```

`date` / `timezone` が invalid な場合、DB query を実行して結果を
`UNRECORDED` として返してはいけない。

------------------------------------------------------------------------

## 26. Acceptance Criteria

### AC-01

`GET /api/v1/dashboard?date=<date>&timezone=<iana>` が 200 を返す。

### AC-02

Dashboard は指定 `date` 時点のスナップショットであり、未来の Weight /
Injection record を混ぜない。

### AC-03

全 section が `RECORDED | UNRECORDED` の共通 status を使用する。

### AC-04

`RECORDED -> record != null`、`UNRECORDED -> record == null` を満たす。

### AC-05

Weight は `record_date <= date` の最新 1 件。

### AC-06

Nutrition は date 当日のみを参照する。

### AC-07

Nutrition NORMAL は food_logs から日次 total を計算する。

### AC-08

空 NORMAL は 0 calories / 0.0 protein。

### AC-09

FREE_DAY は RECORDED かつ totals null。

### AC-10

Nutrition UNRECORDED と FREE_DAY を区別する。

### AC-11

Dashboard Nutrition に food 一覧を含めない。

### AC-12

Symptom は requested timezone 上の date 当日の最新 1 件。

### AC-13

Symptom の tie-breaker は `recorded_at DESC, id DESC`。

### AC-14

Symptom local-day boundary は DST を正しく扱う。

### AC-15

Injection は `record_date <= date` の最新 1 件。

### AC-16

`next_scheduled_date = selected injection.record_date + 7 calendar days`。

### AC-17

next_scheduled_date を DB に保存しない。

### AC-18

Injection record がなければ next_scheduled_date は null。

### AC-19

未来 Injection record を snapshot / next calculation に使用しない。

### AC-20

date / timezone は必須。

### AC-21

timezone は IANA timezone のみ。JST / fixed offset を拒否。

### AC-22

validation failure は既存 error envelope の `VALIDATION_ERROR`。

### AC-23

全データ未記録でも 200 + 全 section UNRECORDED。

### AC-24

Dashboard GET は DB を変更しない。

### AC-25

DB schema / SQLAlchemy model / migration を変更しない。

### AC-26

既存 Weight / Nutrition / Symptom / Injection API の behavior
を変更しない。

### AC-27

Dashboard response は詳細 CRUD response を丸ごと複製せず、定義された軽量
field のみ返す。

### AC-28

JSON numeric values は number。

### AC-29

Symptom recorded_at は UTC Z。

### AC-30

医学的判断・dose/site 推奨・症状診断・体重評価・栄養目標を追加しない。

------------------------------------------------------------------------

## 27. Verification

既存プロジェクトの実行環境を使用する。

標準コマンド:

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

ローカル環境で `uv` command が利用できず、既存 `.venv` に必要な
executable が存在する場合は、同じ environment の executable
を直接使用してよい。

例:

``` bash
cd backend

.venv/bin/ruff format .
.venv/bin/ruff format --check .
.venv/bin/ruff check .
.venv/bin/pytest
.venv/bin/alembic heads
.venv/bin/alembic upgrade head
.venv/bin/alembic check

cd ..
git diff --check
git status --short
```

PostgreSQL 16 を使用して DB-dependent tests を実行する。

期待:

``` text
Alembic head: 20260904_0001
alembic check: No new upgrade operations detected.
```

Spec 006 のために新しい migration が生成されてはいけない。

------------------------------------------------------------------------

## 28. Scope Guardrail

実装中に「ついでに」以下を変更しない。

-   existing CRUD response shape
-   existing DB constraints
-   existing model
-   migration
-   Flutter
-   Dashboard UI
-   History
-   notification
-   auth
-   deployment
-   nutrition target
-   weight goal
-   medical recommendation
-   dose logic
-   site rotation logic

必要な変更が Scope 外に見える場合は、勝手に実装せず報告する。

------------------------------------------------------------------------

## 29. 完了報告

Codex は実装完了時に以下を報告すること。

1.  変更ファイル
2.  実装した endpoint
3.  Dashboard snapshot semantics の実装概要
4.  Weight / Nutrition / Symptom / Injection の選択ルール
5.  timezone / DST 対応
6.  `next_scheduled_date` の派生計算方法
7.  validation / error behavior
8.  side-effect がないこと
9.  追加した test の概要と件数
10. Ruff / pytest / Alembic / git diff check の結果
11. Scope 外変更の有無
12. 未解決事項があれば明記

------------------------------------------------------------------------

## 30. Commit / Push

実装・verification が成功しても、ユーザーから明示的な指示があるまで
commit / push しない。

Spec 006 の実装完了報告後にレビューを受けること。
