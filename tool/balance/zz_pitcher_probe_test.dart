// ignore_for_file: avoid_print
// 投手の確かめ：今のセーブで、能力の高い投手の成績（防御率・被打率・K/BB/HR・BABIP）を、自球団と他球団で比べる
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/db/app_database.dart';
import 'package:npb_pennant_app/models/player.dart';
import 'package:npb_pennant_app/providers/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

String line(Player p, String team) {
  final s = p.seasonStats;
  final ip = s.inningsPitched / 3;
  String r(num v) => ip == 0 ? '-' : (v * 9 / ip).toStringAsFixed(1);
  final bip = s.hitsAllowed - s.hrAllowed;
  final pts = p.pitches.map((x) => '${x.name}${x.breakLevel}/${x.sharpness}').join(' ');
  return '${team.padRight(5)} ${p.registeredName.padRight(9)} OVR${p.ovr} ${p.velocity}km 威${p.pitchPower} 制${p.control} ス${p.stamina} ク${p.quick}  回${ip.toStringAsFixed(0)} 防${ip == 0 ? '-' : (s.earnedRuns * 9 / ip).toStringAsFixed(2)} 被安/9 ${r(s.hitsAllowed)} 振${r(s.pitcherStrikeouts)} 四${r(s.pitcherWalks)} 本${r(s.hrAllowed)} BABIP${(bip / (ip * 3 + bip - s.pitcherStrikeouts).clamp(1, 9999)).toStringAsFixed(3)}  [$pts]';
}

void main() {
  test('pitchers', () async {
    SharedPreferences.setMockInitialValues({});
    final tmp = File('${Directory.systemTemp.path}/s25_ptch.sqlite');
    await File('backup/s25_20261109.sqlite').copy(tmp.path);
    final a = AppState(AppDatabase(NativeDatabase(tmp)));
    while (!a.loaded) { await Future.delayed(const Duration(milliseconds: 20)); }
    final my = a.myTeam!;
    print('日付 ${a.currentDate} 自球団 ${my.name}');
    final all = [for (final t in a.teams.where((t) => t.league == 'CL' || t.league == 'PL')) for (final p in t.players) if (p.isPitcher && p.seasonStats.inningsPitched >= 30) (t, p)];
    print('■ 自球団');
    for (final (t, p) in all.where((x) => x.$1.id == my.id).toList()..sort((x, y) => y.$2.ovr.compareTo(x.$2.ovr))) { print(line(p, t.shortName)); }
    print('■ 他球団 OVR上位15');
    for (final (t, p) in (all.where((x) => x.$1.id != my.id).toList()..sort((x, y) => y.$2.ovr.compareTo(x.$2.ovr))).take(15)) { print(line(p, t.shortName)); }
    for (final lo in [60, 65, 70, 75, 80, 85]) {
      for (final mine in [true, false]) {
        final l = all.where((x) => (x.$1.id == my.id) == mine && x.$2.ovr >= lo && x.$2.ovr < lo + 5).map((x) => x.$2).toList();
        if (l.isEmpty) continue;
        final ip = l.fold<int>(0, (s, p) => s + p.seasonStats.inningsPitched) / 3, er = l.fold<int>(0, (s, p) => s + p.seasonStats.earnedRuns);
        print('OVR$lo台 ${mine ? '自' : '他'} ${l.length}人 回${ip.round()} 防${(er * 9 / ip).toStringAsFixed(2)}');
      }
    }
  });
}
