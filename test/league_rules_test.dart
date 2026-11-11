import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/db/app_database.dart';
import 'package:npb_pennant_app/engine/match_simulator.dart';
import 'package:npb_pennant_app/models/league_rules.dart';
import 'package:npb_pennant_app/providers/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('リーグ規定：DH の有無（ホームのリーグ）と外国人枠が効く', () async {
    SharedPreferences.setMockInitialValues({});
    final a = AppState(AppDatabase(NativeDatabase.memory()));
    while (!a.loaded) {
      await Future.delayed(const Duration(milliseconds: 10));
    }
    a.myTeamId = a.teams.first.id;
    a.autoMode = true;
    expect(a.rulesEditable, true);
    expect(a.setLeagueRules(dhCL: false, dhPL: true, foreign1G: 3, foreignBench: 2), isNull);
    for (final t in a.teams) {
      final pm = {for (final p in t.players) p.id: p};
      expect(t.roster1G.where((id) => pm[id]!.foreignSlot).length <= 3, true, reason: '${t.name} 1軍の外国人');
      expect(t.active26.where((id) => pm[id]!.foreignSlot).length <= 2, true, reason: '${t.name} ベンチの外国人');
    }
    final sim = MatchSimulator();
    final cl = a.matches.firstWhere((m) => m.matchType == 'INTERLEAGUE' && a.teamById(m.homeTeamId)!.league == 'CL');
    final pl = a.matches.firstWhere((m) => m.matchType == 'INTERLEAGUE' && a.teamById(m.homeTeamId)!.league == 'PL');
    for (final (m, dh) in [(cl, false), (pl, true)]) {
      final s = sim.startGame(m, a.teamById(m.homeTeamId)!, a.teamById(m.awayTeamId)!);
      for (final lu in [s.homeLineup, s.awayLineup]) {
        expect(lu.length, 9);
        expect(lu.any((e) => e.position == 'DH'), dh);
        expect(lu.any((e) => e.position == '投'), !dh);
      }
      expect(s.homeOrder.contains(s.homePitcher), !dh, reason: 'DH なしは先発投手が打つ');
    }
    // 規定は保存され、読み直しても同じ
    await a.saveData();
    LeagueRules.load(null);
    expect(LeagueRules.dhCL, true);
    final b = AppState(a.db);
    while (!b.loaded) {
      await Future.delayed(const Duration(milliseconds: 10));
    }
    expect(LeagueRules.dhCL, false);
    expect(LeagueRules.foreign1G, 3);
    expect(LeagueRules.foreignBench, 2);
    // 何日か進めても試合が回る
    for (var i = 0; i < 60; i++) {
      a.playNextDay();
    }
    expect(a.matches.where((m) => m.matchType == 'INTERLEAGUE' || m.matchType == 'LEAGUE').any((m) => m.homeScore != null), true);
    expect(a.rulesEditable, false);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
