import 'package:flutter/material.dart';
import '../../widgets/note_box.dart';
import '../../engine/farm_engine.dart';
import '../../engine/growth_engine.dart';
import '../../models/player.dart';
import '../../models/team.dart';
import '../../providers/app_state.dart';
import '../../utils/grade_utils.dart';
import '../../utils/app_theme.dart';
import 'order_shared.dart';
import 'drag_lineup.dart';

/// 2軍のオーダー。2軍の試合は1軍と同じ日程・同じ対戦チームの2軍と行い、介入できるのはオーダーだけ。
/// 「自動」のときは、怪我・疲労・昇格を見て毎日組み直す。手動にすると、打順・守備位置・先発ローテを指定できる。
class FarmOrderTab extends StatelessWidget {
  final Team team;
  final AppState appState;
  final VoidCallback onChanged;
  const FarmOrderTab({super.key, required this.team, required this.appState, required this.onChanged});

  static const _ink = Color(0xFF1C1917);
  static const _sub = Color(0xFF78716C);

  void _save() {
    appState.updateAndSave();
    onChanged();
  }

  /// 入れ替えの前に：いま出ている打順（自動、または代わりの選手が入った手動）を手動の打順として固める
  void _toManual() {
    team.farmLineup = [for (final e in FarmEngine.effectiveLineup(team)) LineupEntry(playerId: e.playerId, position: e.position)];
    if (team.farmAuto) team.farmRotation = FarmEngine.effectiveRotation(team);
    team.farmAuto = false;
  }

  /// いまの自動オーダーを、手動の初期値としてコピーする
  void _copyAutoToManual() {
    team.farmLineup = FarmEngine.autoLineup(team);
    team.farmRotation = FarmEngine.effectiveRotation(team);
  }

  String _avg(PlayerStats s) => s.atBats == 0 ? '-' : s.battingAverage.toStringAsFixed(3).replaceFirst('0.', '.');
  String _era(PlayerStats s) => s.inningsPitched == 0 ? '-' : s.era.toStringAsFixed(2);

