import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/db/app_database.dart';
import 'package:npb_pennant_app/providers/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 実機から取り出した旧形式のセーブ（ドラフト候補が kv の1つのJSON）を、新しい形（1人1行）に移しても、中身が変わらないこと。
///  backup/ は GitHub に上げていないので、ファイルがなければ飛ばす
void main() {
  const src = 'backup/s25_20261111_now.sqlite';

  Future<AppState> load(File f) async {
    final a = AppState(AppDatabase(NativeDatabase(f)));
    while (!a.loaded) {
      await Future.delayed(const Duration(milliseconds: 20));
    }
    return a;
  }

  test('ドラフト候補を kv から表に移す', () async {
    if (!File(src).existsSync()) {
      markTestSkipped('$src が無いので飛ばす');
      return;
    }
    SharedPreferences.setMockInitialValues({});
    final tmp = File('${Directory.systemTemp.path}/tab_migration_test.sqlite');
    await File(src).copy(tmp.path);

    final a = await load(tmp);
    final before = [for (final p in a.prospects) jsonEncode(p.toJson())];
    final teamCount = a.teams.length;
    expect(before.length, greaterThan(500), reason: '旧形式のセーブから、候補を読めている');
    expect(await a.db.getKv('prospects'), isNotNull, reason: '移す前は kv に入っている');
    expect(await a.db.loadProspectRows(), isEmpty);

    await a.saveData();
    await a.saveData(); // 2回目の保存は、変わっていない候補を書き直さない（エラーにならないこと）
    await a.db.close();

    final raw = AppDatabase(NativeDatabase(tmp));
    final rows = await raw.loadProspectRows();
    expect(rows.length, before.length, reason: '1人1行の表に移った');
    expect(await raw.getKv('prospects'), isNull, reason: '以前の形は消える');
    await raw.close();

    final b = await load(tmp);
    expect([for (final p in b.prospects) jsonEncode(p.toJson())], before, reason: '読み直しても、候補の中身と並びは同じ');
    expect(b.teams.length, teamCount);
    await b.db.close();
    tmp.deleteSync();
  }, timeout: const Timeout(Duration(minutes: 5)));
}
