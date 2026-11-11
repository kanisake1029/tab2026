// ignore_for_file: avoid_print
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/db/app_database.dart';
import 'package:npb_pennant_app/engine/match_simulator.dart';
import 'package:npb_pennant_app/models/player.dart';
import 'package:npb_pennant_app/providers/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('live hr', () async {
    SharedPreferences.setMockInitialValues({});
    final tmp = File('${Directory.systemTemp.path}/s25_lhr.sqlite');
    await File('backup/s25_20261109.sqlite').copy(tmp.path);
    final a = AppState(AppDatabase(NativeDatabase(tmp)));
    while (!a.loaded) { await Future.delayed(const Duration(milliseconds: 20)); }
    final my = a.myTeam!;
    final ms = a.matches.where((m) => m.homeScore == null && m.matchType != 'OPEN' && (m.homeTeamId == my.id || m.awayTeamId == my.id)).take(40).toList();
    for (final live in [true, false]) {
      for (final t in a.teams) { for (final q in t.players) { q.seasonStats = PlayerStats(); } }
      MatchSimulator.debugStats.clear();
      for (final m in ms) {
        final h = a.teams.firstWhere((t) => t.id == m.homeTeamId), w = a.teams.firstWhere((t) => t.id == m.awayTeamId);
        final sim = MatchSimulator();
        final s = sim.startGame(m, h, w);
        if (live) s.userTeamId = my.id;
        while (!sim.isFinished(s)) {
          if (live) { while (sim.stepPitch(s, plan: const AtBatPlan()) != null) {} } else { sim.stepPlateAppearance(s); }
        }
        sim.finishGame(s);
      }
      final l = my.players.where((p) => !p.isPitcher && p.seasonStats.atBats > 40).toList()..sort((x, y) => y.power.compareTo(x.power));
      print(live ? '■ ライブ（采配・指示なし）' : '■ CPU任せ');
      for (final p in l) { final s = p.seasonStats; print('  ${p.registeredName.padRight(9)} パ${p.power} 打数${s.atBats} 安${s.hits} 本${s.homeRuns}'); }
      final opp = [for (final t in a.teams) if (t.id != my.id) for (final p in t.players) p.seasonStats.homeRuns].fold<int>(0, (x, y) => x + y);
      print('  自球団 本${my.players.fold<int>(0, (x, p) => x + p.seasonStats.homeRuns)} 相手 本$opp');
    }
  });
}
