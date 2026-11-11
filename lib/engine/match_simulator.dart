import 'dart:math';
import 'pitch_catalog.dart';
import 'condition_engine.dart';
import 'velo.dart';
import '../models/team.dart';
import '../models/player.dart';
import '../models/league_rules.dart';
import 'pitch_physics.dart';
import 'pitch_engine.dart';
import 'vec3.dart';
import 'environment.dart';
import 'weather.dart';
import 'swing_model.dart';
import 'field_time.dart';
import 'tactics.dart';
import 'ball_spec.dart';
import '../models/stadium.dart';
import '../utils/schedule_generator.dart';
import 'physics_engine.dart';
import 'fielder_ai.dart';
import 'play_resolver.dart';
import 'defense_ai.dart';
import 'spec_constants.dart';

/// 2点間の距離（pow を使わない分だけ速い）
double _hypot(double a, double b) => sqrt(a * a + b * b);

class MatchState {
  int inning = 1;
  bool isTop = true;
  int outs = 0;
  int strikes = 0;
  int balls = 0;
  int homeScore = 0;
  int awayScore = 0;

  String? runner1B;
  String? runner2B;
  String? runner3B;

  List<int> homeInningScores = List.filled(9, 0, growable: true);
  List<int> awayInningScores = List.filled(9, 0, growable: true);

  int homeDefenseOuts = 0; // ホーム投手が奪ったアウト数
  int awayDefenseOuts = 0;

  /// 表示用のコピー（アニメーション中のスコアボードを止めておくため）
  MatchState copy() {
    final c = MatchState()
      ..inning = inning
      ..isTop = isTop
      ..outs = outs
      ..strikes = strikes
      ..balls = balls
      ..homeScore = homeScore
      ..awayScore = awayScore
      ..runner1B = runner1B
      ..runner2B = runner2B
      ..runner3B = runner3B
      ..homeDefenseOuts = homeDefenseOuts
      ..awayDefenseOuts = awayDefenseOuts;
    c.homeInningScores = List.of(homeInningScores, growable: true);
    c.awayInningScores = List.of(awayInningScores, growable: true);
    return c;
  }

  void addOut() {
    outs++;
    if (isTop) { homeDefenseOuts++; } else { awayDefenseOuts++; }
    if (outs >= 3) {
      outs = 0;
      runner1B = null;
      runner2B = null;
      runner3B = null;
      resetCount();
      if (isTop) {
        isTop = false;
      } else {
        isTop = true;
        inning++;
        while (inning <= 12 && homeInningScores.length < inning) {
          homeInningScores.add(0);
          awayInningScores.add(0);
        }
      }
    }
  }

  void addStrike() { strikes++; }
  void addBall() { balls++; }
  void resetCount() { strikes = 0; balls = 0; }
  void addScore(int runs) {
    if (isTop) {
      awayScore += runs;
      if (inning <= awayInningScores.length) awayInningScores[inning - 1] += runs;
    } else {
      homeScore += runs;
      if (inning <= homeInningScores.length) homeInningScores[inning - 1] += runs;
    }
  }
}

/// 1球ごとの構造化記録（ストライクゾーン図・グラウンド図の描画用）
class PitchEvent {
  final int paIndex;          // 何打席目か（試合通算）
  final int pitchNo;          // 打席内の球数
  final bool battingHome;     // 攻撃側がホームか
  final String batter;
  final String batterHand;    // 'R' / 'L' / 'S'
  final String pitcher;
  final String pitchName;
  final double speed;
  final double x;             // ゾーン正規化座標（±1=ゾーン端。+は投手から見て右）
  final double z;             // 同（+は高め）
  final bool inZone;
  final int balls;            // 投球前のカウント
  final int strikes;
  String result = '';         // 見逃し/ボール/空振り/ファウル/インプレー/バント
  String contact = '';        // ゴロ/ライナー/フライ/ポップフライ
  double? landX;              // 打球の落下・捕球地点（本塁(0,0)、+xが右翼側、+yが中堅方向 m）
  double? landY;
  double? launch;
  String fielder = '';        // 捕球・処理した野手（P/C/1B/2B/3B/SS/LF/CF/RF）
  String outcome = '';        // アウト/単打/二塁打/三塁打/ホームラン
  // ---- アニメーション用 ----
  List<List<double>> path = const [];             // 打球の軌跡 [x, y, z]（間引き済み）
  double flightTime = 0;                          // 軌跡を進む時間（秒）
  Map<String, List<double>> fielderStart = const {}; // 投球時の守備位置 role → [x, y]
  String throwTo = '';                            // 送球先（'1B' など。空なら送球なし）
  String desc = '';                               // この1球の結果テキスト
  List<RunMove> runMoves = const [];               // 走者の動き（打った瞬間=0 からの秒）
  List<ThrowLeg> throwLegs = const [];             // 送球（中継含む）
  String playCode = '';                            // 6-4-3 など
  String errorBy = '';                             // 失策した野手の役割（P/C/1B…。失策がなければ空）
  double breakDX = 0, breakDY = 0;                  // 変化球の曲がり（変化球ベクトル図と同じ向き。大きさ0〜1）
  PitchKind? phys;                                  // 3D 物理（リリース位置・回転・握り）。保存はしない
  PitchShot? shot;                                  // 3D 物理での打ち出しの向き・球速・回転の強さ
  DefensePlan? defense;                             // 9人の役割（捕る・ベースカバー・中継・カバー）。保存はしない
  Map<String, Player> fielderPlayers = const {};   // 守っていた9人（role → 選手）。保存はしない
  Player? batterPlayer;                            // 打者（3D 用。保存はしない）
  List<Player?> runnerPlayers = const [null, null, null]; // 打つ前の一塁〜三塁の走者（3D 用）
  double exitSpeed = 0, spray = 0;                 // 打球の初速（m/s）・左右の角度（°、＋＝右翼側）
  GameEnv? env;                                    // その試合の空気・風（3D 用）
  String call = '';                                 // 声の掛け合い（「CFがオーライ」「お見合い」）
  // ---- 実況用の場面（投球前と、この1球の後） ----
  int inning = 1;
  bool top = true;
  int outsBefore = 0, outsAfter = 0;
  List<bool> basesBefore = const [false, false, false], basesAfter = const [false, false, false];
  int offBefore = 0, defBefore = 0, offAfter = 0, defAfter = 0; // 攻撃側・守備側の得点
  int ballsAfter = 0, strikesAfter = 0;
  String batterToday = '';     // 打席に入る前の今日の成績
  int pitcherCount = 0;        // 投手のこの試合の球数（投球前）
  int logIndex = -1;           // 試合の記録（playByPlay）の何行目か
  // ---- ビジョン用（3D。保存はしない）：チーム名と打順（「守備位置|名前|背番号」を1番から） ----
  String homeName = '', awayName = '';
  String stadiumId = 'std'; // この試合の球場
  // 盗塁（この1球と同時に走った）：元の塁（1＝一塁から二塁へ、2＝二塁から三塁へ。0＝なし）と成否
  int stealFrom = 0;
  bool stealSafe = false;
  List<String> homeLine = const [], awayLine = const [];
  PitchEvent({required this.paIndex, required this.pitchNo, required this.battingHome, required this.batter, required this.batterHand, required this.pitcher, required this.pitchName, required this.speed, required this.x, required this.z, required this.inZone, required this.balls, required this.strikes});
}

/// 1打席ずつ進められる試合の進行状態
class GameSession {
  final Match match;
  final Team homeTeam;
  final Team awayTeam;
  final MatchState state = MatchState();
  /// その試合の空気・風（球場と日付から。同じ試合はいつも同じ）
  /// この試合の球場（ホーム球団の本拠地）
  late final Stadium stadium = homeTeam.park; // 改修（テラス・フェンス・芝）も反映
  /// この試合の天候（球場の所在地と日付から。屋根の種類で効き方が変わる）
  late final GameWeather weather = GameWeather.of(stadium, homeTeam.homePrefecture, match.date, seed: DailyWeather.saveSeed);
  late final GameEnv env = GameEnv.forGame(stadium, match.date, seed: (match.homeTeamId + match.awayTeamId).codeUnits.fold(0, (a, c) => (a * 31 + c) & 0x7fffffff), weather: weather);
  final Map<String, int> gamePitchCounts = {};   // 実際の球数（表示用）
  final Map<String, double> staminaUsed = {};    // スタミナ消費量（打たれたイニングは1球1.5）
  final Map<String, String> roughedInning = {};  // 投手ごとに、安打・四球・失点を許したイニング（例 '5回表'）
  Player homePitcher;
  Player awayPitcher;
  final List<Player> homeOrder;
  final List<Player> awayOrder;
  int homeBatterIndex = 0;
  int awayBatterIndex = 0;
  int homeHits = 0;
  int awayHits = 0;
  final List<String> playByPlay = [];
  final List<String> pitchByPitch = [];
  final List<PitchEvent> pitchEvents = [];
  int paCount = 0; // 開始した打席数
  final Map<String, dynamic> boxScore = {
    'homeBatters': <String, dynamic>{},
    'awayBatters': <String, dynamic>{},
    'homePitcher': <String, dynamic>{},
    'awayPitcher': <String, dynamic>{},
  };
  String lastInningStr = '';

  // 試合用のコピー（Team.lineup を恒久変更しない）。打順スロットiと守備位置が対応する
  final List<LineupEntry> homeLineup;
  final List<LineupEntry> awayLineup;
  final Set<String> injuredNow = {};          // この試合で怪我をした選手
  final List<String> injuryNews = [];          // 試合中の怪我のお知らせ（試合後にまとめて出す）
  final Set<String> usedIds = {};              // 一度でも出場した選手（交代後の再出場不可）
  final List<Player> homeAppeared = [];        // 出場した野手
  final List<Player> awayAppeared = [];
  final List<Player> homePitchers = [];        // 登板した投手（先発が先頭）
  final List<Player> awayPitchers = [];
  final Map<String, int> pitcherOuts = {};     // 投手ごとのアウト数

  // ---- 1球ずつ進めるための状態 ----
  Iterator<PaPause>? paIter;       // 進行中の打席（null なら打席の間）
  AtBatPlan? livePlan;             // 打席中に差し替えられる采配（1球ごとに読み直す）
  PitchCommand pitchCommand = PitchCommand.none; // 次の1球だけの指示（待て・外せ）
  bool threeBunt = false;          // 2ストライクからバントを続けるか（スリーバント）
  bool get inPlateAppearance => paIter != null;

  GameSession(this.match, this.homeTeam, this.awayTeam, this.homePitcher, this.awayPitcher, this.homeOrder, this.awayOrder, this.homeLineup, this.awayLineup);

  // ---- 勝敗・セーブ・ホールドの判定用 ----
  final Map<String, List<int>> pitcherEntry = {}; // 登板したときの [自軍の得点, 相手の得点]
  final Map<String, List<int>> pitcherExit = {};  // 降板したときの [自軍の得点, 相手の得点]
  int lastLeader = 0;                              // 1=ホームがリード, -1=ビジターがリード, 0=同点
  final Map<int, Player> winCand = {};             // リードを奪ったときの、その球団の投手（勝利投手の候補）
  final Map<int, Player> loseCand = {};            // リードを奪われたときの、決勝点の走者を出した投手（敗戦投手の候補）
  final Map<String, List<String>> inherit = {};    // 投手 id → 塁上の走者を出した投手の id（先の塁から。引き継いだ走者の責任）
  final Map<String, int> pitcherEntryRunners = {}; // 登板したときの塁上の走者の数（セーブ・ホールドの「同点の走者が塁上・打席・次打者」）
  // 打席の始まり（得点の責任・リードの入れ替わりを打席の終わりに確かめる）
  bool paTop = true;
  int homeSB = 0, awaySB = 0; // 盗塁の数（チーム成績用）
  int paDefOuts = 0; // 打席の始まりの守備側のアウトの数（守備イニングを守備位置ごとに数える）
  final Map<String, Map<String, int>> posOuts = {}; // 選手 id → 守備位置 → 守ったアウトの数
  int paHome = 0, paAway = 0, paDefEr = 0;
  Player? paDef;

  Player? get starterHome => homePitchers.isEmpty ? null : homePitchers.first;
  Player? get starterAway => awayPitchers.isEmpty ? null : awayPitchers.first;

  // ---- 配球の駆け引き（投手と打者の対戦の記憶） ----
  final Map<String, int> battersFaced = {};          // 投手ごとの対戦打者数（打者一巡の判定）
  final Map<String, int> paVs = {};                  // 「投手ID|打者ID」→ これまでの対戦打席数
  final Map<String, double> insideAware = {};        // 「投手ID|打者ID」→ 打者の内角への意識（+1 内角を強く意識 〜 −1 外角に意識）
  final Map<String, Set<String>> seenPitches = {};   // 「投手ID|打者ID」→ 打者が見た球種
  final Map<String, Set<String>> shownPitches = {};  // 投手ごとに、この試合で投げた球種
  final Map<String, int> forcedRuns = {};             // 押し出しで還った走者（登録名 → 回数。得点の記録用）

  // ---- 自分が采配する試合 ----
  String? userTeamId;               // 自球団（CPU 側だけ CPU 監督の作戦を使う）。null なら両方 CPU
  FieldTactic cpuField = FieldTactic.none; // 次の打席の CPU の守備（打席の前に決めて、画面に見せる）
  int cpuFieldPa = -1;              // cpuField を決めた打席の番号
}

/// 1球の配球（球種と狙い所）
class PitchCall {
  final Pitch pitch;
  final double x, z;    // 狙い所（ゾーン正規化座標。±1 がゾーン端。x は打者の内角が +）
  final bool zone;      // ストライクを取りにいく球か
  final String note;    // 実況に添える一言（見せ球・初披露など）
  const PitchCall(this.pitch, this.x, this.z, this.zone, [this.note = '']);
}

/// 1球ごとの指示（次の1球だけ有効）
enum PitchCommand { none, take, pitchOut }

/// 打席の途中で止まる理由
enum PaPauseKind { afterPitch, threeBunt }

class PaPause {
  final PaPauseKind kind;
  final PitchEvent? event; // afterPitch: 直前の投球
  const PaPause(this.kind, [this.event]);
  /// 1人ずつ進めるモードでも止めるべき場面か
  bool get important => kind != PaPauseKind.afterPitch;
}

/// 打撃采配
enum BatTactic { none, pullRight, bunt, squeeze, powerSwing, flyBall, patient, lowBall, highBall, fastballFocus, breakingFocus, contactSwing, oppositeField, pullHit, chopDown, firstPitch }

/// 走塁采配
enum RunTactic { none, steal, hitAndRun, aggressive, cautious }

/// 投手采配
enum PitchTactic { none, groundOut, strikeout, doublePlay, intentionalWalk, fullPower, controlFocus, insideAttack, outsideFocus, fastballMain, breakingMain }

/// 守備采配
enum FieldTactic { none, powerGuard, infieldIn, doublePlayShift, infieldBack, pullShift, oppositeShift }

/// 1打席ぶんの作戦指示（攻撃時は bat+run、守備時は pitch+field を使う）
class AtBatPlan {
  final BatTactic bat;
  final RunTactic run;
  final PitchTactic pitch;
  final FieldTactic field;
  /// 投球コース：5×5のマス（打者から見て、左上から1〜25）。真ん中の3×3（7・8・9・12・13・14・17・18・19）がストライクゾーン
  final int? targetCol;    // 0〜4：内角のボール → 内 → 真ん中 → 外 → 外角のボール
  final int? targetRow;    // 0〜4：高めのボール → 高 → 真ん中 → 低 → 低めのボール
  final String? pitchName; // 球種指定
  const AtBatPlan({this.bat = BatTactic.none, this.run = RunTactic.none, this.pitch = PitchTactic.none, this.field = FieldTactic.none, this.targetCol, this.targetRow, this.pitchName});
  bool get hasTarget => targetCol != null && targetRow != null;
  /// ボール球のマス（外側の一回り）
  bool get ballTarget => hasTarget && (targetCol! % 4 == 0 || targetRow! % 4 == 0);
}

class MatchSimulator {
  /// バットに当たる位置（本塁の後ろの角から投手の方へ m。本塁の前縁は 0.43）
  static const contactY = 0.55;
  /// 打球の出発点（結果の計算）：2＝実際のコース（既定）、0＝本塁上 1m（旧既定）。
  ///  以前は本塁上から出すと、打った瞬間のボールが捕手の手の届く範囲に入り、守備の役割分担が効かなくなっていた（fielder_ai.dart で修正）。3D の再生は投球の来た点から出す
  static int hitStartMode = 2;
  /// 打球の初速の基準（バット速度 m/s・パワー60のとき）。リーグ全体の本塁打・打率を合わせるための調整値（固有12の初期データで 本塁打≒1.0/チーム試合・打率≒.250 になる値。2026-10 調整）
  static double batSpeedBase = 40.2; // 打球の物理を実測に合わせたあとの仮の値（第2・3段階で打撃と守備をまとめて調整し直す）
  static double heavyRef = 55;    // 球種の重さの基準
  static double heavyEffect = 0.5; // 重さ1あたり球威に換算
  /// 球威1ポイントあたりの打球速度の減り方（1軍の平均的な球威 68 を基準にする）
  static double pitchPowerEffect = 0.0012;
  /// パワー1ポイントあたりのスイング速度（m/s）。大きいほど長打力の差が出る
  static double powerSlope = 0.050;
  /// 芯を外したときの打球速度の下限（割合）。大きいほど詰まった当たりでも安打になりやすい
  static double mishitFloor = 0.46;
  /// バットと球のずれの倍率（小さいほど当てやすい＝三振が減る）
  static double contactEase = 0.83;
  /// 3D 物理で投球の到達点と終盤の変化を決める（false で以前の簡易計算）
  static bool usePhysics = true;
  /// 終盤の変化（直球との加速度の差）が打者の予測をずらす強さ
  static double lateBreakK = 0.08;
  /// 打撃も物理（読み → タイミング・芯ずれ → バットとボールの衝突）で決める
  static bool batPhysics = true;
  /// 打者の見積もりの癖（m）：球が実際より少し落ちると思って振る（以前の計算で全球にかかっていた分を引き継ぐ）
  static double perceiveZ = 0.015, perceiveX = -0.003;
  /// ボール球に手を出す基本の確率（小さいほど四球が増える）
  /// 投手がゾーンを狙う割合のずらし（全体）
  static double zoneAim = -0.04; // バランス検証で合わせた値（ゾーン内 約50%）
  /// 制球60を超えた1ごとに、ストライクを取りにいく割合を増やす分
  static double ctrlZoneK = 0.0025;
  /// 打者が直球系を待つ確率 = readFastBase + readFastMul × 直球系の割合
  static double readFastBase = 0.35, readFastMul = 0.65;
  /// 新しい打者の対応モデル（docs/batter_response_spec.md）を使うか
  static bool batterResponse = true;
  /// 検証用：1打席のループがこの回数を超えたら止めて状態を出す（0＝無効）
  static int debugLoopLimit = 0;
  /// チャンス1あたりの、得点圏での打者の能力（ミート・パワー・選球眼）の増減
  static double clutchBatK = 0.36;
  /// 能力の対戦の基準合わせ：打者（ミート・パワー・選球眼）と投手（球速・球威・制球）の水準の中間が 60 になるように、両方を同じだけずらして計算する。
  ///  能力の差はそのまま。同じ能力どうしなら 30 対 30 も 90 対 90 も 60 対 60 と同じ結果になる。表示・記録の球速は本当の値
  static bool levelCenter = true;
  /// 能力差の効きの強さ：中間からの差に掛ける倍率（1 で能力の差そのまま。小さいほど緩やか）
  static double levelGain = 1.0;
  /// 投手のほうが上のときの効きの強さ（エースでも被打率 .200 前後：1差で約 −.0033。打者が上のときは levelGain で 1差 約 +.005）
  static double levelGainP = 0.6;
  int _lvShift = 0;
  /// ピンチ1あたりの、得点圏での投手の能力（球速・球威・制球・キレ・変化量・重さ）の増減
  static double clutchPitK = 0.23;
  /// ゾーン内の球を振る基本の確率
  static double zoneSwingBase = 0.70;
  static double chaseBase = 0.20;
  static int pitchPowerRef = 74;
  /// 追い込まれてからのカット（ファウルで逃げる）の基本確率
  static double cutBase = 0.50;
  /// 盗塁の基本の成功率（走力60・捕手60・クイック50のとき）
  static double stealBase = 0.62;
  /// CPU が盗塁を仕掛ける頻度の倍率
  static double cpuStealRate = 0.8;
  /// 盗塁を仕掛ける確率の大きさ（走力90・標準の監督・無死か1死で、1打席あたりの確率）
  static double cpuStealCurve = 0.72;
  /// 走力による差のつき方：走力がこの値だけ上がると、走る確率が e 倍（小さいほど俊足の選手に盗塁が集まる）
  static double cpuStealExp = 11.0;
  /// 2球目以降に走る判断（1球あたり、最初の球の何倍か）
  static double cpuStealPerPitch = 0.8;
  /// 成功の見込みで走るかを選ぶ度合い：見込みが Sel0 以下ではほぼ走らず、Sel0＋SelW で標準
  static double cpuStealSel0 = 0.1, cpuStealSelW = 0.6;
  /// 芯を外した当たりがファウルになる確率
  static double foulBase = 0.40;
  /// 初球のストライクを見逃す分（スイング率から引く）
  static double firstPitchTake = 0.26;
  /// 検証用：全試合の投球数と打席数（1打席あたり球数の確認）
  static int statPitches = 0, statPa = 0;
  // 打撃の基準（2026-10-06 調整）：各リーグに3割5人前後・30本7人前後、首位打者.310以上・本塁打王30本以上になるように
  /// CPU 監督の傾向（球団ID → bunt/steal/bullpen/youth 0〜100）。自球団は含めない
  static Map<String, Map<String, int>> cpuStyles = {};
  /// 調子・体力・怪我による能力補正を使うか（バランス検証ツールでは false）
  final bool applyForm;
  MatchSimulator({this.applyForm = true});

  final Random _rand = Random();
  static final Map<String, int> debugStats = {};
  static const double _hSpread = 0.45; // 小さいほど打球が左右に散りファウルが増える
  static const double _vSpread = 1.3;  // 小さいほど打球角度が散る
  void _inc(String k) { debugStats[k] = (debugStats[k] ?? 0) + 1; }

  /// スタミナ消費の基準倍率。打たれたイニングは1球1.5消費し、平均すると約1.2倍になるため、上限もその分広げる
  static const double staminaScale = 1.2;

  /// 内野ゴロの送球エラーの起きやすさ（(1 − 送球/100) × これ）
  /// フェア・ファウルを打球の通り道で決める（false なら打ち出しの向き）
  static bool foulByPath = true;
  static double throwErrorBase = 0.18; // NPB の失策（1球団1試合あたり約0.5）に合わせた値
  /// 外野フライの落球の起きやすさ（(1 − 捕球/100) × これ）
  static double dropErrorBase = 0.02;

  /// その投手が質を保てるスタミナ消費量の上限（スタミナ100で約180 = 150球相当）
  static double staminaLimit(Player p) => (30 + p.stamina * 1.2) * staminaScale;
  double _gauss() {
    double u1 = 1.0 - _rand.nextDouble();
    double u2 = _rand.nextDouble();
    return sqrt(-2.0 * log(u1)) * cos(2.0 * pi * u2);
  }

  /// 試合を最後まで一気に進める（CPU同士・自動試合用）
  MatchResult simulateMatch(Match match, Team homeTeam, Team awayTeam) {
    final session = startGame(match, homeTeam, awayTeam);
    while (!isFinished(session)) {
      autoManage(session);
      stepPlateAppearance(session);
    }
    return finishGame(session);
  }

