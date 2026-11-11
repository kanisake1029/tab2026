import 'dart:convert';
import 'dart:math' as m;
import '../models/player.dart';
import 'ball_flight.dart';
import 'ball_spec.dart';
import 'body_model.dart';
import 'environment.dart';
import 'grip_spin.dart';
import 'pitch_motion.dart';
import 'vec3.dart';

/// ゾーンの座標（試合の記録 PitchEvent.x・z。±1＝ゾーンの端、x の＋＝投手から見て右）と本塁基準の座標（m）の換算
class Zone {
  static const halfW = 0.22, midZ = 0.75, halfH = 0.28;
  static double worldX(double zx) => -zx * halfW;
  static double worldZ(double zz) => midZ + zz * halfH;
  static double zoneX(double wx) => -wx / halfW;
  static double zoneZ(double wz) => (wz - midZ) / halfH;
}

/// 1人の投手の1球種（通常のフォーム／クイック別）の物理：基準の1球を実際に飛ばし、
///  打ち出しの向き・球速・回転の強さを少し変えたときに到達点がどれだけ動くか（ヤコビアン）を持っておく。
///  試合の1球ごとはこの線形の関係で到達点を出す（数値積分しなくても誤差は数mm）
class PitchKind {
  final SpinResult spin;
  final V3 release;
  final double vRef; // 基準の球速 m/s
  final double yawRef, pitchRef;
  final V3 cRef; // 基準の1球の到達点
  final double tRef; // 到達までの時間
  final V3 aCross; // 到達点での加速度（重力・空気抵抗・マグヌス力・縫い目の力）
  final List<double> jx, jz; // 到達点の x・z の、yaw・pitch・球速・回転の強さ に対する微分
  V3 aLate = V3.zero; // 直球と比べた、終盤の加速度の差（打者が予測からずれる分）
  V3 vCross = V3.zero; // 基準の1球の本塁での速度

  PitchKind._(this.spin, this.release, this.vRef, this.yawRef, this.pitchRef, this.cRef, this.tRef, this.aCross, this.jx, this.jz);

  factory PitchKind.build(SpinResult spin, V3 release, {GameEnv? env}) {
    final e = env ?? GameEnv.standard;
    final v = spin.speed;
    final d = V3(0, FieldSpec.plateFrontY, Zone.midZ) - release;
    final horiz = m.sqrt(d.x * d.x + d.y * d.y), tG = horiz / (v * 0.95);
    final yaw = m.atan2(d.x, -d.y), pitch = m.atan2(d.z + 0.5 * BallSpec.gravity * tG * tG, horiz);
    Flight fly(double yw, double pt, double sp, double sc) =>
        BallFlight.fly(release, BallFlight.dirOf(yw, pt) * sp, spin.omega * sc, seam: spin.seam.coef == 0 ? spin.seam : SeamForce(spin.seam.coef * sc, spin.seam.dir, wobbleHz: spin.seam.wobbleHz, phase: spin.seam.phase), seamOrient: spin.seamOrient, dt: 0.002, rho: e.rho, wind: e.wind);
    final f0 = fly(yaw, pitch, v, 1);
    const ha = 0.003, hv = 1.0, hs = 0.1;
    final fy = fly(yaw + ha, pitch, v, 1), fp = fly(yaw, pitch + ha, v, 1), fv = fly(yaw, pitch, v + hv, 1), fs = fly(yaw, pitch, v, 1 + hs);
    List<double> col(double Function(V3) g) => [(g(fy.cross) - g(f0.cross)) / ha, (g(fp.cross) - g(f0.cross)) / ha, (g(fv.cross) - g(f0.cross)) / hv, (g(fs.cross) - g(f0.cross)) / hs];
    final a = BallFlight.accel(f0.vCross, f0.tCross, spin.omega, seam: spin.seam, seamOrient: spin.seamOrient, rho: e.rho, wind: e.wind);
    return PitchKind._(spin, release, v, yaw, pitch, f0.cross, f0.tCross, a, col((c) => c.x), col((c) => c.z))..vCross = f0.vCross;
  }

  /// 狙い（ゾーン座標）に投げる。speedKmh：実際の球速、spinScale：回転の強さ（疲れると落ちる）、sigma：制球のばらつき（ゾーン座標）
  ///  投手は「いつもの回転」のつもりで狙い、リリースの向きが制球の分だけぶれる
  PitchShot throwAt(double tx, double tz, {required double speedKmh, double spinScale = 1, required double sigma, double? sigmaRad, required double Function() gauss}) {
    final wx = Zone.worldX(tx), wz = Zone.worldZ(tz);
    final dv = speedKmh / 3.6 - vRef, ds = spinScale - 1;
    // 狙い：球速の違いは織り込み、回転は「いつもどおり」と思って向きを決める
    final ex = wx - cRef.x - jx[2] * dv, ez = wz - cRef.z - jz[2] * dv;
    final det = jx[0] * jz[1] - jx[1] * jz[0];
    final dy = (jz[1] * ex - jx[1] * ez) / det, dp = (-jz[0] * ex + jx[0] * ez) / det;
    // 制球：リリースの向きのぶれ（到達点で σ×ゾーンの半幅・半高になる大きさ）
    // sigmaRad（仕様書 6.2：放出角のガウス誤差）があればそれを使う
    final ey = sigmaRad != null ? gauss() * sigmaRad : gauss() * sigma * Zone.halfW / jx[0].abs();
    final ep = sigmaRad != null ? gauss() * sigmaRad : gauss() * sigma * Zone.halfH / jz[1].abs();
    final ay = dy + ey, ap = dp + ep;
    final cx = cRef.x + jx[0] * ay + jx[1] * ap + jx[2] * dv + jx[3] * ds;
    final cz = cRef.z + jz[0] * ay + jz[1] * ap + jz[2] * dv + jz[3] * ds;
    return PitchShot(Zone.zoneX(cx), Zone.zoneZ(cz), yawRef + ay, pitchRef + ap, speedKmh / 3.6, spinScale, tRef * vRef / (speedKmh / 3.6));
  }
}

