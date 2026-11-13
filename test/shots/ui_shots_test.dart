import 'dart:io';
import 'dart:ui' as ui;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/db/app_database.dart';
import 'package:npb_pennant_app/providers/app_state.dart';
import 'package:npb_pennant_app/screens/draft_screen.dart';
import 'package:npb_pennant_app/screens/slot_screen.dart';
import 'package:npb_pennant_app/widgets/player_avatar.dart';
import 'package:npb_pennant_app/widgets/player_detail_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 画面をスマホの大きさで PNG に描き出す（見た目の確認用）。出力先は環境変数 SHOT_DIR。実機のセーブのコピー（backup/）が要る
///  ドラフト会議の上部（枠なし／枠あり）・スロット画面の控え・選手詳細
void main() {
  const src = 'backup/s25_20261111_now.sqlite';
  final out = Platform.environment['SHOT_DIR'] ?? Directory.systemTemp.path;

  Future<void> shot(WidgetTester tester, GlobalKey key, String name) async {
    await tester.runAsync(() async {
      final img = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage(pixelRatio: 1);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      await File('$out/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    });
  }

  Future<AppState> load(WidgetTester tester) async {
    late AppState a;
    await tester.runAsync(() async {
      final font = FontLoader('JP')..addFont(File('C:/Windows/Fonts/NotoSansJP-VF.ttf').readAsBytes().then((b) => ByteData.view(b.buffer)));
      await font.load();
      await FaceSet.instance.load();
      final tmp = File('${Directory.systemTemp.path}/tab_ui_shot_${DateTime.now().microsecondsSinceEpoch}.sqlite');
      await File(src).copy(tmp.path);
      a = AppState(AppDatabase(NativeDatabase(tmp)));
      while (!a.loaded) {
        await Future.delayed(const Duration(milliseconds: 20));
      }
    });
    return a;
  }

  testWidgets('ドラフト会議の上部（支配下が満員・空きあり）', (tester) async {
    if (!File(src).existsSync()) return;
    SharedPreferences.setMockInitialValues({});
    final a = await load(tester);
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    for (final (name, release) in [('draft_full', 0), ('draft_slots', 8)]) {
      final team = a.myTeam!;
      final ps = team.players.where((p) => !p.ikusei).toList();
      for (var i = 0; i < release; i++) {
        a.releasePlayer(ps[ps.length - 1 - i]);
      }
      final key = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(key: key, child: MaterialApp(theme: ThemeData(fontFamily: 'JP'), home: DraftScreen(appState: a))));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 80));
      }
      await shot(tester, key, name);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('スロット画面の控え', (tester) async {
    if (!File(src).existsSync()) return;
    final dir = Directory.systemTemp.createTempSync('tab_slot_shot');
    AppDatabase.documentsPathOverride = dir.path;
    SharedPreferences.setMockInitialValues({'slotSummary_1': '{"team":"東京新聞タイタンズ","short":"東新","date":"2026-10-31T00:00:00.000","w":0,"l":0,"d":0}'});
    await tester.runAsync(() async {
      final font = FontLoader('JP')..addFont(File('C:/Windows/Fonts/NotoSansJP-VF.ttf').readAsBytes().then((b) => ByteData.view(b.buffer)));
      await font.load();
      final tmp = File('${dir.path}/npb_pennant.sqlite');
      await File(src).copy(tmp.path);
      final db = AppDatabase(NativeDatabase(tmp), true);
      await db.backupSlot(label: '2026年ドラフト会議の前', gameDate: '2026年10月31日');
      await db.backupSlot(label: '契約更改の前（2025年12月1日）', gameDate: '2025年12月1日');
      await db.close();
    });
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    final key = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(key: key, child: MaterialApp(theme: ThemeData(fontFamily: 'JP'), home: SlotScreen(mainOf: (app) => const SizedBox()))));
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await shot(tester, key, 'slot_list');
    final lst = await tester.runAsync(() => AppDatabase.listBackups(1));
    print('控えの数 ${lst?.length} ${lst?.map((b) => b.label).toList()}');
    expect(find.byIcon(Icons.history), findsOneWidget);
    await tester.tap(find.byIcon(Icons.history));
    await tester.pump();
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 150));
      if (find.byType(BottomSheet).evaluate().isNotEmpty) break;
    }
    await tester.pump(const Duration(milliseconds: 600)); // シートが上がりきるまで
    print('控えの画面: BottomSheet ${find.byType(BottomSheet).evaluate().length}件 例外 ${tester.takeException()}');
    await shot(tester, key, 'slot_backups');
    AppDatabase.documentsPathOverride = null;
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  testWidgets('選手詳細（スマホ）', (tester) async {
    if (!File(src).existsSync()) return;
    SharedPreferences.setMockInitialValues({});
    final a = await load(tester);
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    final team = a.myTeam!;
    for (final (name, p) in [('detail_bat', team.players.firstWhere((p) => !p.isPitcher && !p.ikusei)), ('detail_pit', team.players.firstWhere((p) => p.isPitcher && !p.ikusei))]) {
      final key = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(key: key, child: MaterialApp(theme: ThemeData(fontFamily: 'JP'), home: Scaffold(body: PlayerDetailDialog(player: p, appState: a, team: team, isReadOnly: true)))));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 80));
      }
      await shot(tester, key, name);
      await tester.pumpWidget(const SizedBox());
    }
  });
}
