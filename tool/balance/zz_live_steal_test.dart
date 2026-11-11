// ignore_for_file: avoid_print
// ライブ試合（自分が采配・走塁の指示なし）で、自球団の走者が自分の判断で走るか
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/db/app_database.dart';
import 'package:npb_pennant_app/engine/match_simulator.dart';
import 'package:npb_pennant_app/providers/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('live steal', () async {
    SharedPreferences.setMockInitialValues({});
    final tmp = File('${Directory.systemTemp.path}/s25_lsteal.sqlite');
    await File('backup/s25_20261108.sqlite').copy(tmp.path);
    final a = AppState(AppDatabase(NativeDatabase(tmp)));
    while (!a.loaded) { await Future.delayed(const Duration(milliseconds: 20)); }
    final my = a.myTeam!;
    final ms = a.matches.where((m) => m.homeScore == null && (m.homeTeamId == my.id || m.awayTeamId == my.id)).take(40).toList();
    var mySB = 0, myCS = 0, opSB = 0;
    for (final m in ms) {
      final h = a.teams.firstWhere((t) => t.id == m.homeTeamId), w = a.teams.firstWhere((t) => t.id == m.awayTeamId);
      final sim = MatchSimulator();
      final s = sim.startGame(m, h, w)..userTeamId = my.id;
      while (!sim.isFinished(s)) {
        while (sim.stepPitch(s, plan: const AtBatPlan()) != null) {}
      }
      final myHome = h.id == my.id;
      mySB += myHome ? s.homeSB : s.awaySB;
      opSB += myHome ? s.awaySB : s.homeSB;
      myCS += s.playByPlay.where((l) => l.contains('盗塁死') && (myHome ? true : true)).length;
    }
    print('${ms.length}試合 自球団 盗塁$mySB  相手 盗塁$opSB  （盗塁死 両軍 $myCS）');
  });
}
