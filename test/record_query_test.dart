import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/db/app_database.dart';
import 'package:npb_pennant_app/engine/record_query.dart';
import 'package:npb_pennant_app/providers/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 記録タブ「条件で探す」：試合ごとの記録から、節目の達成（何試合目）と連続記録を出せる
void main() {
  test('節目と連続記録', () async {
    SharedPreferences.setMockInitialValues({});
    final tmp = File('${Directory.systemTemp.path}/s25_rq.sqlite');
    await File('backup/s25_20261017.sqlite').copy(tmp.path);
    final a = AppState(AppDatabase(NativeDatabase(tmp)));
    while (!a.loaded) {
      await Future.delayed(const Duration(milliseconds: 20));
    }
    final (logs, teamGames) = await a.gameLogs();
    final pre = await a.preCareers();
    expect(logs, isNotEmpty);
    final hitsK = MilestoneKind.all.first;
    final hits = [
      for (final t in a.teams)
        for (final p in t.players)
          if (!p.isPitcher) RecordQuery.milestone(p, hitsK, 1000, a.careerTotalOf(p), logs[p.id] ?? const [], pre[p.id] ?? const []),
    ].whereType<MilestoneHit>().toList()
      ..sort((x, y) => x.gameNo.compareTo(y.gameNo));
    // ignore: avoid_print
    print('1000安打 ${hits.length}人: ${hits.take(3).map((h) => '${h.p.registeredName} ${h.gameNo}試合目 ${h.year} ${h.age}歳${h.estimated ? '(推定)' : ''}').join(' / ')}');
    final sk = StreakKind.all.first;
    final st = [
      for (final t in a.teams)
        for (final p in t.players)
          if (!p.isPitcher) ...RecordQuery.streaks(p, sk, logs[p.id] ?? const [], teamGames, 8),
    ]..sort((x, y) => y.len.compareTo(x.len));
    // ignore: avoid_print
    print('連続試合安打 ${st.length}件: ${st.take(3).map((s) => '${s.p.registeredName} ${s.len} ${s.start}〜${s.end}').join(' / ')}');
    expect(st, isNotEmpty);
  });
}
