import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/db/app_database.dart';
import 'package:npb_pennant_app/engine/field_time.dart';
import 'package:npb_pennant_app/engine/fielder_ai.dart';
import 'package:npb_pennant_app/engine/match_simulator.dart';
import 'package:npb_pennant_app/engine/play_resolver.dart';
import 'package:npb_pennant_app/providers/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('打球の種類ごとの安打率', () async {
    SharedPreferences.setMockInitialValues({});
    const fts = String.fromEnvironment('FTS'), frb = String.fromEnvironment('FRB');
    if (fts.isNotEmpty) Fielding.timeScale = double.parse(fts);
    if (frb.isNotEmpty) Fielding.reachBase = double.parse(frb);
    if (const String.fromEnvironment('ROLES') == '0') FielderAI.useRoles = false;
    final a = AppState(AppDatabase(NativeDatabase.memory()));
    while (!a.loaded) {
      await Future.delayed(const Duration(milliseconds: 10));
    }
    a.myTeamId = a.teams.first.id;
    a.autoMode = true;
    a.onTeamChosen();
    MatchSimulator.debugStats.clear();
    for (var d = 0; d < 60; d++) {
      a.playNextDay();
    }
    final st = MatchSimulator.debugStats;
    // ignore: avoid_print
    print('内野ゴロの処理 ${PlayResolver.stats}');
    // ignore: avoid_print
    print('ゴロの捕球 ${st.entries.where((e) => e.key.startsWith('gbc_')).toList()}');
    // ignore: avoid_print
    print('ライナーの捕球 ${st.entries.where((e) => e.key.startsWith('ldc_')).toList()}');
    for (final c in ['ゴロ', 'ライナー', 'フライ', 'ポップフライ']) {
      final n = st['bip_$c'] ?? 0, h = st['hit_$c'] ?? 0, d2 = st['d2_$c'] ?? 0;
      // ignore: avoid_print
      print('$c 打球$n 安打率${(h / n).toStringAsFixed(3)} 二塁打$d2');
    }
  });
}
