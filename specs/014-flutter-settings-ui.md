# Spec 014 — Flutter Settings UI

## 1. 目的

MVPのSettings画面をFlutter側に実装し、Bottom Navigationの

- Home
- Record
- History
- Settings

をすべて実際に遷移可能な状態にする。

Settingsは**アプリの表示・固定単位・データ情報・医療上の注意事項を確認するための画面**とする。

このSpecでは、健康目標・減量目標・投薬調整・通知・認証・同期・外部連携などの新機能は追加しない。

---

## 2. 前提

実装開始前に、以下を読むこと。

- `AGENTS.md`
- `README.md`
- `docs/api-design.md`
- `docs/database-design.md`
- `specs/007-flutter-api-foundation.md`
- `specs/008-flutter-weight-ui.md`
- `specs/009-flutter-food-ui-nutrition-free-day.md`
- `specs/010-flutter-symptom-ui.md`
- `specs/011-flutter-injection-ui.md`
- `specs/012-flutter-dashboard-ui.md`
- `specs/013-flutter-history-and-weight-graph.md`
- `mobile/pubspec.yaml`
- `mobile/pubspec.lock`
- `mobile/lib/routing/app_router.dart`
- `mobile/lib/screens/home_screen.dart`
- `mobile/lib/features/history/presentation/history_screen.dart`
- 既存のRecord導線・各記録画面
- 既存test

実際の既存コードをauthoritativeとする。

Spec間で矛盾があれば、勝手に解決せず報告すること。

---

## 3. Scope

### IN

- `/settings` route
- Flutter Settings画面
- Bottom NavigationのSettings接続
- Home / Record / History / SettingsのNavigation整合性
- 体重単位の固定表示
- データ保存・APIに関する情報表示
- 医療上の注意事項
- アプリ情報
- neutral wording
- routing / widget test
- 既存Navigation regression test
- format / analyze / test

### OUT

- backend変更
- DB変更
- Alembic変更
- API変更
- 新規dependency
- persistent settings
- SharedPreferences
- localStorage相当
- theme切替
- light / dark mode設定
- language設定
- account
- auth
- cloud sync
- export
- CSV export
- PDF export
- notification
- injection reminder
- medication reminder
- Apple Health
- Health Connect
- food database
- barcode
- AI analysis
- clinician sharing
- calorie target
- protein target
- weight target
- BMI
- ideal weight
- weight-loss pace
- calorie deficit / surplus
- diet restriction guidance
- medication dose setting
- dose recommendation
- dose escalation / reduction
- injection interval setting
- symptom-based dose suggestion
- symptom diagnosis
- symptom severity classification
- cross-domain medical inference

---

## 4. Navigation

Bottom Navigationは以下の4項目を維持する。

```text
Home
Record
History
Settings
```

概念route:

```text
/
/record
/history
/settings
```

実際の既存GoRouter構成に合わせること。

### 4.1 Settings destination

HomeとHistoryのBottom NavigationからSettingsを押した場合、

```text
/settings
```

へ遷移する。

Settings画面では`selectedIndex = 3`相当とする。

Settings画面のBottom Navigationから、

- Home → `/`
- Record → `/record`
- History → `/history`
- Settings → 現在画面を維持

とする。

同一routeへの不要なpushを避ける。

### 4.2 Record route

既存の`/record`の挙動を変更しない。

Spec 013時点で`/record`が既存画面構成上HomeScreen等へ接続されている場合、その実装を勝手に大規模変更しない。

Navigation整理のためにrouting architecture全体を作り直さない。

---

## 5. Settings画面

画面タイトル:

```text
設定
```

以下のセクションを持つ。

---

## 6. 表示・単位

### 6.1 体重単位

表示:

```text
体重の単位
kg
```

MVPでは`kg`固定。

ユーザーが変更できるtoggle / dropdown / radio buttonは作らない。

変更可能であるように見えるUIも避ける。

例:

```text
体重の単位
kg（固定）
```

のような中立表示でよい。

### 6.2 calorie / protein

Settingsにcalorie targetやprotein targetを追加しない。

以下は禁止:

- 1日の目標calorie
- 1日の目標protein
- 残りcalorie
- 摂取上限
- 摂取下限
- deficit
- surplus
- 制限目標

---

## 7. データ情報

ユーザーに、MVPで記録対象となるデータの種類を確認できる情報を表示する。

例:

```text
記録データ

このアプリでは以下の記録を扱います。

・体重
・食事
・体調
・注射
```

保存先については、実際のarchitectureに沿った事実のみ表示する。

現在のMVP architectureがFastAPI + PostgreSQLであるため、たとえば以下のような表現は可。

```text
記録したデータはアプリからAPIを通じて保存されます。
```

ただし、technical implementation detailを過剰にUIへ出す必要はない。

以下のような断定は、実際に実装されていない限り禁止。

- 暗号化されています
- バックアップされます
- クラウド同期されます
- 他端末でも同期されます
- 永久保存されます

Settings UIは事実表示のみとする。

---

## 8. 医療上の注意事項

Settings内に医療上の注意事項セクションを設ける。

例:

```text
医療上の注意

このアプリは記録を整理・確認するためのものです。
診断や治療方針、薬の量を決めるものではありません。

薬の量や投与方法については、医療者の指示に従ってください。
体調について心配なことがある場合は、医療者へ相談してください。
```

文言は中立的で、過度に不安をあおらない。

### 禁止

- 症状から診断する
- 症状を重症 / 軽症などに分類する
- doseを変更するよう促す
- dose増量 / 減量を提案する
- 注射間隔変更を提案する
- 体重や食事記録から薬の調整を提案する
- 「この症状なら○mg」等の推論
- calorie制限を治療として勧める

---

## 9. アプリ情報

最低限、以下を表示してよい。

```text
アプリ情報
dietapp
```

version表示は、既存コードから安全に取得できる仕組みが**すでに存在する場合のみ**使用してよい。

`package_info_plus`等の新規dependencyを追加してversionを出すことは禁止。

既存dependencyやFlutter標準のみで自然に取得できない場合、version表示は不要。

---

## 10. UI方針

Material UIで既存アプリのvisual styleに合わせる。

大規模なdesign system変更はしない。

利用可能なwidget例:

- `ListView`
- `Card`
- `ListTile`
- `Divider`
- `Text`
- `Icon`
- `NavigationBar`

Settingsは閲覧主体の静的画面でよい。

### 10.1 Interaction

MVPではSettings内に保存操作は不要。

以下は不要:

- Save button
- Apply button
- Reset button

変更可能な設定が存在しないため。

---

## 11. Safe wording

### 使用してよい表現

- 設定
- 体重の単位
- kg
- 記録データ
- 体重
- 食事
- 体調
- 注射
- 医療上の注意
- アプリ情報
- 医療者の指示に従ってください
- 医療者へ相談してください
- 記録を整理・確認するためのものです

### 避ける表現

- 理想体重
- 目標体重
- 痩せる
- 太る
- 順調
- 停滞
- リバウンド
- 食べすぎ
- 食べなさすぎ
- 摂取制限
- calorie deficit
- 危険な体重
- 適正体重
- 適正dose
- 増量
- 減量
- dose変更
- この症状なら
- 治療効果
- 効いている
- 効いていない

---

## 12. Architecture

SettingsはMVPではbackend dataを必要としない。

そのため、原則として以下は作らない。

- SettingsRepository
- Settings API
- Settings DB model
- Settings providerによるremote state
- Settings persistence

静的画面として実装する。

ただし既存architecture上、画面widgetを適切なfeature directoryへ置く。

推奨概念:

```text
mobile/lib/features/settings/presentation/settings_screen.dart
```

既存directory conventionを優先する。

---

## 13. Route実装

`app_router.dart`へSettings routeを追加する。

概念:

```dart
GoRoute(
  path: '/settings',
  builder: ...,
)
```

既存routeを壊さない。

route追加に伴い、

- Home
- History
- Settings

のBottom Navigationを接続する。

Recordの既存routeも維持する。

---

## 14. Navigation重複

Settings route追加のためにNavigationBar実装が複数画面で多少重複しても、Spec 014では大規模共通化を必須にしない。

ただし明らかな小規模共通化が安全で、既存testsを壊さず、scopeを広げない場合は許容する。

以下は禁止:

- ShellRouteへの全面移行
- routing architecture総入れ替え
- 全screen scaffold再設計
- unrelated feature refactor

---

## 15. Error / Loading

Settings画面はremote fetchを行わないため、

- loading state
- API error
- retry

は不要。

route描画時に即表示されること。

---

## 16. Required Tests

最低限、以下を追加または更新する。

