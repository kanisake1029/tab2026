import 'dart:math';
import '../models/league_rules.dart';
import '../models/player.dart';
import '../models/team.dart';
import 'growth_engine.dart';

/// 選手の出入り（入団・移籍・退団）と、CPU 球団の編成
class RosterEngine {
  static const maxShihaika = 70; // 支配下登録の上限
  static const max1G = 31;

  static const posNames = ['捕手', '一塁手', '二塁手', '三塁手', '遊撃手', '左翼手', '中堅手', '右翼手'];
  static const posKeys = ['捕', '一', '二', '三', '遊', '左', '中', '右'];
  static const _posKeyToName = {'捕': '捕手', '一': '一塁手', '二': '二塁手', '三': '三塁手', '遊': '遊撃手', '左': '左翼手', '中': '中堅手', '右': '右翼手'};

  /// 支配下の人数（育成を除く）
  static int shihaikaCount(Team t) => t.players.where((p) => !p.ikusei).length;
  static int ikuseiCount(Team t) => t.players.where((p) => p.ikusei).length;
  static int freeSlots(Team t) => max(0, maxShihaika - shihaikaCount(t));

  /// CPU 球団の支配下の目安（シーズン中の外国人・トレードでの補強に備えて7枠空けておく）
  static const cpuTarget = 63;
  static int cpuRoom(Team t) => max(0, cpuTarget - shihaikaCount(t));

  // ───────── 選手の価値 ─────────

  /// 将来の見込みの OVR（全盛期までに伸びる分の目安）。成長率（才能×向上心）と、全盛期までの年数から計算する
  static int potentialOvr(Player p) {
    final (peakStart, peakEnd) = GrowthEngine.peakRange(p);
    final a = p.age;
    final before = max(0, peakStart - a);              // 全盛期までの年数（伸びが大きい）
    final inPrime = a > peakEnd ? 0 : (peakEnd - max(a, peakStart) + 1).clamp(0, 11); // 全盛期の残り（伸びは小さい）
    final gain = p.growthRate * (before * 2.6 + inPrime * 0.9);
    return min(99, p.ovr + gain.round());
  }

  /// 将来の伸びの見込み（見る人の判断力 eye で見誤る。同じ人が同じ選手を見れば毎回同じ見立てになる）
  ///  eye=null は本当の値。判断力が低いほど、高く見すぎる・低く見すぎるのぶれが大きい
  static double perceivedGain(Player p, {int? eye, String viewer = ''}) {
    final gain = (potentialOvr(p) - p.ovr).toDouble();
    if (eye == null) return gain;
    final r = Random(viewer.hashCode ^ p.id.hashCode);
    double g() => sqrt(-2.0 * log(1.0 - r.nextDouble())) * cos(2.0 * pi * r.nextDouble());
    final miss = (100 - eye.clamp(1, 100)) / 100.0;
    return max(0.0, gain * (1 + g() * miss * 0.6) + g() * miss * 6);
  }

  /// 残す価値（戦力外・トレード・FA の判断に使う）。今の力＋若い選手の伸びしろ−年齢
  ///  eye・viewer を渡すと、その人の見立ての伸びしろで計算する
  static double value(Player p, {int? eye, String viewer = ''}) {
    var v = p.ovr.toDouble();
    if (p.age <= 26) v += perceivedGain(p, eye: eye, viewer: viewer) * (p.age <= 22 ? 0.6 : 0.4);
    if (p.age >= 32) v -= (p.age - 31) * 1.5;
    return v;
  }

