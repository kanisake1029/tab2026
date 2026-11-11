import 'dart:math';
import 'package:flutter/material.dart';

/// 調子の顔アイコン（−2〜+2）
///  絶好調: 赤の笑顔 / 好調: オレンジのほほえみ / 普通: 黄色の真顔 / 不調: 水色の少し具合の悪い顔 / 絶不調: 紫の具合の悪い顔
class ConditionFace extends StatelessWidget {
  final int level;
  final double size;
  const ConditionFace({super.key, required this.level, this.size = 18});

  static const colors = {
    2: Color(0xFFEF4444),
    1: Color(0xFFF97316),
    0: Color(0xFFFACC15),
    -1: Color(0xFF7DD3FC),
    -2: Color(0xFFA855F7),
  };
  static const labels = {2: '絶好調', 1: '好調', 0: '普通', -1: '不調', -2: '絶不調'};

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: labels[level] ?? '',
      child: SizedBox(width: size, height: size, child: CustomPaint(painter: _FacePainter(level.clamp(-2, 2)))),
    );
  }
}

class _FacePainter extends CustomPainter {
  final int level;
  _FacePainter(this.level);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final c = Offset(s / 2, s / 2);
    final r = s / 2;
    canvas.drawCircle(c, r, Paint()..color = ConditionFace.colors[level]!);
    canvas.drawCircle(c, r - 0.5, Paint()..color = Colors.black.withOpacity(0.35)..style = PaintingStyle.stroke..strokeWidth = max(1.0, s * 0.05));
    final ink = Paint()
      ..color = const Color(0xFF1F2937)
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(1.2, s * 0.08)
      ..strokeCap = StrokeCap.round;
    final dot = Paint()..color = const Color(0xFF1F2937);
    final le = Offset(s * 0.34, s * 0.40), re = Offset(s * 0.66, s * 0.40);

    switch (level) {
      case 2: // 目を細めた満面の笑み
        for (final e in [le, re]) {
          canvas.drawArc(Rect.fromCenter(center: e + Offset(0, s * 0.03), width: s * 0.18, height: s * 0.16), pi, pi, false, ink);
        }
        final mouth = Path()
          ..moveTo(s * 0.26, s * 0.58)
          ..quadraticBezierTo(s * 0.5, s * 0.92, s * 0.74, s * 0.58)
          ..close();
        canvas.drawPath(mouth, Paint()..color = const Color(0xFF1F2937));
        break;
      case 1: // ほほえみ
        canvas.drawCircle(le, s * 0.055, dot);
        canvas.drawCircle(re, s * 0.055, dot);
        canvas.drawArc(Rect.fromCenter(center: Offset(s * 0.5, s * 0.58), width: s * 0.42, height: s * 0.28), 0.15 * pi, 0.7 * pi, false, ink);
        break;
      case 0: // 真顔
        canvas.drawCircle(le, s * 0.055, dot);
        canvas.drawCircle(re, s * 0.055, dot);
        canvas.drawLine(Offset(s * 0.33, s * 0.68), Offset(s * 0.67, s * 0.68), ink);
        break;
      case -1: // 少し具合が悪い（波打つ口・汗）
        canvas.drawCircle(le, s * 0.05, dot);
        canvas.drawCircle(re, s * 0.05, dot);
        final w = Path()
          ..moveTo(s * 0.32, s * 0.70)
          ..quadraticBezierTo(s * 0.41, s * 0.62, s * 0.5, s * 0.70)
          ..quadraticBezierTo(s * 0.59, s * 0.78, s * 0.68, s * 0.70);
        canvas.drawPath(w, ink);
        final drop = Path()
          ..moveTo(s * 0.84, s * 0.18)
          ..quadraticBezierTo(s * 0.94, s * 0.34, s * 0.84, s * 0.38)
          ..quadraticBezierTo(s * 0.74, s * 0.34, s * 0.84, s * 0.18);
        canvas.drawPath(drop, Paint()..color = const Color(0xFF2563EB));
        break;
      default: // −2: 具合が悪い（×の目・への字口）
        for (final e in [le, re]) {
          final d = s * 0.07;
          canvas.drawLine(e + Offset(-d, -d), e + Offset(d, d), ink);
          canvas.drawLine(e + Offset(-d, d), e + Offset(d, -d), ink);
        }
        canvas.drawArc(Rect.fromCenter(center: Offset(s * 0.5, s * 0.80), width: s * 0.40, height: s * 0.26), 1.15 * pi, 0.7 * pi, false, ink);
    }
  }

  @override
  bool shouldRepaint(covariant _FacePainter old) => old.level != level;
}
