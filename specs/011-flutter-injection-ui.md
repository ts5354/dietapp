# Spec 011 — Flutter Injection UI

## 1. 目的

Spec 005で実装済みのInjection APIと、Spec 007以降で構築したFlutter API基盤を利用し、
Flutterから注射記録を作成・参照・編集・削除できるようにする。

ユーザーは以下を記録できる。

- 注射日
- 注射時刻
- 医療者の指示に基づくdose
- 注射部位
- メモ

また、最新の注射記録から算出される次回予定日を確認できるようにする。

本機能は「注射の記録」を目的とする。
アプリがdoseや注射間隔を決定・推奨してはならない。

---

## 2. 実装前に読むもの

Codexは実装開始前に以下を確認すること。

- `AGENTS.md`
- `README.md`
- `docs/api-design.md`
- `docs/database-design.md`
- `specs/005-injection-api.md`
- `specs/006-dashboard-api.md`
- `specs/007-flutter-api-foundation.md`
- `specs/008-flutter-weight-ui.md`
- `specs/009-flutter-food-ui-nutrition-free-day.md`
- `specs/010-flutter-symptom-ui.md`
- `mobile/pubspec.yaml`
- `mobile/lib/`
- `mobile/test/`
- backendのInjection router/schema/service/test

Injection APIについてはSpec 005および実際のbackend実装をauthoritativeとする。

Specとbackendに不一致がある場合は推測で修正せず、実装を停止して報告すること。

---

## 3. Scope

### IN

- Injection domain model
- Injection create/update request model
- Injection repository
- Riverpod provider/controller
- Injection記録画面
- 日付による記録取得
- create
- update
- delete
- clinician-directed dose入力
- injection site選択
- memo
- timezone-aware injected_at
- 次回予定日の表示
- loading/create/edit/error/busy state
- local validation
- stable API error handling
- stale response protection
- duplicate mutation prevention
- delete confirmation
- Record menuからのnavigation
- unit test
- widget test

### OUT

- dose recommendation
- dose自動選択
- dose escalation/de-escalation
- 注射間隔変更の提案
- 「次は何mgにするべきか」の判断
- 症状からdoseを変更するロジック
- 食事・体重・症状とdoseの因果推定
- medical severity判定
- 注射リマインダー
- notification
- Injection history一覧
- Injection graph
- Dashboard UI変更
- authentication
- offline support
- cache/retry framework
- backend変更
- DB変更
- Alembic migration
- 新規dependency

---

## 4. Backend contract

実装前にSpec 005およびbackendコードを確認し、
実際のpath / request / responseを確認すること。

概念上使用するendpoint:

```text
POST   /api/v1/injections
GET    /api/v1/injections/{date}
PUT    /api/v1/injections/{date}
DELETE /api/v1/injections/{date}
```

一覧APIが存在していても、Spec 011ではInjection history UIを実装しないため、
必要がなければ使用しない。

PUTはupdate-onlyでありupsertにしない。

---

## 5. InjectionRecord

Flutter domain modelとしてInjectionRecordを定義する。

概念フィールド:

```text
id
recordDate
injectedAt
doseMg
injectionSite
memo
createdAt
updatedAt
```

API JSON:

```text
id
record_date
injected_at
dose_mg
injection_site
memo
created_at
updated_at
```

実際のresponse shapeはbackendを確認して合わせること。

---

## 6. Numeric contract — dose_mg

doseは「医療者から指示されたdoseを記録する値」である。

アプリはdoseを推奨・補完・変更しない。

Flutter requestではJSON numberとして送信する。

以下を禁止する。

- numeric string
- bool
- NaN
- Infinity
- 負数
- 0
- silent rounding

DB:

```text
NUMERIC(5,2)
CHECK dose_mg > 0
```

backendのvalidation contractを確認し、
Flutter側でも明らかにDB precisionを超える値を送信しない。

最大2桁の小数を許可する。

入力された値を別のdoseへ自動変換してはならない。

---

## 7. Injection site

以下のbackend valueのみ扱う。

