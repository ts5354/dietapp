# Spec 015 --- MVP Integration & Device Verification

## 1. 目的

Spec
000〜014で実装したMVP全体を、実際のFlutterアプリ・FastAPI・PostgreSQLを接続した状態で統合確認する。

このSpecの完了を、MVP Definition of Done（DoD）の最終確認とする。

MVP DoD:

> スマホから注射・体調・食事・体重を記録でき、それらがPostgreSQLへ保存され、履歴と日次集計および体重推移をFlutterから確認できる状態。

このSpecでは原則として新機能を追加しない。

統合確認で発見された、既存MVP要件の達成を妨げるintegration
bugのみ修正してよい。

------------------------------------------------------------------------

## 2. 基本方針

このSpecは「新機能実装Spec」ではなく「MVP統合・実機検証Spec」である。

確認対象:

``` text
Flutter
  ↓
Shared Dio / API configuration
  ↓
FastAPI /api/v1
  ↓
SQLAlchemy
  ↓
PostgreSQL
```

以下を実データフローで確認する。

-   Flutterから記録を作成できる
-   FastAPIが受信できる
-   PostgreSQLへ永続化される
-   再取得できる
-   Dashboardへ反映される
-   Historyへ反映される
-   体重グラフへ反映される
-   編集・削除が既存仕様どおり動く
-   Free Dayの意味が失われない
-   日付・時刻・timezoneの契約が崩れない
-   実機またはSimulatorで主要導線が操作できる

------------------------------------------------------------------------

## 3. Preflight

実装・検証開始前に以下を読むこと。

-   `AGENTS.md`
-   `README.md`
-   `docs/api-design.md`
-   `docs/database-design.md`
-   `specs/000-repository-bootstrap.md`
-   `specs/001-initial-database-migration.md`
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
-   `specs/013-flutter-history-and-weight-graph.md`
-   `specs/014-flutter-settings-ui.md`
-   `mobile/pubspec.yaml`
-   `mobile/pubspec.lock`
-   Flutter API configuration
-   Dio provider / repository implementation
-   GoRouter
-   iOS configuration
-   Docker Compose
-   backend application startup configuration
-   Alembic configuration
-   backend tests
-   Flutter tests

実際の既存コードをauthoritativeとする。

Specと実装に矛盾がある場合は勝手に仕様変更せず報告する。

------------------------------------------------------------------------

## 4. Scope

### IN

-   MVP全体の統合確認
-   Flutter ↔ FastAPI通信確認
-   FastAPI ↔ PostgreSQL永続化確認
-   API Base URL設定確認
-   development環境でのAPI URL注入
-   iOS Simulator確認
-   iPhone実機確認が可能な場合の実機確認
-   iOS local network permission確認
-   development環境のHTTP通信に必要な最小設定
-   Home / Record / History / Settings navigation確認
-   Weight E2E
-   Nutrition / Food E2E
-   Free Day E2E
-   Symptom E2E
-   Injection E2E
-   Dashboard反映確認
-   History反映確認
-   Weight graph反映確認
-   CRUD確認
-   timezone / date確認
-   loading / error / retryの基本確認
-   統合確認で発見されたMVP blockerの修正
-   regression test
-   integration testを合理的に追加できる場合の追加
-   verification documentation / completion report

### OUT

-   新しいユーザー機能
-   auth
-   multi-user
-   notification
-   injection reminder
-   medication reminder
-   cloud deployment
-   production deployment
-   Apple Health
-   Health Connect
-   offline sync
-   cache architecture追加
-   background sync
-   food database
-   barcode
-   meal photo
-   AI analysis
-   PDF report
-   clinician sharing
-   export
-   analytics
-   calorie target
-   protein target
-   weight target
-   BMI
-   ideal weight
-   weight-loss pace
-   calorie deficit / surplus
-   nutrition restriction guidance
-   medication dose recommendation
-   medication dose変更機能
-   injection interval変更機能
-   symptom diagnosis
-   symptom severity classification
-   cross-domain medical inference
-   UI redesign
-   routing architecture全面変更
-   repository architecture全面変更

------------------------------------------------------------------------

## 5. Dependency Policy

原則として新規dependencyを追加しない。

統合確認のためだけに以下を追加しない。

-   networking package
-   environment package
-   dotenv package
-   package_info package
-   local storage package
-   integration framework package

既存のFlutter / Dio / Riverpod / FastAPI / pytest等を使用する。

