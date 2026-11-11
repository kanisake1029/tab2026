part of 'app_state.dart';

/// リーグ規定（試合数・リーグごとの DH・外国人枠）の変更。公式戦が始まる前（オフ〜オープン戦）だけ
extension RulesOps on AppState {
  /// いまの日程で公式戦がまだ始まっていない（＝規定を変えられる）
  bool get rulesEditable => !matches.any((m) => m.done && (m.matchType == 'LEAGUE' || m.matchType == 'INTERLEAGUE'));

  String? setLeagueRules({required bool dhCL, required bool dhPL, required int? foreign1G, required int? foreignBench}) {
    if (!rulesEditable) return '公式戦が始まったあとは変えられません（シーズンが終わってから）';
    if (foreign1G != null && foreignBench != null && foreignBench > foreign1G) return 'ベンチ入りの外国人は、1軍登録の人数以下にしてください';
    final changes = <String>[];
    if (dhCL != LeagueRules.dhCL) changes.add('${leagueLabel('CL')}：DH${dhCL ? 'あり' : 'なし'}');
    if (dhPL != LeagueRules.dhPL) changes.add('${leagueLabel('PL')}：DH${dhPL ? 'あり' : 'なし'}');
    if (foreign1G != LeagueRules.foreign1G) changes.add('外国人の1軍登録：${LeagueRules.limitText(foreign1G)}');
    if (foreignBench != LeagueRules.foreignBench) changes.add('外国人のベンチ入り：${LeagueRules.limitText(foreignBench)}');
    LeagueRules.dhCL = dhCL;
    LeagueRules.dhPL = dhPL;
    LeagueRules.foreign1G = foreign1G;
    LeagueRules.foreignBench = foreignBench;
    for (final t in teams) {
      _fitDH(t);
      _fitForeign(t);
    }
    refreshAllBenches();
    if (changes.isNotEmpty) _addNews(['リーグ規定を変更：${changes.join('、')}']);
    updateAndSave();
    return null;
  }

  /// 球団のオーダーを、そのリーグの DH の規定に合わせる（ビジターの試合は、試合ごとにホームの規定へ自動で合わせる）
  void _fitDH(Team t) {
    final dh = t.league == 'CL' ? LeagueRules.dhCL : LeagueRules.dhPL;
    if (t.useDH == dh) return;
    t.useDH = dh;
    final sp = t.players.where((p) => p.id == t.todaysStarterId).firstOrNull ?? t.players.where((p) => p.isPitcher).firstOrNull;
    if (sp == null) return;
    t.lineup = LeagueRules.gameLineup(t, sp, dh);
  }

  /// 1軍の外国人枠を超えていたら、能力の低い外国人から 2軍へ（代わりに 2軍の同じ種類の日本人選手を上げる）
  void _fitForeign(Team t) {
    final cap = LeagueRules.foreign1G;
    if (cap == null) return;
    final pmap = {for (final p in t.players) p.id: p};
    var foreign = [for (final id in t.roster1G) if (pmap[id]?.foreignSlot ?? false) pmap[id]!]..sort((a, b) => a.ovr.compareTo(b.ovr));
    while (foreign.length > cap) {
      final p = foreign.removeAt(0);
      t.roster1G.remove(p.id);
      t.manualBenchOut.remove(p.id);
      for (var i = 0; i < t.rotation.length; i++) {
        if (t.rotation[i] == p.id) t.rotation[i] = '';
      }
      t.rotation = t.rotation;
      for (var i = 0; i < t.winningPattern.length; i++) {
        if (t.winningPattern[i] == p.id) t.winningPattern[i] = '';
      }
      final up = (t.players.where((c) => c.isPitcher == p.isPitcher && !c.foreignSlot && !c.ikusei && !t.roster1G.contains(c.id) && !c.isInjuredOut).toList()..sort((a, b) => b.ovr.compareTo(a.ovr))).firstOrNull;
      if (up != null) t.roster1G.add(up.id);
      // スタメンにいたら、控えの野手で埋める
      for (final l in t.lineup) {
        if (l.playerId != p.id) continue;
        final used = {for (final e in t.lineup) e.playerId};
        final bench = t.roster1G.map((x) => pmap[x]).whereType<Player>().where((c) => !c.isPitcher && !used.contains(c.id) && !c.isInjuredOut).toList()..sort((a, b) => b.ovr.compareTo(a.ovr));
        if (bench.isNotEmpty) l.playerId = bench.first.id;
      }
      if (t.id == myTeamId) _addNews(['外国人枠の変更で、${p.registeredName}を2軍へ（${up == null ? '代わりの選手なし' : '${up.registeredName}を1軍へ'}）']);
    }
    t.autoFillPitchingStaff();
  }
}
