part of 'app_state.dart';

/// 保存・読み込み・バックアップ（JSON）・以前の保存形式からの移行
extension SaveOps on AppState {
  Future<void> loadData() async {
    Map<String, String> kv = const {};
    try {
      kv = await db.allKv();
      final teamJsons = await db.loadTeamJsons();
      final prospectRows = await db.loadProspectRows();
      if (prospectRows.isNotEmpty) {
        kv['prospects'] = '[${prospectRows.map((r) => r.json).join(',')}]';
        for (final r in prospectRows) {
          _savedProspectJson[r.id] = r.json;
          _savedProspectSort[r.id] = r.sort;
        }
      } else if (kv['prospects'] != null) {
        _legacyProspectKv = true; // 以前のセーブ（kv に1つのJSONで入っている）：次の保存で1人1行の表に移す
      }
      if (teamJsons.isNotEmpty) {
        teams = teamJsons.map((s) => Team.fromJson(jsonDecode(s) as Map<String, dynamic>, Player.fromJson)).toList();
        _applyKv(kv);
        if (kv['bodyV2'] != '1') _raiseBody(teams); // 以前のセーブ：体力・回復力・怪我しにくさの基準が変わった
        if (kv['pitchV2'] != '1') _regenPitches(teams); // 以前のセーブ：持ち球を球種カタログで作り直す
        if (kv['traitV3'] != '1') _raiseClutch(teams); // 以前のセーブ：クイック・チャンス・ピンチの平均を60に
        if (kv['velV1'] != '1') _slowVelocity(teams); // 以前のセーブ：固有12の投手の球速を下げる
        if (kv['appsV1'] != '1') _needApps = true;
        if (kv['decV2'] != '1') _needDecisions = true;
        if (kv['recV1'] != '1') _needRecords = true;
        if (kv['handV1'] != '1') _needHands = true;
        if (kv['firstsV1'] != '1') _needFirsts = true;
        if (kv['roster63'] != '1') _needTrim63 = true; // 以前のセーブ：CPU 球団の支配下を63人に（読み込みの最後に行う）
        final rows = await db.loadMatchRows(startYear);
        if (kv['compactV1'] != '1') _compactSeasonPending = startYear - 1; // 以前のセーブ：過去のシーズンの実況・1球ごとの記録を消す
        matches = [for (final r in rows.where((r) => r.idx < AppState.farmIdxBase)) Match.fromJson(jsonDecode(r.json) as Map<String, dynamic>)];
        farmMatches = [for (final r in rows.where((r) => r.idx >= AppState.farmIdxBase)) Match.fromJson(jsonDecode(r.json) as Map<String, dynamic>)];
        _savedPlayed
          ..clear()
          ..addAll([for (var i = 0; i < matches.length; i++) if (matches[i].homeScore != null) i]);
        _savedFarmPlayed
          ..clear()
          ..addAll([for (var i = 0; i < farmMatches.length; i++) if (farmMatches[i].homeScore != null) i]);
        _matchesReplaceAll = false;
        if (matches.isEmpty) {
          _generateSchedule(keepDate: true);
        } else if (farmMatches.length != matches.length) {
          _buildFarmMatches(); // 2軍の日程が無い古いセーブ
          _matchesReplaceAll = true;
        }
        if (thirdMatches.isEmpty && farmMatches.isNotEmpty) _buildThirdMatches(); // 3軍の日程が無いセーブ（今日から先を作る）
      } else if (slot != 1 || !await _migrateFromPrefs()) { // 以前の保存（端末の設定）からの移しかえは、プレイデータ1だけ
        teams = _initialTeams();
        _freshInitial = true;
        weatherSeed = Random().nextInt(1 << 30);
        if (!deferWorldGen) {
          _applySeasonGames();
          _generateSchedule(keepDate: true);
        }
      }
    } catch (e, st) {
      debugPrint('LOAD ERROR: $e\n$st');
      teams = _initialTeams();
      _freshInitial = true;
      if (!deferWorldGen) _generateSchedule(keepDate: true);
    }
    _migratePitchers();
    _migrateForeign();
    if (_needHands) {
      _assignHands([...teams.expand((t) => t.players), ...freeAgents.map((f) => f.player)]);
      _needHands = false;
    }
    _fixDuplicatePlayers();
    _fixCompOfFaSigned();
    // 以前のセーブ：今季の守備イニングを、守備位置ごとの先発試合数の割合で振り分ける（守備位置ごとの記録が無いため）
    for (final p in teams.expand((t) => t.players)) {
      final st = p.seasonStats;
      if (st.defOuts <= 0 || st.posOuts.isNotEmpty) continue;
      final g = {for (final e in st.posGames.entries) if (e.key != 'DH' && e.value > 0) e.key: e.value};
      final total = g.values.fold<int>(0, (a, b) => a + b);
      if (total == 0) continue;
      var left = st.defOuts;
      final keys = g.keys.toList()..sort((a, b) => g[b]!.compareTo(g[a]!));
      for (var i = 0; i < keys.length; i++) {
        final o = i == keys.length - 1 ? left : (st.defOuts * g[keys[i]]! / total).round();
        st.posOuts[keys[i]] = o;
        left -= o;
      }
    }
    // 独立リーグの球団名を、プロ球団に見えない名前に置き換える（入団経緯・ドラフト候補の出身とメモ）
    for (final p in [...teams.expand((t) => t.players), ...freeAgents.map((f) => f.player)]) {
      p.draftInfo = DraftEngine.renameIndep(p.draftInfo);
    }
    for (final pr in prospects) {
      pr.school = DraftEngine.renameIndep(pr.school);
      pr.memo = [for (final m in pr.memo) DraftEngine.renameIndep(m)];
    }
    // 入団時（固有12はゲーム開始時）の能力が無い選手：固有12は初期データ（ゲーム開始時と同じ処理をしたもの）から、
    // それ以外は今年の初めの能力で代わりにする
    if (teams.any((t) => t.players.any((p) => p.baseline.isEmpty))) {
      final init = _freshInitial
          ? {for (final t in teams) for (final p in t.players) p.id: p}
          : {for (final t in _initialTeams()) for (final p in t.players) p.id: p};
      for (final p in [...teams.expand((t) => t.players), ...freeAgents.map((f) => f.player)]) {
        if (p.baseline.isNotEmpty) continue;
        final i = init[p.id];
        if (i != null) {
          p.baseline = GrowthEngine.abilities(i);
          p.baselineNote = 'ゲーム開始時';
        } else if (p.yearStart.isNotEmpty) {
          p.baseline = Map.of(p.yearStart);
          p.baselineNote = '$startYear年の初め';
        } else {
          p.baseline = GrowthEngine.abilities(p);
          p.baselineNote = '記録を始めたとき';
        }
      }
    }
    if (_needDecisions) {
      _rebuildDecisions();
      _needDecisions = false;
    }
    if (_needRecords) {
      rebuildSeasonRecords(); // 以前のセーブ：記録していなかった得点圏・連続記録など、エラーを安打にしていた分
      _needRecords = false;
      _matchesReplaceAll = true;
    }
    if (_needApps) {
      _recountApps();
      _needApps = false;
    }
    if (_needTrim63 && myTeamId.isNotEmpty) {
      _trimCpuRosters();
      _needTrim63 = false;
    }
    _ensureCoaches();
    _fillStaff();
    _ensureScoutNet(onlyEmpty: true); // スカウトが1人もいない球団（あとから作った球団など）にだけ置く
    for (final t in teams) {
      for (final p in t.players) {
        CareerEngine.estimateIfMissing(p);
      }
    }
    _roundSalaries();
    Player.showOpen = openPeriod;
    // 外国人・他リーグの選手：メインポジションが G1 のままなら、得意な位置をメインに
    for (final p in [
      ...teams.expand((t) => t.players).where((p) => p.nationality == '海外'),
      ...foreignPool,
      ...freeAgents.map((f) => f.player).where((p) => p.nationality == '海外'),
      ...?otherWorld?.allPlayers,
    ]) {
      FieldingGen.fixMainPos(p);
    }
    _ensureProspects();
    _ensureManagers();
    _ensureFinance();
    _syncFacilities();
    FarmEngine.devBonus = _farmDevBonus; // 2軍の自動スタメンに、2軍監督の育成眼で「育てる価値」を足す

    if (deferWorldGen && _freshInitial) {
      // 空のスロット（「新しく始める」画面用）：「開始する」を押すまでDB書き込み・他リーグ・アマチュア生成は行わない
      for (final p in [...teams.expand((t) => t.players), ...freeAgents.map((f) => f.player), ...foreignPool, ...prospects.map((x) => x.player)]) {
        if (p.nationality == '海外') {
          p.origin = switch (p.origin) { 'ベネズエラ' || 'プエルトリコ' => 'ドミニカ', 'カナダ' => 'アメリカ', _ => p.origin };
        } else if (p.birthplace.isEmpty) {
          p.birthplace = NamePool.prefecture(Random(p.id.hashCode));
        }
      }
      _ensureScoutNet();
      _snapRosters();
      loaded = true;
      notifyChanged();
      return;
    }

    // 以前のセーブの記録の修復（今季の成績がまだ選手に残っている間に）→ 以前の方式（1月1日に年度更新）のオフなら、ここで年度を切り替える
    await _repairLostSeasonRecords();
    await _fixInGameCareers();
    await _fixInitialProYears();

    var needSave = false;
    var needSaveWorld = false;
    final dirtyKv = <String, String>{};

    // 出身：日本人には都道府県、外国人は8か国（ベネズエラ・プエルトリコ → ドミニカ、カナダ → アメリカ）
    if (kv['originV2'] != '1') {
      for (final p in [...teams.expand((t) => t.players), ...freeAgents.map((f) => f.player), ...foreignPool, ...prospects.map((x) => x.player)]) {
        if (p.nationality == '海外') {
          p.origin = switch (p.origin) { 'ベネズエラ' || 'プエルトリコ' => 'ドミニカ', 'カナダ' => 'アメリカ', _ => p.origin };
        } else if (p.birthplace.isEmpty) {
          p.birthplace = NamePool.prefecture(Random(p.id.hashCode));
        }
      }
      needSave = true;
      dirtyKv['originV2'] = '1';
    }
    // 国内FA を8年に（以前は6年）：すでに日本人選手の扱いになった外国人選手は、そのままにする
    if (kv['fa8V1'] != '1') {
      var lost = 0;
      for (final p in [...teams.expand((t) => t.players), ...freeAgents.map((f) => f.player)]) {
        if (p.faService >= 6 && p.faService < Player.faYears) {
          if (p.nationality == '海外') {
            p.faService = Player.faYears;
          } else if (!p.ikusei) {
            lost++;
          }
        }
      }
      if (lost > 0) _addNews(['制度の変更：国内FA 権の取得は8年になりました（以前は6年）。6〜7年の選手$lost人は、8年になるまで FA 宣言できません']);
      needSave = true;
      dirtyKv['fa8V1'] = '1';
    }
    if (kv['sacRecountV2'] != '1') {
      recountSacAndGidp();
      needSave = true; // 数え直した成績をすぐ保存する
      dirtyKv['sacRecountV2'] = '1';
    }
    await _repairRenamedRecords();
    await _loadOther(); // 他リーグ（なければ作る）
    for (final p in otherWorld?.allPlayers ?? const <Player>[]) {
      FieldingGen.fixMainPos(p); // 以前に作った他リーグの選手：メインポジションが G1 なら得意な位置に
    }
    await _loadAmateur(); // アマチュア球界（なければ作る）
    if (kv['fieldGenV1'] != '1') {
      var n = 0;
      for (final p in [...teams.expand((t) => t.players), ...freeAgents.map((f) => f.player)]) {
        if (_fieldingIfDefault(p)) n++;
      }
      debugPrint('FIELDING REGEN: $n');
      dirtyKv['fieldGenV1'] = '1';
      if (n > 0) needSave = true;
    }
    if (kv['fieldGenV2'] != '1') {
      // 守備の基準を変えた：本職の底上げ（最低E45・多くはD〜B）と、守れる位置を増やす
      final r = Random(startYear * 7 + 3);
      var n = 0;
      for (final p in [...teams.expand((t) => t.players), ...freeAgents.map((f) => f.player), ...prospects.map((x) => x.player)]) {
        if (FieldingGen.upgrade(p, r)) n++;
      }
      debugPrint('FIELDING UPGRADE: $n');
      dirtyKv['fieldGenV2'] = '1';
      if (n > 0) needSave = true;
    }
    if (kv['veloV2'] != '1') {
      // 球速の基準を変えた（2026-11）：NPB 1軍は150km以上、プロ入りの高校生は140km台前半。アンダースローと160km以上はそのまま
      final seen = Set<Player>.identity();
      final pros = [...teams.expand((t) => t.players), ...freeAgents.map((f) => f.player), ...foreignPool, ...?otherWorld?.allPlayers];
      final ama = [...prospects.map((x) => x.player), ...?amWorld?.players.map((x) => x.player)];
      for (final p in pros) {
        if ((!p.isPitcher && !p.twoWay) || !seen.add(p)) continue;
        Velo.setTo(p, Velo.lift(p.velocity, amateur: p.ikusei, slot: p.armSlot));
      }
      for (final p in ama) {
        if ((!p.isPitcher && !p.twoWay) || !seen.add(p)) continue;
        Velo.setTo(p, Velo.lift(p.velocity, amateur: true, slot: p.armSlot));
      }
      debugPrint('VELO V2: ${seen.length}');
      needSave = true;
      needSaveWorld = true;
      dirtyKv['veloV2'] = '1';
    }
    if (kv['eyeV1'] != '1') {
      // 選球眼の平均を60に（チャンス・ピンチと同じ基準）：NPB 12球団の野手の平均との差を、全員に足す
      final bats = [for (final t in leagueTeams) for (final p in t.players) if (!p.isPitcher) p];
      final mean = bats.isEmpty ? 60.0 : bats.fold<int>(0, (s, p) => s + p.eye) / bats.length;
      final d = (60 - mean).round();
      if (d > 0) {
        final seen = Set<Player>.identity();
        for (final p in [...teams.expand((t) => t.players), ...freeAgents.map((f) => f.player), ...foreignPool, ...?otherWorld?.allPlayers, ...prospects.map((x) => x.player), ...?amWorld?.players.map((x) => x.player)]) {
          if (p.isPitcher || !seen.add(p)) continue;
          p.eye = (p.eye + d).clamp(1, 99);
        }
        debugPrint('EYE V1: +$d (${seen.length})');
        needSave = true;
        needSaveWorld = true;
      }
      dirtyKv['eyeV1'] = '1';
    }
    if (kv['fieldGenV3'] != '1') {
      // 守備の技術（捕球・送球・肩力）の高い選手・守備職人型は、本職の守備適性もある程度高く
      final seen = Set<Player>.identity();
      var n = 0;
      for (final p in [...teams.expand((t) => t.players), ...freeAgents.map((f) => f.player), ...foreignPool, ...?otherWorld?.allPlayers, ...prospects.map((x) => x.player), ...?amWorld?.players.map((x) => x.player)]) {
        if (p.isPitcher || !seen.add(p)) continue;
        if (FieldingGen.blendSkill(p, craftsman: CoachEngine.autoType(p) == '守備職人型')) n++;
      }
      debugPrint('FIELDING V3: $n');
      needSave = true;
      needSaveWorld = true;
      dirtyKv['fieldGenV3'] = '1';
    }
    if (kv['scoutNetV1'] != '1') {
      _ensureScoutNet(); // 地区担当・海外担当のスカウト（以前の「スカウト」は本拠地の地区担当に）
      dirtyKv['scoutNetV1'] = '1';
      needSave = true;
    }
    if (needSaveWorld) {
      await _saveAmateur();
      await _saveOther();
    }
    if (needSave) {
      await saveData();
    }
    if (dirtyKv.isNotEmpty) {
      await db.setKvBatch(dirtyKv);
    }
    if (seasonFinished && currentDate.year == startYear) {
      _rollover();
      _addNews(['年度の切り替えを「全日程の終了時」に変えたため、${startYear}年度に切り替えました（年齢・プロ年数＋1、今季の成績は通算へ）']);
    }
    if (_needFirsts) {
      _initFirsts();
      _needFirsts = false;
    }
    // 以前のセーブの修復：シーズン中やオフ宣言前の古いFAケースを破棄、または宣言日を過ぎていれば宣言
    if (!offAfterSeason && !seasonFinished) {
      faCases = [];
    } else if (offAfterSeason) {
      final declareDay = faDeclareDate(currentDate.year);
      if (currentDate.isBefore(declareDay)) {
        faCases = [];
      } else if (faCases.isNotEmpty && faCases.every((f) => f.result.isNotEmpty)) {
        faCases = []; // 前年の結果が残っている
      }
      ensureFaDeclaredIfNeeded();
    }
    _snapRosters(); // ここからの入団・退団を記録する
    if (newsLog.isEmpty && news.isNotEmpty) newsLog[currentDate.year] = List.of(news); // 以前のお知らせを、記録の始まりに
    await db.vacuumIfBloated(); // 以前のセーブ：消した記録の空きページが残っているときだけ、ファイルを詰める（数秒）
    loaded = true;
    notifyChanged();
    loadMatchups();
    _fixCareerEstimates();
    AiWriter.instance.load();
  }

