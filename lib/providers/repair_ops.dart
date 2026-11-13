part of 'app_state.dart';

/// 以前のセーブのデータの修復・作り直し（読み込み時に1度だけ行うもの）
extension RepairOps on AppState {
  /// 推定の通算成績を作り直す（一度だけ）：新しい推定 ＋ ゲームの中で終わったシーズンの成績
  Future<void> _fixCareerEstimates() async {
    if (_careerV2) return;
    try {
      final rows = await (db.select(db.seasonRecords)..where((t) => t.kind.equals('player'))).get();
      final hist = <String, List<PlayerStats>>{};
      for (final r in rows) {
        final j = jsonDecode(r.json) as Map<String, dynamic>;
        if (j['stats'] is Map) hist.putIfAbsent(r.refId, () => []).add(PlayerStats.fromJson(Map<String, dynamic>.from(j['stats'] as Map)));
      }
      var n = 0;
      for (final p in [...teams.expand((t) => t.players), ...freeAgents.map((f) => f.player)]) {
        if (!p.careerEstimated) continue;
        final h = hist[p.id] ?? const <PlayerStats>[];
        final c = CareerEngine.estimate(p, doneSeasons: h.length);
        for (final st in h) {
          c.add(st);
        }
        p.career = c;
        n++;
      }
      _careerV2 = true;
      debugPrint('CAREER REBUILT: $n');
      saveData();
    } catch (e) {
      debugPrint('CAREER FIX ERROR: $e');
    }
  } // 以前のセーブ：今季の勝敗・セーブ・ホールド・自責点を今の規則で付け直す // 以前のセーブ：登板数・先発数を試合の記録から数え直す（読み込みの最後に行う）

  Future<Map<String, List<PreYear>>> _buildPreCareers() async {
    final rows = await (db.select(db.seasonRecords)..where((t) => t.kind.equals('player'))).get();
    final hist = <String, PlayerStats>{};
    final firstTeam = <String, (int, String)>{};
    var gameStart = startYear;
    for (final r in rows) {
      if (r.season < gameStart) gameStart = r.season;
      final j = jsonDecode(r.json) as Map<String, dynamic>;
      final h = hist.putIfAbsent(r.refId, () => PlayerStats());
      if (j['stats'] is Map) h.add(PlayerStats.fromJson(Map<String, dynamic>.from(j['stats'] as Map)));
      var team = r.teamId;
      final sp = j['splits'];
      if (sp is List) {
        for (final x in sp) {
          if (x is Map && x['stats'] is Map) h.add(PlayerStats.fromJson(Map<String, dynamic>.from(x['stats'] as Map)));
        }
        if (sp.isNotEmpty && sp.first is Map) team = '${(sp.first as Map)['team']}';
      }
      final ts = j['teams'];
      if ((sp is! List || sp.isEmpty) && ts is List && ts.isNotEmpty) team = '${ts.first}';
      final f = firstTeam[r.refId];
      if (f == null || r.season < f.$1) firstTeam[r.refId] = (r.season, team);
    }
    final players = <(Player, String)>[
      for (final t in teams) for (final p in t.players) (p, t.id),
      for (final fa in freeAgents) (fa.player, fa.fromTeamId),
    ];
    final out = <String, List<PreYear>>{};
    for (final (p, tid) in players) {
      final pre = PlayerStats()..add(p.career);
      final h = hist[p.id];
      final rest = h == null ? pre : _minusStats(pre, h);
      if (rest.games <= 0 && rest.pitchApps <= 0) continue;
      final entry = startYear - p.proYears + 1;
      final years = gameStart - entry;
      if (years <= 0 || p.joinedInGame) continue; // ゲーム開始後に入団した選手には、開始前の年度は無い（ありもしない年を推定しない）
      final team = firstTeam[p.id]?.$2 ?? tid;
      final ys = PreCareer.split(p, rest, gameStart - years, years, team);
      if (ys.isNotEmpty) out[p.id] = ys;
    }
    final real = <String>{for (final (p, _) in players) ...p.honors};
    final leagueOf = {for (final t in teams) t.id: t.league};
    final teamsOf = <String, List<String>>{};
    for (final t in teams) {
      if (t.league == 'CL' || t.league == 'PL') teamsOf.putIfAbsent(t.league, () => []).add(t.shortName.isNotEmpty ? t.shortName : t.name);
    }
    leagueHistory = LeagueHistory.build(out, {for (final (p, _) in players) p.id: p}, (id) => leagueOf[id] ?? '', teamsOf, real);
    for (final ys in out.values) {
      PreCareer.addMilestones(ys);
    }
    return out;
  }

