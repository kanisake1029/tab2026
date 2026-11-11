import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/db/app_database.dart';
import 'package:npb_pennant_app/engine/coach_engine.dart';
import 'package:npb_pennant_app/engine/growth_engine.dart';
import 'package:npb_pennant_app/providers/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AppState> boot(AppDatabase db) async {
  final a = AppState(db);
  while (!a.loaded) { await Future.delayed(const Duration(milliseconds: 10)); }
  a.autoMode = true;
  return a;
}

void main() {
  test('コーチ・OB・タイプ・相性・通算成績', () async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase(NativeDatabase.memory());
    final a = await boot(db);
    a.myTeamId = a.teams.first.id;
    a.onTeamChosen();
    final my = a.teams.first;

    // 各球団11人のコーチ、OB 野手30人・投手30人
    for (final t in a.teams) {
      expect(CoachEngine.staffRoles.every(a.staffOf(t).containsKey), true);
    }
    // OB は60人。CPU 球団の監督は、この OB から選ばれている
    final managers = a.coaches.where((c) => c.role == '監督').toList();
    expect(managers.length, a.teams.length - 1);
    expect(a.obList.length + managers.length, 60);
    // OB の能力は分からない（幅で表示）、雇って1シーズン経つと分かる
    expect(a.obList.where((c) => c.style.isEmpty).every((c) => !c.known), true);

    // タイプの分布
    final types = <String, int>{};
    for (final t in a.teams) {
      for (final p in t.players) {
        final ty = CoachEngine.playerType(p);
        types[ty] = (types[ty] ?? 0) + 1;
      }
    }
    print('タイプ分布: $types');
    expect(types.length, greaterThanOrEqualTo(8));

    // 相性
    expect(CoachEngine.affinity('スラッガー型', 'スラッガー型'), 1.2);
    expect(CoachEngine.affinity('スラッガー型', '守備職人型'), 0.9);
    expect(CoachEngine.affinity('打撃職人型', '俊足巧打型'), 1.05);
    // 練習効果の倍率は 0.6〜1.8
    final staff = a.staffOf(my);
    for (final p in my.players) {
      for (final s in GrowthEngine.statsOf(p)) {
        final m = CoachEngine.practiceMultiplier(p, s, my, staff);
        expect(m, inInclusiveRange(0.6, 1.8));
      }
    }

    // 打診：OB を打撃コーチに。いまのコーチは OB 一覧へ
    final old = staff['打撃']!;
    final ob = a.obList.firstWhere((c) => !c.pitcherBg);
    a.hireCoach(my, '打撃', ob);
    expect(a.staffOf(my)['打撃']!.id, ob.id);
    expect(old.teamId, isNull);

    // 通算成績：プロ2年目以上は推定値が入っている
    final vets = my.players.where((p) => p.proYears >= 5).toList();
    expect(vets.every((p) => p.career.games > 0), true);
    final v = vets.first;
    final before = v.career.games;

    var guard = 0;
    while (!a.seasonOver && guard++ < 450) { a.playNextDay(); }
    final played = v.seasonStats.games;
    await a.finishSeason();
    expect(v.career.games, before + played);
    expect(ob.known, true); // 1シーズン雇ったので本当の値が分かる
    expect(ob.seasonsWithTeam, 1);

    // 保存して読み直せる
    await a.saveData();
    final b = await boot(db);
    expect(b.coaches.length, a.coaches.length);
    expect(b.staffOf(b.teams.first)['打撃']!.id, ob.id);
  }, timeout: const Timeout(Duration(minutes: 10)));
}
