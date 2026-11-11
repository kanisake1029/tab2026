part of 'app_state.dart';

/// フェーズ6：球団経営・スポンサー・グッズ・経営コンサルタント・オーナー評価と解任
extension FinanceOps on AppState {
  /// 球団の経営データ（無ければ作る）
  TeamFinance finOf(Team t) => finances.putIfAbsent(t.id, () => FinanceEngine.create(t, Random(t.id.hashCode), cpu: t.id != myTeamId));

  TeamFinance? get myFin => myTeam == null ? null : finOf(myTeam!);

  Consultant? consultantOf(TeamFinance f) =>
      consultants.where((c) => c.id == f.consultantId && c.teamId == f.teamId).firstOrNull ?? consultants.where((c) => c.id == f.consultantId).firstOrNull;

  /// 新しいコンサルタントを一覧に足す（ID が重ならないようにする）
  void _addConsultants(List<Consultant> list) {
    final used = consultants.map((c) => c.id).toSet();
    for (final c in list) {
      var id = c.id;
      var n = 2;
      while (used.contains(id)) { id = '${c.id}_${n++}'; }
      used.add(id);
      consultants.add(id == c.id ? c : Consultant(id: id, name: c.name, skill: c.skill, salary: c.salary));
    }
  }

  /// 以前のセーブで ID が重なっていたら直す（雇っている球団の方を正しく指すようにする）
  void _fixConsultantIds() {
    final keep = <Consultant, TeamFinance>{};
    for (final f in finances.values) {
      if (f.consultantId.isEmpty) continue;
      final c = consultantOf(f);
      if (c != null) keep[c] = f;
    }
    final used = <String>{};
    for (var i = 0; i < consultants.length; i++) {
      final c = consultants[i];
      if (!used.contains(c.id)) { used.add(c.id); continue; }
      var id = c.id;
      var n = 2;
      while (used.contains(id)) { id = '${c.id}_${n++}'; }
      used.add(id);
      final nc = Consultant(id: id, name: c.name, skill: c.skill, salary: c.salary, teamId: c.teamId);
      consultants[i] = nc;
      final f = keep[c];
      if (f != null) f.consultantId = id;
    }
  }

  /// お金の出入りを記録する（資金と今季の収支に反映）
  void _money(String teamId, String category, int amount, String reason) {
    final t = teamById(teamId);
    if (t == null || amount == 0) return;
    finOf(t).add(category, amount);
    ledger.add({'y': currentDate.year, 'team': teamId, 'amount': amount, 'reason': reason});
    if (ledger.length > 600) ledger = ledger.sublist(ledger.length - 600);
  }

  /// 経営データ・コンサルタント・スポンサー候補が無ければ作る（CPU 球団はコンサルタントにおまかせ）
  void _ensureFinance() {
    final r = Random(startYear * 53 + 11);
    if (consultants.isEmpty) consultants = FinanceEngine.consultants(startYear, r, count: 8 + teams.length);
    _fixConsultantIds();
    for (final t in teams) {
      final had = finances.containsKey(t.id);
      final f = finOf(t);
      if (had) continue;
      // 最初から地元のスポンサーが3社ついている
      f.sponsors.addAll(FinanceEngine.offers(startYear - 1, Random(t.id.hashCode ^ 7), counts: const {'地方企業': 3}));
      if (t.id != myTeamId) {
        final free = consultants.where((c) => c.teamId.isEmpty).toList();
        if (free.isNotEmpty) {
          final c = free[r.nextInt(free.length)];
          c.teamId = t.id;
          f.consultantId = c.id;
        }
      }
    }
    if (sponsorOffers.isEmpty) sponsorOffers = FinanceEngine.offers(currentDate.year, r);
  }

  /// 年俸総額（選手・コーチ）
  int payrollOf(Team t) => t.players.fold<int>(0, (s, p) => s + p.salary);
  int coachPayrollOf(Team t) => coaches.where((c) => c.teamId == t.id).fold<int>(0, (s, c) => s + c.salary);

  /// リーグ内の年俸総額の順位（1=最も高い）
  int payrollRank(Team t) {
    final lg = teams.where((x) => x.league == t.league).toList()..sort((a, b) => payrollOf(b).compareTo(payrollOf(a)));
    return lg.indexOf(t) + 1;
  }

