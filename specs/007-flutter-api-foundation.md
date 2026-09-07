# Spec 007 --- Flutter API Foundation

## 1. 目的

MVP の各 Flutter 画面を実装する前に、Flutter から FastAPI `/api/v1`
を一貫した方法で呼び出すための共通通信基盤を構築する。

この Spec では、Spec 006 で実装済みの Dashboard API を最初の実利用
endpoint として使用し、以下の通信経路を確立する。

``` text
Flutter
  ↓
Dio
  ↓
API Client / Feature API
  ↓
Repository
  ↓
Riverpod Provider
  ↓
FastAPI /api/v1
```

完成状態は、Flutter 側から Dashboard API を取得し、API JSON を型安全な
Dart model へ変換できることとする。

Home / Dashboard UI への表示はまだ行わない。

------------------------------------------------------------------------

## 2. 実装前に読むもの

実装前に以下を読むこと。

1.  `AGENTS.md`
2.  `README.md`
3.  `docs/api-design.md`
4.  `specs/000-repository-bootstrap.md`
5.  `specs/002-common-api-and-weight.md`
6.  `specs/003-nutrition-and-food-api.md`
7.  `specs/004-symptom-api.md`
8.  `specs/005-injection-api.md`
9.  `specs/006-dashboard-api.md`
10. `mobile/pubspec.yaml`
11. `mobile/lib/` 配下の既存実装
12. `mobile/test/` 配下の既存テスト

既存 Flutter 構成と本 Spec
の例示ディレクトリが衝突する場合は、既存構成を優先しつつ本 Spec
の責務分離を維持する。

既存仕様と本 Spec が矛盾する場合は、勝手に解釈して変更せず報告すること。

------------------------------------------------------------------------

## 3. Scope

### 3.1 IN

以下を実装する。

-   API base URL の環境設定
-   Riverpod 管理の共通 Dio instance
-   共通 API error model / exception
-   Dio error からアプリ共通 error への正規化
-   Dashboard API client
-   Dashboard repository
-   Dashboard Dart model
-   Dashboard provider
-   Dashboard response JSON の型安全な parse
-   Dashboard API の `date` / `timezone` query 生成
-   API contract violation の検出
-   Flutter / Dart unit tests
-   必要な範囲で Freezed / JSON serialization 関連依存を追加
-   必要な生成コード
-   ローカル FastAPI との手動 integration check 手順の整備

### 3.2 OUT

以下は実装しない。

-   Home / Dashboard UI へのデータ表示
-   Weight 入力 UI
-   Food / Nutrition 入力 UI
-   Symptom 入力 UI
-   Injection 入力 UI
-   History UI
-   Settings UI
-   グラフ
-   POST / PUT / DELETE API の feature 実装
-   CRUD 全体を先回りした巨大な generic API abstraction
-   端末 timezone の自動検出
-   offline cache
-   local database
-   retry 戦略
-   認証 / multi-user
-   通知
-   cloud deployment
-   backend API / DB schema / migration の変更
-   医学的判断
-   体重評価
-   栄養目標
-   dose / injection site の提案

------------------------------------------------------------------------

## 4. Architecture

基本構成は以下を推奨する。

``` text
mobile/lib/
├── app/
│   └── router.dart
│
├── core/
│   ├── config/
│   │   └── api_config.dart
│   └── network/
│       ├── api_client.dart
│       ├── api_error.dart
│       └── dio_provider.dart
│
└── features/
    └── dashboard/
        ├── data/
        │   ├── dashboard_api.dart
        │   └── dashboard_repository.dart
        ├── domain/
        │   └── dashboard.dart
        └── providers/
            └── dashboard_provider.dart
```

これは責務の例であり、既存 `mobile/lib/`
の構成がすでにある場合は、無理に全面移動しない。

重要なのは以下の依存方向を維持すること。

``` text
Provider
  ↓
Repository
  ↓
Dashboard API
  ↓
shared Dio
```

feature 内で独自に `Dio()` を生成してはいけない。

UI 層から Dio を直接呼んではいけない。

------------------------------------------------------------------------

## 5. API Base URL

API base URL はソースコードへ環境固有 URL をベタ書きしない。