  GameSession startGame(Match match, Team homeTeam, Team awayTeam) {
    Player starterOf(Team t) {
      final id = t.todaysStarterId;
      if (id != null) {
        for (final p in t.players) { if (p.id == id) return p; }
      }
      return t.players.firstWhere((p) => p.isPitcher, orElse: () => t.players.first);
    }
    Player homePitcher = starterOf(homeTeam);
    Player awayPitcher = starterOf(awayTeam);

    // リーグ規定の DH：ホーム球団のリーグの規定に、両チームの試合用のオーダーを合わせる（1軍の試合だけ。2軍・球宴は DH あり）
    final real = homeTeam.roster1G.isNotEmpty && awayTeam.roster1G.isNotEmpty;
    final dh = LeagueRules.dhFor(homeTeam, match.matchType);
    List<LineupEntry> copyLineup(Team t, Player sp) => real ? LeagueRules.gameLineup(t, sp, dh) : t.lineup.map((l) => LineupEntry(playerId: l.playerId, position: l.position)).toList();
    final notes = <String>[];
    // 出られない選手（怪我で離脱中・1軍にいない）がオーダーにいたら、その試合だけ控えから出す（保存しているオーダーは変えない）
    List<LineupEntry> playable(Team t, List<LineupEntry> lu) {
      if (!real) return lu;
      final byId = {for (final p in t.players) p.id: p};
      final pool = t.active26.isNotEmpty ? t.active26 : t.roster1G;
      for (final e in lu) {
        if (e.position == '投') continue;
        final p = byId[e.playerId];
        if (p != null && !p.isInjuredOut && t.roster1G.contains(p.id)) continue;
        final used = {for (final x in lu) x.playerId};
        int apt(Player x) => switch (e.position) { '捕' => x.fieldC, '一' => x.field1B, '二' => x.field2B, '三' => x.field3B, '遊' => x.fieldSS, '左' => x.fieldLF, '中' => x.fieldCF, '右' => x.fieldRF, _ => 0 };
        final cands = [for (final id in pool) if (byId[id] != null && !byId[id]!.isPitcher && !used.contains(id) && !byId[id]!.isInjuredOut) byId[id]!]
          ..sort((a, b) => e.position == 'DH' ? (b.contact + b.power).compareTo(a.contact + a.power) : (apt(b) * 2 + b.contact).compareTo(apt(a) * 2 + a.contact));
        if (cands.isEmpty) continue;
        notes.add('【欠場】${t.name}: ${p?.registeredName ?? '？'}（${p == null ? '不在' : (p.isInjuredOut ? '怪我' : '登録抹消中')}）→ 今日は${cands.first.registeredName}が出場');
        e.playerId = cands.first.id;
      }
      return lu;
    }
    final homeLu = playable(homeTeam, copyLineup(homeTeam, homePitcher)), awayLu = playable(awayTeam, copyLineup(awayTeam, awayPitcher));
    List<Player> orderOf(Team t, List<LineupEntry> lu) => lu.isNotEmpty ? lu.map((l) => t.players.firstWhere((p) => p.id == l.playerId, orElse: () => t.players.first)).toList() : t.players.where((p) => !p.isPitcher).take(9).toList();
    List<Player> homeOrder = orderOf(homeTeam, homeLu);
    List<Player> awayOrder = orderOf(awayTeam, awayLu);
    final s = GameSession(match, homeTeam, awayTeam, homePitcher, awayPitcher, homeOrder, awayOrder, homeLu, awayLu);
    s.playByPlay.addAll(notes);
    s.homePitchers.add(homePitcher);
    s.awayPitchers.add(awayPitcher);
    s.pitcherEntry[homePitcher.id] = [0, 0];
    s.pitcherEntry[awayPitcher.id] = [0, 0];
    s.homeAppeared.addAll(homeOrder);
    s.awayAppeared.addAll(awayOrder);
    for (var p in [...homeOrder, ...awayOrder, homePitcher, awayPitcher]) { s.usedIds.add(p.id); }
    for (var p in homeOrder) { s.boxScore['homeBatters'][p.registeredName] = {'ab': 0, 'h': 0, 'hr': 0, 'rbi': 0, 'bb': 0, 'so': 0}; }
    for (var p in awayOrder) { s.boxScore['awayBatters'][p.registeredName] = {'ab': 0, 'h': 0, 'hr': 0, 'rbi': 0, 'bb': 0, 'so': 0}; }
    s.boxScore['homePitcher'][homePitcher.registeredName] = <String, dynamic>{'ip': '0', 'er': 0, 'so': 0, 'bb': 0};
    s.boxScore['awayPitcher'][awayPitcher.registeredName] = <String, dynamic>{'ip': '0', 'er': 0, 'so': 0, 'bb': 0};
    return s;
  }

  bool isFinished(GameSession s) {
    final st = s.state;
    if (st.inning > 12) return true;
    if (st.inning >= 9 && !st.isTop && st.homeScore > st.awayScore) return true; // 9回裏以降のサヨナラ・試合終了判定
    if (st.isTop && st.inning >= 10 && s.lastInningStr != '${st.inning}回表' && st.homeScore != st.awayScore) return true; // 9回以降、表裏終了時に点差があれば試合終了
    return false;
  }

  /// 次の打席を1打席ぶん進める（打席の途中なら、その打席の最後まで進める）
  void stepPlateAppearance(GameSession s, {AtBatPlan? plan}) {
    Stadium.current = s.stadium; // 打球の物理・フェンスはこの試合の球場で
    GameWeather.current = s.weather;
    if (s.paIter == null) {
      if (isFinished(s)) return;
      s.livePlan = plan;
      s.paIter = _paSteps(s, plan).iterator;
    } else if (plan != null) {
      s.livePlan = plan;
    }
    while (s.paIter!.moveNext()) {}
    _endPa(s);
  }

  /// 1球（または打席途中の判断ポイント）だけ進める。打席が終わったら null を返す。
  /// plan は打席の最初、または打席中に采配を差し替えるときに渡す。
  PaPause? stepPitch(GameSession s, {AtBatPlan? plan}) {
    Stadium.current = s.stadium;
    GameWeather.current = s.weather;
    if (s.paIter == null) {
      if (isFinished(s)) return null;
      s.livePlan = plan;
      s.paIter = _paSteps(s, plan).iterator;
    } else if (plan != null) {
      s.livePlan = plan;
    }
    if (s.paIter!.moveNext()) return s.paIter!.current;
    _endPa(s);
    return null;
  }

  /// 実況用：投球前の場面を1球の記録に残す
  void _ctxBefore(GameSession s, PitchEvent e, Map? b, int pitches) {
    final st = s.state;
    e.homeName = s.homeTeam.shortName;
    e.stadiumId = s.stadium.id;
    e.awayName = s.awayTeam.shortName;
    List<String> line(List<LineupEntry> lu, Team t) => [
          for (final x in lu)
            () {
              final p = t.players.where((q) => q.id == x.playerId).firstOrNull;
              final ss = p?.seasonStats;
              final avg = ss == null || ss.atBats == 0 ? '---' : (ss.hits / ss.atBats).toStringAsFixed(3).replaceFirst('0.', '.');
              return '${x.position}|${p?.registeredName ?? ''}|${p == null ? '' : (p.uniformNumber < 0 ? '00' : '${p.uniformNumber}')}|$avg|${ss?.homeRuns ?? 0}';
            }(),
        ];
    e.homeLine = line(s.homeLineup, s.homeTeam);
    e.awayLine = line(s.awayLineup, s.awayTeam);
    e.inning = st.inning;
    e.top = st.isTop;
    e.outsBefore = st.outs;
    e.basesBefore = [st.runner1B != null, st.runner2B != null, st.runner3B != null];
    e.offBefore = st.isTop ? st.awayScore : st.homeScore;
    e.defBefore = st.isTop ? st.homeScore : st.awayScore;
    e.pitcherCount = pitches;
    if (b != null) e.batterToday = '${b['ab'] ?? 0}打数${b['h'] ?? 0}安打${(b['hr'] ?? 0) > 0 ? '${b['hr']}本塁打' : ''}';
  }

  /// 実況用：この1球の後の場面（3アウトで攻守が替わっていれば、アウトは3として残す）
  void _ctxAfter(GameSession s, PitchEvent e) {
    final st = s.state;
    final changed = st.isTop != e.top || st.inning != e.inning;
    e.outsAfter = changed ? 3 : st.outs;
    e.basesAfter = changed ? const [false, false, false] : [st.runner1B != null, st.runner2B != null, st.runner3B != null];
    e.offAfter = e.top ? st.awayScore : st.homeScore;
    e.defAfter = e.top ? st.homeScore : st.awayScore;
    e.ballsAfter = st.balls;
    e.strikesAfter = st.strikes;
    e.logIndex = s.playByPlay.length - 1;
  }

  /// 本塁打の一周（ダイヤモンド 110m）にかける秒数：NPB の平均は約 20〜22 秒（全力で走らない）。
  ///  走力が高いほど少し速く、選手ごとに ±2.5 秒のくせ（同じ選手はいつも同じ）
  static double _trot(Player p) {
    final h = p.id.codeUnits.fold(7, (a, c) => (a * 31 + c) & 0xffff);
    return 21.5 - (p.run - 60) * 0.05 + ((h % 100) / 100 - 0.5) * 5.0;
  }

  /// 守っている9人（役割 → 選手）：P と、守備側の打順表の守備位置から
  Map<String, Player> _defenseMapOf(GameSession s, Player pitcher, Team defenseTeam) {
    const pos = {'捕': 'C', '一': '1B', '二': '2B', '三': '3B', '遊': 'SS', '左': 'LF', '中': 'CF', '右': 'RF'};
    final m = <String, Player>{'P': pitcher};
    for (final e in (s.state.isTop ? s.homeLineup : s.awayLineup)) {
      final r = pos[e.position];
      if (r == null) continue;
      m[r] = defenseTeam.players.firstWhere((p) => p.id == e.playerId, orElse: () => defenseTeam.players.first);
    }
    return m;
  }

  void _endPa(GameSession s) {
    _settlePa(s);
    if (applyForm && injuriesInGame) _injuryCheck(s);
    s.paIter = null;
    s.livePlan = null;
    s.pitchCommand = PitchCommand.none;
    s.threeBunt = false;
  }

  /// 試合中の怪我を起こすか（検証ツールでは切れる）
  static bool injuriesInGame = true;

  /// 打席の終わり：打者と投手に、試合中の怪我が起きることがある（1試合あたりの確率を打席・対戦打者で割ったもの）
  ///  軽い怪我（全治10日まで）はそのまま続ける（強行出場）。重い怪我はその場で交代（代走・守備交代・継投）
  void _injuryCheck(GameSession s) {
    if (s.pitchEvents.isEmpty || isFinished(s)) return;
    final e = s.pitchEvents.last;
    final batHome = e.battingHome;
    final batTeam = batHome ? s.homeTeam : s.awayTeam, defTeam = batHome ? s.awayTeam : s.homeTeam;
    final batter = (batHome ? s.homeOrder : s.awayOrder).where((p) => p.registeredName == e.batter).firstOrNull;
    final pitcher = batHome ? s.awayPitcher : s.homePitcher;
    for (final (p, team, home, div) in [(batter, batTeam, batHome, 2.2), (pitcher.registeredName == e.pitcher ? pitcher : null, defTeam, !batHome, 10.0)]) {
      if (p == null || p.injuryDays > 0 || s.injuredNow.contains(p.id)) continue;
      if (_rand.nextDouble() >= ConditionEngine.injuryProb(p, team) / div) continue;
      s.injuredNow.add(p.id);
      s.injuryNews.add(ConditionEngine.inflict(p, team, _rand));
      if (p.injurySeverity <= 1) {
        s.playByPlay.add('【負傷】${team.name}: ${p.registeredName}（${p.injuryName}・軽傷。そのまま出場）');
        continue;
      }
      s.playByPlay.add('【負傷】${team.name}: ${p.registeredName}（${p.injuryName}）。プレーを続けられず交代');
      _injurySub(s, home, p);
    }
  }

  /// 怪我で続けられない選手を交代させる
  void _injurySub(GameSession s, bool home, Player p) {
    final st = s.state;
    final order = home ? s.homeOrder : s.awayOrder;
    final lineup = home ? s.homeLineup : s.awayLineup;
    final slot = order.indexWhere((x) => identical(x, p));
    if (identical(p, home ? s.homePitcher : s.awayPitcher)) {
      var pool = availablePitchers(s, home);
      final fresh = pool.where((x) => x.energyRatio >= 0.3).toList();
      if (fresh.isNotEmpty) pool = fresh;
      if (pool.isEmpty) return;
      pool.sort((a, b) => b.ovr.compareTo(a.ovr));
      final r = pool.first;
      changePitcher(s, home, r);
      if (slot >= 0) _putInOrder(s, home, slot, r, position: '投');
      return;
    }
    if (slot < 0) return;
    final batting = home != st.isTop; // 裏ならホームの攻撃
    final base = !batting ? 0 : (st.runner1B == p.registeredName ? 1 : (st.runner2B == p.registeredName ? 2 : (st.runner3B == p.registeredName ? 3 : 0)));
    final bench = availableBatters(s, home).where((b) => !b.isInjuredOut).toList();
    if (bench.isEmpty) return;
    if (base > 0) {
      bench.sort((a, b) => b.run.compareTo(a.run));
      pinchRun(s, home, base, bench.first);
      return;
    }
    final pos = slot < lineup.length ? lineup[slot].position : 'DH';
    int apt(Player x) => switch (pos) { '捕' => x.fieldC, '一' => x.field1B, '二' => x.field2B, '三' => x.field3B, '遊' => x.fieldSS, '左' => x.fieldLF, '中' => x.fieldCF, '右' => x.fieldRF, _ => 0 };
    bench.sort((a, b) => pos == 'DH' ? (b.contact + b.power).compareTo(a.contact + a.power) : (apt(b) * 2 + b.catchSkill).compareTo(apt(a) * 2 + a.catchSkill));
    defensiveSwap(s, home, slot, bench.first, pos);
  }

  /// 調子・体力・軽い怪我による能力補正（applyForm=false の検証ツールでは 0）
  int formAdj(Player p, DateTime date) {
    if (!applyForm) return 0;
    // 投手は調子の影響を小さく（絶不調でも −3。野手は −6）。体力が減っている時の影響も半分
    final pit = p.isPitcher;
    final c = p.conditionAt(date);
    int a = pit ? (c * 1.5).round() : c * 3;
    final ratio = p.maxEnergy > 0 ? p.energy / p.maxEnergy : 1.0;
    if (ratio < 0.3) {
      a -= pit ? 4 : 8;
    } else if (ratio < 0.5) {
      a -= pit ? 1 : 3;
    }
    if (p.injuryDays > 0 && p.injurySeverity == 1) a -= 5; // 軽い怪我を押しての出場
    return a;
  }

  /// 打者の打球が引っ張り方向へ寄る度合い（°）。パワーのある打者ほど引っ張る
  /// 仕様書 1.2 のフェア／ファウル（打球の通り道。本塁基準の座標で、フェアは y ≥ |x|）
  ///  ・地面に着く前にフェンスを越えた：越えた所がフェアなら本塁打（フェア）
  ///  ・最初に地面に着いた所が一塁・三塁より奥（y ≥ 19.4m）：その点で決める（そのあとファウルへ転がってもフェア）
  ///  ・内野（塁より手前）に落ちた：塁を越える前にファウル地域へ出たらファウル。フェアのまま塁を越えるか止まればフェア
  static bool isFoulTrajectory(List<Vector3D> tr) {
    bool fair(double x, double y) => y >= x.abs();
    for (var i = 0; i < tr.length; i++) {
      final p = tr[i];
      final d = sqrt(p.x * p.x + p.y * p.y);
      final ang = atan2(p.x, p.y) * 180 / pi;
      if (p.z <= 0.001 && i > 0) {
        if (p.y >= 19.397) return !fair(p.x, p.y);
        for (var k = i; k < tr.length; k++) {
          final q = tr[k];
          if (!fair(q.x, q.y)) return true;
          if (q.y >= 19.397) return false;
        }
        return false;
      }
      if (ang.abs() <= 60 && d >= PhysicsConstants.getFenceDistance(ang.clamp(-45.0, 45.0))) return !fair(p.x, p.y);
    }
    final l = tr.last;
    return !fair(l.x, l.y);
  }

  /// 捕手が捕れなかった投球（仕様書 1.5：振り逃げ。暴投・捕逸）
  ///  ワンバウンド（本塁で高さ 0.22m 未満）は捕手が体で止める（守備力で 0.6〜0.97）。止められなければ後ろへそれる。
  ///  大きく外れた球は、まれにそらす。k3：第3ストライク。返り値 reach：振り逃げで打者が一塁に生きる、away：後ろへそれた（走者は進む）
  ({bool reach, bool away, bool dirt}) _loosePitch(double ax, double az, Player? c, {required bool k3, required int outsBefore, required bool firstOccupied}) {
    final wz = Zone.worldZ(az), wx = (ax * Zone.halfW).abs();
    final fc = c?.fieldC ?? 50;
    final dirt = wz < 0.22;
    var away = false;
    if (dirt) {
      away = _rand.nextDouble() > (0.80 + (fc - 50) * 0.004).clamp(0.6, 0.97);
    } else if (wx > 0.75 || wz > 1.9) {
      away = _rand.nextDouble() < (0.10 * (1 - fc / 100)).clamp(0.0, 0.1);
    }
    var reach = false;
    if (k3 && (dirt || away) && (!firstOccupied || outsBefore >= 2)) {
      // 打者は一塁へ走る（右打者 約4.3秒）。捕手は拾って一塁へ（止めた球は前で拾える、それた球はバックネットまで）
      final retrieve = away ? 2.6 + _rand.nextDouble() * 1.6 : 0.8 + _rand.nextDouble() * 0.4;
      final tThrow = retrieve + 0.7 + 1.0; // 握り替え＋一塁までの送球
      reach = tThrow > 4.3 + _gauss() * 0.2;
    }
    return (reach: reach, away: away, dirt: dirt);
  }

  /// 後ろへそれた投球の間に走者が1つ進む（三塁走者は生還＝投手の自責点）。forcedOnly：振り逃げで打者が一塁へ行くとき、押し出される走者だけ進む
  void _advanceOnLoose(GameSession s, Player pitcher, {bool forcedOnly = false}) {
    final st = s.state;
    final box = st.isTop ? s.boxScore['homePitcher'] : s.boxScore['awayPitcher'];
    void run() {
      st.addScore(1);
      pitcher.seasonStats.earnedRuns++;
      final ps = box?[pitcher.registeredName];
      if (ps is Map) ps['er'] = (ps['er'] ?? 0) + 1;
    }

    if (forcedOnly) {
      if (st.runner1B == null) return;
      if (st.runner2B != null) {
        if (st.runner3B != null) run();
        st.runner3B = st.runner2B;
      }
      st.runner2B = st.runner1B;
      st.runner1B = null;
      return;
    }
    if (st.runner3B != null) run();
    st.runner3B = st.runner2B;
    st.runner2B = st.runner1B;
    st.runner1B = null;
  }

  /// 仕様書 6.1 の送球の角度の誤差：距離 d の送球が、受ける野手の届く範囲（左右 1.5m・上 1.2m・下 0.9m＝すくい上げ）を外れたら悪送球
  bool _specThrowError(Player thrower, double d) {
    final s = Spec.throwAngleSigma(thrower.throwAccuracy) * pi / 180;
    final h = d * tan(_gauss() * s), v = d * tan(_gauss() * s);
    return h.abs() > 1.5 || v > 1.2 || v < -0.9;
  }

  /// 外野へのヒットで打者走者が二塁・三塁を狙うか（判断力と得点期待値で決める）。狙って刺されることもある
  ///  def2/def3：返球が二塁・三塁に届く時刻、to2/to3：打者が着く時刻。bases は記録の塁打、outAt は刺された塁（0 なし）
  ({int bases, int outAt}) _stretch(Player batter, double def2, double to2, double def3, double to3, int outs, double pressure, double runAdj) {
    double g() => sqrt(-2 * log(1 - _rand.nextDouble())) * cos(2 * pi * _rand.nextDouble());
    final j = (Judgment.runner(batter) + 60) / 2; // 一塁・三塁コーチの判断も合わせる
    final sig = Judgment.readSigma(j, pressure);
    double pSafe(double margin) => 1 / (1 + exp(-(margin + g() * sig - 0.1) / 0.12));
    final vOut = RunValue.re(0, outs + 1);
    final v1 = RunValue.re(1, outs), v2 = RunValue.re(2, outs), v3 = RunValue.re(4, outs);
    final p2 = pSafe(def2 - to2);
    if (p2 * v2 + (1 - p2) * vOut + runAdj * 0.4 <= v1) return (bases: 1, outAt: 0);
    // 二塁へ（タッチまで 0.1秒）
    if (to2 + g() * 0.15 > def2 + 0.1) return (bases: 1, outAt: 2);
    final p3 = pSafe(def3 - to3);
    if (p3 * v3 + (1 - p3) * vOut + runAdj * 0.4 <= v2) return (bases: 2, outAt: 0);
    if (to3 + g() * 0.15 > def3 + 0.1) return (bases: 2, outAt: 3);
    return (bases: 3, outAt: 0);
  }

  /// フェンスに当たった打球：フェンスの手前へ跳ね返って落ち、少し転がる（0.05秒ごとの点を足す）
  static List<Vector3D> fenceRebound(List<Vector3D> tr, double angleDeg) {
    final hit = tr.last;
    final a = angleDeg * pi / 180;
    final rx = sin(a), ry = cos(a); // 外向き（本塁から見た向き）
    final fd = PhysicsConstants.getFenceDistance(angleDeg) - 0.3;
    final vr = hit.vx * rx + hit.vy * ry; // フェンスへ向かう速さ
    final vtx = hit.vx - vr * rx, vty = hit.vy - vr * ry;
    // 跳ね返り：フェンスに向かう向きは 0.3 倍で逆に、横は半分に
    var vx = -vr.abs() * 0.3 * rx + vtx * 0.5, vy = -vr.abs() * 0.3 * ry + vty * 0.5, vz = hit.z > 0 ? min(0.0, hit.vz) : 0.0;
    var x = fd * rx, y = fd * ry, z = max(0.0, hit.z);
    final out = [...tr.sublist(0, tr.length - 1), Vector3D(x, y, z, vx, vy, vz)];
    const dt = 0.05;
    var onGround = z <= 0;
    for (var k = 0; k < 60; k++) {
      if (!onGround) {
        vz -= PhysicsConstants.gravity * dt;
        z += vz * dt;
        if (z <= 0) {
          z = 0;
          onGround = true;
          vz = 0;
          vx *= 0.6;
          vy *= 0.6;
        }
      } else {
        final v = sqrt(vx * vx + vy * vy);
        final nv = max(0.0, v - 0.4 * PhysicsConstants.gravity * dt);
        if (v > 0) { vx *= nv / v; vy *= nv / v; }
      }
      x += vx * dt;
      y += vy * dt;
      out.add(Vector3D(x, y, z, onGround ? vx : vx, vy, vz));
      if (onGround && sqrt(vx * vx + vy * vy) < 0.5) break;
    }
    out.add(Vector3D(x, y, 0, 0, 0, 0));
    return out;
  }

  /// 打者の待ち球（仕様書 §1）：直球系を待つ確率で系統を選び、その中から球種の割合で1つ選ぶ
  Pitch _guessPitch(Player pitcher, BatTactic? batT, int balls, int strikes) {
    final ps = pitcher.pitches.isEmpty ? [Player.fielderStraight(pitcher.velocity)] : pitcher.pitches;
    final fast = _rand.nextDouble() < _swingRead(pitcher, batT, balls, strikes).pFast;
    var c = ps.where((x) => PitchCatalog.isFastLike(x) == fast).toList();
    if (c.isEmpty) c = ps;
    final tot = c.fold<double>(0, (s, x) => s + max(1, x.ratio));
    var r = _rand.nextDouble() * tot;
    for (final x in c) { r -= max(1, x.ratio); if (r <= 0) return x; }
    return c.last;
  }

