import '../models/player.dart';
import '../models/team.dart';
import '../utils/schedule_generator.dart';

/// ポストシーズンの1つのシリーズ（CSファースト・CSファイナル・日本シリーズ）
///  - CSファースト：2位 対 3位。3試合制、全試合2位の本拠地。先に2勝で勝ち抜け（引き分けを挟んで決まらなければ2位）
///  - CSファイナル：1位 対 ファースト勝者。6試合制、全試合1位の本拠地。1位に1勝のアドバンテージ。先に4勝
///  - 日本シリーズ：7試合制（決まらなければ第8戦まで）。本拠地は 2-3-2。先に4勝
class Series {
  final String id;      // CS1_CL / CSF_CL / CS1_PL / CSF_PL / JS
  final String stage;   // CS1 / CSF / JS
  final String league;  // CL / PL / JS
  String high;          // 上位（アドバンテージを持つ側）。未定は ''
  String low;           // 下位。未定は ''
  final int winsNeeded;
  final int advantage;  // 上位が最初から持っている勝ち数
  final int maxGames;
  final List<int> matchIdx; // matches の中の番号（試合ごとに1つずつ足す）
  String winner;        // 勝ち抜けた球団（未定は ''）
  String mvp;           // シリーズMVP（選手名・球団名）

  Series({
    required this.id,
    required this.stage,
    required this.league,
    this.high = '',
    this.low = '',
    required this.winsNeeded,
    this.advantage = 0,
    required this.maxGames,
    List<int>? matchIdx,
    this.winner = '',
    this.mvp = '',
  }) : matchIdx = matchIdx ?? [];

  String get label {
    final lg = league == 'CL' ? 'Aリーグ' : (league == 'PL' ? 'Bリーグ' : '');
    switch (stage) {
      case 'CS1': return '$lg CSファーストステージ';
      case 'CSF': return '$lg CSファイナルステージ';
      default: return '日本シリーズ';
    }
  }

  String get matchType => stage == 'JS' ? 'JS' : 'CS';

  /// 上位・下位の勝ち数（アドバンテージを含む）と引き分け数、消化試合数
  (int, int, int, int) tally(List<Match> matches) {
    var h = advantage, l = 0, d = 0, n = 0;
    for (final i in matchIdx) {
      if (i < 0 || i >= matches.length) continue;
      final m = matches[i];
      if (m.homeScore == null) continue;
      n++;
      final hs = m.homeTeamId == high ? m.homeScore! : m.awayScore!;
      final ls = m.homeTeamId == high ? m.awayScore! : m.homeScore!;
      if (hs > ls) {
        h++;
      } else if (ls > hs) {
        l++;
      } else {
        d++;
      }
    }
    return (h, l, d, n);
  }

  /// 勝敗が決まったか（決まったら winner を入れる）
  bool settle(List<Match> matches) {
    if (winner.isNotEmpty) return true;
    if (high.isEmpty || low.isEmpty) return false;
    final (h, l, _, n) = tally(matches);
    if (h >= winsNeeded) {
      winner = high;
    } else if (l >= winsNeeded) {
      winner = low;
    } else if (n >= maxGames) {
      winner = l > h ? low : high; // 決まらなければ上位（日本シリーズはホーム有利側）
    }
    return winner.isNotEmpty;
  }

  /// 次の試合がまだ作られていない（=作る必要がある）か
  bool needsGame(List<Match> matches) {
    if (winner.isNotEmpty || high.isEmpty || low.isEmpty) return false;
    return matchIdx.every((i) => i < matches.length && matches[i].homeScore != null);
  }

  /// 第n戦（0始まり）の日付
  DateTime dateOf(int n, int year) {
    switch (stage) {
      case 'CS1': return DateTime(year, 10, 3 + n);
      case 'CSF': return DateTime(year, 10, 8 + n);
      default:
        const days = [17, 18, 20, 21, 22, 24, 25, 26];
        return DateTime(year, 10, days[n.clamp(0, days.length - 1)]);
    }
  }

