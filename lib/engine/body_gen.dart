import 'dart:math';
import '../models/pitching_form.dart';

/// 文字列の安定したハッシュ（FNV-1a 32bit）。Dart の hashCode は Web とネイティブで値が違うので、
/// 体格・フォームのように「どこで計算しても同じ値」が要るものはこれを使う
int stableHash(String s, [int salt = 0]) {
  var h = 0x811c9dc5 ^ (salt & 0xffffffff);
  for (final c in s.codeUnits) {
    h ^= c & 0xff;
    h = (h * 0x01000193) & 0xffffffff;
    h ^= (c >> 8) & 0xff;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return h & 0x7fffffff;
}

/// 体格・フォームの自動の値（選手の id と能力から、毎回同じ値になる）
///  体重：BMI 21〜30（パワー・球威が高いほど重い）
///  腕の長さ（肩先〜中指先）：身長×0.43〜0.47
///  頭囲・胸囲・腹囲・臀囲：身長と BMI から
class BodyGen {
  static Random _r(String id, int salt) => Random(stableHash(id, salt));

  static double _g(Random r) {
    final u1 = 1.0 - r.nextDouble();
    final u2 = r.nextDouble();
    return sqrt(-2.0 * log(u1)) * cos(2.0 * pi * u2);
  }

  /// 身長（以前のデータで決まっていなかった選手）：平均181cm（投手は+1.5）・ばらつき約6cm
  static int height(String id, bool pitcher) => (181 + (pitcher ? 1.5 : 0) + _g(_r(id, 0x4e16)) * 5.8).round().clamp(165, 201);

  /// BMI（体重を決めるもと）
  static double bmi(String id, {required int power, required int pitchPower, required bool pitcher}) {
    final r = _r(id, 0xb0d1);
    final strength = pitcher ? pitchPower : power;
    return (25.4 + (strength - 50) * 0.06 + _g(r) * 1.7).clamp(21.0, 32.0);
  }

  static int weight(String id, int height, {required int power, required int pitchPower, required bool pitcher}) {
    final h = height / 100.0;
    return (bmi(id, power: power, pitchPower: pitchPower, pitcher: pitcher) * h * h).round();
  }

  static int armLength(String id, int height, {required int arm, required int velocity}) {
    final r = _r(id, 0xa2b3);
    final ratio = (0.448 + _g(r) * 0.009 + (arm - 50) * 0.00008 + (velocity - 145) * 0.0001).clamp(0.425, 0.475);
    return (height * ratio).round();
  }

  static int headGirth(String id, int height) => (56.5 + (height - 178) * 0.05 + _g(_r(id, 0x4ead)) * 1.1).round().clamp(52, 62);

  static int chestGirth(String id, int height, double bmi) => (height * 0.52 + (bmi - 22) * 2.4 + _g(_r(id, 0xc4e5)) * 2.5).round().clamp(84, 130);

  static int waistGirth(String id, int height, double bmi) => (height * 0.43 + (bmi - 22) * 3.2 + _g(_r(id, 0x3a15)) * 2.5).round().clamp(68, 125);

  static int hipGirth(String id, int height, double bmi) => (height * 0.52 + (bmi - 22) * 2.2 + _g(_r(id, 0x41b0)) * 2.2).round().clamp(84, 128);

  /// 腕の角度（spinAxis）：オーバー35%・スリークォーター50%・サイド10%・アンダー5%
  static int spinAxis(String id) {
    final r = _r(id, 0x5a15);
    final x = r.nextDouble();
    if (x < 0.35) return 5 + r.nextInt(26); // 5〜30
    if (x < 0.85) return 31 + r.nextInt(30); // 31〜60
    if (x < 0.95) return 70 + r.nextInt(31); // 70〜100
    return 115 + r.nextInt(36); // 115〜150
  }

  /// フォームの自動の値（能力と合うように：球速が速いほど踏み出し・捻転差が大きい、制球がよいほどテイクバックがコンパクト）
  static PitchingForm form(String id, {required int velocity, required int control, required int stamina}) {
    final r = _r(id, 0xf0a7);
    final x = r.nextDouble();
    final windup = x < 0.25 ? 'ワインドアップ' : (x < 0.70 ? 'ノーワインドアップ' : (x < 0.96 ? 'セットポジション' : 'トルネード'));
    int clampI(double v, int lo, int hi) => v.round().clamp(lo, hi);
    final fast = (velocity - 145) / 10.0;
    final f = PitchingForm(
      windup: windup,
      legLiftHeight: clampI(55 + _g(r) * 16 + (windup == 'トルネード' ? 12 : 0) + (windup == 'セットポジション' ? -8 : 0), 10, 100),
      legLiftMs: clampI(520 + _g(r) * 110 + (windup == 'ワインドアップ' ? 80 : 0), 250, 900),
      holdMs: clampI(140 + _g(r) * 90 + (windup == 'トルネード' ? 120 : 0), 0, 600),
      strideRatio: clampI(84 + fast * 2.5 + _g(r) * 3, 72, 96),
      takeback: clampI(50 - (control - 50) * 0.4 + _g(r) * 15, 0, 100),
      hipShoulderSep: clampI(40 + fast * 4 + _g(r) * 6, 20, 65),
      extension: clampI(50 + fast * 6 + _g(r) * 14, 0, 100),
      tempo: clampI(50 + _g(r) * 18, 0, 100),
    );
    // 生体力学の細目（あとから足した項目。上の値が変わらないよう、乱数は後ろで引く）
    final r2 = _r(id, 0x2b7c);
    final y = r2.nextDouble();
    f.rubberPos = y < 0.45 ? 0 : clampI(_g(r2) * 14, -30, 30); // 中央が多い。左右に寄せる投手も
    final hh = r2.nextDouble();
    f.handHold = hh < 0.2 ? 0 : (hh < 0.75 ? 1 : 2);
    f.counterRot = clampI(15 + _g(r2) * 6 + (windup == 'トルネード' ? 12 : 0), 0, 30);
    f.kneeDrop = clampI(36 + _g(r2) * 9 + (stamina - 50) * 0.05, 18, 62);
    f.stepOffset = clampI(_g(r2) * 7, -20, 25);
    f.merDeg = clampI(172 + fast * 3 + _g(r2) * 5, 158, 186);
    f.trunkFlex = clampI(37 + fast * 1.5 + _g(r2) * 3.5, 28, 46);
    return f;
  }
}