  // ───────── 試合ごと ─────────

  /// 主催試合の観客と収入（公式戦・交流戦・オープン戦・ポストシーズン）
  void _gateRevenue(Match m) {
    if (m.matchType == 'ALLSTAR') return;
    final home = teamById(m.homeTeamId);
    if (home == null) return;
    final f = finOf(home);
    final st = computeStandings(teams, matches, home.league, StandingsKind.official);
    final idx = st.indexWhere((x) => x.team.id == home.id);
    final rec = idx >= 0 ? st[idx] : null;
    final g = rec == null ? 0 : rec.w + rec.l;
    final wp = g < 10 ? 0.5 : rec!.w / g;
    final gb = rec == null || idx == 0 ? 0.0 : ((st.first.w - rec.w) + (rec.l - st.first.l)) / 2;
    var att = FinanceEngine.attendance(f, winPct: wp, gamesBehind: gb, weekend: m.date.weekday >= 6, type: m.matchType, r: Random(m.date.millisecondsSinceEpoch ^ home.id.hashCode));
    // 小雨の中の試合（屋外）は観客が 15% 減る
    if (weatherOf(m)?.wetPlay ?? false) att = (att * 0.85).round();
    final eff = FinanceEngine.efficiency(consultantOf(f)?.skill ?? 50);
    FinanceEngine.gameRevenue(f, att, m.matchType, goodsMult: eff).forEach((k, v) => f.add(k, v));
    if (m.matchType != 'OPEN') {
      f.homeGames++;
      f.attendance += att;
    }
    m.boxScore ??= {};
    m.boxScore!['attendance'] = att;
  }

  // ───────── 毎月1日 ─────────

  void _monthlyFinance(DateTime d) {
    if (d.month == 12) _cpuInvest(d); // CPU 球団の施設投資
    _makerMonthly();
    final inSeason = d.month >= 4 && d.month <= 10 && !seasonFinished;
    for (final t in teams) {
      final f = finOf(t);
      final c = consultantOf(f);
      final eff = FinanceEngine.efficiency(c?.skill ?? 50);
      // 年俸は2〜11月の10回払い（NPB と同じ）。運営費は試合のある3〜10月が重く、オフは軽い
      if (d.month >= 2 && d.month <= 11) {
        f.add('選手年俸', -(payrollOf(t) / 10).round());
        f.add('コーチ年俸', -(coachPayrollOf(t) / 10).round());
      }
      final opYear = FinanceEngine.operatingPerMonth * 12;
      f.add('運営費', -(d.month >= 3 && d.month <= 10 ? opYear * 0.85 / 8 : opYear * 0.15 / 4).round());
      final sp = f.sponsors.where((s) => !s.pending).fold<int>(0, (s, x) => s + x.amount); // 来季からの契約はまだ払われない
      if (sp > 0) f.add('スポンサー', (sp / 12 * eff).round());
      if (c != null) f.add('コンサルタント', -(c.salary / 12).round());
      final up = FacilityEngine.upkeep(f.facilities);
      if (up > 0) f.add('施設維持費', -(up / 12).round());

      // 人気（シーズン中は勝率で動く）
      final st = computeStandings(teams, matches, t.league, StandingsKind.official);
      final idx = st.indexWhere((x) => x.team.id == t.id);
      if (inSeason && idx >= 0) {
        final rec = st[idx];
        final g = rec.w + rec.l;
        if (g >= 10) f.popularity = (f.popularity + ((rec.w / g - 0.5) * 6).round() + ((50 - f.popularity) * 0.05).round()).clamp(5, 100);
        // オーナー満足度（毎月）：期待される順位との差と、収支
        if (t.id == myTeamId && d.month <= 9 && g >= 10) {
          final exp = FinanceEngine.expectedRank(payrollRank(t), st.length);
          final dv = ((exp - (idx + 1)) * 1.2 + (f.seasonProfit >= 0 ? 0.5 : -0.5)).round().clamp(-6, 6);
          f.ownerSat = (f.ownerSat + dv).clamp(0, 100);
        }
      }
      // おまかせ（コンサルタント）：チケット価格を見直し、余裕があればグッズを企画
      if (f.autoManage && c != null) {
        final r = Random(d.millisecondsSinceEpoch ^ t.id.hashCode);
        f.ticketPrice = FinanceEngine.bestPrice(f, c.skill, r).clamp(2500, FacilityEngine.maxTicket(f.fac('stadium')));
        if (f.funds > 50000 && f.goods.where((g) => !g.done).isEmpty && d.month >= 3 && d.month <= 9) {
          final star = (List.of(t.players)..sort((a, b) => FinanceEngine.playerAppeal(b).compareTo(FinanceEngine.playerAppeal(a)))).first;
          _launchGoods(t, '選手グッズ', star, r, skill: c.skill);
        }
      }
    }
  }

