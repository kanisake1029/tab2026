import 'dart:math' show sin, cos, sqrt, log, pi, pow, Random;
import '../engine/body_gen.dart';
import '../engine/velo.dart';
import 'pitching_form.dart';
import 'equipment.dart';
import '../engine/grip_model.dart';

class Pitch {
  String name;
  int breakLevel;
  int angle;      
  int speed;
  int ratio;
  int sharpness;
  int heaviness;
  /// 握り（6つの量）。null は球種表の変化・球速から自動で決める
  Grip? grip;

  Pitch({
    required this.name, 
    required this.breakLevel, 
    required this.angle,
    this.speed = 140,
    this.ratio = 25,
    this.sharpness = 50,
    this.heaviness = 50,
    this.grip,
  });

  Map<String, dynamic> toJson() => {
    'name': name, 
    'breakLevel': breakLevel, 
    'angle': angle,
    'speed': speed,
    'ratio': ratio,
    'sharpness': sharpness,
    'heaviness': heaviness,
    if (grip != null) 'grip': grip!.toJson(),
  };
  
  factory Pitch.fromJson(Map<String, dynamic> json) => Pitch(
    name: json['name'] ?? '', 
    breakLevel: json['breakLevel'] ?? 50, 
    angle: json['angle'] ?? 0,
    speed: json['speed'] ?? 140,
    ratio: json['ratio'] ?? 25,
    sharpness: json['sharpness'] ?? 50,
    heaviness: json['heaviness'] ?? 50,
    grip: json['grip'] is Map ? Grip.fromJson(Map<String, dynamic>.from(json['grip'] as Map)) : null,
  );
}

class PlayerStats {
  int games;
  int atBats;
  int hits;
  int homeRuns;
  int rbi;
  int walks;
  int strikeouts;
  int stolenBases;
  int doubles;
  int triples;
  int sacFlies;
  int hitsAllowed; // 被安打
  int hrAllowed; // 被本塁打
  Map<String, int> posGames; // 守備位置ごとの先発出場試合（捕・一・二・三・遊・左・中・右・DH・投）
  Map<String, int> posOuts;  // 守備位置ごとに守ったアウトの数（÷3で守備イニング。途中出場・守備位置の移動も含む）
  int fieldChances; // 処理した打球の数（安打を含む）
  int fieldOuts;    // そのうちアウトにした数

  int inningsPitched; // x3 to handle 1/3 innings
  int earnedRuns;
  int pitcherStrikeouts;
  int pitcherWalks;
  int wins;
  int losses;
  int saves;
  int holds;
  int runs; // 得点
  int hbp; // 死球
  int multiHit; // マルチヒット（1試合2安打以上）
  int mouda; // 猛打賞（1試合3安打以上）
  int cycles; // サイクル安打
  int putouts; // 刺殺
  int assists; // 補殺
  int errors; // 失策
  int dpTurned; // 併殺に関わった数
  int defOuts; // 守備に就いていたアウトの数（÷3で守備イニング）
  int completeGames; // 完投
  int shutouts; // 完封
  int noHitters; // ノーヒットノーラン
  int perfects; // 完全試合
  int hbpAllowed; // 与死球
  int pitchApps;  // 登板数（二刀流の選手は「試合」と別に数える）
  int reliefWins; // 救援勝利（ホールドポイントに足す）
  int rispAB, rispH; // 得点圏（二塁か三塁に走者）での打数・安打
  int multiHR;    // 1試合2本塁打以上の試合
  int walkoffs;   // サヨナラ打
  int qs;         // クオリティスタート（先発で6回以上・自責点3以下）
  int tenK;       // 1試合2桁奪三振
  int gidp;       // 併殺打
  int sacBunts;   // 犠打（送りバント・スクイズの成功）
  /// 打者の詳しい成績（コース・打球方向・球種・球速ごとの [打数, 安打, 本塁打, 三振]。BattingSplits）
  Map<String, List<int>> spl;
  int starts;     // 先発登板の数
  int caughtStealing; // 盗塁死（走者）
  int sbAgainst; // 捕手として許した盗塁
  int csAgainst; // 捕手として刺した盗塁（盗塁阻止）

  PlayerStats({
    this.games = 0,
    this.atBats = 0,
    this.hits = 0,
    this.homeRuns = 0,
    this.rbi = 0,
    this.walks = 0,
    this.strikeouts = 0,
    this.stolenBases = 0,
    this.doubles = 0,
    this.triples = 0,
    this.sacFlies = 0,
    this.hitsAllowed = 0,
    this.hrAllowed = 0,
    this.inningsPitched = 0,
    this.earnedRuns = 0,
    this.pitcherStrikeouts = 0,
    this.pitcherWalks = 0,
    this.wins = 0,
    this.losses = 0,
    this.saves = 0,
    this.holds = 0,
    Map<String, int>? posGames,
    Map<String, List<int>>? spl,
    Map<String, int>? posOuts,
    this.fieldChances = 0,
    this.fieldOuts = 0,
    this.runs = 0,
    this.hbp = 0,
    this.multiHit = 0,
    this.mouda = 0,
    this.cycles = 0,
    this.putouts = 0,
    this.assists = 0,
    this.errors = 0,
    this.dpTurned = 0,
    this.defOuts = 0,
    this.completeGames = 0,
    this.shutouts = 0,
    this.noHitters = 0,
    this.perfects = 0,
    this.hbpAllowed = 0,
    this.pitchApps = 0,
    this.reliefWins = 0,
    this.rispAB = 0,
    this.rispH = 0,
    this.multiHR = 0,
    this.walkoffs = 0,
    this.qs = 0,
    this.tenK = 0,
    this.gidp = 0,
    this.sacBunts = 0,
    this.starts = 0,
    this.caughtStealing = 0,
    this.sbAgainst = 0,
    this.csAgainst = 0,
  }) : posGames = posGames ?? {}, posOuts = posOuts ?? {}, spl = spl ?? {};

  double get battingAverage => atBats == 0 ? 0.0 : hits / atBats;
  double get era => inningsPitched == 0 ? 0.0 : (earnedRuns * 27) / inningsPitched;

