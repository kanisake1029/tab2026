import 'dart:math' as m;
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/engine/body_model.dart';
import 'package:npb_pennant_app/engine/pitch_motion.dart' show J;
import 'package:npb_pennant_app/engine/play_motion.dart';
import 'package:npb_pennant_app/engine/vec3.dart';

/// 守備・走塁・打撃の動き：関節が有限で、骨の長さが体の寸法どおり（脚・腕）
void main() {
  final b = BodyModel.of(heightCm: 180, weightKg: 84, armCm: 80);
  void check(List<V3> p, String name) {
    for (final q in p) {
      expect(q.x.isFinite && q.y.isFinite && q.z.isFinite, true, reason: name);
    }
    double d(J a, J c) => p[a.index].distanceTo(p[c.index]);
    expect(d(J.hipT, J.kneeT), closeTo(b.thigh, 0.01), reason: '$name 太もも');
    expect(d(J.kneeG, J.ankleG), closeTo(b.shank, 0.01), reason: '$name すね');
    expect(d(J.shoulderT, J.elbowT), closeTo(b.upperArm, 0.01), reason: '$name 上腕');
    expect(d(J.elbowG, J.wristG), closeTo(b.forearm, 0.01), reason: '$name 前腕');
    expect(p[J.head.index].z, greaterThan(0.3), reason: '$name 頭');
  }

  test('動きの関節', () {
    for (final lefty in [false, true]) {
      final z = Poser(b, lefty: lefty);
      for (var h = 0.0; h < 6.3; h += 0.7) {
        check(z.ready(const V3(3, 20, 0), h), 'ready');
        check(z.stand(const V3(3, 20, 0), h), 'stand');
        for (var ph = 0.0; ph < 1; ph += 0.1) {
          check(z.run(const V3(3, 20, 0), h, 8, ph), 'run');
        }
        for (var u = 0.0; u <= 1; u += 0.1) {
          check(z.fieldGround(const V3(3, 20, 0), h, u), 'ground');
          check(z.throwBall(const V3(3, 20, 0), h, u), 'throw');
          check(z.swing(right: !lefty, u: u, contact: const V3(-0.1, 0.55, 0.85)), 'swing');
        }
        check(z.catchFly(const V3(3, 20, 0), h, const V3(3.5, 20.6, 2.6)), 'fly');
        check(z.slide(const V3(3, 20, 0), h), 'slide');
      }
    }
    // 走る：1周期で足は体の前にも後ろにも行き、後ろでかかとが上がる。左右は半周期ずれる
    final z = Poser(b);
    var maxY = -9.0, minY = 9.0, maxZ = 0.0;
    for (var ph = 0.0; ph < 1; ph += 0.02) {
      final p = z.run(V3.zero, 0, 8, ph);
      maxY = m.max(maxY, p[J.ankleT.index].y);
      minY = m.min(minY, p[J.ankleT.index].y);
      maxZ = m.max(maxZ, p[J.ankleT.index].z);
      final j = z.run(V3.zero, 0, 3, ph); // ジョグ：接地は体の下の近く（脚が伸びきって足が浮かない）
      expect(j[J.ankleT.index].y.abs(), lessThan(0.6));
    }
    expect(maxY, greaterThan(0.4));
    expect(minY, lessThan(-0.4));
    expect(maxZ, greaterThan(0.3));
  });
}
