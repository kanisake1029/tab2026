import 'package:flutter/material.dart';
import '../models/player.dart';
import '../models/team.dart';
import '../providers/app_state.dart';
import '../utils/standings.dart';

import 'order_tabs/all_players_tab.dart';
import 'order_tabs/level_order_tab.dart';
import 'order_tabs/order_shared.dart';
import '../widgets/player_quick_panel.dart';
import 'team_roster_screen.dart';

/// オーダー（デザイン案B：データ表＋右パネル）
///  見出しに次の試合の相手と相手先発（左右）を出し、タブはスタメン／投手／ベンチ入り／全選手
class OrderScreen extends StatefulWidget {
  final AppState appState;
  const OrderScreen({super.key, required this.appState});

  @override
  State<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends State<OrderScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late Map<String, Player> playerMap;

  static const _tabLabels = ['1軍', '2軍', '3軍', '全選手'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _triggerRebuild() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.appState;
    Team myTeam = app.teams.firstWhere((t) => t.id == app.myTeamId, orElse: () => app.teams.first);
    playerMap = { for (var p in myTeam.players) p.id: p };

    // 次の試合（今日以降で最初の自チームの試合）と相手先発
    final next = app.matches
        .where((m) => !m.isPlayed && (m.homeTeamId == myTeam.id || m.awayTeamId == myTeam.id) && !m.date.isBefore(DateUtils.dateOnly(app.currentDate)))
        .firstOrNull;
    Team? opp;
    Player? oppSp;
    if (next != null) {
      final oppId = next.homeTeamId == myTeam.id ? next.awayTeamId : next.homeTeamId;
      opp = app.teams.where((t) => t.id == oppId).firstOrNull;
      final spId = opp?.todaysStarterId;
      if (spId != null) oppSp = opp!.players.where((p) => p.id == spId).firstOrNull;
    }
    final isToday = next != null && DateUtils.isSameDay(next.date, app.currentDate);
    const dows = ['月', '火', '水', '木', '金', '土', '日'];
    String sub = '次の試合はありません';
    if (next != null && opp != null) {
      sub = '${next.date.month}/${next.date.day}（${dows[next.date.weekday - 1]}）${next.homeTeamId == myTeam.id ? 'vs' : '@'} ${teamShort(opp)}';
      if (isToday && oppSp != null) sub += '　相手先発 ${oppSp.listName}（${oppSp.throws == 'L' ? '左' : '右'}）';
    }
    final oppLefty = isToday && oppSp != null ? oppSp.throws == 'L' : null;
    // 次の相手の情報。タップで相手チームの選手一覧（選手の詳細まで見られる）
    Widget subLine(TextStyle style, {int? maxLines}) {
      final text = Text(sub, maxLines: maxLines, overflow: maxLines == null ? null : TextOverflow.ellipsis, style: style);
      if (opp == null) return text;
      final o = opp;
      return InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TeamRosterScreen(appState: app, team: o))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [Flexible(child: text), Text('　相手を見る ›', style: style.copyWith(color: const Color(0xFF2563EB)))]),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: LayoutBuilder(builder: (context, c) {
          final wide = c.maxWidth >= 760;
          final header = Padding(
            padding: EdgeInsets.fromLTRB(wide ? 24 : 10, wide ? 14 : 6, wide ? 24 : 10, 0),
            child: Container(
              padding: EdgeInsets.only(bottom: wide ? 10 : 6),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: const Color(0xFF1C1917), width: wide ? 2 : 1))),
              child: !wide
                  ? subLine(const TextStyle(fontSize: 11.5, color: Color(0xFF57534E)), maxLines: 1)
                  : Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.end,
                spacing: 16,
                runSpacing: 10,
                children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    subLine(const TextStyle(fontSize: 12, letterSpacing: 1.5, color: Color(0xFF78716C))),
                    Text('${myTeam.name}　オーダー', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                  ]),
                  SegmentedButton<int>(
                    segments: [for (int i = 0; i < _tabLabels.length; i++) ButtonSegment(value: i, label: Text(_tabLabels[i], maxLines: 1, softWrap: false, style: TextStyle(fontSize: wide ? 14 : 12)))],
                    selected: {_tabController.index},
                    showSelectedIcon: false,
                    style: SegmentedButton.styleFrom(
                      selectedBackgroundColor: const Color(0xFF1C1917),
                      selectedForegroundColor: Colors.white,
                      shape: const RoundedRectangleBorder(),
                      side: const BorderSide(color: Color(0xFF1C1917)),
                      visualDensity: VisualDensity.compact,
                    ),
                    onSelectionChanged: (v) => _tabController.animateTo(v.first),
                  ),
                ],
              ),
            ),
          );
          final tabs = TabBarView(
            controller: _tabController,
            physics: const NeverScrollableScrollPhysics(), // ドラッグ操作と横スワイプがぶつからないように
            children: [
              LevelOrderTab(team: myTeam, appState: app, onChanged: _triggerRebuild, playerMap: playerMap, level: 1, oppLefty: oppLefty),
              LevelOrderTab(team: myTeam, appState: app, onChanged: _triggerRebuild, playerMap: playerMap, level: 2),
              LevelOrderTab(team: myTeam, appState: app, onChanged: _triggerRebuild, playerMap: playerMap, level: 3),
              AllPlayersTab(team: myTeam, appState: app, onRosterChanged: _triggerRebuild),
            ],
          );
          final panel = PlayerQuickPanel(selection: selectedOrderPlayer, appState: app, team: myTeam, onChanged: _triggerRebuild, horizontal: !wide);
          final body = wide
              ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Expanded(child: tabs),
                  Container(width: 290, decoration: const BoxDecoration(border: Border(left: BorderSide(color: Color(0xFFE7E5E4)))), child: panel),
                ])
              : Column(children: [
                  Expanded(child: tabs),
                  // スマホ：スタメン・投手…の切り替えは画面の下（親指の届く所）
                  Container(
                    margin: const EdgeInsets.fromLTRB(10, 2, 10, 2),
                    height: 28,
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(color: const Color(0xFF1C1917), borderRadius: BorderRadius.circular(8)),
                    child: AnimatedBuilder(
                      animation: _tabController,
                      builder: (context, _) => Row(children: [
                        for (var i = 0; i < _tabLabels.length; i++)
                          Expanded(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(6),
                              onTap: () => setState(() => _tabController.index = i),
                              child: Container(
                                alignment: Alignment.center,
                                decoration: BoxDecoration(color: _tabController.index == i ? Colors.white : Colors.transparent, borderRadius: BorderRadius.circular(6)),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(_tabLabels[i],
                                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _tabController.index == i ? const Color(0xFF1C1917) : const Color(0xFFD6D3D1))),
                                ),
                              ),
                            ),
                          ),
                      ]),
                    ),
                  ),
                  // 狭い画面：選手を選んだときだけ、下に能力の簡易パネルを出す（×で閉じる）
                  ValueListenableBuilder<Player?>(
                    valueListenable: selectedOrderPlayer,
                    builder: (context, sel, _) => sel == null
                        ? const SizedBox.shrink()
                        : SizedBox(
                            height: 128,
                            child: Column(children: [
                              Container(
                                height: 18,
                                color: const Color(0xFFF1F5F9),
                                padding: const EdgeInsets.only(left: 12),
                                child: Row(children: [
                                  const Expanded(child: Text('選んだ選手の能力', style: TextStyle(fontSize: 10, color: Color(0xFF64748B)))),
                                  IconButton(tooltip: '閉じる', padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 28, minHeight: 18), iconSize: 15, icon: const Icon(Icons.close), onPressed: () => selectedOrderPlayer.value = null),
                                ]),
                              ),
                              Expanded(child: panel),
                            ]),
                          ),
                  ),
                ]);
          return Column(children: [header, Expanded(child: body)]);
        }),
      ),
    );
  }
}
