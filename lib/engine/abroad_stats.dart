import 'dart:math';

import '../models/player.dart';

/// 海外・独立リーグの推定成績（1シーズン分）の生成と、既存文字列からの整合補完。
///  打撃・投球の全項目を四則演算で矛盾なく埋める。
class AbroadStats {
  static double _g(Random r) => sqrt(-2 * log(1 - r.nextDouble())) * cos(2 * pi * r.nextDouble());
  static String _f3(double v) => v.toStringAsFixed(3).replaceFirst(RegExp(r'^0'), '');

  /// 新規生成（外国人選手）：全項目入りの PlayerStats と表示用サマリー行を返す
  static (String line, PlayerStats stats) generateForeign(
    Player p,
    String lg,
    int year,
    double share,
    Random r, {
    required double avgAdj,
    required double eraAdj,
    required double hrMul,
  }) {
    final winter = lg == 'ドミニカンリーグ' || lg == '豪州リーグ';
    if (p.isPitcher) {
      final q = (p.pitchPower + p.control) / 2;
      final era = (4.1 - (q - 60) * 0.06 + eraAdj + _g(r) * 0.55).clamp(1.10, 7.80);
      final starter = p.stamina >= 55;
      var games = starter ? 14 + r.nextInt(17) : 28 + r.nextInt(36);
      if (share < 1) games = (games * share).round().clamp(3, 40);
      if (winter) games = (games * 0.45).round().clamp(4, 30);
      final ipOuts = max(3, (games * (starter ? 4.8 + r.nextDouble() * 1.2 : 0.9 + r.nextDouble() * 0.3) * 3).round());
      final ip = ipOuts / 3.0;
      final k = (ip * (0.72 + (p.pitchPower - 55) * 0.012 + _g(r) * 0.06)).round().clamp(0, 400);
      final dec = starter ? games * 0.62 : games * 0.18;
      final wr = (0.5 + (4.2 - era) * 0.07).clamp(0.2, 0.8);
      final w = (dec * wr).round(), l = (dec * (1 - wr)).round();
      final sv = !starter && p.pitchPower >= 65 && r.nextDouble() < 0.4 ? (games * (0.3 + r.nextDouble() * 0.3)).round() : 0;
      final er = (era * ip / 9.0).round().clamp(0, ipOuts * 2);
      final s = _fillPitcher(
        p: p,
        games: games,
        w: w,
        l: l,
        sv: sv,
        ipOuts: ipOuts,
        k: k,
        er: er,
        r: r,
      );
      final ipStr = '${ipOuts ~/ 3}${ipOuts % 3 == 0 ? '' : '.${ipOuts % 3}'}';
      final line = '$year　$lg　$games試合 $w勝$l敗${sv > 0 ? '$sv S' : ''} 防御率${s.era.toStringAsFixed(2)} $ipStr回 $k奪三振';
      return (line, s);
    }

    var games = 95 + r.nextInt(50);
    if (lg == 'KBO') games = 100 + r.nextInt(45);
    if (lg == 'CPBL') games = 80 + r.nextInt(40);
    if (share < 1) games = (games * share).round().clamp(8, 120);
    if (winter) games = 18 + r.nextInt(28);
    final avg = (0.248 + (p.contact - 60) * 0.0028 + avgAdj + _g(r) * 0.016).clamp(0.170, 0.370);
    final ab = max(10, (games * (3.4 + r.nextDouble() * 0.5)).round());
    final hr = max(0, (games * max(0.015, (p.power - 45) * 0.0055) * hrMul + _g(r) * 3).round());
    final rbi = (hr * 2.5 + games * 0.22 + _g(r) * 6).round().clamp(hr, 200);
    final obpTarget = avg + 0.062 + (p.eye - 55) * 0.0012;
    final slgTarget = avg + hr / max(1, ab) * 3.1 + 0.075 + (p.power - 60) * 0.0015;
    final s = _fillBatter(
      p: p,
      games: games,
      ab: ab,
      avg: avg,
      hr: hr,
      rbi: rbi,
      opsTarget: obpTarget + slgTarget,
      r: r,
    );
    final pa = s.atBats + s.walks + s.sacFlies + s.hbp;
    final obp = pa == 0 ? 0.0 : (s.hits + s.walks + s.hbp) / pa;
    final slg = s.atBats == 0 ? 0.0 : s.totalBases / s.atBats;
    final line = '$year　$lg　$games試合 打率${_f3(s.battingAverage)} ${s.homeRuns}本 ${s.rbi}打点 OPS${_f3(obp + slg)}';
    return (line, s);
  }

