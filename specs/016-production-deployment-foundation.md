# Spec 016: Production Deployment Foundation

## 1. 目的

MVPで完成した Flutter + FastAPI + PostgreSQL 構成を、開発用 Docker Compose / iOS Simulator だけでなく、**実機 iPhone から HTTPS 経由で利用できる production-ready な基盤**へ移行する。

このSpecでは、production環境の土台を整え、以下を達成する。

- FastAPI backend を外部から HTTPS で到達可能にする
- production PostgreSQL を開発DBから完全分離する
- Alembic migration を production に安全に適用できるようにする
- secret / environment variable をソースコードへ埋め込まない
- Flutter が production API を `--dart-define` で切り替えられることを確認する
- health check により backend / DB の稼働確認ができる
- production deployment 手順を文書化する

このSpecは**機能追加Specではない**。既存MVPのAPI契約、DB schema、Flutter画面・機能を変更しない。

---

## 2. 背景

Spec 015 までで、以下は確認済みである。

- Flutter iOS Simulator から FastAPI へ接続可能
- FastAPI から PostgreSQL へ接続可能
- Alembic migration `20260904_0001` 適用済み
- Weight / Food / Free Day / Symptom / Injection / Dashboard / History / Weight graph のE2E確認済み
- Flutter test: 116 passed
- backend pytest: 184 passed
- iOS scaffold追加済み
- Flutter API base URL は `API_BASE_URL` の `--dart-define` で注入可能

現在の開発接続例:

```text
Flutter Simulator
    ↓ http://127.0.0.1:8000
FastAPI (Docker Compose)
    ↓
PostgreSQL (Docker Compose)
```

Spec 016 完了後の想定:

```text
Physical iPhone / Simulator
    ↓ HTTPS
Production FastAPI
    ↓ TLS/managed network
Production PostgreSQL
```

---

## 3. Scope

### 3.1 In Scope

- production用 backend 起動設定
- production用 environment variable 契約
- production PostgreSQL 接続
- HTTPS前提の外部API公開
- health check endpoint
- Alembic migration の production 運用方針
- production用ログ出力の最低限整理
- production deployment documentation
- Flutter production API base URL の設定方法確認
- production / development の明確な分離
- deploy後の最低限 smoke test

### 3.2 Out of Scope

- 認証 / ユーザー管理
- マルチユーザー対応
- Apple Health / Health Connect
- Push通知
- App Store 配布
- TestFlight
- 独自ドメイン必須化
- CI/CD自動デプロイ
- DBバックアップ自動化
- observability SaaS導入
- rate limit
- WAF
- Redis
- background worker
- API version変更
- schema変更
- UI/UX改善
- 新規Flutter画面

これらは後続Specで扱う。

---

## 4. 基本方針

### 4.1 production と development は完全分離する

development:

- Docker Compose
- local PostgreSQL
- local FastAPI
- `http://127.0.0.1:8000`

production:

- public HTTPS endpoint
- managed / isolated PostgreSQL
- production secrets
- production migration state

**development DB と production DB を共有してはならない。**

---

### 4.2 production provider に依存しすぎない

本Specのコード変更は特定クラウドへ強く依存しない構成とする。

利用するplatformは以下を満たせばよい。

- containerized FastAPIを起動可能
- HTTPS endpointを提供可能
- environment variables / secretsを設定可能
- PostgreSQLを提供または外部接続可能
- deploy前後に migration command を手動またはone-shotで実行可能

provider固有設定が必要な場合は最小限とする。

---

## 5. Environment Variable Contract

production backend は最低限以下を environment variable から受け取る。

### 5.1 必須

```text
DATABASE_URL
```

SQLAlchemy / psycopg で利用可能な PostgreSQL 接続URL。

例示用形式:

```text
postgresql+psycopg://<user>:<password>@<host>:<port>/<database>
```

実値をrepositoryへ保存してはならない。

### 5.2 推奨

既存設定構造に自然に追加できる場合のみ、以下を利用してよい。

```text
APP_ENV=production
LOG_LEVEL=INFO
```

ただし、本Specのためだけに大規模なsettings frameworkを導入してはならない。

### 5.3 禁止

以下をgit管理対象へ直接記載しない。

- production DB password
- provider secret
- API token
- private hostname with credentials
- personal LAN IP
- `.env` production実値

必要なら `.env.example` のみ利用する。

---

## 6. Backend Production Startup

### 6.1 起動要件

production backend は以下を満たす。

- `0.0.0.0` でlisten可能
- portをenvironmentから受け取れることが望ましい
- providerが指定する `PORT` に対応可能
- development向けreloadを使用しない
- production起動時にdebug modeを使用しない

例示概念:

```text
uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}
```

実装方法は既存 Dockerfile / project構成へ合わせる。

### 6.2 Migrationをapp startupへ埋め込まない

以下は禁止する。

```text
container boot
  -> alembic upgrade head
  -> uvicorn
```

を常時自動実行する設計。

