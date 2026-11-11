import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/db/app_database.dart';
import 'package:npb_pennant_app/providers/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AppState> boot(AppDatabase db) async {
  final a = AppState(db);
  while (!a.loaded) {
    await Future.delayed(const Duration(milliseconds: 10));
  }
  a.autoMode = true;
  return a;
}

void main() {
  test('保存→再読み込みで、チーム・日程・結果・設定が同じになる', () async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase(NativeDatabase.memory());
    final a = await boot(db);
    expect(a.teams.length, greaterThanOrEqualTo(12));
    a.myTeamId = a.teams.first.id;
    // オフは毎週月曜に止まるので、試合が行われるまで進める
    var guard = 0;
    while (a.matches.where((m) => m.homeScore != null).length < 30 && guard++ < 200) {
      a.playNextDay();
    }
    await a.saveData();
    final played = a.matches.where((m) => m.homeScore != null).length;
    expect(played, greaterThan(0));

    final b = await boot(db);
    expect(b.matches.length, a.matches.length);
    expect(b.matches.where((m) => m.homeScore != null).length, played);
    expect(b.currentDate, a.currentDate);
    expect(b.myTeamId, a.myTeamId);
    expect(jsonEncode(b.teams.map((t) => t.toJson()).toList()), jsonEncode(a.teams.map((t) => t.toJson()).toList()));
    final pm = a.matches.firstWhere((m) => m.homeScore != null);
    final pb = b.matches.firstWhere((m) => m.homeScore != null);
    expect(pb.playByPlay, pm.playByPlay);
    expect(pb.pitchByPitch, pm.pitchByPitch);

    // 続きを進めて保存しても、差分だけが書き込まれて整合する
    b.playNextDay();
    b.playNextDay();
    await b.saveData();
    final c = await boot(db);
    expect(c.matches.where((m) => m.homeScore != null).length, b.matches.where((m) => m.homeScore != null).length);
  }, timeout: const Timeout(Duration(minutes: 3))); // アマチュア球界の作成・保存がある

  test('1球ごとの記録が保存され、2B/3Bなどの成績が付く', () async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase(NativeDatabase.memory());
    final a = await boot(db);
    a.myTeamId = a.teams.first.id;
    // オープン戦の成績は今季成績に入らないので、公式戦が始まるまで進める
    var guard = 0;
    while (!a.matches.any((m) => m.homeScore != null && m.matchType == 'LEAGUE') && guard++ < 200) {
      a.playNextDay();
    }
    await a.saveData();
    // オープン戦の投球は記録しない（ヒートマップ・対戦成績に数えない）ので、公式戦の試合で確かめる
    final idx = a.matches.indexWhere((m) => m.homeScore != null && m.matchType != 'OPEN' && (m.homeTeamId == a.myTeamId || m.awayTeamId == a.myTeamId));
    expect(idx, greaterThanOrEqualTo(0));
    final rows = await db.loadPitches(a.startYear, idx);
    expect(rows.length, greaterThan(100));
    expect(rows.first.seq, 0);
    final other = a.matches.indexWhere((m) => m.homeScore != null && m.matchType != 'OPEN' && m.homeTeamId != a.myTeamId && m.awayTeamId != a.myTeamId);
    final open = a.matches.indexWhere((m) => m.homeScore != null && m.matchType == 'OPEN' && (m.homeTeamId == a.myTeamId || m.awayTeamId == a.myTeamId));
    expect(await db.loadPitches(a.startYear, open), isEmpty);
    expect(await db.loadPitches(a.startYear, other), isEmpty);
    var d = 0, t = 0, h = 0, ha = 0;
    for (final tm in a.teams) {
      for (final p in tm.players) {
        d += p.seasonStats.doubles; t += p.seasonStats.triples; h += p.seasonStats.hits; ha += p.seasonStats.hitsAllowed;
      }
    }
    expect(d, greaterThan(0));
    expect(h, ha);
    expect(h, greaterThan(d + t));
  });

  test('書き出し→読み込みで復元できる／壊れたファイルは拒否', () async {
    SharedPreferences.setMockInitialValues({});
    final a = await boot(AppDatabase(NativeDatabase.memory()));
    a.playNextDay();
    final text = a.exportSaveJson();
    final b = await boot(AppDatabase(NativeDatabase.memory()));
    expect(await b.importSaveJson('これはセーブではない'), false);
    expect(await b.importSaveJson(text), true);
    expect(b.currentDate, a.currentDate);
    expect(b.matches.where((m) => m.homeScore != null).length, a.matches.where((m) => m.homeScore != null).length);
  });

  test('旧方式（SharedPreferences）のセーブをDBへ移す', () async {
    final seed = await boot(AppDatabase(NativeDatabase.memory()));
    seed.myTeamId = seed.teams.first.id;
    seed.playNextDay();
    SharedPreferences.setMockInitialValues({
      'teamsData': jsonEncode(seed.teams.map((t) => t.toJson()).toList()),
      'matchesData': jsonEncode(seed.matches.map((m) => m.toJson()).toList()),
      'currentDate': seed.currentDate.toIso8601String(),
      'myTeamId': seed.myTeamId,
      'gameMode': 'manage',
    });
    final db = AppDatabase(NativeDatabase.memory());
    final a = await boot(db);
    expect(a.gameMode, 'manage');
    expect(a.myTeamId, seed.myTeamId);
    final b = await boot(db);
    expect(b.matches.where((m) => m.homeScore != null).length, seed.matches.where((m) => m.homeScore != null).length);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('teamsData'), isNull);
  });
}
