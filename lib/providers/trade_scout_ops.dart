part of 'app_state.dart';

/// スカウトのトレード候補（毎月1日）：他球団で十分に使われていない、能力・才能・向上心の高い選手を、自球団の補強ポイントに合わせて選ぶ
extension TradeScoutOps on AppState {
  static const _posKeys = ['投手', '捕手', '一塁手', '二塁手', '三塁手', '遊撃手', '左翼手', '中堅手', '右翼手'];

  /// 見立ての才能・向上心（眼力が低いほどずれる。同じ選手は毎回同じ見立て）
  int _estTrait(Player p, int v, int eye, int salt) {
    final err = DraftEngine.traitError(eye);
    final b = (Random(p.id.hashCode ^ salt ^ 0x7ad3).nextDouble() * 2 - 1) * err * 0.8;
    return (v + b).round().clamp(1, 100);
  }

  /// 将来の見込み（見立ての伸びしろの6割。95まで）
  int _potShown(Player p, int eye, String viewer) => (p.ovr + RosterEngine.perceivedGain(p, eye: eye, viewer: viewer) * 0.6).round().clamp(1, 95);

  /// その守備位置で今いちばん良い選手の OVR（自球団）
  int _bestAt(Team t, String pos) => t.players.where((p) => !p.ikusei && p.mainPosition == pos).fold<int>(0, (m, p) => max(m, p.ovr));

  /// 毎月1日：トレード候補を作り直す
  void _scoutTradeTips(DateTime d) {
    final my = myTeam;
    if (my == null) return;
    final eye = scoutEye(my);
    final games = <String, int>{for (final t in teams) t.id: 0};
    for (final m in matches) {
      if (m.homeScore == null || (m.matchType != 'LEAGUE' && m.matchType != 'INTERLEAGUE')) continue;
      games[m.homeTeamId] = (games[m.homeTeamId] ?? 0) + 1;
      games[m.awayTeamId] = (games[m.awayTeamId] ?? 0) + 1;
    }
    // 補強ポイント：層の薄さ・主力の質（RosterEngine.need）
    final needs = {for (final k in _posKeys) k: RosterEngine.need(my, k)};
    final cands = <(double, Player, Team)>[];
    for (final t in teams.where((t) => t.id != my.id)) {
      final g = max(1, games[t.id] ?? 0);
      for (final p in t.players.where((p) => !p.ikusei && p.age <= 33)) {
        final s = p.seasonStats;
        // 十分に使われていない：2軍にいる、または1軍でも出番が少ない
        final in1 = t.roster1G.contains(p.id);
        // 公式戦が始まって間もない（10試合未満）ときは、2軍にいるかどうかだけで判断する
        final used = g < 10 ? true : (p.isPitcher ? s.inningsPitched / 3 >= g * (p.stamina >= 60 ? 0.5 : 0.25) : s.plateAppearances >= g * 2.2);
        if (in1 && used) continue;
        final pot = _potShown(p, eye, my.id);
        final tal = _estTrait(p, p.talent, eye, 1), amb = _estTrait(p, p.ambition, eye, 2);
        if (p.ovr < 55 && pot < 66) continue;
        final need = needs[p.mainPosition] ?? 0;
        final upgrade = max(p.ovr.toDouble(), pot * 0.85) - _bestAt(my, p.mainPosition); // 自球団の主力と比べてどれだけ上か
        final score = p.ovr * 0.5 + pot * 0.5 + (tal - 50) * 0.08 + (amb - 50) * 0.05 + need * 14 + upgrade.clamp(-10, 10) * 0.6 - max(0, p.age - 29) * 1.2;
        cands.add((score, p, t));
      }
    }
    cands.sort((a, b) => b.$1.compareTo(a.$1));
    final perTeam = <String, int>{};
    final perPos = <String, int>{};
    final picks = <Map<String, dynamic>>[];
    for (final (_, p, t) in cands) {
      if ((perTeam[t.id] ?? 0) >= 2 || (perPos[p.mainPosition] ?? 0) >= 2) continue;
      perTeam[t.id] = (perTeam[t.id] ?? 0) + 1;
      perPos[p.mainPosition] = (perPos[p.mainPosition] ?? 0) + 1;
      picks.add({'pid': p.id, 'tid': t.id, 'comment': _tipComment(p, t, my, eye, needs[p.mainPosition] ?? 0, games[t.id] ?? 0), 'date': '${d.year}/${d.month}/${d.day}'});
      if (picks.length >= 5) break;
    }
    tradeTips = picks;
    if (picks.isNotEmpty) _addNews(['スカウトからトレード候補の報告が届きました（${picks.length}人。フロント → 補強 → スカウトのおすすめ）']);
  }

