part of 'app_state.dart';

/// フェーズ4・5：ドラフト・スカウト・育成・引退・戦力外・FA・トレード・外国人・契約更改・CPU 監督
extension OffseasonOps on AppState {
  Team? get myTeam => teams.where((t) => t.id == myTeamId).firstOrNull;

  /// 自球団を選んだとき：自球団の監督枠を空け（監督はユーザー）、ドラフト候補の調査を済ませる
  void onTeamChosen() {
    _ensureManagers();
    // 年度の初めの能力がまだ無い選手（はじめから・以前のセーブ）は、いまの能力を控える
    for (final t in leagueTeams) {
      for (final p in t.players) {
        if (p.yearStart.isEmpty) p.yearStart = {'ovr': p.ovr, for (final s in GrowthEngine.statsOf(p)) s.key: s.get(p)};
      }
    }
    // 自球団の経営は自分で（経営コンサルタントはフロント → 経営で雇える）
    final f = finances[myTeamId];
    if (f != null && f.satHistory.isEmpty && f.season.isEmpty) {
      consultants.where((c) => c.id == f.consultantId).firstOrNull?.teamId = '';
      f.consultantId = '';
      f.autoManage = false;
      f.ticketPrice = FinanceEngine.basePrice;
    }
    preScoutIfNeeded();
  }

  // ───────── 日付 ─────────

  /// 公式戦（交流戦を含む）の最初と最後の日
  (DateTime?, DateTime?) _regularRange() {
    DateTime? a, b;
    for (final m in matches) {
      if (m.matchType != 'LEAGUE' && m.matchType != 'INTERLEAGUE') continue;
      if (a == null || m.date.isBefore(a)) a = m.date;
      if (b == null || m.date.isAfter(b)) b = m.date;
    }
    return (a, b);
  }

  /// トレード・支配下登録ができるか（7月31日が期限。シーズンが終わると再開）
  bool get tradeOpen => seasonFinished || !currentDate.isAfter(DateTime(startYear, 7, 31));

  /// いまのオフシーズンは、シーズンを1つ終えた後か（ゲーム開始直後のオフは FA・契約更改がない）
  bool get _afterSeason => offAfterSeason;

  /// 今日はドラフト会議で、まだ指名していないか
  bool get draftPending => currentDate.month == 10 && currentDate.day == 31 && draftDoneYear < currentDate.year;

  // ───────── ポスティング・海外FA・提携枠（仕様書 3章）─────────

  /// 11月1日：ポスティングの希望。自球団の選手は認めるかを決める（12月1日まで）。CPU 球団は方針で決める
  void _postingRequests() {
    final r = Random(currentDate.year * 613);
    for (final t in leagueTeams) {
      for (final p in t.players) {
        if (postingAsk.containsKey(p.id) || r.nextDouble() >= TransferEngine.postingChance(p)) continue;
        if (t.id == myTeamId && !autoMode) {
          postingAsk[p.id] = 'ask';
          _addNews(['ポスティング：${p.registeredName}が大リーグ挑戦のため、ポスティングでの移籍を希望しています（フロント → 補強 → FA で、12月1日までに決めてください）']);
        } else {
          final ok = r.nextDouble() < TransferEngine.postingAllowChance(t.id == myTeamId ? 'middle' : policyOf(t), p);
          postingAsk[p.id] = ok ? 'ok' : 'no';
          if (!ok) p.trust = (p.trust - 10).clamp(1, 100);
          _addNews(['ポスティング：${teamShort(t)}の${p.registeredName}の希望を、球団が${ok ? '認めました' : '認めませんでした'}']);
        }
      }
    }
  }

  /// 自球団の選手のポスティングを認める／認めない（認めないと監督への信頼が下がる）
  String? decidePosting(Player p, bool ok) {
    if (postingAsk[p.id] != 'ask') return '決める必要はありません';
    postingAsk[p.id] = ok ? 'ok' : 'no';
    if (!ok) p.trust = (p.trust - 10).clamp(1, 100);
    updateAndSave();
    return null;
  }

  /// 12月1日：認められた選手が大リーグの球団と交渉する。契約すれば元の球団に譲渡金と提携枠1つ
  void _postingResolve() {
    final r = Random(currentDate.year * 617);
    for (final e in postingAsk.entries.toList()) {
      final t = teams.where((t) => t.players.any((p) => p.id == e.key)).firstOrNull;
      final p = t?.players.firstWhere((p) => p.id == e.key);
      if (t == null || p == null) continue;
      if (e.value != 'ok') {
        if (e.value == 'ask') _addNews(['ポスティング：${p.registeredName}の希望は、期限までに認めなかったため残留になりました']);
        continue;
      }
      if (r.nextDouble() < TransferEngine.mlbSignChance(p)) {
        final fee = TransferEngine.postingFee(p);
        _money(t.id, 'ポスティング', fee, '譲渡金 ${p.registeredName}');
        _departMlb(p, t, how: 'ポスティング', extra: '譲渡金${formatSalary(fee)}', r: r);
      } else {
        _addNews(['ポスティング：${p.registeredName}（${teamShort(t)}）は大リーグの球団と契約に至らず、残留します']);
      }
    }
    postingAsk.clear();
  }

  /// FA 宣言の日：海外FA 権（9年）を持つ選手の一部が宣言し、大リーグの球団と契約すれば移る（元の球団は提携枠1つ）
  void _overseasFa() {
    final r = Random(currentDate.year * 619);
    for (final t in leagueTeams) {
      for (final p in List.of(t.players)) {
        if (r.nextDouble() >= TransferEngine.overseasFaChance(p)) continue;
        if (r.nextDouble() < TransferEngine.mlbSignChance(p)) {
          _departMlb(p, t, how: '海外FA', extra: '', r: r);
        } else {
          _addNews(['海外FA：${p.registeredName}（${teamShort(t)}）は大リーグとの契約に至らず、残留しました']);
        }
      }
    }
  }

  /// 大リーグへ移る：球団から外し、元の球団に提携枠を与える
  void _departMlb(Player p, Team t, {required String how, required String extra, required Random r}) {
    final org = _mlbTeam(r);
    final mlb = org?.name ?? TransferEngine.mlbTeams[r.nextInt(TransferEngine.mlbTeams.length)];
    RosterEngine.removePlayer(t, p);
    if (org != null) _toMlbOrg(p, org, how, teamShort(t)); // 大リーグでの成績と去就は「他リーグ」タブで追える
    transactions.insert(0, '${_today()} ${p.registeredName} $how ${teamShort(t)} → $mlb（大リーグ）${extra.isEmpty ? '' : '・$extra'}');
    _addNews(['$how：${p.registeredName}が${teamShort(t)}から大リーグの$mlbへ移籍${extra.isEmpty ? '' : '（$extra）'}。${teamShort(t)}は提携枠を1つ得ました']);
    final value = RosterEngine.value(p).toDouble();
    final cands = org != null ? _orgProspects(org, value, offseasonYear + 1, r) : ForeignEngine.partnerProspects(offseasonYear + 1, r, value, mlb);
    final slot = <String, dynamic>{'team': t.id, 'mlb': mlb, 'from': p.registeredName, 'cands': [for (final c in cands) c.toJson()], 'declined': <String>[]};
    partnerSlots.add(slot);
    if (t.id != myTeamId || autoMode) _cpuFillPartner(slot, r);
  }

  /// 提携枠の候補
  List<Player> partnerCands(Map<String, dynamic> slot) => [for (final j in slot['cands'] as List) Player.fromJson(Map<String, dynamic>.from(j as Map))];

  /// CPU 球団が提携枠を埋める：評価の高い候補から、期間3〜5年で申し出る
  void _cpuFillPartner(Map<String, dynamic> slot, Random r) {
    final t = teamById('${slot['team']}');
    if (t == null) return;
    final cands = partnerCands(slot)..sort((a, b) => cpuValue(t, b).compareTo(cpuValue(t, a)));
    for (final c in cands) {
      final years = 3 + r.nextInt(3);
      if (r.nextDouble() < TransferEngine.partnerAcceptChance(t, c, years)) {
        _signPartner(slot, c, years);
        return;
      }
    }
  }

  /// 自球団が提携選手に申し出る（期間3〜5年）。受けるかは出場機会と期間で決まる
  String? offerPartner(Map<String, dynamic> slot, Player c, int years) {
    final t = myTeam;
    if (t == null || slot['team'] != t.id) return '自球団の提携枠ではありません';
    if (RosterEngine.freeSlots(t) <= 0) return '支配下の枠が空いていません';
    final declined = List<String>.from(slot['declined'] as List? ?? []);
    if (declined.contains(c.id)) return 'この選手には断られています';
    final chance = TransferEngine.partnerAcceptChance(t, c, years);
    final roll = Random(Object.hash(c.id, years, currentDate.difference(DateTime(2000)).inDays ~/ 7)).nextDouble();
    if (roll >= chance) {
      slot['declined'] = [...declined, c.id];
      updateAndSave();
      return '${c.registeredName}に断られました（受ける確率${(chance * 100).round()}%）';
    }
    _signPartner(slot, c, years);
    updateAndSave();
    return null;
  }

  void _signPartner(Map<String, dynamic> slot, Player c, int years) {
    final t = teamById('${slot['team']}');
    if (t == null || RosterEngine.freeSlots(t) <= 0) return;
    c.partnerMlb = '${slot['mlb']}';
    _removeFromOther(c.id);
    c.partnerUntil = offseasonYear + years; // 次のシーズンから years 年
    c.offJoin = offseasonYear;
    c.uniformNumber = RosterEngine.freeNumber(t, ikusei: false);
    RosterEngine.addPlayer(t, c);
    logMove(c, '提携選手（${c.partnerMlb}から$years年）', null, t);
    partnerSlots.remove(slot);
    transactions.insert(0, '${_today()} ${teamShort(t)} 提携選手 ${c.registeredName}（${c.mainPosition}・${c.age}歳・${c.partnerMlb}から$years年）');
    _addNews(['提携枠：${teamShort(t)}が${c.partnerMlb}の${c.registeredName}（${c.mainPosition}・${c.age}歳）を$years年の期限付きで迎えました']);
  }

  /// 3月1日：埋まらなかった提携枠は消える
  void _expirePartnerSlots() {
    for (final s in List.of(partnerSlots)) {
      final t = teamById('${s['team']}');
      if (t?.id == myTeamId) _addNews(['提携枠（${s['mlb']}）は、選手が決まらないまま期限を迎えて消えました']);
    }
    partnerSlots.clear();
  }

  /// 11月1日：提携の期間が終わった選手。日本に残りたい選手は、借りていた球団に優先交渉権（自球団は12月1日までに決める）
  void _partnerTermEnd() {
    final r = Random(currentDate.year * 631);
    for (final t in leagueTeams) {
      for (final p in List.of(t.players.where((p) => p.isPartner && p.partnerUntil <= offseasonYear))) {
        final stay = p.ovr >= 55 && r.nextDouble() < 0.6;
        if (!stay) {
          final where = [p.partnerMlb, 'KBO', 'CPBL', 'メキシカンリーグ', '大リーグの他球団'][r.nextInt(5)];
          RosterEngine.removePlayer(t, p);
          final org = otherWorld?.teams.where((x) => x.name == p.partnerMlb).firstOrNull;
          if (org != null) _toMlbOrg(p, org, '提携期間満了', teamShort(t));
          transactions.insert(0, '${_today()} ${p.registeredName} 提携期間満了 ${teamShort(t)} → $where');
          _addNews(['提携期間満了：${p.registeredName}（${teamShort(t)}）は$whereへ移ります']);
        } else if (t.id == myTeamId && !autoMode) {
          if (!partnerStay.contains(p.id)) partnerStay.add(p.id);
          _addNews(['提携期間満了：${p.registeredName}が日本に残ることを望んでいます。優先して交渉できます（フロント → 補強 → FA で、12月1日までに）']);
        } else {
          _keepOrReleasePartner(t, p, cpuValue(t, p) >= 56);
        }
      }
    }
  }

  /// 期間が終わった提携選手を残す（外国人枠の選手として契約）か、手放す（自由契約。他球団も獲れる）
  void _keepOrReleasePartner(Team t, Player p, bool keep) {
    if (keep) {
      p.partnerMlb = '';
      p.salary = round50(estimateSalary(p) * 0.9);
      p.contractYears = 1;
      transactions.insert(0, '${_today()} ${teamShort(t)} ${p.registeredName} 提携期間満了・残留（${formatSalary(p.salary)}）');
      _addNews(['${p.registeredName}は提携期間を終え、${teamShort(t)}に残留（${formatSalary(p.salary)}）']);
    } else {
      RosterEngine.removePlayer(t, p);
      p.partnerMlb = '';
      freeAgents.add(FreeAgent(p, t.id, '提携期間満了'));
      transactions.insert(0, '${_today()} ${p.registeredName} 提携期間満了で自由契約（元${teamShort(t)}）');
      _addNews(['${p.registeredName}は提携期間を終え、${teamShort(t)}を離れて自由契約になりました']);
    }
  }