  /// 第n戦のホーム。CSは上位の本拠地。日本シリーズは 2-3-2（上位＝第1・2・6・7戦がホーム）
  String homeOf(int n) {
    if (stage != 'JS') return high;
    return (n <= 1 || n >= 5) ? high : low;
  }

  Map<String, dynamic> toJson() => {
        'id': id, 'stage': stage, 'league': league, 'high': high, 'low': low, 'winsNeeded': winsNeeded,
        'advantage': advantage, 'maxGames': maxGames, 'matchIdx': matchIdx, 'winner': winner, 'mvp': mvp,
      };

  factory Series.fromJson(Map<String, dynamic> j) => Series(
        id: j['id'], stage: j['stage'], league: j['league'], high: j['high'] ?? '', low: j['low'] ?? '',
        winsNeeded: j['winsNeeded'], advantage: j['advantage'] ?? 0, maxGames: j['maxGames'],
        matchIdx: List<int>.from(j['matchIdx'] ?? []), winner: j['winner'] ?? '', mvp: j['mvp'] ?? '',
      );
}

/// ポストシーズンの予定の1日分：(段階, リーグ, 第n戦（0始まり）)
class PostPlanDay {
  final String stage, league;
  final int n;
  const PostPlanDay(this.stage, this.league, this.n);

  String get stageLabel => switch (stage) { 'CS1' => 'CSファーストステージ', 'CSF' => 'CSファイナルステージ', _ => '日本シリーズ' };
  String get shortLabel => switch (stage) { 'CS1' => 'CS1st', 'CSF' => 'CSファイナル', _ => '日本S' };
  /// 決まらないときだけ行う試合（CS1 の第3戦・CSF の第5・6戦・日本シリーズの第5〜8戦）
  bool get ifNeeded => switch (stage) { 'CS1' => n >= 2, 'CSF' => n >= 4, _ => n >= 4 };
}

/// ポストシーズンの予定（年ごと。日付はシーズンの日程を作った時点で決まっている）。キー＝日付
Map<DateTime, List<PostPlanDay>> postPlan(int year) {
  final out = <DateTime, List<PostPlanDay>>{};
  void add(String stage, String league, int games) {
    final s = Series(id: '', stage: stage, league: league, winsNeeded: 0, maxGames: games);
    for (var n = 0; n < games; n++) {
      out.putIfAbsent(s.dateOf(n, year), () => []).add(PostPlanDay(stage, league, n));
    }
  }

  for (final lg in ['CL', 'PL']) {
    add('CS1', lg, 3);
    add('CSF', lg, 6);
  }
  add('JS', 'JS', 8);
  return out;
}

/// シリーズの最優秀選手（ボックススコアから：安打・本塁打・打点、投手は投球回と自責点）
String seriesMvp(List<Match> games, Team winner, Map<String, Player> byName) {
  final score = <String, double>{};
  for (final m in games) {
    if (m.boxScore == null) continue;
    final side = m.homeTeamId == winner.id ? 'home' : 'away';
    final bat = m.boxScore!['${side}Batters'];
    if (bat is Map) {
      bat.forEach((name, v) {
        if (v is! Map) return;
        final h = (v['h'] ?? 0) as int, hr = (v['hr'] ?? 0) as int, rbi = (v['rbi'] ?? 0) as int, bb = (v['bb'] ?? 0) as int;
        score[name] = (score[name] ?? 0) + h * 1.0 + hr * 2.5 + rbi * 1.2 + bb * 0.4;
      });
    }
    final pit = m.boxScore!['${side}Pitcher'];
    if (pit is Map) {
      pit.forEach((name, v) {
        if (v is! Map) return;
        final ip = double.tryParse('${v['ip']}') ?? 0, er = (v['er'] ?? 0) as int, so = (v['so'] ?? 0) as int;
        score[name] = (score[name] ?? 0) + ip * 0.9 - er * 1.2 + so * 0.3;
      });
    }
  }
  if (score.isEmpty) return '';
  final best = score.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  return '$best（${winner.shortName.isNotEmpty ? winner.shortName : winner.name}）';
}