Flutter の compile-time environment を使用する。

例:

``` bash
flutter run \
  --dart-define=API_BASE_URL=http://localhost:8000
```

Dart 側では概念的に:

``` dart
const String.fromEnvironment('API_BASE_URL')
```

を使用する。

### 5.1 Requirement

-   `API_BASE_URL` は共通 config から参照する
-   feature ごとに URL を定義しない
-   `/api/v1` の扱いは一箇所で一貫させる
-   trailing slash の有無で `//api/...` 等を生成しない
-   production URL、個人 LAN IP、固定 emulator IP を repository
    にベタ書きしない

### 5.2 Missing Configuration

`API_BASE_URL` が未設定または空の場合、silent fallback で適当な
production / localhost URL を採用してはいけない。

開発時に原因が分かる明示的な configuration error として扱う。

テストでは config を注入または override できる構造にする。

------------------------------------------------------------------------

## 6. Dio

Dio instance は Riverpod provider で一元管理する。

概念:

``` text
dioProvider
    ↓
dashboardApiProvider
    ↓
dashboardRepositoryProvider
    ↓
dashboardProvider
```

### 6.1 共通設定

少なくとも以下を共通設定する。

-   base URL
-   JSON response
-   connect timeout
-   receive timeout
-   send timeout

timeout の具体値は既存プロジェクト設定があればそれを優先する。

既存値がなければ、開発・MVPとして妥当な固定値を一箇所に定義する。

### 6.2 禁止

以下は禁止。

``` dart
final dio = Dio();
```

を feature / screen ごとに作成すること。

また、Spec 007 では以下を先回りして実装しない。

-   token refresh
-   authentication interceptor
-   automatic retry
-   offline queue
-   request cache
-   analytics interceptor

------------------------------------------------------------------------

## 7. API Version Path

Backend の Base API path は:

``` text
/api/v1
```

Dashboard endpoint:

``` text
GET /api/v1/dashboard
```

base URL と endpoint path の責務を一貫させる。

以下のどちらか一方に統一してよい。

``` text
baseUrl = http://localhost:8000/api/v1
path    = /dashboard
```

または:

``` text
baseUrl = http://localhost:8000
path    = /api/v1/dashboard
```

同じ project 内で方式を混在させない。

------------------------------------------------------------------------

## 8. Common API Error

Backend の共通 error envelope:

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

Flutter 側では DioException を feature / UI へそのまま露出させず、共通
error 型へ正規化する。

概念:

``` text
ApiException
- kind
- statusCode
- code
- message
- details
- cause
```

実際の命名は既存 style に合わせてよい。

------------------------------------------------------------------------

## 9. Error Kind

最低限、後続 UI が次を区別できるようにする。

``` text
SERVER
NETWORK
TIMEOUT
CONTRACT
CONFIGURATION
UNKNOWN
```

必要であれば `VALIDATION` 等を追加してよいが、backend の stable
`error.code` と transport-level kind を混同しない。

例:

``` text
HTTP 422 + VALIDATION_ERROR
kind       = SERVER
statusCode = 422
code       = VALIDATION_ERROR
```

または project 内でより明確な命名を採用してよい。

重要なのは、backend stable code を失わないこと。

------------------------------------------------------------------------

## 10. Error Details

backend の:

``` json
{
  "field": "timezone",
  "message": "Invalid timezone."
}
```

を表現できる typed model を用意する。

`details` は backend contract 上 optional なので、存在しない response
も正常に parse できること。

Flutter UI 向け日本語メッセージへの完全な mapping は Spec 007 の責務外。

Spec 007 では error の情報を失わず型へ正規化するところまでとする。

------------------------------------------------------------------------

## 11. HTTP Error Handling

HTTP status が 4xx / 5xx で、body が既存 backend error envelope
に従っている場合:

-   status code を保持
-   `error.code` を保持
-   `error.message` を保持
-   `error.details` を保持
-   共通 `ApiException` へ変換

例:

``` text
422
VALIDATION_ERROR
```

を DioException のまま上位へ投げない。

------------------------------------------------------------------------

## 12. Non-HTTP Error Handling

最低限以下を分類する。

### Timeout