  /// グッズ企画の販売が終わったものを締める
  void _settleGoods(DateTime d) {
    final key = _dateKey(d);
    for (final t in teams) {
      final f = finOf(t);
      for (final g in f.goods.where((g) => !g.done && g.endDate.compareTo(key) <= 0)) {
        g.done = true;
        g.revenue = FinanceEngine.goodsRevenue(g);
        f.add('グッズ企画', g.revenue);
        if (g.appeal >= 1.3) f.popularity = (f.popularity + 2).clamp(0, 100);
        if (t.id == myTeamId) {
          final hit = g.revenue >= g.cost * 1.5 ? '大ヒット！' : (g.revenue >= g.cost ? '好調' : '売れ残り');
          _addNews(['グッズ「${g.label}」の販売が終了：売上 ${formatSalary(g.revenue)}（費用 ${formatSalary(g.cost)}）$hit']);
        }
      }
      if (f.goods.length > 30) f.goods.removeRange(0, f.goods.length - 30);
    }
  }

  String _dateKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  void _launchGoods(Team t, String kind, Player? p, Random r, {int skill = 50}) {
    final f = finOf(t);
    final base = kind == '選手グッズ' && p != null ? FinanceEngine.playerAppeal(p) : (kind == '記念グッズ' ? 0.8 + f.popularity / 120 : 1.0 + f.popularity / 150);
    var (cost, appeal) = FinanceEngine.planGoods(kind, base, f, r);
    appeal *= 0.9 + skill / 500; // 手腕のあるコンサルタントは売り方がうまい
    final end = currentDate.add(const Duration(days: 30));
    f.goods.add(GoodsProject(
      id: 'G${currentDate.millisecondsSinceEpoch}_${r.nextInt(9999)}',
      kind: kind,
      label: kind == '選手グッズ' && p != null ? '${p.registeredName} グッズ' : (kind == '記念グッズ' ? '${startYear}年 記念グッズ' : '限定ユニフォーム'),
      cost: cost,
      endDate: _dateKey(end),
      appeal: appeal,
    ));
    f.add('グッズ企画', -cost);
  }

  // ───────── 自球団の操作 ─────────

  String? setTicketPrice(int price) {
    final f = myFin;
    if (f == null) return '球団が選ばれていません';
    f.ticketPrice = price.clamp(2500, FacilityEngine.maxTicket(f.fac('stadium')));
    updateAndSave();
    return null;
  }

  String? launchGoods(String kind, Player? p) {
    final t = myTeam;
    if (t == null) return '球団が選ばれていません';
    final f = finOf(t);
    if (f.goods.where((g) => !g.done).length >= 3) return '同時に進められる企画は3つまでです';
    final cost = switch (kind) { '選手グッズ' => 2000, '記念グッズ' => 3000, _ => 5000 };
    if (f.funds < cost) return '資金が足りません';
    _launchGoods(t, kind, p, Random(DateTime.now().microsecondsSinceEpoch), skill: consultantOf(f)?.skill ?? 50);
    updateAndSave();
    return null;
  }

  /// 12月は来季の契約の期間（新しい契約は来季から。今年で満了する契約は更新できる）
  bool get sponsorRenewalPeriod => currentDate.month == 12;

  /// 枠に数える契約：12月は来季も続く契約（来季からの契約・2年以上残っている契約）、それ以外は今の契約
  int sponsorSlotsUsed(TeamFinance f, {bool? december}) => (december ?? sponsorRenewalPeriod) ? f.sponsors.where((s) => s.pending || s.years > 1).length : f.sponsors.where((s) => !s.pending).length;

