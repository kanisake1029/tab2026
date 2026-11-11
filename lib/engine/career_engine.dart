import 'dart:math';
import '../models/player.dart';
import 'growth_curve.dart';

/// 開始時点の通算成績
///  - 固有12：プロ年数が長い選手は、初期選手編集で通算成績だけを入力する
///  - 入力されていない選手（新規チームを含む）は、能力とプロ年数から、それらしい値を推定して入れる（careerEstimated）
class CareerEngine {
  static void estimateIfMissing(Player p) {
    if (p.career.games > 0 || p.proYears <= 1 || p.joinedInGame) return; // ゲームの中で入団した選手には、開始前の経歴は無い
    p.career = estimate(p);
    p.careerEstimated = true;
  }

  /// ゲーム開始前の経歴の推定（能力とプロ年数から。選手ごとに毎回同じ値）
  ///  doneSeasons：ゲームの中で終わったシーズンの数（その分、推定する年数を減らし、年齢もさかのぼる）
  static PlayerStats estimate(Player p, {int doneSeasons = 0}) {
    final c = PlayerStats();
    for (final y in estimateYears(p, doneSeasons: doneSeasons)) {
      c.add(y);
    }
    return c;
  }

  /// 推定の年度ごとの成績（古い順）。年度別の経歴を作るときの配分の目安にも使う
  static List<PlayerStats> estimateYears(Player p, {int doneSeasons = 0, int? seasonsOverride}) {
    final r = Random(p.id.hashCode ^ 0x5eed);
    final seasons = seasonsOverride ?? p.proYears - 1 - doneSeasons;
    final out = <PlayerStats>[];
    // 年ごとの力：全盛期の前は伸び盛り、後は衰え（いまの能力を基準にした比）× その年の調子
    final (pa, pb) = GrowthCurve.primeRange(p);
    double ageQ(int a) => a < pa ? (1 - 0.07 * (pa - a)).clamp(0.55, 1.0) : (a > pb ? (1 - 0.06 * (a - pb)).clamp(0.55, 1.0) : 1.0);
    final nowQ = ageQ(p.age);
    for (var y = 0; y < seasons; y++) {
      final c = PlayerStats();
      out.add(c);
      final ageThen = p.age - doneSeasons - (seasons - y);
      final ramp = ((ageThen - 18) / 8).clamp(0.2, 1.0); // 若い頃ほど出場が少ない
      final form = 0.8 + r.nextDouble() * 0.4; // その年の調子
      final q = ageQ(ageThen) / nowQ * form; // その年の力（いまの能力＝1）
      final f = (0.75 + r.nextDouble() * 0.5) * ramp * q.clamp(0.45, 1.15);
      if (p.isPitcher) {
        final starter = p.stamina >= 60;
        final quality = ((p.ovr - 45) / 25).clamp(0.1, 1.3);
        final games = ((starter ? 22 : 48) * quality * f).round();
        final ip = (starter ? 140 : 50) * quality * f;
        final era = (4.6 - (p.ovr - 50) * 0.06).clamp(1.8, 6.0) * (0.85 + r.nextDouble() * 0.3) / pow(q, 0.9);
        // 9イニングあたり：被安打・被本塁打は防御率に連動、与四球は制球、奪三振は球威
        final h9 = (8.6 + (era - 3.6) * 0.9).clamp(6.0, 12.0);
        final hr9 = (0.85 + (era - 3.6) * 0.18).clamp(0.3, 2.0);
        final bb9 = (4.2 - p.control * 0.03).clamp(1.2, 5.5);
        final k9 = (4.0 + p.pitchPower * 0.07).clamp(4.0, 12.0) * pow(q, 0.4);
        c.games += games;
        c.pitchApps += games;
        c.inningsPitched += (ip * 3).round();
        c.earnedRuns += (era * ip / 9).round();
        c.hitsAllowed += (h9 * ip / 9).round();
        c.hrAllowed += (hr9 * ip / 9).round();
        c.pitcherWalks += (bb9 * ip / 9).round();
        c.pitcherStrikeouts += (k9 * ip / 9).round();
        c.hbpAllowed += (ip * 0.035).round();
        // 守備（投手）
        if (starter) c.posGames['投'] = (c.posGames['投'] ?? 0) + games;
        c.posOuts['投'] = (c.posOuts['投'] ?? 0) + (ip * 3).round();
        c.defOuts += (ip * 3).round();
        c.putouts += (ip / 9 * 0.15).round();
        c.assists += (ip / 9 * 0.3).round();
        c.errors += (ip / 9 * 0.02).round();
        if (starter) {
          c.starts += games;
          final cg = games * 0.04 * quality;
          c.completeGames += cg.round();
          c.shutouts += (cg * 0.3).round();
          c.wins += (ip / 15 * (0.7 + quality * 0.3)).round();
          c.losses += (ip / 17).round();
        } else {
          final closer = p.ovr >= 68 && r.nextDouble() < 0.5;
          c.saves += closer ? (games * 0.6).round() : 0;
          c.holds += closer ? 0 : (games * 0.35).round();
          final rw = (games * 0.06).round();
          c.wins += rw;
          c.reliefWins += rw;
          c.losses += (games * 0.05).round();
        }
      } else {
        final regular = ((p.ovr - 50) / 20).clamp(0.1, 1.0);
        final games = 130 * regular * f;
        final ab = games * 3.4;
        final avg = (0.215 + (p.contact - 50) * 0.0017).clamp(0.180, 0.330) * pow(q, 0.55);
        final hits = ab * avg;
        final hr = ab * ((p.power - 35) * 0.0007).clamp(0.002, 0.07) * pow(q, 1.6);
        final walks = ab * (0.04 + p.eye / 1500);
        final sb = games * ((p.run - 55) * 0.004).clamp(0.0, 0.4) * q;
        c.games += games.round();
        c.atBats += ab.round();
        c.hits += hits.round();
        c.homeRuns += hr.round();
        c.doubles += (hits * 0.18).round();
        c.triples += (hits * 0.015).round();
        c.rbi += (hr * 2.4 + hits * 0.22).round();
        c.walks += walks.round();
        c.hbp += (ab * 0.008).round();
        c.sacFlies += (ab * 0.008).round();
        c.runs += (hits * 0.4 + hr * 0.35 + walks * 0.25 + sb * 0.3).round();
        c.strikeouts += (ab * 0.19).round();
        c.stolenBases += sb.round();
        c.caughtStealing += (sb * 0.35).round();
        // 守備：主な守備位置で、9イニングあたりの刺殺・補殺・失策・併殺の目安（守備力で失策が増減）
        const pos = {'捕手': '捕', '一塁手': '一', '二塁手': '二', '三塁手': '三', '遊撃手': '遊', '左翼手': '左', '中堅手': '中', '右翼手': '右'};
        const rates = {'捕': [7.0, 0.5, 0.05, 0.1], '一': [8.5, 0.6, 0.05, 0.8], '二': [2.0, 2.9, 0.08, 0.7], '三': [0.7, 1.8, 0.10, 0.15], '遊': [1.6, 2.8, 0.12, 0.6], '左': [1.9, 0.05, 0.03, 0.01], '中': [2.6, 0.05, 0.03, 0.01], '右': [2.0, 0.07, 0.03, 0.01]};
        final k = pos[p.mainPosition];
        if (k != null) {
          final starts = games * 0.9;
          final inn = starts * 8.5;
          final rt = rates[k]!;
          final errMul = (1.6 - p.catchSkill / 100).clamp(0.6, 1.4);
          c.posGames[k] = (c.posGames[k] ?? 0) + starts.round();
          c.posOuts[k] = (c.posOuts[k] ?? 0) + (inn * 3).round();
          c.defOuts += (inn * 3).round();
          c.putouts += (inn / 9 * rt[0]).round();
          c.assists += (inn / 9 * rt[1]).round();
          c.errors += (inn / 9 * rt[2] * errMul).round();
          c.dpTurned += (inn / 9 * rt[3]).round();
        }
      }
    }
    return out;
  }
}