-   connection timeout
-   send timeout
-   receive timeout

→ `TIMEOUT`

### Network

例:

-   connection refused
-   socket / connection failure
-   host unreachable

→ `NETWORK`

### Contract

例:

-   malformed JSON
-   必須 field 欠落
-   unknown enum
-   backend contract と矛盾する section
-   expected object が別型

→ `CONTRACT`

### Configuration

例:

-   `API_BASE_URL` missing / empty

→ `CONFIGURATION`

### Unknown

上記へ分類できない予期しない error。

------------------------------------------------------------------------

## 13. Dashboard Endpoint

Flutter 側で最初に利用する endpoint:

``` http
GET /api/v1/dashboard?date=2026-09-07&timezone=Asia/Tokyo
```

Repository の public API は概念的に:

``` dart
Future<Dashboard> getDashboard({
  required DateTime date,
  required String timezone,
});
```

または date-only をより明確に表現できる既存型が project
にある場合はそれを使用してよい。

新しい重量級 date library をこのためだけに追加しない。

------------------------------------------------------------------------

## 14. DATE Formatting

Backend の `date` query は:

``` text
YYYY-MM-DD
```

で送る。

`DateTime.toString()` の文字列を substring で雑に切り出す実装は禁止。

DATE 用 formatter / helper を明示的に用意する。

例として必要な behavior:

``` text
DateTime(2026, 9, 7)
-> 2026-09-07
```

month / day は zero padding。

DATE query 生成時に UTC conversion して calendar date
を意図せず変えない。

------------------------------------------------------------------------

## 15. timezone

Spec 007 では端末 timezone を自動検出しない。

Dashboard provider / repository 呼び出し側から明示的に:

``` text
date
timezone
```

を渡せる設計にする。

例:

``` text
Asia/Tokyo
America/New_York
```

Flutter 側で IANA timezone の完全な validation database
を重複実装する必要はない。

backend が authoritative。

ただし空文字等、明らかなローカル入力不備を既存設計上自然に防げる場合は最小限の
validation を行ってよい。

------------------------------------------------------------------------

## 16. Dashboard Domain Model

Spec 006 の response を型安全に表現する。

最低限以下に相当する model を用意する。

``` text
Dashboard
DashboardSectionStatus

DashboardWeightSection
DashboardWeightRecord

DashboardNutritionSection
DashboardNutritionRecord
DashboardNutritionMode

DashboardSymptomSection
DashboardSymptomRecord

DashboardInjectionSection
DashboardInjectionRecord
```

命名は Dart style / 既存 style に合わせてよい。

------------------------------------------------------------------------

## 17. Section Status

backend:

``` text
RECORDED
UNRECORDED
```

を Dart enum 等へ変換する。

UI / feature 層で生文字列:

``` dart
if (status == 'RECORDED')
```

のような比較を繰り返さない。

unknown value を `UNRECORDED` に fallback してはいけない。

unknown status は API contract violation。

------------------------------------------------------------------------

## 18. Section Invariant

Spec 006 の不変条件:

``` text
RECORDED   -> record != null
UNRECORDED -> record == null
```

を Dart parse / model construction 時にも検証する。

以下は contract violation:

``` json
{
  "status": "RECORDED",
  "record": null
}
```

および:

``` json
{
  "status": "UNRECORDED",
  "record": {
    "record_date": "2026-09-07"
  }
}
```

silent correction してはいけない。

例:

``` text
RECORDED + null
-> UNRECORDED
```

のように勝手に書き換えることは禁止。

------------------------------------------------------------------------

## 19. Dashboard Weight Model

backend response:

``` json
{
  "status": "RECORDED",
  "record": {
    "record_date": "2026-09-05",
    "weight_kg": 65.5
  }
}
```

Dart 側では:

-   `record_date` を date として扱える型へ parse
-   `weight_kg` を numeric value として扱う
-   nullability は section invariant と一致させる

Dashboard model に backend が返していない detail field を追加しない。

------------------------------------------------------------------------

## 20. Dashboard Nutrition Model

NORMAL:

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

FREE_DAY:

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

UNRECORDED:

``` json
{
  "status": "UNRECORDED",
  "record": null
}
```

`mode` は:

