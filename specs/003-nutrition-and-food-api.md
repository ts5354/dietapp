# Spec 003: 栄養・食事API

## 1. 目的

MVP向けの栄養日（Nutrition Day）および食事記録（Food
Log）APIを実装する。

このSpecでは、NORMAL / FREE_DAY / 仮想UNRECORDED、Food Log
CRUD、日次カロリー・タンパク質集計、栄養日履歴、関連するドメインバリデーションを実装する。

既存のデータベーススキーマおよびAPI規約に従い、このSpecではデータベーススキーマを変更しない。

------------------------------------------------------------------------

## 2. 実装前に読むもの

1.  `AGENTS.md`
2.  `docs/database-design.md`
3.  `docs/api-design.md`
4.  `specs/001-initial-database-migration.md`
5.  `specs/002-common-api-and-weight.md`
6.  現在のバックエンド実装

Spec 002の共通エラー処理、ページネーション、DB
Session管理、バリデーション基盤を再利用する。矛盾を発見した場合は勝手に解釈せず停止して報告する。

------------------------------------------------------------------------

## 3. スコープ

### 対象

-   Nutrition Day取得・作成・モード更新・履歴
-   Food Log作成・更新・削除
-   UNRECORDEDへのFood追加時のNORMAL自動作成
-   NORMAL / FREE_DAYドメインルール
-   仮想UNRECORDED
-   日次calories / protein_g集計
-   Foodの日付整合性
-   日付filter / pagination
-   安定したAPIエラー
-   PostgreSQL APIテスト

### 対象外

Weight変更、Symptom、Injection、Dashboard、Flutter
UI、認証、マルチユーザー、通知、食品DB、バーコード、写真、AI、栄養目標・推奨、水分記録、offline
sync、cloud deploy、PATCH、Nutrition Day全体DELETE、DB
schema/constraint/trigger/migration変更。

Alembic headは既存の`20260904_0001`から変更しない。

------------------------------------------------------------------------

## 4. 既存DBモデル

### `nutrition_days`

`id`, `date`, `mode`, `memo`, `created_at`, `updated_at`

DBに保存可能なmodeは`NORMAL` /
`FREE_DAY`のみ。`UNRECORDED`は保存しない。

### `food_logs`

`id`, `nutrition_day_id`, `name`, `calories`, `protein_g`, `eaten_at`,
`memo`, `created_at`, `updated_at`

既存FK/CASCADEを変更しない。

------------------------------------------------------------------------

## 5. Nutrition Dayの状態

### 5.1 NORMAL

0件以上のFood Logを持てる。calories / protein_g合計はFood
Logから動的計算し、集計値をDB保存しない。

空NORMALは`total_calories: 0`, `total_protein_g: 0.0`, `foods: []`。

### 5.2 FREE_DAY

Food Logを持たない。レスポンスは`total_calories: null`,
`total_protein_g: null`, `foods: []`。

FREE_DAYを0 kcal / 0
gとして扱わない。栄養計算を行わない日として扱い、食事制限・補償・目標値・栄養推奨を実装しない。

### 5.3 UNRECORDED

`nutrition_days`行がない日の仮想状態。詳細GETではHTTP 200で以下を返す。

``` json
{
  "date": "2026-09-04",
  "mode": "UNRECORDED",
  "memo": null,
  "total_calories": null,
  "total_protein_g": null,
  "foods": []
}
```

GETだけではDB行を作らず、DB modeにも保存せず、履歴にも出さない。

------------------------------------------------------------------------

## 6. API

``` text
GET    /api/v1/nutrition/days
GET    /api/v1/nutrition/days/{date}
PUT    /api/v1/nutrition/days/{date}
POST   /api/v1/nutrition/days/{date}/foods
PUT    /api/v1/nutrition/days/{date}/foods/{id}
DELETE /api/v1/nutrition/days/{date}/foods/{id}
```

これ以外のNutrition/Food endpointは追加しない。

------------------------------------------------------------------------

## 7. GET /api/v1/nutrition/days/{date}

pathは`YYYY-MM-DD`。

NORMALではFoodを`eaten_at ASC, id ASC`で返し、合計を動的計算する。FREE_DAYは合計null・foods空。存在しない日はUNRECORDEDをHTTP
200で返し、DBを変更しない。

------------------------------------------------------------------------

## 8. PUT /api/v1/nutrition/days/{date}

このendpointのみPUT upsertの例外。

``` json
{"mode":"NORMAL","memo":null}
```

modeは`NORMAL` /
`FREE_DAY`のみ。`UNRECORDED`や未知値、空文字、空白のみは拒否。extra
field拒否。memoはnull可・最大500文字。

状態遷移：

-   UNRECORDED -\> NORMAL: 空NORMALを作成、200
-   UNRECORDED -\> FREE_DAY: FREE_DAYを作成、200
-   FoodなしNORMAL -\> FREE_DAY: 許可
-   FoodありNORMAL -\> FREE_DAY: `409 FREE_DAY_HAS_FOOD_LOGS`
-   FREE_DAY -\> NORMAL: 空NORMALへ
-   同一mode PUT: 許可、memo更新可

