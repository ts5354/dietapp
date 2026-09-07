# Spec 009 — Flutter Food UI / Nutrition & Free Day

## 1. 目的

Spec 003 で実装済みの Nutrition / Food API と、Spec 007 の Flutter API 通信基盤を利用し、Flutter から日単位の Nutrition 状態と Food Log を記録・編集できる UI を実装する。

Spec 009 の完成状態では、ユーザーが指定日について以下を行えること。

- NORMAL / FREE_DAY / UNRECORDED を確認する
- 未記録日から通常記録を開始する
- 食事イベントを追加する
- 食事イベントを編集する
- 食事イベントを削除する
- 当日の calories / protein の記録合計を確認する
- FREE_DAY に切り替える
- FREE_DAY から NORMAL に戻す
- FREE_DAY と「0 kcal」や「未記録」を混同しない
- API / domain conflict / validation error を安全に扱う

本アプリにおける FREE_DAY は「栄養計算をしない日」を表す記録状態であり、過食・補償・制限を意味するものとして扱わない。

## 2. 実装前に読むもの

Codex は実装前に以下を読むこと。

1. `AGENTS.md`
2. `README.md`
3. `docs/api-design.md`
4. `docs/database-design.md`
5. `specs/003-nutrition-and-food-api.md`
6. `specs/006-dashboard-api.md`
7. `specs/007-flutter-api-foundation.md`
8. `specs/008-flutter-weight-ui.md`
9. `mobile/pubspec.yaml`
10. `mobile/lib/`
11. `mobile/test/`
12. backend の Nutrition / Food router, schemas, services, tests

Nutrition / Food の authoritative contract は Spec 003 と実際の backend 実装とする。

矛盾を発見した場合、backend を勝手に変更せず報告する。

## 3. Scope

### 3.1 IN

- Nutrition day domain model
- Food log domain model
- Nutrition / Food request model
- Nutrition / Food repository
- Riverpod controller / provider
- Food screen
- 指定日の Nutrition 状態表示
- 日付変更
- NORMAL / FREE_DAY / UNRECORDED の表現
- Food Log 一覧
- Food Log create
- Food Log update
- Food Log delete
- Nutrition day mode update
- FREE_DAY への切替
- FREE_DAY → NORMAL
- calories / protein の日次記録合計表示
- loading / empty / error / conflict state
- local validation
- stale response 対策
- duplicate mutation 防止
- delete confirmation
- FREE_DAY 切替 confirmation
- Record menu → Food screen navigation
- unit / widget tests

### 3.2 OUT

- Nutrition history
- Food history across multiple days
- calorie / protein graph
- calorie target
- protein target
- remaining calories
- deficit / surplus
- food recommendation
- dietary judgment
- meal plan
- food database
- barcode
- photo
- AI analysis
- water
- Dashboard UI
- Symptom UI
- Injection UI
- authentication
- offline/cache/retry
- notification
- backend / DB / migration changes

## 4. Backend Endpoints

使用する endpoint:

```http
GET    /api/v1/nutrition/days/{date}
PUT    /api/v1/nutrition/days/{date}

POST   /api/v1/nutrition/days/{date}/foods
PUT    /api/v1/nutrition/days/{date}/foods/{id}
DELETE /api/v1/nutrition/days/{date}/foods/{id}
```

Spec 009 の画面では Nutrition days list endpoint は使用しなくてよい。

## 5. Nutrition State

概念上、日単位で以下の3状態がある。

```text
NORMAL
FREE_DAY
UNRECORDED
```

重要:

```text
UNRECORDED != NORMAL
UNRECORDED != FREE_DAY
FREE_DAY != 0 kcal
```

`UNRECORDED` は DB mode ではなく、GET day endpoint が返す virtual read state。

Flutter では enum 等で明示的に区別する。

unknown mode を fallback で NORMAL にしない。CONTRACT error とする。

## 6. GET Day Contract

```http
GET /api/v1/nutrition/days/2026-09-07
```

### NORMAL

概念:

