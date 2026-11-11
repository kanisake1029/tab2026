// ignore_for_file: avoid_print
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/db/app_database.dart';
import 'package:npb_pennant_app/models/player.dart';
import 'package:npb_pennant_app/providers/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SRC の写しに：推定の中継ぎの勝敗・入団直後の選手の背番号をすぐ変えられる印 → OUT
void main() {
  test('num', () async {
    SharedPreferences.setMockInitialValues({});
    const src = String.fromEnvironment('SRC'), outP = String.fromEnvironment('OUT');
    final out = File(outP);
    if (out.existsSync()) out.deleteSync();
    await File(src).copy(out.path);
    final db = AppDatabase(NativeDatabase(out));
    final a = AppState(db);
    while (!a.loaded) { await Future.delayed(const Duration(milliseconds: 20)); }
    print('勝敗：${await a.fixPreDecisions()}');
    print('2回目：${await a.fixPreDecisions()}');
    final my = a.myTeam!;
    final from = a.currentDate.subtract(const Duration(days: 30));
    final ids = <String>{};
    for (final e in await a.chronicleOf(a.startYear)) {
      final d = DateTime.parse('${e['d']}');
      if (e['team'] == my.id && (e['k'] == 'join' || e['k'] == 'reg') && !d.isBefore(from)) ids.add('${e['pid']}');
    }
    for (final p in my.players.where((p) => ids.contains(p.id))) {
      a.markNumberFree(p, a.currentDate);
      print('すぐ変えられる ${p.registeredName} #${p.uniformText} 〜${p.numberFreeUntil}');
    }
    // 予約と2月1日の流れ（写しの中だけで確かめる）
    final x = my.players.firstWhere((p) => !p.ikusei && !a.numberFreeNow(p));
    print('予約の試し ${x.registeredName} #${x.uniformText} → ${a.setNumber(my, x, 98) ?? 'OK'} 来季 ${x.nextNumber}');
    final h = await a.numberHistory(my);
    print('変遷 ${h.length}件：${h.entries.take(6).map((e) => '#${e.key} ${e.value.map((v) => '${v.$1} ${v.$2} ${v.$3}').join(' / ')}').join(' | ')}');
    x.nextNumber = null; // 試しの予約は消す
    await a.saveData();
    await Future.delayed(const Duration(seconds: 2));
    await db.close();
  });
}
