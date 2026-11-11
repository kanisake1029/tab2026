import '../../widgets/chip_grid.dart';
import '../number_board_screen.dart';
import 'package:flutter/material.dart';
import '../../models/player.dart';
import '../../models/team.dart';
import '../../providers/app_state.dart';
import '../../utils/salary_utils.dart';
import 'order_shared.dart';
import '../../widgets/player_row.dart';
import '../../widgets/player_detail_dialog.dart';

class AllPlayersTab extends StatefulWidget {
  final Team team;
  final AppState appState;
  final VoidCallback onRosterChanged;

  const AllPlayersTab({
    super.key,
    required this.team,
    required this.appState,
    required this.onRosterChanged,
  });

  @override
  State<AllPlayersTab> createState() => _AllPlayersTabState();
}

class _AllPlayersTabState extends State<AllPlayersTab> {
  bool _ikusei = false; // 支配下 / 育成
  String _group = '投手'; // 投手 / 捕手 / 内野手 / 外野手

  static const _groups = ['投手', '捕手', '内野手', '外野手'];
  static String groupOf(Player p) {
    if (p.isPitcher) return '投手';
    final m = p.mainPosition;
    if (m == '捕手') return '捕手';
    if (m == '左翼手' || m == '中堅手' || m == '右翼手') return '外野手';
    return '内野手';
  }


  @override
  Widget build(BuildContext context) {
    Team team = widget.team;
    final pool = team.players.where((p) => p.ikusei == _ikusei).toList();
    final counts = {for (final g in _groups) g: pool.where((p) => groupOf(p) == g).length};
    List<Player> filtered = pool.where((p) => groupOf(p) == _group).toList();
    filtered.sort((a, b) {
      bool a1G = team.roster1G.contains(a.id);
      bool b1G = team.roster1G.contains(b.id);
      if (a1G && !b1G) return -1;
      if (!a1G && b1G) return 1;
      return compareByUniform(a, b);
    });

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 2),
          child: Wrap(
            spacing: 12,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('全${team.players.length}人（1軍${team.roster1G.length}人・2軍${team.players.length - team.roster1G.length}人／支配下${team.players.where((p) => !p.ikusei).length}・育成${team.players.where((p) => p.ikusei).length}）', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
                Text('年俸総額 ${formatSalary(team.players.fold<int>(0, (s, p) => s + p.salary))}（1軍 ${formatSalary(team.players.where((p) => team.roster1G.contains(p.id)).fold<int>(0, (s, p) => s + p.salary))}）', style: const TextStyle(fontSize: 10.5, color: Color(0xFF78716C))),
              ]),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                icon: const Icon(Icons.format_list_numbered, size: 16),
                label: const Text('背番号'),
                onPressed: () async {
                  final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => NumberBoardScreen(app: widget.appState, team: team)));
                  if (ok == true && mounted) {
                    setState(() {});
                    widget.onRosterChanged();
                  }
                },
              ),
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(value: false, label: Text('支配下 ${team.players.where((p) => !p.ikusei).length}')),
                  ButtonSegment(value: true, label: Text('育成 ${team.players.where((p) => p.ikusei).length}')),
                ],
                selected: {_ikusei},
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(visualDensity: const VisualDensity(horizontal: -3, vertical: -4), textStyle: const TextStyle(fontSize: 12), tapTargetSize: MaterialTapTargetSize.shrinkWrap, selectedBackgroundColor: const Color(0xFF1C1917), selectedForegroundColor: Colors.white),
                onSelectionChanged: (v) => setState(() => _ikusei = v.first),
              ),
              SizedBox(
                width: 320,
                child: ChipGrid<String>(items: [for (final g in _groups) (g, '$g ${counts[g]}')], selected: _group, minWidth: 70, padding: EdgeInsets.zero, onSelect: (g) => setState(() => _group = g)),
              ),
            ],
          ),
        ),
        const Padding(padding: EdgeInsets.fromLTRB(10, 0, 10, 2), child: Text('タップで能力、ダブルタップで詳細（昇格・降格は詳細の下、登録名・背番号・ポジションは詳細の名前を押して）', style: TextStyle(fontSize: 10, color: Color(0xFF78716C)))),
        Expanded(
          child: playerRowList(rowHeight: 34, rows: [
            for (final p in filtered)
              orderPlayerRow(context, p, widget.appState, team, () {
                setState(() {});
                widget.appState.updateAndSave();
                widget.onRosterChanged();
              },
                  dim: !team.roster1G.contains(p.id),
                  compact: true,
                  leading: SizedBox(width: 34, child: Text('#${p.uniformText}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900))),
                  tags: [
                    PlayerRow.tag(team.roster1G.contains(p.id) ? '1軍' : (p.ikusei ? '育成' : '2軍'), team.roster1G.contains(p.id) ? Colors.blue : (p.ikusei ? const Color(0xFFB45309) : Colors.grey)),
                    if (p.foreignSlot) PlayerRow.tag('外', const Color(0xFF0F766E)),
                  ],
                  right: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                    PlayerRow.grade(p.ovr, size: 12),
                    Text(formatSalary(p.salary), style: const TextStyle(fontSize: 9.5, color: PlayerRow.subColor)),
                  ])),
          ]),
        ),
      ],
    );
  }
}

class PlayerDetailDialogWrapper extends StatelessWidget {
  final Player player;
  final dynamic appState;
  final Team team;
  final VoidCallback onRosterChanged;

  const PlayerDetailDialogWrapper({super.key, required this.player, required this.appState, required this.team, required this.onRosterChanged});

  @override
  Widget build(BuildContext context) {
    return PlayerDetailDialog(
      player: player,
      appState: appState,
      isReadOnly: true,
      team: team,
      onRosterChanged: onRosterChanged,
    );
  }
}
