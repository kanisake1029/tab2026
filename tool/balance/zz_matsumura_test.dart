// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/db/app_database.dart';
import 'package:npb_pennant_app/engine/match_simulator.dart';
import 'package:npb_pennant_app/engine/swing_model.dart';
import 'package:npb_pennant_app/models/player.dart';
import 'package:npb_pennant_app/models/team.dart';
import 'package:npb_pennant_app/providers/app_state.dart';
import 'package:npb_pennant_app/utils/schedule_generator.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 自球団の投手を1人ずつ、相手チームの全投手に写して、同じ打線に投げさせて比べる
void main() {
  test('matsumura', () async {
    SharedPreferences.setMockInitialValues({});
    final tmp = File('${Directory.systemTemp.path}/s25_mt.sqlite');
    await File('backup/s25_20261109.sqlite').copy(tmp.path);
    final a = AppState(AppDatabase(NativeDatabase(tmp)));
    while (!a.loaded) { await Future.delayed(const Duration(milliseconds: 20)); }
    final npb = a.teams.where((t) => t.league == 'CL' || t.league == 'PL').toList();
    final my = a.myTeam!;
    Team copy(Team t) => Team.fromJson(jsonDecode(jsonEncode(t.toJson())) as Map<String, dynamic>, Player.fromJson);
    const n = int.fromEnvironment('N', defaultValue: 80);
    final names = (Platform.environment['NAMES'] ?? '松村,伊藤,レーン,ジョンソン').split(',');
    final env = Platform.environment;
    double? e(String k) => env[k] == null ? null : double.parse(env[k]!);
    SwingModel.notIdBase = e('NOTID') ?? SwingModel.notIdBase; SwingModel.idRecog = e('IDREC') ?? SwingModel.idRecog; SwingModel.prevPull = e('PULL') ?? SwingModel.prevPull; SwingModel.brkConK = e('BRKK') ?? SwingModel.brkConK; SwingModel.misScale = e('MISS') ?? SwingModel.misScale; SwingModel.misBreakK = e('MISBK') ?? SwingModel.misBreakK;
    if (env['OLD'] != null) { MatchSimulator.batterResponse = false; MatchSimulator.readFastBase = 0; MatchSimulator.readFastMul = 1; }
    if (env['PFB'] != null) { MatchSimulator.readFastBase = double.parse(env['PFB']!); MatchSimulator.readFastMul = 1 - MatchSimulator.readFastBase; }
    for (final nm in names) {
      final src = my.players.where((p) => p.isPitcher && p.registeredName.contains(nm)).firstOrNull;
      if (src == null) { print('$nm なし'); continue; }
      print('■ ${src.registeredName} ${src.throws}投 ${src.age}歳 球速${src.velocity} 球威${src.pitchPower} 制球${src.control} スタ${src.stamina} ク${src.quick} 調子${src.conditionAt(a.currentDate)}');
      for (final pt in src.pitches) { print('   ${pt.name} 速${pt.speed} 変${pt.breakLevel} キレ${pt.sharpness} 重${pt.heaviness} 角${pt.angle} 割合${pt.ratio}'); }
      final js = jsonEncode(src.toJson());
      final sim = MatchSimulator(); MatchSimulator.debugStats.clear();
      var runs = 0, outs = 0, pa = 0, h = 0, hr = 0, so = 0, bb = 0, ab = 0, hbp = 0, d2 = 0;
      var paL = 0, hL = 0, abL = 0, paR = 0, hR = 0, abR = 0;
      for (var g = 0; g < n; g++) {
        final bat = copy(npb[g % npb.length]);
        if (bat.id == my.id) continue;
        final fld = copy(my);
        for (final p in [...fld.players, ...bat.players].where((p) => p.isPitcher)) {
          final c = Player.fromJson(jsonDecode(js) as Map<String, dynamic>);
          p.velocity = c.velocity; p.pitchPower = c.pitchPower; p.control = c.control; p.pitches = c.pitches; p.throws = c.throws;
          if (env['FULLSTA'] != null) p.stamina = 99; else p.stamina = c.stamina;
          p.quick = c.quick;
        }
        for (final p in bat.players) { p.seasonStats = PlayerStats(); }
        final s = sim.startGame(Match(homeTeamId: fld.id, awayTeamId: bat.id, date: DateTime(2026, 6, 1 + g % 28), matchType: 'オープン戦'), fld, bat);
        while (!sim.isFinished(s)) { sim.autoManage(s); sim.stepPlateAppearance(s); }
        sim.finishGame(s);
        runs += s.state.awayScore; outs += 27;
        for (final p in bat.players) {
          final st = p.seasonStats;
          ab += st.atBats; hbp += st.hbp; h += st.hits; hr += st.homeRuns; so += st.strikeouts; bb += st.walks; d2 += st.doubles;
          final ppa = st.atBats + st.walks + st.hbp + st.sacFlies + st.sacBunts; pa += ppa;
          if (p.bats == 'L') { paL += ppa; hL += st.hits; abL += st.atBats; } else { paR += ppa; hR += st.hits; abR += st.atBats; }
        }
      }
      final d = MatchSimulator.debugStats;
      double r(String k, String b) => (d[k] ?? 0) / ((d[b] ?? 1).clamp(1, 1 << 40));
      print('   → 得点/9 ${(runs * 27 / outs).toStringAsFixed(2)} 打率${(h / ab).toStringAsFixed(3)} 本/9 ${(hr * 27 / outs).toStringAsFixed(2)} 二塁打/9 ${(d2 * 27 / outs).toStringAsFixed(2)} 三振% ${(so / pa * 100).toStringAsFixed(1)} 四球% ${(bb / pa * 100).toStringAsFixed(1)}  対左 ${(hL / abL).toStringAsFixed(3)}(${paL}) 対右 ${(hR / abR).toStringAsFixed(3)}(${paR})');
      String bk(String k) => '$k 空振${(r('br_wh_$k', 'br_sw_$k') * 100).toStringAsFixed(0)}% 弱い当たり${(r('br_weak_$k', 'br_bip_$k') * 100).toStringAsFixed(0)}%';
      print('   緩急 ${['first', 'd0', 'd15', 'd30'].map(bk).join(' / ')}');
      print('   変化量 ${['b0', 'b1', 'b2', 'b3'].map(bk).join(' / ')}');
      print('   ゾーン率${(r('zonePitches', 'pitches') * 100).toStringAsFixed(0)}% 空振/スイング${(r('whiffs', 'swings') * 100).toStringAsFixed(0)}% ボール振り${(r('ballSwings', 'ballPitches') * 100).toStringAsFixed(0)}% ゾーン振り${(r('zoneSwings', 'zonePitches') * 100).toStringAsFixed(0)}% 失投${(r('hangingPitches', 'pitches') * 100).toStringAsFixed(1)}% 疲れ球${(r('staminaRoughedPitches', 'pitches') * 100).toStringAsFixed(0)}%');
    }
  }, timeout: const Timeout(Duration(minutes: 30)));
}
