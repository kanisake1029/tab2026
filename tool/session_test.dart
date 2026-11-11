// セッションAPI（1打席ずつ・交代・継投）の動作検証
// 実行: dart run tool/session_test.dart [試合数]
import 'package:npb_pennant_app/models/player.dart';
import 'package:npb_pennant_app/models/team.dart';
import 'package:npb_pennant_app/engine/match_simulator.dart';
import 'package:npb_pennant_app/utils/schedule_generator.dart';

Player _b(String id, int lv) => Player(id: id, isPitcher: false, lastName: id, trajectory: 2, contactLeft: lv, contactRight: lv, power: lv, run: lv, arm: lv, throwAccuracy: lv, catchSkill: lv, eye: lv, clutch: lv, fieldP: lv, fieldC: lv, field1B: lv, field2B: lv, field3B: lv, fieldSS: lv, fieldLF: lv, fieldCF: lv, fieldRF: lv);
Player _p(String id, int lv, {int stamina = 65}) => Player(id: id, isPitcher: true, lastName: id, velocity: 120 + lv ~/ 2, pitchPower: lv, control: lv, stamina: stamina, clutchPitching: lv, spinAxis: 45, run: 60, arm: 60, throwAccuracy: 60, catchSkill: 60, fieldP: 60);

Team _team(String id) {
  const pos = ['中', '二', '遊', '一', '三', '左', '右', '捕', 'DH'];
  final players = <Player>[];
  final lineup = <LineupEntry>[];
  for (var i = 0; i < 9; i++) {
    final p = _b('$id-B$i', 65);
    players.add(p);
    lineup.add(LineupEntry(playerId: p.id, position: pos[i]));
  }
  for (var i = 0; i < 4; i++) { players.add(_b('$id-S$i', 55)); }
  final sp = _p('$id-SP', 65);
  players.add(sp);
  final rel = [for (var i = 0; i < 4; i++) _p('$id-R$i', 62, stamina: 40)];
  final setup = _p('$id-SET', 66, stamina: 40);
  final closer = _p('$id-CL', 70, stamina: 40);
  players.addAll([...rel, setup, closer]);
  return Team(
    id: id, name: id, league: 'CL', players: players, lineup: lineup, rotation: [sp.id],
    winningPattern: [rel[0].id, setup.id, closer.id],
    active26: players.map((p) => p.id).toList(),
  );
}

void main(List<String> args) {
  final games = args.isNotEmpty ? int.parse(args[0]) : 200;
  final sim = MatchSimulator(applyForm: false);
  int runs = 0, relieverGames = 0, closerGames = 0, bad = 0, pitchersTotal = 0;
  double outsDiff = 0;
  for (var g = 0; g < games; g++) {
    final h = _team('H'), a = _team('A');
    final m = Match(homeTeamId: 'H', awayTeamId: 'A', date: DateTime(2026, 4, 1), matchType: 'regular');
    final r = sim.simulateMatch(m, h, a);
    runs += r.homeScore + r.awayScore;
    final hp = r.boxScore['homePitcher'] as Map<String, dynamic>;
    final ap = r.boxScore['awayPitcher'] as Map<String, dynamic>;
    pitchersTotal += hp.length + ap.length;
    if (hp.length > 1) relieverGames++;
    if (hp.keys.any((k) => k.contains('CL')) || ap.keys.any((k) => k.contains('CL'))) closerGames++;
    // 投球回の合計が、実際に守備側が取ったアウト数（27前後）と整合するか
    double ipSum(Map<String, dynamic> m) => m.values.fold(0.0, (s, v) {
          final parts = '${v['ip']}'.split('.');
          return s + int.parse(parts[0]) * 3 + (parts.length > 1 ? int.parse(parts[1]) : 0);
        });
    final totalOuts = ipSum(hp) + ipSum(ap);
    final expected = (r.homeInningScores.length * 2 * 3).toDouble();
    outsDiff += (totalOuts - expected).abs();
    if (hp.isEmpty || ap.isEmpty) bad++;
  }
  print('試合数 $games  1チーム得点 ${(runs / games / 2).toStringAsFixed(2)}');
  print('ホームで継投があった試合 $relieverGames  抑え登板のあった試合 $closerGames  平均登板投手数/試合 ${(pitchersTotal / games).toStringAsFixed(1)}');
  print('アウト数の整合ずれ(平均) ${(outsDiff / games).toStringAsFixed(2)}  異常 $bad');

  // 手動の交代API
  final h = _team('H'), a = _team('A');
  final s = sim.startGame(Match(homeTeamId: 'H', awayTeamId: 'A', date: DateTime(2026, 4, 1), matchType: 'regular'), h, a);
  int steps = 0;
  while (steps < 14 && !sim.isFinished(s)) { sim.stepPlateAppearance(s); steps++; }
  final bench = sim.availableBatters(s, false);
  sim.pinchHit(s, false, bench.first);
  sim.defensiveSwap(s, false, 3, bench[1], '一');
  sim.changePitcher(s, true, sim.availablePitchers(s, true).first);
  print('手動交代後 打順: ${s.awayOrder.map((p) => p.id).join(',')}');
  print('守備位置(アウェイ): ${s.awayLineup.map((l) => '${l.playerId}:${l.position}').join(' ')}');
  while (!sim.isFinished(s)) { sim.stepPlateAppearance(s); }
  final res = sim.finishGame(s);
  print('最終 ${res.awayScore}-${res.homeScore}  ホーム投手: ${(res.boxScore['homePitcher'] as Map).keys.toList()}');
  print('アウェイ打者行: ${(res.boxScore['awayBatters'] as Map).keys.toList()}');
  print(res.playByPlay.where((l) => l.startsWith('【代') || l.startsWith('【守備') || l.startsWith('【投手')).join('\n'));
  print('チームのlineupが変更されていない: ${a.lineup.map((l) => l.playerId).join(',')}');
}
