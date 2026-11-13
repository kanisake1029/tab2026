import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/db/app_database.dart';
import 'package:npb_pennant_app/models/player.dart';
import 'package:npb_pennant_app/providers/app_state.dart';
import 'package:npb_pennant_app/utils/app_theme.dart';
import 'package:npb_pennant_app/widgets/scout_report.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('① テーマのフォントが ZenKakuGothicNew である', () {
    final t = AppTheme.modernLight;
    final c = AppTheme.compact(t);
    expect(t.textTheme.bodyMedium?.fontFamily, 'ZenKakuGothicNew');
    expect(t.appBarTheme.titleTextStyle?.fontFamily, 'ZenKakuGothicNew');
    expect(c.appBarTheme.titleTextStyle?.fontFamily, 'ZenKakuGothicNew');
  });

  testWidgets('② 別リーグ成績は寸評欄ではなく成績表に出る／③ 球団経歴は年表へ移籍経緯付きで載る', (tester) async {
    SharedPreferences.setMockInitialValues({});
    late AppState app;
    await tester.runAsync(() async {
      app = AppState(AppDatabase(NativeDatabase.memory()));
      while (!app.loaded) {
        await Future.delayed(const Duration(milliseconds: 20));
      }
    });
    final t0 = app.teams[0], t1 = app.teams[1];
    final p = t0.players.firstWhere((x) => !x.isPitcher);
    p.abroad = ['2025　3A　110試合 打率.295 18本 65打点 OPS.860'];
    p.moves.add('2026年12月9日 現役ドラフトで${t1.shortName}へ（←${t0.shortName}）');
    final tl = await app.playerTimeline(p);
    expect(tl.any((e) => e.$2.contains('現役ドラフト')), isTrue);

    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.modernLight,
      home: Scaffold(body: SingleChildScrollView(child: ScoutReport(player: p, appState: app, onClose: () {}))),
    ));
    await tester.pumpAndSettle();

    // 寸評欄に「海外での成績」は出ない
    expect(find.textContaining('海外での成績'), findsNothing);

    // 経歴タブの成績表に 3A の成績が出る
    await tester.tap(find.text('経歴').first);
    await tester.pumpAndSettle();
    expect(find.text('3A'), findsOneWidget);
    expect(find.text('.295'), findsOneWidget);

    // 年表タブに「移籍の歩み」は別枠で出ず、年表内に現役ドラフトが出る
    await tester.tap(find.text('年表'));
    await tester.pumpAndSettle();
    expect(find.text('移籍の歩み'), findsNothing);
    expect(find.textContaining('現役ドラフト'), findsOneWidget);
  });

  test('④ オフシーズン（11/1〜1/31）の背番号変更は即時反映され、経歴に残らず入団時番号を書き換える', () async {
    SharedPreferences.setMockInitialValues({});
    final app = AppState(AppDatabase(NativeDatabase.memory()));
    while (!app.loaded) {
      await Future.delayed(const Duration(milliseconds: 20));
    }
    final t = app.teams.first;
    final p = t.players.firstWhere((x) => !x.ikusei);
    final oldNum = p.uniformNumber;
    final newNum = [for (var n = 1; n <= 99; n++) if (!t.players.any((x) => x.uniformNumber == n)) n].first;

    app.currentDate = DateTime(2026, 11, 15);
    app.chron.add({
      'd': '2026-11-10',
      'team': t.id,
      'k': 'join',
      't': '内野手 ${p.registeredName}(${p.age})が入団。背番号は${p.uniformText}。',
      'pid': p.id,
      'pt': '${t.name}に入団。背番号${p.uniformText}。',
    });

    final err = app.setNumber(t, p, newNum);
    expect(err, isNull);
    expect(p.uniformNumber, newNum);
    expect(p.nextNumber, isNull);
    expect(app.chron.any((c) => c['pid'] == p.id && c['k'] == 'number'), isFalse);

    final tl = await app.playerTimeline(p);
    expect(tl.any((e) => e.$2.contains('変更')), isFalse);
    expect(tl.any((e) => e.$2.contains('背番号${uniformLabel(newNum)}。')), isTrue);
    expect(tl.any((e) => e.$2.contains('背番号${uniformLabel(oldNum)}。')), isFalse);
  });
}