### 16.1 Routing

- `/settings`でSettings画面が表示される
- Settings titleが表示される
- Settings Bottom Navigationでselected destinationがSettings
- Settings → Home
- Settings → Record
- Settings → History
- Home → Settings
- History → Settings

### 16.2 Settings content

以下を確認。

- `設定`
- `体重の単位`
- `kg`
- 記録データ
- 体重
- 食事
- 体調
- 注射
- 医療上の注意
- アプリ情報

### 16.3 Medical safety

以下を確認。

- 医療者の指示に従う旨
- 診断や治療方針を決める機能ではない旨
- dose推奨表現がない

prohibited wording例:

```text
適正dose
増量
減量
理想体重
目標体重
順調
停滞
食べすぎ
```

がSettings画面に存在しないこと。

### 16.4 No mutable setting

MVPでは固定表示のみなので、以下が存在しないことを確認してよい。

- calorie target input
- protein target input
- weight target input
- dose input
- injection interval input
- notification toggle
- account controls

### 16.5 Regression

既存testsをすべて実行し、

- Dashboard
- Weight
- Nutrition
- Symptom
- Injection
- History

を壊していないこと。

---

## 17. Acceptance Criteria

以下をすべて満たすこと。

1. `/settings` routeが存在する。
2. Settings画面タイトルが`設定`である。
3. HomeからSettingsへ遷移できる。
4. HistoryからSettingsへ遷移できる。
5. SettingsからHomeへ遷移できる。
6. SettingsからRecordへ遷移できる。
7. SettingsからHistoryへ遷移できる。
8. Bottom NavigationでSettingsが選択状態になる。
9. 体重単位`kg`が固定表示される。
10. calorie / protein / weight targetを設定できない。
11. medication doseを設定・変更できない。
12. injection intervalを設定できない。
13. 記録対象データの情報が表示される。
14. 医療上の注意事項が表示される。
15. dose変更を示唆しない。
16. weight-loss評価を表示しない。
17. symptom diagnosis / severity評価を表示しない。
18. Settings API / DB / persistenceを追加しない。
19. backend変更なし。
20. DB / Alembic変更なし。
21. 新規dependency追加なし。
22. 既存Navigationを壊さない。
23. 既存全testがgreen。
24. `flutter analyze`がgreen。
25. `dart format`後に不要diffなし。
26. `git diff --check`がgreen。
27. commit / pushを行わない。

---

## 18. Verification

実装後に以下を実行する。

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

期待結果:

- format成功
- analyze成功
- 全Flutter test成功
- backend diffなし
- DB / Alembic diffなし
- pubspec dependency diffなし
- lockfile dependency diffなし

---

## 19. Manual Check

可能なら実機 / simulatorで以下を確認する。

```text
Home
  ↓ Settings

Settings
  ├ Home
  ├ Record
  └ History
```

Settingsで、

- unitがkg固定表示
- target入力がない
- dose入力がない
- notification設定がない
- 注意事項が読める
- Navigationが崩れていない

ことを確認する。

Manual integration未実施でも、自動testが通っていれば報告に明記する。

---

## 20. Scope Guard

実装中にSettings関連で追加機能が必要に見えても、このSpecでは勝手に追加しない。

特に以下を追加したくなった場合はSTOPして報告する。

- SharedPreferences
- package_info_plus
- notification package
- auth package
- analytics package
- health integration package
- theme persistence
- remote settings API
- backend settings table

必要なら後続Specとして切り出す。

---

## 21. Completion Report

Codexは実装完了時に以下を報告する。

1. 変更ファイル一覧
2. `/settings` route
3. Home / Record / History / SettingsのNavigation実装
4. Settings表示内容
5. kg固定表示
6. 記録データ情報
7. 医療上の注意事項
8. アプリ情報
9. mutable settingを追加していないこと
10. calorie/protein/weight targetを追加していないこと
11. dose / injection interval設定を追加していないこと
12. backend / DB / Alembic変更がないこと
13. dependency追加がないこと
14. 追加・更新test
15. `dart format`結果
16. `flutter analyze`結果
17. `flutter test`結果
18. `git diff --check`結果
19. manual integration結果
20. blocker / warning
21. commit / pushを行っていないこと

---

## 22. Commit Policy

実装完了後もcommit / pushしない。

ChatGPTによるcommit前レビューを受け、明示的に承認された後のみcommit / pushすること。
