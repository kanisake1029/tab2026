import 'package:flutter/material.dart';
import '../widgets/practice_picker.dart';
import 'front_screens.dart';
import '../engine/growth_engine.dart';
import '../models/player.dart';
import '../models/team.dart';
import '../providers/app_state.dart';
import '../utils/salary_utils.dart';
import '../widgets/player_row.dart';

/// 監督室の「キャンプ」タブ：春季（1月・最大50人）・秋季（11月・最大30人）のメンバーと、選手ごとの練習メニュー
///  - 連れていった選手は練習の効果 ×2。春季に連れていかない選手は2軍キャンプ（×1.3）、秋季は休養
///  - 費用は1人500万円（キャンプが始まるときに払う。キャンプ中に足すとその分を払う）
///  - 選んでいなければ、キャンプが始まるときに自動で選ぶ
class CampTab extends StatefulWidget {
  final AppState app;
  final Team team;
  final VoidCallback onChanged;
  const CampTab({super.key, required this.app, required this.team, required this.onChanged});

  @override
  State<CampTab> createState() => _CampTabState();
}

class _CampTabState extends State<CampTab> {
  late bool _spring = !(widget.app.currentDate.month >= 9 && widget.app.currentDate.month <= 11);
  String _filter = '全員';

  AppState get app => widget.app;
  Team get team => widget.team;
  List<String> get _list => _spring ? team.springCamp : team.autumnCamp;
  int get _max => _spring ? CampOps.springMax : CampOps.autumnMax;
  bool get _active => _spring ? app.inSpringCamp : app.inAutumnCamp;

  void _changed() {
    app.updateAndSave();
    widget.onChanged();
    setState(() {});
  }

  void _auto() {
    final ids = _spring ? app.autoSpringCamp(team) : app.autoAutumnCamp(team);
    if (_active) {
      // キャンプ中は、新しく加わる人数ぶんだけ費用がかかる
      final added = ids.where((id) => !_list.contains(id)).length;
      if (added > 0) app.finOf(team).add(_spring ? '春季キャンプ' : '秋季キャンプ', -added * CampOps.campCost);
    }
    if (_spring) {
      team.springCamp = ids;
    } else {
      team.autumnCamp = ids;
    }
    _changed();
  }

  Future<void> _practice(Player p) async {
    final v = await showPracticePicker(context, p);
    if (v != null) {
      p.practiceInstruction = v;
      _changed();
    }
  }

  String _menuLabel(Player p) {
    final opts = GrowthEngine.practiceOptions(p);
    if (p.practiceInstruction == 'おまかせ' || !opts.contains(p.practiceInstruction)) return 'おまかせ（${GrowthEngine.autoPractice(p)}）';
    return p.practiceInstruction;
  }

  @override
  Widget build(BuildContext context) {
    final ids = team.players.map((p) => p.id).toSet();
    _list.removeWhere((id) => !ids.contains(id));
    var players = team.players.toList();
    if (_filter == '野手') players = players.where((p) => !p.isPitcher).toList();
    if (_filter == '投手') players = players.where((p) => p.isPitcher).toList();
    if (_filter == '参加') players = players.where((p) => _list.contains(p.id)).toList();
    players.sort((a, b) {
      final ia = _list.contains(a.id), ib = _list.contains(b.id);
      if (ia != ib) return ia ? -1 : 1;
      return b.ovr.compareTo(a.ovr);
    });
    final cost = _list.length * CampOps.campCost;
    return Column(children: [
      ProposalList(app: app, onChanged: () => setState(() {})),
      Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            SegmentedButton<bool>(
              segments: const [ButtonSegment(value: true, label: Text('春季（1月）')), ButtonSegment(value: false, label: Text('秋季（11月）'))],
              selected: {_spring},
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(visualDensity: VisualDensity.compact),
              onSelectionChanged: (v) => setState(() => _spring = v.first),
            ),
            const Spacer(),
            TextButton(onPressed: _auto, child: const Text('自動で選ぶ')),
          ]),
          const SizedBox(height: 4),
          Text(
            '${_active ? 'キャンプ中' : (_list.isEmpty ? '未選択（始まるときに自動で選びます）' : '予定')}　${_list.length} / $_max人　費用 ${formatSalary(cost)}',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
          ),
          Text(
            _spring ? '連れていった選手は練習の効果 ×2、それ以外は2軍キャンプ（×1.3）。1人500万円' : '連れていった選手は練習の効果 ×2、それ以外は休養。1人500万円',
            style: const TextStyle(fontSize: 11.5, color: PlayerRow.subColor),
          ),
          const SizedBox(height: 4),
          Wrap(spacing: 6, children: [
            for (final f in const ['全員', '参加', '野手', '投手'])
              ChoiceChip(label: Text(f), selected: _filter == f, visualDensity: VisualDensity.compact, onSelected: (_) => setState(() => _filter = f)),
          ]),
        ]),
      ),
      Expanded(
        child: ListView(children: [
          for (final p in players)
            PlayerRow(
              player: p,
              date: app.currentDate,
              dim: !_list.contains(p.id),
              sub: '${p.age}歳　${GrowthEngine.phaseOf(p).label}　練習：${_menuLabel(p)}',
              selected: _list.contains(p.id),
              onTap: () => _practice(p),
              trailing: Checkbox(
                value: _list.contains(p.id),
                visualDensity: VisualDensity.compact,
                onChanged: (_) {
                  final err = app.toggleCampMember(team, p, spring: _spring);
                  if (err != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                  _changed();
                },
              ),
            ),
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('行をタップすると練習メニューを変えられます。チェックでキャンプのメンバーに入れます。', style: TextStyle(fontSize: 11.5, color: PlayerRow.subColor)),
          ),
        ]),
      ),
    ]);
  }
}