理由:

- 複数instance起動時の競合
- migration失敗時の挙動が不明瞭
- rollback / deployment controlが難しくなる

migration は deploy step / one-shot command / manual release step として明示的に実行する。

---

## 7. Health Check

### 7.1 Endpoint

以下を追加する。

```http
GET /health
```

または既存API方針に合わせる場合:

```http
GET /api/v1/health
```

どちらか一つに統一する。

推奨は platform health check 用として単純な:

```http
GET /health
```

### 7.2 正常レスポンス

```json
{
  "status": "ok"
}
```

HTTP:

```text
200 OK
```

### 7.3 DB reachability

health check は PostgreSQL への軽量な疎通も確認する。

例:

```sql
SELECT 1
```

DB接続不可の場合は 5xx を返す。

### 7.4 禁止

health responseへ以下を含めない。

- DATABASE_URL
- DB password
- internal hostname
- stack trace
- environment dump
- patient/user data

---

## 8. Database / Alembic

### 8.1 production DB 初期化

production DB に対して以下を実行可能にする。

```bash
alembic upgrade head
```

完了後:

```bash
alembic current
```

が:

```text
20260904_0001 (head)
```

またはその時点のrepository headを示すこと。

### 8.2 Alembic check

production deploy前のlocal validationとして:

```bash
alembic check
```

が成功すること。

### 8.3 destructive operation禁止

Spec 016では以下を実行しない。

- `drop database`
- `drop table`
- production volume削除
- migration historyの手動改変
- `alembic stamp` による履歴偽装
- productionデータの一括削除

必要になった場合はSTOPして報告する。

---

## 9. Flutter Production API Configuration

既存の `API_BASE_URL` の仕組みを維持する。

production接続例:

```bash
flutter run \
  --dart-define=API_BASE_URL=https://api.example.com
```

### 9.1 Requirements

- production URLをsource codeへhard-codeしない
- development defaultを変更する必要がある場合でもproduction URLを固定値にしない
- production接続はHTTPSを使用する
- unrestricted ATS exceptionを追加しない

### 9.2 iOS

Spec 016ではHTTPS production APIを前提とし、以下を追加しない。

```text
NSAllowsArbitraryLoads = true
```

local HTTP開発用の例外をproductionへ持ち込まない。

---

## 10. CORS

Flutter mobile applicationからのHTTP通信にはbrowser CORS制約は適用されない。

そのため本Specでは、**Flutterのためだけに広いCORS設定を追加しない。**

既存backendにCORS middlewareがない場合、Spec 016だけを理由に追加しない。

将来Web clientを追加する場合は別Specで扱う。

---

## 11. Logging

productionで最低限以下を確認できること。

- application start
- request status
- unhandled server errors
- DB connection error

### 禁止

ログへ以下を出力しない。

- DATABASE_URL全文
- password
- secret/token
- memo本文を含むrequest body全体
- health-related user dataの不要なdump

既存のframework標準loggingで十分な場合、新規logging libraryを追加しない。

---

## 12. Error Handling

既存のAPI error contractを維持する。

production deploymentのために既存endpointのresponse shapeを変更しない。

unexpected error時にclientへstack traceを返さない。

既存の500 behaviorを大きく書き換える必要がある場合はSTOPして報告する。

---

## 13. Repository Changes

実装時に変更してよい候補:

```text
backend/Dockerfile
backend/... settings/config files
backend/... health endpoint files
backend/tests/...
README.md
AGENTS.md
.env.example
specs/016-production-deployment-foundation.md
```

実際のproject構造へ合わせる。

### 原則変更禁止

```text
mobile/lib/features/**
mobile/lib/screens/**
backend/app/models/**
backend/alembic/versions/**
```

health endpoint追加に必要なrouter変更は可。

DB schema / migrationが必要になった場合はSTOP。

---

## 14. Deployment Documentation

repository内にproduction deployment手順を残す。

推奨:

```text
docs/deployment.md
```

最低限以下を記載する。

1. 必要なproduction environment variables
2. backend build方法
3. backend start command
4. PostgreSQL接続設定
5. Alembic migration command
6. health check方法
7. deploy後smoke test
8. Flutterからproduction APIへ接続する方法
9. rollback時に「DBを破壊しない」原則
10. secretをgitへcommitしない注意

provider固有のdashboard操作は、実際に利用するproviderが決まった範囲のみ記載する。

---

## 15. Automated Verification

### Backend

最低限:

```bash
pytest
```

既存全testがPASSすること。

health endpointについてtestを追加する。

検証例:

- DB正常 -> 200 + `{ "status": "ok" }`
- DB接続失敗 -> 5xx
- secret等をresponseしない

### Flutter

production foundation変更でFlutter codeを変更していなくても:

```bash
flutter analyze
flutter test
```

を実行する。

### Repository

```bash
git diff --check
```

PASSすること。

---

## 16. Manual Deployment Verification

production deploy後に以下を手動確認する。

