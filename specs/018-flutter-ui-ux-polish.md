# Spec 018: Flutter UI/UX Polish

## 1. 目的

MVPで実装済みの機能・API契約・データモデルを維持したまま、Flutterアプリ全体のUI/UXを統一し、実機iPhoneで日常的に使いやすい画面へ改善する。

本Specでは新しい業務機能を追加しない。対象はVisual Design System、Home、Record、History、体重グラフ、体重・食事・体調・注射画面、Settings、Bottom Navigationである。

デザイン基準はSpec018検討時に作成したHomeモックアップの方向性とする。特定アプリの複製ではなく、白ベース、ミント系アクセント、丸みのある日本語タイポグラフィ、大きな余白、淡いカテゴリ色、細い区切り線をdietapp独自のUIとして展開する。

---

## 2. 前提

- Flutter / Dart
- Riverpod
- GoRouter
- Dio
- fl_chart
- 既存REST API `/api/v1`
- Production APIは `--dart-define=API_BASE_URL=...` で指定する
- backend / API / DB / migrationは変更しない
- 既存の体重・食事・体調・注射の記録機能を維持する
- Free Dayの既存domain ruleを維持する
- 注射の用量・投与日は医療者の指示に基づく記録データとしてのみ扱う
- アプリから診断、治療方針、用量変更を提案しない

---

## 3. Scope

### IN

- 共通Visual Design System
- Home UI刷新
- Record UI刷新
- History UI刷新
- 体重グラフの視認性・操作性改善
- Weight / Food / Symptom / Injection UI統一
- Settings UI刷新
- Bottom Navigationの統一
- iPhone SEを含む小さいiPhone画面への対応
- Widget / navigation / graph testの更新・追加
- 物理iPhoneでの最終確認

### OUT

- backend API変更
- DB / Alembic migration変更
- 認証
- Push通知
- Apple Health / Health Connect
- 新しい健康指標
- 体重目標
- カロリー・タンパク質目標
- 記録値の良し悪しを評価する機能
- AI分析
- App Store / TestFlight対応
- 新しいグラフライブラリへの置換
- routing architectureの大規模変更

---

## 4. Visual Design System

### 4.1 基本方針

全主要画面で以下を共通化する。

- 白〜ごく淡いニュートラルカラーを背景とする
- Primary accentはミント / teal系
- 大型の灰色カードを基本レイアウトとして使用しない
- セクション間は余白と細いDividerで区切る
- 重要情報と補足情報の文字サイズ・weight・色を明確に分ける
- タップ可能領域は見た目以上に十分な大きさを確保する
- 不要な長文を常時表示しない
- 状態は `未記録` / `記録済み` / `Free Day` 等の短い表現を優先する
- 色だけで状態を伝えない

### 4.2 Typography

丸ゴシック系の日本語フォントをアプリ全体へ適用する。

第一候補は `M PLUS Rounded 1c` とする。ただし導入前に以下を確認する。

- Flutter / iOS上での可読性
- ライセンス
- バンドル方法
- 既存レイアウトへの影響

フォント導入が想定外のdependency追加やarchitecture変更を必要とする場合はSTOPして報告する。

最低限以下の文字階層を共通化する。

- Page title
- Section title
- Primary value
- Body
- Supporting text
- Button label
- Caption

### 4.3 Category identity

同じカテゴリは全画面で同じアイコンと色表現を使う。

- 体重: 淡い水色系
- 食事: 淡いオレンジ系
- 体調: 淡いピンク系
- 注射: 淡い紫系

カテゴリ色は装飾・識別目的であり、健康状態の良否を表す色として使用しない。

### 4.4 共通Component

可能な範囲で以下をTheme / reusable Widgetとして整理する。

- Page title
- Section header
- Category icon container
- Status / record row
- Primary button
- Secondary button
- Rounded input field
- Divider
- Bottom Navigation
- Empty state
- Medical notice

ただしSpec018のためだけの過度な抽象化や大規模リファクタは行わない。

---

## 5. Home

### 5.1 目的

Homeは「今日の状態と次に確認すべき情報を短時間で把握する画面」とする。

詳細情報を大量に表示する画面にはしない。

### 5.2 Header

- タイトル: `ホーム`
- 日付は `9月13日（日）` のような自然な日本語表記
- 現在の `日付 / YYYY/MM/DD` のような管理画面的表示は廃止する

### 5.3 次回の注射

Home上部に「次回の注射」を専用領域として表示する。

表示例:

- 次回の注射
- 9月18日（金）
- あと5日

既存仕様どおり、次回日付は最新の注射記録から算出された情報であり、DBへ新規保存しない。

これは治療や投与を推奨する表示ではない。

可能であれば、スクロール時にも上部に残るコンパクトなsticky領域とする。

