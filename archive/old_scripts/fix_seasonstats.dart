import 'dart:io';

void main() {
  File f = File('lib/engine/match_simulator.dart');
  String text = f.readAsStringSync();
  
  text = text.replaceAll(
    "bStats['ab'] = (bStats['ab'] ?? 0) + 1;",
    "bStats['ab'] = (bStats['ab'] ?? 0) + 1; batter.seasonStats.atBats++;"
  );
  
  String search = """
    homePitcher.seasonStats.inningsPitched += 27;
    awayPitcher.seasonStats.inningsPitched += 27;
""";
  String replace = """
    for (var p in homeOrder) { p.seasonStats.games++; }
    for (var p in awayOrder) { p.seasonStats.games++; }
    homePitcher.seasonStats.games++;
    awayPitcher.seasonStats.games++;
    homePitcher.seasonStats.inningsPitched += 27;
    awayPitcher.seasonStats.inningsPitched += 27;
""";
  text = text.replaceAll(search, replace);

  f.writeAsStringSync(text);
}
