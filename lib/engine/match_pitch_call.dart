part of 'match_simulator.dart';

/// 配球（球種と狙い所の決め方）・打者の待ち球・CPU 監督の守備の作戦
extension MatchPitchCall on MatchSimulator {
  /// 打者の待ち球（仕様書 §1）：直球系を待つ確率で系統を選び、その中から球種の割合で1つ選ぶ
  Pitch _guessPitch(Player pitcher, BatTactic? batT, int balls, int strikes) {
    final ps = pitcher.pitches.isEmpty ? [Player.fielderStraight(pitcher.velocity)] : pitcher.pitches;
    final fast = _rand.nextDouble() < _swingRead(pitcher, batT, balls, strikes).pFast;
    var c = ps.where((x) => PitchCatalog.isFastLike(x) == fast).toList();
    if (c.isEmpty) c = ps;
    final tot = c.fold<double>(0, (s, x) => s + max(1, x.ratio));
    var r = _rand.nextDouble() * tot;
    for (final x in c) { r -= max(1, x.ratio); if (r <= 0) return x; }
    return c.last;
  }

  /// 打者の読み：投手の球種の割合・カウント・作戦から、直球系を待つ確率と予想の速さ
  SwingRead _swingRead(Player pitcher, BatTactic? batT, int balls, int strikes) {
    final ps = pitcher.pitches.isEmpty ? [Player.fielderStraight(pitcher.velocity)] : pitcher.pitches;
    var fastW = 0.0, slowW = 0.0, slowV = 0.0, slowB = 0.0, fastV = ps.first.speed.toDouble();
    for (final x in ps) {
      final w = max(1, x.ratio).toDouble();
      if (PitchCatalog.isFastLike(x)) {
        if (fastW == 0) fastV = x.speed.toDouble();
        fastW += w;
      } else {
        slowW += w;
        slowV += x.speed * w;
        slowB += x.breakLevel * w;
      }
    }
    var pf = slowW == 0 ? 1.0 : MatchSimulator.readFastBase + MatchSimulator.readFastMul * fastW / (fastW + slowW);
    pf += (balls - strikes) * 0.06; // 打者有利のカウントは直球を待つ
    if (batT == BatTactic.fastballFocus) pf = 0.85;
    if (batT == BatTactic.breakingFocus) pf = 0.25;
    final vs = slowW == 0 ? fastV - 15 : slowV / slowW;
    final drop = slowW == 0 ? 3.0 : 3.5 * (slowB / slowW) / 50;
    return SwingRead(pf.clamp(0.1, 0.95), fastV, vs, drop);
  }

  /// 次の打席の CPU の守備位置を決める（自分が攻撃中なら、打席の前に画面に見せる）
  FieldTactic prepareCpuDefense(GameSession s) {
    final st = s.state;
    final defense = st.isTop ? s.homeTeam : s.awayTeam;
    final home = !st.isTop;
    final order = home ? s.homeOrder : s.awayOrder;
    final batter = order[nextBatterSlot(s, home) % order.length];
    final skill = MatchSimulator.cpuSkill(defense.id);
    final diff = (st.homeScore - st.awayScore).abs();
    var f = FieldTactic.none;
    if (st.runner3B != null && st.outs < 2 && st.inning >= 7 && diff <= 1 && _rand.nextDouble() < 0.6) {
      f = FieldTactic.infieldIn;
    } else if (st.runner1B != null && st.outs < 2 && _rand.nextDouble() < 0.25) {
      f = FieldTactic.doublePlayShift;
    } else if (MatchSimulator.pullTendency(batter) >= 7 && _rand.nextDouble() < 0.35 + (skill - 50) * 0.01) {
      f = FieldTactic.pullShift; // 引っ張る打者には寄せる（判断力の高い監督ほど使う）
    } else if (batter.power < 50 && batter.contact >= 65 && _rand.nextDouble() < 0.15 + (skill - 50) * 0.005) {
      f = FieldTactic.oppositeShift; // 流し打ちの巧打者
    }
    s.cpuField = f;
    s.cpuFieldPa = s.paCount;
    return f;
  }