新規dependencyがMVP
blocker解消に不可欠と判断した場合は、追加する前にSTOPして報告する。

------------------------------------------------------------------------

## 6. API Base URL Preflight

最初に現在のAPI Base URL設定方式を確認する。

確認事項:

1.  Base URLの定義場所
2.  default値
3.  `--dart-define`等の既存注入方式
4.  test時のoverride方式
5.  localhost / 127.0.0.1へのhard-code有無
6.  repositoryごとの独自Dio生成有無
7.  shared Dioが全featureで使用されているか

検索例:

``` bash
grep -R "localhost\|127.0.0.1\|baseUrl\|BASE_URL\|API_BASE" \
  mobile/lib mobile/test mobile/README.md 2>/dev/null
```

### 6.1 原則

既存Spec 007のAPI configurationで十分なら変更しない。

不足している場合のみ、既存architectureを保ったままdevelopment時にBase
URLを注入可能にする。

概念例:

``` bash
flutter run \
  --dart-define=API_BASE_URL=http://<development-host>:8000
```

これは概念例であり、既存のdefine名がある場合はそれを使う。

新しい環境変数名を重複して作らない。

### 6.2 localhostの扱い

実機では`localhost` / `127.0.0.1`がMacを指すとは限らない。

iPhone実機からMac上のFastAPIへ接続する場合は、同一LAN上で到達可能なMacのアドレス等、実際に到達可能なdevelopment
endpointを使用する。

IPアドレスをsource codeへhard-codeしない。

個人のLAN IPをcommitしない。

------------------------------------------------------------------------

## 7. Backend Reachability

Docker ComposeでbackendとPostgreSQLを起動する。

既存repositoryの正式な起動手順を優先する。

概念:

``` bash
docker compose up -d
docker compose ps
```

確認:

-   PostgreSQL healthy / running
-   backend running
-   migration適用済み
-   `/api/v1` endpointへMacから到達可能
-   backendが実機から到達可能なinterfaceでlistenしている
-   development portが想定どおり

`127.0.0.1`
bindが実機接続を妨げている場合のみ、development用途として必要最小限のbind設定を検討する。

本番security policyを弱める変更を行わない。

------------------------------------------------------------------------

## 8. iOS / Local Network Preflight

iOS実機でMac上のdevelopment APIへ接続する場合、local network
accessとHTTP policyを確認する。

iOS 14以降ではlocal
networkへの通信で権限が関係するため、必要なpermission
description等が既存設定にあるか確認する。

FlutterのDebug機能でもlocal network permissionが使われる場合がある。

### 8.1 HTTP

development APIがHTTPの場合、iOSのApp Transport
Security（ATS）により通信できない可能性がある。

対応が必要な場合:

-   development用途に限定する
-   必要最小限の例外にする
-   Releaseへ無制限HTTP許可を持ち込まない
-   `NSAllowsArbitraryLoads = true`を安易に全buildへ追加しない
-   可能ならhost/domain scopedな例外を優先する
-   実際に不要なら変更しない

platform configurationを変更する前に、実際のエラーを確認する。

### 8.2 Local Network Permission

必要な場合は、ユーザーが理解できる中立的なpermission descriptionを使う。

例の概念:

``` text
開発中のAPIへ接続するため、ローカルネットワークを使用します。
```

Release buildに不要なDebug-only service discovery設定を持ち込まない。

------------------------------------------------------------------------

## 9. Device Selection

検証優先順位:

1.  iOS Simulator
2.  iPhone実機

SimulatorだけでMVPの基本統合確認は可能だが、可能であれば最終的に実機でも確認する。

実機が利用できない・署名環境が未設定などの場合、それ自体をMVP
application bugとして扱わない。

Completion Reportへ:

``` text
Simulator: PASS / FAIL / NOT RUN
Physical iPhone: PASS / FAIL / NOT RUN
```

を明記する。

------------------------------------------------------------------------

## 10. Clean Test Data

統合確認にはテスト用の記録を使用する。

実際の健康状態の評価・目標設定を目的にしない。

テストデータはUI/APIの挙動を確認するためのものとする。

既存データがある場合、勝手に全削除しない。

DB resetが必要な場合は、既存development
DBであることを確認し、破壊的操作を実行する前にSTOPして報告する。

------------------------------------------------------------------------

# 11. Weight E2E

## 11.1 Create

Flutterから体重記録を1件作成する。

