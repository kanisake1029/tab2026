import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/engine/fielder_ai.dart';
import 'package:npb_pennant_app/engine/physics_engine.dart';
import 'package:npb_pennant_app/engine/match_simulator.dart';
import 'package:npb_pennant_app/models/player.dart';

/// たくさんの打球を守らせて、おかしな捕球がないかを確かめる
void main() {
  test('ワンバウンドはフライアウトにならない／内野手は深い外野で捕らない／フェンスより奥で捕らない', () {
    final r = Random(9);
    final pe = PhysicsEngine();
    Player pl(String id) => Player(id: id, isPitcher: false, run: 60 + r.nextInt(30), arm: 60);
    var flyOuts = 0, bad1 = 0, bad2 = 0, bad3 = 0, n = 0;
    for (var k = 0; k < 4000; k++) {
      final hit = HitVector(20 + r.nextDouble() * 30, -15 + r.nextDouble() * 60, -40 + r.nextDouble() * 80, 1500);
      var tr = pe.simulateTrajectory(hit);
      // 試合と同じく、フェンスで切る（本塁打は守備なし、当たったら跳ね返る）
      var hr = false, landed = false;
      for (var i = 0; i < tr.length; i++) {
        if (i > 0 && tr[i].z <= 0.0001) landed = true;
        final a = atan2(tr[i].x, tr[i].y) * 180 / pi;
        if (sqrt(tr[i].x * tr[i].x + tr[i].y * tr[i].y) >= PhysicsConstants.getFenceDistance(a)) {
          hr = !landed && tr[i].z > PhysicsConstants.getFenceHeight(a);
          tr = tr.sublist(0, i + 1);
          if (!hr) tr = MatchSimulator.fenceRebound(tr, a);
          break;
        }
      }
      if (hr) continue;
      // 最初に地面に着いた時刻（0.05秒ごとの点の間でも見落とさない）
      var tBounce = double.infinity;
      for (var i = 1; i < tr.length; i++) {
        if (tr[i].z <= 0.0001) {
          tBounce = i * 0.05;
          break;
        }
      }
      final ai = FielderAI();
      final def = {for (final role in ['P', 'C', '1B', '2B', '3B', 'SS', 'LF', 'CF', 'RF']) role: pl(role)};
      final fs = ai.initializeFielders(def);
      final c = ai.simulateDefense(tr, fs);
      n++;
      if (c == null) continue;
      final d = sqrt(c.catchPosition.x * c.catchPosition.x + c.catchPosition.y * c.catchPosition.y);
      if (!c.isGroundBall) {
        flyOuts++;
        if (c.catchTime > tBounce + 1e-9) bad1++; // 跳ねた後なのにノーバウンド扱い
        if (!const {'LF', 'CF', 'RF'}.contains(c.fielderRole) && d > 60.5) bad2++;
      }
      if (d > 123) bad3++;
    }
    // ignore: avoid_print
    print('打球$n ノーバウンド捕球$flyOuts  ワンバウンドをフライ扱い$bad1  内野手の深い捕球$bad2  フェンスより奥$bad3');
    expect(bad1, 0);
    expect(bad2, 0);
    expect(bad3, 0);
  });
}