  /// 自球団が期間満了の提携選手と残留交渉する／しない
  String? decidePartnerStay(Player p, bool keep) {
    final t = myTeam;
    if (t == null || !partnerStay.contains(p.id)) return '決める必要はありません';
    partnerStay.remove(p.id);
    _keepOrReleasePartner(t, p, keep);
    updateAndSave();
    return null;
  }

  /// 12月1日：決めていない提携選手は残す
  void _partnerStayResolve() {
    final t = myTeam;
    for (final id in List.of(partnerStay)) {
      final p = t?.players.where((p) => p.id == id).firstOrNull;
      if (t != null && p != null) _keepOrReleasePartner(t, p, true);
    }
    partnerStay.clear();
  }

  // ───────── 育成テンダー（仕様書 6.1。数値は仮）─────────

  /// 11月20日：育成で通算3年、支配下に上がれなかった選手が対象。他球団が支配下契約を提示する（12月1日に選手が選ぶ）
  void _tenderStart() {
    final r = Random(currentDate.year * 641);
    tenders = [];
    for (final t in leagueTeams) {
      for (final p in t.players.where((p) => p.ikusei && p.ikuseiYears >= 3)) {
        final c = <String, dynamic>{'pid': p.id, 'from': t.id, 'offers': <String, int>{}, 'match': false};
        // 元の球団（CPU）は、見込みがあれば同じ条件で支配下に上げる
        if (t.id != myTeamId && RosterEngine.freeSlots(t) > 0 && cpuValue(t, p) >= 52 + r.nextInt(6)) c['match'] = true;
        tenders.add(c);
      }
    }
    _cpuTenderOffers(r);
    final mine = tenders.where((c) => c['from'] == myTeamId).length;
    if (tenders.isNotEmpty) {
      _addNews(['育成テンダー：育成で3年を過ぎた${tenders.length}人が対象になりました${mine > 0 ? '（自球団$mine人）' : ''}。他球団が支配下契約を提示でき、12月1日に選手が選びます（フロント → 補強 → FA）']);
    }
  }

  void _cpuTenderOffers(Random r) {
    for (final c in tenders) {
      final p = _findPlayer('${c['pid']}');
      if (p == null) continue;
      final offers = Map<String, int>.from(c['offers'] as Map);
      for (final t in leagueTeams.where((t) => t.id != myTeamId && t.id != c['from'])) {
        if (RosterEngine.freeSlots(t) <= 0 || RosterEngine.cpuRoom(t) <= 0) continue;
        final interest = (cpuValue(t, p) - 50) / 10 + RosterEngine.need(t, p.mainPosition) * 0.8 + r.nextDouble() * 0.5;
        if (interest < 1.0) continue;
        offers[t.id] = tenderSalary(p);
      }
      c['offers'] = offers;
    }
  }

  /// テンダーで提示する年俸（支配下の最低ライン以上）
  int tenderSalary(Player p) => max(440, ((estimateSalary(p) * 0.8) / 10).round() * 10);

  /// 自球団が他球団の対象選手に支配下契約を提示する／自球団の対象選手を同じ条件で支配下に上げる
  String? tenderOffer(Map<String, dynamic> c) {
    final my = myTeam;
    if (my == null) return '球団が選ばれていません';
    if (RosterEngine.freeSlots(my) <= 0) return '支配下の枠が空いていません';
    if (c['from'] == my.id) {
      c['match'] = true;
    } else {
      final p = _findPlayer('${c['pid']}');
      if (p == null) return '選手が見つかりません';
      final offers = Map<String, int>.from(c['offers'] as Map);
      offers[my.id] = tenderSalary(p);
      c['offers'] = offers;
    }
    updateAndSave();
    return null;
  }

  /// 12月1日：選手が条件を総合して選ぶ（年俸・出場機会・強さ・人気。元の球団に優先権はない）。他球団へ移れば元の球団に少額の補償
  void _tenderResolve() {
    final r = Random(currentDate.year * 643);
    for (final c in tenders) {
      final from = teamById('${c['from']}');
      final p = from?.players.where((x) => x.id == c['pid']).firstOrNull;
      if (from == null || p == null || !p.ikusei) continue;
      final options = <String, int>{...Map<String, int>.from(c['offers'] as Map), if (c['match'] == true) from.id: tenderSalary(p)};
      if (options.isEmpty) {
        // 誰も提示しなかった：自由契約（仮。仕様書 8章で未決）
        RosterEngine.removePlayer(from, p);
        freeAgents.add(FreeAgent(p, from.id, '育成満了'));
        transactions.insert(0, '${_today()} ${teamShort(from)} ${p.registeredName} 育成テンダー（提示なし）で自由契約');
        if (from.id == myTeamId) _addNews(['育成テンダー：${p.registeredName}にはどこからも提示がなく、自由契約になりました']);
        continue;
      }
      double score(String tid, int salary) {
        final t = teamById(tid)!;
        return salary / 1000 + RosterEngine.need(t, p.mainPosition) * 1.5 + (finOf(t).popularity / 100) * 0.5 + r.nextDouble() * 0.6;
      }

      final best = options.entries.reduce((a, b) => score(a.key, a.value) >= score(b.key, b.value) ? a : b);
      final to = teamById(best.key)!;
      if (RosterEngine.freeSlots(to) <= 0) continue; // 元の球団で支配下にするときも、支配下の枠（70人）に空きが要る
      RosterEngine.removePlayer(from, p);
      p.ikusei = false;
      p.salary = best.value;
      p.contractYears = 1;
      if (to.id != from.id) {
        logMove(p, '育成テンダー（支配下契約）', from, to);
        p.offJoin = offseasonYear;
        const comp = 300; // 元の球団への少額の補償（仮）
        _money(to.id, '育成テンダー', -comp, '育成テンダー補償 ${p.registeredName}');
        _money(from.id, '育成テンダー', comp, '育成テンダー補償 ${p.registeredName}');
      }
      p.uniformNumber = RosterEngine.freeNumber(to, ikusei: false);
      RosterEngine.addPlayer(to, p);
      transactions.insert(0, '${_today()} 育成テンダー ${p.registeredName} ${to.id == from.id ? '${teamShort(from)}で支配下に' : '${teamShort(from)} → ${teamShort(to)}（支配下）'}（${formatSalary(p.salary)}）');
      if (from.id == myTeamId || to.id == myTeamId) {
        _addNews(['育成テンダー：${p.registeredName}は${to.id == from.id ? '${teamShort(from)}で支配下契約' : '${teamShort(from)}から${teamShort(to)}へ支配下で移籍'}（${formatSalary(p.salary)}）']);
      }
    }
    tenders = [];
  }

  /// 現役ドラフトの日（12月9日。シーズンを終えたオフだけ）
  bool get activeDraftPending => _afterSeason && currentDate.month == 12 && currentDate.day == 9 && activeDraftYear < currentDate.year;

  /// 現役ドラフトで自球団が指名できる候補（他球団の対象選手）
  List<Player> activeDraftCandidates() => [
        for (final t in leagueTeams)
          if (t.id != myTeamId)
            for (final p in t.players)
              if (TransferEngine.activeDraftEligible(p, offseasonYear)) p,
      ]..sort((a, b) => RosterEngine.value(b).compareTo(RosterEngine.value(a)));

  /// 自球団の対象選手（指名されるかもしれない）
  List<Player> activeDraftMine() => [for (final p in myTeam?.players ?? const <Player>[]) if (TransferEngine.activeDraftEligible(p, offseasonYear)) p];

  /// 現役ドラフトを行う。myPick：自球団が指名したい選手（null や、先に他球団に指名されたときは CPU の考え方で選ぶ）
  List<String> runActiveDraft(Player? myPick) {
    if (activeDraftYear >= currentDate.year) return const [];
    final order = [for (final id in draftWaiver()) ?teamById(id)];
    final moves = TransferEngine.runActiveDraft(order, offseasonYear, (t, cands) {
      if (t.id == myTeamId && myPick != null && cands.any((p) => p.id == myPick.id)) return cands.firstWhere((p) => p.id == myPick.id);
      final best = (List.of(cands)..sort((a, b) => cpuValue(t, b).compareTo(cpuValue(t, a)))).first;
      return best;
    });
    final lines = <String>[];
    for (final (from, to, p) in moves) {
      RosterEngine.removePlayer(from, p);
      logMove(p, '現役ドラフト', from, to);
      p.offJoin = offseasonYear;
      RosterEngine.addPlayer(to, p);
      lines.add('${teamShort(to)}：${p.registeredName}（${p.mainPosition}・${p.age}歳・元${teamShort(from)}）');
      transactions.insert(0, '${_today()} 現役ドラフト ${p.registeredName} ${teamShort(from)} → ${teamShort(to)}');
    }
    activeDraftYear = currentDate.year;
    _trimTransactions();
    _addNews(['現役ドラフト：${lines.isEmpty ? '移籍なし' : lines.join('、')}']);
    updateAndSave();
    return lines;
  }

  /// FA 宣言の日（11月の第2月曜日）
  DateTime faDeclareDate(int y) {
    var d = DateTime(y, 11, 1);
    while (d.weekday != DateTime.monday) {
      d = d.add(const Duration(days: 1));
    }
    return d.add(const Duration(days: 7));
  }

  /// FA の宣言より前か（残留交渉の期間）
  bool get beforeFaDeclare => faCases.isEmpty;

  /// FA の交渉期間か（宣言〜結果）
  bool get faOpen => faCases.isNotEmpty && faCases.any((f) => f.result.isEmpty);

  /// シーズン後のオフで、FA宣言日以降なのにまだ宣言が行われていなければ宣言を行う（既存セーブの修復・救済用）
  void ensureFaDeclaredIfNeeded() {
    if (!offAfterSeason) return;
    final y = currentDate.year;
    final declareDay = faDeclareDate(y);
    if (!currentDate.isBefore(declareDay) && currentDate.month <= 12) {
      if (faCases.isEmpty) {
        _overseasFa();
        _faDeclare();
        updateAndSave();
      }
    }
  }

