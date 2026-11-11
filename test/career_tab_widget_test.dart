import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/db/app_database.dart';
import 'package:npb_pennant_app/providers/app_state.dart';
import 'package:npb_pennant_app/widgets/scout_report.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final src = File('backup/s25_20261017.sqlite');
  testWidgets('経歴タブが例外なく描ける（実際のセーブ）', (tester) async {
    SharedPreferences.setMockInitialValues({});
    late AppState a;
    await tester.runAsync(() async {
      final tmp = File('${Directory.systemTemp.path}/s25_w.sqlite');
      await File('backup/s25_20261017.sqlite').copy(tmp.path);
      a = AppState(AppDatabase(NativeDatabase(tmp)));
      while (!a.loaded) { await Future.delayed(const Duration(milliseconds: 20)); }
    });
    final p = a.myTeam!.players.firstWhere((x) => x.registeredName.startsWith('佐藤'), orElse: () => a.myTeam!.players.first);
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.6;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ScoutReport(player: p, appState: a, team: a.myTeam, onClose: () {}))));
    await tester.tap(find.text('経歴').first);
    await tester.runAsync(() => Future.delayed(const Duration(seconds: 3)));
    await tester.pump();
    await tester.runAsync(() => Future.delayed(const Duration(seconds: 1)));
    await tester.pump();
    expect(tester.takeException(), isNull);
  }, skip: !src.existsSync());
}
