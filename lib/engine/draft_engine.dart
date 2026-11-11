import 'dart:math';
import 'velo.dart';
import 'pitch_catalog.dart';
import 'fielding_gen.dart';
import '../models/player.dart';
import '../models/prospect.dart';
import '../models/team.dart';
import '../utils/player_traits.dart';
import '../utils/name_pool.dart';
import 'roster_engine.dart';

/// ドラフト候補の生成・スカウトの調査・CPU の評価・ドラフト会議の進行
class DraftEngine {
  static const mainCount = 120; // 本指名の候補（§14 の目安）
  static const ikuseiCount = 110; // 育成の候補（CPU 球団は育成20人前後を保つので多めに）

  static const _places = ['北斗', '青葉', '白峰', '桜丘', '東陵', '西海', '南風', '緑ヶ丘', '旭', '若竹', '明星', '清流', '光陽', '翔洋', '大和', '富岳', '湖南', '鳴門', '飛鳥', '黎明'];
  static const _corp = ['重工', '製鉄', 'ガス', '電機', '自動車', '鉄道', '通運', '生命', '化学', '製紙'];
  // 独立リーグの球団名（プロ球団に見えない名前。以前の名前は indepRename で置き換える）
  static const _indep = ['ブルーリバーズ', 'サンライズ', 'ステラーズ', 'オウルズ', 'シーガルズ', 'レッドフォックス'];
  static const indepRename = {'ブルーウェーブス': 'ブルーリバーズ', 'スターズ': 'ステラーズ', 'ホークアイズ': 'オウルズ', 'マリーンズ': 'シーガルズ', 'レッドウィングス': 'レッドフォックス'};
  static String renameIndep(String s) {
    var out = s;
    // 以前の名前は「地名（漢字）＋名前」。カタカナが前に付くもの（他リーグの「ブルースターズ」など）は別の球団なので変えない
    indepRename.forEach((a, b) => out = out.replaceAll(RegExp('(?<![ァ-ヶー])$a'), b));
    // 以前の置き換えで誤って変わった他リーグの球団名（ブルーステラーズ → ブルースターズ）を戻す
    out = out.replaceAll(RegExp('(?<=[ァ-ヶー])ステラーズ'), 'スターズ');
    return out;
  }

  static double _g(Random r) {
    final u1 = 1.0 - r.nextDouble();
    final u2 = r.nextDouble();
    return sqrt(-2.0 * log(u1)) * cos(2.0 * pi * u2);
  }

  static int _s(Random r, double mean, double sd, {int lo = 15, int hi = 92}) => (mean + _g(r) * sd).round().clamp(lo, hi);

  // ───────── 生成 ─────────

  /// その年のドラフト候補（本指名 120人＋育成 60人）を作る
  static List<Prospect> generate(int year, Random r) {
    final out = <Prospect>[];
    var n = 0;
    // 本指名：高校40・大学45・社会人25・独立10。上位ほど目玉
    final mainCats = [...List.filled(40, '高校'), ...List.filled(45, '大学'), ...List.filled(25, '社会人'), ...List.filled(10, '独立')]..shuffle(r);
    for (var i = 0; i < mainCount; i++) {
      final tier = i < 12 ? 2 : (i < 40 ? 1 : 0); // 目玉12人・上位28人・その他
      out.add(_make(r, year, 'D${year}_${n++}', mainCats[i], tier: tier, ikusei: false));
    }
    // 二刀流の候補：数年に一度（3割ほどの年に1人）。上位の高校・大学の野手を、投手としても力のある選手にする
    if (r.nextDouble() < 0.3) {
      final c = out.where((x) => !x.player.isPitcher && x.category != '独立' && x.category != '社会人').take(40).toList();
      if (c.isNotEmpty) makeTwoWay(c[r.nextInt(c.length)].player, r);
    }
    final ikCats = [...List.filled(45, '高校'), ...List.filled(30, '大学'), ...List.filled(35, '独立')]..shuffle(r);
    for (var i = 0; i < ikuseiCount; i++) {
      out.add(_make(r, year, 'D${year}_${n++}', ikCats[i], tier: -1, ikusei: true));
    }
    return out;
  }

