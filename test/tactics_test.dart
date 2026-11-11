import 'dart:math' as m;
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/engine/field_time.dart';
import 'package:npb_pennant_app/engine/pitch_catalog.dart';
import 'package:npb_pennant_app/engine/tactics.dart';
import 'package:npb_pennant_app/models/player.dart';

void main() {
  Player pit({int quick = 60}) {
    final p = Player(id: 'tp$quick', isPitcher: true, height: 183, velocity: 147, control: 60, stamina: 60, quick: quick);
    p.pitches = PitchCatalog.generate(p, m.Random(2), starter: true);
    return p;
  }

  Player fielder(String id, {int run = 60, int arm = 60, int fieldC = 60}) => Player(id: id, isPitcher: false, run: run, arm: arm, fieldC: fieldC);

  test('盗塁の時間：クイック 1.1〜1.35秒・ポップタイム 1.8〜2.1秒・走者 3.1〜3.5秒', () {
    final q = StealRace.quickTime(pit());
    final pop = StealRace.popTime(fielder('c'), toSecond: true);
    final run = StealRace.runTime(fielder('r', run: 75), toSecond: true, lefty: false);
    // ignore: avoid_print
    print('クイック ${q.toStringAsFixed(2)}秒  ポップ ${pop.toStringAsFixed(2)}秒  タッチ込みの守備 ${(q + pop + 0.12).toStringAsFixed(2)}秒  走者（走力75）${run.toStringAsFixed(2)}秒');
    expect(q, inInclusiveRange(1.05, 1.35));
    expect(pop, inInclusiveRange(1.8, 2.1));
    expect(run, inInclusiveRange(3.0, 3.5));
    // 速い走者ほど、クイックの遅い投手ほど、肩の弱い捕手ほど成功しやすい
    expect(StealRace.runTime(fielder('f', run: 95), toSecond: true, lefty: false), lessThan(run));
    expect(StealRace.quickTime(pit(quick: 30)), greaterThan(StealRace.quickTime(pit(quick: 90))));
    expect(StealRace.popTime(fielder('w', arm: 30), toSecond: true), greaterThan(StealRace.popTime(fielder('s', arm: 90), toSecond: true)));
  });

  test('盗塁：投げた球（遅い球・ワンバウンド）と、捕手の送球の正確さで成否が変わる', () {
    final p = pit();
    expect(StealRace.quickTime(p, kmh: 115), greaterThan(StealRace.quickTime(p, kmh: 150) + 0.08)); // 遅いカーブは届くのが遅い
    final c = fielder('c2');
    expect(StealRace.receiveDelay(c, wz: 0.10, wx: 0), greaterThan(StealRace.receiveDelay(c, wz: 0.9, wx: 0) + 0.1)); // ワンバウンド
    expect(StealRace.receiveDelay(c, wz: 1.3, wx: 0), lessThan(StealRace.receiveDelay(c, wz: 0.9, wx: 0))); // 高めは投げやすい
    int safe(Player cat, double kmh, double wz) {
      final rnd = m.Random(9);
      var n = 0;
      for (var i = 0; i < 4000; i++) {
        if (StealRace.race(fielder('r', run: 85), p, cat, toSecond: true, kmh: kmh, wz: wz, rnd: rnd).safe) n++;
      }
      return n;
    }
    final good = fielder('g')..throwAccuracy = 85, bad = fielder('b')..throwAccuracy = 30;
    expect(safe(good, 150, 1.2), lessThan(safe(good, 115, 0.15))); // 高めの直球より、低めの遅い変化球の方が走りやすい
    expect(safe(good, 145, 0.9), lessThan(safe(bad, 145, 0.9)));  // 送球が正確な捕手ほど刺す
  });

  test('バント：送りバントは多くが成功し、足の速い打者はバントヒットが増える', () {
    final rnd = m.Random(4);
    final def = {'P': pit(), 'C': fielder('c'), '1B': fielder('1b'), '3B': fielder('3b'), '2B': fielder('2b'), 'SS': fielder('ss')};
    Map<BuntResult, int> run(int speed) {
      final cnt = <BuntResult, int>{};
      final b = fielder('b$speed', run: speed)..contactLeft = 60..contactRight = 60;
      for (var i = 0; i < 2000; i++) {
        final ball = BuntBall.make(b, toFirst: true, pitchKmh: 145, rnd: rnd);
        final r = BuntPlay.resolve(ball: ball, batter: b, batterLefty: false, runner1B: fielder('r1'), runner2B: null, defense: def, outs: 0, rnd: rnd);
        cnt[r.result] = (cnt[r.result] ?? 0) + 1;
      }
      return cnt;
    }

    final avg = run(60), fast = run(95);
    // ignore: avoid_print
    print('走力60 $avg\n走力95 $fast');
    expect((avg[BuntResult.sacrifice] ?? 0) / 2000, inInclusiveRange(0.6, 0.9)); // NPB の送りバント成功率は約8割
    expect((fast[BuntResult.hit] ?? 0), greaterThan(avg[BuntResult.hit] ?? 0));
    expect(Running.batterTo1B(fielder('x'), lefty: true), lessThan(Running.batterTo1B(fielder('x'), lefty: false)));
  });

  test('フレーミング：守備の高い捕手ほど際どい球がストライクになる', () {
    final rnd = m.Random(1);
    int strikes(int fc) => [for (var i = 0; i < 4000; i++) Framing.calledStrike(1.0, 0.2, fielder('c$fc', fieldC: fc), rnd)].where((x) => x).length;
    expect(strikes(90), greaterThan(strikes(30)));
  });
}
