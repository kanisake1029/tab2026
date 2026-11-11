import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/engine/batting_splits.dart';
import 'package:npb_pennant_app/engine/matchup_book.dart';
import 'package:npb_pennant_app/models/player.dart';

void main() {
  test('コースのマス：打者から見て左上が1、左が内角', () {
    expect(BattingSplits.cell(0, 0, 'R'), 13); // ど真ん中
    expect(BattingSplits.cell(0.8, 0.8, 'R'), 7); // 右打者の内角高め
    expect(BattingSplits.cell(-0.8, 0.8, 'L'), 7); // 左打者は x が逆
    expect(BattingSplits.cell(1.5, 1.5, 'R'), 1); // 内角高めのボール
    expect(BattingSplits.cell(-1.5, -1.5, 'R'), 25); // 外角低めのボール
  });
  test('打球方向は5等分', () {
    expect(BattingSplits.dir(-60, 60), 0); // 左翼線
    expect(BattingSplits.dir(0, 100), 2); // センター
    expect(BattingSplits.dir(60, 60), 4); // 右翼線
  });
  test('足し算・保存・表示', () {
    final st = PlayerStats();
    final hit = VsLine()..ab = 1..h = 1..hr = 1;
    final k = VsLine()..ab = 1..so = 1;
    BattingSplits.add(st, hit, x: 0, z: 0, bats: 'R', pitchName: 'ストレート', speed: 151, landX: 0, landY: 120);
    BattingSplits.add(st, k, x: 0, z: 0, bats: 'R', pitchName: 'フォーク', speed: 138);
    expect(st.spl['c13'], [2, 1, 1, 1]);
    expect(st.spl['tストレート'], [1, 1, 1, 0]);
    expect(st.spl['v4'], [1, 1, 1, 0]);
    expect(st.spl['d2'], [1, 1, 1, 0]);
    final back = PlayerStats.fromJson(st.toJson());
    final sum = PlayerStats()..add(back)..add(back);
    expect(sum.spl['c13'], [4, 2, 2, 2]);
    expect(BattingSplits.text(st.spl['c13']), '.500(2-1) HR 1 K 1');
    expect(BattingSplits.text(null), '-');
  });
}
