# Spec 010 — Flutter Symptom UI

## 1. 目的

Spec 004 で実装済みの Symptom API と、Spec 007 の Flutter API 通信基盤を利用し、Flutter から体調記録を作成・編集・削除できる UI を実装する。

Spec 010 の完成状態では、ユーザーが指定日時について以下を行えること。

- nausea / abdominal_pain / fatigue / appetite を 1〜10 で記録する
- bowel_condition を任意で記録する
- memo を任意で記録する
- 体調記録を新規作成する
- 既存記録を編集する
- 既存記録を削除する
- 指定日の体調記録を一覧で確認する
- backend の timezone-aware timestamp contract を正しく扱う
- API / validation / not-found error を安全に扱う

本 Spec では、数値を医学的重症度や診断に自動変換しない。
強い症状を示す入力があった場合でも、アプリが薬の増減や治療変更を提案してはならない。

---

## 2. 実装前に読むもの

Codex は実装前に以下を読むこと。

1. `AGENTS.md`
2. `README.md`
3. `docs/api-design.md`
4. `docs/database-design.md`
5. `specs/004-symptom-api.md`
6. `specs/006-dashboard-api.md`
7. `specs/007-flutter-api-foundation.md`
8. `specs/008-flutter-weight-ui.md`
9. `specs/009-flutter-food-ui-nutrition-free-day.md`
10. `mobile/pubspec.yaml`
11. `mobile/lib/`
12. `mobile/test/`
13. backend の Symptom router / schemas / services / tests

Symptom の authoritative contract は Spec 004 と実際の backend 実装とする。

矛盾を発見した場合、backend を勝手に変更せず報告する。

---

## 3. Scope

### 3.1 IN

- Symptom domain model
- Symptom request model
- Symptom repository
- Riverpod controller / provider
- Symptom screen
- 指定日の体調記録一覧
- create
- update
- delete
- local validation
- timezone-aware timestamp serialization
- IANA timezone を用いた日付filter
- loading / ready / error / busy state
- stale response 対策
- duplicate mutation 防止
- delete confirmation
- Record menu → Symptom screen navigation
- neutral Japanese UI
- unit / widget tests

### 3.2 OUT

- 医学的診断
- severity classification
- emergency score
- triage algorithm
- 薬の増減提案
- Mounjaro / tirzepatide dose recommendation
- 症状と薬効の因果推定
- AI analysis
- symptom graph
- symptom history across arbitrary ranges
- Dashboard UI
- Injection UI
- notification
- authentication
- offline/cache/retry
- backend / DB / migration changes

---

## 4. Backend Endpoints

使用する endpoint は実際の Spec 004 / backend 実装を優先する。

概念上:

```http
POST   /api/v1/symptoms
GET    /api/v1/symptoms
GET    /api/v1/symptoms/{id}
PUT    /api/v1/symptoms/{id}
DELETE /api/v1/symptoms/{id}
```

日単位一覧は GET list endpoint に日付filterとtimezoneを指定して取得する。

実際の query parameter 名は Spec 004 / backend に合わせること。

---

## 5. Symptom Model

最低限:

```text
id
recordedAt
nausea
abdominalPain
fatigue
appetite
bowelCondition
memo
createdAt
updatedAt
```

API snake_case:

```text
recorded_at
nausea
abdominal_pain
fatigue
appetite
bowel_condition
memo
created_at
updated_at
```

---

## 6. Scale Contract

以下はすべて integer 1〜10。

```text
nausea
abdominal_pain
fatigue
appetite
```

意味:

```text
larger number = stronger state
```

appetite:

```text
1 = 食欲がかなり低い
10 = 食欲がかなり強い
```

Flutter は 1〜10 以外を送らない。

0 / 11 / decimal / string を送信しない。

API response でも 1〜10 outside range は CONTRACT error。

---

## 7. UI Labels

中立的な日本語:

```text
吐き気
腹痛
だるさ
食欲
```

1〜10 の scale 自体を「良い / 悪い」「危険 / 安全」のように評価しない。

補助説明が必要なら:

```text
1〜10で現在の程度を記録してください。
```

程度が強い症状については一般的な医療安全文言のみ許可する。

例:

```text
強い症状や気になる変化がある場合は、医療機関へ相談してください。
```

薬の調整案は出さない。

---

## 8. Bowel Condition

backend contract:

```text
NORMAL
CONSTIPATION
DIARRHEA
OTHER
null
```

Flutter enum 等で明示的に扱う。

UI表示:

```text
記録しない
通常
便秘
下痢
その他
```

unknown backend value を fallback で OTHER にしない。
CONTRACT error とする。

---

## 9. Memo

- nullable
- max 500 characters
- empty / whitespace-only は null として送ってよい
- 500文字超過は送信前 reject

---

## 10. Create Request

概念:

```json
{
  "recorded_at": "2026-09-08T12:30:00+09:00",
  "nausea": 3,
  "abdominal_pain": 2,
  "fatigue": 5,
  "appetite": 4,
  "bowel_condition": "NORMAL",
  "memo": null
}
```

`id`, `created_at`, `updated_at` は送らない。

---

## 11. Update Request

PUT は complete update。

概念:

```json
{
  "recorded_at": "2026-09-08T12:45:00+09:00",
  "nausea": 2,
  "abdominal_pain": 2,
  "fatigue": 4,
  "appetite": 5,
  "bowel_condition": null,
  "memo": "少し楽になった"
}
```

idはURL pathで指定する。

---

## 12. recorded_at

`recorded_at` は timezone-aware timestamp。

Spec 008 / 009 で使っている shared timezone-aware serializer を再利用する。

固定 `+09:00` 禁止。

response は timezone-aware RFC3339 / ISO8601 を受理する。

例:

```text
2026-09-08T03:30:00Z
2026-09-08T12:30:00+09:00
2026-09-07T23:30:00-04:00
```

timezoneなし:

```text
2026-09-08T12:30:00
```

は CONTRACT error。

---

## 13. Day Filtering

Symptom は DB 上 DATE を持たない。

日単位表示は `recorded_at` と timezone に基づく。

Spec 004 の contract に従い、calendar date filter は IANA timezone を使用する。

例:

```text
Asia/Tokyo
```

固定offsetだけで日境界を計算しない。

DSTがある timezone でも backend が正しい日境界を計算できるよう、実際の endpoint contract に従って timezone query parameter を送る。

Flutter 側で local day start/end を勝手にUTCへ計算して authoritative filter にしない。

---

## 14. Timezone Source

Spec 010 では新規timezone package追加を原則禁止。

既存コード / SDK / project configuration から IANA timezone を安全に取得できる仕組みが既にある場合は再利用する。

もし現在のFlutter基盤から IANA timezone identifier を取得する手段が存在せず、Spec 004 endpoint が必須で要求する場合:

- 勝手に `Asia/Tokyo` を固定しない
- 勝手に offsetだけ送らない
- dependency追加を独断で行わない
- 実装を止め、blockerとして報告する

この場合はユーザー判断を仰ぐ。

---

## 15. Symptom Screen

最低限:

```text
体調記録

日付
[ 2026/09/08 ]

[ 体調を記録 ]

12:30
吐き気 3
腹痛 2
だるさ 5
食欲 4
便通 通常

18:10
...
```

同一日に複数記録を許可する。

---

## 16. List Ordering

backend contract:

```text
recorded_at DESC, id DESC
```

Flutter は backend ordering を基本的に保持する。

独自で ascending に並び替えない。

---

## 17. Create Form

概念:

```text
体調を記録

時刻
[ 12:30 ]

吐き気
[ 1 ... 10 ]

腹痛
[ 1 ... 10 ]

だるさ
[ 1 ... 10 ]

食欲
[ 1 ... 10 ]

便通
[ 記録しない ▼ ]

メモ（任意）
[               ]

[ 保存 ]
```

---

## 18. Edit Form

既存record tapでedit formを開く。

prefill:

- recorded_at の local time
- nausea
- abdominal_pain
- fatigue
- appetite
- bowel_condition
- memo

actions:

```text
更新
記録を削除
```

---

## 19. Input Widgets

1〜10 scale は Slider / Segmented control / Dropdown 等のいずれでもよい。

最優先:

- 現在値が数字で明示される
- 1〜10以外を選べない
- accessibility label がある
- 4項目の意味を取り違えない

---

## 20. Create Default

新規form:

```text
recorded_at = selected date + current local time
nausea = 1
abdominal_pain = 1
fatigue = 1
appetite = 1
bowel_condition = null
memo = empty
```

ただし、デフォルト値が「症状なし」「正常」と医学的評価される表現は避ける。

UIで「1」を単なるscale最小値として扱う。

---

## 21. Date Guard

Food UIと同様、古い日付のformを新しいselected dateへ誤送信しない。

例:

```text
9/8 form open
→ screen dateを9/9に変更
→ 古い9/8 form submit
```

このmutationは実行しない。

---

## 22. Create

POST success 後:

- selected dayを再GETしてbackend truthへreconcileしてよい
- または responseを安全にlistへ反映してよい

ただし Spec 004 のorderingやfilter contractを確実に反映するため、推奨は再GET。

```text
POST
→ GET selected day
→ state更新
```

---

## 23. Update

PUT success 後:

```text
PUT
→ GET selected day
→ state更新
```

を推奨。

recorded_at の時刻変更により ordering が変わる可能性があるため、local list patchのみで済ませない。

---

## 24. Delete

削除前:

```text
この体調記録を削除しますか？
```

actions:

```text
キャンセル
削除
```

success:

```text
DELETE
→ GET selected day
→ state更新
```

DELETE 204 body は parse しない。

---

## 25. Reconciliation Strategy

selected day の record list は backend authoritative。

mutation後:

```text
POST / PUT / DELETE
→ GET day list
→ state update
```

を基本とする。

Flutter独自sortによってbackend orderingを上書きしない。

---

## 26. Loading / State

最低限:

```text
initial loading
ready
error
busy mutation
```

を区別する。

GET失敗時に empty list として扱わない。

空リストは正常なready state。

---

## 27. Empty State

record 0件:

```text
この日の体調記録はまだありません。
```

errorと混同しない。

---

## 28. Stale Response

Spec 008 / 009 と同様に、generation + operation date 等で保護する。

対象:

- old GET
- old create
- old update
- old delete
- old reconciliation GET

例:

```text
9/8 GET pending
→ 9/9へ変更
→ 9/8 GET complete
```

9/9 stateを上書きしてはいけない。

---

## 29. Duplicate Mutation

mutation中は:

- 保存
- 更新
- 削除

の重複送信を防ぐ。

必要なら screen上の日付変更もbusy中disableしてよい。

---

## 30. Error Semantics

最低限stable code:

```text
VALIDATION_ERROR
SYMPTOM_NOT_FOUND
```

`SYMPTOM_NOT_FOUND`:

```text
この体調記録は見つかりませんでした。再読み込みしてください。
```

network:

```text
サーバーに接続できませんでした。
```

timeout:

```text
通信がタイムアウトしました。
```

fallback:

```text
体調記録の処理中にエラーが発生しました。
```

DioExceptionをUIへ漏らさない。

---

## 31. Strong Symptom Safety

アプリは4scaleから医学的重症度を判定しない。

たとえば `10` が入力されたからといって、

```text
重症
危険
緊急
薬を中止
投与量を下げる
```

等を自動表示しない。

ただし、一般的な安全文言として:

