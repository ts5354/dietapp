# Spec 008 --- Flutter Weight UI

## 1. 目的

Spec 007 で構築した Flutter 共通 API 通信基盤の上に、MVP
最初の記録機能として Weight（体重）UI と Weight API の Flutter 側
read/write path を実装する。

この Spec の完成状態は、スマートフォンから以下を行えることとする。

-   体重記録画面を開く
-   日付、体重、記録時刻、任意メモを入力する
-   新規体重記録を FastAPI / PostgreSQL へ保存する
-   指定日の既存体重記録を読み込む
-   既存記録を編集する
-   既存記録を削除する
-   API / validation error を UI 上で安全に扱う

体重の増減を評価したり、目標体重・減量ペース・摂取制限などを提示する機能は実装しない。

------------------------------------------------------------------------

## 2. 実装前に読むもの

実装前に以下を読むこと。

1.  `AGENTS.md`
2.  `README.md`
3.  `docs/api-design.md`
4.  `docs/database-design.md`
5.  `specs/002-common-api-and-weight.md`
6.  `specs/006-dashboard-api.md`
7.  `specs/007-flutter-api-foundation.md`
8.  `mobile/pubspec.yaml`
9.  `mobile/lib/` 配下の既存実装
10. `mobile/test/` 配下の既存テスト
11. backend の Weight API router / schema / service / tests

Spec 002 の Weight API contract と実際の backend 実装を authoritative
とする。

既存仕様と本 Spec が矛盾する場合は、勝手に backend を変更せず報告する。

------------------------------------------------------------------------

## 3. Scope

### 3.1 IN

以下を実装する。

-   Flutter Weight domain / request / response model
-   Weight API client
-   Weight repository
-   Weight 用 Riverpod provider / controller
-   Weight 記録画面
-   日付入力
-   体重 kg 入力
-   記録日時入力
-   任意 memo 入力
-   POST による新規保存
-   GET による指定日取得
-   PUT による既存記録更新
-   DELETE による既存記録削除
-   create / edit mode の切り替え
-   loading / success / validation / API error handling
-   保存後の状態更新
-   削除後の状態更新
-   Record menu から Weight 画面への navigation
-   Widget / unit tests
-   必要最小限の既存 routing 変更

### 3.2 OUT

以下は実装しない。

-   Weight history 一覧
-   7日 / 30日 / 3か月グラフ
-   Dashboard UI
-   Food UI
-   Symptom UI
-   Injection UI
-   Settings UI
-   pagination UI
-   Weight trend analysis
-   BMI
-   目標体重
-   推奨体重
-   減量ペース
-   calorie / protein target
-   体重変化への評価・称賛・警告
-   medication dose adjustment
-   offline cache
-   retry
-   authentication
-   notification
-   backend / DB / migration の変更

History と graph は後続 Spec で実装する。

------------------------------------------------------------------------

## 4. Backend Weight Contract

Base:

``` text
/api/v1
```

使用する endpoint:

``` http
POST   /api/v1/weights
GET    /api/v1/weights/{date}
PUT    /api/v1/weights/{date}
DELETE /api/v1/weights/{date}
```

Spec 008 では Weight list endpoint は UI から使用しなくてよい。

------------------------------------------------------------------------

## 5. Weight Data Contract

新規作成 request:

``` json
{
  "record_date": "2026-09-07",
  "weight_kg": 65.5,
  "recorded_at": "2026-09-07T03:30:00+09:00",
  "memo": "optional memo"
}
```

更新 request:

``` json
{
  "weight_kg": 65.5,
  "recorded_at": "2026-09-07T03:30:00+09:00",
  "memo": "optional memo"
}
```

PUT body に `record_date` は含めない。

Response は backend Spec 002 の既存 Weight response contract に従う。

------------------------------------------------------------------------

## 6. Weight Model

Flutter 側で最低限以下に相当する型を用意する。

``` text
WeightRecord
CreateWeightRequest
UpdateWeightRequest
```

必要であれば DTO / domain を分離してよいが、MVP の単純な CRUD
に対して過剰な layer を追加しない。

WeightRecord は少なくとも以下を保持する。

``` text
id
recordDate
weightKg
recordedAt
memo
createdAt
updatedAt
```

backend response に存在しない値を推測して追加しない。

------------------------------------------------------------------------

## 7. Numeric Contract

