import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/db/app_database.dart';
import 'package:npb_pennant_app/engine/roster_engine.dart';
import 'package:npb_pennant_app/providers/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ドラフトは、支配下の枠が許す限り何人でも本指名できる／シーズン後のオフでは、会議を開いても CPU の戦力外を重ねない
void main() {
  test('本指名は10人を超えても、枠の数まで指名できる', () async {
    SharedPreferences.setMockInitialValues({});
    final a = AppState(AppDatabase(NativeDatabase.memory()));
    while (!a.loaded) {
      await Future.delayed(const Duration(milliseconds: 10));
    }
    a.myTeamId = a.teams[1].id;
    final my = a.myTeam!;
    // 支配下を空ける：枠を 15 にする
    while (RosterEngine.freeSlots(my) < 15) {
      a.releasePlayer(my.players.where((p) => !p.ikusei).last);
    }
    final s = a.createDraftSession();
    expect(s.slots[a.myTeamId], 15);
    // 1位の入札のあと、自球団の番が来るたびに、残っている候補から1人ずつ指名する
    s.bidFirst(s.pool.firstWhere((p) => !p.ikuseiTier));
    var guard = 0;
    while (s.stage != 'ikusei' && s.stage != 'done' && guard++ < 600) {
      if (s.stage == 'first') {
        // 1位の入札（抽選に外れたら、外れ1位でもう一度入札する）
        s.bidFirst(s.firstPending.contains(a.myTeamId) ? s.pool.firstWhere((p) => !p.ikuseiTier) : null);
      } else if (s.stage == 'comp') {
        s.bidComp(s.myCompPending ? s.autoCompBids(a.myTeamId) : null);
      } else if (s.currentTeamId == a.myTeamId) {
        s.pick(s.pool.firstWhere((p) => !p.ikuseiTier));
      } else {
        s.runUntilMine();
      }
    }
    final rounds = s.picks.where((p) => p.teamId == a.myTeamId && !p.ikusei).map((p) => p.round).toList();
    expect(rounds.length, 15, reason: '枠 15 人ぶんすべて本指名できる（以前は10巡で打ち切り）');
    expect(rounds.reduce((x, y) => x > y ? x : y), greaterThan(10));
  });

  test('シーズン後のオフでは、ドラフト会議を開いても CPU の戦力外通告を重ねない', () async {
    const src = 'backup/s25_20261111_now.sqlite'; // 実機のセーブ（10/31・年度は10/25に切り替わり済み）。無ければ飛ばす
    if (!File(src).existsSync()) {
      markTestSkipped('$src が無いので飛ばす');
      return;
    }
    SharedPreferences.setMockInitialValues({});
    final tmp = File('${Directory.systemTemp.path}/tab_draft_prep_${DateTime.now().microsecondsSinceEpoch}.sqlite');
    await File(src).copy(tmp.path);
    final a = AppState(AppDatabase(NativeDatabase(tmp)));
    while (!a.loaded) {
      await Future.delayed(const Duration(milliseconds: 20));
    }
    expect(a.offAfterSeason, true);
    expect(a.currentDate.year < a.startYear, true, reason: '年度が先に進んでいる（これが以前は「はじめから始めた」と同じ扱いになっていた）');
    final before = a.prepDraftYear;
    final freeBefore = a.freeAgents.length;
    a.createDraftSession();
    expect(a.prepDraftYear, before, reason: '戦力外はシーズン終了時に済んでいる。会議を開いても走らせない');
    expect(a.freeAgents.length, freeBefore);
    await a.db.close();
    tmp.deleteSync();
  });
}