FoodありNORMALからFREE_DAYへの失敗時、Food削除・mode変更を一切行わない。

------------------------------------------------------------------------

## 9. POST /api/v1/nutrition/days/{date}/foods

request:

``` json
{
  "name": "朝食",
  "calories": 350,
  "protein_g": 20.0,
  "eaten_at": "2026-09-04T08:30:00+09:00",
  "memo": null
}
```

成功201。responseは`id`, `name`, `calories`, `protein_g`, `eaten_at`,
`memo`, `created_at`, `updated_at`。

`nutrition_day_id`はclientに送らせない。

-   UNRECORDED: NORMAL作成 + Food作成を1 transactionでatomicにcommit
-   NORMAL: 作成可
-   FREE_DAY: `409 FOOD_NOT_ALLOWED_ON_FREE_DAY`

失敗時に自動作成NORMALだけを残さない。

------------------------------------------------------------------------

## 10. Foodの日付整合性

URL dateと、送信された`eaten_at`のtimezone offset上のcalendar
dateが一致する必要がある。

`2026-09-04T00:30:00+09:00`はUTCでは前日でも、URLが`2026-09-04`なら有効。

`/2026-09-04/...`に`2026-09-05T00:30:00+09:00`を送るのは無効で、`422 FOOD_DATE_MISMATCH`。

日付所属を判定する前にUTC変換しない。naive datetimeも拒否。

------------------------------------------------------------------------

## 11. PUT /api/v1/nutrition/days/{date}/foods/{id}

Foodを完全更新。request fieldsは`name`, `calories`, `protein_g`,
`eaten_at`, `memo`のみ。

`id`, `nutrition_day_id`, managed timestampsなどextra
fieldを拒否。update-onlyでupsertしない。

存在しないFood、または別Nutrition
Dayに属するFoodは`404 FOOD_NOT_FOUND`。別の日へ移動させない。eaten_at
mismatchは`422 FOOD_DATE_MISMATCH`。

------------------------------------------------------------------------

## 12. DELETE /api/v1/nutrition/days/{date}/foods/{id}

hard delete。成功204、body空。

存在しないFood、別Nutrition Day所属Foodは`404 FOOD_NOT_FOUND`。

最後のFoodを消してもNutrition
Dayは空NORMALとして残し、UNRECORDED化・自動削除しない。

------------------------------------------------------------------------

## 13. GET /api/v1/nutrition/days

persist済みNutrition Dayのみ。UNRECORDEDは生成しない。

query: `from`, `to`, `limit`, `offset`

-   date range inclusive
-   limit default 50 / max 100 / min 1
-   offset default 0 / min 0
-   from \> toは422 VALIDATION_ERROR
-   `date DESC`
-   `total`はpagination前filtered count

response:

``` json
{"items":[],"total":0,"limit":50,"offset":0}
```

各itemに最低限`date`, `mode`, `memo`, `total_calories`,
`total_protein_g`。NORMALは動的集計、FREE_DAYは両方null。Food一覧は履歴itemへ埋め込まなくてよい。

------------------------------------------------------------------------

## 14. Food validation

明示的Pydantic schemaを使いextra fieldを拒否。

-   `name`: required string、前後trim、trim後空禁止、max 100
-   `calories`: required integer、\>= 0
-   `protein_g`: required numeric、\>= 0、DB `NUMERIC(6,2)`精度に従う
-   `eaten_at`: required timezone-aware datetime、naive禁止
-   `memo`: optional/null、max 500

numeric responseはJSON number。timestamp responseはUTC `Z`へ正規化。

------------------------------------------------------------------------

## 15. Nutrition Day validation

mode requestは`NORMAL` / `FREE_DAY`のみ。PostgreSQL
ENUMは導入しない。memoはoptional/null、max 500。

------------------------------------------------------------------------

## 16. 安定したエラーコード

最低限：

``` text
VALIDATION_ERROR
FOOD_NOT_ALLOWED_ON_FREE_DAY
FOOD_DATE_MISMATCH
FOOD_NOT_FOUND
FREE_DAY_HAS_FOOD_LOGS
```

既存形式：

``` json
{
  "error": {
    "code": "ERROR_CODE",
    "message": "Human-readable fallback message.",
    "details": []
  }
}
```

`details`は任意。FastAPI/Pydantic標準`detail`を露出しない。予期しないDB
errorをdomain errorへ誤変換しない。

------------------------------------------------------------------------

## 17. Transaction

UNRECORDEDへのFood
POSTではNORMAL作成とFood作成を同一transactionにする。どちらかが失敗したら全rollback。

FoodありNORMAL -\>
FREE_DAYは永続化変更前にFood存在を確認し、Foodを暗黙削除しない。

------------------------------------------------------------------------

## 18. Timestamp

Spec 002の共通ルールに従う。

event timestamp inputはtimezone必須。outputはUTC/RFC3339互換、UTCは`Z`。

