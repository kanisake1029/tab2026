part of 'app_state.dart';

/// 記録（企画書 5章）：月間MVP・表彰の記録
/// 試合ごとの選手の記録（選手 id → 古い順）と、球団ごとの公式戦の並び（連続試合出場の判定）
typedef GameLogs = (Map<String, List<GameLine>>, Map<String, List<String>>);

extension RecordOps on AppState {
  /// 今季の1軍の犠打・併殺打を、試合の実況から数え直す（以前は数えていなかったため）。犠飛は試合の中で数えている
  ///  打者は「…vs 球団 N番 名前」の行で分かり、そのあとの結果の行で数える
  void recountSacAndGidp() {
    if (seasonFinished) return;
    final byName = <String, Player?>{};
    for (final p in [...teams.expand((t) => t.players), ...freeAgents.map((f) => f.player)]) {
      byName[p.registeredName] = byName.containsKey(p.registeredName) ? null : p;
    }
    final sac = <String, int>{}, dp = <String, int>{};
    final vs = RegExp(r' vs .+? \d+番 (.+)$');
    for (final m in matches) {
      if (!m.isPlayed || !AppState._officialTypes.contains(m.matchType) || m.playByPlay == null) continue;
      String? cur;
      for (final l in m.playByPlay!) {
        final mm = vs.firstMatch(l);
        if (mm != null) {
          cur = mm.group(1);
          continue;
        }
        if (cur == null) continue;
        if ((l.contains('送りバント成功') && !l.contains('点追加')) || l.contains('スクイズ成功')) sac[cur] = (sac[cur] ?? 0) + 1;
        if (l.contains('(ダブルプレー)') && l.contains('ゴロ')) dp[cur] = (dp[cur] ?? 0) + 1;
      }
    }
    for (final e in byName.entries) {
      final p = e.value;
      if (p == null) continue;
      p.seasonStats.sacBunts = sac[e.key] ?? 0;
      p.seasonStats.gidp = dp[e.key] ?? 0;
    }
    debugPrint('SAC/GIDP RECOUNT: 犠打${sac.values.fold<int>(0, (a, b) => a + b)} 併殺打${dp.values.fold<int>(0, (a, b) => a + b)}');
  }

  // ───────── 試合ごとの記録（記録タブの条件検索） ─────────

  /// ゲームの中の公式戦すべて（過去のシーズンは保存から）。新しい試合が終わるまでは作り直さない
  Future<GameLogs> gameLogs() {
    final key = '$startYear|${matches.where((m) => m.isPlayed).length}';
    if (_glogCache != null && _glogKey == key) return _glogCache!;
    _glogKey = key;
    return _glogCache = _buildGameLogs();
  }

  Future<GameLogs> _buildGameLogs() async {
    final rows = await (db.select(db.seasonRecords)..where((t) => t.kind.equals('player'))).get();
    var first = startYear;
    for (final r in rows) {
      if (r.season < first) first = r.season;
    }
    final all = <Match>[];
    for (var y = first; y < startYear; y++) {
      for (final r in await db.loadMatchRows(y)) {
        try {
          all.add(Match.fromJson(jsonDecode(r.json) as Map<String, dynamic>));
        } catch (_) {}
      }
    }
    all.addAll(matches);
    final official = all.where((m) => m.isPlayed && m.boxScore != null && AppState._officialTypes.contains(m.matchType)).toList()
      ..sort((a, b) => a.date.compareTo(b.date) != 0 ? a.date.compareTo(b.date) : a.dh.compareTo(b.dh));
    // 名前 → 選手（glog の無い以前の試合用。同じ名前が2人いれば使わない）
    final byName = <String, Player?>{};
    for (final p in [...teams.expand((t) => t.players), ...freeAgents.map((f) => f.player)]) {
      byName[p.registeredName] = byName.containsKey(p.registeredName) ? null : p;
    }
    final out = <String, List<GameLine>>{};
    final teamGames = <String, List<String>>{};
    int outsOf(Object? ip) {
      final a = '${ip ?? '0'}'.split('.');
      return (int.tryParse(a[0]) ?? 0) * 3 + (a.length > 1 ? int.tryParse(a[1]) ?? 0 : 0);
    }

    for (final m in official) {
      final box = m.boxScore!;
      final k = '${m.date.toIso8601String().substring(0, 10)}#${m.dh}';
      teamGames.putIfAbsent(m.homeTeamId, () => []).add(k);
      teamGames.putIfAbsent(m.awayTeamId, () => []).add(k);
      final gl = box['glog'];
      if (gl is Map) {
        for (final e in gl.entries) {
          final v = Map<String, dynamic>.from(e.value as Map);
          final tid = '${v['t']}';
          out.putIfAbsent('${e.key}', () => []).add(GameLine(m.date, m.dh, tid, tid == m.homeTeamId ? m.awayTeamId : m.homeTeamId, v));
        }
        continue;
      }
      for (final home in [true, false]) {
        final tid = home ? m.homeTeamId : m.awayTeamId, opp = home ? m.awayTeamId : m.homeTeamId;
        final lines = <String, Map<String, dynamic>>{};
        final bat = box[home ? 'homeBatters' : 'awayBatters'];
        if (bat is Map) {
          for (final e in bat.entries) {
            final p = byName['${e.key}'];
            if (p == null || e.value is! Map) continue;
            final r = e.value as Map;
            lines[p.id] = {'ab': r['ab'] ?? 0, 'h': r['h'] ?? 0, 'hr': r['hr'] ?? 0, 'rbi': r['rbi'] ?? 0, 'bb': r['bb'] ?? 0, 'so': r['so'] ?? 0};
          }
        }
        final pit = box[home ? 'homePitcher' : 'awayPitcher'];
        if (pit is Map) {
          var i = 0;
          for (final e in pit.entries) {
            final p = byName['${e.key}'];
            final r = e.value;
            if (p != null && r is Map) {
              (lines[p.id] ??= {})['p'] = {'outs': outsOf(r['ip']), 'er': r['er'] ?? 0, 'so': r['so'] ?? 0, 'bb': r['bb'] ?? 0, 'dec': r['dec'] ?? '', 'st': i == 0 ? 1 : 0};
            }
            i++;
          }
        }
        for (final e in lines.entries) {
          out.putIfAbsent(e.key, () => []).add(GameLine(m.date, m.dh, tid, opp, e.value));
        }
      }
    }
    return (out, teamGames);
  }

