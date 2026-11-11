import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/db/app_database.dart';
import 'package:npb_pennant_app/engine/item_news.dart';
import 'package:npb_pennant_app/engine/offseason_news.dart';
import 'package:npb_pennant_app/engine/trade_rumor.dart';
import 'package:npb_pennant_app/providers/app_state.dart';
import 'package:npb_pennant_app/widgets/item_news_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// トレード成立の記事（全員）・トレード予想（複数対複数）・FA の見出し・見出しの分け方
void main() {
  test('記事の中身', () async {
    SharedPreferences.setMockInitialValues({});
    final a = AppState(AppDatabase(NativeDatabase.memory()));
    while (!a.loaded) {
      await Future.delayed(const Duration(milliseconds: 20));
    }
    a.myTeamId = a.teams.first.id;
    a.autoMode = true;
    var d = 0;
    while (!(a.currentDate.month == 12 && a.currentDate.day >= 10) && d < 120) {
      a.playNextDay();
      d++;
    }
    final t1 = a.teams[0], t2 = a.teams[1];
    final give = t1.players.where((p) => !p.isPitcher).take(2).toList(), get = t2.players.where((p) => p.isPitcher).take(3).toList();
    final text = 'トレード成立：${t1.shortName}の${give.map((p) => p.registeredName).join('・')}と${t2.shortName}の${get.map((p) => p.registeredName).join('・')}';
    // トレードのあと：give は t2、get は t1
    final n = ItemNews.of('12/1', text, NewsTopic.transfer, player: give.first, team: t2, myTeamId: a.myTeamId, involved: [for (final p in give) (p, t2), for (final p in get) (p, t1)]);
    // ignore: avoid_print
    print('${n.headline}\n${n.body.join('\n')}\n自: ${n.teamFans.map((c) => c.text).join(' / ')}\n他: ${n.otherFans.map((c) => c.text).join(' / ')}\n');
    expect(n.body.where((b) => give.any((p) => b.contains(p.registeredName))).length, greaterThanOrEqualTo(2));
    final rs = TradeRumor.recent(a.teams, a.currentDate, myTeamId: a.myTeamId, count: 6);
    for (final r in rs.take(3)) {
      // ignore: avoid_print
      print('${r.headline}\n${r.body.join('\n')}\n${r.teamFans.map((c) => c.text).join(' / ')}\n');
    }
    final everyone = [for (final t in a.teams) ...t.players, ...a.freeAgents.map((f) => f.player)];
    final preds = OffseasonNews.predictions(teams: a.teams, faCases: a.faCases, freeAgents: a.freeAgents, foreignPool: a.foreignPool, today: a.currentDate, playerById: (id) => everyone.where((p) => p.id == id).firstOrNull, myTeamId: a.myTeamId);
    for (final (_, p) in preds) {
      // ignore: avoid_print
      print('${p.headline} → ${splitHeadline(p.headline)}');
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}
