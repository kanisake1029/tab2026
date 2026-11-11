// ignore_for_file: avoid_print
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/db/app_database.dart';
import 'package:npb_pennant_app/models/player.dart';
import 'package:npb_pennant_app/providers/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SRC の写しの今日（開幕日）だけ、全員の背番号をすぐ変えられるように → OUT
void main() {
  test('open num', () async {
    SharedPreferences.setMockInitialValues({});
    const src = String.fromEnvironment('SRC'), outP = String.fromEnvironment('OUT');
    final out = File(outP);
    if (out.existsSync()) out.deleteSync();
    await File(src).copy(out.path);
    final db = AppDatabase(NativeDatabase(out));
    final a = AppState(db);
    while (!a.loaded) { await Future.delayed(const Duration(milliseconds: 20)); }
    a.openingNumberDay = '${a.currentDate.year}-${a.currentDate.month.toString().padLeft(2, '0')}-${a.currentDate.day.toString().padLeft(2, '0')}';
    final my = a.myTeam!;
    print('日付 ${a.currentDate} 特別な日 ${a.openingNumberDay} → ${a.isOpeningNumberDay}');
    // 写しの別の写しで、入れ替えができるか・変遷に残らないかを試す
    final x = my.players.firstWhere((p) => p.registeredName == '菅原 一希'), y = my.players.firstWhere((p) => !p.ikusei && p.registeredName != '菅原 一希');
    print('試し前 ${x.registeredName}#${x.uniformText} ${y.registeredName}#${y.uniformText}');
    await a.saveData();
    await Future.delayed(const Duration(seconds: 2));
    if (const String.fromEnvironment('TRY') != '1') { await db.close(); return; }
    final nx = y.uniformNumber, ny = x.uniformNumber;
    print('入れ替え ${a.setNumbersBulk(my, {x.id: nx, y.id: ny}) ?? 'OK'} → ${x.registeredName}#${x.uniformText} ${y.registeredName}#${y.uniformText}');
    final h = await a.numberHistory(my);
    print('変遷 ${h.entries.map((e) => '#${uniformLabel(e.key)} ${e.value.map((v) => v.$2).join('/')}').join(' ')}');
    await db.close();
  });
}
