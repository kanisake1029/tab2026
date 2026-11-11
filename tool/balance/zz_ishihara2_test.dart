// ignore_for_file: avoid_print
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/db/app_database.dart';
import 'package:npb_pennant_app/models/player.dart';
import 'package:npb_pennant_app/providers/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('ishihara sim', () async {
    SharedPreferences.setMockInitialValues({});
    final tmp = File('${Directory.systemTemp.path}/s25_ishi2.sqlite');
    await File('backup/s25_20261109.sqlite').copy(tmp.path);
    final a = AppState(AppDatabase(NativeDatabase(tmp)));
    while (!a.loaded) { await Future.delayed(const Duration(milliseconds: 20)); }
    final p = a.myTeam!.players.firstWhere((p) => p.registeredName == '石原 翼');
    final j = p.toJson();
    for (final k in ['height', 'h2', 'trajectory', 'clutch', 'trust', 'motivation', 'conditionFreq', 'conditionPhase', 'injuryDays', 'energy', 'maxEnergy', 'practiceInstruction', 'seasonSplits', 'streaks', 'baseline', 'growthType', 'phaseShift']) { print('$k: ${j[k]}'); }
    final ids = [p.id, ...a.myTeam!.players.where((q) => q.registeredName.contains('河野') || q.registeredName.contains('ミルズ')).map((q) => q.id)];
    for (final t in a.teams) { for (final q in t.players) { q.seasonStats = PlayerStats(); } }
    for (var i = 0; i < 60; i++) { a.playNextDay(); }
    for (final q in a.myTeam!.players.where((q) => ids.contains(q.id))) {
      final s = q.seasonStats;
      print('シム60日 ${q.registeredName} パ${q.power} 打数${s.atBats} 安${s.hits} 二${s.doubles} 本${s.homeRuns} 振${s.strikeouts}');
    }
  });
}
