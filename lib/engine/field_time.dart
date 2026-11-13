import 'dart:math' as m;
import '../models/player.dart';
import 'base_path.dart';
import 'fielding_times.dart';
import 'spec_constants.dart';

/// 守備と走塁の時間（第4章：時空間の到達レース）
///  アウト／セーフは「守備の合計時間（反応＋捕球まで＋握り替え＋送球）」と「走者の合計時間（脱出＋加速＋全力）」の比べ合い

/// 走る人（打者走者・塁上の走者・野手）の速さ：加速してから最高速で走る
class Sprint {
  final double vTop; // 最高速（m/s）
  final double accel; // 加速度（m/s²）
  const Sprint(this.vTop, this.accel);

  /// 走力から：平均（走力60）で最高速 8.7m/s、超俊足（100）で 9.5m/s
  factory Sprint.of(int run) => Sprint(Spec.run ? Spec.sprint(run) : 7.5 + run * 0.02, 7.0 + run * 0.02);

  /// 距離 d を走る時間（v0：走り出しの速さ。リードから走っている走者など）
  double time(double d, {double v0 = 0}) {
    if (d <= 0) return 0;
    final v = vTop;
    final v0c = v0.clamp(0.0, v);
    final dAcc = (v * v - v0c * v0c) / (2 * accel); // 最高速に達するまでの距離
    if (d <= dAcc) return (-v0c + m.sqrt(v0c * v0c + 2 * accel * d)) / accel;
    return (v - v0c) / accel + (d - dAcc) / v;
  }

  /// t 秒で走れる距離
  double distance(double t, {double v0 = 0}) {
    if (t <= 0) return 0;
    final v = vTop, v0c = v0.clamp(0.0, v);
    final tAcc = (v - v0c) / accel;
    if (t <= tAcc) return v0c * t + 0.5 * accel * t * t;
    return v0c * tAcc + 0.5 * accel * tAcc * tAcc + v * (t - tAcc);
  }
}

class Running {
  static const basePath = 27.43;

  /// 打ってから走り出すまで（スイングを振り切って一塁へ向き、最初の数歩は低い姿勢）：右打者 0.52〜0.62秒、左打者 0.40〜0.48秒、走り打ち 0.18〜0.25秒
  ///  一塁到達は平均で右 約4.3秒・左 約4.15秒（NPB の計測の平均）。俊足の左打者で 3.8〜3.9秒
  static double exitTime(Player b, {required bool lefty, bool slap = false}) {
    if (slap) return 0.22;
    final base = lefty ? 0.45 : 0.57;
    return base - (b.run - 60) * 0.0006;
  }

  /// 打者が一塁に着くまで（走り抜け）。平均で約4.1〜4.3秒、左の超俊足で3.7〜3.8秒
  static double batterTo1B(Player b, {required bool lefty, bool slap = false}) => exitTime(b, lefty: lefty, slap: slap) + Sprint.of(b.run).time(basePath);

  /// 打者が n 個先の塁まで：塁を回るたびに膨らんで減速し（BasePath）、最後の塁はスライディングで足が届くまで（一塁は駆け抜け）
  static double batterToBase(Player b, int bases, {required bool lefty}) =>
      exitTime(b, lefty: lefty) + BaseRun.time(b, sFrom: 0, to: bases, end: bases == 1 ? RunEnd.runThrough : RunEnd.slide);

  /// 塁上の走者：塁 from（リード lead m）から塁 to まで。途中の塁は回る。started：打球の前から走っている
  static double runnerTo(Player p, {required int from, required double lead, required int to, double react = 0.15, bool started = false, double v0 = 1.5, RunEnd end = RunEnd.slide}) {
    final s = Sprint.of(p.run);
    return (started ? -0.3 : react) + BaseRun.time(p, sFrom: from + lead / basePath, to: to, end: end, v0: started ? s.vTop * 0.6 : v0);
  }

  /// 塁上の走者が次の塁へ（lead：リードの幅 m、started：打球の前から走っている）
  static double runner(Player p, double dist, {double react = 0.15, bool started = false}) {
    final s = Sprint.of(p.run);
    return (started ? -0.3 : react) + s.time(dist, v0: started ? s.vTop * 0.6 : 1.5);
  }
}

/// 野手の動き：反応（スプリットステップから1歩目まで約0.2秒）、フライは落下点の見極め、加速、最高速
class Fielding {
  /// 調整：反応と見極めの速さの倍率（小さいほど守備範囲が広い）、捕れる範囲の基準
  static double timeScale = 1.0;
  static double reachBase = 1.25;

