import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/db/app_database.dart';
import 'package:npb_pennant_app/engine/item_news.dart';
import 'package:npb_pennant_app/engine/offseason_news.dart';
import 'package:npb_pennant_app/providers/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// オフシーズンの去就予想と、新外国人の入団記事のコメント
void main() {
  test('去就予想と新外国人', () async {
    SharedPreferences.setMockInitialValues({});
    final a = AppState(AppDatabase(NativeDatabase.memory()));
    while (!a.loaded) {
      await Future.delayed(const Duration(milliseconds: 20));
    }
    a.myTeamId = a.teams.first.id;
    a.autoMode = true;
    var d = 0;
    while (!(a.currentDate.month == 12 && a.currentDate.day >= 20) && d < 120) {
      a.playNextDay();
      d++;
    }
    final everyone = [for (final t in a.teams) ...t.players, ...a.freeAgents.map((f) => f.player)];
    final preds = OffseasonNews.predictions(teams: a.teams, faCases: a.faCases, freeAgents: a.freeAgents, foreignPool: a.foreignPool, today: a.currentDate, playerById: (id) => everyone.where((p) => p.id == id).firstOrNull, myTeamId: a.myTeamId);
    for (final (_, n) in preds) {
      // ignore: avoid_print
      print('${n.headline}\n${n.body.join('\n')}\n${n.teamFans.map((c) => c.text).join(' / ')}\n');
    }
    final stars = <MlbStar>[];
    final ow = a.otherWorld;
    if (ow != null) {
      for (final t in ow.teamsOf('MLB')) {
        for (final p in t.players.take(3)) {
          stars.add((p, t.short, null));
        }
      }
    }
    final foreign = everyone.where((p) => p.nationality == '海外' && p.ikusei).toList();
    // ignore: avoid_print
    print('育成外国人 ${foreign.length}人　大リーグ比較 ${stars.length}人');
    if (foreign.isNotEmpty) {
      final p = foreign.first;
      final n = ItemNews.of('12/1', 'ソフトクリームが育成選手として新外国人の${p.registeredName}（${p.mainPosition}）と契約した', NewsTopic.transfer, player: p, team: a.teams.first, myTeamId: a.myTeamId, stars: stars);
      // ignore: avoid_print
      print(n.teamFans.map((c) => c.text).join(' / '));
    }
    expect(preds, isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 10)));
}
