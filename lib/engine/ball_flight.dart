import 'dart:math' as m;
import 'ball_spec.dart';
import 'vec3.dart';

/// 縫い目による力（シームシフテッドウェイク）やナックルの揺れ：
///  ½ρAv² × coef の大きさで、速度に垂直な dir の向き（ナックルは wobbleHz で向きが回る）
class SeamForce {
  final double coef;
  final V3 dir;
  final double wobbleHz;
  final double phase;
  const SeamForce(this.coef, this.dir, {this.wobbleHz = 0, this.phase = 0});
  static const none = SeamForce(0, V3.zero);
}

/// 1球の飛び方の結果
class Flight {
  final V3 cross; // 本塁の前の縁（y＝plateY）を通った位置
  final V3 vCross; // そのときの速度
  final double tCross; // かかった時間（秒）
  final List<V3> path; // 間引いた軌道（keepPath のとき）
  final List<double> pathT;
  final bool reached; // 本塁まで届いたか（地面に落ちた等は false）
  const Flight(this.cross, this.vCross, this.tCross, this.path, this.pathT, this.reached);
}

/// ボールの飛び方（RK4）：重力・空気抵抗・マグヌス力・回転の減衰・縫い目の力
class BallFlight {
  /// pos・vel（m, m/s）、omega（角速度 rad/s。ベクトルの向き＝回転軸、右ねじ）から本塁の前の縁まで飛ばす
  static Flight fly(V3 pos, V3 vel, V3 omega,
      {SeamForce seam = SeamForce.none,
      double rho = BallSpec.airDensity,
      V3 wind = V3.zero,
      double dt = 0.002,
      double plateY = FieldSpec.plateFrontY,
      bool keepPath = false,
      int pathEvery = 5,
      bool magnus = true,
      bool drag = true,
      double seamOrient = 1.0}) {
    var p = pos, v = vel, t = 0.0;
    final path = <V3>[], pathT = <double>[];
    if (keepPath) {
      path.add(p);
      pathT.add(0);
    }
    V3 acc(V3 vv, double tt) => accel(vv, tt, omega, seam: seam, rho: rho, seamOrient: seamOrient, drag: drag, magnus: magnus, wind: wind);

    var step = 0;
    while (t < 3.0) {
      // RK4
      final a1 = acc(v, t);
      final v1 = v;
      final a2 = acc(v + a1 * (dt / 2), t + dt / 2);
      final v2 = v + a1 * (dt / 2);
      final a3 = acc(v + a2 * (dt / 2), t + dt / 2);
      final v3 = v + a2 * (dt / 2);
      final a4 = acc(v + a3 * dt, t + dt);
      final v4 = v + a3 * dt;
      final np = p + (v1 + v2 * 2 + v3 * 2 + v4) * (dt / 6);
      final nv = v + (a1 + a2 * 2 + a3 * 2 + a4) * (dt / 6);
      if (np.y <= plateY) {
        // 本塁の前の縁を通った瞬間を、前後の点の3次補間で求める
        final f = (p.y - plateY) / (p.y - np.y);
        final h = _hermite(p, v, np, nv, f, dt);
        final cv = v.lerp(nv, f);
        final ct = t + dt * f;
        if (keepPath) {
          path.add(h);
          pathT.add(ct);
        }
        return Flight(h, cv, ct, path, pathT, h.z > 0);
      }
      if (np.z < 0) {
        return Flight(np, nv, t + dt, path, pathT, false);
      }
      p = np;
      v = nv;
      t += dt;
      step++;
      if (keepPath && step % pathEvery == 0) {
        path.add(p);
        pathT.add(t);
      }
    }
    return Flight(p, v, t, path, pathT, false);
  }

