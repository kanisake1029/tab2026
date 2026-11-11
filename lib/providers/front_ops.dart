part of 'app_state.dart';

/// 改修2：球団施設への投資と、本拠地球場の改修（フロント）
extension FrontOps on AppState {
  /// 施設の効果を試合・回復の計算に渡す（読み込み時・投資後）。改修した球場も作っておく（試合の写しの 3D で使う）
  void _syncFacilities() {
    ConditionEngine.medicalLevel = {for (final t in teams) t.id: finOf(t).fac('medical')};
    for (final t in teams) {
      t.park;
    }
  }

  /// 施設を 1 Lv 上げる（自球団）。できなければ理由
  String? buildFacility(String key) {
    final t = myTeam;
    if (t == null) return '球団が選ばれていません';
    final f = finOf(t);
    final lv = f.fac(key);
    final cost = FacilityEngine.nextCost(key, lv);
    if (cost == null) return 'すでに最大の Lv です';
    if (f.funds < cost) return '資金が足りません（必要 ${_oku(cost)}）';
    f.add('施設投資', -cost);
    f.facilities[key] = lv + 1;
    _syncFacilities();
    final fac = FacilityEngine.byKey(key);
    _addNews(['${fac.name}を Lv${lv + 1} に改修しました（${_oku(cost)}）']);
    updateAndSave();
    return null;
  }

  static String _oku(int man) => man >= 10000 ? '${(man / 10000).toStringAsFixed(man % 10000 == 0 ? 0 : 1)}億円' : '$man万円';

  /// 球場の改修ができる時期（オフの 11 月〜2 月）で、このオフにまだ改修していない
  int get _offKey => currentDate.month >= 11 ? currentDate.year : currentDate.year - 1;
  bool get parkWorkSeason => currentDate.month >= 11 || currentDate.month <= 2;
  bool get parkWorkDone => (myTeam?.parkWorkYear ?? 0) == _offKey;

  /// 改修の状態：テラスがある・高いフェンス・芝
  bool hasTerrace(Team t) => t.park.oldFence > 0;
  bool hasWall(Team t) => t.parkMods['wall'] == true;

  /// 本拠地球場の改修（オフに 1 回）。key：terrace（新設・撤去）・wall（高く・戻す）・turf（張り替え）
  String? doParkWork(String key) {
    final t = myTeam;
    if (t == null) return '球団が選ばれていません';
    if (!parkWorkSeason) return '球場の改修はオフ（11月〜2月）だけです';
    if (parkWorkDone) return 'このオフはもう改修しました（次のオフまで待ってください）';
    final f = finOf(t);
    final base = Stadium.byId(t.homeStadium);
    final mods = Map<String, dynamic>.from(t.parkMods);
    String what;
    var removing = false;
    switch (key) {
      case 'terrace':
        if (hasTerrace(t)) {
          removing = true;
          if (base.oldFence > 0) {
            mods['terrace'] = false; // もとからのテラスを撤去
          } else {
            mods.remove('terrace');
          }
          what = 'ホームランテラスを撤去（フェンスを元の位置・高さに戻す）';
        } else {
          if (base.oldFence > 0) {
            mods.remove('terrace'); // 撤去していたテラスを戻す
          } else {
            mods['terrace'] = true;
          }
          what = 'ホームランテラスを新設（左右中間を最大3m前へ・フェンス2.5m）';
        }
      case 'wall':
        if (hasWall(t)) {
          removing = true;
          mods.remove('wall');
          what = 'フェンスの高さを元に戻す';
        } else {
          mods['wall'] = true;
          what = 'フェンスを1.5m高くする（モンスターウォール）';
        }
      case 'turf':
        final now = t.park.turf;
        final to = now == '天然芝' ? '人工芝' : '天然芝';
        if (to == base.turf) {
          mods.remove('turf');
        } else {
          mods['turf'] = to;
        }
        what = '芝を$nowから$toに張り替え';
      default:
        return '不明な改修です';
    }
    final cost = FacilityEngine.parkCost(key, removing: removing);
    if (f.funds < cost) return '資金が足りません（必要 ${_oku(cost)}）';
    f.add('球場改修', -cost);
    t.parkMods = mods;
    t.parkWorkYear = _offKey;
    _syncFacilities();
    _addNews(['本拠地 ${base.name}：$what（${_oku(cost)}）']);
    updateAndSave();
    return null;
  }