  /// 今年で満了し、更新できる契約か（12月）
  bool canRenewSponsor(Sponsor s) => sponsorRenewalPeriod && !s.pending && s.years <= 1;

  String? signSponsor(Sponsor s) {
    final t = myTeam;
    if (t == null) return '球団が選ばれていません';
    final f = finOf(t);
    if (sponsorSlotsUsed(f) >= FinanceEngine.maxSponsors) return 'スポンサーは${FinanceEngine.maxSponsors}社までです${sponsorRenewalPeriod ? '（来季の分）' : ''}';
    if (f.popularity < s.minPopularity) return '人気が足りません（人気${s.minPopularity}以上が条件）';
    if (f.sponsors.any((x) => x.name == s.name)) return '${s.name}とはすでに契約しています';
    sponsorOffers.remove(s);
    s.pending = sponsorRenewalPeriod; // 12月の契約は来季（1月1日）から
    f.sponsors.add(s);
    _addNews(['${s.name}とスポンサー契約を結びました（年${formatSalary(s.amount)}・${s.years}年${s.pending ? '・来季から' : ''}）']);
    updateAndSave();
    return null;
  }

  /// 今年で満了するスポンサーとの契約を更新する（12月）。額は人気で変わる。years は来季からの年数
  String? renewSponsor(Sponsor s, int years) {
    final t = myTeam;
    if (t == null) return '球団が選ばれていません';
    final f = finOf(t);
    if (!canRenewSponsor(s)) return '更新できるのは、今年で満了する契約（12月）だけです';
    if (sponsorSlotsUsed(f) >= FinanceEngine.maxSponsors) return 'スポンサーは${FinanceEngine.maxSponsors}社までです（来季の分）';
    if (f.popularity < s.minPopularity) return '人気が条件（${s.minPopularity}）に届かず、更新を断られました';
    final i = f.sponsors.indexOf(s);
    final n = s.renewed(amount: FinanceEngine.renewAmount(s, f.popularity), years: 1 + years);
    f.sponsors[i] = n;
    _addNews(['${s.name}とのスポンサー契約を更新しました（年${formatSalary(n.amount)}・$years年）']);
    updateAndSave();
    return null;
  }

  String? hireConsultant(Consultant c) {
    final t = myTeam;
    if (t == null) return '球団が選ばれていません';
    final f = finOf(t);
    final cur = consultantOf(f);
    if (cur != null) cur.teamId = '';
    c.teamId = t.id;
    f.consultantId = c.id;
    updateAndSave();
    return null;
  }

  void releaseConsultant() {
    final f = myFin;
    if (f == null) return;
    consultantOf(f)?.teamId = '';
    f.consultantId = '';
    f.autoManage = false;
    updateAndSave();
  }

  void setAutoManage(bool v) {
    final f = myFin;
    if (f == null) return;
    f.autoManage = v && consultantOf(f) != null;
    updateAndSave();
  }

  /// 補強に使えるお金があるか（資金がマイナスなら補強できない）
  String? _fundsCheck(Team t, int amount) {
    final f = finOf(t);
    if (f.funds - amount < -50000) return '資金が足りません（資金 ${formatSalary(f.funds)}。マイナス5億円を下回る補強はできません）';
    return null;
  }

  // ───────── 年に一度 ─────────

  /// CPU 球団のスポンサー契約（空き枠を候補から埋める）
  /// CPU 球団のスポンサー：12月は満了する契約を更新（人気が条件を満たせば6割）してから、空いた来季の枠を候補で埋める
  ///  december：12月の来季の契約として扱うか（1月1日の処理は日付が変わる前に呼ばれるので、呼ぶ側が決める）
  void _cpuSponsors({bool december = false}) {
    final r = Random(currentDate.millisecondsSinceEpoch ~/ 86400000);
    for (final t in teams.where((t) => t.id != myTeamId)) {
      final f = finOf(t);
      final eff = consultantOf(f)?.skill ?? 50;
      if (december) {
        for (var i = 0; i < f.sponsors.length; i++) {
          final s = f.sponsors[i];
          if (sponsorSlotsUsed(f, december: true) >= FinanceEngine.maxSponsors) break;
          if (!s.pending && s.years <= 1 && f.popularity >= s.minPopularity && r.nextDouble() < 0.6) {
            f.sponsors[i] = s.renewed(amount: FinanceEngine.renewAmount(s, f.popularity), years: 2 + r.nextInt(3));
          }
        }
      }
      final cands = sponsorOffers.where((s) => f.popularity >= s.minPopularity && !f.sponsors.any((x) => x.name == s.name)).toList()..sort((a, b) => (b.amount + b.bonus * 0.4).compareTo(a.amount + a.bonus * 0.4));
      for (final s in cands) {
        if (sponsorSlotsUsed(f, december: december) >= FinanceEngine.maxSponsors - (eff < 45 ? 2 : 0)) break;
        sponsorOffers.remove(s);
        s.pending = december;
        f.sponsors.add(s);
      }
    }
  }