  /// 配球（捕手のサイン）：球種と狙い所を決める。
  ///  - 初めての対戦は直球で内角を攻めて意識させ、2打席目以降は外の変化球でかわす
  ///  - 先発は打者一巡するまで、比率の低い変化球を隠しておく
  ///  - ストライクは投げられても、追い込んだらボール球・見せ球を使う（球数が増える）
  ///  forced は球種を指定されたとき（狙い所だけ決める）
  PitchCall _callPitch(GameSession s, Player pitcher, Player batter, PitchTactic pitT, FieldTactic fldT, String? lastPitch, {String? forced}) {
    final st = s.state;
    final key = '${pitcher.id}|${batter.id}';
    final faced = (s.paVs[key] ?? 1) - 1; // この打席より前の対戦数
    final a = s.insideAware[key] ?? 0.0;
    final seen = s.seenPitches[key] ?? const <String>{};
    final shown = s.shownPitches[pitcher.id] ?? const <String>{};
    final bf = s.battersFaced[pitcher.id] ?? 1; // この打席を含む対戦打者数
    final isStarter = identical(pitcher, s.starterHome) || identical(pitcher, s.starterAway);
    final balls = st.balls, strikes = st.strikes;
    final ahead = strikes == 2 && balls < 3;
    final behind = balls >= 2 && balls > strikes;
    final early = strikes < 2 && balls + strikes <= 2 && !behind;
    final planInside = faced == 0;
    final pinch = (st.runner2B != null || st.runner3B != null) && strikes == 2;

    // ---- 球種 ----
    Pitch pick;
    final all = pitcher.pitches.isNotEmpty ? pitcher.pitches : [Pitch(name: 'ストレート', breakLevel: 0, angle: 90, speed: pitcher.velocity, ratio: 100, sharpness: 50, heaviness: 50)];
    final forcedPitch = forced == null ? null : all.where((p) => p.name == forced).firstOrNull;
    if (forcedPitch != null) {
      pick = forcedPitch;
    } else {
      // 打者一巡までは比率の低い変化球を隠す（ピンチでは解禁することがある）
      final hidden = <String>{};
      final breaking = all.where((p) => !MatchSimulator.isFastball(p) && p.ratio > 0).toList()..sort((x, y) => x.ratio.compareTo(y.ratio));
      if (isStarter && bf <= 9 && breaking.length >= 3 && !(pinch && _rand.nextDouble() < 0.4)) {
        for (final p in breaking.take(breaking.length >= 4 ? 2 : 1)) {
          if (!shown.contains(p.name)) hidden.add(p.name);
        }
      }
      final cands = all.where((p) => p.ratio > 0 && !hidden.contains(p.name)).toList();
      if (cands.isEmpty) cands.add(all.first);
      final weights = <double>[];
      for (final p in cands) {
        final fast = MatchSimulator.isFastball(p);
        double w = p.ratio.toDouble();
        if (early && planInside && fast) w *= 1.5;               // 初対戦は直球で内角を意識させる
        if (!planInside && !fast) w *= 1.3 + max(0.0, a) * 0.5;   // 2打席目以降は変化球でかわす
        if (ahead) w *= fast ? 0.75 : (MatchSimulator._isDrop(p) ? 1.8 : 1.45); // 追い込んだら決め球
        if (behind) w *= fast ? 1.7 : (pitcher.control >= 70 ? 0.8 : 0.55); // カウントが悪いと直球で取りにいく
        if (p.name == lastPitch) w *= 0.75;                       // 同じ球が続きすぎないように
        if (ahead && faced > 0 && !seen.contains(p.name)) w *= 1.3; // まだ見せていない球で仕留める
        if (pitT == PitchTactic.fastballMain) w *= fast ? 2.2 : 0.6;
        if (pitT == PitchTactic.breakingMain) w *= fast ? 0.45 : 1.5;
        if (pitT == PitchTactic.strikeout && ahead && !fast) w *= 1.3;
        weights.add(max(0.01, w));
      }
      final total = weights.fold(0.0, (x, y) => x + y);
      var roll = _rand.nextDouble() * total;
      pick = cands.last;
      for (var i = 0; i < cands.length; i++) {
        roll -= weights[i];
        if (roll < 0) { pick = cands[i]; break; }
      }
    }
    final fast = MatchSimulator.isFastball(pick);
    final drop = MatchSimulator._isDrop(pick);
    String note = '';
    if (!fast && bf > 9 && isStarter && !shown.contains(pick.name)) note = '（この試合初めての${pick.name}）';

    // ---- ストライクを取りにいくか（有利なカウントでは、あえてボール球を使う） ----
    double zoneP;
    if (balls >= 3) {
      zoneP = strikes == 2 ? 0.76 : 0.82;
    } else if (strikes == 2) {
      zoneP = balls == 0 ? 0.30 : (balls == 1 ? 0.40 : 0.52);
    } else if (balls == 2) {
      zoneP = 0.68;
    } else if (strikes == 1) {
      zoneP = balls == 0 ? 0.56 : 0.60;
    } else {
      zoneP = balls == 0 ? 0.62 : 0.64;
    }
    if (fldT == FieldTactic.powerGuard) zoneP -= 0.08;          // 勝負を避け、際どいコースを突く
    if (pitT == PitchTactic.groundOut) zoneP += 0.04;           // 打たせて取る：ゾーン内で勝負
    if (pitT == PitchTactic.strikeout) zoneP -= 0.02;           // 三振狙い：ボール球で振らせる
    if (pitT == PitchTactic.controlFocus) zoneP += 0.05;        // コントロール重視：ストライク先行
    if (pitT == PitchTactic.outsideFocus) zoneP -= 0.02;        // 外角中心：くさいところを突く
    if (pitT == PitchTactic.breakingMain) zoneP -= 0.03;
    if (pitT == PitchTactic.fastballMain) zoneP += 0.04;        // 直球はストライクを取りやすい        // 変化球はストライクを取りにくい
    zoneP += MatchSimulator.zoneAim;
    zoneP += max(0, pitcher.control - _lvShift - 60) * MatchSimulator.ctrlZoneK; // 制球の良い投手は、ボール球に逃げずストライクで勝負できる
    final inZone = _rand.nextDouble() < zoneP;

    // ---- コース（x は打者の内角が +） ----
    double pIn = (planInside && early) ? 0.65 : 0.40;
    if (!fast) pIn *= 0.7;
    pIn -= 0.35 * a; // 内角を意識している打者には外、外を待つ打者には内
    if (pitT == PitchTactic.insideAttack) pIn = 0.8;
    if (pitT == PitchTactic.outsideFocus) pIn = 0.15;
    pIn = pIn.clamp(0.08, 0.88);
    double sideSign() => _rand.nextDouble() < pIn ? 1.0 : -1.0;
    double x, z;
    if (inZone) {
      x = _rand.nextDouble() < 0.2 ? (_rand.nextDouble() - 0.5) * 0.8 : sideSign() * (0.35 + _rand.nextDouble() * 0.5);
      if (drop) {
        z = -0.35 - _rand.nextDouble() * 0.55;
      } else if (fast) {
        final r = _rand.nextDouble();
        z = r < 0.4 ? 0.3 + _rand.nextDouble() * 0.55 : (r < 0.85 ? -0.3 - _rand.nextDouble() * 0.55 : (_rand.nextDouble() - 0.5) * 0.6);
      } else {
        z = -0.8 + _rand.nextDouble() * 1.3;
      }
    } else if (_rand.nextDouble() < (ahead ? 0.3 : 0.45)) {
      // ゾーンの際（ボール1個ぶん外れる）
      final off = 1.0 + _rand.nextDouble() * 0.25;
      if (_rand.nextBool()) {
        x = sideSign() * off;
        z = (_rand.nextDouble() - 0.5) * 1.6;
      } else {
        x = (_rand.nextDouble() - 0.5) * 1.6;
        z = (drop || _rand.nextDouble() < 0.6) ? -off : off;
      }
    } else {
      // 釣り球・見せ球
      final off = 1.35 + _rand.nextDouble() * 0.5;
      if (drop) {
        x = (_rand.nextDouble() - 0.5) * 1.2;
        z = -off;
      } else if (!fast) {
        x = -off; // 外へ逃げる変化球
        z = -0.3 - _rand.nextDouble() * 0.8;
      } else if ((planInside || a < 0 || pitT == PitchTactic.insideAttack) && _rand.nextBool()) {
        x = off * 0.85; // 内角の見せ球で、のけぞらせる
        z = (_rand.nextDouble() - 0.3) * 1.0;
        note = '（見せ球）';
      } else {
        x = (_rand.nextDouble() - 0.5) * 1.0;
        z = off * 0.85; // 高めの釣り球
      }
    }
    return PitchCall(pick, x, z, inZone, note);
  }
}