  /// 以前の版の誤り（一度だけ）：ゲームの中で入団した選手に、開始前の推定の通算が足されていたら、
  ///  通算を「ゲームの中の年度別の記録（1軍）の合計」に戻す
  Future<void> _fixInGameCareers() async {
    if (await db.getKv('joinFixV1') == '1') return;
    final bad = [for (final t in teams) for (final p in t.players) if (p.careerEstimated && p.joinedInGame) p];
    if (bad.isNotEmpty) {
      final rows = await (db.select(db.seasonRecords)..where((t) => t.kind.equals('player'))).get();
      final hist = <String, PlayerStats>{};
      for (final r in rows) {
        final j = jsonDecode(r.json) as Map<String, dynamic>;
        final h = hist.putIfAbsent(r.refId, () => PlayerStats());
        if (j['stats'] is Map) h.add(PlayerStats.fromJson(Map<String, dynamic>.from(j['stats'] as Map)));
        final sp = j['splits'];
        if (sp is List) {
          for (final x in sp) {
            if (x is Map && x['stats'] is Map) h.add(PlayerStats.fromJson(Map<String, dynamic>.from(x['stats'] as Map)));
          }
        }
      }
      for (final p in bad) {
        p.career = PlayerStats()..add(hist[p.id] ?? PlayerStats());
        p.careerEstimated = false;
      }
      _preCache = null;
      debugPrint('CAREER FIX: ${bad.length} players joined in game');
    }
    await db.setKv('joinFixV1', '1');
  }

  /// a − b（0未満は0。守備位置ごとの値も）
  PlayerStats _minusStats(PlayerStats a, PlayerStats b) {
    final ja = a.toJson(), jb = b.toJson();
    final o = <String, dynamic>{};
    // 数・数の並び（ゾーン別など）・それらの表を、要素ごとに引く（0未満は0）
    dynamic minus(dynamic x, dynamic y) {
      if (x is int) return max(0, x - (y is int ? y : 0));
      if (x is List) {
        final yl = y is List ? y : const [];
        return [for (var i = 0; i < x.length; i++) minus(x[i], i < yl.length ? yl[i] : 0)];
      }
      if (x is Map) {
        final ym = y is Map ? y : const {};
        return {for (final e in x.entries) e.key: minus(e.value, ym[e.key])};
      }
      return x;
    }

    ja.forEach((k, v) {
      if (v is int) o[k] = minus(v, jb[k]);
      if (v is Map) {
        final m = minus(v, jb[k]) as Map;
        m.removeWhere((_, x) => x is int && x <= 0);
        o[k] = m;
      }
      if (v is List) o[k] = minus(v, jb[k]);
    });
    return PlayerStats.fromJson(o);
  }

