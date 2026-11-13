part of 'match_simulator.dart';

/// 試合の後始末：勝敗投手・セーブ・ホールドの判定、ボックススコアと成績の集計
extension MatchFinish on MatchSimulator {
  /// 打席の終わり：引き継いだ走者が還った分の自責点を、走者を出した投手に付け替える。
  ///  リードが入れ替わったら、勝利投手の候補（攻撃側のいまの投手）と敗戦投手の候補（決勝点の走者を出した投手）を決める。
  ///  得点は先の塁の走者（＝引き継いだ走者）から入ったとみなす
  void _settlePa(GameSession s) {
    final dp = s.paDef;
    if (dp == null) {
      _trackLead(s);
      return;
    }
    final top = s.paTop, st = s.state;
    {
      final gained = (top ? st.homeDefenseOuts : st.awayDefenseOuts) - s.paDefOuts;
      if (gained > 0) {
        final lineup = top ? s.homeLineup : s.awayLineup;
        for (final l in lineup) {
          final pos = l.position;
          if (pos == 'DH' || pos == '投') continue; // 投手は下で（交代した投手に付ける）
          final m = s.posOuts.putIfAbsent(l.playerId, () => {});
          m[pos] = (m[pos] ?? 0) + gained;
        }
        final m = s.posOuts.putIfAbsent(dp.id, () => {});
        m['投'] = (m['投'] ?? 0) + gained;
      }
    }
    final off0 = top ? s.paAway : s.paHome, def0 = top ? s.paHome : s.paAway;
    final off1 = top ? st.awayScore : st.homeScore;
    final runs = off1 - off0;
    final q = s.inherit[dp.id] ?? <String>[];
    final consumed = runs > 0 ? q.take(runs).toList() : <String>[];
    if (consumed.isNotEmpty) q.removeRange(0, consumed.length);
    final defHome = top; // 表の攻撃ならホームが守り
    final rows = s.boxScore[defHome ? 'homePitcher' : 'awayPitcher'] as Map<String, dynamic>;
    final pitchers = defHome ? s.homePitchers : s.awayPitchers;
    Player byId(String id) => pitchers.firstWhere((x) => x.id == id, orElse: () => dp);
    // 自責点の付け替え
    final dpRow = rows[dp.registeredName] as Map?;
    final gained = ((dpRow?['er'] ?? 0) as int) - s.paDefEr;
    final mv = min(consumed.length, gained);
    for (var i = 0; i < mv; i++) {
      final r = byId(consumed[i]);
      if (identical(r, dp)) continue;
      dp.seasonStats.earnedRuns--;
      dpRow!['er'] = (dpRow['er'] as int) - 1;
      r.seasonStats.earnedRuns++;
      final rr = rows[r.registeredName] as Map?;
      if (rr != null) rr['er'] = ((rr['er'] ?? 0) as int) + 1;
    }
    // リードの入れ替わり
    if (off0 <= def0 && off1 > def0) {
      final k = def0 - off0 + 1; // 何点目でリードを奪ったか
      final resp = k <= consumed.length ? byId(consumed[k - 1]) : dp;
      final side = top ? -1 : 1;
      s.winCand[side] = top ? s.awayPitcher : s.homePitcher;
      s.loseCand[side] = resp;
    }
    final d = st.homeScore - st.awayScore;
    s.lastLeader = d > 0 ? 1 : (d < 0 ? -1 : 0);
    // 攻守が替わったら塁は空。そうでなければ、塁上の走者の数まで
    if (st.isTop != top) {
      q.clear();
    } else {
      final n = [st.runner1B, st.runner2B, st.runner3B].where((x) => x != null).length;
      if (q.length > n) q.removeRange(n, q.length);
    }
    s.inherit[dp.id] = q;
  }