確認:

-   save成功
-   API request成功
-   PostgreSQLに保存
-   record_date保持
-   recorded_at保持
-   memo保持
-   weight numeric precisionが契約どおり

## 11.2 Dashboard

保存後Homeへ戻る。

確認:

-   Dashboard refresh
-   対象日のweightが表示
-   古い値が残らない
-   評価文言を追加しない

## 11.3 History

History → Weight。

確認:

-   新規記録が表示
-   backend orderどおりnewest-first
-   graphへactual recordのみ表示
-   synthetic pointなし
-   missing day補完なし

## 11.4 Range

確認:

-   7日
-   30日
-   3か月

既存Spec 013のcalendar semanticsを維持する。

## 11.5 Update

既存UI/APIで編集がMVPとして提供されている場合、記録を更新する。

確認:

-   同日duplicate createではなく既存仕様どおり更新
-   Dashboard反映
-   History反映
-   graph反映
-   PostgreSQL反映

## 11.6 Delete

既存UI/APIで削除が提供されている場合、削除する。

確認:

-   DBから削除
-   Dashboard / History / graphから消える
-   stale UIが残らない

もしAPIにはCRUDがあるがFlutterに編集・削除UIが存在しない場合、勝手にUIを追加せず、MVP
DoDおよび過去Specと照合してSTOPして報告する。

------------------------------------------------------------------------

# 12. Nutrition / Food E2E

## 12.1 NORMAL Day

FlutterからNORMAL日のfood recordを作成。

確認:

-   nutrition day作成/取得
-   food log保存
-   name保持
-   calories保持
-   protein_g保持
-   eaten_at保持
-   memo保持
-   eaten_atのlocal dateとnutrition day dateが一致

## 12.2 Daily Total

確認:

-   calorie total
-   protein total

はAPIで集計された実記録から表示される。

Flutterで独自の別ルールを作らない。

目標値、残量、過不足評価を追加しない。

## 12.3 Dashboard

確認:

-   NORMAL日の実totalが表示
-   stale valueなし

## 12.4 History

確認:

-   対象Nutrition Dayが表示
-   NORMALとして表示
-   totalsが表示
-   未記録日を仮想生成しない

## 12.5 Food Update / Delete

既存UIで提供されている範囲で確認。

更新/削除後:

-   total再計算
-   Dashboard反映
-   History反映
-   PostgreSQL反映

------------------------------------------------------------------------

# 13. Free Day E2E

Free Dayは「栄養計算を行わない日」であり、0 kcalの日ではない。

## 13.1 Set Free Day

foodが存在しない対象日をFree Dayへ変更。

確認:

-   `nutrition_days.mode = FREE_DAY`
-   totalsはnull / not applicable
-   Flutterで`Free Day`表示
-   `0 kcal` / `0 g`として表示しない

## 13.2 Dashboard

確認:

``` text
Free Day
```

として表示される。

NORMAL totalへ変換しない。

## 13.3 History

確認:

-   Free Dayとして表示
-   calorie/protein 0として表示しない
-   missing dayと混同しない

## 13.4 Food Conflict

Free Dayにfood追加を試みた場合、既存UI/API
contractどおり拒否されることを確認する。

期待:

``` text
FOOD_NOT_ALLOWED_ON_FREE_DAY
```

または現在のauthoritative contractに対応する既存error。

## 13.5 NORMAL → FREE_DAY conflict

foodが存在するNORMAL日をFree Dayへ変更しようとした場合、silent
deletionしない。

既存contractどおりconflictとなること。

------------------------------------------------------------------------

# 14. Symptom E2E

Flutterから体調記録を作成する。

確認:

-   recorded_at保存
-   nausea 1--10
-   abdominal_pain 1--10
-   fatigue 1--10
-   appetite 1--10
-   bowel_condition
-   memo
-   PostgreSQL保存

同日に複数記録可能であること。

同timestamp duplicateを勝手にdeduplicateしない。

## 14.1 Dashboard

確認:

-   APIが返したsnapshotを表示
-   Flutter独自のseverity評価なし
-   diagnosisなし

## 14.2 History

確認:

-   backend order維持
-   local timestamp表示
-   scales表示
-   bowel condition表示
-   duplicate timestampを落とさない

## 14.3 Safety

UIは症状から診断・薬量変更を提案しない。

体調について心配な場合は医療者へ相談する既存の中立的案内を維持する。