```text
強い症状や気になる変化がある場合は、医療機関へ相談してください。
```

を画面下部等に常設してよい。

---

## 32. Medication Safety

Symptom UIは薬のdoseと直接連動させない。

禁止:

- dose変更提案
- injection interval変更提案
- symptom scoreをdose変更条件にする
- 「症状が強いので次回は減量」等

Spec 010はloggingのみ。

---

## 33. Repository Boundary

概念:

```text
SymptomRepository
- listByDate(date, timezone)
- create(request)
- update(id, request)
- delete(id)
```

shared Dioを利用。

feature内 `Dio()` 禁止。

success malformed bodyは CONTRACT。

204 DELETE body parse禁止。

---

## 34. Controller Responsibility

最低限:

- selected date
- current records
- loading / ready / error
- busy
- load
- create
- update
- delete
- mutation後reconciliation
- stale response guard
- duplicate mutation guard
- error mapping

TextEditingController等のWidget objectをprovider stateへ入れない。

---

## 35. UI Responsibility

Widget:

- date picker
- record list
- create/edit form
- input widgets
- confirmation dialog
- validation message
- success feedback
- provider/controller action

を担当する。

DioException判定やHTTP path constructionをWidgetへ書かない。

---

## 36. Navigation

Record menuに:

```text
[ 体調 ]
```

を追加。

route例:

```text
/record/symptom
```

既存:

```text
/record/weight
/record/food
```

を壊さない。

Injection UIはまだ実装しない。

---

## 37. Accessibility / UX

- 4scaleのlabelを常時表示
- 現在のnumeric valueを表示
- bowel conditionの意味が選択肢から分かる
- memo multiline
- destructive action明示
- busyを色だけで表現しない
- Japanese neutral wording

---

## 38. Numeric Contract

response:

- int only
- boolはint扱いしない
- 1〜10のみ

request:

- int only
- 1〜10のみ

double 1.0 を勝手に1へ丸めない。

---

## 39. Response Parsing

Symptom response:

- required field missing → CONTRACT
- wrong type → CONTRACT
- out-of-range scale → CONTRACT
- unknown bowel_condition → CONTRACT
- naive timestamp → CONTRACT
- invalid timestamp → CONTRACT
- additive unknown fields → allow

nullable `bowel_condition` / `memo` は key存在を要求し、value nullを許可する。

---

## 40. Date List Response Parsing

実際の backend response shape を確認して実装する。

page/list wrapperが存在する場合はそのcontractに従う。

推測で:

```text
[]
```

だけを想定しない。

pagination metadata等があるなら正しくparseする。

---

## 41. Pagination

Spec 004 list endpoint が offset pagination を要求する場合:

Spec 010では selected day の全recordを表示するために必要な範囲だけ扱う。

ただし勝手に巨大limitを設定しない。

既存API contractにdefault / max limitがある場合、それに従う。

もし一日分が複数pageに分かれる可能性があり、UI要件上全件表示が必要なら、その既存contractに従ってpage取得する。

不要な汎用pagination UIは実装しない。

---

## 42. Testing Strategy

実 FastAPI / PostgreSQL に依存しない。

- fake repository
- Dio interceptor / adapter
- Riverpod override
- widget test

を利用してよい。

manual integrationのみ実backendを使用してよい。

---

## 43. 必須テスト契約

テスト関数数はこの数と一致させる必要はない。

### Model

1. valid Symptom parse
2. additive field allowed
3. missing required field reject
4. scale string reject
5. scale double reject
6. scale 0 reject
7. scale 11 reject
8. valid bowel NORMAL
9. CONSTIPATION
10. DIARRHEA
11. OTHER
12. null bowel
13. unknown bowel reject
14. memo null allowed
15. Z timestamp accepted
16. positive offset timestamp accepted
17. negative offset timestamp accepted
18. naive timestamp rejected
19. invalid timestamp rejected

### Serialization