  // ───────── 月間MVP ─────────
  // 月の初めの成績を控え、その月の分（差）で選ぶ。3・4月と9・10月は合算（NPB と同じ）

  static List<int> _snapOf(PlayerStats s) => [
        s.atBats, s.hits, s.doubles, s.triples, s.homeRuns, s.rbi, s.walks, s.stolenBases, s.sacFlies, s.games,
        s.inningsPitched, s.earnedRuns, s.pitcherStrikeouts, s.pitcherWalks, s.wins, s.saves, s.holds,
      ];

  /// 月の初めの成績を控える
  void _takeMonthSnap() {
    monthSnap = {for (final t in teams) for (final p in t.players) p.id: _snapOf(p.seasonStats)};
  }

  /// 7/1 などの月初め：前の月の月間MVP を選ぶ（label は「5月」「3・4月」など）
  void _monthlyMvp(String label) {
    final year = startYear;
    for (final lg in const ['CL', 'PL']) {
      (Player, Team, double, String)? bestBat, bestPit;
      for (final t in teams.where((t) => t.league == lg)) {
        for (final p in t.players) {
          final now = _snapOf(p.seasonStats);
          final was = monthSnap[p.id] ?? List.filled(now.length, 0);
          int d(int i) => now[i] - (i < was.length ? was[i] : 0);
          final ab = d(0), h = d(1), d2 = d(2), d3 = d(3), hr = d(4), rbi = d(5), bb = d(6), sb = d(7), sf = d(8);
          final pa = ab + bb + sf;
          if (!p.isPitcher && pa >= 50) {
            final obp = (h + bb) / pa;
            final slg = ab == 0 ? 0.0 : (h + d2 + d3 * 2 + hr * 3) / ab;
            final score = (obp + slg) * pa / 4 + hr * 1.5 + rbi * 0.3 + sb * 0.3;
            final line = '打率${ab == 0 ? '-' : (h / ab).toStringAsFixed(3).replaceFirst(RegExp(r'^0'), '')} $hr本 $rbi打点';
            if (bestBat == null || score > bestBat.$3) bestBat = (p, t, score, line);
          }
          final outs = d(10), er = d(11), k = d(12), w = d(14), sv = d(15), hld = d(16);
          if (p.isPitcher && (outs >= 45 || sv + hld >= 5)) {
            final score = outs / 3 * 0.8 + k * 0.2 + w * 3 + sv * 2 + hld * 1.2 - er * 1.5;
            final era = outs == 0 ? 0.0 : er * 27 / outs;
            final line = '$w勝${sv > 0 ? ' $svセーブ' : ''}${hld > 0 ? ' $hldホールド' : ''} 防御率${era.toStringAsFixed(2)} ${outs ~/ 3}回';
            if (bestPit == null || score > bestPit.$3) bestPit = (p, t, score, line);
          }
        }
      }
      for (final (kind, e) in [('野手', bestBat), ('投手', bestPit)]) {
        if (e == null) continue;
        monthlyMvps.add({'year': year, 'month': label, 'league': lg, 'kind': kind, 'id': e.$1.id, 'name': e.$1.registeredName, 'team': e.$2.id, 'teamName': teamShort(e.$2), 'line': e.$4});
        e.$1.honors.add('$year年$label 月間MVP（$kind）');
        if (e.$2.id == myTeamId) _addNews(['$label の月間MVP（$kind）に ${e.$1.registeredName} が選ばれました（${e.$4}）']);
      }
    }
    _takeMonthSnap();
  }

