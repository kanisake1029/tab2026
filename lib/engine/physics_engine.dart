import 'dart:math';
import '../models/stadium.dart';
import 'ball_flight.dart';
import 'environment.dart';
import 'vec3.dart';

// 球種の定義
class PitchType {
  final String name;
  final double speedRatio;     
  final double horizontalBreak; 
  final double verticalBreak;   
  final double heaviness;       

  const PitchType(this.name, this.speedRatio, this.horizontalBreak, this.verticalBreak, this.heaviness);
}

class PitchTypes {
  static const fastball = PitchType('ストレート', 1.0, 0.0, 0.0, 1.0);
  static const slider = PitchType('スライダー', 0.90, 30.0, -10.0, 0.9);
  static const curve = PitchType('カーブ', 0.80, 15.0, -40.0, 0.8);
  static const fork = PitchType('フォーク', 0.88, 0.0, -50.0, 1.2);
}

class PhysicsConstants {
  static const double ballMass = 0.150; 
  static const double ballCircumference = 0.23; 
  static const double ballRadius = ballCircumference / (2 * pi); 
  static const double ballArea = pi * ballRadius * ballRadius; 
  static const double ballCOR = 0.41; 
  static const double batMass = 0.900; 
  
  static const double airDensity = 1.225; 
  static const double dragCoefficient = 0.30; 
  static const double gravity = 9.81; 

  static const double fenceDistance = 100.0; 
  static const double fenceHeight = 3.0;     
  static const double infieldDirtRadius = 35.0; 

  static const double dirtRestitution = 0.5; 
  static const double dirtFriction = 0.05;   
  static const double grassRestitution = 0.3; 
  static const double grassFriction = 0.15;
  static const double dirtRolling = 0.45;  // 転がり抵抗係数（土）
  static const double grassRolling = 0.40; // 転がり抵抗係数（人工芝・芝）

  /// フェンスまでの距離・高さ（試合で使う球場から。標準球場は両翼100m・左中間/右中間 約115.6m・中堅122m・高さ3m）
  static double getFenceDistance(double angleDegrees) => Stadium.current.fenceDistance(angleDegrees);
  static double getFenceHeight(double angleDegrees) => Stadium.current.fenceHeight(angleDegrees);
}

class PhysicsEngine {
  /// 強い落下での跳ね返りの減り（落下速度 1m/s あたり）
  static double hardBounceLoss = 0.025;
  /// 打球の空気抵抗の倍率（バランス：NPB の公式球は MLB より飛ばない。打球だけに効く。投球は変えない）
  static double battedDrag = 1.055;
  /// 外野の芝（本塁から 40m より外）の転がりの抵抗の倍率（二塁打が多すぎないように +18%）
  static double ofRollMul = 1.18;
  final Random _rand = Random();

