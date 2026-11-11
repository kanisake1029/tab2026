// 1球ずつ進める API（stepPitch）の検証: 待て・外せ・スリーバント判断・打席中の采配差し替えを
// ランダムに使っても試合が最後まで進み、例外が出ないこと
// 実行: dart run tool/pitch_step_test.dart [試合数]
import 'dart:convert';
import 'dart:math';
import 'package:npb_pennant_app/models/player.dart';
import 'package:npb_pennant_app/models/team.dart';
import 'package:npb_pennant_app/engine/match_simulator.dart';
import 'package:npb_pennant_app/utils/initial_teams_data.dart';
import 'package:npb_pennant_app/utils/schedule_generator.dart';

void main(List<String> args) {
  final n = args.isNotEmpty ? int.parse(args[0]) : 50;
  final r = Random(1);
  final teams = (jsonDecode(InitialTeamsData.jsonString) as List).map<Team>((t) => Team.fromJson(t, Player.fromJson)).toList();
  final sim = MatchSimulator();
  int pitches = 0, pauses3 = 0, games = 0, runs = 0, pas = 0;
  for (var g = 0; g < n; g++) {
    final h = teams[g % 12], a = teams[(g + 1) % 12];
    final s = sim.startGame(Match(homeTeamId: h.id, awayTeamId: a.id, date: DateTime(2026, 5, 1 + g % 28), matchType: 'regular'), h, a);
    while (!sim.isFinished(s) || s.inPlateAppearance) {
      if (!s.inPlateAppearance) sim.autoManage(s);
      final plans = [
        const AtBatPlan(),
        const AtBatPlan(bat: BatTactic.bunt),
        const AtBatPlan(run: RunTactic.hitAndRun),
        const AtBatPlan(run: RunTactic.steal),
        const AtBatPlan(bat: BatTactic.squeeze),
      ];
      AtBatPlan? plan = s.inPlateAppearance ? (r.nextDouble() < 0.1 ? plans[r.nextInt(plans.length)] : null) : plans[r.nextInt(plans.length)];
      final x = r.nextDouble();
      if (s.inPlateAppearance) s.pitchCommand = x < 0.1 ? PitchCommand.take : (x < 0.15 ? PitchCommand.pitchOut : PitchCommand.none);
      final wasIn = s.inPlateAppearance;
      final p = sim.stepPitch(s, plan: plan);
      if (!wasIn) pas++;
      if (p != null && p.kind == PaPauseKind.threeBunt) { pauses3++; s.threeBunt = r.nextBool(); }
      if (p != null && p.kind == PaPauseKind.afterPitch) pitches++;
      if (pitches > 1000000) throw '無限ループ';
    }
    final res = sim.finishGame(s);
    runs += res.homeScore + res.awayScore;
    games++;
  }
  print('試合$games 打席$pas 打席途中の停止$pitches スリーバント判断$pauses3 1試合得点${(runs / games / 2).toStringAsFixed(2)}  OK');
}
