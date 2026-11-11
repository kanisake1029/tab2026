import 'dart:math';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/db/app_database.dart';
import 'package:npb_pennant_app/engine/foreign_engine.dart';
import 'package:npb_pennant_app/engine/transfer_engine.dart';
import 'package:npb_pennant_app/models/player.dart';
import 'package:npb_pennant_app/providers/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AppState> boot(AppDatabase db) async {
  final a = AppState(db);
  while (!a.loaded) {
    await Future.delayed(const Duration(milliseconds: 10));
  }
  return a;
}

/// 仕様書 3章：ポスティング・海外FA・提携枠
void main() {
  test('提携枠：候補の質は流出した選手に釣り合い、外国人枠とは別枠', () async {
    SharedPreferences.setMockInitialValues({});
    final a = await boot(AppDatabase(NativeDatabase.memory()));
    a.myTeamId = a.teams[1].id;
    final r = Random(1);
    double avg(List<Player> l) => l.map((p) => p.ovr + p.talent).reduce((x, y) => x + y) / l.length;
    final hi = ForeignEngine.partnerProspects(2026, r, 85, 'X', count: 30), lo = ForeignEngine.partnerProspects(2026, r, 68, 'X', count: 30);
    expect(avg(hi), greaterThan(avg(lo)), reason: '価値の高い選手の流出ほど、よい候補');
    expect(hi.every((p) => p.age <= 25), true); // 候補は25歳以下
    // 申し出：受ければ提携選手として入り、外国人枠に数えない
    final my = a.myTeam!;
    final slot = <String, dynamic>{'team': my.id, 'mlb': 'テスト球団', 'from': 'A', 'cands': [for (final c in lo.take(5)) c.toJson()], 'declined': <String>[]};
    a.partnerSlots.add(slot);
    String? res = 'x';
    for (final c in a.partnerCands(slot)) {
      res = a.offerPartner(slot, c, 3);
      if (res == null) break;
    }
    if (res == null) {
      final p = my.players.lastWhere((p) => p.isPartner);
      expect(p.partnerMlb, 'テスト球団');
      expect(p.foreignSlot, false, reason: '提携選手は外国人枠の外');
      expect(a.partnerSlots, isEmpty);
    }
    // 方針：再建中は認めやすい
    final star = my.players.reduce((x, y) => x.ovr > y.ovr ? x : y);
    expect(TransferEngine.postingAllowChance('rebuild', star), greaterThan(TransferEngine.postingAllowChance('contend', star)));
    expect(TransferEngine.postingFee(star), greaterThan(0));
  });
}
