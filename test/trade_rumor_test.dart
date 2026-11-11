import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/db/app_database.dart';
import 'package:npb_pennant_app/engine/game_news.dart';
import 'package:npb_pennant_app/engine/trade_rumor.dart';
import 'package:npb_pennant_app/providers/app_state.dart';
import 'package:npb_pennant_app/widgets/game_news_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// トレード予想の記事と、MVP の名前を使った試合の見出し
void main() {
  test('トレード予想と見出し', () async {
    SharedPreferences.setMockInitialValues({});
    final a = AppState(AppDatabase(NativeDatabase.memory()));
    while (!a.loaded) {
      await Future.delayed(const Duration(milliseconds: 20));
    }
    a.myTeamId = a.teams.first.id;
    a.autoMode = true;
    var d = 0;
    while (a.matches.where((m) => m.isPlayed && m.matchType == 'LEAGUE').length < 80 && d < 300) {
      a.playNextDay();
      d++;
    }
    final rs = TradeRumor.recent(a.teams, a.currentDate, myTeamId: a.myTeamId);
    for (final r in rs.take(2)) {
      // ignore: avoid_print
      print('${r.date} ${r.headline}\n${r.body.join('\n')}\n${r.teamFans.map((c) => c.text).join(' / ')}\n');
    }
    expect(rs, isNotEmpty);
    final heads = <String>[];
    for (final m in a.matches.where((m) => m.isPlayed && m.matchType == 'LEAGUE').take(40)) {
      heads.add(GameNews.of(m, a.teamById(m.homeTeamId)!, a.teamById(m.awayTeamId)!, ctx: newsContext(a, m)).headline);
    }
    // ignore: avoid_print
    print(heads.take(15).join('\n'));
    expect(heads.where((h) => h.contains('が') && h.contains('で')).length, greaterThan(5));
  }, timeout: const Timeout(Duration(minutes: 10)));
}
