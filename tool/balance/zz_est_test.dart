// ignore_for_file: avoid_print
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/db/app_database.dart';
import 'package:npb_pennant_app/providers/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SRC の写しに外国人の1年目の推定成績を書く → OUT
void main() {
  test('est', () async {
    SharedPreferences.setMockInitialValues({});
    const src = String.fromEnvironment('SRC', defaultValue: 'backup/s25_opening.sqlite');
    const outP = String.fromEnvironment('OUT', defaultValue: 'backup/s25_opening_est.sqlite');
    final out = File(outP);
    if (out.existsSync()) out.deleteSync();
    await File(src).copy(out.path);
    final db = AppDatabase(NativeDatabase(out));
    final a = AppState(db);
    while (!a.loaded) { await Future.delayed(const Duration(milliseconds: 20)); }
    print(await a.estimateForeignFirstYear());
    print(await a.fixChronicle());
    print('chk2 ${await a.fixChronicle()}');
    print('2回目（重ねて書かない）：${await a.estimateForeignFirstYear()}');
    final j = a.myTeam!.players.firstWhere((p) => p.registeredName == 'イバン・ジョンソン');
    for (final h in await a.playerHistory(j.id)) { print('年度別 ${h.$1} ${h.$2} 1軍${h.$3.pitchApps}登板 2軍${h.$4.pitchApps}登板'); }
    print('通算 ${j.career.pitchApps}登板 ${j.career.wins}勝 日付 ${a.currentDate}');
    for (final y in [2025, 2026]) { for (final e in await a.chronicleOf(y)) { if (RegExp('小西|島川|ドラフト[5-9]位|育成ドラフト[4-9]位|ジョンソン|ストーン|宣世宇|ミルズ|オリバレス').hasMatch('${e['t']}') && (e['team'] == 'C0' || e['team'] == 'P1' || e['team'] == 'P3')) print('C ${e['d']} ${e['k']} ${e['t']}'); } }
    print('歴代用の行数 ${(await a.allPlayerSeasons()).length}');
    await Future.delayed(const Duration(seconds: 2));
    await db.close();
  });
}