```json
{
  "date": "2026-09-07",
  "mode": "NORMAL",
  "memo": null,
  "total_calories": 1850,
  "total_protein_g": 82.5,
  "foods": []
}
```

Food は:

```text
eaten_at ASC, id ASC
```

の backend ordering を保持する。

### Empty NORMAL

Food が0件の NORMAL day:

```text
total_calories = 0
total_protein_g = 0.0
foods = []
```

### FREE_DAY

```json
{
  "date": "2026-09-07",
  "mode": "FREE_DAY",
  "memo": null,
  "total_calories": null,
  "total_protein_g": null,
  "foods": []
}
```

FREE_DAY では totals を 0 と解釈しない。

### UNRECORDED

```json
{
  "date": "2026-09-07",
  "mode": "UNRECORDED",
  "memo": null,
  "total_calories": null,
  "total_protein_g": null,
  "foods": []
}
```

UNRECORDED を FREE_DAY として扱わない。

## 7. Food Log

最低限:

```text
id
nutritionDayId
name
calories
proteinG
eatenAt
memo
createdAt
updatedAt
```

実際の backend response field に合わせること。

Food response の timestamp は Spec 003 / common API contract に従って厳密に parse する。

unknown additive fields は許容してよい。

必須 field の欠落、型不一致、unknown enum、invalid timestamp は CONTRACT error。

## 8. Food Create Request

概念:

```json
{
  "name": "昼食",
  "calories": 600,
  "protein_g": 25.5,
  "eaten_at": "2026-09-07T12:30:00+09:00",
  "memo": null
}
```

`nutrition_day_id` を Flutter から送らない。

URL の date が親日を表す。

## 9. Food Update Request

概念:

```json
{
  "name": "昼食",
  "calories": 620,
  "protein_g": 26.0,
  "eaten_at": "2026-09-07T12:45:00+09:00",
  "memo": null
}
```

PUT は complete update。

`id`, `nutrition_day_id`, `created_at`, `updated_at` を request body に含めない。

## 10. Food Input Form

Food create / edit form:

```text
食事を記録

名前
[             ]

カロリー
[             ] kcal

たんぱく質
[             ] g

時刻
[ 12:30 ]

メモ（任意）
[             ]

[ 保存 ]
```

edit:

```text
食事を編集
...
[ 更新 ]
[ 記録を削除 ]
```

「朝食・昼食・夕食」という固定カテゴリを必須化しない。

1 eating event = 1 Food Log。

## 11. Food Name Validation

backend contract に合わせる。

- required
- trim 後 empty / whitespace-only reject
- max 100 characters
- request では trim 済み name を送る

## 12. Calories Validation

backend:

```text
INTEGER
CHECK calories >= 0
```

Flutter:

- required
- integer only
- >= 0
- JSON integer として送る
- negative reject
- decimal reject
- non-numeric reject
- silent rounding 禁止

0 は有効。

calories を「摂取上限」や「残り」と比較しない。

## 13. Protein Validation

backend:

```text
NUMERIC(6,2)
CHECK protein_g >= 0
```

Flutter:

- required
- numeric
- finite
- >= 0
- 小数第2位まで
- backend precision を明らかに超える値を reject
- silent rounding 禁止
- JSON number として送る

0 は有効。

protein target は実装しない。

## 14. eaten_at

Food の `eaten_at` は timezone-aware timestamp。

UI は selected nutrition date + selected local time を基本とする。

送信:

```text
selected date + selected time + local timezone offset
```

Spec 008 で作成した timezone-aware timestamp serializer を再利用する。

同目的の serializer を複製しない。

固定 `+09:00` 禁止。

## 15. Food Date Invariant

Food の `eaten_at` が表す calendar date は URL の nutrition day date と一致する必要がある。

Flutter UI は selected day + time から `eaten_at` を作ることで、通常操作では一致するようにする。

backend は authoritative。

backend:

```text
422 FOOD_DATE_MISMATCH
```

を返した場合、CONTRACT/UNRECORDED等に変換せず domain error として保持する。

## 16. Memo

Food memo:

- nullable
- max 500
- empty / whitespace-only は `null` として送ってよい
- 500文字超過は送信前 reject