  /// 打者の読み：投手の球種の割合・カウント・作戦から、直球系を待つ確率と予想の速さ
  SwingRead _swingRead(Player pitcher, BatTactic? batT, int balls, int strikes) {
    final ps = pitcher.pitches.isEmpty ? [Player.fielderStraight(pitcher.velocity)] : pitcher.pitches;
    var fastW = 0.0, slowW = 0.0, slowV = 0.0, slowB = 0.0, fastV = ps.first.speed.toDouble();
    for (final x in ps) {
      final w = max(1, x.ratio).toDouble();
      if (PitchCatalog.isFastLike(x)) {
        if (fastW == 0) fastV = x.speed.toDouble();
        fastW += w;
      } else {
        slowW += w;
        slowV += x.speed * w;
        slowB += x.breakLevel * w;
      }
    }
    var pf = slowW == 0 ? 1.0 : readFastBase + readFastMul * fastW / (fastW + slowW);
    pf += (balls - strikes) * 0.06; // 打者有利のカウントは直球を待つ
    if (batT == BatTactic.fastballFocus) pf = 0.85;
    if (batT == BatTactic.breakingFocus) pf = 0.25;
    final vs = slowW == 0 ? fastV - 15 : slowV / slowW;
    final drop = slowW == 0 ? 3.0 : 3.5 * (slowB / slowW) / 50;
    return SwingRead(pf.clamp(0.1, 0.95), fastV, vs, drop);
  }

  static double pullTendency(Player b) => (3 + (b.power - 50) * 0.2).clamp(0.0, 12.0);

  /// CPU 監督の判断力（1〜100）
  static int cpuSkill(String teamId) => cpuStyles[teamId]?['skill'] ?? 55;

  /// 次の打席の CPU の守備位置を決める（自分が攻撃中なら、打席の前に画面に見せる）
  FieldTactic prepareCpuDefense(GameSession s) {
    final st = s.state;
    final defense = st.isTop ? s.homeTeam : s.awayTeam;
    final home = !st.isTop;
    final order = home ? s.homeOrder : s.awayOrder;
    final batter = order[nextBatterSlot(s, home) % order.length];
    final skill = cpuSkill(defense.id);
    final diff = (st.homeScore - st.awayScore).abs();
    var f = FieldTactic.none;
    if (st.runner3B != null && st.outs < 2 && st.inning >= 7 && diff <= 1 && _rand.nextDouble() < 0.6) {
      f = FieldTactic.infieldIn;
    } else if (st.runner1B != null && st.outs < 2 && _rand.nextDouble() < 0.25) {
      f = FieldTactic.doublePlayShift;
    } else if (pullTendency(batter) >= 7 && _rand.nextDouble() < 0.35 + (skill - 50) * 0.01) {
      f = FieldTactic.pullShift; // 引っ張る打者には寄せる（判断力の高い監督ほど使う）
    } else if (batter.power < 50 && batter.contact >= 65 && _rand.nextDouble() < 0.15 + (skill - 50) * 0.005) {
      f = FieldTactic.oppositeShift; // 流し打ちの巧打者
    }
    s.cpuField = f;
    s.cpuFieldPa = s.paCount;
    return f;
  }

  static bool isFastball(Pitch p) => PitchCatalog.isFastLike(p);
  /// 縦に落ちる球（フォーク・チェンジアップなど）
  static bool _isDrop(Pitch p) => p.breakLevel > 30 && (p.angle - 90).abs() <= 35;

  /// 配球（捕手のサイン）：球種と狙い所を決める。
  ///  - 初めての対戦は直球で内角を攻めて意識させ、2打席目以降は外の変化球でかわす
  ///  - 先発は打者一巡するまで、比率の低い変化球を隠しておく
  ///  - ストライクは投げられても、追い込んだらボール球・見せ球を使う（球数が増える）
  ///  forced は球種を指定されたとき（狙い所だけ決める）
  PitchCall _callPitch(GameSession s, Player pitcher, Player batter, PitchTactic pitT, FieldTactic fldT, String? lastPitch, {String? forced}) {
    final st = s.state;
    final key = '${pitcher.id}|${batter.id}';
    final faced = (s.paVs[key] ?? 1) - 1; // この打席より前の対戦数
    final a = s.insideAware[key] ?? 0.0;
    final seen = s.seenPitches[key] ?? const <String>{};
    final shown = s.shownPitches[pitcher.id] ?? const <String>{};
    final bf = s.battersFaced[pitcher.id] ?? 1; // この打席を含む対戦打者数
    final isStarter = identical(pitcher, s.starterHome) || identical(pitcher, s.starterAway);
    final balls = st.balls, strikes = st.strikes;
    final ahead = strikes == 2 && balls < 3;
    final behind = balls >= 2 && balls > strikes;
    final early = strikes < 2 && balls + strikes <= 2 && !behind;
    final planInside = faced == 0;
    final pinch = (st.runner2B != null || st.runner3B != null) && strikes == 2;

    // ---- 球種 ----
    Pitch pick;
    final all = pitcher.pitches.isNotEmpty ? pitcher.pitches : [Pitch(name: 'ストレート', breakLevel: 0, angle: 90, speed: pitcher.velocity, ratio: 100, sharpness: 50, heaviness: 50)];
    final forcedPitch = forced == null ? null : all.where((p) => p.name == forced).firstOrNull;
    if (forcedPitch != null) {
      pick = forcedPitch;
    } else {
      // 打者一巡までは比率の低い変化球を隠す（ピンチでは解禁することがある）
      final hidden = <String>{};
      final breaking = all.where((p) => !isFastball(p) && p.ratio > 0).toList()..sort((x, y) => x.ratio.compareTo(y.ratio));
      if (isStarter && bf <= 9 && breaking.length >= 3 && !(pinch && _rand.nextDouble() < 0.4)) {
        for (final p in breaking.take(breaking.length >= 4 ? 2 : 1)) {
          if (!shown.contains(p.name)) hidden.add(p.name);
        }
      }
      final cands = all.where((p) => p.ratio > 0 && !hidden.contains(p.name)).toList();
      if (cands.isEmpty) cands.add(all.first);
      final weights = <double>[];
      for (final p in cands) {
        final fast = isFastball(p);
        double w = p.ratio.toDouble();
        if (early && planInside && fast) w *= 1.5;               // 初対戦は直球で内角を意識させる
        if (!planInside && !fast) w *= 1.3 + max(0.0, a) * 0.5;   // 2打席目以降は変化球でかわす
        if (ahead) w *= fast ? 0.75 : (_isDrop(p) ? 1.8 : 1.45); // 追い込んだら決め球
        if (behind) w *= fast ? 1.7 : (pitcher.control >= 70 ? 0.8 : 0.55); // カウントが悪いと直球で取りにいく
        if (p.name == lastPitch) w *= 0.75;                       // 同じ球が続きすぎないように
        if (ahead && faced > 0 && !seen.contains(p.name)) w *= 1.3; // まだ見せていない球で仕留める
        if (pitT == PitchTactic.fastballMain) w *= fast ? 2.2 : 0.6;
        if (pitT == PitchTactic.breakingMain) w *= fast ? 0.45 : 1.5;
        if (pitT == PitchTactic.strikeout && ahead && !fast) w *= 1.3;
        weights.add(max(0.01, w));
      }
      final total = weights.fold(0.0, (x, y) => x + y);
      var roll = _rand.nextDouble() * total;
      pick = cands.last;
      for (var i = 0; i < cands.length; i++) {
        roll -= weights[i];
        if (roll < 0) { pick = cands[i]; break; }
      }
    }
    final fast = isFastball(pick);
    final drop = _isDrop(pick);
    String note = '';
    if (!fast && bf > 9 && isStarter && !shown.contains(pick.name)) note = '（この試合初めての${pick.name}）';

    // ---- ストライクを取りにいくか（有利なカウントでは、あえてボール球を使う） ----
    double zoneP;
    if (balls >= 3) {
      zoneP = strikes == 2 ? 0.76 : 0.82;
    } else if (strikes == 2) {
      zoneP = balls == 0 ? 0.30 : (balls == 1 ? 0.40 : 0.52);
    } else if (balls == 2) {
      zoneP = 0.68;
    } else if (strikes == 1) {
      zoneP = balls == 0 ? 0.56 : 0.60;
    } else {
      zoneP = balls == 0 ? 0.62 : 0.64;
    }
    if (fldT == FieldTactic.powerGuard) zoneP -= 0.08;          // 勝負を避け、際どいコースを突く
    if (pitT == PitchTactic.groundOut) zoneP += 0.04;           // 打たせて取る：ゾーン内で勝負
    if (pitT == PitchTactic.strikeout) zoneP -= 0.02;           // 三振狙い：ボール球で振らせる
    if (pitT == PitchTactic.controlFocus) zoneP += 0.05;        // コントロール重視：ストライク先行
    if (pitT == PitchTactic.outsideFocus) zoneP -= 0.02;        // 外角中心：くさいところを突く
    if (pitT == PitchTactic.breakingMain) zoneP -= 0.03;
    if (pitT == PitchTactic.fastballMain) zoneP += 0.04;        // 直球はストライクを取りやすい        // 変化球はストライクを取りにくい
    zoneP += zoneAim;
    zoneP += max(0, pitcher.control - _lvShift - 60) * ctrlZoneK; // 制球の良い投手は、ボール球に逃げずストライクで勝負できる
    final inZone = _rand.nextDouble() < zoneP;

    // ---- コース（x は打者の内角が +） ----
    double pIn = (planInside && early) ? 0.65 : 0.40;
    if (!fast) pIn *= 0.7;
    pIn -= 0.35 * a; // 内角を意識している打者には外、外を待つ打者には内
    if (pitT == PitchTactic.insideAttack) pIn = 0.8;
    if (pitT == PitchTactic.outsideFocus) pIn = 0.15;
    pIn = pIn.clamp(0.08, 0.88);
    double sideSign() => _rand.nextDouble() < pIn ? 1.0 : -1.0;
    double x, z;
    if (inZone) {
      x = _rand.nextDouble() < 0.2 ? (_rand.nextDouble() - 0.5) * 0.8 : sideSign() * (0.35 + _rand.nextDouble() * 0.5);
      if (drop) {
        z = -0.35 - _rand.nextDouble() * 0.55;
      } else if (fast) {
        final r = _rand.nextDouble();
        z = r < 0.4 ? 0.3 + _rand.nextDouble() * 0.55 : (r < 0.85 ? -0.3 - _rand.nextDouble() * 0.55 : (_rand.nextDouble() - 0.5) * 0.6);
      } else {
        z = -0.8 + _rand.nextDouble() * 1.3;
      }
    } else if (_rand.nextDouble() < (ahead ? 0.3 : 0.45)) {
      // ゾーンの際（ボール1個ぶん外れる）
      final off = 1.0 + _rand.nextDouble() * 0.25;
      if (_rand.nextBool()) {
        x = sideSign() * off;
        z = (_rand.nextDouble() - 0.5) * 1.6;
      } else {
        x = (_rand.nextDouble() - 0.5) * 1.6;
        z = (drop || _rand.nextDouble() < 0.6) ? -off : off;
      }
    } else {
      // 釣り球・見せ球
      final off = 1.35 + _rand.nextDouble() * 0.5;
      if (drop) {
        x = (_rand.nextDouble() - 0.5) * 1.2;
        z = -off;
      } else if (!fast) {
        x = -off; // 外へ逃げる変化球
        z = -0.3 - _rand.nextDouble() * 0.8;
      } else if ((planInside || a < 0 || pitT == PitchTactic.insideAttack) && _rand.nextBool()) {
        x = off * 0.85; // 内角の見せ球で、のけぞらせる
        z = (_rand.nextDouble() - 0.3) * 1.0;
        note = '（見せ球）';
      } else {
        x = (_rand.nextDouble() - 0.5) * 1.0;
        z = off * 0.85; // 高めの釣り球
      }
    }
    return PitchCall(pick, x, z, inZone, note);
  }

  /// 監督への信頼による作戦の実行率（信頼30→85%、60以上→100%）
  static double executionRate(Player p) => (0.70 + p.trust * 0.005).clamp(0.0, 1.0);

  /// 監督への信頼による作戦の成功率補正（信頼100で +5%）
  static double trustBonus(Player p) => (p.trust - 50) * 0.001;

