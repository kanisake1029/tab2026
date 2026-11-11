import 'dart:math' as m;
import '../models/player.dart';
import 'ball_flight.dart';
import 'ball_spec.dart';
import 'grip_model.dart';
import 'pitch_catalog.dart';
import 'vec3.dart';

/// 握りと回転の結果（1球種）
class SpinResult {
  final String name, group;
  final double speed; // 初速 m/s
  final double rpm; // 全体の回転数
  final double efficiency; // 回転効率（変化に効く回転の割合。残りはジャイロ）
  final V3 omega; // 角速度 rad/s（本塁基準の座標）
  final double moveH, moveV; // 回転・縫い目で生まれた変化（cm。本塁の前の縁で、回転の無い球との差。H は＋＝投げる腕の側、V は＋＝上）
  final double targetH, targetV; // 目標にした変化
  final SeamForce seam;
  final double seamOrient; // 縫い目の向き（4シーム 0.9・2シーム 1.1）
  final double clock; // 回転の向き（時計の針。12:00＝真上へ浮く回転、投手の後ろから見て）
  final Grip grip; // 握り（6つの量。これが元になって回転・球速・縫い目の力が決まる）
  const SpinResult(this.name, this.group, this.speed, this.rpm, this.efficiency, this.omega, this.moveH, this.moveV, this.targetH, this.targetV, this.seam, this.seamOrient, this.clock, this.grip);

  double get gyroDeg => m.acos(efficiency.clamp(0.0, 1.0)) * 180 / m.pi;
  double get ballEnergy => 0.5 * BallSpec.mass * speed * speed; // J
  double get spinEnergy => 0.5 * BallSpec.inertia * omega.length2; // J
  String get clockText {
    var h = clock;
    while (h < 0.5) {
      h += 12;
    }
    while (h >= 12.5) {
      h -= 12;
    }
    final hh = h.floor(), mm = ((h - hh) * 60 / 15).round() * 15;
    return '${mm == 60 ? hh + 1 : hh}:${(mm % 60).toString().padLeft(2, '0')}';
  }
}

/// 球種の握り → 回転（数・軸・効率）と縫い目の力
///  変化の目標：ストレートは腕の角度と球速・キレから（オーバーほど縦に浮き、サイドほど横へ）。
///  ほかの球種は「ストレートの変化 ＋ 球種表の変化（向き angle・量 breakLevel。100 で約70cm）」。
///  スライダー系・カーブ系は、ストレートの浮き上がる回転を失う分（breakLevel に比例）も下へ
///  その変化を生む回転を、実際に飛ばして（ニュートン法）逆算する。回転数は系統ごとの回転効率から決める
class GripSpin {
  static const _eff = <String, double>{
    'ストレート': 0.93, 'ツーシーム': 0.88, 'ワンシーム': 0.80, 'シュート': 0.85, '高速シュート': 0.88, 'ムービングファスト': 0.72, 'イーファスピッチ': 0.90,
    'スイーパー': 0.85, 'スライダー': 0.40, 'ハードスライダー': 0.35, 'カットボール': 0.45, 'スパイクジャイロ': 0.15, 'スロースライダー': 0.50, 'ナックルスライダー': 0.50, 'スラッター': 0.35, 'スラーブ': 0.65,
    'カーブ': 0.85, 'スローカーブ': 0.85, '超スローカーブ': 0.80, 'ナックルカーブ': 0.90, 'ドロップカーブ': 0.90, 'パワーカーブ': 0.80,
    'フォーク': 0.60, 'スプリット': 0.80, 'スプリットファスト': 0.85, 'スポンカー': 0.85, 'ジャイロフォーク': 0.20, 'スプリットチェンジ': 0.80,
    'チェンジアップ': 0.88, 'チェンジオブペース': 0.90, 'シンカー': 0.90, 'スローシンカー': 0.88, 'ハードシンカー': 0.90, 'サークルチェンジ': 0.88, 'バルカンチェンジ': 0.60, 'エアベンダー': 0.95,
  };
  static const _groupEff = {'ストレート系': 0.9, 'スライダー系': 0.45, 'カーブ系': 0.85, 'フォーク系': 0.7, 'シンカー系': 0.88};
  static const _rpmRange = {'ストレート系': (1800.0, 2900.0), 'スライダー系': (1900.0, 3000.0), 'カーブ系': (1900.0, 3300.0), 'フォーク系': (700.0, 1900.0), 'シンカー系': (1300.0, 2600.0)};

