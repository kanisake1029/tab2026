import 'dart:io';
import 'dart:ui' as ui;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/db/app_database.dart';
import 'package:npb_pennant_app/providers/app_state.dart';
import 'package:npb_pennant_app/screens/live_game_screen.dart';
import 'package:npb_pennant_app/utils/schedule_generator.dart';
import 'package:npb_pennant_app/widgets/player_avatar.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 試合画面をスマホの大きさで PNG に描き出す（見た目の確認用）。出力先は環境変数 SHOT_DIR
void main() {
  testWidgets('試合画面の画像', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final out = Platform.environment['SHOT_DIR'] ?? Directory.systemTemp.path;
    late AppState a;
    await tester.runAsync(() async {
      final font = FontLoader('JP')..addFont(File('C:/Windows/Fonts/NotoSansJP-VF.ttf').readAsBytes().then((b) => ByteData.view(b.buffer)));
      await font.load();
      await FaceSet.instance.load();
      final tmp = File('${Directory.systemTemp.path}/s25_shot.sqlite');
      await File('backup/s25_20261017.sqlite').copy(tmp.path);
      a = AppState(AppDatabase(NativeDatabase(tmp)));
      while (!a.loaded) {
        await Future.delayed(const Duration(milliseconds: 20));
      }
    });
    final home = a.myTeam!, away = a.teams.firstWhere((t) => t.id != home.id && t.league == home.league);
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    for (final (name, me) in [('defense', home.id), ('attack', away.id)]) {
      final m = Match(homeTeamId: home.id, awayTeamId: away.id, date: a.currentDate, matchType: 'OPEN');
      final key = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(key: key, child: MaterialApp(theme: ThemeData(fontFamily: 'JP'), home: LiveGameScreen(key: ValueKey(name), match: m, homeTeam: home, awayTeam: away, myTeamId: me, manage: true, appState: a))));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      await tester.runAsync(() async {
        final img = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage(pixelRatio: 1);
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        await File('$out/live_$name.png').writeAsBytes(bytes!.buffer.asUint8List());
      });
    }
  });
}
