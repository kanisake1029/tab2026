// ignore_for_file: avoid_print
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/db/app_database.dart';

void main() {
  test('vacuum real save', () async {
    final tmpDir = Directory.systemTemp.createTempSync('tab_vac');
    AppDatabase.documentsPathOverride = tmpDir.path;
    final f = File('${tmpDir.path}/npb_pennant.sqlite');
    await File('backup/s25_20261111_now.sqlite').copy(f.path);
    final db = AppDatabase(NativeDatabase(f), true);
    final before = f.lengthSync();
    final teams0 = (await db.select(db.teamRows).get()).length;
    final sw = Stopwatch()..start();
    final did = await db.vacuumIfBloated();
    print('詰めた=$did ${before ~/ 1000000}MB → ${f.lengthSync() ~/ 1000000}MB  ${sw.elapsedMilliseconds}ms  チーム行 $teams0 → ${(await db.select(db.teamRows).get()).length}');
    sw.reset();
    final ok = await db.backupSlot(label: 'テスト', gameDate: 'x');
    final b = (await AppDatabase.listBackups(1)).first;
    print('控え=$ok ${b.bytes ~/ 1000000}MB  ${sw.elapsedMilliseconds}ms');
    await db.close();
    tmpDir.deleteSync(recursive: true);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
