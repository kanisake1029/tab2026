import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/db/app_database.dart';
import 'package:npb_pennant_app/providers/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AppState> boot(AppDatabase db) async {
  final a = AppState(db);
  while (!a.loaded) { await Future.delayed(const Duration(milliseconds: 10)); }
  a.autoMode = true;
  return a;
}

void main() {
  test('オールスター・CS・日本シリーズ・表彰まで1年が回る', () async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase(NativeDatabase.memory());
    final a = await boot(db);
    a.myTeamId = a.teams.first.id;
    var guard = 0;
    while (!a.regularDone && guard++ < 400) { a.playNextDay(); }
    expect(a.regularDone, true);
    // オールスター2試合が実際の選手で行われ、今季成績には入らない
    final asg = a.matches.where((m) => m.matchType == 'ALLSTAR').toList();
    expect(asg.length, 2);
    expect(asg.every((m) => m.homeScore != null), true);
    for (final t in a.teams) {
      final games = a.matches.where((m) => m.homeScore != null && !AppState.isSpecialType(m.matchType) && (m.homeTeamId == t.id || m.awayTeamId == t.id)).length;
      for (final p in t.players) {
        expect(p.seasonStats.games, lessThanOrEqualTo(games));
      }
    }
    final before = {for (final t in a.teams) for (final p in t.players) p.id: p.seasonStats.atBats};

    guard = 0;
    while (!a.seasonOver && guard++ < 60) { a.playNextDay(); }
    expect(a.seasonOver, true, reason: a.postseason.map((s) => '${s.id} ${s.high}-${s.low} w=${s.winner}').join(' / '));
    expect(a.champion, isNotNull);
    for (final s in a.postseason) {
      print('${s.label}: ${a.teamById(s.high)!.name} vs ${a.teamById(s.low)!.name} → ${a.teamById(s.winner)!.name}  MVP ${s.mvp}  試合数${s.matchIdx.length}');
      expect(s.winner.isNotEmpty, true);
      for (final i in s.matchIdx) {
        expect(a.matches[i].matchType, s.stage == 'JS' ? 'JS' : 'CS');
        expect(a.matches[i].date.month, 10);
      }
    }
    // ポストシーズンの成績は今季成績に入らない
    for (final t in a.teams) {
      for (final p in t.players) {
        expect(p.seasonStats.atBats, before[p.id]);
      }
    }
    expect(a.farmMatches.length, a.matches.length);

    final champ = a.champion!.id; // 年度を切り替えるとポストシーズンは消えるので、先に控える
    final r = await a.finishSeason();
    expect(r, isNotNull);
    final aw = r!.awards;
    expect(aw['champion'], champ);
    // 全日程の終了で年度が切り替わる
    expect(a.seasonFinished, false);
    expect(a.offAfterSeason, true);
    for (final lg in ['CL', 'PL']) {
      final L = aw['leagues'][lg] as Map<String, dynamic>;
      expect((L['titles'] as List).length, 12);
      for (final t in L['titles'] as List) {
        final ws = (t['winners'] as List).map((w) => '${w['name']}(${w['teamName']})').join('・');
        print('$lg ${t['title']}: $ws ${t['value']}');
      }
      final b9 = L['b9'] as List;
      expect(b9.length, 8);
      for (final b in b9) {
        final ws = (b['winners'] as List);
        expect(ws.isNotEmpty, true, reason: 'B9 ${b['pos']}');
        print('$lg B9 ${b['pos']}: ${ws.map((w) => '${w['name']}(${w['votes']}票)').join('・')}');
      }
      final gg = L['gg'] as List;
      expect(gg.length, 7);
      print('$lg GG: ${gg.map((g) => '${g['pos']} ${(g['winners'] as List).map((w) => w['name']).join('・')}').join(' / ')}');
      final mvp = (L['mvp']['winners'] as List);
      expect(mvp.length, 1);
      print('$lg MVP: ${mvp.first['name']} ${mvp.first['votes']}票  新人王: ${(L['rookie']['winners'] as List).map((w) => w['name']).join() }');
    }
    print('沢村賞: ${aw['sawamura']}  カムバック賞: ${aw['comeback']}');
    print('球宴MVP: ${aw['allStarMvp']}');
    expect((aw['allStarMvp'] as List).length, 2);

    // 保存して読み直せる
    expect(await a.loadAwards(r.year), isNotNull);
    final b = await boot(db);
    expect(b.postseason.length, a.postseason.length);
    expect(b.startYear, a.startYear);
    expect(b.offAfterSeason, true); // 年度を切り替えたオフのまま読み直せる
    expect(await b.loadAwards(r.year), isNotNull);
  }, timeout: const Timeout(Duration(minutes: 10)));
}