  /// 1日ずつの行事（(from, to] の各日）
  void _dailyEvents(DateTime from, DateTime to) {
    final (firstReg, lastReg) = _regularRange();
    var d = from;
    while (d.isBefore(to)) {
      d = d.add(const Duration(days: 1));
      if (d.month == 2 && d.day == 1) applyNextNumbers(d); // 2月1日：予約した背番号に変える
      if (d.month == 1 && d.day == 1) _newYearDay(); // 1月1日：月初めのお金の処理より先に（来季からのスポンサー契約の支払いを始める）
      final inSeason = !seasonFinished && firstReg != null && lastReg != null && !d.isBefore(firstReg) && !d.isAfter(lastReg);
      if (inSeason) {
        for (final t in leagueTeams) {
          for (final id in t.roster1G) {
            final p = t.players.where((x) => x.id == id).firstOrNull;
            if (p != null) p.regDays++;
          }
        }
      }
      if (d.day == 1) _monthlyFinance(d);
      if (d.day == 1) _scoutTradeTips(d); // 毎月1日：スカウトのトレード候補
      if (d.day == 1 && (d.month == 7 || teamPolicy.isEmpty)) reviewPolicies(); // CPU 球団の方針の見直し
      _monthlyMvpOn(d);
      _settleGoods(d);
      if (d.weekday == DateTime.monday) {
        _amScoutWeek(d); // 地区担当の発掘（4〜10月）
        _overseasScoutWeek(d); // 海外担当（海外の選手・日本の独立リーグ）
        if (prospects.isNotEmpty) _scoutWeek(d);
        _fileWishesIfDue();
        if (faOpen && d.isAfter(faDeclareDate(d.year))) {
          _cpuFaOffers(); // FA の交渉期間（宣言〜12/31）は、毎週 CPU 球団が条件を出す
          _faWeekly(d);
        }
        if (inSeason) _cpuWeekly();
      }
      final played = offAfterSeason; // シーズンを1つ終えた後のオフ
      if (played && d.month == 11 && d.day == faDeclareDate(d.year).day) {
        faCases = [];
        _overseasFa(); // 海外FA（国内FA の宣言より先）
        _faDeclare();
      }
      if (d.month == 3 && d.day == 1) _expirePartnerSlots();
      switch ((d.month, d.day)) {
        case (11, 1):
          if (played) {
            _partnerTermEnd(); // 提携の期間が終わった選手
            _postingRequests(); // ポスティングの希望
          }
          if (draftDoneYear >= d.year && amWorld == null) {
            prospects = _withIndie(DraftEngine.generate(d.year + 1, Random((d.year + 1) * 31 + 7)), d.year + 1); // 種はその年の候補の年（今年の種だと今年と同じ候補になる）。独立出身は他リーグの選手から
            _addNews(['${d.year + 1}年のドラフト候補（${prospects.length}人）の調査を始めました']);
          }
        case (11, 12):
          _tryout();
        case (11, 20):
          if (played) _tenderStart();
        case (12, 31):
          if (faOpen) {
            _cpuFaOffers();
            _faResolve(); // 交渉の期限：残っている選手の行き先をすべて決める（どこからも条件が無ければ自由契約へ）
          }
        case (12, 1):
          if (played) {
            _postingResolve(); // ポスティング：大リーグとの交渉の結果
            _partnerStayResolve(); // 決めていない提携選手の残留は、残す
            _tenderResolve(); // 育成テンダーの結果
            _contractRenewal();
            _cpuForeignDepart();
          }
          foreignPool = buildForeignPool(d.year + 1); // 他リーグに実際にいる選手から
          sponsorOffers = FinanceEngine.offers(d.year + 1, Random(d.year * 59 + 3));
          consultants.removeWhere((c) => c.teamId.isEmpty);
          _addConsultants(FinanceEngine.consultants(d.year + 1, Random(d.year * 61 + 9)));
          _addNews(['新しいスポンサー候補（${sponsorOffers.length}社）と経営コンサルタントの一覧が届きました']);
          _addNews(['海外の選手の一覧が届きました（${foreignPool.length}人）']);
        case (12, 15):
          _cpuSponsors(december: true);
          _cpuForeignSign();
          _cpuIkuseiPromote();
          _cpuTrades(Random(d.year * 17));
        case (1, 15):
          _tryout(); // 年明け：自由契約（FA の未契約を含む）の選手を CPU 球団が獲る
        case (2, 1):
          _retireFreeAgents(); // 1月31日までに契約できなかった自由契約の選手は引退
        case (6, 30):
          _cpuIkuseiPromote();
        case (7, 20):
          _cpuTrades(Random(d.year * 19 + 1));
        case (7, 31):
          _addNews(['今日がトレード・支配下登録の期限です']);
        default:
          break;
      }
      if (loaded) _diffRosters(at: d); // その日の入団・退団を、その日付で記録する
    }
  }

  /// オフシーズンの止まる日（FA 宣言・契約更改・FA の期限）
  List<DateTime> _offseasonStops(DateTime d0) {
    if (!_afterSeason) return const [];
    final y = d0.year;
    return [faDeclareDate(y), DateTime(y, 12, 1), DateTime(y, 12, 9), DateTime(y, 12, 31)];
  }

  // ───────── スカウト・ドラフト ─────────

  /// 次のドラフトの候補がなければ作る（ゲーム開始時は、それまでの調査の分をまとめて済ませる）
  void _ensureProspects() {
    final d = currentDate;
    final y = (d.month < 10 || (d.month == 10 && d.day <= 31)) && draftDoneYear < d.year ? d.year : d.year + 1;
    if (prospects.isNotEmpty && prospects.first.year == y) return;
    // 新しい方式：候補はスカウトが4月から発掘する。ドラフトの直前（10月）に候補が1人もいないとき（はじめから・以前のデータ）だけ、以前の方式で作る
    if (!(d.month == 10 && draftDoneYear < d.year)) return;
    prospects = _withIndie(DraftEngine.generate(y, Random(y * 31 + 7)), y);
    preScoutIfNeeded();
  }

  /// 志望届（9月1日から。force ならドラフト会議の前に必ず）：まだ出していない候補が、希望球団を1〜3まで決めるか「希望なし」を選ぶ
  void _fileWishesIfDue({bool force = false}) {
    if (prospects.isEmpty || teams.isEmpty) return;
    final y = prospects.first.year;
    if (!force && currentDate.isBefore(DateTime(y, 9, 1))) return;
    final pending = prospects.where((p) => !p.wishFiled).toList();
    if (pending.isEmpty) return;
    final league = teams.expand((t) => t.players).toList();
    final ranked = teams.toList();
    // 強さ：前年の順位（なければ今季の勝率）
    double strengthOf(Team t) {
      final lr = lastRankOf[t.id];
      if (lr != null && lr > 0) return 1.0 - (lr - 1) / 6.0;
      final rec = computeStandings(teams, matches, t.league, StandingsKind.official).where((r) => r.team.id == t.id).firstOrNull;
      return rec == null || rec.games == 0 ? 0.5 : rec.w / max(1, rec.w + rec.l);
    }

    final strength = {for (final t in ranked) t.id: strengthOf(t)};
    final r = Random(y * 977 + pending.length);
    for (final pr in pending) {
      final pt = CoachEngine.playerType(pr.player);
      final pos = pr.player.mainPosition;
      final wt = [
        for (final t in leagueTeams)
          WishTeam(
            id: t.id,
            short: teamShort(t),
            facility: finOf(t).fac('bio') + finOf(t).fac('medical'),
            affinity: CoachEngine.affinity(staffOf(t)['監督']?.type ?? '万能型', pt),
            playerIds: {for (final p in t.players) p.id},
            depth: pr.player.isPitcher ? t.players.where((p) => p.isPitcher && !p.ikusei).length ~/ 2 : t.players.where((p) => !p.isPitcher && !p.ikusei && p.mainPosition == pos).length,
            funds: finOf(t).funds,
            strength: strength[t.id] ?? 0.5,
            popularity: finOf(t).popularity,
          ),
      ];
      DraftWish.file(pr, wt, league, r);
    }
    final mine = myTeam == null ? 0 : prospects.where((p) => p.wishes.isNotEmpty && p.wishes.first == myTeamId).length;
    _addNews(['ドラフト候補が志望届を出しました（${pending.length}人）。自球団を1希望にした候補は$mine人。希望球団以外に入団した選手は、国内FA が最大2年早くなります']);
  }

  /// まだ1人も調べていなければ、それまでの調査の分をまとめて済ませる（ゲーム開始時。自球団が決まってから）
  void preScoutIfNeeded() {
    if (myTeam == null || prospects.isEmpty || prospects.any((p) => p.reports > 0)) return;
    final weeksLeft = DateTime(prospects.first.year, 10, 31).difference(currentDate).inDays ~/ 7;
    for (var i = 0; i < max(0, 50 - weeksLeft); i++) {
      _scoutWeek(null);
    }
  }

  /// 球団のスカウト眼力（チーフ6割・スカウト4割）
  int scoutEye(Team t) {
    final s = staffOf(t);
    final chiefs = [for (final c in coaches) if (c.teamId == t.id && c.role == 'チーフスカウト') c.trueAbil['スカウト眼力'] ?? 50]..sort((a, b) => b.compareTo(a));
    if (chiefs.isEmpty) chiefs.add(s['スカウト']?.trueAbil['スカウト眼力'] ?? 50);
    final avg = chiefs.reduce((a, b) => a + b) / chiefs.length;
    return (chiefs.first * 0.7 + avg * 0.3).round() + FacilityEngine.scoutBonus(finOf(t).fac('scout')); // チーフ（複数なら眼力の高い人が中心）＋スカウト情報網＆データ分析室
  }

  /// スカウトの週報：注目の候補を優先し、まだ調べていない有名な候補から6人を調べる
  void _scoutWeek(DateTime? d) {
    final my = myTeam;
    if (my == null || prospects.isEmpty) return;
    final eye = scoutEye(my);
    final r = Random((d?.millisecondsSinceEpoch ?? prospects.length) ^ eye);
    double fame(Prospect p) => (p.player.ovr + RosterEngine.potentialOvr(p.player)) / 2 + p.curBias + (p.ikuseiTier ? -8 : 0);
    final cands = prospects.where((p) => p.reports < 4 && p.knownTo(my.id)).toList()
      ..sort((a, b) {
        final wa = a.watched ? 0 : 1, wb = b.watched ? 0 : 1;
        if (wa != wb) return wa.compareTo(wb);
        if (a.reports != b.reports) return a.reports.compareTo(b.reports);
        return fame(b).compareTo(fame(a));
      });
    final chiefs = coaches.where((c) => c.teamId == my.id && c.role == 'チーフスカウト').length;
    final picked = cands.take(4 + 2 * max(1, chiefs)).toList();
    for (final p in picked) {
      DraftEngine.scout(p, eye, r);
    }
    if (d != null && picked.isNotEmpty) {
      scoutLog.insert(0, '${d.month}/${d.day} スカウト週報：${picked.map((p) => '${p.player.lastName}（${p.school}・${p.player.mainPosition}）').join('、')}');
      if (scoutLog.length > 60) scoutLog = scoutLog.sublist(0, 60);
    }
  }

  /// ドラフト（2巡目）の指名順：下位から、リーグを交互に（どちらのリーグが先かは年ごとに交代）
  List<String> draftWaiver() {
    List<String> order(String lg) => computeStandings(teams, matches, lg, StandingsKind.official).reversed.map((r) => r.team.id).toList();
    final cl = order('CL'), pl = order('PL');
    final plFirst = currentDate.year.isEven;
    final a = plFirst ? pl : cl, b = plFirst ? cl : pl;
    final out = <String>[];
    for (var i = 0; i < max(a.length, b.length); i++) {
      if (i < a.length) out.add(a[i]);
      if (i < b.length) out.add(b[i]);
    }
    for (final t in leagueTeams) {
      if (!out.contains(t.id)) out.add(t.id);
    }
    return out;
  }

  /// スカウトの指名予想：CPU 球団が何位で指名しそうか（例：3球団1位（神・ラ・宮） 2球団2位（西・ソ））
  ///  各球団の評価（CPU と同じ考え方）に、自球団スカウトの眼力による見立てのずれを足して、1〜5位を予想する。週ごとに作り直す
  Map<String, String> draftForecast() {
    final week = currentDate.difference(DateTime(2000)).inDays ~/ 7;
    final key = '${currentDate.year}-$week-${prospects.length}-$myTeamId';
    if (key == _forecastKey) return _forecast;
    final my = myTeam;
    final eye = my == null ? 50 : scoutEye(my);
    final sd = (100 - eye) / 12.0; // 眼力が低いほど予想が外れやすい
    final cpu = leagueTeams.where((t) => t.id != myTeamId && RosterEngine.freeSlots(t) > 0).toList();
    final pool = prospects.where((p) => !p.ikuseiTier).toList();
    double gauss(Random r) => sqrt(-2 * log(1 - r.nextDouble())) * cos(2 * pi * r.nextDouble());
    final score = <String, Map<String, double>>{};
    for (final t in cpu) {
      final r = Random(currentDate.year * 7919 + week * 31 + t.id.hashCode);
      final eyeT = scoutEye(t);
      score[t.id] = {for (final p in pool) if (p.knownTo(t.id)) p.id: DraftEngine.cpuScore(p, t, eyeT, r) + gauss(r) * sd};
    }
    String? best(String tid, Set<String> taken) {
      String? b;
      var bs = -1e9;
      score[tid]!.forEach((pid, s) {
        if (!taken.contains(pid) && s > bs) {
          bs = s;
          b = pid;
        }
      });
      return b;
    }

    final out = <String, Map<String, List<String>>>{}; // 候補 → 「1位」「外れ1位」「2位」… → 球団
    void add(String pid, String label, String tid) => out.putIfAbsent(pid, () => {}).putIfAbsent(label, () => []).add(tid);
    final taken = <String>{};
    // 1位：入札が重なったら抽選（予想では評価の高い球団が引く扱い）、外れた球団は再入札
    var pending = cpu.map((t) => t.id).toList();
    var wave = 0;
    while (pending.isNotEmpty && wave++ < 6) {
      final bids = <String, List<String>>{};
      for (final tid in pending) {
        final b = best(tid, taken);
        if (b != null) bids.putIfAbsent(b, () => []).add(tid);
      }
      pending = [];
      bids.forEach((pid, bidders) {
        for (final tid in bidders) {
          add(pid, wave == 1 ? '1位' : '外れ1位', tid);
        }
        taken.add(pid);
        bidders.sort((a, b) => score[b]![pid]!.compareTo(score[a]![pid]!));
        pending.addAll(bidders.skip(1));
      });
    }
    // 2〜5位：その巡で各球団がいちばん欲しい残りの候補
    for (var rd = 2; rd <= 5; rd++) {
      final want = <String, List<String>>{};
      for (final t in cpu) {
        final b = best(t.id, taken);
        if (b != null) want.putIfAbsent(b, () => []).add(t.id);
      }
      want.forEach((pid, ts) {
        for (final tid in ts) {
          add(pid, '$rd位', tid);
        }
        taken.add(pid);
      });
    }
    String ini(String tid) {
      final t = teamById(tid);
      if (t == null) return '?';
      return t.initialName.isNotEmpty ? t.initialName : teamShort(t).characters.first;
    }

    _forecast = {
      for (final e in out.entries)
        e.key: [for (final l in e.value.entries) '${l.value.length}球団${l.key}（${l.value.map(ini).join('・')}）'].join(' '),
    };
    _forecastKey = key;
    return _forecast;
  }

