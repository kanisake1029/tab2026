import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/db/app_database.dart';
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

/// 仕様書 docs/transfer_system_spec.md の1〜2章：国内FA 8年・補償・1.5位／2.5位・育成の折り返し
void main() {
  test('補償の金額（①指名権＋金銭／②金銭のみ、2回目以降は①の金銭が半分）', () {
    expect(CompCase('a', 'A', 'x', 'y', 10000).money(true), 5000);
    expect(CompCase('a', 'A', 'x', 'y', 10000).money(false), 10000);
    expect(CompCase('a', 'B', 'x', 'y', 10000).money(true), 4000);
    expect(CompCase('a', 'B', 'x', 'y', 10000).money(false), 8000);
    expect(CompCase('a', 'C', 'x', 'y', 10000).money(false), 3000);
    expect(CompCase('a', 'C', 'x', 'y', 10000).hasPick, false);
    expect(CompCase('a', 'A', 'x', 'y', 10000, repeat: true).money(true), 2500);
    expect(CompCase('a', 'B', 'x', 'y', 10000, repeat: true).money(true), 2000);
    expect(Player.faYears, 8);
  });

  test('ドラフト：1位 → 1.5位 → 2位 → 2.5位 → 3位…、育成は折り返し', () async {
    SharedPreferences.setMockInitialValues({});
    final a = await boot(AppDatabase(NativeDatabase.memory()));
    a.myTeamId = a.teams[1].id;
    // 年俸ランク：リーグ全体の順位
    final all = a.teams.expand((t) => t.players).where((p) => !p.ikusei && !p.foreignSlot).toList()..sort((x, y) => y.salary.compareTo(x.salary));
    expect(TransferEngine.faRank(a.teams, all.first), 'A');
    expect(TransferEngine.faRank(a.teams, all[60]), 'B');
    expect(TransferEngine.faRank(a.teams, all.last), 'C');

    final x = a.teams[2].id, y = a.teams[3].id;
    a.compPicks = {x: [2, 0], y: [1, 1]};
    final s = a.createDraftSession();
    s.runAll();
    expect(s.stage, 'done');
    final main = s.picks.where((p) => !p.ikusei).toList();
    final c15 = main.where((p) => p.comp && p.round == 1).toList();
    final c25 = main.where((p) => p.comp && p.round == 2).toList();
    expect(c15.where((p) => p.teamId == x).length, 2, reason: '1.5位を2枠');
    expect(c15.where((p) => p.teamId == y).length, 1);
    expect(c25.length, 1);
    expect(c25.single.teamId, y);
    expect(c15.first.label, '1.5位');
    expect(c25.first.label, '2.5位');
    // 並び：1位がすべて → 1.5位 → 2位 → 2.5位 → 3位
    int idx(bool Function(dynamic p) f) => main.indexWhere((p) => f(p));
    int last(bool Function(dynamic p) f) => main.lastIndexWhere((p) => f(p));
    expect(last((p) => p.round == 1 && !p.comp), lessThan(idx((p) => p.comp && p.round == 1)));
    expect(last((p) => p.comp && p.round == 1), lessThan(idx((p) => p.round == 2 && !p.comp)));
    expect(last((p) => p.round == 2 && !p.comp), lessThan(idx((p) => p.comp && p.round == 2)));
    if (main.any((p) => p.round == 3)) expect(last((p) => p.comp && p.round == 2), lessThan(idx((p) => p.round == 3)));
    // 育成：1巡目は下位から、2巡目は上位から
    final ik1 = s.picks.where((p) => p.ikusei && p.round == 1).toList();
    final ik2 = s.picks.where((p) => p.ikusei && p.round == 2).toList();
    if (ik1.length > 1 && ik2.length > 1) {
      final w = s.waiver;
      expect(w.indexOf(ik1.first.teamId) <= w.indexOf(ik1.last.teamId), true);
      expect(w.indexOf(ik2.first.teamId) >= w.indexOf(ik2.last.teamId), true);
    }
    a.applyDraft(s);
    expect(a.compPicks, isEmpty, reason: '補償の指名権はそのドラフトで使い切る');
    final p15 = a.teams.expand((t) => t.players).firstWhere((p) => p.draftInfo.contains('1.5位'));
    expect(p15.draftInfo, contains('1.5位'));
  });
}
