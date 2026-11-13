import 'dart:io';

void main() {
  File f = File('lib/utils/schedule_generator.dart');
  String text = f.readAsStringSync();
  
  // Revert dynamic back to Map<String, dynamic>?
  text = text.replaceAll("dynamic boxScore;", "Map<String, dynamic>? boxScore;");
  
  // Fix fromJson
  text = text.replaceAll(
    "..boxScore = json['boxScore'];",
    "..boxScore = json['boxScore'] != null ? Map<String, dynamic>.from(json['boxScore']) : null;"
  );
  
  f.writeAsStringSync(text);
  
  File p = File('lib/engine/match_simulator.dart');
  String pText = p.readAsStringSync();
  pText = pText.replaceAll("final dynamic boxScore;", "final Map<String, dynamic> boxScore;");
  
  // Fix the inner maps instantiation to explicitly be Map<String, dynamic> instead of Map<dynamic, dynamic>
  String bSearch = """
    Map<String, dynamic> boxScore = {
      'homeBatters': {},
      'awayBatters': {},
      'homePitcher': {},
      'awayPitcher': {}
    };
""";
  String bReplace = """
    Map<String, dynamic> boxScore = {
      'homeBatters': <String, dynamic>{},
      'awayBatters': <String, dynamic>{},
      'homePitcher': <String, dynamic>{},
      'awayPitcher': <String, dynamic>{}
    };
""";
  pText = pText.replaceAll(bSearch, bReplace);
  
  p.writeAsStringSync(pText);
}
