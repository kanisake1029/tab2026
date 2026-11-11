import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/db/app_database.dart';
import 'package:npb_pennant_app/engine/farm_engine.dart';
import 'package:npb_pennant_app/models/team.dart';
import 'package:npb_pennant_app/providers/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AppState> boot(AppDatabase db) async {
  final a = AppState(db);
  while (!a.loaded) { await Future.delayed(const Duration(milliseconds: 10)); }
  a.autoMode = true;
  return a;
}

void main() {
  test('2軍の試合：同じ日程・同じ対戦、成績は2軍に積み上がり、保存・再読み込みできる', () async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase(NativeDatabase.memory());
    final a = await boot(db);
    // 就任は前年10月31日のドラフトの日から
    expect(a.currentDate, DateTime(a.startYear - 1, 10, 31));
    a.myTeamId = a.teams.first.id;
    final my = a.teams.first;

    // 手動オーダー：2軍の野手の打順と位置を指定する
    final farmBat = FarmEngine.farmPlayers(my).where((p) => !p.isPitcher).toList();
    final auto = FarmEngine.autoLineup(my);
    expect(auto.length, 9);
    expect({for (final e in auto) e.position}.length, 9);
    my.farmAuto = false;
    my.farmLineup = auto.reversed.toList();
    final firstId = my.farmLineup.first.playerId;
    expect(FarmEngine.effectiveLineup(my).first.playerId, firstId);

    for (var i = 0; i < 40; i++) { a.playNextDay(); }
    await a.saveData();
    // 雨天中止のオープン戦は2軍だけ試合をする（今日の分は、雨天中止が決まっていても2軍はまだ試合をしていないので数えない）
    final played = a.matches.where((m) => m.homeScore != null || (m.cancelled && m.date.isBefore(a.currentDate))).length;
    expect(played, greaterThan(20));
    expect(a.farmMatches.where((m) => m.homeScore != null).length, played);
    // 同じ日程・同じ対戦チーム
    for (var i = 0; i < a.matches.length; i++) {
      expect(a.farmMatches[i].homeTeamId, a.matches[i].homeTeamId);
      expect(a.farmMatches[i].awayTeamId, a.matches[i].awayTeamId);
      expect(a.farmMatches[i].date, a.matches[i].date);
    }
    // 2軍の試合は実況・1球ごとの記録を残さない
    final fm = a.farmMatches.firstWhere((m) => m.homeScore != null);
    expect(fm.playByPlay, isNull);
    expect(fm.boxScore, isNotNull);
    // 手動で指定した先頭打者が、2軍で出場している
    final lead = my.players.firstWhere((p) => p.id == firstId);
    expect(lead.farmStats.games, greaterThan(0));
    // 1軍の成績に2軍の試合が混ざらない（1軍の出場試合はチームの試合数以内）
    for (final t in a.teams) {
      final games = a.matches.where((m) => m.homeScore != null && (m.homeTeamId == t.id || m.awayTeamId == t.id)).length;
      for (final p in t.players) {
        expect(p.seasonStats.games, lessThanOrEqualTo(games), reason: '${p.registeredName} の1軍出場が試合数を超えている');
      }
    }
    var fAb = 0, fH = 0, fHr = 0;
    for (final t in a.teams) { for (final p in t.players) { fAb += p.farmStats.atBats; fH += p.farmStats.hits; fHr += p.farmStats.homeRuns; } }
    expect(fAb, greaterThan(1000));
    final runs = a.farmMatches.where((m) => m.homeScore != null).fold<int>(0, (s, m) => s + m.homeScore! + m.awayScore!);
    print('2軍 打率=${(fH / fAb).toStringAsFixed(3)} HR/チーム試合=${(fHr / played / 2).toStringAsFixed(2)} 得点/チーム試合=${(runs / played / 2).toStringAsFixed(2)}');

    // 再読み込み
    final b = await boot(db);
    expect(b.farmMatches.length, a.farmMatches.length);
    expect(b.farmMatches.where((m) => m.homeScore != null).length, played);
    final bm = b.teams.first;
    expect(bm.farmAuto, false);
    expect(bm.farmLineup.length, 9);
    expect(jsonEncode(b.teams.map((t) => t.toJson()).toList()), jsonEncode(a.teams.map((t) => t.toJson()).toList()));

    // 書き出し→読み込みでも2軍が残る
    final c = await boot(AppDatabase(NativeDatabase.memory()));
    expect(await c.importSaveJson(a.exportSaveJson()), true);
    expect(c.farmMatches.where((m) => m.homeScore != null).length, played);
    expect(farmBat.isNotEmpty, true);
    expect(Team.farmRotationSize, 8);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
