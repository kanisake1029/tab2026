import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/engine/body_model.dart';
import 'package:npb_pennant_app/engine/human/gait.dart';
import 'package:npb_pennant_app/engine/human/human_body.dart';
import 'package:npb_pennant_app/engine/pitch_motion.dart' show J;
import 'package:npb_pennant_app/engine/play_motion.dart';
import 'package:npb_pennant_app/engine/vec3.dart';

/// Layer 1（汎用の人体）：骨の長さは一定、ひじ・ひざは逆に曲がらない、関節は可動域の中、目標へ届く
void main() {
  final b = BodyModel.of(heightCm: 180, weightKg: 84, armCm: 80);

  void check(HumanBody hb, List<V3> target, String name, {double tol = 0.12}) {
    final q = hb.fit(target);
    final o = hb.fk(q);
    final p = o.p;
    double d(J a, J c) => p[a.index].distanceTo(p[c.index]);
    expect(d(J.hipT, J.kneeT), closeTo(b.thigh, 1e-6), reason: name);
    expect(d(J.kneeG, J.ankleG), closeTo(b.shank, 1e-6), reason: name);
    expect(d(J.shoulderT, J.elbowT), closeTo(b.upperArm, 1e-6), reason: name);
    expect(d(J.elbowG, J.wristG), closeTo(b.forearm, 1e-6), reason: name);
    for (var s = 0; s < 2; s++) {
      expect(q.knee[s], inInclusiveRange(0, 140), reason: '$name ひざ');
      expect(q.elbow[s], inInclusiveRange(0, 145), reason: '$name ひじ');
      expect(q.hipRot[s], inInclusiveRange(-45, 45), reason: name);
      expect(q.shRot[s], inInclusiveRange(-90, 185), reason: name);
    }
    expect(q.spTwist.abs(), lessThanOrEqualTo(55));
    // ひざは脚の付け根〜足首の線より前（つま先の側）に出る＝逆に折れない
    for (final t in [true, false]) {
      final hip = p[(t ? J.hipT : J.hipG).index], kn = p[(t ? J.kneeT : J.kneeG).index], an = p[(t ? J.ankleT : J.ankleG).index], toe = p[(t ? J.toeT : J.toeG).index];
      final mid = (hip + an) * 0.5;
      final hl = p[J.hipT.index] - p[J.hipG.index];
      final toeDir = (V3.ez.cross(hl) * hb.sT).unit; // 腰の正面
      toe.length;
      final off = (kn - mid);
      if (off.length > 0.03) expect(off.unit.dot(toeDir), greaterThan(-0.2), reason: '$name ひざの向き');
    }
    // 目標へ（可動域で止めた分だけずれる）
    for (final j in [J.ankleT, J.ankleG, J.wristT, J.wristG]) {
      expect(p[j.index].distanceTo(target[j.index]), lessThan(tol), reason: '$name ${j.name} ${p[j.index]} ${target[j.index]}');
    }
  }

  test('Poser の姿勢を人体の関節で再現できる', () {
    for (final lefty in [false, true]) {
      final hb = HumanBody(b, lefty: lefty);
      final z = Poser(b, lefty: lefty);
      for (var h = 0.0; h < 6.3; h += 0.9) {
        check(hb, z.ready(const V3(3, 20, 0), h), 'ready');
        check(hb, z.stand(const V3(3, 20, 0), h), 'stand', tol: 0.03);
        for (var ph = 0.0; ph < 1; ph += 0.1) {
          check(hb, z.run(const V3(3, 20, 0), h, 8, ph), 'run', tol: 0.16); // 腕を後ろへ振る手は、肩の伸展の範囲で少し手前に止まる
        }
        for (var u = 0.0; u <= 1; u += 0.1) {
          check(hb, z.fieldGround(const V3(3, 20, 0), h, u), 'ground');
          check(hb, z.throwBall(const V3(3, 20, 0), h, u), 'throw $u', tol: 0.25); // 送球も Layer 2 で仕様書の段階に作り直す（踏み出した足の向きと腰の回転）
          final tt = -0.75 + u; // 打撃（仕様書の6段階）：インパクト 0
          for (final hz in [0.55, 0.85, 1.1]) {
            check(hb, z.swingAt(right: !lefty, t: tt, contact: V3(lefty ? 0.1 : -0.1, 0.55, hz), spray: -20 + u * 40).p, 'swing $tt $hz', tol: tt > 0.08 ? 0.28 : 0.15); // 振り抜きは関節の範囲で手前に止まる
          }
        }
        check(hb, z.catchFly(const V3(3, 20, 0), h, const V3(3, 20, 0) + Poser.fwdOf(h) * 0.6 - Poser.rightOf(h) * (lefty ? -0.3 : 0.3) + const V3(0, 0, 2.5)), 'fly', tol: 0.25); // 頭上で両手：添える手は水平内転 135° で止まる
      }
    }
  });

  test('ひじ・ひざは反らない（届かない目標でも伸びきるだけ）', () {
    final hb = HumanBody(b);
    final z = Poser(b);
    final p = List<V3>.of(z.stand(V3.zero, 0));
    p[J.wristT.index] = p[J.shoulderT.index] + const V3(0.3, 0, -2); // 遠すぎる
    p[J.ankleG.index] = p[J.hipG.index] + const V3(0, 0, -3);
    final q = hb.fit(p);
    expect(q.elbow[0], inInclusiveRange(0, 5));
    expect(q.knee[1], inInclusiveRange(0, 5));
  });

  test('手の向き：手のひらを指定の向きへ（可動域の中で）', () {
    final hb = HumanBody(b);
    final z = Poser(b);
    final q = hb.fit(z.ready(V3.zero, 0));
    final o = hb.fk(q);
    hb.orientHand(q, o, 1, palm: const V3(0, 1, 0), finger: const V3(0, 0, -1));
    expect(q.pron[1], inInclusiveRange(-90, 90));
    expect(q.wFlex[1], inInclusiveRange(-70, 80));
    expect(q.wDev[1], inInclusiveRange(-20, 35));
    final palm0 = o.hand[1] * const V3(1, 0, 0); // G（右投げ）は左手：手のひら＝＋x
    final o2 = hb.fk(q);
    final palm = o2.hand[1] * const V3(1, 0, 0);
    expect(palm.dot(const V3(0, 1, 0)), greaterThan(palm0.dot(const V3(0, 1, 0)) + 0.3));
    expect(palm.dot(const V3(0, 1, 0)), greaterThan(0.35));
  });

  test('PD：目標へ臨界減衰で近づき、行き過ぎない', () {
    final pd = HumanPd();
    final a = HumanPose(), t = HumanPose()..elbow[0] = 90;
    pd.step(a, 0.016, HumanPd.omega());
    var prev = 0.0;
    for (var i = 0; i < 60; i++) {
      final x = pd.step(t, 1 / 60, HumanPd.omega()).elbow[0];
      expect(x, greaterThanOrEqualTo(prev - 1e-9));
      expect(x, lessThanOrEqualTo(90.0001));
      prev = x;
    }
    expect(prev, greaterThan(85));
  });

  test('走る：接地している足は地面を滑らない・歩幅とケイデンスは速さで決まる', () {
    for (final v in [2.0, 5.0, 8.5]) {
      final g = Gait(b);
      final hb = HumanBody(b);
      final z = Poser(b);
      V3? prevT;
      var wasStance = false;
      var stanceFrames = 0, maxSlip = 0.0, maxH = 0.0;
      for (var i = 0; i < 240; i++) {
        final t = i / 120;
        final pos = V3(0, v * t, 0);
        final fr = g.step(t, pos, V3(0, v, 0), 0, 0, 0);
        final p = hb.fk(hb.fit(z.runGait(pos, 0, fr))).p;
        final a = p[J.ankleT.index];
        maxH = a.z > maxH ? a.z : maxH;
        final st = g.inStance(0);
        if (prevT != null && st && wasStance && i > 20) {
          stanceFrames++;
          final slip = V3(a.x - prevT.x, a.y - prevT.y, 0).length;
          if (slip > maxSlip) maxSlip = slip;
        }
        prevT = a;
        wasStance = st;
      }
      expect(stanceFrames, greaterThan(10), reason: '$v');
      expect(maxSlip, lessThan(0.02), reason: '速さ $v で接地中の足が $maxSlip m 動いた');
      expect(maxH, greaterThan(b.ankleH + 0.08 + 0.02 * v), reason: '遊脚の高さ $v');
    }
    expect(Gait.stepLen(8), closeTo(2.0, 1e-9));
    expect(Gait.cadence(8), closeTo(4.36, 1e-9));
  });
}
