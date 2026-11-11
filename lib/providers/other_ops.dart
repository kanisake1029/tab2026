part of 'app_state.dart';

/// 他リーグ（MLB・マイナー・海外・独立リーグ）：毎日の試合・シーズンの区切り・保存
///  他リーグは数千人いるので、保存は30日ごととシーズンの区切りだけ。読み込んだときに、保存した日から今日の前日までを計算し直す
///  （毎日の試合は日付で決まる乱数なので、計算し直しても同じ結果になる）
extension OtherOps on AppState {
  /// 他リーグを読み込む（なければ作る）。今日の前日まで進める
  Future<void> _loadOther() async {
    try {
      final raw = await db.getKv('olWorld');
      if (raw != null && raw.isNotEmpty) {
        final j = jsonDecode(utf8.decode(gzip.decode(base64.decode(raw)))) as Map<String, dynamic>;
        otherWorld = OtherWorld.fromJson(j);
      }
    } catch (e) {
      debugPrint('OTHER LOAD ERROR: $e');
      otherWorld = null;
    }
    // 作り方を変えたとき（力・年齢・出身の割合）：元NPB の選手がまだいなければ作り直す
    if (await db.getKv('olGenV') != '3') {
      if (otherWorld != null && otherWorld!.fromNpb.isEmpty) otherWorld = null;
      await db.setKv('olGenV', '3');
      await db.setKv('olNamesV3', '1'); // 作り直した分は名前も新しい
    }
    if (otherWorld == null) {
      // 今年の1月1日から作って今日まで進める（シーズンの途中で始めても、ここまでの成績がある）
      otherWorld = OtherLeagueEngine.generate(DateTime(currentDate.year, 1, 1), currentDate.year);
      _otherForceSave = true;
    }
    if (await db.getKv('olTalentV2') != '1' && otherWorld != null) {
      final w = otherWorld!;
      for (final t in w.teams) {
        final lg = OtherLeagueEngine.leagues[t.leagueId];
        if (lg == null) continue;
        for (final p in t.players) {
          final indie = lg.group == '米独立' || lg.group == '日本独立';
          if (w.fromNpb.containsKey(p.id) || (p.nationality != '海外' && !indie)) continue;
          OtherLeagueEngine.setPotential(p, lg, Random(p.id.hashCode));
        }
      }
      _otherForceSave = true;
      await db.setKv('olTalentV2', '1');
    }
    if (await db.getKv('olNamesV3') != '1') {
      _renameOther();
      await db.setKv('olNamesV3', '1');
    }
    _otherAdvance(DateUtils.dateOnly(currentDate));
    // ドラフト候補の独立出身が、まだ他リーグの選手でなければ（以前のセーブ・読み込みの順番）置き換える
    if (prospects.isNotEmpty && prospects.any((p) => p.category == '独立' && otherPlayer(p.id) == null)) {
      prospects = _withIndie(prospects, prospects.first.year);
    }
    if (_otherForceSave) await _saveOther();
  }

  /// 他リーグの選手の名前を、大きな名前の一覧で付け直す（以前に作った分。元NPB の選手はそのまま）
  void _renameOther() {
    final w = otherWorld;
    if (w == null) return;
    final r = Random(7);
    for (final t in w.teams) {
      final used = <String>{};
      for (final p in t.players) {
        if (w.fromNpb.containsKey(p.id)) continue;
        if (p.nationality != '海外') {
          if (p.birthplace.isEmpty) p.birthplace = NamePool.prefecture(r);
          NamePool.assign(p, r, used: used);
          continue;
        }
        final mix = OtherLeagueEngine.originMix[t.leagueId] ?? OtherLeagueEngine.originMix['AAA']!;
        p.origin = NamePool.pickCountry(r, mix);
        final n = NamePool.forOrigin(p.origin, r);
        p.lastName = n.last;
        p.firstName = n.first;
        p.nameType = n.nameType;
        p.customName = '';
      }
    }
    _otherForceSave = true;
  }

