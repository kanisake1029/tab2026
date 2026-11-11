import 'dart:math';
import 'foreign_engine.dart';
import '../models/coach.dart';
import '../models/player.dart';
import '../models/team.dart';
import '../utils/salary_utils.dart';
import 'coach_engine.dart';
import 'growth_engine.dart';
import 'roster_engine.dart';

/// 自由契約の選手（戦力外・契約満了・FA で行き先が決まらない選手など）
class FreeAgent {
  final Player player;
  final String fromTeamId; // 元の球団（'' は海外・新規）
  final String reason;     // 戦力外 / 育成満了 / 退団 など
  FreeAgent(this.player, this.fromTeamId, this.reason);

  Map<String, dynamic> toJson() => {'player': player.toJson(), 'from': fromTeamId, 'reason': reason};
  factory FreeAgent.fromJson(Map<String, dynamic> j) => FreeAgent(Player.fromJson(Map<String, dynamic>.from(j['player'] as Map)), j['from'] ?? '', j['reason'] ?? '');
}

/// FA 宣言した選手と、各球団の条件
class FaCase {
  final String playerId;
  final String fromTeamId;
  final String rank;        // A / B / C（元の球団での年俸順位）
  final int ask;            // 希望年俸（万円）
  final Map<String, List<int>> offers; // 球団ID → [年俸, 年数]
  String result;            // 決まった球団ID（'' は未定）

  FaCase({required this.playerId, required this.fromTeamId, required this.rank, required this.ask, Map<String, List<int>>? offers, this.result = ''})
      : offers = offers ?? {};

  Map<String, dynamic> toJson() => {'pid': playerId, 'from': fromTeamId, 'rank': rank, 'ask': ask, 'offers': offers, 'result': result};
  factory FaCase.fromJson(Map<String, dynamic> j) => FaCase(
        playerId: j['pid'],
        fromTeamId: j['from'],
        rank: j['rank'] ?? 'C',
        ask: j['ask'] ?? 0,
        offers: {for (final e in (j['offers'] as Map? ?? {}).entries) e.key as String: List<int>.from(e.value as List)},
        result: j['result'] ?? '',
      );
}

/// FA の補償（仕様書 2.2）。元の球団が ①指名権＋金銭 か ②金銭のみ を選ぶ。人的補償はない
///  A：①1.5位＋年俸の50% ／ ②100%　B：①2.5位＋40% ／ ②80%　C：金銭30%のみ
///  2回目以降の FA（repeat）は①の金銭が半分
class CompCase {
  final String playerName;
  final String rank;
  final String fromTeamId; // 選手を失った球団（補償を受け取る）
  final String toTeamId;   // 選手を獲った球団（金銭を払う。指名権はリーグが与える）
  final int salary;        // 前年の年俸
  final bool repeat;       // 2回目以降の FA
  CompCase(this.playerName, this.rank, this.fromTeamId, this.toTeamId, this.salary, {this.repeat = false});

  bool get hasPick => rank == 'A' || rank == 'B';
  /// 補償の指名権の名前
  String get pickLabel => rank == 'A' ? '1.5位' : '2.5位';

  /// 金銭の額（withPick：①指名権＋金銭 ／ false：②金銭のみ）
  int money(bool withPick) {
    final rate = switch (rank) {
      'A' => withPick ? (repeat ? 0.25 : 0.5) : 1.0,
      'B' => withPick ? (repeat ? 0.2 : 0.4) : 0.8,
      _ => 0.3,
    };
    return (salary * rate).round();
  }

  Map<String, dynamic> toJson() => {'name': playerName, 'rank': rank, 'from': fromTeamId, 'to': toTeamId, 'salary': salary, if (repeat) 'rep': true};
  factory CompCase.fromJson(Map<String, dynamic> j) => CompCase(j['name'], j['rank'], j['from'], j['to'], j['salary'] ?? 0, repeat: j['rep'] == true);
}

/// 引退・戦力外・FA・トレード・外国人・契約更改
class TransferEngine {
  // ───────── 引退 ─────────

