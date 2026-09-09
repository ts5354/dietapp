# Spec 012 --- Flutter Dashboard UI

## 1. 目的

Spec 006で実装済みのDashboard APIと、Spec 007以降のFlutter
API基盤を利用し、Home画面から指定日の健康記録snapshotを確認できるようにする。

Dashboardでは以下を一画面にまとめる。

-   体重
-   食事 / Nutrition day
-   体調
-   注射
-   記録上の次回注射予定日
-   各記録画面への導線

Dashboardは既存データの確認と各記録画面への入口であり、新しい医療判断、栄養判断、体重評価、dose判断を行わない。

------------------------------------------------------------------------

## 2. 実装前に読むもの

Codexは実装開始前に以下を確認すること。

-   `AGENTS.md`
-   `README.md`
-   `docs/api-design.md`
-   `docs/database-design.md`
-   `specs/006-dashboard-api.md`
-   `specs/007-flutter-api-foundation.md`
-   `specs/008-flutter-weight-ui.md`
-   `specs/009-flutter-food-ui-nutrition-free-day.md`
-   `specs/010-flutter-symptom-ui.md`
-   `specs/011-flutter-injection-ui.md`
-   `mobile/pubspec.yaml`
-   `mobile/lib/`
-   `mobile/test/`
-   backendのDashboard router/schema/service/test

Spec 006と実backendをauthoritativeとする。Spec 007の既存Dashboard
model/repository/providerを優先して再利用する。不一致があれば推測で解決せず停止して報告する。

------------------------------------------------------------------------

## 3. Scope

### IN

-   既存Dashboard domain/repository/providerの確認と必要最小限の補強
-   Home / Dashboard UI
-   selected dateと日付変更
-   Dashboard snapshot取得
-   Weight / Nutrition / Symptom / Injection section
-   next injection date表示
-   RECORDED / UNRECORDED
-   NORMAL / FREE_DAY / UNRECORDED
-   loading / ready / error / retry / refresh
-   stale response protection
-   4記録画面へのnavigation
-   Home再表示後のrefresh方針
-   neutral Japanese wording
-   unit/widget tests

### OUT

-   backend / DB / Alembic変更
-   新規dependency
-   History UI / graph
-   calorie/protein target、remaining、deficit/surplus
-   diet/meal/weight recommendation
-   BMI
-   symptom severity/diagnosis/triage
-   dose recommendationや増減判断
-   injection interval recommendation
-   notification/reminder
-   auth/offline/cache/background sync
-   Dashboard内CRUD form

------------------------------------------------------------------------

## 4. Dashboard API

実装前にSpec 006とbackendを確認し、実際のpath/query/responseを使う。

概念上:

``` text
GET /api/v1/dashboard?date=YYYY-MM-DD
```

Dashboard API responseをauthoritative
snapshotとする。Flutter側でWeight/Nutrition/Symptom/Injection
APIを個別に呼び、独自Dashboardを構築しない。

------------------------------------------------------------------------

## 5. Existing Flutter foundation

Spec 007の既存Dashboard model/repository/provider、shared
Dio、ApiException、API configuration、date
formatterを確認して再利用する。同じ責務の別実装やfeature内`Dio()`を作らない。不足がある場合だけ最小限変更する。

------------------------------------------------------------------------

## 6. Snapshot date / state

初期selected dateはtoday
local。DATEはtimezone変換しない。日付変更時はDashboard APIを再取得する。

最低状態:

``` text
loading
ready
error
```

API failureをUNRECORDED扱いしない。network/timeout/server/contract
errorはerror state。

------------------------------------------------------------------------

## 7. Stale response protection

Spec 008〜011と同様にgeneration/token + selected date等で保護する。

対象:

-   initial GET
-   date change GET
-   retry
-   refresh
-   record screenから戻った後のrefresh

古い日付のresponseが現在の日付stateを上書きしてはならない。

------------------------------------------------------------------------

## 8. Weight section

RECORDED:

``` text
体重
62.3 kg
[ 記録を見る ]
```

UNRECORDED:

``` text
体重
この日の記録はありません。
[ 記録する ]
```

増減評価、良い/悪い、目標との差、BMI、減量ペース、body
judgmentを表示しない。

------------------------------------------------------------------------

## 9. Nutrition section

`NORMAL / FREE_DAY / UNRECORDED`を厳密に区別する。

NORMALではbackendのrecorded totalsを表示する。empty NORMALはbackend
contractどおり0 totalsを表示してよい。

FREE_DAY:

``` text
食事
Free Day
この日は栄養計算を行わない日として記録されています。
```

FREE_DAYを0 kcal / 0 g proteinとして表示しない。

UNRECORDEDは「この日の記録はありません。」とする。

calorie/protein
target、remaining、deficit/surplus、「食べすぎ」「食べなさすぎ」、制限・補償提案は禁止。

------------------------------------------------------------------------