  /// 毎日の処理から呼ぶ：5〜9月の1日に、前の月の月間MVP（5/1 は 3・4月の分）
  void _monthlyMvpOn(DateTime d) {
    if (d.day != 1 || seasonFinished || d.year != startYear) return;
    if (d.month < 5 || d.month > 9) return;
    _monthlyMvp(d.month == 5 ? '3・4月' : '${d.month - 1}月');
  }

  // ───────── 表彰の記録 ─────────

  /// シーズンの表彰を、選手ごとの表彰の記録に書き込む
  void _recordHonors(int year, Map<String, dynamic> awards) {
    final byId = {for (final t in teams) for (final p in t.players) p.id: p};
    void give(dynamic winners, String label) {
      if (winners is! List) return;
      for (final w in winners) {
        if (w is Map && byId[w['id']] != null) byId[w['id']]!.honors.add('$year年 $label');
      }
    }
    final leagues = awards['leagues'];
    if (leagues is Map) {
      for (final lgEntry in leagues.values) {
        if (lgEntry is! Map) continue;
        for (final tt in (lgEntry['titles'] as List? ?? const [])) {
          if (tt is Map) give(tt['winners'], '${tt['title']}');
        }
        if (lgEntry['mvp'] is Map) give(lgEntry['mvp']['winners'], 'MVP');
        if (lgEntry['rookie'] is Map) give(lgEntry['rookie']['winners'], '新人王');
        for (final b in (lgEntry['b9'] as List? ?? const [])) {
          if (b is Map) give(b['winners'], 'ベストナイン（${b['pos']}）');
        }
        for (final g in (lgEntry['gg'] as List? ?? const [])) {
          if (g is Map) give(g['winners'], 'ゴールデングラブ（${g['pos']}）');
        }
      }
    }
    if (awards['sawamura'] is Map) give(awards['sawamura']['winners'], '沢村賞');
    if (awards['comeback'] is Map) give(awards['comeback']['winners'], 'カムバック賞');
    _makerCollabsFromAwards(year, awards);
  }

  // ───────── 試合ごとの記録・連続記録・節目 ─────────