  Iterable<PaPause> _paSteps(GameSession s, AtBatPlan? initialPlan) sync* {
    AtBatPlan? plan = initialPlan;
    final state = s.state;
    final gamePitchCounts = s.gamePitchCounts;
    final homeTeam = s.homeTeam;
    final awayTeam = s.awayTeam;
    final homeOrder = s.homeOrder;
    final awayOrder = s.awayOrder;
    final homePitcher = s.homePitcher;
    final awayPitcher = s.awayPitcher;
    int homeBatterIndex = s.homeBatterIndex;
    int awayBatterIndex = s.awayBatterIndex;
    int homeHits = s.homeHits;
    int awayHits = s.awayHits;
    final playByPlay = s.playByPlay;
    final pitchByPitch = s.pitchByPitch;
    final boxScore = s.boxScore;
    String lastInningStr = s.lastInningStr;
    final bool wasTop = state.isTop;
    final int paIndex = s.paCount++;
    final int outsBefore = wasTop ? state.homeDefenseOuts : state.awayDefenseOuts;
    final Player pitcherAtStart = wasTop ? homePitcher : awayPitcher;
    final String inningAtStart = '${state.inning}回${wasTop ? "表" : "裏"}';
    final int hitsBefore = wasTop ? awayHits : homeHits;
    final int scoreBefore = wasTop ? state.awayScore : state.homeScore;
    int pitcherBB() => ((boxScore[wasTop ? 'homePitcher' : 'awayPitcher'] as Map<String, dynamic>)[pitcherAtStart.registeredName]?['bb'] ?? 0) as int;
    final int bbBefore = pitcherBB();
    s.paTop = wasTop;
    s.paHome = state.homeScore;
    s.paAway = state.awayScore;
    s.paDef = pitcherAtStart;
    s.paDefOuts = outsBefore;
    s.paDefEr = ((boxScore[wasTop ? 'homePitcher' : 'awayPitcher'] as Map<String, dynamic>)[pitcherAtStart.registeredName]?['er'] ?? 0) as int;

    {
      Team offenseTeam = state.isTop ? awayTeam : homeTeam;
      Team defenseTeam = state.isTop ? homeTeam : awayTeam;
      List<Player> currentOrder = state.isTop ? awayOrder : homeOrder;
      int currentBatterIndex = state.isTop ? awayBatterIndex : homeBatterIndex;
      Player batter = currentOrder[currentBatterIndex % currentOrder.length];
      Player pitcher = state.isTop ? homePitcher : awayPitcher;

      String currentInningStr = '${state.inning}回${state.isTop ? "表" : "裏"}';
      if (lastInningStr != currentInningStr) {
         playByPlay.add('【$currentInningStr（${offenseTeam.name}の攻撃）】');
         lastInningStr = currentInningStr;
      }

      playByPlay.add('${defenseTeam.name} ${identical(pitcher, state.isTop ? s.starterHome : s.starterAway) ? "先発" : "救援"} ${pitcher.registeredName} vs ${offenseTeam.name} ${(currentBatterIndex % 9) + 1}番 ${batter.registeredName}');

      var bStats = state.isTop ? boxScore['awayBatters'][batter.registeredName] : boxScore['homeBatters'][batter.registeredName];
      var pStats = state.isTop ? boxScore['homePitcher'][pitcher.registeredName] : boxScore['awayPitcher'][pitcher.registeredName];

      state.resetCount();
      bool atBatOver = false;
      int pitchCount = 0;
      double prevSpeedKmh = 140.0;
      double prevKmhPa = 0.0; // この打席の直前の球の速さ（初球は 0）

      BatTactic batT = BatTactic.none;
      RunTactic runT = RunTactic.none;
      PitchTactic pitT = PitchTactic.none;
      FieldTactic fldT = FieldTactic.none;
      bool hitRun = false;
      double runAdj = 0.0;
      bool skipBatterAdvance = false; // 盗塁死などで3アウトになり、打者が打席を終えていない場合
      bool signChecked = false;       // 作戦のサインを（信頼に応じて）実行できるか判定済みか
      bool signMissed = false;
      bool stealDone = false;
      bool threeBuntAsked = false;
      bool buntForcedOff = false;     // 2ストライク後に強攻へ切り替えた
      final DateTime gameDate = s.match.date;
      final int bForm = formAdj(batter, gameDate);
      final int pForm = formAdj(pitcher, gameDate);
      final double tBonus = trustBonus(batter);
      // 配球の駆け引き：対戦の記憶（内角への意識は打席をまたぐと薄れる）
      statPa++;
      final String vsKey = '${pitcher.id}|${batter.id}';
      final int facedBefore = s.paVs[vsKey] ?? 0;
      s.paVs[vsKey] = facedBefore + 1;
      s.battersFaced[pitcher.id] = (s.battersFaced[pitcher.id] ?? 0) + 1;
      s.insideAware[vsKey] = (s.insideAware[vsKey] ?? 0.0) * 0.6;
      final Set<String> seenBeforePa = Set.of(s.seenPitches[vsKey] ?? const <String>{});
      final double batSide = batter.bats == 'L' ? -1.0 : 1.0; // 打者の内角の向き（ゾーン座標の x）
      final String effHand = batter.bats == 'S' ? (pitcher.throws == 'L' ? 'R' : 'L') : batter.bats; // 両打ちは投手と逆の打席
      String? lastPitchName;

      // CPU（作戦の指示がない打席）も、足の速い一塁走者はときどき盗塁を仕掛ける
      bool cpuSteal = false;
      bool cpuBunt = false; // CPU 監督の送りバント
      BatTactic cpuBat = BatTactic.none;     // CPU 監督の打撃の作戦（ミート打ち・強振・叩きつけ）
      PitchTactic cpuPitch = PitchTactic.none; // CPU 監督の投手の作戦（全力投球・コントロール重視）
      FieldTactic cpuFld = FieldTactic.none;   // CPU 監督の守備位置（シフトなど）
      // CPU が受け持つ側（自分が采配する試合では相手側だけ）
      final bool cpuOffense = plan == null || (s.userTeamId != null && offenseTeam.id != s.userTeamId);
      final bool cpuDefense = plan == null || (s.userTeamId != null && defenseTeam.id != s.userTeamId);
      // 采配を（打席中の差し替えも含めて）読み直す
      void reloadPlan() {
        plan = s.livePlan ?? plan;
        batT = plan?.bat ?? BatTactic.none;
        runT = plan?.run ?? RunTactic.none;
        pitT = plan?.pitch ?? PitchTactic.none;
        fldT = plan?.field ?? FieldTactic.none;
        // 走者の自己判断（グリーンライト）：走塁の指示がなければ、自分が采配する試合でも足の速い走者は自分で走る
        if (cpuSteal && runT == RunTactic.none) runT = RunTactic.steal;
        if (cpuOffense) {
          if (cpuBunt && batT == BatTactic.none) batT = BatTactic.bunt;
          if (batT == BatTactic.none) batT = cpuBat;
        }
        // 守備の作戦（全力投球・シフトなど）：指示がなければ CPU 監督の判断。自分が采配する試合の自球団も同じ
        if (pitT == PitchTactic.none) pitT = cpuPitch;
        if (fldT == FieldTactic.none) fldT = cpuFld;
        // 監督への信頼が低いと、攻撃の作戦（サイン）を実行できないことがある
        final bool selfRun = cpuSteal && (plan?.run ?? RunTactic.none) == RunTactic.none; // 自己判断の盗塁はサイン不要
        if ((batT != BatTactic.none || (runT != RunTactic.none && !selfRun)) && !signChecked) {
          signChecked = true;
          if (applyForm && _rand.nextDouble() > executionRate(batter)) {
            signMissed = true;
            playByPlay.add('（${batter.registeredName}はサインを見落とした…作戦は実行されなかった）');
          }
        }
        if (signMissed) { batT = BatTactic.none; runT = RunTactic.none; }
        if (buntForcedOff && batT == BatTactic.bunt) batT = BatTactic.none;
        hitRun = runT == RunTactic.hitAndRun && state.runner1B != null && state.runner2B == null && state.outs < 2;
        runAdj = runT == RunTactic.aggressive ? 0.15 : (runT == RunTactic.cautious ? -0.15 : 0.0); // 積極走塁/慎重走塁
      }
      final cpuStyle = cpuStyles[offenseTeam.id];
      // 守備位置：CPU 側は CPU 監督が決める。自分が采配する側も、守備の作戦を選んでいなければ CPU 監督（コーチ）の判断を使う
      if (cpuDefense) {
        cpuFld = s.cpuFieldPa == paIndex ? s.cpuField : prepareCpuDefense(s);
      } else if ((plan?.field ?? FieldTactic.none) == FieldTactic.none) {
        final keep = (s.cpuField, s.cpuFieldPa); // 画面に見せる「相手の守備」は変えない
        cpuFld = prepareCpuDefense(s);
        s.cpuField = keep.$1; s.cpuFieldPa = keep.$2;
      }
      final FieldTactic defField = (plan?.field ?? FieldTactic.none) != FieldTactic.none ? plan!.field : cpuFld;
      // 足の速い走者ほど急に走りやすい（走力Sは年間40〜50盗塁が狙える）。大差の試合では走らない。2アウトからも走る
      //  打席の最初の球と、まだ走っていなければ2球目以降も毎球（perPitch 倍）判断する
      double stealChance() {
        final mult = ((cpuStyle?['steal'] ?? 50) / 50.0).clamp(0.6, 1.3); // 機動力を使う監督ほど走らせる
        final int lead = state.isTop ? state.awayScore - state.homeScore : state.homeScore - state.awayScore;
        final bool blowout = lead >= 5 || lead <= -5 || (state.inning >= 8 && lead <= -3);
        final double outsMult = state.outs == 2 ? 0.85 : 1.0;
        // 成功の見込み：投手のクイック（直球）＋捕手の肩・握り替え と 走者の到達時間を比べる。
        //  見込みの低い場面では走らない（足の遅めの走者は、クイックの下手な投手・肩の弱い捕手のときだけ走る）
        double chanceMult(Player r, bool toSecond) {
          if (!usePhysics) return 1.0;
          Player? c;
          for (final e in (state.isTop ? s.homeLineup : s.awayLineup)) {
            if (e.position == '捕') c = defenseTeam.players.where((p) => p.id == e.playerId).firstOrNull;
          }
          final tDef = StealRace.quickTime(pitcher) + (c == null ? 1.95 : StealRace.popTime(c, toSecond: toSecond)) + 0.14;
          final margin = tDef - StealRace.runTime(r, toSecond: toSecond, lefty: pitcher.throws == 'L') + (Spec.thr ? Spec.stealBias : StealRace.bias);
          final pSucc = 1 / (1 + exp(-margin / 0.075)); // 成功の見込み（ばらつき 約0.13秒を近似）
          return ((pSucc - cpuStealSel0) / cpuStealSelW).clamp(0.15, 1.4);
        }
        if (!blowout && state.runner1B != null && state.runner2B == null) {
          // 二盗：走力65以上。走力が5上がるごとに約1.6倍走る（70で年5・75で10・80で15〜20・90で40〜50盗塁の目安）
          final r = currentOrder.where((x) => x.registeredName == state.runner1B).firstOrNull;
          if (r != null && r.run >= 65) {
            final lowBoost = 1 + max(0, 82 - r.run) * 0.14; // 走力70〜80の走者も、年5〜15盗塁くらいは走る
            return min(0.85, exp((r.run - 90) / cpuStealExp) * lowBoost * cpuStealCurve * mult * cpuStealRate * outsMult * chanceMult(r, true));
          }
        } else if (!blowout && state.runner2B != null && state.runner3B == null && state.runner1B == null && state.outs < 2) {
          // 三盗：足の速い走者だけ（走力75以上）
          final r = currentOrder.where((x) => x.registeredName == state.runner2B).firstOrNull;
          if (r != null && r.run >= 75) {
            return pow((r.run - 72) / 25.0, 2.0) * cpuStealCurve * 0.2 * mult * cpuStealRate * chanceMult(r, false);
          }
        }
        return 0;
      }
      if (_rand.nextDouble() < stealChance()) cpuSteal = true;
      // CPU 監督の送りバント：無死一塁（一二塁）で、打力の低い打者か、終盤の接戦
      if (cpuStyle != null && cpuOffense && state.outs == 0 && state.runner1B != null && state.runner3B == null) {
        final diff = (state.homeScore - state.awayScore).abs();
        final weak = batter.contact * 0.5 + batter.power * 0.5 < 52;
        final late = state.inning >= 7 && diff <= 1;
        if ((weak || late) && _rand.nextDouble() < (cpuStyle['bunt'] ?? 50) / 100.0 * 0.55) cpuBunt = true;
      }
      // CPU 監督の打撃・投手の作戦（打者・投手の持ち味と場面で使い分ける）
      if (cpuOffense && !cpuBunt) {
        // 相手のシフトの逆を突く（判断力の高い監督ほど見抜く。ミートが低いと狙い通りに打てないので使わない）
        final offSkill = cpuSkill(offenseTeam.id);
        if (defField == FieldTactic.pullShift && batter.contact >= 55 && _rand.nextDouble() < offSkill / 100.0 * 1.1) {
          cpuBat = BatTactic.oppositeField;
        } else if (defField == FieldTactic.oppositeShift && _rand.nextDouble() < offSkill / 100.0 * 0.8) {
          cpuBat = BatTactic.pullHit;
        }
      }
      if (cpuOffense && !cpuBunt && cpuBat == BatTactic.none) {
        final risp = state.runner2B != null || state.runner3B != null;
        final late = state.inning >= 7;
        final lead = state.isTop ? state.awayScore - state.homeScore : state.homeScore - state.awayScore; // 攻撃側から見た点差
        final rr = _rand.nextDouble();
        if (risp && batter.contact >= 65 && batter.power < 60 && rr < 0.25) {
          cpuBat = BatTactic.contactSwing;
        } else if (late && lead < 0 && lead >= -3 && !risp && batter.power >= 75 && rr < 0.3) {
          cpuBat = BatTactic.powerSwing;
        } else if (state.runner3B != null && state.outs < 2 && batter.power < 55 && rr < 0.2) {
          cpuBat = BatTactic.chopDown;
        }
      }
      // 投手の作戦（守る側の監督）：終盤の接戦のピンチは全力投球、制球の悪い投手はときどきコントロール重視
      {
        final risp = state.runner2B != null || state.runner3B != null;
        final late = state.inning >= 7;
        final lead = state.isTop ? state.awayScore - state.homeScore : state.homeScore - state.awayScore;
        final rp = _rand.nextDouble();
        if (late && lead.abs() <= 2 && risp && rp < 0.5) {
          cpuPitch = PitchTactic.fullPower;
        } else if (pitcher.control < 55 && rp < 0.15) {
          cpuPitch = PitchTactic.controlFocus;
        }
      }
      reloadPlan();

      void creditRuns(int runs) {
        if (runs <= 0) return;
        batter.seasonStats.rbi += runs;
        pitcher.seasonStats.earnedRuns += runs;
        bStats['rbi'] = (bStats['rbi'] ?? 0) + runs;
        pStats['er'] = (pStats['er'] ?? 0) + runs;
      }

      bool canSteal() => (state.runner1B != null && state.runner2B == null) || (state.runner2B != null && state.runner3B == null);

      // 守っている選手（P・C・1B・2B・3B・SS）
      Map<String, Player> defenseNow() {
        const code = {'捕': 'C', '一': '1B', '二': '2B', '三': '3B', '遊': 'SS'};
        final m0 = <String, Player>{'P': pitcher};
        for (final e in (state.isTop ? s.homeLineup : s.awayLineup)) {
          final c = code[e.position];
          if (c == null) continue;
          final p = defenseTeam.players.where((p) => p.id == e.playerId).firstOrNull;
          if (p != null) m0[c] = p;
        }
        return m0;
      }

      // ---- 盗塁（走塁采配）：投球と同時に走者がスタート。外された（ピッチアウト）ら刺されやすい ----
      ({int from, bool safe, Player runner})? stealRec; // 3D 用：次の1球に付ける
      // 走り出した走者（この1球と同時にスタート）：元の塁（1＝二盗、2＝三盗）と名前。投げた球の結果のあとで判定する
      int goFrom = 0;
      String? goName;
      void startSteal() {
        if (!canSteal()) return;
        goFrom = state.runner1B != null && state.runner2B == null ? 1 : 2;
        goName = goFrom == 1 ? state.runner1B : state.runner2B;
      }
      // 盗塁の判定：kmh・ax・az は投げた球（速さ・ゾーン座標）。ev はこの1球の記録（3D 用に走った塁と成否を付ける）
      void doSteal(bool pitchOut, {double? kmh, double ax = 0.3, double az = 0.4, PitchEvent? ev}) {
        final from = goFrom, name = goName;
        goFrom = 0; goName = null;
        stealDone = true;
        if (from == 0 || name == null || state.outs >= 3) return;
        final bool toSecond = from == 1;
        // 走者がまだ元の塁にいて、次の塁が空いているときだけ（四球で押し出された・暴投で進んだときは判定しない）
        if ((toSecond ? state.runner1B : state.runner2B) != name || (toSecond ? state.runner2B : state.runner3B) != null) return;
        final String runnerName = name;
        final order = state.isTop ? awayOrder : homeOrder;
        final Player runner = order.firstWhere((x) => x.registeredName == runnerName, orElse: () => batter);
        // 捕手の送球（肩力・送球・捕手の守備）と、投手のクイックで成否が決まる
        Player? catcher;
        for (final e in (state.isTop ? s.homeLineup : s.awayLineup)) {
          if (e.position == '捕') catcher = defenseTeam.players.where((p) => p.id == e.playerId).firstOrNull;
        }
        final double cDef = catcher == null ? 60 : catcher.arm * 0.6 + catcher.throwAccuracy * 0.25 + catcher.fieldC * 0.15;
        final double prob = (stealBase + (runner.run - 60) * 0.008 - (cDef - 60) * 0.006 - (pitcher.quick - 60) * 0.003
                - (toSecond && pitcher.throws == 'L' ? 0.04 : 0.0) - (toSecond ? 0.0 : 0.10) + trustBonus(runner) - (pitchOut ? 0.40 : 0.0))
            .clamp(0.05, 0.95);
        final int halfBefore = state.inning * 2 + (state.isTop ? 0 : 1);
        _inc('steals');
        // 物理：投手のクイック＋投げた球が届く時間＋捕手の握り替え（球の高さ・コース）＋送球 と 走者の到達時間の比べ合い
        final race = usePhysics
            ? StealRace.race(runner, pitcher, catcher, toSecond: toSecond, pitchOut: pitchOut, runnerBonus: trustBonus(runner) * 0.5,
                kmh: kmh, wz: Zone.worldZ(az), wx: ax * Zone.halfW, rnd: _rand)
            : (safe: _rand.nextDouble() < prob, error: false, tDef: 0.0, tRun: 0.0);
        final bool stealSafe = race.safe;
        if (ev != null) { ev.stealFrom = from; ev.stealSafe = stealSafe; }
        if (stealSafe) {
          _inc('stealSuccess');
          if (toSecond) { state.runner2B = state.runner1B; state.runner1B = null; } else { state.runner3B = state.runner2B; state.runner2B = null; }
          runner.seasonStats.stolenBases++;
          catcher?.seasonStats.sbAgainst++;
          playByPlay.add('${runner.registeredName} ${toSecond ? "二" : "三"}盗成功！');
          if (state.isTop) { s.awaySB++; } else { s.homeSB++; }
          if (race.error) {
            // 悪送球：走者はもう1つ進む（三塁からは生還）
            _inc('stealThrowError');
            playByPlay.add('（捕手の悪送球の間に${runner.registeredName}は${toSecond ? "三塁へ" : "生還"}）');
            if (toSecond) {
              state.runner3B = state.runner2B; state.runner2B = null;
            } else {
              state.runner3B = null;
              state.addScore(1);
            }
          }
        } else {
          if (toSecond) { state.runner1B = null; } else { state.runner2B = null; }
          runner.seasonStats.caughtStealing++;
          catcher?.seasonStats.csAgainst++;
          playByPlay.add('${runner.registeredName} ${toSecond ? "二" : "三"}盗失敗（盗塁死）');
          state.addOut();
        }
        if (state.inning * 2 + (state.isTop ? 0 : 1) != halfBefore) { skipBatterAdvance = true; atBatOver = true; }
      }

      // ---- 敬遠（投手采配）----
      void doIntentionalWalk() {
        gamePitchCounts[pitcher.id] = (gamePitchCounts[pitcher.id] ?? 0) + 4;
        int runs = 0;
        if (state.runner1B != null && state.runner2B != null && state.runner3B != null) {
          state.addScore(1); runs = 1;
        } else if (state.runner1B != null && state.runner2B != null) {
          state.runner3B = state.runner2B; state.runner2B = state.runner1B;
        } else if (state.runner1B != null) {
          state.runner2B = state.runner1B;
        }
        state.runner1B = batter.registeredName;
        batter.seasonStats.walks++;
        pitcher.seasonStats.pitcherWalks++;
        bStats['bb'] = (bStats['bb'] ?? 0) + 1;
        pStats['bb'] = (pStats['bb'] ?? 0) + 1;
        creditRuns(runs);
        final String l = '敬遠 [${state.runner2B != null || state.runner3B != null ? "走者あり" : "ランナー無し"}]${runs > 0 ? " (押し出し1点)" : ""}';
        playByPlay.add(l);
        pitchByPitch.add(l);
        atBatOver = true;
        state.resetCount();
      }

      // ---- スクイズ（打撃采配）----
      void doSqueeze(bool pitchOut) {
        gamePitchCounts[pitcher.id] = (gamePitchCounts[pitcher.id] ?? 0) + 1;
        pitchCount++;
        _inc('squeezes');
        final double sq = (0.55 + (batter.contact - 60) * 0.004 - (pitcher.velocity - 145) * 0.004 + tBonus - (pitchOut ? 0.45 : 0.0)).clamp(0.05, 0.9);
        String sqLog = '$pitchCount球目 スクイズ　';
        final sqEv = PitchEvent(paIndex: paIndex, pitchNo: pitchCount, battingHome: !state.isTop, batter: batter.registeredName, batterHand: batter.bats, pitcher: pitcher.registeredName, pitchName: 'スクイズ', speed: pitcher.velocity.toDouble(), x: pitchOut ? 1.7 : 0, z: 0, inZone: !pitchOut, balls: state.balls, strikes: state.strikes)..result = 'バント';
        s.pitchEvents.add(sqEv);
        _ctxBefore(s, sqEv, bStats, gamePitchCounts[pitcher.id] ?? 0);
        int runs = 0;
        bool isAB = false;
        final double r = _rand.nextDouble();
        if (r < sq) {
          sqLog += 'スクイズ成功';
          _inc('squeezeSuccess');
          state.addScore(1); runs = 1;
          state.runner3B = state.runner2B; state.runner2B = state.runner1B; state.runner1B = null;
          state.addOut();
        } else if (r < sq + (1 - sq) * 0.6) {
          sqLog += 'スクイズ失敗（走者本塁憤死）';
          state.runner3B = null;
          isAB = true;
          final int o = state.outs;
          state.addOut();
          if (o < 2) {
            if (state.runner1B != null && state.runner2B == null) { state.runner2B = state.runner1B; }
            state.runner1B = batter.registeredName;
          }
        } else {
          sqLog += 'スクイズ失敗（小フライ併殺）';
          state.runner3B = null;
          isAB = true;
          state.addOut();
          if (state.outs != 0) { state.addOut(); }
        }
        if (runs > 0) { sqLog += ' ($runs点追加)'; creditRuns(runs); }
        if (isAB) { bStats['ab'] = (bStats['ab'] ?? 0) + 1; batter.seasonStats.atBats++; } else { batter.seasonStats.sacBunts++; }
        sqEv.desc = sqLog;
        playByPlay.add(sqLog);
        pitchByPitch.add(sqLog);
        _ctxAfter(s, sqEv);
        atBatOver = true;
        state.resetCount();
      }

      bool canBunt() => state.outs < 2 && (state.runner1B != null || state.runner2B != null);

      // ---- バント（作戦）：バットに当てて前に転がした打球の結果 ----
      void resolveBunt(PitchEvent bEv, String prefix) {
        _inc('bunts');
        List<String> rs = [];
        if (state.runner1B != null) rs.add('1塁');
        if (state.runner2B != null) rs.add('2塁');
        if (state.runner3B != null) rs.add('3塁');
        String buntRunnerState = rs.join(',');
        String buntLog = '$prefixバント　';
        bEv.result = 'バント';

        double sacProb = (0.72 + (batter.contact - 60) * 0.004 + (batter.run - 60) * 0.001 + tBonus).clamp(0.3, 0.9);
        double hitProb = (0.05 + (batter.run - 60) * 0.002).clamp(0.01, 0.15);
        double fcProb = state.runner1B != null ? 0.12 : 0.0;
        double dpProb = state.runner1B != null ? 0.04 : 0.0;
        double roll = _rand.nextDouble();
        if (usePhysics) {
          // バントの物理：打球を殺して転がす → 前進する一塁手・三塁手と投手・捕手の処理 → 先の走者か一塁か
          final order = state.isTop ? awayOrder : homeOrder;
          Player? rp(String? n) => n == null ? null : order.where((x) => x.registeredName == n).firstOrNull;
          final ball = BuntBall.make(batter, toFirst: state.runner2B == null, pitchKmh: pitcher.velocity.toDouble(), rnd: _rand, pitchZ: bEv.z, brk: min(1.0, sqrt(bEv.breakDX * bEv.breakDX + bEv.breakDY * bEv.breakDY)));
          final res = BuntPlay.resolve(ball: ball, batter: batter, batterLefty: effHand == 'L', runner1B: rp(state.runner1B), runner2B: rp(state.runner2B),
              defense: defenseNow(), outs: state.outs, rnd: _rand);
          const tiny = 1e-6;
          roll = switch (res.result) {
            BuntResult.sacrifice => 0.0,
            BuntResult.hit => sacProb + tiny,
            BuntResult.forceOut => fcProb > 0 ? sacProb + hitProb + tiny : 0.0,
            BuntResult.doublePlay => dpProb > 0 ? sacProb + hitProb + fcProb + tiny : 0.0,
            BuntResult.popOut => 1.0 - tiny,
          };
        }
        int runs = 0;
        bool isAB = true;

        void advanceOne() {
          if (state.runner3B != null) { state.addScore(1); runs++; }
          state.runner3B = state.runner2B;
          state.runner2B = state.runner1B;
          state.runner1B = null;
        }

        if (roll < sacProb) {
          buntLog += '送りバント成功';
          advanceOne();
          isAB = false;
          state.addOut();
          _inc('buntSuccess');
        } else if (roll < sacProb + hitProb) {
          buntLog += 'バントヒット！';
          advanceOne();
          state.runner1B = batter.registeredName;
          if (state.isTop) { awayHits++; } else { homeHits++; }
          batter.seasonStats.hits++;
          pitcher.seasonStats.hitsAllowed++;
          bStats['h'] = (bStats['h'] ?? 0) + 1;
        } else if (roll < sacProb + hitProb + fcProb) {
          buntLog += 'バント失敗（フォースアウト）';
          state.runner1B = null;
          if (state.runner2B != null) {
            if (state.runner3B != null) { state.addScore(1); runs++; }
            state.runner3B = state.runner2B; state.runner2B = null;
          }
          int outsNow = state.outs;
          state.addOut();
          if (outsNow < 2) { state.runner1B = batter.registeredName; }
        } else if (roll < sacProb + hitProb + fcProb + dpProb) {
          buntLog += 'バント失敗（併殺）';
          state.runner1B = null;
          state.addOut();
          if (state.outs != 0) { state.addOut(); }
        } else {
          buntLog += 'バント失敗（小フライ）';
          state.addOut();
        }
        if (runs > 0) {
          buntLog += ' ($runs点追加)';
          batter.seasonStats.rbi += runs;
          pitcher.seasonStats.earnedRuns += runs;
          bStats['rbi'] = (bStats['rbi'] ?? 0) + runs;
          pStats['er'] = (pStats['er'] ?? 0) + runs;
        }
        if (isAB) { bStats['ab'] = (bStats['ab'] ?? 0) + 1; batter.seasonStats.atBats++; } else { batter.seasonStats.sacBunts++; }
        buntLog += ' [$buntRunnerState]';
        bEv.desc = buntLog;
        bEv.landX = (_rand.nextDouble() - 0.5) * 16;
        bEv.landY = 6 + _rand.nextDouble() * 8;
        bEv.contact = 'ゴロ';
        bEv.outcome = buntLog.contains('ヒット') ? '単打' : 'アウト';
        playByPlay.add(buntLog);
        pitchByPitch.add(buntLog);
        _ctxAfter(s, bEv);
        atBatOver = true;
        state.resetCount();
      }

      bool firstLoop = true;
      int loopN = 0;
      while (!atBatOver) {
        // ---- 1球ごとの区切り（UI はここで止めて、次の1球の指示を受けられる） ----
        if (!firstLoop) {
          yield PaPause(PaPauseKind.afterPitch, s.pitchEvents.isNotEmpty ? s.pitchEvents.last : null);
        }
        firstLoop = false;
        reloadPlan();
        final PitchCommand cmd = s.pitchCommand;
        s.pitchCommand = PitchCommand.none;
        final bool pitchOut = cmd == PitchCommand.pitchOut;

        // 2ストライクからのバント：スリーバントか強攻かの判断で止まる（指示がなければ強攻）
        if (batT == BatTactic.bunt && canBunt() && state.strikes >= 2 && !threeBuntAsked) {
          threeBuntAsked = true;
          s.threeBunt = false;
          yield const PaPause(PaPauseKind.threeBunt);
          reloadPlan();
          if (!s.threeBunt) { buntForcedOff = true; batT = BatTactic.none; }
        }

        // 盗塁（打席中に1回）：この1球と同時に走り出す。判定は投げた球の結果のあと（ファウルなら戻ってやり直し）
        if (goFrom != 0) stealDone = false; // 前の球はファウルで戻った：もう一度走れる
        // 2球目以降：まだ走っていなければ、この球で走るかを判断する（盗塁のあと、二塁からの三盗も）
        if (pitchCount > 0 && !cpuSteal && !stealDone && runT == RunTactic.none && _rand.nextDouble() < stealChance() * cpuStealPerPitch) {
          cpuSteal = true;
          reloadPlan();
        }
        goFrom = 0; goName = null;
        if (runT == RunTactic.steal && !stealDone && canSteal()) {
          stealDone = true;
          startSteal();
        }
        // ヒットエンドラン：走者は毎球スタートを切る
        if (hitRun && !stealDone && canSteal()) startSteal();
        // 敬遠
        if (pitT == PitchTactic.intentionalWalk) { doIntentionalWalk(); break; }
        // スクイズ
        if (batT == BatTactic.squeeze && state.runner3B != null && state.outs < 2) { doSqueeze(pitchOut); break; }

        final bool bunting = batT == BatTactic.bunt && canBunt();
        final AtBatPlan? cp = plan;
        pitchCount++;
        statPitches++;
        gamePitchCounts[pitcher.id] = (gamePitchCounts[pitcher.id] ?? 0) + 1;
        final double staminaMult = (s.roughedInning[pitcher.id] == currentInningStr ? 1.5 : 1.0) * (pitT == PitchTactic.fullPower ? 1.6 : 1.0) * (s.weather.heat ? 1.12 : 1.0); // 全力投球は消耗が激しい。猛暑は 12% 増し
        s.staminaUsed[pitcher.id] = (s.staminaUsed[pitcher.id] ?? 0) + staminaMult;
        if (staminaMult > 1.0) _inc('staminaRoughedPitches');
        final double totalPitches = s.staminaUsed[pitcher.id]!;

        // 調子・体力・怪我の補正（球速は補正3につき1km/h）
        int pVelocity = pitcher.velocity + pForm ~/ 3;
        int pControl = (pitcher.control + pForm).clamp(1, 100);

        if (state.inning <= 2 && _rand.nextDouble() < 0.35) {
           pControl = (pControl - 25).clamp(1, 100);
        }
        int pBreakAmt = 0;
        int pSharpness = 50;
        int pHeavy = 55; // 球の重さ（球種ごと）

        int bMeet = (batter.contact + bForm).clamp(1, 100);
        int bPower = (batter.power + bForm).clamp(1, 100);
        int bTrajectory = batter.trajectory;
        int bEye = (batter.eye + bForm).clamp(1, 100);

        bool isRISP = state.runner2B != null || state.runner3B != null;
        // チャンス・ピンチ（仕様書 §5）：得点圏。7回以降の1点差以内・同点は1.5倍
        final int scoreGap = (state.homeScore - state.awayScore).abs();
        final double clutchMul = !isRISP ? 0.0 : ((state.inning >= 7 && scoreGap <= 1) ? 1.5 : 1.0);
        //  チャンス：打者の能力（ミート・パワー・選球眼）がまとめて上がる。ピンチ：投手の能力（球速・球威・制球・キレ・変化量・重さ）がまとめて上がる
        final int bClutchBonus = ((batter.clutch - 60) * clutchBatK * clutchMul).round();
        final int pClutchBonus = ((pitcher.clutchPitching - 60) * clutchPitK * clutchMul).round();

        // 低能力側の効果を緩和（能力が低くても極端に打てなくならないように）
        int soften(int r) => r >= 60 ? r : (60 - (60 - r) * 0.65).round();
        double lvC = 60; // 打者と投手の水準の中間
        if (levelCenter) {
          final bl = (bMeet + bPower + bEye) / 3;
          final pl = (Velo.norm(pitcher.velocity + pForm ~/ 3, slot: pitcher.armSlot) + pitcher.pitchPower + pForm + pitcher.control + pForm) / 3;
          lvC = (bl + pl) / 2;
        } else {
          bMeet = soften(bMeet); bPower = soften(bPower); bEye = soften(bEye);
        }
        // 計算に使う能力：中間を 60 に合わせ、中間からの差に levelGain を掛ける（能力差の効きの強さ）。チャンス・ピンチはその後に上乗せ
        double plv = 0, blv = 0; // 投手・打者の水準（差の向きで効きの強さを変える）
        if (levelCenter) { blv = (bMeet + bPower + bEye) / 3; plv = 2 * lvC - blv; }
        final double gain = !levelCenter ? 1.0 : (plv > blv ? levelGainP : levelGain);
        int bE(num x) => (60 + (x - lvC) * gain + bClutchBonus).round().clamp(1, 100);
        int pE(num x) => (60 + (x - lvC) * gain + pClutchBonus).round().clamp(1, 100);
        bMeet = bE(bMeet); bPower = bE(bPower); bEye = bE(bEye);
        _lvShift = pitcher.control - pE(pitcher.control);
        pControl = pE(pControl);
        // 打撃采配の代償・効果（ミート/パワー）
        if (batT == BatTactic.pullRight) { bMeet = (bMeet - 5).clamp(1, 100); } // 右方向を狙う分、打撃が窮屈になる
        if (batT == BatTactic.powerSwing) { bPower = (bPower + 5).clamp(1, 100); bMeet = (bMeet - 12).clamp(1, 100); } // 一発狙い
        if (batT == BatTactic.flyBall) { bMeet = (bMeet - 3).clamp(1, 100); }
        if (batT == BatTactic.patient) { bMeet = (bMeet + 4).clamp(1, 100); } // 粘れ：見極めてカットする
        if (batT == BatTactic.contactSwing) { bMeet = (bMeet + 8).clamp(1, 100); bPower = (bPower - 6).clamp(1, 100); } // ミート打ち
        if (batT == BatTactic.oppositeField) { bMeet = (bMeet + 4).clamp(1, 100); bPower = (bPower - 2).clamp(1, 100); } // 流し打ち
        if (batT == BatTactic.pullHit) { bMeet = (bMeet - 5).clamp(1, 100); bPower = (bPower + 3).clamp(1, 100); } // 引っ張り
        if (batT == BatTactic.chopDown) { bMeet = (bMeet + 2).clamp(1, 100); bPower = (bPower - 8).clamp(1, 100); } // 叩きつけ
        if (batT == BatTactic.firstPitch && state.balls + state.strikes == 0) { bMeet = (bMeet + 3).clamp(1, 100); } // 初球から積極的
        if (hitRun) { bMeet = (bMeet + 4).clamp(1, 100); } // ヒットエンドラン：確実に当てにいく
        if (pitT == PitchTactic.strikeout) { bMeet = (bMeet - 12).clamp(1, 100); } // 三振狙い：キレ重視で投げ込む
        if (pitT == PitchTactic.outsideFocus) { bPower = (bPower - 5).clamp(1, 100); } // 外角中心：長打は打たれにくい
        if (pitT == PitchTactic.groundOut) { bMeet = (bMeet + 5).clamp(1, 100); bPower = (bPower - 3).clamp(1, 100); } // 打たせて取る：当てやすい球で芯を外す（三振は減る）

        double currentSpeed = pVelocity.toDouble();
        double hBreak = 0.0, vBreak = 15.0;
        double bdx = 0.0, bdy = 0.0;
        String pName = 'ストレート';

        // 配球（球種と狙い所）。球種を指定されたときは、その球種で狙い所だけ決める
        final PitchCall call = _callPitch(s, pitcher, batter, pitT, fldT, lastPitchName, forced: cp?.pitchName);
        if (pitcher.pitches.isNotEmpty) {
           final Pitch selectedPitch = call.pitch;
           currentSpeed = (selectedPitch.speed + pForm ~/ 3).toDouble().clamp(70.0, 180.0); // 未知の球種でも物理が破綻しないよう範囲内に収める
           pName = selectedPitch.name;
           pSharpness = pE(selectedPitch.sharpness + pForm);
           pBreakAmt = selectedPitch.breakLevel.clamp(0, 100);
           // 変化の向きと大きさ（変化球ベクトル図と同じ向き: 角度0=右、90=下）
           final int pAngle = selectedPitch.name == 'ナックル' ? _rand.nextInt(360) : selectedPitch.angle; // ナックルは毎球向きが変わる
           pHeavy = pE(selectedPitch.heaviness);
           bdx = selectedPitch.breakLevel / 100.0 * cos(pAngle * pi / 180);
           bdy = selectedPitch.breakLevel / 100.0 * sin(pAngle * pi / 180);

           double armRad = pitcher.spinAxis * (3.14159 / 180.0);
           double rad = pAngle * (3.14159 / 180.0) - armRad;

           hBreak = (pBreakAmt / 100.0) * 45.0 * cos(rad);
           vBreak = - (pBreakAmt / 100.0) * 45.0 * sin(rad);
        }

        // 投手采配：全力投球（球速・キレ↑、消耗大）／コントロール重視（制球↑、球速・キレ↓）
        if (pitT == PitchTactic.fullPower) { currentSpeed += 3; pSharpness = (pSharpness + 8).clamp(1, 100); }
        if (pitT == PitchTactic.controlFocus) { currentSpeed -= 4; pSharpness = (pSharpness - 8).clamp(1, 100); pControl = (pControl + 8).clamp(1, 100); }

        final double maxPitches = staminaLimit(pitcher);
        double fatigue = 0.0;
        if (totalPitches > maxPitches) {
           fatigue = ((totalPitches - maxPitches) / 40.0).clamp(0.0, 0.30);
        }

        currentSpeed = currentSpeed - (_rand.nextDouble() * 5.0) - (currentSpeed * fatigue * 0.05);
        pSharpness = (pSharpness * (1.0 - fatigue) - _rand.nextDouble() * 5.0).toInt().clamp(1, 100);
        pControl = (pControl * (1.0 - fatigue * 1.5) - _rand.nextDouble() * 5.0).toInt().clamp(1, 100);

        hBreak *= (1.0 - fatigue);
        vBreak *= (1.0 - fatigue);

        double targetX = batSide * call.x, targetZ = call.z;
        if (cp != null && cp.hasTarget && (call.zone || cp.ballTarget)) { // 狙い所の指定（ストライクのマスは、ストライクを取りにいく球で。ボールのマスは毎球）
          // 「[コース]に[球種]を投げろ」：5×5のマスの中心を狙う（打者から見て内/外、高め/低め。外側の一回りはボール球）
          final double side = batter.bats == 'L' ? -1.0 : 1.0;
          targetX = side * (2 - cp.targetCol!) * 0.67 + (_rand.nextDouble() - 0.5) * 0.3;
          targetZ = (2 - cp.targetRow!) * 0.67 + (_rand.nextDouble() - 0.5) * 0.3;
        }
        if (pitchOut) { // 外せ：打者の届かない外角へ大きく外す
          targetX = (batter.bats == 'L' ? -1.0 : 1.0) * -1.8;
          targetZ = 0.3;
        }
        // 失投：制球が悪いほど、狙いより真ん中へ甘く入る（変化球は曲がりきらない）
        final bool hanging = !pitchOut && usePhysics && Spec.pit && _rand.nextDouble() < Spec.mistakeRate(pControl);
        if (hanging) {
          targetX *= 0.25;
          targetZ = targetZ * 0.25 + 0.15;
          _inc('hangingPitches');
        }

        // 制球による誤差（正規分布）。制球が高いほど狙い通りに投げ込める
        // 小雨の中はボールが滑り、制球の誤差が 15% 大きい
        final double wetCtrl = s.weather.wetPlay ? 1.15 : 1.0;
        double controlSigma = (0.12 + (100 - pControl) * 0.0065) * wetCtrl;
        double actualX, actualZ;
        PitchKind? pk;
        PitchShot? shot;
        if (usePhysics) {
          // 3D 物理：投手は回転を織り込んで狙い、リリースの向きが制球の分だけぶれる。疲れると回転が弱まり、狙いより抜ける
          final Pitch thrown = pitcher.pitches.isNotEmpty ? call.pitch : Player.fielderStraight(pitcher.velocity);
          final bool quickMotion = state.runner1B != null || state.runner2B != null || state.runner3B != null;
          pk = PitcherPhysics.of(pitcher).kind(thrown, quick: quickMotion, env: s.env);
          var spinScale = (1.0 - fatigue * 0.5) * (1.0 + _gauss() * 0.03);
          if (hanging && !PitchCatalog.isFastLike(thrown)) spinScale *= 0.6; // 抜けた変化球は曲がりきらない
          // 仕様書 6.2：直球のバックスピンは球威から（1900＋8×球威 rpm）
          if (Spec.pit && PitchCatalog.isFastLike(thrown) && pk.spin.rpm > 100) spinScale *= Spec.fastballRpm(pE(pitcher.pitchPower)) / pk.spin.rpm;
          shot = pk.throwAt(targetX, targetZ, speedKmh: currentSpeed, spinScale: spinScale, sigma: controlSigma, sigmaRad: Spec.pit ? Spec.controlSigma(pControl) * wetCtrl * pi / 180 : null, gauss: _gauss);
          actualX = shot.x;
          actualZ = shot.z;
          if (thrown.name == 'ナックル') { // 無回転の揺れは毎球ちがう
            actualX += _gauss() * 0.25;
            actualZ += _gauss() * 0.25;
          }
        } else {
          actualX = targetX + _gauss() * controlSigma;
          actualZ = targetZ + _gauss() * controlSigma;
        }

        bool isStrike = (actualX >= -1.0 && actualX <= 1.0 && actualZ >= -1.0 && actualZ <= 1.0);
        // 仕様書 0.2：ゾーンの高さは打者の身長から（膝の下 0.27H 〜 0.56H）、幅はボールがかすめる ±0.2525m。zx・zz はその打者のゾーンでの座標
        double zx = actualX, zz = actualZ;
        if (Spec.zon) {
          final hb = batter.height / 100.0;
          final lo = Spec.zoneLow(hb), hi = Spec.zoneHigh(hb);
          zx = actualX * Zone.halfW / Spec.zoneHalfWidth;
          zz = (Zone.worldZ(actualZ) - (lo + hi) / 2) / ((hi - lo) / 2 + Spec.ballR);
          isStrike = zx.abs() <= 1 && zz.abs() <= 1;
        }

        String courseX = "真ん中";
        if (batter.bats == 'L') {
            if (actualX < -0.33) courseX = "インコース";
            else if (actualX > 0.33) courseX = "アウトコース";
        } else {
            if (actualX > 0.33) courseX = "インコース";
            else if (actualX < -0.33) courseX = "アウトコース";
        }

        String courseY = "真ん中";
        if (actualZ < -0.33) courseY = "低め";
        else if (actualZ > 0.33) courseY = "高め";

        String courseStr = (courseX == "真ん中" && courseY == "真ん中") ? "ど真ん中" : "${courseX}${courseY}";
        bool isBorder = (actualX.abs() > 0.8 && actualX.abs() < 1.1) || (actualZ.abs() > 0.8 && actualZ.abs() < 1.1);
        String courseExtra = isBorder ? '（コースいっぱい）' : '';

        String pitchLog = '$pitchCount球目 ${currentSpeed.toInt()}km/h $pName $courseStr$courseExtra${call.note}　';
        final ev = PitchEvent(paIndex: paIndex, pitchNo: pitchCount, battingHome: !state.isTop, batter: batter.registeredName, batterHand: batter.bats, pitcher: pitcher.registeredName, pitchName: pName, speed: currentSpeed, x: actualX, z: actualZ, inZone: isStrike, balls: state.balls, strikes: state.strikes);
        ev.breakDX = bdx;
        ev.breakDY = bdy;
        ev.phys = pk;
        ev.shot = shot;
        // 3D 用：全球に守っていた9人・打者・走者を付ける（打球になったときは下で同じものを入れ直す）。乱数は使わない
        ev.fielderPlayers = _defenseMapOf(s, pitcher, defenseTeam);
        ev.batterPlayer = batter;
        {
          final ord = state.isTop ? s.awayOrder : s.homeOrder;
          Player? rp(String? name) => name == null ? null : (ord.where((x) => x.registeredName == name).firstOrNull ?? batter);
          ev.runnerPlayers = [rp(state.runner1B), rp(state.runner2B), rp(state.runner3B)];
        }
        ev.env = s.env;
        final sr = stealRec;
        if (sr != null) {
          // 盗塁した走者は、元の塁から走る
          ev.stealFrom = sr.from;
          ev.stealSafe = sr.safe;
          final rps = [...ev.runnerPlayers];
          rps[sr.from - 1] = sr.runner;
          if (sr.from < 3) rps[sr.from] = null;
          ev.runnerPlayers = rps;
          stealRec = null;
        }
        s.pitchEvents.add(ev);
        _ctxBefore(s, ev, bStats, gamePitchCounts[pitcher.id] ?? 0);

        // ---- 配球の駆け引き：打者の意識と球種の慣れ ----
        final double inX = actualX * batSide; // + が内角
        final double aware = s.insideAware[vsKey] ?? 0.0;
        double awareSwing = 0.0;
        if (inX < -0.3) {
          bMeet = (bMeet - (8 * aware).round()).clamp(1, 100); // 内角を意識させられていると、外の球に届かない
          if (!isStrike) awareSwing = 0.08 * max(0.0, aware);   // 外へ逃げる球に手が出る
        } else if (inX > 0.3) {
          bMeet = (bMeet + (6 * aware).round()).clamp(1, 100); // 内角を待っていれば打てる。外を待っていると詰まる
        }
        if (facedBefore > 0) {
          // 前の打席で見た球種は目が慣れて打ちやすく、見ていない球種は打ちにくい
          bMeet = (bMeet + (seenBeforePa.contains(pName) ? min<int>(6, facedBefore * 2) : -6)).clamp(1, 100);
        }
        final bool fastPitch = pBreakAmt <= 20;
        s.insideAware[vsKey] = (aware + (inX > 0.35 ? (fastPitch ? 0.30 : 0.15) + (inX > 1.0 ? 0.15 : 0.0) : (inX < -0.35 ? -0.12 : 0.0))).clamp(-1.0, 1.0);
        s.seenPitches.putIfAbsent(vsKey, () => <String>{}).add(pName);
        s.shownPitches.putIfAbsent(pitcher.id, () => <String>{}).add(pName);
        lastPitchName = pName;
        
        List<String> runners = [];
        if (state.runner1B != null) runners.add('1塁');
        if (state.runner2B != null) runners.add('2塁');
        if (state.runner3B != null) runners.add('3塁');
        String runnerState = runners.isEmpty ? 'ランナー無し' : runners.join(',');

        double zoneDist = max(zx.abs(), zz.abs()); // 1.0=ゾーン端

        // スイング判断：選球眼(eye)が高いほどボール球に手を出さず、ゾーン内を振る
        double eyeAdj = (bEye - 60) / 100.0;
        double baseSwingProb;
        if (isStrike) {
          baseSwingProb = zoneSwingBase + eyeAdj * 0.15;
          if (state.strikes == 0) baseSwingProb -= state.balls == 0 ? firstPitchTake : 0.20; // 初球は見ていくことが多い
          if (state.strikes == 2) baseSwingProb += 0.22;
          if (state.balls == 3 && state.strikes < 2) baseSwingProb -= 0.30;
        } else {
          baseSwingProb = chaseBase * (zoneDist < 1.3 ? 1.3 : (zoneDist < 1.7 ? 0.85 : 0.45));
          baseSwingProb -= eyeAdj * 0.25;
          if (state.strikes == 2) baseSwingProb += 0.15;
          if (state.balls == 3 && state.strikes < 2) baseSwingProb -= 0.22;
          if (pBreakAmt > 40) baseSwingProb += 0.08;
        }
        // ---- 采配による狙い・スイング補正 ----
        double launchBias = 0.0; // 打球角度の補正（°）
        baseSwingProb += awareSwing;
        if (batT == BatTactic.patient) { baseSwingProb += isStrike ? -0.12 : -0.10; }
        if (batT == BatTactic.contactSwing && isStrike) { baseSwingProb += 0.03; }
        if (batT == BatTactic.firstPitch && state.balls == 0 && state.strikes == 0) { baseSwingProb += isStrike ? 0.25 : 0.08; }
        if (batT == BatTactic.chopDown) { launchBias -= 3.0; }
        if (batT == BatTactic.powerSwing) { baseSwingProb += isStrike ? 0.06 : 0.04; }
        if (batT == BatTactic.flyBall) { launchBias += 0.5; }
        if (pitT == PitchTactic.groundOut) { launchBias -= 0.2; }
        if (pitT == PitchTactic.doublePlay) { launchBias -= 0.3; }
        if (batT == BatTactic.lowBall || batT == BatTactic.highBall) {
          final bool match = batT == BatTactic.lowBall ? actualZ < -0.2 : actualZ > 0.2;
          baseSwingProb += match ? 0.12 : -0.08;
          bMeet = (bMeet + (match ? 10 : -8)).clamp(1, 100);
        }
        if (batT == BatTactic.fastballFocus || batT == BatTactic.breakingFocus) {
          final bool isFast = pBreakAmt <= 20;
          final bool match = batT == BatTactic.fastballFocus ? isFast : !isFast;
          baseSwingProb += match ? 0.08 : -0.06;
          bMeet = (bMeet + (match ? 10 : -10)).clamp(1, 100);
        }
        if (hitRun) { baseSwingProb = max(baseSwingProb, 0.93); }
        if (cp != null && cp.hasTarget) {
          // 指定コースの難しさ: ど真ん中は打たれやすく、四隅は打ちにくい
          final bool center = cp.targetCol == 2 && cp.targetRow == 2;
          final bool corner = !cp.ballTarget && cp.targetCol != 2 && cp.targetRow != 2; // ゾーンの四隅
          bMeet = (bMeet + (center ? 10 : (corner ? -5 : 0))).clamp(1, 100);
        }
        baseSwingProb = baseSwingProb.clamp(0.02, 0.97);

        _inc('pitches'); _inc(isStrike ? 'zonePitches' : 'ballPitches');
        bool swung = _rand.nextDouble() < baseSwingProb;
        if (cmd == PitchCommand.take) swung = false;   // 待て
        if (pitchOut) swung = hitRun;                  // 外された球。エンドランなら打者は飛びつく（空振り）
        if (swung) { _inc('swings'); _inc(isStrike ? 'zoneSwings' : 'ballSwings'); }

        // ---- バント：ボール球は見送り、それ以外はバットに当てにいく ----
        if (bunting && cmd != PitchCommand.take) {
          if (!isStrike && zoneDist > 1.15) {
            swung = false; // バットを引く
          } else {
            // バントのファウル：高め・変化の大きい球ほど上下の芯がずれてファウルになりやすい（感度 BuntBall.eySens）
            final brkB = min(1.0, sqrt(ev.breakDX * ev.breakDX + ev.breakDY * ev.breakDY));
            final double foulP = (0.24 - (bMeet - 60) * 0.004 + BuntBall.eySens * (0.08 * max(0.0, ev.z - 0.2) + 0.05 * brkB) + (pitchOut ? 0.6 : 0.0)).clamp(0.06, 0.95);
            if (_rand.nextDouble() < foulP) {
              ev.result = 'ファウル';
              state.addStrike();
              if (state.strikes >= 3) {
                pitchLog += 'スリーバント失敗（三振）';
                batter.seasonStats.strikeouts++;
                pitcher.seasonStats.pitcherStrikeouts++;
                bStats['so'] = (bStats['so'] ?? 0) + 1;
                bStats['ab'] = (bStats['ab'] ?? 0) + 1; batter.seasonStats.atBats++;
                pStats['so'] = (pStats['so'] ?? 0) + 1;
                atBatOver = true;
                state.addOut();
              } else {
                pitchLog += 'バント（ファウル）';
              }
              pitchLog += ' [$runnerState]';
              ev.desc = pitchLog;
              playByPlay.add(pitchLog);
              pitchByPitch.add(pitchLog); ev.desc = pitchLog; _ctxAfter(s, ev);
              continue;
            }
            resolveBunt(ev, '$pitchCount球目 ${currentSpeed.toInt()}km/h $pName ');
            break;
          }
        }

        if (!swung) {
          // 見逃しの判定：ゾーンの端は審判の見え方で揺れ、捕手のフレーミングで広がる
          final bool called = usePhysics ? Framing.calledStrike(zx, zz, defenseNow()['C'], _rand) : isStrike;
          ev.result = called ? '見逃し' : 'ボール';
          if (called) {
             state.addStrike();
             pitchLog += state.strikes >= 3 ? '見逃し三振' : '見逃しストライク';
             final lp = _loosePitch(actualX, actualZ, defenseNow()['C'], k3: state.strikes >= 3, outsBefore: state.outs, firstOccupied: state.runner1B != null);
             if (state.strikes >= 3) {
               batter.seasonStats.strikeouts++;
               pitcher.seasonStats.pitcherStrikeouts++;
               bStats['so'] = (bStats['so'] ?? 0) + 1;
               bStats['ab'] = (bStats['ab'] ?? 0) + 1; batter.seasonStats.atBats++;
               pStats['so'] = (pStats['so'] ?? 0) + 1;
               atBatOver = true;
               if (lp.reach) {
                 pitchLog += '（振り逃げで一塁へ）';
                 _inc('droppedK');
                 _advanceOnLoose(s, pitcher, forcedOnly: !lp.away);
                 state.runner1B = batter.registeredName;
               } else {
                 state.addOut();
               }
             } else if (lp.away) {
               pitchLog += lp.dirt ? '（暴投）' : '（捕逸）';
               _inc('wildPitch');
               _advanceOnLoose(s, pitcher);
             }
          } else {
             // 内角に大きく外れた球は、死球になることがある（四球と同じく打者は一塁へ）
             final bool hbp = inX > 1.3 && _rand.nextDouble() < ((inX - 1.3) * 0.12).clamp(0.0, 0.06);
             if (!hbp) state.addBall();
             pitchLog += hbp ? '死球' : (state.balls >= 4 ? '四球' : 'ボール');
             if (!hbp && state.balls < 4) {
               final lp = _loosePitch(actualX, actualZ, defenseNow()['C'], k3: false, outsBefore: state.outs, firstOccupied: state.runner1B != null);
               if (lp.away && (state.runner1B != null || state.runner2B != null || state.runner3B != null)) {
                 pitchLog += lp.dirt ? '（暴投）' : '（捕逸）';
                 _inc('wildPitch');
                 _advanceOnLoose(s, pitcher);
               }
             }
             if (hbp || state.balls >= 4) {
                if (hbp) {
                  ev.result = '死球';
                  batter.seasonStats.hbp++;
                  pitcher.seasonStats.hbpAllowed++;
                } else {
                  batter.seasonStats.walks++;
                  pitcher.seasonStats.pitcherWalks++;
                  bStats['bb'] = (bStats['bb'] ?? 0) + 1;
                  pStats['bb'] = (pStats['bb'] ?? 0) + 1;
                }
                atBatOver = true;

                int runs = 0;
                if (state.runner1B != null && state.runner2B != null && state.runner3B != null) {
                  s.forcedRuns[state.runner3B!] = (s.forcedRuns[state.runner3B!] ?? 0) + 1; // 押し出しで還った走者（得点の記録用）
                  state.addScore(1); runs = 1;
                } else if (state.runner1B != null && state.runner2B != null) {
                  state.runner3B = state.runner2B; state.runner2B = state.runner1B;
                } else if (state.runner1B != null) {
                  state.runner2B = state.runner1B;
                }
                state.runner1B = batter.registeredName;

                if (runs > 0) {
                  batter.seasonStats.rbi += runs;
                  pitcher.seasonStats.earnedRuns += runs;
                  bStats['rbi'] = (bStats['rbi'] ?? 0) + runs;
                  pStats['er'] = (pStats['er'] ?? 0) + runs;
                  if (state.inning >= 9 && !state.isTop && state.homeScore > state.awayScore) {
                      pitchLog += ' 【サヨナラ押し出し！！】';
                      atBatOver = true; state.outs = 3;
                  }
                }
             }
          }
          pitchLog += ' [$runnerState]';
          playByPlay.add(pitchLog);
          pitchByPitch.add(pitchLog); ev.desc = pitchLog;
          // 走っていた走者：見逃し・ボールの球で判定（四球で押し出された・暴投で進んだときは判定しない）
          if (goFrom != 0) doSteal(pitchOut, kmh: currentSpeed, ax: actualX, az: actualZ, ev: ev);
          _ctxAfter(s, ev);
          continue;
        }

        double heightM = pitcher.height / 100.0;
        double armDropRatio = 0.95 - (pitcher.spinAxis / 180.0) * 0.75; 
        double rZ = 0.25 + (heightM * armDropRatio);
        double rX = (pitcher.throws == 'L') ? 0.5 : -0.5;

        late List<double> offsets;
        if (usePhysics && pk != null) {
          // 打者は直球のつもりで最後の約0.15〜0.2秒の軌道を読む。直球との加速度の差だけ予測がずれる（x は投手から見て右が＋）
          final double tRem = 0.15 + (pSharpness / 100.0) * 0.05;
          final double late = 0.5 * tRem * tRem * lateBreakK * (shot?.spinScale ?? 1.0);
          offsets = PitchPhysics.finishOffset(
            errorX: -pk.aLate.x * late + perceiveX,
            errorZ: pk.aLate.z * late + perceiveZ,
            bMeet: bMeet.toDouble(),
            bEye: bEye.toDouble(),
            prevSpeedKmh: prevSpeedKmh,
            currentSpeedKmh: currentSpeed,
            sharpness: pSharpness.toDouble(),
            breakAmount: pBreakAmt.toDouble(),
            locationDifficulty: max(0.0, zoneDist - 0.8),
          );
        } else {
        PitchTrajectory actualTrajectory = PitchPhysics.simulatePitch(
            releaseZ: rZ,
            releaseX: rX,
            initialSpeedKmh: currentSpeed,
            hBreak: hBreak,
            vBreak: vBreak,
            // ゾーン正規化座標(±1=ゾーン端)をメートルに変換（ゾーン幅±0.22m、高さ0.45〜1.05m）
            targetX: actualX * 0.22,
            targetZ: 0.75 + actualZ * 0.28,
        );

        offsets = PitchPhysics.calculateBatOffset(
            actualPitch: actualTrajectory,
            bMeet: bMeet.toDouble(),
            bEye: bEye.toDouble(),
            prevSpeedKmh: prevSpeedKmh,
            currentSpeedKmh: currentSpeed,
            sharpness: pSharpness.toDouble(),
            breakAmount: pBreakAmt.toDouble(),
            locationDifficulty: max(0.0, zoneDist - 0.8),
        );
        }

        // ---- 打撃の物理（第3章）：打者の読み → タイミング・芯ずれ → インパクトの6変数 → 衝突 ----
        SwingOutcome? sw;
        if (usePhysics && batPhysics && pk != null && shot != null && !pitchOut) {
          final Pitch thrown = pitcher.pitches.isNotEmpty ? call.pitch : Player.fielderStraight(pitcher.velocity);
          final Pitch? guess = batterResponse ? _guessPitch(pitcher, batT, state.balls, state.strikes) : null;
          // 基準合わせ：打者が受ける球は、ずらした水準の速さ（rv 倍）と曲がり幅（rb 倍）にする
          final double rv = (!levelCenter && pClutchBonus == 0) ? 1.0 : Velo.fromNorm(pE(Velo.norm(currentSpeed.round()))) / currentSpeed;
          final double rb = ((!levelCenter && pClutchBonus == 0) || pBreakAmt <= 0) ? 1.0 : pE(pBreakAmt) / pBreakAmt;
          sw = SwingModel.swing(
            BatterSkill(meet: bMeet, power: bPower, eye: bEye, trajectory: bTrajectory, pull: (pullTendency(batter) / 12).clamp(0.0, 1.0), lefty: effHand == 'L', bat: batter.bat),
            _swingRead(pitcher, batT, state.balls, state.strikes),
            IncomingPitch(
              perceivedKmh: Velo.fromNorm(pE(Velo.norm((_swingRead(pitcher, batT, state.balls, state.strikes).vFast + Velo.slotBonus(pitcher.armSlot)).round()))).toDouble(), stuff: pE(pitcher.pitchPower + pForm),
              guessKmh: guess == null ? 0 : (guess.speed + pForm ~/ 3) * rv,
              guessALate: guess == null ? V3.zero : PitcherPhysics.of(pitcher).kind(guess, quick: state.runner1B != null || state.runner2B != null || state.runner3B != null, env: s.env).aLate * rb,
              guessSame: guess != null && guess.name == thrown.name, prevKmh: prevKmhPa * rv,
              speedKmh: currentSpeed * rv, time: shot.time / rv, vel: pk.vCross * (shot.speed / pk.vRef * rv), omega: pk.spin.omega * (shot.spinScale * exp(-shot.time / BallSpec.spinDecayTau)),
              aLate: pk.aLate * (shot.spinScale * rb), zoneX: actualX, zoneZ: actualZ, fastLike: PitchCatalog.isFastLike(thrown), sharp: pSharpness,
              brk: (pBreakAmt <= 0 ? 0 : pE(pBreakAmt)) / 100.0, hanging: hanging),
            rnd: _rand,
            corScale: Spec.pit ? Spec.heavyCor(pHeavy) : 1.0, // 仕様書 6.2：重さ
            launchBias: launchBias,
            betaBias: batT == BatTactic.pullRight ? 12.0 : (batT == BatTactic.oppositeField ? (effHand == 'L' ? -10.0 : 10.0) : (batT == BatTactic.pullHit ? (effHand == 'L' ? 6.0 : -6.0) : 0.0)),
            speedMul: batT == BatTactic.powerSwing ? 1.03 : (batT == BatTactic.contactSwing ? 0.96 : 1.0),
            twoStrikes: state.strikes == 2,
            edge: hanging ? -0.3 : max(0.0, zoneDist - 0.8), // 失投は芯でとらえやすい
          );
        }

        if (sw != null) { // 検証用の集計：緩急（直前の球との差）・変化量ごとの空振りと弱い当たり
          final dd = (currentSpeed - prevKmhPa).abs();
          final dk = prevKmhPa <= 0 ? 'first' : (dd >= 30 ? 'd30' : (dd >= 15 ? 'd15' : 'd0'));
          final bk = pBreakAmt < 1 ? 'b0' : (pBreakAmt < 35 ? 'b1' : (pBreakAmt < 60 ? 'b2' : 'b3'));
          for (final k in [dk, bk]) {
            _inc('br_sw_$k');
            if (sw.whiff) _inc('br_wh_$k');
            if (sw.ball != null) { _inc('br_bip_$k'); if (sw.ball!.speed < 36) _inc('br_weak_$k'); }
          }
        }
        double diffX = offsets[0] * contactEase;
        double diffZ = offsets[1] * contactEase;
        double R = sqrt(diffX * diffX + diffZ * diffZ);

        prevSpeedKmh = currentSpeed; prevKmhPa = currentSpeed;

        if ((sw != null ? sw.whiff : R > 0.069) || pitchOut) {
           _inc('whiffs');
           ev.result = '空振り';
           state.addStrike();
           pitchLog += state.strikes >= 3 ? '空振り三振' : '空振り';
           final lp = pitchOut ? (reach: false, away: false, dirt: false) : _loosePitch(actualX, actualZ, defenseNow()['C'], k3: state.strikes >= 3, outsBefore: state.outs, firstOccupied: state.runner1B != null);
           if (state.strikes >= 3) {
              batter.seasonStats.strikeouts++;
              pitcher.seasonStats.pitcherStrikeouts++;
              bStats['so'] = (bStats['so'] ?? 0) + 1;
              bStats['ab'] = (bStats['ab'] ?? 0) + 1; batter.seasonStats.atBats++;
              pStats['so'] = (pStats['so'] ?? 0) + 1;
              atBatOver = true;
              if (lp.reach) {
                pitchLog += '（振り逃げで一塁へ）';
                _inc('droppedK');
                _advanceOnLoose(s, pitcher, forcedOnly: !lp.away);
                state.runner1B = batter.registeredName;
              } else {
                state.addOut();
              }
           } else if (lp.away) {
              pitchLog += lp.dirt ? '（暴投）' : '（捕逸）';
              _inc('wildPitch');
              _advanceOnLoose(s, pitcher);
           }
           pitchLog += ' [$runnerState]';
           ev.desc = pitchLog;
           playByPlay.add(pitchLog);
           pitchByPitch.add(pitchLog); ev.desc = pitchLog;
           // 走っていた走者（盗塁・ヒットエンドランの空振り）：空振りの球で判定。三振なら「三振ゲッツー」もある
           if (goFrom != 0) doSteal(pitchOut, kmh: currentSpeed, ax: actualX, az: actualZ, ev: ev);
           _ctxAfter(s, ev);
           continue;
        }

        // 打点のズレを角度に変換。ズレが大きいほど引っ掛け・詰まりで打球が散る
        double verticalContactAngle = asin((diffZ / (0.069 * _vSpread)).clamp(-1.0, 1.0)) * 180.0 / pi;
        double horizontalAngle = -asin((diffX / (0.069 * _hSpread)).clamp(-1.0, 1.0)) * 180.0 / pi;
        bool rightSide = false;
        final double pullSign = effHand == 'L' ? 1.0 : -1.0; // 引っ張り方向（+ が右方向）
        if (sw != null) { verticalContactAngle = 0; horizontalAngle = 0; }
        if (batT == BatTactic.pullRight) { horizontalAngle += 12.0; rightSide = horizontalAngle > 8.0; }
        // 打球の向き（+ が右方向）。右打者の引っ張りは左方向
        double swingPlaneAngle = 13.0 + (bTrajectory - 2) * 0.5; // 弾道1〜4（1ランクで0.5°。HRは1ランクごとに約1.5倍）
        double launchAngle = sw != null ? sw.ball!.launch : swingPlaneAngle - verticalContactAngle + launchBias;
        if (sw != null) horizontalAngle = sw.ball!.vel.y <= 0 ? (sw.ball!.vel.x >= 0 ? 60.0 : -60.0) : sw.ball!.direction;
        // ゴロは特に引っ張り方向へ偏る（フライは広角に散る）
        // 流し打ちは引っ張りの癖を抑えて逆方向へ、引っ張りは癖を強める
        final double pullMult = batT == BatTactic.oppositeField ? -0.2 : (batT == BatTactic.pullHit ? 1.5 : 1.0);
        if (sw == null) horizontalAngle += pullSign * pullTendency(batter) * (launchAngle < 10.0 ? 3.5 : 0.8) * pullMult;
        // 追い込まれた打者は、芯を外れた球をカットして逃げる（ミートが高いほど上手い）
        // 芯を外した当たりはバックネット・三塁側へのファウルになりやすい
        final bool foulBack = sw == null && R > 0.040 && _rand.nextDouble() < foulBase;
        if (foulBack || (sw == null && state.strikes == 2 && R > 0.035 && _rand.nextDouble() < (cutBase + (bMeet - 60) * 0.005).clamp(0.05, 0.8))) {
          horizontalAngle = horizontalAngle >= 0 ? 50.0 : -50.0;
          _inc('cuts');
        }

        double vPitch = currentSpeed / 3.6; 
        // パワー1ポイントあたりのスイング速度。80超は伸びを緩やかにして上限の暴走を抑える
        double vBat = batSpeedBase + (bPower - 60) * powerSlope - max(0, bPower - 70) * 0.013 - max(0, bPower - 90) * 0.015;
        double penalty = pow(cos((R / 0.069) * (pi / 2.0)), 2.0).toDouble();
        double vExit = sw != null ? sw.ball!.speed : (0.08 * vPitch + 1.05 * vBat) * (mishitFloor + (1.04 - mishitFloor) * pow(penalty, 0.6));
        // 球威：高いほど芯で捉えても打球が飛ばない（重い球）
        final pPow = (pE(pitcher.pitchPower + pForm) + (pHeavy - heavyRef) * heavyEffect).round().clamp(1, 100); // 球種の重さも効く
        if (!Spec.pit || sw == null) vExit *= (1.0 - (pPow - pitchPowerRef) * pitchPowerEffect).clamp(0.85, 1.12); // 仕様書では球威は回転、重さは反発で効く

        PhysicsEngine pEngine = PhysicsEngine();
        // バックスピンは打球角度に応じて付く（フライには揚力、ゴロにはトップスピン）
        double spinRpm = (1000.0 + 40.0 * min(launchAngle, 30.0)).clamp(-1500.0, 2200.0);
        // 打球の出発点：投球が来たコース（本塁の前縁の少し前でバットに当たる）。3D の再生もこの点でバットの芯が当たる
        final hitStart = switch (hitStartMode) { 0 => const V3(0, 0, 1.0), 1 => V3(Zone.worldX(actualX), contactY, 1.0), 3 => V3(Zone.worldX(actualX), 0, 1.0), 4 => const V3(0, contactY, 1.0), _ => V3(Zone.worldX(actualX), contactY, Zone.worldZ(actualZ).clamp(0.25, 1.6)) };
        HitVector hit = sw != null ? HitVector(vExit, launchAngle, horizontalAngle, sw.ball!.backspinRpm, omega: sw.ball!.omega, start: hitStart) : HitVector(vExit, launchAngle, horizontalAngle, spinRpm, start: hitStart);
        List<Vector3D> trajectory = pEngine.simulateTrajectory(hit, env: s.env);
        // 仕様書 1.2：フェアかファウルかは打球の通り道で決める（物理の打撃）。打ち出しの向きだけでは決めない
        final bool foulBall = sw != null && foulByPath ? isFoulTrajectory(trajectory) : (horizontalAngle < -45.0 || horizontalAngle > 45.0);
        if (foulBall && horizontalAngle.abs() <= 45) {
          _inc('foulByPath');
          _inc('foulByPath_${launchAngle < 10 ? 'G' : (launchAngle < 25 ? 'L' : (launchAngle < 45 ? 'F' : 'P'))}');
        }
        if (!foulBall && horizontalAngle.abs() > 45) _inc('fairByPath');
        if (debugStats.isNotEmpty && sw != null && launchAngle >= 25 && launchAngle < 45) {
          // フライの曲がり（着地点の角度 − 打ち出しの角度。＋＝外へ）
          final li = trajectory.indexWhere((p) => p.z <= 0.001);
          final lp3 = li > 0 ? trajectory[li] : trajectory.last;
          final da = (atan2(lp3.x, lp3.y) * 180 / pi - horizontalAngle) * (horizontalAngle >= 0 ? 1 : -1);
          _inc('drift_${(da / 2).round() * 2}');
          _inc('side_${((sw.ball!.sidespinRpm.abs()) / 500).round() * 500}');
        }
        if (foulBall) {
           _inc('fouls');
           ev.result = 'ファウル';
           pitchLog += '打撃（ファウル）';
           // 高く上がったファウルフライは捕球されてアウトになることがある
           if (launchAngle > 40.0 && _rand.nextDouble() < 0.30) {
              pitchLog = pitchLog.replaceFirst('打撃（ファウル）', '打撃（ファウルフライ）捕球 (アウト)');
              bStats['ab'] = (bStats['ab'] ?? 0) + 1; batter.seasonStats.atBats++;
              atBatOver = true;
              pitchLog += ' [$runnerState]';
              playByPlay.add(pitchLog);
              pitchByPitch.add(pitchLog); ev.desc = pitchLog; _ctxAfter(s, ev);
              state.addOut();
              continue;
           }
           if (state.strikes < 2) state.strikes++;
           pitchLog += ' [$runnerState]';
           playByPlay.add(pitchLog);
           pitchByPitch.add(pitchLog); ev.desc = pitchLog; _ctxAfter(s, ev);
           continue;
        }
        _inc('inplay');
        ev.result = 'インプレー';


        // フェンス到達判定：最初にフェンス距離を越えた点の高さがフェンス高を超えていればHR
        bool isHomeRun = false;
        bool groundRule = false;
        bool landed = false; // 一度でも地面に着いたら、そのあと跳ねて越えても本塁打ではない（エンタイトル）
        for (int i = 0; i < trajectory.length; i++) {
          Vector3D pt = trajectory[i];
          if (i > 0 && (pt.z <= 0.001 || (trajectory[i - 1].vz < 0 && pt.vz > 0))) landed = true;
          double angleDeg = atan2(pt.x, pt.y) * 180.0 / pi;
          if (sqrt(pt.x * pt.x + pt.y * pt.y) >= PhysicsConstants.getFenceDistance(angleDeg)) {
            isHomeRun = !landed && pt.z > PhysicsConstants.getFenceHeight(angleDeg);
            groundRule = landed && pt.z > PhysicsConstants.getFenceHeight(angleDeg); // 仕様書 1.2：跳ねて越えたフェア打球はエンタイトルツーベース
            trajectory = trajectory.sublist(0, i + 1);
            if (!isHomeRun && !groundRule) trajectory = fenceRebound(trajectory, angleDeg);
            break;
          }
        }

        Map<String, Player> defenseMap = {};
        defenseMap['P'] = pitcher;
        for (var entry in (state.isTop ? s.homeLineup : s.awayLineup)) {
           if (entry.position != 'DH' && entry.position != '投') {
             String engPos = '';
             switch(entry.position) {
               case '捕': engPos = 'C'; break;
               case '一': engPos = '1B'; break;
               case '二': engPos = '2B'; break;
               case '三': engPos = '3B'; break;
               case '遊': engPos = 'SS'; break;
               case '左': engPos = 'LF'; break;
               case '中': engPos = 'CF'; break;
               case '右': engPos = 'RF'; break;
             }
             if (engPos.isNotEmpty) {
               Player p = defenseTeam.players.firstWhere((p) => p.id == entry.playerId, orElse: () => defenseTeam.players.first);
               defenseMap[engPos] = p;
             }
           }
        }

        FielderAI ai = FielderAI();
        List<FielderState> fielders = ai.initializeFielders(defenseMap, powerGuard: fldT == FieldTactic.powerGuard, infieldIn: fldT == FieldTactic.infieldIn, dpShift: fldT == FieldTactic.doublePlayShift, infieldBack: fldT == FieldTactic.infieldBack,
            shift: fldT == FieldTactic.pullShift ? (effHand == 'L' ? 1.0 : -1.0) : (fldT == FieldTactic.oppositeShift ? (effHand == 'L' ? -0.6 : 0.6) : 0.0), holdRunner: state.runner1B != null);
        final Map<String, List<double>> startPos = {for (final f in fielders) f.role: [f.x, f.y]};
        CatchResult? catchResult = isHomeRun ? null : ai.simulateDefense(trajectory, fielders);
        if (launchAngle < 10) _inc(catchResult == null ? 'gbc_抜けた' : (catchResult.isGroundBall ? 'gbc_${catchResult.fielderRole}' : 'gbc_ノーバン'));
        if (launchAngle >= 10 && launchAngle < 25) _inc(catchResult == null ? 'ldc_落ちた' : (catchResult.isGroundBall ? 'ldc_跳ねて${catchResult.fielderRole}' : 'ldc_${catchResult.fielderRole}'));

        bool isHit = false;
        int hitBases = 0;
        String playDesc = "";

        String contactType = "ゴロ";
        if (launchAngle < 10) contactType = "ゴロ";
        else if (launchAngle < 25) contactType = "ライナー";
        else if (launchAngle < 45) contactType = "フライ";
        else contactType = "ポップフライ";
        _inc('bip_$contactType');
        
        String dir = "センター";
        if (horizontalAngle < -15) dir = "レフト";
        else if (horizontalAngle > 15) dir = "ライト";

        String hitDetail = '打撃（$dir ${launchAngle.toInt()}° $contactType）';
        {
          int bi0 = trajectory.indexWhere((p) => p.z <= 0);
          Vector3D bounce0 = bi0 >= 0 ? trajectory[bi0] : trajectory.last;
          Vector3D lp = catchResult != null
              ? catchResult.catchPosition
              : (isHomeRun ? trajectory.last : (sqrt(bounce0.x * bounce0.x + bounce0.y * bounce0.y) >= 40.0 ? bounce0 : trajectory.last));
          ev.landX = lp.x;
          ev.landY = lp.y;
          ev.launch = launchAngle;
          ev.contact = contactType;
          ev.fielder = catchResult?.fielderRole ?? '';
          // アニメーション用: 軌跡（捕球・落下点まで）を間引いて保存
          int endIdx = trajectory.length - 1;
          if (catchResult != null) {
            final ci = trajectory.indexWhere((p) => (p.x - lp.x).abs() < 0.01 && (p.y - lp.y).abs() < 0.01);
            endIdx = ci >= 0 ? ci : (catchResult.catchTime / 0.05).round().clamp(1, trajectory.length - 1);
          } else if (!isHomeRun && bi0 >= 0 && sqrt(bounce0.x * bounce0.x + bounce0.y * bounce0.y) >= 40.0) {
            endIdx = bi0;
          }
          final step = max(1, endIdx ~/ 24);
          ev.path = [
            for (int i = 0; i <= endIdx; i += step) [trajectory[i].x, trajectory[i].y, max(0.0, trajectory[i].z)],
            [lp.x, lp.y, max(0.0, catchResult != null ? catchResult.catchPosition.z : trajectory[endIdx].z)],
          ];
          ev.flightTime = catchResult != null ? catchResult.catchTime : endIdx * 0.05;
          ev.fielderStart = startPos;
        }

        // ---- 打球処理: 捕球・送球・走者の勝負を時間で判定する（play_resolver.dart）----
        final order = state.isTop ? awayOrder : homeOrder;
        Player? runnerP(String? name) {
          if (name == null) return null;
          for (final x in order) { if (x.registeredName == name) return x; }
          return batter;
        }
        final runnersP = [runnerP(state.runner1B), runnerP(state.runner2B), runnerP(state.runner3B)];
        // 重圧（終盤・接戦・得点圏）と1点の重み（前進守備・終盤の接戦）：判断のぶれと送球先の選び方に効く
        final scoreDiff = state.homeScore - state.awayScore;
        final pressure = Judgment.pressure(inning: state.inning, scoreDiff: scoreDiff, risp: state.runner2B != null || state.runner3B != null);
        final runWeight = (fldT == FieldTactic.infieldIn ? 2.5 : 1.0) + (state.inning >= 8 && scoreDiff.abs() <= 1 ? 0.6 : 0.0);
        final resolver = PlayResolver(_rand, {for (final f in fielders) f.role: f}, startPos,
            runAdj: runAdj, hitRun: hitRun || goFrom == 1, // 盗塁のスタートを切っていた走者も、打球で先へ進みやすい
 infieldIn: fldT == FieldTactic.infieldIn, rightSide: rightSide, batterLefty: effHand == 'L', slowBall: vExit < 22, pressure: pressure, runWeight: runWeight);
        ev.call = ai.lastCall;
        ev.fielderPlayers = defenseMap;
        ev.batterPlayer = batter;
        ev.runnerPlayers = runnersP;
        ev.exitSpeed = vExit;
        ev.spray = horizontalAngle;
        ev.env = s.env;
        final int outsBeforePlay = state.outs;
        PlayOutcome? po;

        // エラー: 全走者が1つ進み、打者は一塁へ（失策。安打・自責点・打点にしない）
        PlayOutcome errorAdvance() {
          final e = PlayOutcome()..error = true;
          final nb = <String?>[batter.registeredName, null, null];
          for (int b = 3; b >= 1; b--) {
            final p = runnersP[b - 1];
            if (p == null) continue;
            if (b == 3) { e.runs++; e.moves.add(RunMove(p.registeredName, 3, 4, false, 0.2, 3.8)); }
            else { nb[b] = p.registeredName; e.moves.add(RunMove(p.registeredName, b, b + 1, false, 0.2, 3.8)); }
          }
          e.moves.add(RunMove(batter.registeredName, 0, 1, false, 0, 4.0));
          e.bases = nb;
          return e;
        }

        // インフィールドフライ（仕様書 1.5）：無死・一死で一・二塁か満塁、内野（本塁から42m 以内）に上がったフライ（ライナー・バントは除く）
        final bool infieldFly = state.outs < 2 && state.runner1B != null && state.runner2B != null && launchAngle >= 30 && !isHomeRun && !groundRule &&
            trajectory.isNotEmpty && () { final li = trajectory.indexWhere((p) => p.z <= 0.001); final lp2 = li > 0 ? trajectory[li] : trajectory.last; return sqrt(lp2.x * lp2.x + lp2.y * lp2.y) < 42; }();
        if (groundRule) {
           // エンタイトルツーベース：打者は二塁、全走者は2つ進む
           isHit = true; hitBases = 2; playDesc = "ワンバウンドでスタンドへ！エンタイトルツーベース";
           final g = PlayOutcome()..hit = true..hitBases = 2;
           final nb = <String?>[null, null, null];
           for (int b = 3; b >= 1; b--) {
             final p = runnersP[b - 1];
             if (p == null) continue;
             final to = b + 2;
             g.moves.add(RunMove(p.registeredName, b, min(4, to), false, 1.0, 1.0 + 2 * 3.2));
             if (to >= 4) { g.runs++; } else { nb[to - 1] = p.registeredName; }
           }
           g.moves.add(RunMove(batter.registeredName, 0, 2, false, 0.5, 0.5 + 2 * 3.4));
           nb[1] = batter.registeredName;
           g.bases = nb;
           po = g;
           _inc('groundRuleDouble');
        } else if (infieldFly && (catchResult == null || catchResult.isGroundBall || catchResult.fumble)) {
           // 落ちても（捕れなくても）打者はアウト。走者は進まなくてよい
           final g = PlayOutcome()..outs = 1;
           g.bases = [runnersP[0]?.registeredName, runnersP[1]?.registeredName, runnersP[2]?.registeredName];
           g.desc = 'インフィールドフライ（打者アウト）';
           playDesc = 'インフィールドフライ（打者アウト）';
           po = g;
           _inc('infieldFly');
        } else if (isHomeRun) {
           isHit = true; hitBases = 4; playDesc = "スタンドへ一直線！！ホームラン！";
        } else if (catchResult != null && !catchResult.isGroundBall) {
           // フライ・ライナーをノーバウンドで捕球
           String stanceStr = catchResult.stance == CatchStance.diving ? "ダイビングキャッチ！" :
                              catchResult.stance == CatchStance.jumping ? "ジャンプ一番のスーパーキャッチ！" : "キャッチ";
           final fly = fielders.firstWhere((f) => f.role == catchResult.fielderRole);
           if (Spec.fld ? catchResult.fumble : const {'LF', 'CF', 'RF'}.contains(catchResult.fielderRole) && _rand.nextDouble() < (1.0 - fly.player.catchSkill / 100.0) * dropErrorBase) {
             po = errorAdvance();
             ev.errorBy = catchResult.fielderRole;
             playDesc = "${catchResult.fielderRole}が落球！エラー出塁";
           } else {
           playDesc = "${catchResult.fielderRole}の$stanceStr (アウト)";
           po = resolver.flyOut(role: catchResult.fielderRole, fx: catchResult.catchPosition.x, fy: catchResult.catchPosition.y,
               tCatch: catchResult.catchTime, runners: runnersP, outsBefore: outsBeforePlay, liner: contactType == 'ライナー');
           playDesc += po.desc;
           }
        } else if (catchResult != null && const {'LF', 'CF', 'RF'}.contains(catchResult.fielderRole)) {
           // 跳ねた打球を外野手が捕球 → 外野へのヒット。打者の塁打は、走る時間と返球の時間で決める
           final ofp = fielders.firstWhere((f) => f.role == catchResult.fielderRole).player;
           final cx = catchResult.catchPosition.x, cy = catchResult.catchPosition.y;
           final tThrowOf = catchResult.catchTime + 0.2 + ThrowStyle.crowHop.transfer + ofp.glove.transferDelay;
           final st = _stretch(batter, resolver.throwTime(catchResult.fielderRole, cx, cy, tThrowOf, 2), Running.batterToBase(batter, 2, lefty: effHand == 'L'),
               resolver.throwTime(catchResult.fielderRole, cx, cy, tThrowOf, 3), Running.batterToBase(batter, 3, lefty: effHand == 'L'), outsBeforePlay, pressure, runAdj);
           hitBases = st.bases;
           playDesc = st.outAt == 2 ? "${catchResult.fielderRole}前へのヒット（二塁を狙うもタッチアウト）" : (hitBases == 2 ? "${catchResult.fielderRole}からの送球が返る間にツーベース！" : "${catchResult.fielderRole}前へのヒット");
           po = resolver.outfieldHit(role: catchResult.fielderRole, fx: cx, fy: cy,
               tField: catchResult.catchTime + 0.2, batterBases: hitBases, batter: batter, runners: runnersP, outsBefore: outsBeforePlay, flyBall: false, batterOutAt: st.outAt);
           playDesc += po.desc;
        } else if (catchResult != null) {
           // ゴロを内野手が捕球 → フォースアウト・併殺・一塁送球・内野安打
           FielderState fs = fielders.firstWhere((f) => f.role == catchResult.fielderRole);
           double handling = _rand.nextDouble() * 0.15 + min(fs.penaltyTimer, 1.2); // 体勢を整える分（握り替えと送球は投げ方で決まる）
           bool throwError = Spec.thr ? _specThrowError(fs.player, _hypot(catchResult.catchPosition.x - 19.4, catchResult.catchPosition.y - 19.4)) : _rand.nextDouble() < (1.0 - fs.player.throwAccuracy / 100.0) * throwErrorBase;
           if (catchResult.fumble) handling += Spec.refieldTime; // こぼして拾い直す
           if (throwError) {
              po = errorAdvance();
              ev.errorBy = catchResult.fielderRole;
              playDesc = "${catchResult.fielderRole}が悪送球！エラー出塁";
              // 3D の再生用：一塁へ投げて、それた送球（受ける野手の届く所を外れて後ろへ）
              final cx = catchResult.catchPosition.x, cy = catchResult.catchPosition.y;
              final dx = 19.4 - cx, dy = 19.4 - cy, dl = max(1.0, _hypot(dx, dy));
              final side = (_rand.nextBool() ? 1 : -1) * (2.0 + _rand.nextDouble() * 2);
              final wx = 19.4 + dx / dl * 5 - dy / dl * side, wy = 19.4 + dy / dl * 5 + dx / dl * side;
              final tRel = catchResult.catchTime + handling + Spec.transfer(fs.player.throwAccuracy);
              po.throws.add(ThrowLeg(cx, cy, wx, wy, tRel, tRel + _hypot(wx - cx, wy - cy) / 30));
           } else {
              po = resolver.groundBall(role: catchResult.fielderRole, fx: catchResult.catchPosition.x, fy: catchResult.catchPosition.y,
                  tBall: catchResult.catchTime + handling, batter: batter, runners: runnersP, outsBefore: outsBeforePlay);
              playDesc = po.desc;
           }
        } else {
           // 捕れなかった打球: 軌道上で野手が最初に追いつける点（回り込み）で処理する
           int bounceIdx = trajectory.indexWhere((p) => p.z <= 0);
           if (bounceIdx < 0) bounceIdx = trajectory.length - 1;
           final bool groundish = bounceIdx * 0.05 < 1.5;
           FielderState? closest;
           int hitIdx = trajectory.length - 1;
           double tHas = double.infinity;
           for (final f in fielders) {
              final sp = startPos[f.role]!;
              final delay = groundish ? f.reactionDelay : f.reactionDelay + f.judge * 0.5; // フライ・ライナーは落下点の見極めの分も
              int idx = -1;
              double tf = 0;
              final bool infielder = !const {'LF', 'CF', 'RF'}.contains(f.role);
              for (int i = bounceIdx; i < trajectory.length; i++) {
                 final b = trajectory[i];
                 if (b.z > 1.2) continue;
                 if (infielder && _hypot(b.x, b.y) > 52) continue; // 外野へ抜けた打球は外野手
                 final d = _hypot(b.x - sp[0], b.y - sp[1]);
                 tf = delay + Sprint(f.speed, f.accel).time(max(0.0, d - f.reach), v0: f.v0);
                 if (tf <= i * 0.05) { idx = i; break; }
              }
              double t;
              if (idx < 0 && infielder && _hypot(trajectory.last.x, trajectory.last.y) > 52) continue; // 外野で止まった打球は外野手が拾う
              if (idx < 0) { // 止まったボールを拾いに行く
                 idx = trajectory.length - 1;
                 final b = trajectory[idx];
                 final d = _hypot(b.x - sp[0], b.y - sp[1]);
                 t = max(idx * 0.05, delay + Sprint(f.speed, f.accel).time(d));
              } else {
                 t = idx * 0.05;
              }
              if (t < tHas) { tHas = t; hitIdx = idx; closest = f; }
           }
           Vector3D landing = trajectory[hitIdx];
           double finalDist = sqrt(landing.x * landing.x + landing.y * landing.y);
           if (closest != null) {
              ev.fielder = closest.role;
              ev.landX = landing.x;
              ev.landY = landing.y;
              final step = max(1, hitIdx ~/ 24);
              ev.path = [for (int i = 0; i <= hitIdx; i += step) [trajectory[i].x, trajectory[i].y, max(0.0, trajectory[i].z)], [landing.x, landing.y, 0.0]];
              ev.flightTime = tHas;
              final double tField = tHas + 0.2 + _rand.nextDouble() * 0.2; // 拾うまで（投げる動作は送球の様式で）
              if (finalDist > 45) {
                 // --- 外野へのヒット: 打者の塁打を走塁と返球の時間で決める ---
                 final double tThrow = tField + ThrowStyle.crowHop.transfer + closest.player.glove.transferDelay;
                 final st = _stretch(batter, resolver.throwTime(closest.role, landing.x, landing.y, tThrow, 2), Running.batterToBase(batter, 2, lefty: effHand == 'L'),
                     resolver.throwTime(closest.role, landing.x, landing.y, tThrow, 3), Running.batterToBase(batter, 3, lefty: effHand == 'L'), outsBeforePlay, pressure, runAdj);
                 hitBases = st.bases;
                 if (hitBases == 3) {
                    playDesc = "${closest.role}が打球を処理する間にサード到達！スリーベース！";
                 } else if (hitBases == 2) {
                    playDesc = st.outAt == 3 ? "${closest.role}の頭上を越えるツーベース（三塁を狙うもタッチアウト）" : "${closest.role}からの送球が返る間にツーベース！";
                 } else {
                    playDesc = st.outAt == 2 ? "${closest.role}の前へ落ちるヒット（二塁を狙うもタッチアウト）" : "${closest.role}の前へ落ちるヒット";
                 }
                 po = resolver.outfieldHit(role: closest.role, fx: landing.x, fy: landing.y, tField: tField,
                     batterBases: hitBases, batter: batter, runners: runnersP, outsBefore: outsBeforePlay,
                     flyBall: contactType == "フライ" || contactType == "ポップフライ", batterOutAt: st.outAt);
                 playDesc += po.desc;
              } else {
                 // --- 内野で処理（弾いた打球・ボテボテのゴロ）---
                 bool isThrowError = false;
                 if (closest.penaltyTimer > 0) {
                    double errorRate = 1.0 - (closest.player.throwAccuracy / 100.0);
                    if (_rand.nextDouble() < errorRate * 2.0 * (s.weather.wetPlay ? 1.15 : 1.0)) isThrowError = true; // 小雨はボールが滑る
                 }
                 if (isThrowError) {
                    po = errorAdvance();
                    ev.errorBy = closest.role;
                    playDesc = "${closest.role} バウンドに対応できずエラー出塁！";
                 } else {
                    final tBall = tField + closest.penaltyTimer;
                    po = resolver.groundBall(role: closest.role, fx: landing.x, fy: landing.y, tBall: tBall, batter: batter, runners: runnersP, outsBefore: outsBeforePlay);
                    playDesc = po.desc;
                 }
              }
           }
        }

        if (po != null) {
           ev.defense = resolver.lastPlan;
           if (ai.lastCall == 'お見合い' && po.hit) playDesc = 'お見合い！ ' + playDesc;
           isHit = po.hit;
           hitBases = po.hitBases;
           ev.runMoves = po.moves;
           ev.throwLegs = po.throws;
           ev.playCode = po.code;
        }
        ev.outcome = (po?.error ?? false)
            ? 'エラー'
            : isHit
            ? (hitBases == 4 ? 'ホームラン' : (hitBases == 3 ? '三塁打' : (hitBases == 2 ? '二塁打' : '単打')))
            : ((po?.outs ?? 1) >= 2 ? '併殺' : ((po?.outs ?? 1) == 0 ? '野選' : 'アウト'));
        if (ev.outcome == '併殺' && contactType == 'ゴロ') batter.seasonStats.gidp++; // 併殺打（ゴロの併殺）
        if (isHit) _inc('hit_$contactType');
        if (isHit && hitBases == 2) _inc('d2_$contactType');

        if (hitBases == 4) {
           // ホームラン: 走者と打者がダイヤモンドを一周する
           final hrMoves = <RunMove>[];
           for (int b = 3; b >= 1; b--) {
             final p = runnersP[b - 1];
             if (p != null) hrMoves.add(RunMove(p.registeredName, b, 4, false, 1.0, 1.0 + (4 - b) * _trot(p) / 4));
           }
           hrMoves.add(RunMove(batter.registeredName, 0, 4, false, 0.5, 0.5 + _trot(batter)));
           int runs = 1;
           if (state.runner3B != null) runs++;
           if (state.runner2B != null) runs++;
           if (state.runner1B != null) runs++;
           state.runner1B = null; state.runner2B = null; state.runner3B = null;
           state.addScore(runs);
           if (state.isTop) awayHits++; else homeHits++;
           pitchLog += '$hitDetail 守備: $playDesc ($runs点追加)';
           batter.seasonStats.homeRuns++;
           batter.seasonStats.hits++;
           pitcher.seasonStats.hrAllowed++;
           pitcher.seasonStats.hitsAllowed++;
           bStats['hr'] = (bStats['hr'] ?? 0) + 1;
           bStats['h'] = (bStats['h'] ?? 0) + 1;
           creditRuns(runs);
           ev.runMoves = hrMoves;
        } else if (po != null) {
           // 統計（記録のための計測）
           if (po.dp) _inc('dp');
           if (po.tp) _inc('tp');
           if (contactType == 'ゴロ' && po.hit && hitBases == 1 && !const {'LF', 'CF', 'RF'}.contains(ev.fielder)) _inc('infieldHit'); // 内野手が処理して一塁セーフ
           for (final m in po.moves) {
             if (hitBases == 1 && po.hit && m.from == 2) { _inc('r2OnSingle'); if (m.to == 4 && !m.out) _inc('r2ScoredOnSingle'); }
             if (hitBases == 1 && po.hit && m.from == 1) { _inc('r1OnSingle'); if (m.to == 3 && !m.out) _inc('r1ToThirdOnSingle'); }
             if (hitBases == 2 && po.hit && m.from == 1) { _inc('r1OnDouble'); if (m.to == 4 && !m.out) _inc('r1ScoredOnDouble'); }
             if (m.out && m.from > 0 && (po.hit || po.sacFly || m.to == 4)) _inc('runnerThrownOut');
           }
           if (po.sacFly) _inc('sacFly');
           // 状態に反映: 得点 → 走者 → アウト（3アウトで走者は消える）
           if (po.runs > 0) state.addScore(po.runs);
           state.runner1B = po.bases[0]; state.runner2B = po.bases[1]; state.runner3B = po.bases[2];
           if (po.hit) {
              if (state.isTop) awayHits++; else homeHits++;
              batter.seasonStats.hits++;
              pitcher.seasonStats.hitsAllowed++;
              if (po.hitBases == 2) batter.seasonStats.doubles++;
              if (po.hitBases >= 3) batter.seasonStats.triples++;
              bStats['h'] = (bStats['h'] ?? 0) + 1;
           }
           final tag = po.code.isNotEmpty && po.dp ? ' (ダブルプレー)' : '';
           pitchLog += '$hitDetail 守備: $playDesc$tag${po.runs > 0 ? " (${po.runs}点追加)" : ""}';
           if (po.runs > 0 && !po.error) {
              if (po.dp) {
                 pitcher.seasonStats.earnedRuns += po.runs;
                 pStats['er'] = (pStats['er'] ?? 0) + po.runs;
              } else {
                 creditRuns(po.runs);
              }
           }
           for (int i = 0; i < po.outs; i++) { if (state.outs < 3 && (i == 0 || state.outs != 0)) state.addOut(); }
        }
        if (!wasTop && state.inning >= 9 && !state.isTop && state.homeScore > state.awayScore) { // 裏の攻撃で勝ち越したときだけ（表の3アウトで裏に替わった直後は除く）
           pitchLog += hitBases == 4 ? ' 【劇的サヨナラホームラン！！】' : ' 【サヨナラ！！】';
           state.outs = 3;
        }
        if (po != null && po.sacFly) batter.seasonStats.sacFlies++;
        if (po == null || !po.sacFly) { bStats['ab'] = (bStats['ab'] ?? 0) + 1; batter.seasonStats.atBats++; }
        atBatOver = true;
        
        pitchLog += ' [$runnerState]';
        playByPlay.add(pitchLog);
        pitchByPitch.add(pitchLog); ev.desc = pitchLog; _ctxAfter(s, ev);
        state.resetCount();
      }

      if (!skipBatterAdvance) { if (wasTop) { awayBatterIndex++; } else { homeBatterIndex++; } }
    }

    s.homeBatterIndex = homeBatterIndex;
    s.awayBatterIndex = awayBatterIndex;
    s.homeHits = homeHits;
    s.awayHits = awayHits;
    s.lastInningStr = lastInningStr;
    final outsAfter = wasTop ? state.homeDefenseOuts : state.awayDefenseOuts;
    s.pitcherOuts[pitcherAtStart.id] = (s.pitcherOuts[pitcherAtStart.id] ?? 0) + (outsAfter - outsBefore);
    // 安打・四球・失点を許したら、そのイニングの残りはスタミナ消費1.5倍（累積しない）
    final hitsAfter = wasTop ? awayHits : homeHits;
    final scoreAfter = wasTop ? state.awayScore : state.homeScore;
    if (hitsAfter > hitsBefore || scoreAfter > scoreBefore || pitcherBB() > bbBefore) {
      s.roughedInning[pitcherAtStart.id] = inningAtStart;
    }
  }