  /// ドラフト・移籍のデータを読む（kv にもバックアップにも同じ形で入れる）
  void _applyMoveKv(Map<String, dynamic> kv) {
    dynamic j(String k) {
      final v = kv[k];
      if (v == null) return null;
      return v is String ? jsonDecode(v) : v;
    }
    prospects = [for (final e in (j('prospects') as List? ?? [])) Prospect.fromJson(Map<String, dynamic>.from(e as Map))];
    draftDoneYear = int.tryParse('${kv['draftDoneYear'] ?? 0}') ?? 0;
    activeDraftYear = int.tryParse('${kv['activeDraftYear'] ?? 0}') ?? 0;
    prepDraftYear = int.tryParse('${kv['prepDraftYear'] ?? 0}') ?? 0;
    scoutLog = List<String>.from(j('scoutLog') as List? ?? []);
    tradeTips = [for (final e in (j('tradeTips') as List? ?? [])) Map<String, dynamic>.from(e as Map)];
    freeAgents = [for (final e in (j('freeAgents') as List? ?? [])) FreeAgent.fromJson(Map<String, dynamic>.from(e as Map))];
    faCases = [for (final e in (j('faCases') as List? ?? [])) FaCase.fromJson(Map<String, dynamic>.from(e as Map))];
    foreignPool = [for (final e in (j('foreignPool') as List? ?? [])) Player.fromJson(Map<String, dynamic>.from(e as Map))];
    foreignWatch = Set<String>.from(j('foreignWatch') as List? ?? const []);
    final rn = j('renewals') as Map?;
    renewSigned = Set<String>.from(rn?['s'] ?? const []);
    renewTries = {for (final e in ((rn?['t'] as Map?) ?? const {}).entries) '${e.key}': (e.value as num).toInt()};
    pendingComp = [for (final e in (j('pendingComp') as List? ?? [])) CompCase.fromJson(Map<String, dynamic>.from(e as Map))];
    compPicks = {for (final e in ((j('compPicks') as Map?) ?? {}).entries) '${e.key}': [for (final v in e.value as List) (v as num).toInt()]};
    pickOwner = Map<String, String>.from((j('pickOwner') as Map?) ?? {});
    teamPolicy = Map<String, String>.from((j('teamPolicy') as Map?) ?? {});
    lastTradeWith = Map<String, String>.from((j('lastTradeWith') as Map?) ?? {});
    postingAsk = Map<String, String>.from((j('postingAsk') as Map?) ?? {});
    partnerSlots = [for (final e in (j('partnerSlots') as List? ?? [])) Map<String, dynamic>.from(e as Map)];
    partnerStay = List<String>.from(j('partnerStay') as List? ?? []);
    tenders = [for (final e in (j('tenders') as List? ?? [])) Map<String, dynamic>.from(e as Map)];
    ledger = [for (final e in (j('ledger') as List? ?? [])) Map<String, dynamic>.from(e as Map)];
    transactions = List<String>.from(j('transactions') as List? ?? []);
    finances = {for (final e in ((j('finance') as Map?) ?? {}).entries) e.key as String: TeamFinance.fromJson(Map<String, dynamic>.from(e.value as Map))};
    for (final f in finances.values) {
      f.capacity = FinanceEngine.capacity; // ver1.0 は12球団とも同じ球場（以前のセーブも合わせる）
    }
    sponsorOffers = [for (final e in (j('sponsorOffers') as List? ?? [])) Sponsor.fromJson(Map<String, dynamic>.from(e as Map))];
    consultants = [for (final e in (j('consultants') as List? ?? [])) Consultant.fromJson(Map<String, dynamic>.from(e as Map))];
    ownerFiring = '${kv['ownerFiring'] ?? '1'}' != '0' && kv['ownerFiring'] != false;
    fired = '${kv['fired'] ?? '0'}' == '1' || kv['fired'] == true;
    firedOffers = List<String>.from(j('firedOffers') as List? ?? []);
    // 試合数（以前のセーブは 156 試合の日程なので 156）・天気の種（なければ作る）
    seasonGames = int.tryParse('${kv['seasonGames'] ?? ''}') ?? 156;
    LeagueRules.load(j('leagueRules') as Map<String, dynamic>?);
    weatherSeed = int.tryParse('${kv['weatherSeed'] ?? ''}') ?? Random().nextInt(1 << 30);
    rainoutCount = int.tryParse('${kv['rainouts'] ?? ''}') ?? 0;
    campProposals = [for (final e in (j('campProposals') as List? ?? [])) Map<String, dynamic>.from(e as Map)];
    makerCollabs = [for (final e in (j('makerCollabs') as List? ?? [])) Map<String, dynamic>.from(e as Map)];
    _applySeasonGames();
    ronin = kv['ronin'] == '1';
    roninReturn = kv['roninReturn'] == '1';
    if (ronin) autoMode = true; // 浪人中はドラフト・補償なども自動で進む
    lastRankOf = Map<String, int>.from((j('lastRank') as Map?) ?? {});
    thirdMatches = [for (final e in (j('thirdMatches') as List? ?? [])) Match.fromJson(Map<String, dynamic>.from(e as Map))];
  }

