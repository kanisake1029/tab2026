import '../widgets/chip_grid.dart';
import 'package:flutter/material.dart';
import '../utils/player_generator.dart';
import '../utils/standings.dart';
import '../providers/app_state.dart';
import '../models/team.dart';
import 'team_editor_screen.dart';

const _ink = Color(0xFF1C1917);
const _sub = Color(0xFF78716C);
const _line = Color(0xFFE7E5E4);

/// 初期選手編集：球団を選ぶ画面。年度のタグで絞り、Aリーグ・Bリーグ・未所属に分けて並べる
class EditorScreen extends StatefulWidget {
  final AppState appState;
  /// 設定・編集メニューの右側に埋め込むときは true（戻るボタンを出さない）
  final bool embedded;
  const EditorScreen({Key? key, required this.appState, this.embedded = false}) : super(key: key);

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  int _selectedYear = 2026;
  String _query = '';

  AppState get app => widget.appState;

  @override
  void initState() {
    super.initState();
    if (app.teams.isNotEmpty) _selectedYear = app.teams.first.year;
  }

  Future<void> _open(Team team) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => TeamEditorScreen(appState: app, team: team)));
    if (mounted) setState(() {});
  }

  void _create() {
    setState(() {
      final t = generateNewTeam(year: _selectedYear);
      app.teams.add(t);
      app.updateAndSave();
      app.saveInitialState(t); // 作ったときの状態を「初期状態」に（新しいデータはこの状態から）
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('新しい球団を作りました（未所属。リーグ編成で枠に入れられます）。いまの状態が「初期状態」です')));
  }

  void _delete(Team team) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('球団を削除'),
        content: Text('${team.name} を削除しますか？（選手も消えます）'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('やめる')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              setState(() {
                app.teams.remove(team);
                app.updateAndSave();
                if (team.id.startsWith('T_')) app.removeInitialState(team.id); // 新しいデータにも出さない
              });
              Navigator.of(ctx).pop();
            },
            child: const Text('削除する'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (app.teams.isEmpty) return const Center(child: CircularProgressIndicator());
    for (final t in app.teams) {
      if (t.year <= 0) t.year = 0;
    }
    final years = app.teams.map((t) => t.year).toSet().toList()..sort();
    if (!years.contains(_selectedYear) && years.isNotEmpty) _selectedYear = years.first;
    final q = _query.trim();
    final inYear = app.teams.where((t) => t.year == _selectedYear && (q.isEmpty || t.name.contains(q) || t.shortName.contains(q))).toList();
    final groups = <(String, Color, List<Team>)>[
      ('Aリーグ', const Color(0xFF16A34A), inYear.where((t) => t.league == 'CL').toList()),
      ('Bリーグ', const Color(0xFF2563EB), inYear.where((t) => t.league == 'PL').toList()),
      ('未所属', const Color(0xFF78716C), inYear.where((t) => t.league != 'CL' && t.league != 'PL').toList()),
    ];
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F4),
      appBar: AppBar(
        title: const Text('初期選手編集：球団を選ぶ'),
        automaticallyImplyLeading: !widget.embedded,
      ),
      floatingActionButton: FloatingActionButton.extended(onPressed: _create, icon: const Icon(Icons.add), label: const Text('新しい球団')),
      body: Column(children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ChipGrid<int>(items: [for (final y in years) (y, y == 0 ? 'タグなし' : '$y年')], selected: _selectedYear, minWidth: 72, padding: EdgeInsets.zero, onSelect: (y) => setState(() => _selectedYear = y)),
            const SizedBox(height: 6),
            TextField(
              decoration: const InputDecoration(isDense: true, prefixIcon: Icon(Icons.search, size: 20), hintText: '球団名で探す', border: OutlineInputBorder()),
              onChanged: (s) => setState(() => _query = s),
            ),
          ]),
        ),
        Expanded(
          child: ListView(padding: const EdgeInsets.fromLTRB(10, 8, 10, 90), children: [
            for (final (title, color, ts) in groups)
              if (ts.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
                  child: Row(children: [
                    Container(width: 4, height: 16, color: color),
                    const SizedBox(width: 6),
                    Text('$title（${ts.length}球団）', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5)),
                  ]),
                ),
                LayoutBuilder(builder: (context, c) {
                  final cols = (c.maxWidth / 330).floor().clamp(1, 4);
                  final w = (c.maxWidth - (cols - 1) * 8) / cols;
                  return Wrap(spacing: 8, runSpacing: 8, children: [for (final t in ts) SizedBox(width: w, child: _card(t))]);
                }),
              ],
            if (inYear.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('この年度の球団はありません', textAlign: TextAlign.center, style: TextStyle(color: _sub))),
          ]),
        ),
      ]),
    );
  }

  Widget _card(Team t) {
    final shi = t.players.where((p) => !p.ikusei).toList();
    final ik = t.players.length - shi.length;
    final avg = shi.isEmpty ? 0 : shi.map((p) => p.ovr).reduce((a, b) => a + b) / shi.length;
    final pit = shi.where((p) => p.isPitcher).length;
    final custom = t.id.length > 10 && t.id.startsWith('T_');
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _open(t),
        child: Container(
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: _line)),
          child: Row(children: [
            Container(width: 8, height: 76, decoration: BoxDecoration(color: teamColor(app.teams, t), borderRadius: const BorderRadius.horizontal(left: Radius.circular(10)))),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: _ink)),
                  const SizedBox(height: 2),
                  Text('略称 ${t.shortName.isEmpty ? '-' : t.shortName}　支配下${shi.length}人（投手$pit）・育成$ik人', style: const TextStyle(fontSize: 11.5, color: _sub)),
                  Text('支配下の平均総合 ${avg.toStringAsFixed(1)}', style: const TextStyle(fontSize: 11.5, color: _sub)),
                ]),
              ),
            ),
            if (custom) IconButton(tooltip: '削除', icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () => _delete(t)),
            const Padding(padding: EdgeInsets.only(right: 8), child: Icon(Icons.chevron_right, color: _sub)),
          ]),
        ),
      ),
    );
  }
}