Nutrition day memo も backend contract に存在する場合は model と mode update request で保持する。

Spec 009 UI では day memo の編集 UI は必須ではない。既存値を不用意に消さないこと。

## 17. Add Food from UNRECORDED

Spec 003 の重要な contract:

```text
UNRECORDED
  + POST food
  ↓
backend が NORMAL nutrition_day を自動作成
  + food を atomically create
```

Flutter は Food 追加前に別途 NORMAL day を作成する必要はない。

つまり:

```text
GET -> UNRECORDED
POST /foods
GET/response reconciliation
→ NORMAL
```

を利用する。

不要な PUT `/nutrition/days/{date}` を先に送らない。

## 18. Add Food on FREE_DAY

FREE_DAY では Food を追加できない。

backend:

```text
409 FOOD_NOT_ALLOWED_ON_FREE_DAY
```

UI でも FREE_DAY 中は Food追加 action を無効 / 非表示にする。

それでも backend conflict が返った場合は正常にerrorとして扱う。

FREE_DAY を勝手に NORMAL に戻して Food を追加しない。

## 19. Nutrition Day PUT

```http
PUT /api/v1/nutrition/days/{date}
```

body:

```json
{
  "mode": "FREE_DAY",
  "memo": null
}
```

または:

```json
{
  "mode": "NORMAL",
  "memo": null
}
```

PUT は Nutrition day に限って create を許す既存 contract。

Flutter はこの例外的 semantics をそのまま利用する。

## 20. FREE_DAYへの切替

### UNRECORDED → FREE_DAY

許可。

```text
PUT mode=FREE_DAY
```

### Empty NORMAL → FREE_DAY

許可。

### NORMAL with foods → FREE_DAY

backend:

```text
409 FREE_DAY_HAS_FOOD_LOGS
```

Food を silent delete してはいけない。

UI でも Food が存在する場合は、FREE_DAY切替を禁止または明確に案内する。

推奨:

```text
この日には食事記録があります。Free Dayに変更するには、先に食事記録を削除してください。
```

Food の一括削除は実装しない。

## 21. FREE_DAY → NORMAL

許可。

```http
PUT /nutrition/days/{date}

{
  "mode": "NORMAL",
  "memo": ...
}
```

結果は empty NORMAL。

Food を自動作成しない。

## 22. FREE_DAY Meaning in UI

表示名:

```text
Free Day
```

補助説明を置く場合:

```text
この日は栄養計算をしない日として記録されています。
```

以下のような意味付けは禁止。

```text
チートデイ
好きなだけ食べる日
食べすぎてもよい日
翌日に調整する日
カロリーを取り戻す日
```

FREE_DAY は単なる logging mode。

## 23. Daily Totals

NORMAL のみ:

```text
記録合計
1,850 kcal
82.5 g protein
```

のように表示してよい。

ただし「目標」「残り」「超過」「不足」は表示しない。

Empty NORMAL:

```text
0 kcal
0 g protein
```

は記録合計として有効。

FREE_DAY:

```text
栄養計算なし
```

等を表示し、`0 kcal / 0 g` と表示しない。

UNRECORDED:

```text
まだ食事記録がありません
```

等とし、0 kcal と表示しない。

## 24. Food List

NORMAL の場合、当日の Food Logs を一覧表示する。

最低限:

```text
name
eaten_at の時刻
calories
protein_g
```

memo は一覧で必須ではない。

backend ordering:

```text
eaten_at ASC, id ASC
```

を基本的にそのまま表示する。

Flutter 側で意味の異なる並べ替えをしない。

Food tap → edit form を開ける。

## 25. Food Create / Edit Presentation

Food form は同一 screen 内 dialog / bottom sheet / route のいずれでもよい。

既存構成に最も単純に適合する方法を選ぶ。

過剰な navigation architecture を追加しない。

## 26. Delete Food

Food edit 時に delete action を提供する。

削除前:

```text
この食事記録を削除しますか？
```

```text
キャンセル
削除
```

DELETE success 後:

- 対象 Food を UI から除去
- totals を backend truth と一致させる
- NORMAL day は残る
- 最後の Food を削除しても UNRECORDED にしない
- Empty NORMAL として扱う

最も安全で単純な実装として、mutation success 後に GET day を再取得してよい。

## 27. Reconciliation Strategy

Nutrition totals は backend が authoritative。

Flutter で calories / protein の totals を独自再計算して backend response の代わりに authoritative としない。

mutation 後は以下のどちらか。

1. mutation response が day全体を完全に返すならそれを使用
2. GET day を再実行して authoritative state を取得

既存 API contract 上、Food mutation response が day totals を保証しない場合は 2 を使用する。

推奨:

```text
POST/PUT/DELETE Food
→ GET /nutrition/days/{date}
→ state更新
```

Nutrition mode PUT 後も必要なら GET でreconcileする。

## 28. Loading State

最低限:

```text
initial loading
ready
error
busy mutation
```

を区別する。

initial GET failure を UNRECORDED として扱わない。

mutation 中は対象操作の二重送信を防ぐ。

## 29. Stale Response

Spec 008 と同様、日付変更と非同期処理の競合を防ぐ。

例:

```text
date A GET
→ date Bへ変更
→ A GET完了
```

A が B を上書きしてはいけない。

mutation:

```text
date A POST/PUT/DELETE
→ date Bへstate変更
→ A完了
```

も B を上書きしない。

mutation後のreconciliation GETも同様。

generation token + operation date 等、Spec 008 の実装を再利用 / 一貫させる。

## 30. Form State Synchronization

日付変更時に前日の Food form 値を新しい日へ持ち越さない。

create Food form を開く場合:

```text
name = empty
calories = empty
protein = empty
time = current local time
memo = empty
```

selected date は現在の Nutrition day date。

edit form は selected Food の値を prefill。

edit中に selected day が変わった場合、古い Food を新しい day へ PUT しない。

## 31. Error Semantics

stable backend codes を保持する。

最低限:

```text
VALIDATION_ERROR
FOOD_NOT_ALLOWED_ON_FREE_DAY
FOOD_DATE_MISMATCH
FOOD_NOT_FOUND
FREE_DAY_HAS_FOOD_LOGS
```

### FOOD_NOT_ALLOWED_ON_FREE_DAY

```text
Free Dayには食事記録を追加できません。
```

### FOOD_DATE_MISMATCH

```text
食事の日時と記録日が一致していません。
```

### FOOD_NOT_FOUND

```text
この食事記録は見つかりませんでした。再読み込みしてください。
```

### FREE_DAY_HAS_FOOD_LOGS

```text
この日には食事記録があります。Free Dayに変更するには、先に食事記録を削除してください。
```

Network:

```text
サーバーに接続できませんでした。
```

Timeout:

```text
通信がタイムアウトしました。
```

Fallback:

```text
食事記録の処理中にエラーが発生しました。
```

## 32. Domain Conflict Handling

409 を transport success / contract failure と誤認しない。

`ApiException` の:

```text
statusCode
code
message
details
kind
```

を Spec 007 と同様に保持する。

UI は stable code から日本語 message を選ぶ。

## 33. Numeric Display

API number は自然な表示にする。

例:

```text
600 kcal
25.5 g
```

不要な:

```text
25.500000 g
```

は避ける。

ただし表示整形によって保存値を変更しない。

## 34. Record Menu Navigation

既存 Record menu に:

```text
[ 食事 ]
```

action を追加し、Food screen へ遷移できるようにする。

例:

```text
/record/food
```

route naming は既存 convention を優先。

Weight route を壊さない。

Symptom / Injection は Spec 009 で実装しない。

## 35. Accessibility / UX

- name は通常 text keyboard
- calories は integer numeric keyboard
- protein は decimal numeric keyboard
- kcal / g unit を明示
- memo は multiline
- field label を明示
- loading / disabled state を色だけで伝えない
- destructive delete は通常保存操作と区別
- FREE_DAY 切替は意味が分かる文言にする
- totals は「記録合計」として表示

## 36. FREE_DAY Confirmation