  /// CPU 球団の育成選手の目標人数：基本20人（資金100億〜200億円）。200億円を超える分は20億円ごとに+1（最大30人）、
  ///  苦しければ減らす（30億〜100億円 16人、0〜30億円 12人、赤字 8人）。資金の単位は万円
  int ikuseiTarget(Team t) => min(_ikuseiTargetFunds(t), ikuseiCap(t));

  int _ikuseiTargetFunds(Team t) {
    final f = finances[t.id];
    if (f == null) return 20;
    final funds = f.funds;
    if (funds >= 2000000) return (20 + (funds - 2000000) ~/ 200000).clamp(20, 30);
    if (funds >= 1000000) return 20;
    if (funds >= 300000) return 16;
    if (funds >= 0) return 12;
    return 8;
  }

  DraftSession createDraftSession() {
    preScoutIfNeeded();
    _fileWishesIfDue(force: true);
    // ゲーム開始直後のドラフト：CPU 球団は先に戦力外通告を済ませて枠を空ける（シーズン後のドラフトでは、シーズン終了時に済んでいる）
    if (prepDraftYear < currentDate.year && currentDate.year < startYear) {
      prepDraftYear = currentDate.year;
      _cpuReleases(currentDate.year);
    }
    return DraftSession(
        year: currentDate.year,
        teams: leagueTeams,
        waiver: draftWaiver(),
        myId: myTeamId,
        candidates: prospects,
        eyes: {for (final t in leagueTeams) t.id: scoutEye(t)},
        ikuseiTargets: {for (final t in leagueTeams) t.id: ikuseiTarget(t)},
        comp15: {for (final e in compPicks.entries) if (e.value.isNotEmpty && e.value[0] > 0) e.key: e.value[0]},
        comp25: {for (final e in compPicks.entries) if (e.value.length > 1 && e.value[1] > 0) e.key: e.value[1]},
        pickOwner: Map.of(pickOwner),
        ikuseiCaps: {for (final t in leagueTeams) t.id: ikuseiCap(t)},
        rnd: Random(currentDate.year * 101 + DateTime.now().millisecond),
      );
  }

  /// ドラフトをおまかせで済ませる（確認用・まとめて進めるとき）
  void runAutoDraft() {
    _ensureProspects();
    final s = createDraftSession();
    s.runAll();
    applyDraft(s);
  }

  /// ドラフトの結果を反映（入団・契約金・背番号）
  void applyDraft(DraftSession s) {
    if (draftDoneYear >= s.year) return; // 同じ年のドラフトを二重に反映しない
    final rollover = currentDate.year == startYear; // この後の1月1日に年を取る
    final mine = <String>[];
    final firsts = <String>[];
    for (final pk in s.picks) {
      final t = teamById(pk.teamId);
      if (t == null) continue;
      var p = pk.prospect.player;
      if (t.players.contains(p)) continue; // もう入団している
      if (teams.any((x) => x.players.any((q) => q.id == p.id))) {
        // 番号がほかの選手とぶつかる（以前のデータの選手など）：番号を付け直して入団させる
        final j = p.toJson();
        j['id'] = '${p.id}_d${s.year}';
        p = Player.fromJson(j);
      }
      _removeFromOther(p.id); // 独立リーグの選手なら、その球団から外す
      p.ikusei = pk.ikusei;
      p.ikuseiYears = 0;
      p.draftYear = s.year;
      p.draftInfo = '${s.year}年ドラフト${pk.label}（${pk.prospect.category}・${pk.prospect.school}）';
      if (rollover) {
        p.age -= 1;
        p.proYears = 0;
      } else {
        p.proYears = 1;
      }
      _applyStartYear(p);
      p.salary = DraftEngine.rookieSalary(pk.payRound, pk.ikusei);
      p.prevSalary = 0;
      p.contractYears = 1;
      p.faService = 0;
      p.faShort = DraftWish.faShortFor(pk.prospect, t.id);
      final wl = DraftWish.wishLabel(pk.prospect, t.id);
      if (wl.isNotEmpty) p.draftInfo = '${p.draftInfo}　$wl${p.faShort > 0 ? '（国内FA ${Player.faYears - p.faShort}年）' : ''}';
      p.regDays = 0;
      p.uniformNumber = RosterEngine.freeNumber(t, ikusei: pk.ikusei);
      RosterEngine.addPlayer(t, p);
      _money(t.id, '契約金', -DraftEngine.signingBonus(pk.payRound, pk.ikusei), '契約金 ${p.registeredName}');
      transactions.insert(0, '${s.year}/10/31 ${teamShort(t)} ${p.draftInfo} ${p.registeredName}（${p.mainPosition}）');
      _amOnDrafted(pk.prospect, t, s.year, pk.label);
      (draftBook[s.year] ??= []).add({
        'round': pk.round, 'label': pk.label, 'team': t.id, 'id': p.id, 'name': p.registeredName, 'pos': p.mainPosition,
        'cat': pk.prospect.category, 'school': pk.prospect.school, 'lottery': pk.lottery, 'ikusei': pk.ikusei, 'comp': pk.comp,
        'snap': p.toJson(),
      });
      if (t.id == myTeamId) mine.add('${pk.label} ${p.registeredName}（${p.mainPosition}・${pk.prospect.school}）');
      if (pk.round == 1 && !pk.ikusei && !pk.comp) firsts.add('${teamShort(t)}：${p.registeredName}${pk.lottery ? '（抽選）' : ''}');
    }
    _trimTransactions();
    draftDoneYear = s.year;
    compPicks = {}; // 補償の指名権は、このドラフトで使い切る（使わなかった枠も消える）
    pickOwner = {}; // トレードで動いた指名権も、このドラフトで使い切る
    prospects = [];
    _addNews([if (firsts.isNotEmpty) 'ドラフト1位：${firsts.join('、')}', if (mine.isNotEmpty) '自球団の指名：${mine.join('、')}']);
    updateAndSave();
  }

  /// 以前のセーブ：今いる選手の「ドラフトの年・順位」から指名の記録を作る
  void _backfillDraftBook() {
    final re = RegExp(r'ドラフト(育成)?(\d+)(\.5)?位（([^・）]+)・([^）]+)）');
    for (final t in teams) {
      for (final p in t.players) {
        if (p.draftYear <= 0) continue;
        final m = re.firstMatch(p.draftInfo);
        if (m == null) continue;
        (draftBook[p.draftYear] ??= []).add({
          'round': int.parse(m.group(2)!), 'label': '${m.group(1) ?? ''}${m.group(2)}${m.group(3) ?? ''}位', 'team': t.id, 'id': p.id, 'name': p.registeredName,
          'pos': p.mainPosition, 'cat': m.group(4), 'school': m.group(5), 'lottery': false, 'ikusei': m.group(1) != null, 'comp': m.group(3) != null,
        });
      }
    }
  }

  /// 指名の記録の選手：いまの選手（どの球団・他リーグでも）を探し、いなければ指名した時のデータ
  (Player?, Team?) draftBookPlayer(Map<String, dynamic> e) {
    final id = e['id'] as String?;
    for (final t in teams) {
      for (final p in t.players) {
        if (p.id == id) return (p, t);
      }
    }
    final snap = e['snap'];
    if (snap is Map) return (Player.fromJson(Map<String, dynamic>.from(snap)), null);
    return (null, null);
  }

  void _trimTransactions() {
    if (transactions.length > 400) transactions = transactions.sublist(0, 400);
  }

  /// オフシーズンの年（10〜12月はその年、1〜3月は前の年）。そのオフに獲った選手・人的補償の判定に使う
  int get offseasonYear => currentDate.month <= 3 ? currentDate.year - 1 : currentDate.year;

  /// 以前のセーブ：そのオフに FA で獲った選手が人的補償で移っていたら、元に戻して補償を選び直す。記録とお知らせも直す
  void _fixCompOfFaSigned() {
    // そのオフに FA で獲った選手に印をつける（移籍の記録から）
    final y = offseasonYear;
    bool inOff(String s) {
      final m = RegExp(r'^(\d{4})年(\d+)月').firstMatch(s);
      if (m == null) return false;
      final yy = int.parse(m.group(1)!), mm = int.parse(m.group(2)!);
      return (yy == y && mm >= 10) || (yy == y + 1 && mm <= 3);
    }

    final all = [for (final t in leagueTeams) for (final p in t.players) (p, t)];
    for (final (p, _) in all) {
      if (p.offJoin == 0 && p.moves.isNotEmpty && p.moves.last.contains('FA 移籍') && inOff(p.moves.last)) p.offJoin = y;
    }
    // 人的補償の記録「2026/12/3 名前 人的補償 A → B（FA 選手の補償）」
    final re = RegExp(r'^(\d{4})/(\d+)/(\d+) (.+?) 人的補償 (.+?) → (.+?)（(.+?)の補償）$');
    for (final line in List.of(transactions)) {
      final m = re.firstMatch(line);
      if (m == null) continue;
      final yy = int.parse(m.group(1)!), mm = int.parse(m.group(2)!);
      if (!((yy == y && mm >= 10) || (yy == y + 1 && mm <= 3))) continue;
      final name = m.group(4)!, toShort = m.group(5)!, fromShort = m.group(6)!, faName = m.group(7)!;
      final to = teams.where((t) => teamShort(t) == toShort).firstOrNull, from = teams.where((t) => teamShort(t) == fromShort).firstOrNull;
      if (to == null || from == null) continue;
      final pick = from.players.where((p) => p.registeredName == name && p.offJoin == y).firstOrNull;
      if (pick == null) continue; // FA で獲った選手ではない（正しい補償）
      final rankM = RegExp('${RegExp.escape(faName)} FA 移籍 .+?（([ABC])ランク').firstMatch(transactions.firstWhere((l) => l.contains('$faName FA 移籍'), orElse: () => ''));
      // 元に戻す（選手・お金・記録・お知らせ）
      RosterEngine.removePlayer(from, pick);
      RosterEngine.addPlayer(to, pick);
      // FA 選手の年俸（補償の額のもと）：戻したあとに探す（FA 選手そのものが補償で戻されていたこともある）
      final fa = to.players.where((p) => p.registeredName == faName).firstOrNull;
      final c = CompCase(faName, rankM?.group(1) ?? 'B', from.id, to.id, fa?.salary ?? 0);
      final paid = c.money(true);
      _money(to.id, 'FA 補償', paid, 'FA 補償の取り消し $faName');
      _money(from.id, 'FA 補償', -paid, 'FA 補償の取り消し $faName');
      transactions.remove(line);
      news.removeWhere((n) => n.contains('人的補償で、$nameが'));
      // 選び直す（自球団が受け取る側なら選んでもらう）
      if (from.id == myTeamId && !autoMode) {
        pendingComp.add(c);
        _addNews(['補償：$faNameの移籍の人的補償で$nameを選んでいましたが、その年に FA で獲った選手は対象外のため取り消しました。補償を選び直してください（フロント → 補強 → FA）']);
      } else {
        _resolveCompAuto(c, y);
        _addNews(['補償の訂正：$faNameの移籍の人的補償（$name）は、その年に FA で獲った選手のため取り消し、選び直しました']);
      }
    }
  }

  String _today() => '${currentDate.year}/${currentDate.month}/${currentDate.day}';

  // ───────── シーズン終了時：引退・FA資格・戦力外・監督交代 ─────────

  /// 引退（すべて OB 一覧へ）。外国人は CPU 球団では退団する。自球団の引退者の名前を返す
  List<String> _processRetirements(int year) {
    final r = Random(year * 7919);
    final mine = <String>[];
    var n = 0;
    for (final t in leagueTeams) {
      for (final p in List.of(t.players)) {
        final foreign = p.foreignSlot;
        double chance;
        if (foreign) {
          if (t.id == myTeamId) continue; // 自球団の外国人は、自分で決める（戦力外）
          chance = p.age >= 36 ? 0.7 : (p.ovr < 54 ? 0.5 : 0.08);
        } else {
          chance = TransferEngine.retireChance(p);
        }
        if (r.nextDouble() >= chance) continue;
        RosterEngine.removePlayer(t, p);
        n++;
        _keepRetiree(p, t, year);
        if (!foreign) coaches.add(TransferEngine.obFromPlayer(p, t.id, r));
        transactions.insert(0, '$year/10 ${teamShort(t)} ${p.registeredName}（${p.age}歳・${p.mainPosition}）${foreign ? '退団' : '引退'}');
      if (t.id == myTeamId) mine.add('${p.registeredName}（${p.age}歳）');
      }
    }
    _trimOb();
    _trimTransactions();
    _addNews(['今季限りで $n人が引退・退団${mine.isNotEmpty ? '（自球団：${mine.join('、')}）' : ''}']);
    return mine;
  }