  /// CPU 球団の施設投資（12月1日）：資金に余裕があれば、いちばん安い次の Lv を 1 つ
  void _cpuInvest(DateTime d) {
    for (final t in teams) {
      if (t.id == myTeamId) continue;
      final f = finOf(t);
      if (f.funds < 1200000) continue; // 120億円より多いときだけ
      String? best;
      int bestCost = 1 << 30;
      for (final fac in FacilityEngine.all) {
        final c = FacilityEngine.nextCost(fac.key, f.fac(fac.key));
        if (c != null && c < bestCost) {
          best = fac.key;
          bestCost = c;
        }
      }
      if (best == null || f.funds - bestCost < 800000) continue;
      f.add('施設投資', -bestCost);
      f.facilities[best] = f.fac(best) + 1;
    }
    _syncFacilities();
  }
}

/// 改修3：キャンプでのコーチからの用具・フォーム改造の提案と、用具メーカーとのアドバイザリー契約
extension EquipOps on AppState {
  static const maxMakerDeals = 2;

  /// コーチの名前（いなければ役職だけ）
  String _coachName(Team t, String role) {
    final c = staffOf(t)[role];
    return c == null ? '$roleコーチ' : '$roleコーチ ${c.name}';
  }

  /// キャンプの提案を作る（自球団。春は 1/1・1/16、秋は 11/1・11/16）。成績（今季＋通算）と能力から、効きそうなものを最大 3 件
  void _makeProposals({required bool spring}) {
    final t = myTeam;
    if (t == null) return;
    final ids = (spring ? t.springCamp : t.autumnCamp).toSet();
    final pool = t.players.where((p) => ids.isEmpty || ids.contains(p.id)).toList()..shuffle(Random(currentDate.millisecondsSinceEpoch));
    final already = {for (final c in campProposals) c['player']};
    final out = <Map<String, dynamic>>[];
    void add(Player p, String kind, String role, String text) {
      if (out.length >= 3 || already.contains(p.id) || out.any((o) => o['player'] == p.id)) return;
      out.add({'id': '${currentDate.millisecondsSinceEpoch}_${p.id}', 'player': p.id, 'kind': kind, 'coach': _coachName(t, role), 'text': text, 'date': '${currentDate.month}/${currentDate.day}'});
    }

    for (final p in pool) {
      final s = p.seasonStats, c = p.career;
      final pa = s.plateAppearances + c.plateAppearances;
      final kRate = pa == 0 ? 0.0 : (s.strikeouts + c.strikeouts) / pa;
      final hrRate = pa == 0 ? 0.0 : (s.homeRuns + c.homeRuns) / pa;
      final contact = (p.contactLeft + p.contactRight) / 2;
      if (p.canBat && !p.isPitcher) {
        final b = p.bat;
        if ((pa >= 150 ? kRate > 0.22 : contact < 52 && p.eye < 55) && b.balance != 'カウンター') {
          add(p, 'bat_short', '打撃', '${p.registeredName}は三振が多い（三振率${pa >= 150 ? '${(kRate * 100).round()}%' : '高め'}）ため、バットを短め・軽め・カウンターバランス（振り出しが軽い）に変えて、ミートの追従性を上げませんか？');
        } else if (p.power >= 65 && (pa < 150 || hrRate < 0.03) && b.balance != 'トップ' && b.weight < 940) {
          add(p, 'bat_top', '打撃', '${p.registeredName}の長打力を伸ばすため、重めのトップバランスのバットに変えて、当たり負けしない（芯の有効質量が大きい）打球を打たせませんか？');
        }
        final pos = p.mainPosition;
        final g = p.glove;
        if ((pos == '二塁手' || pos == '遊撃手') && (g.pocket != '浅い' || g.length > 29)) {
          add(p, 'glove_small', '守備走塁', '二遊間の併殺完成率を上げるため、${p.registeredName}のグラブを浅い小型モデルに変えませんか？（握り替えが約0.05秒速く、捕れる範囲は約2cm狭くなる）');
        }
      }
      if (p.isPitcher) {
        final outs = s.inningsPitched + c.inningsPitched, h = s.hitsAllowed + c.hitsAllowed;
        final opp = outs + h == 0 ? 0.0 : h / (outs + h);
        if (outs >= 150 ? opp > 0.27 : p.pitchPower < 55) {
          if (p.spinAxis <= 70) {
            add(p, 'arm_lower', '投手', '${p.registeredName}の被打率${outs >= 150 ? '（.${(opp * 1000).round()}）' : ''}を下げるため、腕の角度を15°下げてサイドスロー気味に改造し、横の変化で打者の目線をずらしませんか？');
          } else if (p.form.rubberPos < 15) {
            add(p, 'rubber_3b', '投手', '${p.registeredName}のプレートを踏む位置を三塁側へ変えて、打者から見た角度をつけませんか？');
          }
        }
      }
    }
    if (out.isEmpty) return;
    campProposals.addAll(out);
    _addNews(['${spring ? '春季' : '秋季'}キャンプ：コーチから用具・フォームの改造の提案が${out.length}件あります（チーム → キャンプ）']);
  }