  /// 野手を二刀流にする（投手の能力・持ち球・投手適性を足す）
  static void makeTwoWay(Player p, Random r) {
    final base = p.ovr.toDouble();
    p.twoWay = true;
    p.velocity = Velo.lift((138 + r.nextInt(15)).clamp(130, 160), amateur: true, slot: p.armSlot);
    p.pitchPower = _s(r, base + 2, 6);
    p.control = _s(r, base - 3, 7);
    p.stamina = _s(r, base, 8);
    p.clutchPitching = _s(r, 55, 10);
    p.fieldP = _s(r, base, 6, lo: 45, hi: 85);
    p.pitches = PitchCatalog.generate(p, r, starter: true);
    p.talent = max(p.talent, 70 + r.nextInt(20)); // 二刀流は才能のある選手
  }

  /// アマチュア（独立リーグなど）の選手を1人作る（他リーグの日本独立リーグにも使う）
  /// 力の段階（2 目玉・1 上位・0 中位・-1 育成級）を決めて1人作る。支配下・育成は分けない（育成級も一覧は同じ）
  static Prospect makeTier(Random r, int year, String id, String cat, int tier) => _make(r, year, id, cat, tier: tier, ikusei: tier < 0)..ikuseiTier = false;

  static Prospect makeAmateur(Random r, int year, String id, String cat, {int tier = 0}) => _make(r, year, id, cat, tier: tier, ikusei: false);

  static Prospect _make(Random r, int year, String id, String cat, {required int tier, required bool ikusei}) {
    final isPitcher = r.nextDouble() < 0.48;
    final pos = isPitcher ? '投手' : RosterEngine.posNames[r.nextInt(8)];
    final age = switch (cat) { '高校' => 18, '大学' => 22, '社会人' => 23 + r.nextInt(4), _ => 20 + r.nextInt(6) };
    // 今の力と伸びしろ（OVR換算）
    var mean = switch (cat) { '高校' => 41.0, '大学' => 49.0, '社会人' => 53.0, _ => 47.0 };
    var room = switch (cat) { '高校' => 20.0, '大学' => 12.0, '社会人' => 6.0, _ => 8.0 };
    if (tier == 2) { mean += 8; room += 6; }
    if (tier == 1) { mean += 4; room += 3; }
    if (tier == -1) { mean -= 7; room -= 2; }
    mean += _g(r) * 3;
    room = max(2, room + _g(r) * 4);

    final first = NamePool.jpFirst(r);
    final last = NamePool.jpLast(r);
    final bats = ['R', 'R', 'R', 'L', 'L', 'S'][r.nextInt(6)];
    Player p;
    if (isPitcher) {
      final vn = _s(r, mean + 2, 7);
      final speed = 120 + vn ~/ 2;
      p = Player(
        id: id, isPitcher: true, firstName: first, lastName: last, mainPos: '投手', age: age,
        bats: bats, throws: r.nextInt(4) == 0 ? 'L' : 'R', height: 172 + r.nextInt(22), trajectory: 1,
        contactLeft: _s(r, 28, 6), contactRight: _s(r, 28, 6), power: _s(r, 28, 6), run: _s(r, 40, 8),
        arm: _s(r, 58, 8), throwAccuracy: _s(r, 55, 8), catchSkill: _s(r, 55, 8), eye: _s(r, 28, 6), clutch: _s(r, 55, 10),
        fieldP: 60, fieldC: 30, field1B: 30, field2B: 30, field3B: 30, fieldSS: 30, fieldLF: 30, fieldCF: 30, fieldRF: 30,
        velocity: speed, pitchPower: _s(r, mean, 7), control: _s(r, mean, 7), stamina: _s(r, mean, 8), clutchPitching: _s(r, 55, 10),
      );
      Velo.liftNew(p, amateur: true); // アマチュアの水準（プロ入りの高校生で140km台前半）
      p.pitches = PitchCatalog.generate(p, r, starter: p.stamina >= mean);
      _applyFielding(p, r);
    } else {
      final c = _s(r, mean, 7);
      final fieldMain = _s(r, mean + 4, 8, lo: 30, hi: 90);
      int f(String name) => pos == name ? fieldMain : _s(r, 40, 8, lo: 20, hi: 70);
      p = Player(
        id: id, isPitcher: false, firstName: first, lastName: last, mainPos: pos, age: age,
        bats: bats, throws: bats == 'L' && r.nextBool() ? 'L' : 'R', height: 168 + r.nextInt(22), trajectory: [1, 2, 2, 2, 3, 3, 4][r.nextInt(7)],
        contactLeft: (c + _g(r) * 3).round().clamp(15, 92), contactRight: (c + _g(r) * 3).round().clamp(15, 92),
        power: _s(r, mean, 9), run: _s(r, mean + 2, 9), arm: _s(r, mean + 2, 8), throwAccuracy: _s(r, mean, 8), catchSkill: _s(r, mean, 8),
        eye: _s(r, mean + 5, 8), clutch: _s(r, 55, 10),
        fieldP: 20, fieldC: f('捕手'), field1B: max(f('一塁手'), 45), field2B: f('二塁手'), field3B: f('三塁手'), fieldSS: f('遊撃手'),
        fieldLF: max(f('左翼手'), 40), fieldCF: f('中堅手'), fieldRF: max(f('右翼手'), 40),
        velocity: 130, pitchPower: 20, control: 20, stamina: 20,
      );
      _applyFielding(p, r);
    }
    assignTraits(p, r);
    p.birthplace = NamePool.prefecture(r);
    fixBirthDate(p, year);
    p.quick = (p.quick + 10).clamp(1, 99); // クイックは平均60
    p.proYears = 1;
    p.faService = 0;
    p.uniformNumber = 0;
    p.draftType = cat == '高校' ? 'A' : 'B';
    // 才能・向上心（隠し。スカウトが見抜く）。上位の評価の候補ほど才能が高め。高校生はばらつきが大きい
    final tMean = 50.0 + (tier == 2 ? 14 : (tier == 1 ? 7 : (tier == -1 ? -6 : 0))) + (room - 10) * 0.6;
    p.talent = (tMean + _g(r) * (cat == '高校' ? 16 : 12)).round().clamp(1, 100);
    p.ambition = (50 + _g(r) * 17).round().clamp(1, 100);
    final school = switch (cat) {
      '高校' => '${_places[r.nextInt(_places.length)]}高',
      '大学' => '${_places[r.nextInt(_places.length)]}大',
      '社会人' => '${_places[r.nextInt(_places.length)]}${_corp[r.nextInt(_corp.length)]}',
      _ => '${_places[r.nextInt(_places.length)]}${_indep[r.nextInt(_indep.length)]}',
    };
    return Prospect(player: p, year: year, category: cat, school: school, ikuseiTier: ikusei, curBias: r.nextInt(9) - 4, memo: amateurRecord(p, cat, school, r));
  }

