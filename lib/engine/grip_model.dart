import 'dart:math' as m;
import 'ball_flight.dart';
import 'vec3.dart';

/// 握り（リリース直前に指先がボールへ力を加える位置と向き）を6つの量で表す
///  ボールの軌道を変えるのは、重力のほかは空気の力だけ（マグヌス力・縫い目の力・無回転の揺れ）。
///  その力を決める指先の操作を、次の6つに一般化する。既存の球種も、まだ名前の無い球も、この6つの組み合わせ
///  向き（時計の針）は、投手の後ろから見て 12時＝上、3時＝投げる腕の側（左投手も同じ値で鏡写しの球になる）
class Grip {
  /// ① 着力点のずれ d（0〜1。ボールの半径に対する比）：0＝中心を押す（球速が最も出る）、1＝表面を撫でる（遅く、回転は掛かる）
  double offset;

  /// ② 擦り切る向き φ（度。時計の針の向き）：指がボールを弾く向き。変化はその反対向き（180°＝下へ切る → バックスピンで浮く）
  double rip;

  /// ③ ジャイロ角 θ（度。−90〜90）：回転軸を進む向きへ倒す量。回転効率＝cos θ。＋＝回外（スライダー側）、−＝回内（シンカー側）
  double gyro;

  /// ④ 指先の摩擦・拘束 μ（0〜1）：1＝縫い目に掛けて弾く、0.3前後＝挟んで抜く、0.1未満＝爪で押す（ナックル）
  double friction;

  /// ⑤ 縫い目の非対称さ（0〜1）と、縫い目の力が押す向き（度。時計の針）：0＝4シームのような対称、1＝1シームのような偏り
  double seamAsym, seamDir;

  /// ⑥ 親指（−1〜1）：−1＝早く外す（抜く・落とす）、0＝ふつう、＋1＝最後まで支点にして突き上げる（回転を増やす）
  double thumb;

  Grip({this.offset = 0.05, this.rip = 180, this.gyro = 20, this.friction = 0.9, this.seamAsym = 0, this.seamDir = 120, this.thumb = 0});

  Grip copy() => Grip.fromJson(toJson());

  Map<String, dynamic> toJson() => {
        'd': _r(offset), 'phi': _r(rip), 'th': _r(gyro), 'mu': _r(friction), 'sa': _r(seamAsym), 'sd': _r(seamDir), 'tb': _r(thumb),
      };
  static double _r(double v) => (v * 1000).round() / 1000;

  factory Grip.fromJson(Map<String, dynamic> j) => Grip(
        offset: (j['d'] ?? 0.05).toDouble(),
        rip: (j['phi'] ?? 180).toDouble(),
        gyro: (j['th'] ?? 20).toDouble(),
        friction: (j['mu'] ?? 0.9).toDouble(),
        seamAsym: (j['sa'] ?? 0).toDouble(),
        seamDir: (j['sd'] ?? 120).toDouble(),
        thumb: (j['tb'] ?? 0).toDouble(),
      );

  // ───────── 握り → ボール（指先から離れた瞬間の状態） ─────────

  /// 球速の比（ストレートを 1）：中心からずれるほど、指が滑るほど、親指を早く外すほど遅い
  double get speedRatio => (1 - 0.40 * offset * offset - 0.06 * (1 - friction) - 0.01 * m.max(0.0, -thumb)).clamp(0.45, 1.0);

  /// 回転数（velocity：その投手のストレートの球速 km/h）：腕の速さ × 摩擦 × モーメントの腕 × 親指の支点
  double rpmAt(int velocity) => 3150 * (velocity / 150) * friction * (0.75 + 0.5 * offset) * (1 + 0.15 * thumb);

  double get efficiency => m.cos(gyro.abs() * deg);

  /// 無回転の揺れ（ナックル）になるか
  bool get knuckle => friction < 0.15;

  /// 縫い目の向き（抗力の寄せ）：対称 0.9 〜 偏り 1.1
  double get seamOrient => 0.9 + 0.2 * m.min(1.0, seamAsym / 0.3);

