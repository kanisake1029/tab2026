// 固有12の選手名を名前の素材（NamePool）から付け直す
// 使い方: dart run tool/rename_initial_players.dart
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:npb_pennant_app/utils/name_pool.dart';
import 'package:npb_pennant_app/utils/initial_data_format.dart';

void main() {
  final f = File('lib/utils/initial_teams_data.dart');
  final src = f.readAsStringSync();
  final start = src.indexOf('[');
  final end = src.lastIndexOf(']') + 1;
  final teams = jsonDecode(src.substring(start, end)) as List;
  final r = Random(20261006);
  final all = <String>{};
  for (final t in teams) {
    final used = <String>{};
    for (final p in (t['players'] as List)) {
      // 12球団で同姓同名が出ないようにする
      for (var i = 0; i < 20; i++) {
        if (p['nationality'] == '海外') {
          final n = NamePool.foreign(r, avoid: used);
          p['lastName'] = n.last;
          p['firstName'] = n.first;
          p['nameType'] = n.nameType;
        } else {
          p['lastName'] = NamePool.jpLast(r, avoid: used);
          p['firstName'] = NamePool.jpFirst(r);
          p['nameType'] = 'A';
        }
        if (!all.contains('${p['lastName']}${p['firstName']}')) break;
      }
      p['customName'] = '';
      used.add(p['lastName'] as String);
      all.add('${p['lastName']}${p['firstName']}');
    }
  }
  f.writeAsStringSync("${src.substring(0, start)}${encodeInitialTeams(teams)}${src.substring(end)}");
  print('renamed ${all.length} players');
}