  /// 引退する確率（年齢・成長フェーズ・能力・出場）
  static double retireChance(Player p) {
    if (p.age >= 42) return 1.0;
    final phase = GrowthEngine.phaseOf(p);
    var c = 0.0;
    if (phase == GrowthPhase.decline) {
      c = 0.18 + max(0, p.age - 33) * 0.07;
    } else if (phase == GrowthPhase.transition) {
      c = 0.04;
    } else if (p.age >= 30) {
      c = 0.01;
    }
    if (p.ovr < 45) c += 0.2; else if (p.ovr < 50) c += 0.1;
    if (p.ovr >= 68) c -= 0.15;
    if (p.seasonStats.games == 0 && p.age >= 30) c += 0.12;
    if (p.ikusei && p.age >= 26) c += 0.25;
    if (p.styleShift.isNotEmpty && p.age <= 40) c *= 0.45; // モデルチェンジしたベテランは息が長い
    return c.clamp(0.0, 1.0);
  }

  /// 引退した選手から OB（コーチ候補）を作る。指導力の予想は通算成績から、本当の値は 50% が隠れた値
  static Coach obFromPlayer(Player p, String teamId, Random r) {
    final c = p.career;
    final type = CoachEngine.playerType(p);
    final exp = <String, int>{};
    int cl(num v) => v.round().clamp(20, 95).toInt();
    double fame;
    Map<String, int> career;
    if (p.isPitcher) {
      final era = c.inningsPitched == 0 ? 450 : (c.era * 100).round();
      career = {'games': c.games, 'wins': c.wins, 'saves': c.saves, 'era': era};
      fame = (c.wins / 200 + c.saves / 250).clamp(0, 1.2);
      exp['球速球威'] = cl(48 + (type == '剛腕派' ? 16 : 0) + (type == 'イニングイーター' ? 6 : 0) + c.wins / 220 * 12);
      exp['制球'] = cl(48 + (type == '技巧派' ? 16 : 0) + (era < 320 ? 6 : 0));
      exp['スタミナ'] = cl(46 + (type == 'イニングイーター' ? 16 : 0));
      exp['変化球'] = cl(48 + (type == '技巧派' ? 14 : 0) + (type == '本格派' ? 5 : 0));
      exp['打撃'] = cl(32 + r.nextInt(18));
      exp['守備'] = cl(38 + r.nextInt(20));
      exp['走塁'] = cl(32 + r.nextInt(18));
    } else {
      final avg = c.atBats == 0 ? 200 : (c.battingAverage * 1000).round();
      career = {'games': c.games, 'hits': c.hits, 'hr': c.homeRuns, 'avg': avg};
      fame = (c.hits / 2000 + c.homeRuns / 400).clamp(0, 1.2);
      exp['打撃'] = cl(44 + c.hits / 2500 * 28 + (avg - 260) * 0.12 + (type == '打撃職人型' || type == 'スラッガー型' ? 6 : 0));
      exp['守備'] = cl(48 + (type == '守備職人型' ? 18 : 0) + (type == '俊足巧打型' ? 6 : 0));
      exp['走塁'] = cl(46 + (type == '俊足巧打型' ? 18 : 0) + (type == '素材型' ? 8 : 0));
      for (final k in ['球速球威', '制球', 'スタミナ', '変化球']) {
        exp[k] = cl(32 + r.nextInt(16));
      }
    }
    exp['人望'] = cl(44 + fame * 16 + (p.trust - 50) * 0.3 + r.nextInt(21) - 10);
    for (final k in ['代打判断', '継投判断', '守備交代判断', '走塁判断']) {
      exp[k] = cl(42 + r.nextInt(26) - 8);
    }
    exp['スカウト眼力'] = cl(38 + r.nextInt(42));
    exp['育成眼'] = cl(38 + (p.age - 45) * 0.4 + r.nextInt(42));
    final tr = <String, int>{for (final k in Coach.abilityKeys) k: cl((exp[k]! + 30 + r.nextInt(61)) / 2)};
    final coach = Coach(
      id: 'OB_${p.id}',
      lastName: p.lastName,
      firstName: p.firstName,
      age: p.age,
      pitcherBg: p.isPitcher,
      type: type,
      formerTeamId: teamId,
      career: career,
      trueAbil: tr,
      expected: exp,
    );
    coach.salary = CoachEngine.askingSalary(coach, teamId);
    return coach;
  }

  // ───────── 戦力外（CPU） ─────────

