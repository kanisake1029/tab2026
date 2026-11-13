import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../engine/match_simulator.dart';
import '../engine/balance_report.dart';
import '../engine/play_resolver.dart';
import '../models/player.dart';
import '../models/team.dart';
import '../providers/app_state.dart';
import '../utils/schedule_generator.dart';

/// バランス検証：2球団の「写し」で試合をして（セーブは変わらない）、投球・打球・守備・走塁・環境の5つの数字を見る。
///  打球は 3D で1つずつ確かめられる
class BalanceLabPanel extends StatefulWidget {
  final AppState app;
  const BalanceLabPanel({super.key, required this.app});
  @override
  State<BalanceLabPanel> createState() => _BalanceLabPanelState();
}

class _BalanceLabPanelState extends State<BalanceLabPanel> {
  late String homeId = widget.app.teams.first.id;
  late String awayId = widget.app.teams.length > 1 ? widget.app.teams[1].id : widget.app.teams.first.id;
  int games = 10;
  bool running = false;
  int done = 0;
  final List<PitchEvent> events = [];
  final Map<PitchEvent, int> gameOf = Map.identity(); // 何試合目か（打席を試合ごとに数える）
  final List<PitchEvent> lastPlays = []; // 3D で見る打球（最後の数試合）
  int runs = 0, played = 0;
  Map<String, int> dbg = {}, pr = {};
  List<String> envs = [];

  Team _copy(Team t) => Team.fromJson(jsonDecode(jsonEncode(t.toJson())) as Map<String, dynamic>, Player.fromJson);

  Future<void> _run() async {
    setState(() {
      running = true;
      done = 0;
      events.clear();
      gameOf.clear();
      lastPlays.clear();
      runs = 0;
      played = 0;
      envs = [];
    });
    MatchSimulator.startStats();
    PlayResolver.stats.clear();
    final teams = widget.app.teams;
    final h0 = teams.firstWhere((t) => t.id == homeId), a0 = teams.firstWhere((t) => t.id == awayId);
    final sim = MatchSimulator();
    final rnd = math.Random();
    for (var g = 0; g < games; g++) {
      final home = _copy(h0), away = _copy(a0);
      // 季節（気温・風）を散らす：4〜10月のどこか
      final date = DateTime(2026, 4 + rnd.nextInt(7), 1 + rnd.nextInt(28));
      final m = Match(homeTeamId: home.id, awayTeamId: away.id, date: date, matchType: 'オープン戦');
      final s = sim.startGame(m, home, away);
      while (!sim.isFinished(s)) {
        sim.autoManage(s);
        sim.stepPlateAppearance(s);
      }
      sim.finishGame(s);
      runs += s.state.homeScore + s.state.awayScore;
      played++;
      events.addAll(s.pitchEvents);
      for (final e in s.pitchEvents) {
        gameOf[e] = g;
      }
      envs.add('${date.month}/${date.day} ${s.env.tempC.round()}℃ ${s.env.windText}');
      if (g >= games - 1) lastPlays.addAll(s.pitchEvents.where((e) => e.phys != null || e.result == 'インプレー')); // 3D：全球（最後の1試合）
      done = g + 1;
      if (mounted) setState(() {});
      await Future<void>.delayed(Duration.zero);
    }
    // 道中の打球の軌跡を持ちすぎない（3D で見る分だけ残す）
    for (final e in events) {
      if (!lastPlays.contains(e)) e.path = const [];
    }
    dbg = Map.of(MatchSimulator.debugStats);
    MatchSimulator.collectStats = false; // 検証が終わったら、普段の試合では集計しない
    pr = Map.of(PlayResolver.stats);
    if (mounted) setState(() => running = false);
  }


  Widget _sec(String title, String target, List<(String, String, String)> rows) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
          if (target.isNotEmpty) Text(target, style: const TextStyle(fontSize: 11, color: Colors.black54)),
          const SizedBox(height: 6),
          Table(columnWidths: const {0: FlexColumnWidth(1.6), 1: FlexColumnWidth(1), 2: FlexColumnWidth(1)}, children: [
            const TableRow(children: [Text('項目', style: TextStyle(fontSize: 11, color: Colors.black54)), Text('結果', style: TextStyle(fontSize: 11, color: Colors.black54)), Text('NPB の目安', style: TextStyle(fontSize: 11, color: Colors.black54))]),
            for (final r in rows)
              TableRow(children: [
                Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Text(r.$1, style: const TextStyle(fontSize: 13))),
                Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Text(r.$2, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
                Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Text(r.$3, style: const TextStyle(fontSize: 12, color: Colors.black54))),
              ]),
          ]),
        ]),
      ),
    );
  }

  List<Widget> _results() => [
        for (final s in BalanceReport(events: events, gameOf: gameOf, dbg: dbg, pr: pr, runs: runs, played: played, envs: envs).sections()) _sec(s.title, s.note, s.rows),
      ];

  @override
  Widget build(BuildContext context) {
    final teams = widget.app.teams;
    return ListView(padding: const EdgeInsets.all(14), children: [
      const Text('バランス検証', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
      const Text('2球団の写しで試合をします（セーブデータや成績は変わりません）。打球は 3D で1つずつ見られます。', style: TextStyle(fontSize: 12, color: Colors.black54)),
      const SizedBox(height: 10),
      Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        DropdownButton<String>(value: homeId, items: [for (final t in teams) DropdownMenuItem(value: t.id, child: Text('ホーム ${t.name}', overflow: TextOverflow.ellipsis))], onChanged: running ? null : (v) => setState(() => homeId = v!)),
        DropdownButton<String>(value: awayId, items: [for (final t in teams) DropdownMenuItem(value: t.id, child: Text('ビジター ${t.name}', overflow: TextOverflow.ellipsis))], onChanged: running ? null : (v) => setState(() => awayId = v!)),
        DropdownButton<int>(value: games, items: [for (final n in const [1, 5, 10, 30, 100]) DropdownMenuItem(value: n, child: Text('$n 試合'))], onChanged: running ? null : (v) => setState(() => games = v!)),
        FilledButton(onPressed: running ? null : _run, child: Text(running ? '試合中… $done/$games' : '試合をする')),
      ]),
      const SizedBox(height: 10),
      if (played > 0 && !running) ..._results(),
    ]);
  }
}