  /// 縫い目の力（シームシフテッドウェイク）を使う球：投げる腕の側・下へ
  static const _ssw = <String, double>{
    'ツーシーム': 0.035, 'ワンシーム': 0.055, 'ハードシンカー': 0.04, 'シンカー': 0.04, 'スローシンカー': 0.03, 'チェンジアップ': 0.03, 'サークルチェンジ': 0.035,
    'スプリット': 0.025, 'スプリットファスト': 0.02, 'スポンカー': 0.04, 'スプリットチェンジ': 0.03, 'フォーク': 0.015, 'エアベンダー': 0.07, 'シュート': 0.03,
  };
  /// 親指の使い方：カーブ系は支点で突き上げ、フォーク系・抜く球は早く外す
  static double _thumbOf(String name, String g) => switch (name) {
        'バルカンチェンジ' => 0.5,
        'チェンジアップ' || 'サークルチェンジ' || 'スプリットチェンジ' || 'チェンジオブペース' => -0.3,
        _ => g == 'カーブ系' ? 0.5 : (g == 'フォーク系' ? -0.5 : 0.0),
      };

  /// 握りから決める（球種の握りが決まっていればこちら）。name は表示用
  static SpinResult fromGrip(Grip grip, {required String name, required V3 pos, required bool lefty, required int velocity, int seed = 0, double targetH = 0, double targetV = 0}) {
    final side = lefty ? 1.0 : -1.0;
    final speed = velocity * grip.speedRatio / 3.6;
    final (v0, vu) = _launch(pos, speed);
    final omega = grip.omega(vu, velocity, side, seed: seed);
    final seam = grip.seamForce(side, seed: seed);
    final orient = grip.seamOrient;
    final base = BallFlight.fly(pos, v0, V3.zero, seamOrient: orient).cross;
    final c = BallFlight.fly(pos, v0, omega, seam: seam, seamOrient: orient).cross;
    final g = PitchCatalog.groupOf(name);
    final clockDeg = grip.moveClock;
    return SpinResult(name, g, speed, grip.rpmAt(velocity), grip.knuckle ? 0 : grip.efficiency, omega, (c.x - base.x) * 100 * side, (c.z - base.z) * 100, targetH, targetV, seam, orient,
        clockDeg / 30 == 0 ? 12 : clockDeg / 30, grip);
  }

  /// 打ち出し：ゾーンの真ん中へ（重力の分だけ上へ）
  static (V3, V3) _launch(V3 pos, double speed) {
    final d = V3(0, FieldSpec.plateFrontY, 0.80) - pos;
    final horiz = m.sqrt(d.x * d.x + d.y * d.y), tG = horiz / (speed * 0.95);
    final v0 = BallFlight.dirOf(m.atan2(d.x, -d.y), m.atan2(d.z + 0.5 * BallSpec.gravity * tG * tG, horiz)) * speed;
    return (v0, v0.unit);
  }

  /// 投手の持ち球の1つを、握りが決まっていればその握りで、無ければ球種表から握りを決めて求める
  static SpinResult of(Pitch p, {required V3 pos, required int armAngle, required bool lefty, required int velocity, required int fbSharp, required int fbHeavy, int seed = 0}) {
    final g = p.grip;
    if (g != null) return fromGrip(g, name: p.name, pos: pos, lefty: lefty, velocity: velocity, seed: seed);
    return solve(p, pos: pos, armAngle: armAngle, lefty: lefty, velocity: velocity, fbSharp: fbSharp, fbHeavy: fbHeavy, seed: seed);
  }

