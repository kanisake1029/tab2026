part of 'app_state.dart';

/// 今のチームの状態のまま、開幕日（最初の公式戦の日）の試合前に戻す（2026-11 の球速・守備の改定を、開幕から当てるため）
///  そのまま残すもの：選手の能力・経験値・1軍登録・オーダー・ローテ・在籍（移籍・入団は済んだまま）、オープン戦の成績
///  開幕前に戻すもの：公式戦と2軍・3軍の試合の結果、個人成績・勝敗、連続記録、「プロ初」、1球ごとの記録、月間MVP、
///   開幕後の試合で起きた怪我、体力、入場料と4月1日の月の収支（やり直したときに二重にならないように）
///  辻褄合わせ：開幕後のトレードは開幕前日、開幕後の支配下登録・入団は開幕日のことにする（取引・お知らせ・年表・選手の移籍の歩み）
///  開幕の年（最初のシーズン）の途中で使う前提
extension ReplayOps on AppState {
  Future<String> rewindToOpening() async {
    final official = [for (final m in matches) if (m.matchType == 'LEAGUE' || m.matchType == 'INTERLEAGUE') m];
    if (official.isEmpty) return '公式戦がありません';
    final opening = official.map((m) => DateUtils.dateOnly(m.date)).reduce((a, b) => a.isBefore(b) ? a : b);
    final today = DateUtils.dateOnly(currentDate);
    if (!today.isAfter(opening)) return 'まだ開幕前です';
    final npb = leagueTeams;
    final dayBefore = opening.subtract(const Duration(days: 1));
    bool inSeason(DateTime d) => !DateUtils.dateOnly(d).isBefore(opening);
    final log = <String>[];

    // ── お金：終わった主催試合の入場料・グッズ（記録した観客数から同じ計算）と、開幕後の月初めの収支を差し引く ──
    final done = [for (final m in matches) if (m.homeScore != null && m.matchType != 'OPEN' && inSeason(m.date)) m];
    for (final m in done) {
      final home = teamById(m.homeTeamId);
      final att = (m.boxScore?['attendance'] as num?)?.toInt();
      if (home == null || att == null || m.matchType == 'ALLSTAR') continue;
      final f = finOf(home);
      final eff = FinanceEngine.efficiency(consultantOf(f)?.skill ?? 50);
      FinanceEngine.gameRevenue(f, att, m.matchType, goodsMult: eff).forEach((k, v) => f.add(k, -v));
      f.homeGames = max(0, f.homeGames - 1);
      f.attendance = max(0, f.attendance - att);
    }
    for (var d = opening.add(const Duration(days: 1)); !d.isAfter(today); d = d.add(const Duration(days: 1))) {
      if (d.day != 1) continue;
      for (final t in teams) {
        final f = finOf(t);
        final c = consultantOf(f);
        final eff = FinanceEngine.efficiency(c?.skill ?? 50);
        if (d.month >= 2 && d.month <= 11) {
          f.add('選手年俸', (payrollOf(t) / 10).round());
          f.add('コーチ年俸', (coachPayrollOf(t) / 10).round());
        }
        final opYear = FinanceEngine.operatingPerMonth * 12;
        f.add('運営費', (d.month >= 3 && d.month <= 10 ? opYear * 0.85 / 8 : opYear * 0.15 / 4).round());
        final sp = f.sponsors.where((s) => !s.pending).fold<int>(0, (s, x) => s + x.amount);
        if (sp > 0) f.add('スポンサー', -(sp / 12 * eff).round());
        if (c != null) f.add('コンサルタント', (c.salary / 12).round());
        final up = FacilityEngine.upkeep(f.facilities);
        if (up > 0) f.add('施設維持費', (up / 12).round());
      }
      log.add('${d.month}月1日の収支を戻しました');
    }

    // ── 試合を開幕前に戻す（雨で振り替えた試合は元の日に）──
    void clear(Match m) {
      m.homeScore = null;
      m.awayScore = null;
      m.homeInningScores = null;
      m.awayInningScores = null;
      m.homeHits = null;
      m.awayHits = null;
      m.boxScore = null;
      m.playByPlay = null;
      m.pitchByPitch = null;
      m.isPlayed = false;
    }

    var moved = 0;
    for (final m in matches) {
      if (m.matchType == 'OPEN') continue;
      final note = RegExp(r'^(\d+)/(\d+) 雨天中止').firstMatch(m.note);
      if (note != null) {
        final od = DateTime(opening.year, int.parse(note.group(1)!), int.parse(note.group(2)!));
        if (inSeason(od)) {
          if (m.dh != 0) {
            for (final x in matches) {
              if (!identical(x, m) && DateUtils.isSameDay(x.date, m.date) && x.homeTeamId == m.homeTeamId && x.awayTeamId == m.awayTeamId) x.dh = 0;
            }
          }
          m.date = od;
          m.dh = 0;
          m.note = '';
          m.cancelled = false;
          moved++;
        }
      }
      if (inSeason(m.date) || m.homeScore != null && note != null) clear(m);
    }
    for (final fm in farmMatches) {
      if (inSeason(fm.date)) clear(fm);
    }
    _matchesReplaceAll = true;
    if (moved > 0) log.add('雨で振り替えた$moved試合を元の日に戻しました');

    // ── 成績・記録 ──
    for (final t in npb) {
      final c = staffOf(t)['監督'];
      if (c != null && c.mgrWins >= 0) c.mgrWins = max(0, c.mgrWins - t.wins);
      t.wins = 0;
      t.losses = 0;
      t.draws = 0;
    }
    final pre = <String>{}; // 開幕前からの怪我（自球団のお知らせに残っているもの）
    for (final e in newsLog[opening.year] ?? const <String>[]) {
      final mm = RegExp(r'^(\d+)/(\d+) ').firstMatch(e);
      if (mm == null) continue;
      final d = DateTime(opening.year, int.parse(mm.group(1)!), int.parse(mm.group(2)!));
      if (inSeason(d)) continue;
      final inj = RegExp(r'の(.+?)が(負傷|強行出場で悪化)').firstMatch(e);
      if (inj != null) pre.add(inj.group(1)!);
    }
    final elapsed = today.difference(opening).inDays;
    var healed = 0;
    for (final t in npb) {
      for (final p in t.players) {
        p.seasonStats = PlayerStats();
        p.farmStats = PlayerStats();
        p.thirdStats = PlayerStats();
        p.seasonSplits = [];
        p.seasonParts = [];
        p.seasonTeams = [];
        p.hitStreak = 0;
        p.hitStreakBest = 0;
        p.playStreak = 0;
        p.playStreakBest = 0;
        p.streaks = {};
        p.firsts = [];
        _ensureFirsts(p, force: true); // 開幕前の通算成績から「済んだ初記録」を作り直す
        p.energy = p.maxEnergy;
        p.consecDays = 0;
        p.lastPitched = '';
        if (p.lastDemotedDate != null && inSeason(DateTime.parse(p.lastDemotedDate!))) p.lastDemotedDate = null;
        if (p.injuryDays > 0) {
          if (t.id == myTeamId && pre.contains(p.registeredName)) {
            p.injuryDays += elapsed; // 開幕前からの怪我：開幕日の残りの日数に
          } else {
            p.injuryDays = 0;
            p.injurySeverity = 0;
            p.injuryName = '';
            healed++;
          }
        }
        p.moves = [for (final mv in p.moves) _redateMove(mv, opening, dayBefore)];
      }
      t.refreshActive26();
    }
    if (healed > 0) log.add('開幕後の試合で起きた怪我 $healed件を消しました');
    monthSnap = {};
    monthlyMvps.removeWhere((e) => (e['year'] ?? opening.year) == opening.year);
    final from = ChronicleOps.ymd(opening);
    for (final e in chron) {
      final d = e['d'] as String? ?? '';
      if (d.compareTo(from) < 0) continue;
      if (const {'join', 'leave'}.contains(e['k'])) e['d'] = ChronicleOps.ymd(dayBefore);
      if (e['k'] == 'reg') e['d'] = from;
    }
    chron.removeWhere((e) => const {'first', 'milestone', 'manager'}.contains(e['k']) && (e['d'] as String? ?? '').compareTo(from) >= 0);

    // ── 取引・お知らせの日付 ──
    final trade = RegExp(r'トレード');
    final join = RegExp(r'支配下登録|と契約');
    transactions = [
      for (final e in transactions)
        () {
          final mm = RegExp(r'^(\d+)/(\d+)/(\d+) ').firstMatch(e);
          if (mm == null) return e;
          final d = DateTime(int.parse(mm.group(1)!), int.parse(mm.group(2)!), int.parse(mm.group(3)!));
          if (!inSeason(d)) return e;
          final nd = trade.hasMatch(e) ? dayBefore : opening;
          return '${nd.year}/${nd.month}/${nd.day} ${e.substring(mm.end)}';
        }(),
    ];
    {
      // 付け替えた分（開幕前日・開幕日）を、新しい順に先頭へ
      final ob = '${opening.year}/${opening.month}/${opening.day} ', db1 = '${dayBefore.year}/${dayBefore.month}/${dayBefore.day} ';
      final a = transactions.where((e) => e.startsWith(ob)).toList(), b = transactions.where((e) => e.startsWith(db1)).toList();
      transactions = [...a, ...b, ...transactions.where((e) => !e.startsWith(ob) && !e.startsWith(db1))];
    }
    List<String> fixNews(List<String> l) {
      final kept = <String>[], tradesN = <String>[], joinsN = <String>[];
      for (final e in l) {
        final mm = RegExp(r'^(\d+)/(\d+) ').firstMatch(e);
        final d = mm == null ? null : DateTime(opening.year, int.parse(mm.group(1)!), int.parse(mm.group(2)!));
        if (d == null || !inSeason(d)) {
          kept.add(e);
        } else if (e.contains('トレード成立')) {
          tradesN.add('${dayBefore.month}/${dayBefore.day} ${e.substring(mm!.end)}');
        } else if (join.hasMatch(e)) {
          joinsN.add('${opening.month}/${opening.day} ${e.substring(mm!.end)}');
        }
        // それ以外の開幕後のお知らせ（試合・怪我・記録）は、まだ起きていないので消す
      }
      return [...joinsN, ...tradesN, ...kept];
    }
    news = fixNews(news);
    if (newsLog[opening.year] != null) newsLog[opening.year] = fixNews(newsLog[opening.year]!);

    // ── 1球ごとの記録・対戦成績 ──
    await (db.delete(db.pitchRows)..where((t) => t.season.equals(startYear))).go();
    _pendingPitches.clear();
    matchups.clear();
    _savedPlayed.clear();
    _savedFarmPlayed.clear();

    currentDate = opening;
    Player.showOpen = openPeriod;
    _staffCache.clear();
    await saveData();
    log.insert(0, '${opening.month}/${opening.day} の試合前に戻しました（公式戦 ${done.length}試合を取り消し）');
    return log.join('\n');
  }

