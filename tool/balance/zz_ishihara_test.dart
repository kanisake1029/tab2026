// ignore_for_file: avoid_print
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/db/app_database.dart';
import 'package:npb_pennant_app/providers/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('ishihara', () async {
    SharedPreferences.setMockInitialValues({});
    final tmp = File('${Directory.systemTemp.path}/s25_ishi.sqlite');
    await File(const String.fromEnvironment('SAVE', defaultValue: 'backup/s25_20261108.sqlite')).copy(tmp.path);
    final a = AppState(AppDatabase(NativeDatabase(tmp)));
    while (!a.loaded) { await Future.delayed(const Duration(milliseconds: 20)); }
    print('日付 ${a.currentDate}');
    for (final t in a.teams) {
      for (final p in t.players.where((p) => p.registeredName.contains('石原'))) {
        final s = p.seasonStats;
        final j = p.toJson();
        print('${t.shortName} ${p.registeredName} ${p.mainPosition} 年齢${p.age} 打${p.bats} 弾道${j['trajectory']} ミL${p.contactLeft} R${p.contactRight} パ${p.power} 眼${p.eye} 走${p.run} 型${j['type']} 特能${j['abilities'] ?? j['skills']}');
        print('  打数${s.atBats} 安打${s.hits} 二${s.doubles} 三${s.triples} 本${s.homeRuns} 振${s.strikeouts} 四${s.walks}');
        print('  ${j.keys.toList()}');
      }
    }
  });
}
