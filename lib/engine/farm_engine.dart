import '../models/player.dart';
import '../models/team.dart';
import '../utils/schedule_generator.dart';
import 'match_simulator.dart';

/// 2軍の試合（1軍と同じ日程・同じ対戦チームの2軍と行う。介入できるのはオーダーだけ）
///
/// 2軍の選手だけで「影のチーム」を作り、1軍と同じ試合エンジンで試合を計算する。
/// 成績は 1軍の成績（seasonStats）ではなく 2軍の成績（farmStats）に積み上がる。
class FarmEngine {
  /// 2軍で使う価値の上乗せ（2軍監督の育成眼による「育てる価値」。AppState が設定する）。無ければ今の力だけで選ぶ
  static double Function(Team, Player)? devBonus;

  static const lineupPositions = ['捕', '一', '二', '三', '遊', '左', '中', '右', 'DH'];

  /// 守備位置ごとの守備適性
  static int fieldingAt(Player p, String pos) {
    switch (pos) {
      case '捕': return p.fieldC;
      case '一': return p.field1B;
      case '二': return p.field2B;
      case '三': return p.field3B;
      case '遊': return p.fieldSS;
      case '左': return p.fieldLF;
      case '中': return p.fieldCF;
      case '右': return p.fieldRF;
      default: return 0;
    }
  }

  static const _mainPosName = {'捕': '捕手', '一': '一塁手', '二': '二塁手', '三': '三塁手', '遊': '遊撃手', '左': '左翼手', '中': '中堅手', '右': '右翼手'};

  /// 2軍にいる選手（1軍登録でない選手）
  static List<Player> farmPlayers(Team t) => t.players.where((p) => !t.roster1G.contains(p.id)).toList();

  /// 出場できる状態か（出られない怪我でない・体力が残っている）
  static bool isAvailable(Player p) => !p.isInjuredOut && (_relaxed || p.energyRatio >= 0.25);
  static bool _relaxed = false; // 人数が足りないときは、疲れている選手も出す

  static double _hitScore(Player p) => p.contactLeft * 0.25 + p.contactRight * 0.25 + p.power * 0.3 + p.eye * 0.2;

  static double _posScore(Player p, String pos) {
    var s = p.ovr + fieldingAt(p, pos) * 0.5;
    if (p.mainPosition == _mainPosName[pos]) s += 15;
    if (p.isPitcher) s -= 100; // 投手は野手が足りないときだけ
    return s;
  }

  /// 守備の難しい位置から順に、その位置に向く選手を置く。DH は残りの最も打てる選手。打順は打力の高い順
  static List<LineupEntry> autoLineup(Team t, {Map<String, String> keep = const {}}) {
    // 人数が足りないとき（_relaxed）は、投手も野手として出す
    final pool = farmPlayers(t).where((p) => (!p.isPitcher || _relaxed) && isAvailable(p)).toList();
    if (_relaxed) pool.sort((a, b) => (a.isPitcher ? 1 : 0).compareTo(b.isPitcher ? 1 : 0));
    final used = <String>{};
    final byPos = <String, Player>{};
    final bonus = {for (final p in pool) p.id: devBonus == null ? 0.0 : devBonus!(t, p)};
    // 指定済み（手動）の位置を先に確定
    keep.forEach((pos, id) {
      final p = pool.where((x) => x.id == id).toList();
      if (p.isNotEmpty) { byPos[pos] = p.first; used.add(id); }
    });
    for (final pos in ['捕', '遊', '中', '二', '三', '右', '左', '一']) {
      if (byPos.containsKey(pos)) continue;
      Player? best;
      for (final p in pool) {
        if (used.contains(p.id)) continue;
        if (best == null || _posScore(p, pos) + bonus[p.id]! > _posScore(best, pos) + bonus[best.id]!) best = p;
      }
      if (best != null) { byPos[pos] = best; used.add(best.id); }
    }
    if (!byPos.containsKey('DH')) {
      Player? best;
      for (final p in pool) {
        if (used.contains(p.id)) continue;
        if (best == null || _hitScore(p) + bonus[p.id]! > _hitScore(best) + bonus[best.id]!) best = p;
      }
      if (best != null) { byPos['DH'] = best; used.add(best.id); }
    }
    final entries = byPos.entries.map((e) => LineupEntry(playerId: e.value.id, position: e.key)).toList();
    final pmap = {for (final p in t.players) p.id: p};
    entries.sort((a, b) => _hitScore(pmap[b.playerId]!).compareTo(_hitScore(pmap[a.playerId]!)));
    return entries;
  }