  Map<String, dynamic> toJson() => {
    'games': games, 'atBats': atBats, 'hits': hits, 'homeRuns': homeRuns,
    'rbi': rbi, 'walks': walks, 'strikeouts': strikeouts, 'stolenBases': stolenBases,
    'inningsPitched': inningsPitched, 'earnedRuns': earnedRuns, 'pitcherStrikeouts': pitcherStrikeouts,
    'pitcherWalks': pitcherWalks, 'wins': wins, 'losses': losses, 'saves': saves, 'holds': holds,
    'doubles': doubles, 'triples': triples, 'sacFlies': sacFlies, 'hitsAllowed': hitsAllowed, 'hrAllowed': hrAllowed,
    'posGames': posGames, 'posOuts': posOuts, 'fieldChances': fieldChances, 'fieldOuts': fieldOuts,
    'runs': runs, 'hbp': hbp, 'multiHit': multiHit, 'mouda': mouda, 'cycles': cycles, 'putouts': putouts, 'assists': assists, 'errors': errors, 'dpTurned': dpTurned, 'defOuts': defOuts, 'completeGames': completeGames, 'shutouts': shutouts, 'noHitters': noHitters, 'perfects': perfects, 'hbpAllowed': hbpAllowed, 'pitchApps': pitchApps, 'reliefWins': reliefWins, 'rispAB': rispAB, 'rispH': rispH, 'multiHR': multiHR, 'walkoffs': walkoffs, 'qs': qs, 'tenK': tenK, if (gidp > 0) 'gidp': gidp, if (sacBunts > 0) 'sacB': sacBunts, if (spl.isNotEmpty) 'spl': spl, 'starts': starts, 'caughtStealing': caughtStealing, 'sbAgainst': sbAgainst, 'csAgainst': csAgainst,
  };

  factory PlayerStats.fromJson(Map<String, dynamic> json) => PlayerStats(
    games: json['games'] ?? 0, atBats: json['atBats'] ?? 0, hits: json['hits'] ?? 0,
    homeRuns: json['homeRuns'] ?? 0, rbi: json['rbi'] ?? 0, walks: json['walks'] ?? 0,
    strikeouts: json['strikeouts'] ?? 0, stolenBases: json['stolenBases'] ?? 0,
    inningsPitched: json['inningsPitched'] ?? 0, earnedRuns: json['earnedRuns'] ?? 0,
    pitcherStrikeouts: json['pitcherStrikeouts'] ?? 0, pitcherWalks: json['pitcherWalks'] ?? 0,
    wins: json['wins'] ?? 0, losses: json['losses'] ?? 0, saves: json['saves'] ?? 0, holds: json['holds'] ?? 0,
    doubles: json['doubles'] ?? 0, triples: json['triples'] ?? 0, sacFlies: json['sacFlies'] ?? 0,
    hitsAllowed: json['hitsAllowed'] ?? 0, hrAllowed: json['hrAllowed'] ?? 0,
    posGames: json['posGames'] != null ? Map<String, int>.from(json['posGames']) : null,
    spl: json['spl'] is Map ? {for (final e in (json['spl'] as Map).entries) '${e.key}': [for (final v in e.value as List) (v as num).toInt()]} : null,
    posOuts: json['posOuts'] != null ? Map<String, int>.from(json['posOuts']) : null,
    fieldChances: json['fieldChances'] ?? 0, fieldOuts: json['fieldOuts'] ?? 0,
    runs: json['runs'] ?? 0, hbp: json['hbp'] ?? 0, multiHit: json['multiHit'] ?? 0, mouda: json['mouda'] ?? 0, cycles: json['cycles'] ?? 0, putouts: json['putouts'] ?? 0, assists: json['assists'] ?? 0, errors: json['errors'] ?? 0, dpTurned: json['dpTurned'] ?? 0, defOuts: json['defOuts'] ?? 0, completeGames: json['completeGames'] ?? 0, shutouts: json['shutouts'] ?? 0, noHitters: json['noHitters'] ?? 0, perfects: json['perfects'] ?? 0, hbpAllowed: json['hbpAllowed'] ?? 0, pitchApps: json['pitchApps'] ?? 0, reliefWins: json['reliefWins'] ?? 0, rispAB: json['rispAB'] ?? 0, rispH: json['rispH'] ?? 0, multiHR: json['multiHR'] ?? 0, walkoffs: json['walkoffs'] ?? 0, qs: json['qs'] ?? 0, tenK: json['tenK'] ?? 0, gidp: json['gidp'] ?? 0, sacBunts: json['sacB'] ?? 0, starts: json['starts'] ?? 0, caughtStealing: json['caughtStealing'] ?? 0, sbAgainst: json['sbAgainst'] ?? 0, csAgainst: json['csAgainst'] ?? 0,
  );

  /// 別の成績を足し込む（通算成績づくりに使う）
  void add(PlayerStats o) {
    games += o.games; atBats += o.atBats; hits += o.hits; homeRuns += o.homeRuns; rbi += o.rbi; walks += o.walks;
    strikeouts += o.strikeouts; stolenBases += o.stolenBases; doubles += o.doubles; triples += o.triples; sacFlies += o.sacFlies;
    hitsAllowed += o.hitsAllowed; hrAllowed += o.hrAllowed; inningsPitched += o.inningsPitched; earnedRuns += o.earnedRuns;
    pitcherStrikeouts += o.pitcherStrikeouts; pitcherWalks += o.pitcherWalks; wins += o.wins; losses += o.losses; saves += o.saves; holds += o.holds;
    fieldChances += o.fieldChances; fieldOuts += o.fieldOuts;
    runs += o.runs; hbp += o.hbp; multiHit += o.multiHit; mouda += o.mouda; cycles += o.cycles; putouts += o.putouts; assists += o.assists; errors += o.errors; dpTurned += o.dpTurned; defOuts += o.defOuts; completeGames += o.completeGames; shutouts += o.shutouts; noHitters += o.noHitters; perfects += o.perfects; hbpAllowed += o.hbpAllowed; pitchApps += o.pitchApps; reliefWins += o.reliefWins; rispAB += o.rispAB; rispH += o.rispH; multiHR += o.multiHR; walkoffs += o.walkoffs; qs += o.qs; tenK += o.tenK; gidp += o.gidp; sacBunts += o.sacBunts; starts += o.starts; caughtStealing += o.caughtStealing; sbAgainst += o.sbAgainst; csAgainst += o.csAgainst;
    o.posGames.forEach((k, v) => posGames[k] = (posGames[k] ?? 0) + v);
    o.spl.forEach((k, v) {
      final m = spl.putIfAbsent(k, () => List.filled(v.length, 0));
      for (var i = 0; i < v.length && i < m.length; i++) {
        m[i] += v[i];
      }
    });
    o.posOuts.forEach((k, v) => posOuts[k] = (posOuts[k] ?? 0) + v);
  }