  /// 既存のサマリー文字列から全項目が整合する PlayerStats を決定論的に復元する
  static PlayerStats fromLine(Player p, String line, {required bool isPitcher}) {
    final seed = Object.hash(p.id, line, isPitcher);
    final r = Random(seed);
    if (isPitcher) {
      final g = int.tryParse(RegExp(r'(\d+)試合').firstMatch(line)?.group(1) ?? '') ?? 20;
      final wl = RegExp(r'(\d+)勝(\d+)敗').firstMatch(line);
      final w = int.tryParse(wl?.group(1) ?? '') ?? 0;
      final l = int.tryParse(wl?.group(2) ?? '') ?? 0;
      final sv = int.tryParse(RegExp(r'(\d+)\s*S').firstMatch(line)?.group(1) ?? '') ?? 0;
      final era = double.tryParse(RegExp(r'防御率([\d.]+)').firstMatch(line)?.group(1) ?? '') ?? 3.50;
      final ipStr = RegExp(r'([\d.]+)回').firstMatch(line)?.group(1) ?? '50';
      final ipOuts = _parseIpOuts(ipStr);
      final k = int.tryParse(RegExp(r'(\d+)奪三振').firstMatch(line)?.group(1) ?? '') ?? (ipOuts * 0.25).round();
      final er = (era * (ipOuts / 3.0) / 9.0).round().clamp(0, ipOuts * 2);
      return _fillPitcher(p: p, games: g, w: w, l: l, sv: sv, ipOuts: ipOuts, k: k, er: er, r: r);
    }

    final g = int.tryParse(RegExp(r'(\d+)試合').firstMatch(line)?.group(1) ?? '') ?? 100;
    final avg = double.tryParse(RegExp(r'打率([.\d]+)').firstMatch(line)?.group(1) ?? '') ?? 0.250;
    final hr = int.tryParse(RegExp(r'(\d+)本').firstMatch(line)?.group(1) ?? '') ?? 5;
    final rbi = int.tryParse(RegExp(r'(\d+)打点').firstMatch(line)?.group(1) ?? '') ?? 30;
    final ops = double.tryParse(RegExp(r'OPS([.\d]+)').firstMatch(line)?.group(1) ?? '') ?? (avg * 2 + 0.14);
    var ab = max(g, (g * 3.65).round());
    var bestErr = 999.0;
    for (var cand = max(1, (g * 3.3).round()); cand <= max(1, (g * 4.0).round()); cand++) {
      final h = (cand * avg).round();
      final err = (h / cand - avg).abs();
      if (err < bestErr) {
        bestErr = err;
        ab = cand;
        if (err < 0.0004) break;
      }
    }
    return _fillBatter(p: p, games: g, ab: ab, avg: avg, hr: hr, rbi: rbi, opsTarget: ops, r: r);
  }

