import 'dart:math' as m;
import 'velo.dart';
import 'spec_constants.dart';
import '../models/equipment.dart';
import 'bat_physics.dart';
import 'vec3.dart';

/// 打者の能力（スイングに使うもの）
class BatterSkill {
  final int meet, power, eye, trajectory; // ミート・パワー・選球眼・弾道（1〜4）
  final double pull; // 引っ張りの癖（0〜1）
  final bool lefty; // 左打席
  final Bat bat;
  const BatterSkill({required this.meet, required this.power, required this.eye, required this.trajectory, required this.pull, required this.lefty, required this.bat});
}

/// 打者の読み（配球の読み合い：第1層のベイズ事前分布）
class SwingRead {
  final double pFast; // 直球系を待つ確率（0〜1）
  final double vFast, vSlow; // 直球系・変化球の予想の速さ（km/h）
  final double slowDrop; // 変化球を待つときに見込む落ち（m/s²。本塁の手前0.17秒の加速度の差）
  const SwingRead(this.pFast, this.vFast, this.vSlow, this.slowDrop);
  double get vPred => pFast * vFast + (1 - pFast) * vSlow;
}

/// 来た球（物理）
class IncomingPitch {
  final double speedKmh; // 初速
  final double time; // 到達までの秒
  final V3 vel; // 本塁での速度
  /// 変化量（0〜1）：大きく曲がる球ほど、球種を読めても合わせきれない
  final double brk;
  /// 失投（真ん中に甘く入った）：芯でとらえやすい
  final bool hanging;
  final V3 omega; // 本塁での回転
  final V3 aLate; // 直球と比べた終盤の加速度の差
  final double zoneX, zoneZ; // 到達点（ゾーン座標。x の＋＝投手から見て右）
  final bool fastLike;
  final int sharp; // キレ
  /// 投手の直球の体感の速さ（腕の角度の上乗せ込み）と球威。0 なら考えない
  final double perceivedKmh;
  final int stuff;
  /// 打者の待ち球（仕様書 batter_response_spec §1）：速さ・直球との加速度の差・来た球と同じか。guessKmh が 0 なら古い計算
  final double guessKmh;
  final V3 guessALate;
  final bool guessSame;
  /// 直前の球の速さ（打席の初球は 0）：緩急（§2）
  final double prevKmh;
  const IncomingPitch({this.guessKmh = 0, this.guessALate = V3.zero, this.guessSame = false, this.prevKmh = 0, this.perceivedKmh = 0, this.stuff = 70, this.brk = 0.35, this.hanging = false, required this.speedKmh, required this.time, required this.vel, required this.omega, required this.aLate, required this.zoneX, required this.zoneZ, required this.fastLike, required this.sharp});
  double get vaa => m.atan2(vel.z, -vel.y) * 180 / m.pi; // 垂直進入角（下向きが −）
}

/// スイングの結果
class SwingOutcome {
  final bool whiff;
  final Impact impact;
  final BattedBall? ball;
  final double dt; // タイミングのずれ（秒。＋＝早い＝バットが先に来た）
  const SwingOutcome(this.whiff, this.impact, this.ball, this.dt);
}