  /// OB 一覧が増えすぎないように、高齢で実績の小さい人から外す
  void _trimOb() {
    final obs = coaches.where((c) => c.teamId == null).toList();
    if (obs.length <= 160) return;
    double fame(Coach c) => c.pitcherBg ? (c.career['wins'] ?? 0) + (c.career['saves'] ?? 0) * 0.8 : (c.career['hits'] ?? 0) / 10.0 + (c.career['hr'] ?? 0);
    obs.sort((a, b) => (fame(a) - a.age * 3).compareTo(fame(b) - b.age * 3));
    final drop = obs.take(obs.length - 160).map((c) => c.id).toSet();
    coaches.removeWhere((c) => drop.contains(c.id));
  }

  /// FA 資格：1軍登録145日で1年。育成の年数も進める
  void _processService() {
    for (final t in leagueTeams) {
      for (final p in t.players) {
        final wasSlot = p.foreignSlot;
        if (p.regDays >= 145) p.faService++;
        if (wasSlot && !p.foreignSlot) {
          transactions.insert(0, '${_today()} ${teamShort(t)} ${p.registeredName} FA 権取得（外国人枠外・日本人選手の扱いに）');
          if (t.id == myTeamId) _addNews(['${p.registeredName}が FA 権を取得し、日本人選手の扱い（外国人枠外）になりました']);
        }
        p.regDays = 0;
        if (p.ikusei) p.ikuseiYears++;
      }
    }
  }

  /// CPU 球団の戦力外通告（自由契約の一覧へ）
  /// 以前のセーブ：CPU 球団の支配下が63人を超えていたら、価値の低い選手から自由契約にして63人にする
  void _trimCpuRosters() {
    var n = 0;
    for (final t in leagueTeams.where((t) => t.id != myTeamId)) {
      final sh = t.players.where((p) => !p.ikusei).toList()..sort((a, b) => RosterEngine.value(a).compareTo(RosterEngine.value(b)));
      final counts = RosterEngine.posCounts(t);
      var count = sh.length;
      for (final p in sh) {
        if (count <= RosterEngine.cpuTarget) break;
        final pos = p.mainPosition;
        final minN = pos == '投手' ? 28 : (pos == '捕手' ? 3 : 2);
        if ((counts[pos] ?? 0) <= minN || t.lineup.any((l) => l.playerId == p.id) || t.activeRotation.contains(p.id)) continue;
        RosterEngine.removePlayer(t, p);
        counts[pos] = (counts[pos] ?? 1) - 1;
        count--;
        p.salary = max(450, round50(p.salary * 0.7));
        freeAgents.add(FreeAgent(p, t.id, '戦力外'));
        transactions.insert(0, '${_today()} ${teamShort(t)} ${p.registeredName}（${p.age}歳）戦力外通告');
        n++;
      }
    }
    if (n > 0) _addNews(['他球団が支配下を63人に整理しました（戦力外 $n人。自由契約の一覧で獲得できます）']);
  }

  void _cpuReleases(int year) {
    var n = 0;
    for (final t in leagueTeams.where((t) => t.id != myTeamId)) {
      for (final p in TransferEngine.cpuReleases(t)) {
        RosterEngine.removePlayer(t, p);
        p.salary = max(p.ikusei ? 250 : 450, round50(p.salary * 0.7));
        freeAgents.add(FreeAgent(p, t.id, p.ikusei ? '育成満了' : '戦力外'));
        transactions.insert(0, '$year/10 ${teamShort(t)} ${p.registeredName}（${p.age}歳）${p.ikusei ? '育成契約満了' : '戦力外通告'}');
        n++;
      }
    }
    _trimTransactions();
    if (n > 0) _addNews(['他球団の戦力外通告：$n人（自由契約の一覧で獲得できます）']);
  }

  /// 監督の交代（成績が悪い CPU 球団）
  /// CPU 球団の監督交代。交代した球団の ID を返す（浪人明けの打診に使う）
  List<String> _managerChanges(Map<String, int> ranks, int year) {
    final r = Random(year * 4243);
    final changed = <String>[];
    for (final t in leagueTeams.where((t) => t.id != myTeamId || ronin)) {
      final m = staffOf(t)['監督'];
      if (m == null) continue;
      final rank = ranks[t.id] ?? 3;
      final fire = (rank >= 6 && m.seasonsWithTeam >= 2 && r.nextDouble() < 0.6) || (rank >= 5 && m.seasonsWithTeam >= 4 && r.nextDouble() < 0.4) || m.age >= 72;
      if (!fire) continue;
      m.teamId = null;
      m.role = null;
      m.seasonsWithTeam = 0;
      final n = _hireManager(t, r, exclude: m.id);
      changed.add(t.id);
      _addNews(['${t.name}：${m.name}監督が退任、後任は${n.name}']);
      transactions.insert(0, '$year/10 ${teamShort(t)} 監督交代 ${m.name} → ${n.name}');
    }
    _syncStyles();
    return changed;
  }

  // ───────── CPU 監督 ─────────

  /// CPU 球団に監督がいなければ OB から選ぶ。自球団（監督はユーザー）の監督枠は空ける
  void _ensureManagers() {
    final r = Random(startYear * 97);
    for (final t in leagueTeams) {
      final m = staffOf(t)['監督'];
      if (t.id == myTeamId && !ronin) {
        if (m != null) {
          m.teamId = null;
          m.role = null;
        }
        continue;
      }
      if (m == null) _hireManager(t, r);
    }
    _syncStyles();
  }

  Coach _hireManager(Team t, Random r, {String? exclude}) {
    double judge(Coach c) => ['代打判断', '継投判断', '守備交代判断', '走塁判断', '人望'].map((k) => c.trueAbil[k] ?? 50).reduce((a, b) => a + b) / 5 + (c.formerTeamId == t.id ? 3 : 0) + r.nextDouble() * 8;
    final obs = coaches.where((c) => c.teamId == null && c.id != exclude && c.age >= 40).toList()..sort((a, b) => judge(b).compareTo(judge(a)));
    Coach c;
    if (obs.isNotEmpty) {
      c = obs[r.nextInt(min(5, obs.length))];
    } else {
      c = CoachEngine.generate(r, 'CO${DateTime.now().microsecondsSinceEpoch}', pitcherBg: r.nextBool(), formerTeamId: t.id, age: 45 + r.nextInt(20));
      coaches.add(c);
    }
    c.teamId = t.id;
    c.role = '監督';
    c.seasonsWithTeam = 0;
    if (c.mgrWins < 0) c.mgrWins = 0; // 新しく監督になった：監督の勝利を数える
    c.known = true;
    c.style = CoachEngine.managerStyle(c, r);
    c.salary = max(c.salary, 5000);
    return c;
  }

  /// 試合エンジンに CPU 監督の傾向を渡す
  void _syncStyles() {
    for (final c in coaches) {
      if (c.role == '監督' && c.style.isNotEmpty && !c.style.containsKey('potential')) c.style['potential'] = 15 + Random(c.id.hashCode ^ 0x907).nextInt(71);
    }
    MatchSimulator.cpuStyles = {
      for (final c in coaches)
        if (c.role == '監督' && c.teamId != null && (c.teamId != myTeamId || ronin))
          c.teamId!: {...c.style, 'skill': ['代打判断', '継投判断', '守備交代判断', '走塁判断'].map((k) => c.trueAbil[k] ?? 50).reduce((a, b) => a + b) ~/ 4},
    };
  }

  /// CPU 球団の見る目：確かさ（スカウト眼力と監督の判断力の平均）と、実績重視〜将来性重視（0〜100）
  (int, int) cpuEval(Team t) {
    final m = staffOf(t)['監督'];
    final skill = _cpuSkill(t).$1;
    final eye = ((scoutEye(t) + skill) / 2).round();
    final pot = m?.style['potential'] ?? (15 + Random(t.id.hashCode ^ 0x907).nextInt(71));
    return (eye, pot);
  }

  /// CPU 球団の見立てでの選手の価値
  double cpuValue(Team t, Player p) {
    final (eye, pot) = cpuEval(t);
    return RosterEngine.styledValue(p, eye: eye, potential: pot, viewer: t.id);
  }

  /// 相手監督の見る目の説明（トレード画面などに出す）
  String evalStyleText(Team t) {
    final pot = cpuEval(t).$2;
    if (pot >= 62) return '将来性重視：若手の伸びしろを高く見る。ベテランは安く見られがち';
    if (pot <= 38) return '実績重視：今の力と過去の成績を高く見る。若手の伸びしろは安く見られがち';
    return 'バランス型：今の力と将来性の両方を見る';
  }

  /// CPU 監督の手腕（判断力の平均）と若手起用の傾向
  (int, int) _cpuSkill(Team t) {
    final m = staffOf(t)['監督'];
    if (m == null) return (55, 50);
    final skill = ['代打判断', '継投判断', '守備交代判断', '走塁判断'].map((k) => m.trueAbil[k] ?? 50).reduce((a, b) => a + b) ~/ 4;
    return (skill, m.style['youth'] ?? 50);
  }

  /// 毎週月曜（シーズン中）：CPU 球団の1軍・オーダーを組み直す
  void _cpuWeekly() {
    for (final t in leagueTeams.where((t) => t.id != myTeamId || ronin)) { // 浪人中は元の球団も CPU が組む
      final (skill, youth) = _cpuSkill(t);
      RosterEngine.cpuReassign(t, skill: skill, youth: youth, devBonus: (p) => firstDevBonus(t, p));
    }
  }

  void _cpuReassignAll() {
    for (final t in leagueTeams.where((t) => t.id != myTeamId || ronin)) {
      final (skill, youth) = _cpuSkill(t);
      RosterEngine.cpuReassign(t, skill: skill, youth: youth, devBonus: (p) => firstDevBonus(t, p));
    }
    final my = myTeam;
    if (my != null) {
      RosterEngine.repairRoster(my);
      my.autoFillPitchingStaff();
      my.refreshActive26();
    }
  }

  // ───────── FA ─────────

  double _strength(Team t) => (t.wins + t.losses) == 0 ? 0.5 : t.wins / (t.wins + t.losses);

  Player? _findPlayer(String id) {
    for (final t in leagueTeams) {
      for (final p in t.players) {
        if (p.id == id) return p;
      }
    }
    return null;
  }

  Team? teamOfPlayer(String id) => teams.where((t) => t.players.any((p) => p.id == id)).firstOrNull;

  /// 残留を要請する（FA 宣言しにくくなる。年俸＋20%・3年契約）。宣言（11月の第2月曜日）より前だけ
  String? askRetain(Player p) {
    if (!p.hasFA) return 'FA 権を持っていません';
    if (p.retainAsked) return 'すでに要請しています';
    if (faCases.isNotEmpty) return 'FA 宣言の期間は過ぎました';
    if (currentDate.month == 11 && !currentDate.isBefore(faDeclareDate(currentDate.year))) return 'FA 宣言の期間は過ぎました';
    p.retainAsked = true;
    p.salary = round50(p.salary * 1.2);
    p.contractYears = 3;
    updateAndSave();
    return null;
  }

  void _faDeclare() {
    final r = Random(currentDate.year * 211);
    final mine = <String>[];
    for (final t in leagueTeams) {
      final st = _strength(t);
      for (final p in t.players) {
        if (r.nextDouble() >= TransferEngine.declareChance(p, st)) continue;
        faCases.add(FaCase(playerId: p.id, fromTeamId: t.id, rank: TransferEngine.faRank(teams, p), ask: TransferEngine.marketValue(p, r)));
      if (t.id == myTeamId) mine.add(p.registeredName);
      }
    }
    for (final t in leagueTeams) {
      for (final p in t.players) {
        p.retainAsked = false;
      }
    }
    _cpuFaOffers(); // 宣言の日から各球団の条件が見られる
    _addNews(['FA 宣言：${faCases.length}人${mine.isNotEmpty ? '（自球団：${mine.join('、')}）' : ''}。交渉は12月31日まで（毎週月曜に決まる選手もいます。どこと契約しなかった選手は自由契約になります）']);
  }

