# Spec 017: Physical iPhone Support

## 1. 目的

Flutter製のdietappを、iOS Simulatorではなく実際のiPhoneへインストールし、
Railway上のProduction APIへHTTPSで接続して利用できる状態にする。

本Specでは、実機iPhoneでのビルド・署名・起動・Production API接続・主要記録フローの確認までを対象とする。

## 2. 背景

Spec016で以下を完了した。

- RailwayへFastAPIをProduction Deployment
- Railway PostgreSQLへProduction DBを構築
- Alembic migrationをProduction DBへ適用
- HTTPS公開ドメインを発行
- `GET /health` がProduction環境で200
- Flutter iOS SimulatorからProduction APIへ接続
- Simulatorから体重記録を保存し、Home / Historyへ反映

次の段階として、実際のiPhoneで同じProduction環境へ接続できることを確認する。

## 3. ゴール

実機iPhone上でdietappを起動し、Railway Production APIを利用して主要機能を正常に操作できる。

完了時の経路:

```text
Physical iPhone
    ↓ HTTPS
Railway FastAPI
    ↓ private DATABASE_URL
Railway PostgreSQL
```

## 4. In Scope

### 4.1 iOS実機ビルド環境

- MacとiPhoneをUSBまたはAppleが提供する実機デバッグ手段で接続する
- Xcode / Flutterから実機iPhoneを認識できることを確認する
- iOS Developer Modeが必要な場合は有効化する
- Apple ID / Development TeamをXcodeへ設定する
- Development signingでアプリを実機へインストールできるようにする
- Bundle Identifierが実機署名で利用可能な一意の値であることを確認する

### 4.2 Production API設定

Flutter起動時に以下を使用する。

```sh
--dart-define=API_BASE_URL=https://dietapp-production-4895.up.railway.app
```

要件:

- Production URLをソースコードへハードコードしない
- `API_BASE_URL`の既存仕組みを利用する
- HTTPではなくHTTPSを使用する
- ATSを無制限に緩和しない
- Production secretsをFlutterアプリへ埋め込まない

### 4.3 実機動作確認

実機iPhoneで最低限以下を確認する。

- アプリが起動する
- Homeが表示される
- Production APIとの通信エラーがない
- 体重を保存できる
- 食事を保存できる
- Free Dayを設定できる
- 体調を保存できる
- 注射記録を保存できる
- Homeへ反映される
- Historyへ反映される
- 体重グラフが表示される
- Settingsが表示される

### 4.4 Productionデータ確認

実機から保存したデータがProduction API / Production PostgreSQLへ保存されることを確認する。

Simulatorのローカル開発環境やDocker Compose PostgreSQLへ誤って保存されていないことを確認する。

## 5. Out of Scope

本Specでは以下を実装しない。

- App Store公開
- TestFlight配信
- Apple Developer Program有料登録を前提とする配布機能
- Ad Hoc Distribution
- App Store Connect設定
- Release build配布
- CI/CDによるiOS自動ビルド
- Push通知
- Background fetch
- Authentication
- Keychainを必要とする新規認証情報
- Apple Health / HealthKit
- Health Connect
- Offline sync
- Production API URLのアプリ内設定画面
- Flutter flavor構成の大規模導入
- Bundle IDやアプリ名の不要な変更
- UI/UX改善
- 新機能追加

これらは必要に応じて後続Specで扱う。

## 6. 安全要件

- 注射量は医師等から指示された値を記録するだけとする
- アプリから投与量変更を提案しない
- 強い症状がある場合は医療機関への相談を促す既存方針を維持する
- カロリー・タンパク質の目標値や過度な摂取制限を追加しない
- Free Dayは栄養計算を意図的に行わない日として扱い、過食・代償行動を促す表現を追加しない

## 7. 実装方針

### 7.1 既存iOS scaffoldを優先

Spec015で生成済みの標準Flutter iOS scaffoldを利用する。

不要なiOS nativeコードや大規模な設定変更は行わない。

### 7.2 Signing

XcodeのRunner targetでDevelopment signingを設定する。

基本方針:

- Automatically manage signingを優先
- Development Teamはユーザー自身のApple ID / Teamを使用
- Signing certificateやProvisioning ProfileをGitへコミットしない
- `.xcconfig`等にApple IDや秘密情報を書かない

### 7.3 Bundle Identifier

既存Bundle IdentifierがDevelopment signingで使用できない場合のみ変更を許可する。

変更する場合:

- 一意のreverse-DNS形式にする
- iOS実機署名のために必要な最小変更に限定する
- 変更内容を報告する
- Androidその他のplatform identifierを不要に変更しない

### 7.4 API接続

既存の`API_BASE_URL`注入方式をそのまま利用する。

例:

```sh
flutter run   -d <physical-iphone-device-id>   --dart-define=API_BASE_URL=https://dietapp-production-4895.up.railway.app
```

Production URLをGit管理ファイルへ固定値として追加しない。

