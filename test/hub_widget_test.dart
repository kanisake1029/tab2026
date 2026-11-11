import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/db/app_database.dart';
import 'package:npb_pennant_app/main.dart';
import 'package:npb_pennant_app/providers/app_state.dart';
import 'package:npb_pennant_app/widgets/player_avatar.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 下の 5 タブ（ホーム・日程・チーム・フロント・データ）と、新しい画面（施設・球場・メーカー・キャンプ）が
///  スマホの幅で例外なく（はみ出しなく）描けるか。実際のセーブ（S25 の写し）で確かめる
void main() {
  final src = File('backup/s25_20261017.sqlite');
  testWidgets('5タブと新しい画面がスマホ幅で描ける', (tester) async {
    SharedPreferences.setMockInitialValues({});
    late AppState a;
    await tester.runAsync(() async {
      final tmp = File('${Directory.systemTemp.path}/s25_hub.sqlite');
      await src.copy(tmp.path);
      a = AppState(AppDatabase(NativeDatabase(tmp)));
      while (!a.loaded) {
        await Future.delayed(const Duration(milliseconds: 20));
      }
    });
    // ignore: avoid_print
    print('試合数 ${a.seasonGames}（以前のセーブ）・天気の種 ${a.weatherSeed}');
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.8;
    final orig = FlutterError.onError;
    FlutterError.onError = (d) {
      // ignore: avoid_print
      print(d.toString());
      orig?.call(d);
    };
    await tester.runAsync(() => FaceSet.instance.load());
    await tester.pumpWidget(MaterialApp(home: MainTabNavigator(appState: a)));
    await tester.pump();
    Future<void> settle() async {
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 400)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final ex = tester.takeException();
      if (ex is FlutterError) {
        // ignore: avoid_print
        print(ex.toStringDeep());
      }
      expect(ex, isNull);
    }

    for (final tab in ['日程', 'チーム', 'フロント', 'データ', 'ホーム']) {
      await tester.tap(find.text(tab).last);
      await settle();
      if (tab == 'チーム') {
        await tester.tap(find.text('キャンプ・練習'));
        await settle();
        // コーチ：下までスクロールしてスカウトの欄が出るか
        await tester.tap(find.text('コーチ').first);
        await settle();
        await tester.scrollUntilVisible(find.textContaining('スカウト（ドラフト候補'), 400, scrollable: find.byType(Scrollable).last);
        await settle();
        expect(find.textContaining('スカウト（ドラフト候補'), findsOneWidget);
      }
      if (tab == 'フロント') {
        for (final sub in ['施設・球場', 'メーカー', 'リーグ規定', '経営']) {
          await tester.tap(find.text(sub));
          await settle();
        }
      }
    }
    // ホームの中のタブ（順位・タイトル・ニュース・お知らせ）。ニュースは記事を開く
    for (final t in ['タイトル', 'ニュース', 'お知らせ', '順位']) {
      await tester.scrollUntilVisible(find.text(t).last, 300, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text(t).last);
      await settle();
    }
  }, skip: !src.existsSync());
}
