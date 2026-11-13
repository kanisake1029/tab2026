part of 'app_state.dart';

/// アマチュア球界（高校・大学・社会人）：読み込み・保存・4月の年度の切り替え
extension AmateurOps on AppState {
  /// アマチュアの年度（4月に切り替える）
  int amSchoolYear(DateTime d) => d.month >= 4 ? d.year : d.year - 1;

  /// 読み込む（なければ作る）
  Future<void> _loadAmateur() async {
    try {
      final raw = await db.getKv('amWorld');
      if (raw != null && raw.isNotEmpty) {
        amWorld = AmWorld.fromJson(jsonDecode(utf8.decode(gzip.decode(base64.decode(raw)))) as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint('AMATEUR LOAD ERROR: $e');
      amWorld = null;
    }
    if (amWorld != null && amWorld!.gen < AmateurEngine.genVersion && amWorld!.players.isEmpty) amWorld = null; // 作り方が変わった（大学の数・学校の名前）
    if (amWorld == null) {
      final y = amSchoolYear(currentDate);
      amWorld = AmateurEngine.generate(y, Random(y * 17 + 3));
      _amForceSave = true;
    } else if (amWorld!.comps.isEmpty) {
      // 大会のない以前のデータ：今年の大会を作り、4月から計算し直す
      AmateurSeason.setupYear(amWorld!, Random(amWorld!.year * 17 + 5));
      amWorld!.simDate = DateTime(amWorld!.year, 3, 31);
      _amForceSave = true;
    }
    _amSavedAt = amWorld!.simDate;
    _amateurAdvance(currentDate); // 保存した日から今日の前日まで（日付で決まる乱数なので、計算し直しても同じ結果）
    _amRelink(); // ドラフト候補と同じ選手を指すように
    if (_amForceSave) await _saveAmateur();
  }

  Future<void> _saveAmateur() async {
    final w = amWorld;
    if (w == null) return;
    await db.setKv('amWorld', base64.encode(gzip.encode(utf8.encode(jsonEncode(w.toJson())))));
    _amSavedAt = w.simDate;
    _amForceSave = false;
  }

  /// 保存のとき：発掘・年度の切り替え・ドラフトがあったときと、7日ごと（試合は読み込んだときに計算し直せる）
  Future<void> _maybeSaveAmateur() async {
    final w = amWorld;
    if (w == null) return;
    if (_amForceSave || _amSavedAt == null || w.simDate.difference(_amSavedAt!).inDays >= 7) await _saveAmateur();
  }

  /// 日付を進めたとき：今日の前日までの試合をする（4月1日に年度を切り替える）
  void _amateurAdvance(DateTime to) {
    final w = amWorld;
    if (w == null) return;
    final last = DateUtils.dateOnly(to).subtract(const Duration(days: 1));
    var d = DateUtils.dateOnly(w.simDate).add(const Duration(days: 1));
    while (!d.isAfter(last)) {
      if (amSchoolYear(d) > w.year) {
        AmateurEngine.newYear(w, amSchoolYear(d), Random(d.year * 101 + 9));
        _amNewYearProspects();
        _amForceSave = true;
      }
      AmateurSeason.playDay(w, d);
      w.simDate = d;
      d = d.add(const Duration(days: 1));
    }
  }

  // ───────── スカウト網と発掘 ─────────

  /// 球団の本拠地の地区
  int homeRegion(Team t) {
    final i = NameData2.prefectures.indexWhere((p) => p.$1 == t.homePrefecture);
    return i < 0 ? 2 : amPrefRegion[i];
  }

  /// 地区担当・海外担当がいなければ、ふつうの顔ぶれで置く（以前の「スカウト」は本拠地の地区担当に）。読み込みで1度だけ・はじめからのとき
  void _ensureScoutNet({bool onlyEmpty = false}) {
    final r = Random(currentDate.millisecondsSinceEpoch ^ 0x5c);
    for (final t in teams) {
      final mine = coaches.where((c) => c.teamId == t.id).toList();
      for (final c in mine.where((c) => c.role == 'スカウト')) {
        c.role = '${CoachEngine.regionScoutPrefix}${amRegions[homeRegion(t)]}';
      }
      // すでにスカウト網があれば（以前の「スカウト」から移した1人だけなら作る）
      if (mine.where((c) => CoachEngine.isScout(c.role) && c.role != 'チーフスカウト').length > 1) continue;
      if (onlyEmpty && mine.any((c) => CoachEngine.isScout(c.role) && c.role != 'チーフスカウト')) continue; // 読み込み時：1人でもいればそのまま（減らした分を勝手に戻さない）
      // 地区担当：本拠地の地区を含めて5〜9地区（本拠地は2人のことも）
      final home = homeRegion(t);
      final regions = [for (var i = 0; i < amRegions.length; i++) if (i != home) i]..shuffle(r);
      final pick = [home, ...regions.take(4 + r.nextInt(5))];
      final roles = <String>[
        for (final rg in pick) '${CoachEngine.regionScoutPrefix}${amRegions[rg]}',
        if (r.nextBool()) '${CoachEngine.regionScoutPrefix}${amRegions[home]}',
      ];
      // 海外担当：大リーグ・アジアから2〜4リーグ、日本の独立リーグから1つ
      final abroad = ['MLB', 'AAA', 'AA', 'KBO', 'CPBL', 'MEX']..shuffle(r);
      final jp = OtherLeagueEngine.leagues.values.where((l) => l.group == '日本独立').map((l) => l.id).toList()..shuffle(r);
      roles.addAll([for (final id in abroad.take(2 + r.nextInt(3))) '${CoachEngine.overseasScoutPrefix}$id', if (jp.isNotEmpty) '${CoachEngine.overseasScoutPrefix}${jp.first}']);
      for (final role in roles) {
        if (mine.any((c) => c.role == role) && !role.startsWith(CoachEngine.regionScoutPrefix)) continue;
        if (mine.where((c) => c.role == role).length >= 2) continue;
        final c = CoachEngine.generate(r, 'CO${DateTime.now().microsecondsSinceEpoch}${r.nextInt(99999)}', pitcherBg: r.nextBool(), formerTeamId: t.id, age: 38 + r.nextInt(25));
        c.teamId = t.id;
        c.role = role;
        c.salary = CoachEngine.scoutSalary(c);
        coaches.add(c);
        mine.add(c);
      }
    }
    _staffCache.clear();
  }

  /// スカウトの打診の候補：眼力C（60）以上の、どこにも属していない人を最低 n 人そろえる（足りなければスカウトの経験者を作る）
  void ensureScoutMarket({int n = 12}) {
    bool good(Coach c) => c.teamId == null && (c.trueAbil['スカウト眼力'] ?? 0) >= 60;
    var have = coaches.where(good).length;
    final r = Random(currentDate.millisecondsSinceEpoch ^ 0x3a);
    while (have < n) {
      final c = CoachEngine.generate(r, 'CO${DateTime.now().microsecondsSinceEpoch}${r.nextInt(99999)}', pitcherBg: r.nextBool(), formerTeamId: '', age: 40 + r.nextInt(25));
      final eye = 60 + r.nextInt(26); // C〜A
      c.trueAbil['スカウト眼力'] = eye;
      c.expected['スカウト眼力'] = (eye + r.nextInt(9) - 4).clamp(55, 95);
      coaches.add(c);
      have++;
    }
  }

  /// 球団ごとのスカウト網（地区担当の眼力。設備の分も足す）
  List<ScoutNet> _scoutNets() => [
        for (final t in teams)
          ScoutNet(t.id, {
            for (var rg = 0; rg < amRegions.length; rg++)
              rg: [
                for (final c in coaches)
                  if (c.teamId == t.id && c.role == '${CoachEngine.regionScoutPrefix}${amRegions[rg]}') ((c.trueAbil['スカウト眼力'] ?? 50) + FacilityEngine.scoutBonus(finOf(t).fac('scout'))).clamp(1, 99),
              ],
          }),
      ];

  /// 以前の方式の候補で今年のドラフトをする年（その年は発掘をしない）
  bool get _legacyDraftYear => prospects.any((p) => p.knownBy.isEmpty && p.player.origin.isEmpty && p.year == (amWorld?.year ?? -1));

  /// 発掘・知った選手をドラフト候補にする（いなければ作る）
  Prospect _prospectOf(AmPlayer ap) {
    final w = amWorld!;
    final ex = prospects.where((p) => p.id == ap.id).firstOrNull;
    if (ex != null) return ex;
    final t = w.team(ap.teamId)!;
    final r = Random(ap.id.hashCode);
    final pr = Prospect(player: ap.player, year: w.year, category: t.kind, school: t.name, curBias: r.nextInt(9) - 4, memo: ap.record, knownBy: Set.of(ap.foundBy));
    prospects.add(pr);
    return pr;
  }

  /// 毎週月曜（4〜10月）：全球団のスカウトが回って発掘する。自球団の発掘は週報に
  void _amScoutWeek(DateTime d) {
    final w = amWorld;
    if (w == null || d.month < 4 || d.month > 10 || _legacyDraftYear || draftDoneYear >= w.year) return;
    final r = Random(d.year * 1000 + d.month * 40 + d.day);
    final ev = AmateurScout.week(w, _scoutNets(), d, r);
    for (final s in const ['春', '夏']) {
      final k = w.comp('$s-koshien');
      if (k != null && k.done && w.flags.add('$s-koshien')) ev.addAll(AmateurScout.koshienBuzz(w, k, [for (final t in teams) t.id], r));
    }
    final mineNew = <String>[];
    for (final e in ev) {
      final pr = _prospectOf(e.player);
      pr.knownBy.add(e.teamId);
      if (e.teamId == myTeamId) mineNew.add('${e.player.player.lastName}（${w.team(e.player.teamId)?.name ?? ''}・${e.player.player.isPitcher ? '投手' : e.player.player.mainPosition}）');
    }
    if (mineNew.isNotEmpty) {
      scoutLog.insert(0, '${d.month}/${d.day} 発掘：${mineNew.join('、')}');
      if (scoutLog.length > 60) scoutLog = scoutLog.sublist(0, 60);
    }
    if (ev.isNotEmpty) _amForceSave = true;
  }

  /// 毎週月曜：海外担当が受け持ちのリーグの球団を回る。海外の選手は自球団の「追い続ける一覧」に、日本の独立リーグの選手は（4〜10月）ドラフト候補に
  void _overseasScoutWeek(DateTime d) {
    final ow = otherWorld, aw = amWorld;
    if (ow == null) return;
    final r = Random(d.year * 977 + d.month * 31 + d.day);
    final draftOpen = aw != null && d.month >= 4 && d.month <= 10 && !_legacyDraftYear && draftDoneYear < aw.year;
    final mineNew = <String>[];
    for (final t in teams) {
      final byLeague = <String, List<int>>{};
      for (final c in coaches) {
        if (c.teamId != t.id || c.role == null || !c.role!.startsWith(CoachEngine.overseasScoutPrefix)) continue;
        byLeague.putIfAbsent(c.role!.substring(CoachEngine.overseasScoutPrefix.length), () => []).add(((c.trueAbil['スカウト眼力'] ?? 50) + FacilityEngine.scoutBonus(finOf(t).fac('scout'))).clamp(1, 99));
      }
      for (final e in byLeague.entries) {
        final lg = OtherLeagueEngine.leagues[e.key];
        if (lg == null) continue;
        final indie = lg.group == '日本独立';
        if (indie && !draftOpen) continue;
        final eyes = e.value..sort((a, b) => b.compareTo(a));
        var n = 0.0;
        for (var i = 0; i < eyes.length; i++) {
          n += (1 + eyes[i] / 40) * (i == 0 ? 1.0 : 0.7);
        }
        final q = 0.22 * (0.5 + eyes.first / 100);
        final lts = ow.teamsOf(e.key)..shuffle(r);
        for (final ot in lts.take(n.round())) {
          for (final p in ot.players) {
            if (ow.fromNpb.containsKey(p.id) || r.nextDouble() >= q) continue;
            if (indie) {
              if (p.nationality == '海外' || p.draftYear > 0 || p.age > 29) continue;
              final pr = _indieProspect(p, ot, aw!.year);
              if (pr.knownBy.add(t.id)) {
                aw.indie.putIfAbsent(p.id, () => {}).add(t.id);
                if (t.id == myTeamId) mineNew.add('${p.lastName}（${ot.name}）');
              }
            } else if (t.id == myTeamId && p.nationality == '海外' && foreignWatch.add(p.id)) {
              mineNew.add('${p.registeredName}（${lg.name}・${ot.short}）');
            }
          }
        }
      }
    }
    if (mineNew.isNotEmpty) {
      scoutLog.insert(0, '${d.month}/${d.day} 海外担当：${mineNew.take(12).join('、')}${mineNew.length > 12 ? 'ほか${mineNew.length - 12}人' : ''}');
      if (scoutLog.length > 60) scoutLog = scoutLog.sublist(0, 60);
    }
    if (draftOpen) _amForceSave = true;
  }

  /// 日本の独立リーグの選手をドラフト候補にする（いなければ写して作る。指名されたら独立リーグから外れる）
  Prospect _indieProspect(Player src, OTeam ot, int year) {
    final ex = prospects.where((p) => p.id == src.id).firstOrNull;
    if (ex != null) return ex;
    final p = Player.fromJson(src.toJson());
    p.seasonStats = PlayerStats();
    p.farmStats = PlayerStats();
    p.thirdStats = PlayerStats();
    p.career = PlayerStats();
    p.proYears = 1;
    p.faService = 0;
    final memo = [for (final l in src.abroad) l.replaceFirst('日本独立', OtherLeagueEngine.leagues[ot.leagueId]?.name ?? '独立')];
    p.abroad = memo;
    p.amPath = CareerPath.derive(p, '独立', last: '${ot.name}（${OtherLeagueEngine.leagues[ot.leagueId]?.name ?? '独立リーグ'}）');
    final pr = Prospect(player: p, year: year, category: '独立', school: ot.name, curBias: Random(src.id.hashCode).nextInt(9) - 4, memo: memo.isEmpty ? ['（独立リーグでの記録はまだありません）'] : memo);
    prospects.add(pr);
    return pr;
  }

  /// 4月：去年までに発掘した選手が卒業の学年になったら、また候補にする（一度見つけた選手は追い続ける）
  void _amNewYearProspects() {
    final w = amWorld;
    if (w == null) return;
    // 独立リーグ：前に発掘した選手が、まだ独立リーグにいれば候補に
    final ow = otherWorld;
    if (ow != null) {
      w.indie.removeWhere((id, _) => ow.teamOfPlayer(id) == null);
      for (final e in w.indie.entries) {
        final ot = ow.teamOfPlayer(e.key)!;
        final src = ot.players.firstWhere((p) => p.id == e.key);
        if (OtherLeagueEngine.leagues[ot.leagueId]?.group != '日本独立' || src.age > 29) continue;
        _indieProspect(src, ot, w.year).knownBy.addAll(e.value);
      }
    }
    for (final ap in w.players) {
      final t = w.team(ap.teamId);
      if (t == null || ap.foundBy.isEmpty || !AmateurScout.eligible(ap, t)) continue;
      final pr = _prospectOf(ap);
      pr.knownBy.addAll(ap.foundBy);
    }
  }

  /// ドラフトで指名された：チームの指名実績とパイプ（指名した球団のスカウトが、そこで原石を見つけやすくなる）
  void _amOnDrafted(Prospect pr, Team t, int year, String label) {
    final w = amWorld;
    if (w == null) return;
    final ap = w.players.where((x) => x.id == pr.id).firstOrNull;
    if (ap == null) return;
    final am = w.team(ap.teamId);
    if (am != null) {
      am.pipe[t.id] = (am.pipe[t.id] ?? 0) + 1;
      am.drafted.add('$year ${teamShort(t)} $label ${pr.player.registeredName}');
    }
    w.players.remove(ap);
    _amForceSave = true;
  }

  /// 読み込んだとき：ドラフト候補と同じ選手を指すようにつなぎ直す（成績・能力を1つに）
  void _amRelink() {
    final w = amWorld;
    if (w == null) return;
    final byId = {for (final p in prospects) p.id: p};
    for (final ap in w.players) {
      final pr = byId[ap.id];
      if (pr == null) continue;
      ap.player = pr.player;
      pr.memo = ap.record;
    }
  }
}
