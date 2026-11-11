import 'dart:math';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/db/app_database.dart';
import 'package:npb_pennant_app/engine/roster_engine.dart';
import 'package:npb_pennant_app/engine/transfer_engine.dart';
import 'package:npb_pennant_app/providers/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AppState> boot(AppDatabase db) async {
  final a = AppState(db);
  while (!a.loaded) { await Future.delayed(const Duration(milliseconds: 10)); }
  return a;
}

void main() {
  test('ドラフト会議（抽選・ウェーバー・育成）と入団', () async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase(NativeDatabase.memory());
    final a = await boot(db);
    a.myTeamId = a.teams[1].id; // 支配下に空きのある球団（固有12の一部は70人ちょうど）
    expect(a.draftPending, true, reason: 'ゲーム開始はドラフト会議の日');
    expect(a.prospects.length, 230);
    a.preScoutIfNeeded();
    expect(a.prospects.where((p) => p.reports > 0).length, greaterThan(100), reason: "開始時は前年からの調査が済んでいる");

    final s = a.createDraftSession(); // ゲーム開始直後は、CPU 球団がここで戦力外通告を済ませる
    final before = {for (final t in a.teams) t.id: t.players.length};
    // 1位：自球団は最も評価の高い候補に入札
    final target = s.bestFor(a.myTeamId)!;
    final res = s.bidFirst(target);
    expect(res.any((e) => e.prospect == target), true);
    var guard = 0;
    while (s.stage == 'first' && guard++ < 20) {
      s.bidFirst(s.firstPending.contains(a.myTeamId) ? s.bestFor(a.myTeamId) : null);
    }
    for (final t in a.teams) {
      expect(s.picks.where((p) => p.teamId == t.id && p.round == 1).length, 1, reason: '全球団が1位を1人');
    }
    s.runAll();
    expect(s.stage, 'done');
    for (final t in a.teams) {
      final n = s.picks.where((p) => p.teamId == t.id && !p.ikusei).length;
      expect(n, lessThanOrEqualTo(RosterEngine.freeSlots(t)), reason: '支配下の空きまで');
    }
    a.applyDraft(s);
    expect(a.draftPending, false);
    expect(a.prospects, isEmpty);
    for (final t in a.teams) {
      expect(t.players.length, before[t.id]! + s.picks.where((p) => p.teamId == t.id).length);
      for (final r in t.players.where((p) => p.draftYear == s.year)) {
        expect(t.players.where((p) => p.uniformNumber == r.uniformNumber).length, 1, reason: '${t.name} の新人の背番号が重ならない');
      }
      for (final p in t.players.where((p) => p.ikusei)) {
        expect(p.uniformNumber, greaterThanOrEqualTo(100), reason: '育成は3桁');
        expect(t.roster1G.contains(p.id), false);
      }
    }
    final rookie = a.teams[1].players.firstWhere((p) => p.draftYear == s.year);
    expect(rookie.draftInfo, contains('ドラフト'));
    expect(rookie.proYears, 1, reason: '最初のドラフトの新人は1年目（最初の1月1日は年を取らない）');

    // 保存して読み直せる
    await a.saveData();
    final b = await boot(db);
    expect(b.draftDoneYear, s.year);
    expect(b.teams.first.players.length, a.teams.first.players.length);
  });

  test('トレード・戦力外・自由契約・支配下登録・外国人', () async {
    SharedPreferences.setMockInitialValues({});
    final a = await boot(AppDatabase(NativeDatabase.memory()));
    a.myTeamId = a.teams.first.id;
    final my = a.teams.first, pt = a.teams[1];

    // 釣り合わないトレードは断られる
    final star = (List.of(pt.players.where((p) => !p.ikusei))..sort((x, y) => y.ovr.compareTo(x.ovr))).first;
    final scrub = (List.of(my.players.where((p) => !p.ikusei))..sort((x, y) => x.ovr.compareTo(y.ovr))).first;
    expect(a.proposeTrade(pt, [scrub], [star], 0), isNotNull);
    // 主力を出して控えをもらうなら成立
    final myStar = (List.of(my.players.where((p) => !p.ikusei))..sort((x, y) => y.ovr.compareTo(x.ovr))).first;
    final ptScrub = (List.of(pt.players.where((p) => !p.ikusei))..sort((x, y) => x.ovr.compareTo(y.ovr))).first;
    expect(TransferEngine.tradeRatio(pt, [myStar], [ptScrub], 0), greaterThan(1));
    expect(a.proposeTrade(pt, [myStar], [ptScrub], 0), isNull);
    expect(pt.players.contains(myStar), true);
    expect(my.players.contains(ptScrub), true);
    expect(my.lineup.length, 9);
    expect(my.roster1G.length, 31);

    // 戦力外 → 自由契約 → 他球団が契約できる
    final cut = my.players.firstWhere((p) => !my.roster1G.contains(p.id));
    expect(a.releasePlayer(cut), isNull);
    expect(my.players.contains(cut), false);
    expect(a.freeAgents.any((f) => f.player == cut), true);

    // 育成契約 → 支配下登録
    final fa = a.freeAgents.firstWhere((f) => f.player == cut);
    expect(a.signFreeAgent(fa, ikusei: true), isNull);
    expect(cut.ikusei, true);
    expect(cut.uniformNumber, greaterThanOrEqualTo(100));
    expect(a.promoteIkusei(cut), isNull);
    expect(cut.ikusei, false);
    expect(cut.uniformNumber, lessThan(100));

    // 外国人
    a.foreignPool = TransferEngine.foreignMarket(2026, Random(5));
    final f = a.foreignPool.first;
    while (RosterEngine.freeSlots(my) <= 0) {
      a.releasePlayer(my.players.firstWhere((p) => !my.roster1G.contains(p.id)));
    }
    expect(a.signForeign(f), isNull);
    expect(my.players.contains(f), true);
    expect(f.nationality, '海外');
  });
}