  /// 試合が終わったら：猛打賞・マルチヒット・サイクル・得点・完投・完封・ノーヒットノーラン・完全試合・連続記録・節目の記録
  void _gameRecords(GameSession s) {
    _gameFirsts(s); // プロ初出場・初安打・初N番起用など（年表と球団の記録）
    _recordStreaks(s);
    const hitKinds = ['単打', '二塁打', '三塁打', 'ホームラン'];
    // 試合ごとの選手の記録（記録タブの条件検索・連続記録に使う）：選手 id → 値
    final glog = <String, Map<String, dynamic>>{};
    s.boxScore['glog'] = glog;
    // 打席ごとの結果の並び（H安打・O凡退・Kは三振・B四死球・S犠打など）
    final seqs = <String, StringBuffer>{};
    {
      final last = <String, PitchEvent>{};
      for (final e in s.pitchEvents) {
        final k = '${e.battingHome}|${e.paIndex}';
        final l = last[k];
        if (l == null || e.pitchNo >= l.pitchNo) last[k] = e;
      }
      final ordered = last.values.toList()..sort((a, b) => a.paIndex.compareTo(b.paIndex));
      final byName = {for (final home in [true, false]) for (final p in (home ? s.homeTeam : s.awayTeam).players) '$home|${p.registeredName}': p};
      for (final e in ordered) {
        final r = paResult(PitchRec(paIndex: e.paIndex, pitchNo: e.pitchNo, battingHome: e.battingHome, batter: e.batter, pitcher: e.pitcher, result: e.result, outcome: e.outcome, balls: e.balls, strikes: e.strikes));
        if (r == null) continue;
        // 打者の詳しい成績（コース・打球方向・球種・球速）
        final bp = byName['${e.battingHome}|${e.batter}'];
        if (bp != null) BattingSplits.add(bp.seasonStats, r, x: e.x, z: e.z, bats: e.batterHand, pitchName: e.pitchName, speed: e.speed, landX: e.landX, landY: e.landY);
        // 投手の被打率（同じ項目を p 付きで）
        final pp = byName['${!e.battingHome}|${e.pitcher}'];
        if (pp != null) BattingSplits.add(pp.seasonStats, r, x: e.x, z: e.z, bats: e.batterHand, pitchName: e.pitchName, speed: e.speed, landX: e.landX, landY: e.landY, prefix: 'p');
        final c = r.h > 0 ? 'H' : (r.bb + r.hbp > 0 ? 'B' : (r.so > 0 ? 'K' : (r.ab > 0 ? 'O' : 'S')));
        seqs.putIfAbsent('${e.battingHome}|${e.batter}', () => StringBuffer()).write(c);
      }
    }
    for (final home in [true, false]) {
      final t = home ? s.homeTeam : s.awayTeam;
      final names = {for (final p in t.players) p.registeredName};
      final hits = <String, Map<String, int>>{};
      final runs = <String, int>{};
      final atBat = <String>{};
      for (final e in s.pitchEvents) {
        if (e.battingHome != home) continue;
        atBat.add(e.batter);
        if (hitKinds.contains(e.outcome)) {
          final m = hits.putIfAbsent(e.batter, () => {});
          m[e.outcome] = (m[e.outcome] ?? 0) + 1;
        }
        for (final mv in e.runMoves) {
          if (mv.to == 4 && !mv.out && names.contains(mv.name)) runs[mv.name] = (runs[mv.name] ?? 0) + 1;
        }
      }
      s.forcedRuns.forEach((n, c) {
        if (names.contains(n)) runs[n] = (runs[n] ?? 0) + c;
      });
      final appeared = {for (final p in home ? s.homeAppeared : s.awayAppeared) p.id: p};
      for (final p in appeared.values) {
        final h = hits[p.registeredName]?.values.fold<int>(0, (a, b) => a + b) ?? 0;
        final st = p.seasonStats;
        st.runs += runs[p.registeredName] ?? 0;
        if (h >= 2) st.multiHit++;
        if (h >= 3) st.mouda++;
        if (hitKinds.every((k) => (hits[p.registeredName]?[k] ?? 0) > 0)) {
          st.cycles++;
          _addNews(['${teamShort(t)}の${p.registeredName}がサイクル安打を達成！']);
          p.honors.add('$startYear年 サイクル安打');
        }
        // 連続試合出場・連続試合安打（打席に立って安打がなければ途切れる）
        p.playStreak++;
        if (p.playStreak > p.playStreakBest) p.playStreakBest = p.playStreak;
        if (h > 0) {
          p.hitStreak++;
          if (p.hitStreak > p.hitStreakBest) p.hitStreakBest = p.hitStreak;
          if (p.hitStreak == 20 || p.hitStreak == 30) _addNews(['${p.registeredName}（${teamShort(t)}）が${p.hitStreak}試合連続安打']);
        } else if (atBat.contains(p.registeredName)) {
          p.hitStreak = 0;
        }
        // 節目の記録（プロ初も）
        final total = PlayerStats()..add(p.career)..add(st);
        final d = s.match.date;
        final rbiToday = ((s.boxScore[home ? 'homeBatters' : 'awayBatters'] as Map?)?[p.registeredName] as Map?)?['rbi'] as int? ?? 0;
        final sbToday = s.playByPlay.where((l) => l.startsWith('${p.registeredName} ') && l.contains('盗成功')).length;
        {
          final row = (s.boxScore[home ? 'homeBatters' : 'awayBatters'] as Map?)?[p.registeredName];
          final seq = seqs['$home|${p.registeredName}']?.toString() ?? '';
          if (row is Map || seq.isNotEmpty) {
            final hk = hits[p.registeredName] ?? const <String, int>{};
            glog[p.id] = {
              't': t.id,
              'ab': row is Map ? row['ab'] ?? 0 : 0, 'h': h, '2b': hk['二塁打'] ?? 0, '3b': hk['三塁打'] ?? 0, 'hr': hk['ホームラン'] ?? 0,
              'rbi': rbiToday, 'bb': row is Map ? row['bb'] ?? 0 : 0, 'so': row is Map ? row['so'] ?? 0 : 0, 'sb': sbToday, 'r': runs[p.registeredName] ?? 0,
              'seq': seq,
            };
          }
        }
        if (!p.isPitcher || atBat.contains(p.registeredName)) {
          _milestone(p, t, d, '試合出場', total.games, 1, const [500, 1000, 1500, 2000, 2500], first: false);
          _milestone(p, t, d, '安打', total.hits, h, const [500, 1000, 1500, 2000, 2500, 3000]);
          _milestone(p, t, d, '本塁打', total.homeRuns, hits[p.registeredName]?['ホームラン'] ?? 0, const [50, 100, 150, 200, 250, 300, 350, 400, 450, 500]);
          _milestone(p, t, d, '打点', total.rbi, rbiToday, const [500, 1000, 1500]);
          _milestone(p, t, d, '盗塁', total.stolenBases, sbToday, const [100, 200, 300, 400]);
        }
      }
      // 出場しなかった野手は連続試合出場が途切れる
      for (final p in t.players) {
        if (!p.isPitcher && !appeared.containsKey(p.id)) p.playStreak = 0;
      }
      // 投手：完投・完封・ノーヒットノーラン・完全試合、節目（勝利・セーブ）
      final ps = home ? s.homePitchers : s.awayPitchers;
      final box = (s.boxScore[home ? 'homePitcher' : 'awayPitcher'] as Map?) ?? const {};
      if (ps.length == 1) {
        final p = ps.first;
        final oppScore = home ? s.state.awayScore : s.state.homeScore;
        final oppHits = home ? s.awayHits : s.homeHits;
        p.seasonStats.completeGames++;
        if (oppScore == 0) p.seasonStats.shutouts++;
        if (oppHits == 0) {
          final row = box[p.registeredName];
          final bb = row is Map ? (row['bb'] ?? 0) as int : 0;
          final hbp = s.pitchEvents.where((e) => e.battingHome != home && e.result == '死球').length;
          final err = s.pitchEvents.where((e) => e.battingHome != home && e.errorBy.isNotEmpty).length;
          final perfect = bb == 0 && hbp == 0 && err == 0;
          if (perfect) {
            p.seasonStats.perfects++;
          } else {
            p.seasonStats.noHitters++;
          }
          final label = perfect ? '完全試合' : 'ノーヒットノーラン';
          p.honors.add('$startYear年 $label');
          _addNews(['${teamShort(t)}の${p.registeredName}が$labelを達成！']);
        }
      }
      for (final p in ps) {
        final row = box[p.registeredName];
        final dec = row is Map ? row['dec'] : null;
        final total = PlayerStats()..add(p.career)..add(p.seasonStats);
        final d = s.match.date;
        final kToday = row is Map ? (row['so'] ?? 0) as int : 0;
        final e0 = glog[p.id] ?? <String, dynamic>{'t': t.id};
        e0['p'] = {'outs': s.pitcherOuts[p.id] ?? 0, 'er': row is Map ? row['er'] ?? 0 : 0, 'so': kToday, 'bb': row is Map ? row['bb'] ?? 0 : 0, 'dec': dec ?? '', 'st': identical(p, ps.first) ? 1 : 0};
        glog[p.id] = e0;
        _milestone(p, t, d, '登板', total.apps, 1, const [300, 500, 700, 800, 900], first: false);
        _milestone(p, t, d, '奪三振', total.pitcherStrikeouts, kToday, const [1000, 1500, 2000, 2500, 3000]);
        if (dec == '勝') _milestone(p, t, d, '勝', total.wins, 1, const [50, 100, 150, 200, 250]);
        if (dec == 'S') _milestone(p, t, d, 'セーブ', total.saves, 1, const [50, 100, 150, 200, 250, 300]);
        if (dec == 'H') _milestone(p, t, d, 'ホールド', total.holds, 1, const [100, 150, 200, 250, 300]);
      }
    }
  }