  /// 守備適性をランダムに（本職は平均60）
  static void _applyFielding(Player p, Random r) {
    final f = FieldingGen.generate(p.mainPosition, r);
    p.fieldP = f['投手']!;
    p.fieldC = f['捕手']!;
    p.field1B = f['一塁手']!;
    p.field2B = f['二塁手']!;
    p.field3B = f['三塁手']!;
    p.fieldSS = f['遊撃手']!;
    p.fieldLF = f['左翼手']!;
    p.fieldCF = f['中堅手']!;
    p.fieldRF = f['右翼手']!;
    FieldingGen.blendSkill(p);
  }

  // ───────── スカウト ─────────

  /// スカウト眼力による、才能・向上心の見立ての幅（±）。眼力 D50 で ±20、S100 で ±5（50未満はさらに広い）
  static int traitError(int eye) => (20 - (eye - 50) * 0.3).round().clamp(5, 30);

  /// スカウトの調査1回。才能・向上心を眼力に応じた幅で見立てる（調べるほど少し正確になる）
  static void scout(Prospect pr, int eye, Random r) {
    pr.reports++;
    final pl = pr.player;
    final err = (traitError(eye) * max(0.7, 1.0 - (pr.reports - 1) * 0.1)).round();
    // 見立ての中心のずれ（候補ごとに固定）。本当の値は必ず幅の中に入る
    double bias(int salt) => (Random(pl.id.hashCode ^ salt).nextDouble() * 2 - 1) * 0.8;
    (int, int) range(int v, int salt) {
      final c = v + bias(salt) * err;
      return ((c - err).round().clamp(1, 100), (c + err).round().clamp(1, 100));
    }
    final (tl, th) = range(pl.talent, 0x51);
    final (al, ah) = range(pl.ambition, 0x52);
    pr.talentLo = tl; pr.talentHi = th;
    pr.ambitionLo = al; pr.ambitionHi = ah;
    final tMid = (tl + th) / 2, aMid = (al + ah) / 2;
    final cur = pl.ovr + pr.curBias;
    pr.comment = cur >= 57
        ? (tMid >= 65 ? '即戦力で、まだ伸びる' : '即戦力。1年目から1軍で使える')
        : tMid >= 75
            ? '未完の大器。将来の主軸になれる素材'
            : tMid >= 62
                ? (aMid >= 60 ? '練習熱心。数年後のレギュラー候補' : '素質は高いが、伸びるかは本人しだい')
                : aMid >= 65
                    ? '向上心が強く、堅実に伸びる'
                    : '伸びしろは小さい';
  }