  /// CPU 球団が戦力外にする選手。ドラフトの枠（keepSlots 人分）を空け、力の落ちたベテランを外す
  static List<Player> cpuReleases(Team t, {int keepSlots = 13}) { // ドラフト前に57人ほどまで減らす（ドラフト後に63人前後）
    final out = <Player>[];
    final counts = RosterEngine.posCounts(t);
    bool canDrop(Player p) {
      final pos = p.mainPosition;
      final min = pos == '投手' ? 28 : (pos == '捕手' ? 3 : 2);
      return (counts[pos] ?? 0) > min;
    }

    final shihaika = t.players.where((p) => !p.ikusei).toList()..sort((a, b) => RosterEngine.value(a).compareTo(RosterEngine.value(b)));
    var count = shihaika.length;
    var released = 0;
    for (final p in shihaika) {
      final v = RosterEngine.value(p);
      final mustFree = count > RosterEngine.maxShihaika - keepSlots;
      final weak = (p.age >= 28 && v < 48) || (p.age >= 31 && v < 52);
      if (!(mustFree || (weak && released < 4))) continue;
      if (!canDrop(p)) continue;
      out.add(p);
      counts[p.mainPosition] = (counts[p.mainPosition] ?? 1) - 1;
      count--;
      released++;
      if (released >= 9) break;
    }
    // 育成で3年を過ぎた選手は、育成テンダー（11月20日〜12月1日）で扱う
    return out;
  }

  // ───────── 契約更改 ─────────

  /// 今季の成績から年俸の増減の倍率（0.7〜1.6）
  static double performance(Player p) {
    final s = p.seasonStats;
    if (p.isPitcher) {
      final ip = s.inningsPitched / 3;
      if (ip >= 80) return (pow(3.4 / max(1.2, s.era), 0.8) * (0.85 + ip / 600)).clamp(0.7, 1.6).toDouble();
      if (s.games >= 30) return (1.0 + (s.saves + s.holds) / 80 - max(0, s.era - 3.5) * 0.1).clamp(0.7, 1.6);
      return s.games >= 10 ? 0.95 : 0.85;
    }
    final pa = s.plateAppearances;
    if (pa >= 300) return (pow(s.ops / 0.700, 2) * (0.9 + pa / 2500)).clamp(0.7, 1.6).toDouble();
    if (pa >= 100) return (s.ops / 0.700).clamp(0.75, 1.2);
    return s.games >= 20 ? 0.95 : 0.85;
  }

  /// 契約更改。複数年契約は年数を減らすだけ。上げ幅は2倍まで、下げ幅は NPB の減額制限（−25%）まで
  static int renewSalary(Player p) {
    p.prevSalary = p.salary;
    if (p.contractYears > 1) {
      p.contractYears--;
      return p.salary;
    }
    p.salary = renewTarget(p);
    p.contractYears = 1;
    return p.salary;
  }

  /// 契約更改の目安の年俸（今季の働きから。年俸は書き換えない）
  static int renewTarget(Player p) {
    final base = estimateSalary(p);
    final target = (base * performance(p)).round();
    final lo = (p.salary * 0.75).round(), hi = p.salary * 2;
    var s = target.clamp(lo, max(lo, hi));
    if (p.ikusei) s = s.clamp(250, 1000);
    s = max(s, p.ikusei ? 250 : 450);
    return round50(s);
  }

  // ───────── FA ─────────

  /// 年俸ランク（仕様書 2.3）：リーグ全体の日本人選手（外国人枠の選手を除く・支配下）の年俸順位で
  ///  A：1〜36位、B：37〜120位、C：121位以下
  static const rankA = 36, rankB = 120;
  static String faRank(List<Team> teams, Player p) {
    final above = teams.expand((t) => t.players).where((x) => !x.ikusei && !x.foreignSlot && x.id != p.id && x.salary > p.salary).length;
    if (above < rankA) return 'A';
    if (above < rankB) return 'B';
    return 'C';
  }

  /// 市場価値（FA の希望年俸の基準）。FA は高くなりやすい（×1.2〜1.5）
  static int marketValue(Player p, Random r) => ((estimateSalary(p) * performance(p) * (1.2 + r.nextDouble() * 0.3)) / 10).round() * 10;

  /// FA 宣言するか（力のある選手ほど、チームが弱い・信頼が低いほど宣言しやすい。残留要請で下がる）
  static double declareChance(Player p, double teamStrength) {
    if (!p.hasFA || p.ovr < 55) return 0;
    var c = 0.12 + (p.ovr - 60) * 0.02 + (0.5 - teamStrength) * 0.2 + (p.trust < 40 ? 0.15 : 0) - (p.trust > 70 ? 0.08 : 0);
    if (p.age >= 34) c *= 0.4;
    if (p.retainAsked) c *= 0.3;
    return c.clamp(0.0, 0.7);
  }