  /// 監督の見立てによる選手の価値（トレード・FA・自由契約の補強で使う）
  ///  potential：0=実績・現在重視（今の能力と過去の成績を見る。伸びしろは割り引き、ベテランも評価）〜100=将来性重視（才能×向上心の伸びしろに期待し、年齢を嫌う）
  ///  eye：見る目の確かさ。低いほど伸びしろの読みが外れる（監督ごと・選手ごとにずれ方は決まっている）
  static double styledValue(Player p, {required int eye, required int potential, String viewer = ''}) {
    final potW = potential.clamp(0, 100) / 100.0;
    // 実績：今季の成績が十分ならそれを、少なければ通算の成績を見る
    double record = 0;
    PlayerStats? s;
    if (p.isPitcher) {
      s = p.seasonStats.inningsPitched >= 120 ? p.seasonStats : (p.career.inningsPitched >= 270 ? p.career : null);
      if (s != null) record = ((3.70 - s.era) / 0.5 * 1.2).clamp(-5.0, 5.0);
    } else {
      s = p.seasonStats.plateAppearances >= 150 ? p.seasonStats : (p.career.plateAppearances >= 300 ? p.career : null);
      if (s != null) record = ((s.ops - 0.700) / 0.1 * 1.5).clamp(-5.0, 5.0);
    }
    final cur = p.ovr + record * (1.2 - potW);
    // 将来性：見立ての伸びしろ
    final gain = (potentialOvr(p) - p.ovr).toDouble();
    final r = Random(viewer.hashCode ^ p.id.hashCode ^ 0x9e37);
    double g() => sqrt(-2.0 * log(1.0 - r.nextDouble())) * cos(2.0 * pi * r.nextDouble());
    final miss = (100 - eye.clamp(1, 100)) / 100.0;
    final seen = max(0.0, gain * (1 + g() * miss * 1.1) + g() * miss * 9);
    final ageF = p.age <= 22 ? 1.0 : (p.age <= 25 ? 0.8 : (p.age <= 28 ? 0.45 : 0.15));
    final future = seen * (0.05 + 1.45 * potW) * ageF;
    // 年齢：将来性重視ほど年齢を嫌い、実績重視はベテランも評価する
    final agePen = p.age >= 30 ? (p.age - 29) * (0.3 + 2.2 * potW) : 0.0;
    return cur + future - agePen;
  }

  /// 監督の見立てによるトレードの価値（主力ほど大きい）
  static double styledTradeValue(Player p, {required int eye, required int potential, String viewer = ''}) {
    final v = styledValue(p, eye: eye, potential: potential, viewer: viewer) - 40;
    if (v <= 0) return 1;
    return pow(v, 1.7).toDouble();
  }

  /// トレードの価値（主力ほど大きい。控え3人で主力1人と釣り合わないように）
  static double tradeValue(Player p, {int? eye, String viewer = ''}) {
    final v = value(p, eye: eye, viewer: viewer) - 40;
    if (v <= 0) return 1;
    return pow(v, 1.7).toDouble();
  }

  /// 守備位置の人数（メインポジション）
  static Map<String, int> posCounts(Team t) {
    final m = <String, int>{for (final k in posNames) k: 0, '投手': 0};
    for (final p in t.players.where((p) => !p.ikusei)) {
      m[p.mainPosition] = (m[p.mainPosition] ?? 0) + 1;
    }
    return m;
  }

  /// その位置の層の薄さ（0=十分〜1=足りない）。投手は32人、捕手は4人、ほかは4人を目安にする
  static double need(Team t, String pos) {
    final c = posCounts(t);
    final want = pos == '投手' ? 32 : 4;
    final have = c[pos] ?? 0;
    // 主力の質も見る（その位置の最も良い選手の OVR）
    final best = t.players.where((p) => !p.ikusei && p.mainPosition == pos).fold<int>(0, (m, p) => max(m, p.ovr));
    final depth = ((want - have) / want).clamp(0.0, 1.0);
    final quality = ((65 - best) / 20).clamp(0.0, 1.0);
    return (depth * 0.6 + quality * 0.4).clamp(0.0, 1.0);
  }

  // ───────── 背番号 ─────────

