import 'dart:math' as m;
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/engine/ball_spec.dart';
import 'package:npb_pennant_app/engine/pitch_catalog.dart';
import 'package:npb_pennant_app/engine/pitch_engine.dart';
import 'package:npb_pennant_app/engine/swing_model.dart';
import 'package:npb_pennant_app/models/equipment.dart';
import 'package:npb_pennant_app/models/player.dart';

/// 平均的な投手 vs 打者で、ゾーン内外の球を毎回振ったときの分布（MLB の目安と比べる）
Map<String, double> run({int meet = 60, int power = 60, int eye = 60, int traj = 2, int n = 6000, int seed = 1}) {
  final rnd = m.Random(seed);
  final p = Player(id: 'dist', isPitcher: true, throws: 'R', height: 184, velocity: 147, control: 60, stamina: 60);
  p.pitches = PitchCatalog.generate(p, m.Random(5), starter: true);
  final ph = PitcherPhysics.of(p);
  final fb = p.pitches.first;
  final slow = p.pitches.where((x) => !PitchCatalog.isFastLike(x)).toList();
  final vSlow = slow.isEmpty ? fb.speed - 15.0 : slow.map((x) => x.speed).reduce((a, b) => a + b) / slow.length;
  final bat = Bat.auto('b', power: power, contact: meet, height: 180);
  final b = BatterSkill(meet: meet, power: power, eye: eye, trajectory: traj, pull: 0.5, lefty: false, bat: bat);
  var sw = 0, wh = 0, foul = 0, inplay = 0, hard = 0;
  var ev = 0.0, la = 0.0, la2 = 0.0, spin = 0.0;
  final las = <double>[];
  double total = 0;
  for (final x in p.pitches) {
    total += x.ratio;
  }
  for (var i = 0; i < n; i++) {
    var pick = rnd.nextDouble() * total;
    var pc = p.pitches.first;
    for (final x in p.pitches) {
      pick -= x.ratio;
      if (pick <= 0) {
        pc = x;
        break;
      }
    }
    final k = ph.kind(pc);
    double g() => m.sqrt(-2 * m.log(1 - rnd.nextDouble())) * m.cos(2 * m.pi * rnd.nextDouble());
    final s = k.throwAt((rnd.nextDouble() - 0.5) * 1.6, (rnd.nextDouble() - 0.5) * 1.6, speedKmh: pc.speed.toDouble(), sigma: 0.38, gauss: g);
    final inc = IncomingPitch(
      speedKmh: pc.speed.toDouble(), time: s.time, vel: k.vCross * (s.speed / k.vRef), omega: k.spin.omega * m.exp(-s.time / BallSpec.spinDecayTau),
      aLate: k.aLate, zoneX: s.x, zoneZ: s.z, fastLike: PitchCatalog.isFastLike(pc), sharp: pc.sharpness);
    final read = SwingRead(0.6, fb.speed.toDouble(), vSlow, 3.5);
    final o = SwingModel.swing(b, read, inc, rnd: rnd, edge: m.max(0.0, m.max(s.x.abs(), s.z.abs()) - 0.8));
    sw++;
    if (o.whiff) {
      wh++;
      continue;
    }
    final bb = o.ball!;
    if (bb.vel.y <= 0 || bb.direction.abs() > 45) {
      foul++;
      continue;
    }
    inplay++;
    final v = bb.speed * 3.6;
    ev += v;
    la += bb.launch;
    la2 += bb.launch * bb.launch;
    las.add(bb.launch);
    spin += bb.backspinRpm;
    if (v >= 153) hard++;
  }
  final mla = la / inplay;
  las.sort();
  int band(double lo, double hi) => las.where((x) => x >= lo && x < hi).length;
  return {
    '空振り/スイング%': wh / sw * 100, 'ファウル/スイング%': foul / sw * 100, 'インプレー/スイング%': inplay / sw * 100,
    '平均打球速度km/h': ev / inplay, '平均打球角度°': mla, '角度のばらつき°': m.sqrt(la2 / inplay - mla * mla), '強い打球(153km/h以上)%': hard / inplay * 100,
    'ゴロ(<10°)%': band(-90, 10) / inplay * 100, 'ライナー(10-25°)%': band(10, 25) / inplay * 100, 'フライ(25-50°)%': band(25, 50) / inplay * 100, 'ポップ(50°+)%': band(50, 91) / inplay * 100,
    '平均回転rpm': spin / inplay,
  };
}

void main() {
  test('スイングの分布（MLB の目安：空振り/スイング 約25%・ファウル 約40%・平均打球速度 約143km/h・平均角度 約12°・ばらつき 約26°・強い打球 約38%・ゴロ43/ライナー21/フライ26/ポップ10）', () {
    for (final (label, meet, power) in [('平均', 60, 60), ('巧打', 85, 50), ('強打', 50, 85), ('非力', 40, 35)]) {
      final r = run(meet: meet, power: power);
      // ignore: avoid_print
      print('$label ${r.entries.map((e) => '${e.key} ${e.value.toStringAsFixed(1)}').join('  ')}');
    }
  });
}
