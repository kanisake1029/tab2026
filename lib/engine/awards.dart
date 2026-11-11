import 'dart:math';
import '../models/player.dart';
import '../models/team.dart';
import '../utils/schedule_generator.dart';
import '../utils/standings.dart';

/// 年間の表彰（タイトル・MVP・新人王・ベストナイン・ゴールデングラブ・沢村賞・カムバック賞）
///
/// ベストナイン・ゴールデングラブ・MVP・新人王は「点数で候補を出し、記者300人の投票を再現する」。
/// 記者ごとに点数へ揺らぎ（人気＝チーム順位、前年の受賞＝連続受賞されやすさ）を加えて1位を選び、得票数を出す。
class AwardsEngine {
  static const reporters = 300;

  static const _posName = {'捕': '捕手', '一': '一塁手', '二': '二塁手', '三': '三塁手', '遊': '遊撃手', '左': '左翼手', '中': '中堅手', '右': '右翼手'};
  static const _of = ['左', '中', '右'];
  // 守備の負担によるポジション補正（156試合あたりの点）
  static const _posAdj = {'捕': 9.0, '遊': 7.0, '二': 3.0, '中': 2.5, '三': 2.0, '左': -7.0, '右': -7.0, '外': -4.0, '一': -12.0, 'DH': -17.0};

  /// 計算して、保存用の JSON（Map）で返す
  static Map<String, dynamic> compute({
    required int year,
    required List<Team> teams,
    required List<Match> matches,
    Map<String, dynamic>? previous, // 前年の表彰（連続受賞されやすさ）
    Map<String, Map<String, dynamic>> prevStats = const {}, // 前年の成績（カムバック賞）
    List<Map<String, dynamic>> series = const [],
    List<String> allStarMvps = const [],
    String? championId,
  }) {
    final rnd = Random(year * 7919);
    final leagues = <String, dynamic>{};
    final allPitchers = <(Player, Team)>[];
    for (final lg in ['CL', 'PL']) {
      final st = computeStandings(teams, matches, lg, StandingsKind.official);
      if (st.isEmpty) continue;
      final ranks = {for (var i = 0; i < st.length; i++) st[i].team.id: i + 1};
      final g = st.map((r) => r.games).fold(0, max);
      final members = <(Player, Team)>[for (final t in teams.where((t) => t.league == lg)) for (final p in t.players) (p, t)];
      allPitchers.addAll(members.where((e) => e.$1.isPitcher));
      leagues[lg] = _league(lg, members, ranks, g, rnd, previous?['leagues']?[lg] as Map<String, dynamic>?);
    }
    return {
      'year': year,
      'champion': championId,
      'leagues': leagues,
      'sawamura': _sawamura(allPitchers),
      'comeback': _comeback([for (final t in teams) for (final p in t.players) (p, t)], prevStats),
      'series': series,
      'allStarMvp': allStarMvps,
    };
  }

  // ───────── 指標 ─────────

  static double _woba(PlayerStats s) {
    final pa = s.plateAppearances;
    if (pa == 0) return 0;
    final singles = s.hits - s.doubles - s.triples - s.homeRuns;
    return (0.69 * s.walks + 0.89 * singles + 1.27 * s.doubles + 1.62 * s.triples + 2.10 * s.homeRuns) / pa;
  }

  /// 打撃で平均より何点多く生んだか（盗塁を少し加える）
  static double _batRuns(PlayerStats s, double lgWoba) => (_woba(s) - lgWoba) / 1.2 * s.plateAppearances + s.stolenBases * 0.2;

  /// 投球で平均より何点防いだか
  static double _pitRuns(PlayerStats s, double lgEra) => (lgEra - s.era) * (s.inningsPitched / 3) / 9 + s.wins * 0.3 + s.saves * 0.25 + s.holds * 0.12;

  static String _mainPos(Player p) {
    if (p.isPitcher) return '投';
    final pg = p.seasonStats.posGames;
    if (pg.isNotEmpty) {
      final best = pg.entries.where((e) => e.key != '投').fold<MapEntry<String, int>?>(null, (a, b) => a == null || b.value > a.value ? b : a);
      if (best != null && best.value > 0) return best.key;
    }
    for (final e in _posName.entries) {
      if (e.value == p.mainPosition) return e.key;
    }
    return 'DH';
  }

  static String _teamShort(Team t) => t.shortName.isNotEmpty ? t.shortName : t.name;

