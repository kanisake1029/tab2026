import 'package:flutter/material.dart';
import '../../models/player.dart';
import '../../models/team.dart';
import '../../providers/app_state.dart';
import 'level_stats_tables.dart';
import 'game_roster_tab.dart';
import 'lineup_tab.dart';
import 'pitcher_tab.dart';
import 'third_order_tab.dart';

/// 1〜3軍のオーダー（同じ画面）
///  1軍：打順・投手・ベンチ・成績　2・3軍：打順・投手・成績（3軍の成績の下に「優先して出す」）
class LevelOrderTab extends StatefulWidget {
  final Team team;
  final AppState appState;
  final VoidCallback onChanged;
  final Map<String, Player> playerMap;
  final int level; // 1〜3
  final bool? oppLefty; // 1軍：相手先発が左投げか
  const LevelOrderTab({super.key, required this.team, required this.appState, required this.onChanged, required this.playerMap, required this.level, this.oppLefty});

  @override
  State<LevelOrderTab> createState() => _LevelOrderTabState();
}

class _LevelOrderTabState extends State<LevelOrderTab> {
  int _sub = 0;

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final labels = w.level == 1 ? const ['打順', '投手', 'ベンチ', '成績'] : const ['打順', '投手', '成績'];
    final sub = _sub.clamp(0, labels.length - 1);
    final Widget body;
    if (sub == 0) {
      body = LineupTab(key: ValueKey('l${w.level}'), team: w.team, appState: w.appState, onRosterChanged: w.onChanged, playerMap: w.playerMap, level: w.level, oppLefty: w.oppLefty);
    } else if (sub == 1) {
      body = PitcherTab(key: ValueKey('p${w.level}'), team: w.team, appState: w.appState, onRosterChanged: w.onChanged, playerMap: w.playerMap, level: w.level);
    } else if (w.level == 1 && sub == 2) {
      body = GameRosterTab(team: w.team, appState: w.appState, onRosterChanged: w.onChanged, playerMap: w.playerMap);
    } else {
      body = LevelStatsTables(
        key: ValueKey('s${w.level}'),
        team: w.team,
        appState: w.appState,
        level: w.level,
        extra: w.level == 3 ? ThirdOrderTab(team: w.team, appState: w.appState, onChanged: w.onChanged, priorityOnly: true) : null,
      );
    }
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
        child: Row(children: [
          Text('${w.level}軍', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
          const SizedBox(width: 10),
          Expanded(
            child: SegmentedButton<int>(
              segments: [for (var i = 0; i < labels.length; i++) ButtonSegment(value: i, label: Text(labels[i], style: const TextStyle(fontSize: 12.5)))],
              selected: {sub},
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                selectedBackgroundColor: const Color(0xFF1C1917),
                selectedForegroundColor: Colors.white,
              ),
              onSelectionChanged: (v) => setState(() => _sub = v.first),
            ),
          ),
        ]),
      ),
      Expanded(child: body),
    ]);
  }
}
