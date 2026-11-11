import 'dart:math' as m;
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/engine/ball_flight.dart';
import 'package:npb_pennant_app/engine/ball_spec.dart';
import 'package:npb_pennant_app/engine/body_gen.dart';
import 'package:npb_pennant_app/engine/body_model.dart';
import 'package:npb_pennant_app/engine/grip_model.dart';
import 'package:npb_pennant_app/engine/grip_spin.dart';
import 'package:npb_pennant_app/engine/pitch_catalog.dart';
import 'package:npb_pennant_app/engine/pitch_motion.dart';
import 'package:npb_pennant_app/engine/vec3.dart';
import 'package:npb_pennant_app/models/pitching_form.dart';
import 'package:npb_pennant_app/models/player.dart';

void main() {
  final rel = const V3(-0.6, 16.4, 1.85);

  test('ボールの寸法', () {
    expect(BallSpec.radius, closeTo(0.0366, 0.0001));
    expect(BallSpec.area * 1e4, closeTo(42.1, 0.1));
  });

  test('空気抵抗・回転なしの落下は解析解と一致', () {
    final v0 = const V3(0, -40, 1.0);
    final f = BallFlight.fly(rel, v0, V3.zero, magnus: false, drag: false, dt: 0.002);
    final t = f.tCross;
    expect(t, closeTo((rel.y - FieldSpec.plateFrontY) / 40, 1e-9));
    expect(f.cross.z, closeTo(rel.z + 1.0 * t - 0.5 * BallSpec.gravity * t * t, 1e-6));
  });

  test('マグヌス力の向き：バックスピンで浮き、ジャイロは曲がらない', () {
    const v0 = V3(0, -40, 0.5);
    final none = BallFlight.fly(rel, v0, V3.zero).cross;
    final back = BallFlight.fly(rel, v0, const V3(-240, 0, 0)).cross; // 回転軸 −x：バックスピン
    final gyro = BallFlight.fly(rel, v0, v0.unit * 240).cross;
    final side = BallFlight.fly(rel, v0, const V3(0, 0, 240)).cross; // 軸が上：上から見て反時計回り
    expect(back.z - none.z, greaterThan(0.3));
    expect((gyro - none).length, lessThan(0.06)); // 重力で進む向きが下へ曲がる分だけ、ジャイロにも少し横の成分ができる
    expect(side.x - none.x, greaterThan(0.2)); // ω×v = (0,0,1)×(0,-1,0) = (+1,0,0)
    // 終速：150km/h が本塁で 135〜140km/h 前後
    final fl = BallFlight.fly(rel, const V3(0, -41.67, 0.3), const V3(-230, 0, 0));
    expect(fl.vCross.length * 3.6, inInclusiveRange(132, 141));
  });

  test('狙いの解法：到達点が狙いと1cm以内', () {
    for (final tg in [(0.0, 0.75), (0.25, 0.5), (-0.3, 1.1)]) {
      final r = AimSolver.solve(rel, 40, const V3(-200, 30, 40), tg.$1, tg.$2);
      expect((r.flight.cross.x - tg.$1).abs(), lessThan(0.01));
      expect((r.flight.cross.z - tg.$2).abs(), lessThan(0.01));
    }
  });

  final b185 = BodyModel.of(heightCm: 185, weightKg: 88, armCm: 83);
  test('リリース：腕の角度・身長で高さが単調、前への伸び 1.75〜2.20m、角速度が目安どおり', () {
    double h(int a, BodyModel b) => PitchMotion(b, PitchingForm(), armAngleDeg: a, velocity: 148).release.height;
    final hs = [for (final a in [15, 45, 85, 135]) h(a, b185)];
    for (var i = 0; i < 3; i++) {
      expect(hs[i], greaterThan(hs[i + 1]));
    }
    expect(h(45, BodyModel.of(heightCm: 195, weightKg: 95, armCm: 88)), greaterThan(h(45, BodyModel.of(heightCm: 172, weightKg: 75, armCm: 77))));
    for (final a in [15, 45, 85]) {
      final r = PitchMotion(b185, PitchingForm(), armAngleDeg: a, velocity: 148).release;
      expect(r.armAngle, closeTo(a, 1.0));
      expect(r.extension, inInclusiveRange(1.75, 2.2));
      expect(r.pelvisPeak, inInclusiveRange(500, 750));
      expect(r.trunkPeak, inInclusiveRange(950, 1300));
      expect(r.elbowPeak, inInclusiveRange(2000, 2700));
      expect(r.irPeak, inInclusiveRange(7000, 9500));
      expect(r.tPelvisPeak, lessThan(r.tTrunkPeak)); // 運動連鎖：骨盤 → 体幹 → 腕
      expect(r.tTrunkPeak, lessThan(r.tIrPeak));
      expect(r.leadKneeFFS, inInclusiveRange(38, 52));
      expect(r.leadKneeBR, inInclusiveRange(18, 32));
      expect(r.handSpeed * 3.6 / 148, inInclusiveRange(0.85, 1.05));
    }
    // クイック：足上げからリリースまで 1.1 秒以内
    final q = PitchMotion(b185, PitchingForm(), armAngleDeg: 45, velocity: 148, quick: true);
    expect(q.ph.br - q.ph.liftStart, lessThan(1.1));
  });

  test('球種の回転：ストレート 2100〜2600rpm、変化の向きが球種どおり、左右反転', () {
    final pos = PitchMotion(b185, PitchingForm(), armAngleDeg: 40, velocity: 148).release.pos;
    Pitch pc(String n, int b, int a, int sp) => Pitch(name: n, breakLevel: b, angle: a, speed: sp, ratio: 10, sharpness: 60, heaviness: 60);
    SpinResult s(Pitch p, {bool lefty = false}) => GripSpin.solve(p, pos: lefty ? pos.mirrorX : pos, armAngle: 40, lefty: lefty, velocity: 148, fbSharp: 60, fbHeavy: 60);
    final ff = s(pc('ストレート', 0, 90, 148));
    print('ストレート ${ff.rpm.round()}rpm 効率${(ff.efficiency * 100).round()}% ${ff.clockText} H${ff.moveH.toStringAsFixed(1)} V${ff.moveV.toStringAsFixed(1)}');
    expect(ff.rpm, inInclusiveRange(2100, 2600));
    expect(ff.moveV, greaterThan(25));
    expect(ff.moveH, greaterThan(10));
    for (final sp in PitchCatalog.all) {
      if (sp.name == 'ストレート') continue;
      final p = pc(sp.name, (sp.bLo + sp.bHi) ~/ 2, (sp.aLo + sp.aHi) ~/ 2, 148 + (sp.dLo + sp.dHi) ~/ 2);
      final r = s(p);
      final gp = r.grip;
      print('${sp.name.padRight(10, '　')} 握り d${gp.offset.toStringAsFixed(2)} φ${gp.rip.round().toString().padLeft(3)} θ${gp.gyro.round().toString().padLeft(3)} μ${gp.friction.toStringAsFixed(2)} 縫${gp.seamAsym.toStringAsFixed(2)} 親${gp.thumb.toStringAsFixed(1)} → ${(r.speed * 3.6).round()}km/h ${r.rpm.round().toString().padLeft(4)}rpm 効率${(r.efficiency * 100).round().toString().padLeft(3)}% ${r.clockText.padLeft(5)} 変化 H${r.moveH.toStringAsFixed(0).padLeft(4)} V${r.moveV.toStringAsFixed(0).padLeft(4)}（目標 ${r.targetH.toStringAsFixed(0)},${r.targetV.toStringAsFixed(0)}）');
      expect((r.speed * 3.6 - p.speed).abs(), lessThan(2.5), reason: sp.name);
      if (sp.name != 'ナックル') {
        // エアベンダー（魔球）は人の指で掛けられる回転の上限に当たるので、少し届かない
        final tol = sp.name == 'エアベンダー' ? 3.0 : 2.0;
        expect((r.moveH - r.targetH).abs(), lessThan(tol), reason: sp.name);
        expect((r.moveV - r.targetV).abs(), lessThan(tol), reason: sp.name);
        // 握りを保存して読み直しても同じ球になる
        final again = GripSpin.fromGrip(Grip.fromJson(gp.toJson()), name: sp.name, pos: pos, lefty: false, velocity: 148);
        expect((again.moveH - r.moveH).abs() + (again.moveV - r.moveV).abs(), lessThan(0.5), reason: sp.name);
      }
    }
    final sl = s(pc('スライダー', 50, 165, 133)), cv = s(pc('カーブ', 62, 130, 118)), fk = s(pc('フォーク', 65, 90, 134));
    expect(sl.moveH, lessThan(ff.moveH - 20)); // グラブ側へ
    expect(cv.moveV, lessThan(-10)); // トップスピンで落ちる
    expect(fk.rpm, lessThan(1800));
    final ffL = s(pc('ストレート', 0, 90, 148), lefty: true);
    expect(ffL.moveH, closeTo(ff.moveH, 1.5));
    expect(ffL.omega.x, closeTo(ff.omega.x, 1)); // 鏡に映すと回転軸の x は同じ、y・z が逆
    expect(ffL.omega.z, closeTo(-ff.omega.z, 1));
  });

  test('左投手のリリースは鏡写し', () {
    final r = PitchMotion(b185, PitchingForm(), armAngleDeg: 45, velocity: 148).release;
    final l = PitchMotion(b185, PitchingForm(), armAngleDeg: 45, velocity: 148, lefty: true).release;
    expect(l.pos.x, closeTo(-r.pos.x, 1e-9));
    expect(r.pos.x, lessThan(0)); // 右投手は三塁側（捕手から見て左）
    expect(m.sqrt(1), 1);
  });

  test('自動の体格・フォーム 300人：どれも破綻しない', () {
    var exMin = 9.0, exMax = 0.0, hMin = 9.0, hMax = 0.0, worst = 0.0;
    for (var i = 0; i < 300; i++) {
      final id = 'p$i';
      final h = BodyGen.height(id, true);
      final w = BodyGen.weight(id, h, power: 50, pitchPower: 50 + i % 40, pitcher: true);
      final arm = BodyGen.armLength(id, h, arm: 60, velocity: 145);
      final v = 135 + i % 22;
      final a = BodyGen.spinAxis(id);
      final mo = PitchMotion(BodyModel.of(heightCm: h, weightKg: w, armCm: arm), BodyGen.form(id, velocity: v, control: 60, stamina: 60), armAngleDeg: a, velocity: v, lefty: i.isOdd);
      final r = mo.release;
      expect(r.pos.z.isFinite && r.pos.x.isFinite, isTrue);
      worst = m.max(worst, (r.armAngle - a).abs());
      exMin = m.min(exMin, r.extension);
      exMax = m.max(exMax, r.extension);
      hMin = m.min(hMin, r.height);
      hMax = m.max(hMax, r.height);
      for (var t = 0.0; t < mo.ph.end; t += 0.05) {
        for (final j in mo.poseAt(t)) {
          expect(j.x.isFinite && j.y.isFinite && j.z.isFinite, isTrue);
        }
      }
    }
    print('前への伸び ${exMin.toStringAsFixed(2)}〜${exMax.toStringAsFixed(2)}m  高さ ${hMin.toStringAsFixed(2)}〜${hMax.toStringAsFixed(2)}m  腕の角度のずれ 最大${worst.toStringAsFixed(1)}°');
    expect(worst, lessThan(2));
    expect(exMin, greaterThan(1.6));
    expect(exMax, lessThan(2.35));
  });

  test('握りの6つの量：向きと量の物理', () {
    final pos = PitchMotion(b185, PitchingForm(), armAngleDeg: 40, velocity: 148).release.pos;
    SpinResult f(Grip g) => GripSpin.fromGrip(g, name: '試し', pos: pos, lefty: false, velocity: 148);
    final back = f(Grip(rip: 180, gyro: 0)), top = f(Grip(rip: 0, gyro: 0, offset: 0.7));
    final pure = f(Grip(rip: 180, gyro: 90)); // 純ジャイロ：高回転でも揚力が無い
    expect(back.moveV, greaterThan(40));
    expect(top.moveV, lessThan(-30));
    expect(pure.moveV.abs() + pure.moveH.abs(), lessThan(6));
    expect(pure.rpm, greaterThan(1800));
    final arm = f(Grip(rip: 270, gyro: 0)); // 9時へ切る → 3時（投げる腕の側）へ
    expect(arm.moveH, greaterThan(40));
    // 縫い目の力：回転は同じでも、縫い目を偏らせると押す向きへずれる
    final ssw = f(Grip(rip: 180, gyro: 60, seamAsym: 1, seamDir: 90));
    final noSsw = f(Grip(rip: 180, gyro: 60));
    expect(ssw.moveH - noSsw.moveH, greaterThan(10));
    // 摩擦を下げると回転が減り、着力点をずらすと遅くなる
    expect(f(Grip(friction: 0.3)).rpm, lessThan(f(Grip(friction: 0.9)).rpm * 0.4));
    expect(f(Grip(offset: 0.8)).speed, lessThan(f(Grip(offset: 0)).speed * 0.8));
  });
}
