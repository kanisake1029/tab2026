import 'package:flutter/material.dart';
import '../../models/player.dart';
import '../../models/team.dart';
import '../../providers/app_state.dart';
import '../../utils/app_theme.dart';
import '../../utils/grade_utils.dart';
import '../../widgets/player_detail_dialog.dart';
import '../../widgets/player_row.dart';


/// オーダー画面で選択中の選手（右側の簡易パネルに表示）
final ValueNotifier<Player?> selectedOrderPlayer = ValueNotifier<Player?>(null);

/// 選手の詳細ダイアログを開く（閉じたら onRosterChanged）
Future<void> openPlayerDetail(BuildContext context, Player p, AppState appState, Team team, VoidCallback onRosterChanged, {bool isReadOnly = true}) async {
  await showDialog(
    context: context,
    builder: (context) => PlayerDetailDialog(player: p, appState: appState, team: team, isReadOnly: isReadOnly, onRosterChanged: onRosterChanged),
  );
  onRosterChanged();
}

/// ドラッグの開始方法。狭い画面（スマホ）は長押しで掴む（スクロールとぶつからないように）
Widget orderDraggable({required bool longPress, required String data, required Widget feedback, required Widget child, Widget? childWhenDragging}) {
  if (longPress) {
    return LongPressDraggable<String>(data: data, feedback: feedback, childWhenDragging: childWhenDragging, delay: const Duration(milliseconds: 280), child: child);
  }
  return Draggable<String>(data: data, feedback: feedback, childWhenDragging: childWhenDragging, child: child);
}

/// 選手の表示部分を自由に作れる版。タップで簡易パネル、ダブルタップで詳細
Widget buildPlayerTap(
  BuildContext context,
  Player p,
  AppState appState,
  Team team,
  VoidCallback onRosterChanged, {
  bool isReadOnly = true,
  required Widget Function(bool selected) builder,
}) {
  Future<void> openDetail() async {
    await showDialog(
      context: context,
      builder: (context) => PlayerDetailDialog(player: p, appState: appState, team: team, isReadOnly: isReadOnly, onRosterChanged: onRosterChanged),
    );
    onRosterChanged();
  }

  return ValueListenableBuilder<Player?>(
    valueListenable: selectedOrderPlayer,
    builder: (context, sel, _) => InkWell(
      onTap: () => selectedOrderPlayer.value = p,
      onDoubleTap: openDetail,
      child: builder(identical(sel, p)),
    ),
  );
}

/// オーダー画面の共通の1行（タップで「選んだ選手の能力」に表示、ダブルタップで詳細）
Widget orderPlayerRow(BuildContext context, Player p, AppState appState, Team team, VoidCallback onRosterChanged,
    {String? sub, Widget? leading, List<Widget> tags = const [], Widget? right, Widget? trailing, bool dim = false, bool compact = false}) {
  return ValueListenableBuilder<Player?>(
    valueListenable: selectedOrderPlayer,
    builder: (context, sel, _) => PlayerRow(
      face: false,
      player: p,
      date: appState.currentDate,
      sub: sub,
      leading: leading,
      tags: tags,
      right: right,
      trailing: trailing,
      dim: dim,
      compact: compact,
      selected: identical(sel, p),
      onTap: () => selectedOrderPlayer.value = p,
      onDoubleTap: () => openPlayerDetail(context, p, appState, team, onRosterChanged),
    ),
  );
}

/// 選手の一覧を、画面の幅に合わせて1〜3列に並べる（共通の1行を使う）
Widget playerRowList({required List<Widget> rows, double rowHeight = 46}) {
  return LayoutBuilder(builder: (context, c) {
    final cols = (c.maxWidth / 340).floor().clamp(1, 3);
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(0, 2, 0, 12),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, mainAxisExtent: rowHeight, crossAxisSpacing: 8),
      itemCount: rows.length,
      itemBuilder: (context, i) => rows[i],
    );
  });
}

/// 守備位置の略称 → その位置の守備適性
int fieldingAt(Player p, String pos) {
  switch (pos) {
    case '投': return p.fieldP;
    case '捕': return p.fieldC;
    case '一': return p.field1B;
    case '二': return p.field2B;
    case '三': return p.field3B;
    case '遊': return p.fieldSS;
    case '左': return p.fieldLF;
    case '中': return p.fieldCF;
    case '右': return p.fieldRF;
  }
  return 0;
}

Widget buildStatItem(String label, int val) {
  String grade = GradeUtils.getGrade(val);
  Color c = AppTheme.getGradeColor(grade);
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text('$label:', style: const TextStyle(color: Colors.grey, fontSize: 12)),
      Text(grade, style: TextStyle(color: c, fontWeight: FontWeight.bold, fontSize: 14)),
      Text('$val', style: const TextStyle(color: Colors.black54, fontSize: 12)),
      const SizedBox(width: 8),
    ],
  );
}

Widget buildTrajectoryStat(int traj) {
  Color c = AppTheme.getTrajectoryColor(traj);
  return Column(
    children: [
      const Text('弾道', style: TextStyle(color: Colors.grey, fontSize: 9)),
      Text(traj.toString(), style: TextStyle(color: c, fontWeight: FontWeight.bold, fontSize: 14)),
    ],
  );
}