  /// 経歴の辻褄合わせ（開幕日に戻したあと）
  ///  ・今季に入団した外国人選手は、前の年からいて2年目ということに（年齢はそのまま。入団の年・取引・移籍の歩みを1年前に）
  ///  ・ドラフトで入ってトレードで移った選手は、いまの球団の指名ということに：いまの球団の同じ種類（支配下・育成）の最後の順位に付け加え、
  ///    元の球団のそれより後の順位を1つずつ繰り上げる。その選手の移籍の歩みと、取引・お知らせのトレードからその選手を外す
  Future<String> reconcileHistory() async {
    final y0 = startYear, y1 = startYear - 1;
    final log = <String>[];
    // ── 外国人 ──
    final fNames = <String>{}, fIds = <String>{};
    for (final t in leagueTeams) {
      for (final p in t.players) {
        if (p.nationality != '海外') continue;
        if (!(p.draftInfo.contains('（$y0年') || p.draftInfo.contains('入団（$y0年）'))) continue;
        p.draftInfo = p.draftInfo.replaceAll('$y0年', '$y1年');
        p.moves = [for (final m in p.moves) m.startsWith('$y0年') ? '$y1年${m.substring('$y0年'.length)}' : m];
        p.proYears += 1;
        p.faService += 1;
        fNames.add(p.registeredName);
        fIds.add(p.id);
      }
    }
    bool hasF(String e) => fNames.any(e.contains);
    transactions = [
      for (final e in transactions) e.startsWith('$y0/') && hasF(e) && e.contains('契約') ? '$y1/${e.substring('$y0/'.length)}' : e,
    ];
    bool fNews(String e) => hasF(e) && (e.contains('と契約') || e.contains('支配下登録'));
    news.removeWhere((e) => fNews(e) && !e.contains('支配下登録'));
    newsLog[y0]?.removeWhere((e) => fNews(e) && !e.contains('支配下登録'));
    final moveC = chron.where((e) => fIds.contains(e['pid']) && e['k'] == 'join').toList();
    chron.removeWhere(moveC.contains);
    for (final e in moveC) {
      e['d'] = (e['d'] as String).replaceFirst('$y0-', '$y1-');
      chronYears[y1]?.add(e);
    }
    if (fNames.isNotEmpty) log.add('外国人 ${fNames.length}人を$y1年入団（2年目）に：${fNames.join('、')}');

    // ── トレードで移ったドラフト指名選手 ──
    String lab(bool ik, int r) => ik ? '育成${r}位' : '${r}位';
    void relabel(Player p, String l) {
      p.draftInfo = p.draftInfo.replaceFirst(RegExp(r'ドラフト(育成)?\d+位'), 'ドラフト$l');
    }
    for (final y in draftBook.keys) {
      final list = draftBook[y]!;
      for (final e in List.of(list)) {
        if (e['comp'] == true) continue;
        final (p, t) = draftBookPlayer(e);
        if (p == null || t == null || t.id == e['team'] || !leagueTeams.contains(t)) continue;
        final ik = e['ikusei'] == true;
        final oldTeam = e['team'] as String, oldRound = (e['round'] as num).toInt(), oldLabel = e['label'] as String;
        final oldShort = teamShort(teamById(oldTeam)!), newShort = teamShort(t);
        // 元の球団：後の順位を繰り上げ
        for (final x in list) {
          if (x['team'] != oldTeam || (x['ikusei'] == true) != ik || x['comp'] == true || (x['round'] as num) <= oldRound) continue;
          final r = (x['round'] as num).toInt() - 1;
          final ol = x['label'] as String;
          x['round'] = r;
          x['label'] = lab(ik, r);
          final (xp, _) = draftBookPlayer(x);
          if (xp != null) relabel(xp, lab(ik, r));
          transactions = [for (final l in transactions) l.startsWith('$y/10/31') && l.contains('${x['name']}') ? l.replaceFirst('ドラフト$ol', 'ドラフト${lab(ik, r)}') : l];
        }
        // いまの球団：同じ種類の最後の順位の次
        final last = list.where((x) => x['team'] == t.id && (x['ikusei'] == true) == ik && x['comp'] != true).fold<int>(0, (m, x) => max(m, (x['round'] as num).toInt()));
        final nl = lab(ik, last + 1);
        e['team'] = t.id;
        e['round'] = last + 1;
        e['label'] = nl;
        relabel(p, nl);
        p.moves.removeWhere((m) => m.contains('トレード') && m.contains('←$oldShort'));
        final name = p.registeredName;
        // 取引：ドラフトの行は球団と順位を、トレードの行はその選手を外す（その選手だけの側ならトレードごと消す）
        String? dropFromTrade(String l) {
          if (!l.contains('トレード') || !l.contains(name)) return l;
          var r = l.replaceAll('・$name', '').replaceAll('$name・', '');
          if (r.contains(name)) return null; // その選手だけが動いた側
          return r;
        }
        transactions = [
          for (final l in transactions)
            if (l.startsWith('$y/10/31') && l.contains(name)) l.replaceFirst('$oldShort ', '$newShort ').replaceFirst('ドラフト$oldLabel', 'ドラフト$nl')
            else if (dropFromTrade(l) != null) dropFromTrade(l)!,
        ];
        news = [for (final l in news) if (dropFromTrade(l) != null) dropFromTrade(l)!];
        if (newsLog[y0] != null) newsLog[y0] = [for (final l in newsLog[y0]!) if (dropFromTrade(l) != null) dropFromTrade(l)!];
        log.add('$name：$oldShortの$oldLabel → $newShortの$nl（$oldShortの後の順位を繰り上げ）');
      }
    }
    await saveData();
    return log.join('\n');
  }