  /// 他リーグを to の前日まで進める（毎日の試合、シーズンの終わり、1月1日の入れ替え）
  void _otherAdvance(DateTime to) {
    final w = otherWorld;
    if (w == null) return;
    var d = DateUtils.dateOnly(w.simDate).add(const Duration(days: 1));
    final last = DateUtils.dateOnly(to).subtract(const Duration(days: 1));
    var n = 0;
    while (!d.isAfter(last) && n++ < 800) {
      if (d.month == 1 && d.day == 1) {
        final notes = OtherLeagueEngine.newYear(w, d.year, Random(d.year * 4241));
        w.seasonYear = d.year;
        if (notes.isNotEmpty) _addNews(notes.take(5).toList());
        _otherForceSave = true;
      }
      OtherLeagueEngine.playDay(w, d);
      final next = d.add(const Duration(days: 1));
      for (final lg in OtherLeagueEngine.leagues.values) {
        if (lg.inSeason(d) && !lg.inSeason(next)) {
          OtherLeagueEngine.closeSeason(w, lg, lg.seasonYear(d));
          _otherForceSave = true;
        }
      }
      w.simDate = d;
      d = next;
    }
  }

  /// 他リーグを保存する（gzip で縮めて1つの記録に）
  Future<void> _saveOther() async {
    final w = otherWorld;
    if (w == null) return;
    final s = base64.encode(gzip.encode(utf8.encode(jsonEncode(w.toJson()))));
    await db.setKv('olWorld', s);
    _otherSavedAt = w.simDate;
    _otherForceSave = false;
  }

  /// 保存のときに：30日たったか、シーズンの区切りがあったときだけ他リーグも保存する
  Future<void> _maybeSaveOther() async {
    final w = otherWorld;
    if (w == null) return;
    if (_otherForceSave || _otherSavedAt == null || w.simDate.difference(_otherSavedAt!).inDays >= 30) await _saveOther();
  }

  /// 他リーグの球団から選手を外す（NPB の球団に入ったとき）。足りなくなった分はすぐ補う
  void _removeFromOther(String id) {
    final w = otherWorld;
    if (w == null) return;
    for (final t in w.teams) {
      final i = t.players.indexWhere((p) => p.id == id);
      if (i < 0) continue;
      t.players.removeAt(i);
      OtherLeagueEngine.fillRoster(t, w.seasonYear, Random(id.hashCode));
      _otherForceSave = true;
      return;
    }
  }

  static double _g(Random r) => sqrt(-2 * log(1 - r.nextDouble())) * cos(2 * pi * r.nextDouble());

  /// 外国人の補強候補（12月1日）：他リーグに実際にいる選手から。支配下120人・育成60人
  ///  MLB の主力は来ない（MLB は控えの選手だけ）。若い育成候補は 2A・1A・豪州・中東・米独立から
  List<Player> buildForeignPool(int year) {
    final w = otherWorld;
    final r = Random(year * 13 + 5);
    if (w == null) return TransferEngine.foreignMarket(year, r);
    const mainLg = {'MLB', 'AAA', 'AA', 'KBO', 'CPBL', 'MEX', 'US1', 'US2', 'US3', 'US4', 'US5', 'US6', 'AUS', 'ME'};
    const youngLg = {'AA', 'A', 'AUS', 'ME', 'US1', 'US2', 'US3', 'US4', 'US5', 'US6'};
    final mains = <(OTeam, Player, double)>[], youngs = <(OTeam, Player, double)>[];
    for (final t in w.teams) {
      for (final p in t.players) {
        if (p.nationality != '海外' || w.fromNpb.containsKey(p.id)) continue;
        if (mainLg.contains(t.leagueId) && p.age >= 24 && p.age <= 34 && (t.leagueId != 'MLB' || (p.ovr < 76 && r.nextDouble() < 0.5))) {
          mains.add((t, p, p.ovr + _g(r) * 3));
        }
        if (youngLg.contains(t.leagueId) && p.age <= 23) youngs.add((t, p, p.talent + p.ovr * 0.5 + _g(r) * 6));
      }
    }
    mains.sort((a, b) => b.$3.compareTo(a.$3));
    youngs.sort((a, b) => b.$3.compareTo(a.$3));
    final used = <String>{};
    final out = <Player>[];
    for (final x in mains) {
      if (out.length >= 120) break;
      if (used.add(x.$2.id)) out.add(_foreignCopy(x.$2, x.$1, year, r, ikusei: false));
    }
    var n = 0;
    for (final x in youngs) {
      if (n >= 60) break;
      if (used.add(x.$2.id)) {
        out.add(_foreignCopy(x.$2, x.$1, year, r, ikusei: true));
        n++;
      }
    }
    return out;
  }

