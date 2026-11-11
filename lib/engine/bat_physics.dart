import 'dart:math' as m;
import 'ball_spec.dart';
import 'vec3.dart';

/// インパクトの6変数（バットの速さ・アタックアングル・水平の向き・上下の芯ずれ・長さ方向の芯ずれ・有効質量）と、その結果
class Impact {
  final double vBat; // バットの芯の速さ（m/s）
  final double attack; // アタックアングル α（度。＋＝アッパー）
  final double beta; // 水平の向き（度。中堅を 0、＋＝右翼側）
  final double ey; // 上下の芯ずれ（m。＋＝バットがボールの中心より下＝下を叩く）
  final double ex; // 長さ方向の芯ずれ（m。＋＝先、−＝手元）
  final double mEff; // 芯での有効質量（kg）
  const Impact(this.vBat, this.attack, this.beta, this.ey, this.ex, this.mEff);
}

class BattedBall {
  final V3 vel; // 打球の速度（本塁基準の座標：x＝一塁・右翼側、y＝中堅方向、z＝上）
  final V3 omega; // 回転（rad/s）
  final double cor; // その当たりの反発係数
  const BattedBall(this.vel, this.omega, this.cor);
  double get speed => vel.length;
  double get launch => m.atan2(vel.z, m.sqrt(vel.x * vel.x + vel.y * vel.y)) * 180 / m.pi;
  double get direction => m.atan2(vel.x, vel.y) * 180 / m.pi;

  /// バックスピン（＋）／トップスピン（−）の回転数
  double get backspinRpm {
    final h = V3(vel.x, vel.y, 0).unit;
    return omega.dot(h.cross(V3.ez)) * 60 / (2 * m.pi);
  }

  /// 横回転（＋＝上から見て反時計回り＝右へ曲がる…ではなく、ω×v の向きで右翼側へ切れる）
  double get sidespinRpm => omega.z * 60 / (2 * m.pi);
}

/// バットとボールの衝突（剛体の撃力）：芯ずれの分だけ当たる面が傾き、反発係数は芯から外れるほど下がる
///  法線方向：相対速度 × (1+e) / (1 + m/M_eff)。接線方向：転がり条件（相対すべりの 2/7 まで。摩擦で頭打ち）で回転が生まれる
class BatPhysics {
  static const batRadius = 0.033; // 太さ 6.6cm
  static const reach = batRadius + BallSpec.radius; // 上下の芯ずれがこれを超えたら空振り（約 6.96cm）
  static const cor0 = 0.50; // 木のバットの芯での反発係数（相対速度 40m/s 前後）
  static const friction = 0.5;

  /// バットの長さ方向のすべりが回転になる割合（円筒の軸方向は転がらず、すべるだけ。横回転＝フック・スライスの大きさ）
  static double axialSpin = 0.35;

  /// 長さ方向の芯ずれで下がる反発係数（手元はゆるやかに、先は急に下がる。振動に食われる）
  static double corAt(double ex, {double base = cor0}) {
    final k = ex < 0 ? 1 - 0.55 * m.pow(ex / 0.16, 2) : 1 - 0.85 * m.pow(ex / 0.11, 2);
    return (base * k).clamp(0.08, base).toDouble();
  }

  /// 衝突：ballVel・ballOmega はインパクト直前のボール（本塁基準の座標）
  static BattedBall collide(Impact im, V3 ballVel, V3 ballOmega, {double corBase = cor0}) {
    final a = im.attack * deg, b = im.beta * deg;
    final d = V3(m.sin(b) * m.cos(a), m.cos(b) * m.cos(a), m.sin(a)); // バットの芯の進む向き
    final vb = d * im.vBat;
    // 当たる面の向き：芯ずれ ey の分、バットの進む向きから上へ傾く（下を叩くと上へ）
    final th = m.asin((im.ey / reach).clamp(-0.999, 0.999));
    var up = V3.ez.perpTo(d);
    up = up.length < 1e-6 ? V3.ey : up.unit;
    final n = d * m.cos(th) + up * m.sin(th);
    final e = corAt(im.ex, base: corBase);
    final mb = BallSpec.mass, ratio = mb / im.mEff;
    final rel = ballVel - vb; // バットから見たボールの速度
    final un = rel.dot(n);
    if (un >= 0) return BattedBall(ballVel, ballOmega, e); // 当たらない（離れていく）
    // 法線：ボールの速度の変化
    final dvn = n * (-(1 + e) * un / (1 + ratio));
    // 接線：当たる点のすべり（ボールの回転も含む）を、転がりに近づける。摩擦で上限
    final r = BallSpec.radius;
    final contact = n * (-r); // ボールの中心から当たる点
    final slip0 = rel.perpTo(n) + ballOmega.cross(contact);
    // バットの長さ方向（水平でスイングの向きに直角）の成分は回転になりにくい
    var axis = V3.ez.cross(d);
    axis = axis.length < 1e-6 ? V3.ex : axis.unit;
    final along = axis * slip0.dot(axis);
    final slip = slip0 - along + along * axialSpin;
    final slipLen = slip.length;
    var dvt = V3.zero;
    if (slipLen > 1e-9) {
      // 完全に転がるまではいかない（実測の回転数に合わせて 2/7 の約7割）
      final want = slipLen * 0.2 / (1 + ratio * 0.2);
      final cap = friction * dvn.length;
      dvt = slip / slipLen * (-m.min(want, cap));
    }
    final vOut = ballVel + dvn + dvt;
    // 回転：接線の撃力が当たる点にかかる（I＝0.4mr²）
    final dOmega = contact.cross(dvt) / (0.4 * r * r);
    final wOut = ballOmega * 0.3 + dOmega; // 投球の回転は衝突でほとんど打ち消される
    return BattedBall(vOut, wOut, e);
  }
}