  /// 前の年からいたことにした外国人選手（reconcileHistory のあと）に、1年目（前の年）の成績を推定して書く
  ///  支配下の選手は1軍、育成だった選手は2軍の成績（能力と年齢から。選手ごとにいつも同じ値）。1軍の分は通算にも足す
  ///  年度別の記録には 'pre'（推定）として入れる：選手の年度別成績には出るが、歴代記録・リーグの歴史には入れない
  Future<String> estimateForeignFirstYear() async {
    final y1 = startYear - 1;
    final have = {for (final r in await (db.select(db.seasonRecords)..where((t) => t.season.equals(y1))).get()) r.refId};
    final rows = <SeasonRecordsCompanion>[];
    final log = <String>[];
    for (final t in leagueTeams) {
      for (final p in t.players) {
        if (p.nationality != '海外' || have.contains(p.id)) continue;
        if (!(p.draftInfo.contains('（$y1年') || p.draftInfo.contains('入団（$y1年）'))) continue;
        final est = CareerEngine.estimateYears(p, seasonsOverride: 1).first;
        // 前の年に育成だったか：いまも育成、入団が育成、今年（開幕日）に支配下登録した
        final wasIkusei = p.ikusei || p.draftInfo.contains('育成') || transactions.any((l) => l.startsWith('$startYear/') && l.contains(p.registeredName) && l.contains('支配下登録'));
        // 2軍で1年いたときの出場の目安（能力が高いほど多い）
        final target = p.isPitcher
            ? (p.stamina >= 60 ? (12 + (p.ovr - 40) * 0.3).clamp(8.0, 22.0) : (25 + (p.ovr - 40) * 0.5).clamp(25.0, 45.0))
            : (60 + (p.ovr - 40) * 1.5).clamp(40.0, 110.0);
        final estG = p.isPitcher ? est.pitchApps : est.games;
        final one = wasIkusei ? PlayerStats() : est;
        final rest = target - (wasIkusei ? 0 : estG);
        final farm = rest < target * 0.5 ? PlayerStats() : _scaledStats(est, estG <= 0 ? 1.0 : rest / estG);
        _reliefDecisions(p, one);
        _reliefDecisions(p, farm);
        if (!wasIkusei) p.career.add(one);
        rows.add(SeasonRecordsCompanion.insert(
          season: y1, kind: 'pre', refId: p.id, teamId: t.id,
          json: jsonEncode({'name': p.registeredName, 'age': p.age - 1, 'ovr': p.ovr, 'pos': p.mainPosition, 'stats': one.toJson(), 'farm': farm.toJson(), 'est': true}),
        ));
        final s = wasIkusei ? farm : one;
        if (farm.games + farm.pitchApps > 0 && !wasIkusei) log.add('${p.registeredName}（2軍）${farm.games}試合');
        log.add('${p.registeredName}（${wasIkusei ? '2軍' : '1軍'}）${p.isPitcher ? '${s.pitchApps}登板 ${s.wins}勝${s.losses}敗 防${s.inningsPitched == 0 ? '-' : (s.earnedRuns * 27 / s.inningsPitched).toStringAsFixed(2)}' : '${s.games}試合 打率${s.atBats == 0 ? '-' : (s.hits / s.atBats).toStringAsFixed(3)} ${s.homeRuns}本'}');
      }
    }
    if (rows.isNotEmpty) await db.upsertRecords(rows);
    _preCache = null;
    _sortTransactions();
    await saveData();
    return '$y1年の推定成績：${log.join('、')}';
  }

