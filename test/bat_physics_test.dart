import 'dart:math' as m;
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/engine/bat_physics.dart';
import 'package:npb_pennant_app/engine/vec3.dart';

void main() {
  // 145km/h の直球が本塁で約133km/h・下向き約6°、バックスピン 2200rpm（軸は x）で来る
  final vBall = V3(0, -37 * m.cos(6 * deg), -37 * m.sin(6 * deg));
  final wBall = const V3(-230, 0, 0) * 1.0;
  test('上下の芯ずれ → 打球の速さ・角度・回転', () {
    for (final ey in [-0.04, -0.02, -0.01, 0.0, 0.005, 0.01, 0.015, 0.02, 0.03, 0.045]) {
      final b = BatPhysics.collide(Impact(32.5, 10, 0, ey, 0, 0.65), vBall, wBall);
      // ignore: avoid_print
      print('芯ずれ ${(ey * 100).toStringAsFixed(1)}cm → ${(b.speed * 3.6).round()}km/h  ${b.launch.toStringAsFixed(1)}°  回転${b.backspinRpm.round()}rpm');
    }
    final sq = BatPhysics.collide(Impact(32.5, 10, 0, 0, 0, 0.65), vBall, wBall);
    expect(sq.speed * 3.6, inInclusiveRange(165, 185)); // 芯で正面衝突（MLB の最速級の打球）
    final under = BatPhysics.collide(Impact(32.5, 10, 0, 0.012, 0, 0.65), vBall, wBall);
    expect(under.launch, inInclusiveRange(20, 38)); // 約1cm 下を叩く → 25〜30°・バックスピン
    expect(under.backspinRpm, inInclusiveRange(1500, 3200));
    final top = BatPhysics.collide(Impact(32.5, 10, 0, -0.015, 0, 0.65), vBall, wBall);
    expect(top.launch, lessThan(0)); // 上を叩く → ゴロ・トップスピン
    expect(top.backspinRpm, lessThan(0));
    // 先・根元で打つと反発が落ちる
    expect(BatPhysics.collide(Impact(32.5, 10, 0, 0, 0.12, 0.65), vBall, wBall).speed, lessThan(sq.speed * 0.85));
    expect(BatPhysics.collide(Impact(32.5, 10, 0, 0, -0.25, 0.65), vBall, wBall).speed, lessThan(sq.speed * 0.85));
    // 水平の向き
    expect(BatPhysics.collide(Impact(32.5, 10, -30, 0, 0, 0.65), vBall, wBall).direction, inInclusiveRange(-55, -35)); // 来る球の勢いが面に沿って残るので、バットの向きより少し大きく切れる
  });
}
