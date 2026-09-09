# Spec 013 --- Flutter History UI + Weight Graph

## 1. 目的

MVPのHistory機能をFlutterへ実装する。Bottom
Navigationの「履歴」から、体重・食事/Nutrition
day・体調・注射の既存記録を確認できるようにする。体重履歴には既存記録値だけを使った時系列グラフを追加し、期間を「7日
/ 30日 / 3か月」で切り替えられるようにする。

Historyは記録済みデータの閲覧を目的とし、体重・食事・症状・注射doseについて評価、推奨、診断、医療判断を生成しない。

## 2. 実装前に必ず読むもの

-   `AGENTS.md`
-   `README.md`
-   `docs/api-design.md`
-   `docs/database-design.md`
-   `specs/002-common-api-and-weight.md`
-   `specs/003-nutrition-and-food-api.md`
-   `specs/004-symptom-api.md`
-   `specs/005-injection-api.md`
-   `specs/006-dashboard-api.md`
-   `specs/007-flutter-api-foundation.md`
-   `specs/008-flutter-weight-ui.md`
-   `specs/009-flutter-food-ui-nutrition-free-day.md`
-   `specs/010-flutter-symptom-ui.md`
-   `specs/011-flutter-injection-ui.md`
-   `specs/012-flutter-dashboard-ui.md`
-   `mobile/pubspec.yaml`, `mobile/pubspec.lock`, `mobile/lib/`,
    `mobile/test/`
-   backendのWeight / Nutrition / Symptom / Injection
    router/schema/service/test

実backend contractをauthoritativeとする。実装前に4domainのlist
endpoint、pagination、range filter、ordering、NutritionのNORMAL/FREE_DAY
response、Symptom timezone
contract、`fl_chart`の既存dependency有無を確認する。不一致・不足を推測で埋めない。

## 3. Blocker Check

### 3.1 History API

概念上:

``` text
GET /api/v1/weights
GET /api/v1/nutrition-days
GET /api/v1/symptoms
GET /api/v1/injections
```

実path/queryはbackendをauthoritativeとする。4domainのHistoryに必要なAPIが不足する場合、backend
endpointを追加せず、別APIの大量呼び出しで疑似listを作らず、実装を停止してblocker報告する。

### 3.2 Weight graph dependency

`fl_chart`が既に`pubspec.yaml`に存在する場合のみ使用する。存在しない場合はdependencyを独断追加せず停止し、

``` text
BLOCKER:
Weight graph実装にfl_chartが必要だが、現在のpubspec.yamlには存在しない。
新規dependency追加の承認が必要。
```

と報告する。別chart packageやCustomPainterで回避しない。

## 4. Scope

### IN

-   History画面
-   Bottom Navigation History接続
-   Weight / Food / Symptom / Injectionの4 tabs
-   Weight履歴一覧
-   `fl_chart`によるWeight graph
-   7日 / 30日 / 3か月
-   Nutrition day履歴、NORMAL / FREE_DAY
-   Symptom履歴
-   Injection履歴
-   pagination / loading / empty / error / retry / refresh
-   stale response / duplicate request protection
-   strict parsing
-   既存記録画面への安全な導線
-   unit/widget tests

### OUT

backend/DB/Alembic/API追加、新規dependencyの無断追加、auth、通知、offline/cache/background
sync、Dashboard変更、BMI、目標体重、理想体重、体重予測、増減評価、calorie/protein
target、remaining/deficit/surplus、食事制限提案、症状severity/diagnosis/triage、dose推奨/増減/間隔判断、cross-domain
inference、food/symptom/injection graph、export。

## 5. Navigation / History Screen

Bottom Navigation:

``` text
Home
Record
History
Settings
```

既存GoRouter設計を再利用し、概念上`/history`へ接続する。既存routeがあればそれを使う。

History上部:

``` text
[ 体重 | 食事 | 体調 | 注射 ]
```

各tabは独立stateを持ってよい。一つのdomainの取得失敗で他tabまで閲覧不能にしない設計を優先する。

# Part A --- Weight

## 6. Weight API / ordering

実backendのlist endpointを使用する。既知の概念:

``` text
GET /api/v1/weights?from=&to=&limit=&offset=
```