  /// 打席数（死球は記録していないので 打数＋四球＋犠飛）
  int get plateAppearances => atBats + walks + sacFlies;
  /// 登板数（数え始める前の記録は試合数で代用）
  int get apps => pitchApps > 0 ? pitchApps : games;
  /// 「25登板（18先発）」
  String get appsText => '${apps}登板${starts > 0 ? '（$starts先発）' : ''}';
  double get obp => plateAppearances == 0 ? 0 : (hits + walks) / plateAppearances;
  int get totalBases => hits + doubles + triples * 2 + homeRuns * 3;
  double get slg => atBats == 0 ? 0 : totalBases / atBats;
  double get ops => obp + slg;
  double get winPct => (wins + losses) == 0 ? 0 : wins / (wins + losses);
  int get holdPoints => holds + reliefWins; // ホールドポイント＝ホールド＋救援勝利
  double get rispAvg => rispAB == 0 ? 0 : rispH / rispAB; // 得点圏打率
  /// 守備位置の先発出場（外野はまとめて数える用）
  int posGamesOf(Iterable<String> ps) => ps.fold(0, (s, p) => s + (posGames[p] ?? 0));
}

class Player {
  final String id;
  final bool isPitcher;
  
  String firstName;
  String lastName;
  String nameType;
  String practiceInstruction;
  String customName; // オリジナルの姓（または「イチロー」のような1つの名前）
  String customFirst = ''; // オリジナルの名（空なら1つの名前）
  String nationality;
  int age;
  String birthDate;
  int uniformNumber; // 0〜999。-1 は「00」（0より前に並ぶ）
  String mainPos;   // メインポジション（投手/捕手/一塁手/二塁手/三塁手/遊撃手/左翼手/中堅手/右翼手）。空なら守備適性の最大から推定
  String bats;
  String throws;
  int height;
  /// 体格（体重 kg・腕の長さ・頭囲・胸囲・腹囲・臀囲 cm）。0 は自動（id と能力から毎回同じ値）。編集した値だけを持つ
  int bodyWeight = 0, bodyArm = 0, bodyHead = 0, bodyChest = 0, bodyWaist = 0, bodyHip = 0;
  Bat? batSet; // 用具（null は自動）。読むときは bat・glove
  Glove? gloveSet;
  PitchingForm? formSet; // 投球フォーム（null は自動）。読むときは form
  
  String draftType;
  String? lastDemotedDate;
  int? nextNumber;         // 来季の背番号（2月1日から。null は変更なし。-1 は「00」）
  String numberFreeUntil;  // 入団・移籍した直後で、背番号をすぐ変えられる期限（yyyy-mm-dd。'' はなし）
  int draftCustomAge;
  int proYears;

  int trajectory;
  int contactLeft;
  int contactRight;
  int power;
  int run;
  int arm;
  int throwAccuracy;
  int catchSkill;
  int eye;
  int clutch;
  
  int fieldP;
  int fieldC;
  int field1B;
  int field2B;
  int field3B;
  int fieldSS;
  int fieldLF;
  int fieldCF;
  int fieldRF;

  int velocity; 
  int pitchPower;
  int control;
  int stamina;
  int clutchPitching;
  int spinAxisSet; // 腕の角度（0＝真上 90＝真横 180＝真下）。-1 は自動（id から）。読み書きは spinAxis
  int get spinAxis => spinAxisSet >= 0 ? spinAxisSet : BodyGen.spinAxis(id);
  set spinAxis(int v) => spinAxisSet = v;
  List<Pitch> pitches;

  // ===== 身体・精神（たたき台。試合への影響は未実装） =====
  int maxEnergy;        // 体力の最大値 1〜1000（ランクは÷10）
  int energy;           // 体力の現在値 0〜maxEnergy
  int recovery;         // 回復力 1〜100（体力の毎日の回復量）
  int durability;       // 怪我しにくさ 1〜100
  int trust;            // 監督への信頼 1〜100
  double conditionFreq; // 調子の波の速さ t（調子 = 2.5·sin(t·x + φ) を0方向に丸める）
  double conditionPhase;// 調子の波の位相 φ
  int motivation;       // モチベーション 0〜100
  String growthType;    // 以前の成長タイプ（早熟 / 普通 / 晩成）。今は成長曲線（下の4つ）に移すときだけ使う
  int injuryDays;       // 怪我の残り日数（0=健康）
  String injuryName;    // 怪我の名前
  int injurySeverity;   // 0=なし 1=軽度（強行出場可） 2=中度 3=重度

  // ===== 契約 =====
  int salary;           // 年俸（万円）
  int contractYears;    // 契約年数

  int prevSalary;       // 前年の年俸（契約更改の前年比。0=なし）

  // ===== 所属・権利（フェーズ4・5） =====
  bool ikusei;          // 育成契約（背番号3桁。1軍に上がるには支配下登録が要る）
  int ikuseiYears;      // 育成契約の年数（3年で満了）
  int regDays;          // 今季の1軍登録日数（145日で FA の1年に数える）
  int faService;        // FA の資格年数（8年で国内FA権。FA 移籍すると4に戻り、4年で再取得）
  int faCount;          // FA で移籍した回数（2回目以降は補償の金銭が半分）
  int faShort;          // 志望届の希望球団による国内FA の短縮年数（2・3希望は1年、希望外は2年）
  String partnerMlb;    // 提携選手：在籍する大リーグ球団（空なら提携選手ではない）。外国人枠とは別枠
  int partnerUntil;     // 提携の最後のシーズン
  bool retainAsked;     // 自球団から残留を要請された（FA 宣言しにくくなる）
  String draftInfo;     // 入団の経緯（例：2026年ドラフト1位）
  int draftYear;        // ドラフトの年（0=不明）
  int offJoin;          // FA・新外国人で獲ったオフシーズンの年（0=なし）。そのオフは人的補償の対象外
  String lastPitched;   // 最後に登板した日（連投の判定）
  int consecDays;       // 連投の日数

