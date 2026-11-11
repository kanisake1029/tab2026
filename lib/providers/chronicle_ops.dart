part of 'app_state.dart';

/// 出来事の記録（球団の歴史・選手の年表）とお知らせの保存
///  出来事は年度ごとに kv「chron_年度」へ：{d: 日付, team, k: 種類, t: 球団の記録の文, pid: 選手, pt: 選手の年表の文}
///  種類：join 入団 / leave 退団 / reg 支配下登録 / coach コーチ / first 初記録 / milestone 節目 / manager 監督の記録
extension ChronicleOps on AppState {
  static String ymd(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// 今の年度の出来事
  List<Map<String, dynamic>> get chron => chronYears.putIfAbsent(startYear, () => []);

  void _chron(DateTime d, String teamId, String kind, String text, {String? pid, String? pt}) {
    chron.add({'d': ymd(d), 'team': teamId, 'k': kind, 't': text, if (pid != null) 'pid': pid, if (pt != null) 'pt': pt});
    if (chronFirstYear == 0 || chronFirstYear > startYear) chronFirstYear = startYear;
  }

  /// ある年度の出来事（今と前の年度はメモリ、それより前は保存から）
  Future<List<Map<String, dynamic>>> chronicleOf(int year) async {
    final m = chronYears[year];
    if (m != null) return m;
    final s = await db.getKv('chron_$year');
    if (s == null) return const [];
    return [for (final e in jsonDecode(s) as List) Map<String, dynamic>.from(e as Map)];
  }

  String _pos(Player p) => p.isPitcher ? '投手' : p.mainPosition;

  // ───────── 入団・退団・コーチ（前回の控えとの差分） ─────────

  /// いまの所属を控える（読み込み直後など。ここからの変化を記録する）
  void _snapRosters() {
    _rosterSnap = {for (final t in teams) for (final p in t.players) p.id: (t.id, p.ikusei, p)};
    _coachSnap = {
      for (final c in coaches)
        if (c.teamId != null && c.role != null && teams.any((t) => t.id == c.teamId)) c.id: (c.teamId!, c.role!, c),
    };
  }

  /// 前回の控えと比べて、入団・退団・支配下登録・コーチの就任と退任を記録する（保存のたびに呼ぶ）
  ///  at：その日の行事の後に呼ぶとき、その日付（省くと今日）
  void _diffRosters({DateTime? at}) {
    final old = _rosterSnap, oldC = _coachSnap;
    if (old == null || oldC == null) {
      _snapRosters();
      return;
    }
    final d = at ?? currentDate;
    final now = {for (final t in teams) for (final p in t.players) p.id: (t, p)};
    // 退団（ほかの球団へ移った選手は、入団の側で書く）
    for (final e in old.entries) {
      final (tid, _, p) = e.value;
      final cur = now[e.key];
      if (cur != null && cur.$1.id == tid) continue;
      final t = teamById(tid);
      if (t == null) continue;
      if (cur != null) {
        final last = p.moves.isEmpty ? '' : p.moves.last;
        final how = last.contains('FA') ? 'FAで' : (last.contains('トレード') ? 'トレードで' : (last.contains('人的補償') ? '人的補償で' : ''));
        _chron(d, tid, 'leave', '${_pos(p)} ${p.registeredName}(${p.age})が$how${teamShort(cur.$1)}へ移籍。', pid: p.id);
        continue;
      }
      final fa = freeAgents.where((f) => f.player.id == p.id).firstOrNull;
      final retired = retirees.any((r) => r['id'] == p.id) && fa == null;
      final (why, pt) = retired
          ? ('現役を引退', '現役を引退（プロ${p.proYears}年）。')
          : switch (fa?.reason) {
              '戦力外' => ('戦力外通告を受けて退団', '戦力外通告を受けて${t.name}を退団。'),
              '育成満了' => ('育成契約が満了して退団', '育成契約が満了して${t.name}を退団。'),
              'FA 未契約' => ('FA 宣言後、契約できずに退団', 'FA 宣言後、契約できずに${t.name}を退団。'),
              _ when p.nationality == '海外' => ('退団（帰国）', '${t.name}を退団（帰国）。'),
              _ => ('退団', '${t.name}を退団。'),
            };
      _chron(d, tid, 'leave', '${_pos(p)} ${p.registeredName}(${p.age})が$why。', pid: p.id, pt: pt);
    }
    // 入団・支配下登録
    for (final e in now.entries) {
      final (t, p) = e.value;
      final o = old[e.key];
      if (o != null && o.$1 == t.id) {
        if (o.$2 && !p.ikusei) {
          _chron(d, t.id, 'reg', '${_pos(p)} ${p.registeredName}(${p.age})を支配下登録。背番号は${p.uniformText}。', pid: p.id, pt: '支配下登録。背番号${p.uniformText}。');
          if (t.id == myTeamId) markNumberFree(p, d); // 支配下登録の直後は、背番号をすぐ変えられる
        }
        continue;
      }
      final (how, pt) = _joinText(p, t, from: o == null ? null : teamById(o.$1));
      _chron(d, t.id, 'join', '${_pos(p)} ${p.registeredName}(${p.age})が$how。背番号は${p.uniformText}。', pid: p.id, pt: '$pt背番号${p.uniformText}。');
      if (t.id == myTeamId) markNumberFree(p, d); // 入団・移籍の直後は、背番号をすぐ変えられる
    }
    // コーチ
    final nowC = {
      for (final c in coaches)
        if (c.teamId != null && c.role != null && teams.any((t) => t.id == c.teamId)) c.id: (c.teamId!, c.role!, c),
    };
    String roleName(String r) => r.contains('監督') ? r : '$rコーチ';
    for (final e in oldC.entries) {
      final (tid, role, c) = e.value;
      final cur = nowC[e.key];
      if (cur == null || cur.$1 != tid) {
        _chron(d, tid, 'coach', '${roleName(role)} ${c.name}(${c.age})が退任。');
      } else if (cur.$2 != role) {
        _chron(d, tid, 'coach', '${c.name}が${roleName(role)}から${roleName(cur.$2)}に配置転換。');
      }
    }
    for (final e in nowC.entries) {
      final (tid, role, c) = e.value;
      final o = oldC[e.key];
      if (o == null || o.$1 != tid) _chron(d, tid, 'coach', '${roleName(role)}に${c.name}(${c.age})が就任。');
    }
    _snapRosters();
  }

  /// 入団の経緯（球団の記録の文, 選手の年表の文）
  (String, String) _joinText(Player p, Team t, {Team? from}) {
    final last = p.moves.isEmpty ? '' : p.moves.last;
    if (from != null) {
      final how = last.contains('FA') ? 'FA' : (last.contains('トレード') ? 'トレード' : (last.contains('人的補償') ? '人的補償' : ''));
      return ('${how.isEmpty ? '' : '$howで'}${teamShort(from)}から移籍して入団', '${how.isEmpty ? '' : '$howで'}${from.name}から${t.name}に移籍。');
    }
    if (last.contains('自由契約')) {
      final ik = last.contains('育成');
      return ('自由契約から${ik ? '育成契約で' : ''}入団', '自由契約から${t.name}に${ik ? '育成契約で' : ''}入団。');
    }
    final m = RegExp(r'ドラフト(育成)?(\d+)位（(.+?)・(.+?)）').firstMatch(p.draftInfo);
    if (m != null && p.moves.isEmpty) {
      final cat = switch (m.group(3)) { '高校' => '高卒', '大学' => '大卒', '社会人' => '社会人', '独立' => '独立リーグ', _ => m.group(3)! };
      final ik = m.group(1) ?? '';
      return ('$ikドラフト${m.group(2)}位（${m.group(3)}・${m.group(4)}）で入団', '$cat$ikドラフト${m.group(2)}位で${t.name}に入団（${m.group(4)}）。');
    }
    if (p.nationality == '海外') return ('来日して入団', '来日して${t.name}に入団。');
    return ('入団', '${t.name}に入団。');
  }

  // ───────── 試合の初記録（公式戦・1軍） ─────────

  /// 試合で初めての記録（プロ初出場・初安打・初N番起用・初勝利など）を、選手の年表と球団の記録に書く
  void _gameFirsts(GameSession s) {
    final m = s.match;
    final d = m.date;
    for (final home in [true, false]) {
      final t = home ? s.homeTeam : s.awayTeam, opp = home ? s.awayTeam : s.homeTeam;
      final n = matches.where((x) => x.homeScore != null && !AppState._noStats(x.matchType) && x.matchType != 'ALLSTAR' && !x.date.isAfter(d) && ((x.homeTeamId == t.id && x.awayTeamId == opp.id) || (x.homeTeamId == opp.id && x.awayTeamId == t.id))).length;
      final vs = 'vs${opp.name}$n回戦';
      final order = [for (final l in t.lineup) l.playerId];
      final box = (s.boxScore[home ? 'homeBatters' : 'awayBatters'] as Map?) ?? const {};
      final pbox = (s.boxScore[home ? 'homePitcher' : 'awayPitcher'] as Map?) ?? const {};
      final pas = <String, int>{}, hits = <String, int>{}, hrs = <String, int>{}, hbp = <String, int>{}, bunts = <String, int>{}, runs = <String, int>{};
      const hitKinds = ['単打', '二塁打', '三塁打', 'ホームラン'];
      final names = {for (final p in t.players) p.registeredName};
      for (final e in s.pitchEvents) {
        if (e.battingHome != home) continue;
        if (e.pitchNo == 1) pas[e.batter] = (pas[e.batter] ?? 0) + 1;
        if (hitKinds.contains(e.outcome)) hits[e.batter] = (hits[e.batter] ?? 0) + 1;
        if (e.outcome == 'ホームラン') hrs[e.batter] = (hrs[e.batter] ?? 0) + 1;
        if (e.result == '死球') hbp[e.batter] = (hbp[e.batter] ?? 0) + 1;
        if (e.desc.contains('送りバント成功') || e.desc.contains('スクイズ成功')) bunts[e.batter] = (bunts[e.batter] ?? 0) + 1;
        for (final mv in e.runMoves) {
          if (mv.to == 4 && !mv.out && names.contains(mv.name)) runs[mv.name] = (runs[mv.name] ?? 0) + 1;
        }
      }
      final pitchers = home ? s.homePitchers : s.awayPitchers;
      final players = {for (final p in [...(home ? s.homeAppeared : s.awayAppeared), ...pitchers]) p.id: p};
      for (final p in players.values) {
        _ensureFirsts(p);
        final tags = <String>[];
        var pro = false;
        void first(String key, String label, {bool big = false}) {
          if (p.firsts.contains(key)) return;
          p.firsts.add(key);
          tags.add(label);
          if (big) pro = true;
        }

        final nm = p.registeredName;
        final row = box[nm] as Map?;
        final slot = order.indexOf(p.id);
        String? slotLabel;
        final batted = (pas[nm] ?? 0) > 0 || slot >= 0 || (!p.isPitcher);
        if (batted || !pitchers.contains(p)) first('g', '出場', big: true);
        if (slot >= 0) {
          final wasStarter = p.firsts.contains('st');
          first('st', 'スタメン', big: true);
          final k = 'o${slot + 1}';
          if (!p.firsts.contains(k)) {
            p.firsts.add(k);
            slotLabel = '初${slot + 1}番起用';
            if (wasStarter) tags.insert(0, '${slot + 1}番起用');
            if (wasStarter) slotLabel = null;
          }
        }
        if ((pas[nm] ?? 0) > 0) first('pa', '打席', big: true);
        final h = hits[nm] ?? 0;
        if (h > 0) first('hit', '安打', big: true);
        if (h > 0 || ((row?['bb'] ?? 0) as int) > 0 || (hbp[nm] ?? 0) > 0) first('ob', '出塁');
        if ((hrs[nm] ?? 0) > 0) first('hr', '本塁打', big: true);
        if (((row?['rbi'] ?? 0) as int) > 0) first('rbi', '打点', big: true);
        if ((runs[nm] ?? 0) > 0) first('run', '得点');
        if ((bunts[nm] ?? 0) > 0) first('sh', '犠打');
        if (s.playByPlay.any((l) => l.startsWith('$nm ') && l.contains('盗成功'))) first('sb', '盗塁');
        // 投手
        if (pitchers.contains(p)) {
          first('p', '登板', big: true);
          if (pitchers.first == p) first('ps', '先発', big: true);
          final pr = pbox[nm] as Map?;
          switch (pr?['dec']) {
            case '勝':
              first('w', '勝利', big: true);
            case 'S':
              first('s', 'セーブ', big: true);
            case 'H':
              first('h', 'ホールド', big: true);
            case '敗':
              first('l', '黒星');
          }
          if (((pr?['so'] ?? 0) as int) > 0) first('k', '奪三振');
          if (pitchers.length == 1) {
            first('cg', '完投', big: true);
            if ((home ? s.state.awayScore : s.state.homeScore) == 0) first('sho', '完封', big: true);
          }
        }
        if (tags.isEmpty && slotLabel == null) continue;
        var text = tags.isEmpty ? '' : [for (var i = 0; i < tags.length; i++) i == 0 ? '${pro ? (p.nationality == '海外' ? '来日' : 'プロ') : ''}初${tags[i]}' : '初${tags[i]}'].join('・');
        if (slotLabel != null) text = text.isEmpty ? slotLabel : '$text（$slotLabel）';
        _chron(d, t.id, 'first', '$nmが$vsで$text。', pid: p.id, pt: '$vsで$text。');
      }
    }
  }

  /// 以前のセーブ：今いる選手の「プロ初」の記録を、通算成績から済んだことにする（済んでいない記録だけ、これから年表に書く）
  void _initFirsts() {
    for (final p in [...teams.expand((t) => t.players), ...freeAgents.map((f) => f.player)]) {
      _ensureFirsts(p, force: true);
    }
  }

  /// 選手の「プロ初」の記録が空で、出場の記録があれば、通算成績から済んだことにする（新しいゲームのベテランなど）
  void _ensureFirsts(Player p, {bool force = false}) {
    if (!force && (p.firsts.isNotEmpty || p.career.games + p.career.pitchApps == 0)) return;
    {
      final s = PlayerStats()..add(p.career)..add(p.seasonStats);
      for (final sp in p.seasonSplits) {
        if (sp['stats'] is Map) s.add(PlayerStats.fromJson(Map<String, dynamic>.from(sp['stats'] as Map)));
      }
      final f = <String>{...p.firsts};
      final playedBat = s.atBats + s.walks > 0;
      if (s.games > 0 || s.pitchApps > 0) f.add('g');
      if (playedBat) {
        f.addAll(['pa', 'st', 'sh', 'o1', 'o2', 'o3', 'o4', 'o5', 'o6', 'o7', 'o8', 'o9']); // 打順・スタメン・犠打は記録が無いので、出ていた選手は済みにする
      }
      if (s.hits > 0) f.add('hit');
      if (s.hits + s.walks + s.hbp > 0) f.add('ob');
      if (s.homeRuns > 0) f.add('hr');
      if (s.rbi > 0) f.add('rbi');
      if (s.runs > 0) f.add('run');
      if (s.stolenBases > 0) f.add('sb');
      if (s.pitchApps > 0) f.add('p');
      if (s.starts > 0) f.add('ps');
      if (s.wins > 0) f.add('w');
      if (s.losses > 0) f.add('l');
      if (s.saves > 0) f.add('s');
      if (s.holds > 0) f.add('h');
      if (s.pitcherStrikeouts > 0) f.add('k');
      if (s.completeGames > 0) f.add('cg');
      if (s.shutouts > 0) f.add('sho');
      p.firsts = f.toList();
    }
  }

  /// シーズン終了時の順位表（リーグごと。勝敗・勝率・ゲーム差・得失点・チーム成績）
  Map<String, dynamic> _standingsSnapshot() {
    final ts = computeTeamStats(teams, matches, StandingsKind.official);
    return {
      for (final lg in ['CL', 'PL'])
        lg: [
          for (final r in computeStandings(teams, matches, lg, StandingsKind.official))
            () {
              final recs = computeStandings(teams, matches, lg, StandingsKind.official);
              final s = ts[r.team.id] ?? TeamStats();
              return {
                'id': r.team.id, 'name': r.team.name, 'w': r.w, 'l': r.l, 'd': r.d, 'pct': r.pctText, 'gb': gamesBehind(recs.first, r),
                'rs': r.rs, 'ra': r.ra, 'era': s.era, 'sEra': s.starterEra, 'rEra': s.reliefEra, 'avg': s.avg, 'hr': s.hr, 'sb': s.sb, 'e': s.e,
              };
            }(),
        ],
    };
  }

  // ───────── 監督の勝利 ─────────

  static const _mgrMarks = [1, 100, 200, 300, 400, 500, 600, 700, 800, 900, 1000, 1500, 2000];

  /// 監督の勝利（公式戦）：初勝利と節目（100勝ごと）を球団の記録に
  void _managerWin(Team t, DateTime d) {
    int total;
    String who;
    if (t.id == myTeamId && !ronin) {
      total = myCareer.fold<int>(0, (a, e) => a + ((e['w'] ?? 0) as int)) + t.wins;
      who = '監督（あなた）';
    } else {
      final c = staffOf(t)['監督'];
      if (c == null || c.mgrWins < 0) return;
      c.mgrWins++;
      total = c.mgrWins;
      who = '${c.name}監督';
    }
    if (_mgrMarks.contains(total)) _chron(d, t.id, 'manager', total == 1 ? '$whoが監督初勝利。' : '$whoが監督通算$total勝。');
  }

  // ───────── 年度の記録（球団の歴史の画面） ─────────

  /// その年度の順位表の詳細（シーズン終了時に保存したもの。無ければ null）
  Future<Map<String, dynamic>?> loadStandings(int year) async {
    final s = await db.getKv('standings_$year');
    return s == null ? null : jsonDecode(s) as Map<String, dynamic>;
  }

  /// その年度の記録の行（kind：team / player）：(ID, 球団ID, 記録の JSON)
  Future<List<(String, String, Map<String, dynamic>)>> seasonRows(int year, String kind) async {
    final rows = await (db.select(db.seasonRecords)..where((r) => r.season.equals(year) & r.kind.equals(kind))).get();
    return [for (final r in rows) (r.refId, r.teamId, jsonDecode(r.json) as Map<String, dynamic>)];
  }

  // ───────── 年表 ─────────

  /// 選手の年表（古い順）：出来事の記録と、記録を始める前の入団・移籍・節目（表彰の日付）
  Future<List<(DateTime, String)>> playerTimeline(Player p) => timelineOf(p.id, draftInfo: p.draftInfo, moves: p.moves, honors: p.honors, firstTeam: _team(p));

  Team? _team(Player p) => teams.where((t) => t.players.any((x) => x.id == p.id)).firstOrNull;

  Future<List<(DateTime, String)>> timelineOf(String pid, {String draftInfo = '', List<String> moves = const [], List<String> honors = const [], Team? firstTeam}) async {
    final out = <(DateTime, String)>[];
    final from = chronFirstYear == 0 ? startYear : chronFirstYear;
    DateTime? chronStart;
    for (var y = from; y <= startYear; y++) {
      for (final e in await chronicleOf(y)) {
        if (e['pid'] != pid || e['pt'] == null) continue;
        final dt = DateTime.parse(e['d'] as String);
        chronStart ??= dt;
        out.add((dt, e['pt'] as String));
      }
    }
    final start = chronStart ?? DateTime(9999);
    final hasJoin = out.isNotEmpty;
    // 記録を始める前の分（入団・移籍・表彰の日付つきの節目）
    final dm = RegExp(r'^(\d{4})年ドラフト(育成)?(\d+)位（(.+?)・(.+?)）').firstMatch(draftInfo);
    if (dm != null && !hasJoin) {
      final y = int.parse(dm.group(1)!);
      final cat = switch (dm.group(4)) { '高校' => '高卒', '大学' => '大卒', '社会人' => '社会人', '独立' => '独立リーグ', _ => dm.group(4)! };
      out.add((DateTime(y, 10, 31), '$cat${dm.group(2) ?? ''}ドラフト${dm.group(3)}位で${firstTeam == null || moves.isNotEmpty ? '' : '${firstTeam.name}に'}入団（${dm.group(5)}）。'));
    }
    final dre = RegExp(r'^(\d{4})年(\d+)月(\d+)日 (.+)$');
    for (final mv in moves) {
      final mm = dre.firstMatch(mv);
      if (mm == null) continue;
      final dt = DateTime(int.parse(mm.group(1)!), int.parse(mm.group(2)!), int.parse(mm.group(3)!));
      if (!dt.isBefore(start)) continue;
      out.add((dt, '${mm.group(4)!}。'));
    }
    for (final h in honors) {
      final mm = dre.firstMatch(h);
      if (mm == null) continue;
      final dt = DateTime(int.parse(mm.group(1)!), int.parse(mm.group(2)!), int.parse(mm.group(3)!));
      if (!dt.isBefore(start)) continue;
      out.add((dt, '${mm.group(4)!.replaceAll(RegExp(r'（.+?）$'), '')}。'));
    }
    out.sort((a, b) => a.$1.compareTo(b.$1));
    return out;
  }

  /// 保存から読む（出来事は今と前の年度、お知らせは過去3年）
  void _applyChronKv(Map<String, String> kv) {
    final y0 = int.tryParse(kv['startYear'] ?? '') ?? startYear;
    chronFirstYear = int.tryParse(kv['chronFirst'] ?? '0') ?? 0;
    openingNumberDay = kv['openingNumbers'] ?? '';
    chronYears = {
      for (final y in [y0 - 1, y0])
        if (kv['chron_$y'] != null) y: [for (final e in jsonDecode(kv['chron_$y']!) as List) Map<String, dynamic>.from(e as Map)],
    };
    final cy = kv['currentDate'] != null ? DateTime.parse(kv['currentDate']!).year : DateTime.now().year;
    newsLog = {
      for (final e in kv.entries)
        if (e.key.startsWith('news_') && (int.tryParse(e.key.substring(5)) ?? 0) >= cy - 2) int.parse(e.key.substring(5)): List<String>.from(jsonDecode(e.value) as List),
    };
  }

  // ───────── お知らせ（過去3年） ─────────

  void _logNews(List<String> items) {
    final y = currentDate.year;
    final l = newsLog.putIfAbsent(y, () => []);
    l.insertAll(0, items.map((e) => '${currentDate.month}/${currentDate.day} $e'));
    if (l.length > 4000) l.removeRange(4000, l.length);
  }
}
