import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/engine/environment.dart';
import 'package:npb_pennant_app/engine/physics_engine.dart';
import 'package:npb_pennant_app/engine/vec3.dart';

/// 打球の飛距離（地面に最初に着くまで）。高さ1mから打ち出す
double carry(double kmh, double la, {double spin = 2000, GameEnv? env}) {
  final tr = PhysicsEngine().simulateTrajectory(HitVector(kmh / 3.6, la, 0, spin), env: env ?? GameEnv.standard);
  for (var i = 1; i < tr.length; i++) {
    if (tr[i].z <= 0.001 || (tr[i - 1].vz < 0 && tr[i].vz > 0)) {
      final f = tr[i - 1].z / max(1e-6, tr[i - 1].z + tr[i].z);
      return tr[i - 1].y + (tr[i].y - tr[i - 1].y) * f;
    }
  }
  return tr.last.y;
}

void main() {
  test('打球速度・角度 → 飛距離の表', () {
    final b = StringBuffer('        ');
    const las = [5.0, 10.0, 15.0, 20.0, 25.0, 30.0, 35.0, 40.0, 45.0];
    for (final la in las) {
      b.write('${la.round()}°'.padLeft(6));
    }
    // ignore: avoid_print
    print(b);
    for (final v in [120.0, 130.0, 140.0, 150.0, 160.0, 170.0, 180.0]) {
      final r = StringBuffer('${v.round()}km/h ');
      for (final la in las) {
        r.write('${carry(v, la, spin: (800 + 45 * la).clamp(0, 2600).toDouble()).round()}m'.padLeft(6));
      }
      // ignore: avoid_print
      print(r);
    }
  });

  test('実測の目安（Statcast：海抜0m・21℃前後・無風）と合う', () {
    // 100mph（161km/h）・28° → 約400ft（122m）、105mph・28° → 約425ft（130m）、95mph・30° → 約375ft（114m）
    expect(carry(161, 28, spin: 2000), inInclusiveRange(114, 128));
    expect(carry(169, 28, spin: 2100), inInclusiveRange(122, 138));
    expect(carry(153, 30, spin: 2000), inInclusiveRange(106, 120));
    // 低いライナーは伸びず、高すぎるフライは失速する（最も飛ぶのは 25〜35°）
    expect(carry(161, 10, spin: 1200), lessThan(carry(161, 28, spin: 2000)));
    expect(carry(161, 50, spin: 2400), lessThan(carry(161, 30, spin: 2000)));
  });

  test('環境：標高1600m で空気が約18%薄く、飛距離が5〜8%伸びる／気温・風', () {
    final std = GameEnv.standard;
    final high = GameEnv.of(altitude: 1600, tempC: 20, humidity: 0.6);
    expect(std.rho, closeTo(1.20, 0.02));
    expect(1 - high.rho / std.rho, inInclusiveRange(0.15, 0.20));
    final d0 = carry(161, 28, env: std), d1 = carry(161, 28, env: high);
    // ignore: avoid_print
    print('標高 ${d0.toStringAsFixed(1)} → ${d1.toStringAsFixed(1)}m（+${((d1 / d0 - 1) * 100).toStringAsFixed(1)}%）');
    expect(d1 / d0 - 1, inInclusiveRange(0.04, 0.10));
    final hot = GameEnv.of(altitude: 10, tempC: 32, humidity: 0.6), cold = GameEnv.of(altitude: 10, tempC: 8, humidity: 0.6);
    expect(carry(161, 28, env: hot), greaterThan(carry(161, 28, env: cold)));
    final tail = GameEnv.of(altitude: 10, tempC: 20, humidity: 0.6, wind: const V3(0, 4, 0)), head = GameEnv.of(altitude: 10, tempC: 20, humidity: 0.6, wind: const V3(0, -4, 0));
    // ignore: avoid_print
    print('風 4m/s 追い風 ${carry(161, 28, env: tail).toStringAsFixed(1)}m ／ 向かい風 ${carry(161, 28, env: head).toStringAsFixed(1)}m ／ 暑い日32℃ ${carry(161, 28, env: hot).toStringAsFixed(1)}m ／ 寒い日8℃ ${carry(161, 28, env: cold).toStringAsFixed(1)}m');
    expect(carry(161, 28, env: tail), greaterThan(d0 + 4));
    expect(carry(161, 28, env: head), lessThan(d0 - 4));
  });
}