orderingは`record_date DESC`を想定するが実backendで確認する。History
listはbackend orderingを維持する。

## 7. Range

selector:

``` text
7日
30日
3か月
```

終了日は原則today local。7日はtodayを含む7 calendar
days、30日はtodayを含む30 calendar days。

3か月は固定90日へ変換せずcalendar month
semanticsで算出する。月末overflowを安全に処理する。backendのinclusive
range contractに合わせる。

## 8. Graph source / ordering

Weight list
APIから取得した実recordのみを使用する。未記録日を前日値、次回値、平均、0、interpolationで補わない。

API/listがnewest→oldestでもchart表示用にはoldest→newestへ変換してよい。元recordをmutationしない。

## 9. Graph UI

`fl_chart` line chartを使用する。

-   X = DATE
-   Y = weight_kg
-   actual recorded points only
-   range selector
-   no-data state

禁止: target/ideal/BMI zone、good/bad zone、forecast、goal、calorie/dose
correlation、moving average。

Y rangeはrecorded
valuesから描画上のpaddingを付けてよい。同値pointだけでも描画可能にする。これは健康評価ではない。X
labelは可読性のため間引いてよいがrecord
pointを間引かない。DATEをtimezoneで前後日にずらさない。

tooltipは日付と記録値程度に限定し、前日比や評価を表示しない。

## 10. Weight list / empty

例:

``` text
9/8  62.3 kg
9/7  62.5 kg
```

差分・「増えた/減った/順調/停滞」等を表示しない。

empty:

``` text
この期間の体重記録はありません。
```

0kg等のsynthetic graphを作らない。

# Part B --- Nutrition

## 11. Nutrition source / UI

既存Nutrition day list endpointを使用する。既存day
rowsだけを表示し、missing datesを大量のvirtual
UNRECORDEDとして生成しない。

NORMAL:

``` text
9/8
1840 kcal
82.5 g protein
```

FREE_DAY:

``` text
9/7
Free Day
```

FREE_DAYを0 kcal / 0 g
proteinとして表示しない。APIがUNRECORDEDを返す場合のみbackend
contractに従う。

target、remaining、over/under、deficit/surplus、restriction、compensationは禁止。Free
Dayを「チート」「食べ過ぎの日」と表現しない。

# Part C --- Symptom

## 12. Symptom API / timezone / ordering

既存list endpointを使用する。calendar date filterにIANA
timezoneが必要ならSpec
010/012の共通`DeviceTimezone`を再利用する。`DateTime.timeZoneName`、固定`Asia/Tokyo`、offsetをIANA
timezone代替にしない。

orderingは実backendを確認し、既知の`recorded_at DESC, id DESC`を維持する。同timestampをdeduplicateしない。

## 13. Symptom UI / safety

例:

``` text
9/8 14:20
吐き気 2
腹痛 1
だるさ 4
食欲 6
便通 通常
```

recorded
valuesのみ表示。軽症/中等症/重症、危険度、改善悪化の医学的判定、diagnosis、cause、dose
correlation/recommendationは禁止。

# Part D --- Injection

## 14. Injection API / ordering

既存list endpointを使用する。既知:

``` text
GET /api/v1/injections?limit=&offset=
```

orderingは実backendで確認し、既知の`injected_at DESC, id DESC`を維持する。

list
responseにdose/siteが含まれる場合のみ表示する。不足fieldを1件ずつdetail
GETするN+1補完は禁止。不足するならblocker報告する。

## 15. Injection UI / safety

例:

``` text
9/8 10:00
2.5 mg
腹部 右上
```

doseはclinician-directed recorded
valueとしてのみ表示する。次回dose、recommended
dose、増量/減量、適正判断、symptom/weight/food→dose、interval
adviceは禁止。

必要な中立文言:

``` text
doseや実際の投与日は、医療者の指示に従ってください。
```

# Part E --- Pagination / Concurrency

## 16. Strict pagination

実backend contractを確認する。offset
paginationでresponseが`items,total,limit,offset`なら最低限:

-   total \>= 0
-   limit \> 0
-   offset \>= 0
-   response offset == requested offset
-   response limit == requested limit
-   items.length \<= limit
-   offset + items.length \<= total
-   offset \< totalなのにempty page → CONTRACT
-   progressしないresponse → CONTRACT