20. request snake_case
21. scale JSON integer
22. recorded_at timezone-aware
23. memo trim-empty -> null
24. bowel null serialized correctly
25. id excluded
26. created_at excluded
27. updated_at excluded

### Validation

28. all scales 1 accepted
29. all scales 10 accepted
30. out-of-range rejected
31. memo >500 rejected
32. invalid form sends no request

### Repository

33. list path/query correct
34. IANA timezone sent
35. create path/body
36. update path/body/id
37. delete path
38. shared Dio
39. 204 no body parse
40. Dio network normalized
41. timeout normalized
42. stable SYMPTOM_NOT_FOUND preserved
43. malformed success -> CONTRACT

### Controller

44. selected day load success
45. empty list is ready
46. load failure is error, not empty
47. old GET ignored
48. create -> reconcile
49. update -> reconcile
50. delete -> reconcile
51. old create ignored
52. old update ignored
53. old delete ignored
54. old reconcile ignored
55. duplicate mutation prevented
56. old-date form mutation prevented
57. reconciliation failure -> error
58. SYMPTOM_NOT_FOUND preserved

### Widget

59. Symptom route reachable
60. Weight route still reachable
61. Food route still reachable
62. empty state
63. list rendering
64. create form fields
65. scale values visible
66. create default values
67. create success neutral feedback
68. edit prefill
69. edit success neutral feedback
70. delete confirmation cancel
71. delete confirmation accept
72. bowel options render
73. memo renders
74. validation blocks request
75. busy disables duplicate action
76. no severity classification
77. no dose recommendation
78. general clinician consultation safety text may render
79. no Injection UI implemented

---

## 44. Manual Integration

可能なら実 backend + PostgreSQLで:

```text
1. selected day GET → 0件
2. POST symptom
3. GET → 1件
4. PUT symptom
5. GET → updated
6. second POST same day
7. GET ordering確認
8. DELETE
9. GET
```

を確認する。

日付filterは実端末 / 実環境の IANA timezone contractで確認する。

実施できない場合は理由を報告する。

---

## 45. Backend Non-Modification

変更禁止:

```text
backend/
database schema
Alembic migrations
```

contract不整合があれば報告。

---

## 46. Dependency Policy

原則dependency追加なし。

Flutter SDK + 既存 Riverpod / Dio / GoRouter を利用する。

特にtimezone取得のためだけに新packageを無断追加しない。

IANA timezone取得が現状不可能ならblockerとして報告する。

---

## 47. Verification

```bash
cd mobile
dart format .
flutter analyze
flutter test --reporter compact

cd ..
git diff --check
git status --short
git diff -- backend
git diff -- mobile/pubspec.yaml mobile/pubspec.lock
```

---

## 48. Acceptance Criteria

### AC-01
Record menuからSymptom screenへ遷移できる。

### AC-02
Weight routeを壊さない。

### AC-03
Food routeを壊さない。

### AC-04
selected dateを変更できる。

### AC-05
指定日のSymptom一覧を取得できる。

### AC-06
日付filterにSpec 004準拠のIANA timezoneを使用する。

### AC-07
IANA timezoneが取得不能なら固定値で誤魔化さずblocker報告する。

### AC-08
同日複数recordを表示できる。

### AC-09
backend orderingを保持する。

### AC-10
empty listをreadyとして扱う。

### AC-11
GET failureをempty listへ変換しない。

### AC-12
nauseaを1〜10で入力できる。

### AC-13
abdominal_painを1〜10で入力できる。

### AC-14
fatigueを1〜10で入力できる。

### AC-15
appetiteを1〜10で入力できる。

### AC-16
scaleはJSON integer。

### AC-17
scale outside 1〜10をrejectする。

### AC-18
decimal scaleをrejectする。

### AC-19
bowel_condition nullを扱える。

### AC-20
NORMALを扱える。

### AC-21
CONSTIPATIONを扱える。