``` text
NORMAL
FREE_DAY
```

を enum 等へ変換する。

unknown mode は contract violation。

### 20.1 Nutrition Invariant

NORMAL:

``` text
total_calories != null
total_protein_g != null
```

FREE_DAY:

``` text
total_calories == null
total_protein_g == null
```

Spec 006 と矛盾する JSON を silent fallback しない。

FREE_DAY を 0 として変換しない。

UNRECORDED と FREE_DAY を同一視しない。

------------------------------------------------------------------------

## 21. Dashboard Symptom Model

backend:

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

`bowel_condition` は nullable。

既存値:

``` text
NORMAL
CONSTIPATION
DIARRHEA
OTHER
null
```

文字列 enum として扱う場合、unknown non-null value は contract
violation。

`recorded_at` は `DateTime` へ parse する。

backend response は UTC Z だが、domain model で勝手に端末 local time
へ変換しない。

表示時の local conversion は UI の責務。

症状値から severity / diagnosis を導出しない。

------------------------------------------------------------------------

## 22. Dashboard Injection Model

RECORDED:

``` json
{
  "status": "RECORDED",
  "record": {
    "record_date": "2026-09-01"
  },
  "next_scheduled_date": "2026-09-08"
}
```

UNRECORDED:

``` json
{
  "status": "UNRECORDED",
  "record": null,
  "next_scheduled_date": null
}
```

追加 invariant:

``` text
record == null
-> next_scheduled_date == null
```

RECORDED の場合、Spec 006 response contract 上 `next_scheduled_date` は
non-null。

矛盾する JSON は contract violation。

Flutter 側で `record_date + 7 days` を再計算して backend
値を上書きしない。

backend response を authoritative な read model として扱う。

この値を医学的な投与判断として解釈・表示するロジックは Spec 007
では追加しない。

------------------------------------------------------------------------

## 23. Freezed / JSON Serialization

Spec 007 で新規 model を実装する際、Freezed を使用してよい。

既存 dependencies に不足があれば、必要最小限で以下に相当する package
を追加する。

runtime:

``` text
freezed_annotation
json_annotation
```

dev:

``` text
build_runner
freezed
json_serializable
```

Dio / Riverpod が既存 dependency にある場合は重複・不要な変更をしない。

### 23.1 Generated Code

生成コードを使用する構成の場合:

-   正規の generator command で生成
-   手編集しない
-   repository に含める
-   generation 後に analyzer / test を実行

### 23.2 Custom Validation

Freezed / `json_serializable` の自動 parse だけでは section invariant
を保証できない場合、factory / converter / DTO → domain mapping
等で明示的に検証する。

「生成コードを使うために invariant を諦める」ことは禁止。

------------------------------------------------------------------------

## 24. Dashboard API Client

Dashboard API client は HTTP details を担当する。

責務:

-   GET `/api/v1/dashboard`
-   `date` query の format
-   `timezone` query
-   response body の受け取り
-   transport / HTTP error の共通 error への変換に必要な連携

API client が UI state を管理してはいけない。

------------------------------------------------------------------------

## 25. Dashboard Repository

Repository は feature 側の取得窓口。

概念:

``` dart
Future<Dashboard> getDashboard({
  required DateTime date,
  required String timezone,
});
```

責務:

-   Dashboard API の呼び出し
-   JSON / DTO → domain model
-   API contract validation
-   domain model の返却

Repository から DioException をそのまま外へ漏らさない。

------------------------------------------------------------------------

## 26. Riverpod Providers

最低限以下に相当する provider を用意する。

``` text
apiConfigProvider
dioProvider
dashboardApiProvider
dashboardRepositoryProvider
dashboardProvider
```

既存 provider naming/style がある場合は合わせる。

Dashboard provider は `date` と `timezone` を引数に取得できる family
相当の設計にする。

概念:

``` text
dashboardProvider(date, timezone)
```

UI はまだ作らないため、この Spec では provider
が存在しテスト可能であればよい。

------------------------------------------------------------------------

## 27. Provider State

Dashboard の非同期状態は Riverpod の標準的な async state を使用する。

独自に:

``` text
isLoading
hasError
data
```

