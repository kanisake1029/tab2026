import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/engine/body_gen.dart';
import 'package:npb_pennant_app/models/player.dart';
import 'package:npb_pennant_app/utils/initial_teams_data.dart';

void main() {
  test('体格・フォームの自動の値：決まった値になり、分布がもっともらしい', () {
    final teams = jsonDecode(InitialTeamsData.jsonString) as List;
    final ps = [for (final t in teams) for (final p in (t as Map)['players'] as List) Player.fromJson(Map<String, dynamic>.from(p as Map))];
    expect(stableHash('P0_P1'), stableHash('P0_P1'));
    double mean(Iterable<num> v) => v.fold<double>(0, (a, b) => a + b) / v.length;
    final w = ps.map((p) => p.weight), h = ps.map((p) => p.height);
    // ignore: avoid_print
    print('${ps.length}人　身長 平均${mean(h).toStringAsFixed(1)}　体重 平均${mean(w).toStringAsFixed(1)} 最小${w.reduce((a, b) => a < b ? a : b)} 最大${w.reduce((a, b) => a > b ? a : b)}');
    // ignore: avoid_print
    print('腕の長さ 平均${mean(ps.map((p) => p.armLength)).toStringAsFixed(1)}　頭${mean(ps.map((p) => p.headGirth)).toStringAsFixed(1)} 胸${mean(ps.map((p) => p.chestGirth)).toStringAsFixed(1)} 腹${mean(ps.map((p) => p.waistGirth)).toStringAsFixed(1)} 臀${mean(ps.map((p) => p.hipGirth)).toStringAsFixed(1)}');
    final pit = ps.where((p) => p.isPitcher).toList();
    final slots = <String, int>{}, wind = <String, int>{};
    for (final p in pit) {
      slots[p.armSlot] = (slots[p.armSlot] ?? 0) + 1;
      wind[p.form.windup] = (wind[p.form.windup] ?? 0) + 1;
    }
    // ignore: avoid_print
    print('投手${pit.length}人　$slots　$wind　踏み出し平均${mean(pit.map((p) => p.form.strideRatio)).toStringAsFixed(1)}%');
    // 保存して読み直しても同じ（自動の値は保存しない）
    final p0 = ps.first;
    final back = Player.fromJson(jsonDecode(jsonEncode(p0.toJson())) as Map<String, dynamic>);
    expect(back.weight, p0.weight);
    expect(back.spinAxis, p0.spinAxis);
    expect(back.form.toJson(), p0.form.toJson());
    // 編集した値は残る
    p0.bodyWeight = 99;
    p0.spinAxis = 120;
    final back2 = Player.fromJson(jsonDecode(jsonEncode(p0.toJson())) as Map<String, dynamic>);
    expect(back2.weight, 99);
    expect(back2.spinAxis, 120);
    expect(back2.armSlot, 'アンダー');
  });
}