  /// 以前のセーブ：同じ ID の選手が2球団にいたら直す。
  ///  ・同じ選手（名前と入団の記録が同じ）が二重に入っている → 1球団だけに残す（自球団 → ドラフトの記録の球団 → 先の球団）
  ///  ・別の選手が同じ ID を持っている（同じ年のドラフト候補が作り直されたときに起きた）→ 後の球団の選手に新しい ID を振る。
  ///    球団の中の打順・ローテ・登録などの ID もまとめて置き換える（選手はどこからも消さない）
  void _fixDuplicatePlayers() {
    // 同じ球団の中で2人が同じ ID：2人目に新しい ID（打順などの参照は1人目のまま）
    final used = <String>{for (final t in teams) for (final p in t.players) p.id};
    for (final t in teams) {
      final seen = <String>{};
      for (var i = 0; i < t.players.length; i++) {
        final p = t.players[i];
        if (seen.add(p.id)) continue;
        var n = 0;
        String nid;
        do {
          nid = '${p.id}_s${++n}';
        } while (used.contains(nid));
        used.add(nid);
        t.players[i] = Player.fromJson({...p.toJson(), 'id': nid});
        debugPrint('DUP IN TEAM: ${p.registeredName}（${t.name}） ${p.id} → $nid');
      }
    }
    // 自由契約の一覧の選手が、球団の選手と同じ ID：自由契約の選手に新しい ID
    for (var i = 0; i < freeAgents.length; i++) {
      final fa = freeAgents[i];
      if (!used.contains(fa.player.id)) {
        used.add(fa.player.id);
        continue;
      }
      var n = 0;
      String nid;
      do {
        nid = '${fa.player.id}_f${++n}';
      } while (used.contains(nid));
      used.add(nid);
      freeAgents[i] = FreeAgent(Player.fromJson({...fa.player.toJson(), 'id': nid}), fa.fromTeamId, fa.reason);
      debugPrint('DUP FREE AGENT: ${fa.player.registeredName} ${fa.player.id} → $nid');
    }
    final where = <String, List<Team>>{};
    for (final t in teams) {
      for (final p in t.players) {
        where.putIfAbsent(p.id, () => []).add(t);
      }
    }
    final allIds = where.keys.toSet();
    for (final e in where.entries.where((e) => e.value.length > 1)) {
      final ts = e.value;
      final p0 = ts.first.players.firstWhere((p) => p.id == e.key);
      final keep = ts.firstWhere((t) => t.id == myTeamId, orElse: () => ts.firstWhere((t) => transactions.any((l) => l.contains(' ${teamShort(t)} ${p0.draftInfo} ${p0.registeredName}')), orElse: () => ts.first));
      final kp = teams.firstWhere((x) => x.id == keep.id).players.firstWhere((p) => p.id == e.key);
      var n = 0;
      for (final t0 in ts.where((t) => t.id != keep.id)) {
        final t = teams.firstWhere((x) => x.id == t0.id); // 先に作り直した球団なら、その新しい方
        final p = t.players.firstWhere((x) => x.id == e.key);
        if (p.registeredName == kp.registeredName && p.draftInfo == kp.draftInfo) {
          RosterEngine.removePlayer(t, p);
          transactions.removeWhere((l) => p.draftInfo.isNotEmpty && l.contains(' ${teamShort(t)} ${p.draftInfo} ${p.registeredName}'));
          debugPrint('DUP SAME: ${p.registeredName} ${e.key} → ${keep.name}（${t.name}から外す）');
          continue;
        }
        String nid;
        do {
          nid = '${e.key}_r${++n}';
        } while (allIds.contains(nid));
        allIds.add(nid);
        final js = jsonEncode(t.toJson()).replaceAll('"${e.key}"', '"$nid"');
        final nt = Team.fromJson(jsonDecode(js) as Map<String, dynamic>, Player.fromJson);
        final i = teams.indexOf(t);
        teams[i] = nt;
        debugPrint('DUP NEW ID: ${p.registeredName}（${t.name}） ${e.key} → $nid');
      }
    }
  }

