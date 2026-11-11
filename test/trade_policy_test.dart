import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/db/app_database.dart';
import 'package:npb_pennant_app/engine/transfer_engine.dart';
import 'package:npb_pennant_app/providers/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AppState> boot(AppDatabase db) async {
  final a = AppState(db);
  while (!a.loaded) {
    await Future.delayed(const Duration(milliseconds: 10));
  }
  return a;
}

/// 仕様書 4・5章と9章-1：球団の方針・指名権のトレード・現役ドラフト
void main() {
  test('方針・指名権のトレード・現役ドラフト', () async {
    SharedPreferences.setMockInitialValues({});
    final a = await boot(AppDatabase(NativeDatabase.memory()));
    a.myTeamId = a.teams[1].id;
    // 方針：3種類のどれか。複数の方針に分かれる
    final pols = {for (final t in a.teams) a.policyOf(t)};
    expect(pols.every(TransferEngine.policyLabels.containsKey), true);
    expect(pols.length, greaterThanOrEqualTo(2), reason: '方針が分かれる: $pols');
    // 再建中の球団は、優勝を狙う球団より指名権を高く見る
    expect(TransferEngine.pickValue(2, winNow: -0.5), greaterThan(TransferEngine.pickValue(2, winNow: 0.4)));

    // 指名権のトレード：自球団の2位を相手へ → 次のドラフトで相手が2巡目に2回指名する
    final my = a.myTeam!, pt = a.teams[4];
    expect(a.tradablePicks(my).length, 4, reason: '2〜5位の4つ');
    var err = 'x';
    for (var i = 0; i < 6 && err.isNotEmpty; i++) {
      err = a.proposeTrade(pt, const [], const [], 30000, givePicks: [(2, my.id)]) ?? '';
      if (err.isNotEmpty) a.lastTradeWith.clear();
    }
    expect(err, '', reason: '2位＋3億円なら受ける');
    expect(a.pickOwnerOf(2, my.id), pt.id);
    expect(a.tradablePicks(my).any((x) => x.$1 == 2), false);
    expect(a.proposeTrade(pt, const [], const [], 1000, givePicks: [(3, my.id)]), contains('日たたないと'), reason: '同じ球団とは14日あける');
    final s = a.createDraftSession();
    s.runAll();
    final r2 = s.picks.where((p) => !p.ikusei && !p.comp && p.round == 2);
    expect(r2.where((p) => p.teamId == my.id).length, 0, reason: '2位を手放した');
    expect(r2.where((p) => p.teamId == pt.id).length, lessThanOrEqualTo(2));
    a.applyDraft(s);
    expect(a.pickOwner, isEmpty);

    // 現役ドラフト：各球団が獲るのは1人まで、失うのは1人まで
    final moves = TransferEngine.runActiveDraft(a.teams, 2025, (t, c) => c.first);
    expect(moves, isNotEmpty);
    final gain = <String, int>{}, lose = <String, int>{};
    for (final (f, to, _) in moves) {
      gain[to.id] = (gain[to.id] ?? 0) + 1;
      lose[f.id] = (lose[f.id] ?? 0) + 1;
      expect(f.id == to.id, false);
    }
    expect(gain.values.every((n) => n == 1), true);
    expect(lose.values.every((n) => n == 1), true);
  });
}