固定領域がiPhone SEでコンテンツを圧迫しないよう、コンパクトな高さを優先する。

実装に `SliverPersistentHeader` 等を使用してよいが、大規模なscroll architecture変更が必要な場合はSTOPして報告する。

### 5.4 今日の記録

以下を縦方向のシンプルなセクションとして表示する。

- 体重
- 食事
- 体調
- 注射

大型カードを4枚並べるのではなく、

`カテゴリ色付きアイコン + 見出し + 要約 + 操作 + Divider`

を基本とする。

表示例:

- 体重: `未記録` または記録値
- 食事: `Free Day` / `未記録` / 記録済みの要約
- 体調: `14:42 記録済み` 等
- 注射: `未記録` または記録済みの要約

Homeでは体調の全スコア等を常時展開しない。

記録済みの場合は詳細へ、未記録の場合は既存記録画面へ遷移できる。

### 5.5 Homeから削減する情報

Homeで常時表示する必要のない長い説明文は、詳細・入力画面等の適切な場所へ残す。

医療上必要な注意文そのものを削除してはならない。

### 5.6 Homeに体重グラフは追加しない

体重グラフはHistoryの責務とし、本SpecではHomeへ追加しない。

---

## 6. Record

既存4導線を維持する。

- 体重 — 今日の体重を記録
- 食事 — 食べたものを記録
- 体調 — 今日の状態を記録
- 注射 — 注射の記録

各行は以下を持つ。

- カテゴリアイコン
- タイトル
- 1行の短い説明
- Chevron
- 十分なタップ領域

既存routeを維持する。

- `/record/weight`
- `/record/food`
- `/record/symptom`
- `/record/injection`

Record tabの `selectedIndex == 1` を維持する。

---

## 7. History

### 7.1 Tabs

既存の以下4タブを維持する。

- 体重
- 食事
- 体調
- 注射

選択状態を新Design Systemへ合わせて視覚的に分かりやすくする。

### 7.2 History list

各カテゴリの履歴は、大型カードの連続ではなく、余白とDividerを使った読みやすいリストを基本とする。

記録の詳細へ到達できる既存導線を維持する。

---

## 8. Weight Graph

### 8.1 期間

既存の以下3期間を維持する。

- 7日
- 30日
- 3か月

### 8.2 データ

実在する体重記録だけをグラフデータとして扱う。

- 記録のない日を `0 kg` として扱わない
- 存在しない測定値を新しい記録値として生成しない
- 期間内に存在する実測データを時系列順の推移線に使用する

### 8.3 X軸

期間ごとの代表目盛り・代表ポイントの表示間隔を以下とする。

- 7日: 1日ごと
- 30日: 約1週間ごと
- 3か月: 約2週間ごと

重要: 上記はX軸の代表表示間隔であり、期間内の実測データそのものを削除・破棄する仕様ではない。

### 8.4 Y軸

縦軸は期間内の実測体重に応じた「大まかなkg目盛り」とする。

要件:

- 全実測値が表示範囲内に収まる
- 読みやすい丸めた目盛りを使う
- 過度に細かな変化を誇張する表示を避ける
- `kg` が分かる表示にする
- データが1件だけの場合も破綻しない

tick / range計算は、必要に応じてテスト可能な純粋関数へ分離してよい。

### 8.5 Point interaction

グラフ上の実測ポイントをタップするとTooltipを表示する。

Tooltipには最低限以下を表示する。

- 日付
- 体重（kg）

例:

- `9月11日`
- `80.2 kg`

タップ判定領域は表示上の点より広くし、小さいiPhoneでも操作しやすくする。

### 8.6 Visual

- 強い外枠を削減
- Grid lineは控えめ
- 推移線はPrimary accent
- Pointは必要最小限
- 最新値を読み取りやすくする
- 7日 / 30日 / 3か月切替は現在よりコンパクトにする
- 既存 `fl_chart` を利用する
- 新しいgraph dependencyは追加しない

---

## 9. Weight screen

既存のcreate / edit / delete behaviorを維持する。

基本構造:

1. Page title
2. Date
3. Weight input
4. Recorded time
5. Memo
6. Primary action
7. Edit時のみdelete action

UI:

- Weight inputは丸みのある入力領域
- `kg` を明確に表示
- 記録時刻を読みやすく表示
- Memoは複数行入力として視覚的に分かる形にする
- createでは `保存する`
- editでは `更新する`
- deleteはPrimary actionより視覚的優先度を下げる

体重値について評価・目標・増減の良否を示す文言は追加しない。

---

## 10. Food screen

既存のFood / Nutrition Day / Free Dayのdomain behaviorを変更しない。

画面は以下の順序を基本とする。

