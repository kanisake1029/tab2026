import 'dart:math';
import 'package:flutter/material.dart';
import '../engine/fielder_ai.dart';
import '../engine/match_simulator.dart';
import '../engine/physics_engine.dart';

/// 結果の色（統一）: ストライク・ファウル=黄 / ボール=緑 / アウト=赤 / ヒット=青
const Color kStrikeColor = Color(0xFFFACC15);
const Color kBallColor = Color(0xFF22C55E);
const Color kOutColor = Color(0xFFEF4444);
const Color kHitColor = Color(0xFF3B82F6);

bool isHitOutcome(String outcome) => const {'単打', '二塁打', '三塁打', 'ホームラン'}.contains(outcome);

/// 投球結果の色
Color pitchResultColor(PitchEvent e) {
  if (e.desc.contains('三振') || e.desc.contains('捕球 (アウト)')) return kOutColor;
  if (e.result == 'インプレー' || e.result == 'バント') {
    if (e.outcome.isEmpty) return kStrikeColor;
    return isHitOutcome(e.outcome) || e.outcome == 'エラー' ? kHitColor : kOutColor;
  }
  if (e.result == 'ボール') return kBallColor;
  return kStrikeColor; // 見逃し・空振り・ファウル
}

/// 投球結果の表示名
String pitchResultLabel(PitchEvent e) {
  if (e.desc.contains('三振')) return '三振';
  if (e.result == 'インプレー' || e.result == 'バント') return e.outcome.isNotEmpty ? e.outcome : e.result;
  if (e.result == 'ボール' && e.desc.contains('四球')) return '四球';
  return e.result;
}

/// ストライクゾーン図（投手側から見た図。+xが右）。打者は左右の打席に簡易表示。
class StrikeZoneView extends StatelessWidget {
  final List<PitchEvent> events; // 描画する投球（通常は直近の打席ぶん）
  const StrikeZoneView({super.key, required this.events});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 0.85,
      child: CustomPaint(painter: _ZonePainter(events)),
    );
  }
}

class _ZonePainter extends CustomPainter {
  final List<PitchEvent> events;
  _ZonePainter(this.events);

  @override
  void paint(Canvas canvas, Size size) {
    const range = 2.2; // 表示範囲 ±2.2（ゾーン端=±1）
    Offset map(double x, double z) => Offset(size.width / 2 + x / range * size.width / 2, size.height / 2 - z / range * size.height / 2);

    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFF1F5F9));
    // ゾーン
    final tl = map(-1, 1), br = map(1, -1);
    final zoneRect = Rect.fromPoints(tl, br);
    canvas.drawRect(zoneRect, Paint()..color = Colors.white);
    final grid = Paint()..color = Colors.grey.shade400..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      final gx = zoneRect.left + zoneRect.width * i / 3;
      final gz = zoneRect.top + zoneRect.height * i / 3;
      canvas.drawLine(Offset(gx, zoneRect.top), Offset(gx, zoneRect.bottom), grid);
      canvas.drawLine(Offset(zoneRect.left, gz), Offset(zoneRect.right, gz), grid);
    }
    canvas.drawRect(zoneRect, Paint()..color = Colors.black87..style = PaintingStyle.stroke..strokeWidth = 2);

    // 打者のシルエット（右打者=画面右、左打者=画面左）
    if (events.isNotEmpty) {
      final left = events.last.batterHand == 'L';
      final bx = left ? size.width * 0.07 : size.width * 0.93;
      final p = Paint()..color = Colors.black26;
      canvas.drawCircle(Offset(bx, size.height * 0.28), 9, p);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(bx, size.height * 0.5), width: 16, height: size.height * 0.34), const Radius.circular(6)), p);
    }

    // 投球
    for (var i = 0; i < events.length; i++) {
      final e = events[i];
      if (e.result == 'バント') continue;
      final c = map(e.x.clamp(-range, range).toDouble(), e.z.clamp(-range, range).toDouble());
      canvas.drawCircle(c, 11, Paint()..color = pitchResultColor(e));
      canvas.drawCircle(c, 11, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 1.5);
      final tp = TextPainter(text: TextSpan(text: '${e.pitchNo}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)), textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _ZonePainter old) => true;
}

/// 球場を上から見た図。守備位置・走者・直近の打球の落下点を表示（おおよその位置）。
class FieldView extends StatelessWidget {
  final List<PitchEvent> battedBalls; // 打球のある投球（landX/landYあり）
  final bool runner1B;
  final bool runner2B;
  final bool runner3B;
  final bool showFielders;
  const FieldView({super.key, required this.battedBalls, this.runner1B = false, this.runner2B = false, this.runner3B = false, this.showFielders = true});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.15,
      child: CustomPaint(painter: _FieldPainter(battedBalls, runner1B, runner2B, runner3B, showFielders)),
    );
  }
}