  /// 他リーグの選手を、外国人の候補として写す（契約するまでは他リーグでプレーを続ける）
  Player _foreignCopy(Player src, OTeam t, int year, Random r, {required bool ikusei}) {
    final p = Player.fromJson(src.toJson());
    FieldingGen.fixMainPos(p);
    p.seasonStats = PlayerStats();
    p.farmStats = PlayerStats();
    p.thirdStats = PlayerStats();
    p.career = PlayerStats();
    p.ikusei = ikusei;
    p.proYears = 1;
    p.faService = 0;
    p.uniformNumber = 0;
    final lg = OtherLeagueEngine.leagues[t.leagueId];
    p.draftInfo = '外国人選手（$year年・${lg?.name ?? ''}の${t.name}から${ikusei ? '・育成' : ''}）';
    if (p.adapt <= 0) p.adapt = (60 + _g(r) * 13).round().clamp(20, 95);
    p.salary = ikusei ? 300 + r.nextInt(4) * 100 : round50(estimateSalary(p) * (0.55 + r.nextDouble() * 0.3));
    return p;
  }

  /// ドラフト候補の「独立」出身を、日本の独立リーグに実際にいる選手（まだ NPB に入ったことがない）に置き換える
  List<Prospect> _withIndie(List<Prospect> base, int year) {
    final w = otherWorld;
    if (w == null) return base;
    final r = Random(year * 37 + 11);
    final mainN = base.where((p) => p.category == '独立' && !p.ikuseiTier).length, ikN = base.where((p) => p.category == '独立' && p.ikuseiTier).length;
    final pool = <(OTeam, Player, double)>[];
    for (final t in w.teams.where((t) => OtherLeagueEngine.leagues[t.leagueId]?.group == '日本独立')) {
      for (final p in t.players) {
        if (p.nationality == '海外' || w.fromNpb.containsKey(p.id) || p.draftYear > 0 || p.age > 29) continue;
        pool.add((t, p, p.ovr * 0.6 + p.talent * 0.4 + _g(r) * 4));
      }
    }
    pool.sort((a, b) => b.$3.compareTo(a.$3));
    Prospect make((OTeam, Player, double) x, bool ikusei) {
      final src = x.$2;
      final p = Player.fromJson(src.toJson());
      p.seasonStats = PlayerStats();
      p.farmStats = PlayerStats();
      p.thirdStats = PlayerStats();
      p.career = PlayerStats();
      p.proYears = 1;
      p.faService = 0;
      final memo = [for (final l in src.abroad) l.replaceFirst('日本独立', OtherLeagueEngine.leagues[x.$1.leagueId]?.name ?? '独立')];
      p.abroad = [];
      return Prospect(player: p, year: year, category: '独立', school: x.$1.name, ikuseiTier: ikusei, curBias: r.nextInt(9) - 4, memo: memo.isEmpty ? ['（独立リーグでの記録はまだありません）'] : memo);
    }

    final out = base.where((p) => p.category != '独立').toList();
    for (var i = 0; i < pool.length && i < mainN + ikN; i++) {
      out.add(make(pool[i], i >= mainN));
    }
    return out;
  }

  // ───────── NPB との行き来（仕様：ポスティング・戦力外のあとを追い、声をかけて呼び戻す）─────────

  /// NPB の選手を他リーグの球団に入れる（成績は0から。いちばん力の低い選手が押し出される）
  void _joinOther(Player p, OTeam t, String note) {
    final w = otherWorld;
    if (w == null) return;
    p.seasonStats = PlayerStats();
    p.farmStats = PlayerStats();
    p.thirdStats = PlayerStats();
    if (p.isPartner) p.partnerMlb = '';
    final same = t.players.where((x) => x.isPitcher == p.isPitcher && !w.fromNpb.containsKey(x.id)).toList()..sort((a, b) => a.ovr.compareTo(b.ovr));
    if (same.isNotEmpty) t.players.remove(same.first);
    t.players.add(p);
    w.fromNpb[p.id] = note;
    _otherForceSave = true;
  }

  /// MLB の球団（名前）。他リーグがなければ架空の一覧から
  OTeam? _mlbTeam(Random r) {
    final l = otherWorld?.teamsOf('MLB') ?? const <OTeam>[];
    return l.isEmpty ? null : l[r.nextInt(l.length)];
  }

  /// 大リーグへ移った選手を、その球団（力が足りなければ傘下の 3A）に入れる
  void _toMlbOrg(Player p, OTeam mlb, String how, String fromShort) {
    final w = otherWorld;
    if (w == null) return;
    final mlbAvg = mlb.players.map((x) => x.ovr).reduce((a, b) => a + b) / mlb.players.length;
    final t = p.ovr >= mlbAvg - 3 ? mlb : (w.teams.where((x) => x.leagueId == 'AAA' && x.org == mlb.id).firstOrNull ?? mlb);
    _joinOther(p, t, '${currentDate.year}年${currentDate.month}月 $howで${mlb.name}へ（元$fromShort）');
  }