  /// 架空のアマチュア成績（スカウトメモに載せる）。能力から作り、ばらつきを入れる
  static List<String> amateurRecord(Player p, String cat, String school, Random r) {
    final out = <String>[];
    String avg(double v) => v.toStringAsFixed(3).replaceFirst(RegExp(r'^0'), '');
    String bat(int games, double scale) {
      final ab = (games * (3.4 + r.nextDouble() * 0.6)).round();
      final a = (0.20 + (p.contact - 30) * 0.0045 + _g(r) * 0.03) * scale;
      final hr = max(0, (ab * (p.power - 25) * 0.0011 * scale + _g(r) * 1.2).round());
      final rbi = max(hr, (ab * (0.10 + p.power * 0.0015) + _g(r) * 2).round());
      final sb = max(0, (games * (p.run - 45) * 0.006 + _g(r)).round());
      return '$games試合 打率${avg(a.clamp(0.150, 0.600))} ${hr}本 ${rbi}打点 ${sb}盗塁';
    }
    String pit(int games, double scale) {
      final ip = games * (3.5 + r.nextDouble() * 4) * (p.stamina / 60);
      final era = ((5.5 - (p.pitchPower + p.control - 80) * 0.035) / scale + _g(r) * 0.5).clamp(0.20, 7.0);
      final k = (ip * (0.6 + (p.velocity - 135) * 0.02 + _g(r) * 0.1)).round().clamp(0, 999);
      final w = (games * (0.25 + r.nextDouble() * 0.3) * scale).round();
      return '$games登板 ${w}勝 防御率${era.toStringAsFixed(2)} ${ip.round()}回 ${k}奪三振';
    }
    String line(int games, double scale) => p.isPitcher ? pit(games, scale) : bat(games, scale);
    final velo = p.isPitcher ? '　最速${p.velocity + r.nextInt(3)}km' : '';
    switch (cat) {
      case '高校':
        out.add('3年夏 地方大会：${line(4 + r.nextInt(4), 1.25)}$velo');
        if (r.nextDouble() < 0.35 + (p.ovr - 40) * 0.02) {
          final w = 1 + r.nextInt(4);
          out.add('甲子園（${r.nextBool() ? '春' : '夏'}）：${w >= 4 ? 'ベスト4以上' : '$w回戦'}　${line(w, 1.0)}');
        } else {
          out.add('甲子園：出場なし');
        }
      case '大学':
        out.add('大学リーグ通算：${line(40 + r.nextInt(30), 1.1)}$velo');
        if (r.nextDouble() < 0.4) out.add('大学日本代表に選出');
      case '社会人':
        out.add('社会人2年間：${line(30 + r.nextInt(20), 1.05)}$velo');
        out.add(r.nextDouble() < 0.5 ? '都市対抗：${line(2 + r.nextInt(3), 1.0)}' : '都市対抗：出場なし');
      default:
        out.add('独立リーグ（$school）：${line(50 + r.nextInt(30), 1.0)}$velo');
    }
    return out;
  }

  /// 画面に出す「今の能力」の幅（実際の値±5。見立てのずれを含む）
  static (int, int) curRange(Prospect pr, [int? value]) {
    final v = (value ?? pr.player.ovr) + pr.curBias;
    return ((v - 5).clamp(1, 99), (v + 5).clamp(1, 99));
  }

  // ───────── CPU の評価 ─────────

  /// CPU 球団の評価。今の力45%・将来の見込み55%に、眼力による揺らぎと、チームに足りない位置の加点
  static double cpuScore(Prospect pr, Team t, int eye, Random r) {
    final cur = pr.player.ovr.toDouble();
    final pot = RosterEngine.potentialOvr(pr.player).toDouble();
    final sd = (100 - eye) / 10.0 + 3.0; // 眼力による揺らぎ＋球団ごとの好み（1位の入札が1人に集中しすぎないように）
    return cur * 0.45 + pot * 0.55 + _g(r) * sd + RosterEngine.need(t, pr.player.mainPosition) * 6;
  }

