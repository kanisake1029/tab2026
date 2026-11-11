import 'package:flutter/material.dart';
import '../models/player.dart';
import '../models/team.dart';
import '../providers/app_state.dart';
import '../utils/salary_utils.dart';
import '../utils/standings.dart';
import '../widgets/player_detail_dialog.dart';
import '../widgets/player_row.dart';
import 'team_roster_screen.dart';

const _sub = Color(0xFF78716C);
const _line = Color(0xFFE7E5E4);

/// 監督室の「全球団選手一覧」：12球団の選手一覧と、名前での検索。選手をタップすると詳細
class AllTeamsTab extends StatefulWidget {
  final AppState app;
  const AllTeamsTab({super.key, required this.app});

  @override
  State<AllTeamsTab> createState() => _AllTeamsTabState();
}

class _AllTeamsTabState extends State<AllTeamsTab> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final hits = <(Player, Team)>[];
    if (_q.trim().isNotEmpty) {
      final q = _q.trim();
      for (final t in app.teams) {
        for (final p in t.players) {
          if (p.listName.contains(q) || p.registeredName.contains(q) || '${p.lastName}${p.firstName}'.contains(q)) hits.add((p, t));
        }
      }
    }
    Widget teamCard(Team t) {
      final ovr = t.players.isEmpty ? 0 : t.players.map((p) => p.ovr).reduce((a, b) => a + b) / t.players.length;
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: _line)),
          child: ListTile(
            dense: true,
            title: Text(t.name, style: TextStyle(fontWeight: FontWeight.w800, color: t.id == app.myTeamId ? const Color(0xFFB45309) : null)),
            subtitle: Text('${t.wins}勝${t.losses}敗${t.draws}分　選手${t.players.length}人　平均OVR ${ovr.toStringAsFixed(1)}　年俸総額 ${formatSalary(t.players.fold<int>(0, (s, p) => s + p.salary))}',
                style: const TextStyle(fontSize: 11.5)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TeamRosterScreen(appState: app, team: t))),
          ),
        ),
      );
    }

    return ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 24), children: [
      TextField(
        decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: '選手の名前で探す（12球団）', isDense: true, border: OutlineInputBorder()),
        onChanged: (v) => setState(() => _q = v),
      ),
      const SizedBox(height: 10),
      if (_q.trim().isNotEmpty) ...[
        Text('検索結果 ${hits.length}人', style: const TextStyle(fontSize: 12, color: _sub)),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Column(children: [
            for (final (p, t) in hits.take(60))
              PlayerRow(
                player: p,
                date: app.currentDate,
                sub: '${teamShort(t)}　${PlayerRow.defaultSub(p)}',
                onTap: () async {
                  await showPlayerDetail(context, app, p, allowActions: t.id == app.myTeamId, onChanged: () => setState(() {}));
                  if (mounted) setState(() {});
                },
              ),
          ]),
        ),
        const SizedBox(height: 14),
      ],
      for (final lg in const ['CL', 'PL']) ...[
        Padding(padding: const EdgeInsets.only(bottom: 6, top: 4), child: Text(leagueLabel(lg), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900))),
        for (final t in app.teams.where((t) => t.league == lg)) teamCard(t),
      ],
      const Padding(padding: EdgeInsets.only(top: 6), child: Text('球団をタップすると選手一覧（1軍・2軍・投手・野手）、選手をタップすると詳細を見られます。', style: TextStyle(fontSize: 11.5, color: _sub))),
    ]);
  }
}