  /// 提携枠の候補：流出先の大リーグ球団の傘下（3A・2A・1A）の、25歳以下・成長率1.50以上の若手から、価値に釣り合う5人（足りなければほかの球団の傘下からも）
  List<Player> _orgProspects(OTeam mlb, double value, int year, Random r) {
    final w = otherWorld!;
    bool ok(Player p) => p.age <= 25 && p.nationality == '海外' && p.growthRate >= 1.5 && !w.fromNpb.containsKey(p.id);
    bool minor(OTeam t) => t.leagueId == 'AAA' || t.leagueId == 'AA' || t.leagueId == 'A';
    final pool = [
      for (final t in w.teams.where((t) => t.org == mlb.id && minor(t)))
        for (final p in t.players)
          if (ok(p)) p,
    ];
    if (pool.length < 5) {
      pool.addAll([
        for (final t in w.teams.where((t) => t.org != mlb.id && t.org.isNotEmpty && minor(t)))
          for (final p in t.players)
            if (ok(p)) p,
      ]);
    }
    final target = 44 + (value - 65) * 0.6 + 6;
    pool.sort((a, b) => ((a.ovr + a.talent * 0.3) - target).abs().compareTo(((b.ovr + b.talent * 0.3) - target).abs()));
    return [
      for (final p in pool.take(5))
        () {
          final c = Player.fromJson(p.toJson());
          c.seasonStats = PlayerStats();
          c.career = PlayerStats();
          c.proYears = 1;
          c.faService = 0;
          c.salary = round50(estimateSalary(c) * 0.6);
          c.draftInfo = '提携選手（${mlb.name}から・$year年）';
          return c;
        }(),
    ];
  }

  /// 戦力外・退団で NPB を離れた選手の行き先：日本人は独立リーグ、外国人は母国のリーグ（または米独立・3A）。年を取った選手は引退
  bool _leaveToOther(Player p, String fromShort, String why, Random r) {
    final w = otherWorld;
    if (w == null || p.age >= 36 || p.ovr < 40) return false;
    OTeam pickIn(Iterable<OTeam> l) {
      final ls = l.toList();
      return ls[r.nextInt(ls.length)];
    }

    OTeam t;
    if (p.nationality != '海外') {
      t = pickIn(w.teams.where((t) => OtherLeagueEngine.leagues[t.leagueId]?.group == '日本独立'));
    } else {
      final lg = switch (p.origin) {
        '韓国' => 'KBO',
        '台湾' => 'CPBL',
        'メキシコ' => 'MEX',
        'オーストラリア' => 'AUS',
        _ => p.ovr >= 62 && p.age <= 33 ? 'AAA' : 'US1',
      };
      final ls = w.teamsOf(lg);
      t = ls.isEmpty ? pickIn(w.teams.where((t) => t.leagueId.startsWith('US'))) : ls[r.nextInt(ls.length)];
    }
    _joinOther(p, t, '${currentDate.year}年${currentDate.month}月 $whyで${OtherLeagueEngine.leagues[t.leagueId]!.name}の${t.name}へ（元$fromShort）');
    return true;
  }

  /// 自球団が他リーグの選手に声をかけられるか（日本の独立リーグで NPB 未経験の選手はドラフトを通す）
  String? otherOfferBlock(Player p) {
    final w = otherWorld;
    if (w == null) return '他リーグがありません';
    final t = w.teamOfPlayer(p.id);
    if (t == null) return '見つかりません';
    final jp = OtherLeagueEngine.leagues[t.leagueId]?.group == '日本独立';
    if (jp && p.nationality != '海外' && !w.fromNpb.containsKey(p.id) && p.draftYear == 0) return 'NPB 未経験の独立リーグの選手は、ドラフトで指名します';
    return null;
  }