```text
ABDOMEN_UPPER_RIGHT
ABDOMEN_LOWER_RIGHT
ABDOMEN_UPPER_LEFT
ABDOMEN_LOWER_LEFT
THIGH_RIGHT
THIGH_LEFT
```

Flutterでは明示的なenumを使用する。

表示例:

```text
腹部 右上
腹部 右下
腹部 左上
腹部 左下
右太もも
左太もも
```

unknown backend valueはCONTRACT error。

unknown valueをOTHER等へfallbackしてはならない。

---

## 8. Timestamp

`injected_at`はtimezone-aware timestampである。

request serializationにはSpec 008/009/010で使用している
shared timezone-aware formatterを再利用する。

禁止:

- `DateTime.toIso8601String()`だけを使ってoffsetを失う
- `+09:00`固定
- `Asia/Tokyo`前提
- timezone-less timestamp

responseではtimezone-aware RFC3339を要求する。

許可例:

```text
2026-09-08T03:30:00Z
2026-09-08T12:30:00+09:00
2026-09-07T23:30:00-04:00
```

naive timestampはCONTRACT error。

---

## 9. record_date / injected_at整合性

Injection APIでは、`record_date`と`injected_at`が同じcalendar dateを表す必要がある。

backendがauthoritative。

Flutterでも送信前に整合性を保証する。

Injection formではselected dateと選択時刻から`injected_at`を構築する。

edit時に別の日付へPUTしてrecord_dateを変更する設計にはしない。

別の日付を選択した場合は、その日のInjection recordをGETする。

---

## 10. 一日一件

Injection recordは最大一日一件。

POSTで既存日付へ作成しようとした場合、

```text
409 INJECTION_ALREADY_EXISTS
```

を正常なdomain conflictとして扱う。

既存recordをsilent overwriteしてはならない。

GETで、

```text
404 INJECTION_NOT_FOUND
```

の場合のみcreate modeへ移行する。

network error等を「未記録」と解釈してはならない。

---

## 11. 画面

Route:

```text
/record/injection
```

Record menu:

```text
記録する

[ 体重 ]
[ 食事 ]
[ 体調 ]
[ 注射 ]
```

既存Weight / Food / Symptom routeを壊さない。

---

## 12. Injection Screen

画面上部:

```text
注射記録

日付
2026/09/08
```

selected dateのInjection recordを読み込む。

状態:

```text
loading
create
edit
error
busy
```

---

## 13. Create mode

未記録日の表示例:

```text
この日の注射記録はまだありません。

注射時刻
12:30

dose
[      ] mg

注射部位
[ 選択 ]

メモ
[                    ]

[ 保存 ]
```

dose labelには、

```text
医療者から指示されたdoseを入力してください
```

等の中立的な補足を表示してよい。

アプリが適切なdoseを提示してはならない。

---

## 14. Create defaults

selected date:

```text
today local
```

injectedAt:

```text
selected date + current local time
```

dose:

```text
empty
```

injection site:

```text
unselected
```

memo:

```text
empty
```

doseやsiteを過去記録から自動入力しない。

---

## 15. Edit mode

GETでrecordが存在した場合edit mode。

既存値をprefillする。

表示:

```text
注射時刻
dose
注射部位
メモ

[ 更新 ]
[ 記録を削除 ]
```

record_dateそのものはPUT bodyに含めない。

---

## 16. Delete

削除前にconfirmation dialogを表示する。

例:

```text
この注射記録を削除しますか？

[ キャンセル ]
[ 削除 ]
```

成功は204。

成功後:

- create modeへ移行
- formをcreate defaultへreset

失敗:

- recordを消さない
- create modeへ移行しない

---

## 17. Next injection date

次回予定日はbackend/databaseへ保存しない。

Spec 006と既存設計に従い、
最新の注射記録から派生値として扱う。

基本ルール:

```text
record_date + 7 calendar days
```

ただし、これは「記録上の次回予定日」であり、
医療上のdose・投与間隔の推奨ではない。

表示例:

```text
記録上の次回予定日
2026/09/15
```

