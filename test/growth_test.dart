import 'dart:math';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/db/app_database.dart';
import 'package:npb_pennant_app/engine/growth_engine.dart';
import 'package:npb_pennant_app/engine/match_simulator.dart';
import 'package:npb_pennant_app/engine/spec_constants.dart';
import 'package:npb_pennant_app/engine/swing_model.dart';
import 'package:npb_pennant_app/engine/tactics.dart';
import 'package:npb_pennant_app/engine/field_time.dart';
import 'package:npb_pennant_app/models/player.dart';
import 'package:npb_pennant_app/models/stadium.dart';
import 'package:npb_pennant_app/providers/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('数シーズン進めて、年度更新と成長が回り、能力がインフレしない', () async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase(NativeDatabase.memory());
    final a = AppState(db);
    while (!a.loaded) { await Future.delayed(const Duration(milliseconds: 10)); }
    a.myTeamId = a.teams.first.id;
    a.autoMode = true;
    a.onTeamChosen();
    final n = const int.fromEnvironment('SEASONS', defaultValue: 4);
    const vbat = String.fromEnvironment('VBAT');
    if (vbat.isNotEmpty) MatchSimulator.batSpeedBase = double.parse(vbat);
    const ps = String.fromEnvironment('PSLOPE'), mf = String.fromEnvironment('MFLOOR');
    if (ps.isNotEmpty) MatchSimulator.powerSlope = double.parse(ps);
    if (mf.isNotEmpty) MatchSimulator.mishitFloor = double.parse(mf);
    const ce = String.fromEnvironment('CEASE'), ch = String.fromEnvironment('CHASE');
    if (ce.isNotEmpty) MatchSimulator.contactEase = double.parse(ce);
    if (ch.isNotEmpty) MatchSimulator.chaseBase = double.parse(ch);
    const cut = String.fromEnvironment('CUT'), fpt = String.fromEnvironment('FPT');
    if (cut.isNotEmpty) MatchSimulator.cutBase = double.parse(cut);
    if (fpt.isNotEmpty) MatchSimulator.firstPitchTake = double.parse(fpt);
    // 経験値の基本の量（調整用）
    const gx = String.fromEnvironment('GAMEXP'), pa = String.fromEnvironment('PAPP'), pi = String.fromEnvironment('PINN'), px = String.fromEnvironment('PRACT');
    if (gx.isNotEmpty) GrowthEngine.gameExpBase = double.parse(gx);
    if (pa.isNotEmpty) GrowthEngine.pitcherAppExp = double.parse(pa);
    if (pi.isNotEmpty) GrowthEngine.pitcherInningExp = double.parse(pi);
    if (px.isNotEmpty) GrowthEngine.practiceExpBase = double.parse(px);
    const sbb = String.fromEnvironment('STEALB'), csr = String.fromEnvironment('CPUSTEAL');
    if (sbb.isNotEmpty) MatchSimulator.stealBase = double.parse(sbb);
    if (csr.isNotEmpty) MatchSimulator.cpuStealRate = double.parse(csr);
    const lk = String.fromEnvironment('LATEK'), phy = String.fromEnvironment('PHYS');
    if (lk.isNotEmpty) MatchSimulator.lateBreakK = double.parse(lk);
    if (phy == '0') MatchSimulator.usePhysics = false;
    const vbs = String.fromEnvironment('VBS'), nsc = String.fromEnvironment('NSC'), msc = String.fromEnvironment('MSC');
    if (vbs.isNotEmpty) SwingModel.vBatScale = double.parse(vbs);
    if (nsc.isNotEmpty) SwingModel.noiseScale = double.parse(nsc);
    if (msc.isNotEmpty) SwingModel.misScale = double.parse(msc);
    double? sdd(String v) => v.isEmpty ? null : double.parse(v);
    Spec.batA = sdd(const String.fromEnvironment('BATA')) ?? Spec.batA;
    Spec.batB = sdd(const String.fromEnvironment('BATB')) ?? Spec.batB;
    Spec.attK = sdd(const String.fromEnvironment('ATTK')) ?? Spec.attK;
    const stb = String.fromEnvironment('STB');
    if (stb.isNotEmpty) StealRace.bias = double.parse(stb);
    const fts = String.fromEnvironment('FTS'), frb = String.fromEnvironment('FRB');
    if (fts.isNotEmpty) Fielding.timeScale = double.parse(fts);
    if (frb.isNotEmpty) Fielding.reachBase = double.parse(frb);
    const turf = String.fromEnvironment('TURF');
    if (turf.isNotEmpty) Stadium.standard.turf = turf;
    for (var y = 0; y < n; y++) {
      var guard = 0;
      while (!a.seasonOver && guard++ < 400) { a.playNextDay(); }
      expect(a.seasonOver, true);
      final yr = a.startYear;
      final farmPlayed = a.farmMatches.where((m) => m.homeScore != null).length;
      final firstPlayed = a.matches.where((m) => (m.homeScore != null || m.cancelled) && !AppState.isSpecialType(m.matchType)).length; // 雨天中止のオープン戦は2軍だけ試合をする
      expect(farmPlayed, firstPlayed, reason: '2軍も1軍と同じ日程で試合をしている');
      {
        final all = [for (final t in a.teams) ...t.players];
        int top(int Function(Player) f) => all.map(f).reduce((x, y) => x > y ? x : y);
        final hr = List.of(all.where((p) => !p.isPitcher))..sort((x, y) => y.seasonStats.homeRuns.compareTo(x.seasonStats.homeRuns));
        for (final p in hr.take(6)) {
          print('    ${p.registeredName} ${p.seasonStats.homeRuns}本 打率${p.seasonStats.battingAverage.toStringAsFixed(3)} 打数${p.seasonStats.atBats} パワー${p.power} ミート${p.contact} 弾道${p.trajectory} ${p.age}歳 ${p.nationality} ${p.draftInfo}');
        }
        final pw = [for (final p in all.where((p) => !p.isPitcher)) p.power]..sort();
        print('    パワー上位 ${pw.reversed.take(15).join(',')}');
        final q = all.where((p) => !p.isPitcher && p.seasonStats.plateAppearances >= 484).toList();
        final qp = all.where((p) => p.isPitcher && p.seasonStats.inningsPitched >= 156 * 3).toList();
        double best(Iterable<double> v, bool hi) => v.isEmpty ? 0 : v.reduce((x, y) => hi ? (x > y ? x : y) : (x < y ? x : y));
        for (final lg in ['CL', 'PL']) {
          final bs = [for (final t in a.teams.where((t) => t.league == lg)) for (final p in t.players) if (!p.isPitcher) p];
          final qb = bs.where((p) => p.seasonStats.plateAppearances >= 484).toList();
          final avgs = qb.map((p) => p.seasonStats.battingAverage).toList()..sort();
          final hrs = bs.map((p) => p.seasonStats.homeRuns).toList()..sort();
          print('  [$lg] 3割 ${avgs.where((v) => v >= 0.3).length}人 首位${avgs.isEmpty ? '-' : avgs.last.toStringAsFixed(3)} 規定${qb.length}人 ／ 30本 ${hrs.where((v) => v >= 30).length}人 20本 ${hrs.where((v) => v >= 20).length}人 HR王${hrs.last} 上位${hrs.reversed.take(8).join(',')}');
        }
        {
          var pa = 0, ab = 0, h = 0, hr = 0, k = 0, bb = 0, sf = 0, d2 = 0;
          for (final p in all.where((p) => !p.isPitcher)) {
            final s = p.seasonStats;
            pa += s.plateAppearances; ab += s.atBats; h += s.hits; hr += s.homeRuns; k += s.strikeouts; bb += s.walks; sf += s.sacFlies; d2 += s.doubles;
          }
          print('  球数/打席${(MatchSimulator.statPitches / max(1, MatchSimulator.statPa)).toStringAsFixed(2)} 三振率${(k / pa * 100).toStringAsFixed(1)}% 四球率${(bb / pa * 100).toStringAsFixed(1)}% BABIP${((h - hr) / (ab - k - hr + sf)).toStringAsFixed(3)} HR/打球${(hr / (ab - k + sf) * 100).toStringAsFixed(1)}% 二塁打$d2');
        }
        print('  首位打者${best(q.map((p) => p.seasonStats.battingAverage), true).toStringAsFixed(3)} 打点王${top((p) => p.seasonStats.rbi)} 防御率1位${best(qp.map((p) => p.seasonStats.era), false).toStringAsFixed(2)} 奪三振${top((p) => p.seasonStats.pitcherStrikeouts)} 規定投球回${qp.length}人');
        final aces = List.of(all.where((p) => p.isPitcher))..sort((x, y) => y.ovr.compareTo(x.ovr));
        print('    エース級 ${aces.take(5).map((p) => '${p.registeredName} ${p.velocity}km 球威${p.pitchPower} 制球${p.control} 防${p.seasonStats.era.toStringAsFixed(2)} ${p.seasonStats.inningsPitched ~/ 3}回').join(' / ')}');
        {
          final all = a.teams.expand((t) => t.players);
          final sb = all.fold<int>(0, (x, p) => x + p.seasonStats.stolenBases), cs = all.fold<int>(0, (x, p) => x + p.seasonStats.caughtStealing);
          final hbp = all.fold<int>(0, (x, p) => x + p.seasonStats.hbp);
          final top = (all.map((p) => p.seasonStats.stolenBases).toList()..sort((x, y) => y.compareTo(x))).take(5).toList();
          print('  盗塁 リーグ計$sb 成功率${(sb / (sb + cs).clamp(1, 1 << 30) * 100).toStringAsFixed(1)}% 上位$top　死球 計$hbp');
        }
        print('  本塁打王${top((p) => p.seasonStats.homeRuns)} 最多セーブ${top((p) => p.seasonStats.saves)} 最多ホールド${top((p) => p.seasonStats.holds)} 最多勝${top((p) => p.seasonStats.wins)} 盗塁王${top((p) => p.seasonStats.stolenBases)}');
      }
      final r = await a.finishSeason();
      expect(r, isNotNull);
      for (final t in a.teams) {
        final f = a.finances[t.id]!;
        final ls = f.lastSeason;
        String oku(int v) => (v / 10000).toStringAsFixed(1);
        print('  ${t.id} ${r!.ranks[t.id]}位 収支${oku(ls.values.fold(0, (x, y) => x + y))}億 資金${oku(f.funds)}億 観客${f.lastAttendance} 人気${f.popularity} 入場${oku(ls['入場料'] ?? 0)} グッズ${oku(ls['グッズ・飲食'] ?? 0)} 放映${oku(ls['放映権'] ?? 0)} スポ${oku(ls['スポンサー'] ?? 0)} 年俸${oku(ls['選手年俸'] ?? 0)} 運営${oku(ls['運営費'] ?? 0)} 価格${f.ticketPrice}');
      }
      if (r!.finance != null) print('  オーナー満足度 ${r.finance!.sat}：${r.finance!.notes.join(' / ')}');
      expect(r!.records.values.every((x) => x[0] + x[1] + x[2] == a.seasonGames), true, reason: '公式戦は1球団${a.seasonGames}試合');
      final s = r.summary;
      final up = r.changes.where((c) => c.ovrDiff > 0).length;
      final down = r.changes.where((c) => c.ovrDiff < 0).length;
      print('$yr: 得点/試合=${(s['runsPerTeamGame'] as num).toStringAsFixed(2)} 打率=${(s['avg'] as num).toStringAsFixed(3)} HR/試合=${(s['hrPerTeamGame'] as num).toStringAsFixed(2)} '
          '野手OVR ${(s['avgOvrBat'] as num).toStringAsFixed(1)}→${(s['avgOvrBatAfter'] as num).toStringAsFixed(1)} 投手OVR ${(s['avgOvrPit'] as num).toStringAsFixed(1)}→${(s['avgOvrPitAfter'] as num).toStringAsFixed(1)} 上昇$up人 下降$down人');
      // 全日程の終了で年度が切り替わり、新しい年度の日程になる。オフ（ドラフト会議 10/31〜）は新しい年度の出来事
      expect(a.startYear, yr + 1);
      expect(a.seasonFinished, false);
      expect(a.offAfterSeason, true);
      expect(a.teams.expand((t) => t.players).every((p) => p.seasonStats.games == 0), true);
      var guard2 = 0;
      var sawDraft = false;
      while (!(a.currentDate.year == yr + 1 && a.currentDate.month == 1) && guard2++ < 40) {
        a.playNextDay();
        if (a.currentDate.month == 10 && a.currentDate.day == 31) sawDraft = true;
      }
      expect(sawDraft, true);
      expect(a.startYear, yr + 1);
      expect(a.seasonFinished, false);
      expect(a.currentDate, DateTime(yr + 1, 1, 1));
      expect(a.offAfterSeason, false); // 1月1日でオフは終わり
      // 選手の入れ替わり（ドラフト・引退・戦力外・FA・外国人）
      final sizes = a.teams.map((t) => t.players.where((p) => !p.ikusei).length).toList();
      final ik = a.teams.fold<int>(0, (s, t) => s + t.players.where((p) => p.ikusei).length);
      final ages = [for (final t in a.teams) for (final p in t.players) p.age];
      double mean(bool pit) { final v = [for (final t in a.teams) for (final p in t.players) if (!p.ikusei && p.isPitcher == pit) p.ovr]; return v.reduce((x, y) => x + y) / v.length; }
      print('  リーグ全体の平均OVR 野手${mean(false).toStringAsFixed(1)} 投手${mean(true).toStringAsFixed(1)} 引退${a.transactions.where((s) => s.contains('引退')).length}');
      List<int> topOvr(bool pit) => (a.teams.expand((t) => t.players).where((p) => p.isPitcher == pit).map((p) => p.ovr).toList()..sort((x, y) => y.compareTo(x))).take(8).toList();
      print('  OVR上位 野手${topOvr(false)} 投手${topOvr(true)}');
      {
        final st = [for (final t in a.teams) for (final l in t.lineup) t.players.firstWhere((p) => p.id == l.playerId)];
        final rot = [for (final t in a.teams) for (final id in t.activeRotation) if (id.isNotEmpty) t.players.firstWhere((p) => p.id == id)];
        double av(Iterable<int> v) => v.reduce((x, y) => x + y) / v.length;
        print('  スタメン ミート${av(st.map((p) => p.contact)).toStringAsFixed(1)} パワー${av(st.map((p) => p.power)).toStringAsFixed(1)} 選球${av(st.map((p) => p.eye)).toStringAsFixed(1)} 年齢${av(st.map((p) => p.age)).toStringAsFixed(1)}'
            ' ／ 先発 球速${av(rot.map((p) => p.velocity)).toStringAsFixed(1)} 球威${av(rot.map((p) => p.pitchPower)).toStringAsFixed(1)} 制球${av(rot.map((p) => p.control)).toStringAsFixed(1)} スタミナ${av(rot.map((p) => p.stamina)).toStringAsFixed(1)} 年齢${av(rot.map((p) => p.age)).toStringAsFixed(1)}');
      }
      final rookies = [for (final t in a.teams) for (final p in t.players) if (p.draftYear == yr) p].length;
      print('  支配下 ${sizes.reduce((x, y) => x < y ? x : y)}〜${sizes.reduce((x, y) => x > y ? x : y)}人 育成計$ik 平均年齢${(ages.reduce((x, y) => x + y) / ages.length).toStringAsFixed(1)} 新人$rookies '
          'FA宣言${a.transactions.where((s) => s.contains('FA 移籍')).length}移籍 記録${a.transactions.length}件 OB${a.obList.length}');
      expect(sizes.every((n) => n <= 70), true, reason: '支配下は70人まで');
      expect(sizes.every((n) => n >= 55), true, reason: '選手が減りすぎない');
      for (final t in a.teams) {
        expect(t.roster1G.length, 31, reason: '${t.name} の1軍は31人');
        expect(t.lineup.length, 9);
        expect(t.players.where((p) => t.roster1G.contains(p.id)).every((p) => !p.ikusei), true, reason: '育成は1軍に入れない');
      }
      expect(a.matches.every((m) => m.homeScore == null), true);
      expect(a.farmMatches.every((m) => m.homeScore == null), true);
    }
    // 年齢別の平均OVR変化（最後の年）
    final byPhase = <String, List<int>>{};
    for (final t in a.teams) {
      for (final p in t.players) { byPhase.putIfAbsent(GrowthEngine.phaseOf(p).label, () => []).add(p.ovr); }
    }
    byPhase.forEach((k, v) => print('$k: ${v.length}人 平均OVR ${(v.reduce((x, y) => x + y) / v.length).toStringAsFixed(1)}'));
    final rows = await db.select(db.seasonRecords).get();
    expect(rows.length, greaterThan(500));
  }, timeout: const Timeout(Duration(minutes: 20)));
}
