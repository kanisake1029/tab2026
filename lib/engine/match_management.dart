part of 'match_simulator.dart';

/// 交代・代打・代走・守備位置の入れ替え・CPU 監督の継投と采配（おまかせ）
extension MatchManagement on MatchSimulator {
  List<Player> _bench(GameSession s, bool home, {required bool pitchers}) {
    final team = home ? s.homeTeam : s.awayTeam;
    final ids = team.active26.isNotEmpty ? team.active26 : team.roster1G;
    return team.players.where((p) => (pitchers ? p.canPitch : p.canBat) && ids.contains(p.id) && !s.usedIds.contains(p.id)).toList();
  }

  /// 次に打席が回ってくる打順スロット
  int nextBatterSlot(GameSession s, bool home) {
    final order = home ? s.homeOrder : s.awayOrder;
    return (home ? s.homeBatterIndex : s.awayBatterIndex) % order.length;
  }

  void _ensureBatterRow(GameSession s, bool home, Player p) {
    final m = s.boxScore[home ? 'homeBatters' : 'awayBatters'] as Map<String, dynamic>;
    m.putIfAbsent(p.registeredName, () => {'ab': 0, 'h': 0, 'hr': 0, 'rbi': 0, 'bb': 0, 'so': 0});
  }

  void _putInOrder(GameSession s, bool home, int slot, Player p, {String? position}) {
    final order = home ? s.homeOrder : s.awayOrder;
    final lineup = home ? s.homeLineup : s.awayLineup;
    order[slot] = p;
    if (slot < lineup.length) {
      lineup[slot].playerId = p.id;
      if (position != null) lineup[slot].position = position;
    }
    (home ? s.homeAppeared : s.awayAppeared).add(p);
    s.usedIds.add(p.id);
    _ensureBatterRow(s, home, p);
  }

  /// 投手交代
  void changePitcher(GameSession s, bool home, Player p) {
    final old = home ? s.homePitcher : s.awayPitcher;
    final my = home ? s.state.homeScore : s.state.awayScore, opp = home ? s.state.awayScore : s.state.homeScore;
    s.pitcherExit[old.id] = [my, opp];
    s.pitcherEntry[p.id] = [my, opp];
    // 守っている側の交代なら、塁上の走者を引き継ぐ（走者を出した投手の責任のまま）
    final defending = home == s.state.isTop; // 表（ビジターの攻撃）ならホームが守り
    final n = defending ? [s.state.runner1B, s.state.runner2B, s.state.runner3B].where((x) => x != null).length : 0;
    final q = List<String>.of(s.inherit[old.id] ?? const []);
    if (q.length > n) q.removeRange(n, q.length);
    while (q.length < n) {
      q.add(old.id);
    }
    s.inherit[p.id] = q;
    s.pitcherEntryRunners[p.id] = n;
    if (home) { s.homePitcher = p; s.homePitchers.add(p); } else { s.awayPitcher = p; s.awayPitchers.add(p); }
    s.usedIds.add(p.id);
    (s.boxScore[home ? 'homePitcher' : 'awayPitcher'] as Map<String, dynamic>)
        .putIfAbsent(p.registeredName, () => <String, dynamic>{'ip': '0', 'er': 0, 'so': 0, 'bb': 0});
    s.playByPlay.add('【投手交代】${(home ? s.homeTeam : s.awayTeam).name}: ${old.registeredName} → ${p.registeredName}');
  }

  /// 代打（次の打者を差し替える。守備位置は元の選手のものを引き継ぐ）
  void pinchHit(GameSession s, bool home, Player p) {
    final slot = nextBatterSlot(s, home);
    final old = (home ? s.homeOrder : s.awayOrder)[slot];
    if (applyForm) old.trust = (old.trust - 1).clamp(1, 100); // 代打を送られると信頼が少し下がる
    _putInOrder(s, home, slot, p);
    s.playByPlay.add('【代打】${(home ? s.homeTeam : s.awayTeam).name}: ${old.registeredName} → ${p.registeredName}');
  }

  /// 代走（base: 1=一塁, 2=二塁, 3=三塁）
  void pinchRun(GameSession s, bool home, int base, Player p) {
    final st = s.state;
    final oldName = base == 1 ? st.runner1B : (base == 2 ? st.runner2B : st.runner3B);
    if (oldName == null) return;
    final order = home ? s.homeOrder : s.awayOrder;
    final slot = order.indexWhere((x) => x.registeredName == oldName);
    if (slot < 0) return;
    _putInOrder(s, home, slot, p);
    if (base == 1) { st.runner1B = p.registeredName; } else if (base == 2) { st.runner2B = p.registeredName; } else { st.runner3B = p.registeredName; }
    s.playByPlay.add('【代走】${(home ? s.homeTeam : s.awayTeam).name}: $oldName → ${p.registeredName}');
  }

