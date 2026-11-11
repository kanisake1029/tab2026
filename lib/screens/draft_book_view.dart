import 'package:flutter/material.dart';
import '../models/player.dart';
import '../models/team.dart';
import '../providers/app_state.dart';
import '../utils/standings.dart';
import '../widgets/chip_grid.dart';
import '../widgets/player_detail_dialog.dart' show showPlayerDetail;
import '../widgets/player_quick_panel.dart';

const _sub = Color(0xFF64748B);
const _line = Color(0xFFE2E8F0);

/// ドラフトの指名の記録：年ごと・球団ごと。押すと下に能力、もう一度押す（詳細ボタン）で詳しい画面
class DraftBookView extends StatefulWidget {
  final AppState app;
  const DraftBookView({super.key, required this.app});

  @override
  State<DraftBookView> createState() => _DraftBookViewState();
}

class _DraftBookViewState extends State<DraftBookView> {
  int? _year;
  String _team = '';
  final _sel = ValueNotifier<Player?>(null);
  Team? _selTeam;
  String? _selKey;
  AppState get app => widget.app;

  @override
  void dispose() {
    _sel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final years = app.draftBook.keys.toList()..sort((a, b) => b.compareTo(a));
    if (years.isEmpty) {
      return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('まだドラフトの記録はありません（ドラフトを行うと残ります）', textAlign: TextAlign.center, style: TextStyle(color: _sub))));
    }
    final y = _year != null && years.contains(_year) ? _year! : years.first;
    final all = app.draftBook[y]!;
    final teamIds = <String>[for (final e in all) e['team'] as String].toSet().toList();
    final teams = [for (final t in app.teams) if (teamIds.contains(t.id)) t];
    final list = all.where((e) => _team.isEmpty || e['team'] == _team).toList();
    // 球団ごと（自球団を先頭）に、順位の順で
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final e in list) {
      (groups[e['team'] as String] ??= []).add(e);
    }
    final order = groups.keys.toList()..sort((a, b) => a == app.myTeamId ? -1 : (b == app.myTeamId ? 1 : teamIds.indexOf(a).compareTo(teamIds.indexOf(b))));

    return Column(children: [
      Container(
        color: Colors.white,
        child: Column(children: [
          YearStepper(years: years, selected: y, label: (v) => '$v年ドラフト', onSelect: (v) => setState(() => _year = v)),
          ChipGrid<String>(items: [('', '全球団'), for (final t in teams) (t.id, teamShort(t))], selected: _team, minWidth: 56, onSelect: (v) => setState(() => _team = v)),
        ]),
      ),
      Expanded(
        child: ListView(padding: const EdgeInsets.only(bottom: 12), children: [
          for (final tid in order) ...[
            Builder(builder: (_) {
              final t = app.teamById(tid);
              return Container(
                color: const Color(0xFFF1F5F9),
                padding: const EdgeInsets.fromLTRB(10, 5, 10, 5),
                child: Row(children: [
                  Container(width: 4, height: 14, color: t == null ? _sub : teamColor(app.teams, t)),
                  const SizedBox(width: 6),
                  Text(t == null ? tid : teamShort(t), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
                  if (tid == app.myTeamId) const Text('　自球団', style: TextStyle(fontSize: 11, color: Color(0xFFB45309), fontWeight: FontWeight.w800)),
                  const Spacer(),
                  Text('${groups[tid]!.length}人', style: const TextStyle(fontSize: 11, color: _sub)),
                ]),
              );
            }),
            for (final e in groups[tid]!) _row(e),
          ],
        ]),
      ),
      // 能力バー（押した選手）
      if (_selKey != null && _selTeam != null)
        SizedBox(height: 132, child: PlayerQuickPanel(selection: _sel, appState: app, team: _selTeam!, onChanged: () => setState(() {}), horizontal: true)),
    ]);
  }

  Widget _row(Map<String, dynamic> e) {
    final (p, now) = app.draftBookPlayer(e);
    final key = '${e['id']}_${e['label']}_${e['team']}';
    final sel = key == _selKey;
    final gone = now == null;
    final status = p == null
        ? '記録のみ'
        : gone
            ? '退団'
            : now.id != e['team']
                ? '現在 ${teamShort(now)}'
                : (p.ikusei ? '育成' : (now.roster1G.contains(p.id) ? '1軍' : '2軍'));
    return InkWell(
      onTap: p == null
          ? null
          : () {
              if (sel) {
                showPlayerDetail(context, app, p, allowActions: now?.id == app.myTeamId);
                return;
              }
              setState(() {
                _selKey = key;
                _selTeam = now ?? app.teamById(e['team'] as String);
                _sel.value = p;
              });
            },
      onDoubleTap: p == null ? null : () => showPlayerDetail(context, app, p, allowActions: now?.id == app.myTeamId),
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 5, 10, 5),
        decoration: BoxDecoration(color: sel ? const Color(0xFFFEF3C7) : Colors.white, border: const Border(bottom: BorderSide(color: _line))),
        child: Row(children: [
          SizedBox(
            width: 52,
            child: Text('${e['label']}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: (e['ikusei'] == true) ? _sub : const Color(0xFF0F172A))),
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text('${e['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800))),
                const SizedBox(width: 6),
                Text('${e['pos']}', style: const TextStyle(fontSize: 11.5, color: _sub)),
                if (e['lottery'] == true) ...[
                  const SizedBox(width: 4),
                  Container(padding: const EdgeInsets.symmetric(horizontal: 4), decoration: BoxDecoration(color: const Color(0xFFFEE2E2), borderRadius: BorderRadius.circular(3)), child: const Text('抽選', style: TextStyle(fontSize: 9.5, color: Color(0xFFB91C1C), fontWeight: FontWeight.w800))),
                ],
              ]),
              Text('${e['cat']}・${e['school']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, color: _sub)),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(color: gone ? const Color(0xFFF1F5F9) : const Color(0xFFE0F2FE), borderRadius: BorderRadius.circular(4)),
            child: Text(status, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: gone ? _sub : const Color(0xFF0369A1))),
          ),
        ]),
      ),
    );
  }
}