  /// 以前のセーブ：シーズン終了時の記録の保存が失敗していた（同じ ID の選手がいて、年度別の記録がまとめて書けなかった）。
  ///  オフシーズンの間（今季の成績がまだ選手に残っている間）なら作り直す：年度別の記録（選手・球団）・リーグの要約・表彰、表彰を選手の経歴へ。
  ///  所属は、シーズン終了時の球団（オフに移った選手は移籍の記録から元の球団、自由契約の選手は元の球団）。引退した選手の分は作れない
  Future<void> _repairLostSeasonRecords() async {
    final year = startYear;
    if (!seasonFinished || currentDate.year != year) return;
    try {
      if (await db.getKv('awards_$year') != null) return;
      final have = await (db.select(db.seasonRecords)..where((r) => r.season.equals(year))).get();
      if (have.any((r) => r.kind == 'player')) return;
      // シーズン終了時の所属（オフに動いた選手を元の球団へ）
      final byShort = {for (final t in teams) teamShort(t): t};
      String? endTeam(Player p) {
        for (final m in p.moves) {
          final mm = RegExp(r'^(\d{4})年(\d+)月\d+日 .+（←(.+)）$').firstMatch(m);
          if (mm == null) continue;
          if (int.parse(mm.group(1)!) == year && int.parse(mm.group(2)!) >= 10) return byShort[mm.group(3)!]?.id;
        }
        return null;
      }

      final snap = [for (final t in teams) Team.fromJson(jsonDecode(jsonEncode(t.toJson())) as Map<String, dynamic>, Player.fromJson)];
      final snapById = {for (final t in snap) t.id: t};
      final real = {for (final t in teams) for (final p in t.players) p.id: p};
      // 作り直した球団の選手を、本物の選手に差し替える（成績・表彰を本物に書くため）
      for (final t in snap) {
        final ps = [for (final p in t.players) real[p.id] ?? p];
        t.players
          ..clear()
          ..addAll(ps);
      }
      for (final t in teams) {
        for (final p in t.players) {
          final e = endTeam(p);
          if (e == null || e == t.id || snapById[e] == null) continue;
          snapById[t.id]!.players.removeWhere((x) => x.id == p.id);
          snapById[e]!.players.add(p);
        }
      }
      for (final fa in freeAgents) {
        final t = snapById[fa.fromTeamId];
        if (t != null && !t.players.any((x) => x.id == fa.player.id)) t.players.add(fa.player);
      }
      // そのオフのドラフトの新人は、今季はいなかった
      for (final t in snap) {
        t.players.removeWhere((p) => p.draftYear == year && p.seasonStats.games == 0 && p.farmStats.games == 0);
      }

      final ranks = <String, int>{};
      final records = <String, List<int>>{};
      for (final lg in ['CL', 'PL']) {
        final st = computeStandings(snap, matches, lg, StandingsKind.official);
        for (var i = 0; i < st.length; i++) {
          ranks[st[i].team.id] = i + 1;
          records[st[i].team.id] = [st[i].w, st[i].l, st[i].d];
        }
      }
      final rows = <SeasonRecordsCompanion>[];
      for (final t in snap) {
        rows.add(SeasonRecordsCompanion.insert(
          season: year, kind: 'team', refId: t.id, teamId: t.id,
          json: jsonEncode({'name': t.name, 'league': t.league, 'wins': records[t.id]?[0], 'losses': records[t.id]?[1], 'draws': records[t.id]?[2], 'rank': ranks[t.id],
            'champion': champion?.id == t.id, 'manager': t.id == myTeamId ? 'あなた' : (staffOf(teamById(t.id) ?? t)['監督']?.name ?? '')}),
        ));
        for (final p in t.players) {
          rows.add(SeasonRecordsCompanion.insert(
            season: year, kind: 'player', refId: p.id, teamId: t.id,
            json: jsonEncode({'name': p.registeredName, 'age': p.age, 'ovr': p.ovr, 'pos': p.mainPosition, 'stats': p.seasonStats.toJson(), 'farm': p.farmStats.toJson(), 'teams': p.seasonTeams, 'splits': p.seasonSplits}),
          ));
        }
      }
      final summary = _leagueSummary(year);
      final awards = AwardsEngine.compute(
        year: year,
        teams: snap,
        matches: matches,
        previous: null,
        prevStats: const {},
        series: [for (final s in postseason) {'id': s.id, 'label': s.label, 'high': s.high, 'low': s.low, 'winner': s.winner, 'mvp': s.mvp, 'score': _seriesScore(s)}],
        allStarMvps: [for (final m in matches.where((m) => m.matchType == 'ALLSTAR')) if (m.boxScore?['mvp'] is String) m.boxScore!['mvp'] as String],
        championId: champion?.id,
      );
      await db.saveRecords(year, rows);
      await db.setKv('summary_$year', jsonEncode(summary));
      await db.setKv('awards_$year', jsonEncode(awards));
      // 表彰を選手の経歴へ（まだ書いていなければ）
      final before = {for (final p in [...teams.expand((t) => t.players), ...freeAgents.map((f) => f.player)]) p.id: p.honors.length};
      final already = teams.expand((t) => t.players).any((p) => p.honors.any((h) => h == '$year年 MVP' || h.startsWith('$year年 首位打者') || h.startsWith('$year年 本塁打王')));
      if (!already) _recordHonors(year, awards);
      final added = teams.expand((t) => t.players).fold<int>(0, (a, p) => a + p.honors.length - (before[p.id] ?? p.honors.length));
      _preCache = null;
      debugPrint('SEASON RECORDS REBUILT: $year rows=${rows.length} honors+$added');
      _addNews(['$year年の年度別成績・表彰の記録を作り直しました（保存に失敗していた分）']);
      updateAndSave();
    } catch (e, st) {
      debugPrint('SEASON REPAIR ERROR: $e $st');
    }
  }

