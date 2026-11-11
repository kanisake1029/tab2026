// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:math';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/db/app_database.dart';
import 'package:npb_pennant_app/providers/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('ishihara balls', () async {
    SharedPreferences.setMockInitialValues({});
    final tmp = File('${Directory.systemTemp.path}/s25_ishi3.sqlite');
    await File('backup/s25_20261109.sqlite').copy(tmp.path);
    final a = AppState(AppDatabase(NativeDatabase(tmp)));
    while (!a.loaded) { await Future.delayed(const Duration(milliseconds: 20)); }
    final rows = await a.db.loadSeasonPitches(a.startYear);
    print('記録 ${rows.length}球');
    for (final name in ['石原 翼', 'デクスター・ミルズ', '河野 玲央', '林 颯', '青柳 優人']) {
      final l = rows.where((r) => r.batter == name).toList();
      final ip = l.where((r) => r.result == 'インプレー').toList();
      final c = <String, int>{};
      for (final r in ip) { c[r.contact] = (c[r.contact] ?? 0) + 1; }
      final la = ip.where((r) => r.launch != null).map((r) => r.launch!).toList()..sort();
      final dist = ip.where((r) => r.landY != null).map((r) => sqrt(r.landX! * r.landX! + r.landY! * r.landY!)).toList()..sort();
      final fly = la.where((x) => x >= 20 && x <= 40).length;
      print('$name 球${l.length} 振${l.where((r) => r.result == '空振り').length} 打球${ip.length} 当たり$c');
      print('   角度 中央${la.isEmpty ? '-' : la[la.length ~/ 2].toStringAsFixed(0)} 20〜40°${fly}本  飛距離 上位5 ${dist.reversed.take(5).map((d) => d.toStringAsFixed(0)).toList()}  100m超${dist.where((d) => d > 100).length}');
      final outs = <String, int>{};
      for (final r in ip) { outs[r.outcome] = (outs[r.outcome] ?? 0) + 1; }
      print('   結果 $outs');
      for (final r in ip.where((r) => r.landY != null && sqrt(r.landX! * r.landX! + r.landY! * r.landY!) > 100)) { print('     ${sqrt(r.landX! * r.landX! + r.landY! * r.landY!).toStringAsFixed(0)}m 方向${(atan2(r.landX!, r.landY!) * 180 / pi).toStringAsFixed(0)}° 角度${r.launch?.toStringAsFixed(0)} ${r.contact} ${r.outcome} ${r.fielder} 試合${r.matchIdx}'); }
    }
  });
}