  // ───────── 契約金・年俸 ─────────

  /// 契約金（万円）。1位は1億円＋出来高5000万円（出来高は記録のみ）
  static int signingBonus(int round, bool ikusei) {
    if (ikusei) return 300; // 支度金
    return const {1: 10000, 2: 7000, 3: 5000, 4: 4000, 5: 3000}[round] ?? 2500;
  }

  /// 新人の年俸（万円。上限 1600万）
  static int rookieSalary(int round, bool ikusei) {
    if (ikusei) return 400;
    return const {1: 1600, 2: 1200, 3: 1000, 4: 900, 5: 800}[round] ?? 700;
  }
}

/// 指名1人分
class DraftPick {
  final int round;
  final String teamId;
  final Prospect prospect;
  final bool ikusei;
  final bool lottery; // 1位の抽選で引き当てた
  final bool comp;    // 補償の巡（round 1 → 1.5位、round 2 → 2.5位）
  DraftPick(this.round, this.teamId, this.prospect, {this.ikusei = false, this.lottery = false, this.comp = false});

  /// 「1位」「1.5位」「育成3位」など
  String get label => '${ikusei ? '育成' : ''}${comp ? '$round.5' : '$round'}位';
  /// 契約金・年俸の目安にする巡（1.5位は2位、2.5位は3位の扱い）
  int get payRound => comp ? round + 1 : round;
}

/// 補償の巡（1.5位・2.5位）の入札の結果1件：球団ごとの枠（くじの本数）と当たった球団
class CompLot {
  final Prospect prospect;
  final Map<String, int> tickets;
  final String winner;
  CompLot(this.prospect, this.tickets, this.winner);
}

/// 1位入札の結果1件（重複したら抽選）
class LotteryEntry {
  final Prospect prospect;
  final List<String> bidders;
  final String winner;
  LotteryEntry(this.prospect, this.bidders, this.winner);
}

/// ドラフト会議の進行
///  1位：全球団が同時に入札、重複は抽選、外れた球団は再入札
///  2位以降：ウェーバー（2巡目は下位から、3巡目は逆順…）。各球団は「選択終了」できる
///  本指名のあと育成ドラフト（1巡目は下位から、2巡目は上位から…の折り返し）
///  補償の巡（仕様書 2.3）：1位のあとに1.5位、2位のあとに2.5位。FA で A・B ランクの選手を失った球団が、流出1人につき1枠で
///   全球団が同時に入札する。1枠＝くじ1本。同じ選手に枠を重ねてよく、当たればその選手1人で重ねた枠はすべて使い切る。
///   外れた枠は残り、再入札できる
class DraftSession {
  final int year;
  final List<Team> teams;
  final List<String> waiver; // 2巡目の指名順（下位から、リーグ交互）
  final String myId;
  final List<Prospect> pool;
  final Random r;
  final Map<String, int> eyes; // 球団ごとのスカウト眼力
  final Map<String, int> slots = {}; // 本指名できる残り人数（支配下の空き）
  final Map<String, int> plan = {}; // CPU の本指名予定数
  final Map<String, int> ikuseiPlan = {};
  final Map<String, Map<String, double>> _scores = {};
  final List<DraftPick> picks = [];
  final List<List<LotteryEntry>> lotteries = [];
  final Set<String> doneMain = {};
  final Set<String> doneIkusei = {};
  List<String> firstPending = [];
  String stage = 'first'; // first / comp（1.5位・2.5位）/ main / ikusei / done
  /// 補償の巡の枠（球団 ID → 枠の数）
  final Map<String, int> comp15, comp25;
  /// トレードで動いた指名権：'巡|元の球団' → 持ち主（本指名の2〜5位）
  final Map<String, String> pickOwner;
  String _owner(int rd, String orig) => stage == 'main' ? (pickOwner['$rd|$orig'] ?? orig) : orig;
  /// いまの補償の巡（1 → 1.5位、2 → 2.5位）と、各球団の残りの枠
  int compRound = 0;
  final Map<String, int> compLeft = {};
  bool _comp25Done = false;
  /// 補償の巡の入札の結果（1回ごと）
  final List<List<CompLot>> compLots = [];
  int round = 1;
  int cursor = 0;
  static const maxMainRound = 10;
  static const maxIkuseiRound = 12;
  static const ikuseiLimit = 40;
  /// CPU 球団の育成の目標人数（球団 ID → 人数）。無ければ20人
  final Map<String, int> ikuseiTargets;
  /// 球団ごとの育成選手の上限（仕様書 6.2）
  final Map<String, int> ikuseiCaps;
  int _ikTarget(String id) => min(ikuseiLimit, ikuseiTargets[id] ?? 20);