1. Page title
2. Date
3. 当日の状態 / 記録概要
4. Food log list
5. `食事を記録`
6. Free Day操作

Free Dayは引き続き「栄養計算を行わない日」として扱う。

- `0 kcal` と同義にしない
- 食事量の多寡を評価しない
- 補償行動を促す表現を追加しない
- 既存のNORMAL / FREE_DAY / UNRECORDEDルールを維持する
- 既存conflict handlingを変更しない

---

## 11. Symptom screen

既存の症状記録機能を維持する。

対象:

- 吐き気
- 腹痛
- だるさ
- 食欲
- 便通

1〜10の意味・既存validationを変更しない。

履歴/要約では値を整列して読みやすくする。

Homeでは詳細値を圧縮し、記録画面・詳細画面では読みやすく表示する。

強い症状や気になる変化がある場合に医療機関へ相談する既存の安全案内を維持する。

アプリから診断や薬の調整を提案しない。

---

## 12. Injection screen

既存Injection domain behaviorを維持する。

### 表示

UI上の英語 `dose` は、意味が分かる日本語へ統一する。

推奨表示:

`用量（mg）`

これは医療者から指示された用量をユーザーが記録するフィールドであることを維持する。

### Fields

- Date
- Injected time
- Clinician-directed dose
- Injection site
- Memo

既存の6注射部位を維持する。

次回注射日は既存ロジックで算出し、治療提案として扱わない。

医療者の指示に従う旨の既存安全文言を維持する。

---

## 13. Settings

Settingsは大型説明カード中心から、セクション＋Divider中心の構成へ変更する。

### 表示・単位

- 体重の単位
- `kg（固定）`

### データについて

- 体重
- 食事
- 体調
- 注射
- APIを通じて保存される旨

### 医療上の注意

既存の意味を維持する。

最低限以下を伝える。

- 記録を整理・確認するためのアプリ
- 診断や治療方針を決めるものではない
- 薬の量を決めるものではない
- 薬の量・投与方法は医療者の指示に従う
- 体調について心配な場合は医療者へ相談する

### アプリ情報

- `dietapp`

---

## 14. Bottom Navigation

既存4 destinationを維持する。

- Home
- Record
- History
- Settings

要件:

- 全主要画面で視覚表現を統一
- 選択中destinationが明確
- ミント系アクセントを使用
- ラベルとアイコンの可読性を維持
- iPhone SEで窮屈にならない
- navigation behaviorは既存routeを維持
- Record navigation regressionを再発させない

---

## 15. Responsive / Accessibility

最低限、Spec017で使用した物理iPhoneを含む小さいiPhone画面で確認する。

- 横方向overflowなし
- Bottom Navigationが欠けない
- 入力欄がキーボードで操作不能にならない
- Sticky injection areaが画面を過度に占有しない
- 長い日本語が不自然に切れない
- Tooltipが画面外へ大きくはみ出さない
- タップ可能領域を十分確保する
- 色だけで状態を伝えない
- destructive actionはPrimary actionと明確に区別する
- Loading / Error / Empty stateの既存behaviorを失わない

---

## 16. Implementation order

Codexは一度に全画面を書き換えない。

以下の順で実装・検証する。

1. Design System / Theme / reusable presentation components
2. Home
3. Record
4. History + Weight Graph
5. Weight
6. Food
7. Symptom
8. Injection
9. Settings
10. Bottom Navigation / cross-screen consistency
11. automated tests
12. physical iPhone verification

各段階で既存テストを壊していないことを確認する。

---

## 17. Acceptance Criteria

### Design System

- AC-01: 白ベース＋ミント系accentの共通Themeが適用される
- AC-02: 丸ゴシック系日本語フォント方針が全主要画面で統一される
- AC-03: 体重・食事・体調・注射のカテゴリ色/アイコンが画面間で一貫する
- AC-04: 大型灰色カードの乱用が解消され、余白とDivider中心の情報設計になる

### Home

- AC-05: Homeに自然な日本語日付が表示される
- AC-06: 次回注射情報がHome上部にコンパクトに表示される
- AC-07: 可能な範囲で次回注射領域がスクロール時も上部に残る
- AC-08: 体重・食事・体調・注射の今日の状態を短時間で把握できる
- AC-09: Homeから既存記録/詳細導線へ到達できる
- AC-10: Homeに体重グラフを追加しない
- AC-11: Homeで長い体調詳細・注意文を常時展開しない

### Record

- AC-12: Recordに4カテゴリが統一デザインで表示される
- AC-13: 各カテゴリから既存4 routeへ遷移できる
- AC-14: Record tabのselected stateが正しい

### History / Graph