  // ===== 育成（能力ごとのEXP・才能・向上心） =====
  Map<String, int> exp;        // 能力ごとのEXP（たまると能力+1。必要量は能力の高さで変わる。マイナスで下がる）
  Map<String, int> potential;  // 以前の「潜在能力（上限）」。ver1.0 からは使わない（古いセーブの読み込み用に残す）
  int quick;                   // クイック（投手。1〜100）。高いほど盗塁されにくい
  bool twoWay;                 // 二刀流（野手なら投手としても、投手なら野手としても起用できる）
  int adapt;                   // 環境適応力（外国人。1〜100・隠し）。入団時に能力へ倍率がかかる（D50×0.8・C60×0.9・B70×1.0）
  String origin;               // 出身国（外国人。例：ドミニカ）
  String birthplace;           // 出身地（日本人の都道府県。例：大阪府）
  String styleShift = '';      // ベテランのモデルチェンジ：'技巧派'（投手）・'職人'（野手）。'' はなし
  int styleShiftYear = 0;      // 転向した年
  List<String> abroad;         // 海外での成績（外国人。来日前のシーズンごと）
  int talent;                  // 才能（1〜100）。成長率 ×0.7〜×1.5
  int ambition;                // 向上心（1〜100）。成長率 ×0.2〜×3.0
  int phaseShift;              // 成長フェーズの戻り（年）。過渡期・衰退期から1つ前のフェーズに戻った分だけ、年齢を若く数える
  // 成長曲線（GrowthCurve）：全盛期が始まる年齢と、成長期・全盛期・過渡期の長さ。primeStart=0 はまだ決めていない
  int primeStart, riseLen, primeLen, transLen;
  Map<String, int> yearStart;  // 年度の初めの能力（1年の成長の結果を出すため）
  Map<String, int> baseline;   // 入団時（固有12はゲーム開始時）の能力（経歴タブで今と比べる）
  String baselineNote;         // 「入団時（2026年ドラフト）」「ゲーム開始時」など
  /// ゲームの中で入団した選手（ドラフトで指名・入団時の記録がある）。ゲーム開始前の経歴は無いので推定しない
  bool get joinedInGame => draftYear > 0 || baselineNote.startsWith('入団時');
  int hitStreak, hitStreakBest;   // 連続試合安打（いま・最高）
  int playStreak, playStreakBest; // 連続試合出場（いま・最高）
  /// 連続記録：種類 → {cur: いま, start: 始まった日, best: 自己最高, bestStart, bestEnd}
  ///  hit 連続試合安打・onBase 連続試合出塁・play 連続試合出場・hr 連続試合本塁打・scoreless 連続イニング無失点（アウトの数）・relief 救援での連続試合無失点
  Map<String, Map<String, dynamic>> streaks;
  List<String> firsts = [];    // 済んだ「プロ初」の記録（出場・安打・2番起用など。年表の初記録を一度だけ書くため）
  List<String> honors;         // 表彰・タイトルの記録（例：「2026年 首位打者」「2026年5月 月間MVP（野手）」）
  
  PlayerStats seasonStats; // 追加
  /// オープン戦の成績（今季成績・通算には入れない。開幕前の表示と、オープン戦のランキングに使う。年が明けると0）
  PlayerStats openStats;
  /// 開幕前（オープン戦の期間）は、オーダーなどにオープン戦の成績を出す
  static bool showOpen = false;
  PlayerStats get shownStats => showOpen ? openStats : seasonStats;
  PlayerStats farmStats;   // 2軍の成績（2軍の試合で積み上がる）
  PlayerStats thirdStats;  // 3軍の成績（3軍戦の簡易計算で積み上がる）
  PlayerStats career;      // 通算成績（1軍・前年まで。シーズンが終わるたびに今季の成績を足す）
  // シーズン途中の移籍：同じリーグなら成績は合算し、球団の並び（seasonTeams）だけ残す。他リーグへ移ったら、それまでの成績を seasonSplits に分けて今季成績は0から
  List<String> seasonTeams;              // 今季在籍した前の球団（同じリーグの移籍。古い順）
  List<Map<String, dynamic>> seasonSplits; // 他リーグへ移る前の成績 {team: 球団id（同リーグで移った分は「a/b」）, stats, farm}
  List<Map<String, dynamic>> seasonParts;  // 今季、前にいた球団ごとの成績（リーグに関係なく球団ごと）{team, stats, farm}。スコアラーの球団別の成績に使う
  Map<String, dynamic> partBase;           // 今の球団に来たときの今季成績 {stats, farm}（今の球団での分＝今季成績−これ）
  String typeSet;                         // 選手のタイプの指定（素材型・技巧派など。空なら能力から自動）
  List<String> amPath;                    // プロに入る前の経歴（「高校　枚方商業高（大阪）」「大学　…」）。空なら出身地と入団の経路から作る
  List<String> moves;                     // 移籍の歩み（「2026年7月15日 トレードで神戸へ（←東京新聞）」）
  bool careerEstimated;    // 通算成績が能力とプロ年数からの推定値（初期選手編集で直せる）

  Player({
    required this.id,
    required this.isPitcher,
    this.firstName = '',
    this.lastName = '',
    this.nameType = 'A',
    this.practiceInstruction = 'おまかせ',
    this.customName = '',
    this.nationality = '日本',
    this.age = 25,
    this.birthDate = '2000-01-01',
    this.uniformNumber = 0,
    this.mainPos = '',
    this.bats = 'R',
    this.throws = 'R',
    this.height = 180,
    this.draftType = 'A',
    this.lastDemotedDate,
    this.nextNumber,
    this.numberFreeUntil = '',
    this.draftCustomAge = 24,
    this.proYears = 1,
    this.trajectory = 2,
    this.contactLeft = 50,
    this.contactRight = 50,
    this.power = 50,
    this.run = 50,
    this.arm = 50,
    this.throwAccuracy = 50,
    this.catchSkill = 50,
    this.eye = 50,
    this.clutch = 50,
    this.fieldP = 1,
    this.fieldC = 1,
    this.field1B = 1,
    this.field2B = 1,
    this.field3B = 1,
    this.fieldSS = 1,
    this.fieldLF = 1,
    this.fieldCF = 1,
    this.fieldRF = 1,
    this.velocity = 145,
    this.pitchPower = 50,
    this.control = 50,
    this.stamina = 50,
    this.clutchPitching = 50,
    int spinAxis = -1,
    List<Pitch>? pitches,
    PlayerStats? seasonStats,
    PlayerStats? openStats,
    PlayerStats? farmStats,
    PlayerStats? thirdStats,
    PlayerStats? career,
    this.careerEstimated = false,
    List<String>? seasonTeams,
    List<Map<String, dynamic>>? seasonSplits,
    List<Map<String, dynamic>>? seasonParts,
    Map<String, dynamic>? partBase,
    List<String>? moves,
    List<String>? amPath,
    this.typeSet = '',
    this.maxEnergy = 500,
    int? energy,
    this.recovery = 50,
    this.durability = 50,
    this.trust = 50,
    this.conditionFreq = 0.3,
    this.conditionPhase = 0.0,
    this.motivation = 50,
    this.growthType = '普通',
    this.injuryDays = 0,
    this.injuryName = '',
    this.injurySeverity = 0,
    this.salary = 0,
    this.contractYears = 1,
    this.prevSalary = 0,
    this.ikusei = false,
    this.ikuseiYears = 0,
    this.regDays = 0,
    int? faService,
    this.faCount = 0,
    this.faShort = 0,
    this.partnerMlb = '',
    this.partnerUntil = 0,
    this.retainAsked = false,
    this.draftInfo = '',
    this.draftYear = 0,
    this.offJoin = 0,
    this.lastPitched = '',
    this.consecDays = 0,
    Map<String, int>? exp,
    Map<String, int>? potential,
    int? quick,
    this.adapt = 60,
    this.twoWay = false,
    this.origin = '',
    this.birthplace = '',
    List<String>? abroad,
    int? talent,
    int? ambition,
    this.phaseShift = 0,
    this.primeStart = 0,
    this.riseLen = 2,
    this.primeLen = 4,
    this.transLen = 2,
    Map<String, int>? yearStart,
    Map<String, int>? baseline,
    this.baselineNote = '',
    List<String>? honors,
    this.hitStreak = 0,
    this.hitStreakBest = 0,
    Map<String, Map<String, dynamic>>? streaks,
    this.playStreak = 0,
    this.playStreakBest = 0,
  }) : spinAxisSet = spinAxis,
       faService = faService ?? (proYears - 1).clamp(0, 30), // 開始時はプロ9年目以上が FA 権を持つ
       exp = exp ?? {},
       potential = potential ?? {},
       quick = quick ?? _seededTrait(id, 0x51c7), // 生成時は平均50。初期データ・ドラフト・外国人で +10 して平均60にする
       abroad = abroad ?? [],
       talent = talent ?? _seededTrait(id, 0x7a1e),
       ambition = ambition ?? _seededTrait(id, 0x3b9c),
       yearStart = yearStart ?? {},
       baseline = baseline ?? {},
       honors = honors ?? [],
       seasonStats = seasonStats ?? PlayerStats(),
       openStats = openStats ?? PlayerStats(),
       farmStats = farmStats ?? PlayerStats(),
       thirdStats = thirdStats ?? PlayerStats(),
       career = career ?? PlayerStats(),
       seasonTeams = seasonTeams ?? [],
       seasonSplits = seasonSplits ?? [],
       seasonParts = seasonParts ?? [],
       partBase = partBase ?? {},
       moves = moves ?? [],
       amPath = amPath ?? [],
       streaks = streaks ?? {},
       energy = energy ?? maxEnergy,
       pitches = pitches ?? (isPitcher ? [
          Pitch(name: 'ストレート', breakLevel: 0, angle: 90, speed: velocity, ratio: 45, sharpness: 60, heaviness: 60),
          Pitch(name: 'スライダー', breakLevel: 60, angle: 180, speed: velocity - 15, ratio: 25, sharpness: 60, heaviness: 60),
          Pitch(name: 'カーブ', breakLevel: 60, angle: 135, speed: velocity - 30, ratio: 15, sharpness: 60, heaviness: 60),
          Pitch(name: 'フォーク', breakLevel: 60, angle: 90, speed: velocity - 20, ratio: 15, sharpness: 60, heaviness: 60),
       ] : [fielderStraight(velocity)]);

