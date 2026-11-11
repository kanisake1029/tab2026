import 'package:flutter/material.dart';
import '../models/player.dart';
import '../utils/app_theme.dart';
import '../utils/grade_utils.dart';
import 'player_avatar.dart';
import 'condition_face.dart';

/// 選手一覧の共通の1行（オーダー画面の控え野手の行と同じ形）。
///  [先頭（背番号・打順など）] [調子の顔] [名前・怪我・タグ ／ 2行目の補足] [OVR ／ 体力] [末尾（ボタンなど）]
///  どの画面でも同じ見た目・同じタップ動作（タップ＝選ぶ、ダブルタップ＝詳細）にする
class PlayerRow extends StatelessWidget {
  final Player player;
  final DateTime date;
  final String? sub;          // 2行目。省略すると守備位置・投打・今季の成績
  final String? sub2;         // 3行目（小さく。年齢・全盛期・成長率など）
  final Widget? leading;      // 背番号・打順など
  final List<Widget> tags;    // 1軍・育成・外国人などの小さな札
  final Widget? right;        // OVR・体力の代わりに出すもの（年俸など）。null なら OVR・体力
  final Widget? trailing;     // 行の右端（ボタンなど）
  final bool selected;
  final bool dim;             // 2軍などを薄く表示する
  final bool face;            // 顔アイコン（false＝調子のマークだけ。オーダーの画面）
  final bool compact;         // 詰めた表示（全選手の一覧）：字と余白を小さく
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;

  const PlayerRow({
    super.key,
    required this.player,
    required this.date,
    this.sub,
    this.sub2,
    this.leading,
    this.tags = const [],
    this.right,
    this.trailing,
    this.selected = false,
    this.dim = false,
    this.face = true,
    this.compact = false,
    this.onTap,
    this.onDoubleTap,
  });

  static const ink = Color(0xFF1C1917);
  static const subColor = Color(0xFF78716C);
  static const line = Color(0xFFE7E5E4);
  static const selBg = Color(0xFFFEF3C7);
  static const selBorder = Color(0xFFF59E0B);

  static String hand(Player p) => p.isPitcher ? (p.throws == 'L' ? '左投' : '右投') : (p.bats == 'L' ? '左打' : (p.bats == 'S' ? '両打' : '右打'));

  /// 2行目の既定：野手は「守備位置 投打 打率 本塁打」、投手は「投手 投 勝敗 防御率」
  static String defaultSub(Player p) {
    final s = p.shownStats;
    if (p.isPitcher) return '投手　${hand(p)}　${s.wins}勝${s.losses}敗${s.holds > 0 ? '${s.holds}H' : ''}${s.saves > 0 ? '${s.saves}S' : ''}　防${s.inningsPitched == 0 ? '-.--' : s.era.toStringAsFixed(2)}';
    return '${p.mainPosition}　${hand(p)}　${s.battingAverage.toStringAsFixed(3).replaceFirst(RegExp(r'^0'), '')}　${s.homeRuns}本';
  }