  /// 年表の辻褄合わせ（reconcileHistory のあと）
  ///  ・ドラフトの入団の記録を、指名の記録（球団・順位）に合わせる。球団が変わった選手は、トレードの退団・入団の記録を消す
  ///  ・前の年からいたことにした外国人選手の入団を、前の年の年表に入れる（取引の記録の日付。なければ1月1日）
  Future<String> fixChronicle() async {
    final y1 = startYear - 1;
    final log = <String>[];
    for (final y in {y1, startYear, ...draftBook.keys}) {
      chronYears[y] = List.of(await chronicleOf(y));
    }
    final moved = <String>{};
    // 年表の年度はシーズンの終わりで切り替わるので、ドラフト（10月末）の記録は次の年度の年表にある。両方を探す
    final lists = [for (final y in chronYears.keys) chronYears[y]!];
    for (final y in draftBook.keys) {
      for (final e in draftBook[y]!) {
        final pid = e['id'], team = e['team'], r = (e['round'] as num).toInt(), ik = e['ikusei'] == true;
        final want = ik ? '育成ドラフト${r}位' : 'ドラフト${r}位';
        for (final c in lists.expand((l) => l).where((c) => c['pid'] == pid && c['k'] == 'join' && '${c['t']}'.contains('ドラフト'))) {
          final t0 = '${c['t']}';
          c['t'] = t0.replaceFirst(RegExp(r'(育成)?ドラフト\d+位'), want);
          if (c['pt'] is String) c['pt'] = (c['pt'] as String).replaceFirst(RegExp(r'(育成)?ドラフト\d+位'), want);
          if (c['team'] != team) {
            c['team'] = team;
            final np = draftBookPlayer(e).$1;
            if (np != null) {
              c['t'] = '${c['t']}'.replaceFirst(RegExp(r'背番号は\d+'), '背番号は${np.uniformText}');
              if (c['pt'] is String) c['pt'] = (c['pt'] as String).replaceFirst(RegExp(r'背番号\d+'), '背番号${np.uniformText}');
            }
            moved.add('$pid');
          }
          if (c['t'] != t0) log.add('年表：${e['name']} を$wantに');
        }
      }
    }
    for (final list in chronYears.values) {
      list.removeWhere((c) => moved.contains(c['pid']) && '${c['t']}'.contains('トレード'));
    }
    if (moved.isNotEmpty) log.add('年表：トレードの記録を消した選手 ${moved.length}人');
    // 外国人の入団（前の年）
    final l1 = chronYears[y1]!, l0 = chronYears[startYear]!;
    // 今の年度の年表の最初の日（前のシーズンの終わり）より後なら、今の年度の年表に入れる
    final cut = l0.isEmpty ? '${startYear}-01-01' : l0.map((c) => '${c['d']}').reduce((a, b) => a.compareTo(b) <= 0 ? a : b);
    var added = 0;
    for (final t in leagueTeams) {
      for (final p in t.players) {
        if (p.nationality != '海外') continue;
        if (!(p.draftInfo.contains('（$y1年') || p.draftInfo.contains('入団（$y1年）'))) continue;
        if ([...l1, ...l0].any((c) => c['pid'] == p.id && c['k'] == 'join')) continue;
        final tx = transactions.where((l) => l.startsWith('$y1/') && l.contains(p.registeredName) && l.contains('契約')).firstOrNull;
        final m = tx == null ? null : RegExp(r'^(\d+)/(\d+)/(\d+) ').firstMatch(tx);
        final d = m == null ? DateTime(y1, 1, 1) : DateTime(y1, int.parse(m.group(2)!), int.parse(m.group(3)!));
        final from = RegExp(r'（\d+年・(.+?から)').firstMatch(p.draftInfo)?.group(1) ?? RegExp(r'^(.+から)入団').firstMatch(p.draftInfo)?.group(1);
        final ik = p.draftInfo.contains('育成') || (tx?.contains('育成') ?? false);
        final how = '${from == null ? '' : from}${ik ? '育成契約で' : ''}入団';
        (ChronicleOps.ymd(d).compareTo(cut) >= 0 ? l0 : l1).add({'d': ChronicleOps.ymd(d), 'team': t.id, 'k': 'join', 't': '${_pos(p)} ${p.registeredName}(${p.age - 1})が$how。背番号は${p.uniformText}。', 'pid': p.id, 'pt': '$how。背番号${p.uniformText}。'});
        added++;
      }
    }
    if (added > 0) log.add('年表：$y1年に外国人 $added人の入団を追加');
    for (final list in chronYears.values) {
      final idx = [for (var i = 0; i < list.length; i++) i]..sort((a, b) {
          final c = '${list[a]['d']}'.compareTo('${list[b]['d']}');
          return c != 0 ? c : a.compareTo(b);
        });
      final sorted = [for (final i in idx) list[i]];
      list
        ..clear()
        ..addAll(sorted);
    }
    for (final y in chronYears.keys.where((y) => y < startYear - 1)) {
      await db.setKv('chron_$y', jsonEncode(chronYears[y])); // 保存は前の年と今年だけなので、それより前の年はここで
    }
    await saveData();
    return log.join('\n');
  }

