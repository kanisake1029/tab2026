import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/engine/amateur_engine.dart';
import 'package:npb_pennant_app/engine/amateur_season.dart';
import 'package:npb_pennant_app/engine/draft_engine.dart';
import 'package:npb_pennant_app/models/amateur.dart';

void main() {
  test('1年の大会・リーグが日程どおりに進む', () {
    final r = Random(5);
    final w = AmateurEngine.generate(2025, r);
    // 有望株を少し置く（成績が残るか見る）
    final strong = (w.ofKind('高校').toList()..sort((a, b) => b.strength.compareTo(a.strength))).take(20).toList();
    for (var i = 0; i < 20; i++) {
      final pr = DraftEngine.makeAmateur(r, 2025, 'X$i', '高校', tier: 2);
      w.players.add(AmPlayer(player: pr.player, teamId: strong[i].id, grade: 3));
    }
    final sw = Stopwatch()..start();
    for (var d = DateTime(2025, 4, 1); d.isBefore(DateTime(2025, 11, 1)); d = d.add(const Duration(days: 1))) {
      AmateurSeason.playDay(w, d);
      w.simDate = d;
    }
    print('4月〜10月の計算 ${sw.elapsedMilliseconds}ms');
    for (final s in ['春', '夏']) {
      final k = w.comp('$s-koshien')!;
      expect(k.teams.length, 50);
      expect(k.rounds.first.length, 64);
      expect(k.rounds.first.where((x) => x.isEmpty).length, 14); // シード14校
      expect(k.done, true);
      final champ = w.team(k.champion!)!;
      print('$sの甲子園 優勝 ${champ.name}（強さ${champ.strength}・${amRegions[champ.region]}）');
    }
    for (var rg = 0; rg < amRegions.length; rg++) {
      final c = w.comp('秋-region-$rg')!;
      expect(c.teams.length, inInclusiveRange(12, 22));
      expect(c.done, true);
      final lg = w.comp('league-$rg-0')!;
      expect(lg.done, true);
      final st = AmateurSeason.standings(lg);
      for (final x in st) {
        expect(x.$2 + x.$3 + x.$4, 50);
      }
      if (rg == 2) print('${lg.name}：${st.map((x) => '${w.team(x.$1)!.name} ${x.$2}-${x.$3}').join(' / ')}');
    }
    final main = w.comp('main')!;
    expect(main.teams.length, 32);
    expect(main.done, true);
    expect(w.comps.where((c) => c.stage == 'pref').every((c) => c.done), true);
    // 有望株のアマ時代の成績
    final rec = w.players.expand((p) => p.record).toList();
    print('成績の行 ${rec.length}件　例：${rec.take(3).join(' ｜ ')}');
    expect(rec.length, greaterThan(40));
    // 保存の大きさ
    final raw = base64.encode(gzip.encode(utf8.encode(jsonEncode(w.toJson()))));
    print('保存の大きさ ${raw.length ~/ 1024}KB');
    final back = AmWorld.fromJson(jsonDecode(utf8.decode(gzip.decode(base64.decode(raw)))) as Map<String, dynamic>);
    expect(jsonEncode(back.toJson()), jsonEncode(w.toJson()));
    // 次の年度
    AmateurEngine.newYear(w, 2026, r);
    expect(w.comps.every((c) => !c.done), true);
    expect(w.ofKind('高校').where((t) => t.history.isNotEmpty).length, greaterThan(50));
  });
}
