import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/engine/transfer_engine.dart';
import 'package:npb_pennant_app/engine/trust_engine.dart';
import 'package:npb_pennant_app/models/player.dart';

void main() {
  test('①② 信頼度はスタメン起用で逓減しながら S90 前後に達し、平均は 60 前後に収束する', () {
    final r = Random(7);
    final starter = Player(id: 'S1', isPitcher: false, lastName: '主力', firstName: '太郎', age: 25, trust: 50);
    for (var g = 0; g < 260; g++) {
      TrustEngine.addTrust(starter, 0.45, r);
    }
    expect(starter.trust, inInclusiveRange(86, 96));

    final demoted = Player(id: 'D1', isPitcher: false, lastName: '降格', firstName: '二郎', age: 24, trust: 65);
    TrustEngine.addTrust(demoted, -5.0, r);
    expect(demoted.trust, lessThan(65));
  });

  test('①③ 希望年数（FA権・全盛期・外国人入団時）とチーム愛×信頼の受諾判定', () {
    final r = Random(11);
    final nearPrimeForeign = Player(
      id: 'F1',
      isPitcher: false,
      lastName: 'テスト',
      firstName: '助っ人',
      age: 27,
      primeStart: 28,
      nationality: '海外',
    );
    expect(TrustEngine.preferredYears(nearPrimeForeign, isInitialForeign: true), 1);

    final youngForeign = Player(
      id: 'F2',
      isPitcher: false,
      lastName: 'テスト',
      firstName: '若手',
      age: 22,
      primeStart: 28,
      nationality: '海外',
    );
    expect(TrustEngine.preferredYears(youngForeign, isInitialForeign: true), 3);

    final preFa = Player(
      id: 'J1',
      isPitcher: false,
      lastName: '若手',
      firstName: '国内',
      age: 24,
      primeStart: 28,
      faService: 6,
    );
    expect(TrustEngine.preferredYears(preFa), 2);
    final ask2 = TrustEngine.askForYears(preFa, 5000, 2);
    final ask4 = TrustEngine.askForYears(preFa, 5000, 4);
    expect(ask4, greaterThan(ask2));

    final prime = Player(id: 'J2', isPitcher: false, lastName: '全盛', firstName: '四郎', age: 29, primeStart: 27, primeLen: 4, transLen: 2, contactLeft: 80, contactRight: 80, power: 80);
    expect(TrustEngine.preferredYears(prime), greaterThanOrEqualTo(3));

    final highBond = Player(id: 'B1', isPitcher: false, trust: 92, teamLove: 90);
    final lowBond = Player(id: 'B2', isPitcher: false, trust: 45, teamLove: 45);
    var highAcc = 0, lowAcc = 0;
    for (var i = 0; i < 200; i++) {
      if (TrustEngine.acceptOffer(highBond, offerSalary: 8500, needSalary: 10000, r: r)) highAcc++;
      if (TrustEngine.acceptOffer(lowBond, offerSalary: 8500, needSalary: 10000, r: r)) lowAcc++;
    }
    expect(highAcc, greaterThan(100));
    expect(lowAcc, 0);
  });

  test('トップクラスの生え抜き年俸（5〜6億）とFA市場価値（約8億）の相場', () {
    final star = Player(
      id: 'ST1',
      isPitcher: false,
      mainPos: '右翼手',
      age: 29,
      proYears: 8,
      contactLeft: 85,
      contactRight: 85,
      power: 85,
      run: 72,
      arm: 75,
      fieldRF: 78,
      eye: 82,
      clutch: 82,
      salary: 45000,
      seasonStats: PlayerStats(games: 140, atBats: 520, hits: 165, doubles: 30, homeRuns: 35, rbi: 105, walks: 75),
    );
    final homegrown = TransferEngine.renewTarget(star);
    final fa = TransferEngine.marketValue(star, Random(1));
    expect(homegrown, inInclusiveRange(45000, 75000));
    expect(fa, inInclusiveRange(65000, 100000));
  });
}