  /// 推定の成績の中継ぎ・抑え（先発なし）に勝敗・ホールド・セーブを付ける（登板数から。端数は選手ごとに決まった値で）
  ///  すでに勝敗がある成績はそのまま。変えたら true
  static bool _reliefDecisions(Player p, PlayerStats s) {
    if (!p.isPitcher || s.pitchApps <= 0 || s.starts > 0) return false;
    if (s.wins + s.losses > 0) return false;
    final keepHS = s.holds + s.saves > 0; // ホールド・セーブがすでにあれば、そのまま
    final before = [s.wins, s.losses, s.holds, s.saves];
    final r = Random(p.id.hashCode ^ 0x7e1);
    int n(double x) => x.floor() + (r.nextDouble() < x - x.floor() ? 1 : 0);
    final era = s.inningsPitched == 0 ? 4.0 : s.earnedRuns * 27 / s.inningsPitched;
    final good = (4.5 - era).clamp(-2.0, 2.5); // 防御率がよいほど勝ちが多く、負けが少ない
    final closer = p.ovr >= 68 && r.nextDouble() < 0.4;
    s.wins = n(s.pitchApps * (0.07 + good * 0.01));
    s.reliefWins = s.wins;
    s.losses = n(s.pitchApps * (0.06 - good * 0.01).clamp(0.02, 0.12));
    if (keepHS) {
    } else if (closer) {
      s.saves = n(s.pitchApps * 0.55);
    } else {
      s.holds = n(s.pitchApps * (0.25 + good * 0.03).clamp(0.1, 0.4));
    }
    return before[0] != s.wins || before[1] != s.losses || before[2] != s.holds || before[3] != s.saves;
  }

