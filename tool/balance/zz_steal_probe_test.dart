// ignore_for_file: avoid_print
// 盗塁の確かめ：自動で何日か進め、企図・成功率・走力ごとの盗塁数（143試合に直した数）を見る
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/db/app_database.dart';
import 'package:npb_pennant_app/engine/match_simulator.dart';
import 'package:npb_pennant_app/engine/tactics.dart';
import 'package:npb_pennant_app/engine/spec_constants.dart';
import 'package:npb_pennant_app/models/player.dart';
import 'package:npb_pennant_app/providers/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('steal probe', () async {
    final env = Platform.environment;
    if (env["EXP"] != null) MatchSimulator.cpuStealExp = double.parse(env["EXP"]!);
    if (env["SEL0"] != null) MatchSimulator.cpuStealSel0 = double.parse(env["SEL0"]!);
    if (env["SELW"] != null) MatchSimulator.cpuStealSelW = double.parse(env["SELW"]!);
    if (env["PP"] != null) MatchSimulator.cpuStealPerPitch = double.parse(env["PP"]!);
    if (env["CURVE"] != null) MatchSimulator.cpuStealCurve = double.parse(env['CURVE']!);
    if (env['BIAS'] != null) Spec.stealBias = double.parse(env['BIAS']!);
    print('curve ${MatchSimulator.cpuStealCurve} bias ${Spec.stealBias} ${StealRace.bias}');
    SharedPreferences.setMockInitialValues({});
    final tmp = File('${Directory.systemTemp.path}/s25_steal.sqlite');
    await File('backup/s25_20261109.sqlite').copy(tmp.path);
    final a = AppState(AppDatabase(NativeDatabase(tmp)));
    while (!a.loaded) { await Future.delayed(const Duration(milliseconds: 20)); }
    for (final t in a.teams) { t.wins = 0; t.losses = 0; t.draws = 0; }
    // 走力をそろえる試し：RUNS=70,75,80,90 なら、各球団で打数の多い野手4人にその走力を割り当てる（統計はそのあと消す）
    final forced = <String, int>{};
    final runsList = (env['RUNS'] ?? '').split(',').where((x) => x.isNotEmpty).map(int.parse).toList();
    if (runsList.isNotEmpty) {
      for (final t in a.teams.where((t) => t.league == 'CL' || t.league == 'PL')) {
        final l = t.players.where((p) => !p.isPitcher).toList()..sort((x, y) => y.seasonStats.atBats.compareTo(x.seasonStats.atBats));
        for (var i = 0; i < runsList.length && i < l.length; i++) { l[i].run = runsList[i]; forced[l[i].id] = runsList[i]; }
      }
    }
    for (final t in a.teams) { for (final p in t.players) { p.seasonStats = PlayerStats(); } }
    MatchSimulator.debugStats.clear();
    final days = int.parse(env['DAYS'] ?? '70');
    for (var i = 0; i < days; i++) { a.playNextDay(); }
    final npb = a.teams.where((t) => t.league == 'CL' || t.league == 'PL').toList();
    final d = MatchSimulator.debugStats;
    print('日付 ${a.currentDate}  企図(2軍込) ${d['steals']} 成功 ${d['stealSuccess']} 悪送球 ${d['stealThrowError']}');
    var tsb = 0, tcs = 0, tg = 0;
    final rows = <(int, double, int, int)>[];
    for (final t in npb) {
      final g = t.wins + t.losses + t.draws;
      tg += g;
      for (final p in t.players.where((p) => !p.isPitcher)) {
        tsb += p.seasonStats.stolenBases; tcs += p.seasonStats.caughtStealing;
        if (p.seasonStats.atBats >= g * 2.5) rows.add((p.run, p.seasonStats.stolenBases * 143 / g, p.seasonStats.stolenBases, p.seasonStats.caughtStealing));
      }
    }
    print('1軍 盗塁$tsb 死$tcs 成功率${(tsb / (tsb + tcs) * 100).toStringAsFixed(0)}%  1球団143試合あたり ${(tsb * 143 / tg).toStringAsFixed(0)}  企図/試合(両軍) ${((tsb + tcs) * 2 / tg).toStringAsFixed(2)}');
    for (final lo in [60, 70, 80, 85, 90, 95]) {
      final hi = lo == 60 ? 70 : (lo == 70 ? 80 : (lo == 80 ? 85 : (lo == 85 ? 90 : (lo == 90 ? 95 : 101))));
      final l = rows.where((r) => r.$1 >= lo && r.$1 < hi).toList()..sort((x, y) => y.$2.compareTo(x.$2));
      if (l.isEmpty) continue;
      final avg = l.map((r) => r.$2).reduce((x, y) => x + y) / l.length;
      final sb = l.fold<int>(0, (s, r) => s + r.$3), cs = l.fold<int>(0, (s, r) => s + r.$4);
      print('走力$lo〜${hi - 1} レギュラー${l.length}人 平均${avg.toStringAsFixed(0)}盗塁/143試合 成功率${sb + cs == 0 ? '-' : (sb / (sb + cs) * 100).toStringAsFixed(0)}%  最多${l.first.$2.toStringAsFixed(0)}');
    }
    for (final rv in runsList) {
      final l = [for (final t in a.teams) for (final p in t.players) if (forced[p.id] == rv) (p, t.wins + t.losses + t.draws)];
      final per = [for (final (p, g) in l) if (g > 0) p.seasonStats.stolenBases * 143 / g];
      final sb = l.fold<int>(0, (x, e) => x + e.$1.seasonStats.stolenBases), cs = l.fold<int>(0, (x, e) => x + e.$1.seasonStats.caughtStealing);
      per.sort();
      print('走力${rv}にした${l.length}人 平均${(per.reduce((x, y) => x + y) / per.length).toStringAsFixed(1)}盗塁/143試合 成功率${sb + cs == 0 ? '-' : (sb / (sb + cs) * 100).toStringAsFixed(0)}%  ${per.map((x) => x.round()).toList()}');
    }
  });
}
