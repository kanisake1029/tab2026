import 'package:flutter/material.dart';
import '../models/player.dart';
import '../providers/app_state.dart';
import '../utils/standings.dart';
import '../widgets/frozen_table.dart';

const _ink = Color(0xFF1C1917);
const _sub = Color(0xFF78716C);
const _line = Color(0xFFE7E5E4);
const _bg = Color(0xFFF5F5F4);

/// 引退した選手（OB）の一覧。球団で絞り込み、タップで年度別成績と経歴
class ObListView extends StatefulWidget {
  final AppState app;
  const ObListView({super.key, required this.app});
  @override
  State<ObListView> createState() => _ObListViewState();
}

class _ObListViewState extends State<ObListView> {
  String _team = '';
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final list = app.retirees.where((e) => (_team.isEmpty || e['team'] == _team) && (_q.isEmpty || '${e['name']}'.contains(_q))).toList()
      ..sort((a, b) {
        final c = ((b['year'] ?? 0) as int).compareTo((a['year'] ?? 0) as int);
        return c != 0 ? c : ((PlayerStats.fromJson(Map<String, dynamic>.from(b['career'] as Map? ?? {})).games).compareTo(PlayerStats.fromJson(Map<String, dynamic>.from(a['career'] as Map? ?? {})).games));
      });
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
        child: Row(children: [
          Expanded(
            child: DropdownButton<String>(
              value: _team,
              isExpanded: true,
              items: [
                const DropdownMenuItem(value: '', child: Text('全球団')),
                for (final t in app.teams.where((t) => t.league == 'CL' || t.league == 'PL')) DropdownMenuItem(value: t.id, child: Text(t.name, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() => _team = v ?? ''),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 120,
            child: TextField(decoration: const InputDecoration(isDense: true, hintText: '名前で探す', prefixIcon: Icon(Icons.search, size: 18)), onChanged: (v) => setState(() => _q = v.trim())),
          ),
        ]),
      ),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text('引退した選手 ${list.length}人（新しい順）。タップで年度別成績と経歴', style: const TextStyle(fontSize: 11.5, color: _sub))),
      Expanded(
        child: list.isEmpty
            ? const Center(child: Text('引退した選手はまだいません', style: TextStyle(color: _sub)))
            : ListView(padding: const EdgeInsets.fromLTRB(8, 4, 8, 20), children: [
                for (final e in list)
                  InkWell(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ObDetailScreen(app: app, ob: e))),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
                      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _line))),
                      child: Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${e['name']}${e['hof'] == true ? '　★殿堂' : ''}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                            Text('${e['pos'] ?? ''}　${e['teamName'] ?? ''}　${e['year']}年引退（${e['age']}歳）', style: const TextStyle(fontSize: 11.5, color: _sub)),
                          ]),
                        ),
                        Text(_summary(e), style: const TextStyle(fontSize: 12, color: _ink)),
                        const Icon(Icons.chevron_right, size: 18, color: _sub),
                      ]),
                    ),
                  ),
              ]),
      ),
    ]);
  }

  static String _summary(Map<String, dynamic> e) {
    final c = PlayerStats.fromJson(Map<String, dynamic>.from(e['career'] as Map? ?? {}));
    if (e['pitcher'] == true) return '${c.apps}登板 ${c.wins}勝${c.saves > 0 ? ' ${c.saves}S' : ''}';
    return '${c.games}試合 ${c.hits}安打 ${c.homeRuns}本';
  }
}

/// OB の詳細：年度別成績（1軍）と経歴（年表）。能力は出さない
class ObDetailScreen extends StatelessWidget {
  final AppState app;
  final Map<String, dynamic> ob;
  const ObDetailScreen({super.key, required this.app, required this.ob});

