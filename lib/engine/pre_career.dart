import '../models/player.dart';
import 'career_engine.dart';

/// ゲーム開始前の1年分の経歴（推定）
class PreYear {
  final int year;
  final String teamId;
  final PlayerStats stats;
  final List<String> honors; // 「2024年 本塁打王」「2024年 通算100本塁打達成」（推定）
  PreYear(this.year, this.teamId, this.stats) : honors = [];
}

/// ゲーム開始前の経歴を年度ごとに推定する。
///  - 年度ごとの成績は、開始時点の通算（ゲームの中の年度別を引いた残り）を、能力と年齢から作った推定の形で配分する（合計は通算と必ず一致）
///  - 所属は、ゲーム開始時の球団（その前の移籍は分からないので同じ球団とする）
///  - タイトルは、同じ年・同じリーグの推定成績の中で1位の選手に（実際の記録がある年・タイトルはそちらを優先）
///  - 節目の記録は、推定の通算がしきい値を超えた年に
class PreCareer {
  static const _intKeys = [
    'games', 'atBats', 'hits', 'homeRuns', 'rbi', 'walks', 'strikeouts', 'stolenBases', 'doubles', 'triples', 'sacFlies', 'hitsAllowed', 'hrAllowed',
    'fieldChances', 'fieldOuts', 'inningsPitched', 'earnedRuns', 'pitcherStrikeouts', 'pitcherWalks', 'wins', 'losses', 'saves', 'holds', 'runs', 'hbp',
    'multiHit', 'mouda', 'cycles', 'putouts', 'assists', 'errors', 'dpTurned', 'defOuts', 'completeGames', 'shutouts', 'noHitters', 'perfects',
    'hbpAllowed', 'pitchApps', 'reliefWins', 'multiHR', 'walkoffs', 'qs', 'tenK', 'gidp', 'sacBunts', 'starts', 'caughtStealing', 'sbAgainst', 'csAgainst',
  ];

  /// total を weights の割合で配分する（端数は大きい順に1ずつ。合計は total と一致）
  static List<int> _split(int total, List<num> weights) {
    final n = weights.length;
    if (n == 0) return const [];
    if (total <= 0) return List.filled(n, 0);
    var w = weights.map((x) => x <= 0 ? 0.0 : x.toDouble()).toList();
    var sum = w.fold<double>(0, (a, b) => a + b);
    if (sum <= 0) {
      w = List.filled(n, 1.0);
      sum = n.toDouble();
    }
    final raw = [for (final x in w) total * x / sum];
    final out = [for (final x in raw) x.floor()];
    var rest = total - out.fold<int>(0, (a, b) => a + b);
    final order = List.generate(n, (i) => i)..sort((a, b) => (raw[b] - raw[b].floor()).compareTo(raw[a] - raw[a].floor()));
    for (var i = 0; rest > 0; i = (i + 1) % n) {
      out[order[i]]++;
      rest--;
    }
    return out;
  }

  /// 1人分：pre（ゲーム開始前の通算）を years 年（firstYear から）に配分
  static List<PreYear> split(Player p, PlayerStats pre, int firstYear, int years, String teamId) {
    if (years <= 0 || pre.games <= 0 && pre.pitchApps <= 0) return const [];
    final shapes = CareerEngine.estimateYears(p, seasonsOverride: years);
    final pj = pre.toJson();
    final sj = [for (final s in shapes) s.toJson()];
    final outJ = [for (var i = 0; i < years; i++) <String, dynamic>{}];
    // 出場の配分を基本の重みに（その項目の推定が全部0の年しかないときに使う）
    final gameW = [for (final s in shapes) s.games + s.pitchApps];
    for (final k in _intKeys) {
      final t = (pj[k] ?? 0) as int;
      var w = <num>[for (final s in sj) (s[k] ?? 0) as int];
      if (w.every((x) => x == 0)) w = gameW;
      final parts = _split(t, w);
      for (var i = 0; i < years; i++) {
        outJ[i][k] = parts[i];
      }
    }
    for (final mk in ['posGames', 'posOuts']) {
      final m = (pj[mk] as Map?) ?? const {};
      for (var i = 0; i < years; i++) {
        outJ[i][mk] = <String, int>{};
      }
      for (final e in m.entries) {
        final w = <num>[for (final s in sj) ((s[mk] as Map?)?[e.key] ?? 0) as int];
        final parts = _split(e.value as int, w.every((x) => x == 0) ? gameW : w);
        for (var i = 0; i < years; i++) {
          if (parts[i] > 0) (outJ[i][mk] as Map<String, int>)[e.key as String] = parts[i];
        }
      }
    }
    // 打数より安打が多い・投球回0で自責点など、配分の端数で崩れたところを整える
    for (final j in outJ) {
      if ((j['hits'] as int) > (j['atBats'] as int)) j['atBats'] = j['hits'];
      if ((j['games'] as int) == 0 && ((j['atBats'] as int) > 0 || (j['pitchApps'] as int) > 0)) j['games'] = 1;
    }
    return [for (var i = 0; i < years; i++) PreYear(firstYear + i, teamId, PlayerStats.fromJson(outJ[i]))];
  }