  /// 試合ごとの回数記録・連続記録・得点圏の成績（公式戦）
  ///  打者：連続試合安打・出塁・出場・本塁打、2本塁打以上の試合、サヨナラ打、得点圏の打数と安打
  ///  投手：連続イニング無失点、救援での連続試合無失点、クオリティスタート、2桁奪三振
  void _recordStreaks(GameSession s) {
    final d = s.match.date;
    final walkoff = s.playByPlay.any((l) => l.contains('【サヨナラ') || l.contains('サヨナラホームラン') || l.contains('サヨナラ押し出し'));
    final lastBatter = s.pitchEvents.isEmpty ? '' : s.pitchEvents.last.batter;
    for (final home in [true, false]) {
      final t = home ? s.homeTeam : s.awayTeam;
      final box = (s.boxScore[home ? 'homeBatters' : 'awayBatters'] as Map?) ?? const {};
      // 得点圏：打席ごと（最初の1球の塁の状態と、打席の結果）
      final first = <int, PitchEvent>{}, last = <int, PitchEvent>{};
      for (final e in s.pitchEvents) {
        if (e.battingHome != home) continue;
        first.putIfAbsent(e.paIndex, () => e);
        final l = last[e.paIndex];
        if (l == null || e.pitchNo >= l.pitchNo) last[e.paIndex] = e;
      }
      final risp = <String, List<int>>{}; // 名前 → [打数, 安打]
      final hbp = <String, int>{};
      for (final k in last.keys) {
        final e = last[k]!;
        if (e.result == '死球') hbp[e.batter] = (hbp[e.batter] ?? 0) + 1;
        final b = first[k]!.basesBefore;
        if (!(b.length > 2 && (b[1] || b[2]))) continue;
        final r = paResult(PitchRec(paIndex: e.paIndex, pitchNo: e.pitchNo, battingHome: e.battingHome, batter: e.batter, pitcher: e.pitcher, result: e.result, outcome: e.outcome, balls: e.balls, strikes: e.strikes));
        if (r == null) continue;
        final x = risp.putIfAbsent(e.batter, () => [0, 0]);
        x[0] += r.ab;
        x[1] += r.h;
      }
      for (final p in (home ? s.homeAppeared : s.awayAppeared)) {
        final row = box[p.registeredName];
        final st = p.seasonStats;
        final rr = risp[p.registeredName];
        if (rr != null) {
          st.rispAB += rr[0];
          st.rispH += rr[1];
        }
        if (row is! Map) continue;
        final ab = (row['ab'] ?? 0) as int, h = (row['h'] ?? 0) as int, bb = (row['bb'] ?? 0) as int, hr = (row['hr'] ?? 0) as int;
        final hp = hbp[p.registeredName] ?? 0;
        final pa = ab + bb + hp > 0;
        p.streakStep('play', true, d);
        if (pa) {
          p.streakStep('hit', h > 0, d);
          p.streakStep('onBase', h + bb + hp > 0, d);
          p.streakStep('hr', hr > 0, d);
        }
        if (hr >= 2) st.multiHR++;
        if (walkoff && home && p.registeredName == lastBatter) st.walkoffs++;
      }
      // 出場しなかった野手は連続試合出場が途切れる
      final appeared = {for (final p in (home ? s.homeAppeared : s.awayAppeared)) p.id};
      for (final p in t.players) {
        if (!p.isPitcher && !appeared.contains(p.id)) p.streakStep('play', false, d);
      }
      // 投手
      final ps = home ? s.homePitchers : s.awayPitchers;
      final prow = (s.boxScore[home ? 'homePitcher' : 'awayPitcher'] as Map?) ?? const {};
      for (var i = 0; i < ps.length; i++) {
        final p = ps[i];
        final row = prow[p.registeredName];
        final er = row is Map ? (row['er'] ?? 0) as int : 0, so = row is Map ? (row['so'] ?? 0) as int : 0;
        final outs = s.pitcherOuts[p.id] ?? 0;
        p.streakStep('scoreless', er == 0, d, add: outs);
        if (i == 0) {
          if (outs >= 18 && er <= 3) p.seasonStats.qs++;
        } else {
          p.streakStep('relief', er == 0, d);
        }
        if (so >= 10) p.seasonStats.tenK++;
      }
    }
  }