  HitVector calculateHit({
    required int maxVelocity, 
    required int pitchPower, 
    required PitchType pitchType,
    required int sharpness, 
    required int breakAmount, 
    required int batterPower, 
    required int batterMeet, 
    required int batterTrajectory
  }) {
    double pitchSpeed = maxVelocity * pitchType.speedRatio;
    
    // キレ・変化量による空振り率の増加 (空振り率を大幅アップ)
    double lateBreakFactor = (sharpness / 100.0) * (pitchType.horizontalBreak.abs() + pitchType.verticalBreak.abs()) * (breakAmount / 100.0);
    double whiffProb = 0.25 + (lateBreakFactor * 0.005) - (batterMeet * 0.002); 
    
    if (_rand.nextDouble() < whiffProb) {
       return HitVector(0, 0, 0, 0, isWhiff: true);
    }

    // ミートポイントのズレ計算
    double baseZOffset = (_rand.nextDouble() - 0.5) * 0.10 * (1.1 - batterMeet / 100.0); 
    // フォークだと上を叩いてしまう＝プラス方向のズレ(ゴロ)
    baseZOffset -= (pitchType.verticalBreak * (breakAmount / 100.0) * 0.0006); 
    baseZOffset = baseZOffset.clamp(-0.05, 0.05);

    double baseXOffset = (_rand.nextDouble() - 0.5) * 0.10 * (1.1 - batterMeet / 100.0);
    baseXOffset -= (pitchType.horizontalBreak * (breakAmount / 100.0) * 0.0006);
    baseXOffset = baseXOffset.clamp(-0.05, 0.05);

    // スイング軌道 (弾道1=0度(水平), 弾道2=5度, 弾道3=10度, 弾道4=15度)
    double swingPlaneAngle = (batterTrajectory - 1) * 5.0;

    // スイングスピードを低下（HR率と打率の調整）
    double vSwing = (75.0 + batterPower * 0.45) * 1000 / 3600; 
    double vPitch = pitchSpeed * 1000 / 3600; 

    double offsetDist = sqrt(baseZOffset*baseZOffset + baseXOffset*baseXOffset);
    double offsetPenalty = cos(offsetDist * 25); 
    if (offsetPenalty < 0.1) offsetPenalty = 0.1;

    double heaviness = pitchType.heaviness * (pitchPower / 100.0);
    double ea = (0.41 - 0.16) / 1.16; 
    double effectiveEa = (ea * offsetPenalty) - (heaviness * 0.03);

    double vExit = effectiveEa * vPitch + (1 + effectiveEa) * vSwing;

    // レベルスイング(0度)でボールの真ん中を叩けば0度（地面と平行）
    // 上を叩く(zOffset > 0)とマイナス角度（ゴロ）
    double hitAngleFromCenter = -baseZOffset * 1000.0; 
    double launchAngle = swingPlaneAngle + hitAngleFromCenter;

    double horizontalAngle = -baseXOffset * 1000.0; 
    horizontalAngle = horizontalAngle.clamp(-45.0, 45.0);

    double backspin = (-baseZOffset * 50000) - (pitchPower * 10);

    return HitVector(vExit, launchAngle, horizontalAngle, backspin, isWhiff: false);
  }

