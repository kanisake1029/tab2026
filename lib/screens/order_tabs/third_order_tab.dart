import 'package:flutter/material.dart';
import '../../engine/farm_engine.dart';
import '../../models/player.dart';
import '../../models/team.dart';
import '../../providers/app_state.dart';
import '../../utils/standings.dart';
import 'drag_lineup.dart';
import 'order_shared.dart';
import 'lineup_tab.dart' show ageLine;
import '../../widgets/player_row.dart';

/// 3軍のオーダー。3軍戦は2軍戦のある日に12球団の総当たりで行い、結果は能力・調子による簡易計算。
/// オーダーは3軍監督が毎試合組む（1軍・その日の2軍戦に出る選手を除く）。介入できるのは「優先して出す」選手の指定だけ。
class ThirdOrderTab extends StatelessWidget {
  final Team team;
  final AppState appState;
  final VoidCallback onChanged;
  /// 「優先して出す」の一覧だけを出す（打順・投手は1軍と同じ画面で組む）
  final bool priorityOnly;
  const ThirdOrderTab({super.key, required this.team, required this.appState, required this.onChanged, this.priorityOnly = false});

  static const _sub = Color(0xFF78716C);

  /// 打順を入れ替える：いま出ている打順を「自分で組む」の打順として固めてから変える
  void _edit(AppState app, List<Player> shown, void Function(List<String>) f) {
    final l = [for (final p in shown) p.id];
    f(l);
    team.thirdLineup = l;
    team.thirdAuto = false;
    app.updateAndSave();
    onChanged();
  }

  String _avg(PlayerStats s) => s.atBats == 0 ? '-' : s.battingAverage.toStringAsFixed(3).replaceFirst('0.', '.');
  String _era(PlayerStats s) => s.inningsPitched == 0 ? '-' : s.era.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    final app = appState;
    // 2軍戦に出る見込みの選手（2軍の打順と次の先発）を除いて、3軍監督の見込みのオーダー
    final rot = FarmEngine.effectiveRotation(team);
    final used = <String>{
      for (final e in FarmEngine.effectiveLineup(team)) e.playerId,
      if (rot.isNotEmpty) rot[team.farmRotationIndex % rot.length],
    };
    final order = app.thirdOrder(team, used: used);
    final pool = team.players.where((p) => !team.roster1G.contains(p.id) && !used.contains(p.id)).toList()
      ..sort((a, b) => a.isPitcher == b.isPitcher ? b.ovr.compareTo(a.ovr) : (a.isPitcher ? 1 : -1));
    final next = app.thirdMatches.where((m) => m.homeScore == null && (m.homeTeamId == team.id || m.awayTeamId == team.id) && !m.date.isBefore(DateUtils.dateOnly(app.currentDate))).firstOrNull;
    String? nextText;
    if (next != null) {
      final opp = app.teamById(next.homeTeamId == team.id ? next.awayTeamId : next.homeTeamId);
      nextText = '次の3軍戦　${next.date.month}/${next.date.day}　${opp == null ? '' : teamShort(opp)}（${next.homeTeamId == team.id ? 'ホーム' : 'ビジター'}）';
    }

