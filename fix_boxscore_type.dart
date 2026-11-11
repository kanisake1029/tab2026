import 'dart:io';

void main() {
  File f = File('lib/utils/schedule_generator.dart');
  String text = f.readAsStringSync();
  text = text.replaceAll("Map<String, dynamic>? boxScore;", "dynamic boxScore;");
  f.writeAsStringSync(text);
  
  File p = File('lib/engine/match_simulator.dart');
  String pText = p.readAsStringSync();
  pText = pText.replaceAll("final Map<String, dynamic> boxScore;", "final dynamic boxScore;");
  p.writeAsStringSync(pText);
}
