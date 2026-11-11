import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/engine/amateur_engine.dart';
import 'package:npb_pennant_app/engine/amateur_scout.dart';
import 'package:npb_pennant_app/engine/amateur_season.dart';
import 'package:npb_pennant_app/engine/roster_engine.dart';
import 'package:npb_pennant_app/models/amateur.dart';

/// 1年（4〜10月）の発掘を回す
Map<String, int> runYear(AmWorld w, List<ScoutNet> nets, Random r) {
  for (var d = DateTime(w.year, 4, 1); d.isBefore(DateTime(w.year, 11, 1)); d = d.add(const Duration(days: 1))) {
    AmateurSeason.playDay(w, d);
    if (d.weekday == DateTime.monday) {
      AmateurScout.week(w, nets, d, r);
      for (final s in const ['春', '夏']) {
        final k = w.comp('$s-koshien');
        if (k != null && k.done && w.flags.add('$s-koshien')) AmateurScout.koshienBuzz(w, k, [for (final n in nets) n.teamId], r);
      }
    }
  }
  return {for (final n in nets) n.teamId: w.players.where((p) => p.foundBy.contains(n.teamId)).length};
}

void main() {
  test('発掘の人数：スカウトの人数と眼力で変わる', () {
    final r = Random(11);
    // ふつうの顔ぶれ（5〜9地区、眼力50〜70）の11球団＋調べる球団
    List<ScoutNet> nets(Map<int, List<int>> mine) => [
          for (var i = 0; i < 11; i++)
            ScoutNet('T$i', {
              for (final rg in (List.generate(9, (k) => k)..shuffle(Random(i))).take(5 + i % 5)) rg: [50 + (i * 7) % 21],
            }),
          ScoutNet('ME', mine),
        ];
    for (final (label, mine) in [
      ('地区担当2人・眼力C(60)', {2: [60], 6: [60]}),
      ('ふつう（7地区・眼力60）', {for (var rg = 0; rg < 7; rg++) rg: [60]}),
      ('地区担当18人・眼力A(85)', {for (var rg = 0; rg < 9; rg++) rg: [85, 85]}),
    ]) {
      final w = AmateurEngine.generate(2026, Random(3));
      final known = runYear(w, nets(mine), r);
      final all = w.players.where((p) => p.foundBy.isNotEmpty).toList();
      final hs = all.where((p) => w.team(p.teamId)!.kind == '高校').length;
      final un = all.where((p) => w.team(p.teamId)!.kind == '大学').length;
      final mineP = all.where((p) => p.foundBy.contains('ME')).toList();
      final good = mineP.where((p) => RosterEngine.potentialOvr(p.player) >= 70).length;
      final cpu = known.entries.where((e) => e.key != 'ME').map((e) => e.value).toList()..sort();
      print('$label：自球団 ${known['ME']}人（伸びしろ70以上 $good人）　CPU ${cpu.first}〜${cpu.last}人　全体 ${all.length}人（高校$hs・大学$un・社会人${all.length - hs - un}）');
    }
  });
}
