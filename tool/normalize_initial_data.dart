// 固有12球団の初期データを整備して lib/utils/initial_teams_data.dart を再生成する（整備用）
//  第2弾: 有効なJSON / mainPos 明示 / 守備適性すべて60 / 生年月日 = 2026 − 年齢 / スタメンを本職で再作成（済み）
//  第3弾:
//   - 先発ローテ人数 rotationCount = 6、手動ベンチ外 manualBenchOut = []
//   - 1軍31人 = 投手18（先発6＋方程式3＋中継ぎ9）＋野手13（スタメン9＋控え捕手＋控え3）
//     → 今日投げない先発5人が自動でベンチ外になり、ベンチ入りは投手13＋野手13
//   - 体力・回復力・怪我しにくさ・信頼・調子の波・成長タイプ・年俸を固定シードで決めて保存
// 実行: dart run tool/normalize_initial_data.dart
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:npb_pennant_app/models/player.dart';
import 'package:npb_pennant_app/models/team.dart';
import 'package:npb_pennant_app/utils/initial_teams_data.dart';
import 'package:npb_pennant_app/utils/player_traits.dart';
import 'package:npb_pennant_app/utils/initial_data_format.dart';
import 'package:npb_pennant_app/utils/salary_utils.dart';

void main() {
  final teams = (jsonDecode(InitialTeamsData.jsonString) as List).map<Team>((t) => Team.fromJson(t, Player.fromJson)).toList();
  final rnd = Random(20260401); // 固定シード（何度実行しても同じ値になる）
  for (final t in teams) {
    for (final p in t.players) {
      assignTraits(p, rnd);
    }
    final pit = t.players.where((p) => p.isPitcher).toList()..sort((a, b) => b.ovr.compareTo(a.ovr));
    final fld = t.players.where((p) => !p.isPitcher).toList()..sort((a, b) => b.ovr.compareTo(a.ovr));
    t.rotationCount = 6;
    t.rotationIndex = 0;
    t.manualBenchOut = [];
    final pids = <String>{...t.activeRotation, ...t.winningPattern}..remove('');
    for (final p in pit) { if (pids.length >= 18) break; pids.add(p.id); }
    final fids = <String>{...t.lineup.map((l) => l.playerId)};
    final backupC = fld.where((p) => p.mainPos == '捕手' && !fids.contains(p.id));
    if (backupC.isNotEmpty) fids.add(backupC.first.id);
    for (final p in fld) { if (fids.length >= 13) break; fids.add(p.id); }
    t.roster1G = [...pids, ...fids];
    t.refreshActive26();
  }
  File('lib/utils/initial_teams_data.dart').writeAsStringSync(initialTeamsSource(teams.map((t) => t.toJson()).toList()));
  for (final t in teams) {
    final act = t.players.where((p) => t.active26.contains(p.id));
    final first = t.players.where((p) => t.roster1G.contains(p.id));
    final pay1G = first.fold<int>(0, (s, p) => s + p.salary);
    final payAll = t.players.fold<int>(0, (s, p) => s + p.salary);
    final top = t.players.reduce((a, b) => a.salary >= b.salary ? a : b);
    print('${t.id} 1軍${t.roster1G.length}(投${first.where((p) => p.isPitcher).length}) ベンチ入り${t.active26.length}(投${act.where((p) => p.isPitcher).length}/野${act.where((p) => !p.isPitcher).length}) '
        '年俸総額 ${formatSalary(payAll)}（1軍 ${formatSalary(pay1G)}） 最高 ${top.registeredName} ${formatSalary(top.salary)}(OVR${top.ovr})');
  }
  final all = teams.expand((t) => t.players).toList();
  final sal = all.map((p) => p.salary).toList()..sort();
  print('年俸 中央値 ${formatSalary(sal[sal.length ~/ 2])} / 上位10% ${formatSalary(sal[sal.length * 9 ~/ 10])} / 最低 ${formatSalary(sal.first)} / 最高 ${formatSalary(sal.last)}');
  final gt = <String, int>{};
  for (final p in all) { gt[p.growthType] = (gt[p.growthType] ?? 0) + 1; }
  print('成長タイプ $gt  体力最大値 平均${(all.fold<int>(0, (s, p) => s + p.maxEnergy) / all.length).toStringAsFixed(0)}  回復力 平均${(all.fold<int>(0, (s, p) => s + p.recovery) / all.length).toStringAsFixed(1)}');
}
