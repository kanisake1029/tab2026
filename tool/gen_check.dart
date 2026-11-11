// 新規チーム自動生成の検証: OVR平均・年齢平均・構成・変化球
// 実行: dart run tool/gen_check.dart [チーム数]
import 'package:npb_pennant_app/utils/player_generator.dart';
import 'package:npb_pennant_app/utils/salary_utils.dart';
void main(List<String> args) {
  final n = args.isNotEmpty ? int.parse(args[0]) : 300;
  double ovr = 0, age = 0, startOvr = 0; int cnt = 0, bad = 0, startCnt = 0;
  for (var i = 0; i < n; i++) {
    final t = generateNewTeam(year: 2026);
    if (t.players.length != 67 || t.players.where((p) => p.isPitcher).length != 35) bad++;
    for (final p in t.players) {
      ovr += p.ovr; age += p.age; cnt++;
      if (p.isPitcher && p.pitches.length != 4) bad++;
      if (!p.isPitcher && p.fieldSS != 60) bad++;
      if (p.mainPos.isEmpty) bad++;
    }
    for (final l in t.lineup) { startOvr += t.players.firstWhere((p) => p.id == l.playerId).ovr; startCnt++; }
    if (t.lineup.length != 9 || t.activeRotation.contains('') || t.winningPattern.contains('') || t.active26.length != 26 || t.roster1G.length != 31) bad++;
  }
  print('チーム$n  OVR平均 ${(ovr / cnt).toStringAsFixed(1)}  年齢平均 ${(age / cnt).toStringAsFixed(1)}  スタメンOVR平均 ${(startOvr / startCnt).toStringAsFixed(1)}  構成の異常 $bad');
  final ex = generateNewTeam(year: 2026);
  final pay = ex.players.fold<int>(0, (s, p) => s + p.salary);
  final act = ex.players.where((p) => ex.active26.contains(p.id));
  print('例: ${ex.name}  年俸総額 ${formatSalary(pay)}  ベンチ入り 投${act.where((p) => p.isPitcher).length}/野${act.where((p) => !p.isPitcher).length}  '
      '成長タイプ ${ex.players.map((p) => p.growthType).toSet().map((g) => '$g${ex.players.where((p) => p.growthType == g).length}').join(' ')}');
}
