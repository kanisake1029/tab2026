// ignore_for_file: avoid_print
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/db/app_database.dart';
import 'package:npb_pennant_app/models/player.dart';
import 'package:npb_pennant_app/providers/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('avg', () async {
    SharedPreferences.setMockInitialValues({});
    final tmp = File('${Directory.systemTemp.path}/s25_avg.sqlite');
    await File('backup/s25_20261108.sqlite').copy(tmp.path);
    final a = AppState(AppDatabase(NativeDatabase(tmp)));
    while (!a.loaded) { await Future.delayed(const Duration(milliseconds: 20)); }
    final all = [for (final t in a.leagueTeams) ...t.players];
    final one = [for (final t in a.leagueTeams) for (final p in t.players) if (t.roster1G.contains(p.id)) p];
    String row(String k, num Function(Player) f, bool pit) {
      double av(List<Player> l) { final x = l.where((p) => p.isPitcher == pit).toList(); return x.isEmpty ? 0 : x.map(f).reduce((a, b) => a + b) / x.length; }
      return '$k 全体${av(all).toStringAsFixed(1)} 1軍${av(one).toStringAsFixed(1)}';
    }
    final bat = <String, num Function(Player)>{'ミート': (p) => p.contact, 'パワー': (p) => p.power, '走力': (p) => p.run, '肩力': (p) => p.arm, '送球': (p) => p.throwAccuracy, '捕球': (p) => p.catchSkill, '選球眼': (p) => p.eye, 'チャンス': (p) => p.clutch, '弾道': (p) => p.trajectory, '本職守備': (p) => {'捕手': p.fieldC, '一塁手': p.field1B, '二塁手': p.field2B, '三塁手': p.field3B, '遊撃手': p.fieldSS, '左翼手': p.fieldLF, '中堅手': p.fieldCF, '右翼手': p.fieldRF}[p.mainPosition] ?? 0, 'OVR': (p) => p.ovr};
    final pit = <String, num Function(Player)>{'球速km': (p) => p.velocity, '球速値': (p) => p.velocityNorm, '球威': (p) => p.pitchPower, '制球': (p) => p.control, 'スタミナ': (p) => p.stamina, 'ピンチ': (p) => p.clutchPitching, 'OVR': (p) => p.ovr};
    print('野手'); bat.forEach((k, f) => print('  ${row(k, f, false)}'));
    print('投手'); pit.forEach((k, f) => print('  ${row(k, f, true)}'));
  });
}