  /// 勝利・敗戦・セーブ・ホールドを決めて、成績とボックススコアに記録する（公認野球規則 9.17〜9.19・NPB のホールド）
  ///  - 勝利：最後にリードを奪ったときの投手。先発は5回（15アウト）以上が必要で、届かなければ最も効果的な救援投手。
  ///          救援がリードを奪った投手でも、1回未満で失点した短い登板なら、後の最も効果的な救援投手
  ///  - 敗戦：最後にリードを奪われたとき、決勝点の走者を出した投手（引き継いだ走者なら前の投手）
  ///  - セーブ：勝利投手以外で最後まで投げ（1アウト以上）、リードして登板し、次のどれか
  ///          ①3点差以内で1回以上 ②同点の走者が塁上・打席・次打者の場面で登板 ③3回以上
  ///  - ホールド：勝敗もセーブも付かず、最後まで投げなかった救援（1アウト以上）で、次のどちらか
  ///          ①セーブと同じ場面（①②③）で登板し、リードを保って降板 ②同点で登板し、失点せずに降板
  ///  - ホールドポイント：ホールド＋救援勝利
  void _decide(GameSession s) {
    if (s.paDef == null) _trackLead(s);
    final d = s.state.homeScore - s.state.awayScore;
    final box = s.boxScore;
    void mark(Player p, bool home, String dec) {
      final row = (box[home ? 'homePitcher' : 'awayPitcher'] as Map<String, dynamic>)[p.registeredName];
      if (row is Map) row['dec'] = dec;
    }
    Player? winner, loser, saver;
    if (d != 0) {
      final w = d > 0 ? 1 : -1;
      final wPitchers = w == 1 ? s.homePitchers : s.awayPitchers;
      final rows = box[w == 1 ? 'homePitcher' : 'awayPitcher'] as Map<String, dynamic>;
      int outs(Player p) => s.pitcherOuts[p.id] ?? 0;
      int er(Player p) => ((rows[p.registeredName] as Map?)?['er'] ?? 0) as int;
      // 最も効果的な救援投手（アウトの数 − 失点×3。同じなら先に投げた投手）
      Player? best(Iterable<Player> ps) {
        Player? b;
        for (final p in ps) {
          if (b == null || outs(p) - er(p) * 3 > outs(b) - er(b) * 3) b = p;
        }
        return b;
      }

      final starter = wPitchers.first;
      winner = s.winCand[w] ?? starter;
      if (identical(winner, starter)) {
        if (outs(starter) < 15 && wPitchers.length > 1) winner = best(wPitchers.skip(1))!;
      } else {
        final i = wPitchers.indexOf(winner);
        if (outs(winner) < 3 && er(winner) >= 1 && i >= 0 && i + 1 < wPitchers.length) winner = best(wPitchers.skip(i + 1))!;
      }
      loser = s.loseCand[w] ?? (w == 1 ? s.awayPitchers.first : s.homePitchers.first);
      winner.seasonStats.wins++;
      if (!identical(winner, starter)) winner.seasonStats.reliefWins++;
      loser.seasonStats.losses++;
      mark(winner, w == 1, '勝');
      mark(loser, w != 1, '敗');
      final last = wPitchers.last;
      if (!identical(last, winner) && !identical(last, starter) && outs(last) >= 1) {
        final e = s.pitcherEntry[last.id] ?? [0, 0];
        final lead = e[0] - e[1];
        final runners = s.pitcherEntryRunners[last.id] ?? 0;
        if (lead >= 1 && ((lead <= 3 && outs(last) >= 3) || lead <= runners + 2 || outs(last) >= 9)) {
          saver = last;
          last.seasonStats.saves++;
          mark(last, w == 1, 'S');
        }
      }
    }
    for (final home in [true, false]) {
      final ps = home ? s.homePitchers : s.awayPitchers;
      for (var i = 1; i < ps.length; i++) {
        final p = ps[i];
        if (identical(p, winner) || identical(p, loser) || identical(p, saver) || identical(p, ps.last)) continue;
        final e = s.pitcherEntry[p.id], x = s.pitcherExit[p.id];
        if (e == null || x == null) continue;
        final leadIn = e[0] - e[1], leadOut = x[0] - x[1];
        final o = s.pitcherOuts[p.id] ?? 0;
        final runners = s.pitcherEntryRunners[p.id] ?? 0;
        final saveSit = leadIn >= 1 && (leadIn <= 3 || leadIn <= runners + 2 || o >= 9);
        final tieHold = leadIn == 0 && leadOut >= 0 && x[1] == e[1]; // 同点で登板し、失点せずに降板
        if (o >= 1 && ((saveSit && leadOut >= 1) || tieHold)) {
          p.seasonStats.holds++;
          mark(p, home, 'H');
        }
      }
    }
  }