必ず補足する:

```text
実際の投与日は医療者の指示に従ってください。
```

---

## 18. Next injection dateのsource

Spec 011ではselected dateのrecordから無条件に
「次回予定日」を表示してはならない。

次回予定日は「最新のInjection record」を基準にする。

実装前にSpec 005 / Spec 006 / backend APIを確認し、
最新recordを取得できる既存endpointがあるか確認する。

既存endpointだけで安全に取得可能なら再利用する。

新しいbackend endpointをSpec 011で追加してはならない。

もし既存APIでは最新recordを取得できない場合:

- selected recordをlatestと仮定しない
- backendを変更しない
- 新規endpointを追加しない
- blockerとして報告する

---

## 19. Date change

date pickerで日付を変更した場合:

```text
GET /api/v1/injections/{newDate}
```

foundならedit。

exact:

```text
404 INJECTION_NOT_FOUND
```

のみcreate。

network / timeout / contract errorはerror。

---

## 20. Form validation

dose:

- required
- numeric
- finite
- > 0
- 最大2 decimal places
- NUMERIC(5,2)を明らかに超えない

site:

- required

memo:

```text
<= 500 chars
```

時刻はselected dateと結合してtimezone-aware timestampとして送信。

invalid formではAPI requestを送らない。

---

## 21. Repository

概念interface:

```text
InjectionRepository.getByDate(date)
InjectionRepository.create(request)
InjectionRepository.update(date, request)
InjectionRepository.delete(date)
```

latest record取得が既存API contractで可能な場合のみ、
必要最小限のread methodを追加してよい。

shared Dioを使用する。

feature内部で`Dio()`を新規生成しない。

ApiException normalizationはSpec 007基盤を再利用する。

`ApiException`をcatchした後にgeneric exceptionへ潰さない。

---

## 22. Controller

Riverpod controller/providerが管理するもの:

```text
selected date
record
mode
busy
message
latest record / next scheduled date
```

必要な責務:

- load
- create
- update
- delete
- latest injection read
- next date derivation
- stale protection
- duplicate mutation prevention
- error mapping

WidgetへDio/HTTP path判定を置かない。

---

## 23. Backend authoritative

mutation成功後はbackend stateをauthoritativeとして扱う。

create/update:

```text
mutation
→ selected date GET
→ latest record取得
→ state reconcile
```

delete:

```text
DELETE
→ selected date GET
→ latest record取得
→ state reconcile
```

selected date GETが404ならcreate state。

ローカルだけでrecordをpatchして最終状態としない。

---

## 24. Stale response protection

Spec 008〜010と同様にgeneration/token + operation dateで保護する。

対象:

- old GET
- old latest-record GET
- old POST
- old PUT
- old DELETE
- old reconciliation

例:

```text
9/8 load
↓
9/9へ変更
↓
遅れて9/8 response
```

9/8 responseで9/9 stateを上書きしてはならない。

---

## 25. Duplicate mutation prevention

mutation中:

- 保存無効
- 更新無効
- 削除無効
- 日付変更無効

同じ操作を二重送信しない。

---

## 26. Error handling

最低限stable codeを保持:

```text
VALIDATION_ERROR
INJECTION_ALREADY_EXISTS
INJECTION_NOT_FOUND
INJECTION_DATE_MISMATCH
```

例:

`INJECTION_ALREADY_EXISTS`

```text
この日にはすでに注射記録があります。再読み込みしてください。
```

`INJECTION_NOT_FOUND`

```text
この注射記録は見つかりませんでした。再読み込みしてください。
```

`INJECTION_DATE_MISMATCH`

```text
注射日時と記録日が一致していません。
```

network:

```text
サーバーに接続できませんでした。
```

timeout:

```text
通信がタイムアウトしました。
```

DioException等をUIへ直接表示しない。

---

## 27. Medical safety

Injection UIは記録UIである。

以下を表示・生成しない。

- 「あなたには○mgがおすすめ」
- 「次は増量してください」
- 「体重が減っていないので増量」
- 「副作用があるので減量」
- 「症状が軽いので増量可能」
- 「○日早めても大丈夫」
- 「○日遅らせても大丈夫」