  static int freeNumber(Team t, {required bool ikusei}) {
    final used = {for (final p in t.players) ...[p.uniformNumber, if (p.nextNumber != null) p.nextNumber!]}; // 来季の予約の番号も使わない
    if (ikusei) {
      for (var n = 101; n < 1000; n++) {
        if (!used.contains(n)) return n;
      }
      return 999;
    }
    for (final n in [for (var i = 10; i < 100; i++) i, for (var i = 0; i < 10; i++) i]) {
      if (!used.contains(n)) return n;
    }
    return 99;
  }

  // ───────── 入団・退団 ─────────

  /// 選手を球団に加える（2軍から）。背番号が重なれば空き番号にする
  static void addPlayer(Team t, Player p) {
    // 入団時の能力（経歴タブで今と比べる）。まだ無ければ、入ったときの能力を残す
    if (p.baseline.isEmpty) {
      p.baseline = GrowthEngine.abilities(p);
      p.baselineNote = '入団時';
    }
    p.lastDemotedDate = null;
    p.retainAsked = false;
    if (t.players.any((x) => x.uniformNumber == p.uniformNumber) || (p.ikusei != (p.uniformNumber >= 100))) {
      p.uniformNumber = freeNumber(t, ikusei: p.ikusei);
    }
    t.players.add(p);
  }

  /// 選手を球団から外す。スタメン・ローテ・方程式・1軍の穴は自動で埋める
  static void removePlayer(Team t, Player p) {
    t.players.removeWhere((x) => x.id == p.id);
    t.roster1G.remove(p.id);
    t.manualBenchOut.remove(p.id);
    t.active26.remove(p.id);
    for (var i = 0; i < t.rotation.length; i++) {
      if (t.rotation[i] == p.id) t.rotation[i] = '';
    }
    for (var i = 0; i < t.winningPattern.length; i++) {
      if (t.winningPattern[i] == p.id) t.winningPattern[i] = '';
    }
    // 2軍の手動の打順に穴が空いたら、同じ守備位置に近い2軍の野手で埋める
    for (final l in t.farmLineup.where((l) => l.playerId == p.id)) {
      final used = t.farmLineup.map((e) => e.playerId).toSet();
      final posName = _posKeyToName[l.position];
      final cands = t.players.where((c) => c.id != p.id && !c.isPitcher && !t.roster1G.contains(c.id) && !used.contains(c.id) && !c.isInjuredOut).toList()
        ..sort((a, b) => ((b.mainPosition == posName ? 10 : 0) + b.ovr).compareTo((a.mainPosition == posName ? 10 : 0) + a.ovr));
      if (cands.isNotEmpty) l.playerId = cands.first.id;
    }
    t.farmLineup.removeWhere((l) => l.playerId == p.id);
    for (var i = 0; i < t.farmRotation.length; i++) {
      if (t.farmRotation[i] == p.id) t.farmRotation[i] = '';
    }
    final hole = t.lineup.where((l) => l.playerId == p.id).toList();
    repairRoster(t);
    for (final l in hole) {
      final used = t.lineup.map((e) => e.playerId).toSet();
      final posName = _posKeyToName[l.position];
      final cands = t.players.where((c) => !c.isPitcher && !c.ikusei && t.roster1G.contains(c.id) && !used.contains(c.id) && !c.isInjuredOut).toList()
        ..sort((a, b) => ((b.mainPosition == posName ? 10 : 0) + b.ovr).compareTo((a.mainPosition == posName ? 10 : 0) + a.ovr));
      if (cands.isNotEmpty) {
        l.playerId = cands.first.id;
      } else {
        t.lineup.remove(l);
      }
    }
    if (t.lineup.length < 9) _fillLineup(t);
    t.autoFillPitchingStaff();
    if (t.roster1G.isNotEmpty) t.refreshActive26();
  }