`weight_kg` は JSON number として送信する。

文字列:

``` json
{
  "weight_kg": "65.5"
}
```

として送信しない。

Flutter form では text input から数値へ明示的に parse する。

空文字、数値として解釈できない入力、0 以下は送信前 validation error
とする。

backend DB contract:

``` text
NUMERIC(4,1)
CHECK weight_kg > 0
```

に合わせ、少なくとも小数第1位までを正しく扱う。

入力値を backend 制約へ合わせるために silent rounding してはいけない。

例:

``` text
65.55
```

を勝手に:

``` text
65.6
```

へ変換して保存しない。

backend が拒否する値は、可能なら Flutter 側でも validation する。

------------------------------------------------------------------------

## 8. Date

Weight は 1 calendar date あたり最大 1 record。

`record_date` は:

``` text
YYYY-MM-DD
```

で扱う。

Spec 007 の DATE formatter を再利用する。

同じ目的の別 formatter を feature 内に複製しない。

日付は DatePicker 等、Flutter 標準 UI を優先する。

------------------------------------------------------------------------

## 9. recorded_at

`recorded_at` は timezone-aware ISO 8601 timestamp として backend
へ送る。

Flutter form ではユーザーが記録日時を設定できる。

最低限:

-   date
-   time

を選択できること。

送信時に timezone offset を含める。

naive timestamp 相当を backend へ送らない。

### 9.1 record_date との関係

Weight API の authoritative contract は Spec 002 / backend 実装に従う。

Flutter 側で不必要な独自 cross-field rule を追加しない。

ただし UI の初期値として record_date と recorded_at を自然に同じ
calendar day に設定してよい。

------------------------------------------------------------------------

## 10. Default Form Values

新規記録画面を開いた場合:

``` text
record_date = 今日
recorded_at = 現在日時
weight_kg   = empty
memo        = empty
```

を基本とする。

「今日」は端末 local calendar date を UI 初期値として使用してよい。

これは Spec 007 で禁止した「Dashboard API 用 IANA timezone
自動検出」とは別であり、Flutter のローカル DateTime
をフォーム初期値として使うだけである。

------------------------------------------------------------------------

## 11. Memo

memo は任意。

backend contract に合わせて最大 500 文字。

UI では:

-   空欄を許可
-   500文字超過を送信前に validation
-   空欄は `null` として送信してよい
-   whitespace-only は既存 backend contract / Flutter 共通方針に合わせる

医学的な解釈を memo から行わない。

------------------------------------------------------------------------

## 12. API Client

Weight API client を実装する。

概念:

``` text
WeightApi
- createWeight(...)
- getWeight(date)
- updateWeight(date, ...)
- deleteWeight(date)
```

shared `dioProvider` を使用する。

feature 内で新しい `Dio()` を生成しない。

Spec 007 の共通 `ApiException` / `normalizeDioException()`
を再利用する。

DioException を repository / UI へ直接漏らさない。

------------------------------------------------------------------------

## 13. GET Semantics

``` http
GET /api/v1/weights/2026-09-07
```

成功:

``` text
200 + WeightRecord
```

未存在:

``` text
404 WEIGHT_NOT_FOUND
```

Spec 008 の repository / controller
では、画面初期化のための「その日に既存記録があるか」を判定する必要がある。

`WEIGHT_NOT_FOUND` は create mode を意味する通常の分岐として扱ってよい。

ただし transport failure や別の 404/contract error
を「未記録」として隠してはいけない。

------------------------------------------------------------------------

## 14. POST Semantics

新規保存:

``` http
POST /api/v1/weights
```

成功:

``` text
201
```

同じ `record_date` が存在:

``` text
409 WEIGHT_ALREADY_EXISTS
```

この conflict を silent overwrite してはいけない。

UI
は「この日付にはすでに記録があります」に相当する中立的なエラーを表示し、ユーザーが既存記録を確認・編集できる状態へ導ける設計にする。

自動 DELETE / PUT へ切り替えない。

------------------------------------------------------------------------

## 15. PUT Semantics

``` http
PUT /api/v1/weights/{date}
```

PUT は update-only。

存在しない場合:

``` text
404 WEIGHT_NOT_FOUND
```

upsert として扱わない。

body:

``` json
{
  "weight_kg": 65.5,
  "recorded_at": "...",
  "memo": null
}
```

