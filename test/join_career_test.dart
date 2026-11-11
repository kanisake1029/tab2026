import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/db/app_database.dart';
import 'package:npb_pennant_app/providers/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ゲームの中で入団した選手（ドラフト・入団時の記録がある）に、ありもしない開始前の推定の経歴が出ない
void main() {
  final src = File('backup/s25_20261017.sqlite');
  test('ゲームの中で入団した選手には、開始前の推定の年度が無い', () async {
    SharedPreferences.setMockInitialValues({});
    final tmp = File('${Directory.systemTemp.path}/s25_join.sqlite');
    await src.copy(tmp.path);
    final a = AppState(AppDatabase(NativeDatabase(tmp)));
    while (!a.loaded) {
      await Future.delayed(const Duration(milliseconds: 20));
    }
    final joined = [for (final t in a.teams) for (final p in t.players) if (p.joinedInGame) p];
    final pre = await a.preCareers();
    final withPre = joined.where((p) => pre.containsKey(p.id)).toList();
    final estimated = joined.where((p) => p.careerEstimated).toList();
    // ignore: avoid_print
    print('ゲームの中で入団 ${joined.length}人 / 開始前の推定あり ${withPre.length}人 / 推定の通算 ${estimated.length}人 / 開始前の推定がある選手（全体）${pre.length}人');
    expect(withPre, isEmpty);
    expect(estimated, isEmpty);
  }, skip: !src.existsSync());
}