/// 1球の結果（物理）
class PitchShot {
  final double x, z; // 到達点（ゾーン座標）
  final double yaw, pitch, speed, spinScale, time;
  const PitchShot(this.x, this.z, this.yaw, this.pitch, this.speed, this.spinScale, this.time);
}

/// 投手ごとの物理（体格・フォーム・球種が変わるまで使い回す）
class PitcherPhysics {
  final String sig;
  final Player p;
  final MotionRelease normal, quick;
  double quickRelease = 0.75; // クイックで動き始めてから放すまで（秒）
  double get flightTime => (FieldSpec.rubberFrontY - quick.extension - FieldSpec.plateFrontY) / (p.velocity / 3.6 * 0.93); // 直球が届くまで
  final _kinds = <String, PitchKind>{};
  PitcherPhysics._(this.sig, this.p, this.normal, this.quick);

  static final _cache = <String, PitcherPhysics>{};

  /// 体格・フォーム・球種の「しるし」。変わったら作り直す
  static String _sigOf(Player p) {
    final b = StringBuffer('${p.height},${p.weight},${p.armLength},${p.spinAxis},${p.throws},${p.velocity},${jsonEncode(p.form.toJson())}');
    for (final x in p.pitches) {
      b.write('|${x.name}:${x.speed}:${x.breakLevel}:${x.angle}:${x.sharpness}:${x.heaviness}');
      if (x.grip != null) b.write(':${jsonEncode(x.grip!.toJson())}');
    }
    return b.toString();
  }

  static PitcherPhysics of(Player p) {
    final sig = _sigOf(p);
    final c = _cache[p.id];
    if (c != null && c.sig == sig) return c;
    final body = BodyModel.ofPlayer(p);
    final lefty = p.throws == 'L';
    final n = PitchMotion(body, p.form, armAngleDeg: p.spinAxis, lefty: lefty, velocity: p.velocity).release;
    final qm = PitchMotion(body, p.form, armAngleDeg: p.spinAxis, lefty: lefty, velocity: p.velocity, quick: true);
    return _cache[p.id] = PitcherPhysics._(sig, p, n, qm.release)..quickRelease = qm.ph.br - qm.ph.liftStart + 0.05;
  }

  static void clearCache() => _cache.clear();

  Pitch get _fastball => p.pitches.where((x) => x.name == 'ストレート').firstOrNull ?? (p.pitches.isEmpty ? Player.fielderStraight(p.velocity) : p.pitches.first);

  final _spins = <String, SpinResult>{};

  /// 球種の回転（握りで決まる。空気には左右されない）
  SpinResult spinOf(Pitch x, {bool quick = false}) {
    final key = '${x.name}|${x.speed}|$quick';
    final c = _spins[key];
    if (c != null) return c;
    final fb = _fastball;
    final rel = (quick ? this.quick : normal).pos;
    return _spins[key] = GripSpin.of(x, pos: rel, armAngle: p.spinAxis, lefty: p.throws == 'L', velocity: p.velocity, fbSharp: fb.sharpness, fbHeavy: fb.heaviness, seed: p.id.hashCode & 0xffff);
  }

  /// 球種の飛び方（その試合の空気・風で）
  PitchKind kind(Pitch pitch, {bool quick = false, GameEnv? env}) {
    final e = env ?? GameEnv.standard;
    final key = '${pitch.name}|${pitch.speed}|$quick|${e.key}';
    final k = _kinds[key];
    if (k != null) return k;
    final rel = (quick ? this.quick : normal).pos;
    final fb = _fastball;
    final kk = PitchKind.build(spinOf(pitch, quick: quick), rel, env: e);
    if (pitch.name != fb.name || pitch.speed != fb.speed) {
      final fk = '${fb.name}|${fb.speed}|$quick|${e.key}';
      final f = _kinds[fk] ?? (_kinds[fk] = PitchKind.build(spinOf(fb, quick: quick), rel, env: e));
      kk.aLate = kk.aCross - f.aCross;
    }
    if (_kinds.length > 200) _kinds.clear();
    return _kinds[key] = kk;
  }
}