`record_date` を body に含めない。

既存 record の `record_date` 自体を edit form から別日に変更する機能は
Spec 008 では実装しない。

日付を変更したい場合は、別日の新規記録として扱う後続操作になる。

------------------------------------------------------------------------

## 16. DELETE Semantics

``` http
DELETE /api/v1/weights/{date}
```

成功:

``` text
204 No Content
```

削除後:

-   local state から既存 WeightRecord を除去
-   create mode に戻す
-   form を安全な状態へ戻す

削除は hard delete であり undo は Spec 008 では実装しない。

------------------------------------------------------------------------

## 17. Screen

Weight 記録画面は、記録のためのシンプルな form とする。

概念:

``` text
体重を記録

日付
[ 2026/09/07 ]

体重
[        ] kg

記録時刻
[ 15:30 ]

メモ（任意）
[                    ]

[ 保存 ]
```

既存 record がある場合:

``` text
体重を編集

日付
2026/09/07

体重
[ 65.5 ] kg

記録時刻
[ 15:30 ]

メモ（任意）
[ ... ]

[ 更新 ]

[ 記録を削除 ]
```

既存 design system / Theme があればそれを優先する。

------------------------------------------------------------------------

## 18. Create / Edit Mode

画面は最低限:

``` text
loading
create
edit
error
```

を区別できる。

### Create

指定日に record が存在しない。

### Edit

指定日に record が存在する。

### Loading

GET / save / update / delete の必要な非同期処理中。

### Error

通信・contract 等により画面状態を安全に決められない。

GET の network error を create mode と誤認しない。

------------------------------------------------------------------------

## 19. Date Selection Behavior

新規 create mode では日付を変更できる。

日付を変更したら、その日付の既存 record の有無を確認する。

``` text
date changed
→ GET /weights/{newDate}
→ found     → edit mode
→ not found → create mode
```

既存 edit mode で record_date 自体を移動させる update は実装しない。

日付変更 UI を提供する場合も、別日の record をロードする navigation /
selection として扱う。

「既存 record の primary date を変更する PUT」として扱わない。

------------------------------------------------------------------------

## 20. recorded_at Editing

create / edit の両方で記録日時を編集できる。

Flutter 標準の DatePicker / TimePicker 等を利用してよい。

recorded_at の日付部分も変更できる構成にする場合、backend contract
と矛盾しないこと。

Spec 008 では UI complexity を抑えるため、record_date 選択 +
記録時刻選択を基本とし、recorded_at の calendar date は record_date
に合わせる方式を推奨する。

この場合:

``` text
recorded_at = selected record_date + selected local time + local offset
```

として送る。

------------------------------------------------------------------------

## 21. Timezone Offset Serialization

Dart 標準 `DateTime.toIso8601String()` は local DateTime であっても
`+09:00` のような offset suffix を付与しないため、そのまま
timezone-aware backend contract 用 serializer として使用しない。

Weight API 用に timezone offset を明示した ISO 8601 serializer を共通
helper として実装または既存 helper を再利用する。

例:

``` text
2026-09-07T15:30:00+09:00
```

UTC の場合:

``` text
2026-09-07T06:30:00Z
```

等、backend が timezone-aware と認識できる形式にする。

端末 local offset を使用する場合、その日時に対する `timeZoneOffset`
を使用する。

固定 `+09:00` をコードへベタ書きしない。

------------------------------------------------------------------------

## 22. Form Validation

保存前に最低限以下を validation する。

### weight_kg

-   required

-   JSON number に変換可能

-   finite

-   0

-   backend precision / scale と明らかに矛盾しない

-   小数第1位を超える値を silent rounding しない

### memo

-   nullable
-   max 500 characters

### date / time

-   valid selected values

validation failure では API request を送らない。

------------------------------------------------------------------------

## 23. Weight Value Presentation

体重値は記録された値として中立的に表示する。

許可:

``` text
65.5 kg
```

禁止例:

``` text
昨日より増えました
順調に減っています
目標まであと○kg
太りすぎです
もっと減らしましょう
```

Spec 008 では Weight の意味付け・評価を行わない。

------------------------------------------------------------------------

## 24. Error Presentation

ユーザー向け error text は Flutter UI
上で日本語の中立的な文言を使用する。

最低限区別する。

### Validation

例:

``` text
体重を入力してください
体重は0より大きい値を入力してください
体重は小数第1位まで入力してください
メモは500文字以内で入力してください
```

### Duplicate

`WEIGHT_ALREADY_EXISTS`:

``` text
この日付にはすでに体重記録があります。
```

### Not Found during update/delete

`WEIGHT_NOT_FOUND`:

``` text
この体重記録は見つかりませんでした。再読み込みしてください。
```

### Network

``` text
サーバーに接続できませんでした。
```

### Timeout

``` text
通信がタイムアウトしました。
```

### Other

``` text
体重記録の処理中にエラーが発生しました。
```

backend の英語 fallback message をそのまま主要 UI text
として表示する必要はない。

stable error code / kind に基づいて UI message を決める。

------------------------------------------------------------------------

## 25. Loading / Double Submit

保存・更新・削除中は同じ操作の二重送信を防ぐ。

最低限:

-   submit button disable
-   delete button disable

等を行う。

複数 POST が同時に飛ぶ構造にしない。

------------------------------------------------------------------------

## 26. Success Behavior

### Create success

-   returned WeightRecord を state に反映
-   edit mode へ移行
-   form を server response と整合させる
-   中立的な保存完了 feedback を表示してよい

例:

``` text
体重を保存しました。
```

### Update success

-   returned WeightRecord を state に反映
-   edit mode 維持
-   中立的な更新完了 feedback を表示してよい

### Delete success

-   record を state から除去
-   create mode へ戻す
-   form の weight / memo をクリア
-   selected date は維持してよい
-   recorded time は現在時刻等の安全な create default に戻してよい

------------------------------------------------------------------------

## 27. Riverpod State Management

Spec 007 の provider 方針を維持する。

Weight の CRUD + form interaction では、必要に応じて controller /
notifier を導入してよい。

ただし form の `TextEditingController` 自体を global provider
へ無理に保持する必要はない。

責務を分ける。

概念:

``` text
WeightScreen
  ↓
WeightController / Provider
  ↓
WeightRepository
  ↓
WeightApi
  ↓
shared Dio
```

network state と widget-local form controller を混同しない。

------------------------------------------------------------------------

## 28. State Consistency

非同期操作後に stale state を残さない。

特に:

-   date A の GET 中に date B へ切り替えた場合
-   save 中に rebuild
-   delete 後
-   409 duplicate 後
-   update/delete 404 後

を考慮する。

最低限、遅れて返った date A response が現在選択中の date B state
を上書きしない設計にする。

実装方法は:

-   request generation token
-   selected date comparison
-   Riverpod family
-   controller 内 sequence

等、既存構成に最も単純に適合する方法を選ぶ。

------------------------------------------------------------------------

## 29. Navigation

既存 MVP navigation:

``` text
Home / Record / History / Settings
```

Record menu:

``` text
記録する

[ 体重 ]
[ 食事 ]
[ 体調 ]
[ 注射 ]
```

Spec 008 では Record menu の「体重」から Weight screen
へ遷移できるようにする。

既存 GoRouter を使用する。

新しい navigation package を追加しない。

route path / route name は既存 naming convention に合わせる。

Food / Symptom / Injection button はこの Spec のために実装しない。

既存 placeholder があれば壊さない。

------------------------------------------------------------------------

## 30. Accessibility / Input

最低限以下を守る。

-   体重 field に numeric keyboard
-   decimal input を許可
-   label を placeholder だけに依存させない
-   kg unit を明示
-   memo は multiline 可
-   button text が操作内容を示す
-   loading 中も何の処理中か理解できる
-   destructive delete は通常の save と視覚・操作上区別できる

色だけで状態を伝えない。

------------------------------------------------------------------------

## 31. Delete Confirmation

誤操作防止のため、削除ボタン押下後に確認 dialog を表示する。

例:

``` text
この体重記録を削除しますか？
```

選択肢:

``` text
キャンセル
削除
```

過度に不安を煽る文言は使わない。

------------------------------------------------------------------------

## 32. Testing Strategy

unit / widget tests は実 FastAPI / PostgreSQL を必須としない。

Repository / Dio boundary を fake / interceptor / provider override
等で制御する。

UI test が localhost に依存してはいけない。

------------------------------------------------------------------------

## 33. 必須テスト契約

最低限、以下を意味的に網羅する。