/// 打撃の一般化モデル（第3章）：読み → タイミングと高さのずれ → インパクトの6変数 → 衝突
///  タイミング：予想の速さとの差（Δt ＝ 実際の到達時間 − 予想）を、球の見極めで縮める。残りがスイングのずれ
///  高さ：終盤の変化（直球との差）を見込めなかった分＋タイミングのずれ×（ボールの落ちる速さ − バットの上がる速さ）＋ばらつき
///   → アタックアングルが進入角に合う（α ＝ −VAA）ほど、タイミングのずれが高さのずれにならない
///  横：引っ張りの癖・内外角・タイミング（早いと引っ張り、遅いと流し打ち）
///  長さ方向：内角ほど手元、外角ほど先。先から外れると空振り
class SwingModel {
  static double vBatScale = 0.94; // バランス調整（第3段階で守備と合わせて合わせた値）
  static double noiseScale = 0.83; // ミートのばらつき（守備の判断を入れた後に、打球の種類の割合と合わせた値）
  static double timingScale = 1.0; // タイミングのばらつき（早い・遅い → 引っ張り・流しのファウル、空振り）
  static double contactScale = 0.85; // 当たる高さのばらつき（芯の上下 → ゴロ・ポップ・空振り）
  static double aimBase = 0.0085; // 狙う高さ（ボールの中心より少し下）
  static double misScale = 1.0;
  static double veloContact = 0.3; // 速い球ほど芯を外す（タイミングの倍率の何乗）
  static double stuffK = 0.008; // 球威1あたりの芯ずれの増え方
  static double stuffCor = 0.002;
  /// 球種を読めても打ち消しきれない変化の割合：resid0 ＋ 変化量（0〜1）× residK
  static double breakResid0 = 0.15, breakResidK = 0.7;
  /// 待ち球と違う球に気づけない割合の基準・気づいたときに直せずに残るずれ（待ち球の速さとの差に掛ける）・見誤ったときの曲がりのずれの倍率
  static double notIdBase = 0.69, idRecog = 0.2, misBreakK = 1.2;
  /// 緩急：直前の球の速さに引っ張られる割合（ミート60）
  static double prevPull = 0.25;
  /// 芯ずれ：変化量の山形（ピーク brkPeak）の効き・キレ1あたりの効き
  static double brkConK = 0.15, brkPeak = 0.25, sharpConK = 0.002;
  /// 大きい変化（変化量 55 超）：合わせきれずに空振り（bigWhiff）。当たれば芯ずれは小さめ（bigEase の分だけ高さのずれを減らす）
  static double bigWhiff = 0.12, bigEase = 0.4; // 球威1あたりの反発の減り方 // 球種の見誤りやすさ（三振の多さ。NPB の三振率 約19% に合わせた値）

  /// バットの芯の速さ（m/s）：パワー → 約30〜36m/s（時速110〜130km）。バットの慣性モーメントで変わる
  static double batSpeed(BatterSkill b) => Spec.bat ? Spec.batSpeed(b.power) * b.bat.swingSpeedRatio : (25.0 + b.power * 0.08) * b.bat.swingSpeedRatio * vBatScale;

  static double _g(m.Random r) => m.sqrt(-2 * m.log(1 - r.nextDouble())) * m.cos(2 * m.pi * r.nextDouble());

