import 'dart:math';

import '../models/player.dart';
import '../models/team.dart';

/// 監督への信頼（trust）とチーム愛（teamLove）の計算・契約希望年数・交渉判定。
///  ・どちらも 1〜100、平均 60 前後、主力スタメンの信頼度は S90 前後に達する逓減カーブ
///  ・交渉受諾は「チーム愛 × 監督への信頼」の相乗効果で決まる
class TrustEngine {
  static int _applyDelta(int cur, double rawDelta, Random r) {
    if (rawDelta == 0) return cur;
    final double eff;
    if (rawDelta > 0) {
      // 大きくなるほどゆるやかに上がる（95 付近で頭打ち、主力で S90 前後）
      eff = rawDelta * ((95 - cur) / 45.0).clamp(0.10, 1.40);
    } else {
      eff = rawDelta * (cur / 60.0).clamp(0.50, 1.20);
    }
    final absE = eff.abs();
    final whole = absE.floor();
    final frac = absE - whole;
    final step = whole + (r.nextDouble() < frac ? 1 : 0);
    return (cur + (eff >= 0 ? step : -step)).clamp(1, 100);
  }

  /// 信頼度の増減（1軍試合 +0.45 / 2軍試合 +0.22 / 3軍試合 +0.15 / 1軍昇格 +3 / 2軍降格 -5）
  static void addTrust(Player p, double rawDelta, [Random? r]) {
    p.trust = _applyDelta(p.trust, rawDelta, r ?? Random(p.id.hashCode ^ p.trust));
  }

  /// チーム愛の増減（チーム勝利 +0.25 / 憧れの選手 / 在籍年数）
  static void addTeamLove(Player p, double rawDelta, [Random? r]) {
    p.teamLove = _applyDelta(p.teamLove, rawDelta, r ?? Random(p.id.hashCode ^ p.teamLove));
  }

  /// シーズン終了時のチーム愛・信頼度の調整（勝敗・憧れの選手・在籍年数・平均60への緩やかな回帰）
  static void seasonEndAdjust(Team t, {required int wins, required int losses, Set<String> movedIn = const {}, Random? r}) {
    final rnd = r ?? Random(t.id.hashCode ^ wins ^ losses);
    final totalG = max(1, wins + losses);
    final winPct = wins / totalG;
    final stars = t.players.where((x) => x.ovr >= 78 || (x.proYears >= 10 && x.ovr >= 70)).toList();

    for (final p in t.players) {
      // 1. 勝敗によるチーム愛
      if (winPct >= 0.55) {
        addTeamLove(p, 2.5, rnd);
      } else if (winPct < 0.40) {
        addTeamLove(p, -2.0, rnd);
      }

      // 2. 憧れの選手（チーム内のスター・ベテラン）の存在
      final idol = stars.any((s) => s.id != p.id && ((s.isPitcher == p.isPitcher) || (p.nationality == '海外' && s.nationality == '海外')));
      if (idol) {
        addTeamLove(p, 2.5, rnd);
      } else if (stars.any((s) => s.id != p.id)) {
        addTeamLove(p, 1.2, rnd);
      }

      // 3. 長年在籍によるチーム愛（今年移籍していなければ増加）
      if (!movedIn.contains(p.id)) {
        addTeamLove(p, p.proYears >= 6 ? 2.5 : 1.5, rnd);
      }

      // 4. リーグ平均が約 60 に落ち着く緩やかな自然収束（スタメンは試合出場で高いまま維持）
      final lovePull = (60 - p.teamLove) * 0.08;
      if (lovePull.abs() >= 0.3) addTeamLove(p, lovePull, rnd);
      final trustPull = (58 - p.trust) * 0.06;
      if (trustPull.abs() >= 0.3) addTrust(p, trustPull, rnd);
    }
  }

  /// 希望契約年数
  ///  - 外国人入団時：1〜3年。全盛期が近いほど短い契約を好む
  ///  - 通常更改・外国人再契約：全盛期前は FA 権獲得年で切れる年数を好み、全盛期〜過渡期は長期契約を好む
  static int preferredYears(Player p, {bool isInitialForeign = false}) {
    final primeS = p.primeStart > 0 ? p.primeStart : 27;
    final transEnd = primeS + p.primeLen + p.transLen;
    if (isInitialForeign) {
      final toPrime = primeS - p.age;
      if (toPrime <= 2) return 1;
      if (toPrime <= 4) return 2;
      return 3;
    }
    if (p.age < primeS) {
      if (!p.foreignSlot && !p.hasFA) {
        final faLeft = max(1, p.faNeed - p.faService);
        return faLeft.clamp(1, 3);
      }
      return 2;
    }
    if (p.age <= transEnd) {
      return p.ovr >= 72 ? 4 : 3;
    }
    return 1;
  }

  /// チーム愛 × 監督への信頼（平均 60×60 なら 1.0、90×90 なら 2.25）
  static double bondFactor(Player p) => (p.teamLove / 60.0) * (p.trust / 60.0);

  /// 提示年数に応じた希望年俸の計算（希望年数とズレる場合は上乗せを求める）
  static int askForYears(Player p, int baseAsk, int years, {bool isInitialForeign = false}) {
    final primeS = p.primeStart > 0 ? p.primeStart : 27;
    final pref = preferredYears(p, isInitialForeign: isInitialForeign);
    var mul = 1.0;

    if (isInitialForeign) {
      final toPrime = primeS - p.age;
      if (toPrime <= 2 && years > 1) {
        mul += 0.18 * (years - 1);
      } else if (years != pref) {
        mul += 0.06 * (years - pref).abs();
      }
    } else if (p.age < primeS && !p.foreignSlot && !p.hasFA) {
      final faLeft = max(1, p.faNeed - p.faService);
      if (years > faLeft) {
        // FA権獲得を超えて縛られる年数には強い上乗せを求める
        mul += 0.22 * (years - faLeft);
      } else if (years < pref) {
        mul += 0.03 * (pref - years);
      }
    } else if (p.age >= primeS && years < pref) {
      // 全盛期〜過渡期で長期契約を望むのに単年〜短い提示なら少し上乗せ
      mul += 0.06 * (pref - years);
    } else if (p.age >= 30 && years > 1) {
      mul -= 0.025 * (years - 1);
    }

    final floor = p.ikusei ? 250 : 450;
    return max(floor, ((baseAsk * mul) / 50).round() * 50);
  }

  /// 交渉の受諾判定：チーム愛 × 監督への信頼が高いほど、希望と違う条件でも承諾しやすい
  static bool acceptOffer(Player p, {required int offerSalary, required int needSalary, required Random r}) {
    if (offerSalary >= needSalary) return true;
    final bond = bondFactor(p);
    final allowance = (0.04 + 0.14 * (bond - 0.5)).clamp(0.0, 0.25);
    final minAcceptable = needSalary * (1.0 - allowance);
    if (offerSalary < minAcceptable) return false;
    final ratio = (offerSalary - minAcceptable) / max(1.0, needSalary - minAcceptable);
    final chance = (0.25 + 0.65 * ratio * bond.clamp(0.5, 1.8)).clamp(0.05, 0.95);
    return r.nextDouble() < chance;
  }
}