------------------------------------------------------------------------

# 15. Injection E2E

Flutterから注射記録を作成する。

この記録は医療者の指示に基づく実施内容を記録するためのものであり、アプリがdoseを決定するものではない。

確認:

-   record_date
-   injected_at
-   dose_mg
-   injection_site
-   memo
-   PostgreSQL保存

6 site:

-   ABDOMEN_UPPER_RIGHT
-   ABDOMEN_LOWER_RIGHT
-   ABDOMEN_UPPER_LEFT
-   ABDOMEN_LOWER_LEFT
-   THIGH_RIGHT
-   THIGH_LEFT

## 15.1 Date consistency

`record_date`と`injected_at`のoffsetが表すlocal calendar
dateが一致すること。

不一致は既存contractどおり拒否。

## 15.2 Dashboard

確認:

-   実際の記録が表示
-   next scheduled dateがbackend contractどおり表示
-   Flutter側で独自に+7計算しない
-   next dateをDBへ保存しない

## 15.3 History

確認:

-   backend ordering
-   dose/siteが実記録として表示
-   N+1 fetchなし
-   dose評価なし

## 15.4 Safety

禁止:

-   dose recommendation
-   dose increase/decrease suggestion
-   symptom-based dose adjustment
-   injection interval変更提案

------------------------------------------------------------------------

# 16. Dashboard Integration

任意の検証日について、Dashboardの4 sectionを確認する。

-   Weight
-   Nutrition
-   Symptom
-   Injection

確認:

-   requested dateとresponse date一致
-   requested timezoneとresponse timezone一致
-   RECORDED / UNRECORDED contract維持
-   Free Day semantics維持
-   stale request protection
-   record screenから戻った後refresh
-   pull-to-refresh

DashboardがDBを直接参照することはない。

必ず既存API経由。

------------------------------------------------------------------------

# 17. History Integration

4 tabs:

-   Weight
-   Food
-   Symptom
-   Injection

確認:

-   tab switching
-   initial loading
-   empty
-   error
-   retry
-   refresh
-   load more
-   no duplicate append
-   stale response ignore
-   backend order維持

Weightのみrange変更:

-   7日
-   30日
-   3か月

range変更前の古いresponseが混入しない。

------------------------------------------------------------------------

# 18. Navigation Integration

Bottom Navigation:

``` text
Home
Record
History
Settings
```

確認:

-   Home → Record
-   Home → History
-   Home → Settings
-   History → Home
-   History → Record
-   History → Settings
-   Settings → Home
-   Settings → Record
-   Settings → History

Settings再選択で不要なroute stackを増やさない。

既存record routes:

-   Weight
-   Food
-   Symptom
-   Injection

へ到達できること。

------------------------------------------------------------------------

# 19. Date / Time / Timezone Verification

このMVPではDATEとTIMESTAMPTZを明確に分ける。

## DATE

-   weight record_date
-   nutrition day date
-   injection record_date

DATEをtimezone conversionしない。

## TIMESTAMPTZ

-   recorded_at
-   eaten_at
-   injected_at
-   created_at
-   updated_at

APIではtimezone-aware timestamp。

backend responseは既存contractどおりUTC Zへnormalize。

Flutter表示時のみdevice local timeへ変換。

## Verification

少なくとも以下を確認:

-   current local date
-   midnight付近のtimestampをunit/widget testで扱えている
-   offset付き入力のcalendar date validation
-   fixed `+09:00` hard-codeなし
-   fixed IANA timezone hard-codeなし
-   offset stringをIANA timezoneとして送らない

実機のtimezoneを勝手に変更する必要はない。

------------------------------------------------------------------------

# 20. PostgreSQL Persistence Verification

Flutter UI上の表示だけで成功判定しない。

少なくとも各domainについて、backend/APIまたはdevelopment DB
inspectionで永続化を確認する。

対象:

-   weight_logs
-   nutrition_days
-   food_logs
-   symptom_logs
-   injection_records

確認:

-   create後に存在
-   update後に値反映
-   delete対象はdelete後に不存在
-   timestamps存在
-   enum-like valuesがcontract内

DB inspectionはread-only queryを優先する。

本番DBを想定した破壊的SQLをSpec 015で作らない。

------------------------------------------------------------------------

# 21. Error Verification

最低限、既存contractに沿って以下を確認する。