`created_at` /
`updated_at`はbackend管理。create時に両方設定、update時はupdated_atのみ更新、created_at維持。Nutrition
DayのDATEはtimezone変換しない。

------------------------------------------------------------------------

## 19. 推奨構成

``` text
backend/app/api/v1/nutrition.py
backend/app/schemas/nutrition.py
backend/app/services/nutrition.py
backend/tests/test_nutrition_api.py
```

既存`errors.py`, `dependencies.py`,
`api/v1/router.py`を再利用。不要な抽象化を増やさない。

------------------------------------------------------------------------

## 20. Service層の責務

主に以下：

-   persisted Nutrition Day取得
-   UNRECORDED response用データ
-   Nutrition Day作成・更新
-   FREE_DAY遷移前Food確認
-   Food作成
-   NORMAL自動作成 + Food作成atomic処理
-   nested Food更新/削除
-   NORMAL日次集計
-   Nutrition Day履歴・filtered count

医療・栄養推奨ロジックを入れない。

------------------------------------------------------------------------

## 21. 必須テスト

migration適用済みPostgreSQLを使用し、SQLiteで代用しない。

### 詳細

-   UNRECORDEDは200
-   GETでDB行を作らない
-   空NORMALは0 totals
-   FoodありNORMALの集計
-   Food order `eaten_at ASC, id ASC`
-   FREE_DAYはnull totals / foods \[\]

### 状態遷移

-   UNRECORDED -\> NORMAL
-   UNRECORDED -\> FREE_DAY
-   empty NORMAL -\> FREE_DAY
-   FoodありNORMAL -\> FREE_DAYは409
-   409後もmode/Food不変
-   FREE_DAY -\> NORMAL
-   same-mode memo update
-   UNRECORDED request拒否
-   extra field拒否

### Food create

-   NORMALへ作成
-   UNRECORDEDでNORMAL自動作成
-   NORMAL+Food永続化
-   FREE_DAYで409
-   failure時FREE_DAY不変
-   mismatch 422
-   UTC dateが違ってもoffset local date一致なら成功
-   naive timestamp拒否
-   invalid calories/protein拒否
-   blank/whitespace/overlong name拒否
-   extra field拒否

### Food update

-   正常更新
-   created_at維持 / updated_at更新
-   missing 404
-   other-day 404
-   day移動不可
-   mismatch 422
-   extra field拒否

### Food delete

-   204 + empty body
-   hard delete
-   missing 404
-   other-day 404
-   last Food削除後もempty NORMAL

### History

-   persisted daysのみ
-   UNRECORDEDなし
-   date DESC
-   NORMAL totals
-   FREE_DAY totals null
-   inclusive from/to
-   pagination
-   total before pagination
-   default limit/offset
-   invalid limit/offset/range/dateは422

### 共通契約

失敗responseが`{"error":{"code":"...","message":"..."}}`形式で、FastAPI標準`detail`を露出しない。

------------------------------------------------------------------------

## 22. Acceptance Criteria

-   AC-01: detail GETがNORMAL / FREE_DAY / UNRECORDEDを正しく返す
-   AC-02: UNRECORDED GETでDBを変更しない
-   AC-03: Food nested CRUDが動作
-   AC-04: UNRECORDED Food POSTでNORMALをatomic作成
-   AC-05: FREE_DAYへFood追加不可
-   AC-06: FoodありNORMAL -\> FREE_DAY不可
-   AC-07: mode変更でFoodを暗黙削除しない
-   AC-08: FREE_DAY -\> empty NORMAL可能
-   AC-09: eaten_atは送信offset上の日付でURL dateと一致必須
-   AC-10: NORMAL totalsは動的計算・非保存
-   AC-11: FREE_DAY totalsは0でなくnull
-   AC-12: UNRECORDEDをDB modeに保存しない
-   AC-13: historyはpersist済み日のみdate DESC
-   AC-14: historyはinclusive filter + pagination
-   AC-15: domain/validation errorが共通contract
-   AC-16: input timezone必須、output UTC
-   AC-17: schema/migration変更なし
-   AC-18: Spec 000/001/002既存test pass
-   AC-19: Spec 003 testがPostgreSQLでpass
-   AC-20: Ruff format/lint pass

------------------------------------------------------------------------

## 23. 検証

`backend`で：

``` bash
uv sync --dev
uv run ruff format .
uv run ruff format --check .
uv run ruff check .
uv run pytest
uv run alembic heads
uv run alembic check
```

Alembic head expected:

``` text
20260904_0001
```

repository rootで：

``` bash
git diff --check
```

`alembic check`のためだけにmigrationを作らない。

------------------------------------------------------------------------

## 24. 完了報告

実装後に以下を報告：

1.  新規ファイル
2.  変更ファイル
3.  実装endpoint
4.  実装domain rule
5.  追加test
6.  実行command
7.  test/lint/migration結果
8.  warning/未解決事項
9.  DB schema未変更の確認
10. scope外機能未実装の確認

commit /
pushは自動実行しない。実装・検証完了時点で停止し、commit前レビュー可能な状態にする。
