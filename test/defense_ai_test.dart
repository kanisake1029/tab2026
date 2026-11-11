import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/engine/defense_ai.dart';
import 'package:npb_pennant_app/engine/fielder_ai.dart';
import 'package:npb_pennant_app/engine/field_time.dart';
import 'package:npb_pennant_app/engine/physics_engine.dart';
import 'package:npb_pennant_app/engine/play_resolver.dart';
import 'package:npb_pennant_app/models/player.dart';

/// 守備・走塁の判断（役割の割り当て・送球先の期待値・走者の判断）
void main() {
  Player pl(String id, {int run = 60, int field = 60, int years = 5}) => Player(
      id: id, isPitcher: false, run: run, arm: 60, catchSkill: field, throwAccuracy: 60, proYears: years,
      fieldP: field, fieldC: field, field1B: field, field2B: field, field3B: field, fieldSS: field, fieldLF: field, fieldCF: field, fieldRF: field);
  const roles = ['P', 'C', '1B', '2B', '3B', 'SS', 'LF', 'CF', 'RF'];

  ({PlayResolver res, List<FielderState> fs}) setup(int seed, {int field = 60}) {
    final ai = FielderAI();
    final fs = ai.initializeFielders({for (final r in roles) r: pl(r, field: field)});
    final res = PlayResolver(Random(seed), {for (final f in fs) f.role: f}, {for (final f in fs) f.role: [f.x, f.y]});
    return (res: res, fs: fs);
  }

  test('得点期待値：走者が多いほど・アウトが少ないほど大きい', () {
    for (var o = 0; o < 3; o++) {
      expect(RunValue.re(7, o), greaterThan(RunValue.re(0, o)));
      if (o < 2) expect(RunValue.re(1, o), greaterThan(RunValue.re(1, o + 1)));
    }
    expect(RunValue.re(0, 3), 0);
  });

  test('判断力：経験・守備力が高いほど迷いが短く、見積もりのぶれが小さい', () {
    final rookie = Judgment.fielder(pl('a', years: 1), 50), vet = Judgment.fielder(pl('b', years: 12, field: 85), 85);
    expect(vet, greaterThan(rookie));
    expect(Judgment.hesitation(vet, 0), lessThan(Judgment.hesitation(rookie, 0)));
    expect(Judgment.readSigma(rookie, 1), greaterThan(Judgment.readSigma(rookie, 0))); // 重圧で乱れる
  });

  test('役割：遊ゴロ・走者一塁は二塁手が二塁、一塁手が一塁に入る。投ゴロは右打者なら遊撃手が二塁', () {
    final s = setup(1);
    final info = {for (final f in s.fs) f.role: DefenderInfo(f.role, f.player, f.x, f.y, f.reactionDelay, sprintOf(f), f.judgment)};
    final p1 = DefensePlan.assign(d: info, primary: 'SS', fx: -12, fy: 40, tField: 1.4, ballClass: BallClass.grounder, bits: 1, outs: 0, batterLefty: false);
    expect(p1.cover[2], '2B');
    expect(p1.cover[1], '1B');
    final p2 = DefensePlan.assign(d: info, primary: 'P', fx: 0, fy: 17, tField: 0.8, ballClass: BallClass.grounder, bits: 1, outs: 0, batterLefty: false);
    expect(p2.cover[2], 'SS');
    final p3 = DefensePlan.assign(d: info, primary: '1B', fx: 22, fy: 25, tField: 1.0, ballClass: BallClass.grounder, bits: 0, outs: 0, batterLefty: false);
    expect(p3.cover[1], 'P'); // 一塁手が捕ったら投手がベースカバー
    // 右中間の長打：二塁手と遊撃手がダブルカット
    final p4 = DefensePlan.assign(d: info, primary: 'RF', fx: 35, fy: 100, tField: 4.0, ballClass: BallClass.gap, bits: 1, outs: 0, batterLefty: false);
    expect(p4.cutoffs, ['2B', 'SS']);
  });

  test('遊ゴロ・走者一塁・無死：ほとんどは二塁で封殺し、多くは 6-4-3 の併殺', () {
    var force = 0, dp = 0, n = 0;
    for (var k = 0; k < 300; k++) {
      final s = setup(k);
      final o = s.res.groundBall(role: 'SS', fx: -11, fy: 42, tBall: 1.35, batter: pl('bat'), runners: [pl('r1'), null, null], outsBefore: 0);
      n++;
      if (o.moves.firstWhere((m) => m.from == 1).out) force++;
      if (o.dp) {
        dp++;
        expect(o.code, '6-4-3');
      }
    }
    expect(force / n, greaterThan(0.85));
    expect(dp / n, greaterThan(0.45));
  });

  test('ボテボテのゴロ・走者一塁：二塁は無理なので一塁へ（野選にしない）', () {
    var fc = 0;
    for (var k = 0; k < 200; k++) {
      final s = setup(k);
      final o = s.res.groundBall(role: '3B', fx: -8, fy: 14, tBall: 2.4, batter: pl('bat'), runners: [pl('r1'), null, null], outsBefore: 0);
      if (o.outs == 0 && !o.hit) fc++;
    }
    expect(fc, lessThan(30));
  });

  test('一・二塁の三ゴロ（三塁の近く）：本塁か三塁で封殺し、三重殺もまれに起きる', () {
    var tp = 0, homeOrThird = 0;
    for (var k = 0; k < 400; k++) {
      final s = setup(k);
      final o = s.res.groundBall(role: '3B', fx: -18, fy: 21, tBall: 0.9, batter: pl('bat', run: 40), runners: [pl('r1', run: 40), pl('r2', run: 40), null], outsBefore: 0);
      if (o.moves.any((m) => m.out && (m.to == 3 || m.to == 4))) homeOrThird++;
      if (o.tp) tp++;
    }
    expect(homeOrThird, greaterThan(300));
    expect(tp, greaterThan(0));
  });

  test('三塁走者：内野の深い所へのゴロ（一死）なら本塁へ走り、前進守備の正面なら止まる', () {
    var goBack = 0, goIn = 0;
    for (var k = 0; k < 200; k++) {
      final back = setup(k).res.groundBall(role: '2B', fx: 12, fy: 44, tBall: 1.6, batter: pl('bat'), runners: [null, null, pl('r3')], outsBefore: 1);
      if (back.moves.any((m) => m.from == 3 && m.to == 4)) goBack++;
      final inn = setup(k).res.groundBall(role: 'SS', fx: -6, fy: 26, tBall: 0.9, batter: pl('bat'), runners: [null, null, pl('r3')], outsBefore: 1);
      if (inn.moves.any((m) => m.from == 3 && m.to == 4)) goIn++;
    }
    expect(goBack, greaterThan(140));
    expect(goIn, lessThan(goBack));
  });

  test('エンドランの一塁走者：内野ライナーで捕られると戻れずに併殺', () {
    var dp = 0;
    for (var k = 0; k < 100; k++) {
      final ai = FielderAI();
      final fs = ai.initializeFielders({for (final r in roles) r: pl(r)});
      final res = PlayResolver(Random(k), {for (final f in fs) f.role: f}, {for (final f in fs) f.role: [f.x, f.y]}, hitRun: true);
      final o = res.flyOut(role: '2B', fx: 10, fy: 42, tCatch: 0.6, runners: [pl('r1'), null, null], outsBefore: 0, liner: true);
      if (o.dp) dp++;
    }
    expect(dp, greaterThan(70));
  });

  test('声の掛け合い：内野と外野の間のフライは外野手（中堅手が最優先）', () {
    final pe = PhysicsEngine();
    var of = 0, n = 0;
    for (var k = 0; k < 100; k++) {
      final tr = pe.simulateTrajectory(HitVector(31, 42, -5, 2000));
      final ai = FielderAI();
      final fs = ai.initializeFielders({for (final r in roles) r: pl(r)});
      final c = ai.simulateDefense(tr, fs);
      if (c == null || c.isGroundBall) continue;
      n++;
      if (const {'LF', 'CF', 'RF'}.contains(c.fielderRole)) of++;
    }
    expect(n, greaterThan(40));
    // ignore: avoid_print
    print('浅いフライ：外野手が捕った $of / $n');
    expect(of / n, greaterThan(0.9));
  });
}

// テスト用：FielderState から走りの性能
Sprint sprintOf(FielderState f) => Sprint(f.speed, f.accel);
