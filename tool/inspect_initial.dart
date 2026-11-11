import 'dart:convert';
import 'package:npb_pennant_app/models/player.dart';
import 'package:npb_pennant_app/models/team.dart';
import 'package:npb_pennant_app/utils/initial_teams_data.dart';
void main() {
  final teams = (jsonDecode(InitialTeamsData.jsonString.replaceAllMapped(RegExp(r',(\s*[\]}])'), (m) => m[1]!)) as List).map<Team>((t) => Team.fromJson(t, Player.fromJson)).toList();
  for (final t in teams) {
    final pit = t.players.where((p) => p.isPitcher).length;
    final cnt = <String, int>{};
    for (final p in t.players.where((p) => !p.isPitcher)) { cnt[p.mainPosition] = (cnt[p.mainPosition] ?? 0) + 1; }
    final nums = t.players.map((p) => p.uniformNumber).toList();
    final dup = nums.length - nums.toSet().length;
    final ages = t.players.map((p) => p.age);
    print('${t.id} ${t.name} 計${t.players.length} 投$pit 野手$cnt 背番号0:${nums.where((n) => n == 0).length} 重複$dup 最大${nums.reduce((a, b) => a > b ? a : b)} 年齢平均${(ages.reduce((a, b) => a + b) / ages.length).toStringAsFixed(1)} roster1G${t.roster1G.length} active${t.active26.length} rot${t.rotation.length} lineup${t.lineup.length}');
  }
  final p = teams.first.players.first;
  print('例 ${p.registeredName} age${p.age} birth${p.birthDate} pro${p.proYears} draft${p.draftType} num${p.uniformNumber}');
}