  static SwingOutcome swing(BatterSkill b, SwingRead read, IncomingPitch p,
      {required m.Random rnd, double corScale = 1, double launchBias = 0, double betaBias = 0, double speedMul = 1, bool twoStrikes = false, double edge = 0}) {
    // ── 球種の見極め：待っていない方の球が来ると見誤りやすい（キレがあるほど、選球眼が低いほど）──
    final vMul = p.perceivedKmh > 0 ? Velo.timingMul(p.perceivedKmh, adapt: Velo.adapt(b.meet, b.eye, b.power)) : 1.0; // 速い投手ほど指数関数的に差し込まれる
    final vLin = p.perceivedKmh > 0 ? ((p.perceivedKmh - Velo.pivot) * 0.012).clamp(-0.25, 0.3) : 0.0;
    final bool guessed = p.guessKmh > 0;
    final double notId = (notIdBase * (1 + vLin) * (1 - (b.eye - 60) * 0.005 - (b.meet - 60) * 0.005) * (1 + (p.sharp - 60) * 0.015) * misScale * (twoStrikes ? 0.75 : 1.0) * (p.hanging ? 0.6 : 1.0)).clamp(0.02, 0.9);
    final misP = guessed ? (p.guessSame ? 0.0 : notId) : ((1 + vLin) * (p.fastLike ? (1 - read.pFast) * 0.55 : read.pFast * 0.75) * (1 - (b.eye - 60) * 0.005 - (b.meet - 60) * 0.005) * (1 + (p.sharp - 60) * 0.015) * misScale * (twoStrikes ? 0.75 : 1.0) * (p.hanging ? 0.6 : 1.0)).clamp(0.02, 0.9); // 追い込まれると当てにいく
    final misread = rnd.nextDouble() < misP;
    // ── タイミング：待っていた球の速さで振り出し、見極めた分だけ直す ──
    var vExp = misread ? (p.fastLike ? read.vSlow : read.vFast) : (p.fastLike ? read.vFast : read.vSlow);
    var recog = misread ? 0.9 : ((0.35 - (b.eye - 60) * 0.003 - (b.meet - 60) * 0.002) * (1 + vLin)).clamp(0.12, 0.7);
    if (guessed) {
      // 待ち球の速さで振り出す。待ち球どおりならずれは緩急の分だけ。違うと気づけば、待ち球との差を idRecog だけ残して直す
      vExp = p.guessSame ? p.speedKmh : p.guessKmh;
      if (!misread && !p.guessSame) recog *= idRecog / 0.35;
      // 緩急：体内時計が直前の球の速さに引っ張られる（ミートが高いほど引っ張られにくい）
      if (p.prevKmh > 0) {
        final pull = (prevPull * (1 - (b.meet - 60) * 0.01)).clamp(0.1, 0.4);
        vExp += (p.prevKmh - vExp) * pull;
      }
    }
    final dtRaw = p.time - p.time * p.speedKmh / vExp; // ＋＝球が予想より遅い → 打者は早い
    final sigT = (0.007 + (100 - b.meet) * 0.0001) * noiseScale * timingScale * (twoStrikes ? 0.9 : 1.0) * vMul;
    final dt = dtRaw * recog + _g(rnd) * sigT + b.pull * 0.004;
    // ── スイング ──
    var vBat = batSpeed(b) * speedMul * (twoStrikes ? 0.97 : 1.0);
    if (dt.abs() > 0.06) vBat *= 0.85; // 大きく崩されると当てにいくだけ
    final zPlate = 0.75 + p.zoneZ * 0.28;
    final attack = (Spec.bat ? Spec.attack(b.trajectory) : 3.0 + (b.trajectory - 1) * 3.0) + (0.75 - zPlate) * 14 + launchBias * 0.5;
    final vBall = p.vel.length;
    // ── 高さのずれ（＋＝バットがボールの中心より下）──
    // 打者がボールを見て合わせられる最後の時間：キレがあるほど曲がり始めが遅く、合わせる時間が短い（変化の効きが大きい）
    const tRem = 0.17;
    final tLate = p.fastLike ? tRem : (0.14 + p.sharp * 0.0006).clamp(0.14, 0.21);
    final latePow = (tLate / tRem) * (tLate / tRem);
    // 球種を読めても打ち消しきれない分：変化が大きいほど多く、ミートが高いほど少ない
    final resid = ((breakResid0 + p.brk * breakResidK) * (1 - (b.meet - 60) * 0.006)).clamp(0.12, 0.75);
    final track = (1 - (b.eye - 60) * 0.003).clamp(0.6, 1.2);
    double eyLate;
    if (guessed && misread) {
      // 待ち球と来た球の、終盤の曲がりの差の分だけ高さがずれる
      eyLate = 0.5 * (p.aLate.z - p.guessALate.z) * tRem * tRem * latePow * misBreakK;
    } else if (guessed) {
      eyLate = p.fastLike ? 0.0 : 0.5 * p.aLate.z * tRem * tRem * latePow * resid;
    } else if (p.fastLike) {
      // 直球：変化球と見誤ると、落ちると見込んで下を振る → 下を叩く（ポップフライ・空振り）
      eyLate = misread ? 0.5 * read.slowDrop * tRem * tRem : 0.0;
    } else {
      // 変化球：直球と見誤ると、変化を見込めない。見極めても少しは残る
      eyLate = 0.5 * p.aLate.z * tRem * tRem * latePow * (misread ? 1.8 : resid);
    }
    // 大きい変化：見極めた後のずれは「当たらない（空振り）」に回し、当たったときのずれは減らす（§3）
    final big = (guessed && !p.fastLike && !misread) ? ((p.brk - 0.55) / 0.45).clamp(0.0, 1.0) : 0.0;
    if (big > 0) eyLate *= 1 - bigEase * big;
    eyLate *= track;
    final descend = vBall * m.sin(-p.vaa * deg); // ボールの落ちる速さ（m/s）
    final eyTiming = dt * (descend - vBat * m.sin(attack * deg)) * 0.5;
    final aim = (Spec.bat ? Spec.eyTarget(b.trajectory) : aimBase + (b.trajectory - 2) * 0.002) + launchBias * 0.0008;
    // 球威：芯を外しやすい（70 を基準に1ごとに stuffK）
    final stuffMul = (1 + (p.stuff - 74) * stuffK).clamp(0.75, 1.35);
    // 変化量：小〜中くらいの変化は当たるが芯を外す（山形。大きい変化は空振りで効き、当たれば芯ずれは小さめ）。キレも芯を外す
    final bs = p.brk / brkPeak;
    final brkMul = guessed ? (1 + brkConK * bs * m.exp(1 - bs)) * (1 + (p.sharp - 60) * sharpConK).clamp(0.85, 1.2) : 1.0;
    final sigY = (Spec.bat ? Spec.sigEy(b.meet) : (0.016 + (100 - b.meet) * 0.00025) * noiseScale * contactScale) * (1 + edge * 0.9) * stuffMul * brkMul * m.pow(vMul, veloContact);
    final ey = aim + eyLate + eyTiming + _g(rnd) * sigY;
    // ── 長さ方向（＋＝先）── 投手から見て右（x の＋）は右打者の外角
    final outside = b.lefty ? -p.zoneX : p.zoneX;
    final exLate = (guessed && misread)
        ? 0.5 * (p.aLate.x - p.guessALate.x) * tRem * tRem * latePow * (b.lefty ? 1 : -1)
        : 0.5 * p.aLate.x * tRem * tRem * latePow * (b.lefty ? 1 : -1) * (p.fastLike ? 0 : 1);
    final ex = outside * 0.09 + exLate + _g(rnd) * (Spec.bat ? Spec.sigEx(b.meet) : (0.02 + (100 - b.meet) * 0.0002) * noiseScale);
    // ── 横の向き（＋＝右翼側）とスイング円弧の幾何学・加速プロファイル ──
    final pullSign = b.lefty ? 1.0 : -1.0;
    final beta = pullSign * (b.pull * 8 + (-outside) * 10 + dt * 2200) + betaBias;
    final thetaPull = pullSign * beta;
    // 円弧半径 ~0.55m：垂直から傾くほど軌道が体側へ引かれ、芯が先端(+)側へズレる
    final arcEx = 0.55 * (1.0 - m.cos(beta * deg));
    final exFull = ex + arcEx;
    // 人体のスイング加速：体前（+8°＋引っ張りポイント）で最大速度に達し、振り遅れ側は加速途中
    final thetaPeak = 8.0 + b.pull * 6.0;
    final dTheta = thetaPull - thetaPeak;
    final arcSpeed = dTheta < 0 ? m.cos(m.min(50.0, dTheta.abs() * 0.65) * deg) : m.cos(m.min(35.0, dTheta * 0.35) * deg);
    final im = Impact(vBat * arcSpeed, attack, beta, ey, exFull, b.bat.effectiveMass);
    // タイミングが大きくずれると、バットが打つ場所を通り過ぎている（早すぎ）／まだ来ていない（遅すぎ）
    final missT = ((dt.abs() - 0.025) / 0.03).clamp(0.0, 1.0);
    if (ey.abs() >= BatPhysics.reach || exFull > 0.17 || exFull < -0.42 || rnd.nextDouble() < missT || (big > 0 && rnd.nextDouble() < bigWhiff * big)) return SwingOutcome(true, im, null, dt);
    final ball = BatPhysics.collide(im, p.vel, p.omega, corBase: BatPhysics.cor0 * corScale * (1 - (p.stuff - 74) * stuffCor).clamp(0.9, 1.06)); // 球威：押し込まれて打球が弱い
    return SwingOutcome(false, im, ball, dt);
  }
}
