import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/db/app_database.dart';
import 'package:npb_pennant_app/providers/app_state.dart';
import 'package:npb_pennant_app/utils/player_generator.dart';
import 'package:npb_pennant_app/utils/standings.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AppState> boot(AppDatabase db, [int slot = 1]) async {
  final a = AppState(db, slot);
  while (!a.loaded) {
    await Future.delayed(const Duration(milliseconds: 10));
  }
  return a;
}

void main() {
  AppState.scanOtherSlots = false;
  test('はじめから：新規作成チームは初期状態から（移籍で入った選手は残らず、出ていった選手は戻る）', () async {
    SharedPreferences.setMockInitialValues({});
    final a = await boot(AppDatabase(NativeDatabase.memory()));
    final kochi = generateNewTeam(year: 2026)..id = 'T_kochi_test';
    a.teams.add(kochi);
    kochi.league = 'PL';
    a.teams.firstWhere((t) => t.league == 'PL' && t.id != kochi.id).league = '';
    // 高知の選手が他球団へ移籍、他球団の選手が高知へ移籍
    final other = a.teams.firstWhere((t) => t.league == 'CL');
    final gone = kochi.players.first;
    kochi.players.remove(gone);
    other.players.add(gone);
    gone.moves.add('2026年7月1日 トレードで${teamShort(other)}へ（←${teamShort(kochi)}）');
    final came = other.players.firstWhere((p) => p != gone);
    other.players.remove(came);
    kochi.players.add(came);
    came.moves.add('2026年7月1日 トレードで${teamShort(kochi)}へ（←${teamShort(other)}）');
    a.myTeamId = kochi.id;
    await a.resetToInitialTeams();
    final k = a.teamById(kochi.id)!;
    expect(k.league, 'PL');
    expect(k.players.any((p) => p.id == gone.id), true);
    expect(k.players.any((p) => p.id == came.id), false);
    expect(a.teamById(other.id)!.players.any((p) => p.id == came.id), true); // 固有球団は初期データから
    // 2回目のはじめからも同じ（初期状態が保存されている）
    await a.resetToInitialTeams();
    expect(a.teamById(kochi.id)!.players.length, k.players.length);
  });

  test('プレイデータは枠ごとに別（空いた枠は初期データから、新規作成チームも選べる）', () async {
    SharedPreferences.setMockInitialValues({});
    final a1 = await boot(AppDatabase(NativeDatabase.memory()), 1);
    final t = generateNewTeam(year: 2026)..id = 'T_slot_test';
    a1.teams.add(t);
    await a1.saveInitialState(t);
    a1.myTeamId = a1.teams.first.id;
    a1.autoMode = true;
    for (var i = 0; i < 5; i++) {
      a1.playNextDay();
    }
    final a2 = await boot(AppDatabase(NativeDatabase.memory()), 2);
    expect(a2.isFresh, true);
    expect(a2.currentDate.isBefore(a1.currentDate), true);
    await a2.addStoredTeams();
    expect(a2.teams.any((x) => x.id == 'T_slot_test' && x.league == ''), true);
  });
}
