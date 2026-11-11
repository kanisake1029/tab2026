import 'package:flutter/material.dart';
import '../models/player.dart';
import '../providers/app_state.dart';
import '../utils/salary_utils.dart';
import '../widgets/player_detail_dialog.dart';
import '../utils/standings.dart';
import 'reinforce_screens.dart' show PlayerLine;

/// 現役ドラフト（仕様書 5章）：条件を満たした選手が自動で対象になる。各球団が他球団の対象選手から1人ずつ指名する
class ActiveDraftScreen extends StatefulWidget {
  final AppState app;
  const ActiveDraftScreen({super.key, required this.app});

  @override
  State<ActiveDraftScreen> createState() => _ActiveDraftScreenState();
}

class _ActiveDraftScreenState extends State<ActiveDraftScreen> {
  AppState get app => widget.app;
  Player? _sel;
  String _filter = '全て';

  Future<void> _run() async {
    final lines = app.runActiveDraft(_sel);
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('現役ドラフトの結果'),
        content: SingleChildScrollView(child: Text(lines.isEmpty ? '移籍はありませんでした' : lines.join('\n'), style: const TextStyle(fontSize: 13.5, height: 1.6))),
        actions: [FilledButton(onPressed: () => Navigator.pop(d), child: const Text('閉じる'))],
      ),
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final all = app.activeDraftCandidates();
    final list = all.where((p) => _filter == '全て' || (_filter == '投手') == p.isPitcher).toList();
    final mine = app.activeDraftMine();
    String teamOf(Player p) => app.teams.where((t) => t.players.contains(p)).map(teamShort).firstOrNull ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('現役ドラフト')),
      body: Column(children: [
        Container(
          width: double.infinity,
          color: const Color(0xFF0B1626),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Text(
            '各球団が、他球団の対象選手から1人ずつ指名します（下位の球団から。指名された球団が次に指名）。各球団から移るのは1人まで。'
            '対象は自動で決まります（支配下・プロ3年目以上・31歳以下・FA 権なし・年俸5000万円未満・今季の1軍出場が少ない選手。育成は対象外）。\n'
            '自球団の対象：${mine.isEmpty ? 'なし' : mine.map((p) => p.registeredName).join('・')}',
            style: const TextStyle(color: Color(0xFFC6F24E), fontSize: 12.5, height: 1.5),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
          child: Row(children: [
            SegmentedButton<String>(
              segments: const [ButtonSegment(value: '全て', label: Text('全て')), ButtonSegment(value: '投手', label: Text('投手')), ButtonSegment(value: '野手', label: Text('野手'))],
              selected: {_filter},
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              onSelectionChanged: (v) => setState(() => _filter = v.first),
            ),
            const SizedBox(width: 10),
            Text('${list.length}人', style: const TextStyle(color: Color(0xFF64748B))),
          ]),
        ),
        Expanded(
          child: ListView(children: [
            for (final p in list)
              PlayerLine(
                app: app,
                p: p,
                selected: identical(p, _sel),
                note: '${teamOf(p)}　今季1軍 ${p.isPitcher ? '${p.seasonStats.apps}登板' : '${p.seasonStats.games}試合'}　${formatSalary(p.salary)}',
                onTap: () => showPlayerDetail(context, app, p, allowActions: false),
                trailing: Radio<String>(value: p.id, groupValue: _sel?.id, onChanged: (_) => setState(() => _sel = p)),
              ),
          ]),
        ),
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: SafeArea(
            top: false,
            child: Row(children: [
              Expanded(child: Text(_sel == null ? '指名する選手を選んでください（選ばなければおまかせ）' : '${_sel!.registeredName}（${teamOf(_sel!)}）を指名', style: const TextStyle(fontWeight: FontWeight.w800))),
              FilledButton(onPressed: _run, child: Text(_sel == null ? 'おまかせで行う' : '指名する')),
            ]),
          ),
        ),
      ]),
    );
  }
}
