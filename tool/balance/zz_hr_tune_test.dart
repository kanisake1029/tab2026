// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/db/app_database.dart';
import 'package:npb_pennant_app/engine/match_simulator.dart';
import 'package:npb_pennant_app/engine/spec_constants.dart';
import 'package:npb_pennant_app/engine/swing_model.dart';
import 'package:npb_pennant_app/models/player.dart';
import 'package:npb_pennant_app/models/team.dart';
import 'package:npb_pennant_app/providers/app_state.dart';
import 'package:npb_pennant_app/utils/schedule_generator.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 本塁打・打率の合わせ：A＝今のリーグどうし、B＝主砲クラス（ミート80・パワー89・選球63）を弾道1〜4 で、今のリーグの投手・守備と対戦
void main() {
  test('hr tune', () async {
    final sw0 = Stopwatch()..start();
    SharedPreferences.setMockInitialValues({});
    final tmp = File('${Directory.systemTemp.path}/s25_hrt.sqlite');
    await File('backup/s25_opening.sqlite').copy(tmp.path);
    final a = AppState(AppDatabase(NativeDatabase(tmp)));
    while (!a.loaded) { await Future.delayed(const Duration(milliseconds: 20)); }
    print('読み込み ${sw0.elapsedMilliseconds}ms');
    final env = Platform.environment;
    double? e(String k) => env[k] == null ? null : double.parse(env[k]!);
    Spec.eyA = e('EYA') ?? Spec.eyA; Spec.eyK = e('EYK') ?? Spec.eyK; Spec.attA = e('ATTA') ?? Spec.attA; Spec.attK = e('ATTK') ?? Spec.attK;
    Spec.batA = e('BATA') ?? Spec.batA; Spec.batB = e('BATB') ?? Spec.batB; Spec.sigEyBase = e('SIGEY') ?? Spec.sigEyBase;
    SwingModel.noiseScale = e('NOISE') ?? SwingModel.noiseScale;
    MatchSimulator.levelGain = e('GAIN') ?? MatchSimulator.levelGain;

    final npb = a.teams.where((t) => t.league == 'CL' || t.league == 'PL').toList();
    Team copy(Team t) => Team.fromJson(jsonDecode(jsonEncode(t.toJson())) as Map<String, dynamic>, Player.fromJson);
    final n = int.parse(env["N"] ?? "80");
    final starPow = int.parse(env["POW"] ?? "89"), starMeet = int.parse(env["MEET"] ?? "80");
    final parts = (env['PARTS'] ?? 'A,1,2,3,4').split(',');
    final tm = [0, 0, 0, 0, 0];
    final per = <String, List<int>>{}; // 選手ごと：打席・打数・安打・本塁打・打点
    for (final part in parts) {
      final sim = MatchSimulator();
      var runs = 0, pa = 0, ab = 0, h = 0, hr = 0, so = 0, bb = 0, sf = 0, d2 = 0, games = 0;
      for (var g = 0; g < n; g++) {
        final t0 = sw0.elapsedMicroseconds;
        final bat = copy(npb[g % npb.length]);
        final fld = copy(npb[(g + 1 + (g ~/ npb.length) % (npb.length - 1)) % npb.length]); // 相手は順に入れ替える
        for (final p in bat.players) {
          p.seasonStats = PlayerStats();
          if (part != 'A' && part != 'L' && !p.isPitcher) { p.contactLeft = starMeet; p.contactRight = starMeet; p.power = starPow; p.eye = 63; p.clutch = 60; p.trajectory = int.parse(part); }
        }
        final t1 = sw0.elapsedMicroseconds;
        final s = sim.startGame(Match(homeTeamId: fld.id, awayTeamId: bat.id, date: DateTime(2026, 6, 1 + g % 28), matchType: 'オープン戦'), fld, bat);
        final t2 = sw0.elapsedMicroseconds;
        var paN = 0;
        while (!sim.isFinished(s)) { sim.autoManage(s); sim.stepPlateAppearance(s); if (++paN > 600) throw StateError('試合が終わらない: 回${s.state.inning} ${s.state.awayScore}-${s.state.homeScore} O${s.state.outs}'); }
        final t3 = sw0.elapsedMicroseconds;
        sim.finishGame(s);
        final t4 = sw0.elapsedMicroseconds;
        tm[0] += t1 - t0; tm[1] += t2 - t1; tm[2] += t3 - t2; tm[3] += t4 - t3; tm[4] += paN;
        runs += s.state.awayScore; games++;
        for (final p in bat.players.where((p) => !p.isPitcher)) {
          final st = p.seasonStats;
          ab += st.atBats; h += st.hits; hr += st.homeRuns; so += st.strikeouts; bb += st.walks; sf += st.sacFlies; d2 += st.doubles;
          pa += st.atBats + st.walks + st.hbp + st.sacFlies + st.sacBunts;
          if (part == 'L') { final l = per.putIfAbsent(p.id, () => [0, 0, 0, 0, 0]); l[0] += st.atBats + st.walks + st.hbp + st.sacFlies + st.sacBunts; l[1] += st.atBats; l[2] += st.hits; l[3] += st.homeRuns; l[4] += st.rbi; }
        }
      }
      if (part == 'L') {
        final all = {for (final t in npb) for (final p in t.players) p.id: (p, t)};
        final rows = per.entries.where((x) => x.value[0] >= 400).toList()..sort((x, y) => (y.value[3] / y.value[0]).compareTo(x.value[3] / x.value[0]));
        for (final x in rows.take(14)) { final (p, t) = all[x.key]!; final v = x.value; print('実力 ${p.registeredName.padRight(8)} ${t.shortName.padRight(5)} ${p.bats}打 ミ${p.contact} パ${p.power} 弾${p.trajectory} 選${p.eye} | 打席${v[0]} 打率${(v[2] / v[1]).toStringAsFixed(3)} 本/600 ${(v[3] * 600 / v[0]).toStringAsFixed(1)} 点/600 ${(v[4] * 600 / v[0]).toStringAsFixed(1)}'); }
        final byAvg = per.entries.where((x) => x.value[0] >= 400).toList()..sort((x, y) => (y.value[2] / y.value[1]).compareTo(x.value[2] / x.value[1]));
        for (final x in byAvg.take(8)) { final (p, t) = all[x.key]!; final v = x.value; print('実力(打率) ${p.registeredName.padRight(8)} ミ${p.contact} パ${p.power} 弾${p.trajectory} 選${p.eye} 走${p.run} | 打席${v[0]} 打率${(v[2] / v[1]).toStringAsFixed(3)} 本/600 ${(v[3] * 600 / v[0]).toStringAsFixed(1)}'); }
      }
      print('部 $part 終了 ${sw0.elapsedMilliseconds}ms  コピー${tm[0] ~/ 1000}ms 開始${tm[1] ~/ 1000}ms 試合${tm[2] ~/ 1000}ms 終了処理${tm[3] ~/ 1000}ms 打席${tm[4]}');
      final babip = (h - hr) / (ab - so - hr + sf);
      print('${part == 'A' ? 'リーグ    ' : '主砲 弾道$part'}  打率${(h / ab).toStringAsFixed(3)} BABIP${babip.toStringAsFixed(3)} 本/600打席${(hr / pa * 600).toStringAsFixed(1)} 二塁打/600${(d2 / pa * 600).toStringAsFixed(1)} 三振%${(so / pa * 100).toStringAsFixed(1)} 四球%${(bb / pa * 100).toStringAsFixed(1)} 得点/試合${(runs / games).toStringAsFixed(2)} 本/試合${(hr / games).toStringAsFixed(2)}');
    }
  }, timeout: const Timeout(Duration(minutes: 60)));
}
