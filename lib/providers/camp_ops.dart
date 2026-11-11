part of 'app_state.dart';

/// 育成（企画書 4章）：試合の経験値・春季／秋季キャンプ・3軍戦
extension CampOps on AppState {
  static const springMax = 50;   // 春季キャンプ（1軍キャンプ）の人数の上限
  static const autumnMax = 30;   // 秋季キャンプの人数の上限
  static const campCost = 500;   // キャンプの費用（1人・万円）

  /// 春季キャンプ中（1月）／秋季キャンプ中（11月）
  bool get inSpringCamp => currentDate.month == 1;
  bool get inAutumnCamp => currentDate.month == 11;

  // ───────── 試合の経験値 ─────────

  /// 試合に出た選手に経験値を入れる（1軍 1.0、2軍 0.5）。投手は投げた回の長さで増える
  void _awardGameExp(GameSession s, double level) {
    final done = <String>{};
    for (final home in [true, false]) {
      final t = home ? s.homeTeam : s.awayTeam;
      for (final p in home ? s.homePitchers : s.awayPitchers) {
        if (!done.add(p.id)) continue;
        GrowthEngine.gameExp(p, level, innings: (s.pitcherOuts[p.id] ?? 0) / 3.0, coach: (st) => _gameExpMult(t, p, st));
      }
      for (final p in home ? s.homeAppeared : s.awayAppeared) {
        if (!done.add(p.id)) continue;
        GrowthEngine.gameExp(p, level, coach: (st) => _gameExpMult(t, p, st));
      }
      // 1軍の試合：ベンチにいて出なかった選手にも、2軍の試合に出たのと同じ経験値（先発ローテの投手は登板間隔のため除く）
      if (level >= 1.0) {
        final real = teamById(t.id) ?? t;
        final pmap = {for (final p in real.players) p.id: p};
        for (final id in real.active26) {
          final p = pmap[id];
          if (p == null || done.contains(p.id) || real.activeRotation.contains(p.id)) continue;
          done.add(p.id);
          GrowthEngine.gameExp(p, 0.5, innings: p.isPitcher ? 1.0 : 0, coach: (st) => _gameExpMult(real, p, st));
        }
      }
    }
  }

  // ───────── キャンプ ─────────

  /// 春季キャンプの自動の人選：1軍の選手と、伸びしろのある若手から50人
  List<String> autoSpringCamp(Team t) {
    final sorted = t.players.where((p) => !p.isInjuredOut).toList()
      ..sort((a, b) => _campScore(t, b, spring: true).compareTo(_campScore(t, a, spring: true)));
    return sorted.take(springMax).map((p) => p.id).toList();
  }

  /// 秋季キャンプの自動の人選：若手を中心に30人
  List<String> autoAutumnCamp(Team t) {
    final sorted = t.players.where((p) => !p.isInjuredOut && p.age <= 30).toList()
      ..sort((a, b) => _campScore(t, b, spring: false).compareTo(_campScore(t, a, spring: false)));
    return sorted.take(autumnMax).map((p) => p.id).toList();
  }

  double _campScore(Team t, Player p, {required bool spring}) {
    final grow = RosterEngine.potentialOvr(p) - p.ovr; // これから伸びる見込み
    final first = t.roster1G.contains(p.id) ? (spring ? 25.0 : 0.0) : 0.0;
    return p.ovr * (spring ? 0.6 : 0.2) + grow * 1.5 + first - (spring ? 0 : (p.age - 22).clamp(0, 10) * 1.5);
  }

