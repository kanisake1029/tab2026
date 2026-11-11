import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/engine/fielding_gen.dart';
import 'package:npb_pennant_app/utils/grade_utils.dart';

/// 守備適性の分布：本職は最低E45・多くはD〜B・ときどきA。守れる位置（F35以上）は型の2つ＋ランダム2つ
void main() {
  test('本職とサブポジションの分布', () {
    final r = Random(1);
    final grades = <String, int>{};
    var subs = 0;
    const n = 4000;
    for (var i = 0; i < n; i++) {
      final pos = FieldingGen.positions[i % FieldingGen.positions.length];
      final f = FieldingGen.generate(pos, r);
      final g = GradeUtils.getGrade(f[pos]!);
      grades[g] = (grades[g] ?? 0) + 1;
      expect(f[pos]!, greaterThanOrEqualTo(45));
      subs += FieldingGen.positions.where((p) => p != pos && f[p]! >= 35).length;
    }
    // ignore: avoid_print
    print('本職 $grades　サブポジション平均 ${(subs / n).toStringAsFixed(2)}');
    final db = (grades['D'] ?? 0) + (grades['C'] ?? 0) + (grades['B'] ?? 0);
    expect(db / n, greaterThan(0.8));
    expect((grades['A'] ?? 0) + (grades['S'] ?? 0), greaterThan(0));
    expect(subs / n, greaterThanOrEqualTo(3.5));
  });
}
