import 'dart:convert';
import 'dart:io';
import 'lib/utils/data_generator.dart';

void main() {
  var teams = DataGenerator.generateInitialData();
  String jsonStr = jsonEncode(teams.map((t) => t.toJson()).toList());
  
  String fileContent = """
class InitialTeamsData {
  static const String jsonString = r'''
\$jsonStr
''';
}
""";

  File('lib/utils/initial_teams_data.dart').writeAsStringSync(fileContent);
  print("Generated initial_teams_data.dart");
}
