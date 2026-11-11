import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/db/app_database.dart';
import 'package:npb_pennant_app/engine/coach_engine.dart';
import 'package:npb_pennant_app/providers/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AppState> boot(AppDatabase db) async {
  final a = AppState(db);
  while (!a.loaded) {
    await Future.delayed(const Duration(milliseconds: 10));
  }
  return a;
}

/// 仕様書 6・7章：3軍コーチ（複数人）・負荷・育成の上限
void main() {
  test('負荷の係数', () {
    expect(CoachEngine.loadFactor(0, 0), 1.0);
    expect(CoachEngine.loadFactor(6, 2), 1.08); // 50%
    expect(CoachEngine.loadFactor(8, 2), 1.05); // 67%
    expect(CoachEngine.loadFactor(12, 2), 1.0); // 100%
    expect(CoachEngine.loadFactor(18, 2), lessThan(1.0)); // 上限超え
  });

  test('3軍コーチは複数人・育成の上限が増える', () async {
    SharedPreferences.setMockInitialValues({});
    final a = await boot(AppDatabase(NativeDatabase.memory()));
    a.myTeamId = a.teams[1].id;
    final my = a.myTeam!;
    for (final r in CoachEngine.roles3G) {
      expect(a.staffListOf(my, r).length, 1, reason: '$r：初めは1人ずつ');
    }
    final cap0 = a.ikuseiCap(my);
    final ob = a.coaches.firstWhere((c) => c.teamId == null);
    a.hireCoach(my, '3軍打撃', ob);
    expect(a.staffListOf(my, '3軍打撃').length, 2, reason: '交代ではなく追加');
    expect(a.ikuseiCap(my), cap0 + 5);
    a.releaseCoach(ob);
    expect(a.staffListOf(my, '3軍打撃').length, 1);
    // ほかの役職はこれまでどおり交代
    final ob2 = a.coaches.firstWhere((c) => c.teamId == null);
    a.hireCoach(my, '打撃', ob2);
    expect(a.staffListOf(my, '打撃').length, 1);
  });
}