### 33.1 Model / Serialization

1.  valid Weight response を parse
2.  JSON numeric `weight_kg` を parse
3.  string `weight_kg` を contract error
4.  invalid record_date を contract error
5.  invalid / naive response timestamp を contract error
6.  nullable memo を parse
7.  unknown additive response field を許容
8.  create request が record_date を含む
9.  create request weight_kg が JSON number
10. create request recorded_at が timezone-aware
11. update request に record_date を含めない
12. memo null serialization

### 33.2 Weight Validation

13. empty weight を reject
14. non-numeric weight を reject
15. zero を reject
16. negative を reject
17. non-finite を reject
18. 小数第2位以上を reject
19. valid integer-style input を受理
20. valid one-decimal input を受理
21. memo \> 500 を reject
22. validation failure では request を送らない

### 33.3 API

23. POST path / method / body
24. GET `/weights/{date}`
25. PUT `/weights/{date}`
26. DELETE `/weights/{date}`
27. path date zero padding
28. shared Dio を使用
29. DioException が正規化される
30. malformed success body -\> CONTRACT

### 33.4 Error Semantics

31. GET 404 `WEIGHT_NOT_FOUND` を create-mode 分岐として扱える
32. GET network error を unrecorded と誤認しない
33. POST 409 `WEIGHT_ALREADY_EXISTS` を保持
34. PUT 404 `WEIGHT_NOT_FOUND` を保持
35. DELETE 404 `WEIGHT_NOT_FOUND` を保持
36. timeout message / state
37. network message / state
38. unexpected error state

### 33.5 Controller / State

39. initial date load found -\> edit
40. initial date load not found -\> create
41. create success -\> edit
42. update success -\> edit
43. delete success -\> create
44. delete success clears weight/memo state as applicable
45. selected date is preserved after delete
46. late response from old date does not overwrite new date
47. duplicate submit is prevented
48. error does not silently mutate persisted-state representation

### 33.6 Widget

49. create screen renders required fields
50. edit screen pre-fills record
51. create button says 保存
52. edit button says 更新
53. edit screen shows delete action
54. create screen does not show delete action
55. local validation text appears
56. local validation prevents repository call
57. loading disables submit
58. loading disables delete
59. delete confirmation cancel does not delete
60. delete confirmation accept calls delete
61. success feedback is neutral
62. API error message is neutral Japanese
63. Weight value has kg unit
64. no goal / trend / body judgment text is rendered

### 33.7 Navigation

65. Record menu Weight action navigates to Weight screen
66. existing unrelated navigation remains functional

テスト関数数は66と一致させる必要はない。parameterized tests / helper
を使用してよい。

------------------------------------------------------------------------

## 34. Manual Integration Check

可能な環境では backend + PostgreSQL を起動し、Flutter
から実際に以下を確認する。

``` text
1. 未記録日を開く
2. Weight を POST
3. GET で edit mode になる
4. Weight を PUT
5. DELETE
6. 再度 GET して create mode になる
```

manual check 用データは開発用 DB のみで扱う。

unit / widget tests は実 server に依存させない。

実機 / emulator では host address が異なる場合があるため:

``` bash
--dart-define=API_BASE_URL=...
```

で環境ごとに指定する。

固定 emulator IP を repository に埋め込まない。

manual integration を実施できない場合は理由を完了報告へ記載する。

------------------------------------------------------------------------

## 35. Backend Non-Modification

Spec 008 では backend を変更しない。

以下への変更は禁止。

``` text
backend/app/
backend/tests/
backend migrations
database schema
```

Weight API contract に問題を発見した場合は、勝手に修正せず報告する。

------------------------------------------------------------------------

## 36. Dependency Policy

原則、新規 dependency を追加しない。

Flutter SDK、既存 Dio、Riverpod、GoRouter で実装できる範囲を優先する。

入力 format のためだけに package を追加しない。

既存 dependency の version を理由なく更新しない。

------------------------------------------------------------------------

## 37. Verification

実装後:

``` bash
cd mobile

dart format .
flutter analyze
flutter test
```

repository root:

``` bash
cd ..
git diff --check
git status --short
```

既存 project に追加の standard verification がある場合はそれも実行する。

backend が変更されていないことを確認する。

------------------------------------------------------------------------

## 38. Acceptance Criteria

### AC-01