UNRECORDED / Empty NORMAL から FREE_DAY に変更する際、確認 dialog を表示する。

```text
Free Dayとして記録しますか？

この日は栄養計算をしない日として記録されます。
```

actions:

```text
キャンセル
Free Dayにする
```

NORMAL with foods では、Food を消すconfirmationにしてはいけない。

Foodが存在することを説明し、切替を実行しない。

## 37. NORMALへ戻す

FREE_DAY画面には:

```text
通常の記録に戻す
```

action を提供する。

実行後:

```text
mode = NORMAL
foods = []
totals = 0 / 0
```

を backend response / reconciliation から表示する。

Food追加 action が利用可能になる。

## 38. Day Memo Preservation

Nutrition day PUT で mode を変更する場合、既存 day memo を不用意に null へ上書きしない。

現在 GET response に memo が存在するなら、その memo を PUT body に含めて保持する。

UNRECORDED から新規 day を作る場合は null でよい。

Spec 009 では day memo editor は不要。

## 39. Repository Boundary

概念:

```text
NutritionRepository
- getDay(date)
- setDayMode(date, mode, memo)
- createFood(date, request)
- updateFood(date, id, request)
- deleteFood(date, id)
```

shared Dio を利用。

feature 内 `Dio()` 禁止。

DioException を controller / UI へ漏らさない。

malformed success body は CONTRACT。

204 DELETE body を parse しない。

## 40. Controller Responsibility

Controller は最低限:

- selected date
- current NutritionDay
- initial loading/error
- mutation busy
- date load
- mode change
- Food create
- Food update
- Food delete
- mutation後reconciliation
- stale response guard
- stable error message

を扱う。

TextEditingController 等の widget object を provider state に入れない。

## 41. UI Responsibility

Widget は最低限:

- day state 表示
- date picker
- totals
- food list
- Food form
- local form validation feedback
- confirmation dialog
- success feedback
- provider/controller action 呼び出し

を担当する。

API request construction や DioException 判定を Widget 内で行わない。

## 42. Testing Strategy

実 FastAPI / PostgreSQL に依存しない。

- fake repository
- Dio interceptor / adapter
- Riverpod override
- widget test

等を利用する。

manual integration のみ実 backend を使用してよい。

## 43. 必須テスト契約

テスト関数数は以下と一致させる必要はない。parameterized / helper を使用してよい。

### Model

1. NORMAL parse
2. empty NORMAL totals 0
3. FREE_DAY parse
4. FREE_DAY totals null
5. UNRECORDED parse
6. UNRECORDED totals null
7. Food parse
8. Food numeric fields reject string
9. invalid date reject
10. naive timestamp reject
11. unknown mode reject
12. additive fields allow
13. NORMAL totals null reject
14. FREE_DAY non-null totals reject
15. FREE_DAY foods non-empty reject
16. UNRECORDED foods non-empty reject

### Serialization

17. Food create name trimmed
18. calories JSON integer
19. protein JSON number
20. eaten_at timezone-aware
21. Food update excludes id
22. Food update excludes nutrition_day_id
23. empty memo -> null
24. mode PUT sends NORMAL/FREE_DAY only
25. day memo preserved

### Validation

26. empty name reject
27. whitespace name reject
28. name >100 reject
29. calories empty reject
30. calories nonnumeric reject
31. calories decimal reject
32. calories negative reject
33. calories zero accept
34. protein empty reject
35. protein nonnumeric reject
36. protein negative reject
37. protein >2 decimals reject
38. protein zero accept
39. memo >500 reject
40. invalid form sends no request

### Repository

41. GET day path
42. PUT day path/body
43. POST Food path/body
44. PUT Food nested path/body
45. DELETE Food nested path
46. shared Dio
47. Dio error normalized
48. valid backend error code preserved
49. malformed success -> CONTRACT
50. DELETE 204 no body parse

### Controller