  /// 1軍の人数を31人に戻す（足りなければ2軍の良い選手を上げる。育成と出られない怪我人は除く）
  static void repairRoster(Team t) {
    final pmap = {for (final p in t.players) p.id: p};
    t.roster1G.removeWhere((id) => pmap[id] == null || pmap[id]!.ikusei);
    while (t.roster1G.length < max1G) {
      final pitchers1G = t.roster1G.where((id) => pmap[id]!.isPitcher).length;
      final wantPitcher = pitchers1G < 15;
      final foreign = t.roster1G.where((id) => pmap[id]!.foreignSlot).length;
      final cands = t.players
          .where((p) => !t.roster1G.contains(p.id) && !p.ikusei && !p.isInjuredOut && (!p.foreignSlot || LeagueRules.underBench(foreign)))
          .toList()
        ..sort((a, b) => ((b.isPitcher == wantPitcher ? 20 : 0) + b.ovr).compareTo((a.isPitcher == wantPitcher ? 20 : 0) + a.ovr));
      if (cands.isEmpty) break;
      t.roster1G.add(cands.first.id);
    }
  }

  static void _fillLineup(Team t) {
    final used = t.lineup.map((e) => e.playerId).toSet();
    final have = t.lineup.map((e) => e.position).toSet();
    for (final pos in [...posKeys, 'DH']) {
      if (have.contains(pos)) continue;
      final posName = _posKeyToName[pos];
      final cands = t.players.where((c) => !c.isPitcher && !c.ikusei && t.roster1G.contains(c.id) && !used.contains(c.id) && !c.isInjuredOut).toList()
        ..sort((a, b) => ((b.mainPosition == posName ? 10 : 0) + b.ovr).compareTo((a.mainPosition == posName ? 10 : 0) + a.ovr));
      if (cands.isEmpty) continue;
      t.lineup.add(LineupEntry(playerId: cands.first.id, position: pos));
      used.add(cands.first.id);
    }
  }

  // ───────── CPU 球団の編成 ─────────

  static double _hitScore(Player p) => p.contact * 0.35 + p.power * 0.3 + p.eye * 0.2 + p.run * 0.15;

