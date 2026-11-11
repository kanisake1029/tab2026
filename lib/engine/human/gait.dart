import 'dart:math' as m;

import '../body_model.dart';
import '../vec3.dart';
import 'rot.dart';

/// 【Layer 1】二足の歩行・走行（接地の拘束つき）
///  ・歩幅 L＝0.8＋0.15v（m）、ケイデンス f＝1.8＋0.32v（歩/秒）で位相を進める
///  ・接地している足は着いた地点に固定（地面を滑らない）。遊脚は高さ 0.08＋0.04v まで上げて、次の着地点へ弧を描く
///  ・加速で前傾（a×6°、−20°〜45°）、曲がるときは内側へ傾く（atan(vω/g)）
///  ・腕は反対の脚と逆位相（右脚が前のとき左腕が前）
class GaitFrame {
  final V3 footT, footG; // 足首の目標（地面からの高さ込み）
  final double heelT, heelG; // かかとを上げる量（m）
  final double lean, bank; // 前傾・内傾（度）
  final double armT, armG; // 腕の振り（＋＝前、−1〜1）
  final double drop; // 骨盤を下げる量（m）
  final double k; // 走りの強さ 0〜1.2
  const GaitFrame(this.footT, this.footG, this.heelT, this.heelG, this.lean, this.bank, this.armT, this.armG, this.drop, this.k);
}

class Gait {
  final BodyModel b;
  final double sT; // T の側（右＝＋1）
  Gait(this.b, {this.sT = 1});

  double phase = 0; // T の足の位相 0〜1（1周期＝左右1歩ずつ）
  final List<V3?> _pin = [null, null]; // 接地している足の位置
  final List<V3?> _lift = [null, null]; // 離地した位置
  final List<bool> _stance = [true, true];
  double _lastT = double.nan;

  /// いま接地しているか（0＝T、1＝G）
  bool inStance(int s) => _stance[s];

  void reset() {
    _pin[0] = _pin[1] = null;
    _lift[0] = _lift[1] = null;
    _stance[0] = _stance[1] = true;
    _lastT = double.nan;
  }

  static double stepLen(double v) => 0.8 + 0.15 * v;
  static double cadence(double v) => 1.8 + 0.32 * v;

  /// t：時刻（巻き戻しや飛ばしは reset）。pos：骨盤の真下の地面、vel：速度、acc：前への加速度、turn：向きの変わる速さ（rad/s）、h：体の向き
  GaitFrame step(double t, V3 pos, V3 vel, double acc, double turn, double h) {
    final dt = _lastT.isNaN ? 0.0 : t - _lastT;
    if (dt < 0 || dt > 0.3) reset();
    _lastT = t;
    final v = V3(vel.x, vel.y, 0).length;
    final k = (v / 8.5).clamp(0.0, 1.2);
    final f = cadence(v);
    final period = 2 / f;
    phase = (phase + (dt > 0 && dt <= 0.3 ? dt / period : 0)) % 1.0;
    // 接地している割合：歩き 0.6 → 走り（2.5m/s〜）0.35 → 全力 0.23
    final dWalk = 0.60 - 0.06 * v.clamp(0.0, 2.0), dRun = (0.40 - 0.02 * v).clamp(0.22, 0.40);
    final duty = v <= 1.6 ? dWalk : (v >= 2.2 ? dRun : dWalk + (dRun - dWalk) * (v - 1.6) / 0.6);
    final fw = V3(m.sin(h), m.cos(h), 0), rt = V3(m.cos(h), -m.sin(h), 0);
    final vdir = v > 0.05 ? V3(vel.x, vel.y, 0) / v : fw;
    final width = b.hipW * (0.5 - 0.08 * k.clamp(0.0, 1.0)); // 走るほど足の着く線は体の中心へ
    final half = v * duty * period / 2; // 接地のあいだに体が進む距離の半分（着地は体の前、離地は後ろ）
    final hLift = 0.08 + 0.04 * v; // 遊脚の高さ
    V3 landAt(int s, double tau) {
      final xs = s == 0 ? sT : -sT;
      return pos + V3(vel.x, vel.y, 0) * tau + vdir * (half * 0.85) + rt * (xs * width) + V3(0, 0, b.ankleH); // 着地は体の少し前、離地は後ろ
    }

    final feet = <V3>[], heels = <double>[];
    for (var s = 0; s < 2; s++) {
      final q = (phase + (s == 0 ? 0 : 0.5)) % 1.0;
      final inStance = q < duty;
      if (inStance && !_stance[s]) {
        _pin[s] = landAt(s, 0); // 着地：この地点に固定
      }
      if (!inStance && _stance[s]) {
        _lift[s] = _pin[s] ?? landAt(s, 0); // 離地
      }
      _stance[s] = inStance;
      if (inStance) {
        // 体から離れすぎた固定点（止まった・向きを変えた・始め）は、いまの着地点へ
        final pin = _pin[s];
        if (pin == null || V3(pin.x - pos.x, pin.y - pos.y, 0).length > half * 1.3 + 0.9) _pin[s] = landAt(s, -(q / duty) * duty * period);
        feet.add(_pin[s]!);
        // 蹴り出し：接地の後半でかかとが上がる
        heels.add((0.06 + 0.06 * k) * ((q / duty - 0.45) / 0.55).clamp(0.0, 1.0));
      } else {
        final u = (q - duty) / (1 - duty); // 遊脚の進み 0〜1
        final tau = (1 - u) * (1 - duty) * period;
        final land = landAt(s, tau);
        final from = _lift[s] ?? land;
        final e = u * u * (3 - 2 * u);
        var p = from.lerp(land, e);
        // 走るときは、まずかかとを尻へ引き上げてから、ひざを前へ出す
        final kick = (0.10 + 0.28 * k) * m.sin(m.pi * m.min(1.0, u * 1.8)) * (1 - u) * k;
        p = p - vdir * (0.15 * k * m.sin(m.pi * m.min(1.0, u * 2.0)) * (1 - u)) + V3(0, 0, hLift * m.sin(m.pi * u) + kick);
        feet.add(p);
        heels.add(0.04);
      }
    }
    // 前傾（加速）・内傾（曲がる）
    final lean = clampD(acc * 6, -20, 45) + 3 + 6 * k;
    final bank = m.atan(v * turn / 9.8) / deg;
    // 腕：T の脚が前（着地 q=0 付近）のとき T の腕は後ろ
    final armT = -m.cos(2 * m.pi * (phase - duty / 2));
    // 骨盤：接地の真ん中で一番低い
    final bob = (0.015 + 0.03 * k) * m.cos(4 * m.pi * (phase - duty / 2));
    return GaitFrame(feet[0], feet[1], heels[0], heels[1], lean, clampD(bank, -30, 30), armT, -armT, 0.05 + 0.07 * k - bob, k);
  }
}