  // ===================== 采配（交代）API =====================

  List<Player> _bench(GameSession s, bool home, {required bool pitchers}) {
    final team = home ? s.homeTeam : s.awayTeam;
    final ids = team.active26.isNotEmpty ? team.active26 : team.roster1G;
    return team.players.where((p) => (pitchers ? p.canPitch : p.canBat) && ids.contains(p.id) && !s.usedIds.contains(p.id)).toList();
  }

  /// 交代に使える控え野手（ベンチ入り・未出場）
  List<Player> availableBatters(GameSession s, bool home) => _bench(s, home, pitchers: false);

  /// 交代に使える控え投手（ベンチ入り・未登板）
  List<Player> availablePitchers(GameSession s, bool home) => _bench(s, home, pitchers: true);

  /// 次に打席が回ってくる打順スロット
  int nextBatterSlot(GameSession s, bool home) {
    final order = home ? s.homeOrder : s.awayOrder;
    return (home ? s.homeBatterIndex : s.awayBatterIndex) % order.length;
  }

  void _ensureBatterRow(GameSession s, bool home, Player p) {
    final m = s.boxScore[home ? 'homeBatters' : 'awayBatters'] as Map<String, dynamic>;
    m.putIfAbsent(p.registeredName, () => {'ab': 0, 'h': 0, 'hr': 0, 'rbi': 0, 'bb': 0, 'so': 0});
  }