  DraftSession({required this.year, required this.teams, required this.waiver, required this.myId, required List<Prospect> candidates, required this.eyes, this.ikuseiTargets = const {}, this.comp15 = const {}, this.comp25 = const {}, this.pickOwner = const {}, this.ikuseiCaps = const {}, Random? rnd})
      : pool = List.of(candidates),
        r = rnd ?? Random() {
    for (final c in candidates) {
      fixBirthDate(c.player, year);
    }
    for (final t in teams) {
      slots[t.id] = RosterEngine.freeSlots(t);
      plan[t.id] = min(RosterEngine.cpuRoom(t), 4 + r.nextInt(4)); // CPU は支配下63人まで
      // 育成：目標人数に足りない分（1回のドラフトで最大12人）。足りていても1人くらいは獲ることがある
      ikuseiPlan[t.id] = min(12, max(0, _ikTarget(t.id) - RosterEngine.ikuseiCount(t)) + r.nextInt(2));
      if (RosterEngine.ikuseiCount(t) >= (ikuseiCaps[t.id] ?? 999)) doneIkusei.add(t.id); // 上限に達している
      if (slots[t.id]! <= 0) doneMain.add(t.id);
    }
    firstPending = [for (final t in teams) if (!doneMain.contains(t.id)) t.id];
    if (firstPending.isEmpty) _toMain();
  }

  Team teamOf(String id) => teams.firstWhere((t) => t.id == id);

  /// その球団が知っている候補か（スカウトが発掘・調査した選手だけを指名できる）
  bool knows(String teamId, Prospect p) => p.knownTo(teamId);

  double score(String teamId, Prospect p) {
    if (!knows(teamId, p)) return -1e9;
    final m = _scores.putIfAbsent(teamId, () => {});
    return m.putIfAbsent(p.id, () => DraftEngine.cpuScore(p, teamOf(teamId), eyes[teamId] ?? 55, r));
  }

  /// その球団（CPU の考え方）が最も欲しい候補
  Prospect? bestFor(String teamId, {bool ikusei = false}) {
    Prospect? best;
    var bs = -1e9;
    for (final p in pool) {
      if (!ikusei && p.ikuseiTier) continue;
      if (!knows(teamId, p)) continue;
      final s = score(teamId, p);
      if (s > bs) {
        bs = s;
        best = p;
      }
    }
    return best;
  }

  /// 2番目に欲しい候補
  Prospect? secondFor(String teamId) {
    final l = pool.where((p) => !p.ikuseiTier && knows(teamId, p)).toList()..sort((a, b) => score(teamId, b).compareTo(score(teamId, a)));
    return l.length > 1 ? l[1] : null;
  }

  List<DraftPick> picksOf(String teamId) => picks.where((p) => p.teamId == teamId).toList();
  bool get myTurn => currentTeamId == myId;
  bool get myFirstPending => stage == 'first' && firstPending.contains(myId);

  /// 1位入札（自球団の入札 myBid。自球団が入札済み・不参加なら null）。抽選の結果を返す
  List<LotteryEntry> bidFirst(Prospect? myBid) {
    final bids = <String, List<String>>{};
    final byId = {for (final p in pool) p.id: p};
    for (final tid in List.of(firstPending)) {
      Prospect? b;
      if (tid == myId) {
        b = myBid;
        if (b == null) {
          firstPending.remove(tid);
          doneMain.add(tid);
          continue;
        }
      } else {
        b = bestFor(tid);
        // 最初の入札では、競合を避けて2番手に入札する球団もある
        if (lotteries.isEmpty && b != null && r.nextDouble() < 0.35) b = secondFor(tid) ?? b;
      }
      if (b == null) {
        firstPending.remove(tid);
        doneMain.add(tid);
        continue;
      }
      bids.putIfAbsent(b.id, () => []).add(tid);
    }
    final entries = <LotteryEntry>[];
    bids.forEach((pid, bidders) {
      final winner = bidders[r.nextInt(bidders.length)];
      final p = byId[pid]!;
      entries.add(LotteryEntry(p, bidders, winner));
      _take(winner, p, round: 1, lottery: bidders.length > 1);
      firstPending.remove(winner);
    });
    lotteries.add(entries);
    if (firstPending.isEmpty) _toMain();
    return entries;
  }