  /// 以前のセーブ：今季の1軍・公式戦の実況ログとボックススコアから、記録していなかったものを組み立て直す（一度だけ）
  ///  ・エラーで出塁したのに安打に数えていた分を、打者・投手・チームの安打から引く
  ///  ・得点圏の打数と安打、連続記録（日付つき）、2本塁打以上の試合・サヨナラ打・QS・2桁奪三振
  ///  ・スコアボードの失策（E）とチームの盗塁の数（ボックススコアに無い試合）
  void rebuildSeasonRecords() {
    final global = <String, Player?>{};
    for (final t in teams) {
      for (final p in t.players) {
        global[p.registeredName] = global.containsKey(p.registeredName) ? null : p;
        p.streaks = {};
        final st = p.seasonStats;
        st.rispAB = 0;
        st.rispH = 0;
        st.multiHR = 0;
        st.walkoffs = 0;
        st.qs = 0;
        st.tenK = 0;
      }
    }
    final games = [
      for (final m in matches)
        if (m.homeScore != null && (m.matchType == 'LEAGUE' || m.matchType == 'INTERLEAGUE') && m.boxScore != null) m
    ]..sort((a, b) => a.date.compareTo(b.date));
    final head = RegExp(r'^【(\d+)回(表|裏)');
    final paRe = RegExp(r'^(.+?) (先発|救援) (.+?) vs (.+) (\d+)番 (.+)$');
    final pitchRe = RegExp(r'^\d+球目');
    final bracketRe = RegExp(r'\[([^\]]*)\]\s*$');
    for (final m in games) {
      final home = teamById(m.homeTeamId), away = teamById(m.awayTeamId);
      if (home == null || away == null) continue;
      Player? find(Team t, String name) => t.players.where((x) => x.registeredName == name).firstOrNull ?? global[name];
      final box = m.boxScore!;
      final log = m.playByPlay ?? const <String>[];
      // ---- 実況ログを打席ごとに ----
      var top = true;
      var bat = '', pit = '', lastLine = '';
      var risp = false, firstPitch = true;
      var hE = 0, aE = 0, hSb = 0, aSb = 0;
      final rispAB = <String, int>{}, rispH = <String, int>{}, hbp = <String, int>{};
      var lastBatHome = false;
      var lastBat = '';
      void endPa() {
        if (bat.isEmpty || lastLine.isEmpty) return;
        final l = lastLine;
        final key = '$top|$bat';
        final isHit = !l.contains('エラー') && (l.contains('ヒット') || l.contains('ツーベース') || l.contains('スリーベース') || l.contains('ホームラン'));
        final noAb = l.contains('四球') || l.contains('死球') || l.contains('敬遠') || l.contains('犠牲フライ') || l.contains('犠打') || l.contains('送りバント');
        if (l.contains('死球')) hbp[key] = (hbp[key] ?? 0) + 1;
        if (risp && !noAb) {
          rispAB[key] = (rispAB[key] ?? 0) + 1;
          if (isHit) rispH[key] = (rispH[key] ?? 0) + 1;
        }
        // エラーで出塁：以前は安打に数えていたので引く
        if (l.contains('エラー出塁')) {
          final bt = top ? away : home, pt = top ? home : away;
          final b = find(bt, bat), p = find(pt, pit);
          if (b != null && b.seasonStats.hits > 0) b.seasonStats.hits--;
          if (p != null && p.seasonStats.hitsAllowed > 0) p.seasonStats.hitsAllowed--;
          final row = (box[top ? 'awayBatters' : 'homeBatters'] as Map?)?[bat];
          if (row is Map && ((row['h'] ?? 0) as int) > 0) row['h'] = (row['h'] as int) - 1;
          if (top) {
            if ((m.awayHits ?? 0) > 0) m.awayHits = m.awayHits! - 1;
          } else {
            if ((m.homeHits ?? 0) > 0) m.homeHits = m.homeHits! - 1;
          }
        }
        lastBatHome = !top;
        lastBat = bat;
      }

      for (final l in log) {
        final h = head.firstMatch(l);
        if (h != null) {
          endPa();
          bat = '';
          lastLine = '';
          top = h.group(2) == '表';
          continue;
        }
        final pa = paRe.firstMatch(l);
        if (pa != null) {
          endPa();
          pit = pa.group(3)!;
          bat = pa.group(6)!;
          risp = false;
          firstPitch = true;
          lastLine = '';
          continue;
        }
        if (l.contains('盗成功')) {
          if (top) {
            aSb++;
          } else {
            hSb++;
          }
        }
        if (l.contains('エラー')) {
          if (top) {
            hE++;
          } else {
            aE++;
          }
        }
        if (pitchRe.hasMatch(l) || l.startsWith('敬遠')) {
          if (firstPitch) {
            final br = bracketRe.firstMatch(l)?.group(1) ?? '';
            risp = br.contains('2塁') || br.contains('3塁');
            firstPitch = false;
          }
          lastLine = l;
        }
      }
      endPa();
      box['homeE'] ??= hE;
      box['awayE'] ??= aE;
      box['homeSB'] ??= hSb;
      box['awaySB'] ??= aSb;
      final walkoff = log.any((l) => l.contains('サヨナラ')) && (m.homeScore ?? 0) > (m.awayScore ?? 0);
      // ---- ボックススコアから、選手ごとの記録 ----
      for (final side in [true, false]) {
        final t = side ? home : away;
        final topKey = !side; // 表の攻撃＝ビジター
        final rows = (box[side ? 'homeBatters' : 'awayBatters'] as Map?) ?? const {};
        final appeared = <String>{};
        for (final e in rows.entries) {
          final p = find(t, e.key as String);
          if (p == null || e.value is! Map) continue;
          final v = e.value as Map;
          final ab = (v['ab'] ?? 0) as int, hh = (v['h'] ?? 0) as int, bb = (v['bb'] ?? 0) as int, hr = (v['hr'] ?? 0) as int;
          final key = '$topKey|${e.key}';
          final hp = hbp[key] ?? 0;
          appeared.add(p.id);
          p.streakStep('play', true, m.date);
          if (ab + bb + hp > 0) {
            p.streakStep('hit', hh > 0, m.date);
            p.streakStep('onBase', hh + bb + hp > 0, m.date);
            p.streakStep('hr', hr > 0, m.date);
          }
          if (hr >= 2) p.seasonStats.multiHR++;
          p.seasonStats.rispAB += rispAB[key] ?? 0;
          p.seasonStats.rispH += rispH[key] ?? 0;
          if (walkoff && side && lastBatHome && e.key == lastBat) p.seasonStats.walkoffs++;
        }
        for (final p in t.players) {
          if (!p.isPitcher && !appeared.contains(p.id) && t.roster1G.contains(p.id)) p.streakStep('play', false, m.date);
        }
        final prow = (box[side ? 'homePitcher' : 'awayPitcher'] as Map?) ?? const {};
        var i = 0;
        for (final e in prow.entries) {
          final p = find(t, e.key as String);
          final v = e.value;
          if (p != null && v is Map) {
            final er = (v['er'] ?? 0) as int, so = (v['so'] ?? 0) as int;
            final ip = '${v['ip'] ?? '0'}'.split('.');
            final outs = (int.tryParse(ip[0]) ?? 0) * 3 + (ip.length > 1 ? int.tryParse(ip[1]) ?? 0 : 0);
            p.streakStep('scoreless', er == 0, m.date, add: outs);
            if (i == 0) {
              if (outs >= 18 && er <= 3) p.seasonStats.qs++;
            } else {
              p.streakStep('relief', er == 0, m.date);
            }
            if (so >= 10) p.seasonStats.tenK++;
          }
          i++;
        }
      }
    }
    // 以前の連続試合安打・出場の数も、組み立て直した値に合わせる
    for (final p in teams.expand((t) => t.players)) {
      final h = p.streaks['hit'], pl = p.streaks['play'];
      if (h != null) {
        p.hitStreak = (h['cur'] ?? 0) as int;
        p.hitStreakBest = max(p.hitStreakBest, (h['best'] ?? 0) as int);
      }
      if (pl != null) {
        p.playStreak = (pl['cur'] ?? 0) as int;
        p.playStreakBest = max(p.playStreakBest, (pl['best'] ?? 0) as int);
      }
    }
  }

