import 'package:npb_pennant_app/models/stadium.dart';
import 'dart:convert';
import 'dart:math' as math;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/db/app_database.dart';
import 'package:npb_pennant_app/engine/balance_report.dart';
import 'package:npb_pennant_app/engine/base_path.dart';
import 'package:npb_pennant_app/engine/match_simulator.dart';
import 'package:npb_pennant_app/engine/play_resolver.dart';
import 'package:npb_pennant_app/engine/physics_engine.dart';
import 'package:npb_pennant_app/engine/bat_physics.dart';
import 'package:npb_pennant_app/engine/field_time.dart';
import 'package:npb_pennant_app/engine/fielder_ai.dart';
import 'package:npb_pennant_app/engine/swing_model.dart';
import 'package:npb_pennant_app/engine/spec_constants.dart';
import 'package:npb_pennant_app/models/player.dart';
import 'package:npb_pennant_app/models/team.dart';
import 'package:npb_pennant_app/providers/app_state.dart';
import 'package:npb_pennant_app/utils/schedule_generator.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// バランス検証（画面と同じ計算）を、12球団の写しの総当たりで多めに回す
///  flutter test test/balance_lab_test.dart --dart-define=GAMES=240
void main() {
  test('バランス検証（5分野）', () async {
    SharedPreferences.setMockInitialValues({});
    final a = AppState(AppDatabase(NativeDatabase.memory()));
    while (!a.loaded) {
      await Future.delayed(const Duration(milliseconds: 10));
    }
    const n = int.fromEnvironment('GAMES', defaultValue: 132);
    double? d(String k) { final v = const {
        'ZA': String.fromEnvironment('ZA'), 'ZS': String.fromEnvironment('ZS'), 'CH': String.fromEnvironment('CH'), 'MSC': String.fromEnvironment('MSC'),
        'VBS': String.fromEnvironment('VBS'), 'NSC': String.fromEnvironment('NSC'), 'TE': String.fromEnvironment('TE'), 'TS': String.fromEnvironment('TS'), 'CO': String.fromEnvironment('CO'), 'AIM': String.fromEnvironment('AIM'), 'CS': String.fromEnvironment('CS')}[k]!; return v.isEmpty ? null : double.parse(v); }
    MatchSimulator.zoneAim = d('ZA') ?? MatchSimulator.zoneAim;
    MatchSimulator.zoneSwingBase = d('ZS') ?? MatchSimulator.zoneSwingBase;
    MatchSimulator.chaseBase = d('CH') ?? MatchSimulator.chaseBase;
    MatchSimulator.throwErrorBase = d('TE') ?? MatchSimulator.throwErrorBase;
    MatchSimulator.cpuStealRate = d('CS') ?? MatchSimulator.cpuStealRate;
    SwingModel.timingScale = d('TS') ?? SwingModel.timingScale;
    SwingModel.contactScale = d('CO') ?? SwingModel.contactScale;
    SwingModel.aimBase = d('AIM') ?? SwingModel.aimBase;
    SwingModel.misScale = d('MSC') ?? SwingModel.misScale;
    if (const String.fromEnvironment('STAD').isNotEmpty) Stadium.forceId = const String.fromEnvironment('STAD');
    if (const String.fromEnvironment('SPEC') == '0') Spec.on = false;
    double? sd(String v) => v.isEmpty ? null : double.parse(v);
    Spec.batA = sd(const String.fromEnvironment('BATA')) ?? Spec.batA;
    Spec.attK = sd(const String.fromEnvironment('ATTK')) ?? Spec.attK;
    Spec.sigEyBase = sd(const String.fromEnvironment('SEY')) ?? Spec.sigEyBase;
    Spec.ctrlBase = sd(const String.fromEnvironment('CTRL')) ?? Spec.ctrlBase;
    Spec.thrBase = sd(const String.fromEnvironment('THR')) ?? Spec.thrBase;
    Spec.ofDepth = sd(const String.fromEnvironment('OFD')) ?? Spec.ofDepth;
    if (const String.fromEnvironment('FBP') == '0') MatchSimulator.foulByPath = false;
    if (const String.fromEnvironment('BPATH') == '0') BasePath.curves = false;
    MatchSimulator.hitStartMode = int.tryParse(const String.fromEnvironment('HSM')) ?? MatchSimulator.hitStartMode;
    FielderAI.chaseWindow = sd(const String.fromEnvironment('CHW')) ?? FielderAI.chaseWindow;
    FielderAI.linerJudge = sd(const String.fromEnvironment('LJ')) ?? FielderAI.linerJudge;
    ThrowStyle.drag = sd(const String.fromEnvironment('DRAG')) ?? ThrowStyle.drag;
    PlayResolver.tagTime = sd(const String.fromEnvironment('TAG')) ?? PlayResolver.tagTime;
    BatPhysics.axialSpin = sd(const String.fromEnvironment('AXS')) ?? BatPhysics.axialSpin;
    PhysicsEngine.hardBounceLoss = sd(const String.fromEnvironment('HBL')) ?? PhysicsEngine.hardBounceLoss;
    PhysicsEngine.battedDrag = sd(const String.fromEnvironment('BDRAG')) ?? PhysicsEngine.battedDrag;
    PhysicsEngine.ofRollMul = sd(const String.fromEnvironment('OFROLL')) ?? PhysicsEngine.ofRollMul;
    FielderAI.ofReachBonus = sd(const String.fromEnvironment('OFREACH')) ?? FielderAI.ofReachBonus;
    Spec.umpEdge = sd(const String.fromEnvironment('UMP')) ?? Spec.umpEdge;
    Spec.stealBias = sd(const String.fromEnvironment('STB')) ?? Spec.stealBias;
    const only = String.fromEnvironment('SPECONLY'); // 例：bat,pit（この分野だけ仕様書の数値）
    if (only.isNotEmpty) {
      final o = only.split(',');
      Spec.batting = o.contains('bat');
      Spec.pitching = o.contains('pit');
      Spec.zone = o.contains('zon');
      Spec.fielding = o.contains('fld');
      Spec.throwing = o.contains('thr');
      Spec.running = o.contains('run');
      Spec.field = o.contains('fie');
    }
    SwingModel.vBatScale = d('VBS') ?? SwingModel.vBatScale;
    SwingModel.noiseScale = d('NSC') ?? SwingModel.noiseScale;
    MatchSimulator.startStats();
    PlayResolver.stats.clear();
    final sim = MatchSimulator();
    final rnd = math.Random(7);
    final events = <PitchEvent>[];
    final gameOf = Map<PitchEvent, int>.identity();
    final envs = <String>[];
    var runs = 0;
    Team copy(Team t) => Team.fromJson(jsonDecode(jsonEncode(t.toJson())) as Map<String, dynamic>, Player.fromJson);
    final teams = a.teams;
    for (var g = 0; g < n; g++) {
      final h = copy(teams[g % teams.length]), w = copy(teams[(g * 5 + 1 + g ~/ teams.length) % teams.length]);
      if (h.id == w.id) continue;
      final date = DateTime(2026, 4 + rnd.nextInt(7), 1 + rnd.nextInt(28));
      final s = sim.startGame(Match(homeTeamId: h.id, awayTeamId: w.id, date: date, matchType: 'オープン戦'), h, w);
      while (!sim.isFinished(s)) {
        sim.autoManage(s);
        sim.stepPlateAppearance(s);
      }
      sim.finishGame(s);
      runs += s.state.homeScore + s.state.awayScore;
      for (final e in s.pitchEvents) {
        e.path = const [];
        gameOf[e] = g;
      }
      events.addAll(s.pitchEvents);
      envs.add('${date.month}/${date.day} ${s.env.tempC.round()}℃ ${s.env.windText}');
    }
    final played = gameOf.values.toSet().length;
    final rep = BalanceReport(events: events, gameOf: gameOf, dbg: MatchSimulator.debugStats, pr: PlayResolver.stats, runs: runs, played: played, envs: envs.take(4).toList());
    // ignore: avoid_print
    print('$played 試合\n$rep');
    // ignore: avoid_print
    // 打球の種類 × 結果、ゴロの二塁打の方向・速さ・処理した野手（調整の手がかり）
    final oc = <String, int>{};
    final gd = <String, int>{};
    for (final e in events.where((e) => e.result == 'インプレー')) {
      oc['${e.contact}:${e.outcome}'] = (oc['${e.contact}:${e.outcome}'] ?? 0) + 1;
      if (e.contact == 'ライナー' && e.outcome == '二塁打' && e.landX != null) {
        final d = math.sqrt(e.landX! * e.landX! + e.landY! * e.landY!);
        final k = 'L ${(d / 10).floor() * 10}m ${e.flightTime.toStringAsFixed(0)}s ${e.fielder}';
        gd[k] = (gd[k] ?? 0) + 1;
      }
      if (e.contact == 'ゴロ' && e.outcome == '二塁打') {
        final k = '${(e.spray.abs() / 10).floor() * 10}° ${(e.exitSpeed * 3.6 / 20).floor() * 20}km ${e.fielder}';
        gd[k] = (gd[k] ?? 0) + 1;
      }
    }
    // ignore: avoid_print
    print('結果 $oc');
    // ignore: avoid_print
    print('通り道で決まった ${MatchSimulator.debugStats.entries.where((e) => e.key.contains('ByPath') || e.key.startsWith('drift_') || e.key.startsWith('side_')).toList()} インプレー ${MatchSimulator.debugStats['inplay']}');
    // ignore: avoid_print
    print('ゴロの二塁打 ${(gd.entries.toList()..sort((a, b) => b.value - a.value)).take(15).map((e) => '${e.key}:${e.value}').join('  ')}');
  });
}