  /// ストレートの変化（cm。H＋＝投げる腕の側、V＋＝上）
  static (double, double) fastballMove(int armAngle, int velocity, int sharp, int heavy) {
    final mag = (43 + (velocity - 145) * 0.5 + (sharp - 60) * 0.12 - (heavy - 60) * 0.08).clamp(28.0, 58.0);
    final dir = m.min(88.0, armAngle * 0.72 + 5) * deg; // 真上から投げる腕の側へ
    return (mag * m.sin(dir), mag * m.cos(dir));
  }

  /// 球種の変化の目標（cm）
  static (double, double) targetMove(Pitch p, {required int armAngle, required int velocity, required int fbSharp, required int fbHeavy}) {
    final fb = fastballMove(armAngle, velocity, fbSharp, fbHeavy);
    if (p.name == 'ストレート' || p.breakLevel <= 0 && PitchCatalog.groupOf(p.name) == 'ストレート系') return fb;
    if (p.name == 'イーファスピッチ') return (fb.$1 * 0.3, fb.$2 * 0.3);
    if (p.name == 'ナックル') return (0, 0);
    final g = PitchCatalog.groupOf(p.name);
    final mag = p.breakLevel / 100 * 70;
    final a = p.angle * deg;
    // 曲げる球は回転の軸が傾き、ストレートの浮き上がり・シュート回転を失う（変化が大きいほど）
    final keep = switch (g) {
      'スライダー系' || 'カーブ系' => 1 - m.min(1.0, p.breakLevel / 70) * 0.8,
      'ストレート系' => 1 - p.breakLevel / 100 * 0.6,
      _ => 1.0,
    };
    final lose = (g == 'スライダー系' || g == 'カーブ系') ? 0.2 * p.breakLevel : 0.0;
    final heavy = (p.heaviness - 60) * 0.05;
    return (fb.$1 * keep + m.cos(a) * mag, fb.$2 * keep - m.sin(a) * mag - lose - heavy);
  }