  /// 速度 vv・時刻 tt（リリースからの秒）のときの加速度（重力・空気抵抗・マグヌス力・縫い目の力）
  static V3 accel(V3 vv, double tt, V3 omega,
      {SeamForce seam = SeamForce.none, double rho = BallSpec.airDensity, double seamOrient = 1.0, bool drag = true, bool magnus = true, V3 wind = V3.zero, double dragMul = 1.0}) {
    final k = 0.5 * rho * BallSpec.area / BallSpec.mass;
    vv = vv - wind; // 空気に対する速度
    final sp = vv.length;
    var a = const V3(0, 0, -BallSpec.gravity);
    if (sp < 1e-6) return a;
    final vu = vv / sp;
    final w = omega * m.exp(-tt / BallSpec.spinDecayTau);
    final wT = w.perpTo(vu); // ジャイロ成分（進む向きの回転）は揚力を生まない
    final wTl = wT.length;
    final s = BallSpec.radius * wTl / sp;
    if (drag) a = a - vu * (k * BallSpec.cd(sp, s, seam: seamOrient) * dragMul * sp * sp);
    if (magnus && wTl > 1e-9) a = a + (wT / wTl).cross(vu) * (k * BallSpec.cl(s) * sp * sp);
    if (seam.coef != 0) {
      var d = seam.dir;
      if (seam.wobbleHz != 0) d = d.rotate(vu, seam.phase + 2 * m.pi * seam.wobbleHz * tt);
      final dp = d.perpTo(vu).unit;
      a = a + dp * (k * seam.coef * sp * sp);
    }
    return a;
  }

  static V3 _hermite(V3 p0, V3 v0, V3 p1, V3 v1, double s, double dt) {
    final s2 = s * s, s3 = s2 * s;
    return p0 * (2 * s3 - 3 * s2 + 1) + v0 * ((s3 - 2 * s2 + s) * dt) + p1 * (-2 * s3 + 3 * s2) + v1 * ((s3 - s2) * dt);
  }

  /// 打ち出しの向き（yaw：x 方向への振り、pitch：上向き。ラジアン）→ 単位ベクトル（本塁へ向かう）
  static V3 dirOf(double yaw, double pitch) => V3(m.sin(yaw) * m.cos(pitch), -m.cos(yaw) * m.cos(pitch), m.sin(pitch));
}

/// 狙い：リリース位置・球速・回転が決まっているとき、本塁の前の縁で (tx, tz) を通る打ち出しの向きを求める
///  ニュートン法（数値微分のヤコビアン。同じ投手・球種ならヤコビアンは使い回せる）
class AimSolver {
  final List<double> jacInv; // 2x2 の逆行列 [a b c d]（x, z の誤差 → yaw, pitch の補正）
  AimSolver._(this.jacInv);

  static ({V3 vel, Flight flight, int iters, AimSolver solver}) solve(V3 pos, double speed, V3 omega, double tx, double tz,
      {SeamForce seam = SeamForce.none, double rho = BallSpec.airDensity, V3 wind = V3.zero, double dt = 0.002, AimSolver? cached, double tol = 0.002, double seamOrient = 1.0}) {
    // 最初の向き：まっすぐ狙って、重力で落ちる分だけ上へ
    final d = V3(tx, FieldSpec.plateFrontY, tz) - pos;
    var yaw = m.atan2(d.x, -d.y);
    final horiz = m.sqrt(d.x * d.x + d.y * d.y);
    final tGuess = horiz / (speed * 0.95);
    var pitch = m.atan2(d.z + 0.5 * BallSpec.gravity * tGuess * tGuess, horiz);
    Flight run(double yw, double pt) => BallFlight.fly(pos, BallFlight.dirOf(yw, pt) * speed, omega, seam: seam, rho: rho, wind: wind, dt: dt, seamOrient: seamOrient);
    var f = run(yaw, pitch);
    var solver = cached;
    if (solver == null) {
      const h = 0.002;
      final fy = run(yaw + h, pitch), fp = run(yaw, pitch + h);
      final a = (fy.cross.x - f.cross.x) / h, c = (fy.cross.z - f.cross.z) / h;
      final b = (fp.cross.x - f.cross.x) / h, dd = (fp.cross.z - f.cross.z) / h;
      final det = a * dd - b * c;
      solver = AimSolver._([dd / det, -b / det, -c / det, a / det]);
    }
    final j = solver.jacInv;
    var it = 0;
    for (; it < 8; it++) {
      final ex = tx - f.cross.x, ez = tz - f.cross.z;
      if (ex.abs() < tol && ez.abs() < tol) break;
      yaw += j[0] * ex + j[1] * ez;
      pitch += j[2] * ex + j[3] * ez;
      f = run(yaw, pitch);
    }
    return (vel: BallFlight.dirOf(yaw, pitch) * speed, flight: f, iters: it, solver: solver);
  }
}