-   backend停止時にFlutterがcrashしない
-   retry可能
-   validation errorがgeneric crashにならない
-   conflictが既存localized messageへ変換される
-   malformed responseのCONTRACT handlingが既存testで維持
-   load-more errorで既存itemsを失わない

実機で全error caseを人工的に再現する必要はない。

unit/widget/backend
testsで既に保証されるものはtest結果を根拠にしてよい。

------------------------------------------------------------------------

# 22. Integration Bug Policy

統合確認で問題を発見した場合、以下を満たすものだけSpec
015内で修正してよい。

1.  Spec 000〜014の既存要件に反している
2.  MVP DoDを妨げる
3.  原因が再現できる
4.  最小修正で解決できる
5.  新機能ではない
6.  architecture全面変更ではない

例:

### 修正してよい

-   API Base URLが実機から到達不能
-   shared Dioが一部featureで使われていない
-   record後Dashboardがrefreshされない
-   Historyに新規recordが反映されない
-   timezone変換ミス
-   Free Dayが0として表示される
-   actual recordがgraphに出ない
-   iOS Debugだけdevelopment APIへ接続できない
-   routeが実機操作で到達不能

### 修正してはいけない

-   notificationを追加
-   cloud deploy
-   login追加
-   新しいgraph追加
-   target設定追加
-   AI分析追加
-   Health連携
-   UI全面リニューアル

------------------------------------------------------------------------

# 23. STOP Conditions

以下の場合は勝手に進めず報告する。

-   新規dependencyが必要
-   backend API contract変更が必要
-   DB schema変更が必要
-   Alembic migrationが必要
-   destructive DB resetが必要
-   authが必要
-   architecture全面変更が必要
-   過去Specとauthoritative implementationが矛盾
-   FlutterにMVP CRUD UIが欠落しており、新規画面実装が必要
-   iOS Release security policyを弱める必要がある
-   実データを削除する必要がある

STOP時は:

1.  blocker
2.  再現手順
3.  原因
4.  最小修正案
5.  scopeへの影響

を報告する。

------------------------------------------------------------------------

# 24. Automated Verification

実装変更の有無にかかわらず、最終的に既存test suiteをすべて実行する。

## Backend

repository既存手順を優先。

概念:

``` bash
cd backend
uv run pytest
```

実際のproject commandが異なる場合は既存README / pyprojectに従う。

## Flutter

``` bash
cd mobile

dart format .
flutter analyze
flutter test --reporter compact
```

## Repository

``` bash
cd ..

git diff --check
git status --short
```

変更が発生した場合:

``` bash
git diff -- backend
git diff -- mobile
```

を確認する。

------------------------------------------------------------------------

# 25. Manual Verification Matrix

Completion Reportに以下を埋める。

  Area                     Simulator   Physical iPhone   Result / Notes
  ------------------------ ----------- ----------------- ----------------
  App launch                                             
  API connection                                         
  Home                                                   
  Record navigation                                      
  Weight create                                          
  Weight update                                          
  Weight delete                                          
  Weight Dashboard                                       
  Weight History                                         
  Weight graph                                           
  Food create                                            
  Food update                                            
  Food delete                                            
  Nutrition totals                                       
  Free Day                                               
  Symptom create                                         
  Symptom History                                        
  Injection create                                       
  Injection History                                      
  Next injection date                                    
  History refresh                                        
  Settings                                               
  PostgreSQL persistence                                 

値:

``` text
PASS
FAIL
NOT RUN
BLOCKED
```

------------------------------------------------------------------------

# 26. MVP DoD Final Checklist

以下をすべて満たした場合、MVP DONEと判定する。

### Application

-   [ ] Flutter appが起動する
-   [ ] FastAPIへ接続できる
-   [ ] PostgreSQLへ接続できる

### Weight

-   [ ] スマホ/Simulatorから記録できる
-   [ ] PostgreSQLへ保存される
-   [ ] Dashboardで確認できる
-   [ ] Historyで確認できる
-   [ ] 体重graphで確認できる

### Nutrition

-   [ ] foodを記録できる
-   [ ] PostgreSQLへ保存される
-   [ ] daily totalを確認できる
-   [ ] Dashboardで確認できる
-   [ ] Historyで確認できる

### Free Day

-   [ ] Free Dayを設定できる
-   [ ] 0 kcalとして扱われない
-   [ ] DashboardでFree Day表示
-   [ ] HistoryでFree Day表示

### Symptom