/// オールスターの選抜チーム（リーグの各ポジションで成績と人気の高い選手＋投手）
Team buildAllStarTeam(String id, String league, List<Team> teams, Map<String, int> rankOf) {
  final pool = <Player>[];
  final teamOf = <String, Team>{};
  for (final t in teams.where((t) => t.league == league)) {
    for (final p in t.players.where((p) => t.roster1G.contains(p.id) && !p.isInjuredOut)) {
      pool.add(p);
      teamOf[p.id] = t;
    }
  }
  double fanScore(Player p) {
    final s = p.seasonStats;
    final pop = 8.0 - (rankOf[teamOf[p.id]!.id] ?? 6); // 順位の高い球団ほど人気
    if (p.isPitcher) return p.ovr + s.wins * 0.8 + s.saves * 0.3 + s.holds * 0.2 + pop;
    return p.ovr + s.homeRuns * 0.6 + s.hits * 0.08 + pop;
  }
  final batters = pool.where((p) => !p.isPitcher).toList()..sort((a, b) => fanScore(b).compareTo(fanScore(a)));
  final pitchers = pool.where((p) => p.isPitcher).toList()..sort((a, b) => fanScore(b).compareTo(fanScore(a)));
  const posName = {'捕': '捕手', '一': '一塁手', '二': '二塁手', '三': '三塁手', '遊': '遊撃手', '左': '左翼手', '中': '中堅手', '右': '右翼手'};
  final lineup = <LineupEntry>[];
  final used = <String>{};
  for (final pos in ['捕', '遊', '二', '中', '三', '右', '左', '一']) {
    Player? best;
    for (final p in batters) {
      if (used.contains(p.id)) continue;
      if (p.mainPosition == posName[pos]) { best = p; break; }
    }
    best ??= batters.where((p) => !used.contains(p.id)).firstOrNull;
    if (best == null) continue;
    used.add(best.id);
    lineup.add(LineupEntry(playerId: best.id, position: pos));
  }
  final dh = batters.where((p) => !used.contains(p.id)).firstOrNull;
  if (dh != null) { used.add(dh.id); lineup.add(LineupEntry(playerId: dh.id, position: 'DH')); }
  final bench = batters.where((p) => !used.contains(p.id)).take(7).toList();
  final pick = pitchers.take(13).toList();
  final starters = [...pick]..sort((a, b) => b.stamina.compareTo(a.stamina));
  final rotation = starters.take(4).map((p) => p.id).toList();
  final relievers = pick.where((p) => !rotation.contains(p.id)).toList()..sort((a, b) => b.ovr.compareTo(a.ovr));
  final wp = [relievers.length > 2 ? relievers[2].id : '', relievers.length > 1 ? relievers[1].id : '', relievers.isNotEmpty ? relievers[0].id : ''];
  final members = <Player>[...pool.where((p) => used.contains(p.id)), ...bench, ...pick];
  // 打順：打てる順
  final byId = {for (final p in members) p.id: p};
  lineup.sort((a, b) => byId[b.playerId]!.ovr.compareTo(byId[a.playerId]!.ovr));
  return Team(
    id: id,
    name: league == 'CL' ? 'Aリーグ選抜' : 'Bリーグ選抜',
    shortName: league == 'CL' ? 'A選抜' : 'B選抜',
    initialName: league == 'CL' ? 'A' : 'B',
    league: league,
    players: members,
    roster1G: [],
    rotation: rotation,
    rotationCount: 4,
    winningPattern: wp,
    lineup: lineup,
    active26: members.map((p) => p.id).toList(),
  );
}
