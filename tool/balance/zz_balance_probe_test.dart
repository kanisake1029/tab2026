// ignore_for_file: avoid_print
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/db/app_database.dart';
import 'package:npb_pennant_app/models/player.dart';
import 'package:npb_pennant_app/engine/swing_model.dart';
import 'package:npb_pennant_app/engine/field_time.dart';
import 'package:npb_pennant_app/providers/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

String f3(num a, num b) => b == 0 ? '-' : (a / b).toStringAsFixed(3);
String f2(num a, num b) => b == 0 ? '-' : (a / b).toStringAsFixed(2);

String bat(List<PlayerStats> l, int teamGames) {
  var ab = 0, h = 0, hr = 0, bb = 0, so = 0, d2 = 0, d3 = 0, sf = 0, hbp = 0, r = 0;
  for (final s in l) { ab += s.atBats; h += s.hits; hr += s.homeRuns; bb += s.walks; so += s.strikeouts; d2 += s.doubles; d3 += s.triples; sf += s.sacFlies; hbp += s.hbp; r += s.runs; }
  final pa = ab + bb + hbp + sf;
  final tb = h + d2 + 2 * d3 + 3 * hr;
  final babip = (h - hr) / (ab - so - hr + sf);
  return '打率${f3(h, ab)} 出塁${f3(h + bb + hbp, pa)} 長打${f3(tb, ab)} 得点/試合${f2(r, teamGames)} 本/試合${f2(hr, teamGames)} 三振%${(so / pa * 100).toStringAsFixed(1)} 四球%${(bb / pa * 100).toStringAsFixed(1)} BABIP${babip.toStringAsFixed(3)}';
}

String pit(List<PlayerStats> l) {
  var ip = 0, er = 0, h = 0, hr = 0, so = 0, bb = 0, gs = 0, app = 0;
  for (final s in l) { ip += s.inningsPitched; er += s.earnedRuns; h += s.hitsAllowed; hr += s.hrAllowed; so += s.pitcherStrikeouts; bb += s.pitcherWalks; gs += s.starts; app += s.pitchApps; }
  final inn = ip / 3;
  return '防御率${(er * 9 / inn).toStringAsFixed(2)} 回${inn.round()} 登板$app 先発$gs 回/先発${gs == 0 ? '-' : (inn / gs).toStringAsFixed(1)} 被安/9 ${(h * 9 / inn).toStringAsFixed(1)} 本/9 ${(hr * 9 / inn).toStringAsFixed(2)} 振/9 ${(so * 9 / inn).toStringAsFixed(1)} 四/9 ${(bb * 9 / inn).toStringAsFixed(1)}';
}

