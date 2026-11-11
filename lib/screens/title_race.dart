import '../widgets/chip_grid.dart';
import 'package:flutter/material.dart';
import '../models/player.dart';
import '../models/team.dart';
import '../utils/schedule_generator.dart';
import '../utils/standings.dart';
import '../widgets/player_detail_dialog.dart';

/// タイトル争い：ホームに上位3人、タップでリーグごとのすべての順位
class TitleDef {
  final String title;
  final bool pitcher;
  final num Function(PlayerStats) value;
  final String Function(num) fmt;
  final bool low;        // 小さいほど上（防御率）
  final bool qualified;  // 規定打席・規定投球回が必要
  final bool Function(PlayerStats)? extra;
  const TitleDef(this.title, this.pitcher, this.value, this.fmt, {this.low = false, this.qualified = false, this.extra});
}

String _rate(num v) => v.toStringAsFixed(3).replaceFirst(RegExp(r'^0'), '');

final titleDefs = <TitleDef>[
  TitleDef('首位打者', false, (s) => s.battingAverage, _rate, qualified: true),
  TitleDef('本塁打', false, (s) => s.homeRuns, (v) => '$v本'),
  TitleDef('打点', false, (s) => s.rbi, (v) => '$v打点'),
  TitleDef('盗塁', false, (s) => s.stolenBases, (v) => '$v盗塁'),
  TitleDef('最高出塁率', false, (s) => s.obp, _rate, qualified: true),
  TitleDef('最多安打', false, (s) => s.hits, (v) => '$v安打'),
  TitleDef('最優秀防御率', true, (s) => s.era, (v) => v.toStringAsFixed(2), low: true, qualified: true),
  TitleDef('最多勝利', true, (s) => s.wins, (v) => '$v勝'),
  TitleDef('最多奪三振', true, (s) => s.pitcherStrikeouts, (v) => '$v奪三振'),
  TitleDef('最高勝率', true, (s) => s.winPct, _rate, extra: (s) => s.wins >= 14),
  TitleDef('最多セーブ', true, (s) => s.saves, (v) => '${v}S'),
  TitleDef('最優秀中継ぎ', true, (s) => s.holdPoints, (v) => '${v}H'),
];

/// 球団ごとの公式戦（open ならオープン戦）の消化試合数（規定打席・規定投球回の基準）
Map<String, int> teamGamesPlayed(List<Team> teams, List<Match> matches, {bool open = false}) {
  final g = {for (final t in teams) t.id: 0};
  for (final m in matches) {
    if (m.homeScore == null || (open ? m.matchType != 'OPEN' : (m.matchType != 'LEAGUE' && m.matchType != 'INTERLEAGUE'))) continue;
    g[m.homeTeamId] = (g[m.homeTeamId] ?? 0) + 1;
    g[m.awayTeamId] = (g[m.awayTeamId] ?? 0) + 1;
  }
  return g;
}

/// リーグの順位（同じ値は同順位）。規定に届かない選手は入らない
List<(Player, Team, num)> titleRanking(List<Team> teams, List<Match> matches, String league, TitleDef d, {bool open = false}) {
  final games = teamGamesPlayed(teams, matches, open: open);
  final out = <(Player, Team, num)>[];
  for (final t in teams.where((t) => t.league == league)) {
    final g = games[t.id] ?? 0;
    for (final p in t.players) {
      if (p.isPitcher != d.pitcher) continue;
      final s = open ? p.openStats : p.seasonStats;
      if (d.pitcher ? s.games == 0 : s.plateAppearances == 0) continue;
      if (d.qualified && (d.pitcher ? s.inningsPitched < g * 3 : s.plateAppearances < (g * 3.1).floor())) continue;
      if (d.extra != null && !d.extra!(s)) continue;
      final v = d.value(s);
      if (!d.low && v <= 0) continue;
      out.add((p, t, v));
    }
  }
  out.sort((a, b) => d.low ? a.$3.compareTo(b.$3) : b.$3.compareTo(a.$3));
  return out;
}

/// 全順位の画面（リーグを切り替え）
class TitleRankingScreen extends StatefulWidget {
  final dynamic app;
  final int initial;
  final String league;
  const TitleRankingScreen({super.key, required this.app, required this.initial, required this.league});
  @override
  State<TitleRankingScreen> createState() => _TitleRankingScreenState();
}

class _TitleRankingScreenState extends State<TitleRankingScreen> with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: titleDefs.length, vsync: this, initialIndex: widget.initial);
  late String _league = widget.league;
  late bool _open = Player.showOpen; // 開幕前はオープン戦から

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final teams = widget.app.teams as List<Team>;
    final matches = widget.app.matches as List<Match>;
    final games = teamGamesPlayed(teams, matches, open: _open);
    final lgGames = teams.where((t) => t.league == _league).map((t) => games[t.id] ?? 0).fold<int>(0, (a, b) => a > b ? a : b);
    return Scaffold(
      appBar: AppBar(
        title: Text(_open ? 'オープン戦の成績ランキング' : 'タイトル争い'),
      ),
      body: Column(children: [
        Container(color: Colors.white, child: TabGrid(controller: _tab, labels: [for (final d in titleDefs) d.title], minWidth: 64)),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(children: [
            SegmentedButton<String>(
              segments: const [ButtonSegment(value: 'CL', label: Text('Aリーグ')), ButtonSegment(value: 'PL', label: Text('Bリーグ'))],
              selected: {_league},
              showSelectedIcon: false,
              onSelectionChanged: (v) => setState(() => _league = v.first),
            ),
            const SizedBox(width: 6),
            SegmentedButton<bool>(
              segments: const [ButtonSegment(value: false, label: Text('公式戦')), ButtonSegment(value: true, label: Text('オープン戦'))],
              selected: {_open},
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              onSelectionChanged: (v) => setState(() => _open = v.first),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text('規定打席 ${(lgGames * 3.1).floor()}・規定投球回 $lgGames（球団の試合数が基準）', style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)))),
          ]),
        ),
        Expanded(
          child: TabBarView(controller: _tab, children: [
            for (final d in titleDefs)
              Builder(builder: (_) {
                final list = titleRanking(teams, matches, _league, d, open: _open);
                if (list.isEmpty) return const Center(child: Text('まだ対象の選手がいません'));
                var rank = 0;
                num? prev;
                return ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final (p, t, v) = list[i];
                    if (prev == null || v != prev) rank = i + 1;
                    prev = v;
                    final mine = t.id == widget.app.myTeamId;
                    return ListTile(
                      dense: true,
                      leading: SizedBox(width: 30, child: Text('$rank', textAlign: TextAlign.center, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: rank <= 3 ? const Color(0xFFB45309) : null))),
                      title: Text(p.listName, style: TextStyle(fontWeight: FontWeight.w800, color: mine ? const Color(0xFFB45309) : null)),
                      subtitle: Text('${teamShort(t)}　${p.mainPosition}　${p.age}歳'),
                      trailing: Text(d.fmt(v), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()])),
                      onTap: () => showPlayerDetail(context, widget.app, p, allowActions: mine),
                    );
                  },
                );
              }),
          ]),
        ),
      ]),
    );
  }
}