## 10. Symptom section

Dashboard APIが採用したsymptom snapshotだけを表示する。Flutter側でlatest
recordを独自推測しない。

RECORDEDではresponseに存在する時刻・4尺度等だけを表示する。UNRECORDEDは未記録表示。

scoreから軽症/重症、危険度、診断、原因、dose判断を生成しない。

必要な一般案内は「強い症状や気になる変化がある場合は、医療機関へ相談してください。」程度に留める。

------------------------------------------------------------------------

## 11. Injection section

Dashboard responseに含まれるrecorded
fieldsだけを表示する。他APIで補完しない。

UNRECORDEDは未記録表示。

doseはrecorded
valueとしてのみ表示し、推奨・自動選択・増減・間隔変更・他domainからのdose判断を行わない。

------------------------------------------------------------------------

## 12. Next injection date

Spec 006 Dashboard responseが返すderived next injection
dateをauthoritativeとする。

Flutter Dashboardでselected
injectionや任意のrecordから`+7 days`を独自計算しない。

存在する場合:

``` text
記録上の次回予定日
2026/09/15
実際の投与日は医療者の指示に従ってください。
```

存在しなければfabricateしない。

------------------------------------------------------------------------

## 13. Strict response parsing

既存Spec 007 modelを確認し、不足するcontractだけ補強する。

最低限:

-   required field missing → CONTRACT
-   wrong type → CONTRACT
-   unknown status → CONTRACT
-   invalid date/timestamp → CONTRACT
-   invalid numeric → CONTRACT
-   impossible nullable/non-null combination → CONTRACT

additive unknown fieldsは許可。string→number等のsilent coercionは禁止。

------------------------------------------------------------------------

## 14. Navigation

Dashboardから既存routeへ遷移できること。

``` text
/record/weight
/record/food
/record/symptom
/record/injection
```

既存routeを壊さない。selected dateを渡すための大規模route redesignやSpec
008〜011の大規模変更は行わない。

現在の簡易HomeをDashboardへ置換してよいが、4機能すべてへの明確な導線を維持する。

------------------------------------------------------------------------

## 15. Refresh after record screen

記録画面からHomeへ戻った後、古いsnapshotを永久に表示しない。

既存GoRouter構成で安全かつ小さく実現できればHome再表示時にrefreshする。複雑なglobal
event busやdependencyは追加しない。

難しい場合は明示的な「再読み込み」またはPull-to-refreshを提供し、制約を完了報告する。

------------------------------------------------------------------------

## 16. Error handling

既存ApiException normalizationを使用する。

-   network: `サーバーに接続できませんでした。`
-   timeout: `通信がタイムアウトしました。`
-   contract/server/unknown:
    `ホーム情報の取得中にエラーが発生しました。`

DioException、stack trace、raw backend bodyをUIへ表示しない。error
stateにはretryを提供する。

------------------------------------------------------------------------

## 17. Provider / Controller

既存Dashboard providerを優先する。必要ならselected dateとUI
stateを扱うcontrollerへ最小限拡張する。

概念state:

``` text
date
mode
dashboard
message
```

責務:

-   initial load
-   date change
-   retry
-   refresh
-   stale response protection
-   error mapping

WidgetにHTTP path/DioException判定を置かない。

------------------------------------------------------------------------

## 18. UI wording / safety

中立的な日本語を使う。

推奨:

``` text
ホーム
日付
体重
食事
体調
注射
この日の記録はありません。
記録する
記録を見る
Free Day
記録上の次回予定日
再読み込み
```

避ける:

``` text
順調
不調
食べすぎ
食べなさすぎ
太った
痩せた
危険
適正dose
```

cross-domain inferenceは禁止:

``` text
weight → dose
nutrition → dose
symptom → dose
weight → calorie restriction
nutrition → body judgment
symptom → diagnosis
```

------------------------------------------------------------------------

## 19. Required tests

実backend/PostgreSQLなしで完結すること。既存Spec 007
testsを再利用し、不足分だけ追加する。

### Domain / contract

1.  valid response
2.  additive unknown field
3.  missing required top-level field → CONTRACT
4.  invalid snapshot date → CONTRACT
5.  unknown section status → CONTRACT
6.  Weight RECORDED / UNRECORDED
7.  Nutrition NORMAL / FREE_DAY / UNRECORDED
8.  FREE_DAY totals null contract
9.  NORMAL numeric totals
10. Symptom RECORDED / UNRECORDED
11. Injection RECORDED / UNRECORDED
12. next injection date present / null
13. malformed numeric → CONTRACT
14. malformed timestamp → CONTRACT

### Repository / Controller

15. selected dateがDashboard requestへ送られる
16. shared Dio/repository利用
17. network/timeout normalization
18. malformed success → CONTRACT
19. initial load → ready
20. API error → errorでありUNRECORDEDではない
21. retry成功
22. date change再取得
23. stale old-date GET無視
24. stale retry/refresh無視
25. refreshで新snapshotへ更新

