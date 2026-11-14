import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/engine/abroad_stats.dart';
import 'package:npb_pennant_app/engine/foreign_engine.dart';
import 'package:npb_pennant_app/engine/physics_engine.dart';
import 'package:npb_pennant_app/engine/swing_model.dart';
import 'package:npb_pennant_app/engine/vec3.dart';
import 'package:npb_pennant_app/models/player.dart';

void main() {
  test('① AbroadStats は新規生成・既存行復元ともに全項目を整合性を持って埋める', () {
    final batter = Player(
      id: 'FB1',
      isPitcher: false,
      lastName: 'テスト',
      firstName: 'バッター',
      mainPos: '一塁手',
      age: 28,
      contactLeft: 72,
      contactRight: 72,
      power: 80,
      eye: 70,
      run: 62,
      clutch: 68,
      nationality: '海外',
      origin: 'アメリカ',
    );
    final lines = ForeignEngine.abroadRecord(batter, 'アメリカ', 2026, Random(42));
    expect(lines, isNotEmpty);
    expect(batter.abroadStats.length, lines.length);
    for (final s in batter.abroadStats) {
      expect(s.games, greaterThan(0));
      expect(s.atBats, greaterThan(0));
      expect(s.hits, inInclusiveRange(s.homeRuns, s.atBats));
      expect(s.totalBases, s.hits + s.doubles + s.triples * 2 + s.homeRuns * 3);
      expect(s.strikeouts, lessThanOrEqualTo(s.atBats));
    }

    const legacyBatterLine = '2026　3A　118試合 打率.284 22本 78打点 OPS.862';
    final synB = AbroadStats.fromLine(batter, legacyBatterLine, isPitcher: false);
    expect(synB.games, 118);
    expect(synB.homeRuns, 22);
    expect(synB.rbi, 78);
    expect((synB.battingAverage - 0.284).abs(), lessThan(0.01));
    final pa = synB.atBats + synB.walks + synB.hbp + synB.sacFlies;
    final ops = (synB.hits + synB.walks + synB.hbp) / pa + synB.totalBases / synB.atBats;
    expect((ops - 0.862).abs(), lessThan(0.03));

    final pitcher = Player(
      id: 'FP1',
      isPitcher: true,
      lastName: 'テスト',
      firstName: 'ピッチャー',
      mainPos: '投手',
      age: 29,
      pitchPower: 76,
      control: 68,
      stamina: 72,
      nationality: '海外',
      origin: 'アメリカ',
    );
    const legacyPitcherLine = '2026　3A　24試合 11勝6敗 防御率3.12 141.1回 138奪三振';
    final synP = AbroadStats.fromLine(pitcher, legacyPitcherLine, isPitcher: true);
    expect(synP.pitchApps, 24);
    expect(synP.starts, greaterThan(0));
    expect(synP.wins, 11);
    expect(synP.losses, 6);
    expect(synP.inningsPitched, 141 * 3 + 1);
    expect(synP.pitcherStrikeouts, 138);
    expect(synP.hitsAllowed, greaterThan(0));
    expect(synP.pitcherWalks, greaterThan(0));
    expect((synP.era - 3.12).abs(), lessThan(0.10));
  });

  test('② 3D打撃物理は引っ張り方向のHRが流し方向より明確に多くなる', () {
    final rnd = Random(12345);
    final skill = BatterSkill(meet: 70, power: 82, eye: 68, trajectory: 4, pull: 0.7, lefty: false, bat: Player(id: 'B', isPitcher: false, lastName: 'A', firstName: 'B', mainPos: '一塁手', age: 25).bat);
    const read = SwingRead(0.6, 148, 126, 0.2);
    final eng = PhysicsEngine();
    var pullHr = 0, centerHr = 0, oppoHr = 0;

    for (var i = 0; i < 3000; i++) {
      final zx = (rnd.nextDouble() * 2 - 1) * 0.85;
      final zz = (rnd.nextDouble() * 2 - 1) * 0.85;
      final fast = rnd.nextDouble() < 0.6;
      final spd = fast ? 147.0 : 126.0;
      final sw = SwingModel.swing(
        skill,
        read,
        IncomingPitch(
          perceivedKmh: 147,
          stuff: 70,
          guessKmh: 147,
          guessALate: V3.zero,
          guessSame: fast,
          prevKmh: 145,
          speedKmh: spd,
          time: 18.44 / (spd / 3.6),
          vel: V3(0, -spd / 3.6, -2.2),
          omega: const V3(190, 0, 0),
          aLate: fast ? V3.zero : const V3(0, 0, -3.5),
          zoneX: zx,
          zoneZ: zz,
          fastLike: fast,
          sharp: 65,
          brk: fast ? 0 : 0.4,
          hanging: false,
        ),
        rnd: rnd,
      );
      if (sw.whiff || sw.ball == null) continue;
      final b = sw.ball!;
      final dir = b.vel.y <= 0 ? (b.vel.x >= 0 ? 60.0 : -60.0) : b.direction;
      if (dir.abs() > 45) continue;
      final traj = eng.simulateTrajectory(HitVector(b.speed, b.launch, dir, b.backspinRpm, omega: b.omega));
      var hr = false;
      for (final pt in traj) {
        final ang = atan2(pt.x, pt.y) * 180 / pi;
        if (sqrt(pt.x * pt.x + pt.y * pt.y) >= PhysicsConstants.getFenceDistance(ang)) {
          hr = pt.z > PhysicsConstants.getFenceHeight(ang);
          break;
        }
      }
      if (!hr) continue;
      if (dir < -15) {
        pullHr++;
      } else if (dir <= 15) {
        centerHr++;
      } else {
        oppoHr++;
      }
    }

    print('HR分布 (右打者3000スイング): 引っ張り(左)=$pullHr, 中=$centerHr, 流し(右)=$oppoHr');
    expect(pullHr + centerHr, greaterThan(oppoHr * 2));
    expect(pullHr, greaterThan(oppoHr));
  });
}