  /// 守備交代（打順スロットの選手を差し替え、守備位置を指定: 捕/一/二/三/遊/左/中/右/DH）
  /// 出ている選手同士の守備位置の入れ替え（打順はそのまま）
  void swapPositions(GameSession s, bool home, int a, int b) {
    final lineup = home ? s.homeLineup : s.awayLineup;
    final order = home ? s.homeOrder : s.awayOrder;
    if (a == b || a >= lineup.length || b >= lineup.length) return;
    final pa = lineup[a].position, pb = lineup[b].position;
    lineup[a].position = pb;
    lineup[b].position = pa;
    s.playByPlay.add('【守備位置の変更】${(home ? s.homeTeam : s.awayTeam).name}: ${order[a].registeredName}（$pa→$pb）・${order[b].registeredName}（$pb→$pa）');
  }

  void defensiveSwap(GameSession s, bool home, int slot, Player p, String position) {
    final old = (home ? s.homeOrder : s.awayOrder)[slot];
    _putInOrder(s, home, slot, p, position: position);
    s.playByPlay.add('【守備交代】${(home ? s.homeTeam : s.awayTeam).name}: ${old.registeredName} → ${p.registeredName}（$position）');
  }

  /// CPU（自動）の継投判断。守備側のチームについて、次の打席の前に呼ぶ
  void autoPitching(GameSession s, bool home) {
    final st = s.state;
    var pool = availablePitchers(s, home);
    // 体力が3割を切った投手は起用しない（全員そうなら仕方なく使う）
    if (applyForm) {
      final fresh = pool.where((p) => p.energyRatio >= 0.3).toList();
      if (fresh.isNotEmpty) pool = fresh;
    }
    if (pool.isEmpty) return;
    final team = home ? s.homeTeam : s.awayTeam;
    final cur = home ? s.homePitcher : s.awayPitcher;
    final isStarter = identical(cur, home ? s.starterHome : s.starterAway);
    final rotation = {for (final id in team.rotation.take(team.rotationCount)) if (id.isNotEmpty) id};
    if (st.inning < 12) {
      final rel = pool.where((p) => !rotation.contains(p.id)).toList();
      if (rel.isNotEmpty) pool = rel;
    }
    final pitches = s.staminaUsed[cur.id] ?? 0; // スタミナ消費量（打たれたイニングは1.5倍）
    final er = ((s.boxScore[home ? 'homePitcher' : 'awayPitcher'] as Map<String, dynamic>)[cur.registeredName]?['er'] ?? 0) as int;
    final lead = home ? st.homeScore - st.awayScore : st.awayScore - st.homeScore;
    final halfStart = s.lastInningStr != '${st.inning}回${st.isTop ? "表" : "裏"}';

    Player? byId(String? id) {
      if (id == null || id.isEmpty) return null;
      for (final p in pool) { if (p.id == id) return p; }
      return null;
    }

    // 3連投はさせない（前日まで2日続けて投げた投手は休ませる）
    final y = s.match.date.subtract(const Duration(days: 1));
    final yesterday = '${y.year}-${y.month}-${y.day}';
    bool rested(Player p) => !(p.consecDays >= 2 && p.lastPitched == yesterday);
    // 勝利の方程式（リード時）: winningPattern = [7回, 8回, 9回以降]。各イニング開始時に1〜3点リードなら登板
    final np = s.gamePitchCounts[cur.id] ?? 0; // 実際の球数
    if (halfStart && lead >= 1 && lead <= 3 && st.inning >= 7) {
      final idx = st.inning >= 9 ? 2 : st.inning - 7;
      final w = byId(team.winningPattern[idx]);
      final dominant = isStarter && (st.inning >= 9 ? (er == 0 && np < 105) : (er <= 1 && np < 85));
      if (w != null && !identical(w, cur) && rested(w) && !dominant) { changePitcher(s, home, w); return; }
    }
    // 左のワンポイント：7回以降・2点差以内で、次の打者が左の強打者なら、左の中継ぎを挟む（判断力しだい）
    final oppOrder = home ? s.awayOrder : s.homeOrder;
    final nextB = oppOrder[nextBatterSlot(s, !home) % oppOrder.length];
    if (st.inning >= 7 && lead.abs() <= 2 && nextB.bats == 'L' && nextB.power >= 72 && cur.throws != 'L' && !team.winningPattern.contains(cur.id)) {
      final lefty = (pool.where((p) => p.throws == 'L' && !team.winningPattern.contains(p.id) && rested(p) && p.ovr >= 55).toList()..sort((a, b) => b.ovr.compareTo(a.ovr))).firstOrNull;
      if (lefty != null && _rand.nextDouble() < (MatchSimulator.cpuSkill(team.id) / 100.0) * 0.6) {
        changePitcher(s, home, lefty);
        s.playByPlay.add('（左のワンポイント）');
        return;
      }
    }
    // ── 交代するか ──
    // 先発：球数の目安（スタミナ50で約98球・70で約105球・90で約112球。継投の早い監督ほど早め）で降板。
    //       炎上（自責5、または5回までに自責4）・疲れ切った（スタミナの上限）でも降板
    // 中継ぎ：1イニング投げ終えたら次の回は別の投手。回の途中は球数・失点で降板
    final quick = ((MatchSimulator.cpuStyles[team.id]?['bullpen'] ?? 50) - 50) * 0.3;
    final outs = s.pitcherOuts[cur.id] ?? 0;
    final close = lead.abs() <= 2;
    bool tired;
    if (isStarter) {
      final target = (80 + cur.stamina * 0.35 - quick).clamp(80.0, 125.0);
      tired = er >= 5 ||
          (er >= 4 && st.inning <= 5) ||
          pitches >= MatchSimulator.staminaLimit(cur) - 8 ||
          (halfStart && np >= target) ||
          np >= target + 15;
    } else {
      final long = lead.abs() >= 4 && st.inning <= 6; // 大差の序盤・中盤は長く投げてよい
      tired = er >= 3 ||
          np >= 30 + cur.stamina * 0.15 + (long ? 15 : 0) ||
          (halfStart && outs >= 3 && !(long && np < 35));
    }
    if (!tired) return;

    // ── 誰を出すか ──（場面ごとの役割・連投の疲れ・その日の調子のぶれで散らす）
    final reserved = {...team.winningPattern};
    var cands = pool.where((p) => !reserved.contains(p.id) && rested(p) && !identical(p, cur)).toList();
    if (cands.isEmpty) cands = pool.where((p) => !reserved.contains(p.id) && !identical(p, cur)).toList();
    if (cands.isEmpty) cands = pool.where((p) => !identical(p, cur)).toList();
    if (cands.isEmpty) return;
    // 延長・接戦の終盤で他にいなければ、勝ちパターンも使う
    final sorted = [...cands]..sort((x, y) => y.ovr.compareTo(x.ovr));
    final rank = {for (var i = 0; i < sorted.length; i++) sorted[i].id: i};
    final blowout = lead.abs() >= 4;
    final early = st.inning <= 5;
    double score(Player p) {
      final top = 1 - rank[p.id]! / sorted.length; // 1 = いちばん良い投手
      double v;
      if (early && (blowout || lead < 0)) {
        v = p.stamina * 0.8 + p.ovr * 0.3; // ロングリリーフ：長く投げられる投手
      } else if (blowout) {
        v = (1 - top) * 60 + p.stamina * 0.2; // 敗戦処理・大量リード：控えめの投手で主力を休ませる
      } else if (close && st.inning >= 6) {
        v = top * 80 + p.ovr * 0.3; // 接戦の終盤：良い投手から
      } else {
        v = top * 45 + p.ovr * 0.2; // 中盤：中くらいの投手
      }
      // 連投の疲れ：前日投げた投手は控えめに。体力（調子）が減っている投手も
      if (p.lastPitched == '${y.year}-${y.month}-${y.day}') v -= 18;
      if (applyForm) v -= (1 - p.energyRatio) * 30;
      return v + _rand.nextDouble() * 14; // その日の判断のぶれ
    }

    cands.sort((x, y) => score(y).compareTo(score(x)));
    changePitcher(s, home, cands.first);
  }

