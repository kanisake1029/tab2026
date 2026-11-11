// ignore_for_file: avoid_print
// 経験値の仕組みの新旧比べ：若い選手をレギュラー扱いで18〜40歳まで育て、年齢ごとの能力を比べる（試合・練習の倍率は1）
import 'dart:io';
import 'dart:math';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/db/app_database.dart';
import 'package:npb_pennant_app/engine/growth_engine.dart';
import 'package:npb_pennant_app/models/player.dart';
import 'package:npb_pennant_app/providers/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── 旧：係数・必要量・衰え ──
double oldW(GrowthStat s) {
  const w = {'clutch': .6, 'arm': .7, 'throwAccuracy': .8, 'catchSkill': .8, 'velocity': .3, 'stamina': .8, 'clutchPitching': .6, 'maxEnergy': .5, 'recovery': .35};
  if (s.key.startsWith('field')) return .3;
  if (s.key.endsWith(':sharpness')) return .7;
  if (s.key.startsWith('pitch:')) return .5;
  return w[s.key] ?? 1.0;
}

int oldNeed(GrowthStat s, int v) {
  if (s.key == 'velocity') return (1000 * pow(2, (v - 150) / (v < 150 ? 12 : 6))).round().clamp(300, 20000);
  final l = GrowthEngine.levelOf(s, v);
  if (l <= 60) return 1000;
  if (l <= 80) return 1500;
  if (l <= 90) return 2000;
  return 4000;
}

void oldAdd(Player p, GrowthStat s, double amount) {
  var e = (p.exp[s.key] ?? 0) + amount.round();
  var v = s.get(p);
  while (e >= oldNeed(s, v)) {
    if (v >= s.max) { e = 0; break; }
    e -= oldNeed(s, v);
    v = min(v + s.step, s.max);
  }
  while (e < 0 && e.abs() >= oldNeed(s, max(s.min, v - s.step))) {
    if (v <= s.min) { e = 0; break; }
    e += oldNeed(s, max(s.min, v - s.step));
    v = max(v - s.step, s.min);
  }
  p.exp[s.key] = e.clamp(-1999, 1999);
  s.set(p, v);
}

List<GrowthStat> oldStats(Player p) => [
      for (final s in GrowthEngine.statsOf(p)) if (s.key != 'quick') s,
      ...GrowthEngine.pitchStatsOf(p),
      if (GrowthEngine.fieldStatOf(p) != null) GrowthEngine.fieldStatOf(p)!,
    ];

void oldYear(Player p, Random r) {
  final ph = GrowthEngine.phaseOf(p);
  final m = ph.expMultiplier * p.growthRate;
  final games = p.isPitcher ? 25.0 : 143.0;
  final per = p.isPitcher ? 18 + 5 * 6.5 : 15.0;
  for (final s in oldStats(p)) {
    oldAdd(p, s, games * per * m * oldW(s));
  }
  // 練習：おまかせ 360日分（キャンプ込み）
  for (var d = 0; d < 36; d++) {
    final menu = GrowthEngine.autoPractice(p);
    final ts = GrowthEngine.practiceTargets(p, menu: menu).where((s) => !s.label.startsWith('守備適性（')).toList();
    for (final s in ts) {
      oldAdd(p, s, 100 * m * GrowthEngine.practiceMult(p, menu: menu) * (s.key == 'velocity' ? .3 : 1.0));
    }
    final groups = {for (final s in ts) if (s.group != 'body' && !s.key.startsWith('pitch:')) s.group};
    for (final s in GrowthEngine.statsOf(p)) {
      if (s.key == 'quick' || !groups.contains(s.group) || ts.any((x) => x.key == s.key) || s.key == 'velocity') continue;
      oldAdd(p, s, 100 * m * .3 * oldW(s));
    }
  }
  // 衰え
  for (final s in GrowthEngine.statsOf(p)) {
    if (s.key == 'quick') continue;
    final fast = {'velocity', 'run', 'arm'}.contains(s.key), slow = {'contactLeft', 'contactRight', 'eye', 'control'}.contains(s.key);
    final d = ph == GrowthPhase.transition ? (fast ? 2.0 : (slow ? .5 : 1.0)) : (ph == GrowthPhase.decline ? (fast ? 3.8 : (slow ? 1.7 : 3.0)) : 0.0);
    if (d > 0) oldAdd(p, s, -d * (0.7 + r.nextDouble() * 0.6) * oldNeed(s, s.get(p)) * (s.key == 'velocity' ? 1.0 : oldW(s)));
  }
  if (ph == GrowthPhase.transition || ph == GrowthPhase.decline) {
    for (final s in GrowthEngine.pitchStatsOf(p)) {
      if (s.key.endsWith(':heaviness')) continue;
      oldAdd(p, s, -(ph == GrowthPhase.transition ? .5 : 1.5) * (0.7 + r.nextDouble() * 0.6) * oldNeed(s, s.get(p)));
    }
  }
}

