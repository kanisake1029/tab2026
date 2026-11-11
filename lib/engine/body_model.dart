import 'dart:math';
import '../models/player.dart';

/// 体格 → 体節の長さ・太さ・質量（m・kg）
///  長さは身長に対する比（Drillis & Contini）、腕は「腕の長さ」（肩先〜中指先）に合わせて上腕・前腕・手を伸び縮みさせる
///  質量は体重に対する比（Dempster / Winter）、胴の太さは胸囲・腹囲・臀囲（楕円とみなす）から
class BodyModel {
  final double height, weight;
  final double upperArm, forearm, hand; // 肩〜肘・肘〜手首・手首〜中指先
  final double thigh, shank, footLen, ankleH;
  final double hipJointH; // 立ったときの股関節の高さ
  final double trunk; // 骨盤の中心〜首の付け根
  final double neck, headR; // 首の長さ、頭の半径
  final double shoulderW, hipW; // 両肩（肩関節の中心）の幅、両股関節の間
  final double chestA, chestB, waistA, waistB, hipA, hipB; // 胴の楕円の半径（横・前後）
  final double upperArmR, forearmR, thighR, shankR; // 手足の太さ（半径）
  final double eyeH; // 立ったときの目の高さ

  BodyModel._(this.height, this.weight, this.upperArm, this.forearm, this.hand, this.thigh, this.shank, this.footLen, this.ankleH, this.hipJointH, this.trunk, this.neck,
      this.headR, this.shoulderW, this.hipW, this.chestA, this.chestB, this.waistA, this.waistB, this.hipA, this.hipB, this.upperArmR, this.forearmR, this.thighR, this.shankR, this.eyeH);

  /// 楕円の周囲 g（横÷前後＝k）→ 前後の半径（周囲 ≒ 2π√((a²+b²)/2)）
  static double _semiB(double g, double k) => g / (2 * pi * sqrt((k * k + 1) / 2));

  factory BodyModel.of({required int heightCm, required int weightKg, required int armCm, int headCm = 57, int chestCm = 98, int waistCm = 82, int hipCm = 98}) {
    final h = heightCm / 100.0, w = weightKg.toDouble();
    final arm = armCm / 100.0;
    final armScale = arm / (h * (0.186 + 0.146 + 0.108));
    final cb = _semiB(chestCm / 100, 1.40), wb = _semiB(waistCm / 100, 1.25), hb = _semiB(hipCm / 100, 1.30);
    final bmi = w / (h * h);
    final fat = (bmi - 22) / 8; // 太さの寄せ（筋肉・脂肪）
    return BodyModel._(
      h, w,
      h * 0.186 * armScale, h * 0.146 * armScale, h * 0.108 * armScale,
      h * 0.245, h * 0.246, h * 0.152, h * 0.039,
      h * 0.530,
      h * 0.298,
      h * 0.052, (headCm / 100) / (2 * pi) * 1.02,
      h * 0.212, h * 0.100,
      cb * 1.40, cb, wb * 1.25, wb, hb * 1.30, hb,
      h * (0.024 + 0.006 * fat), h * (0.019 + 0.004 * fat), h * (0.042 + 0.009 * fat), h * (0.027 + 0.005 * fat),
      h * 0.936,
    );
  }

  factory BodyModel.ofPlayer(Player p) => BodyModel.of(
      heightCm: p.height, weightKg: p.weight, armCm: p.armLength, headCm: p.headGirth, chestCm: p.chestGirth, waistCm: p.waistGirth, hipCm: p.hipGirth);

  /// 長さだけを置き換えた体（3D の人体の骨に合わせるとき）
  BodyModel copyWith({double? height, double? upperArm, double? forearm, double? hand, double? thigh, double? shank, double? footLen, double? ankleH, double? hipJointH, double? trunk, double? neck, double? headR, double? shoulderW, double? hipW, double? eyeH}) =>
      BodyModel._(height ?? this.height, weight, upperArm ?? this.upperArm, forearm ?? this.forearm, hand ?? this.hand, thigh ?? this.thigh, shank ?? this.shank, footLen ?? this.footLen,
          ankleH ?? this.ankleH, hipJointH ?? this.hipJointH, trunk ?? this.trunk, neck ?? this.neck, headR ?? this.headR, shoulderW ?? this.shoulderW, hipW ?? this.hipW,
          chestA, chestB, waistA, waistB, hipA, hipB, upperArmR, forearmR, thighR, shankR, eyeH ?? this.eyeH);

  double get legLen => thigh + shank;

  /// 手首〜ボールの中心（指の付け根あたりで握る）
  double get handToBall => hand * 0.62;

  // 体節の質量（体重に対する比）
  double get massUpperArm => weight * 0.028;
  double get massForearm => weight * 0.016;
  double get massHand => weight * 0.006;
  double get massThigh => weight * 0.100;
  double get massShank => weight * 0.0465;
  double get massFoot => weight * 0.0145;
  double get massHead => weight * 0.081;
  double get massTrunk => weight * 0.497;
}