  String get registeredName {
    if (nameType == 'A') return '$lastName $firstName';
    if (nameType == 'B') return '$lastName$firstName';
    if (nameType == 'C') return '$lastName${firstName.isNotEmpty ? firstName[0] : ''}';
    if (nameType == 'D') return firstName;
    if (nameType == 'E') return customName.isNotEmpty ? (customFirst.isNotEmpty ? '$customName $customFirst' : customName) : '$lastName $firstName';
    if (nameType == 'F') return firstName.isNotEmpty ? '$firstName・$lastName' : lastName;
    return lastName;
  }

  /// 才能・向上心の初期値（id から固定で決める。平均50・ばらつき15）
  static int _seededTrait(String id, int salt, {double mean = 50, double sd = 15}) {
    final r = Random(id.hashCode ^ salt);
    final g = sqrt(-2.0 * log(1.0 - r.nextDouble())) * cos(2.0 * pi * r.nextDouble());
    return (mean + g * sd).round().clamp(1, 100);
  }

  /// ver1.0.1：クイック・チャンス・ピンチの平均を60に（以前のデータと初期データ）。一律50だった値は選手ごとにばらつかせる
  void raiseClutchQuick() {
    int lift(int v, int salt) => v == 50 ? _seededTrait(id, salt, mean: 60, sd: 10) : (v + 10).clamp(1, 99);
    clutch = lift(clutch, 0xc1);
    clutchPitching = lift(clutchPitching, 0xc2);
    quick = (quick + 10).clamp(1, 99);
  }

  /// 成長率 = 才能の倍率 × 向上心の倍率（平均の選手（50・50）が ×1.0）。向上心が主役：
  ///  向上心 1→×0.2、50→×1.0、80→×1.85、100→×3.0（高いほど急に伸びる。80を超えるとさらに上乗せ）。才能 1→×0.7、100→×1.5（才能だけでは伸びない。努力家は才能が並でも大きく伸びる）
  double get growthRate => rateOf(talent, ambition);
  static double rateOf(num talent, num ambition) => (0.7 + talent * 0.008) * (0.2 + 2.3 * pow(ambition / 100, 1.5) + (ambition > 80 ? (ambition - 80) / 20 * 0.5 : 0)) / 1.1142;

  /// 一覧に出す名前：日本人は「姓 名」、外国人（F）は姓だけ、それ以外は登録名
  String get listName => nameType == 'F' ? lastName : (nameType == 'A' ? '$lastName $firstName'.trim() : registeredName);

  int get contact => ((contactLeft + contactRight) / 2).round();

  /// 連続記録を進める：続いたら add だけ伸ばし、途切れたら0に。自己最高を更新したら期間も残す
  void streakStep(String key, bool keep, DateTime d, {int add = 1}) {
    final m = streaks.putIfAbsent(key, () => {'cur': 0, 'best': 0});
    final day = '${d.year}/${d.month}/${d.day}';
    if (!keep) {
      m['cur'] = 0;
      m.remove('start');
      return;
    }
    if ((m['cur'] ?? 0) == 0) m['start'] = day;
    m['cur'] = (m['cur'] ?? 0) + add;
    if ((m['cur'] as int) > (m['best'] ?? 0)) {
      m['best'] = m['cur'];
      m['bestStart'] = m['start'];
      m['bestEnd'] = day;
    }
  }

  int get ovr {
    // チャンス・ピンチは平均60（ver1.0.1で+10）。OVR はそれ以前と同じ基準になるよう、10を引いて数える
    if (isPitcher) return ((velocityNorm + pitchPower + control + stamina + clutchPitching - 10) / 5).round();
    return ((contact + power + run + arm + throwAccuracy + catchSkill + eye + clutch - 10) / 8).round();
  }

  /// 投手として起用できるか（投手、または二刀流）
  bool get canPitch => isPitcher || twoWay;

  /// 野手として打順に入れられるか（野手、または二刀流）
  bool get canBat => !isPitcher || twoWay;

