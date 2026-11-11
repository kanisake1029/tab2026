import 'dart:math';
import '../models/player.dart';

/// 1チーム分の試合の顔ぶれ（打順9人・先発・中継ぎ・抑え）
class QuickSide {
  final List<Player> lineup;
  final Player starter;
  final List<Player> bullpen; // 中継ぎ（使う順の候補）
  final Player? closer;
  const QuickSide(this.lineup, this.starter, this.bullpen, this.closer);
}

/// 簡易の試合計算（他リーグ用）：1打席ずつ、打者（ミート・パワー・選球眼）と投手（球威・制球・球速）で結果を決める。
///  先発はスタミナに応じて5〜7回、そのあと中継ぎが1回ずつ、9回に3点差以内なら抑え。成績は stats(選手) に書き込む
class QuickGame {
  final Random r;
  final PlayerStats Function(Player) stats;
  /// リーグの打高・投高の補正（安打の確率に足す）
  final double hitAdj;
  /// 本塁打の出やすさの補正
  final double hrAdj;
  QuickGame(this.r, this.stats, {this.hitAdj = 0, this.hrAdj = 0});

  /// 戻り値：(ビジターの得点, ホームの得点)
  (int, int) play(QuickSide away, QuickSide home) {
    final score = [0, 0];
    final bat = [0, 0];
    final sides = [away, home];
    final pitcherNow = [home.starter, away.starter]; // 守る側の投手（side 0 の攻撃中は home の投手）
    final outsBy = <String, int>{};
    final runsBy = <String, int>{};
    final used = [<Player>{home.starter}, <Player>{away.starter}];
    final relIdx = [0, 0];
    final starterInn = [
      (5 + (home.starter.stamina - 50) / 15).round().clamp(4, 8),
      (5 + (away.starter.stamina - 50) / 15).round().clamp(4, 8),
    ];
    String? winP, loseP;
    var leader = -1;
    for (final b in [...away.lineup, ...home.lineup]) {
      stats(b).games++;
    }
    for (final p in [home.starter, away.starter]) {
      final s = stats(p);
      s.games++;
      s.pitchApps++;
      s.starts++;
    }
    var inning = 1;
    while (true) {
      for (final side in [0, 1]) {
        if (inning >= 9 && side == 1 && score[1] > score[0]) break; // 裏の攻撃は不要
        final def = 1 - side; // 守る側
        final defSide = sides[def];
        // 投手交代：先発は決めた回まで、そのあとは中継ぎ。9回以降で3点差以内のリードなら抑え
        if (inning > starterInn[side]) {
          Player? next;
          final lead = score[def] - score[side];
          if (inning >= 9 && lead > 0 && lead <= 3 && defSide.closer != null && !used[side].contains(defSide.closer)) {
            next = defSide.closer;
          } else if (pitcherNow[side] == defSide.starter || (outsBy[pitcherNow[side].id] ?? 0) >= 3) {
            while (relIdx[side] < defSide.bullpen.length && used[side].contains(defSide.bullpen[relIdx[side]])) {
              relIdx[side]++;
            }
            if (relIdx[side] < defSide.bullpen.length) next = defSide.bullpen[relIdx[side]++];
          }
          if (next != null && next != pitcherNow[side]) {
            pitcherNow[side] = next;
            used[side].add(next);
            final s = stats(next);
            s.games++;
            s.pitchApps++;
          }
        }
        final pit = pitcherNow[side];
        final ps = stats(pit);
        final off = sides[side];
        final q = (pit.pitchPower + pit.control + pit.velocityNorm) / 3.0;
        var outs = 0, runs = 0;
        final base = List<Player?>.filled(3, null);
        while (outs < 3) {
          final b = off.lineup[bat[side] % off.lineup.length];
          bat[side]++;
          final s = stats(b);
          final c = (b.contactLeft + b.contactRight) / 2.0;
          var scored = 0;
          void home1(Player? x) {
            if (x == null) return;
            scored++;
            stats(x).runs++;
          }

          void force() {
            if (base[0] != null) {
              if (base[1] != null) {
                home1(base[2]);
                base[2] = base[1];
              }
              base[1] = base[0];
            }
            base[0] = b;
          }

          final x = r.nextDouble();
          final pBb = (0.08 + (b.eye - 50) * 0.0009 - (pit.control - 50) * 0.0009).clamp(0.03, 0.16);
          final pSo = (0.20 + (q - 50) * 0.0035 - (c - 50) * 0.0025).clamp(0.08, 0.38);
          if (x < pBb) {
            s.walks++;
            ps.pitcherWalks++;
            force();
          } else if (x < pBb + pSo) {
            s.atBats++;
            s.strikeouts++;
            ps.pitcherStrikeouts++;
            outs++;
          } else {
            s.atBats++;
            final pHit = (0.315 + hitAdj + (c - q) * 0.0032).clamp(0.18, 0.46);
            if (r.nextDouble() < pHit) {
              s.hits++;
              ps.hitsAllowed++;
              final hr = (0.075 + hrAdj + (b.power - 55) * 0.004 - (pit.pitchPower - 55) * 0.0015).clamp(0.01, 0.34);
              final y = r.nextDouble();
              if (y < hr) {
                s.homeRuns++;
                ps.hrAllowed++;
                base.forEach(home1);
                home1(b);
                base.fillRange(0, 3, null);
              } else if (y < hr + 0.02 + (b.run - 50) * 0.0004) {
                s.triples++;
                base.forEach(home1);
                base.fillRange(0, 3, null);
                base[2] = b;
              } else if (y < hr + 0.22) {
                s.doubles++;
                home1(base[2]);
                home1(base[1]);
                final first = base[0];
                base.fillRange(0, 3, null);
                if (first != null) {
                  if (r.nextDouble() < 0.4) {
                    home1(first);
                  } else {
                    base[2] = first;
                  }
                }
                base[1] = b;
              } else {
                home1(base[2]);
                final second = base[1], first = base[0];
                base.fillRange(0, 3, null);
                if (second != null) {
                  if (r.nextDouble() < 0.6) {
                    home1(second);
                  } else {
                    base[2] = second;
                  }
                }
                if (first != null) {
                  if (base[2] == null && r.nextDouble() < 0.3) {
                    base[2] = first;
                  } else {
                    base[1] = first;
                  }
                }
                base[0] = b;
              }
            } else if (r.nextDouble() < 0.02) {
              force(); // 失策で出塁
            } else {
              outs++;
              if (outs < 3 && base[2] != null && r.nextDouble() < 0.3) {
                s.atBats--;
                s.sacFlies++;
                home1(base[2]);
                base[2] = null;
              } else if (outs < 3 && base[0] != null && r.nextDouble() < 0.12) {
                outs++; // 併殺
                s.gidp++;
                base[0] = null;
              }
            }
          }
          if (scored > 0) {
            s.rbi += scored;
            runs += scored;
            ps.earnedRuns += scored;
            runsBy[pit.id] = (runsBy[pit.id] ?? 0) + scored;
          }
          if (inning >= 9 && side == 1 && score[1] + runs > score[0]) break; // サヨナラ
          final rn = base[0];
          if (outs < 3 && rn != null && base[1] == null && rn.run >= 60 && r.nextDouble() < (rn.run - 55) * 0.01) {
            if (r.nextDouble() < (0.65 + (rn.run - 60) * 0.01).clamp(0.5, 0.9)) {
              stats(rn).stolenBases++;
              base[1] = rn;
            } else {
              stats(rn).caughtStealing++;
              outs++;
            }
            base[0] = null;
          }
        }
        outsBy[pit.id] = (outsBy[pit.id] ?? 0) + outs;
        ps.inningsPitched += outs;
        score[side] += runs;
        final now = score[0] > score[1] ? 0 : (score[1] > score[0] ? 1 : -1);
        if (now != leader) {
          leader = now;
          if (now >= 0) {
            winP = pitcherNow[1 - now].id; // 勝ち越した側の、そのときの投手
            loseP = pit.id;
          } else {
            winP = null;
            loseP = null;
          }
        }
      }
      if (inning >= 9 && score[0] != score[1]) break;
      if (inning >= 12) break; // 引き分け
      inning++;
    }
    // 勝敗・セーブ
    final all = [...used[0], ...used[1]];
    for (final p in all) {
      final s = stats(p);
      if (p.id == winP) s.wins++;
      if (p.id == loseP) s.losses++;
    }
    if (score[0] != score[1]) {
      final w = score[1] > score[0] ? 1 : 0;
      final last = pitcherNow[1 - w];
      final lead = (score[w] - score[1 - w]).abs();
      if (last.id != winP && lead <= 3 && (outsBy[last.id] ?? 0) >= 3) {
        stats(last).saves++;
      }
    }
    return (score[0], score[1]);
  }
}
