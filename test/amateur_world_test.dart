import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/engine/amateur_engine.dart';
import 'package:npb_pennant_app/engine/draft_engine.dart';
import 'package:npb_pennant_app/models/amateur.dart';
import 'package:npb_pennant_app/utils/name_data.dart';

void main() {
  test('高校3,400校・大学162校・社会人90チームができる', () {
    final w = AmateurEngine.generate(2025, Random(1));
    final hs = w.ofKind('高校').toList();
    expect(hs.length, 3400);
    expect(w.ofKind('大学').length, 162);
    expect(w.ofKind('社会人').length, 90);
    // 名前はすべて違う
    expect(w.teams.map((t) => t.name).toSet().length, w.teams.length);
    // 都道府県ごとの校数：東京が最も多く、鳥取が最も少ない
    final per = AmateurEngine.hsPerPref();
    final tokyo = NameData2.prefectures.indexWhere((p) => p.$1 == '東京都');
    final tottori = NameData2.prefectures.indexWhere((p) => p.$1 == '鳥取県');
    expect(per.reduce(max), per[tokyo]);
    expect(per.reduce(min), per[tottori]);
    print('東京${per[tokyo]}校 鳥取${per[tottori]}校 大阪${per[NameData2.prefectures.indexWhere((p) => p.$1 == '大阪府')]}校');
    // 大学は各地区6校
    for (var rg = 0; rg < amRegions.length; rg++) {
      expect(w.ofKind('大学').where((t) => t.region == rg).length, 18);
    }
    final strong = hs.where((t) => t.strength >= 70).length;
    print('強豪（強さ70以上）$strong校 例：${hs.take(5).map((t) => '${t.name}(${t.strength})').join(' ')}');
    expect(strong, inInclusiveRange(40, 250));
  });

  test('保存して読み込むと同じになる（大きさも確かめる）', () {
    final w = AmateurEngine.generate(2025, Random(2));
    final raw = base64.encode(gzip.encode(utf8.encode(jsonEncode(w.toJson()))));
    print('保存の大きさ ${raw.length ~/ 1024}KB');
    final back = AmWorld.fromJson(jsonDecode(utf8.decode(gzip.decode(base64.decode(raw)))) as Map<String, dynamic>);
    expect(jsonEncode(back.toJson()), jsonEncode(w.toJson()));
  });

  test('4月の切り替え：進級・卒業・進路、パイプは弱まる', () {
    final r = Random(3);
    final w = AmateurEngine.generate(2025, r);
    final hs = w.ofKind('高校').first, un = w.ofKind('大学').first;
    hs.pipe['T1'] = 1.0;
    for (var i = 0; i < 200; i++) {
      final pr = DraftEngine.makeAmateur(r, 2025, 'A$i', i.isEven ? '高校' : '大学');
      w.players.add(AmPlayer(player: pr.player, teamId: i.isEven ? hs.id : un.id, grade: i.isEven ? 3 : 4));
    }
    AmateurEngine.newYear(w, 2026, r);
    expect(w.year, 2026);
    expect(hs.pipe['T1'], closeTo(0.8, 1e-9));
    // 卒業した高校生は大学・社会人に進むか、やめる。高校に残る選手はいない
    expect(w.players.where((p) => p.teamId == hs.id), isEmpty);
    final toUniv = w.players.where((p) => w.team(p.teamId)!.kind == '大学' && p.grade == 1).length;
    final toCorp = w.players.where((p) => w.team(p.teamId)!.kind == '社会人').length;
    print('進学$toUniv人 社会人$toCorp人 残り${w.players.length}人（200人中）');
    expect(toUniv, greaterThan(20));
    expect(toCorp, greaterThan(20));
    expect(w.players.length, lessThan(200));
  });
}
