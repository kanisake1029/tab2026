import 'dart:math' as m;
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/models/stadium.dart';

void main() {
  test('標準球場はこれまでの試合のフェンスと同じ（差 5cm 未満）', () {
    final s = Stadium.standard;
    var worst = 0.0;
    for (var a = -45.0; a <= 45; a += 0.25) {
      worst = m.max(worst, (s.fenceDistance(a) - (100 + 22 * m.cos(2 * a * m.pi / 180))).abs());
      expect(s.fenceHeight(a), closeTo(3.0, 1e-9));
    }
    expect(worst, lessThan(0.05));
    expect(s.fenceDistance(45), closeTo(100, 1e-9));
    expect(s.fenceDistance(-22.5), closeTo(115.56, 0.01));
    expect(s.fenceDistance(0), closeTo(122, 1e-9));
    final back = Stadium.fromJson(s.toJson());
    expect(back.fenceDistance(10), closeTo(s.fenceDistance(10), 1e-9));
    expect(back.stands.length, s.stands.length);
  });

  test('標準球場は公認野球規則 2.01 の目安を満たす', () {
    final s = Stadium.standard;
    const ft = 0.3048;
    expect(s.backstop, greaterThanOrEqualTo(60 * ft));
    expect(s.foulFirst, greaterThanOrEqualTo(60 * ft));
    expect(s.foulThird, greaterThanOrEqualTo(60 * ft));
    expect(s.fenceDistance(45), greaterThanOrEqualTo(320 * ft));
    expect(s.fenceDistance(-45), greaterThanOrEqualTo(320 * ft));
    expect(s.fenceDistance(0), greaterThanOrEqualTo(400 * ft));
  });
}