  /// 打球の飛び方：重力・空気抵抗・マグヌス力（投球と同じ式）・風、地面の跳ね方は落ちた場所の地面（芝・土）で
  ///  0.05 秒ごとの点を返す（守備・描画はこの間隔で読む）。中では 0.005 秒刻みの RK4
  List<Vector3D> simulateTrajectory(HitVector hit, {GameEnv? env, Stadium? stadium}) {
    final e = env ?? GameEnv.standard;
    final st = stadium ?? Stadium.current;
    const out = 0.05, dt = 0.005;
    final trajectory = <Vector3D>[];
    final radV = hit.launchAngle * pi / 180, radH = hit.horizontalAngle * pi / 180;
    var p = hit.start;
    var v = V3(hit.v0 * cos(radV) * sin(radH), hit.v0 * cos(radV) * cos(radH), hit.v0 * sin(radV));
    // 回転：バックスピン（＋）は進む向きと上に垂直な軸。トップスピンは −
    final hu = V3(v.x, v.y, 0).unit;
    var omega = hit.omega ?? hu.cross(V3.ez) * (hit.backspin * 2 * pi / 60);
    var t = 0.0, next = 0.0, airT = 0.0;
    var rolling = false;
    var bounced = false; // 前の点から今の点までの間に地面に着いた（守備はこれでバウンドを知る）
    while (trajectory.length < 300) {
      if (t >= next - 1e-9) {
        // バウンドした区間の次の点は、高さ 0（地面）として残す（0.05秒ごとの点の間で跳ねても、守備がバウンドを見落とさない）
        trajectory.add(Vector3D(p.x, p.y, bounced ? 0.0 : p.z, v.x, v.y, v.z));
        bounced = false;
        next += out;
      }
      if (!rolling) {
        // 空中：RK4（回転は空中の時間で減る）
        // 球場ごとの飛びやすさ（carry）と、よく吹く風は上空（スタンドより上：高さ 12m から 20m にかけて効き始める）の空気の流れ。
        //  低いライナーやゴロには効かない（本塁打と深いフライの出やすさだけが球場で変わる）
        final aloft = ((p.z - 12) / 8).clamp(0.0, 1.0);
        final dm = battedDrag * (1 + (Stadium.current.carry - 1) * aloft);
        V3 acc(V3 vv) => BallFlight.accel(vv, airT, omega, rho: e.rho, wind: e.wind, dragMul: dm);
        final a1 = acc(v), a2 = acc(v + a1 * (dt / 2)), a3 = acc(v + a2 * (dt / 2)), a4 = acc(v + a3 * dt);
        final np = p + (v + (v + a1 * (dt / 2)) * 2 + (v + a2 * (dt / 2)) * 2 + (v + a3 * dt)) * (dt / 6);
        final nv = v + (a1 + a2 * 2 + a3 * 2 + a4) * (dt / 6);
        if (np.z <= 0) {
          // 着地：落ちた場所の地面で跳ねる
          final f = p.z / (p.z - np.z);
          p = p.lerp(np, f);
          p = V3(p.x, p.y, 0);
          final g = Surface.at(st, p.x, p.y);
          final vz = nv.z;
          bounced = true;
          if (vz < -1.0) {
            // 垂直は反発係数で跳ね返り、横は1回ごとに減る（急な角度ほど大きく減る）
            final steep = (-vz / max(1.0, sqrt(nv.x * nv.x + nv.y * nv.y))).clamp(0.2, 1.5);
            final keep = 1.0 - g.bounceLoss * (0.6 + 0.4 * steep);
            // 強く打ちつけるほどボールも地面もつぶれて、跳ね返りが小さい（落下 5m/s までは表の値、25m/s で約半分）
            final eHit = g.restitution * (1.0 - hardBounceLoss * max(0.0, -vz - 5.0)).clamp(0.45, 1.0);
            v = V3(nv.x * keep, nv.y * keep, -vz * eHit);
            omega = omega * 0.5;
            airT = 0;
          } else {
            v = V3(nv.x, nv.y, 0);
            rolling = true;
          }
        } else {
          p = np;
          v = nv;
          airT += dt;
        }
      } else {
        // 転がり：地面ごとの転がり抵抗で一定に減速
        final g = Surface.at(st, p.x, p.y);
        final vh = sqrt(v.x * v.x + v.y * v.y);
        // 外野の芝（本塁から 40m より外）は転がりの抵抗を強める（外野の間を抜けたゴロがフェンスまで届きにくい）
        final ofGrass = g.name != '土' && p.x * p.x + p.y * p.y > 1600;
        final nv = max(0.0, vh - g.rolling * (ofGrass ? ofRollMul : 1.0) * PhysicsConstants.gravity * dt);
        v = vh > 0 ? V3(v.x * nv / vh, v.y * nv / vh, 0) : V3.zero;
        p = p + v * dt;
      }
      t += dt;
      if (p.z <= 0 && sqrt(v.x * v.x + v.y * v.y) < 1.0) {
        trajectory.add(Vector3D(p.x, p.y, 0, 0, 0, 0));
        break;
      }
    }
    return trajectory;
  }
}

class HitVector {
  final double v0;              
  final double launchAngle;     
  final double horizontalAngle; 
  final double backspin;        
  final bool isWhiff;
  final V3? omega; // 回転（打撃の物理で求めたとき。横回転も含む）
  final V3 start; // 打球の出発点（バットに当たった所。投球が来たコース）

  HitVector(this.v0, this.launchAngle, this.horizontalAngle, this.backspin, {this.isWhiff = false, this.omega, this.start = const V3(0, 0.45, 1.0)});
}

class Vector3D {
  final double x, y, z;
  final double vx, vy, vz;
  Vector3D(this.x, this.y, this.z, this.vx, this.vy, this.vz);
}