  /// 提案を受ける（true）・断る（false）
  String? answerProposal(String id, bool accept) {
    final i = campProposals.indexWhere((c) => c['id'] == id);
    if (i < 0) return '提案が見つかりません';
    final c = campProposals.removeAt(i);
    final p = myTeam?.players.where((x) => x.id == c['player']).firstOrNull;
    if (p == null) {
      updateAndSave();
      return '選手がいません';
    }
    if (accept) {
      final b = p.bat, g = p.glove;
      switch (c['kind']) {
        case 'bat_short':
          p.batSet = Bat(length: max(82, b.length - 1), weight: max(850, b.weight - 20), balance: 'カウンター', choke: b.choke, finish: b.finish, maker: b.maker);
        case 'bat_top':
          p.batSet = Bat(length: b.length, weight: min(950, b.weight + 25), balance: 'トップ', choke: b.choke, finish: b.finish, maker: b.maker);
        case 'glove_small':
          p.gloveSet = Glove(length: 28.5, pocket: '浅い', color: g.color, lace: g.lace, web: g.web, maker: g.maker);
        case 'arm_lower':
          p.spinAxis = min(150, p.spinAxis + 15);
        case 'rubber_3b':
          final f = p.form.copy();
          f.rubberPos = 20;
          p.formSet = f;
      }
      _addNews(['${p.registeredName}：${c['coach']}の提案で改造しました']);
    }
    updateAndSave();
    return null;
  }

  // ───── メーカー契約 ─────
  /// 自球団の 1 軍で、そのメーカーのバットかグラブを使っている選手の数
  int makerUsers(Team t, String maker) => t.players.where((p) => t.roster1G.contains(p.id) && (p.bat.maker == maker || p.glove.maker == maker)).length;

  /// 年間の契約金（球団へ。使っている選手が多いほど高い）
  int makerFee(Team t, String maker) => 3000 + makerUsers(t, maker) * 400;

  String? toggleMakerDeal(String maker) {
    final t = myTeam;
    if (t == null) return '球団が選ばれていません';
    final f = finOf(t);
    if (f.makerDeals.contains(maker)) {
      f.makerDeals.remove(maker);
      updateAndSave();
      return null;
    }
    if (f.makerDeals.length >= maxMakerDeals) return 'アドバイザリー契約は$maxMakerDeals社までです';
    f.makerDeals.add(maker);
    _addNews(['$makerとアドバイザリー契約を結びました（年${makerFee(t, maker)}万円）']);
    updateAndSave();
    return null;
  }

  /// 毎月：契約金の入金（12 分の 1）
  void _makerMonthly() {
    for (final t in teams) {
      final f = finOf(t);
      for (final m in f.makerDeals) {
        f.add('メーカー契約', (makerFee(t, m) / 12).round());
      }
    }
  }

  /// 表彰が決まったら：契約メーカーの用具でタイトル・ゴールデングラブを取った自球団の選手の、コラボ・レプリカグッズの企画を用意する
  void _makerCollabsFromAwards(int year, Map<String, dynamic> awards) {
    final t = myTeam;
    if (t == null) return;
    final deals = finOf(t).makerDeals;
    if (deals.isEmpty) return;
    final byId = {for (final p in t.players) p.id: p};
    final before = makerCollabs.length;
    void check(dynamic winners, String title, {required bool glove}) {
      if (winners is! List) return;
      for (final w in winners) {
        final p = w is Map ? byId[w['id']] : null;
        if (p == null) continue;
        final maker = glove ? p.glove.maker : p.bat.maker;
        if (!deals.contains(maker)) continue;
        makerCollabs.add({'year': year, 'maker': maker, 'player': p.registeredName, 'title': title, 'item': glove ? 'グラブ' : 'バット'});
      }
    }

    final leagues = awards['leagues'];
    if (leagues is Map) {
      for (final lg in leagues.values) {
        if (lg is! Map) continue;
        for (final tt in (lg['titles'] as List? ?? const [])) {
          if (tt is! Map) continue;
          final name = '${tt['title']}';
          final bat = name.contains('打') || name.contains('盗塁') || name.contains('出塁');
          check(tt['winners'], name, glove: !bat);
        }
        for (final g in (lg['gg'] as List? ?? const [])) {
          if (g is Map) check(g['winners'], 'ゴールデングラブ（${g['pos']}）', glove: true);
        }
      }
    }
    if (makerCollabs.length > before) _addNews(['契約メーカーの用具でタイトルを取った選手のコラボグッズが企画できます（フロント → メーカー）']);
  }