  void _putInOrder(GameSession s, bool home, int slot, Player p, {String? position}) {
    final order = home ? s.homeOrder : s.awayOrder;
    final lineup = home ? s.homeLineup : s.awayLineup;
    order[slot] = p;
    if (slot < lineup.length) {
      lineup[slot].playerId = p.id;
      if (position != null) lineup[slot].position = position;
    }
    (home ? s.homeAppeared : s.awayAppeared).add(p);
    s.usedIds.add(p.id);
    _ensureBatterRow(s, home, p);
  }

  /// 投手交代
  void changePitcher(GameSession s, bool home, Player p) {
    final old = home ? s.homePitcher : s.awayPitcher;
    final my = home ? s.state.homeScore : s.state.awayScore, opp = home ? s.state.awayScore : s.state.homeScore;
    s.pitcherExit[old.id] = [my, opp];
    s.pitcherEntry[p.id] = [my, opp];
    // 守っている側の交代なら、塁上の走者を引き継ぐ（走者を出した投手の責任のまま）
    final defending = home == s.state.isTop; // 表（ビジターの攻撃）ならホームが守り
    final n = defending ? [s.state.runner1B, s.state.runner2B, s.state.runner3B].where((x) => x != null).length : 0;
    final q = List<String>.of(s.inherit[old.id] ?? const []);
    if (q.length > n) q.removeRange(n, q.length);
    while (q.length < n) {
      q.add(old.id);
    }
    s.inherit[p.id] = q;
    s.pitcherEntryRunners[p.id] = n;
    if (home) { s.homePitcher = p; s.homePitchers.add(p); } else { s.awayPitcher = p; s.awayPitchers.add(p); }
    s.usedIds.add(p.id);
    (s.boxScore[home ? 'homePitcher' : 'awayPitcher'] as Map<String, dynamic>)
        .putIfAbsent(p.registeredName, () => <String, dynamic>{'ip': '0', 'er': 0, 'so': 0, 'bb': 0});
    s.playByPlay.add('【投手交代】${(home ? s.homeTeam : s.awayTeam).name}: ${old.registeredName} → ${p.registeredName}');
  }