-   [ ] 体調を記録できる
-   [ ] PostgreSQLへ保存される
-   [ ] Dashboardで確認できる
-   [ ] Historyで確認できる

### Injection

-   [ ] 注射記録を作成できる
-   [ ] PostgreSQLへ保存される
-   [ ] Dashboardで確認できる
-   [ ] Historyで確認できる
-   [ ] next injection dateが既存contractどおり表示される
-   [ ] dose recommendationがない

### Navigation

-   [ ] Home
-   [ ] Record
-   [ ] History
-   [ ] Settings

### Quality

-   [ ] backend tests green
-   [ ] Flutter tests green
-   [ ] flutter analyze green
-   [ ] dart format clean
-   [ ] git diff --check green
-   [ ] blockerなし

------------------------------------------------------------------------

# 27. Security / Development Configuration

development実機接続のための設定とproduction/release設定を混同しない。

特に:

-   LAN IPをsourceへcommitしない
-   secretをcommitしない
-   `.env`等を追加する場合は既存policyを確認する
-   Releaseへ不要なlocal network debug serviceを入れない
-   Releaseへ無制限cleartext HTTP許可を入れない
-   production endpointをこのSpecで作らない

このSpecの目的はdevelopment
environmentでMVPを統合確認することであり、本番deploymentではない。

------------------------------------------------------------------------

# 28. Documentation

API Base
URLの指定方法が既存READMEに存在せず、実機検証の再現に必要な場合のみ、README等へ最小限のdevelopment手順を追記してよい。

記載候補:

-   backend起動
-   Flutter起動
-   API Base URL注入方法
-   Simulatorとphysical deviceの違い
-   local network permission
-   development HTTPに関する注意

個人固有のIPアドレスを書かない。

例:

``` text
flutter run --dart-define=API_BASE_URL=http://<MAC_LAN_IP>:8000
```

実際のdefine名は既存実装に従う。

------------------------------------------------------------------------

# 29. Required Tests for Fixes

Spec 015でproduction codeを修正した場合、そのbugに対するregression
testを追加する。

原則:

``` text
bug reproduction
→ failing test
→ minimal fix
→ passing test
```

対象例:

-   base URL parsing
-   stale refresh
-   timezone conversion
-   navigation
-   Free Day semantics
-   response parsing

実機固有で自動testが困難な設定変更の場合は、manual
verification結果を明記する。

------------------------------------------------------------------------

# 30. Completion Report

Codexは完了時に以下を報告する。

1.  Preflight結果
2.  変更ファイル一覧
3.  production code変更の有無
4.  API Base URLの現在の仕組み
5.  実際に使用したdevelopment endpointの種類
    -   localhost
    -   Simulator-compatible host
    -   LAN host
    -   その他
6.  backend起動結果
7.  PostgreSQL起動結果
8.  migration状態
9.  Flutter → FastAPI接続結果
10. FastAPI → PostgreSQL永続化結果
11. Weight E2E結果
12. Nutrition E2E結果
13. Free Day E2E結果
14. Symptom E2E結果
15. Injection E2E結果
16. Dashboard結果
17. History結果
18. Weight graph結果
19. Navigation結果
20. timezone/date結果
21. error/retry結果
22. Simulator結果
23. Physical iPhone結果
24. Manual Verification Matrix
25. backend test結果
26. Flutter test結果
27. `flutter analyze`結果
28. `dart format`結果
29. `git diff --check`結果
30. backend / DB / Alembic変更の有無
31. dependency変更の有無
32. integration bugと修正内容
33. 未実施項目
34. blocker / warning
35. MVP DoD Final Checklist
36. MVP DONE / NOT DONE判定
37. commit / pushを行っていないこと

------------------------------------------------------------------------

# 31. Commit Policy

Spec 015の検証・必要なbug fixが完了してもcommit / pushしない。

ChatGPTによるcommit前レビューを受け、明示的に承認された後のみcommit /
pushする。

Manual verification中に一時的なdevelopment endpointや個人LAN
IPを使用しても、それをsource codeやcommit対象へ残さない。

------------------------------------------------------------------------

# 32. 最終判定

Spec 015完了時に、以下のどちらかを明示する。

``` text
MVP DONE
```

または

``` text
MVP NOT DONE
```

`MVP NOT DONE`の場合は、未達項目を列挙し、MVP完成に必要な最小の次アクションだけを提示する。

Post-MVP機能を混ぜない。