  /// 受けてくれる確率：MLB の主力はまず来ない。くすぶっている（3A で27歳以上・出場が少ない）選手や、元 NPB の選手は来やすい
  double otherAcceptChance(Player p) {
    final w = otherWorld;
    final t = w?.teamOfPlayer(p.id);
    if (w == null || t == null) return 0;
    final lg = OtherLeagueEngine.leagues[t.leagueId]!;
    var c = switch (lg.id) { 'MLB' => p.ovr >= 75 ? 0.03 : 0.2, 'AAA' => 0.45, 'AA' || 'A' => 0.35, 'KBO' || 'CPBL' => 0.4, _ => 0.6 };
    if (lg.id == 'AAA' && p.age >= 27) c += 0.2; // くすぶっている
    if (w.fromNpb.containsKey(p.id)) c += 0.2; // 日本球界復帰
    final gs = p.isPitcher ? p.seasonStats.pitchApps : p.seasonStats.games;
    final tg = t.w + t.l + t.d;
    if (tg >= 20 && gs < tg * 0.3) c += 0.1; // 出番がない
    return c.clamp(0.02, 0.9);
  }

  /// 他リーグの選手を獲るときの年俸の目安
  int otherSalary(Player p) {
    final t = otherWorld?.teamOfPlayer(p.id);
    final k = switch (t?.leagueId) { 'MLB' => 1.5, 'AAA' => 0.8, 'KBO' || 'CPBL' || 'MEX' => 0.9, _ => 0.6 };
    return max(450, round50(estimateSalary(p) * k));
  }

  /// 自球団が他リーグの選手に声をかける（支配下は7月31日まで。育成はいつでも）
  String? offerOtherPlayer(Player p, {bool ikusei = false}) {
    final my = myTeam, w = otherWorld;
    if (my == null || w == null) return '球団が選ばれていません';
    final block = otherOfferBlock(p);
    if (block != null) return block;
    final t = w.teamOfPlayer(p.id)!;
    if (!ikusei && RosterEngine.freeSlots(my) <= 0) return '支配下の枠（70人）が空いていません';
    if (!ikusei && !tradeOpen) return '支配下での契約は7月31日までです';
    if (ikusei && RosterEngine.ikuseiCount(my) >= ikuseiCap(my)) return '育成選手の上限（${ikuseiCap(my)}人）に達しています';
    final salary = ikusei ? min(otherSalary(p), 600) : otherSalary(p);
    final fe = _fundsCheck(my, salary);
    if (fe != null) return fe;
    final chance = otherAcceptChance(p) * (ikusei ? 0.7 : 1.0);
    final roll = Random(Object.hash(p.id, ikusei, currentDate.difference(DateTime(2000)).inDays ~/ 7)).nextDouble();
    if (roll >= chance) return '${p.registeredName}に断られました（受ける確率${(chance * 100).round()}%。週が変われば考え直すこともあります）';
    final lg = OtherLeagueEngine.leagues[t.leagueId]!;
    final back = w.fromNpb.containsKey(p.id);
    // 今季ここまでの他リーグの成績を来歴に残してから NPB へ
    if (p.seasonStats.games > 0) p.abroad.insert(0, OtherLeagueEngine.recordLine(p, lg, t, lg.seasonYear(currentDate)));
    t.players.remove(p);
    OtherLeagueEngine.fillRoster(t, w.seasonYear, Random(p.id.hashCode));
    w.fromNpb.remove(p.id);
    p.seasonStats = PlayerStats();
    p.ikusei = ikusei;
    p.salary = salary;
    p.contractYears = 1;
    p.offJoin = offseasonYear;
    if (!back) {
      p.proYears = max(1, p.proYears);
      p.faService = 0;
      p.draftInfo = '${lg.name}の${t.name}から入団（${currentDate.year}年）';
      if (p.nationality == '海外' && !ikusei) ForeignEngine.applyAdapt(p);
    }
    p.uniformNumber = RosterEngine.freeNumber(my, ikusei: ikusei);
    RosterEngine.addPlayer(my, p);
    logMove(p, back ? '日本球界復帰（${lg.name}の${t.name}から）' : '${lg.name}の${t.name}から入団', null, my);
    transactions.insert(0, '${_today()} ${teamShort(my)} ${p.registeredName}（${back ? '日本球界復帰・' : ''}${lg.name}の${t.name}から${ikusei ? '・育成' : ''}）と契約（${formatSalary(salary)}）');
    _addNews(['${p.registeredName}（${lg.name}の${t.name}）と契約しました${back ? '。日本球界に復帰します' : ''}（${formatSalary(salary)}）']);
    _otherForceSave = true;
    updateAndSave();
    return null;
  }

  /// 他リーグの選手を探す（id）
  (OTeam, Player)? otherPlayer(String id) {
    final w = otherWorld;
    if (w == null) return null;
    for (final t in w.teams) {
      for (final p in t.players) {
        if (p.id == id) return (t, p);
      }
    }
    return null;
  }
}