  MatchResult finishGame(GameSession s) {
    final state = s.state;
    final homeTeam = s.homeTeam;
    final awayTeam = s.awayTeam;
    final boxScore = s.boxScore;
    // 実際に行われたイニング数に配列を揃える（終了判定前に先行追加された列を除く）
    int playedInnings = (state.isTop ? state.inning - 1 : state.inning).clamp(9, 12);
    if (state.homeInningScores.length > playedInnings) state.homeInningScores.length = playedInnings;
    if (state.awayInningScores.length > playedInnings) state.awayInningScores.length = playedInnings;

    for (var p in s.homeAppeared) { p.seasonStats.games++; }
    for (var p in s.awayAppeared) { p.seasonStats.games++; }
    String ipStr(int outs) => '${outs ~/ 3}${outs % 3 == 0 ? "" : ".${outs % 3}"}';
    if (s.homePitchers.isNotEmpty) s.homePitchers.first.seasonStats.starts++;
    if (s.awayPitchers.isNotEmpty) s.awayPitchers.first.seasonStats.starts++;
    for (var p in s.homePitchers) {
      final outs = s.pitcherOuts[p.id] ?? 0;
      p.seasonStats.pitchApps++;
      if (!s.homeAppeared.contains(p)) p.seasonStats.games++; // 二刀流で打順にもいれば、試合数は1回だけ
      p.seasonStats.inningsPitched += outs;
      boxScore['homePitcher'][p.registeredName]['ip'] = ipStr(outs);
      boxScore['homePitcher'][p.registeredName]['np'] = s.gamePitchCounts[p.id] ?? 0; // 球数
    }
    for (var p in s.awayPitchers) {
      final outs = s.pitcherOuts[p.id] ?? 0;
      p.seasonStats.pitchApps++;
      if (!s.awayAppeared.contains(p)) p.seasonStats.games++;
      p.seasonStats.inningsPitched += outs;
      boxScore['awayPitcher'][p.registeredName]['ip'] = ipStr(outs);
      boxScore['awayPitcher'][p.registeredName]['np'] = s.gamePitchCounts[p.id] ?? 0;
    }

    _decide(s);
    // 失策の数（スコアボードの E）。表の攻撃のときの失策はホームの失策
    boxScore['homeE'] = s.pitchEvents.where((e) => e.errorBy.isNotEmpty && !e.battingHome).length;
    boxScore['awayE'] = s.pitchEvents.where((e) => e.errorBy.isNotEmpty && e.battingHome).length;
    boxScore['homeSB'] = s.homeSB;
    boxScore['awaySB'] = s.awaySB;

    final homeHits = s.homeHits;
    final awayHits = s.awayHits;
    final playByPlay = s.playByPlay;
    final pitchByPitch = s.pitchByPitch;
    return MatchResult(
      homeTeamId: homeTeam.id,
      awayTeamId: awayTeam.id,
      homeScore: state.homeScore,
      awayScore: state.awayScore,
      homeInningScores: state.homeInningScores,
      awayInningScores: state.awayInningScores,
      homeHits: homeHits,
      awayHits: awayHits,
      playByPlay: playByPlay,
      pitchByPitch: pitchByPitch,
      boxScore: boxScore,
      session: s,
    );
  }
}