  /// 能力のランクと値（例：B 71）
  static Widget grade(int v, {double size = 13}) {
    final g = GradeUtils.getGrade(v);
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: g, style: TextStyle(fontWeight: FontWeight.w900, fontSize: size, color: AppTheme.getGradeColor(g))),
        TextSpan(text: ' $v', style: TextStyle(fontSize: size - 0.5, color: ink)),
      ]),
      textAlign: TextAlign.right,
    );
  }

  /// 体力の割合（30%未満は赤、50%未満は橙）
  static Widget energy(Player p, {double size = 11}) => Text('${(p.energyRatio * 100).round()}%',
      textAlign: TextAlign.right,
      style: TextStyle(fontSize: size, fontFeatures: const [FontFeature.tabularFigures()], color: p.energyRatio < 0.3 ? Colors.red : (p.energyRatio < 0.5 ? const Color(0xFFB45309) : const Color(0xFF57534E))));

  /// 怪我のマーク
  static Widget injury(Player p) => p.injuryDays > 0
      ? Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Tooltip(message: '${p.injuryName} 残り${p.injuryDays}日', child: Icon(Icons.local_hospital, size: 14, color: p.injurySeverity >= 2 ? Colors.redAccent : Colors.orange)),
        )
      : const SizedBox.shrink();

  /// 抹消されてから1軍に再登録できるまでの残り日数（抹消後10日間は登録できない。0 なら登録できる）
  static int regWait(Player p, DateTime date) {
    final d = p.lastDemotedDate == null ? null : DateTime.tryParse(p.lastDemotedDate!);
    if (d == null) return 0;
    return (10 - DateUtils.dateOnly(date).difference(DateUtils.dateOnly(d)).inDays).clamp(0, 10);
  }

  /// 小さな札（1軍・育成など）
  static Widget tag(String text, Color color) => Container(
        margin: const EdgeInsets.only(left: 4),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
        child: Text(text, style: const TextStyle(fontSize: 9.5, color: Colors.white, fontWeight: FontWeight.bold, height: 1.2)),
      );

  @override
  Widget build(BuildContext context) {
    final p = player;
    final row = Container(
      padding: compact ? const EdgeInsets.symmetric(horizontal: 6, vertical: 2) : const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: selected ? selBg : (dim ? const Color(0xFFF5F5F4) : Colors.white),
        border: Border(bottom: const BorderSide(color: line), left: BorderSide(color: selected ? selBorder : Colors.transparent, width: 3)),
      ),
      child: Row(children: [
        if (leading != null) ...[leading!, const SizedBox(width: 6)],
        if (face) PlayerAvatar(p, size: compact ? 22 : 30, date: date) else ConditionFace(level: p.conditionAt(date), size: compact ? 15 : 20), // 顔アイコン（右下に調子）。オーダーは調子だけ
        SizedBox(width: compact ? 4 : 6),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Flexible(child: Text(p.listName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: compact ? 12 : 13.5, fontWeight: FontWeight.w700, color: dim ? subColor : ink, height: compact ? 1.15 : null))),
              injury(p),
              ...tags,
              if (regWait(p, date) > 0) tag('登録まであと${regWait(p, date)}日', const Color(0xFF64748B)),
            ]),
            Text(sub ?? defaultSub(p), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: compact ? 9.5 : 11, color: subColor, height: compact ? 1.15 : null)),
            if (sub2 != null) Text(sub2!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9.5, color: Color(0xFF0F766E), height: 1.2)),
          ]),
        ),
        const SizedBox(width: 4),
        right ?? Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [grade(p.ovr), energy(p)]),
        if (trailing != null) ...[const SizedBox(width: 6), trailing!],
      ]),
    );
    if (onTap == null && onDoubleTap == null) return row;
    return InkWell(onTap: onTap, onDoubleTap: onDoubleTap, child: row);
  }
}

/// 投手の1行：調子・名前・利き手（薄い字）・登板（先発）・〇勝〇敗〇H〇S・防御率。体力が7割を切ったときだけ体力
class PitcherLine extends StatelessWidget {
  final Player p;
  final PlayerStats s;
  final DateTime date;
  final double faceSize;
  const PitcherLine({super.key, required this.p, required this.s, required this.date, this.faceSize = 14});

  @override
  Widget build(BuildContext context) {
    const num = TextStyle(fontSize: 12, fontFeatures: [FontFeature.tabularFigures()], color: Color(0xFF292524));
    Widget fit(double w, String t, {TextStyle style = num}) => SizedBox(
          width: w,
          child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight, child: Text(t, style: style)),
        );
    final none = s.apps == 0;
    return Row(children: [
      SizedBox(width: faceSize + 6, child: Align(alignment: Alignment.centerLeft, child: ConditionFace(level: p.conditionAt(date), size: faceSize))),
      const SizedBox(width: 3),
      Expanded(
        child: Row(children: [
          Flexible(child: Text(p.listName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: PlayerRow.ink))),
          PlayerRow.injury(p),
          if (p.energyRatio < 0.7) Padding(padding: const EdgeInsets.only(left: 2), child: PlayerRow.energy(p, size: 9)),
        ]),
      ),
      const SizedBox(width: 2),
      SizedBox(width: 14, child: Text(p.throws == 'L' ? '左' : '右', style: const TextStyle(fontSize: 10.5, color: Color(0xFF94A3B8)))),
      fit(40, none ? '登板なし' : '${s.apps}試${s.starts > 0 ? '(${s.starts})' : ''}'),
      const SizedBox(width: 3),
      fit(60, none ? '' : '${s.wins}勝${s.losses}敗${s.holds}H${s.saves}S'),
      const SizedBox(width: 3),
      fit(32, none || s.inningsPitched == 0 ? '-' : s.era.toStringAsFixed(2), style: num.copyWith(fontWeight: FontWeight.w700)),
    ]);
  }
}