  /// すでに書いた推定の年度（'pre'）の中継ぎ・抑えに、勝敗・ホールド・セーブを付け直す（1軍の分は通算にも）
  Future<String> fixPreDecisions() async {
    final rows = await (db.select(db.seasonRecords)..where((t) => t.kind.equals('pre'))).get();
    final byId = {for (final t in teams) for (final p in t.players) p.id: p};
    final out = <SeasonRecordsCompanion>[];
    final log = <String>[];
    for (final r in rows) {
      final p = byId[r.refId];
      if (p == null) continue;
      final j = jsonDecode(r.json) as Map<String, dynamic>;
      final one = j['stats'] is Map ? PlayerStats.fromJson(Map<String, dynamic>.from(j['stats'] as Map)) : PlayerStats();
      final farm = j['farm'] is Map ? PlayerStats.fromJson(Map<String, dynamic>.from(j['farm'] as Map)) : PlayerStats();
      final w0 = one.wins, l0 = one.losses, h0 = one.holds, s0 = one.saves;
      final a = _reliefDecisions(p, one), b = _reliefDecisions(p, farm);
      if (!a && !b) continue;
      if (a) {
        p.career.wins += one.wins - w0;
        p.career.reliefWins += one.wins - w0;
        p.career.losses += one.losses - l0;
        p.career.holds += one.holds - h0;
        p.career.saves += one.saves - s0;
      }
      j['stats'] = one.toJson();
      j['farm'] = farm.toJson();
      out.add(SeasonRecordsCompanion.insert(season: r.season, kind: 'pre', refId: r.refId, teamId: r.teamId, json: jsonEncode(j)));
      final s = a ? one : farm;
      log.add('${p.registeredName}（${a ? '1軍' : '2軍'}）${s.pitchApps}登板 ${s.wins}勝${s.losses}敗${s.saves > 0 ? ' ${s.saves}S' : ' ${s.holds}H'}');
    }
    if (out.isNotEmpty) await db.upsertRecords(out);
    await saveData();
    return log.join('、');
  }