  static int _parseIpOuts(String ipStr) {
    final parts = ipStr.split('.');
    final whole = int.tryParse(parts[0]) ?? 0;
    final frac = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0).clamp(0, 2) : 0;
    return max(1, whole * 3 + frac);
  }

  static PlayerStats _fillPitcher({
    required Player p,
    required int games,
    required int w,
    required int l,
    required int sv,
    required int ipOuts,
    required int k,
    required int er,
    required Random r,
  }) {
    final ip = ipOuts / 3.0;
    final avgIp = games == 0 ? 0.0 : ip / games;
    final starter = sv == 0 && (avgIp >= 3.0 || p.stamina >= 55);
    final starts = starter ? (games * 0.92).round().clamp(w + l > 0 ? 1 : 0, games) : 0;
    final relief = max(0, games - starts);
    final holds = (!starter && sv < relief) ? (relief * (0.28 + r.nextDouble() * 0.18)).round().clamp(0, max(0, relief - sv)).toInt() : 0;
    final cg = starter && avgIp >= 5.2 && p.stamina >= 62 ? (starts * (0.04 + r.nextDouble() * 0.06)).round().clamp(0, w + l).toInt() : 0;
    final sho = cg > 0 ? (cg * 0.45).round().clamp(0, min(cg, w)).toInt() : 0;

    final bbRate = (0.34 - (p.control - 55) * 0.004 + _g(r) * 0.04).clamp(0.14, 0.65);
    final bb = (ip * bbRate).round().clamp(0, ipOuts * 2);
    final hbp = (bb * (0.09 + r.nextDouble() * 0.06)).round();
    final era = ip == 0 ? 3.5 : er * 9.0 / ip;
    final whipTarget = (0.98 + era * 0.085 + _g(r) * 0.05).clamp(0.82, 1.85);
    final ha = max((er * 1.15).round(), (whipTarget * ip - bb).round()).clamp(0, ipOuts * 3);
    final hra = (ip * (0.085 + (era - 3.0) * 0.015 + _g(r) * 0.015)).round().clamp(0, min(ha, er + 2)).toInt();

    return PlayerStats(
      games: games,
      pitchApps: games,
      starts: starts,
      wins: w,
      losses: l,
      holds: holds,
      saves: sv,
      completeGames: cg,
      shutouts: sho,
      inningsPitched: ipOuts,
      hitsAllowed: ha,
      hrAllowed: hra,
      pitcherStrikeouts: k,
      pitcherWalks: bb,
      hbpAllowed: hbp,
      earnedRuns: er,
    );
  }

  static PlayerStats _fillBatter({
    required Player p,
    required int games,
    required int ab,
    required double avg,
    required int hr,
    required int rbi,
    required double opsTarget,
    required Random r,
  }) {
    final hits = (ab * avg).round().clamp(hr, ab);
    final realAvg = hits / max(1, ab);
    final nonHrHits = max(0, hits - hr);

    // 選球眼から四球・死球・犠飛・三振を算出
    final bbRate = (0.075 + (p.eye - 55) * 0.0018 + _g(r) * 0.012).clamp(0.03, 0.17);
    final bb = (ab * bbRate / (1 - bbRate)).round().clamp(0, games * 2);
    final hbp = max(0, (games * (0.02 + r.nextDouble() * 0.03)).round());
    final sf = max(0, (rbi * 0.06).round());
    final pa = ab + bb + hbp + sf;
    final obp = pa == 0 ? 0.0 : (hits + bb + hbp) / pa;

    // 目標OPSに合うように長打（二塁打・三塁打）を調整
    final slgTarget = max(realAvg, opsTarget - obp);
    final needExtraBases = max(hr * 3, ((slgTarget - realAvg) * ab).round());
    var extraRemaining = max(0, needExtraBases - hr * 3);
    final triples = p.run >= 65
        ? min(nonHrHits ~/ 6, (games * (p.run - 55) * 0.0012 + r.nextDouble() * 2).round()).clamp(0, extraRemaining ~/ 2)
        : min(nonHrHits ~/ 12, (r.nextDouble() * 2).round()).clamp(0, extraRemaining ~/ 2);
    extraRemaining = max(0, extraRemaining - triples * 2);
    final doubles = extraRemaining.clamp(0, max(0, nonHrHits - triples)).toInt();

    final kRate = (0.19 - (p.contact - 60) * 0.002 + (p.power - 60) * 0.0012 + _g(r) * 0.02).clamp(0.06, 0.36);
    final so = (ab * kRate).round().clamp(0, ab - hits);
    final mouda = (ab * (0.022 + (80 - p.run) * 0.0002)).round().clamp(0, max(0, ab - hits - so)).toInt();

    final sbAttempts = p.run >= 62
        ? (games * (p.run - 54) * 0.0055 + r.nextDouble() * 3).round().clamp(0, 50)
        : (games * 0.015 * r.nextDouble()).round();
    final sbRate = (0.64 + (p.run - 60) * 0.005).clamp(0.50, 0.88);
    final sb = (sbAttempts * sbRate).round();
    final cs = max(0, sbAttempts - sb);

    final runs = (hr + (hits - hr + bb + hbp) * (0.31 + (p.run - 55) * 0.002)).round().clamp(hr, pa);
    final rispAB = (ab * 0.24).round().clamp(1, ab);
    final rispAvg = (realAvg + (p.clutch - 60) * 0.0012).clamp(0.100, 0.450);
    final rispHits = (rispAB * rispAvg).round().clamp(0, min(hits, rispAB));

    return PlayerStats(
      games: games,
      atBats: ab,
      runs: runs,
      hits: hits,
      doubles: doubles,
      triples: triples,
      homeRuns: hr,
      rbi: rbi,
      stolenBases: sb,
      caughtStealing: cs,
      walks: bb,
      hbp: hbp,
      strikeouts: so,
      sacFlies: sf,
      mouda: mouda,
    )
      ..rispAB = rispAB
      ..rispH = rispHits.toInt();
  }
}