  /// コラボ・レプリカグッズを企画する：人気に応じて 1〜3 億円の特別収入
  String? launchCollab(int index) {
    final t = myTeam;
    if (t == null || index < 0 || index >= makerCollabs.length) return '企画が見つかりません';
    final c = makerCollabs.removeAt(index);
    final f = finOf(t);
    final rev = (10000 + f.popularity * 200 + Random().nextInt(3000)).clamp(10000, 30000);
    f.add('メーカーコラボ', rev);
    _addNews(['${c['maker']}×${c['player']}（${c['title']}）のレプリカ${c['item']}が完売：${(rev / 10000).toStringAsFixed(1)}億円']);
    updateAndSave();
    return null;
  }
}

/// 改修5.2：衰えの見え始めたベテラン（33歳以降）のモデルチェンジ（技巧派・職人への転向）。春季キャンプの初日に判定する
extension VeteranOps on AppState {
  void _modelChanges() {
    final year = currentDate.year;
    final mine = <String>[];
    for (final t in teams) {
      final staff = staffOf(t);
      for (final p in t.players) {
        if (p.styleShift.isNotEmpty || p.age < 33) continue;
        final ph = GrowthEngine.phaseOf(p);
        if (ph != GrowthPhase.transition && ph != GrowthPhase.decline) continue;
        // 向上心が高い、または担当コーチ（投手・打撃）の指導力が高いと転向しやすい
        final coach = staff[p.isPitcher ? '投手' : '打撃'];
        final teach = coach?.trueAbil[p.isPitcher ? '制球' : '打撃'] ?? 50;
        final chance = p.ambition >= 70 ? 0.55 : (p.ambition >= 60 || teach >= 70 ? 0.3 : 0.06);
        final r = Random(p.id.hashCode ^ (year * 31));
        if (r.nextDouble() >= chance) continue;
        p.styleShiftYear = year;
        if (p.isPitcher) {
          p.styleShift = '技巧派';
          // 新しい球種を覚える（ツーシーム・カットボール・チェンジアップのうち持っていないもの）
          final learned = _learnPitch(p, r);
          p.control = min(100, p.control + 3);
          if (t.id == myTeamId) mine.add('${p.registeredName}（${p.age}歳）が技巧派へモデルチェンジ。球速の衰えを制球と変化球で補う${learned.isEmpty ? '' : '（新球種：$learned）'}');
        } else {
          p.styleShift = '職人';
          p.eye = min(100, p.eye + 3);
          p.clutch = min(100, p.clutch + 3);
          p.field1B = max(p.field1B, 70); // 一塁・三塁への転向の適性
          p.field3B = max(p.field3B, 65);
          if (t.id == myTeamId) mine.add('${p.registeredName}（${p.age}歳）が職人肌へモデルチェンジ。選球眼・勝負強さ・守備固めで生きる（一塁・三塁も守れるように）');
        }
      }
    }
    if (mine.isNotEmpty) _addNews(mine);
  }

  String _learnPitch(Player p, Random r) {
    final have = {for (final x in p.pitches) x.name};
    final cands = ['ツーシーム', 'カットボール', 'チェンジアップ'].where((n) => !have.contains(n)).toList();
    if (cands.isEmpty || p.pitches.length >= 6) return '';
    final name = cands[r.nextInt(cands.length)];
    final s = PitchCatalog.of(name);
    if (s == null) return '';
    final np = Pitch(
      name: name,
      breakLevel: ((s.bLo + s.bHi) / 2).round(),
      angle: ((s.aLo + s.aHi) / 2).round(),
      speed: p.velocity + ((s.dLo + s.dHi) / 2).round(),
      ratio: 12,
      sharpness: 55,
      heaviness: ((s.hLo + s.hHi) / 2).round(),
    );
    // 割合の合計を 100 に保つ（ほかの球種を少しずつ減らす）
    final total = p.pitches.fold<int>(0, (a, x) => a + x.ratio);
    if (total > 0) {
      for (final x in p.pitches) {
        x.ratio = max(3, (x.ratio * (100 - np.ratio) / total).round());
      }
    }
    p.pitches.add(np);
    return name;
  }
}