  /// 節目の記録（その試合で total がしきい値を超えたら、お知らせと記録）。first：プロ初（初安打・初本塁打・初勝利など）も残す
  ///  記録は「2026年6月3日 通算100本塁打達成」の形で、選手の経歴に残る
  void _milestone(Player p, Team t, DateTime d, String label, int total, int gained, List<int> marks, {bool first = true}) {
    if (gained <= 0) return;
    final day = '${d.year}年${d.month}月${d.day}日';
    // プロ初の記録は年表（_gameFirsts）に書く
    for (final m in marks) {
      if (total >= m && total - gained < m) {
        final text = '通算$m$label';
        p.honors.add('$day $text達成（${teamShort(t)}）');
        _chron(d, t.id, 'milestone', '${p.registeredName}が$text達成。', pid: p.id, pt: '$text達成。');
        _addNews(['${p.registeredName}（${teamShort(t)}）が$textを達成！']);
      }
    }
  }

  // ───────── 引退した選手・殿堂入り ─────────

  /// 引退した選手の記録を残す（1軍で30試合以上の選手。歴代記録と殿堂入りの投票に使う）
  void _keepRetiree(Player p, Team t, int year) {
    if (retirees.any((e) => e['id'] == p.id)) return; // 引退した選手はすべて残す（OB の経歴・年度別成績）
    retirees.add({
      'id': p.id, 'name': p.registeredName, 'team': t.id, 'teamName': teamShort(t), 'year': year, 'age': p.age, 'proYears': p.proYears,
      'draftInfo': p.draftInfo, 'moves': List<String>.from(p.moves), 'uniform': p.uniformText,
      'pitcher': p.isPitcher, 'pos': p.mainPosition, 'career': p.career.toJson(), 'honors': List<String>.from(p.honors),
      'hitStreakBest': p.hitStreakBest, 'playStreakBest': p.playStreakBest, 'ballots': 0, 'hof': false,
    });
  }