### AC-22
DIARRHEAを扱える。

### AC-23
OTHERを扱える。

### AC-24
unknown bowel conditionをCONTRACT errorにする。

### AC-25
memoを任意入力できる。

### AC-26
memo >500をrejectする。

### AC-27
recorded_atをtimezone-awareで送る。

### AC-28
shared timestamp serializerを再利用する。

### AC-29
固定+09:00を使わない。

### AC-30
Z response timestampを受理する。

### AC-31
positive offset responseを受理する。

### AC-32
negative offset responseを受理する。

### AC-33
naive timestampをCONTRACT errorにする。

### AC-34
Food/Weightと同様にstrict parsingする。

### AC-35
POST createできる。

### AC-36
PUT updateできる。

### AC-37
DELETEできる。

### AC-38
DELETE前confirmationを表示する。

### AC-39
create後backend stateへreconcileする。

### AC-40
update後backend stateへreconcileする。

### AC-41
delete後backend stateへreconcileする。

### AC-42
old GETが新日付stateを上書きしない。

### AC-43
old createが新日付stateを上書きしない。

### AC-44
old updateが新日付stateを上書きしない。

### AC-45
old deleteが新日付stateを上書きしない。

### AC-46
old reconciliationが新日付stateを上書きしない。

### AC-47
旧日付formを新日付へ送信しない。

### AC-48
duplicate mutationを防ぐ。

### AC-49
reconciliation failure時にlocal stateを捏造しない。

### AC-50
DioExceptionをUIへ漏らさない。

### AC-51
shared Dioを使用する。

### AC-52
SYMPTOM_NOT_FOUNDを保持する。

### AC-53
malformed successをCONTRACT errorにする。

### AC-54
create formをneutral wordingで表示する。

### AC-55
edit formをprefillできる。

### AC-56
success feedbackをneutral wordingにする。

### AC-57
scaleを医学的重症度へ自動分類しない。

### AC-58
diagnosisを表示しない。

### AC-59
dose変更提案を表示しない。

### AC-60
injection interval変更提案を表示しない。

### AC-61
一般的な医療相談安全文言のみ許可する。

### AC-62
Dashboard UIを実装しない。

### AC-63
Injection UIを実装しない。

### AC-64
graph/history拡張を実装しない。

### AC-65
backendを変更しない。

### AC-66
DB/migrationを変更しない。

### AC-67
新規dependencyを原則追加しない。

### AC-68
unit/widget testsが実backendを必須としない。

### AC-69
`dart format .`成功。

### AC-70
`flutter analyze`成功。

### AC-71
`flutter test`成功。

### AC-72
`git diff --check`成功。

---

## 49. Scope Guardrail

以下を「ついでに」実装しない。

```text
symptom charts
long-range symptom history
severity score
medical diagnosis
triage
dose recommendation
injection schedule recommendation
drug interaction analysis
AI analysis
Dashboard UI
Injection UI
offline
cache
retry
authentication
notifications
generic CRUD framework
```

---

## 50. 完了報告

Codex は完了時に以下を報告する。

1. 変更ファイル
2. dependencies変更
3. Symptom model
4. scale validation
5. bowel_condition handling
6. timestamp parsing/serialization
7. IANA timezone handling
8. repository
9. Riverpod controller/provider
10. selected day loading
11. create/update/delete
12. reconciliation strategy
13. stale response対策
14. duplicate mutation対策
15. old-date form guard
16. UI / navigation
17. delete confirmation
18. error mapping
19. safety wording
20. tests概要・件数
21. `dart format`
22. `flutter analyze`
23. `flutter test`
24. manual integration結果
25. `git diff --check`
26. backend差分
27. pubspec差分
28. Scope外変更
29. blocker / 未解決事項

---

## 51. Commit / Push

実装とverificationが成功しても、ユーザーの明示指示まではcommit / pushしない。

commit前レビューを受けること。
