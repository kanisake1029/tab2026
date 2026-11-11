import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/db/app_database.dart';
import 'package:npb_pennant_app/providers/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AppState> boot(AppDatabase db) async {
  final a = AppState(db);
  while (!a.loaded) { await Future.delayed(const Duration(milliseconds: 10)); }
  return a;
}

void main() {
  test('観客・収入・毎月の支出・スポンサー・グッズ', () async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase(NativeDatabase.memory());
    final a = await boot(db);
    a.myTeamId = a.teams.first.id;
    a.autoMode = true;
    a.onTeamChosen();
    expect(a.finances.length, a.teams.length);
    expect(a.myFin!.consultantId, '', reason: '自球団の経営は自分で');
    expect(a.teams.skip(1).every((t) => a.finOf(t).consultantId.isNotEmpty), true, reason: 'CPU 球団はコンサルタントにおまかせ');
    final funds0 = a.myFin!.funds;

    // 公式戦が始まって少し経つまで進める
    var guard = 0;
    while (a.matches.where((m) => m.homeScore != null && m.matchType == 'LEAGUE').length < 60 && guard++ < 300) {
      a.playNextDay();
    }
    final played = a.matches.firstWhere((m) => m.homeScore != null && m.matchType == 'LEAGUE');
    expect(played.boxScore!['attendance'], isA<int>());
    final f = a.myFin!;
    expect(f.season['入場料'] ?? 0, greaterThan(0));
    expect(f.season['選手年俸'] ?? 0, lessThan(0), reason: '毎月1日に年俸を払う');
    expect(f.funds, isNot(funds0));

    // スポンサー契約（人気の条件を満たすもの）
    final s = a.sponsorOffers.where((s) => s.minPopularity <= f.popularity).firstOrNull;
    if (s != null && f.sponsors.length < 6) {
      expect(a.signSponsor(s), isNull);
      expect(f.sponsors.contains(s), true);
    }
    // グッズ企画：30日後に売上が決まる
    expect(a.launchGoods('記念グッズ', null), isNull);
    final g = f.goods.last;
    expect(g.done, false);
    final end = a.currentDate.add(const Duration(days: 32));
    guard = 0;
    while (a.currentDate.isBefore(end) && guard++ < 60) {
      a.playNextDay();
    }
    expect(g.done, true);
    expect(g.revenue, greaterThan(0));

    // 保存して読み直せる
    await a.saveData();
    final b = await boot(db);
    expect(b.finances[a.myTeamId]!.funds, f.funds);
    expect(b.finances[a.myTeamId]!.goods.length, f.goods.length);
  }, timeout: const Timeout(Duration(minutes: 10)));

  test('解任とオファー', () async {
    SharedPreferences.setMockInitialValues({});
    final a = await boot(AppDatabase(NativeDatabase.memory()));
    a.myTeamId = a.teams.first.id;
    a.autoMode = true;
    a.onTeamChosen();
    var guard = 0;
    while (!a.seasonOver && guard++ < 450) {
      a.playNextDay();
    }
    // 満足度が低いまま2年続いた形にして、シーズンを締める
    a.autoMode = false;
    a.ownerFiring = true;
    a.myFin!.ownerSat = -100; // シーズンの評価と平均しても35未満になるように
    a.myFin!.satHistory = [10];
    final r = await a.finishSeason();
    expect(r!.finance!.fired, true);
    expect(a.fired, true);
    expect(a.firedOffers, isNotEmpty);
    final date = a.currentDate;
    a.playNextDay();
    expect(a.currentDate, date, reason: '行き先を選ぶまで進まない');
    final old = a.myTeamId;
    a.acceptOffer(a.firedOffers.first);
    expect(a.myTeamId, isNot(old));
    expect(a.fired, false);
    expect(a.staffOf(a.myTeam!)['監督'], isNull, reason: '新しい球団の監督はユーザー');
    expect(a.staffOf(a.teamById(old)!)['監督'], isNotNull, reason: '元の球団には CPU の監督');
  }, timeout: const Timeout(Duration(minutes: 10)));

  test('解任のあと1年浪人して、オフに打診を受ける', () async {
    SharedPreferences.setMockInitialValues({});
    final a = await boot(AppDatabase(NativeDatabase.memory()));
    a.myTeamId = a.teams.first.id;
    a.autoMode = true;
    a.onTeamChosen();
    var guard = 0;
    while (!a.seasonOver && guard++ < 450) {
      a.playNextDay();
    }
    a.autoMode = false;
    a.ownerFiring = true;
    a.myFin!.ownerSat = -100;
    a.myFin!.satHistory = [10];
    await a.finishSeason();
    expect(a.fired, true);
    final old = a.myTeamId;
    final year = a.startYear;
    a.goRonin();
    expect(a.ronin, true);
    expect(a.fired, false);
    expect(a.staffOf(a.myTeam!)['監督'], isNotNull, reason: '浪人中は元の球団に CPU の監督');
    await a.roninAdvance();
    expect(a.startYear, year + 1, reason: '1シーズン進む');
    expect(a.roninReturn, true);
    expect(a.fired, true, reason: '打診を選ぶまで止まる');
    expect(a.firedOffers, isNotEmpty);
    final pick = a.firedOffers.firstWhere((id) => id != old, orElse: () => a.firedOffers.first);
    a.acceptOffer(pick);
    expect(a.ronin, false);
    expect(a.myTeamId, pick);
    expect(a.staffOf(a.myTeam!)['監督'], isNull);
  }, timeout: const Timeout(Duration(minutes: 15)));
}
