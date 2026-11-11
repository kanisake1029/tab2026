// ignore_for_file: avoid_print
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/db/app_database.dart';
import 'package:npb_pennant_app/providers/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('draft state', () async {
    SharedPreferences.setMockInitialValues({});
    final tmp = File('${Directory.systemTemp.path}/s25_ds.sqlite');
    await File(Platform.environment['SAVE'] ?? 'backup/s25_20261111_afterdraft.sqlite').copy(tmp.path);
    final a = AppState(AppDatabase(NativeDatabase(tmp)));
    while (!a.loaded) { await Future.delayed(const Duration(milliseconds: 20)); }
    print('日付 ${a.currentDate} 開始年 ${a.startYear} 自球団 ${a.myTeam?.name} draftDoneYear ${a.draftDoneYear} 候補 ${a.prospects.length}人 amWorld ${a.amWorld?.players.length}');
    print('compPicks ${a.compPicks} pickOwner ${a.pickOwner}');
    for (final y in a.draftBook.keys) { print('draftBook $y: ${a.draftBook[y]!.length}件'); }
    final book = a.draftBook[a.draftDoneYear] ?? [];
    for (final e in book.where((e) => e['team'] == a.myTeamId)) { print('  自球団 ${e['label']} ${e['name']} ${e['pos']} ${e['cat']} ${e['school']}'); }
    for (final t in a.transactions.take(8)) { print('取引 $t'); }
    for (final n in a.news.take(6)) { print('ニュース $n'); }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
