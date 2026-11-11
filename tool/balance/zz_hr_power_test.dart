// ignore_for_file: avoid_print
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/db/app_database.dart';
import 'package:npb_pennant_app/providers/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('hr by power', () async {
    SharedPreferences.setMockInitialValues({});
    final tmp = File('${Directory.systemTemp.path}/s25_hrp.sqlite');
    await File('backup/s25_20261109.sqlite').copy(tmp.path);
    final a = AppState(AppDatabase(NativeDatabase(tmp)));
    while (!a.loaded) { await Future.delayed(const Duration(milliseconds: 20)); }
    final ps = [for (final t in a.teams.where((t) => t.league == 'CL' || t.league == 'PL')) for (final p in t.players) if (!p.isPitcher && p.seasonStats.atBats >= 60) (t, p)];
    ps.sort((x, y) => y.$2.power.compareTo(x.$2.power));
    for (final (t, p) in ps.take(30)) {
      final s = p.seasonStats;
      print('${t.shortName.padRight(5)} ${p.registeredName.padRight(8)} 弾${p.trajectory} パ${p.power} ミ${p.contact}  打数${s.atBats} 本${s.homeRuns} 二${s.doubles} 打率${(s.hits / s.atBats).toStringAsFixed(3)}');
    }
    for (final lo in [50, 60, 70, 80, 90]) {
      final l = ps.where((x) => x.$2.power >= lo && x.$2.power < lo + 10).toList();
      final ab = l.fold<int>(0, (s, x) => s + x.$2.seasonStats.atBats), hr = l.fold<int>(0, (s, x) => s + x.$2.seasonStats.homeRuns);
      print('パワー$lo台 ${l.length}人 打数$ab 本$hr  → 93打数あたり ${(hr / ab * 93).toStringAsFixed(1)}本');
    }
  });
}
