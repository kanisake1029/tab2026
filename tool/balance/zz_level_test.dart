// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/db/app_database.dart';
import 'package:npb_pennant_app/engine/match_simulator.dart';
import 'package:npb_pennant_app/engine/pitch_catalog.dart';
import 'package:npb_pennant_app/engine/swing_model.dart';
import 'package:npb_pennant_app/engine/velo.dart';
import 'package:npb_pennant_app/models/player.dart';
import 'package:npb_pennant_app/models/team.dart';
import 'package:npb_pennant_app/providers/app_state.dart';
import 'package:npb_pennant_app/utils/schedule_generator.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 能力をそろえた打線（ミート・パワー・選球眼・走力＝B）と 守備（投手の球速・球威・制球・変化量・キレ・重さ、野手の守備＝P）を対戦させる。
///  同じ能力どうし（30 vs 30、60 vs 60、90 vs 90）は打率 .250 前後になるべき
void main() {
  test('level', () async {
    SharedPreferences.setMockInitialValues({});
    final tmp = File('${Directory.systemTemp.path}/s25_lv.sqlite');
    await File('backup/s25_20261109.sqlite').copy(tmp.path);
    final a = AppState(AppDatabase(NativeDatabase(tmp)));
    while (!a.loaded) { await Future.delayed(const Duration(milliseconds: 20)); }
    final env = Platform.environment;
    double? e(String k) => env[k] == null ? null : double.parse(env[k]!);
    SwingModel.noiseScale = e('NOISE') ?? SwingModel.noiseScale;
    Velo.pivot = e('PIVOT') ?? Velo.pivot; MatchSimulator.levelGain = e('GAIN') ?? MatchSimulator.levelGain; MatchSimulator.levelGainP = e('GAINP') ?? MatchSimulator.levelGainP; Velo.fastLinK = e('LINK') ?? Velo.fastLinK; SwingModel.notIdBase = e('NOTID') ?? SwingModel.notIdBase; SwingModel.idRecog = e('IDREC') ?? SwingModel.idRecog; SwingModel.misScale = e('MISS') ?? SwingModel.misScale; SwingModel.timingScale = e('TIMS') ?? SwingModel.timingScale;
    final npb = a.teams.where((t) => t.league == 'CL' || t.league == 'PL').toList();
    Team copy(Team t) => Team.fromJson(jsonDecode(jsonEncode(t.toJson())) as Map<String, dynamic>, Player.fromJson);
    final n = int.parse(env['N'] ?? '40');
    void setBat(Team t, int b) {
      for (final p in t.players) {
        p.seasonStats = PlayerStats();
        if (p.isPitcher) continue;
        p.contactLeft = b; p.contactRight = b; p.power = b; p.eye = b; p.run = env['RUN'] == null ? b : int.parse(env['RUN']!); p.clutch = 60; p.trajectory = 2;
      }
    }
    final fdef = env['DEF'] == null ? null : int.parse(env['DEF']!); // 野手の守備（指定がなければ投手と同じ）
    void setDef(Team t, int d) {
      for (final p in t.players) {
        final f = fdef ?? d;
        p.fieldP = f; p.fieldC = f; p.field1B = f; p.field2B = f; p.field3B = f; p.fieldSS = f; p.fieldLF = f; p.fieldCF = f; p.fieldRF = f;
        p.arm = f; p.throwAccuracy = f; p.catchSkill = f;
        if (!p.isPitcher) continue;
        Velo.setTo(p, Velo.fromNorm(d));
        p.pitchPower = d; p.control = d; p.clutchPitching = 60; p.quick = d;
        for (final x in p.pitches) {
          if (!PitchCatalog.isFastLike(x) && x.breakLevel > 0) x.breakLevel = d;
          x.sharpness = d; x.heaviness = d;
        }
      }
    }
    final cells = (env['CELLS'] ?? '30:30,45:45,60:60,75:75,90:90,30:60,60:30,60:90,90:60,30:90,90:30').split(',');
    for (final c in cells) {
      final bl = int.parse(c.split(':')[0]), pl = int.parse(c.split(':')[1]);
      final sim = MatchSimulator();
      var runs = 0, pa = 0, ab = 0, h = 0, hr = 0, so = 0, bb = 0, sf = 0, hbp = 0;
      for (var g = 0; g < n; g++) {
        final bat = copy(npb[g % npb.length]);
        final fld = copy(npb[(g + 5) % npb.length]);
        setBat(bat, bl); setDef(fld, pl);
        final s = sim.startGame(Match(homeTeamId: fld.id, awayTeamId: bat.id, date: DateTime(2026, 6, 1 + g % 28), matchType: 'オープン戦'), fld, bat);
        while (!sim.isFinished(s)) { sim.autoManage(s); sim.stepPlateAppearance(s); }
        sim.finishGame(s);
        runs += s.state.awayScore;
        for (final p in bat.players) {
          final st = p.seasonStats;
          ab += st.atBats; h += st.hits; hr += st.homeRuns; so += st.strikeouts; bb += st.walks; sf += st.sacFlies; hbp += st.hbp;
          pa += st.atBats + st.walks + st.hbp + st.sacFlies + st.sacBunts;
        }
      }
      final babip = (h - hr) / (ab - so - hr + sf);
      print('打者$bl vs 守備$pl  打率${(h / ab).toStringAsFixed(3)} BABIP${babip.toStringAsFixed(3)} 本/600打席${(hr / pa * 600).toStringAsFixed(1)} 三振%${(so / pa * 100).toStringAsFixed(1)} 四球%${(bb / pa * 100).toStringAsFixed(1)} 得点/9回${(runs / n).toStringAsFixed(2)}');
    }
  }, timeout: const Timeout(Duration(minutes: 40)));
}