class _FieldPainter extends CustomPainter {
  final List<PitchEvent> balls;
  final bool r1, r2, r3, showFielders;
  _FieldPainter(this.balls, this.r1, this.r2, this.r3, this.showFielders);

  @override
  void paint(Canvas canvas, Size size) {
    // 表示範囲: x -75〜75、y -8〜130（本塁が下）
    const minX = -75.0, maxX = 75.0, minY = -8.0, maxY = 130.0;
    Offset map(double x, double y) => Offset((x - minX) / (maxX - minX) * size.width, size.height - (y - minY) / (maxY - minY) * size.height);

    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFE2E8F0));
    // 外野の芝（フェンス内）
    final fence = Path();
    for (var a = -45.0; a <= 45.0; a += 3) {
      final r = PhysicsConstants.getFenceDistance(a);
      final p = map(r * sin(a * pi / 180), r * cos(a * pi / 180));
      if (a == -45.0) { fence.moveTo(p.dx, p.dy); } else { fence.lineTo(p.dx, p.dy); }
    }
    fence.lineTo(map(0, 0).dx, map(0, 0).dy);
    fence.close();
    canvas.drawPath(fence, Paint()..color = const Color(0xFF86EFAC));
    canvas.drawPath(fence, Paint()..color = Colors.green.shade800..style = PaintingStyle.stroke..strokeWidth = 2);
    // 内野の土
    canvas.drawCircle(map(0, 22), size.width * 0.22, Paint()..color = const Color(0xFFD6A77A));
    // ファウルライン
    final line = Paint()..color = Colors.white..strokeWidth = 1.5;
    canvas.drawLine(map(0, 0), map(PhysicsConstants.getFenceDistance(45) * sin(pi / 4), PhysicsConstants.getFenceDistance(45) * cos(pi / 4)), line);
    canvas.drawLine(map(0, 0), map(-PhysicsConstants.getFenceDistance(45) * sin(pi / 4), PhysicsConstants.getFenceDistance(45) * cos(pi / 4)), line);
    // ダイヤモンド
    final bases = [map(0, 0), map(19.4, 19.4), map(0, 38.8), map(-19.4, 19.4)];
    final dia = Path()..moveTo(bases[0].dx, bases[0].dy);
    for (var i = 1; i < 4; i++) { dia.lineTo(bases[i].dx, bases[i].dy); }
    dia.close();
    canvas.drawPath(dia, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 2);
    // 塁（走者がいる塁は色付き）
    final occ = [false, r1, r2, r3];
    for (var i = 0; i < 4; i++) {
      canvas.drawRect(Rect.fromCenter(center: bases[i], width: 9, height: 9), Paint()..color = occ[i] ? const Color(0xFFEF4444) : Colors.white);
    }
    // 守備位置
    if (showFielders) {
      final pos = FielderAI().basePositions;
      pos.forEach((role, xy) {
        if (role == 'C') return;
        final c = map(xy[0], xy[1]);
        canvas.drawCircle(c, 5, Paint()..color = Colors.indigo.shade400);
        final tp = TextPainter(text: TextSpan(text: role, style: const TextStyle(color: Colors.black87, fontSize: 9, fontWeight: FontWeight.bold)), textDirection: TextDirection.ltr)..layout();
        tp.paint(canvas, c + const Offset(6, -5));
      });
    }
    // 打球
    for (final b in balls) {
      if (b.landX == null || b.landY == null) continue;
      final end = map(b.landX!, b.landY!);
      Color col;
      switch (b.outcome) {
        case 'ホームラン':
          col = const Color(0xFFDC2626);
          break;
        case 'アウト':
          col = Colors.grey.shade700;
          break;
        default:
          col = const Color(0xFF16A34A);
      }
      canvas.drawLine(map(0, 0), end, Paint()..color = col.withAlpha(150)..strokeWidth = 2);
      canvas.drawCircle(end, b.outcome == 'ホームラン' ? 7 : 5, Paint()..color = col);
      canvas.drawCircle(end, b.outcome == 'ホームラン' ? 7 : 5, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 1.5);
    }
  }

  @override
  bool shouldRepaint(covariant _FieldPainter old) => true;
}