  static String _ipText(int outs) => '${outs ~/ 3}${outs % 3 == 0 ? "" : " ${outs % 3}/3"}';

  static String _rate(double v) => v.toStringAsFixed(3).replaceFirst(RegExp(r'^0'), '');

  static Map<String, dynamic> _who(Player p, Team t) => {'id': p.id, 'name': p.registeredName, 'team': t.id, 'teamName': _teamShort(t)};

  // ───────── リーグごと ─────────

  static Map<String, dynamic> _league(String lg, List<(Player, Team)> members, Map<String, int> ranks, int g, Random rnd, Map<String, dynamic>? prev) {
    final qPa = (g * 3.1).floor();
    final qIp = g; // 規定投球回（チーム試合数）
    final hitters = members.where((e) => !e.$1.isPitcher && e.$1.seasonStats.plateAppearances > 0).toList();
    final pitchers = members.where((e) => e.$1.isPitcher && e.$1.seasonStats.games > 0).toList();

    var paSum = 0, wobaSum = 0.0, erSum = 0, ipSum = 0;
    for (final (p, _) in hitters) {
      paSum += p.seasonStats.plateAppearances;
      wobaSum += _woba(p.seasonStats) * p.seasonStats.plateAppearances;
    }
    for (final (p, _) in pitchers) {
      erSum += p.seasonStats.earnedRuns;
      ipSum += p.seasonStats.inningsPitched;
    }
    final lgWoba = paSum == 0 ? 0.3 : wobaSum / paSum;
    final lgEra = ipSum == 0 ? 3.5 : erSum * 27 / ipSum;

    // ---- タイトル ----
    final titles = <Map<String, dynamic>>[];
    void leader(String title, List<(Player, Team)> pool, num Function(PlayerStats) v, String Function(num) fmt, {bool low = false, bool needPositive = true}) {
      final cands = pool.where((e) => !needPositive || v(e.$1.seasonStats) > 0).toList();
      if (cands.isEmpty) {
        titles.add({'title': title, 'winners': [], 'value': '該当者なし'});
        return;
      }
      final best = cands.map((e) => v(e.$1.seasonStats)).reduce((a, b) => low ? min(a, b) : max(a, b));
      final ws = cands.where((e) => v(e.$1.seasonStats) == best).toList();
      titles.add({'title': title, 'winners': [for (final (p, t) in ws) _who(p, t)], 'value': fmt(best)});
    }
    final qHit = hitters.where((e) => e.$1.seasonStats.plateAppearances >= qPa).toList();
    final qPit = pitchers.where((e) => e.$1.seasonStats.inningsPitched >= qIp * 3).toList();
    leader('首位打者', qHit, (s) => s.battingAverage, (v) => _rate(v.toDouble()));
    leader('本塁打王', hitters, (s) => s.homeRuns, (v) => '$v本');
    leader('打点王', hitters, (s) => s.rbi, (v) => '$v打点');
    leader('盗塁王', hitters, (s) => s.stolenBases, (v) => '$v盗塁');
    leader('最高出塁率', qHit, (s) => s.obp, (v) => _rate(v.toDouble()));
    leader('最多安打', hitters, (s) => s.hits, (v) => '$v安打');
    leader('最優秀防御率', qPit, (s) => s.era, (v) => v.toStringAsFixed(2), low: true, needPositive: false);
    leader('最多勝利', pitchers, (s) => s.wins, (v) => '$v勝');
    leader('最多奪三振', pitchers, (s) => s.pitcherStrikeouts, (v) => '$v奪三振');
    leader('最高勝率', pitchers.where((e) => e.$1.seasonStats.wins >= 14).toList(), (s) => s.winPct, (v) => _rate(v.toDouble()));
    leader('最多セーブ', pitchers, (s) => s.saves, (v) => '$vセーブ');
    leader('最優秀中継ぎ', pitchers, (s) => s.holdPoints, (v) => '${v}HP');

    // ---- 点数 ----
    double teamBonus(Team t) => (7 - (ranks[t.id] ?? 6)) * 0.8; // 順位の高い球団ほど人気
    double valueOf(Player p, {String? asPos}) {
      if (p.isPitcher) return _pitRuns(p.seasonStats, lgEra);
      final pos = asPos ?? _mainPos(p);
      final games = p.seasonStats.games.clamp(0, 999);
      return _batRuns(p.seasonStats, lgWoba) + (_posAdj[pos] ?? 0) * games / 156;
    }

    Map<String, dynamic> vote(String key, List<(Player, Team)> pool, double Function(Player) score, {double sigma = 4, String? prevId, int pick = 1, Map<String, dynamic>? prevBlock}) {
      if (pool.isEmpty) return {'winners': [], 'ranking': []};
      final votes = <String, int>{};
      final prevIds = <String>{if (prevId != null) prevId};
      final base = {for (final (p, t) in pool) p.id: score(p) + teamBonus(t)};
      for (var r = 0; r < reporters; r++) {
        final s = <String, double>{};
        base.forEach((id, v) {
          final n = (rnd.nextDouble() + rnd.nextDouble() + rnd.nextDouble() - 1.5) * sigma * 1.4;
          s[id] = v + n + (prevIds.contains(id) ? sigma * 0.6 : 0);
        });
        final top = s.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
        for (final e in top.take(pick)) {
          votes[e.key] = (votes[e.key] ?? 0) + 1;
        }
      }
      final byId = {for (final (p, t) in pool) p.id: (p, t)};
      final ranking = votes.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      return {
        'winners': [for (final e in ranking.take(pick)) {..._who(byId[e.key]!.$1, byId[e.key]!.$2), 'votes': e.value}],
        'ranking': [for (final e in ranking.take(pick + 3)) {..._who(byId[e.key]!.$1, byId[e.key]!.$2), 'votes': e.value}],
      };
    }

    String? prevWinner(String block, String pos) {
      final list = prev?[block];
      if (list is! List) return null;
      for (final x in list) {
        if (x is Map && x['pos'] == pos) {
          final ws = x['winners'];
          if (ws is List && ws.isNotEmpty) return ws.first['id'] as String?;
        }
      }
      return null;
    }

    // ---- MVP・新人王 ----
    final mvpPool = [...hitters.where((e) => e.$1.seasonStats.plateAppearances >= qPa * 0.7), ...pitchers.where((e) => e.$1.seasonStats.inningsPitched >= qIp * 3 * 0.7 || e.$1.seasonStats.saves >= 25 || e.$1.seasonStats.holds >= 30)];
    final mvp = vote('mvp', mvpPool, (p) => valueOf(p) + (ranks[members.firstWhere((e) => e.$1 == p).$2.id] == 1 ? 6 : 0), sigma: 6);
    final rookies = [...hitters, ...pitchers].where((e) => e.$1.proYears <= 1).toList();
    final rookiePool = rookies.where((e) => e.$1.seasonStats.plateAppearances >= 150 || e.$1.seasonStats.inningsPitched >= 120 || e.$1.seasonStats.games >= 30).toList();
    final rookie = vote('rookie', rookiePool, (p) => valueOf(p), sigma: 4);

    // ---- ベストナイン ----
    final b9 = <Map<String, dynamic>>[];
    List<(Player, Team)> eligible(String pos, {bool forGG = false}) {
      List<(Player, Team)> at(double share) {
        if (pos == '投') {
          return pitchers.where((e) => e.$1.seasonStats.inningsPitched >= qIp * 3 * share || e.$1.seasonStats.games >= 50 * share).toList();
        }
        final keys = pos == '外' ? _of : [pos];
        return hitters.where((e) => e.$1.seasonStats.posGamesOf(keys) >= g * 0.5 * share).toList();
      }
      var list = at(1.0);
      if (list.isEmpty) list = at(0.5);
      if (list.isEmpty) list = at(0.1);
      return list;
    }
    for (final pos in ['投', '捕', '一', '二', '三', '遊', '外', 'DH']) {
      final pool = eligible(pos);
      final res = vote('b9_$pos', pool, (p) => valueOf(p, asPos: pos), sigma: 4, prevId: prevWinner('b9', pos), pick: pos == '外' ? 3 : 1);
      b9.add({'pos': pos, ...res});
    }

    // ---- ゴールデングラブ ----
    final gg = <Map<String, dynamic>>[];
    // 位置ごとの平均（1試合あたりのアウト数）
    double outsPerGame(Player p, String pos) {
      final keys = pos == '外' ? _of : [pos];
      final games = p.seasonStats.posGamesOf(keys);
      return games == 0 ? 0 : p.seasonStats.fieldOuts / games;
    }
    for (final pos in ['投', '捕', '一', '二', '三', '遊', '外']) {
      final pool = eligible(pos, forGG: true);
      final avg = pool.isEmpty ? 0.0 : pool.map((e) => outsPerGame(e.$1, pos)).reduce((a, b) => a + b) / pool.length;
      double def(Player p) {
        double apt;
        if (pos == '投') {
          apt = p.fieldP + p.catchSkill * 0.4;
        } else if (pos == '捕') {
          apt = p.fieldC + p.arm * 0.5 + p.throwAccuracy * 0.3;
        } else if (pos == '外') {
          final keys = {'左': p.fieldLF, '中': p.fieldCF, '右': p.fieldRF};
          var best = 0;
          var most = -1;
          for (final k in _of) {
            final gms = p.seasonStats.posGames[k] ?? 0;
            if (gms > most) { most = gms; best = keys[k]!; }
          }
          apt = best + p.run * 0.3 + p.arm * 0.3 + p.catchSkill * 0.3;
        } else {
          final f = {'一': p.field1B, '二': p.field2B, '三': p.field3B, '遊': p.fieldSS}[pos]!;
          apt = f + p.catchSkill * 0.4 + p.throwAccuracy * 0.3 + (pos == '遊' || pos == '三' ? p.arm * 0.3 : p.arm * 0.1);
        }
        return apt / 3 + (outsPerGame(p, pos) - avg) * 12;
      }
      final res = vote('gg_$pos', pool, def, sigma: 3, prevId: prevWinner('gg', pos), pick: pos == '外' ? 3 : 1);
      gg.add({'pos': pos, ...res});
    }

    return {
      'pennant': ranks.entries.firstWhere((e) => e.value == 1).key,
      'games': g,
      'qualifiedPa': qPa,
      'qualifiedIp': qIp,
      'titles': titles,
      'mvp': mvp,
      'rookie': rookie,
      'b9': b9,
      'gg': gg,
    };
  }