  /// 同じ ID だった選手の年度別の記録を直す（新しい ID を振った選手：ID の後ろが _r1 / _s1 など）。
  ///  記録は年度・ID ごとに1行なので、2人のうち1人分しか残っていない。残っている行は名前でどちらの選手か分かるので、
  ///  ・新しい ID の選手の行だった → 新しい ID へ移す
  ///  ・もう1人の行が無い → シーズンが終わってから年度が変わるまで（今季の成績がまだ選手に残っている間）は、その成績から作る
  Future<void> _repairRenamedRecords() async {
    final renamed = [for (final t in teams) for (final p in t.players) if (RegExp(r'_[rs]\d+$').hasMatch(p.id)) (p, t)];
    if (renamed.isEmpty) return;
    final byId = {for (final t in teams) for (final p in t.players) p.id: (p, t)};
    final canRebuild = seasonFinished && currentDate.year == startYear; // 今季の成績がまだ残っている
    try {
      final rows = await (db.select(db.seasonRecords)..where((r) => r.kind.equals('player'))).get();
      final have = {for (final r in rows) '${r.season}|${r.refId}': r};
      String nameOf(SeasonRecord r) => '${(jsonDecode(r.json) as Map)['name'] ?? ''}';
      SeasonRecordsCompanion fromData(Player p, Team t) => SeasonRecordsCompanion.insert(
            season: startYear, kind: 'player', refId: p.id, teamId: t.id,
            json: jsonEncode({'name': p.registeredName, 'age': p.age, 'ovr': p.ovr, 'pos': p.mainPosition, 'stats': p.seasonStats.toJson(), 'farm': p.farmStats.toJson(), 'teams': p.seasonTeams, 'splits': p.seasonSplits}),
          );
      final out = <SeasonRecordsCompanion>[];
      for (final (p, t) in renamed) {
        final base = p.id.replaceFirst(RegExp(r'_[rs]\d+$'), '');
        final seasons = {for (final r in rows) if (r.refId == base) r.season};
        for (final season in seasons) {
          if (have['$season|${p.id}'] != null) continue; // 直してある
          final baseRow = have['$season|$base']!;
          final other = byId[base];
          if (nameOf(baseRow) == p.registeredName) {
            // 残っていたのはこの選手の行 → 新しい ID へ。もう1人の行は作り直す
            out.add(SeasonRecordsCompanion.insert(season: season, kind: 'player', refId: p.id, teamId: baseRow.teamId, json: baseRow.json));
            if (other != null && other.$1.registeredName != p.registeredName && season == startYear && canRebuild) out.add(fromData(other.$1, other.$2));
          } else if (season == startYear && canRebuild) {
            out.add(fromData(p, t)); // 残っていたのはもう1人の行 → この選手の行を作る
          }
        }
      }
      if (out.isEmpty) return;
      await db.upsertRecords(out);
      _preCache = null;
      debugPrint('RECORDS REPAIRED: ${out.length}');
    } catch (e, st) {
      debugPrint('RECORDS REPAIR ERROR: $e $st');
    }
  }

  /// 固有12（初期データ）の投打の左右を振り分ける（初期データは全員が右投右打だったため）。
  ///  選手の id から決めるので、何度やっても同じ結果になる。割合は実際のプロ野球に近づける：
  ///  投手は約3割が左投げ。野手は右投右打55%・右投左打32%・左投左打10%・右投両打3%（捕手・二塁・三塁・遊撃は右投げ）
  void _assignHands(Iterable<Player> ps) {
    final orig = RegExp(r'^[CP]\d_P\d+$');
    const rightOnly = {'捕手', '二塁手', '三塁手', '遊撃手'};
    for (final p in ps) {
      if (!orig.hasMatch(p.id) || p.bats != 'R' || p.throws != 'R') continue;
      final x = Random(p.id.hashCode ^ 0x4a7d).nextDouble(), y = Random(p.id.hashCode ^ 0x1b3f).nextDouble();
      if (p.isPitcher) {
        p.throws = x < 0.30 ? 'L' : 'R';
        p.bats = p.throws == 'L' ? (y < 0.85 ? 'L' : 'R') : (y < 0.75 ? 'R' : (y < 0.98 ? 'L' : 'S'));
      } else {
        if (x < 0.55) {
          p.throws = 'R';
          p.bats = 'R';
        } else if (x < 0.87) {
          p.throws = 'R';
          p.bats = 'L';
        } else if (x < 0.97) {
          p.throws = rightOnly.contains(p.mainPosition) ? 'R' : 'L';
          p.bats = 'L';
        } else {
          p.throws = 'R';
          p.bats = 'S';
        }
      }
    }
  }

