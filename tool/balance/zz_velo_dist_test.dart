// ignore_for_file: avoid_print
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/db/app_database.dart';
import 'package:npb_pennant_app/providers/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';
void main() {
  test('velo', () async {
    SharedPreferences.setMockInitialValues({});
    final tmp = File('${Directory.systemTemp.path}/s25_vd.sqlite');
    await File('backup/s25_20261109.sqlite').copy(tmp.path);
    final a = AppState(AppDatabase(NativeDatabase(tmp)));
    while (!a.loaded) { await Future.delayed(const Duration(milliseconds: 20)); }
    final ps = [for (final t in a.teams.where((t) => t.league == 'CL' || t.league == 'PL')) for (final id in t.roster1G) ...t.players.where((p) => p.id == id && p.isPitcher)];
    final v = ps.map((p) => p.velocity).toList()..sort();
    print('1軍投手 ${v.length}人 平均${(v.reduce((a, b) => a + b) / v.length).toStringAsFixed(1)} 中央${v[v.length ~/ 2]}');
    for (final lo in [140, 145, 150, 155, 160, 165]) { print('$lo-${lo + 4}km ${v.where((x) => x >= lo && x < lo + 5).length}人'); }
    print('148km以下の割合 ${(v.where((x) => x <= 148).length * 100 / v.length).toStringAsFixed(0)}%');
    final fr = ps.map((p) => p.pitches.where((x) => x.name.contains('ストレート') || x.name.contains('ツーシーム') || x.name.contains('カット')).fold<int>(0, (s, x) => s + x.ratio) / p.pitches.fold<int>(0, (s, x) => s + x.ratio).clamp(1, 9999)).toList()..sort();
    print('直球系の割合 中央${(fr[fr.length ~/ 2] * 100).round()}% 下位10%=${(fr[fr.length ~/ 10] * 100).round()}%');
  });
}
