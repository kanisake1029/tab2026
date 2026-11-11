import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/db/app_database.dart';
import 'package:npb_pennant_app/engine/roster_engine.dart';
import 'package:npb_pennant_app/models/player.dart';
import 'package:npb_pennant_app/providers/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('ゲーム開始前の経歴の推定：年度の合計が通算と一致し、タイトルは年・リーグで1人。CPU の育成は20人前後', () async {
    SharedPreferences.setMockInitialValues({});
    final a = AppState(AppDatabase(NativeDatabase.memory()));
    while (!a.loaded) { await Future.delayed(const Duration(milliseconds: 10)); }
    a.autoMode = true;
    a.myTeamId = a.teams.first.id;
    final pre = await a.preCareers();
    expect(pre, isNotEmpty);
    final byId = {for (final t in a.teams) for (final p in t.players) p.id: p};
    for (final e in pre.entries) {
      final p = byId[e.key];
      if (p == null) continue;
      final sum = PlayerStats();
      for (final y in e.value) { sum.add(y.stats); }
      expect(sum.homeRuns, p.career.homeRuns, reason: p.registeredName);
      expect(sum.wins, p.career.wins);
      expect(sum.games, greaterThanOrEqualTo(p.career.games));
      expect(e.value.length, p.proYears - 1, reason: '${p.registeredName} ${p.proYears}');
    }
    final seen = <String>{};
    final lg = {for (final t in a.teams) t.id: t.league};
    var titles = 0, marks = 0;
    for (final ys in pre.values) {
      for (final y in ys) {
        for (final h in y.honors) {
          if (h.contains('達成')) { marks++; continue; }
          titles++;
          if (h.contains('ベストナイン') || h.contains('ゴールデングラブ')) continue; // 守備位置ごとに1人（リーグで複数）
          final k = '$h|${lg[y.teamId]}';
          expect(seen.add(k), isTrue, reason: k);
        }
      }
    }
    // ignore: avoid_print
    print('推定 ${pre.length}人 タイトル$titles 節目$marks');
    final star = pre.entries.where((e) => byId[e.key] != null).reduce((x, y) => x.value.length >= y.value.length ? x : y);
    for (final y in star.value) {
      // ignore: avoid_print
      print('${byId[star.key]!.registeredName} ${y.year} ${y.stats.games}試合 ${y.stats.homeRuns}本 ${y.stats.wins}勝 ${y.honors}');
    }
    // ドラフトまで進めて、CPU 球団の育成の人数
    a.runAutoDraft();
    for (final t in a.teams) {
      // ignore: avoid_print
      print('${t.shortName} 育成${RosterEngine.ikuseiCount(t)} 目標${a.ikuseiTarget(t)}');
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