  /// 固有12（初期データ）の投手の球速を現実的に：160km 以上は各球団3人ほど、165km 以上は各リーグ1人。
  ///  球団内の速い順に並べ直して割り当てる（順位は変えない）。持ち球の球速も同じだけずらす
  void _slowVelocity(List<Team> ts) {
    final orig = RegExp(r'^[CP]\d_P\d+$');
    final changed = <Player, int>{};
    for (final t in ts) {
      final ps = t.players.where((p) => p.isPitcher && orig.hasMatch(p.id)).toList()
        ..sort((a, b) => b.velocity != a.velocity ? b.velocity.compareTo(a.velocity) : b.pitchPower.compareTo(a.pitchPower));
      final r = Random(t.id.hashCode ^ 0x5e1);
      for (var i = 0; i < ps.length; i++) {
        final int v;
        if (i == 0) {
          v = 162 + r.nextInt(3);
        } else if (i == 1) {
          v = 160 + r.nextInt(3);
        } else if (i == 2) {
          v = 160 + r.nextInt(2);
        } else {
          final q = ps.length <= 4 ? 0.0 : (i - 3) / (ps.length - 4);
          v = (159 - q * 21 + r.nextInt(3) - 1).round().clamp(136, 159);
        }
        changed[ps[i]] = ps[i].velocity;
        ps[i].velocity = v;
      }
    }
    // 各リーグで元々いちばん速かった投手だけ 165km 以上に
    for (final lg in const ['CL', 'PL']) {
      final cands = changed.keys.where((p) => ts.any((t) => t.league == lg && t.players.contains(p))).toList()
        ..sort((a, b) => changed[b]!.compareTo(changed[a]!));
      if (cands.isNotEmpty) cands.first.velocity = 165 + Random(lg.hashCode).nextInt(2);
    }
    changed.forEach((p, old) {
      final d = p.velocity - old;
      for (final x in p.pitches) {
        x.speed = (x.speed + d).clamp(70, 170);
      }
    });
  }

  /// 打者の詳しい成績（コース・打球方向・球種・球速）を、保存してある今季の1球ごとの記録から作る（一度だけ）。
  ///  1球ごとの記録が全試合そろうのは自球団の試合だけなので、自球団の選手だけ（他球団の選手はこれからの試合から数える）
  void _backfillSplits(List<PitchRow> rows) {
    final my = teams.where((t) => t.id == myTeamId).firstOrNull;
    if (my == null || seasonFinished) return;
    final mine = {for (final p in my.players) p.id: p};
    for (final p in mine.values) {
      p.seasonStats.spl.clear();
    }
    final last = <String, PitchRow>{};
    for (final r in rows) {
      if (r.matchIdx < 0 || r.matchIdx >= matches.length || !AppState._officialTypes.contains(matches[r.matchIdx].matchType)) continue;
      final k = '${r.matchIdx}|${r.battingHome}|${r.paIndex}';
      final l = last[k];
      if (l == null || r.pitchNo >= l.pitchNo) last[k] = r;
    }
    final resolvers = <int, String? Function(bool, String)>{};
    var n = 0;
    for (final r in last.values) {
      final res = paResult(PitchRec(paIndex: r.paIndex, pitchNo: r.pitchNo, battingHome: r.battingHome, batter: r.batter, pitcher: r.pitcher, result: r.result, outcome: r.outcome, balls: r.balls, strikes: r.strikes));
      if (res == null) continue;
      final resolve = resolvers.putIfAbsent(r.matchIdx, () => _idResolver(matches[r.matchIdx]));
      final p = mine[resolve(r.battingHome, r.batter)];
      if (p != null) {
        BattingSplits.add(p.seasonStats, res, x: r.x, z: r.z, bats: r.batterHand, pitchName: r.pitchName, speed: r.speed, landX: r.landX, landY: r.landY);
        n++;
      }
      final pp = mine[resolve(!r.battingHome, r.pitcher)];
      if (pp != null) BattingSplits.add(pp.seasonStats, res, x: r.x, z: r.z, bats: r.batterHand, pitchName: r.pitchName, speed: r.speed, landX: r.landX, landY: r.landY, prefix: 'p');
    }
    debugPrint('SPLITS BACKFILL: $n');
  }

