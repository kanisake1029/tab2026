import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/db/app_database.dart';
import 'package:npb_pennant_app/models/player.dart';
import 'package:npb_pennant_app/providers/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('オープン戦の成績は別に残り、今季成績・通算には入らない。開幕前はオープン戦の成績を表示', () async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase(NativeDatabase.memory());
    final a = AppState(db);
    while (!a.loaded) {
      await Future.delayed(const Duration(milliseconds: 10));
    }
    a.autoMode = true;
    a.myTeamId = a.teams.first.id;
    final careerBefore = {for (final p in a.teams.expand((t) => t.players)) p.id: p.career.atBats};
    var guard = 0;
    while (a.matches.where((m) => m.matchType == 'OPEN' && m.homeScore != null).length < 40 && guard++ < 200) {
      a.playNextDay();
    }
    final all = a.teams.expand((t) => t.players).toList();
    final openAb = all.fold<int>(0, (s, p) => s + p.openStats.atBats);
    final seasonAb = all.fold<int>(0, (s, p) => s + p.seasonStats.atBats);
    // ignore: avoid_print
    print('オープン戦 打数計 $openAb　今季 $seasonAb　表示はオープン戦=${Player.showOpen}');
    expect(openAb, greaterThan(500));
    expect(seasonAb, 0);
    expect(Player.showOpen, true);
    for (final p in all) {
      expect(p.career.atBats, careerBefore[p.id] ?? 0);
    }
    // 開幕したら、表示は今季成績に戻る
    guard = 0;
    while (!a.matches.any((m) => m.matchType == 'LEAGUE' && m.homeScore != null) && guard++ < 200) {
      a.playNextDay();
    }
    expect(Player.showOpen, false);
    expect(all.fold<int>(0, (s, p) => s + p.openStats.atBats), greaterThanOrEqualTo(openAb)); // オープン戦の記録は残る
  }, timeout: const Timeout(Duration(minutes: 8)));
}
