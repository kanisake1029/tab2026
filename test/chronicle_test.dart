import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/db/app_database.dart';
import 'package:npb_pennant_app/providers/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('出来事の記録：ドラフトの入団、プロ初出場・初安打・初N番起用、年表', () async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase(NativeDatabase.memory());
    final a = AppState(db);
    while (!a.loaded) { await Future.delayed(const Duration(milliseconds: 10)); }
    a.autoMode = true;
    a.myTeamId = a.teams.first.id;
    while (a.matches.where((m) => m.homeScore != null && m.matchType == 'LEAGUE').length < 120) { a.playNextDay(); }
    await a.saveData();
    final ev = a.chron;
    final kinds = <String, int>{};
    for (final e in ev) { kinds[e['k'] as String] = (kinds[e['k'] as String] ?? 0) + 1; }
    // ignore: avoid_print
    print('出来事 ${ev.length}件 $kinds');
    final my = a.teams.first;
    for (final e in ev.where((e) => e['team'] == my.id).take(25)) {
      // ignore: avoid_print
      print('  ${e['d']} ${e['t']}');
    }
    expect(kinds['join'] ?? 0, greaterThan(20));
    expect(kinds['first'] ?? 0, greaterThan(0));
    final rookie = my.players.where((p) => p.draftYear == a.startYear - 1 && p.firsts.isNotEmpty).firstOrNull;
    if (rookie != null) {
      final tl = await a.playerTimeline(rookie);
      // ignore: avoid_print
      print('年表 ${rookie.registeredName}：');
      for (final x in tl) {
        // ignore: avoid_print
        print('  ${x.$1.year % 100}/${x.$1.month}/${x.$1.day} ${x.$2}');
      }
    }
    // 保存して読み直しても出来事が残る
    final b = AppState(db);
    while (!b.loaded) { await Future.delayed(const Duration(milliseconds: 10)); }
    expect(b.chron.length, ev.length);
  }, timeout: const Timeout(Duration(minutes: 10)));
}
