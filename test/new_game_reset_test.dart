import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/db/app_database.dart';
import 'package:npb_pennant_app/providers/app_state.dart';
import 'package:npb_pennant_app/utils/player_generator.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AppState> boot(AppDatabase db) async {
  final a = AppState(db);
  while (!a.loaded) {
    await Future.delayed(const Duration(milliseconds: 10));
  }
  return a;
}

void main() {
  test('はじめから：お知らせ・記録・これまでの試合が残らない', () async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase(NativeDatabase.memory());
    final a = await boot(db);
    a.autoMode = true;
    a.myTeamId = a.teams.first.id;
    for (var i = 0; i < 30; i++) {
      a.playNextDay();
    }
    await a.saveData();
    expect(a.news, isNotEmpty);
    expect(a.matches.any((m) => m.homeScore != null), true);
    // はじめから
    a.resetSeason();
    await a.saveData();
    expect(a.news, isEmpty);
    expect(a.transactions, isEmpty);
    expect(a.matches.any((m) => m.homeScore != null), false);
    final b = await boot(db);
    // ignore: avoid_print
    print('読み込み直し：お知らせ${b.news.length}件 記録${b.transactions.length}件 済んだ試合${b.matches.where((m) => m.homeScore != null).length} 日付${b.currentDate}');
    expect(b.news, isEmpty);
    expect(b.transactions, isEmpty);
    // ignore: avoid_print
    print('newsLog ${b.newsLog}');
    expect(b.newsLog, isEmpty);
    expect(b.matches.any((m) => m.homeScore != null), false);
    expect(await db.select(db.seasonRecords).get(), isEmpty);
    expect(await db.select(db.pitchRows).get(), isEmpty);
    for (final p in b.teams.expand((t) => t.players)) {
      expect(p.openStats.games, 0);
      expect(p.seasonStats.games, 0);
    }
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('はじめから：リーグに入れた新規球団はリーグに残り、ドラフトに参加する', () async {
    SharedPreferences.setMockInitialValues({});
    final a = await boot(AppDatabase(NativeDatabase.memory()));
    final kochi = generateNewTeam(year: 2026);
    kochi.id = 'T_kochi';
    a.teams.add(kochi);
    final out = a.teams.firstWhere((t) => t.league == 'PL');
    kochi.league = 'PL';
    out.league = '';
    a.myTeamId = kochi.id;
    await a.resetToInitialTeams();
    expect(a.teamById('T_kochi')!.league, 'PL');
    expect(a.teamById(out.id)!.league, '');
    final s = a.createDraftSession();
    expect(s.teams.any((t) => t.id == 'T_kochi'), true);
    expect(s.teams.any((t) => t.id == out.id), false);
    expect(a.coaches.any((c) => c.teamId == 'T_kochi' && (c.role ?? '').startsWith('地区スカウト')), true);
  });
}
