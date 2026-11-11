import 'package:flutter/material.dart';
import '../widgets/note_box.dart';

import '../models/league_rules.dart';
import '../providers/app_state.dart';
import '../utils/schedule_generator.dart';
import '../utils/standings.dart';

const _sub = Color(0xFF78716C);
const _line = Color(0xFFE7E5E4);

/// リーグ規定：公式戦の試合数・リーグごとの DH・外国人枠（1軍登録・ベンチ入り。廃止も）。
///  公式戦が始まる前（オフ〜オープン戦）だけ変えられる
class LeagueRulesPanel extends StatefulWidget {
  final AppState app;
  const LeagueRulesPanel({super.key, required this.app});
  @override
  State<LeagueRulesPanel> createState() => _LeagueRulesPanelState();
}

class _LeagueRulesPanelState extends State<LeagueRulesPanel> {
  AppState get app => widget.app;
  late int _games = app.seasonGames;
  late bool _dhCL = LeagueRules.dhCL, _dhPL = LeagueRules.dhPL;
  late int? _f1 = LeagueRules.foreign1G, _fb = LeagueRules.foreignBench;

  bool get _dirty => _games != app.seasonGames || _dhCL != LeagueRules.dhCL || _dhPL != LeagueRules.dhPL || _f1 != LeagueRules.foreign1G || _fb != LeagueRules.foreignBench;

  Widget _card(String title, String note, List<Widget> children) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: _line), borderRadius: BorderRadius.circular(10)),
        child: Material(
          type: MaterialType.transparency, // 中のスイッチの押した波紋を見せる
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
          NoteBox(note, margin: const EdgeInsets.only(top: 6, bottom: 8)),
          ...children,
        ]),
        ),
      );

  Widget _chips<T>(List<T> values, T current, String Function(T) label, void Function(T) onPick, bool enabled) => Wrap(spacing: 6, runSpacing: 4, children: [
        for (final v in values) ChoiceChip(label: Text(label(v)), selected: v == current, onSelected: enabled ? (_) => setState(() => onPick(v)) : null),
      ]);

  void _apply() {
    String? err;
    var msg = 'リーグ規定を変更しました';
    if (_games != app.seasonGames) {
      final now = app.setSeasonGames(_games);
      msg += now ? '（日程を$_games試合で作り直しました）' : '';
    }
    err = app.setLeagueRules(dhCL: _dhCL, dhPL: _dhPL, foreign1G: _f1, foreignBench: _fb);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err ?? msg)));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final on = app.rulesEditable;
    return ListView(padding: const EdgeInsets.fromLTRB(10, 12, 10, 24), children: [
      Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: on ? const Color(0xFFF0FDF4) : const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(10), border: Border.all(color: on ? const Color(0xFF86EFAC) : const Color(0xFFFCA5A5))),
        child: Text(
          on ? 'いまはオフ（公式戦の前）なので、リーグ規定を変えられます。変えた規定は今季の公式戦から使います。' : '公式戦の途中なので変えられません。シーズンが終わり、次の日程ができてから（オフ〜オープン戦の間）変えられます。',
          style: const TextStyle(fontSize: 12.5, height: 1.5),
        ),
      ),
      _card('公式戦の試合数', '120：同一リーグ20回戦＋交流戦20／143：25回戦＋交流戦18（NPB と同じ）／156：27回戦＋交流戦21（移動日が少なく、投手の回復1.08倍）', [
        _chips<int>(ScheduleGenerator.seasonLengths, _games, (g) => '$g試合', (g) => _games = g, on),
      ]),
      _card('指名打者（DH）', 'リーグごとに、DH を使うかを決めます。交流戦・日本シリーズはホーム球団のリーグの規定で行い、DH のない試合では先発投手が打順に入ります。', [
        SwitchListTile(contentPadding: EdgeInsets.zero, title: Text('${leagueLabel('CL')}：DH${_dhCL ? 'あり' : 'なし'}'), value: _dhCL, onChanged: on ? (v) => setState(() => _dhCL = v) : null),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: Text('${leagueLabel('PL')}：DH${_dhPL ? 'あり' : 'なし'}'), value: _dhPL, onChanged: on ? (v) => setState(() => _dhPL = v) : null),
      ]),
      _card('外国人枠', '外国人枠に入るのは、海外出身で FA 権（6年）を取る前の選手です。「制限なし」を選ぶと枠を廃止します。枠を減らすと、超えた分は能力の低い外国人から2軍へ移ります。', [
        const Text('1軍に登録できる人数', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        _chips<int?>(LeagueRules.foreign1GChoices, _f1, (v) => v == null ? '制限なし' : '$v人', (v) {
          _f1 = v;
          if (v != null && _fb != null && _fb! > v) _fb = v;
        }, on),
        const SizedBox(height: 10),
        const Text('試合のベンチに入れる人数', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        _chips<int?>([for (final v in LeagueRules.foreignBenchChoices) if (v == null || _f1 == null || v <= _f1!) v], _fb, (v) => v == null ? '制限なし' : '$v人', (v) => _fb = v, on),
      ]),
      FilledButton(onPressed: on && _dirty ? _apply : null, child: const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Text('この規定で決める'))),
      const SizedBox(height: 6),
      Text('いまの規定：${app.seasonGames}試合・${leagueLabel('CL')} DH${LeagueRules.dhCL ? 'あり' : 'なし'}・${leagueLabel('PL')} DH${LeagueRules.dhPL ? 'あり' : 'なし'}・外国人 1軍${LeagueRules.limitText(LeagueRules.foreign1G)}／ベンチ${LeagueRules.limitText(LeagueRules.foreignBench)}',
          style: const TextStyle(fontSize: 12, color: _sub)),
    ]);
  }
}
