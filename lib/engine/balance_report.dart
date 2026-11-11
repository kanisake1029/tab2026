import 'match_simulator.dart';

/// バランス検証の数字（投球・打球・守備・走塁・環境）。試合の写しの1球ごとの記録から作る
///  画面（設定・編集 → バランス検証）とテスト（test/balance_lab_test.dart）で同じ計算を使う
class BalanceSection {
  final String title, note;
  final List<(String, String, String)> rows; // 項目・結果・NPB の目安
  const BalanceSection(this.title, this.note, this.rows);
}

class BalanceReport {
  final List<PitchEvent> events;
  final Map<PitchEvent, int> gameOf;
  final Map<String, int> dbg, pr;
  final int runs, played;
  final List<String> envs;
  BalanceReport({required this.events, required this.gameOf, required this.dbg, required this.pr, required this.runs, required this.played, required this.envs});

  String _pct(num a, num b) => b == 0 ? '-' : '${(a / b * 100).toStringAsFixed(1)}%';
  String _f3(num a, num b) => b == 0 ? '-' : (a / b).toStringAsFixed(3).replaceFirst('0.', '.');
  String _pg(num a) => played == 0 ? '-' : (a / played).toStringAsFixed(2);
  BalanceSection _sec(String t, String n, List<(String, String, String)> r) => BalanceSection(t, n, r);

  @override
  String toString() => [for (final s in sections()) '【${s.title}】\n${[for (final r in s.rows) '  ${r.$1}: ${r.$2}${r.$3.isEmpty ? '' : '（目安 ${r.$3}）'}'].join('\n')}'].join('\n');