  /// CPU采配をまとめて実行（守備固め・継投・代打・代走）
  void autoManage(GameSession s) {
    if (isFinished(s)) return;
    autoDefenseSubs(s, s.state.isTop); // 表の守備側＝ホーム
    autoPitching(s, s.state.isTop);
    autoOffenseSubs(s, !s.state.isTop);
  }

  /// CPU の代打・代走（攻撃側）。終盤の接戦や負けている場面で使う
  void autoOffenseSubs(GameSession s, bool home) {
    final st = s.state;
    if (st.inning < 7) return;
    final team = home ? s.homeTeam : s.awayTeam;
    final lead = home ? st.homeScore - st.awayScore : st.awayScore - st.homeScore;
    final bench = availableBatters(s, home);
    if (bench.isEmpty) return;
    final order = home ? s.homeOrder : s.awayOrder;
    final lineup = home ? s.homeLineup : s.awayLineup;
    final opp = home ? s.awayPitcher : s.homePitcher;
    // 代走：8回以降・1点差以内で、足の遅い走者に足の速い控え
    if (st.inning >= 8 && lead.abs() <= 1) {
      for (final base in [2, 1]) {
        final name = base == 2 ? st.runner2B : st.runner1B;
        if (name == null) continue;
        final runner = order.where((x) => x.registeredName == name).firstOrNull;
        if (runner == null || runner.run >= 55) continue;
        final fast = (bench.where((b) => b.run >= 70).toList()..sort((a, b) => b.run.compareTo(a.run))).firstOrNull;
        if (fast != null && _judge(team)) {
          pinchRun(s, home, base, fast);
          return;
        }
      }
    }
    // 代打：7回以降で負けている（同点を含む）場面。打力が明らかに上の控え、または左右の相性
    if (lead > 0 || lead < -4) return;
    final slot = nextBatterSlot(s, home);
    final cur = order[slot];
    final pos = slot < lineup.length ? lineup[slot].position : '';
    if (pos == '投') return; // 投手の打順には代打を出さない（そのあとの継投をエンジンが扱えないため）
    if (cur.twoWay) return; // 二刀流で起用している選手には代打を出さない
    if (pos == '捕' && !bench.any((b) => b.mainPosition == '捕手')) return; // 控え捕手がいなければ捕手には代打を出さない
    double bat(Player b) {
      final hand = b.bats == 'S' ? 0 : (b.bats == opp.throws ? -6 : 3); // 同じ利き同士は打ちにくい
      return (b.contactLeft + b.contactRight) / 4 + b.power * 0.5 + hand;
    }
    final best = (List.of(bench)..sort((a, b) => bat(b).compareTo(bat(a)))).first;
    final margin = 10 - (MatchSimulator.cpuSkill(team.id) - 50) * 0.08; // 判断力の高い監督ほど、小さな差でも代打を出す
    if (bat(best) >= bat(cur) + margin && _judge(team)) pinchHit(s, home, best);
  }