  /// キャンプの開始・終了（1/1 春季開始、2/1 春季終了、11/1 秋季開始、12/1 秋季終了）
  void _campEvents(DateTime from, DateTime to) {
    var d = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day);
    while (d.isBefore(end)) {
      d = d.add(const Duration(days: 1));
      if (d.day == 16 && (d.month == 1 || d.month == 11)) _makeProposals(spring: d.month == 1); // キャンプの中ごろにも提案
      if (d.day != 1) continue;
      if (d.month == 1) {
        _startCamp(spring: true);
        _makeProposals(spring: true);
        _modelChanges();
      }
      if (d.month == 11) {
        _startCamp(spring: false);
        _makeProposals(spring: false);
      }
      if (d.month == 2 || d.month == 12) campProposals.clear(); // キャンプが終わったら、答えていない提案は消える
      if (d.month == 2) {
        for (final t in teams) {
          t.springCamp = [];
        }
      }
      if (d.month == 12) {
        for (final t in teams) {
          t.autumnCamp = [];
        }
      }
    }
  }

  /// キャンプが始まる：メンバーを決め（選んでいなければ自動）、費用を払う
  void _startCamp({required bool spring}) {
    for (final t in teams) {
      final ids = t.players.map((p) => p.id).toSet();
      var list = (spring ? t.springCamp : t.autumnCamp).where(ids.contains).toList();
      if (list.isEmpty) list = spring ? autoSpringCamp(t) : autoAutumnCamp(t);
      list = list.take(spring ? springMax : autumnMax).toList();
      if (spring) {
        t.springCamp = list;
      } else {
        t.autumnCamp = list;
      }
      finOf(t).add(spring ? '春季キャンプ' : '秋季キャンプ', -list.length * campCost);
      if (t.id == myTeamId) {
        _addNews(['${spring ? '春季' : '秋季'}キャンプが始まりました（${list.length}人・費用 ${formatSalary(list.length * campCost)}）']);
      }
    }
  }

  /// キャンプ中に、自球団のメンバーを足す・外す（足すときは費用がかかる）
  String? toggleCampMember(Team t, Player p, {required bool spring}) {
    final list = spring ? t.springCamp : t.autumnCamp;
    final active = spring ? inSpringCamp : inAutumnCamp;
    if (list.contains(p.id)) {
      list.remove(p.id);
      return null;
    }
    if (list.length >= (spring ? springMax : autumnMax)) return '${spring ? '春季' : '秋季'}キャンプは${spring ? springMax : autumnMax}人までです';
    list.add(p.id);
    if (active) finOf(t).add(spring ? '春季キャンプ' : '秋季キャンプ', -campCost);
    return null;
  }

  /// その日の練習の倍率
  ///  1月：春季キャンプ ×2、それ以外は2軍キャンプ ×1.3　11月：秋季キャンプ ×2、それ以外は休養（練習なし）
  ///  10月・12月：自主トレ ×0.8　それ以外：×1
  double _campMult(Team t, Player p, DateTime d) {
    if (d.month == 1) return t.springCamp.contains(p.id) ? 2.0 : 1.3;
    if (d.month == 11) return t.autumnCamp.contains(p.id) ? 2.0 : 0.0;
    return GrowthEngine.defaultPracticeMult(d);
  }

  // ───────── 3軍戦 ─────────

  /// 3軍の日程：2軍の試合がある日に、12球団の総当たり（円の回し方）で6試合を組む。今日より前の日は作らない
  void _buildThirdMatches() {
    final today = DateUtils.dateOnly(currentDate);
    final days = <DateTime>{
      for (final m in farmMatches)
        if (!AppState.isSpecialType(m.matchType) && m.matchType != 'ALLSTAR') DateUtils.dateOnly(m.date),
    }.toList()
      ..sort();
    final ids = [for (final t in teams) t.id];
    thirdMatches = [];
    if (ids.length < 2) return;
    if (ids.length.isOdd) ids.add('');
    final n = ids.length;
    for (var d = 0; d < days.length; d++) {
      if (days[d].isBefore(today)) continue;
      final r = d % (n - 1);
      // 1番目の球団は動かさず、残りを r だけ回す
      final rot = [ids[0], for (var i = 0; i < n - 1; i++) ids[1 + (i + r) % (n - 1)]];
      for (var i = 0; i < n ~/ 2; i++) {
        final a = rot[i], b = rot[n - 1 - i];
        if (a.isEmpty || b.isEmpty) continue;
        final swap = (d + i).isOdd;
        thirdMatches.add(Match(homeTeamId: swap ? b : a, awayTeamId: swap ? a : b, date: days[d], matchType: 'LEAGUE'));
      }
    }
  }

  /// 3軍のオーダー（3軍監督が組む）：1軍・今日の2軍戦に出た選手を除いた中から、優先する選手 → 伸ばす価値のある若手の順。
  ///  野手が9人に足りない分は、今日の2軍戦に出た野手を借りる（2軍から派遣。3人目の値に入れる）。
  ///  seed が null のときはばらつきなし（オーダー画面の見込み）
  (List<Player>, List<Player>, Set<String>)? thirdOrder(Team t, {Set<String> used = const {}, int? seed}) {
    final pool = t.players.where((p) => !t.roster1G.contains(p.id) && !used.contains(p.id) && !p.isInjuredOut).toList();
    final fielders = pool.where((p) => !p.isPitcher).toList();
    final pitchers = pool.where((p) => p.isPitcher).toList();
    if (pitchers.isEmpty) return null; // 投げられる投手がいない日は3軍戦なし
    final mgr = staffOf(t)['3軍監督'];
    final skill = mgr == null ? 40 : ((mgr.trueAbil['代打判断'] ?? 50) + (mgr.trueAbil['人望'] ?? 50)) ~/ 2;
    final r = seed == null ? null : Random(seed);
    // 判断力が高い監督ほど、伸ばす価値のある若手（育成選手を含む）を選ぶ。低いと選び方がばらつく
    double score(Player p) =>
        (t.thirdPriority.contains(p.id) ? 1000 : 0) + (RosterEngine.potentialOvr(p) - p.ovr) * 1.5 + p.ovr * 0.3 - (p.age - 20).clamp(0, 15) + (r == null ? 0 : r.nextDouble() * (110 - skill) * 0.4);
    final fs = {for (final p in fielders) p.id: score(p)}, ps = {for (final p in pitchers) p.id: score(p)};
    fielders.sort((a, b) => fs[b.id]!.compareTo(fs[a.id]!));
    pitchers.sort((a, b) => ps[b.id]!.compareTo(ps[a.id]!));
    // 足りない野手は、今日の2軍戦に出た野手から（2軍から派遣）
    final borrowed = <String>{};
    if (fielders.length < 9) {
      final extra = t.players.where((p) => !p.isPitcher && !t.roster1G.contains(p.id) && used.contains(p.id) && !p.isInjuredOut).toList()
        ..sort((a, b) => a.ovr.compareTo(b.ovr));
      for (final p in extra.take(9 - fielders.length)) {
        borrowed.add(p.id);
        fielders.add(p);
      }
      if (fielders.length < 9) return null;
    }
    final nine = fielders.take(9).toList()
      // 打順：出塁・ミートの高い選手を上位、パワーのある選手を3〜5番に（簡易）
      ..sort((a, b) => (b.contactRight + b.power + b.eye).compareTo(a.contactRight + a.power + a.eye));
    var order = [...nine.skip(3).take(2), nine[0], nine[1], nine[2], ...nine.skip(5)];
    // 自分で組んだ打順：出られる選手はその打順のまま、出られない選手の打順は3軍監督の選んだ選手で埋める
    if (!t.thirdAuto && t.thirdLineup.isNotEmpty) {
      final can = {for (final p in [...pool.where((p) => !p.isPitcher), ...fielders]) p.id: p};
      final mine = [for (final id in t.thirdLineup.take(9)) can[id]];
      final rest = order.where((p) => !mine.any((m) => m?.id == p.id)).toList();
      order = [for (final m in mine) m ?? (rest.isEmpty ? null : rest.removeAt(0))].whereType<Player>().toList();
      while (order.length < 9 && rest.isNotEmpty) {
        order.add(rest.removeAt(0));
      }
    }
    return (order, pitchers.take(3).toList(), borrowed);
  }

  /// 3軍戦：1軍の試合にも2軍の試合にも出ていない選手から、3軍監督がオーダーを組む。
  /// 出場した選手に経験値（1軍の ×0.3）。今日の3軍の日程があれば、能力・調子で簡易に試合を計算して成績を残す
  void _playThirdTeam(Map<String, Set<String>> appearedToday) {
    final lineups = <String, (List<Player>, List<Player>)>{};
    for (final t in teams) {
      final o = thirdOrder(t, used: appearedToday[t.id] ?? const <String>{}, seed: currentDate.millisecondsSinceEpoch ^ t.id.hashCode);
      if (o == null) continue;
      lineups[t.id] = (o.$1, o.$2);
      for (final p in o.$1.where((p) => !o.$3.contains(p.id))) {
        GrowthEngine.gameExp(p, 0.3, coach: (st) => _gameExpMult(t, p, st));
      }
      for (final p in o.$2) {
        GrowthEngine.gameExp(p, 0.3, innings: 3, coach: (st) => _gameExpMult(t, p, st));
      }
    }
    final today = thirdMatches.where((m) => DateUtils.isSameDay(m.date, currentDate) && m.homeScore == null).toList();
    for (final m in today) {
      final h = lineups[m.homeTeamId], a = lineups[m.awayTeamId];
      if (h == null || a == null) {
        thirdMatches.remove(m); // 人数が足りず中止
        continue;
      }
      _simThird(m, h, a);
    }
  }

  /// 3軍戦の簡易計算：1打席ずつ、打者（ミート・パワー・選球眼・調子）と投手（球威・制球・球速・調子）で結果を決める。3人の投手が3回ずつ
  void _simThird(Match m, (List<Player>, List<Player>) home, (List<Player>, List<Player>) away) {
    final r = Random(m.date.millisecondsSinceEpoch ^ m.homeTeamId.hashCode ^ (m.awayTeamId.hashCode << 1));
    final d = currentDate;
    final score = [0, 0]; // 0=ビジター 1=ホーム
    final inn = [<int>[], <int>[]];
    final hits = [0, 0], errs = [0, 0], sbs = [0, 0], ab = [0, 0], hrs = [0, 0];
    final bat = [0, 0]; // 次の打者
    final pOuts = <String, int>{}, pEr = <String, int>{};
    String? winP, loseP;
    var leader = -1; // 今リードしている側
    final ab0 = {for (final pl in [...home.$1, ...away.$1]) pl.id: pl.thirdStats.atBats};
    for (final pl in [...home.$1, ...away.$1]) {
      pl.thirdStats.games++;
    }
    for (var i = 1; i <= 9; i++) {
      for (final side in [0, 1]) {
        if (i == 9 && side == 1 && score[1] > score[0]) break; // 9回裏はホームがリードなら無し
        final off = side == 0 ? away : home, def = side == 0 ? home : away;
        final pit = def.$2[min((i - 1) ~/ 3, def.$2.length - 1)];
        if (!pOuts.containsKey(pit.id)) {
          pOuts[pit.id] = 0;
          pit.thirdStats.pitchApps++;
          pit.thirdStats.games++;
          if (i == 1) pit.thirdStats.starts++;
        }
        final q = (pit.pitchPower + pit.control + pit.velocityNorm) / 3.0 + pit.conditionAt(d) * 2;
        var outs = 0, runs = 0;
        final base = List<Player?>.filled(3, null);
        while (outs < 3) {
          final b = off.$1[bat[side] % 9];
          bat[side]++;
          final s = b.thirdStats, ps = pit.thirdStats;
          final c = (b.contactLeft + b.contactRight) / 2.0 + b.conditionAt(d) * 2;
          var scored = 0;
          void home1(Player? x) {
            if (x == null) return;
            scored++;
            x.thirdStats.runs++;
          }

          // 押し出しで1つずつ進む（四球・失策）
          void force() {
            if (base[0] != null) {
              if (base[1] != null) {
                home1(base[2]);
                base[2] = base[1];
              }
              base[1] = base[0];
            }
            base[0] = b;
          }

          final x = r.nextDouble();
          final pBb = (0.075 + (b.eye - 50) * 0.0008 - (pit.control - 50) * 0.0008).clamp(0.03, 0.15);
          final pSo = (0.19 + (q - 50) * 0.003 - (c - 50) * 0.002).clamp(0.08, 0.35);
          if (x < pBb) {
            s.walks++;
            ps.pitcherWalks++;
            force();
          } else if (x < pBb + pSo) {
            s.atBats++;
            s.strikeouts++;
            ps.pitcherStrikeouts++;
            outs++;
          } else {
            s.atBats++;
            final pHit = (0.27 + (c - q) * 0.003).clamp(0.16, 0.42);
            if (r.nextDouble() < pHit) {
              s.hits++;
              ps.hitsAllowed++;
              hits[side]++;
              final hr = (0.06 + (b.power - 50) * 0.004 - (pit.pitchPower - 50) * 0.001).clamp(0.01, 0.3);
              final y = r.nextDouble();
              if (y < hr) {
                s.homeRuns++;
                ps.hrAllowed++;
                hrs[side]++;
                base.forEach(home1);
                home1(b);
                base.fillRange(0, 3, null);
              } else if (y < hr + 0.02) {
                s.triples++;
                base.forEach(home1);
                base.fillRange(0, 3, null);
                base[2] = b;
              } else if (y < hr + 0.2) {
                s.doubles++;
                home1(base[2]);
                home1(base[1]);
                final first = base[0];
                base.fillRange(0, 3, null);
                if (first != null) {
                  if (r.nextDouble() < 0.4) {
                    home1(first);
                  } else {
                    base[2] = first;
                  }
                }
                base[1] = b;
              } else {
                home1(base[2]);
                final second = base[1], first = base[0];
                base.fillRange(0, 3, null);
                if (second != null) {
                  if (r.nextDouble() < 0.6) {
                    home1(second);
                  } else {
                    base[2] = second;
                  }
                }
                if (first != null) {
                  if (base[2] == null && r.nextDouble() < 0.3) {
                    base[2] = first;
                  } else {
                    base[1] = first;
                  }
                }
                base[0] = b;
              }
            } else if (r.nextDouble() < 0.025) {
              errs[1 - side]++; // 失策で出塁
              force();
            } else {
              outs++;
              if (outs < 3 && base[2] != null && r.nextDouble() < 0.3) {
                // 犠飛・内野ゴロの間に生還（犠飛は打数に入れない）
                s.atBats--;
                s.sacFlies++;
                home1(base[2]);
                base[2] = null;
              }
            }
          }
          if (scored > 0) {
            s.rbi += scored;
            runs += scored;
            ps.earnedRuns += scored;
            pEr[pit.id] = (pEr[pit.id] ?? 0) + scored;
          }
          // サヨナラ
          if (i == 9 && side == 1 && score[1] + runs > score[0]) {
            if (scored > 0) s.walkoffs++;
            break;
          }
          // 盗塁：一塁に足の速い走者、二塁が空いている
          final rn = base[0];
          if (outs < 3 && rn != null && base[1] == null && rn.run >= 60 && r.nextDouble() < (rn.run - 55) * 0.012) {
            if (r.nextDouble() < (0.65 + (rn.run - 60) * 0.01).clamp(0.5, 0.9)) {
              rn.thirdStats.stolenBases++;
              sbs[side]++;
              base[1] = rn;
            } else {
              rn.thirdStats.caughtStealing++;
              outs++;
            }
            base[0] = null;
          }
        }
        pOuts[pit.id] = pOuts[pit.id]! + outs;
        pit.thirdStats.inningsPitched += outs;
        score[side] += runs;
        inn[side].add(runs);
        // 勝ち越し・逆転：そのときに投げていた両チームの投手（勝ち越した側の投手は直前の守りの投手）
        final now = score[0] > score[1] ? 0 : (score[1] > score[0] ? 1 : -1);
        if (now != leader) {
          leader = now;
          if (now >= 0) {
            final win = now == 0 ? away : home;
            final idx = now == 1 ? (i - 1) ~/ 3 : (i - 2).clamp(0, 8) ~/ 3;
            winP = win.$2[min(idx, win.$2.length - 1)].id;
            loseP = pit.id;
          } else {
            winP = null;
            loseP = null;
          }
        }
      }
    }
    for (final side in [0, 1]) {
      for (final b in (side == 0 ? away : home).$1) {
        ab[side] += b.thirdStats.atBats - ab0[b.id]!;
      }
    }
    for (final p in [...home.$2, ...away.$2]) {
      if (p.id == winP) p.thirdStats.wins++;
      if (p.id == loseP) p.thirdStats.losses++;
    }
    // 投手の成績表（チーム成績用）・打撃はチーム合計だけ
    Map<String, dynamic> pitBox((List<Player>, List<Player>) t) => {
          for (final p in t.$2)
            if (pOuts.containsKey(p.id)) p.listName: {'ip': '${pOuts[p.id]! ~/ 3}.${pOuts[p.id]! % 3}', 'er': pEr[p.id] ?? 0},
        };
    m.homeScore = score[1];
    m.awayScore = score[0];
    m.homeInningScores = inn[1];
    m.awayInningScores = inn[0];
    m.homeHits = hits[1];
    m.awayHits = hits[0];
    m.isPlayed = true;
    m.boxScore = {
      'third': true,
      'homePitcher': pitBox(home),
      'awayPitcher': pitBox(away),
      'homeBatters': {'チーム': {'ab': ab[1], 'h': hits[1], 'hr': hrs[1]}},
      'awayBatters': {'チーム': {'ab': ab[0], 'h': hits[0], 'hr': hrs[0]}},
      'homeE': errs[1],
      'awayE': errs[0],
      'homeSB': sbs[1],
      'awaySB': sbs[0],
    };
  }
}