## 8. 実機セットアップ手順

### 8.1 iPhoneをMacへ接続

1. iPhoneをMacへ接続
2. iPhone側で「このコンピュータを信頼」を承認
3. Mac側でも必要な確認を許可
4. iPhoneのロックを解除した状態で認識を確認

### 8.2 Flutter認識確認

```sh
flutter devices
```

実機iPhoneが一覧へ表示されること。

必要に応じて:

```sh
flutter doctor -v
```

### 8.3 Developer Mode

iOSが要求する場合:

```text
設定
→ プライバシーとセキュリティ
→ デベロッパモード
```

を有効化する。

再起動や確認操作が要求された場合はiPhone上で完了する。

### 8.4 Xcode Signing

```sh
open ios/Runner.xcworkspace
```

Xcodeで:

```text
Runner
→ TARGETS: Runner
→ Signing & Capabilities
```

を開く。

確認項目:

- Automatically manage signing
- Team
- Bundle Identifier
- Signing Certificate

### 8.5 実機起動

Flutter CLIから実機を指定して起動する。

```sh
flutter run   -d <DEVICE_ID>   --dart-define=API_BASE_URL=https://dietapp-production-4895.up.railway.app
```

## 9. 受け入れ基準

### AC-01
`flutter devices`で実機iPhoneが認識される。

### AC-02
Xcode signingがDevelopment用途で成立する。

### AC-03
`flutter run`で実機iPhoneへアプリをインストールできる。

### AC-04
実機iPhoneでアプリが起動し、起動直後にクラッシュしない。

### AC-05
Production API URLは`--dart-define=API_BASE_URL=...`から注入される。

### AC-06
Production URLがFlutterソースへハードコードされていない。

### AC-07
実機からProduction API接続が成立する。

### AC-08
HomeがAPIエラーなく表示される。

### AC-09
実機から体重を1件保存できる。

### AC-10
保存した体重がHomeへ反映される。

### AC-11
保存した体重がHistoryへ反映される。

### AC-12
食事記録を保存できる。

### AC-13
Free Dayを設定できる。

### AC-14
体調記録を保存できる。

### AC-15
注射記録を保存できる。

### AC-16
体重グラフが表示される。

### AC-17
Settingsが表示される。

### AC-18
実機から保存したデータがProduction PostgreSQLへ保存される。

### AC-19
開発用Docker Compose PostgreSQLへ誤保存されていない。

### AC-20
ATSの無制限許可を追加していない。

### AC-21
Production secret / Apple credential / signing secretをGitへコミットしていない。

### AC-22
既存backend API contract・DB schema・Alembic migrationに変更がない。

### AC-23
既存Flutter automated testsがPASSする。

### AC-24
`flutter analyze`がPASSする。

### AC-25
`git diff --check`がPASSする。

## 10. Verification Commands

実装変更が発生した場合:

```sh
cd mobile
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

Repository root:

```sh
git diff --check
git status
```

実機確認:

```sh
flutter devices

flutter run   -d <DEVICE_ID>   --dart-define=API_BASE_URL=https://dietapp-production-4895.up.railway.app
```

## 11. STOP条件

以下が必要になった場合は勝手に進めず停止して報告する。

- Apple Developer Programの有料契約
- App Store Connectの操作
- 新規有料サービス
- Production DBへの破壊的操作
- DB schema / migration変更
- Backend API contract変更
- Authentication追加
- Production secretのGit管理
- ATSの無制限許可
- 大規模なiOS native実装
- Bundle Identifier以外の広範囲なproject rename
- 新規package / pluginの追加が必要
- Productionデータの削除

## 12. Codex実行ルール

Codexは以下を守る。

1. `AGENTS.md`を読む
2. 本Specを読む
3. 関連する既存iOS / Flutter設定を確認する
4. Spec017の範囲だけを扱う
5. 不要な変更を行わない
6. 実機操作が必要な部分はユーザー操作として明確に分離する
7. Apple credentialやsecretを要求・保存しない
8. 変更が必要な場合は最小差分にする
9. format / analyze / test / `git diff --check`を実行する
10. commit / pushは行わない
11. 最後に変更ファイル・実行コマンド・テスト結果・manual verification結果・未完了項目・STOP条件を報告する

## 13. Definition of Done

以下をすべて満たした時のみSpec017をDONEとする。

- 実機iPhoneがFlutter/Xcodeから認識される
- Development signingが成立する
- dietappを実機へインストールできる
- Production API URLをdart-defineで指定して起動できる
- Homeが正常表示される
- 体重・食事・Free Day・体調・注射を実機から操作できる
- History / 体重グラフ / Settingsが正常表示される
- 実機から保存したデータがProduction PostgreSQLへ保存される
- ATSを無制限に緩和していない
- secrets / signing credentialsをGitへ追加していない
- backend API / DB schema / migrationを変更していない
- Flutter tests / analyze / `git diff --check`がPASSする
