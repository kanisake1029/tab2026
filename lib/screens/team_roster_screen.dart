import 'package:flutter/material.dart';
import '../models/player.dart';
import '../models/team.dart';
import '../utils/salary_utils.dart';
import '../utils/standings.dart';
import '../widgets/player_detail_dialog.dart' show showPlayerDetail;
import '../widgets/player_row.dart';

/// 球団の選手一覧（閲覧用。他球団も見られる）。共通の1行で並べ、タップで選手の詳細
class TeamRosterScreen extends StatefulWidget {
  final dynamic appState;
  final Team team;
  const TeamRosterScreen({super.key, required this.appState, required this.team});

  @override
  State<TeamRosterScreen> createState() => _TeamRosterScreenState();
}

class _TeamRosterScreenState extends State<TeamRosterScreen> {
  String _filter = '1軍';

  @override
  Widget build(BuildContext context) {
    final t = widget.team;
    var list = t.players.toList();
    switch (_filter) {
      case '1軍':
        list = list.where((p) => t.roster1G.contains(p.id)).toList();
      case '2軍':
        list = list.where((p) => !t.roster1G.contains(p.id)).toList();
      case '野手':
        list = list.where((p) => !p.isPitcher).toList();
      case '投手':
        list = list.where((p) => p.isPitcher).toList();
    }
    // 1軍はスタメン→先発→その他の順、ほかは投手・野手→背番号
    final lineup = t.lineup.map((l) => l.playerId).toList();
    int key(Player p) {
      final li = lineup.indexOf(p.id);
      if (li >= 0) return li;
      final ri = t.activeRotation.indexOf(p.id);
      if (ri >= 0) return 20 + ri;
      return p.isPitcher ? 40 : 60;
    }
    list.sort((a, b) {
      final c = key(a).compareTo(key(b));
      return c != 0 ? c : compareByUniform(a, b);
    });
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: Text(t.name, overflow: TextOverflow.ellipsis), backgroundColor: Colors.white, foregroundColor: const Color(0xFF111827), elevation: 0),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${leagueLabel(t.league)}　${t.wins}勝${t.losses}敗${t.draws}分　選手${t.players.length}人　年俸総額 ${formatSalary(t.players.fold<int>(0, (s, p) => s + p.salary))}',
                style: const TextStyle(fontSize: 12, color: PlayerRow.subColor)),
            const SizedBox(height: 4),
            Wrap(spacing: 6, children: [
              for (final f in const ['1軍', '2軍', '野手', '投手'])
                ChoiceChip(label: Text(f), selected: _filter == f, visualDensity: VisualDensity.compact, onSelected: (_) => setState(() => _filter = f)),
            ]),
          ]),
        ),
        Expanded(
          child: ListView(children: [
            for (final p in list)
              PlayerRow(
                player: p,
                date: widget.appState.currentDate as DateTime,
                leading: SizedBox(
                  width: 30,
                  child: Text(
                    lineup.contains(p.id) ? '${lineup.indexOf(p.id) + 1}番' : (t.activeRotation.contains(p.id) ? '先発' : p.uniformText),
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ),
                dim: !t.roster1G.contains(p.id),
                onTap: () => showPlayerDetail(context, widget.appState, p).then((_) => setState(() {})),
              ),
            const Padding(padding: EdgeInsets.all(12), child: Text('タップで選手の詳細', style: TextStyle(fontSize: 11, color: PlayerRow.subColor))),
          ]),
        ),
      ]),
    );
  }
}
