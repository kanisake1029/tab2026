import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/db/app_database.dart';
import 'package:npb_pennant_app/engine/batting_splits.dart';
import 'package:npb_pennant_app/engine/career_path.dart';
import 'package:npb_pennant_app/engine/other_league_engine.dart';
import 'package:npb_pennant_app/engine/roster_engine.dart';
import 'package:npb_pennant_app/models/player.dart';
import 'package:npb_pennant_app/providers/app_state.dart';
import 'package:npb_pennant_app/utils/app_theme.dart';
import 'package:npb_pennant_app/widgets/player_detail_dialog.dart';
import 'package:npb_pennant_app/widgets/scout_report.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('① テーマのフォントが BIZUDPGothic である', () {
    final t = AppTheme.modernLight;
    final c = AppTheme.compact(t);
    expect(t.textTheme.bodyMedium?.fontFamily, 'BIZUDPGothic');
    expect(t.appBarTheme.titleTextStyle?.fontFamily, 'BIZUDPGothic');
    expect(c.appBarTheme.titleTextStyle?.fontFamily, 'BIZUDPGothic');
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

    // 経歴タブの成績表に 3A* の成績が出る（2025以前は憶測のため * とグレー）
    await tester.tap(find.text('経歴').first);
    await tester.pumpAndSettle();
    expect(find.text('3A*'), findsOneWidget);
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

  test('④-2 シーズン途中の入団・来日でも1か月の猶予期間中は即時反映＆経歴に当初番号として残る', () async {
    SharedPreferences.setMockInitialValues({});
    final app = AppState(AppDatabase(NativeDatabase.memory()));
    while (!app.loaded) {
      await Future.delayed(const Duration(milliseconds: 20));
    }
    final t = app.teams.first;
    final p = t.players.firstWhere((x) => !x.ikusei);
    final n14 = [for (var n = 14; n <= 99; n++) if (!t.players.any((x) => x.uniformNumber == n)) n].first;
    final n53 = [for (var n = 53; n <= 99; n++) if (n != n14 && !t.players.any((x) => x.uniformNumber == n)) n].first;
    p.uniformNumber = n14;

    final joinDate = DateTime(2026, 4, 1);
    app.currentDate = DateTime(2026, 4, 15);
    app.markNumberFree(p, joinDate);
    app.chron.add({
      'd': '2026-04-01',
      'team': t.id,
      'k': 'join',
      't': '外野手 ${p.registeredName}(${p.age})が来日して入団。背番号は${uniformLabel(n14)}。',
      'pid': p.id,
      'pt': '来日して${t.name}に入団。背番号${uniformLabel(n14)}。',
    });

    final err = app.setNumber(t, p, n53);
    expect(err, isNull);
    expect(p.uniformNumber, n53);
    expect(p.nextNumber, isNull);
    expect(app.chron.any((c) => c['pid'] == p.id && c['k'] == 'number'), isFalse);

    final tl = await app.playerTimeline(p);
    expect(tl.any((e) => e.$2.contains('変更')), isFalse);
    expect(tl.any((e) => e.$2.contains('来日して${t.name}に入団。背番号${uniformLabel(n53)}。')), isTrue);
    expect(tl.any((e) => e.$2.contains('背番号${uniformLabel(n14)}。')), isFalse);
  });

  testWidgets('支配下登録: 2027/6/12・支配下65人で選手詳細ダイアログから支配下登録できる', (tester) async {
    SharedPreferences.setMockInitialValues({});
    late AppState app;
    await tester.runAsync(() async {
      app = AppState(AppDatabase(NativeDatabase.memory()));
      while (!app.loaded) {
        await Future.delayed(const Duration(milliseconds: 20));
      }
    });
    app.myTeamId = app.teams.first.id;
    app.startYear = 2027;
    app.currentDate = DateTime(2027, 6, 12);
    app.seasonFinished = false;
    final my = app.myTeam!;
    final sh = my.players.where((p) => !p.ikusei).toList();
    while (sh.length > 65) {
      my.players.remove(sh.removeLast());
    }
    final ik = my.players.firstWhere((p) => p.ikusei, orElse: () {
      final p = my.players.last;
      p.ikusei = true;
      p.uniformNumber = 101;
      return p;
    });
    expect(RosterEngine.shihaikaCount(my), lessThanOrEqualTo(65));
    expect(ik.ikusei, isTrue);

    await tester.binding.setSurfaceSize(const Size(411, 860));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => showPlayerDetail(ctx, app, ik),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('支配下登録'), findsOneWidget);
    await tester.tap(find.text('支配下登録'));
    await tester.pumpAndSettle();

    expect(find.text('登録する'), findsOneWidget);
    await tester.tap(find.text('登録する'));
    await tester.pumpAndSettle();

    expect(ik.ikusei, isFalse);
    expect(ik.uniformNumber, lessThan(100));
  });

  test('海外球団3文字略称・外国人経歴の時系列整理・コース得手不得手', () {
    expect(OtherLeagueEngine.abbr3('ロサンゼルス・ドジャース'), 'LAD');
    expect(OtherLeagueEngine.abbr3('ソウル'), 'SEO');

    final f = Player(id: 'foreign_test', lastName: 'テスト', isPitcher: false, nationality: '海外', origin: 'アメリカ', mainPos: '外野手', age: 27, abroad: [
      '2024　3A・OKC　100試合 打率.290 15本 50打点 OPS.850',
      '2023　MLB・LAD　30試合 打率.210 2本 10打点 OPS.620',
      '2023　3A・OKC　80試合 打率.305 14本 48打点 OPS.900',
      '2022　3A・OKC　115試合 打率.280 18本 65打点 OPS.830',
    ]);
    final cp = CareerPath.of(f);
    expect(cp, ['出身　アメリカ', '3A・OKC（2022）*', 'MLB・LAD／3A・OKC（2023）*', '3A・OKC（2024）*']);

    // コース相性は -1.0〜1.0 に収まり、内外角/高低で符号が反転する
    final b = Player(id: 'batter_course_1', lastName: '打者', isPitcher: false, bats: 'R', mainPos: '一塁手');
    final a1 = BattingSplits.courseAffinity(b, -0.8, 0.8, 'R');
    final a2 = BattingSplits.courseAffinity(b, 0.8, -0.8, 'R');
    expect(a1, inInclusiveRange(-1.0, 1.0));
    expect(a2, inInclusiveRange(-1.0, 1.0));
    expect(a1, closeTo(-a2, 1e-9));
  });
}
