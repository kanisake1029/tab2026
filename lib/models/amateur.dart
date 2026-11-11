import 'player.dart';

/// アマチュア球界の地区（秋季地区大会・大学リーグ・都市対抗の予選）
const amRegions = ['北海道', '東北', '関東', '中部', '北陸', '東海', '近畿', '中国・四国', '九州・沖縄'];

/// 都道府県の番号（NameData2.prefectures の順）→ 地区の番号
const amPrefRegion = [
  0, // 北海道
  1, 1, 1, 1, 1, 1, // 青森〜福島
  2, 2, 2, 2, 2, 2, 2, // 茨城〜神奈川
  3, // 新潟
  4, 4, 4, // 富山・石川・福井
  3, 3, // 山梨・長野
  5, 5, 5, 5, // 岐阜・静岡・愛知・三重
  6, 6, 6, 6, 6, 6, // 滋賀〜和歌山
  7, 7, 7, 7, 7, 7, 7, 7, 7, // 鳥取〜高知
  8, 8, 8, 8, 8, 8, 8, 8, // 福岡〜沖縄
];

/// 高校・大学・社会人の1チーム
class AmTeam {
  final String id;
  final String name;     // 「青葉商業高」「白峰学院大」「北斗重工」
  final String kind;     // 高校 / 大学 / 社会人
  final int pref;        // 都道府県の番号（大学・社会人は所在地）
  final int region;      // 地区の番号（amRegions）
  int strength;          // 今年の強さ（1〜99）
  int prestige;          // 名門度（強さが戻っていく先。1〜99）
  int w, l, d;           // 今年の勝敗（大会・リーグ）
  /// NPB 球団とのパイプ（球団 id → 強さ。指名すると強まり、年ごとに弱まる）
  Map<String, double> pipe;
  /// 過去の年度の記録（画面には出さない）「2026 夏 甲子園 ベスト8」「2026 リーグ2位 32勝18敗」
  List<String> history;
  /// ドラフト指名実績（画面には出さない）「2026 ソフトクリーム 3位 山田 太郎」
  List<String> drafted;
  /// 今年の隠れた原石の数（-1 はまだ決めていない）と、そのうち発掘された数
  int hid;
  int gen;

  AmTeam({required this.id, required this.name, required this.kind, required this.pref, required this.region, required this.strength, required this.prestige, this.w = 0, this.l = 0, this.d = 0, Map<String, double>? pipe, List<String>? history, List<String>? drafted, this.hid = -1, this.gen = 0})
      : pipe = pipe ?? {},
        history = history ?? [],
        drafted = drafted ?? [];

  Map<String, dynamic> toJson() => {
        'id': id, 'n': name, 'k': kind, 'pf': pref, 'rg': region, 's': strength, 'pr': prestige,
        if (w + l + d > 0) 'r': [w, l, d],
        if (pipe.isNotEmpty) 'pp': {for (final e in pipe.entries) e.key: (e.value * 100).round() / 100},
        if (history.isNotEmpty) 'h': history,
        if (drafted.isNotEmpty) 'dr': drafted,
        if (hid >= 0) 'hd': hid,
        if (gen > 0) 'gn': gen,
      };

  factory AmTeam.fromJson(Map<String, dynamic> j) {
    final r = (j['r'] as List?)?.cast<int>() ?? const [0, 0, 0];
    return AmTeam(
      id: j['id'], name: j['n'], kind: j['k'], pref: j['pf'] ?? 0, region: j['rg'] ?? 0, strength: j['s'] ?? 40, prestige: j['pr'] ?? 40,
      w: r[0], l: r[1], d: r[2],
      pipe: {for (final e in ((j['pp'] as Map?) ?? const {}).entries) '${e.key}': (e.value as num).toDouble()},
      history: List<String>.from(j['h'] ?? const []),
      drafted: List<String>.from(j['dr'] ?? const []),
      hid: j['hd'] ?? -1,
      gen: j['gn'] ?? 0,
    );
  }
}

/// 発掘された選手（アマチュア）。発掘されたときに生まれる
class AmPlayer {
  Player player; // ドラフト候補（Prospect）と同じものを指す（読み込んだときにつなぎ直す）
  String teamId;
  int grade;             // 学年（高校1〜3・大学1〜4）。社会人は入社からの年数
  /// 発掘・調査した NPB 球団の id。ここにない球団からは「不明」
  Set<String> foundBy;
  /// アマ時代の成績（大会・リーグごとの行）
  List<String> record;
  /// 今の大会・リーグの成績（大会が終わると record の行になる）
  PlayerStats cur;

