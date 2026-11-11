import 'dart:math' as m;

import 'body_model.dart';
import 'human/gait.dart';
import 'pitch_motion.dart' show J;
import 'vec3.dart';

/// 守備・走塁・打撃の動き（第5段階）：最小動作（defense_ai.dart の Motion）を、関節の位置（15本の骨）にする
///  座標は本塁基準（x＝一塁側、y＝中堅方向、z＝上）。向き h はラジアン（0＝中堅方向、＋＝一塁側へ回る）
///  脚・腕は2本の骨の逆運動学（体の寸法どおりの長さ）で、足先・手先の目標に合わせる
///  投げる・打つは、局面ごとの姿勢（キーフレーム）をなめらかにつなぐ（腰が先に回り、肩があとから追う）
class Poser {
  final BodyModel b;
  final bool lefty; // T（投げる腕・打者の後ろの手の側）が左
  Poser(this.b, {this.lefty = false});

  /// 直前の姿勢の見る点（Layer 1 の首の向きに渡す）
  V3? lastLook;

  double get _sT => lefty ? -1.0 : 1.0;
  double get _top => b.hipJointH + b.trunk; // 首の付け根の高さ（立ったとき）

  static V3 fwdOf(double h) => V3(m.sin(h), m.cos(h), 0);
  static V3 rightOf(double h) => V3(m.cos(h), -m.sin(h), 0);

  /// 2歩ぶん（左右1回ずつ）で進む距離（m）：速いほど歩幅が大きい
  static double cycleLen(double v) => 1.2 + 0.30 * v.clamp(0.0, 10.0);

  /// 2本の骨の逆運動学：根元 a・先 t・長さ l1,l2・曲げる向きのヒント hint → 中間の関節
  static V3 ik(V3 a, V3 t, double l1, double l2, V3 hint) {
    var d = t - a;
    var len = d.length;
    final maxL = (l1 + l2) * 0.999;
    if (len > maxL) {
      d = d.unit * maxL;
      len = maxL;
    }
    if (len < 1e-4) return a + hint.unit * l1;
    final u = d / len;
    final aa = (l1 * l1 - l2 * l2 + len * len) / (2 * len);
    final hh = m.sqrt(m.max(0.0, l1 * l1 - aa * aa));
    var p = hint.perpTo(u);
    if (p.length < 1e-5) p = V3.ez.perpTo(u);
    return a + u * aa + p.unit * hh;
  }

