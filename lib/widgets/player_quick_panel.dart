import 'package:flutter/material.dart';
import '../models/player.dart';
import '../models/team.dart';
import '../utils/app_theme.dart';
import '../utils/grade_utils.dart';
import 'player_avatar.dart';
import 'player_detail_dialog.dart';

/// オーダー画面の右側に出す選手の簡易情報。
///  野手: OVR・弾道・ミート・パワー・走力
///  投手: OVR・球速・球威・制球・スタミナ・持ち球（球種と球速）
class PlayerQuickPanel extends StatelessWidget {
  final ValueNotifier<Player?> selection;
  final dynamic appState;
  final Team team;
  final VoidCallback onChanged;
  final bool horizontal; // 画面が狭いとき（下部に横長で表示）
  final bool editable;   // 詳細ボタンで編集できるダイアログを開く（初期選手編集画面）

  const PlayerQuickPanel({super.key, required this.selection, required this.appState, required this.team, required this.onChanged, this.horizontal = false, this.editable = false});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Player?>(
      valueListenable: selection,
      builder: (context, p, _) {
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            border: horizontal ? Border(top: BorderSide(color: Colors.grey.shade300)) : Border(left: BorderSide(color: Colors.grey.shade300)),
          ),
          padding: horizontal ? const EdgeInsets.fromLTRB(3, 4, 3, 4) : const EdgeInsets.all(10),
          child: p == null
              ? const Center(child: Text('選手名をタップすると\nここに能力が表示されます\n（ダブルタップで詳細）', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)))
              : _content(context, p),
        );
      },
    );
  }

  Widget _content(BuildContext context, Player p) {
    final DateTime date = appState.currentDate as DateTime;
    final header = Row(children: [
      PlayerAvatar(p, size: horizontal ? 28 : 40, date: date), // 顔（右下に調子）
      const SizedBox(width: 6),
      Expanded(
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('#${p.uniformText} ', style: TextStyle(fontSize: horizontal ? 13 : 15, fontWeight: FontWeight.w900)),
          Flexible(child: Text(p.listName, style: TextStyle(fontSize: horizontal ? 13 : 15, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 6),
          Flexible(
            child: Text('${p.mainPosition} ${p.age}歳 ${p.throws == 'L' ? '左' : '右'}投${p.bats == 'L' ? '左' : (p.bats == 'S' ? '両' : '右')}打',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: horizontal ? 10.5 : 12, color: Colors.black54)),
          ),
        ]),
      ),
      IconButton(
        tooltip: editable ? "詳細・編集" : "詳細",
        icon: const Icon(Icons.open_in_new, size: 16),
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        onPressed: () async {
          await showDialog(context: context, builder: (c) => PlayerDetailDialog(player: p, appState: appState, team: editable ? null : team, isReadOnly: !editable, onRosterChanged: onChanged));
          onChanged();
        },
      ),
    ]);

    // 野手：OVR・メインポジションの守備適性・弾道・ミ・パ・走・肩・送（送球）・捕（捕球）を1行に詰める
    final mainApt = const {'捕手': '捕', '一塁手': '一', '二塁手': '二', '三塁手': '三', '遊撃手': '遊', '左翼手': '左', '中堅手': '中', '右翼手': '右'}[p.mainPosition];
    final stats = p.isPitcher
        ? [
            _stat('OVR', p.ovr),
            _stat('守備(投)', p.fieldP),
            _stat('球速', p.velocityNorm, text: '${p.velocity}'),
            _stat('球威', p.pitchPower),
            _stat('制球', p.control),
            _stat('スタミナ', p.stamina),
            _stat('ピンチ', p.clutchPitching),
          ]
        : [
            _stat('OVR', p.ovr),
            _stat('守備(${mainApt ?? ''})', _apt(p)),
            _traj(p.trajectory),
            _stat('ミート', p.contact),
            _stat('パワー', p.power),
            _stat('走力', p.run),
            _stat('肩力', p.arm),
            _stat('送球', p.throwAccuracy),
            _stat('捕球', p.catchSkill),
          ];

    final energy = Padding(
      padding: EdgeInsets.only(top: horizontal ? 2 : 4),
      child: Row(children: [
        SizedBox(width: horizontal ? 26 : 36, child: Text('体力', style: TextStyle(fontSize: horizontal ? 10 : 12, color: Colors.black54))),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: p.energyRatio,
              minHeight: horizontal ? 4 : 6,
              backgroundColor: Colors.grey.shade300,
              color: p.energyRatio < 0.3 ? Colors.redAccent : (p.energyRatio < 0.5 ? Colors.orange : Colors.green),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text('${p.energy}/${p.maxEnergy}', style: TextStyle(fontSize: horizontal ? 9.5 : 11)),
      ]),
    );
    final injury = p.injuryDays > 0
        ? Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('🏥 ${p.injuryName} 残り${p.injuryDays}日${p.injurySeverity == 1 ? '（強行出場可）' : ''}', style: const TextStyle(fontSize: 12, color: Colors.redAccent)),
          )
        : const SizedBox.shrink();

    // 持ち球は1行の文字で（変化球の図・守備範囲の図はやめて、情報を詰める）
    final pitches = p.isPitcher
        ? Padding(
            padding: EdgeInsets.only(top: horizontal ? 2 : 4),
            child: Text(p.pitches.map((x) => '${x.name} ${x.speed}km').join('・'), maxLines: horizontal ? 1 : null, overflow: horizontal ? TextOverflow.ellipsis : null, style: TextStyle(fontSize: horizontal ? 9.5 : 11, color: Colors.black54)),
          )
        : const SizedBox.shrink();
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        header,
        SizedBox(height: horizontal ? 2 : 4),
        horizontal
            ? Row(children: [for (final w in stats) Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 0.5), child: w))])
            : Wrap(spacing: 4, runSpacing: 4, children: stats),
        energy,
        injury,
        pitches,
      ]),
    );
  }

  /// メインポジションの守備適性
  int _apt(Player p) => switch (p.mainPosition) {
        '捕手' => p.fieldC,
        '一塁手' => p.field1B,
        '二塁手' => p.field2B,
        '三塁手' => p.field3B,
        '遊撃手' => p.fieldSS,
        '左翼手' => p.fieldLF,
        '中堅手' => p.fieldCF,
        '右翼手' => p.fieldRF,
        _ => p.fieldP,
      };

  /// 能力の小さな枠（狭い画面では詰める）
  Widget _stat(String label, int v, {String? text}) {
    final g = GradeUtils.getGrade(v);
    final c = AppTheme.getGradeColor(g);
    if (horizontal) {
      return Container(
        alignment: Alignment.topCenter,
        padding: const EdgeInsets.symmetric(vertical: 1),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(3), border: Border.all(color: Colors.grey.shade300, width: 0.6)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1, style: const TextStyle(fontSize: 9, color: Color(0xFF64748B), height: 1.2))),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
              Text(g, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: c, height: 1.1)),
              const SizedBox(width: 1),
              Text(text ?? '$v', style: const TextStyle(fontSize: 9, color: Color(0xFF94A3B8), height: 1.1)),
            ]),
          ),
        ]),
      );
    }
    return Container(
      width: 60,
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.grey.shade300)),
      child: Column(children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.black54)),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(g, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: c)),
          const SizedBox(width: 3),
          Text(text ?? '$v', style: const TextStyle(fontSize: 11)),
        ]),
      ]),
    );
  }

  Widget _traj(int t) => horizontal
      ? Container(
          alignment: Alignment.topCenter,
          padding: const EdgeInsets.symmetric(vertical: 1),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(3), border: Border.all(color: Colors.grey.shade300, width: 0.6)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const FittedBox(fit: BoxFit.scaleDown, child: Text('弾道', maxLines: 1, style: TextStyle(fontSize: 9, color: Color(0xFF64748B), height: 1.2))),
            Text('$t', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.getTrajectoryColor(t), height: 1.1)),
          ]),
        )
      : Container(
          width: 60,
          padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.grey.shade300)),
          child: Column(children: [
            const Text('弾道', style: TextStyle(fontSize: 11, color: Colors.black54)),
            Text('$t', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.getTrajectoryColor(t))),
          ]),
        );
}

