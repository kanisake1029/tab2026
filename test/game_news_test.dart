import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/db/app_database.dart';
import 'package:npb_pennant_app/engine/game_news.dart';
import 'package:npb_pennant_app/providers/app_state.dart';
import 'package:npb_pennant_app/widgets/game_news_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 公式戦の記事：チーム状況（開幕戦・順位・連勝連敗）とコーチ名のコメントが入り、試合の中身と食い違わない
void main() {
  test('記事とコメント', () async {
    SharedPreferences.setMockInitialValues({});
    final a = AppState(AppDatabase(NativeDatabase.memory()));
    while (!a.loaded) {
      await Future.delayed(const Duration(milliseconds: 20));
    }
    a.myTeamId = a.teams.first.id;
    a.autoMode = true;
    var d = 0;
    while (a.matches.where((m) => m.isPlayed && m.matchType == 'LEAGUE').length < 60 && d < 300) {
      a.playNextDay();
      d++;
    }
    final official = a.matches.where((m) => m.isPlayed && (m.matchType == 'LEAGUE' || m.matchType == 'INTERLEAGUE')).toList();
    var situational = 0, coach = 0;
    for (final m in official.take(60)) {
      final home = a.teamById(m.homeTeamId)!, away = a.teamById(m.awayTeamId)!;
      final ctx = newsContext(a, m);
      final n = GameNews.of(m, home, away, myTeamId: a.myTeamId, ctx: ctx);
      final all = [...n.homeFans, ...n.awayFans].map((c) => c.text).toList();
      if (n.lead.contains('首位') || n.lead.contains('開幕戦') || n.lead.contains('連') || n.lead.contains('最下位')) situational++;
      if (all.any((t) => t.contains('監督') || t.contains('コーチ'))) coach++;
      // 中継ぎが点を取られていないのに「中継ぎがヒヤヒヤ」は出さない
      for (final homeSide in [true, false]) {
        final rows = ((m.boxScore![homeSide ? 'homePitcher' : 'awayPitcher'] as Map).values.toList()).skip(1);
        final rr = rows.fold<int>(0, (s, v) => s + ((v as Map)['er'] ?? 0) as int);
        final fans = homeSide ? n.homeFans : n.awayFans;
        if (rr < 2) expect(fans.any((c) => c.text.contains('中継ぎがヒヤヒヤ')), false);
      }
    }
    final m = official.first;
    final n = GameNews.of(m, a.teamById(m.homeTeamId)!, a.teamById(m.awayTeamId)!, ctx: newsContext(a, m));
    // ignore: avoid_print
    print('${n.headline}\n${n.lead}\n${n.body.join('\n')}\n${[...n.homeFans, ...n.awayFans].map((c) => c.text).join(' / ')}\nチーム状況あり $situational/60　コーチ名あり $coach/60');
    expect(situational, greaterThan(5));
    expect(coach, greaterThan(5));
  }, timeout: const Timeout(Duration(minutes: 10)));
}