  /// 今季の登板数・先発数を、試合のボックススコア（先発が先頭）から数え直す。1軍は成績に入る試合、2軍は2軍の試合
  void _recountApps() {
    final global = <String, Player?>{};
    for (final t in teams) {
      for (final p in t.players) {
        global[p.registeredName] = global.containsKey(p.registeredName) ? null : p;
        for (final st in [p.seasonStats, p.farmStats]) {
          st.pitchApps = 0;
          st.starts = 0;
        }
      }
    }
    void count(Match m, bool farm) {
      final box = m.boxScore;
      if (box == null || m.homeScore == null) return;
      for (final side in ['home', 'away']) {
        final tid = side == 'home' ? m.homeTeamId : m.awayTeamId;
        final team = teams.where((t) => t.id == tid).firstOrNull;
        final rows = box['${side}Pitcher'];
        if (rows is! Map) continue;
        var first = true;
        for (final name in rows.keys) {
          final p = team?.players.where((x) => x.registeredName == name).firstOrNull ?? global[name];
          if (p != null) {
            final st = farm ? p.farmStats : p.seasonStats;
            st.pitchApps++;
            if (first) st.starts++;
          }
          first = false;
        }
      }
    }
    for (final m in matches) {
      if (!AppState._noStats(m.matchType) && m.matchType != 'ALLSTAR') count(m, false);
    }
    for (final m in farmMatches) {
      count(m, true);
    }
  }

  /// 今季の1軍の公式戦の勝利・敗戦・セーブ・ホールド・自責点を、実況ログから今の規則で付け直す（DecisionRebuild）。
  ///  ボックススコアの判定と自責点を書き換え、前の判定との差を選手の今季成績に反映する。救援勝利は数え直す
  void _rebuildDecisions() {
    final global = <String, Player?>{};
    for (final t in teams) {
      for (final p in t.players) {
        global[p.registeredName] = global.containsKey(p.registeredName) ? null : p;
        p.seasonStats.reliefWins = 0;
      }
    }
    void bump(PlayerStats st, String dec, int d) {
      switch (dec) {
        case '勝': st.wins += d; break;
        case '敗': st.losses += d; break;
        case 'S': st.saves += d; break;
        case 'H': st.holds += d; break;
      }
    }
    var changed = 0;
    for (final m in matches) {
      if (m.homeScore == null || !AppState._officialTypes.contains(m.matchType)) continue;
      final home = teams.where((t) => t.id == m.homeTeamId).firstOrNull, away = teams.where((t) => t.id == m.awayTeamId).firstOrNull;
      if (home == null || away == null) continue;
      final r = DecisionRebuild.run(m, home, away);
      if (r == null) continue;
      for (final side in [true, false]) {
        final rows = m.boxScore![side ? 'homePitcher' : 'awayPitcher'];
        if (rows is! Map) continue;
        final team = side ? home : away;
        for (final e in rows.entries) {
          final name = e.key as String;
          final row = e.value as Map;
          final p = team.players.where((x) => x.registeredName == name).firstOrNull ?? global[name];
          final old = (row['dec'] ?? '') as String, neu = r.dec[(side, name)] ?? '';
          final oldEr = (row['er'] ?? 0) as int, newEr = r.er[side]?[name] ?? oldEr;
          if (p != null) {
            if (old != neu) {
              bump(p.seasonStats, old, -1);
              bump(p.seasonStats, neu, 1);
            }
            p.seasonStats.earnedRuns += newEr - oldEr;
            if (r.reliefWin == (side, name)) p.seasonStats.reliefWins++;
          }
          if (old != neu) changed++;
          if (neu.isEmpty) {
            row.remove('dec');
          } else {
            row['dec'] = neu;
          }
          row['er'] = newEr;
        }
      }
    }
    _matchesReplaceAll = true; // 書き換えたボックススコアを保存する
    debugPrint('DECISIONS REBUILT: $changed changed');
  }
}