  /// 球種表の変化から回転を逆算し、それを生む握り（6つの量）を求める。pos：リリース位置、lefty：左投げ、seed：ナックルの揺れ（毎球変える）
  static SpinResult solve(Pitch p, {required V3 pos, required int armAngle, required bool lefty, required int velocity, required int fbSharp, required int fbHeavy, int seed = 0}) {
    final g = PitchCatalog.groupOf(p.name).isEmpty ? (p.breakLevel <= 20 ? 'ストレート系' : 'スライダー系') : PitchCatalog.groupOf(p.name);
    final speed = p.speed / 3.6;
    final tgt = targetMove(p, armAngle: armAngle, velocity: velocity, fbSharp: fbSharp, fbHeavy: fbHeavy);
    final side = lefty ? 1.0 : -1.0; // 投げる腕の側（本塁基準の x）
    final tx = tgt.$1 / 100 * side, tz = tgt.$2 / 100;
    final (v0, vu) = _launch(pos, speed);
    final d = V3(0, FieldSpec.plateFrontY, 0.80) - pos;
    final horiz = m.sqrt(d.x * d.x + d.y * d.y);
    final e1 = vu.cross(V3.ez).unit; // この向きの回転 → 上へ
    final e2 = vu.cross(V3.ex.perpTo(vu).unit).unit; // → x の＋へ
    final sswC = _ssw[p.name] ?? 0;
    final seamGrip = Grip(seamAsym: (sswC / 0.07).clamp(0.0, 1.0), seamDir: 121);
    final orient = seamGrip.seamOrient;
    final seam = seamGrip.seamForce(side);
    final base = BallFlight.fly(pos, v0, V3.zero, seamOrient: orient).cross;
    // 回転数の決め方：変化に効く回転 ÷ その球種の回転効率（系統ごとの範囲に収める）
    final e0 = _eff[p.name] ?? _groupEff[g] ?? 0.85;
    final range = p.name == 'イーファスピッチ' ? (700.0, 1400.0) : (_rpmRange[g] ?? (1500.0, 2800.0));
    double rpmOf(double wTrpm) {
      final r = (wTrpm / e0 * (1 + (p.sharpness - 60) * 0.003)).clamp(range.$1, range.$2);
      return r < wTrpm ? wTrpm : r;
    }

    final gyroSign = (g == 'シンカー系' || g == 'フォーク系') ? -1.0 : 1.0;
    // ジャイロ成分も入れて飛ばす（重力で進む向きが曲がると、ジャイロにも少し変化が出る）
    V3 omegaOf(double a, double b) {
      final wT = m.sqrt(a * a + b * b), wTot = rpmOf(wT * 60 / (2 * m.pi)) * 2 * m.pi / 60;
      return e1 * a + e2 * b + vu * (m.sqrt(m.max(0, wTot * wTot - wT * wT)) * gyroSign * (side > 0 ? -1 : 1));
    }

    (double, double) move(double a, double b, SeamForce sf) {
      final c = BallFlight.fly(pos, v0, omegaOf(a, b), seam: sf, seamOrient: orient).cross;
      return (c.x - base.x, c.z - base.z);
    }

    // 最初の見当：必要な揚力係数 → 回転パラメータ → 角速度
    final tFl = horiz / (speed * 0.93);
    double guess(double mv) {
      final acc = 2 * mv.abs() / (tFl * tFl);
      final cl = (acc * BallSpec.mass / (0.5 * BallSpec.airDensity * BallSpec.area * speed * speed) / 0.92).clamp(0.0, 0.40);
      final s = 0.4 * cl / (1 - 2.32 * cl);
      return s * speed / BallSpec.radius * (mv < 0 ? -1 : 1);
    }

    var wa = guess(tz), wb = guess(tx);
    if (p.name != 'ナックル') {
      for (var it = 0; it < 4; it++) {
        final mv = move(wa, wb, seam);
        final ex = tx - mv.$1, ez = tz - mv.$2;
        if (ex.abs() < 0.003 && ez.abs() < 0.003) break;
        const h = 8.0;
        final ma = move(wa + h, wb, seam), mb = move(wa, wb + h, seam);
        final j11 = (ma.$1 - mv.$1) / h, j21 = (ma.$2 - mv.$2) / h, j12 = (mb.$1 - mv.$1) / h, j22 = (mb.$2 - mv.$2) / h;
        final det = j11 * j22 - j12 * j21;
        if (det.abs() < 1e-12) break;
        wa += (j22 * ex - j12 * ez) / det;
        wb += (-j21 * ex + j11 * ez) / det;
      }
    } else {
      wa = 0;
      wb = 0;
    }
    final wT = m.sqrt(wa * wa + wb * wb); // rad/s
    final wTrpm = wT * 60 / (2 * m.pi);
    double rpm;
    if (p.name == 'ナックル') {
      rpm = 80 + (seed % 150).toDouble();
    } else {
      rpm = rpmOf(wTrpm);
    }
    final eff = rpm <= 0 ? 0.0 : (wTrpm / rpm).clamp(0.0, 1.0);
    final thumb = _thumbOf(p.name, g);
    final grip = Grip.fit(
      rpm: rpm, efficiency: eff, wUp: wa, wArm: wb * side, speedRatio: p.speed / velocity, velocity: velocity,
      sswCoef: sswC, sswDir: 121, thumb: thumb, gyroSign: gyroSign, knuckle: p.name == 'ナックル',
    );
    // 握りが元：握りから回転・球速・縫い目の力を出し直す（球種表の値とほぼ一致する）
    return fromGrip(grip, name: p.name, pos: pos, lefty: lefty, velocity: velocity, seed: seed, targetH: tgt.$1, targetV: tgt.$2);
  }
}