  static double _ss(double x) {
    final t = x.clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  /// キーフレームの補間（us は昇順の時刻 0〜1）
  static double kf(double u, List<double> us, List<double> vs) {
    if (u <= us.first) return vs.first;
    for (var i = 0; i + 1 < us.length; i++) {
      if (u <= us[i + 1]) return vs[i] + (vs[i + 1] - vs[i]) * _ss((u - us[i]) / (us[i + 1] - us[i]));
    }
    return vs.last;
  }

  static V3 kv(double u, List<double> us, List<V3> vs) {
    if (u <= us.first) return vs.first;
    for (var i = 0; i + 1 < us.length; i++) {
      if (u <= us[i + 1]) return vs[i].lerp(vs[i + 1], _ss((u - us[i]) / (us[i + 1] - us[i])));
    }
    return vs.last;
  }

  /// 姿勢を組み立てる
  ///  root：骨盤の真下の地面の点、h：体（足・腰）の向き、hipTwist：腰だけのひねり（度、＋＝T の腰が前）、
  ///  drop：骨盤を下げる量（m）、lean：前傾（度）、twist：肩のひねり（度、h から。＋＝T の肩が前）、side：横の傾き（度）、
  ///  footT/footG：足首の目標、toeDirT/toeDirG：つま先の向き（null なら体の向き）、heelT/heelG：かかとを上げる量（m）、
  ///  handT/handG：手首の目標、look：見る点（null なら正面の遠く）
  List<V3> build({
    required V3 root,
    required double h,
    double hipTwist = 0,
    double drop = 0,
    double lean = 0,
    double twist = 0,
    double side = 0,
    V3? footT,
    V3? footG,
    V3? toeDirT,
    V3? toeDirG,
    double heelT = 0,
    double heelG = 0,
    required V3 handT,
    required V3 handG,
    V3? look,
    double throwArm = 0,
  }) {
    final p = List<V3>.filled(J.values.length, V3.zero);
    final f = fwdOf(h), r = rightOf(h);
    final sT = _sT;
    final hr = r.rotate(V3.ez, hipTwist * deg * sT); // 腰の線
    final hipFwd = V3(-hr.y, hr.x, 0); // r を反時計回りに90° ＝ 正面
    final pel = root + V3(0, 0, b.hipJointH - drop);
    p[J.pelvis.index] = pel;
    final hipT = pel + hr * (sT * b.hipW / 2), hipG = pel - hr * (sT * b.hipW / 2);
    p[J.hipT.index] = hipT;
    p[J.hipG.index] = hipG;
    // 足首が届かない所なら、脚を伸ばしきった所まで（足が浮く）
    V3 reachLeg(V3 hip, V3 t) {
      final d = t - hip, l = (b.thigh + b.shank) * 0.999;
      return d.length > l ? hip + d.unit * l : t;
    }

    final fT = reachLeg(hipT, (footT ?? V3(hipT.x, hipT.y, b.ankleH)) + V3(0, 0, heelT));
    final fG = reachLeg(hipG, (footG ?? V3(hipG.x, hipG.y, b.ankleH)) + V3(0, 0, heelG));
    p[J.ankleT.index] = fT;
    p[J.ankleG.index] = fG;
    // ひざは腰の正面へ（少し外）
    // ひざのポール（仕様書 1.3）：つま先の向き
    p[J.kneeT.index] = ik(hipT, fT, b.thigh, b.shank, (toeDirT ?? hipFwd) + hr * (sT * 0.05));
    p[J.kneeG.index] = ik(hipG, fG, b.thigh, b.shank, (toeDirG ?? hipFwd) - hr * (sT * 0.05));
    // つま先：かかとを上げた分だけ、つま先は地面に残る
    V3 toe(V3 a, V3? dir, double heel) {
      final d = (dir ?? hipFwd).unit;
      final z = m.max(0.02, a.z - b.ankleH - heel + 0.02);
      return V3(a.x, a.y, 0) + d * (b.footLen * 0.72) + V3(0, 0, z);
    }

    p[J.toeT.index] = toe(fT, toeDirT, heelT);
    p[J.toeG.index] = toe(fG, toeDirG, heelG);
    // 胴：前傾（腰の正面へ）・横の傾き
    // 右手の法則で、腰の右向きの軸のまわりに −lean 回すと前へ倒れる
    final up = V3.ez.rotate(hr, -lean * deg).rotate(hipFwd, side * deg);
    final neck = pel + up * b.trunk;
    p[J.neck.index] = neck;
    final sr = r.rotate(V3.ez, twist * deg * sT); // 肩の線（＋ひねり＝T の肩が前へ）
    final sh = neck - up * 0.06;
    final shT = sh + sr * (sT * b.shoulderW / 2), shG = sh - sr * (sT * b.shoulderW / 2);
    p[J.shoulderT.index] = shT;
    p[J.shoulderG.index] = shG;
    // 頭：胴が傾いても、首で起こして見る点へ向ける（目線は水平に近く）
    final lk = look ?? (neck + f * 20 + V3(0, 0, 0.0));
    lastLook = lk;
    final toLook = (lk - neck).unit;
    var hd = (V3.ez * 1.6 + up * 0.6 + toLook * 0.9).unit;
    p[J.head.index] = neck + hd * (b.neck + b.headR);
    // 腕：ひじのポール（仕様書 1.3）は背中側かつ下方（肋骨の横後方）。投げる腕は、コッキング〜リリースで肩の線の外側・水平へ
    final shF = V3(-sr.y, sr.x, 0); // 肩の正面
    //  手が体の前にあるときは、ひじは下・外（後ろへ回すと胸の後ろへ入る）
    double back(V3 hand, V3 sh) => ((hand - sh).dot(shF) < 0 && hand.z < sh.z - 0.2 ? 0.6 : 0.12);
    final poleT = (-V3.ez - shF * back(handT, shT) + sr * (sT * 0.3)) * (1 - throwArm) + (sr * sT + V3.ez * 0.1) * throwArm;
    final elT = ik(shT, handT, b.upperArm, b.forearm, poleT);
    final elG = ik(shG, handG, b.upperArm, b.forearm, -V3.ez - shF * back(handG, shG) - sr * (sT * 0.3));
    p[J.elbowT.index] = elT;
    p[J.elbowG.index] = elG;
    final wT = shT + (handT - shT).unit * m.min((handT - shT).length, (b.upperArm + b.forearm) * 0.999);
    final wG = shG + (handG - shG).unit * m.min((handG - shG).length, (b.upperArm + b.forearm) * 0.999);
    p[J.wristT.index] = wT;
    p[J.wristG.index] = wG;
    p[J.ball.index] = wT + (wT - elT).unit * (b.hand * 0.5);
    p[J.glove.index] = wG + (wG - elG).unit * (b.hand * 0.5);
    return p;
  }

  // ───────────── 最小動作 ─────────────

  /// 構え（PrePitch_Creep・SplitStep の後）：足を肩幅より広く、ひざを曲げ、両手はひざの前。目は打者（look）へ
  List<V3> ready(V3 at, double h, {double crouch = 0.7, V3? look}) {
    final f = fwdOf(h), r = rightOf(h);
    final w = b.hipW * 1.45;
    final hz = b.hipJointH * (1 - 0.42 * crouch);
    return build(
      root: at,
      h: h,
      drop: 0.13 * crouch,
      lean: 24 * crouch,
      footT: at + r * (_sT * w) + f * 0.02 + V3(0, 0, b.ankleH),
      footG: at - r * (_sT * w) + f * 0.06 + V3(0, 0, b.ankleH),
      toeDirT: (f + r * (_sT * 0.25)).unit,
      toeDirG: (f - r * (_sT * 0.25)).unit,
      handT: at + f * (0.30 + 0.25 * crouch) + r * (_sT * 0.16) + V3(0, 0, hz),
      handG: at + f * (0.32 + 0.25 * crouch) - r * (_sT * 0.14) + V3(0, 0, hz),
      look: look ?? at + f * 25 + V3(0, 0, 1.0),
    );
  }

  /// 立つ（プレーの後・審判）：ひざを軽く曲げ、腕は体の横。見る点へ顔を向ける
  List<V3> stand(V3 at, double h, {V3? look}) {
    final f = fwdOf(h), r = rightOf(h);
    final hz = _top - 0.06 - (b.upperArm + b.forearm) * 0.93; // 腕は自然に下ろす（ひじは少し曲がる）
    return build(
      root: at,
      h: h,
      drop: 0.01,
      lean: 4,
      footT: at + r * (_sT * b.hipW * 0.55) - f * 0.02 + V3(0, 0, b.ankleH),
      footG: at - r * (_sT * b.hipW * 0.55) + f * 0.06 + V3(0, 0, b.ankleH),
      toeDirT: (f + r * (_sT * 0.2)).unit,
      toeDirG: (f - r * (_sT * 0.2)).unit,
      handT: at + r * (_sT * (b.shoulderW / 2 + 0.04)) + f * 0.06 + V3(0, 0, hz), // 腕は体の横で、肘を少し曲げる
      handG: at - r * (_sT * (b.shoulderW / 2 + 0.04)) + f * 0.07 + V3(0, 0, hz + 0.01),
      look: look,
    );
  }

  /// 走る：v（m/s）、phase（走った距離 ÷ cycleLen。1で左右1歩ずつ）
  ///  片脚の1周期：接地（前で着いて体の下を後ろへ）→ 蹴り出し → かかとが尻へ上がる → ひざを前へ出して振り下ろす
  List<V3> run(V3 at, double h, double v, double phase, {V3? look}) {
    final f = fwdOf(h), r = rightOf(h);
    final k = (v / 8.5).clamp(0.0, 1.2);
    final sf = (0.42 - 0.17 * k).clamp(0.24, 0.45); // 接地している割合（走りはジョグでも両足が浮く時間がある。速いほど短い）
    final half = cycleLen(v) * sf / 2; // 接地中に足が体の下を動く距離の半分
    double ph(double x) => x - x.floorToDouble();
    final sT = _sT;
    // 片脚の足首の位置（体の真下の点から）
    (double, double) foot(double q) {
      q = ph(q);
      if (q < sf) return (half - 2 * half * (q / sf), 0.0); // 接地：前 → 後ろ
      final s = (q - sf) / (1 - sf);
      // 遊脚：まず後ろでかかとが上がり（尻へ）、ひざから前へ振り出して、前で下りる
      final x = -half + (2 * half + 0.10 * k) * _ss((s - 0.15) / 0.75) - 0.12 * k * m.sin(m.pi * m.min(1.0, s * 2.2));
      final lift = (0.06 + 0.22 * k) * m.sin(m.pi * s) + (0.10 + 0.30 * k) * m.sin(m.pi * m.min(1.0, s * 1.8)) * (1 - s);
      return (x, lift);
    }

    final qT = phase, qG = phase + 0.5;
    final (xT, zT) = foot(qT);
    final (xG, zG) = foot(qG);
    // 骨盤：接地の真ん中で一番低く、蹴り出しで上がる
    final bob = (0.015 + 0.03 * k) * m.cos(4 * m.pi * (ph(phase) - sf / 2));
    // 腕：反対側の脚と同じ向きに振る（肘は約90°）。前の手は胸の前、後ろの手は腰の後ろ
    V3 hand(double legX, double sideSign) {
      final a = (legX / m.max(0.2, half)).clamp(-1.3, 1.3); // ＋＝前
      final fwd = a > 0 ? 0.12 + a * (0.20 + 0.12 * k) : 0.10 + a * 0.16; // 後ろへは肩の伸展の範囲（ひじは開く）
      final up = b.hipJointH + 0.05 + (a > 0 ? a * (0.22 + 0.10 * k) : a * 0.10);
      return at + f * fwd + r * (sideSign * (0.20 - (a > 0 ? 0.06 * a : 0))) + V3(0, 0, up);
    }

    return build(
      root: at,
      h: h,
      drop: 0.04 + 0.05 * k - bob,
      lean: 4 + 10 * k,
      twist: -8 * (xT / m.max(0.2, half)) * k, // 脚と逆に肩が少し回る
      footT: at + f * xT + r * (sT * b.hipW * 0.42) + V3(0, 0, b.ankleH + zT),
      footG: at + f * xG - r * (sT * b.hipW * 0.42) + V3(0, 0, b.ankleH + zG),
      heelT: zT > 0.02 ? 0.04 : 0,
      heelG: zG > 0.02 ? 0.04 : 0,
      handT: hand(xG, sT), // T の手は G の脚と同じ向き
      handG: hand(xT, -sT),
      look: look ?? at + f * 25 + V3(0, 0, 1.2),
    );
  }

  /// 走る（Layer 1 の歩行エンジンの結果から）：足は接地点に固定、腕は脚と逆位相でひじ約90°、加速で前傾・曲がると内傾
  List<V3> runGait(V3 at, double h, GaitFrame g, {V3? look}) {
    final f = fwdOf(h), r = rightOf(h);
    final k = g.k;
    V3 hand(double a, double sideSign) {
      a = a * 1.15;
      final fwd = a > 0 ? 0.12 + a * (0.20 + 0.12 * k) : 0.10 + a * 0.16;
      final up = b.hipJointH + 0.05 + (a > 0 ? a * (0.22 + 0.10 * k) : a * 0.10);
      return at + f * fwd + r * (sideSign * (0.20 - (a > 0 ? 0.06 * a : 0))) + V3(0, 0, up);
    }

    return build(
      root: at,
      h: h,
      drop: g.drop,
      lean: g.lean,
      side: g.bank,
      twist: 8 * k * g.armT, // 腕と一緒に肩が少し回る
      footT: g.footT,
      footG: g.footG,
      heelT: g.heelT,
      heelG: g.heelG,
      handT: hand(g.armT, _sT),
      handG: hand(g.armG, -_sT),
      look: look ?? at + f * 25 + V3(0, 0, 1.2),
    );
  }

  /// ゴロの捕球（Field_Ground_Std）：u 0〜1。寄せながら腰を落とし（0〜0.45）、グラブを地面に（0.5で捕る）、両手で胸へ引き上げる
  ///  backhand：0〜1 で逆シングル寄り
  List<V3> fieldGround(V3 at, double h, double u, {double backhand = 0, V3? look}) {
    final f = fwdOf(h), r = rightOf(h);
    final sT = _sT;
    final uu = u.clamp(0.0, 1.0);
    final down = kf(uu, const [0, 0.45, 0.6, 1.0], const [0, 1, 1, 0.3]);
    final w = b.hipW * 1.9;
    final ground = at + f * 0.55 - r * (sT * (0.10 + backhand * 0.55)) + V3(0, 0, 0.10);
    final chest = at + f * 0.30 + V3(0, 0, _top - 0.15);
    final glove = uu < 0.55 ? (at + f * 0.6 + V3(0, 0, b.hipJointH * 0.7)).lerp(ground, _ss(uu / 0.5)) : ground.lerp(chest, _ss((uu - 0.55) / 0.45));
    return build(
      root: at,
      h: h,
      drop: 0.32 * down,
      lean: 15 + 40 * down,
      footT: at + r * (sT * w * 0.5) - f * 0.12 + V3(0, 0, b.ankleH),
      footG: at - r * (sT * w * 0.5) + f * 0.14 + V3(0, 0, b.ankleH),
      toeDirT: (f + r * (sT * 0.4)).unit,
      toeDirG: (f - r * (sT * 0.2)).unit,
      handT: glove + V3(0, 0, 0.10) + r * (sT * 0.06),
      handG: glove,
      look: look ?? ground,
    );
  }

  /// フライの捕球（Catch_Fly_Set）：グラブを顔の前の上へ、ボールを見る。ball：ボールの位置
  List<V3> catchFly(V3 at, double h, V3 ball) {
    final f = fwdOf(h), r = rightOf(h);
    final sT = _sT;
    final shG = at + V3(0, 0, _top - 0.06) - r * (sT * b.shoulderW / 2);
    var g = ball;
    final reach = (b.upperArm + b.forearm) * 0.92;
    if ((g - shG).length > reach) g = shG + (g - shG).unit * reach;
    return build(
      root: at,
      h: h,
      lean: -4,
      look: ball,
      footT: at + r * (sT * b.hipW * 0.6) - f * 0.12 + V3(0, 0, b.ankleH),
      footG: at - r * (sT * b.hipW * 0.6) + f * 0.18 + V3(0, 0, b.ankleH),
      handT: g + r * (sT * 0.10) - V3(0, 0, 0.10),
      handG: g,
    );
  }

  /// 送球（Footwork_ProStep / CrowHop → Throw_Overhand・ThreeQuarter）：h は投げる向き
  ///  u：0 構え（ボールはグラブの中）→ 0.3 踏み出し・テイクバック → 0.5 着地・トップ（肘は肩の高さ、グラブの腕は目標へ）
  ///  → 0.6 リリース（腰が先に回り、肩が追う）→ 0.8 フォロースルー（腕は反対のひざの外へ、後ろ脚が前へ抜ける）→ 1 戻り
  List<V3> throwBall(V3 at, double h, double u, {double armSlot = 30, V3? look}) {
    final f = fwdOf(h), r = rightOf(h);
    final sT = _sT;
    final rT = r * sT; // 投げる腕の側
    final uu = u.clamp(0.0, 1.0);
    final top = _top;
    final stride = b.height * 0.45;
    final sl = armSlot * deg;
    const us = [0.0, 0.3, 0.5, 0.6, 0.8, 1.0];
    final root = kv(uu, us, [at, at + f * 0.05, at + f * (stride * 0.35), at + f * (stride * 0.5), at + f * (stride * 0.65), at + f * (stride * 0.7)]);
    final hipTw = kf(uu, us, const [-35, -50, -35, 35, 65, 55]);
    final shTw = kf(uu, us, const [-40, -70, -80, 30, 85, 60]);
    final lean = kf(uu, us, const [8, 0, -6, 12, 34, 18]);
    final footG = kv(uu, us, [
      at + f * 0.22 - rT * 0.12,
      at + f * 0.35 - rT * 0.10 + V3(0, 0, 0.12), // 前の足を上げて踏み出す
      at + f * stride - rT * 0.08,
      at + f * stride - rT * 0.08,
      at + f * stride - rT * 0.08,
      at + f * stride - rT * 0.08,
    ]);
    final footT = kv(uu, us, [
      at - f * 0.05 + rT * 0.14,
      at - f * 0.02 + rT * 0.14,
      at + rT * 0.16,
      at + f * 0.05 + rT * 0.14, // 蹴って回る
      at + f * (stride * 0.45) + rT * 0.18 + V3(0, 0, 0.30), // 後ろ脚が前へ抜ける
      at + f * (stride * 0.95) + rT * 0.30,
    ]);
    final heelT = kf(uu, us, const [0, 0, 0.02, 0.10, 0.05, 0]);
    final rel = at + f * (stride * 0.55 + 0.45) + rT * (m.sin(sl) * 0.32) + V3(0, 0, top + 0.08 + m.cos(sl) * 0.24);
    final handT = kv(uu, us, [
      at + f * 0.32 + V3(0, 0, top - 0.25), // 胸の前（グラブの中）
      at - f * 0.25 + rT * 0.30 + V3(0, 0, b.hipJointH + 0.15), // 腕を下から後ろへ回す
      at - f * 0.30 + rT * 0.42 + V3(0, 0, top + 0.18), // トップ
      rel, // リリース
      at + f * (stride * 0.75 + 0.25) - rT * 0.35 + V3(0, 0, b.hipJointH * 0.75), // 反対のひざの外へ
      at + f * (stride * 0.75) - rT * 0.10 + V3(0, 0, b.hipJointH * 1.05),
    ]);
    final handG = kv(uu, us, [
      at + f * 0.34 - rT * 0.02 + V3(0, 0, top - 0.22),
      at + f * 0.40 - rT * 0.10 + V3(0, 0, top - 0.10),
      at + f * (stride * 0.35 + 0.55) - rT * 0.12 + V3(0, 0, top - 0.14), // グラブの腕は目標へ（肩の高さ）
      at + f * (stride * 0.5 + 0.25) - rT * 0.18 + V3(0, 0, top - 0.22), // 胸へ引きつける
      at + f * (stride * 0.6 + 0.15) - rT * 0.25 + V3(0, 0, top - 0.30),
      at + f * (stride * 0.7) - rT * 0.25 + V3(0, 0, b.hipJointH * 1.05),
    ]);
    return build(
      root: root,
      h: h,
      hipTwist: hipTw,
      drop: kf(uu, us, const [0.05, 0.03, 0.10, 0.08, 0.10, 0.04]),
      lean: lean,
      twist: shTw,
      footT: footT + V3(0, 0, b.ankleH),
      footG: footG + V3(0, 0, b.ankleH),
      toeDirT: uu < 0.55 ? (f + rT * 1.2).unit : f,
      toeDirG: (f - rT * 0.25).unit,
      heelT: heelT,
      handT: handT,
      handG: handG,
      look: look ?? at + f * 30 + V3(0, 0, 1.5),
      throwArm: kf(uu, const [0.0, 0.3, 0.45, 0.62, 0.75, 1.0], const [0.0, 0.5, 1.0, 1.0, 0.3, 0.0]),
    );
  }

  /// 打者のスイング：right＝右打席。u：0 構え → 0.2 足を上げる（ため）→ 0.3 踏み込み → 0.45 腰が回り始める
  ///  → 0.6 ミート（腰 70°・肩 60°、後ろのかかとが上がる）→ 0.8 押し込み → 1 フィニッシュ（両手は前の肩の上、後ろ足はつま先立ち）
  ///  contact：ミートの点、look：見る点（打球を追う）
  List<V3> swing({required bool right, required double u, required V3 contact, V3? look, V3? bat}) {
    final s = right ? -1.0 : 1.0; // 打席の x の側
    final h = right ? m.pi / 2 : -m.pi / 2; // 体の正面は本塁の方
    final f = fwdOf(h); // 本塁へ
    final at = V3(s * 0.95, 0.25, 0);
    const toP = V3(0, 1, 0); // 投手の方向
    final uu = u.clamp(0.0, 1.0);
    final top = _top;
    const us = [0.0, 0.2, 0.3, 0.45, 0.6, 0.8, 1.0];
    final handsAt = contact - (contact - at).unit * 0.62; // バットの先がミートの点に届く手の位置
    final hands = kv(uu, us, [
      at - toP * 0.20 + f * 0.10 + V3(0, 0, top + 0.04), // 後ろの肩の前（耳の高さ。前の腕は胸の前を横切る）
      at - toP * 0.27 + f * 0.08 + V3(0, 0, top + 0.06), // ため（手を後ろへ）
      at - toP * 0.27 + f * 0.10 + V3(0, 0, top + 0.02),
      at - toP * 0.12 + f * 0.12 + V3(0, 0, top - 0.10), // 体の近くを最短で
      handsAt,
      at + toP * 0.45 + f * 0.30 + V3(0, 0, top - 0.25), // 押し込み（両腕が伸びる）
      at + toP * 0.20 - f * 0.08 + V3(0, 0, top + 0.12), // 前の肩の上へ振り抜く
    ]);
    final footG = kv(uu, us, [
      at + toP * 0.42,
      at + toP * 0.36 + V3(0, 0, 0.08), // 前の足を少し上げる
      at + toP * 0.70,
      at + toP * 0.70,
      at + toP * 0.70,
      at + toP * 0.70,
      at + toP * 0.70,
    ]);
    final footBack = at - toP * 0.40;
    final heelT = kf(uu, us, const [0, 0, 0, 0.02, 0.06, 0.10, 0.12]);
    final hipTw = kf(uu, us, const [0, -8, -10, 35, 70, 90, 95]);
    final shTw = kf(uu, us, const [-12, -22, -25, 10, 60, 105, 125]);
    final root = kv(uu, us, [at, at - toP * 0.05, at + toP * 0.06, at + toP * 0.09, at + toP * 0.11, at + toP * 0.12, at + toP * 0.12]);
    // 後ろ足のつま先は回転して投手の方へ向く
    final toeT = f.lerp(toP, _ss((uu - 0.45) / 0.4)).unit;
    return build(
      root: root,
      h: h,
      hipTwist: hipTw,
      drop: kf(uu, us, const [0.13, 0.11, 0.15, 0.16, 0.15, 0.13, 0.11]), // ひざを曲げて構え、振り抜いても沈んだまま
      lean: kf(uu, us, const [16, 14, 16, 14, 12, 8, 4]),
      side: kf(uu, us, const [0, 0, 0, -4, -8, -6, -2]) * (right ? 1 : -1),
      twist: shTw,
      footT: footBack + V3(0, 0, b.ankleH),
      footG: footG + V3(0, 0, b.ankleH),
      toeDirT: toeT,
      toeDirG: (f + toP * 0.6).unit,
      heelT: heelT,
      // 両手はバットに沿って並ぶ（上の手 T がバットの先の側）
      handT: bat != null ? hands + bat.unit * 0.045 : hands + V3(0, 0, 0.03),
      handG: bat != null ? hands - bat.unit * 0.045 : hands - V3(0, 0, 0.05),
      look: look ?? contact,
    );
  }

  /// 打撃（仕様書 2.3 の6段階）。t：インパクト＝0 の時刻（秒）、contact：バットの芯が当たる点、spray：打球の向き（度、＋＝一塁側）
  ///  ① 構え・ロード（軸足の股関節に体重を乗せる）−0.75〜−0.45
  ///  ② ストライド・割れ（骨盤は前へ、グリップは後ろへ。−0.15 で前のかかとが着く＝打つかの決断）
  ///  ③ 回転・ラグ（骨盤 → 胸の順に回り、バットは寝て遅れて出る。コースの高さで体幹を 10〜42° 横へ傾ける）
  ///  ④ インパクト 0（手首は返さない：上の手のひらは上、下の手のひらは下。上の腕のひじ約100°）
  ///  ⑤ エクステンション・ロールオーバー（両ひじが伸びきってから手首を返し、背中へ巻きつけて減速）
  ///  ⑥ バットを置いて走り出す（呼ぶ側で走りへ切り替える）
  /// 返り値：関節の目標・バットの向き（グリップ → 先）・上と下の手のひらの向き
  ({List<V3> p, V3 bat, V3 palmTop, V3 palmBottom}) swingAt({required bool right, required double t, required V3 contact, double spray = 0, V3? look}) {
    final s = right ? -1.0 : 1.0; // 打席の x の側
    final h = right ? m.pi / 2 : -m.pi / 2; // 体の正面は本塁の方
    final f = fwdOf(h); // 本塁へ
    final at = V3(s * 0.95, 0.20, 0);
    const toP = V3(0, 1, 0); // 投手の方向
    final top = _top;
    const ts = [-0.75, -0.45, -0.15, -0.07, 0.0, 0.08, 0.25];
    final tt = t.clamp(ts.first, ts.last);
    double kt(List<double> vs) {
      for (var i = 0; i + 1 < ts.length; i++) {
        if (tt <= ts[i + 1]) return vs[i] + (vs[i + 1] - vs[i]) * _ss((tt - ts[i]) / (ts[i + 1] - ts[i]));
      }
      return vs.last;
    }

    V3 kp(List<V3> vs) {
      for (var i = 0; i + 1 < ts.length; i++) {
        if (tt <= ts[i + 1]) return vs[i].lerp(vs[i + 1], _ss((tt - ts[i]) / (ts[i + 1] - ts[i])));
      }
      return vs.last;
    }

    // インパクトのバット：打球の向きに直角（芯の面が打球の向き）。低めほど先が下がる
    final sp = spray * deg;
    final out = V3(m.sin(sp), m.cos(sp), 0);
    final axisH = V3(out.y, -out.x, 0) * (right ? 1.0 : -1.0); // 右打者は一塁側（＋x）へ先が向く
    final low = ((0.95 - contact.z) / 0.5).clamp(0.0, 1.0);
    final dip = (5 + 30 * low) * deg;
    final axis = (axisH * m.cos(dip) - V3.ez * m.sin(dip)).unit;
    final handsHit = contact - axis * 0.62; // 芯（先から 0.15m）が当たる点に来る手の位置
    final up = V3.ez;
    final hands = kp([
      at - toP * 0.15 + f * 0.20 + V3(0, 0, top - 0.02), // 構え：後ろの肩の前
      at - toP * 0.20 + f * 0.20 + V3(0, 0, top + 0.0), // ロード：グリップを後ろへ
      at - toP * 0.22 + f * 0.20 + V3(0, 0, top - 0.04), // 割れ：前足が着いても手は後ろ
      at - toP * 0.08 + f * 0.24 + V3(0, 0, (top + handsHit.z) / 2 + 0.05), // 回転：体の近くを最短で、手が先に出る
      handsHit,
      handsHit + toP * 0.30 + f * 0.04 + V3(0, 0, 0.10), // 押し込み：両腕が伸びきる
      at + toP * 0.16 - f * 0.04 + V3(0, 0, top + 0.10), // 前の肩の上（回ったあとの顔の横）へ振り抜く
    ]);
    final bat = kp([
      (up * 0.85 - toP * 0.35 + V3(-s * 0.15, 0, 0)).unit, // 構え：立てて少し後ろへ寝かす
      (up * 0.70 - toP * 0.60 + V3(-s * 0.15, 0, 0)).unit, // ロード：さらに寝かす（ヘッドは投手の方へ向かない）
      (up * 0.55 - toP * 0.75 + V3(-s * 0.10, 0, 0)).unit,
      (-toP * 0.95 + V3(-s * 0.25, 0, 0) + up * 0.05).unit, // ラグ：寝て、先は捕手の方に残る
      axis,
      (toP * 0.85 + up * 0.15 + V3(s * 0.25, 0, 0)).unit, // 押し込み：先は投手の方
      (V3(s * 0.55, -0.45, -0.35)).unit, // ロールオーバー：背中へ巻きつく
    ]).unit;
    // 足：前足はロードで少し浮かせ、−0.15 でかかとから着く。後ろ足は回転でかかとが上がりつま先で回る
    final footG = kp([
      at + toP * 0.40,
      at + toP * 0.36 + V3(0, 0, 0.07),
      at + toP * 0.68,
      at + toP * 0.68,
      at + toP * 0.68,
      at + toP * 0.68,
      at + toP * 0.68,
    ]);
    final footBack = at - toP * 0.40;
    final heelT = kt(const [0, 0, 0, 0.03, 0.06, 0.09, 0.12]);
    final hipTw = kt(const [0, -10, -6, 40, 75, 92, 100]);
    final shTw = kt(const [-25, -38, -42, -5, 55, 115, 150]); // 肩は骨盤より遅れて回る（捻転差）
    final sideHit = 10 + 32 * low; // 体幹の側屈（仕様書：10〜42°）
    final side = kt([0, 0, 2, sideHit * 0.6, sideHit, sideHit * 0.6, 4]) * (right ? 1 : -1);
    final root = kp([at, at - toP * 0.06, at + toP * 0.08, at + toP * 0.10, at + toP * 0.11, at + toP * 0.12, at + toP * 0.12]);
    final toeT = f.lerp(toP, _ss((tt + 0.07) / 0.3)).unit;
    // 手のひら：インパクトまでは上の手が上・下の手が下、押し込みのあとで手首を返す（上の手のひらが下へ）
    final roll = _ss((tt - 0.06) / 0.12);
    final palmTop = (up * (1 - 2 * roll) + f * 0.2).unit;
    final palmBottom = (-up * (1 - 2 * roll) + f * 0.2).unit;
    final p = build(
      root: root,
      h: h,
      hipTwist: hipTw,
      drop: kt(const [0.13, 0.15, 0.16, 0.16, 0.15, 0.13, 0.11]), // 軸足の股関節に乗せて沈む
      lean: kt(const [16, 18, 15, 13, 12, 9, 5]),
      side: side,
      twist: shTw,
      footT: footBack + V3(0, 0, b.ankleH),
      footG: footG + V3(0, 0, b.ankleH),
      toeDirT: toeT,
      toeDirG: (f + toP * 0.5).unit,
      heelT: heelT,
      handT: hands + bat * 0.05, // 上の手（T）はバットの先の側
      handG: hands - bat * 0.05,
      look: look ?? contact,
    );
    return (p: p, bat: bat, palmTop: palmTop, palmBottom: palmBottom);
  }

  /// 片腕を、手首の目標へ届かせ直す（肩は動かさない。仕様書 2.2：上の手をバットの握りの位置へ）
  List<V3> reachArm(List<V3> p, bool t, V3 wrist) {
    final q = List<V3>.of(p);
    final sh = q[(t ? J.shoulderT : J.shoulderG).index];
    final elOld = q[(t ? J.elbowT : J.elbowG).index];
    final l = (b.upperArm + b.forearm) * 0.999;
    final w = (wrist - sh).length > l ? sh + (wrist - sh).unit * l : wrist;
    final el = ik(sh, w, b.upperArm, b.forearm, elOld - (sh + w) * 0.5);
    q[(t ? J.elbowT : J.elbowG).index] = el;
    q[(t ? J.wristT : J.wristG).index] = w;
    q[(t ? J.ball : J.glove).index] = w + (w - el).unit * (b.hand * 0.5);
    return q;
  }

  /// 走者のリード：腰を落とし、両手はひざの前、次の塁の方へ体を開いて投手を見る（look）
  List<V3> lead(V3 at, double h, {V3? look}) => ready(at, h, crouch: 0.45, look: look);

  /// スライディング（足から）：進む向き h
  List<V3> slide(V3 at, double h) {
    final f = fwdOf(h), r = rightOf(h);
    final sT = _sT;
    return build(
      root: at,
      h: h,
      drop: b.hipJointH - 0.22,
      lean: -55,
      footT: at + f * 0.75 + r * (sT * 0.1) + V3(0, 0, 0.12),
      footG: at + f * 0.45 - r * (sT * 0.15) + V3(0, 0, 0.25),
      handT: at - f * 0.1 + r * (sT * 0.35) + V3(0, 0, 0.6),
      handG: at - f * 0.1 - r * (sT * 0.35) + V3(0, 0, 0.6),
      look: at + f * 10 + V3(0, 0, 0.5),
    );
  }
}