  /// 取引の記録を日付の新しい順に並べ直す（同じ日の中の順番はそのまま）
  void _sortTransactions() {
    DateTime? dateOf(String l) {
      final m = RegExp(r'^(\d+)/(\d+)/(\d+) ').firstMatch(l);
      return m == null ? null : DateTime(int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!));
    }
    final idx = [for (var i = 0; i < transactions.length; i++) i];
    final d = [for (final l in transactions) dateOf(l)];
    idx.sort((a, b) {
      final da = d[a], db = d[b];
      if (da == null || db == null || da == db) return a.compareTo(b);
      return db.compareTo(da);
    });
    transactions = [for (final i in idx) transactions[i]];
  }

  /// 成績の数をまとめて k 倍する（率は変わらない）
  static PlayerStats _scaledStats(PlayerStats s, double k) {
    Object? sc(Object? v) => v is int ? (v * k).round() : (v is Map ? {for (final e in v.entries) e.key: sc(e.value)} : v);
    final j = s.toJson();
    return PlayerStats.fromJson({for (final e in j.entries) e.key: sc(e.value)});
  }

  /// 移籍の歩みの日付：開幕後のトレードは開幕前日、入団・支配下登録は開幕日に
  static String _redateMove(String mv, DateTime opening, DateTime dayBefore) {
    final mm = RegExp(r'^(\d+)年(\d+)月(\d+)日').firstMatch(mv);
    if (mm == null) return mv;
    final d = DateTime(int.parse(mm.group(1)!), int.parse(mm.group(2)!), int.parse(mm.group(3)!));
    if (d.isBefore(opening)) return mv;
    final nd = mv.contains('トレード') ? dayBefore : opening;
    return '${nd.year}年${nd.month}月${nd.day}日${mv.substring(mm.end)}';
  }
}