  /// CPU 球団の1軍・スタメン・打順・先発ローテ・方程式を組み直す。
  ///  skill（手腕 0〜100）が低いほど判断に揺らぎが出る。youth（若手起用 0〜100）が高いほど若手を使う
  ///  devBonus：監督の育成眼による「伸び盛りの若手を使う価値」（OVR の点数）。無ければ 0
  static void cpuReassign(Team t, {int skill = 60, int youth = 50, Random? rnd, double Function(Player)? devBonus}) {
    final r = rnd ?? Random();
    final noise = (100 - skill) / 12.0;
    double score(Player p) {
      var s = p.ovr + (r.nextDouble() * 2 - 1) * noise;
      if (p.age <= 25) s += (youth - 50) / 25.0;
      if (p.energyRatio < 0.5) s -= 4;
      if (devBonus != null) s += devBonus(p);
      return s;
    }

    final healthy = t.players.where((p) => !p.ikusei && !p.isInjuredOut).toList();
    final sc = {for (final p in healthy) p.id: score(p)};
    final fielders = healthy.where((p) => !p.isPitcher).toList()..sort((a, b) => sc[b.id]!.compareTo(sc[a.id]!));
    final pitchers = healthy.where((p) => p.isPitcher).toList()..sort((a, b) => sc[b.id]!.compareTo(sc[a.id]!));
    if (fielders.length < 9 || pitchers.length < 8) return;
    var foreign = 0;
    bool foreignOk(Player p) => !p.foreignSlot || LeagueRules.underBench(foreign);

    // スタメン：守備の難しい位置から、その位置の選手を優先
    final used = <String>{};
    final byPos = <String, Player>{};
    for (final pos in ['捕', '遊', '二', '中', '三', '右', '左', '一']) {
      final name = _posKeyToName[pos]!;
      Player? best;
      double bestS = -999;
      for (final p in fielders) {
        if (used.contains(p.id) || !foreignOk(p)) continue;
        final s = sc[p.id]! + (p.mainPosition == name ? 12 : (pos == '捕' ? -40 : 0));
        if (s > bestS) {
          bestS = s;
          best = p;
        }
      }
      if (best == null) continue;
      byPos[pos] = best;
      used.add(best.id);
      if (best.foreignSlot) foreign++;
    }
    {
      final dh = fielders.where((p) => !used.contains(p.id) && foreignOk(p)).toList()..sort((a, b) => _hitScore(b).compareTo(_hitScore(a)));
      if (dh.isNotEmpty) {
        byPos['DH'] = dh.first;
        used.add(dh.first.id);
        if (dh.first.foreignSlot) foreign++;
      }
    }
    // 打順：1番は出塁と走力、4番は長打、ほかは打力順
    final order = byPos.entries.toList()..sort((a, b) => _hitScore(b.value).compareTo(_hitScore(a.value)));
    final lead = (List.of(order.take(6))..sort((a, b) => (b.value.contact + b.value.eye + b.value.run).compareTo(a.value.contact + a.value.eye + a.value.run))).first;
    final clean = (List.of(order.take(5).where((e) => e != lead))..sort((a, b) => b.value.power.compareTo(a.value.power))).first;
    final rest = order.where((e) => e != lead && e != clean).toList();
    final batting = [lead, ...rest.take(2), clean, ...rest.skip(2)];
    t.lineup = [for (final e in batting) LineupEntry(playerId: e.value.id, position: e.key)];

    // 投手：先発はスタミナ重視、方程式は残りの上位
    final starters = (List.of(pitchers.where(foreignOk))..sort((a, b) => (sc[b.id]! + b.stamina * 0.5).compareTo(sc[a.id]! + a.stamina * 0.5))).take(t.rotationCount).toList();
    for (final p in starters) {
      if (p.foreignSlot) foreign++;
    }
    final sid = starters.map((p) => p.id).toSet();
    final pen = pitchers.where((p) => !sid.contains(p.id) && foreignOk(p)).toList();
    // 今いる先発は同じ枠のまま（登板間隔を崩さない）。空いた枠に新しい先発を入れる
    final newRot = List<String>.filled(Team.maxRotation, '');
    final left = List.of(starters.map((p) => p.id));
    for (var i = 0; i < t.rotationCount; i++) {
      final cur = t.rotation[i];
      if (cur.isNotEmpty && left.contains(cur)) {
        newRot[i] = cur;
        left.remove(cur);
      }
    }
    for (var i = 0; i < t.rotationCount && left.isNotEmpty; i++) {
      if (newRot[i].isEmpty) newRot[i] = left.removeAt(0);
    }
    t.rotation = newRot;
    final wp = pen.take(3).toList();
    t.winningPattern = [wp.length > 2 ? wp[2].id : '', wp.length > 1 ? wp[1].id : '', wp.isNotEmpty ? wp[0].id : ''];
    for (final p in wp) {
      if (p.foreignSlot) foreign++;
    }
    // 1軍31人：投手16（先発＋方程式＋中継ぎ）＋野手15
    final first = <String>{...sid, ...wp.map((p) => p.id), ...t.lineup.map((l) => l.playerId)};
    for (final p in pen.skip(3)) {
      if (first.where((id) => healthy.firstWhere((x) => x.id == id).isPitcher).length >= 16) break;
      if (!foreignOk(p)) continue;
      first.add(p.id);
      if (p.foreignSlot) foreign++;
    }
    final backupC = fielders.where((p) => p.mainPosition == '捕手' && !first.contains(p.id));
    if (backupC.isNotEmpty) first.add(backupC.first.id);
    for (final p in fielders) {
      if (first.length >= max1G) break;
      if (first.contains(p.id) || !foreignOk(p)) continue;
      first.add(p.id);
      if (p.foreignSlot) foreign++;
    }
    for (final p in pitchers) {
      if (first.length >= max1G) break;
      if (first.contains(p.id) || !foreignOk(p)) continue;
      first.add(p.id);
    }
    t.roster1G = first.toList();
    t.manualBenchOut = [];
    t.rotationIndex %= t.rotationCount;
    t.autoFillPitchingStaff();
    t.refreshActive26();
  }
}
