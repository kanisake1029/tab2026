import '../widgets/chip_grid.dart';
import 'package:flutter/material.dart';

import '../models/team.dart';
import '../providers/app_state.dart';
import '../utils/standings.dart';
import 'all_teams_tab.dart';
import 'camp_screen.dart';
import 'finance_screens.dart';
import 'front_screens.dart';
import 'office_screen.dart';
import 'league_rules_screen.dart';
import 'order_screen.dart';
import 'records_screen.dart';
import 'reinforce_screens.dart';
import 'scorer_tab.dart';

const _ink = Color(0xFF1C1917);
const _sub = Color(0xFF78716C);
const _bg = Color(0xFFF5F5F4);

/// 下のタブの 1 つ（上に見出しと横のタブ。中身は既存の画面をそのまま並べる）
class _Hub extends StatefulWidget {
  final AppState app;
  final String title;
  final List<(String, Widget Function(Team))> tabs;
  const _Hub({required this.app, required this.title, required this.tabs});
  @override
  State<_Hub> createState() => _HubState();
}

class _HubState extends State<_Hub> with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: widget.tabs.length, vsync: this);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final team = app.teams.where((t) => t.id == app.myTeamId).firstOrNull ?? app.teams.first;
    final narrow = MediaQuery.of(context).size.width < 600;
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(children: [
          Container(
            color: Colors.white,
            padding: EdgeInsets.fromLTRB(narrow ? 6 : 16, narrow ? 2 : 12, narrow ? 6 : 16, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (!narrow) Text('${teamShort(team)}　${widget.title}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              TabGrid(controller: _tab, labels: [for (final t in widget.tabs) t.$1], minWidth: narrow ? 76 : 110, padding: const EdgeInsets.symmetric(vertical: 6)),
            ]),
          ),
          // 中の操作（保存）で画面を描き直す
          // タブを替えて戻っても、スクロールの位置を覚えておく
          Expanded(child: ListenableBuilder(listenable: app, builder: (context, _) => TabBarView(controller: _tab, children: [for (final t in widget.tabs) KeyedSubtree(key: PageStorageKey('${widget.title}_${t.$1}'), child: t.$2(team))]))),
        ]),
      ),
    );
  }
}

/// 『チーム』（現場の管理）：オーダー（スタメン・投手・ベンチ・全選手・2軍・3軍）、コーチ、キャンプ（練習メニュー・改造の提案）、面談
class TeamHubScreen extends StatelessWidget {
  final AppState appState;
  const TeamHubScreen({super.key, required this.appState});
  @override
  Widget build(BuildContext context) => _Hub(app: appState, title: 'チーム', tabs: [
        ('オーダー', (_) => OrderScreen(appState: appState)),
        ('コーチ', (t) => CoachTab(app: appState, team: t, onChanged: () {})),
        ('キャンプ・練習', (t) => CampTab(app: appState, team: t, onChanged: () {})),
        ('面談・イベント', (_) => const _Soon('面談・イベント', '選手との面談（信頼・モチベーションが変わる）、チームのイベント')),
      ]);
}

/// 『フロント』（GM・経営）：補強、経営（収支・チケット・スポンサー・グッズ）、施設・球場の改修、メーカー契約、オーナー
class FrontHubScreen extends StatelessWidget {
  final AppState appState;
  const FrontHubScreen({super.key, required this.appState});
  @override
  Widget build(BuildContext context) => _Hub(app: appState, title: 'フロント', tabs: [
        ('補強', (t) => ReinforceTab(app: appState, team: t, onChanged: () {})),
        ('経営', (t) => FinanceTab(app: appState, team: t)),
        ('施設・球場', (t) => FacilityTab(app: appState, team: t)),
        ('メーカー', (t) => MakerTab(app: appState, team: t)),
        ('オーナー', (t) => OwnerTab(app: appState, team: t)),
        ('リーグ規定', (_) => LeagueRulesPanel(app: appState)),
      ]);
}

/// 『データ』（記録・分析）：スコアラー、記録（個人・チーム・歴代・球団史）、全球団の選手
class DataHubScreen extends StatelessWidget {
  final AppState appState;
  const DataHubScreen({super.key, required this.appState});
  @override
  Widget build(BuildContext context) => _Hub(app: appState, title: 'データ', tabs: [
        ('スコアラー', (t) => ScorerTab(app: appState, team: t)),
        ('記録', (_) => RecordsTab(app: appState)),
        ('全球団選手', (_) => AllTeamsTab(app: appState)),
      ]);
}

class _Soon extends StatelessWidget {
  final String title, body;
  const _Soon(this.title, this.body);
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text(body, textAlign: TextAlign.center, style: const TextStyle(color: _sub, height: 1.6)),
            const SizedBox(height: 8),
            const Text('準備中', style: TextStyle(color: _sub, fontSize: 12)),
          ]),
        ),
      );
}