を重複保持する巨大 state class をこの段階で作らない。

後続 UI が:

``` text
loading
data
error
```

を扱える構造にする。

------------------------------------------------------------------------

## 28. Contract Violation

以下は network error や UNRECORDED として扱わず、API contract violation
とする。

例:

-   malformed JSON
-   response root が object でない
-   required field missing
-   wrong primitive type
-   unknown section status
-   RECORDED + record null
-   UNRECORDED + record non-null
-   unknown Nutrition mode
-   NORMAL + null totals
-   FREE_DAY + non-null totals
-   unknown bowel condition
-   invalid ISO date
-   invalid timestamp
-   Injection record null + next date non-null
-   Injection RECORDED + next date null

contract violation は後続 UI が「未記録」と誤認しない形で error state
へ流す。

------------------------------------------------------------------------

## 29. Unknown Extra Fields

backend が将来 additive field を追加する可能性を考慮し、既知 field の
parse に不要な extra JSON field まで理由なく拒否する必要はない。

ただし既知 field の型・enum・invariant は strict に検証する。

この方針は backend の「extra request fields
reject」とは別であり、response の forward compatibility のためのもの。

------------------------------------------------------------------------

## 30. Backend Error Envelope Parse Failure

4xx / 5xx response で backend error envelope が正しく parse
できない場合:

-   成功 response として扱わない
-   backend stable code を捏造しない
-   `CONTRACT` または適切な unexpected-server-response category
    として扱う

HTML error page 等を通常の API error envelope と誤認しない。

------------------------------------------------------------------------

## 31. Logging

Spec 007 のために本格的な logging framework を追加しない。

debug 時に必要な最小限の情報を扱う場合も、将来 token / sensitive data
が入る可能性を考慮し、request / response body 全体を無条件に print する
interceptor は追加しない。

------------------------------------------------------------------------

## 32. Testing Strategy

unit test はローカル FastAPI server や PostgreSQL
が起動していなくても再現可能にする。

Dio の adapter、fake、mock、dependency override 等を利用し、network
boundary を制御する。

CI / 通常の `flutter test` を:

``` text
localhost:8000
```

へ依存させない。

------------------------------------------------------------------------

## 33. 必須テスト契約

最低限、以下を意味的に網羅する。

### 33.1 API Config

1.  有効な API base URL を使用できる
2.  API base URL の trailing slash を安全に扱う
3.  missing / empty API base URL を silent fallback しない
4.  test から config を override できる

### 33.2 Date Query

5.  `2026-09-07` 形式で送信
6.  month / day zero padding
7.  DateTime の timezone conversion で意図せず DATE を変更しない
8.  timezone query をそのまま送る

### 33.3 Normal Dashboard Parse

9.  完全な RECORDED response を parse
10. Weight numeric parse
11. Nutrition NORMAL parse
12. Nutrition total numeric parse
13. Symptom timestamp parse
14. nullable bowel_condition parse
15. Injection date parse
16. next_scheduled_date parse

### 33.4 UNRECORDED

17. 全 section UNRECORDED response を parse
18. UNRECORDED record が null
19. Injection UNRECORDED + next null

### 33.5 FREE_DAY

20. FREE_DAY を NORMAL と区別
21. FREE_DAY totals null
22. FREE_DAY を 0 totals に変換しない

### 33.6 Section Invariants

23. RECORDED + null record -\> CONTRACT
24. UNRECORDED + non-null record -\> CONTRACT
25. unknown status -\> CONTRACT

### 33.7 Nutrition Invariants

26. unknown mode -\> CONTRACT
27. NORMAL + null calories -\> CONTRACT
28. NORMAL + null protein -\> CONTRACT
29. FREE_DAY + non-null calories -\> CONTRACT
30. FREE_DAY + non-null protein -\> CONTRACT

### 33.8 Symptom Contract

31. invalid recorded_at -\> CONTRACT
32. unknown bowel_condition -\> CONTRACT
33. bowel_condition null を受理

### 33.9 Injection Contract

34. UNRECORDED + next non-null -\> CONTRACT
35. RECORDED + next null -\> CONTRACT
36. invalid next date -\> CONTRACT

### 33.10 Malformed Response