  @override
  Widget build(BuildContext context) {
    final id = '${ob['id']}';
    final pitcher = ob['pitcher'] == true;
    final career = PlayerStats.fromJson(Map<String, dynamic>.from(ob['career'] as Map? ?? {}));
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(title: Text('${ob['name']}（OB）')),
      body: FutureBuilder<(List<(int, String, PlayerStats, PlayerStats)>, List<(DateTime, String)>)>(
        future: () async {
          final h = await app.playerHistory(id);
          final tl = await app.timelineOf(id, draftInfo: '${ob['draftInfo'] ?? ''}', moves: List<String>.from(ob['moves'] as List? ?? const []), honors: List<String>.from(ob['honors'] as List? ?? const []), firstTeam: app.teamById('${ob['team']}'));
          return (h, tl);
        }(),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final (hist, tl) = snap.data!;
          // 年度別の記録がある分と、通算との差（記録を始める前）
          final known = PlayerStats();
          for (final h in hist) {
            known.add(h.$3);
          }
          final rows = <(String, String, PlayerStats)>[];
          if (career.games > known.games) rows.add(('〜${hist.isEmpty ? ob['year'] : hist.first.$1 - 1}', '', _minus(career, known)));
          for (final h in hist) {
            if (h.$3.games + h.$3.pitchApps > 0) rows.add(('${h.$1}', _teamName(h.$2), h.$3));
          }
          rows.add(('通算', '', career));
          final honors = [for (final h in List<String>.from(ob['honors'] as List? ?? const [])) if (RegExp(r'^\d{4}年 ').hasMatch(h) && !h.contains('達成')) h];
          return ListView(padding: const EdgeInsets.fromLTRB(10, 10, 10, 30), children: [
            Text('${ob['pos'] ?? ''}　最終所属 ${ob['teamName'] ?? ''}　${ob['year']}年に${ob['age']}歳で引退${ob['proYears'] != null ? '（プロ${ob['proYears']}年）' : ''}${ob['uniform'] != null ? '　背番号${ob['uniform']}' : ''}',
                style: const TextStyle(fontSize: 12.5)),
            if ('${ob['draftInfo'] ?? ''}'.isNotEmpty) Text('入団：${ob['draftInfo']}', style: const TextStyle(fontSize: 12, color: _sub)),
            const SizedBox(height: 10),
            _h('年度別成績（1軍）'),
            _table(pitcher, rows),
            const Text('「〜年」は年度別の記録を始める前の分（通算との差）です', style: TextStyle(fontSize: 10.5, color: _sub)),
            if (honors.isNotEmpty) ...[
              const SizedBox(height: 10),
              _h('タイトル・表彰'),
              Wrap(spacing: 6, runSpacing: 4, children: [for (final h in honors) Chip(label: Text(h, style: const TextStyle(fontSize: 11)), visualDensity: VisualDensity.compact)]),
            ],
            const SizedBox(height: 10),
            _h('経歴'),
            if (tl.isEmpty) const Text('経歴の記録がありません', style: TextStyle(color: _sub, fontSize: 12.5)),
            for (final x in tl) timelineLine(x.$1, x.$2),
          ]);
        },
      ),
    );
  }

  String _teamName(String ids) => ids.split('/').map((id) {
        final t = app.teamById(id);
        return t == null ? '−' : teamShort(t);
      }).join('/');

  static PlayerStats _minus(PlayerStats a, PlayerStats b) {
    final ja = a.toJson(), jb = b.toJson();
    return PlayerStats.fromJson({
      for (final e in ja.entries)
        if (e.value is int) e.key: ((e.value as int) - ((jb[e.key] ?? 0) as int)).clamp(0, 1 << 30),
    });
  }

  Widget _h(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [Container(width: 3, height: 14, color: _ink), const SizedBox(width: 6), Text(s, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900))]),
      );

  Widget _table(bool pitcher, List<(String, String, PlayerStats)> rows) {
    final cols = pitcher
        ? const <(String, double)>[('登板', 38), ('先発', 38), ('勝', 32), ('敗', 32), ('S', 30), ('H', 30), ('投球回', 52), ('奪三振', 46), ('防御率', 50)]
        : const <(String, double)>[('試合', 38), ('打数', 42), ('安打', 40), ('本', 32), ('打点', 38), ('盗塁', 38), ('打率', 46)];
    List<String> cells(PlayerStats s) => pitcher
        ? ['${s.apps}', '${s.starts}', '${s.wins}', '${s.losses}', '${s.saves}', '${s.holds}', '${s.inningsPitched ~/ 3}${s.inningsPitched % 3 == 0 ? '' : '.${s.inningsPitched % 3}'}', '${s.pitcherStrikeouts}', s.inningsPitched == 0 ? '-' : s.era.toStringAsFixed(2)]
        : ['${s.games}', '${s.atBats}', '${s.hits}', '${s.homeRuns}', '${s.rbi}', '${s.stolenBases}', s.atBats == 0 ? '-' : s.battingAverage.toStringAsFixed(3).replaceFirst(RegExp(r'^0'), '')];
    return FrozenTable(
      leadHeader: '年度・球団',
      leadWidth: 104,
      headers: [for (final c in cols) c.$1],
      widths: [for (final c in cols) c.$2],
      rowHeight: 28,
      rows: [
        for (final r in rows)
          FrozenRow(
            color: r.$1 == '通算' ? const Color(0xFFFEF9C3) : null,
            lead: Text('${r.$1} ${r.$2}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
            cells: cells(r.$3),
          ),
      ],
    );
  }
}

/// 年表の1行「26/10/31 高卒ドラフト7位で東新に入団。」（日付の分からない推定の行は 23:59 にして「26年」と出す）
Widget timelineLine(DateTime d, String text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 62, child: Text(d.hour == 23 && d.minute == 59 ? '${(d.year % 100).toString().padLeft(2, '0')}年' : '${(d.year % 100).toString().padLeft(2, '0')}/${d.month}/${d.day}', style: const TextStyle(fontSize: 12, color: _sub, fontFeatures: [FontFeature.tabularFigures()]))),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 12.5, height: 1.4))),
      ]),
    );
