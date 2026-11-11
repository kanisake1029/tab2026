import 'dart:math' as m;
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/engine/ball_flight.dart';
import 'package:npb_pennant_app/engine/pitch_catalog.dart';
import 'package:npb_pennant_app/engine/pitch_engine.dart';
import 'package:npb_pennant_app/models/player.dart';

void main() {
  Player mk(String id, String throws) {
    final p = Player(id: id, isPitcher: true, throws: throws, height: 184, velocity: 148, control: 60, stamina: 60);
    p.pitches = PitchCatalog.generate(p, m.Random(3), starter: true);
    return p;
  }

  test('線形の到達点は、実際に飛ばした到達点と 1.5cm 以内', () {
    for (final t in ['R', 'L']) {
      final p = mk('eng$t', t);
      final ph = PitcherPhysics.of(p);
      for (final pc in p.pitches) {
        final k = ph.kind(pc);
        for (final (tx, tz, sp, sc) in [(0.0, 0.0, pc.speed.toDouble(), 1.0), (0.9, -0.8, pc.speed - 4.0, 0.85), (-1.2, 1.0, pc.speed + 3.0, 1.0)]) {
          final s = k.throwAt(tx, tz, speedKmh: sp, spinScale: sc, sigma: 0, gauss: () => 0);
          expect((s.x - tx).abs() * Zone.halfW, lessThan(sc == 1 ? 0.01 : 0.2)); // 回転が弱ると狙いから外れる（抜ける）
          final seam = k.spin.seam.coef == 0 ? k.spin.seam : SeamForce(k.spin.seam.coef * sc, k.spin.seam.dir, wobbleHz: k.spin.seam.wobbleHz, phase: k.spin.seam.phase);
          final f = BallFlight.fly(k.release, BallFlight.dirOf(s.yaw, s.pitch) * s.speed, k.spin.omega * sc, seam: seam, seamOrient: k.spin.seamOrient);
          expect((Zone.zoneX(f.cross.x) - s.x).abs() * Zone.halfW, lessThan(0.015), reason: '${pc.name} x');
          expect((Zone.zoneZ(f.cross.z) - s.z).abs() * Zone.halfH, lessThan(0.015), reason: '${pc.name} z');
        }
      }
    }
  });

  test('制球のばらつき：到達点の標準偏差が σ（ゾーン座標）', () {
    final p = mk('engS', 'R');
    final k = PitcherPhysics.of(p).kind(p.pitches.first);
    final r = m.Random(1);
    double g() => m.sqrt(-2 * m.log(1 - r.nextDouble())) * m.cos(2 * m.pi * r.nextDouble());
    var sx = 0.0, sz = 0.0;
    const n = 4000;
    for (var i = 0; i < n; i++) {
      final s = k.throwAt(0.3, -0.2, speedKmh: 148, sigma: 0.4, gauss: g);
      sx += m.pow(s.x - 0.3, 2);
      sz += m.pow(s.z + 0.2, 2);
    }
    expect(m.sqrt(sx / n), closeTo(0.4, 0.02));
    expect(m.sqrt(sz / n), closeTo(0.4, 0.02));
  });

  test('終盤の変化（直球との差）', () {
    final p = mk('engL', 'R');
    final ph = PitcherPhysics.of(p);
    for (final pc in p.pitches) {
      final a = ph.kind(pc).aLate;
      // ignore: avoid_print
      print('${pc.name} 変化${pc.breakLevel} 角${pc.angle} → 終盤の加速度の差 x${a.x.toStringAsFixed(2)} z${a.z.toStringAsFixed(2)} m/s²');
    }
  });
}
