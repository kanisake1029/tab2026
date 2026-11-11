import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/db/app_database.dart';
import 'package:npb_pennant_app/providers/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AppState> boot(AppDatabase db) async {
  final a = AppState(db);
  while (!a.loaded) {
    await Future.delayed(const Duration(milliseconds: 10));
  }
  return a;
}

/// 他リーグと NPB のつながり：外国人の候補・ドラフトの独立出身・契約したら他リーグから外れる・保存と読み込み
void main() {
  test('他リーグの選手が外国人の候補とドラフト候補になる', () async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase(NativeDatabase.memory());
    final a = await boot(db);
    a.myTeamId = a.teams[1].id;
    final w = a.otherWorld!;
    expect(w.teams.length, 267);
    // ドラフト候補の独立出身は、日本の独立リーグにいる選手
    final indie = a.prospects.where((p) => p.category == '独立').toList();
    expect(indie, isNotEmpty);
    expect(indie.every((p) => a.otherPlayer(p.id) != null), true, reason: '独立リーグに実際にいる');
    // 外国人の候補は他リーグにいる選手
    final pool = a.buildForeignPool(2026);
    expect(pool.length, 180);
    expect(pool.every((p) => a.otherPlayer(p.id) != null), true);
    expect(pool.where((p) => p.ikusei).length, 60);
    // 契約すると他リーグから外れ、その球団は26人に戻る
    a.foreignPool = pool;
    final p = pool.firstWhere((p) => !p.ikusei);
    final team = a.otherPlayer(p.id)!.$1;
    expect(a.signForeign(p), isNull);
    expect(a.otherPlayer(p.id), isNull);
    expect(team.players.length, 26);
    // ドラフトで指名した独立の選手も外れる
    final s = a.createDraftSession();
    s.runAll();
    a.applyDraft(s);
    for (final pk in s.picks.where((x) => x.prospect.category == '独立')) {
      expect(a.otherPlayer(pk.prospect.id), isNull);
    }
    // 保存して読み込むと同じ
    await a.saveData();
    final b = await boot(db);
    expect(b.otherWorld!.teams.length, 267);
    expect(b.otherPlayer(p.id), isNull);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
