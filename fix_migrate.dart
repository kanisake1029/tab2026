import 'dart:io';

void main() {
  File f = File('lib/providers/app_state.dart');
  String text = f.readAsStringSync();
  
  String search = "if (p.isPitcher && p.pitches.length == 1 && p.pitches.first.name == 'スライダー') {";
  String replace = "if (p.isPitcher && p.pitches.length <= 1) {";
  text = text.replaceAll(search, replace);

  f.writeAsStringSync(text);
}
