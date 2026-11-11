import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/db/app_database.dart';
import 'package:npb_pennant_app/engine/scout_comment.dart';
import 'package:npb_pennant_app/providers/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('寸評（体格×フォーム×球種×成績）が文章になる', () async {
    SharedPreferences.setMockInitialValues({});
    final a = AppState(AppDatabase(NativeDatabase.memory()));
    while (!a.loaded) {
      await Future.delayed(const Duration(milliseconds: 10));
    }
    final ps = a.teams.expand((t) => t.players).toList();
    final pit = (ps.where((p) => p.isPitcher).toList()..sort((x, y) => y.ovr.compareTo(x.ovr))).take(4);
    final bat = (ps.where((p) => !p.isPitcher).toList()..sort((x, y) => y.ovr.compareTo(x.ovr))).take(5);
    for (final p in [...pit, ...bat]) {
      final t = ScoutComment.of(p);
      // ignore: avoid_print
      print('${p.registeredName}: $t');
      expect(t.length > 20, true);
      expect(t.contains('null'), false);
    }
  });
}
