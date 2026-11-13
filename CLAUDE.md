# CLAUDE.md — プロジェクト引き継ぎ・共同開発ガイド

このリポジトリは **Claude Code と Antigravity の共同開発** で管理されています。
作業を始める前に、まず最新の Git 履歴（`git log -n 10 --oneline` / `git show <commit>`）を確認して直近の変更内容を把握してください。

## リポジトリ・リリース構成
- **GitHub リポジトリ**: `https://github.com/kanisake1029/tab2026.git`（ブランチ: `main`）
- **GitHub Pages (PWA)**: `main` ブランチのルート（`/`）をそのまま公開しています（URL: `https://kanisake1029.github.io/tab2026/`）。
  - Web を更新する場合は `tool/deploy_web.ps1`（ビルドして `build/web/*` をルートへコピー。コミットとプッシュは自分で行う）。
  - Webビルドコマンド（Wasm 有効化）:
    `flutter build web --release --wasm --base-href /tab2026/`
  - ルートの `index.html`・`main.dart.js`・`canvaskit/`・`assets/AssetManifest*` などはビルド成果物（コミットのたびに数MBの差分になる）。成果物だけを `gh-pages` ブランチに分けたいときは `tool/deploy_web.ps1 -Target gh-pages`（GitHub の Settings → Pages → Branch を `gh-pages` に1度変更する必要あり）。
- **Android APK フレーバー**（`android/app/build.gradle.kts`）:
  - `pub`: 配布用リリース版（`flutter build apk --release --flavor pub` → `build/app/outputs/flutter-apk/app-pub-release.apk`）
  - `dev`: 開発者版（本番セーブが入っているアプリ。AI寸評は 2026-10-26 に全版で無効にした）
  - `dbg`: デバッグ版（別アプリケーションID `.dbg`・セーブも別）

## S25 への入れ方（セーブを消さない）
実機は Galaxy S25（adb の ID `RFCY41FEAKJ`）。dev（本番セーブ）と dbg を入れている。
1. `flutter build apk --release --split-per-abi --flavor dev`（dbg も同様）
2. `adb -s RFCY41FEAKJ install -r build/app/outputs/flutter-apk/app-arm64-v8a-dev-release.apk`
- **`flutter install` は使わない**（入れる前にアンインストールされて、セーブが消える）。
- **`pub` を S25 に入れない**（dev と同じアプリID。開発者版の表示などが上書きされる）。
- **dev の本番セーブで試合を進めない**。試すときは dbg か、PC 上のコピーで。
- 入れる前に、実機のセーブを取り出しておく（debug 版を入れて `adb exec-out run-as com.example.npb_pennant_app cat app_flutter/npb_pennant.sqlite`）。`backup/` に置く（Git には上げない）。
- 署名：dev・dbg はデバッグ鍵のまま（鍵を変えると、入っているアプリに上書きできずセーブが消える）。pub だけ `android/key.properties` があればその鍵で署名する（未作成。作る前に、すでに配った APK の利用者が上書き更新できなくなることを確認する）。

## セーブデータ（sqlite / drift）
- 表: `kv_entries`（設定・世界のデータ）、`team_rows`（球団＋選手のJSON）、`match_rows`（試合）、`season_records`（年度の成績）、`pitch_rows`（1球ごとの記録）、`prospect_rows`（ドラフト候補。スキーマ3から1人1行。以前は kv の `prospects` に1つのJSON）。
- スキーマを変えるとき: `dart run build_runner build --delete-conflicting-outputs`、`onUpgrade`、そして旧形式のセーブで読み直せることを `test/db_migration_test.dart`（`backup/` の実機セーブが要る。無ければ飛ばす）で確かめる。
- **自動の控え**：ドラフト会議・年度替わり・契約更改の直前に、詰めた形（`VACUUM INTO`）で3世代まで残す（アプリの書類フォルダの `backups/`）。スロット画面の「控え」から戻せる（戻す前の状態も残る）。
- **空きページの整理**：起動時と年度替わりのあと、空きページが30%以上なら `VACUUM`（実機のセーブは 124MB → 30MB）。プレイデータを消去したときも詰める。
- **1球ごとの記録**（`pitch_rows`）：自球団の試合ぶん（1シーズン約3.4MB。他球団も記録する設定なら約20MB）。終わった2シーズン（他球団も記録しているときは1シーズン）ぶん残し、それより古いものは年度替わりに消す。試合の実況テキストは、シーズンが終わると外す（スコア・ボックススコア・選手の成績は残る）。対戦成績と「アニメで振り返る」は、今季ぶんだけを使う。
- `test/db_maintenance_test.dart`：詰める・控え・復元・候補の表・1球の保持のテスト。