  /// 代打（次の打者を差し替える。守備位置は元の選手のものを引き継ぐ）
  void pinchHit(GameSession s, bool home, Player p) {
    final slot = nextBatterSlot(s, home);
    final old = (home ? s.homeOrder : s.awayOrder)[slot];
    if (applyForm) old.trust = (old.trust - 1).clamp(1, 100); // 代打を送られると信頼が少し下がる
    _putInOrder(s, home, slot, p);
    s.playByPlay.add('【代打】${(home ? s.homeTeam : s.awayTeam).name}: ${old.registeredName} → ${p.registeredName}');
  }

  /// 代走（base: 1=一塁, 2=二塁, 3=三塁）
  void pinchRun(GameSession s, bool home, int base, Player p) {
    final st = s.state;
    final oldName = base == 1 ? st.runner1B : (base == 2 ? st.runner2B : st.runner3B);
    if (oldName == null) return;
    final order = home ? s.homeOrder : s.awayOrder;
    final slot = order.indexWhere((x) => x.registeredName == oldName);
    if (slot < 0) return;
    _putInOrder(s, home, slot, p);
    if (base == 1) { st.runner1B = p.registeredName; } else if (base == 2) { st.runner2B = p.registeredName; } else { st.runner3B = p.registeredName; }
    s.playByPlay.add('【代走】${(home ? s.homeTeam : s.awayTeam).name}: $oldName → ${p.registeredName}');
  }

  /// 守備交代（打順スロットの選手を差し替え、守備位置を指定: 捕/一/二/三/遊/左/中/右/DH）
  /// 出ている選手同士の守備位置の入れ替え（打順はそのまま）
  void swapPositions(GameSession s, bool home, int a, int b) {
    final lineup = home ? s.homeLineup : s.awayLineup;
    final order = home ? s.homeOrder : s.awayOrder;
    if (a == b || a >= lineup.length || b >= lineup.length) return;
    final pa = lineup[a].position, pb = lineup[b].position;
    lineup[a].position = pb;
    lineup[b].position = pa;
    s.playByPlay.add('【守備位置の変更】${(home ? s.homeTeam : s.awayTeam).name}: ${order[a].registeredName}（$pa→$pb）・${order[b].registeredName}（$pb→$pa）');
  }

  void defensiveSwap(GameSession s, bool home, int slot, Player p, String position) {
    final old = (home ? s.homeOrder : s.awayOrder)[slot];
    _putInOrder(s, home, slot, p, position: position);
    s.playByPlay.add('【守備交代】${(home ? s.homeTeam : s.awayTeam).name}: ${old.registeredName} → ${p.registeredName}（$position）');
  }