doseは必ずuser-entered clinician-directed data。

症状・体重・食事データをdose判断へ利用しない。

一般的な表示:

```text
doseや実際の投与日は、医療者の指示に従ってください。
```

は許可する。

---

## 28. UI wording

中立的な日本語を使用する。

例:

```text
注射記録
注射時刻
dose
注射部位
メモ
記録上の次回予定日
```

doseについて「少ない」「多い」「適正」等の評価をしない。

---

## 29. Response parsing

success responseについてstrict parsingする。

最低限:

- required field missing → CONTRACT
- wrong type → CONTRACT
- invalid dose → CONTRACT
- unknown injection_site → CONTRACT
- timezone-less injected_at → CONTRACT
- invalid created_at / updated_at → CONTRACT

additive unknown fieldsは許可する。

nullable memoはkeyが存在することを要求し、valueはnullを許可する。

numeric JSON contractは実際のbackend responseを確認する。

DecimalがJSON numberとして返る既存contractを尊重し、
stringへのsilent coercionはしない。

---

## 30. Testing

実backend/PostgreSQLなしでFlutter testが完結すること。

fake repository / Dio adapter / Riverpod overrideを使用してよい。

最低限以下を検証する。

### Domain

1. valid response
2. additive field
3. missing required field
4. dose numeric response
5. dose string rejection
6. dose bool rejection
7. dose <= 0 rejection
8. unknown site rejection
9. all six sites
10. memo null
11. Z timestamp
12. positive offset
13. negative offset
14. naive timestamp rejection
15. invalid timestamp rejection

### Request / Validation

16. exact snake_case
17. dose JSON number
18. record_date create body
19. PUT body excludes record_date
20. timezone-aware injected_at
21. empty dose rejected
22. nonnumeric dose rejected
23. zero/negative rejected
24. >2 decimals rejected
25. overflow rejected
26. site required
27. memo >500 rejected
28. invalid form sends no API request

### Repository

29. GET date path
30. POST path/body
31. PUT date path/body
32. DELETE date path
33. DELETE 204 ignores body
34. shared Dio usage
35. network normalization
36. timeout normalization
37. INJECTION_ALREADY_EXISTS preserved
38. INJECTION_NOT_FOUND preserved
39. INJECTION_DATE_MISMATCH preserved
40. malformed success → CONTRACT

### Controller

41. initial load
42. exact 404 → create
43. network error != create
44. found → edit
45. create → reconcile
46. update → reconcile
47. delete → reconcile/create
48. failed delete keeps record/error
49. duplicate mutation prevention
50. stale GET ignored
51. stale create ignored
52. stale update ignored
53. stale delete ignored
54. stale reconciliation ignored
55. old-date form blocked
56. latest-record state
57. next date calculated from latest record
58. selected old record not treated as latest
59. latest read failure does not fabricate next date

### Widget

60. `/record/injection` reachable
61. Weight route preserved
62. Food route preserved
63. Symptom route preserved
64. create state
65. edit prefill
66. dose empty by default
67. site unselected by default
68. all six site labels
69. create validation
70. create success
71. edit success
72. delete confirmation cancel
73. delete confirmation accept
74. busy disables mutation
75. next date shown only when authoritative latest exists
76. clinician-direction wording present
77. no dose recommendation wording
78. no symptom→dose wording
79. no Injection history UI

---

## 31. Manual integration

可能なら任意で確認:

```text
GET unrecorded date
POST injection
GET same date
PUT same date
GET same date
GET latest injection using existing API
DELETE same date
GET same date
```

実施しなかった場合は完了報告に明記する。

---

## 32. Dependency policy

新規dependencyは追加しない。

Spec 010で追加した`flutter_timezone`をInjection UIのために
追加利用する必要は原則ない。

record_dateはDATEであり、
injected_at requestには既存timezone-aware serializerを使用する。

新規dependencyが必要だと判断した場合は実装を停止し、
理由をblockerとして報告する。

