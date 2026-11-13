import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/db/app_database.dart';

/// データベースの整理：空きページを詰める・自動の控え（3世代）・控えへの復元・ドラフト候補の表・1球ごとの記録の保持
void main() {
  late Directory dir;
  late File dbFile;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('tab_db_test');
    AppDatabase.documentsPathOverride = dir.path;
    dbFile = File('${dir.path}/npb_pennant.sqlite');
  });
  tearDown(() {
    AppDatabase.documentsPathOverride = null;
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  AppDatabase open() => AppDatabase(NativeDatabase(dbFile), true);

  /// 試合の行を大量に入れてから、ほとんど消す（空きページが残る）
  Future<void> bloat(AppDatabase db) async {
    final big = jsonEncode({'t': List.filled(900, 'あいうえお')});
    await db.batch((b) => b.insertAll(db.matchRows, [for (var i = 0; i < 3000; i++) MatchRowsCompanion.insert(season: 2020, idx: i, json: big)]));
    await (db.delete(db.matchRows)..where((t) => t.idx.isBiggerOrEqualValue(100))).go();
  }

  test('空きページが多いときだけ詰める。中身は変わらない', () async {
    final db = open();
    await db.setKv('k', 'v');
    expect(await db.vacuumIfBloated(), false, reason: '小さいデータベースは詰めない');
    await bloat(db);
    final before = dbFile.lengthSync();
    expect(await db.vacuumIfBloated(), true);
    final after = dbFile.lengthSync();
    expect(after, lessThan(before ~/ 4), reason: '3000行→100行に減らしたので、ファイルも小さくなる');
    expect(await db.getKv('k'), 'v');
    expect((await db.select(db.matchRows).get()).length, 100);
    expect(await db.vacuumIfBloated(), false, reason: '詰めたあとはもう詰めない');
    await db.close();
  });

  test('控えは3世代まで。いちばん新しいものが先頭', () async {
    final db = open();
    for (var i = 1; i <= 4; i++) {
      await db.setKv('gen', '$i');
      expect(await db.backupSlot(label: '控え$i', gameDate: '2026年10月$i日'), true);
    }
    final list = await AppDatabase.listBackups(1);
    expect(list.map((b) => b.label).toList(), ['控え4', '控え3', '控え2'], reason: '4つ目を取ると、いちばん古い控え1が消える');
    expect(list.first.gameDate, '2026年10月4日');
    await db.close();
  });

  test('控えに戻す：戻す前の状態も残る', () async {
    var db = open();
    await db.setKv('gen', 'before');
    await db.backupSlot(label: 'ドラフト会議の前', gameDate: '2026年10月31日');
    await db.setKv('gen', 'after'); // ドラフトの結果が入った、という想定
    await db.close();

    final list = await AppDatabase.listBackups(1);
    expect(await AppDatabase.restoreBackup(list.first, currentGameDate: '2026年10月31日'), true);

    db = open();
    expect(await db.getKv('gen'), 'before', reason: '控えの状態に戻る');
    await db.close();

    final after = await AppDatabase.listBackups(1);
    expect(after.any((b) => b.gen == -1), true, reason: '戻す前の状態が「復元の直前の状態」として残る');
    // 戻す前の状態にも戻せる
    expect(await AppDatabase.restoreBackup(after.firstWhere((b) => b.gen == -1)), true);
    db = open();
    expect(await db.getKv('gen'), 'after');
    await db.close();
  });

  test('ドラフト候補は1人1行：変わった人だけ書き、無くなった人は消す', () async {
    final db = open();
    ProspectRowsCompanion row(String id, int sort, String json) => ProspectRowsCompanion.insert(id: id, sort: sort, json: json);
    await db.syncProspects([row('a', 0, '{"n":1}'), row('b', 1, '{"n":2}'), row('c', 2, '{"n":3}')], ['a', 'b', 'c']);
    expect((await db.loadProspectRows()).map((r) => r.id).toList(), ['a', 'b', 'c']);
    await db.syncProspects([row('b', 0, '{"n":22}')], ['b', 'c']); // b だけ変わり、a は無くなった
    final rows = await db.loadProspectRows();
    expect(rows.map((r) => r.id).toList(), ['b', 'c']);
    expect(rows.first.json, '{"n":22}');
    await db.syncProspects([], []); // ドラフトが終わって候補が空になった
    expect(await db.loadProspectRows(), isEmpty);
    await db.close();
  });

  test('1球ごとの記録は、直近2シーズンぶん残す', () async {
    final db = open();
    PitchRowsCompanion pr(int season) => PitchRowsCompanion.insert(
        season: season, matchIdx: 0, seq: 0, paIndex: 0, pitchNo: 1, battingHome: false, batter: 'b', batterHand: 'R', pitcher: 'p', pitchName: 'ストレート', speed: 150,
        x: 0, z: 0, inZone: true, balls: 0, strikes: 0, result: '見逃し', contact: '', fielder: '', outcome: '', playCode: '', breakDX: 0, breakDY: 0);
    await db.savePitches([pr(2025), pr(2026), pr(2027)]);
    Future<Set<int>> seasons() async => (await db.select(db.pitchRows).get()).map((r) => r.season).toSet();
    await db.compactSeason(2026); // 2026 年度が終わった：終わった2シーズン（2025・2026）は残す
    expect(await seasons(), {2025, 2026, 2027});
    await db.compactSeason(2027); // 2027 年度が終わった：2025 年が消える
    expect(await seasons(), {2026, 2027});
    await db.compactSeason(2027, keepPitchSeasons: 1); // 他球団も記録しているときは1シーズンだけ
    expect(await seasons(), {2027});
    await db.close();
  });
}
