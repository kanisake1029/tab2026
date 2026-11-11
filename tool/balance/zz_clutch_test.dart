// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/db/app_database.dart';
import 'package:npb_pennant_app/engine/match_simulator.dart';
import 'package:npb_pennant_app/models/player.dart';
import 'package:npb_pennant_app/models/team.dart';
import 'package:npb_pennant_app/providers/app_state.dart';
import 'package:npb_pennant_app/utils/schedule_generator.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 打線全員のチャンスを 90 / 60 / 30 にして、得点圏打率と それ以外の打率を比べる
void main() {
  test('clutch', () async {
    SharedPreferences.setMockInitialValues({});
    final tmp = File('${Directory.systemTemp.path}/s25_cl.sqlite');
    await File('backup/s25_20261109.sqlite').copy(tmp.path);
    final a = AppState(AppDatabase(NativeDatabase(tmp)));
    while (!a.loaded) { await Future.delayed(const Duration(milliseconds: 20)); }
    final env = Platform.environment;
    if (env['CK'] != null) MatchSimulator.clutchBatK = double.parse(env['CK']!);
    if (env['PK'] != null) MatchSimulator.clutchPitK = double.parse(env['PK']!);
    final pinch = env['MODE'] == 'pinch';
    final npb = a.teams.where((t) => t.league == 'CL' || t.league == 'PL').toList();
    Team copy(Team t) => Team.fromJson(jsonDecode(jsonEncode(t.toJson())) as Map<String, dynamic>, Player.fromJson);
    final n = int.parse(env['N'] ?? '300');
    for (final c in [90, 60, 30]) {
      final sim = MatchSimulator();
      var ab = 0, h = 0, rab = 0, rh = 0;
      for (var g = 0; g < n; g++) {
        final bat = copy(npb[g % npb.length]);
        final fld = copy(npb[(g + 5) % npb.length]);
        for (final p in bat.players) { p.seasonStats = PlayerStats(); p.clutch = pinch ? 60 : c; }
        for (final p in fld.players) { p.clutchPitching = pinch ? c : 60; }
        final s = sim.startGame(Match(homeTeamId: fld.id, awayTeamId: bat.id, date: DateTime(2026, 6, 1 + g % 28), matchType: 'オープン戦'), fld, bat);
        int tot(bool hits) => bat.players.fold<int>(0, (x, p) => x + (hits ? p.seasonStats.hits : p.seasonStats.atBats));
        while (!sim.isFinished(s)) {
          sim.autoManage(s);
          final risp = s.state.isTop && (s.state.runner2B != null || s.state.runner3B != null);
          final a0 = tot(false), h0 = tot(true);
          sim.stepPlateAppearance(s);
          if (risp) { rab += tot(false) - a0; rh += tot(true) - h0; }
        }
        sim.finishGame(s);
        for (final p in bat.players) { final st = p.seasonStats; ab += st.atBats; h += st.hits; }
      }
      print('${pinch ? 'ピンチ' : 'チャンス'}$c 得点圏 ${(rh / rab).toStringAsFixed(3)}（$rab打数） それ以外 ${((h - rh) / (ab - rab)).toStringAsFixed(3)}  差 ${((rh / rab) - (h - rh) / (ab - rab)).toStringAsFixed(3)}');
    }
  }, timeout: const Timeout(Duration(minutes: 40)));
}