shapeが違えば実contractに合わせる。

追加page失敗時は既存itemsを残す設計を優先。同一pageをduplicate
appendしない。

## 17. Range / refresh / stale

Weight range変更時はpaginationを初期化し、新rangeを取得し、old-range
responseを無視する。

各tabにPull-to-refreshまたは明示refreshを提供。refreshはfirst
pageからauthoritative dataを再取得し、旧page responseをappendしない。

stale protection対象:

-   initial load
-   Weight range change
-   retry
-   refresh
-   load more
-   route再表示

generation/token + query
identity等を使う。同じload-moreの並行発行を防止する。

# Part F --- Architecture / Parsing

## 18. Controller

既存architectureを確認し、必要ならdomain別controller/providerとする。

概念:

``` text
WeightHistoryController
NutritionHistoryController
SymptomHistoryController
InjectionHistoryController
```

過剰抽象化は禁止。shared
Dio/repositoriesを再利用し、feature内`Dio()`を生成しない。

## 19. Existing parsers

既存Weight/Nutrition/Symptom/Injection
parserを再利用し、History専用duplicate parserを作らない。

共通contract:

-   missing required → CONTRACT
-   wrong type → CONTRACT
-   numeric string coercion禁止
-   bool→number禁止
-   NaN/Infinity禁止
-   unknown enum → CONTRACT
-   invalid DATE/timestamp → CONTRACT
-   additive unknown fields許可

Weight: `weight_kg > 0`、valid DATE、timezone-aware timestamp。
Nutrition: NORMAL/FREE_DAY semantics、FREE_DAY totals null、unknown
mode拒否。 Symptom: scale 1--10、bowel strict、timezone-aware
timestamp。 Injection: dose numeric strict/positive/precision/bound、6
exact sites、timezone-aware timestamp。

# Part G --- Existing Screen Protection

## 20. Row navigation

既存screenがrecord/date route
argumentを安全に受け取れる場合のみrowから利用する。対応していない場合、row
tapを必須にせず一般の該当記録画面への導線でよい。

HistoryのためにSpec 008〜011を大規模refactorしない。

## 21. Neutral wording

使用可:

``` text
履歴
体重
食事
体調
注射
7日
30日
3か月
この期間の記録はありません。
記録はありません。
Free Day
再読み込み
さらに読み込む
```

禁止:

``` text
順調
停滞
リバウンド
太った
痩せた
食べすぎ
食べなさすぎ
危険
適正
成功
失敗
```

# Part H --- Required Tests

## 22. Preflight confirmation

完了報告に以下を含める:

1.  Weight list API存在
2.  Nutrition list API存在
3.  Symptom list API存在
4.  Injection list API存在
5.  pagination contract
6.  ordering contract
7.  `fl_chart`が実装前から存在したか

## 23. Weight tests

最低限:

-   valid list
-   malformed page → CONTRACT
-   default range 7日
-   7日 boundary
-   30日 boundary
-   3か月 calendar boundary
-   month-end 3か月 boundary
-   range change resets pagination
-   stale old-range ignored
-   list DESC ordering維持
-   chart oldest→newest
-   missing dates not synthesized
-   one-point chart
-   multi-point chart
-   empty range
-   refresh
-   stale refresh
-   duplicate load-more prevention
-   malformed numeric → CONTRACT

## 24. Nutrition tests

-   NORMAL
-   FREE_DAY
-   FREE_DAY not zero totals
-   unknown mode → CONTRACT
-   pagination
-   malformed pagination → CONTRACT
-   refresh
-   stale ignored
-   empty

## 25. Symptom tests

-   ordering preserved
-   scales
-   bowel
-   IANA timezone passed when required
-   timezone acquisition failure → error
-   malformed timestamp → CONTRACT
-   pagination
-   premature empty page → CONTRACT
-   refresh
-   stale ignored
-   duplicate timestamps preserved

## 26. Injection tests

-   ordering preserved
-   recorded dose
-   all six site mappings
-   unknown site → CONTRACT
-   pagination
-   malformed pagination → CONTRACT
-   refresh
-   stale ignored
-   clinician-direction wording
-   no dose recommendation

## 27. Widget/navigation tests

