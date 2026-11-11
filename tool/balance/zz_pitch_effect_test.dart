// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/db/app_database.dart';
import 'package:npb_pennant_app/engine/match_simulator.dart';
import 'package:npb_pennant_app/engine/spec_constants.dart';
import 'package:npb_pennant_app/models/player.dart';
import 'package:npb_pennant_app/models/team.dart';
import 'package:npb_pennant_app/providers/app_state.dart';
import 'package:npb_pennant_app/utils/schedule_generator.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 投手の能力を1つずつ変えて、同じ打線がどれだけ打つかを比べる
void main() {
  test('pitch effect', () async {
    SharedPreferences.setMockInitialValues({});
    final tmp = File('${Directory.systemTemp.path}/s25_pe.sqlite');
    await File('backup/s25_20261109.sqlite').copy(tmp.path);
    final a = AppState(AppDatabase(NativeDatabase(tmp)));
    while (!a.loaded) { await Future.delayed(const Duration(milliseconds: 20)); }
    final npb = a.teams.where((t) => t.league == 'CL' || t.league == 'PL').toList();
    Team copy(Team t) => Team.fromJson(jsonDecode(jsonEncode(t.toJson())) as Map<String, dynamic>, Player.fromJson);
    const n = int.fromEnvironment('N', defaultValue: 60);
    final env = Platform.environment;
    if (env['CTRLK'] != null) Spec.ctrlK = double.parse(env['CTRLK']!);
    if (env['CTRLB'] != null) Spec.ctrlBase = double.parse(env['CTRLB']!);
    if (env['MISB'] != null) Spec.mistakeBase = double.parse(env['MISB']!);
    if (env['CZK'] != null) MatchSimulator.ctrlZoneK = double.parse(env['CZK']!);
    final only = env['ONLY'];
    final all = <String, (int, int, int, int, int)>{
      '制球40': (152, 70, 40, 0, 0),
      '制球55': (152, 70, 55, 0, 0),
      '基準 152/70/70': (152, 70, 70, 0, 0),
      '制球80': (152, 70, 80, 0, 0),
      '制球90': (152, 70, 90, 0, 0),
      '球速145': (145, 70, 70, 0, 0),
      '球速160': (160, 70, 70, 0, 0),
      '球威85': (152, 85, 70, 0, 0),
      '変化量+20': (152, 70, 70, 20, 0),
      'キレ+20': (152, 70, 70, 0, 20),
      'キレ-20': (152, 70, 70, 0, -20),
      '全部上 160/85/85/+20/+20': (160, 85, 85, 20, 20),
      '全部下 145/55/55/-20/-20': (145, 55, 55, -20, -20),
    };
    final conds = {for (final e in all.entries) if (only == null || only.split(',').any((k) => e.key.startsWith(k))) e.key: e.value};
    for (final c in conds.entries) {
      final sim = MatchSimulator();
      var runs = 0, outs = 0, pa = 0, h = 0, hr = 0, so = 0, bb = 0, ab = 0, hbp = 0;
      for (var g = 0; g < n; g++) {
        final bat = copy(npb[g % npb.length]);
        final fld = copy(npb[(g + 5) % npb.length]);
        for (final p in fld.players.where((p) => p.isPitcher)) {
          final (v, pw, ct, br, sh) = c.value;
          final r = v / p.velocity;
          for (final pt in p.pitches) { pt.speed = (pt.speed * r).round(); if (pt.breakLevel > 0) pt.breakLevel = (pt.breakLevel + br).clamp(1, 100); pt.sharpness = (pt.sharpness + sh).clamp(1, 100); }
          p.velocity = v; p.pitchPower = pw; p.control = ct;
        }
        for (final p in bat.players) { p.seasonStats = PlayerStats(); }
        final s = sim.startGame(Match(homeTeamId: fld.id, awayTeamId: bat.id, date: DateTime(2026, 6, 1 + g % 28), matchType: 'オープン戦'), fld, bat);
        while (!sim.isFinished(s)) { sim.autoManage(s); sim.stepPlateAppearance(s); }
        sim.finishGame(s);
        runs += s.state.awayScore;
        for (final p in bat.players) {
          final st = p.seasonStats;
          ab += st.atBats; hbp += st.hbp; h += st.hits; hr += st.homeRuns; so += st.strikeouts; bb += st.walks; pa += st.atBats + st.walks + st.hbp + st.sacFlies + st.sacBunts;
        }
        outs += 27;
      }
      print('${c.key.padRight(20)} 得点/9回 ${(runs * 27 / outs).toStringAsFixed(2)} 打率 ${(h / ab).toStringAsFixed(3)} 本/試合 ${(hr / n).toStringAsFixed(2)} 三振% ${(so / pa * 100).toStringAsFixed(1)} 四球% ${(bb / pa * 100).toStringAsFixed(1)}  与四球/9 ${(bb * 27 / outs).toStringAsFixed(2)} 与四死球/9 ${((bb + hbp) * 27 / outs).toStringAsFixed(2)}');
    }
  }, timeout: const Timeout(Duration(minutes: 20)));
}
