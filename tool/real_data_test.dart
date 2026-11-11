// 初期データ（実チーム）で総当たりの試合を回し、リーグ全体の数値と異常を確認する
// 実行: dart run tool/real_data_test.dart [試合数]
import 'dart:convert';
import 'package:npb_pennant_app/models/player.dart';
import 'package:npb_pennant_app/models/team.dart';
import 'package:npb_pennant_app/engine/match_simulator.dart';
import 'package:npb_pennant_app/utils/initial_teams_data.dart';
import 'package:npb_pennant_app/utils/schedule_generator.dart';

void main(List<String> args) {
  final games = args.isNotEmpty && !args[0].startsWith('--') ? int.parse(args[0]) : 300;
  final teams = (jsonDecode(InitialTeamsData.jsonString.replaceAllMapped(RegExp(r',(\s*[\]}])'), (m) => m[1]!)) as List).map<Team>((t) => Team.fromJson(t, Player.fromJson)).toList();
  print('チーム数 ${teams.length}');
  // 初期データは担当位置の守備適性が1のため、検証用にスタメンの担当位置の守備を60に補正する（--fix 指定時）
  if (args.contains('--fix')) {
    for (final t in teams) {
      for (final l in t.lineup) {
        final p = t.players.firstWhere((p) => p.id == l.playerId);
        switch (l.position) { case '捕': p.fieldC = 60; break; case '一': p.field1B = 60; break; case '二': p.field2B = 60; break; case '三': p.field3B = 60; break; case '遊': p.fieldSS = 60; break; case '左': p.fieldLF = 60; break; case '中': p.fieldCF = 60; break; case '右': p.fieldRF = 60; break; }
      }
    }
  }
  if (args.contains('--traj2')) { for (final t in teams) { for (final p in t.players) { p.trajectory = 2; } } }
  for (final a in args) { if (a.startsWith('--vbat=')) MatchSimulator.batSpeedBase = double.parse(a.substring(7)); }
  final sim = MatchSimulator();
  int runs = 0, errors = 0, relievers = 0, n = 0;
  for (var g = 0; g < games; g++) {
    final h = teams[g % teams.length];
    final a = teams[(g * 7 + 3) % teams.length];
    if (h.id == a.id) continue;
    try {
      final r = sim.simulateMatch(Match(homeTeamId: h.id, awayTeamId: a.id, date: DateTime(2026, 4, 1), matchType: 'regular'), h, a);
      runs += r.homeScore + r.awayScore;
      if ((r.boxScore['homePitcher'] as Map).length > 1) relievers++;
      n++;
    } catch (e, st) {
      errors++;
      if (errors < 3) print('ERROR $e\n$st');
    }
  }
  int ab = 0, hits = 0, hr = 0, so = 0, bb = 0, er = 0, ip = 0;
  for (final t in teams) {
    for (final p in t.players) {
      final s = p.seasonStats;
      if (!p.isPitcher) { ab += s.atBats; hits += s.hits; hr += s.homeRuns; so += s.strikeouts; bb += s.walks; }
      if (p.isPitcher) { er += s.earnedRuns; ip += s.inningsPitched; }
    }
  }
  final t0 = teams.first;
  print('試合 $n  エラー $errors  1チーム得点 ${(runs / n / 2).toStringAsFixed(2)}  継投あり試合 $relievers');
  print('打率 ${(hits / ab).toStringAsFixed(3)}  HR/チーム/試合 ${(hr / n / 2).toStringAsFixed(2)}  三振 ${(so / n / 2).toStringAsFixed(2)}  四球 ${(bb / n / 2).toStringAsFixed(2)}  防御率 ${(er * 27 / ip).toStringAsFixed(2)}');
  print('例 ${t0.name}: lineup ${t0.lineup.length}人 rotation ${t0.rotation.length} active26 ${t0.active26.length} winningPattern ${t0.winningPattern}');
  double avg(Iterable<int> xs) => xs.isEmpty ? 0 : xs.reduce((a, b) => a + b) / xs.length;
  print('スタメン平均OVR ${avg(teams.expand((t) => t.lineup.map((l) => t.players.firstWhere((p) => p.id == l.playerId).ovr))).toStringAsFixed(1)}  支配下平均OVR ${avg(teams.expand((t) => t.players.map((p) => p.ovr))).toStringAsFixed(1)}');
}