-   History route
-   4 tabs
-   Weight default tab
-   7/30/3か月 selector
-   graph with records
-   Weight empty
-   Weight list
-   Nutrition NORMAL/FREE_DAY
-   Symptom tab
-   Injection tab
-   loading/error/retry
-   load-more UI if applicable
-   Home/Record/Settings routes preserved
-   existing record routes preserved
-   no weight judgment
-   no calorie target/remaining
-   no symptom severity
-   no dose recommendation

Race testsはCompleter等で実際にresponse順序を逆転させる。

# Part I --- Acceptance Criteria

## 28. Acceptance Criteria

-   AC-01 History画面
-   AC-02 Bottom Navigationから到達
-   AC-03 4 tabs
-   AC-04 Weight default 7日
-   AC-05 7/30/3か月切替
-   AC-06 3か月はcalendar month semantics
-   AC-07 Weight list API使用
-   AC-08 graphは実recordのみ
-   AC-09 missing date補間なし
-   AC-10 chart oldest→newest
-   AC-11 list backend ordering維持
-   AC-12 target/ideal/BMI/forecastなし
-   AC-13 weight judgmentなし
-   AC-14 Weight empty state
-   AC-15 Nutrition list API使用
-   AC-16 NORMAL/FREE_DAY
-   AC-17 FREE_DAYを0 totals表示しない
-   AC-18 missing datesをvirtual rows化しない
-   AC-19 nutrition target/remaining/deficit/surplusなし
-   AC-20 Symptom list API使用
-   AC-21 ordering/duplicate timestamp維持
-   AC-22 IANA timezone contract遵守
-   AC-23 severity/diagnosisなし
-   AC-24 Injection list API使用
-   AC-25 dose recorded valueのみ
-   AC-26 dose recommendation/増減なし
-   AC-27 N+1 detail補完なし
-   AC-28 strict pagination
-   AC-29 duplicate appendなし
-   AC-30 stale initial/range/refresh/load-more無視
-   AC-31 retry/refresh/loading/empty/error
-   AC-32 strict existing parser再利用
-   AC-33 unknown enum/malformed numeric/timestamp → CONTRACT
-   AC-34 additive unknown fields許可
-   AC-35 shared Dio
-   AC-36 feature内Dio生成なし
-   AC-37 existing routes/featuresを壊さない
-   AC-38 Dashboard変更なし
-   AC-39 backend/DB/Alembic/API追加なし
-   AC-40 dependency無断追加なし
-   AC-41 cross-domain inferenceなし
-   AC-42 unit/widget tests成功
-   AC-43 `dart format .`成功
-   AC-44 `flutter analyze`成功
-   AC-45 `flutter test`成功
-   AC-46 `git diff --check`成功
-   AC-47 commit/push未実施

# Part J --- Verification / Report

## 29. Verification

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
format/analyze/tests/diff成功、backend/DB/Alembic差分なし、dependency差分なし、commit/pushなし。

## 30. Manual integration

可能ならHistory route、4 tabs、Weight各range、multi/one/empty
graph、Nutrition
NORMAL/FREE_DAY、Symptom/Injection複数record、pagination、refresh、error/retryを確認する。実backend/端末で未実施なら明記する。

## 31. Codex完了報告

以下を報告すること。

1.  変更ファイル
2.  4 list endpointの実path/query
3.  各pagination/range/timezone/ordering contract
4.  Injection list fields
5.  `fl_chart`の実装前dependency有無
6.  History route / Bottom Navigation / 4 tabs
7.  Weight range計算と3か月month-end処理
8.  graph source / ordering / missing-date handling
9.  Weight list
10. Nutrition NORMAL/FREE_DAY
11. Symptom history
12. Injection history
13. pagination / strict validation
14. refresh / retry
15. stale / duplicate request protection
16. parser再利用
17. navigation
18. neutral wording
19. weight/nutrition/symptom/dose safety
20. cross-domain inferenceなし
21. unit/widget tests
22. format/analyze/test
23. manual integration
24. diff check
25. backend/DB/Alembic差分
26. pubspec/lock差分
27. scope外変更
28. blocker/warning
29. commit/push未実施

## 32. Commit policy

実装完了後もcommit /
pushしない。ChatGPTによるcommit前レビューと明示的承認を待つこと。
