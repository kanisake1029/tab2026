// ignore_for_file: avoid_print
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/db/app_database.dart';
import 'package:npb_pennant_app/engine/roster_engine.dart';
import 'package:npb_pennant_app/providers/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('draft state2', () async {
    SharedPreferences.setMockInitialValues({});
    final tmp = File('${Directory.systemTemp.path}/s25_ds2.sqlite');
    await File(Platform.environment['SAVE'] ?? 'backup/s25_20261111_now.sqlite').copy(tmp.path);
    final a = AppState(AppDatabase(NativeDatabase(tmp)));
    while (!a.loaded) { await Future.delayed(const Duration(milliseconds: 20)); }
    print('日付 ${a.currentDate} 開始年 ${a.startYear} draftDoneYear ${a.draftDoneYear} prepDraftYear ${a.prepDraftYear} draftPending ${a.draftPending} 候補 ${a.prospects.length} 候補の年 ${a.prospects.isEmpty ? '-' : a.prospects.first.year}');
    for (final t in a.leagueTeams) {
      final reg = t.players.where((p) => !p.ikusei).length, iku = t.players.where((p) => p.ikusei).length;
      final d26 = t.players.where((p) => p.draftYear == 2026).toList();
      final d25 = t.players.where((p) => p.draftYear == 2025).toList();
      print('${t.shortName.padRight(6)} 支配下$reg 育成$iku 空き枠${RosterEngine.freeSlots(t)} 2026年ドラフト入団${d26.length}人(育成${d26.where((p) => p.ikusei).length}) 2025年${d25.length}人${t.id == a.myTeamId ? ' ←自球団' : ''}');
      if (t.id == a.myTeamId) { for (final p in [...d26, ...d25]) { print('   ${p.registeredName} ${p.age}歳 ${p.draftInfo} 育成=${p.ikusei} 背番号${p.uniformNumber}'); } }
    }
    for (final t in a.transactions.where((x) => x.contains('ドラフト')).take(6)) { print('取引 $t'); }
    print('取引の先頭 ${a.transactions.take(3).join(' | ')}');
    final ids = {for (final t in a.teams) for (final p in t.players) p.id};
    print('候補のうち、もう球団にいる選手 ${a.prospects.where((p) => ids.contains(p.id)).length}人');
    print('志望届 ${a.prospects.where((p) => p.wishFiled).length}人  種別 ${{for (final p in a.prospects) p.category}.map((c) => '$c:${a.prospects.where((p) => p.category == c).length}').join(' ')}  育成候補 ${a.prospects.where((p) => p.ikuseiTier).length}');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