  /// 自球団の条件を出す（年俸・年数）。交渉の期限（12月31日）まで。条件を出し直すこともできる
  String? offerFa(FaCase f, int salary, int years) {
    if (f.result.isNotEmpty) return '交渉は終わっています';
    if (myTeam != null && f.fromTeamId != myTeamId) {
      final err = _fundsCheck(myTeam!, salary);
      if (err != null) return err;
    }
    f.offers[myTeamId] = [salary, years];
    updateAndSave();
    return null;
  }

  void _cpuFaOffers() {
    final r = Random(currentDate.millisecondsSinceEpoch ~/ 86400000 * 223); // 週ごとに違う判断になるよう、日付から
    // 1球団が条件を出すのは、交渉期間を通して2人まで
    final count = <String, int>{};
    for (final f in faCases) {
      for (final tid in f.offers.keys) {
        if (tid != f.fromTeamId) count[tid] = (count[tid] ?? 0) + 1;
      }
    }
    for (final f in faCases) {
      final p = _findPlayer(f.playerId);
      if (p == null) continue;
      for (final t in leagueTeams.where((t) => t.id != myTeamId)) {
        if (f.offers.containsKey(t.id)) continue;
        if (t.id == f.fromTeamId) {
          if (RosterEngine.value(p) >= 58 && r.nextDouble() < 0.7) f.offers[t.id] = [((f.ask * (0.85 + r.nextDouble() * 0.15)) / 10).round() * 10, 2 + r.nextInt(2)];
          continue;
        }
        if ((count[t.id] ?? 0) >= 2 || RosterEngine.cpuRoom(t) <= 0 || finOf(t).funds < f.ask * 2) continue; // 資金の乏しい球団は手を出さない
        final pol = policyOf(t);
        final interest = RosterEngine.need(t, p.mainPosition) * 0.6 + (cpuValue(t, p) - 60) / 30 + r.nextDouble() * 0.35 + (pol == 'contend' ? 0.15 : 0) - (pol == 'rebuild' ? (p.age >= 30 ? 0.5 : 0.1) : 0); // 監督の見る目（実績重視・将来性重視）と球団の方針で評価
        if (interest < 0.55) continue;
        final years = p.age <= 29 ? 3 + r.nextInt(2) : (p.age <= 32 ? 2 + r.nextInt(2) : 1 + r.nextInt(2));
        f.offers[t.id] = [((f.ask * (0.95 + r.nextDouble() * 0.25)) / 10).round() * 10, years];
        count[t.id] = (count[t.id] ?? 0) + 1;
      }
    }
  }

  /// 毎週月曜：条件が出ている選手のうち、何人かが行き先を決める（期限が近いほど決めやすい）
  void _faWeekly(DateTime d) {
    final r = Random(d.millisecondsSinceEpoch ~/ 86400000);
    final daysLeft = DateTime(d.year, 12, 31).difference(d).inDays;
    final chance = (0.75 - daysLeft / 70.0).clamp(0.12, 0.9); // 11月中旬 約15%〜12月下旬 約70%
    final ready = faCases.where((f) => f.result.isEmpty && f.offers.keys.any((k) => k != f.fromTeamId) && r.nextDouble() < chance).toList();
    if (ready.isEmpty) return;
    _faResolve(only: ready.toSet());
  }

  /// FA の行き先を決める（only を渡すとその選手だけ、無ければ残っている全員）
  void _faResolve({Set<FaCase>? only}) {
    final r = Random(currentDate.year * 227 + currentDate.day);
    for (final f in faCases.where((f) => f.result.isEmpty && (only == null || only.contains(f))).toList()) {
      final p = _findPlayer(f.playerId);
      final from = teamById(f.fromTeamId);
      if (p == null || from == null) {
        f.result = f.fromTeamId;
        continue;
      }
      if (f.offers.isEmpty) {
        // 期限までにどこからも条件が無かった：自由契約へ（1月31日まで契約できる）
        f.result = '-';
        RosterEngine.removePlayer(from, p);
        p.retainAsked = false;
        freeAgents.add(FreeAgent(p, from.id, 'FA 未契約'));
        transactions.insert(0, '${_today()} ${p.registeredName} FA 未契約で自由契約（元${teamShort(from)}）');
        _addNews(['FA：${p.registeredName}（元${teamShort(from)}）はどこの球団とも契約せず、自由契約になりました']);
        continue;
      }
      String best = f.fromTeamId;
      var bs = -1.0;
      f.offers.forEach((tid, o) {
        final t = teamById(tid);
        if (t == null) return;
        if (tid != f.fromTeamId && RosterEngine.freeSlots(t) <= 0) return;
        final s = TransferEngine.offerScore(f, tid, o, _strength(t), r);
        if (s > bs) {
          bs = s;
          best = tid;
        }
      });
      f.result = best;
      final o = f.offers[best];
      if (o != null) {
        p.prevSalary = p.salary;
        p.salary = o[0];
        p.contractYears = o[1];
      }
      if (best == f.fromTeamId) {
        _addNews(['FA：${p.registeredName}は${teamShort(from)}に残留（${formatSalary(p.salary)}・${p.contractYears}年）']);
        transactions.insert(0, '${_today()} ${teamShort(from)} ${p.registeredName} FA 残留');
        continue;
      }
      final to = teamById(best)!;
      RosterEngine.removePlayer(from, p);
      final repeat = p.faCount > 0; // 2回目以降の FA
      p.faService = Player.faYears - 4; // 4年で再取得
      p.faCount++;
      logMove(p, 'FA 移籍', from, to);
      p.offJoin = offseasonYear;
      RosterEngine.addPlayer(to, p);
      transactions.insert(0, '${_today()} ${p.registeredName} FA 移籍 ${teamShort(from)} → ${teamShort(to)}（${f.rank}ランク・${formatSalary(p.salary)}×${p.contractYears}年）');
      _addNews(['FA：${p.registeredName}が${teamShort(from)}から${teamShort(to)}へ移籍（${formatSalary(p.salary)}・${p.contractYears}年）']);
      // 補償の金額は前年の年俸（＝ FA 宣言のときの年俸）がもと
      final prevSalary = p.prevSalary > 0 ? p.prevSalary : p.salary;
      final comp = CompCase(p.registeredName, f.rank, from.id, to.id, prevSalary, repeat: repeat);
      if (!comp.hasPick) {
        _applyComp(comp, false); // C ランク：金銭のみ（年俸の30%）
      } else if (from.id == myTeamId && !autoMode) {
        pendingComp.add(comp);
        _addNews(['補償：${p.registeredName}の移籍の補償を選んでください（フロント → 補強 → FA）']);
      } else {
        _resolveCompAuto(comp, offseasonYear);
      }
    }
    _trimTransactions();
  }

  /// 補償を自動で決める（選手を失った CPU 球団、または自動進行）：A・B は指名権＋金銭を選ぶ
  void _resolveCompAuto(CompCase c, int year) => _applyComp(c, c.hasPick);

  /// 補償を反映：獲った球団が金銭を払い、指名権（1.5位・2.5位）はリーグが元の球団に与える（次のドラフトで使う）
  void _applyComp(CompCase c, bool withPick) {
    final to = teamById(c.toTeamId), from = teamById(c.fromTeamId);
    if (to == null || from == null) return;
    final pick = withPick && c.hasPick;
    final money = c.money(pick);
    _money(to.id, 'FA 補償', -money, 'FA 補償 ${c.playerName}');
    _money(from.id, 'FA 補償', money, 'FA 補償 ${c.playerName}');
    if (pick) {
      final l = compPicks.putIfAbsent(from.id, () => [0, 0]);
      while (l.length < 2) {
        l.add(0);
      }
      l[c.rank == 'A' ? 0 : 1]++;
      transactions.insert(0, '${_today()} ${teamShort(from)} 補償 ${c.pickLabel}指名権＋${formatSalary(money)}（${c.playerName}の${teamShort(to)}への FA 移籍）');
      _addNews(['補償：${c.playerName}の移籍の補償で、${teamShort(from)}が次のドラフトの${c.pickLabel}指名権と${formatSalary(money)}を得ました']);
    } else {
      transactions.insert(0, '${_today()} ${teamShort(from)} 補償 金銭${formatSalary(money)}（${c.playerName}の${teamShort(to)}への FA 移籍）');
      _addNews(['補償：${c.playerName}の移籍の補償は金銭のみ（${teamShort(from)}へ${formatSalary(money)}）']);
    }
  }

  /// 自球団が補償を選ぶ（withPick：①指名権＋金銭 ／ false：②金銭のみ）
  String? resolveComp(CompCase c, bool withPick) {
    if (myTeam == null) return '球団が選ばれていません';
    _applyComp(c, withPick);
    pendingComp.remove(c);
    updateAndSave();
    return null;
  }

  // ───────── 自由契約・トライアウト ─────────

  void _tryout() {
    if (freeAgents.isEmpty) return;
    final r = Random(currentDate.year * 229);
    var n = 0;
    final cpu = leagueTeams.where((t) => t.id != myTeamId).toList()..shuffle(r);
    for (final t in cpu) {
      var signed = 0;
      final pool = List.of(freeAgents)..sort((a, b) => RosterEngine.value(b.player).compareTo(RosterEngine.value(a.player)));
      for (final fa in pool) {
        if (signed >= 2) break;
        final v = cpuValue(t, fa.player);
        if (fa.fromTeamId == t.id) continue;
        if (RosterEngine.cpuRoom(t) > 0 && v >= 55 + RosterEngine.need(t, fa.player.mainPosition) * -5 && r.nextDouble() < 0.5) {
          _signFa(fa, t, ikusei: false);
          signed++;
          n++;
        } else if (fa.player.age <= 24 && v >= 50 && RosterEngine.ikuseiCount(t) < ikuseiTarget(t) && r.nextDouble() < 0.3) {
          _signFa(fa, t, ikusei: true);
          signed++;
          n++;
        }
      }
    }
    _addNews(['${currentDate.month == 1 ? '自由契約' : 'トライアウト'}：$n人が他球団と契約。自由契約の選手は1月31日までに契約がなければ引退します']);
  }

  void _signFa(FreeAgent fa, Team t, {required bool ikusei}) {
    freeAgents.remove(fa);
    final p = fa.player;
    p.ikusei = ikusei;
    p.ikuseiYears = 0;
    if (ikusei) p.salary = min(p.salary, 600);
    p.contractYears = 1;
    final from = teamById(fa.fromTeamId);
    if (from != null) midSeasonMove(p, from, t);
    logMove(p, ikusei ? '自由契約から育成契約' : '自由契約から入団', from, t);
    RosterEngine.addPlayer(t, p);
    transactions.insert(0, '${_today()} ${teamShort(t)} ${p.registeredName}と${ikusei ? '育成' : ''}契約（自由契約・元${teamById(fa.fromTeamId) == null ? '−' : teamShort(teamById(fa.fromTeamId)!)}）');
  }

  /// 自球団が自由契約の選手と契約する
  String? signFreeAgent(FreeAgent fa, {required bool ikusei}) {
    final my = myTeam;
    if (my == null) return '球団が選ばれていません';
    if (!ikusei && RosterEngine.freeSlots(my) <= 0) return '支配下の枠（70人）が空いていません';
    if (!ikusei && !tradeOpen) return '支配下での契約は7月31日までです';
    if (ikusei && RosterEngine.ikuseiCount(my) >= ikuseiCap(my)) return '育成選手の上限（${ikuseiCap(my)}人）に達しています（設備や3軍コーチで増やせます）';
    final fe = _fundsCheck(my, ikusei ? min(fa.player.salary, 600) : fa.player.salary);
    if (fe != null) return fe;
    _signFa(fa, my, ikusei: ikusei);
    updateAndSave();
    return null;
  }

  /// 育成再契約ができる時期（シーズン終了後〜開幕前のオフ）
  bool get canReSignIkusei => seasonOver || _offPeriod(DateUtils.dateOnly(currentDate));