  AmPlayer({required this.player, required this.teamId, required this.grade, Set<String>? foundBy, List<String>? record, PlayerStats? cur})
      : foundBy = foundBy ?? {},
        record = record ?? [],
        cur = cur ?? PlayerStats();

  String get id => player.id;

  Map<String, dynamic> toJson() => {'p': player.toJson(), 't': teamId, 'g': grade, 'f': foundBy.toList(), if (record.isNotEmpty) 'rc': record, if (cur.games > 0) 'cs': cur.toJson()};

  factory AmPlayer.fromJson(Map<String, dynamic> j) => AmPlayer(
        player: Player.fromJson(Map<String, dynamic>.from(j['p'] as Map)),
        teamId: j['t'],
        grade: j['g'] ?? 1,
        foundBy: Set<String>.from(j['f'] ?? const []),
        record: List<String>.from(j['rc'] ?? const []),
        cur: j['cs'] == null ? null : PlayerStats.fromJson(Map<String, dynamic>.from(j['cs'] as Map)),
      );
}


/// 今年の大会・リーグ（トーナメントかリーグ戦）
class AmComp {
  final String id;        // 年度の中で一意（'夏-pref-12' など）
  final String name;      // 「春季東京都大会」「夏の甲子園」「関東地区大学リーグ」
  final String cat;       // 高校 / 大学 / 社会人
  final String stage;     // pref（都道府県）・koshien・region（地区大会）・league（大学リーグ）・qual（都市対抗予選）・main（都市対抗本大会）
  final String season;    // 春 / 夏 / 秋 / ''（大学・社会人）
  final int pref, region; // 都道府県・地区の番号（なければ -1）
  final DateTime start;   // 1回戦（1節）の日
  final int gap;          // 回戦（節）の間の日数
  List<String> teams;     // 出場チーム（決まるまで空）
  /// トーナメント：rounds[r] は r 回戦の枠（チーム id。'' は不戦勝の空き）。scores[r] は各組の [先, 後]（不戦勝は空）
  List<List<String>> rounds;
  List<List<List<int>>> scores;
  /// リーグ戦：[節, a の番号, b の番号, a の得点, b の得点]（未消化は得点 -1）
  List<List<int>> games;
  bool done;

  AmComp({required this.id, required this.name, required this.cat, required this.stage, required this.season, this.pref = -1, this.region = -1, required this.start, required this.gap, List<String>? teams, List<List<String>>? rounds, List<List<List<int>>>? scores, List<List<int>>? games, this.done = false})
      : teams = teams ?? [],
        rounds = rounds ?? [],
        scores = scores ?? [],
        games = games ?? [];

  bool get isLeague => stage == 'league';

  /// その日が何回戦（何節）か。試合の日でなければ -1
  int roundOn(DateTime d) {
    final k = DateTime(d.year, d.month, d.day).difference(start).inDays;
    return k < 0 || k % gap != 0 ? -1 : k ~/ gap;
  }

  /// 決勝までの回戦の数
  int get totalRounds {
    var n = 0;
    for (var s = rounds.isEmpty ? 1 : rounds.first.length; s > 1; s ~/= 2) {
      n++;
    }
    return n;
  }

  /// 優勝チーム（トーナメントが終わっていれば）
  String? get champion => !isLeague && done && rounds.isNotEmpty && rounds.last.length == 1 ? rounds.last.first : null;

  /// チームが残っていた最後の回戦（0 始まり。優勝は totalRounds）。出ていなければ -1
  int reached(String id) {
    for (var r = rounds.length - 1; r >= 0; r--) {
      if (rounds[r].contains(id)) return r;
    }
    return -1;
  }

  /// 成績の言葉：優勝・準優勝・ベスト4・ベスト8・2回戦敗退…
  String resultOf(String id) {
    final r = reached(id);
    if (r < 0) return '';
    if (rounds[r].length == 1) return '優勝';
    if (!done && r == rounds.length - 1) return '勝ち残り';
    return switch (totalRounds - r) { 1 => '準優勝', 2 => 'ベスト4', 3 => 'ベスト8', 4 => 'ベスト16', _ => '${r + 1}回戦敗退' };
  }

