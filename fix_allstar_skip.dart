import 'dart:io';

void main() {
  File f = File('lib/providers/app_state.dart');
  String text = f.readAsStringSync();
  
  String search = """
      for (var m in todaysMatches) {
        if (m.homeScore != null) continue;
        Team hTeam = teams.firstWhere((t) => t.id == m.homeTeamId);
""";
  String replace = """
      for (var m in todaysMatches) {
        if (m.homeScore != null) continue;
        if (m.matchType == 'ALLSTAR') {
          m.isPlayed = true;
          m.homeScore = 0;
          m.awayScore = 0;
          continue;
        }
        Team hTeam = teams.firstWhere((t) => t.id == m.homeTeamId, orElse: () => teams.first);
""";
  text = text.replaceAll(search, replace);

  f.writeAsStringSync(text);
}