37. malformed JSON -\> CONTRACT
38. root が object でない -\> CONTRACT
39. required field missing -\> CONTRACT
40. wrong primitive type -\> CONTRACT

### 33.11 Backend Error

41. 422 error envelope を ApiException へ変換
42. statusCode 422 を保持
43. `VALIDATION_ERROR` code を保持
44. message を保持
45. details を保持
46. details omitted を受理
47. 500 error envelope を共通 error へ変換
48. malformed 4xx / 5xx body を成功扱いしない

### 33.12 Transport Error

49. connect timeout -\> TIMEOUT
50. send timeout -\> TIMEOUT
51. receive timeout -\> TIMEOUT
52. connection failure -\> NETWORK
53. unexpected error -\> UNKNOWN または定義済み適切 category

### 33.13 Provider / Repository

54. dashboardRepositoryProvider が shared API client を使用
55. dashboardProvider が date / timezone を受け取る
56. success 時に Dashboard model を返す
57. failure 時に error state となる
58. DioException が provider consumer まで生で漏れない

### 33.14 Forward Compatibility

59. response に未知の extra field があっても既知契約が正しければ parse
    できる

テスト関数数は上記件数と一致させる必要はない。parameterized tests
等を使用してよい。

------------------------------------------------------------------------

## 34. Manual Integration Check

unit test とは別に、可能な環境ではローカル FastAPI / PostgreSQL
を起動し、Flutter/Dart 側から実 endpoint:

``` text
GET /api/v1/dashboard
```

へ到達できることを確認する。

ただしこの manual check のために test suite を localhost
依存へ変更しない。

環境によって `localhost` が host machine
を指さない場合があるため、Android emulator / physical device
等の環境固有 host address を repository の default 値として固定しない。

実行時の `--dart-define=API_BASE_URL=...` で解決する。

manual check
が環境上実施できない場合は、未実施理由を完了報告へ明記すればよい。

------------------------------------------------------------------------

## 35. Backend Non-Modification

Spec 007 は Flutter 側の基盤 Spec。

原則として以下を変更しない。

``` text
backend/
docs/database-design.md
backend migration
backend models
backend API behavior
```

Flutter 実装中に backend contract の問題を発見した場合、勝手に backend
を変更せず報告する。

------------------------------------------------------------------------

## 36. Dependency Policy

新規 dependency は必要最小限。

追加前に既存 `pubspec.yaml` を確認する。

想定候補:

``` text
dio
flutter_riverpod
freezed_annotation
json_annotation
```

dev:

``` text
build_runner
freezed
json_serializable
```

すでに導入済みなら version を理由なく変更しない。

同じ目的の別 package を重複導入しない。

日付 format のためだけに重量級 dependency を追加する必要はない。

mock package についても、Dio adapter / simple fake
で十分なら追加しない。

------------------------------------------------------------------------

## 37. Generated Files

code generation を使用する場合、実装後に generator を実行する。

一般例:

``` bash
dart run build_runner build --delete-conflicting-outputs
```

実際には既存 project の standard command があればそれに従う。

generated file を手書きしない。

generated file の差分も review 対象とする。

------------------------------------------------------------------------

## 38. Formatting / Static Analysis / Test

実装後、少なくとも Flutter project で以下を実行する。

``` bash
cd mobile

dart format .
flutter analyze
flutter test
```

code generation を使用する場合は analyze / test より前に generator
を実行する。

例:

``` bash
dart run build_runner build --delete-conflicting-outputs
dart format .
flutter analyze
flutter test
```

repository root で:

``` bash
git diff --check
git status --short
```

も確認する。

既存 project に追加の standard verification command
がある場合はそれも実行する。

------------------------------------------------------------------------

## 39. Acceptance Criteria

### AC-01

API base URL が共通 config から取得され、feature に環境固有 URL
がベタ書きされていない。

### AC-02

`API_BASE_URL` missing / empty を silent fallback しない。

### AC-03

Dio instance が Riverpod で一元管理される。

### AC-04

Dashboard feature が独自 `Dio()` を生成しない。

### AC-05

Dashboard API client が `GET /api/v1/dashboard` を呼べる。

### AC-06