race testはCompleter等で実際にresponse順序を逆転させる。

### Widget

26. HomeでDashboard表示
27. loading/error/retry
28. selected dateとdate change
29. Weight RECORDED / UNRECORDED
30. Nutrition NORMAL / FREE_DAY / UNRECORDED
31. FREE_DAYを0 kcal表示しない
32. Symptom RECORDED / UNRECORDED
33. Injection RECORDED / UNRECORDED
34. next date表示 / null時fabricateなし
35. clinician-direction wording
36. 4既存routeへの導線
37. calorie target/remaining wordingなし
38. weight judgmentなし
39. symptom severity wordingなし
40. dose recommendation wordingなし

------------------------------------------------------------------------

## 20. Existing feature protection

以下を壊さない。

-   Weight UI
-   Nutrition/Food UI
-   Free Day semantics
-   Symptom UI
-   Injection UI
-   shared Dio / ApiException
-   timezone-aware timestamp formatter
-   GoRouter
-   existing tests

既存featureの大規模refactorは禁止。

------------------------------------------------------------------------

## 21. Dependency / Backend policy

新規dependencyを追加しない。`pubspec.yaml` /
`pubspec.lock`は原則変更しない。

以下は変更禁止:

``` text
backend/
database schema
Alembic migration
```

既存APIで実現できなければ独断変更せずblockerとして報告する。

------------------------------------------------------------------------

## 22. Acceptance Criteria

-   AC-01 HomeがDashboard UIになる
-   AC-02 initial dateはtoday local
-   AC-03 date表示・変更可能
-   AC-04 date changeでDashboard再取得
-   AC-05 Dashboard APIをauthoritativeにする
-   AC-06 individual APIから独自Dashboardを構築しない
-   AC-07 loading/ready/error/retry
-   AC-08 API errorをUNRECORDED扱いしない
-   AC-09 stale GET/refreshを無視
-   AC-10 Weight RECORDED/UNRECORDED
-   AC-11 weight judgment/BMIなし
-   AC-12 Nutrition NORMAL/FREE_DAY/UNRECORDED
-   AC-13 FREE_DAYを0 totals表示しない
-   AC-14 target/remaining/deficit/surplusなし
-   AC-15 diet recommendationなし
-   AC-16 Symptom RECORDED/UNRECORDED
-   AC-17 severity/diagnosisなし
-   AC-18 Injection RECORDED/UNRECORDED
-   AC-19 dose recommendation/増減判断なし
-   AC-20 next injection dateはDashboard API由来
-   AC-21 Dashboardでnext dateを独自計算しない
-   AC-22 next date不存在時fabricateしない
-   AC-23 clinician-direction wordingあり
-   AC-24 Weight/Food/Symptom/Injection routeへ遷移可能
-   AC-25 Home再表示後のstale snapshot対策または明示refreshあり
-   AC-26 strict response parsing
-   AC-27 unknown status/malformed numeric/timestamp → CONTRACT
-   AC-28 shared Dio使用
-   AC-29 DioExceptionをUI表示しない
-   AC-30 backend/DB/migration変更なし
-   AC-31 新規dependencyなし
-   AC-32 History/graph/notification/offline/cache追加なし
-   AC-33 unit/widget test成功
-   AC-34 `dart format .`成功
-   AC-35 `flutter analyze`成功
-   AC-36 `flutter test`成功
-   AC-37 `git diff --check`成功
-   AC-38 commit/push未実施

------------------------------------------------------------------------

## 23. Verification

``` bash
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

-   format成功
-   analyze issueなし
-   全Flutter test成功
-   diff check成功
-   backend差分なし
-   pubspec dependency差分なし

------------------------------------------------------------------------

## 24. 完了報告

Codexは以下を報告すること。

1.  変更ファイル
2.  実Dashboard API path/query
3.  実response shape
4.  Spec 007基盤の再利用内容
5.  domain/parser変更
6.  repository変更
7.  provider/controller
8.  selected date
9.  loading/ready/error/retry/refresh
10. stale response protection
11. Weight section
12. Nutrition NORMAL/FREE_DAY/UNRECORDED
13. Symptom section
14. Injection section
15. next injection dateのsource
16. Dashboard内でnext dateを独自計算していないこと
17. 4記録画面へのnavigation
18. Home再表示後のrefresh方針
19. health/medical safety wording
20. cross-domain inferenceがないこと
21. unit/widget tests
22. `dart format` / `flutter analyze` / `flutter test`
23. manual integration結果または未実施理由
24. `git diff --check`
25. backend差分
26. pubspec差分
27. scope外変更
28. blocker / 未解決事項

------------------------------------------------------------------------

## 25. Commit policy

実装完了後もcommit / pushしない。

ChatGPTによるcommit前レビューと明示的な承認を待つこと。