  Widget _status(Player p) {
    if (p.isInjuredOut) return const Text('怪我', style: TextStyle(color: Color(0xFFB91C1C), fontSize: 12, fontWeight: FontWeight.w700));
    if (p.injuryDays > 0) return const Text('軽傷', style: TextStyle(color: Color(0xFFB45309), fontSize: 12));
    if (p.energyRatio < 0.5) return const Text('疲労', style: TextStyle(color: Color(0xFFB45309), fontSize: 12));
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final farm = FarmEngine.farmPlayers(team);
    final batters = farm.where((p) => !p.isPitcher).toList()..sort((a, b) => b.ovr.compareTo(a.ovr));
    final pitchers = farm.where((p) => p.isPitcher).toList()..sort((a, b) => b.ovr.compareTo(a.ovr));
    final pmap = {for (final p in team.players) p.id: p};
    final lineup = FarmEngine.effectiveLineup(team);
    final rotation = FarmEngine.effectiveRotation(team);
    final manual = !team.farmAuto;
    final nextIdx = team.farmRotationIndex % team.farmRotationCount;

    Widget card(String title, Widget child, {Widget? trailing, bool tight = false}) => Container(
          margin: EdgeInsets.only(bottom: tight ? 6 : 14),
          padding: tight ? const EdgeInsets.fromLTRB(2, 4, 2, 2) : const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: const Color(0xFFE7E5E4)), borderRadius: BorderRadius.circular(8)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: EdgeInsets.only(left: tight ? 4 : 0),
              child: Row(children: [Expanded(child: Text(title, style: TextStyle(fontWeight: FontWeight.w900, fontSize: tight ? 13 : 15))), if (trailing != null) trailing]),
            ),
            SizedBox(height: tight ? 3 : 8),
            child,
          ]),
        );

    String playerLabel(Player p) => '${p.registeredName}　${p.ovr}';

    // プルダウンの1行：名前・OVR・守備位置／怪我・体力（現在/最大）・成長率・成長フェーズ
    Widget optionItem(Player c) {
      final g = GradeUtils.getGrade(c.ovr);
      final inj = c.injuryDays > 0 ? '${c.injuryName} 残り${c.injuryDays}日' : '故障なし';
      final injColor = c.injuryDays > 0 ? (c.injurySeverity >= 2 ? Colors.redAccent : const Color(0xFFD97706)) : const Color(0xFF16A34A);
      final er = c.maxEnergy > 0 ? c.energy / c.maxEnergy : 1.0;
      final eColor = er < 0.3 ? Colors.redAccent : (er < 0.5 ? const Color(0xFFD97706) : const Color(0xFF57534E));
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Flexible(child: Text(c.registeredName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5))),
            const SizedBox(width: 6),
            Text(g, style: TextStyle(fontWeight: FontWeight.w900, color: AppTheme.getGradeColor(g))),
            Text(' ${c.ovr}', style: const TextStyle(fontSize: 12.5)),
            const SizedBox(width: 6),
            Text('${c.mainPosition}　${c.age}歳', style: const TextStyle(fontSize: 11.5, color: _sub)),
          ]),
          Text.rich(
            TextSpan(style: const TextStyle(fontSize: 11), children: [
              TextSpan(text: inj, style: TextStyle(color: injColor, fontWeight: FontWeight.w700)),
              TextSpan(text: '　体力 ${c.energy}/${c.maxEnergy}', style: TextStyle(color: eColor, fontWeight: FontWeight.w700)),
              TextSpan(text: '　成長率 ×${c.growthRate.toStringAsFixed(2)}', style: const TextStyle(color: Color(0xFF475569))),
              TextSpan(text: '　${GrowthEngine.phaseOf(c).label}', style: const TextStyle(color: Color(0xFF0F766E), fontWeight: FontWeight.w700)),
            ]),
            overflow: TextOverflow.ellipsis,
          ),
        ]),
      );
    }

    /// 選手を選ぶシート。auto=true なら「（自動で決める）」も選べる（選んだら '' を返す）
    Future<String?> pickSheet(String title, List<Player> cands, {String? current, bool auto = false}) => showModalBottomSheet<String>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (ctx) => SafeArea(
            child: SizedBox(
              height: MediaQuery.of(ctx).size.height * 0.75,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 6), child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900))),
                Expanded(
                  child: ListView(children: [
                    if (auto)
                      ListTile(dense: true, title: const Text('（自動で決める）'), selected: current == null, onTap: () => Navigator.pop(ctx, '')),
                    for (final c in cands)
                      InkWell(
                        onTap: () => Navigator.pop(ctx, c.id),
                        child: Container(
                          color: c.id == current ? const Color(0xFFFEF3C7) : null,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          decoration: null,
                          child: optionItem(c),
                        ),
                      ),
                  ]),
                ),
              ]),
            ),
          ),
        );

    // 閉じているときの表示（1行：名前と怪我のマーク。OVR は右の列に出る）
    Widget closedItem(Player c) => Row(children: [
          Flexible(child: Text(c.registeredName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
          if (c.injuryDays > 0) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.local_hospital, size: 14, color: Colors.orange)),
        ]);

    Widget pitcherSlot(int i) {
      final id = rotation[i];
      final p = pmap[id];
      final used = rotation.where((e) => e.isNotEmpty).toSet();
      Widget nameCell;
      if (manual) {
        final cands = [if (p != null) p, ...pitchers.where((b) => !used.contains(b.id))];
        nameCell = InkWell(
          onTap: () async {
            final v = await pickSheet('先発ローテ ${i + 1}番手', cands, current: p?.id, auto: true);
            if (v == null) return;
            while (team.farmRotation.length < team.farmRotationCount) {
              team.farmRotation.add('');
            }
            team.farmRotation[i] = v;
            _save();
          },
          child: Row(children: [Expanded(child: p == null ? const Text('（自動で決める）', style: TextStyle(color: _sub)) : closedItem(p)), const Icon(Icons.arrow_drop_down, color: _sub)]),
        );
      } else {
        nameCell = Text(p == null ? '-' : playerLabel(p), overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600));
      }
      if (!manual && p != null) {
        return orderPlayerRow(context, p, appState, team, _save,
            leading: SizedBox(width: 40, child: Text(i == nextIdx ? '${i + 1} 次' : '${i + 1}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
            sub: '投手　2軍 ${p.farmStats.wins}勝${p.farmStats.losses}敗　防${_era(p.farmStats)}',
            trailing: _status(p));
      }
      return InkWell(
        onTap: p == null ? null : () => selectedOrderPlayer.value = p,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF1F1F0)))),
          child: Row(children: [
            SizedBox(width: 24, child: Text('${i + 1}', textAlign: TextAlign.center, style: const TextStyle(color: _sub))),
            SizedBox(
              width: 44,
              child: i == nextIdx
                  ? Container(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      decoration: BoxDecoration(color: _ink, borderRadius: BorderRadius.circular(4)),
                      child: const Text('次', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                    )
                  : const SizedBox.shrink(),
            ),
            Expanded(child: nameCell),
            if (p != null) ...[
              SizedBox(width: 50, child: Text(_era(p.farmStats), textAlign: TextAlign.right, style: const TextStyle(fontSize: 12.5))),
              SizedBox(width: 56, child: Text('${p.farmStats.wins}勝${p.farmStats.losses}敗', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12.5))),
              SizedBox(width: 38, child: Center(child: _status(p))),
            ],
          ]),
        ),
      );
    }

    Widget header(List<(String, double)> cols) => Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Row(children: [for (final c in cols) c.$2 == 0 ? Expanded(child: Text(c.$1, style: const TextStyle(fontSize: 11, color: _sub))) : SizedBox(width: c.$2, child: Text(c.$1, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: _sub)))]),
        );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        card(
          '2軍のオーダー',
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const NoteBox('2軍の試合は、1軍と同じ日程・同じ対戦チームの2軍と行います。介入できるのはオーダーだけで、試合は自動で進みます（1球速報はありません）。'),
            const SizedBox(height: 8),
            Wrap(spacing: 12, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              SegmentedButton<bool>(
                segments: const [ButtonSegment(value: true, label: Text('自動で組む')), ButtonSegment(value: false, label: Text('自分で組む'))],
                selected: {team.farmAuto},
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(visualDensity: VisualDensity.compact),
                onSelectionChanged: (v) {
                  team.farmAuto = v.first;
                  if (!team.farmAuto) _copyAutoToManual();
                  _save();
                },
              ),
              if (manual)
                OutlinedButton.icon(
                  onPressed: () {
                    _copyAutoToManual();
                    _save();
                  },
                  icon: const Icon(Icons.auto_fix_high, size: 18),
                  label: const Text('自動の並びに戻す'),
                ),
            ]),
            if (manual) const Padding(padding: EdgeInsets.only(top: 6), child: Text('怪我・昇格などで出られない選手がいるときは、自動で代わりの選手が入ります。打順を入れ替えると「自分で組む」になります。', style: TextStyle(fontSize: 12, color: _sub))),
          ]),
        ),
        card(
          '打順（${manual ? '自分で組む' : '自動'}）',
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (lineup.length < 9) const Padding(padding: EdgeInsets.all(8), child: Text('出場できる2軍の野手が足りません（この間、2軍の試合は行われません）', style: TextStyle(color: Color(0xFFB91C1C)))),
            DragLineup(
              order: [for (final l in lineup) if (pmap[l.playerId] != null) (pmap[l.playerId]!, l.position)],
              bench: batters.where((b) => !lineup.any((l) => l.playerId == b.id)).toList(),
              date: appState.currentDate,
              positions: FarmEngine.lineupPositions,
              stat: (p) => '2軍 ${_avg(p.farmStats)}　${p.farmStats.homeRuns}本　${p.farmStats.rbi}点',
              onSwap: (x, y) {
                _toManual();
                final t = team.farmLineup[x];
                team.farmLineup[x] = team.farmLineup[y];
                team.farmLineup[y] = t;
                _save();
              },
              onReplace: (i, id) {
                _toManual();
                team.farmLineup[i] = LineupEntry(playerId: id, position: team.farmLineup[i].position);
                _save();
              },
              onPosition: (i, pos) {
                _toManual();
                final j = team.farmLineup.indexWhere((x) => x.position == pos);
                if (j >= 0) team.farmLineup[j].position = team.farmLineup[i].position;
                team.farmLineup[i].position = pos;
                _save();
              },
            ),
          ]),
        ),
        card(
          '先発ローテ（${team.farmRotationCount}人）',
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            header([('', 24), ('', 44), ('投手　総合', 0), ('防御率', 50), ('勝敗', 56), ('', 38)]),
            for (int i = 0; i < rotation.length; i++) pitcherSlot(i),
          ]),
        ),
      ],
    );
  }
}