  /// 以前の保存方式（SharedPreferences）のデータがあれば、DBへ移す。移せたら true
  Future<bool> _migrateFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final teamsJson = prefs.getString('teamsData');
    if (teamsJson == null) return false;
    try {
      teams = (jsonDecode(teamsJson) as List).map((t) => Team.fromJson(t, Player.fromJson)).toList();
      _raiseBody(teams);
      if (prefs.getString('currentDate') != null) currentDate = DateTime.parse(prefs.getString('currentDate')!);
      gameMode = prefs.getString('gameMode') ?? 'auto';
      news = prefs.getStringList('news') ?? [];
      myTeamId = prefs.getString('myTeamId') ?? '';
      if (prefs.getString('matchesData') != null) {
        matches = (jsonDecode(prefs.getString('matchesData')!) as List).map((m) => Match.fromJson(m)).toList();
      } else {
        _generateSchedule(keepDate: true);
      }
      _buildFarmMatches();
      _matchesReplaceAll = true;
      await saveData();
      for (final k in ['teamsData', 'currentDate', 'gameMode', 'news', 'myTeamId', 'matchesData']) {
        await prefs.remove(k);
      }
      return true;
    } catch (e) {
      debugPrint('MIGRATE ERROR: $e');
      return false;
    }
  }

  Future<void> saveData() async {
    _writeSlotSummary();
    if (_wipeHistory) {
      _wipeHistory = false;
      await db.wipeHistory();
      _matchesReplaceAll = true; // 試合は今の日程で書き直す
    }
    _roundSalaries(); // 年俸は50万円単位
    await _maybeSaveOther(); // 他リーグは30日ごと・シーズンの区切りに
    await _maybeSaveAmateur(); // アマチュア球界は7日ごと・年度の区切りに
    if (loaded) _diffRosters(); // 入団・退団・コーチの就任と退任を記録する
    // 画面の状態をこの時点で固めてから、順に書き込む（連続して呼ばれても混ざらない）
    final changedTeams = <TeamRowsCompanion>[];
    for (var i = 0; i < teams.length; i++) {
      final js = jsonEncode(teams[i].toJson());
      if (_savedTeamJson[teams[i].id] != js || _savedTeamSort[teams[i].id] != i) {
        changedTeams.add(TeamRowsCompanion.insert(id: teams[i].id, sort: i, json: js));
        _savedTeamJson[teams[i].id] = js;
        _savedTeamSort[teams[i].id] = i;
      }
    }
    final teamIds = [for (final t in teams) t.id];
    _savedTeamJson.removeWhere((k, _) => !teamIds.contains(k));
    final changedProspects = <ProspectRowsCompanion>[];
    final prospectIds = <String>[];
    for (var i = 0; i < prospects.length; i++) {
      final id = prospects[i].id;
      prospectIds.add(id);
      final js = jsonEncode(prospects[i].toJson());
      if (_savedProspectJson[id] != js || _savedProspectSort[id] != i) {
        changedProspects.add(ProspectRowsCompanion.insert(id: id, sort: i, json: js));
        _savedProspectJson[id] = js;
        _savedProspectSort[id] = i;
      }
    }
    final prospectIdSet = prospectIds.toSet();
    _savedProspectJson.removeWhere((k, _) => !prospectIdSet.contains(k));
    _savedProspectSort.removeWhere((k, _) => !prospectIdSet.contains(k));
    final dropLegacyProspects = _legacyProspectKv;
    _legacyProspectKv = false;
    final backupLabel = _backupBeforeSave;
    _backupBeforeSave = null;
    final backupDate = '${currentDate.year}年${currentDate.month}月${currentDate.day}日';
    final season = startYear;
    final kv = <String, String>{
      'startYear': '$startYear',
      'currentDate': currentDate.toIso8601String(),
      'gameMode': gameMode,
      'recordAllPitches': recordAllPitches ? '1' : '0',
      'seasonFinished': seasonFinished ? '1' : '0',
      'offAfter': offAfterSeason ? '1' : '0',
      'postseason': jsonEncode(postseason.map((s) => s.toJson()).toList()),
      'coaches': jsonEncode(coaches.map((c) => c.toJson()).toList()),
      'myTeamId': myTeamId,
      'news': jsonEncode(news),
      'monthlyMvps': jsonEncode(monthlyMvps),
      'monthSnap': jsonEncode(monthSnap),
      'retirees': jsonEncode(retirees),
      'draftBook': jsonEncode({for (final e in draftBook.entries) '${e.key}': e.value}),
      'myCareer': jsonEncode(myCareer),
      'bodyV2': '1',
      'pitchV2': '1',
      'traitV3': '1',
      'velV1': '1',
      'roster63': '1',
      'appsV1': '1',
      'decV2': '1',
      'recV1': '1',
      'careerV3': _careerV2 ? '1' : '0',
      'handV1': '1',
      'compactV1': '1',
      'firstsV1': '1',
      if (_freshInitial) ...const {
        'proYearFixV1': '1',
        'originV2': '1',
        'fa8V1': '1',
        'sacRecountV2': '1',
        'fieldGenV1': '1',
        'fieldGenV2': '1',
        'veloV2': '1',
        'eyeV1': '1',
        'fieldGenV3': '1',
        'scoutNetV1': '1',
      },
      'chronFirst': '$chronFirstYear',
      'openingNumbers': openingNumberDay,
      for (final y in [startYear - 1, startYear]) if (chronYears[y] != null) 'chron_$y': jsonEncode(chronYears[y]),
      for (final e in newsLog.entries) if (e.key >= currentDate.year - 2) 'news_${e.key}': jsonEncode(e.value),
      ..._moveKv(withProspects: false),
    };
    kv.removeWhere((k, v) => _savedKv[k] == v);
    _savedKv.addAll(kv);
    final pitchRows = _pendingPitches;
    _pendingPitches = [];
    final compact = _compactSeasonPending;
    _compactSeasonPending = null;
    final replaceAll = _matchesReplaceAll;
    _matchesReplaceAll = false;
    final allJson = <int, String>{};
    final allPlayed = <int, bool>{};
    final newJson = <int, String>{};
    final newPlayed = <int, bool>{};
    if (replaceAll) {
      for (var i = 0; i < matches.length; i++) {
        allJson[i] = jsonEncode(matches[i].toJson());
        allPlayed[i] = matches[i].homeScore != null;
      }
      for (var i = 0; i < farmMatches.length; i++) {
        allJson[AppState.farmIdxBase + i] = jsonEncode(farmMatches[i].toJson());
        allPlayed[AppState.farmIdxBase + i] = farmMatches[i].homeScore != null;
      }
      _savedPlayed
        ..clear()
        ..addAll([for (var i = 0; i < matches.length; i++) if (matches[i].homeScore != null) i]);
      _savedFarmPlayed
        ..clear()
        ..addAll([for (var i = 0; i < farmMatches.length; i++) if (farmMatches[i].homeScore != null) i]);
    } else {
      for (var i = 0; i < matches.length; i++) {
        if (matches[i].homeScore != null && !_savedPlayed.contains(i)) {
          newJson[i] = jsonEncode(matches[i].toJson());
          newPlayed[i] = true;
          _savedPlayed.add(i);
        }
      }
      for (var i = 0; i < farmMatches.length; i++) {
        if (farmMatches[i].homeScore != null && !_savedFarmPlayed.contains(i)) {
          newJson[AppState.farmIdxBase + i] = jsonEncode(farmMatches[i].toJson());
          newPlayed[AppState.farmIdxBase + i] = true;
          _savedFarmPlayed.add(i);
        }
      }
    }
    Future<void> write() async {
    try {
      // ドラフト・年度替わり・契約更改の直前：書き込む前のデータベース（前の保存の状態）を、詰めた形で控えに残す
      if (backupLabel != null) await db.backupSlot(label: backupLabel, gameDate: backupDate);
      await db.syncTeams(changedTeams, teamIds);
      await db.syncProspects(changedProspects, prospectIds);
      if (dropLegacyProspects) await db.deleteKv('prospects');
      await db.setKvBatch(kv);
      if (pitchRows.isNotEmpty) await db.savePitches(pitchRows);
      if (compact != null) {
        await db.compactSeason(compact, keepPitchSeasons: recordAllPitches ? 1 : 2); // 1球ごとの記録は直近2シーズン（他球団も記録しているときは1シーズン）残す
        await db.vacuumIfBloated(); // 消した分の空きページを詰める
      }
      if (replaceAll) {
        await db.replaceMatches(season, allJson, allPlayed);
      } else if (newJson.isNotEmpty) {
        await db.upsertMatches(season, newJson, newPlayed);
      }
    } catch (e, st) {
      debugPrint('SAVE ERROR: $e\n$st');
      _pendingPitches.insertAll(0, pitchRows);
      _savedTeamJson.clear(); // 失敗したら、次は全部書き直す
      _savedProspectJson.clear();
      _savedProspectSort.clear();
      if (dropLegacyProspects) _legacyProspectKv = true;
      _savedKv.clear();
      _matchesReplaceAll = true; // 失敗したら、次は全部書き直す
    }
    }
    return _saveQueue = _saveQueue.then((_) => write());
  }

  /// バックアップを読み込んで置き換える。読めなければ false（今のデータは変えない）
  Future<bool> importSaveJson(String text) async {
    try {
      final d = jsonDecode(text) as Map<String, dynamic>;
      if (d['format'] != AppState._backupFormat) return false;
      final newTeams = (d['teams'] as List).map((t) => Team.fromJson(t, Player.fromJson)).toList();
      final newMatches = (d['matches'] as List).map((m) => Match.fromJson(m)).toList();
      teams = newTeams;
      matches = newMatches;
      farmMatches = [for (final m in (d['farmMatches'] as List? ?? [])) Match.fromJson(m)];
      seasonFinished = d['seasonFinished'] as bool? ?? false;
      offAfterSeason = d['offAfter'] as bool? ?? false;
      postseason = [for (final j in (d['postseason'] as List? ?? [])) Series.fromJson(j as Map<String, dynamic>)];
      coaches = [for (final j in (d['coaches'] as List? ?? [])) Coach.fromJson(j as Map<String, dynamic>)];
      _applyMoveKv(d);
      _ensureCoaches();
      _fillStaff();
      for (final t in teams) {
        for (final p in t.players) {
          CareerEngine.estimateIfMissing(p);
        }
      }
      if (farmMatches.length != matches.length) _buildFarmMatches();
      startYear = d['startYear'] as int;
      currentDate = DateTime.parse(d['currentDate'] as String);
      gameMode = d['gameMode'] as String? ?? 'auto';
      myTeamId = d['myTeamId'] as String? ?? '';
      news = List<String>.from(d['news'] as List? ?? []);
      _migratePitchers();
      _roundSalaries();
      _ensureProspects();
      _ensureManagers();
      _ensureFinance();
      _syncFacilities();
      _matchesReplaceAll = true;
      notifyChanged();
      await saveData();
      return true;
    } catch (e) {
      debugPrint('IMPORT ERROR: $e');
      return false;
    }
  }

  /// プレイデータの枠の一覧に出す要約（球団・日付・成績）
  Future<void> _writeSlotSummary() async {
    final t = myTeam;
    if (t == null || !loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('slotSummary_$slot', jsonEncode({'team': t.name, 'short': teamShort(t), 'date': currentDate.toIso8601String(), 'w': t.wins, 'l': t.losses, 'd': t.draws}));
    } catch (_) {}
  }
}
