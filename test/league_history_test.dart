import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/db/app_database.dart';
import 'package:npb_pennant_app/providers/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ゲーム開始前の架空の歴史：タイトルはそれらしい成績でしか取れない（11本で本塁打王にならない）。年ごとの成績に波がある
void main() {
  test('架空の歴史と年度ごとの推定', () async {
    SharedPreferences.setMockInitialValues({});
    final tmp = File('${Directory.systemTemp.path}/s25_hist.sqlite');
    await File('backup/s25_20261017.sqlite').copy(tmp.path);
    final a = AppState(AppDatabase(NativeDatabase(tmp)));
    while (!a.loaded) {
      await Future.delayed(const Duration(milliseconds: 20));
    }
    final pre = await a.preCareers();
    final h = a.leagueHistory!;
    expect(h.years, isNotEmpty);
    var own = 0;
    for (final y in h.years.entries) {
      for (final lg in y.value.entries) {
        for (final e in lg.value.entries) {
          if (e.value.playerId != null) own++;
          final m = RegExp(r'(\d+)本$').firstMatch(e.value.text);
          if (e.key == '本塁打王' && m != null) expect(int.parse(m.group(1)!), greaterThanOrEqualTo(25), reason: '${y.key} ${e.value.text}');
        }
      }
    }
    final years = h.years.keys.toList()..sort();
    // ignore: avoid_print
    print('歴史 ${years.first}〜${years.last}　今いる選手の受賞 $own');
    // ignore: avoid_print
    print(h.years[years.last]!.map((k, v) => MapEntry(k, {for (final e in v.entries.take(6)) e.key: e.value.text})));
    // 年ごとの波：長くいる打者の打率の幅
    final long = pre.entries.where((e) => e.value.length >= 8).toList();
    expect(long, isNotEmpty);
    final ys = long.first.value;
    // ignore: avoid_print
    print([for (final y in ys) '${y.year}:${y.stats.games}試合 ${y.stats.atBats == 0 ? '-' : y.stats.battingAverage.toStringAsFixed(3)} ${y.stats.homeRuns}本 ${y.stats.wins}勝 ${y.stats.era.toStringAsFixed(2)}'].join(' / '));
  });
}