  /// 変化の向き（時計の針の度）：擦り切る向きの反対
  double get moveClock => (rip + 180) % 360;

  /// 角速度（rad/s）。vu：打ち出しの向き、side：投げる腕の側の x（右投手 −1、左投手 ＋1）
  V3 omega(V3 vu, int velocity, double side, {int seed = 0}) {
    final w = rpmAt(velocity) * 2 * m.pi / 60;
    if (knuckle) {
      final r = m.Random(seed + 7);
      return V3(r.nextDouble() - 0.5, r.nextDouble() - 0.5, r.nextDouble() - 0.5).unit * w;
    }
    final e1 = vu.cross(V3.ez).unit; // この向きの回転 → 上へ
    final e2 = vu.cross(V3.ex.perpTo(vu).unit).unit; // → x の＋へ
    final c = moveClock * deg;
    final wT = w * efficiency;
    final wG = w * m.sin(gyro.abs() * deg) * (gyro >= 0 ? 1 : -1) * (side > 0 ? -1 : 1);
    return e1 * (wT * m.cos(c)) + e2 * (wT * m.sin(c) * side) + vu * wG;
  }

  /// 縫い目の力（シームシフテッドウェイク）。ナックルは向きが毎球・飛びながら変わる揺れ
  SeamForce seamForce(double side, {int seed = 0}) {
    if (knuckle) {
      final r = m.Random(seed);
      final ph = r.nextDouble() * 2 * m.pi;
      return SeamForce((0.10 + r.nextDouble() * 0.08) * (1 - friction / 0.15 * 0.5), V3(m.cos(ph), 0, m.sin(ph)), wobbleHz: 1.2 + r.nextDouble() * 2.0, phase: r.nextDouble() * 6.28);
    }
    if (seamAsym <= 0) return SeamForce.none;
    final d = seamDir * deg;
    return SeamForce(0.07 * seamAsym, V3(m.sin(d) * side, 0, m.cos(d)));
  }

  // ───────── ボール → 握り（既存の球種を6つの量に置き換える） ─────────

  /// 回転（数・効率・変化に効く回転の向き）、球速の比、縫い目の力、親指から握りを求める
  ///  wUp：上へ浮かせる回転、wArm：投げる腕の側へ曲げる回転（rad/s）
  factory Grip.fit({required double rpm, required double efficiency, required double wUp, required double wArm, required double speedRatio, required int velocity,
      double sswCoef = 0, double sswDir = 120, double thumb = 0, double gyroSign = 1, bool knuckle = false}) {
    if (knuckle) {
      // 爪で押し出す：摩擦はほぼ 0。球速は腕を緩める分（着力点のずれ）で合わせる
      final d = m.sqrt(m.max(0.0, (1 - 0.06 * 0.95 - 0.005 - speedRatio) / 0.40)).clamp(0.0, 1.0);
      return Grip(offset: d, rip: 180, gyro: 0, friction: 0.05, seamAsym: 0, seamDir: 0, thumb: -0.5);
    }
    var mu = 0.8, d = 0.0;
    for (var i = 0; i < 12; i++) {
      d = m.sqrt(m.max(0.0, (1 - 0.06 * (1 - mu) - 0.01 * m.max(0.0, -thumb) - speedRatio) / 0.40)).clamp(0.0, 1.0);
      mu = (rpm / (3150 * (velocity / 150) * (0.75 + 0.5 * d) * (1 + 0.15 * thumb))).clamp(0.16, 1.0);
    }
    final clock = (m.atan2(wArm, wUp) / deg + 360) % 360;
    return Grip(
      offset: d,
      rip: (clock + 180) % 360,
      gyro: m.acos(efficiency.clamp(0.0, 1.0)) / deg * (gyroSign >= 0 ? 1 : -1),
      friction: mu,
      seamAsym: (sswCoef / 0.07).clamp(0.0, 1.0),
      seamDir: sswDir,
      thumb: thumb,
    );
  }
}