  /// スカウトの寸評
  String _tipComment(Player p, Team t, Team my, int eye, double need, int g) {
    final lines = <String>[];
    final s = p.seasonStats, f = p.farmStats;
    final pos = p.mainPosition;
    if (need >= 0.5) {
      lines.add('$posは手薄で、すぐに戦力になる。');
    } else if (need >= 0.25) {
      lines.add('$posの層を厚くできる。');
    }
    final best = _bestAt(my, pos);
    if (p.ovr >= best + 3) lines.add('今いる$posの主力（OVR$best）より上の力がある。');
    if (!t.roster1G.contains(p.id)) {
      lines.add('${teamShort(t)}では2軍暮らしが続いている。');
    } else {
      lines.add(p.isPitcher ? '${teamShort(t)}では登板機会が少ない（${s.appsText}）。' : '${teamShort(t)}では出番が少ない（${s.games}試合）。');
    }
    if (p.isPitcher && f.inningsPitched >= 30) {
      lines.add('2軍で防御率${f.era.toStringAsFixed(2)}・${f.pitcherStrikeouts}奪三振。');
    } else if (!p.isPitcher && f.atBats >= 60) {
      lines.add('2軍で打率${f.battingAverage.toStringAsFixed(3).replaceFirst(RegExp(r'^0'), '')}・${f.homeRuns}本。');
    }
    // いちばんの持ち味
    final abil = p.isPitcher
        ? {'球速': p.velocityNorm, '球威': p.pitchPower, '制球': p.control, 'スタミナ': p.stamina}
        : {'ミート': p.contact, 'パワー': p.power, '走力': p.run, '守備': p.catchSkill, '肩力': p.arm};
    final top = abil.entries.reduce((a, b) => a.value >= b.value ? a : b);
    final topText = top.key == '球速' ? '${p.velocity}kmの球速' : '${top.key}${GradeUtils.getGrade(top.value)}';
    lines.add('$topTextが持ち味。');
    final tal = _estTrait(p, p.talent, eye, 1), amb = _estTrait(p, p.ambition, eye, 2);
    if (p.age <= 25 && tal >= 65 && amb >= 60) {
      lines.add('才能・向上心ともに高く、まだまだ伸びる見立て。');
    } else if (p.age <= 25 && tal >= 65) {
      lines.add('才能は高い。環境が変われば化けるかもしれない。');
    } else if (amb >= 70) {
      lines.add('練習熱心で、伸びしろがある。');
    } else if (p.age >= 30) {
      lines.add('${p.age}歳のベテランで、即戦力として計算できる。');
    }
    final pot = _potShown(p, eye, my.id);
    lines.add('見立て：今 ${GradeUtils.getGrade(p.ovr)}${p.ovr} → 将来 ${GradeUtils.getGrade(pot)}$pot。');
    return lines.join('');
  }

  /// トレード候補（まだ相手の球団にいる選手だけ）
  List<(Player, Team, String, String)> currentTradeTips() {
    final out = <(Player, Team, String, String)>[];
    for (final e in tradeTips) {
      final t = teamById(e['tid'] as String? ?? '');
      final p = t?.players.where((x) => x.id == e['pid']).firstOrNull;
      if (t == null || p == null) continue;
      out.add((p, t, e['comment'] as String? ?? '', e['date'] as String? ?? ''));
    }
    return out;
  }

  /// 一覧が空なら今の時点で作る（初めて開いたとき）
  void ensureTradeTips() {
    if (tradeTips.isEmpty) {
      _scoutTradeTips(currentDate);
      updateAndSave();
    }
  }
}
