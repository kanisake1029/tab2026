# 引き継ぎ資料：NPBペナントアプリ 試合エンジンのバグ修正

## プロジェクト概要
- Flutter製のNPB風ペナントシミュレーション。パス: `C:\Users\kazum\.gemini\antigravity\scratch\npb_pennant_app`
- Flutter SDK: `C:\src\flutter\bin`（`dart` / `flutter` コマンド使用可）
- 1日の進行: `lib/providers/app_state.dart` の `playNextDay()` → `MatchSimulator.simulateMatch()`
- 保存: shared_preferences（JSON）。初期データ `lib/utils/initial_teams_data.dart`（1.5MB、読まなくてよい）
- 使用中のエンジン: `lib/engine/match_simulator.dart`, `pitch_physics.dart`, `physics_engine.dart`, `fielder_ai.dart`
- 未使用の旧エンジン（触らない）: `matchup_engine.dart`, `fielding_engine.dart`, `game_state.dart`, `test_*.dart`, `physics_logic.dart`

## 座標系・仕様
- 打球/守備: 本塁(0,0)、1塁(19.4,19.4)、2塁(0,38.8)、3塁(-19.4,19.4)、y=センター方向(m)、z=高さ
- 投球: y=18.44(投手)→0(本塁)。`targetX/targetZ` はストライクゾーン正規化座標（±1がゾーン端）だが、pitch_physics内ではメートルとして扱われている（要整理）
- 腕の角度 `spinAxis`: 0°=真上（不可能）、45°=スリークォーター(標準)、90°=サイド
- マウンド25cm。リリース高 = 0.25 + 身長×係数。左投げ releaseX=+0.5、右投げ -0.5
- 延長は最大12回。9回以降の裏、ホームがリードした時点で即サヨナラ終了
- 9回表終了時にホームがリード → 9回裏なし。9回以降の各回終了時に点差があれば試合終了
- スタミナ100で150球（`maxPitches = 30 + stamina*1.2`）
- ユーザーの意向：選球(eye)・勝負強さ(clutch/clutchPitching)も試合に効かせる

## バランス検査ツール（必ずこれで検証）
`dart run tool/balance_sim.dart 200`
オール60（弾道2、球速150km/h）チーム同士をメモリ上で200試合。セーブデータに触れない。

### 現状の結果（1チーム/1試合）
| 指標 | 現状 | 目標(NPB) |
|---|---|---|
| 得点 | 3.28 | 3.5〜4.0 |
| 安打 | 9.19 | 約8 |
| 本塁打 | 0.00 | 0.7〜0.9 |
| 三振 | 2.56 | 7〜8 |
| 四球 | 0.00 | 約3 |
| 打率 | .228 | .245〜.255 |
| 1打席あたり球数 | 2.09 | 3.7〜3.9 |
| 安打内訳 | 三塁打63% | 単打70% / 二塁打18% / 三塁打2% / 本塁打10% |

## 修正すべきバグ（1〜7）

1. **ほぼ全球ストライク**（match_simulator.dart 195-205行付近）
   `targetX/Z` が ±1 の一様乱数でゾーンと同範囲、制球60の誤差は ±0.06 のみ → ボール球が出ず四球0・初球打ち多発。
   → 投手は「ゾーン内/ゾーン際/釣り球」を狙い分け、制球で誤差を正規分布的に。ボール球率 約38〜40%を目標。
   スイング判断に選球(eye)を反映（ボール球スイング率 約30%、ゾーン内 約65%）。

2. **外野手が誤った地点へ走る**（fielder_ai.dart 108行 `landingSpot = ballTrajectory.last`）
   `.last` は転がって止まった地点。→ 最初に z<=0 となった点（第1バウンド地点）を落下地点にする。
   ゴロの場合は打球進路上の捕球可能地点へ向かうインターセプト計算に。

3. **ゴロが野手正面を素通り**（fielder_ai.dart 140行 `ballZ >= 0.2`）
   → 低い打球(z<0.2)でも距離1.5m以内なら捕球（ゴロ捕球）。ゴロ捕球後は一塁送球タイム vs 打者走塁タイムでアウト/内野安打判定（match_simulator 428-485行のロジックを流用）。
   CF初期位置 y=110 は深すぎ（実際は約95m）。LF/RFも要確認。

4. **ホームランが出ない**（match_simulator.dart 417行 `trajectory.last` かつ `landing.z > 0`）
   → 軌道上でフェンス距離 `PhysicsConstants.getFenceDistance(角度)` を越えた瞬間の高さ > フェンス高(3m)ならHR。
   physics_engine の打球にフェンス判定がないので simulateTrajectory 側で検出するのが良い。

5. **カウントが次打者に持ち越し**（match_simulator.dart 三振・四球の `continue` 経路）
   289-292行・337-340行で `continue` してループ終了 → 579行の `state.resetCount()` を通らない。
   → 打席開始時（121行の while の前）に `state.resetCount()`。

6. **試合終了判定とイニング配列**
   - 94行の while: 9回裏終了後にアウェイがリードしていても延長に入る。→ 各イニング終了時（表裏完了時）に `inning>=9 && 点差あり` で終了。12回終了で同点なら引き分け。
   - MatchState.addOut の `homeInningScores.add(0)` が毎回実行され配列が約18列に。→ `inning > length` のときだけ追加。
   - 投手成績 `inningsPitched += 27` 固定・`ip: 9` 固定も実際の回数に（余裕があれば）。

7. **当たりすぎ（空振り・ファウル不足）**（pitch_physics.dart calculateBatOffset / match_simulator 325-355行）
   ズレのノイズが小さく R>0.069 になりにくい。ファウル判定 |水平角|>45° も起きにくい。
   → 空振り率（スイング中）約20〜25%、ファウル率（スイング中）約35〜40% を目標に調整。
   ファウルフライアウトも追加すると良い。キレ・変化量・緩急・ミートが効くこと。

## 進め方
1. 5・6（単純バグ）→ 4 → 2・3（守備）→ 1・7（投打バランス）の順で修正
2. 各段階で `dart run tool/balance_sim.dart 200` を実行し、表の目標に近づける
3. 最後に `flutter analyze lib/engine` でエラーがないこと確認
4. 実況ログ（pitchLog の書式）は既存の詳細形式を維持すること