  // ───────── 沢村賞（両リーグから1人） ─────────
  static Map<String, dynamic> _sawamura(List<(Player, Team)> pitchers) {
    // 選考基準（156試合制に合わせて少し緩める）：15勝・150奪三振・180投球回・防御率2.50・勝率6割・25登板。4項目以上を満たす投手から
    Map<String, dynamic>? best;
    double bestScore = -1e9;
    for (final (p, t) in pitchers) {
      final s = p.seasonStats;
      final ip = s.inningsPitched / 3;
      if (ip < 150) continue;
      final met = [s.wins >= 15, s.pitcherStrikeouts >= 150, ip >= 180, s.era <= 2.50, s.winPct >= 0.600, s.games >= 25].where((x) => x).length;
      if (met < 4) continue;
      final score = s.wins * 1.0 + s.pitcherStrikeouts / 15 + ip / 20 + (3.5 - s.era) * 5 + met * 2;
      if (score > bestScore) {
        bestScore = score;
        best = {..._who(p, t), 'value': '${s.wins}勝${s.losses}敗 防御率${s.era.toStringAsFixed(2)} ${s.pitcherStrikeouts}奪三振 ${_ipText(s.inningsPitched)}回', 'met': met};
      }
    }
    return best ?? {'none': true};
  }