51. NORMAL load -> ready
52. FREE_DAY load -> ready
53. UNRECORDED load -> ready
54. GET network error -> error, not UNRECORDED
55. old GET ignored
56. UNRECORDED + create Food -> POST directly, no preliminary mode PUT
57. create Food success -> reconcile GET
58. update Food success -> reconcile GET
59. delete Food success -> reconcile GET
60. deleting last Food leaves NORMAL
61. old create response ignored after date change
62. old update response ignored
63. old delete response ignored
64. duplicate mutation prevented
65. FREE_DAY create Food prevented
66. UNRECORDED -> FREE_DAY
67. empty NORMAL -> FREE_DAY
68. NORMAL with foods does not silently delete
69. FREE_DAY_HAS_FOOD_LOGS preserved
70. FREE_DAY -> NORMAL
71. mode PUT preserves day memo
72. reconciliation failure is error, not fabricated local totals

### Widget

73. Food route reachable
74. Weight route still reachable
75. UNRECORDED presentation distinct from zero totals
76. NORMAL totals shown as recorded totals
77. empty NORMAL displays 0 totals
78. FREE_DAY does not display 0 kcal as daily total
79. FREE_DAY explanation shown
80. NORMAL Food list renders
81. Food create form fields render
82. Food create form clears stale values
83. Food edit form prefill
84. create validation shown
85. validation prevents request
86. create success feedback neutral
87. edit success feedback neutral
88. delete confirmation cancel
89. delete confirmation accept
90. FREE_DAY confirmation cancel
91. FREE_DAY confirmation accept
92. NORMAL with foods blocks FREE_DAY transition
93. FREE_DAY -> NORMAL action
94. busy disables duplicate actions
95. calories displays kcal unit
96. protein displays g unit
97. no target/remaining/deficit/surplus text
98. no diet/body judgment text

## 44. Manual Integration

可能なら:

```text
1. 未記録日を開く → UNRECORDED
2. Food POST → NORMAL + Food 1件
3. Food PUT
4. Food DELETE → empty NORMAL
5. empty NORMAL → FREE_DAY
6. FREE_DAY → NORMAL
7. UNRECORDED → FREE_DAY
8. FoodありNORMAL → FREE_DAY conflict / block
```

を実 backend + PostgreSQL で確認する。

API base URL:

```bash
--dart-define=API_BASE_URL=...
```

固定 localhost / emulator address をrepositoryへ埋め込まない。

実施できなければ理由を報告。

## 45. Backend Non-Modification

Spec 009 では以下を変更しない。

```text
backend/
database schema
Alembic migration
```

API contract の問題を発見した場合は報告する。

## 46. Dependency Policy

原則 dependency 追加なし。

Flutter SDK + 既存 Dio / Riverpod / GoRouter を使用。

新しい state management / HTTP / form library を追加しない。

version update も行わない。

## 47. Verification

```bash
cd mobile
dart format .
flutter analyze
flutter test
```

root:

```bash
cd ..
git diff --check
git status --short
```

backend差分、pubspec差分も確認する。

## 48. Acceptance Criteria

### AC-01
Record menuからFood screenへ遷移できる。

### AC-02
既存Weight navigationを壊さない。

### AC-03
selected dateを変更できる。

### AC-04
NORMAL / FREE_DAY / UNRECORDEDを型で区別する。

### AC-05
unknown modeをCONTRACT errorにする。

### AC-06
UNRECORDEDを0 kcalとして表示しない。

### AC-07
FREE_DAYを0 kcalとして表示しない。

### AC-08
empty NORMALのみ0 totalsとして扱う。

### AC-09
NORMALでbackend totalsを表示する。

### AC-10
totalsを目標値と比較しない。

### AC-11
Food listをbackend orderingで表示する。

### AC-12
Food nameを入力できる。

### AC-13
caloriesをintegerとして送信する。

### AC-14
protein_gをJSON numberとして送信する。

### AC-15
eaten_atをtimezone-aware timestampとして送信する。

### AC-16
Spec 008のtimestamp serializerを再利用する。

### AC-17
固定+09:00を使用しない。

### AC-18
Food memoを任意入力できる。

### AC-19
Food local validationを行う。

### AC-20
invalid formでAPI requestを送らない。

### AC-21
UNRECORDEDからFoodを直接POSTできる。