  /// 育成再契約：支配下の選手をいったん自由契約にして、育成選手として結び直す。育成満了（3年）の選手は育成のまま3年契約し直す。
  ///  育成枠は資金が続く限り無制限。年俸は600万円まで
  String? reSignIkusei(Player p) {
    final my = myTeam;
    if (my == null) return '球団が選ばれていません';
    if (!canReSignIkusei) return '育成再契約はオフシーズン（シーズン終了後〜開幕前）だけです';
    if (!p.ikusei && RosterEngine.ikuseiCount(my) >= ikuseiCap(my)) return '育成選手の上限（${ikuseiCap(my)}人）に達しています';
    if (!p.ikusei) {
      final pitchers = my.players.where((x) => x.isPitcher && !x.ikusei).length, fielders = my.players.where((x) => !x.isPitcher && !x.ikusei).length;
      if (p.isPitcher && pitchers <= 14) return '支配下の投手が足りなくなります';
      if (!p.isPitcher && fielders <= 12) return '支配下の野手が足りなくなります';
      RosterEngine.removePlayer(my, p);
      p.ikusei = true;
      RosterEngine.addPlayer(my, p); // 背番号は3桁になる
    }
    // 育成の年数は通算で数える（支配下に上げて戻す抜け道を防ぐ。仕様書 6.1）
    p.prevSalary = p.salary;
    p.salary = min(p.salary, 600);
    p.contractYears = 1;
    transactions.insert(0, '${_today()} ${teamShort(my)} ${p.registeredName} 育成再契約（背番号${p.uniformNumber}）');
    _addNews(['${p.registeredName}と育成選手として再契約しました（年俸${formatSalary(p.salary)}・背番号${p.uniformNumber}）']);
    updateAndSave();
    return null;
  }

  /// 戦力外通告（自由契約の一覧へ）
  String? releasePlayer(Player p) {
    final my = myTeam;
    if (my == null) return '球団が選ばれていません';
    final pitchers = my.players.where((x) => x.isPitcher).length, fielders = my.players.length - pitchers;
    if (p.isPitcher && pitchers <= 14) return '投手が足りなくなります';
    if (!p.isPitcher && fielders <= 12) return '野手が足りなくなります';
    RosterEngine.removePlayer(my, p);
    freeAgents.add(FreeAgent(p, my.id, p.ikusei ? '育成満了' : '戦力外'));
    transactions.insert(0, '${_today()} ${teamShort(my)} ${p.registeredName} 戦力外通告');
    _addNews(['${p.registeredName}に戦力外を通告しました']);
    updateAndSave();
    return null;
  }

  /// 育成選手を支配下に登録する（背番号は2桁に）
  String? promoteIkusei(Player p) {
    final my = myTeam;
    if (my == null || !p.ikusei) return null;
    if (RosterEngine.freeSlots(my) <= 0) return '支配下の枠（70人）が空いていません';
    if (!tradeOpen) return '支配下登録は7月31日までです';
    p.ikusei = false;
    p.uniformNumber = RosterEngine.freeNumber(my, ikusei: false);
    p.salary = max(p.salary, 450);
    transactions.insert(0, '${_today()} ${teamShort(my)} ${p.registeredName} 支配下登録（背番号${p.uniformNumber}）');
    _addNews(['${p.registeredName}を支配下登録しました（背番号${p.uniformNumber}）']);
    updateAndSave();
    return null;
  }

  void _cpuIkuseiPromote() {
    for (final t in leagueTeams.where((t) => t.id != myTeamId)) {
      final sh = t.players.where((p) => !p.ikusei && !p.foreignSlot).toList()..sort((a, b) => a.ovr.compareTo(b.ovr));
      final weakest = sh.isEmpty ? 0 : sh.first.ovr;
      for (final p in t.players.where((p) => p.ikusei).toList()..sort((a, b) => b.ovr.compareTo(a.ovr))) {
        if (RosterEngine.cpuRoom(t) <= 0 || p.ovr < weakest + 4) break;
        p.ikusei = false;
        p.uniformNumber = RosterEngine.freeNumber(t, ikusei: false);
        p.salary = max(p.salary, 450);
        transactions.insert(0, '${_today()} ${teamShort(t)} ${p.registeredName} 支配下登録');
      }
    }
  }

  // ───────── 契約更改 ─────────

  void _contractRenewal() {
    final moved = faCases.map((f) => f.playerId).toSet(); // FA 宣言した選手（交渉中も含む）は契約更改の対象外
    final y = currentDate.year;
    final notes = <String>[];
    var before = 0, after = 0;
    for (final t in leagueTeams) {
      for (final p in t.players) {
        if (moved.contains(p.id) || p.draftYear == y) continue;
        if (t.id == myTeamId && renewSigned.contains(p.id)) continue; // 11月に更改が済んだ（年数もそのとき決めた）
        final old = p.salary;
        TransferEngine.renewSalary(p);
        if (t.id == myTeamId) {
          before += old;
          after += p.salary;
          if (old > 0 && (p.salary - old).abs() >= max(1000, old * 0.3)) notes.add('${p.registeredName} ${formatSalary(old)}→${formatSalary(p.salary)}');
        }
      }
    }
    _addNews(['契約更改：自球団の年俸総額 ${formatSalary(before)} → ${formatSalary(after)}${notes.isNotEmpty ? '（${notes.take(5).join('、')}）' : ''}（11月に更改しなかった選手は希望額で）']);
    renewSigned = {};
    renewTries = {};
  }

  // ───────── 外国人選手 ─────────

  void _cpuForeignDepart() {
    for (final t in leagueTeams.where((t) => t.id != myTeamId)) {
      for (final p in t.players.where((p) => p.foreignSlot && (p.ovr < 56 || p.age >= 36)).toList()) {
        RosterEngine.removePlayer(t, p);
        _leaveToOther(p, teamShort(t), '退団', Random(p.id.hashCode));
        transactions.insert(0, '${_today()} ${teamShort(t)} ${p.registeredName} 退団（帰国）');
      }
    }
  }

  void _cpuForeignSign() {
    final r = Random(currentDate.year * 233);
    for (final t in leagueTeams.where((t) => t.id != myTeamId).toList()..shuffle(r)) {
      var signed = 0;
      final eye = scoutEye(t);
      while (signed < 2 && foreignPool.any((p) => !p.ikusei) && RosterEngine.cpuRoom(t) > 0 && finOf(t).funds > 0) {
        final foreign = t.players.where((p) => p.foreignSlot && !p.ikusei).length;
        if (foreign >= (LeagueRules.foreign1G ?? 7) || r.nextDouble() > (foreign <= 2 ? 0.8 : 0.35)) break;
        // CPU 球団もスカウトの見立て（適応力の幅）で入団後の力を見積もる
        final cands = foreignPool.where((p) => !p.ikusei).toList()
          ..sort((a, b) => (ForeignEngine.perceivedOvr(b, eye) + RosterEngine.need(t, b.mainPosition) * 8).compareTo(ForeignEngine.perceivedOvr(a, eye) + RosterEngine.need(t, a.mainPosition) * 8));
        final p = cands.first;
        foreignPool.remove(p);
        _removeFromOther(p.id);
        ForeignEngine.applyAdapt(p);
        p.offJoin = offseasonYear;
        RosterEngine.addPlayer(t, p);
        transactions.insert(0, '${_today()} ${teamShort(t)} ${p.registeredName}（外国人・${p.mainPosition}）と契約（${formatSalary(p.salary)}）');
        signed++;
      }
      // 育成の外国人：才能の見立てが高い若手を時々獲る
      if (RosterEngine.ikuseiCount(t) < ikuseiTarget(t) && r.nextDouble() < 0.3) {
        final ik = foreignPool.where((p) => p.ikusei).toList()
          ..sort((a, b) {
            final va = ForeignEngine.view(a, eye, currentDate.year), vb = ForeignEngine.view(b, eye, currentDate.year);
            return (vb.talentLo! + vb.talentHi!).compareTo(va.talentLo! + va.talentHi!);
          });
        if (ik.isNotEmpty) {
          final p = ik.first;
          foreignPool.remove(p);
          _removeFromOther(p.id);
          RosterEngine.addPlayer(t, p);
          transactions.insert(0, '${_today()} ${teamShort(t)} ${p.registeredName}（外国人・育成・${p.mainPosition}）と契約');
        }
      }
    }
  }

  /// 自球団が外国人選手と契約する
  String? signForeign(Player p) {
    final my = myTeam;
    if (my == null) return '球団が選ばれていません';
    if (p.ikusei) {
    } else {
      if (RosterEngine.freeSlots(my) <= 0) return '支配下の枠（70人）が空いていません';
      if (!tradeOpen) return '7月31日を過ぎると契約できません';
    }
    final fe = _fundsCheck(my, p.salary);
    if (fe != null) return fe;
    foreignPool.remove(p);
    _removeFromOther(p.id);
    if (!p.ikusei) ForeignEngine.applyAdapt(p); // 環境への適応：入団前の能力に倍率がかかる
    p.offJoin = offseasonYear;
    RosterEngine.addPlayer(my, p);
    transactions.insert(0, '${_today()} ${teamShort(my)} ${p.registeredName}（外国人・${p.ikusei ? '育成・' : ''}${p.mainPosition}）と契約（${formatSalary(p.salary)}）');
    _addNews(['${p.registeredName}と契約しました（${formatSalary(p.salary)}）']);
    updateAndSave();
    return null;
  }

  // ───────── トレード ─────────

  /// シーズン途中の移籍の成績：同じリーグなら合算（前の球団を seasonTeams に残す）。
  ///  他リーグへ移ったら、それまでの成績を seasonSplits に分け、今季成績は0から（タイトル・規定もそのリーグの分だけ）
  /// 移籍の歩みを選手に残す（経歴タブ）
  void logMove(Player p, String how, Team? from, Team to) {
    final d = currentDate;
    p.moves.add('${d.year}年${d.month}月${d.day}日 $howで${teamShort(to)}へ${from == null ? '' : '（←${teamShort(from)}）'}');
  }

  void midSeasonMove(Player p, Team from, Team to) {
    if (seasonFinished || from.id == to.id) return;
    if (p.seasonStats.games + p.farmStats.games == 0 && p.seasonTeams.isEmpty) return;
    // 前の球団での分（スコアラーの球団別の成績）：今季成績から、その球団に来たときの分を引いたもの
    final ps = seasonPortion(p), pf = seasonPortion(p, farm: true);
    if (ps.games + ps.pitchApps + pf.games + pf.pitchApps > 0) p.seasonParts.add({'team': from.id, 'stats': ps.toJson(), 'farm': pf.toJson()});
    if (from.league == to.league) {
      if (p.seasonTeams.isEmpty || p.seasonTeams.last != from.id) p.seasonTeams.add(from.id);
      p.partBase = {'stats': p.seasonStats.toJson(), 'farm': p.farmStats.toJson()};
      return;
    }
    p.partBase = {};
    p.seasonSplits.add({
      'team': [...p.seasonTeams, from.id].join('/'),
      'stats': p.seasonStats.toJson(),
      'farm': p.farmStats.toJson(),
    });
    p.seasonTeams = [];
    p.seasonStats = PlayerStats();
    p.farmStats = PlayerStats();
    p.thirdStats = PlayerStats();
  }


  /// トレードを申し込む。成立すれば null、断られたら理由
  /// トレードの成功確率（相手の監督の判断力で見た釣り合いから）
  double tradeChance(Team partner, List<Player> give, List<Player> get, int money, {List<int> giveRounds = const [], List<int> getRounds = const []}) {
    if (give.isEmpty && get.isEmpty && giveRounds.isEmpty && getRounds.isEmpty) return 0;
    final (eye, pot) = cpuEval(partner);
    return TransferEngine.tradeChance(TransferEngine.tradeRatio(partner, give, get, money, eye: eye, potential: pot, mood: tradeMood(partner), giveRounds: giveRounds, getRounds: getRounds));
  }

  // ───────── CPU 球団の方針（仕様書 9章-1）─────────

  /// 球団の方針（優勝を狙う／中間／再建中）。なければ今の戦力と成績から決める
  String policyOf(Team t) => teamPolicy[t.id] ??= _decidePolicy(t);

  /// 方針を決める：主力15人の力（リーグの中での高さ）・前年（シーズン中は今季）の順位・主力の年齢
  String _decidePolicy(Team t) {
    double coreOvr(Team x) {
      final l = x.players.where((p) => !p.ikusei).map((p) => p.ovr).toList()..sort((a, b) => b.compareTo(a));
      final c = l.take(15);
      return c.isEmpty ? 50 : c.reduce((a, b) => a + b) / c.length;
    }

    final avg = teams.map(coreOvr).reduce((a, b) => a + b) / teams.length;
    final core = (t.players.where((p) => !p.ikusei).toList()..sort((a, b) => b.ovr.compareTo(a.ovr))).take(15).toList();
    final age = core.isEmpty ? 28.0 : core.map((p) => p.age).reduce((a, b) => a + b) / core.length;
    int? rank = lastRankOf[t.id];
    if (t.wins + t.losses >= 40) {
      final st = computeStandings(teams, matches, t.league, StandingsKind.official);
      final i = st.indexWhere((r) => r.team.id == t.id);
      if (i >= 0) rank = i + 1;
    }
    // 主力の力はリーグの中のばらつき（標準偏差）で比べる（能力の基準が変わっても、強い球団・弱い球団に分かれるように）
    final cores = teams.map(coreOvr).toList();
    final sd = sqrt(cores.map((c) => (c - avg) * (c - avg)).reduce((a, b) => a + b) / cores.length);
    final s = (coreOvr(t) - avg) / max(1.0, sd) * 0.75 + (rank == null ? 0 : (3.5 - rank) / 2.5) - max(0.0, age - 30) * 0.35;
    return s >= 0.6 ? 'contend' : (s <= -0.6 ? 'rebuild' : 'middle');
  }