  // ───────── カムバック賞 ─────────
  static Map<String, dynamic> _comeback(List<(Player, Team)> all, Map<String, Map<String, dynamic>> prevStats) {
    if (prevStats.isEmpty) return {'none': true, 'reason': '前年の記録がありません'};
    Map<String, dynamic>? best;
    double bestScore = 0;
    for (final (p, t) in all) {
      final prev = prevStats[p.id];
      if (prev == null || p.proYears < 5) continue;
      final ps = PlayerStats.fromJson(prev);
      final s = p.seasonStats;
      final wasDown = ps.plateAppearances < 150 && ps.inningsPitched < 120;
      if (!wasDown) continue;
      double score = 0;
      String value = '';
      if (!p.isPitcher && s.plateAppearances >= 400 && s.ops >= 0.800) {
        score = s.ops * 100;
        value = '打率${_rate(s.battingAverage)} ${s.homeRuns}本 OPS${_rate(s.ops)}';
      } else if (p.isPitcher && s.inningsPitched >= 360 && s.era <= 3.00) {
        score = 100 - s.era * 10 + s.wins;
        value = '${s.wins}勝 防御率${s.era.toStringAsFixed(2)}';
      }
      if (score > bestScore) {
        bestScore = score;
        best = {..._who(p, t), 'value': value};
      }
    }
    return best ?? {'none': true};
  }
}
