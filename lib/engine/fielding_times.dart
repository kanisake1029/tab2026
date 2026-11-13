/// 守備・走塁の「この動作に何秒」の表（能力 → 秒・速さ）。
///
/// 守備と走塁は、野手の処理の速さと走者・打者の速さの勝負なので、打者と投手のように水準合わせはしない。
/// 能力 30・60・90 の3点の値を決めて、間を直線でつなぐ（30 より下・90 より上も、同じ傾きで伸ばす）。
/// 調整するときは、ここの値を書き換える。値を変えたら、tool/balance の検証（BABIP・失策・盗塁）で確かめる。
///
/// いまの値は、仕様書 6.1 の式と同じ（表にまとめただけで、結果は変わらない）。実際のプロの計測値との突き合わせは、これから。
library;

/// 能力（1〜100）→ 値。30・60・90 の3点を決めて、直線でつなぐ
class AbilityCurve {
  final double at30, at60, at90;
  const AbilityCurve(this.at30, this.at60, this.at90);

  double at(num ability) {
    final a = ability.clamp(1, 100).toDouble();
    return a <= 60 ? at60 + (at30 - at60) * (60 - a) / 30 : at60 + (at90 - at60) * (a - 60) / 30;
  }
}

class FieldTimes {
  /// 打球に反応して動き出すまで（秒）。守備力。守備60 で 0.28 秒、GG クラス（90）で 0.205 秒。投手は投げ終わりの体勢から +0.25 秒
  static const reaction = AbilityCurve(0.355, 0.28, 0.205);

  /// 落下点の見極め（秒）。外野手はフライの軌道を読むので長い。その間は6割の速さで寄る
  static const judgeInfield = AbilityCurve(0.32, 0.26, 0.20);
  static const judgeOutfield = AbilityCurve(0.46, 0.40, 0.34);

  /// 標準のステップ送球の握り替え（捕ってから投げ始めるまでの基準の秒）。送球の正確さ。ほかの投げ方（素手・ノーステップ・ジャンピング・クロウホップ）は、この比率で伸び縮みする
  static const transferSec = AbilityCurve(0.76, 0.67, 0.58);

  /// 最大送球初速（km/h）。肩の強さ。クロウホップの遠投。肩60 で 139km/h、90 で 153km/h
  static const throwKmh = AbilityCurve(124.4, 138.8, 153.2);

  /// 最高走速度（m/s）。走力。走力60 で 8.48m/s、90 で 9.32m/s
  static const sprintMs = AbilityCurve(7.64, 8.48, 9.32);

  /// 握り替えの比率（送球の正確さ 60 を 1 とする）
  static double transferRatio(num accuracy) => transferSec.at(accuracy) / transferSec.at60;
}
