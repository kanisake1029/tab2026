// 1シーズン通しての体力・怪我・調子の検証（AppState と同じ順で処理）
//  - チーム0 は先発4人ローテ、チーム1 は先発6人ローテにして、9月の先発の体力を比べる
// 実行: dart run tool/season_condition_test.dart
import 'dart:convert';
import 'package:npb_pennant_app/models/player.dart';
import 'package:npb_pennant_app/models/team.dart';
import 'package:npb_pennant_app/engine/match_simulator.dart';
import 'package:npb_pennant_app/engine/condition_engine.dart';
import 'package:npb_pennant_app/utils/initial_teams_data.dart';
import 'package:npb_pennant_app/utils/schedule_generator.dart';

void main() {
  final teams = (jsonDecode(InitialTeamsData.jsonString) as List).map<Team>((t) => Team.fromJson(t, Player.fromJson)).toList();
  teams[0].setRotationCount(4);
  teams[1].setRotationCount(6);
  final matches = ScheduleGenerator.generateSeasonSchedule(2026, teams).where((m) => m.matchType != 'OPEN' && teams.any((t) => t.id == m.homeTeamId) && teams.any((t) => t.id == m.awayTeamId)).toList()
    ..sort((a, b) => a.date.compareTo(b.date));
  final sim = MatchSimulator();
  final byId = {for (final t in teams) t.id: t};
  DateTime? cur;
  int games = 0, runs = 0, injuries = 0, demotions = 0;
  final monthRuns = <int, List<int>>{};
  String month(DateTime d) => '${d.month}月';
  String lastReport = '';

  void report(DateTime d) {
    double avg(Iterable<double> xs) => xs.isEmpty ? 0 : xs.reduce((a, b) => a + b) / xs.length;
    String starters(Team t) => avg(t.activeRotation.where((e) => e.isNotEmpty).map((id) => t.players.firstWhere((p) => p.id == id).energyRatio)).toStringAsFixed(2);
    final regulars = teams.expand((t) => t.lineup.map((l) => t.players.firstWhere((p) => p.id == l.playerId)));
    final relievers = teams.expand((t) => t.players.where((p) => p.isPitcher && t.active26.contains(p.id) && !t.activeRotation.contains(p.id)));
    final out = teams.fold<int>(0, (s, t) => s + t.players.where((p) => p.isInjuredOut).length);
    final mild = teams.fold<int>(0, (s, t) => s + t.players.where((p) => p.injuryDays > 0 && p.injurySeverity == 1).length);
    final cond = <int, int>{};
    for (final p in regulars) { final c = p.conditionAt(d); cond[c] = (cond[c] ?? 0) + 1; }
    print('${month(d).padLeft(3)} 体力: 4人ローテ先発 ${starters(teams[0])} / 6人ローテ先発 ${starters(teams[1])} / 中継ぎ平均 ${avg(relievers.map((p) => p.energyRatio)).toStringAsFixed(2)} / スタメン平均 ${avg(regulars.map((p) => p.energyRatio)).toStringAsFixed(2)}'
        '  離脱中$out人 軽傷$mild人  調子分布(スタメン) ${[-2, -1, 0, 1, 2].map((c) => '${Player.conditionLabels[c]}${cond[c] ?? 0}').join(' ')}');
  }

  for (final m in matches) {
    if (cur == null || m.date != cur) {
      if (cur != null) {
        ConditionEngine.advanceDays(teams, m.date.difference(cur).inDays);
        if (month(m.date) != lastReport) { report(cur); lastReport = month(m.date); }
      }
      cur = m.date;
      for (final t in teams) { t.refreshActive26(); }
    }
    final h = byId[m.homeTeamId]!, a = byId[m.awayTeamId]!;
    final r = sim.simulateMatch(m, h, a);
    h.advanceRotation(); a.advanceRotation();
    h.refreshActive26(); a.refreshActive26();
    final news = ConditionEngine.applyPostGame(r.session!);
    injuries += news.where((e) => e.contains('負傷') || e.contains('悪化')).length;
    demotions += news.where((e) => e.contains('登録抹消')).length;
    games++;
    runs += r.homeScore + r.awayScore;
    monthRuns.putIfAbsent(m.date.month, () => [0, 0]);
    monthRuns[m.date.month]![0] += r.homeScore + r.awayScore;
    monthRuns[m.date.month]![1] += 2;
  }
  report(cur!);
  print('試合$games 1チーム得点 ${(runs / games / 2).toStringAsFixed(2)}  負傷 $injuries件（1球団 ${(injuries / 12).toStringAsFixed(1)}件） 登録抹消 $demotions件');
  print('月別得点: ${monthRuns.entries.map((e) => '${e.key}月 ${(e.value[0] / e.value[1]).toStringAsFixed(2)}').join(' / ')}');
  for (final t in teams.take(2)) {
    final sp = t.players.where((p) => p.isPitcher && p.seasonStats.games > 0).toList()..sort((a, b) => b.seasonStats.inningsPitched.compareTo(a.seasonStats.inningsPitched));
    print('${t.name}（先発${t.rotationCount}人）: 投球回上位 ${sp.take(6).map((p) => '${p.registeredName} ${(p.seasonStats.inningsPitched / 3).toStringAsFixed(0)}回 防${p.seasonStats.era.toStringAsFixed(2)}').join(' / ')}  ${t.wins}勝${t.losses}敗');
  }
}