  void _take(String teamId, Prospect p, {required int round, bool lottery = false, bool ikusei = false, bool comp = false}) {
    pool.remove(p);
    picks.add(DraftPick(round, teamId, p, ikusei: ikusei, lottery: lottery, comp: comp));
    if (!ikusei) {
      slots[teamId] = (slots[teamId] ?? 0) - 1;
      if (slots[teamId]! <= 0) doneMain.add(teamId);
    }
  }

  void _toMain() {
    if (_startComp(1)) return;
    stage = 'main';
    round = 2;
    cursor = 0;
    _normalize();
  }

  /// 補償の巡を始める（枠を持つ球団がなければ false）
  bool _startComp(int rd) {
    final src = rd == 1 ? comp15 : comp25;
    compLeft.clear();
    src.forEach((id, n) {
      if (n > 0 && !doneMain.contains(id) && (slots[id] ?? 0) > 0) compLeft[id] = n;
    });
    if (compLeft.isEmpty || pool.where((p) => !p.ikuseiTier).isEmpty) return false;
    stage = 'comp';
    compRound = rd;
    return true;
  }

  /// 補償の巡を終えて、本指名の続きへ
  void _endComp() {
    compLeft.clear();
    stage = 'main';
    if (compRound == 1) {
      round = 2;
    } else {
      _comp25Done = true;
      round = 3;
    }
    cursor = 0;
    _normalize();
  }

  /// 自球団が補償の巡の入札を待っているか
  bool get myCompPending => stage == 'comp' && (compLeft[myId] ?? 0) > 0;
  String get compLabel => compRound == 1 ? '1.5位' : '2.5位';

  /// CPU の補償の巡の入札：残りの枠を、欲しい順に別々の選手へ1枠ずつ
  Map<String, int> autoCompBids(String teamId) {
    final n = compLeft[teamId] ?? 0;
    final l = pool.where((p) => !p.ikuseiTier && knows(teamId, p)).toList()..sort((a, b) => score(teamId, b).compareTo(score(teamId, a)));
    return {for (final p in l.take(n)) p.id: 1};
  }

  /// 補償の巡の入札（myBids：自球団の 候補ID → 重ねる枠の数。null なら自球団は入札しない＝残りの枠を手放す）。
  ///  1枠＝くじ1本で抽選し、当たった球団はその選手を獲って重ねた枠を使い切る。外れた枠は残る
  List<CompLot> bidComp(Map<String, int>? myBids) {
    final bids = <String, Map<String, int>>{}; // 候補 → 球団 → 枠
    for (final tid in List.of(compLeft.keys)) {
      final Map<String, int> b;
      if (tid == myId) {
        if (myBids == null || myBids.isEmpty) {
          compLeft.remove(tid);
          continue;
        }
        b = myBids;
      } else {
        b = autoCompBids(tid);
      }
      var used = 0;
      b.forEach((pid, n) {
        final k = min(n, (compLeft[tid] ?? 0) - used);
        if (k <= 0) return;
        used += k;
        bids.putIfAbsent(pid, () => {})[tid] = k;
      });
      if (used == 0) compLeft.remove(tid);
    }
    final byId = {for (final p in pool) p.id: p};
    final lots = <CompLot>[];
    bids.forEach((pid, m) {
      final p = byId[pid];
      if (p == null) return;
      final total = m.values.fold<int>(0, (a, b) => a + b);
      var x = r.nextInt(total);
      var winner = m.keys.first;
      for (final e in m.entries) {
        if (x < e.value) {
          winner = e.key;
          break;
        }
        x -= e.value;
      }
      lots.add(CompLot(p, Map.of(m), winner));
      _take(winner, p, round: compRound, comp: true);
      compLeft[winner] = (compLeft[winner] ?? 0) - m[winner]!; // 重ねた枠は使い切る
    });
    compLots.add(lots);
    compLeft.removeWhere((id, n) => n <= 0 || doneMain.contains(id) || (slots[id] ?? 0) <= 0);
    if (compLeft.isEmpty || bids.isEmpty || pool.where((p) => !p.ikuseiTier).isEmpty) _endComp();
    return lots;
  }

  List<String> orderFor(int rd) {
    if (stage == 'ikusei') return rd.isOdd ? waiver : waiver.reversed.toList(); // 育成：1巡目は下位から、以降は折り返し
    return rd.isEven ? waiver : waiver.reversed.toList();
  }

