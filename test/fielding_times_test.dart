import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/engine/fielding_times.dart';
import 'package:npb_pennant_app/engine/spec_constants.dart';
import 'package:npb_pennant_app/engine/field_time.dart';

/// 守備・走塁の秒数の表は、仕様書 6.1 の式と同じ値であること（表にまとめただけで、結果は変わらない）。
void main() {
  test('表の値は、これまでの式と同じ（能力 1〜100）', () {
    for (var a = 1; a <= 100; a++) {
      expect(Spec.reaction(a), closeTo(0.18 + 0.25 * (1 - a / 100), 1e-9), reason: '反応 $a');
      expect(Fielding.judge(a, 'CF'), closeTo(0.32 + (100 - a) * 0.002, 1e-9), reason: '外野の見極め $a');
      expect(Fielding.judge(a, 'SS'), closeTo(0.18 + (100 - a) * 0.002, 1e-9), reason: '内野の見極め $a');
      expect(Spec.transfer(a), closeTo(0.85 - 0.003 * a, 1e-9), reason: '握り替え $a');
      expect(Spec.throwMaxKmh(a), closeTo(110 + 0.48 * a, 1e-9), reason: '送球初速 $a');
      expect(Spec.sprint(a), closeTo(6.8 + 0.028 * a, 1e-9), reason: '走速度 $a');
    }
  });

  test('能力が高いほど速い（秒は短く、速度は大きく）', () {
    for (var a = 1; a < 100; a++) {
      expect(FieldTimes.reaction.at(a + 1), lessThan(FieldTimes.reaction.at(a)));
      expect(FieldTimes.judgeInfield.at(a + 1), lessThan(FieldTimes.judgeInfield.at(a)));
      expect(FieldTimes.judgeOutfield.at(a + 1), lessThan(FieldTimes.judgeOutfield.at(a)));
      expect(FieldTimes.transferSec.at(a + 1), lessThan(FieldTimes.transferSec.at(a)));
      expect(FieldTimes.throwKmh.at(a + 1), greaterThan(FieldTimes.throwKmh.at(a)));
      expect(FieldTimes.sprintMs.at(a + 1), greaterThan(FieldTimes.sprintMs.at(a)));
    }
  });

  test('30・60・90 の3点を通る。握り替えの比率は 60 で 1', () {
    expect(FieldTimes.reaction.at(30), 0.355);
    expect(FieldTimes.reaction.at(60), 0.28);
    expect(FieldTimes.reaction.at(90), 0.205);
    expect(FieldTimes.transferRatio(60), 1.0);
    expect(FieldTimes.transferRatio(90), lessThan(1.0));
    expect(FieldTimes.transferRatio(30), greaterThan(1.0));
  });
}