### AC-22
Food追加前に不要なNORMAL PUTを行わない。

### AC-23
Food create後backend stateをreconcileする。

### AC-24
Food update後backend stateをreconcileする。

### AC-25
Food delete後backend stateをreconcileする。

### AC-26
最後のFood削除後もempty NORMALである。

### AC-27
Food delete前にconfirmationを表示する。

### AC-28
FREE_DAY中にFood追加を行わない。

### AC-29
FOOD_NOT_ALLOWED_ON_FREE_DAYを保持する。

### AC-30
FOOD_DATE_MISMATCHを保持する。

### AC-31
FOOD_NOT_FOUNDを保持する。

### AC-32
UNRECORDEDからFREE_DAYへ変更できる。

### AC-33
empty NORMALからFREE_DAYへ変更できる。

### AC-34
FoodありNORMALをsilent deleteしてFREE_DAYにしない。

### AC-35
FREE_DAY_HAS_FOOD_LOGSを適切に扱う。

### AC-36
FREE_DAY前にconfirmationを表示する。

### AC-37
FREE_DAYからNORMALへ戻せる。

### AC-38
Nutrition day memoをmode PUTで保持する。

### AC-39
FREE_DAYの意味を栄養計算なしとして表現する。

### AC-40
FREE_DAYをbinge/compensationとして表現しない。

### AC-41
日付変更時にold GETがstateを上書きしない。

### AC-42
old Food mutationが新しい日付stateを上書きしない。

### AC-43
mutation後reconciliationにもstale guardがある。

### AC-44
mutation二重送信を防ぐ。

### AC-45
GET failureをUNRECORDEDに変換しない。

### AC-46
reconciliation failure時にlocal totalsを捏造しない。

### AC-47
DioExceptionをUIへ漏らさない。

### AC-48
shared Dioを使用する。

### AC-49
malformed responseをCONTRACT errorにする。

### AC-50
Food edit formをprefillできる。

### AC-51
Food create formへ前日値を持ち越さない。

### AC-52
UI error messageは中立的な日本語。

### AC-53
success feedbackは中立的。

### AC-54
kcal / g unitを明示する。

### AC-55
calorie/protein targetを実装しない。

### AC-56
remaining/deficit/surplusを実装しない。

### AC-57
food/body judgmentを表示しない。

### AC-58
food recommendation / meal planを実装しない。

### AC-59
history / graphを実装しない。

### AC-60
Dashboard / Symptom / Injection UIを実装しない。

### AC-61
backend / DB / migrationを変更しない。

### AC-62
offline / retry / auth / notificationを追加しない。

### AC-63
新規dependencyを原則追加しない。

### AC-64
unit/widget testsが実backendを必須としない。

### AC-65
`dart format .`成功。

### AC-66
`flutter analyze`成功。

### AC-67
`flutter test`成功。

### AC-68
`git diff --check`成功。

## 49. Scope Guardrail

以下を「ついでに」実装しない。

```text
nutrition history
food history
charts
targets
remaining calories
diet score
BMI
weight analysis
food recommendations
meal planning
food database
barcode
photos
AI analysis
water logging
generic CRUD framework
offline storage
cache
retry
authentication
notifications
Dashboard UI
Symptom UI
Injection UI
```

## 50. 完了報告

Codex は完了時に以下を報告する。

1. 変更ファイル
2. dependencies変更
3. Nutrition/Food models
4. serialization
5. validation
6. repository
7. Riverpod controller/provider
8. NORMAL/FREE_DAY/UNRECORDED state
9. Food create/update/delete
10. mode transition
11. reconciliation strategy
12. stale response対策
13. duplicate mutation対策
14. day memo preservation
15. UI / navigation
16. confirmation dialogs
17. error mapping
18. tests概要・件数
19. `dart format`
20. `flutter analyze`
21. `flutter test`
22. manual integration結果
23. `git diff --check`
24. backend差分
25. pubspec差分
26. Scope外変更
27. 未解決事項

## 51. Commit / Push

実装とverificationが成功しても、ユーザーの明示指示まではcommit / pushしない。

commit前レビューを受けること。