  /// 殿堂入りの点数（通算成績・タイトル・表彰から。100点が満票の目安）
  static double hofScore(Map<String, dynamic> e) {
    final c = PlayerStats.fromJson(Map<String, dynamic>.from(e['career'] as Map));
    final honors = List<String>.from(e['honors'] as List? ?? const []);
    int count(String w) => honors.where((h) => h.contains(w)).length;
    final titles = honors.where((h) => !h.contains('月間MVP') && !h.contains('ベストナイン') && !h.contains('ゴールデングラブ') && !h.contains('達成') && !h.contains('サイクル') && !h.contains('ノーヒット') && !h.contains('完全試合') && !h.contains('MVP') && !h.contains('新人王') && !h.contains('プロ初')).length;
    double v;
    if (e['pitcher'] == true) {
      v = c.wins / 200 * 45 + c.saves / 250 * 35 + c.pitcherStrikeouts / 2500 * 15 + count('沢村賞') * 8;
    } else {
      v = c.hits / 2000 * 40 + c.homeRuns / 400 * 30 + c.stolenBases / 400 * 10 + (c.atBats >= 4000 ? (c.battingAverage - 0.270) * 200 : 0);
    }
    v += titles * 4 + count('MVP') * 8 + count('ベストナイン') * 2.5 + count('ゴールデングラブ') * 1.2 + count('月間MVP') * 0.6;
    return v;
  }

  /// 殿堂入りの投票（毎年のシーズンの終わり）。引退から5年たった選手が対象。得票率75%以上で殿堂入り、15回まで
  void _hallOfFameVote(int year) {
    final r = Random(year * 4241);
    for (final e in retirees) {
      if (e['hof'] == true) continue;
      final ry = (e['year'] as num).toInt();
      final ballots = (e['ballots'] as num? ?? 0).toInt();
      if (year - ry < 5 || ballots >= 15) continue;
      final score = hofScore(e);
      if (score < 25 && ballots == 0) {
        e['ballots'] = 15; // 候補にならない（1回目に5%未満と同じ扱い）
        continue;
      }
      final pct = (score * 0.95 + ballots * 1.5 + (r.nextDouble() - 0.5) * 16).clamp(0.0, 100.0);
      e['ballots'] = ballots + 1;
      e['lastPct'] = (pct * 10).round() / 10;
      if (pct >= 75) {
        e['hof'] = true;
        e['hofYear'] = year;
        _addNews(['殿堂入り：${e['name']}（元${e['teamName']}）が得票率${e['lastPct']}%で選ばれました']);
      } else if (pct < 5) {
        e['ballots'] = 15; // 得票率5%未満は候補から外れる
      }
    }
  }

  // ───────── 自分の戦績 ─────────

  /// シーズンの終わりに、自分（監督）の戦績を残す
  void _recordMyCareer(int year, Map<String, int> ranks, Map<String, List<int>> records, String? championId) {
    final t = myTeam;
    if (t == null) return;
    final rec = records[t.id] ?? const [0, 0, 0];
    myCareer.removeWhere((e) => e['year'] == year);
    myCareer.add({
      'year': year, 'team': t.id, 'teamName': t.name, 'league': t.league,
      'w': rec[0], 'l': rec[1], 'd': rec[2], 'rank': ranks[t.id] ?? 0,
      'pennant': ranks[t.id] == 1, 'champion': championId == t.id,
    });
  }
}