  /// いま指名する球団（本指名・育成のとき）
  String? get currentTeamId {
    if (stage != 'main' && stage != 'ikusei') return null;
    final ord = orderFor(round);
    return cursor < ord.length ? _owner(round, ord[cursor]) : null;
  }

  void _normalize() {
    while (stage == 'main' || stage == 'ikusei') {
      final done = stage == 'main' ? doneMain : doneIkusei;
      final maxRound = stage == 'main' ? maxMainRound : maxIkuseiRound;
      final active = waiver.where((id) => !done.contains(id));
      if (active.isEmpty || round > maxRound || pool.isEmpty) {
        if (stage == 'main') {
          stage = 'ikusei';
          round = 1;
          cursor = 0;
          continue;
        }
        stage = 'done';
        return;
      }
      final ord = orderFor(round);
      if (cursor >= ord.length) {
        // 2位が終わったら 2.5位（補償の巡）
        if (stage == 'main' && round == 2 && !_comp25Done) {
          _comp25Done = true;
          if (_startComp(2)) return;
        }
        round++;
        cursor = 0;
        continue;
      }
      if (done.contains(_owner(round, ord[cursor]))) {
        cursor++;
        continue;
      }
      return;
    }
  }

  /// いまの球団が指名する
  void pick(Prospect p) {
    final tid = currentTeamId;
    if (tid == null) return;
    if (stage == 'ikusei') {
      _take(tid, p, round: round, ikusei: true);
      // 育成選手の上限まで（CPU 球団は目標人数＋1まで）
      final have = picks.where((x) => x.teamId == tid && x.ikusei).length + RosterEngine.ikuseiCount(teamOf(tid));
      final limit = min(ikuseiCaps[tid] ?? 999, tid == myId ? 999 : _ikTarget(tid) + 1);
      if (have >= limit) doneIkusei.add(tid);
    } else {
      _take(tid, p, round: round);
    }
    cursor++;
    _normalize();
  }

  /// いまの球団が選択を終える
  void pass() {
    final tid = currentTeamId;
    if (tid == null) return;
    (stage == 'main' ? doneMain : doneIkusei).add(tid);
    cursor++;
    _normalize();
  }

  /// CPU の考え方で、いまの球団の1手を決める
  void autoStep() {
    final tid = currentTeamId;
    if (tid == null) return;
    if (stage == 'main') {
      final n = picks.where((x) => x.teamId == tid && !x.ikusei).length;
      final want = tid == myId ? min(slots[tid]! + n, 6) : plan[tid]!;
      final b = bestFor(tid);
      if (n >= want || b == null) {
        pass();
      } else {
        pick(b);
      }
    } else {
      final n = picks.where((x) => x.teamId == tid && x.ikusei).length;
      final want = tid == myId ? 2 : ikuseiPlan[tid]!;
      final b = bestFor(tid, ikusei: true);
      if (n >= want || b == null) {
        pass();
      } else {
        pick(b);
      }
    }
  }

  /// 自球団の番が来るまで（または終わるまで）CPU の指名を進める
  void runUntilMine() {
    var guard = 0;
    while (guard++ < 3000) {
      if (stage == 'comp' && !myCompPending) {
        bidComp(null);
      } else if ((stage == 'main' || stage == 'ikusei') && currentTeamId != myId) {
        autoStep();
      } else {
        break;
      }
    }
  }

  /// 最後までおまかせで進める（自球団も CPU の考え方で指名）
  void runAll() {
    var guard = 0;
    while (stage != 'done' && guard++ < 5000) {
      if (stage == 'first') {
        bidFirst(firstPending.contains(myId) ? bestFor(myId) : null);
      } else if (stage == 'comp') {
        bidComp(myCompPending ? autoCompBids(myId) : null);
      } else {
        autoStep();
      }
    }
  }
}

/// 生年月日が初期値のまま（2000-01-01）なら、年齢に合うように決める（ドラフト会議の10月末に その年齢になる日）
void fixBirthDate(Player p, int year) {
  if (p.birthDate != '2000-01-01') return;
  final h = p.id.hashCode & 0x7fffffff;
  final m = 1 + h % 12, d = 1 + (h ~/ 12) % 28;
  final y = year - p.age - (m >= 11 ? 1 : 0);
  p.birthDate = '$y-${m.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
}