  /// FA 選手が条件を比べる点数。年俸×年数、元の球団の上乗せ、チームの強さ
  static double offerScore(FaCase f, String teamId, List<int> offer, double strength, Random r) {
    final years = offer[1].clamp(1, 5);
    var s = offer[0] * (1 + 0.08 * (years - 1));
    if (teamId == f.fromTeamId) s *= 1.1;
    s *= 0.9 + strength * 0.2;
    return s * (0.92 + r.nextDouble() * 0.16);
  }

  /// プロテクトから外れた選手（獲った球団の支配下。外国人・新人・育成は対象外。上位28人はプロテクト）
  static const protectCount = 31;

  /// 人的補償の対象になれる選手（支配下・日本人扱い・そのオフのドラフト・FA・新外国人で獲った選手以外）。draftYear はオフシーズンの年
  static List<Player> protectEligible(Team t, int draftYear) => t.players.where((p) => !p.ikusei && !p.foreignSlot && p.draftYear != draftYear && p.offJoin != draftYear).toList()
    ..sort((a, b) => RosterEngine.value(b).compareTo(RosterEngine.value(a)));

  /// 自動のプロテクト（価値の高い順に31人）
  static List<String> autoProtect(Team t, int draftYear) => protectEligible(t, draftYear).take(protectCount).map((p) => p.id).toList();

  /// プロテクトされていない選手。球団のプロテクトリスト（31人）があればそれを使い、なければ上位31人を自動で守る
  static List<Player> unprotected(Team t, int draftYear) {
    final elig = protectEligible(t, draftYear);
    final list = t.protectList.where((id) => elig.any((p) => p.id == id)).toSet();
    if (list.isEmpty) return elig.skip(protectCount).toList();
    return elig.where((p) => !list.contains(p.id)).toList();
  }

  // ───────── トレード ─────────

  /// トレードの評価。相手（CPU）が受けるかどうか。>=1.0 で成立
  ///  money：自球団が相手に払う金額（万円。マイナスは受け取る）
  /// トレードの釣り合い（1以上で相手が受ける）。eye は相手の監督の判断力（若手の将来性を見誤る度合い）
  ///  potential：相手監督の見る目（0=実績重視〜100=将来性重視）
  ///  mood：相手球団の今の事情（優勝争い中で目先の結果がほしい／下位で売り手に回る／探している役割）
  /// CPU 球団の方針（仕様書 9章-1）
  static const policyLabels = {'contend': '優勝を狙う', 'middle': '中間', 'rebuild': '再建中'};

  /// トレードできる指名権の巡（次のドラフトの2〜5位。1位は抽選のため、補償の1.5位・2.5位は対象外）
  static const tradableRounds = [2, 3, 4, 5];

  /// 指名権の価値（選手の tradeValue と同じ尺度）。再建中の球団は高く、優勝を狙う球団は低く見る
  static double pickValue(int round, {double winNow = 0}) {
    const base = {2: 110.0, 3: 70.0, 4: 45.0, 5: 30.0};
    return (base[round] ?? 20) * (1 - 0.45 * winNow).clamp(0.5, 1.6);
  }

  static double tradeRatio(Team partner, List<Player> give, List<Player> get, int money, {int eye = 55, int potential = 50, TradeMood mood = const TradeMood(), List<int> giveRounds = const [], List<int> getRounds = const []}) {
    double sum(List<Player> ps, {bool receiving = false}) {
      var s = 0.0;
      for (final p in ps) {
        var v = RosterEngine.styledTradeValue(p, eye: eye, potential: potential, viewer: partner.id);
        final w = mood.winNow;
        if (receiving) {
          // 穴のポジションは、優勝争い中ほど高く見る
          v *= 1 + RosterEngine.need(partner, p.mainPosition) * (0.3 + 0.5 * max(0.0, w));
          if (w > 0 && p.age >= 29 && p.ovr >= 62) v *= 1 + 0.35 * w; // 即戦力のベテラン
          if (w > 0 && p.age <= 24) v *= 1 - 0.2 * w; // 将来の選手はいま要らない
          if (w < 0 && p.age <= 25) v *= 1 - 0.3 * w; // 売り手は若手がほしい
          if (w < 0 && p.age >= 30) v *= 1 + 0.4 * w;
          v *= mood.roleBonus(p); // 探している役割（右の代打・左の代打・左のリリーフ）
        } else {
          v *= trustFactor(p); // 監督への信頼が低い選手は手放しやすい
          if (w < 0 && p.age >= 30) v *= 1 + 0.4 * w; // 売り手はベテランを安く手放す
          if (w < 0 && p.age <= 24) v *= 1 - 0.3 * w; // 若手は手放したくない
          if (w > 0 && partner.lineup.any((l) => l.playerId == p.id || partner.rotation.contains(p.id))) v *= 1 + 0.2 * w; // 優勝争い中は主力を出したくない
        }
        s += v;
      }
      return s;
    }

    final picksIn = giveRounds.fold<double>(0, (a, r) => a + pickValue(r, winNow: mood.winNow));
    final picksOut = getRounds.fold<double>(0, (a, r) => a + pickValue(r, winNow: mood.winNow));
    final players = sum(give, receiving: true) + picksIn;
    // 金銭は、選手・指名権の価値の半分までしか効かない（お金だけで主力を買い占められないように）
    final cash = money / 400.0; // 1億円 ≒ 主力の1/10 ほど
    final recv = players + (cash > 0 ? min(cash, max(players, 30.0) * 0.5) : cash);
    final lose = sum(get) * 1.05 + picksOut * 1.05 + 1; // 相手は少し得をしないと受けない
    return recv / lose;
  }