// ── 新：GrowthEngine をそのまま ──
void newYear(Player p, Random r) {
  final games = p.isPitcher ? 25 : 143;
  for (var g = 0; g < games; g++) {
    GrowthEngine.gameExp(p, 1.0, innings: p.isPitcher ? 6.5 : 0);
  }
  final ph = GrowthEngine.phaseOf(p);
  for (var d = 0; d < 36; d++) {
    final menu = GrowthEngine.autoPractice(p);
    final ts = GrowthEngine.practiceTargets(p, menu: menu);
    for (final s in ts) {
      GrowthEngine.addExp(p, s, 100 * p.growthRate * GrowthEngine.phaseMult(p, s, ph) * GrowthEngine.practiceMult(p, menu: menu) * s.weight);
    }
    final groups = {for (final s in ts) if (s.group != 'body' && !s.key.startsWith('pitch:')) s.group};
    for (final s in GrowthEngine.statsOf(p)) {
      if (!groups.contains(s.group) || ts.any((x) => x.key == s.key) || s.key == 'velocity') continue;
      GrowthEngine.addExp(p, s, 100 * p.growthRate * GrowthEngine.phaseMult(p, s, ph) * .3);
    }
  }
}

void main() {
  test('growth cmp', () async {
    SharedPreferences.setMockInitialValues({});
    final tmp = File('${Directory.systemTemp.path}/s25_gcmp.sqlite');
    await File('backup/s25_phone_open.sqlite').copy(tmp.path);
    final a = AppState(AppDatabase(NativeDatabase(tmp)));
    while (!a.loaded) { await Future.delayed(const Duration(milliseconds: 20)); }
    final young = [for (final t in a.leagueTeams) for (final p in t.players) if (p.age <= 19) p];
    print('若手 ${young.length}人');
    int fieldMain(Player p) => {'捕手': p.fieldC, '一塁手': p.field1B, '二塁手': p.field2B, '三塁手': p.field3B, '遊撃手': p.fieldSS, '左翼手': p.fieldLF, '中堅手': p.fieldCF, '右翼手': p.fieldRF}[p.mainPosition] ?? 0;
    double avgSharp(Player p) => p.pitches.isEmpty ? 0 : p.pitches.map((x) => x.sharpness).reduce((a, b) => a + b) / p.pitches.length;
    double avgBreak(Player p) { final l = p.pitches.where((x) => x.breakLevel > 20).toList(); return l.isEmpty ? 0 : l.map((x) => x.breakLevel).reduce((a, b) => a + b) / l.length; }
    final bat = <String, num Function(Player)>{'ミ': (p) => p.contact, 'パ': (p) => p.power, '眼': (p) => p.eye, 'チ': (p) => p.clutch, '走': (p) => p.run, '肩': (p) => p.arm, '送': (p) => p.throwAccuracy, '捕': (p) => p.catchSkill, '守': fieldMain, 'OVR': (p) => p.ovr};
    final pit = <String, num Function(Player)>{'km': (p) => p.velocity, '威': (p) => p.pitchPower, '制': (p) => p.control, 'ク': (p) => p.quick, 'ス': (p) => p.stamina, 'ピ': (p) => p.clutchPitching, 'キレ': avgSharp, '変化': avgBreak, 'OVR': (p) => p.ovr};
    for (final model in ['旧', '新']) {
      final ps = [for (final p in young) Player.fromJson(p.toJson())..exp.clear()];
      final r = Random(7);
      final snaps = <int, List<Player>>{};
      for (var age = 18; age <= 40; age++) {
        for (final p in ps) {
          if (model == '旧') { oldYear(p, r); } else { newYear(p, r); GrowthEngine.decline(p, GrowthEngine.phaseOf(p), r); }
          p.age++;
        }
        if ({22, 26, 30, 33, 36, 39}.contains(age + 1)) snaps[age + 1] = [for (final p in ps) Player.fromJson(p.toJson())];
      }
      print('=== $model ===');
      for (final e in snaps.entries) {
        String line(bool pitcher, Map<String, num Function(Player)> m) {
          final l = e.value.where((p) => p.isPitcher == pitcher).toList();
          final b = StringBuffer();
          m.forEach((k, f) {
            final v = l.map(f).toList()..sort();
            b.write('$k ${(v.reduce((a, b) => a + b) / v.length).toStringAsFixed(0)}/${v[(v.length * 0.9).floor()].toStringAsFixed(0)}  ');
          });
          return b.toString();
        }
        print('${e.key}歳 野手 ${line(false, bat)}');
        print('${e.key}歳 投手 ${line(true, pit)}');
      }
    }
  });
}