Record menu の Weight action から Weight screen へ遷移できる。

### AC-02

新規画面で selected date が初期化される。

### AC-03

新規画面で recorded time が初期化される。

### AC-04

Weight kg を入力できる。

### AC-05

Memo を任意入力できる。

### AC-06

指定日の既存 record を GET できる。

### AC-07

未存在 `WEIGHT_NOT_FOUND` を create mode として扱う。

### AC-08

GET の network / timeout / contract failure を create mode
と誤認しない。

### AC-09

既存 record がある場合 edit mode になる。

### AC-10

create mode から POST できる。

### AC-11

create request に `record_date` が含まれる。

### AC-12

create / update request の `weight_kg` は JSON number。

### AC-13

`recorded_at` は timezone-aware ISO 8601。

### AC-14

固定 `+09:00` を serializer にベタ書きしない。

### AC-15

create success 後 edit mode になる。

### AC-16

edit mode から PUT できる。

### AC-17

PUT body に `record_date` を含めない。

### AC-18

update success 後 edit mode を維持する。

### AC-19

edit mode で delete action が表示される。

### AC-20

delete 前に確認 dialog が表示される。

### AC-21

delete success 後 create mode になる。

### AC-22

delete success 後 stale WeightRecord を保持しない。

### AC-23

Weight validation が保存前に行われる。

### AC-24

0 以下を送信しない。

### AC-25

小数第2位以上を silent rounding しない。

### AC-26

memo 500文字超過を送信しない。

### AC-27

validation failure では API request を送信しない。

### AC-28

409 `WEIGHT_ALREADY_EXISTS` を silent overwrite しない。

### AC-29

PUT / DELETE の `WEIGHT_NOT_FOUND` を適切に error として扱う。

### AC-30

DioException を UI へ直接漏らさない。

### AC-31

shared Dio を使用する。

### AC-32

date formatter を Spec 007 から再利用する。

### AC-33

date selection 後に対象日の record を再取得できる。

### AC-34

old-date response が new-date state を上書きしない。

### AC-35

save / update / delete の二重送信を防ぐ。

### AC-36

create / edit / loading / error を安全に区別できる。

### AC-37

API error を中立的な日本語で表示できる。

### AC-38

体重値を kg unit 付きで表示する。

### AC-39

Weight trend / goal / BMI を追加しない。

### AC-40

体重増減への評価・称賛・批判を表示しない。

### AC-41

栄養制限や calorie / protein target を追加しない。

### AC-42

medication dose adjustment を追加しない。

### AC-43

Weight history / graph を実装しない。

### AC-44

Food / Symptom / Injection UI を実装しない。

### AC-45

backend / DB / migration を変更しない。

### AC-46

offline / retry / auth / notification を追加しない。

### AC-47

unit / widget tests が localhost / PostgreSQL を必須としない。

### AC-48

`dart format .` が成功する。

### AC-49

`flutter analyze` が成功する。

### AC-50

`flutter test` が成功する。

### AC-51

`git diff --check` が成功する。

------------------------------------------------------------------------

## 39. Scope Guardrail

「後で必要になる」という理由で以下を実装しない。

``` text
Weight history
Weight chart
BMI
target weight
trend analysis
nutrition target
generic CRUD framework
offline DB
cache
retry
authentication
notification
Dashboard UI
Food UI
Symptom UI
Injection UI
```

Spec 008 は Weight 単体の CRUD UI を完成させることに集中する。

------------------------------------------------------------------------

## 40. 完了報告

Codex は完了時に以下を報告する。

1.  変更ファイル
2.  dependencies の変更有無
3.  Weight model / serialization
4.  timezone-aware timestamp serialization
5.  Weight API client
6.  Repository
7.  Riverpod controller / provider
8.  create / edit state transition
9.  date change 時の stale response 対策
10. local validation
11. error code → UI message
12. navigation
13. delete confirmation
14. tests の概要と件数
15. `dart format` 結果
16. `flutter analyze` 結果
17. `flutter test` 結果
18. manual integration check の有無と結果
19. `git diff --check` 結果
20. backend 差分の有無
21. Scope 外変更の有無
22. 未解決事項

------------------------------------------------------------------------

## 41. Commit / Push

実装・verification が成功しても、ユーザーから明示的な指示があるまで
commit / push しない。

Spec 008 実装完了後にレビューを受けること。