## 検証（バランス）
- `tool/balance/zz_*_test.dart`：環境変数で値を変えながら、リーグの打率・本塁打・三振などを測る（`flutter test tool/balance/zz_balance_probe_test.dart --dart-define=DAYS=60` など）。実機のセーブのコピー（`backup/`）を使うものがある。
- 長い検証（数分〜）は、裏で動かすと省電力コアに回されて3〜5倍遅くなる。`tool/ft.sh`（PowerShell なら Git Bash 経由）で `flutter test` を包むと、高性能コアに固定できる。マスクは Core i7-14700F 用（`FT_MASK` で変える）。
- 試合の集計（`MatchSimulator.debugStats`）は、普段は止めている。使うときは `MatchSimulator.startStats()`（終わったら `collectStats = false`）。
- バランスの考え方（`docs/batter_response_spec.md` §8〜9）：打者（ミート・パワー・選球眼）と投手（球速・球威・制球など）は、同じ数字どうしで対戦すれば、30 でも 60 でも 90 でもリーグ平均（打率 .250 前後）になる（`MatchSimulator.levelCenter`）。能力の差は、打者が上回るとき 1あたり約 +.005、投手が上回るとき約 −.003。**守備と走塁は合わせない**（野手の処理の速さと走者の速さの勝負）。結果に合わせて相手の能力を直接いじる調整はしない。
- 守備・走塁の「この動作に何秒」は `lib/engine/fielding_times.dart` の表（能力 30・60・90 の値を決めて直線でつなぐ）。値を変えたら BABIP・失策・盗塁を検証で確かめる。

## ファイル構成のメモ
- `lib/engine/match_simulator.dart`：1試合の計算。`_paSteps`（1打席ごとの流れ）が約2000行の1つの関数で、分けていない。
- `lib/providers/app_state.dart` ＋ `*_ops.dart`（`part` ＋ `extension AppState`）：保存・読み込みは `save_ops.dart`、以前のセーブの修復は `repair_ops.dart`。拡張機能の中から `notifyListeners` は呼べないので `notifyChanged()` を使う。
- 古い一度きりのスクリプトは `archive/old_scripts/`（参照されていない）。新しいものは `tool/` に置く。
- リリース用の APK は `releases/`（Git には上げない）。

## 直近の主な変更（v1.0.4 / Antigravity による修正）
詳細なコード差分は `git log cca8678..HEAD` を参照してください。

1. **1年目終了後のオフ（2回目）のFAが行われない不具合の修正** (`fd637fe`)
   - `lib/providers/offseason_ops.dart`: `_faDeclare()` の実行条件に `if (played)` を追加し、宣言日に `faCases = [];` を確実に行うよう修正。自動修復用 `ensureFaDeclaredIfNeeded()` を追加。
   - `lib/providers/app_state.dart`: `_rollover()` と `_newYearDay()` でのクリーンアップ、および `loadData()` 時の過去セーブデータ修復を追加。
   - `lib/screens/reinforce_screens.dart`: `_FaScreenState.initState()` で `ensureFaDeclaredIfNeeded()` を呼び出すよう対応。
   - ※ このコミットには、同じ日に Claude Code が作業していた変更（下の「Claude による変更」）も一緒に入っている。

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

## Claude による変更（2026-11-09〜、v1.0.4 に含まれる）
- **盗塁の作り直し**：投球の速さ・高さ・コースと、捕手の送球・肩で決まる。走力 70/75/80/90 で年 5/10/15〜20/40〜50 盗塁。
- **投手の直し**：制球が悪いほど四死球が増える（S90 で与四死球率 約1.2、E40 で約4.5）。変化量・キレ・球威・失投が成績に効く。
- **打者の対応モデル**（`docs/batter_response_spec.md`）：待ち球・緩急・変化量・チャンス/ピンチ、打者と投手の能力の基準合わせ。
- **タイトル水準の調整**：本塁打・打点を下げた（`Spec.attK` 1.8、`Spec.batB` 0.12 ほか）。
- **ドラフト**：支配下の空きが少ないときの確認、「やり直す」ボタン、本指名は枠が許す限り何人でも（巡の上限 70）。

## 注意事項
- `backup/`, `*.sqlite`, `*.db`, `*.apk` は `.gitignore` で除外されています（100MB超ファイルを GitHub へプッシュしないため）。
- コードを変更した際は `flutter analyze` および関連する `flutter test` を実行し、変更内容をわかりやすくコミットメッセージに残してください。
- Windows では作業フォルダの改行が CRLF になる（`core.autocrlf`）。ファイルを機械的に書き換えるスクリプトは、改行の違いで照合が外れないようにする。
