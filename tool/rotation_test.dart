// 先発ローテ（4〜7人を順番に登板）・ベンチ入り26人の自動決定・旧セーブからの移行の検証
// 実行: dart run tool/rotation_test.dart
import 'dart:convert';
import 'package:npb_pennant_app/models/player.dart';
import 'package:npb_pennant_app/models/team.dart';
import 'package:npb_pennant_app/engine/match_simulator.dart';
import 'package:npb_pennant_app/utils/initial_teams_data.dart';
import 'package:npb_pennant_app/utils/schedule_generator.dart';

List<Team> _load() => (jsonDecode(InitialTeamsData.jsonString) as List).map<Team>((t) => Team.fromJson(t, Player.fromJson)).toList();

void main() {
  final sim = MatchSimulator(applyForm: false);
  var allOk = true;
  void ng(String m) { allOk = false; print('NG: $m'); }

  for (var n = Team.minRotation; n <= Team.maxRotation; n++) {
    final teams = _load();
    for (final t in teams) { t.setRotationCount(n); }
    final seqs = {for (final t in teams) t.id: <String>[]};
    final expected = {for (final t in teams) t.id: [for (var g = 0; g < 30; g++) t.rotation[g % n]]};
    for (var day = 0; day < 30; day++) {
      for (final t in teams) { t.refreshActive26(); }
      for (final t in teams) {
        final today = t.todaysStarterId!;
        final act = t.active26.toSet();
        if (act.length != Team.benchSize) ng('n=$n ${t.id} day$day ベンチ入り${act.length}人');
        if (!act.contains(today)) ng('n=$n ${t.id} 今日の先発がベンチ外');
        final restingIn = t.restingStarters.where(act.contains).length;
        final expectIn = (n - 1 - t.benchOutNeeded).clamp(0, 9);
        // 1軍の外国人が5人いると、外国人枠(4)のために日本人の先発が1人ベンチへ戻ることがある
        final foreign1G = t.players.where((p) => t.roster1G.contains(p.id) && p.nationality == '海外').length;
        if (restingIn != expectIn && !(foreign1G > 4 && restingIn == expectIn + 1)) ng('n=$n ${t.id} ベンチに残った先発 $restingIn人（期待$expectIn人）');
        for (final l in t.lineup) { if (!act.contains(l.playerId)) ng('n=$n ${t.id} スタメンがベンチ外'); }
        for (final w in t.winningPattern) { if (w.isNotEmpty && !act.contains(w)) ng('n=$n ${t.id} 方程式がベンチ外'); }
      }
      for (var i = 0; i < teams.length; i += 2) {
        final h = teams[i], a = teams[i + 1];
        final m = Match(homeTeamId: h.id, awayTeamId: a.id, date: DateTime(2026, 4, 1 + day), matchType: 'regular');
        final s = sim.startGame(m, h, a);
        seqs[h.id]!.add(s.homePitcher.id);
        seqs[a.id]!.add(s.awayPitcher.id);
        final again = sim.startGame(m, h, a);
        if (again.homePitcher.id != s.homePitcher.id) ng('startGame で先発が進んでいる');
        sim.simulateMatch(m, h, a);
        // 試合確定（AppState._applyResult と同じ順）
        h.advanceRotation(); a.advanceRotation();
        h.refreshActive26(); a.refreshActive26();
      }
    }
    final rotOk = teams.every((t) => seqs[t.id]!.join(',') == expected[t.id]!.join(','));
    if (!rotOk) ng('n=$n ローテ順が崩れている');
    final t0 = teams[0];
    final act = t0.players.where((p) => t0.active26.contains(p.id));
    print('先発$n人: ローテ${rotOk ? 'OK' : 'NG'}  例 ${t0.name}: 1軍${t0.roster1G.length} ベンチ入り${t0.active26.length}(投${act.where((p) => p.isPitcher).length}/野${act.where((p) => !p.isPitcher).length}) '
        '自動ベンチ外(先発)${t0.autoBenchOutRotation.length} 自動補充${t0.autoBenchOutFill.length}');
  }

  // 手動ベンチ外: 4人ローテで2人を手動指定 → 自動補充が0になる
  {
    final t = _load().firstWhere((t) => t.players.where((p) => t.roster1G.contains(p.id) && p.nationality == '海外').length <= 4);
    t.setRotationCount(4);
    final cands = t.active26.where((id) => !t.lineup.any((l) => l.playerId == id) && !t.winningPattern.contains(id) && id != t.todaysStarterId).take(2).toList();
    t.manualBenchOut.addAll(cands);
    t.refreshActive26();
    final ok = t.active26.length == 26 && t.autoBenchOutFill.isEmpty && cands.every((id) => !t.active26.contains(id));
    if (!ok) ng('手動ベンチ外が反映されない: 指定$cands 手動${t.manualBenchOut} 自動補充${t.autoBenchOutFill} 先発外${t.autoBenchOutRotation} ベンチ入り${t.active26.length}');
    print('手動ベンチ外(4人ローテ・2人指定): ${ok ? 'OK' : 'NG'}');
  }

  // 旧セーブからの移行（rotationCount / manualBenchOut / winningPattern なし）
  {
    final h = _load()[0];
    final old = jsonDecode(jsonEncode(h.toJson())) as Map<String, dynamic>;
    old.remove('winningPattern');
    old.remove('rotationIndex');
    old.remove('rotationCount');
    old.remove('manualBenchOut');
    old['setup'] = h.winningPattern[1];
    old['closer'] = h.winningPattern[2];
    old['closer2'] = null;
    old['rotation'] = h.rotation.sublist(0, 5);
    final t = Team.fromJson(old, Player.fromJson);
    final ok = t.rotationCount == 6 && t.activeRotation.every((e) => e.isNotEmpty) && t.active26.length == 26 && t.winningPattern[1] == h.winningPattern[1];
    if (!ok) ng('旧セーブの移行');
    print('旧セーブ移行: ${ok ? 'OK' : 'NG'} 先発${t.rotationCount}人 ベンチ入り${t.active26.length}');
  }
  print(allOk ? '=== すべてOK ===' : '=== NGあり ===');
}