    Widget card(String title, List<Widget> children) => Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: const Color(0xFFE7E5E4)), borderRadius: BorderRadius.circular(8)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
            const SizedBox(height: 8),
            ...children,
          ]),
        );

    Widget row(String head, Player p, String stat, {String? tag}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            SizedBox(width: 40, child: Text(head, style: const TextStyle(fontSize: 12, color: _sub))),
            Expanded(child: Text('${p.listName}　${p.mainPosition}　${p.age}歳', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
            if (tag != null)
              Container(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(3)),
                child: Text(tag, style: const TextStyle(fontSize: 10, color: Color(0xFFB45309), fontWeight: FontWeight.w700)),
              ),
            Text(stat, style: const TextStyle(fontSize: 12, color: _sub)),
          ]),
        );

    Widget prioRow(Player p) => PlayerRow(
          face: false,
          player: p,
          date: app.currentDate,
          onTap: () => selectedOrderPlayer.value = p,
          tags: [if (p.ikusei) PlayerRow.tag('育成', const Color(0xFF7C3AED))],
          sub: '${p.mainPosition}　3軍 ${p.isPitcher ? '防${_era(p.thirdStats)}' : '${_avg(p.thirdStats)} ${p.thirdStats.homeRuns}本'}',
          sub2: ageLine(p),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            const Text('優先', style: TextStyle(fontSize: 10.5, color: _sub)),
            Switch(
              value: team.thirdPriority.contains(p.id),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: (v) {
                if (v) {
                  team.thirdPriority.add(p.id);
                } else {
                  team.thirdPriority.remove(p.id);
                }
                app.updateAndSave();
                onChanged();
              },
            ),
          ]),
        );
    final prioCard = card('3軍の選手（優先して出す）', [
        if (pool.isEmpty) const Text('3軍の選手はいません', style: TextStyle(color: _sub)),
        for (final p in pool) prioRow(p),
      ]);
    if (priorityOnly) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [if (nextText != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(nextText, style: const TextStyle(fontWeight: FontWeight.w800))), prioCard]);
    return ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 24), children: [
      Text('3軍戦は2軍戦のある日に12球団の総当たりで行います（結果は能力・調子による簡易計算）。オーダーは3軍監督が毎試合、1軍とその日の2軍戦に出る選手を除いて組みます。'
          '野手が9人に足りないときは2軍から派遣します（派遣の選手には経験値が二重に入りません）。打順は長押しで入れ替えられます（入れ替えると「自分で組む」。その日に出られない選手の打順は3軍監督が埋めます）。下の「優先」は、おまかせのときに3軍監督のオーダーより先に入れる選手です。',
          style: const TextStyle(fontSize: 12, height: 1.6, color: _sub)),
      if (nextText != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(nextText, style: const TextStyle(fontWeight: FontWeight.w800))),
      const SizedBox(height: 10),
      card('次の3軍戦の見込みオーダー（${team.thirdAuto ? '3軍監督におまかせ' : '自分で組む'}）', [
        Row(children: [
          Expanded(child: SegmentedButton<bool>(
            segments: const [ButtonSegment(value: true, label: Text('おまかせ')), ButtonSegment(value: false, label: Text('自分で組む'))],
            selected: {team.thirdAuto},
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(visualDensity: VisualDensity.compact),
            onSelectionChanged: (v) {
              team.thirdAuto = v.first;
              if (!team.thirdAuto && order != null) team.thirdLineup = [for (final p in order.$1) p.id];
              app.updateAndSave();
              onChanged();
            },
          )),
        ]),
        const SizedBox(height: 6),
        if (order == null) const Text('投手がいないため、3軍戦は組めません', style: TextStyle(color: _sub)),
        if (order != null) ...[
          DragLineup(
            order: [for (final p in order.$1) (p, '')],
            bench: pool.where((p) => !p.isPitcher && !order.$1.contains(p)).toList(),
            date: app.currentDate,
            stat: (p) => '3軍 ${_avg(p.thirdStats)}　${p.thirdStats.homeRuns}本',
            tagged: order.$3,
            tagText: '2軍から',
            onSwap: (a, b) => _edit(app, order.$1, (l) {
              final t = l[a];
              l[a] = l[b];
              l[b] = t;
            }),
            onReplace: (i, id) => _edit(app, order.$1, (l) => l[i] = id),
          ),
          const Divider(height: 14),
          const Text('投手（3回ずつ。3軍監督が選ぶ）', style: TextStyle(fontSize: 12, color: _sub)),
          for (var i = 0; i < order.$2.length; i++) row('${i * 3 + 1}〜${i * 3 + 3}回', order.$2[i], '3軍 防${_era(order.$2[i].thirdStats)}'),
        ],
      ]),
      prioCard,
    ]);
  }
}
