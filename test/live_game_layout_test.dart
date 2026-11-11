import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/db/app_database.dart';
import 'package:npb_pennant_app/providers/app_state.dart';
import 'package:npb_pennant_app/screens/live_game_screen.dart';
import 'package:npb_pennant_app/utils/schedule_generator.dart';
import 'package:npb_pennant_app/widgets/player_avatar.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 試合画面（案C）がスマホの大きさではみ出さずに描ける。タブ「データ・速報」とオーダーのボタンも開ける
void main() {
  testWidgets('試合画面 案C スマホ', (tester) async {
    SharedPreferences.setMockInitialValues({});
    late AppState a;
    await tester.runAsync(() async {
      await FaceSet.instance.load();
      final tmp = File('${Directory.systemTemp.path}/s25_live.sqlite');
      await File('backup/s25_20261017.sqlite').copy(tmp.path);
      a = AppState(AppDatabase(NativeDatabase(tmp)));
      while (!a.loaded) {
        await Future.delayed(const Duration(milliseconds: 20));
      }
    });
    final home = a.myTeam!, away = a.teams.firstWhere((t) => t.id != home.id && t.league == home.league);
    final m = Match(homeTeamId: home.id, awayTeamId: away.id, date: a.currentDate, matchType: 'OPEN');
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    await tester.pumpWidget(MaterialApp(home: LiveGameScreen(match: m, homeTeam: home, awayTeam: away, myTeamId: home.id, manage: true, appState: a)));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    Future<void> settle() async {
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
    }
    // 采配の分類（チップ）・速報・対戦の「詳しく」・オーダー
    for (final tab in ['配球', '守備', '交代', '速報']) {
      await tester.tap(find.text(tab).last);
      await settle();
      expect(tester.takeException(), isNull, reason: tab);
    }
    await tester.tap(find.text('詳しく'));
    await settle();
    expect(tester.takeException(), isNull, reason: '詳しく');
    expect(find.textContaining('対戦成績'), findsWidgets);
    await tester.tapAt(const Offset(20, 20)); // 閉じる
    await settle();
    await tester.tap(find.text('オーダー').last); // オーダーはボタンで浮かせて出す
    await settle();
    expect(tester.takeException(), isNull, reason: 'オーダー');
    expect(find.textContaining('ビジター　'), findsWidgets); // オーダー：試合前と同じ表（ビジター・ホーム）
    expect(find.textContaining('ホーム　'), findsWidgets);
  });
}
