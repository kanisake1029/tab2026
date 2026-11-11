import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/db/app_database.dart';
import 'package:npb_pennant_app/providers/app_state.dart';
import 'package:npb_pennant_app/utils/schedule_generator.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('試合数（120・143・156）どおりの日程になる', () async {
    SharedPreferences.setMockInitialValues({});
    final a = AppState(AppDatabase(NativeDatabase.memory()));
    while (!a.loaded) {
      await Future.delayed(const Duration(milliseconds: 10));
    }
    for (final g in ScheduleGenerator.seasonLengths) {
      final ms = ScheduleGenerator.generateSeasonSchedule(2026, a.teams, games: g);
      final off = ms.where((m) => m.matchType == 'LEAGUE' || m.matchType == 'INTERLEAGUE').toList();
      final last = off.map((m) => m.date).reduce((x, y) => x.isAfter(y) ? x : y);
      final first = off.map((m) => m.date).reduce((x, y) => x.isBefore(y) ? x : y);
      final inter = off.where((m) => m.matchType == 'INTERLEAGUE').map((m) => m.date).toList()..sort();
      final star = ms.where((m) => m.matchType == 'ALLSTAR').map((m) => m.date).toList();
      final homes = <int>[];
      for (final t in a.teams) {
        final mine = off.where((m) => m.homeTeamId == t.id || m.awayTeamId == t.id).toList();
        expect(mine.length, g, reason: '${t.id} $g');
        homes.add(mine.where((m) => m.homeTeamId == t.id).length);
        // 同じ日に 2 試合ない
        final days = mine.map((m) => '${m.date.month}/${m.date.day}').toSet();
        expect(days.length, mine.length);
      }
      // ignore: avoid_print
      print('$g試合: 開幕 ${first.month}/${first.day} 最終 ${last.month}/${last.day} 交流戦 ${inter.first.month}/${inter.first.day}〜${inter.last.month}/${inter.last.day} 球宴 ${star.map((d) => '${d.month}/${d.day}').join(',')} ホーム ${homes.reduce((x, y) => x < y ? x : y)}〜${homes.reduce((x, y) => x > y ? x : y)}');
      expect(last.isBefore(DateTime(2026, 10, 3)), true);
    }
  });
}