- AC-15: 体重・食事・体調・注射の4タブを維持する
- AC-16: 体重の7日/30日/3か月切替を維持する
- AC-17: 7日は1日、30日は約1週間、3か月は約2週間をX軸の代表表示間隔とする
- AC-18: 実在する全期間内体重記録を推移線データとして保持する
- AC-19: 欠損日を0kgとして表示しない
- AC-20: Y軸が期間内データに応じた大まかなkg目盛りになる
- AC-21: 実測pointをタップすると日付とkgのTooltipが表示される
- AC-22: 1件のみ/少数データ/欠損を含む期間でもグラフが破綻しない
- AC-23: History listが新Design Systemへ統一される

### Record detail/input screens

- AC-24: Weight画面の既存create/edit/deleteが維持される
- AC-25: Food / Free Dayの既存domain behaviorが維持される
- AC-26: Symptomの既存1〜10 validationと安全案内が維持される
- AC-27: Injectionの既存validation・注射部位・安全案内が維持される
- AC-28: Injection UIの `dose` 表記が意味の明確な日本語へ改善される
- AC-29: 4記録画面のフォームデザインが統一される

### Settings / Navigation

- AC-30: Settingsがセクション＋Divider中心のUIになる
- AC-31: 医療上の注意の意味が維持される
- AC-32: Bottom Navigationの4 destinationが維持される
- AC-33: Home / Record / History / Settings間のnavigation regressionがない

### Quality

- AC-34: `dart format .` がPASS
- AC-35: `flutter analyze` がPASS
- AC-36: `flutter test` がPASS
- AC-37: `git diff --check` がPASS
- AC-38: backend / API / DB / migrationに不要な変更がない
- AC-39: 新しいグラフdependencyを追加していない
- AC-40: Production API URLをhard-codeしていない
- AC-41: 物理iPhoneで主要4タブと記録画面を確認できる
- AC-42: 物理iPhoneで体重グラフの期間切替とpoint tooltipを確認できる
- AC-43: 小さいiPhone画面で重大なoverflowがない
- AC-44: 記録値の良し悪し、体型、減量速度、食事制限等を評価・促進する新規文言がない
- AC-45: アプリが薬の用量変更・治療判断を提案しない

---

## 18. Tests

既存テストを維持し、変更されたUIに合わせて更新する。

最低限以下をテストする。

- Homeの主要セクション表示
- Homeから各記録導線
- Record 4導線
- Bottom Navigation
- History 4 tabs
- 7日 / 30日 / 3か月切替
- graph X軸interval selection
- graph Y軸range/tick calculation
- graph missing data behavior
- graph single-point behavior
- graph point touch / tooltip behavior
- Weight create/edit
- Food / Free Day
- Symptom
- Injection
- Settings
- Loading / Error / Empty state

可能なものは表示文字列だけではなく、Widgetの状態・route・callback等を確認する。

---

## 19. STOP条件

以下が必要になった場合は実装を進めず報告する。

- backend API contract変更
- DB schema / migration変更
- 新規有料サービス
- 新しいグラフライブラリ
- routing architectureの大規模変更
- Free Day domain rule変更
- Injection domain rule変更
- 認証追加
- Production secretのrepo保存
- unrestricted ATS
- 医療判断・用量推奨につながる仕様変更
- 体重目標、摂取目標、食事制限等の新しい健康判断機能
- フォント導入でライセンス上の問題が判明
- フォント導入に想定外のdependency/architecture変更が必要

---

## 20. Verification

実装完了後、最低限以下を実行する。

```bash
cd mobile
dart format .
flutter analyze
flutter test --reporter compact

cd ..
git diff --check
git status --short
```

実機確認ではProduction APIをdart-defineで指定する。

```bash
cd mobile

flutter run   -d <physical-iphone-device-id>   --dart-define=API_BASE_URL=https://<production-host>
```

Production URLをソースコードへhard-codeしない。

実機で最低限以下を確認する。

- Home
- Sticky / compact next injection area
- Record
- Weight
- Food
- Symptom
- Injection
- History
- Weight graph 7d / 30d / 3mo
- Point tooltip
- Settings
- Bottom Navigation
- Scroll
- Keyboard
- overflow

---

## 21. Definition of Done

以下をすべて満たしたときSpec018をDONEとする。

1. AC-01〜AC-45を確認済み
2. Flutter format / analyze / test PASS
3. `git diff --check` PASS
4. backend / API / DB / migrationへの不要な変更なし
5. 物理iPhoneで主要画面を確認済み
6. 体重グラフの期間切替・大まかなY軸・point tooltipを実機確認済み
7. Home / Record / History / Settingsのデザインが一貫している
8. 既存の体重・食事・体調・注射機能が維持されている
9. 医療安全上の既存方針が維持されている
10. commit / push前に差分レビューを行う