  /// 成立の確率（釣り合い 0.6 で 0%、0.85 で 50%、1.0 で 80%、1.1 以上で 100%）
  static double tradeChance(double ratio) => ((ratio - 0.6) / 0.5).clamp(0.0, 1.0);

  /// 相手球団が自分の選手を手放すときの価値の割引：監督への信頼が低いほど安く見る（50以上は ×1.0、35で ×0.87、20で ×0.73、1で ×0.56）
  static double trustFactor(Player p) => p.trust >= 50 ? 1.0 : 0.55 + p.trust * 0.009;

  static String tradeVerdict(double ratio) => ratio >= 1.1
      ? '確実に成立'
      : ratio >= 1.0
      ? '成立します'
      : ratio >= 0.85
          ? 'もう一押し'
          : ratio >= 0.6
              ? '釣り合いません'
              : '話になりません';

  // ───────── ポスティング・海外FA・提携枠（仕様書 3章。数値は仮）─────────

  /// 架空の大リーグ球団
  static const mlbTeams = ['ベイシティ・ハーバーズ', 'レイクサイド・ノーザンズ', 'サンバレー・コメッツ', 'ゴールドコースト・マリナーズ', 'リバータウン・パイオニアーズ', 'ハイランド・ローバーズ', 'デザート・サンダーズ', 'イーストポート・クリッパーズ', 'メトロ・ナイツ', 'プレーリー・ブルズ'];

  /// 大リーグが関心を持つ力（日本人選手の価値）
  static bool mlbClass(Player p) => !p.ikusei && p.nationality != '海外' && !p.isPartner && p.ovr >= 72 && p.age <= 33;

  /// 海外FA を宣言するか（海外FA 権＝在籍9年。力・向上心が高いほど）
  static double overseasFaChance(Player p) => !mlbClass(p) || p.faService < Player.overseasFaYears ? 0 : (0.12 + (p.ovr - 72) * 0.04 + (p.ambition - 50) * 0.004).clamp(0.0, 0.7);

  /// ポスティングを希望するか（プロ6年目以上・31歳以下・海外FA 権の前）
  static double postingChance(Player p) => !mlbClass(p) || p.proYears < 6 || p.age > 31 || p.faService >= Player.overseasFaYears ? 0 : (0.06 + (p.ovr - 72) * 0.03 + (p.ambition - 50) * 0.003).clamp(0.0, 0.5);

  /// 大リーグの球団と契約できるか
  static double mlbSignChance(Player p) => (0.35 + (p.ovr - 72) * 0.07).clamp(0.1, 0.95);

  /// ポスティングの譲渡金（万円）
  static int postingFee(Player p) => (pow(max(5, p.ovr - 60).toDouble(), 1.8) * 1000 / 100).round() * 100;

  /// CPU 球団がポスティングを認めるか：再建中は認めやすく、優勝を狙う球団は認めにくい（主力ほど認めない）
  static double postingAllowChance(String policy, Player p) {
    final base = switch (policy) { 'rebuild' => 0.8, 'contend' => 0.25, _ => 0.5 };
    return (base - (p.ovr - 75) * 0.02).clamp(0.05, 0.95);
  }

