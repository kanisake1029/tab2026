import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/db/app_database.dart';
import 'package:npb_pennant_app/providers/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 自動の継投：先発の球数・イニング、中継ぎの登板の散らばり、ローテ投手の中継ぎ登板
void main() {
  test('自動の継投が偏らない', () async {
    SharedPreferences.setMockInitialValues({});
    final a = AppState(AppDatabase(NativeDatabase.memory()));
    while (!a.loaded) {
      await Future.delayed(const Duration(milliseconds: 10));
    }
    a.myTeamId = a.teams.first.id;
    a.autoMode = true;
    // 開幕から1か月ほど
    var days = 0;
    while (days < 90) {
      a.playNextDay();
      days++;
    }
    var starts = 0, startOuts = 0, rotRelief = 0;
    final relApps = <int>[];
    for (final t in a.leagueTeams) {
      final rot = t.rotation.take(t.rotationCount).where((e) => e.isNotEmpty).toSet();
      final rel = <int>[];
      for (final p in t.players.where((p) => p.isPitcher)) {
        final st = p.seasonStats;
        starts += st.starts;
        if (st.starts > 0) startOuts += st.inningsPitched; // 先発のみの投手が多い前提のおおよそ
        final relief = st.pitchApps - st.starts;
        if (rot.contains(p.id)) rotRelief += relief;
        if (!rot.contains(p.id) && relief > 0) rel.add(relief);
      }
      rel.sort((x, y) => y.compareTo(x));
      relApps.add(rel.length);
      // ignore: avoid_print
      print('${t.shortName}: 中継ぎ登板 $rel');
    }
    final ipPerStart = startOuts / 3 / (starts == 0 ? 1 : starts);
    // ignore: avoid_print
    print('先発1試合の平均投球回 ${ipPerStart.toStringAsFixed(2)}  いまのローテ投手の中継ぎ登板（ローテ入り前の分も含む） $rotRelief  中継ぎを使った人数 $relApps');
    expect(ipPerStart, lessThan(7.0));
    expect(ipPerStart, greaterThan(5.0));
    expect(relApps.every((n) => n >= 5), true);
  }, timeout: const Timeout(Duration(minutes: 10)));
}