void main() {
  test('probe', () async {
    final env = Platform.environment;
    if (env['NOISE'] != null) SwingModel.noiseScale = double.parse(env['NOISE']!);
    if (env['STUFFK'] != null) SwingModel.stuffK = double.parse(env['STUFFK']!);
    if (env['BR0'] != null) SwingModel.breakResid0 = double.parse(env['BR0']!);
    if (env['FTS'] != null) Fielding.timeScale = double.parse(env['FTS']!);
    if (env['REACH'] != null) Fielding.reachBase = double.parse(env['REACH']!);
    SharedPreferences.setMockInitialValues({});
    final tmp = File('${Directory.systemTemp.path}/s25_probe.sqlite');
    await File(const String.fromEnvironment('SAVE', defaultValue: 'backup/s25_20261108.sqlite')).copy(tmp.path);
    final db = AppDatabase(NativeDatabase(tmp));
    final a = AppState(db);
    while (!a.loaded) { await Future.delayed(const Duration(milliseconds: 20)); }
    const days = int.fromEnvironment('DAYS', defaultValue: 0);
    if (days > 0) {
      for (final t in a.teams) { for (final p in t.players) { p.seasonStats = PlayerStats(); } }
      final before = {for (final m in a.matches) m: m.homeScore != null};
      for (var i = 0; i < days; i++) { a.playNextDay(); }
      a.matches.removeWhere((m) => before[m] == true);
      for (final t in a.teams) { t.wins = 0; t.losses = 0; t.draws = 0; }
      for (final m in a.matches.where((m) => m.homeScore != null && m.matchType != 'OPEN')) {
        for (final t in a.teams) {
          final my = t.id == m.homeTeamId ? m.homeScore! : (t.id == m.awayTeamId ? m.awayScore! : -1);
          if (my < 0) continue;
          final op = t.id == m.homeTeamId ? m.awayScore! : m.homeScore!;
          if (my > op) { t.wins++; } else if (my < op) { t.losses++; } else { t.draws++; }
        }
      }
    }
    print('日付 ${a.currentDate} 開始年 ${a.startYear} 自球団 ${a.myTeam?.name}');
    final npb = a.teams.where((t) => t.league == 'CL' || t.league == 'PL').toList();
    final played = a.matches.where((m) => m.homeScore != null && (m.matchType == 'REG' || m.matchType.isEmpty)).toList();
    print('試合種別 ${{for (final m in a.matches) m.matchType}}');
    final reg = a.matches.where((m) => m.homeScore != null && m.matchType != 'OPEN').toList();
    final tg = reg.length * 2;
    print('終わった公式戦 ${reg.length}（REG ${played.length}） 平均得点 ${f2(reg.fold<int>(0, (s, m) => s + m.homeScore! + m.awayScore!), tg)}');
    // 回ごとの得点
    final byInn = List.filled(12, 0);
    for (final m in reg) { for (final l in [m.homeInningScores, m.awayInningScores]) { if (l == null) continue; for (var i = 0; i < l.length && i < 12; i++) { byInn[i] += l[i]; } } }
    print('回ごとの得点/試合 ${[for (var i = 0; i < 9; i++) '${i + 1}回:${f2(byInn[i], tg)}'].join(' ')}');
    final all = [for (final t in npb) for (final p in t.players) p];
    print('今季 打撃 ${bat([for (final p in all) p.seasonStats], tg)}');
    print('今季 投手全体 ${pit([for (final p in all.where((p) => p.seasonStats.inningsPitched > 0)) p.seasonStats])}');
    final sp = all.where((p) => p.seasonStats.starts * 2 > p.seasonStats.pitchApps && p.seasonStats.starts > 0).map((p) => p.seasonStats).toList();
    final rp = all.where((p) => p.seasonStats.starts * 2 <= p.seasonStats.pitchApps && p.seasonStats.pitchApps > 0).map((p) => p.seasonStats).toList();
    print('今季 先発投手 ${pit(sp)}');
    print('今季 中継ぎ   ${pit(rp)}');
    // 球団ごと
    for (final t in npb) {
      final ps = t.players.map((p) => p.seasonStats).toList();
      final g = t.wins + t.losses + t.draws;
      print('${t.name.padRight(8)} ${t.wins}-${t.losses}-${t.draws} ${bat(ps, g == 0 ? 1 : g).split(' ').take(4).join(' ')} | ${pit(ps.where((s) => s.inningsPitched > 0).toList()).split(' ').take(1).join()}');
    }
    // 能力の平均（1軍）
    double avg(Iterable<num> l) => l.isEmpty ? 0 : l.reduce((x, y) => x + y) / l.length;
    final p1 = [for (final t in npb) for (final id in t.roster1G) ...t.players.where((p) => p.id == id && p.isPitcher)];
    final b1 = [for (final t in npb) for (final id in t.roster1G) ...t.players.where((p) => p.id == id && !p.isPitcher)];
    print('1軍投手 ${p1.length}人 球速${avg(p1.map((p) => p.velocity)).toStringAsFixed(1)} 球威${avg(p1.map((p) => p.pitchPower)).toStringAsFixed(1)} 制球${avg(p1.map((p) => p.control)).toStringAsFixed(1)} スタ${avg(p1.map((p) => p.stamina)).toStringAsFixed(1)}');
    print('1軍野手 ${b1.length}人 ミート${avg(b1.map((p) => (p.contactLeft + p.contactRight) / 2)).toStringAsFixed(1)} パワー${avg(b1.map((p) => p.power)).toStringAsFixed(1)} 選球${avg(b1.map((p) => p.eye)).toStringAsFixed(1)} 走力${avg(b1.map((p) => p.run)).toStringAsFixed(1)}');

    // 能力の段階ごとの成績（投手：球速・球威・制球の平均で並べて3等分、15回以上）
    double q(Player p) => ((p.velocity - 130) * 2 + p.pitchPower + p.control) / 3;
    final ps = all.where((p) => p.isPitcher && p.seasonStats.inningsPitched >= 30).toList()..sort((x, y) => q(y).compareTo(q(x)));
    for (var k = 0; k < 3; k++) {
      final g = ps.sublist(ps.length * k ~/ 3, ps.length * (k + 1) ~/ 3);
      print('投手 能力${['上', '中', '下'][k]} ${g.length}人 球速${avg(g.map((p) => p.velocity)).toStringAsFixed(0)} 球威${avg(g.map((p) => p.pitchPower)).toStringAsFixed(0)} 制球${avg(g.map((p) => p.control)).toStringAsFixed(0)} → ${pit(g.map((p) => p.seasonStats).toList())}');
    }
    double qb(Player p) => ((p.contactLeft + p.contactRight) / 2 + p.power) / 2;
    final bs = all.where((p) => !p.isPitcher && p.seasonStats.atBats >= 30).toList()..sort((x, y) => qb(y).compareTo(qb(x)));
    for (var k = 0; k < 3; k++) {
      final g = bs.sublist(bs.length * k ~/ 3, bs.length * (k + 1) ~/ 3);
      print('打者 能力${['上', '中', '下'][k]} ${g.length}人 ミート${avg(g.map((p) => (p.contactLeft + p.contactRight) / 2)).toStringAsFixed(0)} パワー${avg(g.map((p) => p.power)).toStringAsFixed(0)} → ${bat(g.map((p) => p.seasonStats).toList(), 1).split(' 得点')[0]}');
    }
    final my = a.myTeam!;
    {
      final q = [for (final t in npb) for (final p in t.players) if (!p.isPitcher && p.seasonStats.atBats + p.seasonStats.walks >= (t.wins + t.losses + t.draws) * 3.1) p];
      final g = npb.first.wins + npb.first.losses + npb.first.draws;
      final avgs = q.map((p) => p.seasonStats.hits / p.seasonStats.atBats).toList()..sort();
      final hrs = [for (final t in npb) for (final p in t.players) if (!p.isPitcher) p.seasonStats.homeRuns]..sort();
      final rbis = [for (final t in npb) for (final p in t.players) if (!p.isPitcher) p.seasonStats.rbi]..sort();
      print('タイトル（143試合換算） 首位打者 ${avgs.isEmpty ? '-' : avgs.last.toStringAsFixed(3)}  3割 ${avgs.where((x) => x >= .3).length}人  本塁打王 ${(hrs.last * 143 / g).round()}  打点王 ${(rbis.last * 143 / g).round()}  規定${q.length}人');
    }
    {
      // 能力上位の打者（ミート＋パワー）の成績を 600打席・143試合に換算
      final g = npb.first.wins + npb.first.losses + npb.first.draws;
      final top = [for (final t in npb) for (final p in t.players) if (!p.isPitcher && p.seasonStats.atBats >= 80) p]..sort((x, y) => (y.contact + y.power).compareTo(x.contact + x.power));
      for (final p in top.take(12)) {
        final st = p.seasonStats; final pa = st.atBats + st.walks + st.hbp + st.sacFlies;
        print('上位打者 ${p.registeredName.padRight(8)} ミート${p.contact} パワー${p.power} 弾道${p.trajectory} 選球${p.eye} | 打率${(st.hits / st.atBats).toStringAsFixed(3)} 本/600打席${(st.homeRuns * 600 / pa).toStringAsFixed(1)} 打点/143試合${(st.rbi * 143 / g).round()}');
      }
    }
    {
      // 部門ごとの上位（実数と 143試合換算）
      final g = npb.first.wins + npb.first.losses + npb.first.draws;
      final bats = [for (final t in npb) for (final p in t.players) if (!p.isPitcher && p.seasonStats.atBats > 0) p];
      String row(Player p) { final st = p.seasonStats; final pa = st.atBats + st.walks + st.hbp + st.sacFlies; return '${p.registeredName.padRight(8)} ミ${p.contact} パ${p.power} 弾${p.trajectory} 選${p.eye} チャ${p.clutch} | 打席$pa 打率${(st.hits / st.atBats).toStringAsFixed(3)} 本${st.homeRuns}(${(st.homeRuns * 143 / g).round()}) 点${st.rbi}(${(st.rbi * 143 / g).round()})'; }
      print('試合数 $g');
      final q = bats.where((p) => p.seasonStats.atBats + p.seasonStats.walks >= g * 3.1).toList();
      for (final p in (q..sort((x, y) => (y.seasonStats.hits / y.seasonStats.atBats).compareTo(x.seasonStats.hits / x.seasonStats.atBats))).take(8)) { print('打率順 ${row(p)}'); }
      for (final p in (bats..sort((x, y) => y.seasonStats.homeRuns.compareTo(x.seasonStats.homeRuns))).take(8)) { print('本塁打順 ${row(p)}'); }
      for (final p in (bats..sort((x, y) => y.seasonStats.rbi.compareTo(x.seasonStats.rbi))).take(8)) { print('打点順 ${row(p)}'); }
      final pit = [for (final t in npb) for (final p in t.players) if (p.seasonStats.inningsPitched >= g * 3) p]..sort((x, y) => (x.seasonStats.earnedRuns / x.seasonStats.inningsPitched).compareTo(y.seasonStats.earnedRuns / y.seasonStats.inningsPitched));
      for (final p in pit.take(6)) { final st = p.seasonStats; print('防御率順 ${p.registeredName.padRight(8)} 球速${p.velocity} 威${p.pitchPower} 制${p.control} | 回${st.inningsPitched ~/ 3} 防${(st.earnedRuns * 27 / st.inningsPitched).toStringAsFixed(2)} 振${st.pitcherStrikeouts} 勝${st.wins}'); }
    }
    print('--- 自球団の投手 ---');
    for (final p in my.players.where((p) => p.isPitcher && p.seasonStats.pitchApps > 0).toList()..sort((x, y) => y.seasonStats.inningsPitched.compareTo(x.seasonStats.inningsPitched))) {
      final s = p.seasonStats;
      print('${p.registeredName.padRight(6)} ${p.age}歳 球速${p.velocity} 球威${p.pitchPower} 制球${p.control} スタ${p.stamina} 球種${p.pitches.length} 調子${p.conditionAt(a.currentDate)} | 登板${s.pitchApps} 先発${s.starts} 回${s.inningsPitched ~/ 3}.${s.inningsPitched % 3} 責${s.earnedRuns} 防${(s.earnedRuns * 27 / s.inningsPitched).toStringAsFixed(2)} 安${s.hitsAllowed} 本${s.hrAllowed} 振${s.pitcherStrikeouts} 四${s.pitcherWalks}');
    }
    // 過去シーズン
    final hist = await a.allPlayerSeasons();
    final years = {for (final h in hist) h.$1}.toList()..sort();
    for (final y in years) {
      final l = hist.where((h) => h.$1 == y && npb.any((t) => t.id == h.$2)).map((h) => h.$4).toList();
      final gs = l.fold<int>(0, (s, x) => s + x.starts);
      print('$y年 ${bat(l, gs)}');
      print('$y年 ${pit(l.where((s) => s.inningsPitched > 0).toList())}');
    }
  }, timeout: const Timeout(Duration(minutes: 90)));
}