  /// 1月1日：スポンサー契約の年数を減らし（シーズン後のオフだけ）、満了した契約を外す。12月に結んだ来季からの契約はここから始まる
  void _newYearFinance({bool decrement = true}) {
    for (final f in finances.values) {
      for (final s in f.sponsors) {
        if (s.pending) {
          s.pending = false;
        } else if (decrement) {
          s.years--;
        }
      }
      final ended = f.sponsors.where((s) => s.years <= 0).toList();
      f.sponsors.removeWhere((s) => s.years <= 0);
      if (f.teamId == myTeamId && ended.isNotEmpty) _addNews(['スポンサー契約が満了：${ended.map((s) => s.name).join('、')}（フロント → 経営で新しいスポンサーを探せます）']);
    }
    _cpuSponsors();
  }

  /// シーズン終了時：スポンサーのボーナス、人気、オーナーの評価、解任の判定。自球団の結果を返す
  FinanceResult? _financeSeasonEnd(Map<String, int> ranks, int year) {
    FinanceResult? mine;
    final pennants = <String>{for (final lg in ['CL', 'PL']) ...ranks.entries.where((e) => e.value == 1 && teamById(e.key)?.league == lg).map((e) => e.key)};
    final csTeams = {for (final e in ranks.entries) if (e.value <= 3) e.key};
    final champ = champion?.id;
    for (final t in teams) {
      final f = finOf(t);
      final rank = ranks[t.id] ?? 6;
      for (final s in f.sponsors) {
        if (FinanceEngine.conditionMet(s, rank: rank, avgAttendance: f.avgAttendance)) f.add('スポンサー', s.bonus);
      }
      // 人気：優勝・日本一で上がり、最下位で下がる。少しずつ50に戻る
      var pop = f.popularity + (t.id == champ ? 8 : 0) + (pennants.contains(t.id) ? 5 : 0) - (rank == 6 ? 3 : 0);
      pop = (pop + (50 - pop) * 0.1).round();
      f.popularity = pop.clamp(5, 100);
      if (t.id == myTeamId) {
        final lgSize = teams.where((x) => x.league == t.league).length;
        final prev = f.satHistory.isEmpty ? null : prevRankOf(t);
        final (v, notes) = FinanceEngine.ownerEval(
          rank: rank,
          expected: FinanceEngine.expectedRank(payrollRank(t), lgSize),
          pennant: pennants.contains(t.id),
          champion: t.id == champ,
          cs: csTeams.contains(t.id),
          prevRank: prev,
          profit: f.seasonProfit,
          avgAtt: f.avgAttendance,
          prevAtt: f.lastAttendance,
          sponsors: f.sponsors.length,
        );
        final before = f.ownerSat;
        f.ownerSat = ((f.ownerSat + v) / 2).round().clamp(0, 100);
        f.ownerNotes = ['シーズンの評価 $v（月ごとの満足度 $before と平均して ${f.ownerSat}）', ...notes];
        f.satHistory.add(f.ownerSat);
        final low2 = f.satHistory.length >= 2 && f.satHistory[f.satHistory.length - 1] < 35 && f.satHistory[f.satHistory.length - 2] < 35;
        final fire = ownerFiring && !autoMode && !ronin && (f.ownerSat < 20 || low2);
        mine = FinanceResult(profit: f.seasonProfit, sat: f.ownerSat, notes: f.ownerNotes, fired: fire);
        lastRankOf[t.id] = rank;
        if (fire) {
          fired = true;
          firedOffers = _offersAfterFiring(ranks);
          _addNews(['オーナーから解任を告げられました（満足度 ${f.ownerSat}）']);
        }
      }
      f.lastSeason = Map.of(f.season);
      f.season = {};
      f.lastAttendance = f.avgAttendance;
      f.homeGames = 0;
      f.attendance = 0;
    }
    return mine;
  }