  List<BalanceSection> sections() {
    final ev = events;
    final pitches = ev.length;
    // 打席の最後の1球
    final last = <String, PitchEvent>{};
    for (final e in ev) {
      final k = '${gameOf[e]}|${e.battingHome}|${e.paIndex}';
      final c = last[k];
      if (c == null || e.pitchNo >= c.pitchNo) last[k] = e;
    }
    final pa = last.length;
    final so = last.values.where((e) => e.result == '空振り' || e.result == '見逃し').where((e) => e.strikes == 2).length;
    final bb = last.values.where((e) => e.result == 'ボール' && e.balls == 3).length;
    final inZone = ev.where((e) => e.inZone).length;
    final swings = ev.where((e) => const {'空振り', 'ファウル', 'インプレー'}.contains(e.result)).length;
    final whiffs = ev.where((e) => e.result == '空振り').length;
    final chase = ev.where((e) => !e.inZone && const {'空振り', 'ファウル', 'インプレー'}.contains(e.result)).length;
    final outZone = pitches - inZone;
    final fast = ev.where((e) => e.pitchName.contains('ストレート') || e.pitchName.contains('直球'));
    final avgFast = fast.isEmpty ? 0 : fast.map((e) => e.speed).reduce((a, b) => a + b) / fast.length;
    // 打球
    final bip = ev.where((e) => e.result == 'インプレー').toList();
    int nC(String c) => bip.where((e) => e.contact == c).length;
    bool isHit(PitchEvent e) => const {'単打', '二塁打', '三塁打', 'ホームラン'}.contains(e.outcome);
    final hr = bip.where((e) => e.outcome == 'ホームラン').length;
    String babipOf(String c) {
      final l = bip.where((e) => e.contact == c && e.outcome != 'ホームラン');
      return _f3(l.where(isHit).length, l.length);
    }

    final evs = bip.where((e) => e.exitSpeed > 0).toList();
    final avgEv = evs.isEmpty ? 0 : evs.map((e) => e.exitSpeed * 3.6).reduce((a, b) => a + b) / evs.length;
    final avgLa = evs.isEmpty ? 0 : evs.map((e) => e.launch ?? 0).reduce((a, b) => a + b) / evs.length;
    final hard = evs.where((e) => e.exitSpeed * 3.6 >= 152).length;
    final nonHr = bip.where((e) => e.outcome != 'ホームラン').toList();
    final hits = last.values.where(isHit).length;
    final ab = pa - bb - last.values.where((e) => e.desc.contains('犠')).length;
    final d2 = bip.where((e) => e.outcome == '二塁打').length, d3 = bip.where((e) => e.outcome == '三塁打').length;
    // 守備
    final errs = bip.where((e) => e.errorBy.isNotEmpty).length;
    final dp = bip.where((e) => e.outcome == '併殺').length;
    final calls = bip.where((e) => e.call == 'お見合い').length;
    final gb = bip.where((e) => e.contact == 'ゴロ').length;
    return [
      _sec('全体', '', [
        ('1試合の得点（両軍）', _pg(runs), '約7.5'),
        ('打率', _f3(hits, ab), '.245〜.255'),
        ('本塁打／試合（両軍）', _pg(hr), '約1.6'),
      ]),
      _sec('① 投球', '球速・制球・球の見極め（3D 物理の軌道で判定）', [
        ('球数／打席', pa == 0 ? '-' : (pitches / pa).toStringAsFixed(2), '約3.9'),
        ('三振率', _pct(so, pa), '約19〜21%'),
        ('四球率', _pct(bb, pa), '約7〜8%'),
        ('ゾーン内の割合', _pct(inZone, pitches), '約45〜50%'),
        ('スイング率', _pct(swings, pitches), '約45〜48%'),
        ('空振り÷スイング', _pct(whiffs, swings), '約22〜25%'),
        ('ボール球を振る率', _pct(chase, outZone), '約28〜32%'),
        ('ファウル÷スイング', _pct(ev.where((e) => e.result == 'ファウル').length, swings), '約38〜40%'),
        ('インプレー÷スイング', _pct(ev.where((e) => e.result == 'インプレー').length, swings), '約36〜38%'),
        ('直球の平均球速', '${avgFast.toStringAsFixed(1)}km/h', '約146〜148'),
      ]),
      _sec('② 打球', '打球の速さ・角度と、種類ごとの安打率（本塁打を除く）', [
        ('平均打球速度', '${avgEv.toStringAsFixed(1)}km/h', '約135〜140'),
        ('平均打球角度', '${avgLa.toStringAsFixed(1)}°', '約10〜13°'),
        ('強い打球（152km/h〜）', _pct(hard, evs.length), '約35%'),
        ('ゴロ／ライナー／フライ／ポップ', '${_pct(nC('ゴロ'), bip.length)} ${_pct(nC('ライナー'), bip.length)} ${_pct(nC('フライ'), bip.length)} ${_pct(nC('ポップフライ'), bip.length)}', '45／22／25／8%'),
        ('インプレーの安打率', _f3(nonHr.where(isHit).length, nonHr.length), '約.290〜.300'),
        ('ゴロ／ライナー／フライの安打率', '${babipOf('ゴロ')} ${babipOf('ライナー')} ${babipOf('フライ')}', '.24／.68／.13'),
        ('本塁打÷打球', _pct(hr, bip.length), '約3.5〜4%'),
        ('二塁打の内訳 ゴロ／ライナー／フライ', '${dbg['d2_ゴロ'] ?? 0}／${dbg['d2_ライナー'] ?? 0}／${dbg['d2_フライ'] ?? 0}', ''),
        ('先の塁を狙って刺された', '${bip.where((e) => e.desc.contains('狙うもタッチアウト')).length}', ''),
        ('二塁打／三塁打（試合）','${_pg(d2)}／${_pg(d3)}', '約3.0／0.3'),
      ]),
      _sec('③ 守備', '役割の割り当て・送球先の判断・捕球', [
        ('失策／試合（両軍）', _pg(errs), '約1.0'),
        ('併殺／試合（両軍）', _pg(dp), '約1.4'),
        ('三重殺', '${dbg['tp'] ?? 0}', 'まれ'),
        ('内野安打÷ゴロ', _pct(dbg['infieldHit'] ?? 0, gb), '約5〜7%'),
        ('野選・挟殺', '${pr['gbFC'] ?? 0}・${pr['gbRundown'] ?? 0}', ''),
        ('お見合い', '$calls', 'まれ'),
        ('暴投・捕逸／試合（両軍）', _pg(dbg['wildPitch'] ?? 0), '約0.6'),
        ('振り逃げで出塁・エンタイトル二塁打・インフィールドフライ', '${dbg['droppedK'] ?? 0}・${dbg['groundRuleDouble'] ?? 0}・${dbg['infieldFly'] ?? 0}', ''),
        ('中継で刺した・送球で刺した走者','${dbg['runnerThrownOut'] ?? 0}', ''),
      ]),
      _sec('④ 走塁', '盗塁の時間の勝負・進塁の判断（期待値）', [
        ('盗塁企図／試合', _pg(dbg['steals'] ?? 0), '約1.0'),
        ('盗塁成功率', _pct(dbg['stealSuccess'] ?? 0, dbg['steals'] ?? 0), '約70%'),
        ('単打で一塁→三塁', _pct(dbg['r1ToThirdOnSingle'] ?? 0, dbg['r1OnSingle'] ?? 0), '約28%'),
        ('単打で二塁→生還', _pct(dbg['r2ScoredOnSingle'] ?? 0, dbg['r2OnSingle'] ?? 0), '約60%'),
        ('二塁打で一塁→生還', _pct(dbg['r1ScoredOnDouble'] ?? 0, dbg['r1OnDouble'] ?? 0), '約40%'),
        ('犠飛', '${dbg['sacFly'] ?? 0}', ''),
        ('バント成功', _pct(dbg['buntSuccess'] ?? 0, dbg['bunts'] ?? 0), '約85%'),
      ]),
      _sec('⑤ 環境', '気温・湿度・風（球場と日付で決まる）', [
        for (final s in envs.take(8)) (s, '', ''),
        if (envs.length > 8) ('ほか ${envs.length - 8}試合', '', ''),
      ]),
    ];
  }

}
