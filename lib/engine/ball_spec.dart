import 'dart:math';
import 'vec3.dart';

/// ボールと球場の寸法（物理・3D描画・打球計算で共通に使う）
///  ボール：重さ 145g、周囲 23cm（直径 約7.32cm）、縫い目の高さ 0.9mm・幅 0.8cm、108針
class BallSpec {
  static const mass = 0.145; // kg
  static const circumference = 0.23; // m
  static const radius = circumference / (2 * pi); // 約0.0366m
  static const diameter = radius * 2;
  static const area = pi * radius * radius; // 断面積 約42.1cm²
  static const seamHeight = 0.0009; // m
  static const seamWidth = 0.008; // m
  static const stitches = 108;

  /// 慣性モーメント（中身の詰まった球より芯が重いので 0.4 より少し小さい）
  static const inertia = 0.37 * mass * radius * radius;

  static const airDensity = 1.20; // kg/m³（20℃・海抜0m）
  static const gravity = 9.80;

  /// 回転の減り方（e で割れるまでの秒数）
  static const spinDecayTau = 1.6;

  /// 抗力係数：速さ v（m/s）、回転パラメータ S（＝半径×角速度÷速さ）、縫い目の向き seam（4シーム 0.9・2シーム 1.1）
  ///  縫い目が高いほど空気を乱して少し増える。遅い球ほど増える（臨界より下）
  static double cd(double v, double s, {double seam = 1.0}) {
    final seamTerm = (seamHeight / 0.0008 - 1) * 0.05 * seam;
    final slow = ((32 - v) / 12).clamp(0.0, 1.0) * 0.06;
    return 0.30 + 0.16 * s.clamp(0.0, 0.5) + seamTerm + (seam - 1) * 0.02 + slow;
  }

  /// 揚力係数（マグヌス力）：Nathan の形 CL = S / (2.32S + 0.4) を、実測（回転数と変化量。ストレート 2300rpm で約45cm）に合わせて 0.92 倍
  static double cl(double s) => s <= 0 ? 0 : 0.92 * s / (2.32 * s + 0.4);

  /// 縫い目の中心線（半径1の球の上の閉じた曲線。t は 0〜2π）
  ///  x = a cos t + b cos 3t、y = a sin t − b sin 3t、z = 2√(ab) sin 2t は半径 a+b の球に乗る
  static V3 seamPoint(double t) {
    const a = 1.0, b = 0.4;
    final s = sqrt(a * b);
    return V3(a * cos(t) + b * cos(3 * t), a * sin(t) - b * sin(3 * t), 2 * s * sin(2 * t)) / (a + b);
  }
}

/// 球場の寸法（本塁基準の座標：x＝一塁側、y＝投手の方向、z＝上）
class FieldSpec {
  static const rubberFrontY = 18.44; // 本塁の後ろの角から投手板の前の縁まで
  static const rubberDepth = 0.152; // 投手板の奥行き
  static const rubberWidth = 0.61;
  static const moundHeight = 0.254;
  static const plateFrontY = 0.4318; // 本塁の前の縁（到達点はここで測る）
  static const plateHalfWidth = 0.2159;

  /// マウンドの高さ（y：本塁基準）。投手板の前 15cm から 1フィートにつき 1インチ下がる
  static double groundZ(double y) {
    final d = rubberFrontY - y; // 投手板の前の縁から本塁側への距離
    if (d < -0.8) return 0; // 投手板の後ろ
    if (d <= rubberDepth) return moundHeight;
    return max(0.0, moundHeight - (d - rubberDepth) / 12);
  }
}