  /// 手動の打順を、いまの2軍の顔ぶれに合わせて直す（昇格・怪我などで欠けた枠は、その位置に向く選手で埋める）
  static List<LineupEntry> effectiveLineup(Team t) {
    if (t.farmAuto || t.farmLineup.length != 9) return autoLineup(t);
    final avail = {for (final p in farmPlayers(t).where((p) => !p.isPitcher && isAvailable(p))) p.id: p};
    final keep = <String, String>{};
    final order = <String>[]; // 手動の打順（位置の並び）
    for (final l in t.farmLineup) {
      order.add(l.position);
      if (avail.containsKey(l.playerId) && !keep.containsValue(l.playerId)) keep[l.position] = l.playerId;
    }
    final filled = autoLineup(t, keep: keep);
    final byPos = {for (final e in filled) e.position: e};
    // 手動の打順の並びを保つ
    return [for (final pos in order) if (byPos[pos] != null) byPos[pos]!];
  }

  /// 先発ローテ（最大5人）。手動の枠は、怪我などで欠けたら自動の候補で埋める
  static List<String> effectiveRotation(Team t) {
    final lineupIds = _relaxed ? autoLineup(t).map((l) => l.playerId).toSet() : const <String>{};
    final pitchers = farmPlayers(t).where((p) => p.isPitcher && isAvailable(p) && !lineupIds.contains(p.id)).toList()
      ..sort((a, b) => (b.stamina * 0.6 + b.ovr * 0.4).compareTo(a.stamina * 0.6 + a.ovr * 0.4));
    final ids = {for (final p in pitchers) p.id};
    final rot = List<String>.filled(t.farmRotationCount, '');
    if (!t.farmAuto) {
      for (var i = 0; i < t.farmRotationCount && i < t.farmRotation.length; i++) {
        if (ids.contains(t.farmRotation[i]) && !rot.contains(t.farmRotation[i])) rot[i] = t.farmRotation[i];
      }
    }
    final pool = pitchers.where((p) => !rot.contains(p.id)).iterator;
    for (var i = 0; i < rot.length; i++) {
      if (rot[i].isNotEmpty) continue;
      if (pool.moveNext()) rot[i] = pool.current.id;
    }
    return rot;
  }

  /// 2軍の人数（確認用）：野手・投手・出られない怪我人
  static String shortage(Team t) {
    final f = farmPlayers(t);
    return '${t.id} 2軍${f.length}人 野手${f.where((p) => !p.isPitcher).length}（出場可${f.where((p) => !p.isPitcher && isAvailable(p)).length}） 投手${f.where((p) => p.isPitcher).length}（出場可${f.where((p) => p.isPitcher && isAvailable(p)).length}）';
  }

  /// 試合用の影のチーム。2軍の選手が足りなければ null
  static Team? buildShadow(Team t) {
    final lineup = effectiveLineup(t);
    if (lineup.length < 9) return null;
    final rot = effectiveRotation(t);
    if (rot.every((e) => e.isEmpty)) return null;
    final farm = farmPlayers(t);
    final pitchers = farm.where((p) => p.isPitcher && isAvailable(p) && !rot.contains(p.id)).toList()..sort((a, b) => b.ovr.compareTo(a.ovr));
    final pattern = [for (var i = 0; i < 3; i++) i < pitchers.length ? pitchers[i].id : ''];
    final wp = [pattern.length > 2 ? pattern[2] : '', pattern.length > 1 ? pattern[1] : '', pattern[0]]; // [7回, 8回, 9回]
    // 今日の先発（空き枠は飛ばす）。1軍のローテは最大7枠なので、影のチームには今日の先発だけを入れ、
    // ほかの先発は登板間隔を守るためベンチから外す
    String today = '';
    for (var k = 0; k < t.farmRotationCount; k++) {
      final id = rot[(t.farmRotationIndex + k) % t.farmRotationCount];
      if (id.isNotEmpty) {
        today = id;
        break;
      }
    }
    final resting = rot.where((id) => id.isNotEmpty && id != today).toSet();
    final bench = farm.where(isAvailable).map((p) => p.id).where((id) => !resting.contains(id)).toList();
    return Team(
      id: t.id,
      name: '${t.name}(2軍)',
      league: t.league,
      players: farm,
      roster1G: [],
      rotation: [today, '', '', ''],
      rotationCount: 4,
      rotationIndex: 0,
      winningPattern: wp,
      lineup: lineup,
      useDH: true,
      active26: bench,
    );
  }

  static void _swapStats(Team shadow) {
    for (final p in shadow.players) {
      final tmp = p.seasonStats;
      p.seasonStats = p.farmStats;
      p.farmStats = tmp;
    }
  }

  /// 2軍の試合を1つ計算する。出場できる選手がそろわないときは null（試合は成立しない）
  static MatchResult? play(MatchSimulator sim, Match m, Team home, Team away) {
    Team? shadow(Team t) {
      final s = buildShadow(t);
      if (s != null) return s;
      _relaxed = true;
      try {
        return buildShadow(t);
      } finally {
        _relaxed = false;
      }
    }
    final hs = shadow(home);
    final as = shadow(away);
    if (hs == null || as == null) return null;
    _swapStats(hs);
    _swapStats(as);
    try {
      return sim.simulateMatch(m, hs, as);
    } finally {
      _swapStats(hs);
      _swapStats(as);
    }
  }
}
