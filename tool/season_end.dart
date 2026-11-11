import 'dart:convert';
import '../lib/models/team.dart';
import '../lib/models/player.dart';
import '../lib/utils/initial_teams_data.dart';
import '../lib/utils/schedule_generator.dart';

void main() {
  final s = InitialTeamsData.jsonString.replaceAllMapped(RegExp(r',(\s*[\]}])'), (m) => m[1]!);
  final teams = (jsonDecode(s) as List).map<Team>((t) => Team.fromJson(t, Player.fromJson)).toList();
  for (final y in [2026, 2027]) {
    final ms = ScheduleGenerator.generateSeasonSchedule(y, teams);
    ms.sort((a, b) => a.date.compareTo(b.date));
    final types = <String, int>{};
    for (final m in ms) { types[m.matchType] = (types[m.matchType] ?? 0) + 1; }
    print('$y: ${ms.length} games, ${ms.first.date} .. ${ms.last.date}  $types');
    final per = <String, int>{};
    for (final m in ms) { if (m.matchType == 'ALLSTAR') continue; per[m.homeTeamId] = (per[m.homeTeamId] ?? 0) + 1; per[m.awayTeamId] = (per[m.awayTeamId] ?? 0) + 1; }
    print('  per-team games: ${per.values.toSet()}');
  }
}
