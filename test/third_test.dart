import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/db/app_database.dart';
import 'package:npb_pennant_app/providers/app_state.dart';
import 'package:npb_pennant_app/utils/standings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('3軍戦：日程が組まれ、簡易計算で結果・成績が残り、保存・再読み込みできる', () async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase(NativeDatabase.memory());
    final a = AppState(db);
    while (!a.loaded) { await Future.delayed(const Duration(milliseconds: 10)); }
    a.autoMode = true;
    a.myTeamId = a.teams.first.id;
    expect(a.thirdMatches, isNotEmpty);
    while (a.matches.where((m) => m.homeScore != null && m.matchType == 'LEAGUE').length < 300) { a.playNextDay(); }
    final played = a.thirdMatches.where((m) => m.homeScore != null).toList();
    expect(played, isNotEmpty);
    var runs = 0, hits = 0, games = 0, draws = 0;
    for (final m in played) {
      runs += m.homeScore! + m.awayScore!;
      hits += m.homeHits! + m.awayHits!;
      games++;
      if (m.homeScore == m.awayScore) draws++;
    }
    // ignore: avoid_print
    print('3軍 ${games}試合 1チーム平均 得点${(runs / games / 2).toStringAsFixed(2)} 安打${(hits / games / 2).toStringAsFixed(2)} 引分$draws');
    final recs = computeStandings(a.teams, a.thirdMatches, allLeagues, StandingsKind.official);
    final ts = computeTeamStats(a.teams, a.thirdMatches, StandingsKind.official);
    for (final r in recs) {
      // ignore: avoid_print
      print('${r.team.shortName} ${r.w}-${r.l}-${r.d} 防${ts[r.team.id]!.era} 率${ts[r.team.id]!.avg} 本${ts[r.team.id]!.hr} 盗${ts[r.team.id]!.sb} 失${ts[r.team.id]!.e}');
    }
    final ps = a.teams.expand((t) => t.players).where((p) => p.thirdStats.atBats > 0).toList();
    expect(ps, isNotEmpty);
    await a.saveData();
    final b = AppState(db);
    while (!b.loaded) { await Future.delayed(const Duration(milliseconds: 10)); }
    expect(b.thirdMatches.where((m) => m.homeScore != null).length, played.length);
    final p0 = ps.first;
    expect(b.teams.expand((t) => t.players).firstWhere((p) => p.id == p0.id).thirdStats.atBats, p0.thirdStats.atBats);
  }, timeout: const Timeout(Duration(minutes: 10)));
}
