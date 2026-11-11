import 'dart:io';

void main() {
  File f = File('lib/providers/app_state.dart');
  String text = f.readAsStringSync();
  
  if (!text.contains("void resetSeason()")) {
    String newMethod = """
  void resetSeason() {
    for (var t in teams) {
      t.wins = 0;
      t.losses = 0;
      t.draws = 0;
      for (var p in t.players) {
        p.seasonStats = PlayerStats();
      }
    }
    _generateSchedule();
    updateAndSave();
  }

  void updateAndSave() {
""";
    text = text.replaceAll("  void updateAndSave() {", newMethod);
    f.writeAsStringSync(text);
    print("Added resetSeason()");
  } else {
    print("Already added.");
  }
}
