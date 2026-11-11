import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/db/app_database.dart';
import 'package:npb_pennant_app/engine/finance_engine.dart';
import 'package:npb_pennant_app/providers/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final src = File('backup/s25_20261017.sqlite');
  test('スポンサー：12月1日に大・中・地方の候補、12月は来季の契約・更新、1月1日から始まる', () async {
    SharedPreferences.setMockInitialValues({});
    final tmp = File('${Directory.systemTemp.path}/s25_sponsor.sqlite');
    await src.copy(tmp.path);
    final a = AppState(AppDatabase(NativeDatabase(tmp)));
    while (!a.loaded) { await Future.delayed(const Duration(milliseconds: 20)); }
    a.autoMode = true;
    while (!(a.currentDate.month == 12 && a.currentDate.day >= 1) ) { a.playNextDay(); }
    expect(a.currentDate.month, 12);
    final tiers = <String, int>{};
    for (final s in a.sponsorOffers) { tiers[s.tier] = (tiers[s.tier] ?? 0) + 1; }
    // ignore: avoid_print
    print('12/1 の候補 ${a.sponsorOffers.length}社 $tiers');
    expect(a.sponsorOffers.length, 40);
    final f = a.finOf(a.myTeam!);
    // ignore: avoid_print
    print('自球団 人気${f.popularity} 契約：${f.sponsors.map((s) => '${s.name}(${s.tier} 残${s.years}年)').join('、')}　来季の枠 ${a.sponsorSlotsUsed(f)}');
    // 満了する契約を更新
    final exp = f.sponsors.where(a.canRenewSponsor).toList();
    if (exp.isNotEmpty) {
      expect(a.renewSponsor(exp.first, 2), isNull);
      expect(f.sponsors.firstWhere((s) => s.name == exp.first.name).years, 3);
    }
    // 新しい契約は来季から
    final cand = a.sponsorOffers.where((s) => s.minPopularity <= f.popularity).first;
    final before = a.sponsorSlotsUsed(f);
    final err = a.signSponsor(cand);
    // ignore: avoid_print
    print('12月の契約 ${cand.name}（${cand.tier}）：${err ?? '来季から'}　来季の枠 $before→${a.sponsorSlotsUsed(f)}');
    if (err == null) expect(cand.pending, isTrue);
    // 1月1日：来季からの契約が始まり、満了した契約が外れる
    while (!(a.currentDate.month == 1)) { a.playNextDay(); }
    expect(f.sponsors.any((s) => s.pending), isFalse);
    expect(f.sponsors.length, lessThanOrEqualTo(FinanceEngine.maxSponsors));
    // ignore: avoid_print
    print('1/1 契約：${f.sponsors.map((s) => '${s.name}(${s.tier} 残${s.years}年)').join('、')}');
    final cpu = a.teams.where((t) => t.id != a.myTeamId).map((t) => '${t.shortName}${a.finOf(t).sponsors.length}').join(' ');
    // ignore: avoid_print
    print('他球団のスポンサー数 $cpu　残りの候補 ${a.sponsorOffers.length}社');
  }, timeout: const Timeout(Duration(minutes: 5)), skip: !src.existsSync());
}
