// ignore_for_file: avoid_print
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/db/app_database.dart';
import 'package:npb_pennant_app/providers/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AppState> load(String f, String tag) async {
  final tmp = File('${Directory.systemTemp.path}/s25_ds3_$tag.sqlite');
  await File(f).copy(tmp.path);
  final a = AppState(AppDatabase(NativeDatabase(tmp)));
  while (!a.loaded) { await Future.delayed(const Duration(milliseconds: 20)); }
  return a;
}

void main() {
  test('draft state3', () async {
    SharedPreferences.setMockInitialValues({});
    final old = await load('backup/s25_20261109.sqlite', 'old');
    final now = await load('backup/s25_20261111_now.sqlite', 'now');
    final mo = old.myTeam!, mn = now.myTeam!;
    print('4/29 支配下${mo.players.where((p) => !p.ikusei).length} 育成${mo.players.where((p) => p.ikusei).length} ／ 今 支配下${mn.players.where((p) => !p.ikusei).length} 育成${mn.players.where((p) => p.ikusei).length}');
    final oldIds = {for (final p in mo.players) p.id: p};
    for (final p in mn.players.where((p) => !oldIds.containsKey(p.id))) { print('増えた ${p.registeredName} ${p.age}歳 ${p.mainPosition} 育成=${p.ikusei} ${p.draftInfo} 入団=${p.offJoin} moves=${p.moves.take(2)}'); }
    for (final p in mn.players.where((p) => oldIds.containsKey(p.id) && oldIds[p.id]!.ikusei && !p.ikusei)) { print('育成→支配下 ${p.registeredName}'); }
    final nowIds = {for (final p in mn.players) p.id};
    for (final p in mo.players.where((p) => !nowIds.contains(p.id))) { print('いなくなった ${p.registeredName} ${p.age}歳 育成=${p.ikusei}'); }
    for (final t in now.transactions.where((x) => x.contains('東新')).take(25)) { print('取引 $t'); }
    final s = now.createDraftSession();
    print('ドラフト会議を開く：段階 ${s.stage} 自球団の本指名の枠 ${s.slots[now.myTeamId]} 本指名は済み扱い ${s.doneMain.contains(now.myTeamId)} 育成は済み扱い ${s.doneIkusei.contains(now.myTeamId)} 1位入札待ち ${s.firstPending.length}球団 候補 ${s.pool.length}');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