  Map<String, dynamic> toJson() => {
        'id': id, 'n': name, 'c': cat, 'st': stage, 'se': season, 'pf': pref, 'rg': region,
        's': start.toIso8601String().substring(0, 10), 'gap': gap, 't': teams,
        if (rounds.isNotEmpty) 'r': rounds,
        if (scores.isNotEmpty) 'sc': scores,
        if (games.isNotEmpty) 'g': games,
        if (done) 'd': true,
      };

  factory AmComp.fromJson(Map<String, dynamic> j) => AmComp(
        id: j['id'], name: j['n'], cat: j['c'], stage: j['st'], season: j['se'] ?? '', pref: j['pf'] ?? -1, region: j['rg'] ?? -1,
        start: DateTime.parse(j['s']), gap: j['gap'] ?? 1, teams: List<String>.from(j['t'] ?? const []),
        rounds: [for (final x in (j['r'] as List? ?? [])) List<String>.from(x as List)],
        scores: [for (final x in (j['sc'] as List? ?? [])) [for (final y in (x as List)) List<int>.from(y as List)]],
        games: [for (final x in (j['g'] as List? ?? [])) List<int>.from(x as List)],
        done: j['d'] == true,
      );
}

/// アマチュア球界全体
class AmWorld {
  int year;              // 今の年度（4月に切り替える）
  List<AmTeam> teams;
  List<AmPlayer> players;
  int nextId;            // 選手の番号
  DateTime simDate;      // ここまでの日の試合を計算した
  List<AmComp> comps;    // 今年の大会・リーグ（年度が替わると消える）
  /// 今年、NPB 球団のスカウトが回ったチーム（球団 id → チーム id）
  Map<String, Set<String>> visits;
  /// 1年に1度だけの処理の印（'夏-koshien' など）
  Set<String> flags;
  /// 日本の独立リーグの選手を発掘した球団（選手 id → 球団 id。年をまたいで残る）
  Map<String, Set<String>> indie;
  /// 作り方の版（AmateurEngine.genVersion）
  int gen;

  AmWorld({required this.year, required this.teams, List<AmPlayer>? players, this.nextId = 0, DateTime? simDate, List<AmComp>? comps, Map<String, Set<String>>? visits, Set<String>? flags, Map<String, Set<String>>? indie, this.gen = 1})
      : players = players ?? [],
        indie = indie ?? {},
        visits = visits ?? {},
        flags = flags ?? {},
        simDate = simDate ?? DateTime(year, 3, 31),
        comps = comps ?? [];

  late final Map<String, AmTeam> _byId = {for (final t in teams) t.id: t};
  AmTeam? team(String id) => _byId[id];
  Iterable<AmTeam> ofKind(String k) => teams.where((t) => t.kind == k);
  Iterable<AmPlayer> playersOf(String teamId) => players.where((p) => p.teamId == teamId);
  AmComp? comp(String id) {
    for (final c in comps) {
      if (c.id == id) return c;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'y': year, 'n': nextId, 'gv': gen, 'sd': simDate.toIso8601String().substring(0, 10),
        't': [for (final t in teams) t.toJson()],
        'p': [for (final p in players) p.toJson()],
        'c': [for (final c in comps) c.toJson()],
        if (visits.isNotEmpty) 'v': {for (final e in visits.entries) e.key: e.value.toList()},
        if (flags.isNotEmpty) 'fl': flags.toList(),
        if (indie.isNotEmpty) 'ind': {for (final e in indie.entries) e.key: e.value.toList()},
      };

  factory AmWorld.fromJson(Map<String, dynamic> j) => AmWorld(
        year: j['y'],
        nextId: j['n'] ?? 0,
        gen: j['gv'] ?? 1,
        simDate: j['sd'] == null ? null : DateTime.parse(j['sd']),
        teams: [for (final e in (j['t'] as List)) AmTeam.fromJson(Map<String, dynamic>.from(e as Map))],
        players: [for (final e in (j['p'] as List? ?? [])) AmPlayer.fromJson(Map<String, dynamic>.from(e as Map))],
        comps: [for (final e in (j['c'] as List? ?? [])) AmComp.fromJson(Map<String, dynamic>.from(e as Map))],
        visits: {for (final e in ((j['v'] as Map?) ?? const {}).entries) '${e.key}': Set<String>.from(e.value as List)},
        flags: Set<String>.from(j['fl'] ?? const []),
        indie: {for (final e in ((j['ind'] as Map?) ?? const {}).entries) '${e.key}': Set<String>.from(e.value as List)},
      );
}
