part of 'match_simulator.dart';

// 1試合の計算で使うデータのクラス・列挙型（状態・1球の記録・試合の保持・作戦・結果）。計算本体は match_simulator.dart


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



