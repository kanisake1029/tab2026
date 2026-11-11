import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/db/app_database.dart';
import 'package:npb_pennant_app/providers/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('1シーズン通して進められる（雨天中止・振替・ダブルヘッダーを含む）', () async {
    SharedPreferences.setMockInitialValues({});
    final a = AppState(AppDatabase(NativeDatabase.memory()));
    while (!a.loaded) { await Future.delayed(const Duration(milliseconds: 10)); }
    a.myTeamId = a.teams.first.id;
    a.autoMode = true;
    const g = int.fromEnvironment('GAMES', defaultValue: 143);
    if (g != a.seasonGames) a.setSeasonGames(g);
    // 自チームのダブルヘッダーを 1 組作る（同じカードの別の日の試合を、その日の第1試合に移す）
    final mine = a.matches.where((m) => m.matchType == 'LEAGUE' && m.homeTeamId == a.myTeamId).toList()..sort((x, y) => x.date.compareTo(y.date));
    final g2 = mine[10], g1 = mine.lastWhere((m) => m.awayTeamId == g2.awayTeamId);
    g1.date = g2.date;
    g1.dh = 1;
    g2.dh = 2;
    final sw = Stopwatch()..start();
    var days = 0;
    while (a.matches.any((m) => !m.done) && days < 400) { a.playNextDay(); days++; }
    final official = a.matches.where((m) => m.matchType == 'LEAGUE' || m.matchType == 'INTERLEAGUE').toList();
    final moved = official.where((m) => m.note.contains('雨天中止')).length;
    final dh = official.where((m) => m.dh != 0).length ~/ 2;
    final cut = official.where((m) => m.cancelled).length;
    final last = official.map((m) => m.date).reduce((x, y) => x.isAfter(y) ? x : y);
    final perTeam = {for (final t in a.teams) t.id: official.where((m) => m.homeScore != null && (m.homeTeamId == t.id || m.awayTeamId == t.id)).length};
    print('days=$days date=${a.currentDate} games=${a.seasonGames} 雨天中止=${a.rainoutCount} 振替=$moved ダブルヘッダー=$dh 打ち切り=$cut 最終=${last.month}/${last.day} 消化=${perTeam.values.toSet()} ${sw.elapsed}');
    expect(a.matches.where((m) => !m.done && m.matchType != 'ALLSTAR').length, 0);
    expect(g1.homeScore != null && g2.homeScore != null, true);
    expect(perTeam.values.toSet().length, 1);
  }, timeout: const Timeout(Duration(minutes: 10)));
}