  /// 方針の見直し（シーズン終了・7月1日）。変わった CPU 球団はお知らせ
  void reviewPolicies() {
    final changed = <String>[];
    for (final t in leagueTeams) {
      final before = teamPolicy[t.id];
      final now = _decidePolicy(t);
      teamPolicy[t.id] = now;
      if (before != null && before != now && t.id != myTeamId) changed.add('${teamShort(t)}は${TransferEngine.policyLabels[now]}');
    }
    if (changed.isNotEmpty) _addNews(['球団の方針：${changed.join('、')}に切り替えました']);
  }

  /// 指名権の持ち主（次のドラフトの round 位、元の球団 orig）
  String pickOwnerOf(int round, String orig) => pickOwner['$round|$orig'] ?? orig;

  /// 球団が持っている、トレードできる指名権（[巡, 元の球団]）
  List<(int, String)> tradablePicks(Team t) => [
        for (final rd in TransferEngine.tradableRounds)
          for (final o in teams)
            if (pickOwnerOf(rd, o.id) == t.id) (rd, o.id),
      ];

  /// 球団の今の事情：順位・ゲーム差から「目先の結果がほしい度合い」と、ベンチに足りない役割
  ///  公式戦が20試合を過ぎてから。トレード期限（7月）が近いほど強くなる。実績重視の監督はさらに目先を追う
  TradeMood tradeMood(Team t) {
    var w = 0.0;
    if (t.wins + t.losses >= 20) {
      final st = computeStandings(teams, matches, t.league, StandingsKind.official);
      final i = st.indexWhere((r) => r.team.id == t.id);
      if (i >= 0) {
        final r = st[i], top = st.first;
        final gb = ((top.w - r.w) - (top.l - r.l)) / 2;
        if (gb <= 3) {
          w = 1.0;
        } else if (gb <= 6) {
          w = 0.6;
        } else if (gb <= 10) {
          w = 0.25;
        } else if (i >= st.length - 2) {
          w = -0.8;
        }
        if (currentDate.month == 7) w *= 1.2;
        final pot = cpuEval(t).$2;
        if (w > 0) w += (50 - pot) / 200; // 実績重視の監督ほど目先を追う
        w = w.clamp(-1.0, 1.0);
      }
    }
    // ベンチに足りない役割（1軍のスタメン以外の野手・先発以外の投手）
    final pmap = {for (final p in t.players) p.id: p};
    final starters = t.lineup.map((l) => l.playerId).toSet();
    final bench = t.roster1G.map((id) => pmap[id]).whereType<Player>().where((p) => !p.isPitcher && !starters.contains(p.id)).toList();
    final pen = t.roster1G.map((id) => pmap[id]).whereType<Player>().where((p) => p.isPitcher && !t.rotation.contains(p.id)).toList();
    final roles = <String>{
      if (!bench.any((p) => p.clutch >= 68 && (p.bats == 'R' || p.bats == 'S'))) 'rhPH',
      if (!bench.any((p) => p.clutch >= 68 && (p.bats == 'L' || p.bats == 'S'))) 'lhPH',
      if (pen.where((p) => p.throws == 'L').length < 2) 'lhRP',
    };
    // 球団の方針を土台にする（シーズン中は順位の事情を足す）
    final base = switch (policyOf(t)) { 'contend' => 0.4, 'rebuild' => -0.5, _ => 0.0 };
    w = (t.wins + t.losses >= 20 ? w + base * 0.5 : base).clamp(-1.0, 1.0);
    return TradeMood(winNow: w, roles: w > 0 ? roles : const {}); // 役割を探すのは勝ちにいく球団だけ
  }

  /// 同じ球団とトレードできるまでの日数（続けて同じ球団の弱みを突けないように。14日あける）
  int tradeWait(Team partner) {
    final d = DateTime.tryParse(lastTradeWith[partner.id] ?? '');
    if (d == null) return 0;
    return max(0, 14 - currentDate.difference(d).inDays);
  }

  String? proposeTrade(Team partner, List<Player> give, List<Player> get, int money, {List<(int, String)> givePicks = const [], List<(int, String)> getPicks = const []}) {
    final my = myTeam;
    if (my == null) return '球団が選ばれていません';
    if (!tradeOpen) return 'トレードの期限（7月31日）を過ぎています';
    if (give.isEmpty && get.isEmpty && givePicks.isEmpty && getPicks.isEmpty) return '選手か指名権を選んでください';
    if (give.length > 4 || get.length > 4) return '最大4人対4人までです';
    final wait = tradeWait(partner);
    if (wait > 0) return '${teamShort(partner)}とは、あと$wait日たたないとトレードできません';
    if (givePicks.any((x) => pickOwnerOf(x.$1, x.$2) != my.id) || getPicks.any((x) => pickOwnerOf(x.$1, x.$2) != partner.id)) return '持っていない指名権が入っています';
    if ([...give, ...get].any((p) => p.ikusei) && ![...give, ...get].every((p) => p.ikusei)) return '育成選手は、育成選手同士でしかトレードできません';
    final shGive = give.where((p) => !p.ikusei).length, shGet = get.where((p) => !p.ikusei).length;
    if (RosterEngine.shihaikaCount(my) - shGive + shGet > RosterEngine.maxShihaika) return '自球団の支配下が70人を超えます';
    if (RosterEngine.shihaikaCount(partner) - shGet + shGive > RosterEngine.maxShihaika) return '相手の支配下が70人を超えます';
    if (money > 0) {
      final fe = _fundsCheck(my, money);
      if (fe != null) return fe;
    }
    final chance = tradeChance(partner, give, get, money, giveRounds: [for (final x in givePicks) x.$1], getRounds: [for (final x in getPicks) x.$1]);
    // 同じ週に同じ条件で申し込み直しても結果は変わらない（週・相手・選手・指名権・金銭で決まる乱数）
    final ids = [...give.map((p) => p.id), ...givePicks.map((x) => '${x.$1}${x.$2}'), '|', ...get.map((p) => p.id), ...getPicks.map((x) => '${x.$1}${x.$2}')].join(',');
    final roll = Random(Object.hash(partner.id, ids, money, currentDate.difference(DateTime(2000)).inDays ~/ 7)).nextDouble();
    if (roll >= chance) return '断られました（成功確率${(chance * 100).round()}%）';
    _doTrade(my, partner, give, get, money, aPicks: givePicks, bPicks: getPicks);
    lastTradeWith[partner.id] = currentDate.toIso8601String();
    updateAndSave();
    return null;
  }

  /// 指名権の名前「2027年 東新の3位」
  String pickName((int, String) x) {
    final t = teamById(x.$2);
    final y = prospects.isNotEmpty ? prospects.first.year : currentDate.year;
    return '$y年 ${t == null ? '' : teamShort(t)}の${x.$1}位';
  }

  void _doTrade(Team a, Team b, List<Player> aGive, List<Player> bGive, int money, {List<(int, String)> aPicks = const [], List<(int, String)> bPicks = const []}) {
    for (final x in aPicks) {
      pickOwner['${x.$1}|${x.$2}'] = b.id;
    }
    for (final x in bPicks) {
      pickOwner['${x.$1}|${x.$2}'] = a.id;
    }
    pickOwner.removeWhere((k, v) => k.endsWith('|$v')); // 元の球団に戻った指名権は記録しない
    for (final p in aGive) {
      midSeasonMove(p, a, b);
      logMove(p, 'トレード', a, b);
    }
    for (final p in bGive) {
      midSeasonMove(p, b, a);
      logMove(p, 'トレード', b, a);
    }
    for (final p in aGive) {
      RosterEngine.removePlayer(a, p);
    }
    for (final p in bGive) {
      RosterEngine.removePlayer(b, p);
    }
    for (final p in aGive) {
      RosterEngine.addPlayer(b, p);
    }
    for (final p in bGive) {
      RosterEngine.addPlayer(a, p);
    }
    if (money != 0) {
      _money(a.id, 'トレード', -money, 'トレード');
      _money(b.id, 'トレード', money, 'トレード');
    }
    String names(List<Player> ps, List<(int, String)> pk) {
      final l = [...ps.map((p) => p.registeredName), ...pk.map(pickName)];
      return l.isEmpty ? '金銭' : l.join('・');
    }
    transactions.insert(0, '${_today()} トレード ${teamShort(a)}：${names(aGive, aPicks)} ⇄ ${teamShort(b)}：${names(bGive, bPicks)}${money != 0 ? '（${formatSalary(money.abs())}）' : ''}');
    _addNews(['トレード成立：${teamShort(a)}の${names(aGive, aPicks)}と${teamShort(b)}の${names(bGive, bPicks)}${money > 0 ? '＋${formatSalary(money)}' : ''}']);
    for (final t in [a, b]) {
      if (t.id != myTeamId) {
        final (skill, youth) = _cpuSkill(t);
        RosterEngine.cpuReassign(t, skill: skill, youth: youth, devBonus: (p) => firstDevBonus(t, p));
      }
    }
    _trimTransactions();
  }

  /// CPU 同士のトレード（足りない位置を、余っている球団から、釣り合う選手と交換）
  void _cpuTrades(Random r) {
    final cpu = leagueTeams.where((t) => t.id != myTeamId).toList();
    if (cpu.length < 2) return;
    for (var attempt = 0; attempt < 6; attempt++) {
      final a = cpu[r.nextInt(cpu.length)];
      final b = cpu[r.nextInt(cpu.length)];
      if (a == b) continue;
      final aNeed = RosterEngine.posNames.followedBy(['投手']).reduce((x, y) => RosterEngine.need(a, x) >= RosterEngine.need(a, y) ? x : y);
      final bNeed = RosterEngine.posNames.followedBy(['投手']).reduce((x, y) => RosterEngine.need(b, x) >= RosterEngine.need(b, y) ? x : y);
      if (aNeed == bNeed || RosterEngine.need(a, aNeed) < 0.25 || RosterEngine.need(b, bNeed) < 0.25) continue;
      final fromB = b.players.where((p) => !p.ikusei && p.mainPosition == aNeed && !p.foreignSlot).toList()..sort((x, y) => RosterEngine.value(y).compareTo(RosterEngine.value(x)));
      final fromA = a.players.where((p) => !p.ikusei && p.mainPosition == bNeed && !p.foreignSlot).toList()..sort((x, y) => RosterEngine.value(y).compareTo(RosterEngine.value(x)));
      if (fromB.length < 2 || fromA.length < 2) continue;
      // 主力（各位置の1番手）は出さない
      final x = fromA[1 + r.nextInt(fromA.length - 1)];
      Player? y;
      for (final c in fromB.skip(1)) {
        final ratio = RosterEngine.tradeValue(c, eye: _cpuSkill(a).$1, viewer: a.id) / RosterEngine.tradeValue(x, eye: _cpuSkill(b).$1, viewer: b.id);
        if (ratio > 0.8 && ratio < 1.25) {
          y = c;
          break;
        }
      }
      if (y == null) continue;
      _doTrade(a, b, [x], [y], 0);
      return;
    }
  }

  // ───────── 1月1日 ─────────

  /// 年度更新の前に：FA の記録を片付ける（自由契約の選手は1月31日まで契約できる）
  void _newYearCleanup() {
    faCases = [];
  }

  /// 2月1日：契約できなかった自由契約の選手は引退（OB へ）
  void _retireFreeAgents() {
    final year = startYear - 1; // 最後にプレーしたシーズン
    final r = Random(startYear * 3571);
    var moved = 0;
    for (final fa in List.of(freeAgents)) {
      final from = teamById(fa.fromTeamId);
      if (_leaveToOther(fa.player, from == null ? '' : teamShort(from), fa.reason, r)) {
        freeAgents.remove(fa);
        moved++;
        continue;
      }
      if (from != null) _keepRetiree(fa.player, from, year);
      if (fa.player.nationality != '海外' && fa.player.career.games >= 50) coaches.add(TransferEngine.obFromPlayer(fa.player, fa.fromTeamId, r));
    }
    if (freeAgents.isNotEmpty) _addNews(['自由契約の${freeAgents.length}人が引退しました']);
    if (moved > 0) _addNews(['自由契約の$moved人が、独立リーグや海外のリーグへ移りました（他リーグ調査の「元NPB」で追えます）']);
    freeAgents = [];
    _trimOb();
  }
}
