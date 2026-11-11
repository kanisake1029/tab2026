import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/engine/fielding_gen.dart';
import 'package:npb_pennant_app/utils/player_generator.dart';

/// 以前の選手の守備を寄せる：本職を上げたら、型のサブポジションも同じ割合で上がる
void main() {
  test('本職とサブポジションを一緒に上げる', () {
    final p = generateNewTeam(year: 2026).players.firstWhere((x) => !x.isPitcher && x.mainPosition == '遊撃手');
    p.fieldSS = 40;
    p.field2B = 36; // 型のサブ（0.9倍）
    p.field3B = 32; // 型のサブ（0.8倍）
    p.fieldC = 1;
    p.field1B = 1;
    p.fieldLF = 1;
    p.fieldCF = 1;
    p.fieldRF = 1;
    FieldingGen.upgrade(p, Random(2));
    // ignore: avoid_print
    print('遊 ${p.fieldSS} 二 ${p.field2B} 三 ${p.field3B} 一 ${p.field1B} 左 ${p.fieldLF} 中 ${p.fieldCF} 右 ${p.fieldRF} 捕 ${p.fieldC}');
    expect(p.fieldSS, 46);
    expect(p.field2B, (36 * 46 / 40).round());
    expect(p.field3B, (32 * 46 / 40).round());
    expect(p.fieldC, 1);
  });
}
