import 'dart:io';

void main() {
  File f = File('lib/engine/match_simulator.dart');
  String text = f.readAsStringSync();
  
  text = text.replaceAll(
    "List<int> homeInningScores = List.filled(9, 0);",
    "List<int> homeInningScores = List.filled(9, 0, growable: true);"
  );
  text = text.replaceAll(
    "List<int> awayInningScores = List.filled(9, 0);",
    "List<int> awayInningScores = List.filled(9, 0, growable: true);"
  );
  
  // Also fix the double play bug while we're at it
  String dpSearch = """
                 state.addOut();
                 if (state.outs < 3) state.addOut();
""";
  String dpReplace = """
                 int outsBefore = state.outs;
                 state.addOut();
                 if (outsBefore < 2) state.addOut();
""";
  text = text.replaceAll(dpSearch, dpReplace);

  f.writeAsStringSync(text);
}