  /// CPU の守備固め（守備側）。8回以降に1〜3点リードしている回の初めに、守備の弱い選手を替える
  void autoDefenseSubs(GameSession s, bool home) {
    final st = s.state;
    final halfStart = s.lastInningStr != '${st.inning}回${st.isTop ? "表" : "裏"}';
    if (!halfStart || st.inning < 8) return;
    final team = home ? s.homeTeam : s.awayTeam;
    final lead = home ? st.homeScore - st.awayScore : st.awayScore - st.homeScore;
    if (lead < 1 || lead > 3) return;
    final bench = availableBatters(s, home);
    final order = home ? s.homeOrder : s.awayOrder;
    final lineup = home ? s.homeLineup : s.awayLineup;
    int apt(Player p, String pos) => switch (pos) { '捕' => p.fieldC, '一' => p.field1B, '二' => p.field2B, '三' => p.field3B, '遊' => p.fieldSS, '左' => p.fieldLF, '中' => p.fieldCF, '右' => p.fieldRF, _ => 0 };
    for (var i = 0; i < lineup.length && i < order.length; i++) {
      final pos = lineup[i].position;
      if (pos == 'DH' || pos == '投') continue;
      final cur = order[i];
      final a = apt(cur, pos) + cur.catchSkill * 0.3;
      final cand = (bench.where((b) => apt(b, pos) >= 55).toList()..sort((x, y) => (apt(y, pos) + y.catchSkill * 0.3).compareTo(apt(x, pos) + x.catchSkill * 0.3))).firstOrNull;
      if (cand == null) continue;
      if (apt(cand, pos) + cand.catchSkill * 0.3 >= a + 15 && _judge(team)) {
        defensiveSwap(s, home, i, cand, pos);
        return; // 1回に1人まで
      }
    }
  }

  /// リードの入れ替わりを記録する（打席が終わるたびに呼ぶ）
  void _trackLead(GameSession s) {
    final d = s.state.homeScore - s.state.awayScore;
    final leader = d > 0 ? 1 : (d < 0 ? -1 : 0);
    if (leader != 0 && leader != s.lastLeader) {
      s.winCand[leader] = leader == 1 ? s.homePitcher : s.awayPitcher;
      s.loseCand[leader] = leader == 1 ? s.awayPitcher : s.homePitcher;
    }
    s.lastLeader = leader;
  }
}