  static const _titles = <(String, bool)>[
    ('首位打者', false), ('本塁打王', false), ('打点王', false), ('盗塁王', false), ('最多安打', false),
    ('最優秀防御率', true), ('最多勝利', true), ('最多奪三振', true), ('最多セーブ', true), ('最優秀中継ぎ', true),
  ];

  static num? _titleValue(String title, PlayerStats s) => switch (title) {
        '首位打者' => s.atBats + s.walks + s.hbp + s.sacFlies >= 400 ? s.battingAverage : null,
        '本塁打王' => s.homeRuns >= 15 ? s.homeRuns : null,
        '打点王' => s.rbi >= 50 ? s.rbi : null,
        '盗塁王' => s.stolenBases >= 15 ? s.stolenBases : null,
        '最多安打' => s.hits >= 120 ? s.hits : null,
        '最優秀防御率' => s.inningsPitched >= 130 * 3 ? -s.era : null,
        '最多勝利' => s.wins >= 8 ? s.wins : null,
        '最多奪三振' => s.pitcherStrikeouts >= 100 ? s.pitcherStrikeouts : null,
        '最多セーブ' => s.saves >= 10 ? s.saves : null,
        '最優秀中継ぎ' => s.holdPoints >= 15 ? s.holdPoints : null,
        _ => null,
      };

  /// 推定のタイトル：年・リーグごとに1位の選手へ。realHonors（実際の表彰の文字列）にその年・そのタイトルがあれば推定しない
  static void addTitles(Map<String, List<PreYear>> all, String Function(String teamId) leagueOf, Set<String> realHonors) {
    final groups = <String, List<(String, PreYear)>>{};
    for (final e in all.entries) {
      for (final y in e.value) {
        groups.putIfAbsent('${y.year}|${leagueOf(y.teamId)}', () => []).add((e.key, y));
      }
    }
    for (final g in groups.entries) {
      final year = int.parse(g.key.split('|').first);
      for (final (title, _) in _titles) {
        if (realHonors.contains('$year年 $title')) continue;
        PreYear? best;
        num? bv;
        for (final (_, y) in g.value) {
          final v = _titleValue(title, y.stats);
          if (v == null) continue;
          if (bv == null || v > bv) {
            bv = v;
            best = y;
          }
        }
        best?.honors.add('$year年 $title');
      }
    }
  }

  /// 推定の節目の記録（推定の通算が、しきい値を超えた年に）
  static void addMilestones(List<PreYear> years) {
    const marks = <(String, int Function(PlayerStats), List<int>)>[
      ('試合出場', _games, [500, 1000, 1500, 2000, 2500]),
      ('安打', _hits, [500, 1000, 1500, 2000, 2500, 3000]),
      ('本塁打', _hr, [50, 100, 150, 200, 250, 300, 350, 400, 450, 500]),
      ('打点', _rbi, [500, 1000, 1500]),
      ('盗塁', _sb, [100, 200, 300, 400]),
      ('登板', _apps, [300, 500, 700, 800, 900]),
      ('奪三振', _k, [1000, 1500, 2000, 2500, 3000]),
      ('勝', _w, [50, 100, 150, 200, 250]),
      ('セーブ', _sv, [50, 100, 150, 200, 250, 300]),
      ('ホールド', _hd, [100, 150, 200, 250, 300]),
    ];
    final cum = PlayerStats();
    for (final y in years) {
      final before = PlayerStats()..add(cum);
      cum.add(y.stats);
      for (final (label, f, ms) in marks) {
        if (label == '試合出場' && y.stats.pitchApps > 0) continue; // 投手は登板で
        for (final m in ms) {
          if (f(before) < m && f(cum) >= m) y.honors.add('${y.year}年 通算$m$label達成');
        }
      }
    }
  }

  static int _games(PlayerStats s) => s.games;
  static int _hits(PlayerStats s) => s.hits;
  static int _hr(PlayerStats s) => s.homeRuns;
  static int _rbi(PlayerStats s) => s.rbi;
  static int _sb(PlayerStats s) => s.stolenBases;
  static int _apps(PlayerStats s) => s.pitchApps;
  static int _k(PlayerStats s) => s.pitcherStrikeouts;
  static int _w(PlayerStats s) => s.wins;
  static int _sv(PlayerStats s) => s.saves;
  static int _hd(PlayerStats s) => s.holds;
}