---

## 33. Backend modification policy

変更禁止:

```text
backend/
Alembic migration
database schema
```

既存APIでSpec 011要件を実現できない場合、
backendを独断で変更せずblockerとして報告する。

---

## 34. Acceptance Criteria

- AC-01 `/record/injection`へ遷移できる
- AC-02 Weight/Food/Symptom導線を維持
- AC-03 selected dateを表示できる
- AC-04 selected date変更で該当日のGETを行う
- AC-05 exact INJECTION_NOT_FOUNDのみcreate扱い
- AC-06 network errorを未記録扱いしない
- AC-07 existing recordでedit mode
- AC-08 create default doseはempty
- AC-09 create default siteはunselected
- AC-10 doseはuser-entered
- AC-11 dose >0
- AC-12 dose最大2 decimal places
- AC-13 doseをsilent roundingしない
- AC-14 dose JSON number
- AC-15 injection siteは6値のみ
- AC-16 unknown siteはCONTRACT
- AC-17 memo <=500
- AC-18 injected_at timezone-aware
- AC-19 +09固定なし
- AC-20 create bodyにrecord_date
- AC-21 PUT bodyからrecord_date除外
- AC-22 record_date/injected_at整合
- AC-23 POST duplicateをoverwriteしない
- AC-24 create成功後reconcile
- AC-25 update成功後reconcile
- AC-26 delete成功後reconcile
- AC-27 delete失敗でrecordを消さない
- AC-28 delete confirmationあり
- AC-29 duplicate mutation防止
- AC-30 mutation中の日付変更防止
- AC-31 old GETを無視
- AC-32 old POSTを無視
- AC-33 old PUTを無視
- AC-34 old DELETEを無視
- AC-35 old reconciliationを無視
- AC-36 old-date form送信防止
- AC-37 latest injectionを既存APIから取得
- AC-38 latestが取得できない場合にselected recordで代用しない
- AC-39 next dateはlatest record_date + 7 calendar days
- AC-40 next dateをDBへ保存しない
- AC-41 next dateをdose recommendationとして扱わない
- AC-42 clinician-direction wordingを表示
- AC-43 dose recommendationなし
- AC-44 dose escalation/de-escalationなし
- AC-45 symptom→dose判断なし
- AC-46 weight→dose判断なし
- AC-47 food→dose判断なし
- AC-48 stable API code保持
- AC-49 malformed responseはCONTRACT
- AC-50 DioExceptionをUI表示しない
- AC-51 shared Dio使用
- AC-52 backend変更なし
- AC-53 DB変更なし
- AC-54 migration追加なし
- AC-55 新規dependencyなし
- AC-56 Injection history UIなし
- AC-57 notificationなし
- AC-58 offline/cache追加なし
- AC-59 unit/widget test成功
- AC-60 flutter analyze成功
- AC-61 dart format成功
- AC-62 git diff --check成功
- AC-63 commit/push未実施

---

## 35. Verification

実装後:

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

期待:

- format成功
- analyze issueなし
- 全Flutter test成功
- diff check成功
- backend差分なし
- pubspec dependency差分なし

---

## 36. 完了報告

Codexは以下を報告すること。

1. 変更ファイル
2. domain model
3. dose parsing
4. dose validation
5. injection site enum
6. timestamp handling
7. record_date/injected_at整合性
8. repository
9. provider/controller
10. create mode
11. edit mode
12. delete
13. reconciliation
14. stale response protection
15. duplicate mutation prevention
16. date change guard
17. latest injection取得方法
18. next injection date算出方法
19. selected recordをlatest代用していないこと
20. stable error handling
21. medical safety wording
22. unit tests
23. widget tests
24. `dart format`結果
25. `flutter analyze`結果
26. `flutter test`結果
27. manual integration結果または未実施理由
28. `git diff --check`
29. backend差分
30. pubspec差分
31. scope外変更
32. blocker / 未解決事項

---

## 37. Commit policy

実装完了後もcommit / pushしない。

ChatGPTによるcommit前レビューと明示的な承認を待つこと。