  int? prevRankOf(Team t) => lastRankOf[t.id];

  /// 解任されたときのオファー：成績の振るわなかった球団から最大3球団
  List<String> _offersAfterFiring(Map<String, int> ranks) {
    final cands = teams.where((t) => t.id != myTeamId).toList()..sort((a, b) => (ranks[b.id] ?? 3).compareTo(ranks[a.id] ?? 3));
    return cands.take(3).map((t) => t.id).toList();
  }

  /// 1年浪人する：次のシーズンは試合に関わらず日付だけ進み（元の球団は CPU の監督）、オフに監督を交代した球団から打診が来る
  void goRonin() {
    fired = false;
    firedOffers = [];
    ronin = true;
    roninReturn = false;
    autoMode = true;
    final f = myFin;
    if (f != null) f.autoManage = true;
    _ensureManagers(); // 元の球団に CPU の監督を就ける
    _addNews(['1年間の浪人生活に入りました。オフに監督を交代した球団から打診が来るのを待ちます']);
    updateAndSave();
  }

  /// 浪人中：次のシーズンの終わりまで、すべて自動で進めて、シーズンを締める（そこで打診が届く）
  Future<void> roninAdvance() async {
    if (!ronin) return;
    var guard = 0;
    // いまのシーズンが締まっていれば、年が明けて次のシーズンが終わるまで進める
    while (!(seasonOver && !seasonFinished) && guard++ < 500) {
      playNextDay();
      if (guard % 10 == 0) await Future<void>.delayed(Duration.zero);
    }
    if (seasonOver && !seasonFinished) await finishSeason();
    updateAndSave();
  }

  /// 浪人明けの打診：今季監督を交代した球団（成績の悪い順）から最大3球団。無ければ下位の球団
  void _roninOffers(Map<String, int> ranks, List<String> changed) {
    final byRank = teams.where((t) => t.league == 'CL' || t.league == 'PL').toList()..sort((a, b) => (ranks[b.id] ?? 3).compareTo(ranks[a.id] ?? 3));
    var offers = [for (final t in byRank) if (changed.contains(t.id)) t.id].take(3).toList();
    if (offers.isEmpty) offers = byRank.take(2).map((t) => t.id).toList();
    firedOffers = offers;
    fired = true; // 行き先を選ぶまで進めない（打診の画面を出す）
    roninReturn = true;
    _addNews(['浪人明け：${offers.length}球団から監督の打診が届きました']);
  }

  /// オファーを受けて別の球団の監督になる
  void acceptOffer(String teamId) {
    final old = myTeam;
    final wasRonin = ronin;
    ronin = false;
    roninReturn = false;
    if (wasRonin) autoMode = false;
    myTeamId = teamId;
    fired = false;
    firedOffers = [];
    final f = myFin!;
    f.ownerSat = 60;
    f.satHistory = [];
    f.autoManage = consultantOf(f) != null;
    _ensureManagers(); // 新しい球団の監督枠を空け、元の球団には CPU の監督を就ける
    if (old != null) {
      finOf(old).autoManage = true;
      _addNews(['${old.name}を離れ、${myTeam!.name}の監督に就任しました']);
    }
    updateAndSave();
  }

  /// 解任後に、はじめからやり直す（固有12球団を初期データに戻し、経営もやり直す）
  Future<void> restartAfterFired() async {
    fired = false;
    firedOffers = [];
    ronin = false;
    roninReturn = false;
    autoMode = false;
    finances = {};
    sponsorOffers = [];
    transactions = [];
    ledger = [];
    lastRankOf = {};
    await resetToInitialTeams();
    _ensureFinance();
    _ensureManagers();
    updateAndSave();
  }
}

/// シーズン終了時の自球団の経営の結果
class FinanceResult {
  final int profit;
  final int sat;
  final List<String> notes;
  final bool fired;
  FinanceResult({required this.profit, required this.sat, required this.notes, required this.fired});
}
