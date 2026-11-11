import 'dart:convert';
import 'package:npb_pennant_app/models/player.dart';
import 'package:npb_pennant_app/models/team.dart';
import 'package:npb_pennant_app/utils/initial_teams_data.dart';
double avg(Iterable<num> xs) => xs.isEmpty ? 0 : xs.fold<double>(0, (a, b) => a + b) / xs.length;
void main() {
  final teams = (jsonDecode(InitialTeamsData.jsonString.replaceAllMapped(RegExp(r',(\s*[\]}])'), (m) => m[1]!)) as List).map<Team>((t) => Team.fromJson(t, Player.fromJson)).toList();
  final starters = <Player>[];
  final posStat = <int>[];
  for (final t in teams) {
    for (final l in t.lineup) {
      final p = t.players.firstWhere((p) => p.id == l.playerId);
      starters.add(p);
      final f = {'捕': p.fieldC, '一': p.field1B, '二': p.field2B, '三': p.field3B, '遊': p.fieldSS, '左': p.fieldLF, '中': p.fieldCF, '右': p.fieldRF}[l.position];
      if (f != null) posStat.add(f);
    }
  }
  print('スタメン n=${starters.length} contact ${avg(starters.map((p) => p.contact)).toStringAsFixed(1)} power ${avg(starters.map((p) => p.power)).toStringAsFixed(1)} eye ${avg(starters.map((p) => p.eye)).toStringAsFixed(1)} run ${avg(starters.map((p) => p.run)).toStringAsFixed(1)} traj ${avg(starters.map((p) => p.trajectory)).toStringAsFixed(2)} 守備(担当位置) ${avg(posStat).toStringAsFixed(1)}');
  final sps = <Player>[];
  for (final t in teams) { if (t.rotation.isNotEmpty) sps.add(t.players.firstWhere((p) => p.id == t.rotation.first)); }
  print('先発1番手 n=${sps.length} ovr ${avg(sps.map((p) => p.ovr)).toStringAsFixed(1)} velocity ${avg(sps.map((p) => p.velocity)).toStringAsFixed(1)} control ${avg(sps.map((p) => p.control)).toStringAsFixed(1)} stamina ${avg(sps.map((p) => p.stamina)).toStringAsFixed(1)} clutchP ${avg(sps.map((p) => p.clutchPitching)).toStringAsFixed(1)}');
  final p0 = sps.first;
  print('例 ${p0.registeredName} spinAxis ${p0.spinAxis} height ${p0.height} pitches ${p0.pitches.map((x) => '${x.name}(br${x.breakLevel} sh${x.sharpness} sp${x.speed} r${x.ratio})').join(' ')}');
  print('全投手 sharp平均 ${avg(teams.expand((t) => t.players.where((p) => p.isPitcher).expand((p) => p.pitches.map((x) => x.sharpness)))).toStringAsFixed(1)} break平均 ${avg(teams.expand((t) => t.players.where((p) => p.isPitcher).expand((p) => p.pitches.map((x) => x.breakLevel)))).toStringAsFixed(1)}');
}