  /// 反応：守備力が高いほど速い。投手は投げ終わりの体勢から
  static double reaction(int fieldStat, String role) {
    if (Spec.fld) return (Spec.reaction(fieldStat) + (role == 'P' ? 0.25 : 0)) * timeScale; // 仕様書 6.1（投手は投げ終わりの体勢から）
    var t = 0.20 + (100 - fieldStat) * 0.0028; // 守備60で約0.31秒
    if (role == 'P') t += 0.25;
    return t * timeScale;
  }

  /// フライ・ライナーの落下点の見極め（外野手は 0.35〜0.50秒で判断）。その間は 6割の速さで寄る
  static double judge(int fieldStat, String role) {
    final outfield = role == 'LF' || role == 'CF' || role == 'RF';
    return (outfield ? FieldTimes.judgeOutfield : FieldTimes.judgeInfield).at(fieldStat); // 見極めは反応の速さの調整とは別（外野 0.35〜0.5秒）
  }

  /// 野手の走り：走力60で最高速 8.0m/s・加速 7.2m/s²（構えた姿勢から10mを約1.8秒。外野手は打ってから2.5秒で約10m＝計測の「1歩目」の平均）
  static Sprint sprint(Player p) => Sprint(Spec.run ? Spec.sprint(p.run) : 6.9 + p.run * 0.019, 6.0 + p.run * 0.02);

  /// 捕れる範囲（腕＋グラブ。m）
  static double reach(Player p) => reachBase + p.glove.reachBonus;
}

/// 送球の様式（第4章 4.3）：残り時間と送球距離から最適なものを選ぶ
class ThrowStyle {
  final String name;
  final double transfer; // 捕ってから投げるまで（秒）
  final double speed; // 球速（m/s。肩60の基準）
  final double maxDist; // この投げ方で届く距離（m）
  final double errorRate; // 悪送球の起こりやすさ（倍率）
  const ThrowStyle(this.name, this.transfer, this.speed, this.maxDist, this.errorRate);

  static const bare = ThrowStyle('素手でスナップスロー', 0.40, 100 / 3.6, 25, 2.2); // バント・ボテボテ
  static const sidearm = ThrowStyle('当て捕りからノーステップ', 0.55, 128 / 3.6, 32, 1.4); // 浅いゴロ・併殺のトス
  static const standard = ThrowStyle('ステップしてスリークォーター', 0.73, 142 / 3.6, 45, 1.0); // 定位置のゴロ
  static const jump = ThrowStyle('逆シングルからジャンピングスロー', 0.85, 140 / 3.6, 45, 1.8); // 三遊間の深い所
  static const crowHop = ThrowStyle('クロウホップから遠投', 1.02, 155 / 3.6, 95, 1.2); // 外野からの返球

  /// 肩の強さで球速が変わる（肩60で基準、100で約1.1倍）
  static double armFactor(Player p) => Spec.thr ? Spec.throwMaxKmh(p.arm) / 155 : 0.85 + p.arm * 0.0025; // 仕様書：最大送球初速（クロウホップの遠投）が 110+0.48×肩

  /// 握り替え（仕様書 5.3 の様式ごとの時間 × 送球の能力 6.1）
  double transferOf(Player f) {
    if (!Spec.thr) return transfer;
    final base = identical(this, standard) ? 0.70 : (identical(this, crowHop) ? 1.00 : transfer);
    return base * Spec.transfer(f.throwAccuracy) / Spec.transfer(60);
  }

  /// 送球が届くまでの時間（遠いほど空気抵抗で後半が失速する）
  static double drag = 0.005; // 遠投の失速（70m で約1.35倍の時間。走路の膨らみを入れたときに合わせ直し）
  static double flight(double dist, double speed) => dist / speed * (1 + dist * drag);

  /// 捕球してから塁に届くまでの時間が最も短い投げ方
  ///  ballSlow：打球が弱い（素手で拾える）、deepHole：逆シングルで追った
  static ({ThrowStyle style, double t}) best(Player f, double dist, {bool outfield = false, bool ballSlow = false, bool deepHole = false}) {
    final cands = outfield ? [crowHop, standard] : [if (ballSlow) bare, sidearm, standard, if (deepHole) jump];
    ThrowStyle? pick;
    var bt = double.infinity;
    for (final s in cands) {
      if (dist > s.maxDist * (0.85 + f.arm * 0.003) && s != crowHop && s != standard) continue;
      final t = s.transferOf(f) + f.glove.transferDelay + flight(dist, s.speed * armFactor(f));
      if (t < bt) {
        bt = t;
        pick = s;
      }
    }
    return (style: pick ?? standard, t: bt);
  }
}
