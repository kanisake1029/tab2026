import 'dart:convert';

/// 固有12の初期データの書き出し形式（容量を減らすため字下げなし。選手1人を1行にして、差分を見やすくする）
String encodeInitialTeams(List<dynamic> teams) {
  final out = StringBuffer('[\n');
  for (var i = 0; i < teams.length; i++) {
    final t = Map<String, dynamic>.from(teams[i] as Map);
    final players = (t['players'] as List?) ?? const [];
    t['players'] = '__PLAYERS__';
    final head = jsonEncode(t);
    out.write(head.replaceFirst('"__PLAYERS__"', '[\n${players.map(jsonEncode).join(',\n')}\n]'));
    out.write(i < teams.length - 1 ? ',\n' : '\n');
  }
  out.write(']');
  return out.toString();
}

/// initial_teams_data.dart のソース全体
String initialTeamsSource(List<dynamic> teams) => "class InitialTeamsData {\n  static const String jsonString = r'''\n${encodeInitialTeams(teams)}\n''';\n}\n";