Dashboard request の date が `YYYY-MM-DD` で送信される。

### AC-07

timezone が query parameter として送信される。

### AC-08

Dashboard response を型安全な Dart model へ parse できる。

### AC-09

RECORDED / UNRECORDED を enum 等で表現する。

### AC-10

unknown section status を contract violation とする。

### AC-11

`RECORDED -> record != null` を検証する。

### AC-12

`UNRECORDED -> record == null` を検証する。

### AC-13

Nutrition NORMAL / FREE_DAY を型で区別する。

### AC-14

Nutrition NORMAL の totals は non-null。

### AC-15

Nutrition FREE_DAY の totals は null。

### AC-16

FREE_DAY を zero totals や UNRECORDED に変換しない。

### AC-17

Symptom `recorded_at` を DateTime として parse する。

### AC-18

Symptom bowel_condition null を扱える。

### AC-19

unknown bowel_condition を contract violation とする。

### AC-20

Injection の record_date / next_scheduled_date を date として parse
する。

### AC-21

Injection UNRECORDED では next_scheduled_date が null。

### AC-22

Injection RECORDED では next_scheduled_date が non-null。

### AC-23

Flutter 側で next_scheduled_date を独自再計算しない。

### AC-24

backend error envelope を共通 ApiException へ変換する。

### AC-25

backend stable error code / statusCode / message / details を失わない。

### AC-26

DioException を repository / provider consumer へそのまま漏らさない。

### AC-27

timeout を transport error として分類できる。

### AC-28

connection failure を network error として分類できる。

### AC-29

malformed JSON / contract mismatch を UNRECORDED として扱わない。

### AC-30

未知の additive response field は既知契約が正しければ許容する。

### AC-31

Dashboard repository が実装される。

### AC-32

Dashboard provider が date / timezone を引数に取得できる。

### AC-33

Provider が成功時に Dashboard domain model を返す。

### AC-34

Provider が失敗時に Riverpod の error state になる。

### AC-35

unit tests が実 FastAPI / PostgreSQL の起動を必須としない。

### AC-36

必要な Freezed / serialization generated code が正規 generator
で生成される。

### AC-37

`dart format .` が成功する。

### AC-38

`flutter analyze` が成功する。

### AC-39

`flutter test` が成功する。

### AC-40

`git diff --check` が成功する。

### AC-41

backend / DB / migration を変更しない。

### AC-42

Home / Dashboard UI を実装しない。

### AC-43

POST / PUT / DELETE feature を先回りして実装しない。

### AC-44

端末 timezone 自動検出を追加しない。

### AC-45

offline / retry / auth / notification を追加しない。

### AC-46

医学的判断、症状診断、体重評価、栄養目標、dose/site 推奨を追加しない。

------------------------------------------------------------------------

## 40. Scope Guardrail

実装中に「今後必要になるから」という理由だけで以下を先回りしない。

-   generic CRUD repository
-   generic pagination framework
-   auth token architecture
-   refresh token interceptor
-   retry middleware
-   offline synchronization
-   SQLite / local DB
-   caching
-   analytics
-   logging framework
-   notification
-   device timezone plugin
-   Weight/Food/Symptom/Injection write API
-   Home UI

Spec 007 は「共通通信基盤 + Dashboard read
path」を完成させることに集中する。

------------------------------------------------------------------------

## 41. 完了報告

Codex は実装完了時に以下を報告すること。

1.  変更ファイル
2.  追加・変更した dependencies
3.  API base URL の設定方法
4.  Dio の共通構成
5.  ApiException / error classification
6.  Dashboard model の構成
7.  section invariant の検証方法
8.  Dashboard API / Repository / Provider の依存関係
9.  date / timezone query の生成方法
10. 追加した test の概要と件数
11. code generation command と結果
12. `dart format` の結果
13. `flutter analyze` の結果
14. `flutter test` の結果
15. manual integration check の実施有無と結果
16. `git diff --check` の結果
17. Scope 外変更の有無
18. 未解決事項

------------------------------------------------------------------------

## 42. Commit / Push

実装・verification が成功しても、ユーザーから明示的な指示があるまで
commit / push しない。

Spec 007 の実装完了報告後にレビューを受けること。
