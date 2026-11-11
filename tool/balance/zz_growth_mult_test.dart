// ignore_for_file: avoid_print
// 個人差の確かめ：同じ18歳の選手を、成長率（才能×向上心）・コーチ・設備を変えて18〜38歳まで育てる（1軍レギュラー扱い）
import 'dart:io';
import 'dart:math';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/db/app_database.dart';
import 'package:npb_pennant_app/engine/facility_engine.dart';
import 'package:npb_pennant_app/engine/growth_curve.dart';
import 'package:npb_pennant_app/engine/growth_engine.dart';
import 'package:npb_pennant_app/models/player.dart';
import 'package:npb_pennant_app/providers/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void year(Player p, double coach, int lab, Random r) {
  double m(GrowthStat s) => coach * FacilityEngine.labMult(lab, s.key);
  final games = p.isPitcher ? 25 : 143;
  for (var g = 0; g < games; g++) {
    GrowthEngine.gameExp(p, 1.0, innings: p.isPitcher ? 6.5 : 0, coach: m);
  }
  final ph = GrowthEngine.phaseOf(p);
  for (var d = 0; d < 36; d++) {
    final menu = GrowthEngine.autoPractice(p);
    final ts = GrowthEngine.practiceTargets(p, menu: menu);
    for (final s in ts) {
      GrowthEngine.addExp(p, s, 100 * p.growthRate * GrowthEngine.phaseMult(p, s, ph) * GrowthEngine.practiceMult(p, menu: menu) * s.weight * m(s));
    }
    final groups = {for (final s in ts) if (s.group != 'body' && !s.key.startsWith('pitch:')) s.group};
    for (final s in GrowthEngine.statsOf(p)) {
      if (!groups.contains(s.group) || ts.any((x) => x.key == s.key) || s.key == 'velocity') continue;
      GrowthEngine.addExp(p, s, 100 * p.growthRate * GrowthEngine.phaseMult(p, s, ph) * .3 * m(s));
    }
  }
  GrowthEngine.decline(p, ph, r);
}

void main() {
  test('growth mult', () async {
    GrowthEngine.highK = double.parse(Platform.environment['HIGHK'] ?? '150');
    print('highK ${GrowthEngine.highK}');
    SharedPreferences.setMockInitialValues({});
    final tmp = File('${Directory.systemTemp.path}/s25_gmult.sqlite');
    await File('backup/s25_phone_open.sqlite').copy(tmp.path);
    final a = AppState(AppDatabase(NativeDatabase(tmp)));
    while (!a.loaded) { await Future.delayed(const Duration(milliseconds: 20)); }
    final young = [for (final t in a.leagueTeams) for (final p in t.players) if (p.age <= 19) p];
    // 真ん中くらいの野手・投手
    Player mid(bool pit) {
      final l = young.where((p) => p.isPitcher == pit && !GrowthCurve.mature(p)).toList()..sort((x, y) => x.ovr.compareTo(y.ovr));
      return l[l.length ~/ 2];
    }
    final cases = <(String, int, int, double, int)>[
      ('向上心 低（才能50・向上心20）', 50, 20, 1.0, 0),
      ('標準（才能50・向上心50）', 50, 50, 1.0, 0),
      ('努力家（才能50・向上心80）', 50, 80, 1.0, 0),
      ('天才努力家（才能90・向上心100）', 90, 100, 1.0, 0),
      ('標準＋名コーチ（×1.3）', 50, 50, 1.3, 0),
      ('標準＋ダメコーチ（×0.75）', 50, 50, 0.75, 0),
      ('標準＋名コーチ＋ラボLv5', 50, 50, 1.3, 5),
    ];
    for (final pit in [false, true]) {
      final base = mid(pit);
      print('\n■ ${pit ? '投手' : '野手'} ${base.registeredName}（18歳時点 OVR ${base.ovr}、全盛期 ${GrowthEngine.peakRange(base)}）');
      for (final c in cases) {
        final p = Player.fromJson(base.toJson())..exp.clear();
        p.talent = c.$2;
        p.ambition = c.$3;
        p.age = 18;
        final r = Random(3);
        final row = StringBuffer('${c.$1.padRight(22)} 成長率×${p.growthRate.toStringAsFixed(2)}  OVR ');
        String detail = '';
        for (var age = 18; age < 38; age++) {
          year(p, c.$4, c.$5, r);
          p.age++;
          if ({22, 26, 30, 33, 36}.contains(p.age)) row.write('${p.age}歳 ${p.ovr}  ');
          if (p.age == 30) {
            detail = pit
                ? '30歳：${p.velocity}km 球威${p.pitchPower} 制球${p.control} スタ${p.stamina}'
                : '30歳：ミート${p.contact} パワー${p.power} 走${p.run} 肩${p.arm} 守備${GrowthEngine.fieldStatOf(p)!.get(p)}';
          }
        }
        print(row);
        print('    $detail');
      }
    }
  });
}

