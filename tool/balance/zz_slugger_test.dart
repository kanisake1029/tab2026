// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/db/app_database.dart';
import 'package:npb_pennant_app/providers/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('sluggers', () async {
    SharedPreferences.setMockInitialValues({});
    final tmp = File('${Directory.systemTemp.path}/s25_sl.sqlite');
    await File('backup/s25_opening.sqlite').copy(tmp.path);
    final a = AppState(AppDatabase(NativeDatabase(tmp)));
    while (!a.loaded) { await Future.delayed(const Duration(milliseconds: 20)); }
    for (final nm in ['河野 玲央', '村田 大成']) {
      for (final t in a.teams) {
        for (final p in t.players.where((p) => p.registeredName == nm)) {
          final j = p.toJson()..removeWhere((k, v) => k.contains('tats') || k == 'pitches' || k == 'history' || v is List && v.length > 12 || v is Map && v.length > 12);
          print('JSON ${jsonEncode(j)}');
        }
      }
    }
  });
}
