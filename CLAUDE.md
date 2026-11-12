# CLAUDE.md — プロジェクト引き継ぎ・共同開発ガイド

このリポジトリは **Claude Code と Antigravity の共同開発** で管理されています。
作業を始める前に、まず最新の Git 履歴（`git log -n 10 --oneline` / `git show <commit>`）を確認して直近の変更内容を把握してください。

## リポジトリ・リリース構成
- **GitHub リポジトリ**: `https://github.com/kanisake1029/tab2026.git`（ブランチ: `main`）
- **GitHub Pages (PWA)**: `main` ブランチのルート（`/`）をそのまま公開しています（URL: `https://kanisake1029.github.io/tab2026/`）。
  - Web を更新する場合は、ビルド後に `build/web/*` をプロジェクトルートへコピーしてコミットしてください。
  - Webビルドコマンド（Wasm 有効化）:
    `flutter build web --release --wasm --base-href /tab2026/`
- **Android APK フレーバー**（`android/app/build.gradle.kts`）:
  - `pub`: 配布用リリース版（`flutter build apk --release --flavor pub` → `build/app/outputs/flutter-apk/app-pub-release.apk`）
  - `dev`: 開発者版（AI寸評あり）
  - `dbg`: デバッグ版（別アプリケーションID `.dbg`）

## 直近の主な変更（v1.0.4 / Antigravity による修正）
詳細なコード差分は `git log cca8678..HEAD` を参照してください。

1. **1年目終了後のオフ（2回目）のFAが行われない不具合の修正** (`fd637fe`)
   - `lib/providers/offseason_ops.dart`: `_faDeclare()` の実行条件に `if (played)` を追加し、宣言日に `faCases = [];` を確実に行うよう修正。自動修復用 `ensureFaDeclaredIfNeeded()` を追加。
   - `lib/providers/app_state.dart`: `_rollover()` と `_newYearDay()` でのクリーンアップ、および `loadData()` 時の過去セーブデータ修復を追加。
   - `lib/screens/reinforce_screens.dart`: `_FaScreenState.initState()` で `ensureFaDeclaredIfNeeded()` を呼び出すよう対応。

2. **バージョン表記と配布物の更新** (`8f53b76`)
   - `pubspec.yaml`: `1.0.4+5`
   - `lib/screens/slot_screen.dart` / `lib/screens/start_screen.dart`: タイトル下に `v1.0.4` を表示。

3. **PWA（Web / iOS・Chrome）の Wasm 対応と高速化** (`f0e9369`, `b4a8a4c`, `ce5fdc9`)
   - `web/flutter_bootstrap.js` / `web/index.html`: Chrome (`blink`)・iOS (`webkit`) 等で Wasm (`skwasm`) を有効化、旧 Service Worker を自動解除、起動画面にロードステップと経過時間を表示（`?js=1` で JS モードにフォールバック可能）。
   - `lib/db/app_database.dart`: `setKvBatch()` を追加し、KV 保存を 1 トランザクションに統合。
   - `lib/providers/app_state.dart` / `lib/screens/slot_screen.dart`:
     - `SlotScreen` での不要な 3 スロット連続 DB オープンを廃止（`SharedPreferences` の `slotSummary_$n` を優先）。
     - 空スロットからの「新しく始める」時に `deferWorldGen: true` を使い、開始決定（`resetToInitialTeams()`）まで重い他リーグ・アマチュア生成や DB 書き込みを先送り。
     - `loadData()` 内のマイグレーション保存を 1 回に統合し、1.5MB の初期 JSON 整形結果（`_cleanedInitialCache`）をキャッシュ。
     - `_templatesFromOtherSlots()` で空の他スロット DB を開かないよう改善。

## 注意事項
- `backup/`, `*.sqlite`, `*.db`, `*.apk` は `.gitignore` で除外されています（100MB超ファイルを GitHub へプッシュしないため）。
- コードを変更した際は `flutter analyze` および関連する `flutter test` を実行し、変更内容をわかりやすくコミットメッセージに残してください。
