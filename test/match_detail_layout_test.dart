import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/db/app_database.dart';
import 'package:npb_pennant_app/engine/game_news.dart';
import 'package:npb_pennant_app/providers/app_state.dart';
import 'package:npb_pennant_app/screens/match_detail_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 試合結果：スコアボード（横にすべらない）・勝敗と本塁打の表・野手/投手のタブ・ニュース記事とコメントがスマホ幅で描ける
void main() {
  testWidgets('試合結果の画面', (tester) async {
    SharedPreferences.setMockInitialValues({});
    late AppState a;
    await tester.runAsync(() async {
      a = AppState(AppDatabase(NativeDatabase.memory()));
      while (!a.loaded) {
        await Future.delayed(const Duration(milliseconds: 20));
      }
      a.myTeamId = a.teams.first.id;
      a.autoMode = true;
      var d = 0;
      while (!a.matches.any((m) => m.isPlayed && m.matchType == 'OPEN') && d < 200) {
        a.playNextDay();
        d++;
      }
      for (var i = 0; i < 3; i++) {
        a.playNextDay();
      }
    });
    final m = a.matches.lastWhere((m) => m.isPlayed && m.boxScore != null);
    final home = a.teamById(m.homeTeamId)!, away = a.teamById(m.awayTeamId)!;
    final n = GameNews.of(m, home, away, myTeamId: a.myTeamId);
    // ignore: avoid_print
    print('${n.headline}\nMVP ${n.mvp?.name} ${n.mvp?.line}\n${n.lead}\nコメント ${n.awayFans.length}+${n.homeFans.length}：${n.homeFans.take(3).map((c) => c.text).join(' / ')}');
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.8;
    await tester.pumpWidget(MaterialApp(home: MatchDetailScreen(match: m, home: home, away: away, appState: a)));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('勝利投手'), findsWidgets);
    await tester.tap(find.text('投手成績'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('記事とコメントを読む ›'), 400, scrollable: find.byType(Scrollable).first);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('記事とコメントを読む ›'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('コメント（'), findsOneWidget);
  });
}