  // ───────── 体格（編集した値、無ければ自動） ─────────
  double get _bmi => BodyGen.bmi(id, power: power, pitchPower: pitchPower, pitcher: isPitcher);
  int get weight => bodyWeight > 0 ? bodyWeight : BodyGen.weight(id, height, power: power, pitchPower: pitchPower, pitcher: isPitcher);
  int get armLength => bodyArm > 0 ? bodyArm : BodyGen.armLength(id, height, arm: arm, velocity: velocity);
  int get headGirth => bodyHead > 0 ? bodyHead : BodyGen.headGirth(id, height);
  int get chestGirth => bodyChest > 0 ? bodyChest : BodyGen.chestGirth(id, height, _bmi);
  int get waistGirth => bodyWaist > 0 ? bodyWaist : BodyGen.waistGirth(id, height, _bmi);
  int get hipGirth => bodyHip > 0 ? bodyHip : BodyGen.hipGirth(id, height, _bmi);

  /// 投球フォーム（編集したもの、無ければ自動）。腕の角度の分類は armSlot
  PitchingForm get form => formSet ?? BodyGen.form(id, velocity: velocity, control: control, stamina: stamina);
  String get armSlot => PitchingForm.armSlotOf(spinAxis);

  /// 用具（編集したもの、無ければ自動）
  Bat get bat => batSet ?? Bat.auto(id, power: power, contact: (contactLeft + contactRight) ~/ 2, height: height);
  Glove get glove => gloveSet ?? Glove.auto(id, isPitcher ? '投手' : mainPosition);

  int get velocityNorm => Velo.norm(velocity, slot: armSlot); // 球速の能力の値（速いほど1kmの価値が大きい。アンダーは体感で上乗せ）

  String get mainPosition {
    if (isPitcher) return '投手';
    if (mainPos.isNotEmpty && mainPos != '投手') return mainPos;
    Map<String, int> pos = {
      '捕手': fieldC, '一塁手': field1B, '二塁手': field2B, '三塁手': field3B,
      '遊撃手': fieldSS, '左翼手': fieldLF, '中堅手': fieldCF, '右翼手': fieldRF,
    };
    var sorted = pos.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return sorted.first.key;
  }

  /// 体力のランク用の値（最大値÷10、1〜100）
  int get energyRank => (maxEnergy / 10).round().clamp(1, 100);

  /// 調子（−2〜+2）。2.5·sin(t·x + φ) を0の方向へ丸める（正は切り捨て・負は切り上げ）。x はシーズン開始からの日数
  int conditionOn(int day) => (2.5 * sin(conditionFreq * day + conditionPhase)).truncate().clamp(-2, 2);

  /// その日の調子（x = その年の1月1日からの日数）
  int conditionAt(DateTime d) => conditionOn(dayOfYear(d));

