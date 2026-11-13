import 'dart:convert';
import 'dart:io';
import 'lib/utils/data_generator.dart';

void main() {
  var teams = DataGenerator.generateInitialData();
  String jsonStr = JsonEncoder.withIndent('  ').convert(teams.map((t) => t.toJson()).toList());
  
  String fileContent = "class InitialTeamsData {\n  static const String jsonString = r'''\n" + jsonStr + "\n''';\n}\n";

  File('lib/utils/initial_teams_data.dart').writeAsStringSync(fileContent);
  print("Generated formatted initial_teams_data.dart");
}
