import 'dart:io';

void main() {
  File f = File('lib/engine/match_simulator.dart');
  String text = f.readAsStringSync();
  text = text.replaceAll("pPitchPower", "pSharpness");
  f.writeAsStringSync(text);
  print("Patched pPitchPower");
}