  /// CPU（自動）の継投判断。守備側のチームについて、次の打席の前に呼ぶ
  void autoPitching(GameSession s, bool home) {
    final st = s.state;
    var pool = availablePitchers(s, home);
    // 体力が3割を切った投手は起用しない（全員そうなら仕方なく使う）
    if (applyForm) {
      final fresh = pool.where((p) => p.energyRatio >= 0.3).toList();
      if (fresh.isNotEmpty) pool = fresh;
    }
    if (pool.isEmpty) return;
    final team = home ? s.homeTeam : s.awayTeam;
    final cur = home ? s.homePitcher : s.awayPitcher;
    final isStarter = identical(cur, home ? s.starterHome : s.starterAway);
    final rotation = {for (final id in team.rotation.take(team.rotationCount)) if (id.isNotEmpty) id};
    if (st.inning < 12) {
      final rel = pool.where((p) => !rotation.contains(p.id)).toList();
      if (rel.isNotEmpty) pool = rel;
    }
    final pitches = s.staminaUsed[cur.id] ?? 0; // スタミナ消費量（打たれたイニングは1.5倍）
    final er = ((s.boxScore[home ? 'homePitcher' : 'awayPitcher'] as Map<String, dynamic>)[cur.registeredName]?['er'] ?? 0) as int;
    final lead = home ? st.homeScore - st.awayScore : st.awayScore - st.homeScore;
    final halfStart = s.lastInningStr != '${st.inning}回${st.isTop ? "表" : "裏"}';

    Player? byId(String? id) {
      if (id == null || id.isEmpty) return null;
      for (final p in pool) { if (p.id == id) return p; }
      return null;
    }

    // 3連投はさせない（前日まで2日続けて投げた投手は休ませる）
    final y = s.match.date.subtract(const Duration(days: 1));
    final yesterday = '${y.year}-${y.month}-${y.day}';
    bool rested(Player p) => !(p.consecDays >= 2 && p.lastPitched == yesterday);
    // 勝利の方程式（リード時）: winningPattern = [7回, 8回, 9回以降]。各イニング開始時に1〜3点リードなら登板
    final np = s.gamePitchCounts[cur.id] ?? 0; // 実際の球数
    if (halfStart && lead >= 1 && lead <= 3 && st.inning >= 7) {
      final idx = st.inning >= 9 ? 2 : st.inning - 7;
      final w = byId(team.winningPattern[idx]);
      final dominant = isStarter && (st.inning >= 9 ? (er == 0 && np < 105) : (er <= 1 && np < 85));
      if (w != null && !identical(w, cur) && rested(w) && !dominant) { changePitcher(s, home, w); return; }
    }
    // 左のワンポイント：7回以降・2点差以内で、次の打者が左の強打者なら、左の中継ぎを挟む（判断力しだい）
    final oppOrder = home ? s.awayOrder : s.homeOrder;
    final nextB = oppOrder[nextBatterSlot(s, !home) % oppOrder.length];
    if (st.inning >= 7 && lead.abs() <= 2 && nextB.bats == 'L' && nextB.power >= 72 && cur.throws != 'L' && !team.winningPattern.contains(cur.id)) {
      final lefty = (pool.where((p) => p.throws == 'L' && !team.winningPattern.contains(p.id) && rested(p) && p.ovr >= 55).toList()..sort((a, b) => b.ovr.compareTo(a.ovr))).firstOrNull;
      if (lefty != null && _rand.nextDouble() < (cpuSkill(team.id) / 100.0) * 0.6) {
        changePitcher(s, home, lefty);
        s.playByPlay.add('（左のワンポイント）');
        return;
      }
    }
    // ── 交代するか ──
    // 先発：球数の目安（スタミナ50で約98球・70で約105球・90で約112球。継投の早い監督ほど早め）で降板。
    //       炎上（自責5、または5回までに自責4）・疲れ切った（スタミナの上限）でも降板
    // 中継ぎ：1イニング投げ終えたら次の回は別の投手。回の途中は球数・失点で降板
    final quick = ((cpuStyles[team.id]?['bullpen'] ?? 50) - 50) * 0.3;
    final outs = s.pitcherOuts[cur.id] ?? 0;
    final close = lead.abs() <= 2;
    bool tired;
    if (isStarter) {
      final target = (80 + cur.stamina * 0.35 - quick).clamp(80.0, 125.0);
      tired = er >= 5 ||
          (er >= 4 && st.inning <= 5) ||
          pitches >= staminaLimit(cur) - 8 ||
          (halfStart && np >= target) ||
          np >= target + 15;
    } else {
      final long = lead.abs() >= 4 && st.inning <= 6; // 大差の序盤・中盤は長く投げてよい
      tired = er >= 3 ||
          np >= 30 + cur.stamina * 0.15 + (long ? 15 : 0) ||
          (halfStart && outs >= 3 && !(long && np < 35));
    }
    if (!tired) return;

    // ── 誰を出すか ──（場面ごとの役割・連投の疲れ・その日の調子のぶれで散らす）
    final reserved = {...team.winningPattern};
    var cands = pool.where((p) => !reserved.contains(p.id) && rested(p) && !identical(p, cur)).toList();
    if (cands.isEmpty) cands = pool.where((p) => !reserved.contains(p.id) && !identical(p, cur)).toList();
    if (cands.isEmpty) cands = pool.where((p) => !identical(p, cur)).toList();
    if (cands.isEmpty) return;
    // 延長・接戦の終盤で他にいなければ、勝ちパターンも使う
    final sorted = [...cands]..sort((x, y) => y.ovr.compareTo(x.ovr));
    final rank = {for (var i = 0; i < sorted.length; i++) sorted[i].id: i};
    final blowout = lead.abs() >= 4;
    final early = st.inning <= 5;
    double score(Player p) {
      final top = 1 - rank[p.id]! / sorted.length; // 1 = いちばん良い投手
      double v;
      if (early && (blowout || lead < 0)) {
        v = p.stamina * 0.8 + p.ovr * 0.3; // ロングリリーフ：長く投げられる投手
      } else if (blowout) {
        v = (1 - top) * 60 + p.stamina * 0.2; // 敗戦処理・大量リード：控えめの投手で主力を休ませる
      } else if (close && st.inning >= 6) {
        v = top * 80 + p.ovr * 0.3; // 接戦の終盤：良い投手から
      } else {
        v = top * 45 + p.ovr * 0.2; // 中盤：中くらいの投手
      }
      // 連投の疲れ：前日投げた投手は控えめに。体力（調子）が減っている投手も
      if (p.lastPitched == '${y.year}-${y.month}-${y.day}') v -= 18;
      if (applyForm) v -= (1 - p.energyRatio) * 30;
      return v + _rand.nextDouble() * 14; // その日の判断のぶれ
    }

    cands.sort((x, y) => score(y).compareTo(score(x)));
    changePitcher(s, home, cands.first);
  }

  /// CPU采配をまとめて実行（守備固め・継投・代打・代走）
  void autoManage(GameSession s) {
    if (isFinished(s)) return;
    autoDefenseSubs(s, s.state.isTop); // 表の守備側＝ホーム
    autoPitching(s, s.state.isTop);
    autoOffenseSubs(s, !s.state.isTop);
  }

  /// CPU の判断の確率（判断力 50 で 50%、80 で 80%）
  bool _judge(Team t) => _rand.nextDouble() < (cpuSkill(t.id) / 100.0).clamp(0.2, 0.95);

  /// CPU の代打・代走（攻撃側）。終盤の接戦や負けている場面で使う
  void autoOffenseSubs(GameSession s, bool home) {
    final st = s.state;
    if (st.inning < 7) return;
    final team = home ? s.homeTeam : s.awayTeam;
    final lead = home ? st.homeScore - st.awayScore : st.awayScore - st.homeScore;
    final bench = availableBatters(s, home);
    if (bench.isEmpty) return;
    final order = home ? s.homeOrder : s.awayOrder;
    final lineup = home ? s.homeLineup : s.awayLineup;
    final opp = home ? s.awayPitcher : s.homePitcher;
    // 代走：8回以降・1点差以内で、足の遅い走者に足の速い控え
    if (st.inning >= 8 && lead.abs() <= 1) {
      for (final base in [2, 1]) {
        final name = base == 2 ? st.runner2B : st.runner1B;
        if (name == null) continue;
        final runner = order.where((x) => x.registeredName == name).firstOrNull;
        if (runner == null || runner.run >= 55) continue;
        final fast = (bench.where((b) => b.run >= 70).toList()..sort((a, b) => b.run.compareTo(a.run))).firstOrNull;
        if (fast != null && _judge(team)) {
          pinchRun(s, home, base, fast);
          return;
        }
      }
    }
    // 代打：7回以降で負けている（同点を含む）場面。打力が明らかに上の控え、または左右の相性
    if (lead > 0 || lead < -4) return;
    final slot = nextBatterSlot(s, home);
    final cur = order[slot];
    final pos = slot < lineup.length ? lineup[slot].position : '';
    if (pos == '投') return; // 投手の打順には代打を出さない（そのあとの継投をエンジンが扱えないため）
    if (cur.twoWay) return; // 二刀流で起用している選手には代打を出さない
    if (pos == '捕' && !bench.any((b) => b.mainPosition == '捕手')) return; // 控え捕手がいなければ捕手には代打を出さない
    double bat(Player b) {
      final hand = b.bats == 'S' ? 0 : (b.bats == opp.throws ? -6 : 3); // 同じ利き同士は打ちにくい
      return (b.contactLeft + b.contactRight) / 4 + b.power * 0.5 + hand;
    }
    final best = (List.of(bench)..sort((a, b) => bat(b).compareTo(bat(a)))).first;
    final margin = 10 - (cpuSkill(team.id) - 50) * 0.08; // 判断力の高い監督ほど、小さな差でも代打を出す
    if (bat(best) >= bat(cur) + margin && _judge(team)) pinchHit(s, home, best);
  }

  /// CPU の守備固め（守備側）。8回以降に1〜3点リードしている回の初めに、守備の弱い選手を替える
  void autoDefenseSubs(GameSession s, bool home) {
    final st = s.state;
    final halfStart = s.lastInningStr != '${st.inning}回${st.isTop ? "表" : "裏"}';
    if (!halfStart || st.inning < 8) return;
    final team = home ? s.homeTeam : s.awayTeam;
    final lead = home ? st.homeScore - st.awayScore : st.awayScore - st.homeScore;
    if (lead < 1 || lead > 3) return;
    final bench = availableBatters(s, home);
    final order = home ? s.homeOrder : s.awayOrder;
    final lineup = home ? s.homeLineup : s.awayLineup;
    int apt(Player p, String pos) => switch (pos) { '捕' => p.fieldC, '一' => p.field1B, '二' => p.field2B, '三' => p.field3B, '遊' => p.fieldSS, '左' => p.fieldLF, '中' => p.fieldCF, '右' => p.fieldRF, _ => 0 };
    for (var i = 0; i < lineup.length && i < order.length; i++) {
      final pos = lineup[i].position;
      if (pos == 'DH' || pos == '投') continue;
      final cur = order[i];
      final a = apt(cur, pos) + cur.catchSkill * 0.3;
      final cand = (bench.where((b) => apt(b, pos) >= 55).toList()..sort((x, y) => (apt(y, pos) + y.catchSkill * 0.3).compareTo(apt(x, pos) + x.catchSkill * 0.3))).firstOrNull;
      if (cand == null) continue;
      if (apt(cand, pos) + cand.catchSkill * 0.3 >= a + 15 && _judge(team)) {
        defensiveSwap(s, home, i, cand, pos);
        return; // 1回に1人まで
      }
    }
  }

  /// リードの入れ替わりを記録する（打席が終わるたびに呼ぶ）
  void _trackLead(GameSession s) {
    final d = s.state.homeScore - s.state.awayScore;
    final leader = d > 0 ? 1 : (d < 0 ? -1 : 0);
    if (leader != 0 && leader != s.lastLeader) {
      s.winCand[leader] = leader == 1 ? s.homePitcher : s.awayPitcher;
      s.loseCand[leader] = leader == 1 ? s.awayPitcher : s.homePitcher;
    }
    s.lastLeader = leader;
  }

  /// 打席の終わり：引き継いだ走者が還った分の自責点を、走者を出した投手に付け替える。
  ///  リードが入れ替わったら、勝利投手の候補（攻撃側のいまの投手）と敗戦投手の候補（決勝点の走者を出した投手）を決める。
  ///  得点は先の塁の走者（＝引き継いだ走者）から入ったとみなす
  void _settlePa(GameSession s) {
    final dp = s.paDef;
    if (dp == null) {
      _trackLead(s);
      return;
    }
    final top = s.paTop, st = s.state;
    {
      final gained = (top ? st.homeDefenseOuts : st.awayDefenseOuts) - s.paDefOuts;
      if (gained > 0) {
        final lineup = top ? s.homeLineup : s.awayLineup;
        for (final l in lineup) {
          final pos = l.position;
          if (pos == 'DH' || pos == '投') continue; // 投手は下で（交代した投手に付ける）
          final m = s.posOuts.putIfAbsent(l.playerId, () => {});
          m[pos] = (m[pos] ?? 0) + gained;
        }
        final m = s.posOuts.putIfAbsent(dp.id, () => {});
        m['投'] = (m['投'] ?? 0) + gained;
      }
    }
    final off0 = top ? s.paAway : s.paHome, def0 = top ? s.paHome : s.paAway;
    final off1 = top ? st.awayScore : st.homeScore;
    final runs = off1 - off0;
    final q = s.inherit[dp.id] ?? <String>[];
    final consumed = runs > 0 ? q.take(runs).toList() : <String>[];
    if (consumed.isNotEmpty) q.removeRange(0, consumed.length);
    final defHome = top; // 表の攻撃ならホームが守り
    final rows = s.boxScore[defHome ? 'homePitcher' : 'awayPitcher'] as Map<String, dynamic>;
    final pitchers = defHome ? s.homePitchers : s.awayPitchers;
    Player byId(String id) => pitchers.firstWhere((x) => x.id == id, orElse: () => dp);
    // 自責点の付け替え
    final dpRow = rows[dp.registeredName] as Map?;
    final gained = ((dpRow?['er'] ?? 0) as int) - s.paDefEr;
    final mv = min(consumed.length, gained);
    for (var i = 0; i < mv; i++) {
      final r = byId(consumed[i]);
      if (identical(r, dp)) continue;
      dp.seasonStats.earnedRuns--;
      dpRow!['er'] = (dpRow['er'] as int) - 1;
      r.seasonStats.earnedRuns++;
      final rr = rows[r.registeredName] as Map?;
      if (rr != null) rr['er'] = ((rr['er'] ?? 0) as int) + 1;
    }
    // リードの入れ替わり
    if (off0 <= def0 && off1 > def0) {
      final k = def0 - off0 + 1; // 何点目でリードを奪ったか
      final resp = k <= consumed.length ? byId(consumed[k - 1]) : dp;
      final side = top ? -1 : 1;
      s.winCand[side] = top ? s.awayPitcher : s.homePitcher;
      s.loseCand[side] = resp;
    }
    final d = st.homeScore - st.awayScore;
    s.lastLeader = d > 0 ? 1 : (d < 0 ? -1 : 0);
    // 攻守が替わったら塁は空。そうでなければ、塁上の走者の数まで
    if (st.isTop != top) {
      q.clear();
    } else {
      final n = [st.runner1B, st.runner2B, st.runner3B].where((x) => x != null).length;
      if (q.length > n) q.removeRange(n, q.length);
    }
    s.inherit[dp.id] = q;
  }

  /// 勝利・敗戦・セーブ・ホールドを決めて、成績とボックススコアに記録する（公認野球規則 9.17〜9.19・NPB のホールド）
  ///  - 勝利：最後にリードを奪ったときの投手。先発は5回（15アウト）以上が必要で、届かなければ最も効果的な救援投手。
  ///          救援がリードを奪った投手でも、1回未満で失点した短い登板なら、後の最も効果的な救援投手
  ///  - 敗戦：最後にリードを奪われたとき、決勝点の走者を出した投手（引き継いだ走者なら前の投手）
  ///  - セーブ：勝利投手以外で最後まで投げ（1アウト以上）、リードして登板し、次のどれか
  ///          ①3点差以内で1回以上 ②同点の走者が塁上・打席・次打者の場面で登板 ③3回以上
  ///  - ホールド：勝敗もセーブも付かず、最後まで投げなかった救援（1アウト以上）で、次のどちらか
  ///          ①セーブと同じ場面（①②③）で登板し、リードを保って降板 ②同点で登板し、失点せずに降板
  ///  - ホールドポイント：ホールド＋救援勝利
  void _decide(GameSession s) {
    if (s.paDef == null) _trackLead(s);
    final d = s.state.homeScore - s.state.awayScore;
    final box = s.boxScore;
    void mark(Player p, bool home, String dec) {
      final row = (box[home ? 'homePitcher' : 'awayPitcher'] as Map<String, dynamic>)[p.registeredName];
      if (row is Map) row['dec'] = dec;
    }
    Player? winner, loser, saver;
    if (d != 0) {
      final w = d > 0 ? 1 : -1;
      final wPitchers = w == 1 ? s.homePitchers : s.awayPitchers;
      final rows = box[w == 1 ? 'homePitcher' : 'awayPitcher'] as Map<String, dynamic>;
      int outs(Player p) => s.pitcherOuts[p.id] ?? 0;
      int er(Player p) => ((rows[p.registeredName] as Map?)?['er'] ?? 0) as int;
      // 最も効果的な救援投手（アウトの数 − 失点×3。同じなら先に投げた投手）
      Player? best(Iterable<Player> ps) {
        Player? b;
        for (final p in ps) {
          if (b == null || outs(p) - er(p) * 3 > outs(b) - er(b) * 3) b = p;
        }
        return b;
      }

      final starter = wPitchers.first;
      winner = s.winCand[w] ?? starter;
      if (identical(winner, starter)) {
        if (outs(starter) < 15 && wPitchers.length > 1) winner = best(wPitchers.skip(1))!;
      } else {
        final i = wPitchers.indexOf(winner);
        if (outs(winner) < 3 && er(winner) >= 1 && i >= 0 && i + 1 < wPitchers.length) winner = best(wPitchers.skip(i + 1))!;
      }
      loser = s.loseCand[w] ?? (w == 1 ? s.awayPitchers.first : s.homePitchers.first);
      winner.seasonStats.wins++;
      if (!identical(winner, starter)) winner.seasonStats.reliefWins++;
      loser.seasonStats.losses++;
      mark(winner, w == 1, '勝');
      mark(loser, w != 1, '敗');
      final last = wPitchers.last;
      if (!identical(last, winner) && !identical(last, starter) && outs(last) >= 1) {
        final e = s.pitcherEntry[last.id] ?? [0, 0];
        final lead = e[0] - e[1];
        final runners = s.pitcherEntryRunners[last.id] ?? 0;
        if (lead >= 1 && ((lead <= 3 && outs(last) >= 3) || lead <= runners + 2 || outs(last) >= 9)) {
          saver = last;
          last.seasonStats.saves++;
          mark(last, w == 1, 'S');
        }
      }
    }
    for (final home in [true, false]) {
      final ps = home ? s.homePitchers : s.awayPitchers;
      for (var i = 1; i < ps.length; i++) {
        final p = ps[i];
        if (identical(p, winner) || identical(p, loser) || identical(p, saver) || identical(p, ps.last)) continue;
        final e = s.pitcherEntry[p.id], x = s.pitcherExit[p.id];
        if (e == null || x == null) continue;
        final leadIn = e[0] - e[1], leadOut = x[0] - x[1];
        final o = s.pitcherOuts[p.id] ?? 0;
        final runners = s.pitcherEntryRunners[p.id] ?? 0;
        final saveSit = leadIn >= 1 && (leadIn <= 3 || leadIn <= runners + 2 || o >= 9);
        final tieHold = leadIn == 0 && leadOut >= 0 && x[1] == e[1]; // 同点で登板し、失点せずに降板
        if (o >= 1 && ((saveSit && leadOut >= 1) || tieHold)) {
          p.seasonStats.holds++;
          mark(p, home, 'H');
        }
      }
    }
  }

  MatchResult finishGame(GameSession s) {
    final state = s.state;
    final homeTeam = s.homeTeam;
    final awayTeam = s.awayTeam;
    final boxScore = s.boxScore;
    // 実際に行われたイニング数に配列を揃える（終了判定前に先行追加された列を除く）
    int playedInnings = (state.isTop ? state.inning - 1 : state.inning).clamp(9, 12);
    if (state.homeInningScores.length > playedInnings) state.homeInningScores.length = playedInnings;
    if (state.awayInningScores.length > playedInnings) state.awayInningScores.length = playedInnings;

    for (var p in s.homeAppeared) { p.seasonStats.games++; }
    for (var p in s.awayAppeared) { p.seasonStats.games++; }
    String ipStr(int outs) => '${outs ~/ 3}${outs % 3 == 0 ? "" : ".${outs % 3}"}';
    if (s.homePitchers.isNotEmpty) s.homePitchers.first.seasonStats.starts++;
    if (s.awayPitchers.isNotEmpty) s.awayPitchers.first.seasonStats.starts++;
    for (var p in s.homePitchers) {
      final outs = s.pitcherOuts[p.id] ?? 0;
      p.seasonStats.pitchApps++;
      if (!s.homeAppeared.contains(p)) p.seasonStats.games++; // 二刀流で打順にもいれば、試合数は1回だけ
      p.seasonStats.inningsPitched += outs;
      boxScore['homePitcher'][p.registeredName]['ip'] = ipStr(outs);
      boxScore['homePitcher'][p.registeredName]['np'] = s.gamePitchCounts[p.id] ?? 0; // 球数
    }
    for (var p in s.awayPitchers) {
      final outs = s.pitcherOuts[p.id] ?? 0;
      p.seasonStats.pitchApps++;
      if (!s.awayAppeared.contains(p)) p.seasonStats.games++;
      p.seasonStats.inningsPitched += outs;
      boxScore['awayPitcher'][p.registeredName]['ip'] = ipStr(outs);
      boxScore['awayPitcher'][p.registeredName]['np'] = s.gamePitchCounts[p.id] ?? 0;
    }

    _decide(s);
    // 失策の数（スコアボードの E）。表の攻撃のときの失策はホームの失策
    boxScore['homeE'] = s.pitchEvents.where((e) => e.errorBy.isNotEmpty && !e.battingHome).length;
    boxScore['awayE'] = s.pitchEvents.where((e) => e.errorBy.isNotEmpty && e.battingHome).length;
    boxScore['homeSB'] = s.homeSB;
    boxScore['awaySB'] = s.awaySB;

    final homeHits = s.homeHits;
    final awayHits = s.awayHits;
    final playByPlay = s.playByPlay;
    final pitchByPitch = s.pitchByPitch;
    return MatchResult(
      homeTeamId: homeTeam.id,
      awayTeamId: awayTeam.id,
      homeScore: state.homeScore,
      awayScore: state.awayScore,
      homeInningScores: state.homeInningScores,
      awayInningScores: state.awayInningScores,
      homeHits: homeHits,
      awayHits: awayHits,
      playByPlay: playByPlay,
      pitchByPitch: pitchByPitch,
      boxScore: boxScore,
      session: s,
    );
  }
}

class MatchResult {
  final String homeTeamId;
  final String awayTeamId;
  final int homeScore;
  final int awayScore;
  final List<int> homeInningScores;
  final List<int> awayInningScores;
  final int homeHits;
  final int awayHits;
  final List<String> playByPlay;
  final List<String> pitchByPitch;
  final Map<String, dynamic> boxScore;
  final GameSession? session; // 試合後の体力・怪我・モチベーション処理用（保存はしない）

  MatchResult({
    this.session,
    required this.homeTeamId,
    required this.awayTeamId,
    required this.homeScore,
    required this.awayScore,
    required this.homeInningScores,
    required this.awayInningScores,
    required this.homeHits,
    required this.awayHits,
    required this.playByPlay,
    required this.pitchByPitch,
    required this.boxScore,
  });
}



