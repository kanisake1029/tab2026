import 'package:flutter/material.dart';
import '../../engine/growth_engine.dart';
import '../../models/player.dart';
import '../../utils/app_theme.dart';
import '../../utils/grade_utils.dart';
import '../../widgets/condition_face.dart';
import 'order_shared.dart';

const _ink = Color(0xFF1C1917);
const _sub = Color(0xFF78716C);
const _line = Color(0xFFE7E5E4);

/// 2軍・3軍の打順の編集（1軍のスタメンと同じく、長押しで掴んで入れ替える）
///  打順同士に落とす＝打順の入れ替え、控えを打順に落とす＝交代、守備位置の枠をタップ＝位置を選ぶ（その位置の選手と入れ替え）
///  選手名の横に成長フェーズと成長率を出す（育成の判断に使う）
class DragLineup extends StatelessWidget {
  final List<(Player, String)> order; // 打順（選手・守備位置。位置を使わないときは ''）
  final List<Player> bench;
  final DateTime date;
  final List<String> positions; // 選べる守備位置（空なら位置は変えられない）
  final String Function(Player) stat;
  final void Function(int a, int b) onSwap;
  final void Function(int i, String playerId) onReplace;
  final void Function(int i, String pos)? onPosition;
  final Set<String> tagged; // 「2軍から」など印をつける選手
  final String tagText;

  const DragLineup({
    super.key,
    required this.order,
    required this.bench,
    required this.date,
    required this.stat,
    required this.onSwap,
    required this.onReplace,
    this.positions = const [],
    this.onPosition,
    this.tagged = const {},
    this.tagText = '',
  });

  static String growthText(Player p) => '${GrowthEngine.phaseOf(p).label}・成長率×${p.growthRate.toStringAsFixed(2)}';

  Widget _grade(int v) {
    final g = GradeUtils.getGrade(v);
    return Text.rich(TextSpan(children: [
      TextSpan(text: g, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: AppTheme.getGradeColor(g))),
      TextSpan(text: ' $v', style: const TextStyle(fontSize: 12.5, color: _ink)),
    ]));
  }

  Widget _row(BuildContext context, Player p, {String? head, String? pos, int? index, bool hovered = false}) {
    final apt = pos == null || pos.isEmpty || pos == 'DH' ? null : fieldingAt(p, pos);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      decoration: BoxDecoration(color: hovered ? const Color(0xFFFEF3C7) : Colors.white, border: const Border(bottom: BorderSide(color: _line))),
      child: Row(children: [
        if (head != null) SizedBox(width: 22, child: Text(head, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800))),
        if (pos != null)
          SizedBox(
            width: 46,
            child: pos.isEmpty
                ? Text(p.mainPosition.replaceAll('手', ''), style: const TextStyle(fontSize: 12, color: _sub))
                : InkWell(
                    onTap: positions.isEmpty || index == null || onPosition == null ? null : () => _choose(context, index, p, pos),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      height: 26,
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(border: Border.all(color: _ink), borderRadius: BorderRadius.circular(6)),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Text(posLabel(pos), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                        if (positions.isNotEmpty) const Icon(Icons.arrow_drop_down, size: 15),
                      ]),
                    ),
                  ),
          ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              ConditionFace(level: p.conditionAt(date), size: 15),
              const SizedBox(width: 5),
              Flexible(child: Text(p.listName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700))),
              if (p.ikusei) const Text(' 育', style: TextStyle(fontSize: 10.5, color: Color(0xFFB45309), fontWeight: FontWeight.w800)),
              if (p.injuryDays > 0) const Padding(padding: EdgeInsets.only(left: 3), child: Icon(Icons.local_hospital, size: 14, color: Colors.orange)),
              if (tagged.contains(p.id))
                Container(
                  margin: const EdgeInsets.only(left: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(3)),
                  child: Text(tagText, style: const TextStyle(fontSize: 9.5, color: Color(0xFFB45309), fontWeight: FontWeight.w700)),
                ),
              const SizedBox(width: 6),
              Flexible(child: Text(growthText(p), overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, color: Color(0xFF0F766E), fontWeight: FontWeight.w700))),
            ]),
            Text.rich(
              TextSpan(style: const TextStyle(fontSize: 11, color: _sub, height: 1.2), children: [
                TextSpan(text: '${p.age}歳　'),
                if (apt != null) ...[
                  const TextSpan(text: '守'),
                  TextSpan(text: GradeUtils.getGrade(apt), style: TextStyle(fontWeight: FontWeight.w900, color: apt < 40 ? Colors.red : AppTheme.getGradeColor(GradeUtils.getGrade(apt)))),
                  const TextSpan(text: '　'),
                ],
                TextSpan(text: stat(p)),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ]),
        ),
        _grade(p.ovr),
        const SizedBox(width: 2),
        const Icon(Icons.drag_indicator, size: 16, color: Color(0xFFA8A29E)),
      ]),
    );
  }

  Future<void> _choose(BuildContext context, int index, Player p, String cur) async {
    final val = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('${p.listName} の守備位置', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
            const SizedBox(height: 4),
            const Text('その位置にいた選手と入れ替わります。文字はその位置の守備適性', style: TextStyle(fontSize: 12, color: _sub)),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final pos in positions)
                ChoiceChip(
                  selected: pos == cur,
                  label: Text(pos == 'DH' ? '指' : '$pos ${GradeUtils.getGrade(fieldingAt(p, pos))}'),
                  onSelected: (_) => Navigator.pop(c, pos),
                ),
            ]),
          ]),
        ),
      ),
    );
    if (val != null && val != cur) onPosition?.call(index, val);
  }

  Widget _drag(BuildContext context, Player p, Widget Function(bool hovered) body) => orderDraggable(
        longPress: true,
        data: p.id,
        feedback: Material(color: Colors.transparent, child: SizedBox(width: 340, child: Opacity(opacity: 0.9, child: body(false)))),
        childWhenDragging: Opacity(opacity: 0.3, child: body(false)),
        child: InkWell(onTap: () => selectedOrderPlayer.value = p, child: body(false)),
      );

  @override
  Widget build(BuildContext context) {
    final ids = [for (final (p, _) in order) p.id];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('長押しで掴んで入れ替え（打順同士＝打順の入れ替え、控え→打順＝交代）。タップで能力を表示', style: TextStyle(fontSize: 11.5, color: _sub)),
      const SizedBox(height: 4),
      for (var i = 0; i < order.length; i++)
        DragTarget<String>(
          onAcceptWithDetails: (d) {
            final from = ids.indexOf(d.data);
            if (from == i) return;
            if (from >= 0) {
              onSwap(from, i);
            } else {
              onReplace(i, d.data);
            }
          },
          builder: (context, cand, _) => _drag(context, order[i].$1, (h) => _row(context, order[i].$1, head: '${i + 1}', pos: order[i].$2, index: i, hovered: h || cand.isNotEmpty)),
        ),
      const SizedBox(height: 10),
      Text('控え（${bench.length}人）', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
      const SizedBox(height: 2),
      if (bench.isEmpty) const Text('控えの野手はいません', style: TextStyle(fontSize: 12, color: _sub)),
      for (final p in bench) _drag(context, p, (h) => _row(context, p, hovered: h)),
    ]);
  }
}