  /// その年の1月1日からの日数（0〜365）。DateTime を作らずに計算する（試合中に何度も呼ぶため）
  static int dayOfYear(DateTime d) {
    const cum = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334];
    final leap = d.year % 4 == 0 && (d.year % 100 != 0 || d.year % 400 == 0);
    return cum[d.month - 1] + d.day - 1 + (leap && d.month > 2 ? 1 : 0);
  }

  /// 体力の割合（0〜1）
  double get energyRatio => maxEnergy > 0 ? (energy / maxEnergy).clamp(0.0, 1.0) : 1.0;

  static const conditionLabels = {-2: '絶不調', -1: '不調', 0: '普通', 1: '好調', 2: '絶好調'};

  /// 怪我で出場できないか（軽度は強行出場できる）
  bool get isInjuredOut => injuryDays > 0 && injurySeverity >= 2;

  /// FA 権を持っているか（資格6年。外国人・育成は対象外）
  /// 外国人枠に入る選手（海外出身で、FA 権（6年）を取る前）。FA 権を取ると日本人選手の扱い（外国人枠外・FA 宣言・人的補償の対象）
  /// 国内FA の資格年数（仕様書 2.1）
  static const faYears = 8;
  /// 海外FA の資格年数（仮。仕様書 8章で未決：現実は9年）
  static const overseasFaYears = 9;
  bool get isPartner => partnerMlb.isNotEmpty;
  bool get foreignSlot => nationality == '海外' && faService < faYears && !isPartner; // 提携選手は外国人枠とは別枠
  /// この選手の国内FA の年数（志望届で短くなることがある。FA で移籍したあとの再取得は短縮なし）
  int get faNeed => faCount > 0 ? faYears : faYears - faShort;
  bool get hasFA => faService >= faNeed && !ikusei;

  /// オリジナルの名前を使っているか（お知らせで本名を（）に添える）
  bool get hasOriginalName => nameType == 'E' && customName.isNotEmpty;

  /// 本名（姓名）
  String get realName => '$lastName$firstName';

  String get shortName {
    if (nameType == 'A' || nameType == 'F') return lastName;
    if (nameType == 'E') return customName.isNotEmpty ? customName : lastName;
    return registeredName;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'isPitcher': isPitcher,
      'firstName': firstName,
      'lastName': lastName,
      'nameType': nameType,
      'practiceInstruction': practiceInstruction,
      'customName': customName,
      if (customFirst.isNotEmpty) 'customFirst': customFirst,
      'nationality': nationality,
      'age': age,
      'birthDate': birthDate,
      'uniformNumber': uniformNumber,
      'mainPos': mainPos,
      'bats': bats,
      'throws': throws,
      'height': height,
      'h2': true,
      'draftType': draftType,
      'lastDemotedDate': lastDemotedDate,
      if (nextNumber != null) 'nextNumber': nextNumber,
      if (numberFreeUntil.isNotEmpty) 'numberFreeUntil': numberFreeUntil,
      'draftCustomAge': draftCustomAge,
      'proYears': proYears,
      'trajectory': trajectory,
      'contactLeft': contactLeft,
      'contactRight': contactRight,
      'power': power,
      'run': run,
      'arm': arm,
      'throwAccuracy': throwAccuracy,
      'catchSkill': catchSkill,
      'eye': eye,
      'clutch': clutch,
      'fieldP': fieldP, 'fieldC': fieldC, 'field1B': field1B, 'field2B': field2B,
      'field3B': field3B, 'fieldSS': fieldSS, 'fieldLF': fieldLF, 'fieldCF': fieldCF, 'fieldRF': fieldRF,
      'velocity': velocity,
      'pitchPower': pitchPower,
      'control': control,
      'stamina': stamina,
      'clutchPitching': clutchPitching,
      'spinAxis': spinAxisSet,
      'sa2': true,
      if (bodyWeight + bodyArm + bodyHead + bodyChest + bodyWaist + bodyHip > 0) 'body': [bodyWeight, bodyArm, bodyHead, bodyChest, bodyWaist, bodyHip],
      if (batSet != null) 'bat': batSet!.toJson(),
      if (gloveSet != null) 'glove': gloveSet!.toJson(),
      if (formSet != null) 'form': formSet!.toJson(),
      'pitches': pitches.map((p) => p.toJson()).toList(),
      'maxEnergy': maxEnergy,
      'energy': energy,
      'recovery': recovery,
      'durability': durability,
      'trust': trust,
      'conditionFreq': conditionFreq,
      'conditionPhase': conditionPhase,
      'motivation': motivation,
      'growthType': growthType,
      'injuryDays': injuryDays,
      'injuryName': injuryName,
      'injurySeverity': injurySeverity,
      'salary': salary,
      'contractYears': contractYears,
      'prevSalary': prevSalary,
      'ikusei': ikusei,
      'ikuseiYears': ikuseiYears,
      'regDays': regDays,
      'faService': faService,
      if (faCount > 0) 'faCount': faCount,
      if (faShort > 0) 'faShort': faShort,
      if (partnerMlb.isNotEmpty) 'partner': [partnerMlb, partnerUntil],
      'retainAsked': retainAsked,
      'draftInfo': draftInfo,
      'draftYear': draftYear,
      if (offJoin != 0) 'offJoin': offJoin,
      'lastPitched': lastPitched,
      'consecDays': consecDays,
      'exp': exp,
      'potential': potential,
      'quick': quick,
      if (nationality == '海外') 'adapt': adapt,
      if (twoWay) 'twoWay': true,
      if (origin.isNotEmpty) 'origin': origin,
      if (birthplace.isNotEmpty) 'bp': birthplace,
      if (styleShift.isNotEmpty) 'shift': styleShift,
      if (styleShiftYear != 0) 'shiftY': styleShiftYear,
      if (abroad.isNotEmpty) 'abroad': abroad,
      'talent': talent,
      'ambition': ambition,
      'phaseShift': phaseShift,
      'curve': [primeStart, riseLen, primeLen, transLen],
      'yearStart': yearStart,
      'baseline': baseline,
      'baselineNote': baselineNote,
      'honors': honors,
      if (firsts.isNotEmpty) 'firsts': firsts,
      'hitStreak': hitStreak, 'hitStreakBest': hitStreakBest, 'playStreak': playStreak, 'playStreakBest': playStreakBest, 'streaks': streaks,
      'seasonStats': seasonStats.toJson(),
      if (openStats.games > 0 || openStats.pitchApps > 0) 'openStats': openStats.toJson(),
      'farmStats': farmStats.toJson(),
      'thirdStats': thirdStats.toJson(),
      'career': career.toJson(),
      'seasonTeams': seasonTeams,
      'seasonSplits': seasonSplits,
      if (seasonParts.isNotEmpty) 'seasonParts': seasonParts,
      if (partBase.isNotEmpty) 'partBase': partBase,
      'moves': moves,
      if (amPath.isNotEmpty) 'amp': amPath,
      if (typeSet.isNotEmpty) 'typ': typeSet,
      'careerEstimated': careerEstimated,
    };
  }

  /// 野手の持ち球（ストレートだけ）
  static Pitch fielderStraight(int velocity) => Pitch(name: 'ストレート', breakLevel: 0, angle: 90, speed: velocity, ratio: 100, sharpness: 30, heaviness: 30);

    static List<Pitch> _parsePitches(dynamic pitchesJson, bool isPitcher, int velocity) {
    if (pitchesJson != null && pitchesJson is List && pitchesJson.isNotEmpty) {
      return pitchesJson.map((p) => Pitch.fromJson(p)).toList();
    }
    if (isPitcher) {
      return [
        Pitch(name: 'ストレート', breakLevel: 0, angle: 90, speed: velocity, ratio: 45, sharpness: 60, heaviness: 60),
        Pitch(name: 'スライダー', breakLevel: 60, angle: 180, speed: velocity - 15, ratio: 25, sharpness: 60, heaviness: 60),
        Pitch(name: 'カーブ', breakLevel: 60, angle: 135, speed: velocity - 30, ratio: 15, sharpness: 60, heaviness: 60),
        Pitch(name: 'フォーク', breakLevel: 60, angle: 90, speed: velocity - 20, ratio: 15, sharpness: 60, heaviness: 60),
      ];
    }
    return [fielderStraight(velocity)];
  }
  
  factory Player.fromJson(Map<String, dynamic> json) {
    final p = _fromJson(json)..firsts = List<String>.from(json['firsts'] ?? const []);
    if (json['bat'] is Map) p.batSet = Bat.fromJson(Map<String, dynamic>.from(json['bat'] as Map));
    if (json['glove'] is Map) p.gloveSet = Glove.fromJson(Map<String, dynamic>.from(json['glove'] as Map));
    final b = json['body'];
    if (b is List && b.length >= 6) {
      p.bodyWeight = b[0];
      p.bodyArm = b[1];
      p.bodyHead = b[2];
      p.bodyChest = b[3];
      p.bodyWaist = b[4];
      p.bodyHip = b[5];
    }
    if (json['form'] is Map) p.formSet = PitchingForm.fromJson(Map<String, dynamic>.from(json['form'] as Map));
    p.styleShift = json['shift'] ?? '';
    p.styleShiftYear = json['shiftY'] ?? 0;
    p.customFirst = json['customFirst'] ?? '';
    return p;
  }

  static Player _fromJson(Map<String, dynamic> json) {
    return Player(
      id: json['id'],
      isPitcher: json['isPitcher'],
      firstName: json['firstName'],
      lastName: json['lastName'],
      nameType: json['nameType'] ?? 'A',
      practiceInstruction: json['practiceInstruction'] ?? 'おまかせ',
      customName: json['customName'] ?? '',
      nationality: json['nationality'] ?? '日本',
      age: json['age'],
      birthDate: json['birthDate'] ?? '2000-01-01',
      uniformNumber: json['uniformNumber'],
      mainPos: json['mainPos'] ?? '',
      bats: json['bats'] ?? 'R',
      throws: json['throws'] ?? 'R',
      // 身長：以前のデータは全員が初期値の180だったので、180は id から決まる値として読む（h2 があれば保存した値どおり）
      height: json['h2'] == true ? (json['height'] ?? 180) : ((json['height'] ?? 180) == 180 ? BodyGen.height(json['id'] as String, json['isPitcher'] == true) : json['height']),
      draftType: json['draftType'] ?? 'A',
      lastDemotedDate: json['lastDemotedDate'],
      nextNumber: json['nextNumber'] as int?,
      numberFreeUntil: (json['numberFreeUntil'] ?? '') as String,
      draftCustomAge: json['draftCustomAge'],
      proYears: json['proYears'],
      trajectory: json['trajectory'],
      contactLeft: json['contactLeft'],
      contactRight: json['contactRight'],
      power: json['power'],
      run: json['run'],
      arm: json['arm'],
      throwAccuracy: json['throwAccuracy'],
      catchSkill: json['catchSkill'],
      eye: json['eye'] ?? 50,
      clutch: json['clutch'] ?? 50,
      fieldP: json['fieldP'], fieldC: json['fieldC'], field1B: json['field1B'], field2B: json['field2B'],
      field3B: json['field3B'], fieldSS: json['fieldSS'], fieldLF: json['fieldLF'], fieldCF: json['fieldCF'], fieldRF: json['fieldRF'],
      velocity: json['velocity'],
      pitchPower: json['pitchPower'],
      control: json['control'],
      stamina: json['stamina'],
      clutchPitching: json['clutchPitching'] ?? 50,
      // 腕の角度：以前のデータは全員が初期値の45だったので、45は「自動」として読む（sa2 があれば保存した値どおり）
      spinAxis: json['sa2'] == true ? (json['spinAxis'] ?? -1) : ((json['spinAxis'] ?? 45) == 45 ? -1 : json['spinAxis']),
      pitches: _parsePitches(json['pitches'], json['isPitcher'], json['velocity']),
      seasonStats: json['seasonStats'] != null ? PlayerStats.fromJson(json['seasonStats']) : null,
      openStats: json['openStats'] != null ? PlayerStats.fromJson(Map<String, dynamic>.from(json['openStats'] as Map)) : null,
      farmStats: json['farmStats'] != null ? PlayerStats.fromJson(json['farmStats']) : null,
      thirdStats: json['thirdStats'] != null ? PlayerStats.fromJson(json['thirdStats']) : null,
      career: json['career'] != null ? PlayerStats.fromJson(json['career']) : null,
      seasonTeams: json['seasonTeams'] != null ? List<String>.from(json['seasonTeams']) : null,
      seasonSplits: json['seasonSplits'] != null ? [for (final e in json['seasonSplits'] as List) Map<String, dynamic>.from(e as Map)] : null,
      seasonParts: json['seasonParts'] != null ? [for (final e in json['seasonParts'] as List) Map<String, dynamic>.from(e as Map)] : null,
      partBase: json['partBase'] != null ? Map<String, dynamic>.from(json['partBase'] as Map) : null,
      moves: json['moves'] != null ? List<String>.from(json['moves']) : null,
      amPath: json['amp'] != null ? List<String>.from(json['amp']) : null,
      typeSet: json['typ'] ?? '',
      careerEstimated: json['careerEstimated'] ?? false,
      maxEnergy: json['maxEnergy'] ?? 500,
      energy: json['energy'],
      recovery: json['recovery'] ?? 50,
      durability: json['durability'] ?? 50,
      trust: json['trust'] ?? 50,
      conditionFreq: (json['conditionFreq'] as num?)?.toDouble() ?? 0.3,
      conditionPhase: (json['conditionPhase'] as num?)?.toDouble() ?? 0.0,
      motivation: json['motivation'] ?? 50,
      growthType: json['growthType'] ?? '普通',
      injuryDays: json['injuryDays'] ?? 0,
      injuryName: json['injuryName'] ?? '',
      injurySeverity: json['injurySeverity'] ?? 0,
      salary: json['salary'] ?? 0,
      contractYears: json['contractYears'] ?? 1,
      prevSalary: json['prevSalary'] ?? 0,
      ikusei: json['ikusei'] ?? false,
      ikuseiYears: json['ikuseiYears'] ?? 0,
      regDays: json['regDays'] ?? 0,
      faService: json['faService'],
      faCount: json['faCount'] ?? 0,
      faShort: json['faShort'] ?? 0,
      partnerMlb: json['partner'] is List ? '${(json['partner'] as List)[0]}' : '',
      partnerUntil: json['partner'] is List ? ((json['partner'] as List)[1] as num).toInt() : 0,
      retainAsked: json['retainAsked'] ?? false,
      draftInfo: json['draftInfo'] ?? '',
      draftYear: json['draftYear'] ?? 0,
      offJoin: json['offJoin'] ?? 0,
      lastPitched: json['lastPitched'] ?? '',
      consecDays: json['consecDays'] ?? 0,
      exp: json['exp'] != null ? Map<String, int>.from(json['exp']) : null,
      potential: json['potential'] != null ? Map<String, int>.from(json['potential']) : null,
      quick: json['quick'],
      adapt: json['adapt'] ?? 60,
      twoWay: json['twoWay'] == true,
      origin: json['origin'] ?? '',
      birthplace: json['bp'] ?? '',
      abroad: json['abroad'] != null ? List<String>.from(json['abroad']) : null,
      talent: json['talent'],
      ambition: json['ambition'],
      phaseShift: json['phaseShift'] ?? 0,
      primeStart: json['curve'] is List ? (json['curve'] as List)[0] as int : 0,
      riseLen: json['curve'] is List ? (json['curve'] as List)[1] as int : 2,
      primeLen: json['curve'] is List ? (json['curve'] as List)[2] as int : 4,
      transLen: json['curve'] is List ? (json['curve'] as List)[3] as int : 2,
      yearStart: json['yearStart'] != null ? Map<String, int>.from(json['yearStart']) : null,
      baseline: json['baseline'] != null ? Map<String, int>.from(json['baseline']) : null,
      baselineNote: json['baselineNote'] ?? '',
      honors: json['honors'] != null ? List<String>.from(json['honors']) : null,
      hitStreak: json['hitStreak'] ?? 0, hitStreakBest: json['hitStreakBest'] ?? 0, playStreak: json['playStreak'] ?? 0, playStreakBest: json['playStreakBest'] ?? 0,
      streaks: json['streaks'] is Map ? {for (final e in (json['streaks'] as Map).entries) '${e.key}': Map<String, dynamic>.from(e.value as Map)} : null,
    );
  }
}




/// 背番号の表示（-1 は「00」）
String uniformLabel(int n) => n < 0 ? '00' : '$n';

/// 背番号の並び替えキー（00 → 0 → 1 → … → 999）
int uniformSortKey(int n) => n;

/// 入力文字列を背番号に変換する（"00"→-1、"0"〜"999"→数値、不正はnull）
int? parseUniform(String s) {
  final t = s.trim();
  if (t == '00') return -1;
  final v = int.tryParse(t);
  if (v == null || v < 0 || v > 999) return null;
  return v;
}

extension PlayerUniform on Player {
  String get uniformText => uniformLabel(uniformNumber);
}

/// 背番号順（同じ番号は名前順）の比較関数
int compareByUniform(Player a, Player b) {
  final c = uniformSortKey(a.uniformNumber).compareTo(uniformSortKey(b.uniformNumber));
  return c != 0 ? c : a.registeredName.compareTo(b.registeredName);
}
