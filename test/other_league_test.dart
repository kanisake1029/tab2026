import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/engine/other_league_engine.dart';
import 'package:npb_pennant_app/models/other_league.dart';

/// 他リーグ：生成・1年分の毎日の試合・シーズンの区切り・年明け
void main() {
  test('他リーグを作って1年回す', () {
    final sw = Stopwatch()..start();
    final w = OtherLeagueEngine.generate(DateTime(2026, 1, 1), 2026);
    final gen = sw.elapsedMilliseconds;
    expect(w.teams.length, 30 * 4 + 10 + 6 + 20 + 4 + 4 + (10 + 12 + 18 + 12 + 4 + 16) + (4 + 9 + 5 + 6 + 4 + 3));
    expect(w.teams.every((t) => t.players.length == 26), true);
    sw.reset();
    var d = DateTime(2026, 1, 1);
    final ended = <String>{};
    while (d.year == 2026) {
      OtherLeagueEngine.playDay(w, d);
      final next = d.add(const Duration(days: 1));
      for (final lg in OtherLeagueEngine.leagues.values) {
        if (!lg.winter && lg.inSeason(d) && !lg.inSeason(next) && ended.add(lg.id)) {
          // 締める前に、成績の水準を見る
          final ps = w.teamsOf(lg.id).expand((t) => t.players).toList();
          final ab = ps.fold<int>(0, (a, p) => a + p.seasonStats.atBats), h = ps.fold<int>(0, (a, p) => a + p.seasonStats.hits);
          final hr = ps.fold<int>(0, (a, p) => a + p.seasonStats.homeRuns), er = ps.fold<int>(0, (a, p) => a + p.seasonStats.earnedRuns), ip = ps.fold<int>(0, (a, p) => a + p.seasonStats.inningsPitched);
          final g = w.teamsOf(lg.id).fold<int>(0, (a, t) => a + t.w + t.l + t.d) / w.teamsOf(lg.id).length;
          final topHr = ps.map((p) => p.seasonStats.homeRuns).reduce(max);
          print('${lg.name.padRight(10)} 試合${g.toStringAsFixed(0)} 打率${(h / ab).toStringAsFixed(3)} 防御率${(er * 27 / ip).toStringAsFixed(2)} 本塁打/試合${(hr / g / w.teamsOf(lg.id).length).toStringAsFixed(2)} 本塁打王${topHr}');
          expect(g, closeTo(lg.games, lg.games * 0.2));
          OtherLeagueEngine.closeSeason(w, lg, 2026);
        }
      }
      d = next;
    }
    final sim = sw.elapsedMilliseconds;
    // 年ごとの記録：順位表とタイトルが残る
    final mlb = w.seasons['MLB']!.first;
    expect(mlb['y'], 2026);
    expect((mlb['st'] as List).length, greaterThan(30));
    expect((mlb['ld'] as List).length, 8);
    print((mlb['ld'] as List).take(3).join(' / '));
    final notes = OtherLeagueEngine.newYear(w, 2027, Random(3));
    expect(w.teams.every((t) => t.players.length == 26), true);
    final s = jsonEncode(w.toJson());
    final gz = gzip.encode(utf8.encode(s));
    print('生成${gen}ms 1年${sim}ms 選手${w.allPlayers.length}人 保存${s.length ~/ 1000000}MB（gzip ${gz.length ~/ 1000}KB） 引退メモ${notes.length}');
    final back = OtherWorld.fromJson(jsonDecode(s));
    expect(back.teams.length, w.teams.length);
    expect(w.allPlayers.first.abroad, isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