### 16.1 Backend

```bash
curl -i https://<production-host>/health
```

期待:

```text
HTTP 200
```

```json
{"status":"ok"}
```

### 16.2 Existing API

production DBが空の場合、例として:

```bash
curl -i https://<production-host>/api/v1/weights/2099-01-01
```

期待:

```text
404
WEIGHT_NOT_FOUND
```

既存error contractがproductionでも維持されること。

### 16.3 Flutter

SimulatorまたはPhysical iPhoneから:

```bash
flutter run \
  --dart-define=API_BASE_URL=https://<production-host>
```

以下を最低限確認する。

- app起動
- Dashboard load
- Weight画面load
- network errorなし

完全な実機CRUD E2EはSpec 017で行う。

---

## 17. Acceptance Criteria

### AC-01
production backendがpublic HTTPS endpointから到達可能。

### AC-02
production PostgreSQLがdevelopment PostgreSQLと完全に分離されている。

### AC-03
production secretがrepositoryへcommitされていない。

### AC-04
backendがproduction `DATABASE_URL` をenvironmentから取得できる。

### AC-05
production backendがprovider指定portで起動可能。

### AC-06
productionでreload/debug前提の起動を行わない。

### AC-07
`GET /health` がDB正常時に200を返す。

### AC-08
DB接続不可時、health checkが正常扱いにならない。

### AC-09
health responseにsecret/internal DB情報を含めない。

### AC-10
production DBへ `alembic upgrade head` を適用できる。

### AC-11
migration後に `alembic current` がheadを示す。

### AC-12
app startupへAlembic migrationを常時自動実行する実装を入れていない。

### AC-13
Flutterから`--dart-define=API_BASE_URL=https://...`でproduction APIを利用できる。

### AC-14
production用にunrestricted ATS exceptionを追加していない。

### AC-15
Flutter向けという理由だけでwildcard CORSを追加していない。

### AC-16
既存API contract / DB schema / migration historyを変更していない。

### AC-17
backend全testがPASS。

### AC-18
Flutter analyze/testがPASS。

### AC-19
`git diff --check`がPASS。

### AC-20
`docs/deployment.md`にproduction deployment procedureが記録されている。

### AC-21
production health checkと既存APIのmanual smoke testがPASS。

### AC-22
production URLを用いたFlutter起動・Dashboard/Weight画面loadがPASS。

---

## 18. Definition of Done

Spec 016は以下の状態でDONEとする。

> FastAPI backend と PostgreSQL がdevelopment環境から分離されたproduction環境で稼働し、HTTPS経由で到達可能であり、Alembic migration、health check、secret管理、Flutter production API接続方法が確立され、既存MVPのAPI contract・DB schema・機能を壊さずに自動テストとproduction smoke testを通過している。

---

## 19. STOP Conditions

以下のいずれかが必要になった場合、Codexは独断で進めずSTOPして報告する。

- DB schema変更
- 新規Alembic migration作成
- production data削除
- production DB reset
- authentication追加
- API contract変更
- wildcard CORS追加
- unrestricted ATS exception追加
- production secretのrepository保存
- 新規有料service契約が必要
- provider account / billing操作が必要
- domain購入が必要
- architectureの大幅変更
- Docker Compose development環境を壊す変更
- dependencyの大規模追加
- migrationをapp startupへ自動組み込みする必要があると判断した場合

外部providerのdashboard操作・credential入力はユーザーが行う。Codexはcredentialを要求・保存しない。

---

## 20. Codex Implementation Procedure

1. `AGENTS.md` を読む
2. 本Specを読む
3. `docs/api-design.md`、`docs/database-design.md`を確認
4. 現在のDockerfile / backend startup / config構造を確認
5. 既存の `API_BASE_URL` 実装を確認
6. 最小変更案を決める
7. health endpointと必要なproduction startup対応を実装
8. health testを追加
9. `docs/deployment.md`を作成
10. format / lint / testを実行
11. `git diff --check`
12. 変更ファイルと検証結果を報告
13. commit / pushは行わない

---

## 21. Codex Final Report Format

実装後、以下を報告する。

```text
- 判定: PASS / FAIL
- 変更ファイル
- production startup方法
- environment variables
- health check仕様
- migration運用方法
- deployment manual手順
- backend test結果
- Flutter analyze/test結果
- git diff --check結果
- STOP条件該当有無
- 未実施の外部作業
- commit前の注意点
```

外部providerへの実deployが未実施の場合は、コード側PASSとproduction deploy未完了を明確に分けて報告する。

---

## 22. Spec Completion Rule

Spec 016のコード実装が完了しても、外部production環境が未作成の場合は:

```text
Implementation: PASS
Deployment: NOT DONE
Spec 016: NOT DONE
```

とする。

実際にproduction環境へdeployし、AC-01〜AC-22のうち外部環境を必要とする項目まで確認できた時点で:

```text
Implementation: PASS
Deployment: PASS
Spec 016: DONE
```

とする。