  /// 提携選手が申し出を受けるか：出場機会（その位置の層の薄さ）と期間（短いほど受けやすい）
  static double partnerAcceptChance(Team t, Player p, int years) => (0.45 + RosterEngine.need(t, p.mainPosition) * 0.4 + (5 - years) * 0.08).clamp(0.1, 0.95);

  // ───────── 現役ドラフト（仕様書 5章）─────────

  /// 現役ドラフトの対象（自動）：支配下・日本人扱い・プロ3年目以上・31歳以下・FA 権なし・年俸5000万円未満・
  ///  今季の1軍出場が少ない（野手30試合未満・投手15登板未満）・そのオフに入った選手でない。育成選手は対象外（条件は仮）
  static bool activeDraftEligible(Player p, int offYear) =>
      !p.ikusei && !p.foreignSlot && !p.hasFA && p.proYears >= 3 && p.age <= 31 && p.salary < 5000 && p.offJoin != offYear && p.draftYear != offYear &&
      (p.isPitcher ? p.seasonStats.apps < 15 : p.seasonStats.games < 30);

  /// 現役ドラフトを行う：order（指名の順。最初の球団から）で、各球団が1人ずつ指名する。
  ///  選手を指名された球団が次に指名する（すでに指名した球団なら、まだの球団を順に）。各球団から指名されるのは1人まで。
  ///  pick(球団, 候補) で選ぶ（null なら指名なし）。戻り値は [元の球団, 行き先, 選手]
  static List<(Team, Team, Player)> runActiveDraft(List<Team> order, int offYear, Player? Function(Team t, List<Player> cands) pick) {
    final picked = <String>{}, lost = <String>{};
    final moves = <(Team, Team, Player)>[];
    var cur = order.isEmpty ? null : order.first;
    var guard = 0;
    while (cur != null && guard++ < order.length * 2) {
      final me = cur;
      picked.add(me.id);
      final cands = [
        for (final t in order)
          if (t.id != me.id && !lost.contains(t.id))
            for (final p in t.players)
              if (activeDraftEligible(p, offYear) && !moves.any((m) => m.$3.id == p.id)) p,
      ];
      final p = cands.isEmpty ? null : pick(me, cands);
      Team? next;
      if (p != null) {
        final from = order.firstWhere((t) => t.players.contains(p));
        lost.add(from.id);
        moves.add((from, me, p));
        if (!picked.contains(from.id)) next = from;
      }
      next ??= order.where((t) => !picked.contains(t.id)).firstOrNull;
      cur = next;
    }
    return moves;
  }

  // ───────── 外国人選手 ─────────


  /// 海外の選手の一覧（支配下120人・育成60人。ForeignEngine を参照）
  static List<Player> foreignMarket(int year, Random r) => ForeignEngine.market(year, r);
}

/// 相手球団の今の事情（トレードの判断に使う）
class TradeMood {
  /// 目先の結果がほしい度合い：+1 優勝争いで全力の買い手 〜 0 ふつう 〜 −1 下位で売り手
  final double winNow;
  /// 探している役割：'rhPH' 右の代打、'lhPH' 左の代打、'lhRP' 左のリリーフ
  final Set<String> roles;
  const TradeMood({this.winNow = 0, this.roles = const {}});

  /// 探している役割に合う選手の上乗せ
  double roleBonus(Player p) {
    if (roles.isEmpty) return 1.0;
    if (!p.isPitcher && p.clutch >= 68) {
      if (roles.contains('rhPH') && (p.bats == 'R' || p.bats == 'S')) return 1.3;
      if (roles.contains('lhPH') && (p.bats == 'L' || p.bats == 'S')) return 1.3;
    }
    if (p.isPitcher && p.throws == 'L' && p.stamina < 65 && roles.contains('lhRP')) return 1.3;
    return 1.0;
  }

  static const roleLabels = {'rhPH': '右の代打', 'lhPH': '左の代打', 'lhRP': '左のリリーフ'};

  /// 画面に出す説明
  String text() {
    final r = roles.map((x) => roleLabels[x]).join('・');
    final head = winNow >= 0.6
        ? '優勝争い中：目先の結果がほしい。即戦力のベテランや穴のポジションの選手を高く評価し、主力は出したがらない'
        : (winNow >= 0.25 ? 'Aクラス争い中：即戦力をやや高く評価' : (winNow <= -0.4 ? '下位に沈み売り手：ベテランを安く手放し、若手をほしがる' : '特に急いでいない'));
    return r.isEmpty ? head : '$head。$rを探している';
  }
}
