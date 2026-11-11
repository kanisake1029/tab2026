import 'dart:math' as m;
import '../models/pitching_form.dart';
import 'ball_spec.dart';
import 'body_model.dart';
import 'vec3.dart';

/// 関節（T＝投げる腕の側、G＝グラブの側。脚は T＝軸足、G＝踏み出す足）
enum J { pelvis, hipT, hipG, kneeT, kneeG, ankleT, ankleG, toeT, toeG, neck, head, shoulderT, shoulderG, elbowT, elbowG, wristT, wristG, ball, glove }

/// 局面の時刻（秒。動き始め＝0）
class MotionPhases {
  final double liftStart, liftPeak, holdEnd, handBreak, ffs, mer, br, end;
  const MotionPhases(this.liftStart, this.liftPeak, this.holdEnd, this.handBreak, this.ffs, this.mer, this.br, this.end);
}

/// リリースの結果（本塁基準の座標。m・m/s・度・度/秒）
class MotionRelease {
  final V3 pos; // ボールを放した位置
  final double extension; // 投手板の前の縁から前へ何 m で放したか
  final V3 handVel; // 指先（ボール）の速度
  final double armAngle; // 実際の腕の角度（捕手から見た肩→ボールの線の、真上からの角度）
  final double abduction; // 肩の外転（体幹に対する腕の上がり）
  final double tilt; // 体幹の横の傾き（＋＝グラブ側）
  final double trunkFlex; // 体幹の前傾
  final double sepFFS; // 着地での腰と肩の捻転差
  final double pelvisPeak, trunkPeak, elbowPeak, irPeak; // 骨盤・体幹の回転、肘の伸展、肩の内旋の最大の角速度
  final double tPelvisPeak, tTrunkPeak, tElbowPeak, tIrPeak;
  final double leadKneeFFS, leadKneeBR, merDeg, strideM;
  const MotionRelease({
    required this.pos, required this.extension, required this.handVel, required this.armAngle, required this.abduction, required this.tilt, required this.trunkFlex,
    required this.sepFFS, required this.pelvisPeak, required this.trunkPeak, required this.elbowPeak, required this.irPeak,
    required this.tPelvisPeak, required this.tTrunkPeak, required this.tElbowPeak, required this.tIrPeak,
    required this.leadKneeFFS, required this.leadKneeBR, required this.merDeg, required this.strideM,
  });
  double get handSpeed => handVel.length;
  double get height => pos.z;
}

/// キーフレームの時系列（単調な3次補間 Fritsch–Carlson：行き過ぎない、なめらか）
class _Track {
  final _k = <(double, double)>[];
  late List<double> _t, _v, _m;
  void add(double t, double v) => _k.add((t, v));

  /// a→b を「ベル形の速さ」（sin² の速度。最大の速さ＝2×平均）で動かす
  void bell(double ta, double tb, double a, double b, {int n = 14}) {
    for (var i = 0; i <= n; i++) {
      final u = i / n;
      add(ta + (tb - ta) * u, a + (b - a) * (u - m.sin(2 * m.pi * u) / (2 * m.pi)));
    }
  }

  void build() {
    _k.sort((a, b) => a.$1.compareTo(b.$1));
    final t = <double>[], v = <double>[];
    for (final k in _k) {
      if (t.isNotEmpty && k.$1 - t.last < 1e-5) {
        v[v.length - 1] = k.$2; // 同じ時刻は後のもの
        continue;
      }
      t.add(k.$1);
      v.add(k.$2);
    }
    _t = t;
    _v = v;
    final n = t.length;
    final d = List<double>.generate(m.max(0, n - 1), (i) => (v[i + 1] - v[i]) / (t[i + 1] - t[i]));
    final mm = List<double>.filled(n, 0);
    if (n >= 2) {
      mm[0] = d[0];
      mm[n - 1] = d[n - 2];
      for (var i = 1; i < n - 1; i++) {
        mm[i] = d[i - 1] * d[i] <= 0 ? 0 : (d[i - 1] + d[i]) / 2;
      }
      for (var i = 0; i < n - 1; i++) {
        if (d[i] == 0) {
          mm[i] = 0;
          mm[i + 1] = 0;
          continue;
        }
        final a = mm[i] / d[i], b = mm[i + 1] / d[i];
        final s = a * a + b * b;
        if (s > 9) {
          final tau = 3 / m.sqrt(s);
          mm[i] = tau * a * d[i];
          mm[i + 1] = tau * b * d[i];
        }
      }
    }
    _m = mm;
  }

  int _seg(double t) {
    var lo = 0, hi = _t.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (_t[mid] <= t) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  double at(double t) {
    if (_t.length == 1 || t <= _t.first) return _v.first;
    if (t >= _t.last) return _v.last;
    final i = _seg(t);
    final h = _t[i + 1] - _t[i], s = (t - _t[i]) / h;
    final s2 = s * s, s3 = s2 * s;
    return _v[i] * (2 * s3 - 3 * s2 + 1) + _m[i] * h * (s3 - 2 * s2 + s) + _v[i + 1] * (-2 * s3 + 3 * s2) + _m[i + 1] * h * (s3 - s2);
  }

  double vel(double t) {
    if (_t.length == 1 || t <= _t.first || t >= _t.last) return 0;
    final i = _seg(t);
    final h = _t[i + 1] - _t[i], s = (t - _t[i]) / h;
    final s2 = s * s;
    return (_v[i] * (6 * s2 - 6 * s) + _m[i] * h * (3 * s2 - 4 * s + 1) + _v[i + 1] * (-6 * s2 + 6 * s) + _m[i + 1] * h * (3 * s2 - 2 * s)) / h;
  }
}

/// 体幹の向き（向き yaw・前傾 flex・横の傾き tilt）→ 前 F・右 R・上 U
class _Frame {
  final V3 f, r, u;
  const _Frame(this.f, this.r, this.u);
  factory _Frame.of(double yawDeg, double flexDeg, double tiltDeg) {
    final y = yawDeg * deg, p = flexDeg * deg, l = tiltDeg * deg;
    final f0 = V3(m.sin(y), m.cos(y), 0), l0 = V3(-m.cos(y), m.sin(y), 0);
    final u1 = V3.ez * m.cos(p) + f0 * m.sin(p), f1 = f0 * m.cos(p) - V3.ez * m.sin(p);
    final u2 = u1 * m.cos(l) + l0 * m.sin(l), l2 = l0 * m.cos(l) - u1 * m.sin(l);
    return _Frame(f1, -l2, u2);
  }
  V3 get l => -r;
  V3 toLocal(V3 v) => V3(v.dot(f), v.dot(r), v.dot(u));
  V3 fromLocal(V3 c) => f * c.x + r * c.y + u * c.z;
}

/// 投球動作：フォーム・体格・腕の角度 → 全身の関節の動き（時系列）と、リリースの位置・速さ・角速度
///  右投手として作り、左投手は鏡に映す。局面と数値の目安：
///   ①足上げ（股関節 30〜120°・骨盤を背中側へ 10〜30°）→ ②並進（踏み出し 身長の 80〜90%）→ 着地（FFS：前膝 40〜50°・捻転差 40〜60°）
///   → ③レイトコッキング（肩の最大外旋 160〜185°）→ ④加速（肘の伸展 約2300°/s・肩の内旋 7000〜9000°/s）→ リリース（前膝 20〜30°・前傾 30〜45°）
///  投手の向きの座標（右投手）：X＝三塁側、Y＝本塁の方向、Z＝上。原点は投手板の前の縁の中央・マウンドの頂上
class PitchMotion {
  final BodyModel body;
  final PitchingForm form;
  final int armAngleDeg;
  final bool lefty, quick;
  final double sf; // 速さの寄せ（球速÷145）
  late final MotionPhases ph;
  late final double _rubberX, _strideY;
  late final V3 _ankleT0, _ankleG0, _land;
  late final double _liftAlpha, _leadKFFS, _leadKBR;
  final _pYaw = _Track(), _tYaw = _Track(), _tFlex = _Track(), _tTilt = _Track();
  final _px = _Track(), _py = _Track(), _pz = _Track();
  final _ae = _Track(), _ah = _Track(), _ar = _Track(), _ak = _Track(), _aw = _Track(); // 投げる腕：外転 ε・水平外転 η・外旋 ρ・肘の屈曲 κ・手首（−＝背屈）
  final _gf = _Track(), _gr = _Track(), _gu = _Track(); // グラブの手の位置（体幹の座標）
  final _pivotY = _Track(), _pivotZ = _Track(), _pivotX = _Track();
  double _eBR = 90;
  late final MotionRelease release;

  PitchMotion(this.body, this.form, {required this.armAngleDeg, this.lefty = false, this.quick = false, int velocity = 145}) : sf = (velocity / 145.0).clamp(0.7, 1.15) {
    _build();
  }

  static double _groundL(double y) => FieldSpec.groundZ(FieldSpec.rubberFrontY - y) - FieldSpec.moundHeight;

  /// 投手の座標 → 本塁基準の座標
  V3 toWorld(V3 p) => V3(lefty ? p.x : -p.x, FieldSpec.rubberFrontY - p.y, p.z + FieldSpec.moundHeight);

  double get _tilt => PitchingForm.lateralTiltOf(armAngleDeg);

  void _build() {
    final f = form, b = body;
    final tempoF = 1.15 - f.tempo / 100 * 0.3;
    final windup = quick ? 'セットポジション' : f.windup;
    final pre = quick ? 0.05 : switch (windup) { 'ワインドアップ' => 0.55, 'トルネード' => 0.45, 'セットポジション' => 0.10, _ => 0.30 };
    final liftMs = quick ? 0.20 : f.legLiftMs / 1000 * tempoF;
    final hold = quick ? 0.0 : f.holdMs / 1000;
    final strideDur = (quick ? 0.30 : 0.40 * tempoF) * m.sqrt(f.strideRatio / 85);
    final liftPeak = pre + liftMs, holdEnd = liftPeak + hold;
    final ffs = holdEnd + strideDur;
    final mer = ffs + 0.145 / sf, br = mer + 0.040 / sf;
    ph = MotionPhases(pre, liftPeak, holdEnd, holdEnd + 0.04, ffs, mer, br, br + 0.75);
    final cr = quick ? 5.0 : f.counterRot.toDouble();
    final faceHome = !quick && windup != 'セットポジション';
    final yaw0 = faceHome ? 0.0 : 90.0;

    // ── 足の位置 ──
    _rubberX = f.rubberPos / 100.0;
    _strideY = f.strideRatio / 100 * b.height;
    _ankleT0 = V3(_rubberX, 0.07, b.ankleH);
    _ankleG0 = faceHome ? V3(_rubberX - 0.26, -0.12, b.ankleH) : V3(_rubberX - 0.04, 0.42, _groundL(0.42) + b.ankleH);
    _land = V3(_rubberX + f.stepOffset / 100.0, _strideY, _groundL(_strideY) + b.ankleH);
    // 足上げの股関節の曲がり（仕様書 2.3 ②：標準で約100°）：0＝すり足 30°、50＝100°、100＝120°
    _liftAlpha = quick ? 38 : 30 + 70 * m.min(1.0, f.legLiftHeight / 50) + 20 * m.max(0.0, (f.legLiftHeight - 50) / 50);
    _leadKFFS = 44 + (f.kneeDrop - 35) * 0.3;
    _leadKBR = 25 + (f.kneeDrop - 35) * 0.2;

    // ── 骨盤の向き ──
    final pk = 600 * m.pow(sf, 1.5); // 最大の角速度の目安
    _pYaw
      ..add(0, yaw0)
      ..add(pre, yaw0 + (90 - yaw0) * 0.6)
      ..add(liftPeak, 90 + cr)
      ..add(holdEnd, 90 + cr);
    final pA = 90 + cr * 0.3, pB = -25.0;
    final pTb = br + 0.03;
    final pTa = m.max(holdEnd + 0.05, pTb - 2 * (pA - pB) / pk);
    _pYaw
      ..bell(pTa, pTb, pA, pB)
      ..add(br + 0.30, -40)
      ..add(ph.end, -45)
      ..build();

    // ── 体幹の向き（捻転差は着地で sep） ──
    final tk = 1100 * m.pow(sf, 1.5);
    final tA = _pYaw.at(ffs) + f.hipShoulderSep, tB = -30.0;
    final tTb = br + 0.05;
    final tTa = m.max(holdEnd + 0.08, tTb - 2 * (tA - tB) / tk);
    _tYaw
      ..add(0, yaw0)
      ..add(pre, yaw0 + (90 - yaw0) * 0.6)
      ..add(liftPeak, 90 + cr * 1.25)
      ..add(holdEnd, 90 + cr * 1.25)
      ..add(m.min(tTa, ffs) - 0.001, tA)
      ..bell(tTa, tTb, tA, tB)
      ..add(br + 0.30, -55)
      ..add(ph.end, -60)
      ..build();
    _tFlex
      ..add(0, 5)
      ..add(liftPeak, -2)
      ..add(holdEnd, 0)
      ..add(ffs, 8)
      ..add(mer, 20 + (f.trunkFlex - 36) * 0.4)
      ..add(br, f.trunkFlex.toDouble())
      ..add(br + 0.08, f.trunkFlex + 14.0)
      ..add(ph.end, f.trunkFlex + 22.0)
      ..build();
    _tTilt
      ..add(0, 0)
      ..add(holdEnd, 0)
      ..add(ffs, -4)
      ..add(mer, _tilt * 0.7)
      ..add(br, _tilt)
      ..add(br + 0.1, _tilt * 0.8)
      ..add(ph.end, _tilt * 0.5)
      ..build();

    // ── 骨盤の位置 ──
    final hipH = b.hipJointH;
    V3 lp(double t) {
      final y = _pYaw.at(t) * deg;
      return V3(-m.cos(y), m.sin(y), 0);
    }

    V3 overPivot(double t, double dz) {
      final c = _ankleT0 + lp(t) * (b.hipW / 2);
      return V3(c.x, c.y, hipH + dz);
    }

    V3 fromLead(double t, double shankBackDeg, double kneeFlex) {
      final sh = shankBackDeg * deg, th = (shankBackDeg + kneeFlex) * deg;
      final knee = _land + V3(0, -m.sin(sh), m.cos(sh)) * b.shank;
      final hipG = knee + V3(0, -m.sin(th), m.cos(th)) * b.thigh;
      final c = hipG - lp(t) * (b.hipW / 2);
      return V3((c.x + _land.x) / 2, c.y, c.z);
    }

    final start = faceHome ? V3((_ankleT0.x + _ankleG0.x) / 2, (_ankleT0.y + _ankleG0.y) / 2, hipH - 0.02) : V3(_ankleT0.x, (_ankleT0.y + _ankleG0.y) / 2, hipH - 0.03);
    final pPeak = overPivot(liftPeak, -0.04), pHold = overPivot(holdEnd, -0.05);
    final pF = fromLead(ffs, 4, _leadKFFS);
    final pB2 = fromLead(br, 12 - (f.extension - 50) * 0.12, _leadKBR);
    final drop = _kneeDrop(f.kneeDrop.toDouble()) * 1.3;
    final tDrive = holdEnd + strideDur * 0.55;
    final pD = V3(pHold.x + (pF.x - pHold.x) * 0.4, pHold.y + (pF.y - pHold.y) * 0.38, hipH - drop);
    final pEnd = V3(pB2.x - 0.15, pB2.y + 0.20, pB2.z - 0.12);
    for (final (t, p) in [(0.0, start), (pre, start.lerp(pPeak, 0.3)), (liftPeak, pPeak), (holdEnd, pHold), (tDrive, pD), (ffs, pF), (br, pB2), (br + 0.15, pB2.lerp(pEnd, 0.6)), (ph.end, pEnd)]) {
      _px.add(t, p.x);
      _py.add(t, p.y);
      _pz.add(t, p.z);
    }
    _px.build();
    _py.build();
    _pz.build();

    // ── 軸足（投げ終わると前へ振り出す） ──
    final ft = V3(_land.x - 0.30, _land.y - 0.25, _groundL(_land.y - 0.25) + b.ankleH);
    for (final (t, p) in [(0.0, _ankleT0), (br + 0.02, _ankleT0), (br + 0.25, (_ankleT0.lerp(ft, 0.6)) + const V3(0, 0, 0.35)), (br + 0.5, ft), (ph.end, ft)]) {
      _pivotX.add(t, p.x);
      _pivotY.add(t, p.y);
      _pivotZ.add(t, p.z);
    }
    _pivotX.build();
    _pivotY.build();
    _pivotZ.build();

    // ── 投げる腕 ──
    _buildArm();
    // 腕の角度に合うよう、リリースでの肩の外転を合わせ直す
    for (var i = 0; i < 16; i++) {
      final a = _measuredArmAngle(ph.br);
      final err = armAngleDeg - a;
      if (err.abs() < 0.3) break;
      _eBR = (_eBR - err * 0.8).clamp(40.0, 175.0);
      _buildArm();
    }
    _buildGlove();
    release = _measure();
  }

  static double _kneeDrop(double kneeFlex) {
    const a = 0.45, b = 0.45;
    final k = kneeFlex * deg;
    return (a + b) - m.sqrt(a * a + b * b + 2 * a * b * m.cos(k));
  }

  // ───── 姿勢の部品 ─────
  _Frame _trunkAt(double t) => _Frame.of(_tYaw.at(t), _tFlex.at(t), _tTilt.at(t));
  V3 pelvisAt(double t) => V3(_px.at(t), _py.at(t), _pz.at(t));
  V3 _lp(double t) {
    final y = _pYaw.at(t) * deg;
    return V3(-m.cos(y), m.sin(y), 0);
  }

  V3 _fp(double t) {
    final y = _pYaw.at(t) * deg;
    return V3(m.sin(y), m.cos(y), 0);
  }

  V3 neckAt(double t) => pelvisAt(t) + _trunkAt(t).u * body.trunk;
  V3 shoulderTAt(double t) {
    final fr = _trunkAt(t);
    return neckAt(t) - fr.u * 0.03 + fr.r * (body.shoulderW / 2);
  }

  /// 投げる腕の順運動学：肩 S・体幹 fr・角度（度）→ 肘・手首・ボール
  (V3, V3, V3) _armFK(V3 s, _Frame fr, double e, double h, double r, double k, [double w = 0]) {
    final ee = e * deg, hh = h * deg, rr = r * deg, kk = k * deg, ww = w * deg;
    final hu = (-fr.u * m.cos(ee) + (fr.r * m.cos(hh) - fr.f * m.sin(hh)) * m.sin(ee)).unit;
    var f0 = fr.f.perpTo(hu);
    if (f0.length < 0.05) f0 = fr.u.perpTo(hu);
    f0 = f0.unit;
    final u0 = hu.cross(f0);
    final pd = f0 * m.cos(rr) + u0 * m.sin(rr);
    final fd = hu * m.cos(kk) + pd * m.sin(kk);
    final elbow = s + hu * body.upperArm;
    final wrist = elbow + fd * body.forearm;
    // 手首：内旋で手が進む向き q の側へ曲げる（掌屈）。背屈（−）でしなりを溜め、リリースで返す
    final q = f0 * m.sin(rr) - u0 * m.cos(rr);
    final hd = fd * m.cos(ww) + q * m.sin(ww);
    return (elbow, wrist, wrist + hd * body.handToBall);
  }

  /// 肘・手首の位置 → 腕の角度（_armFK の逆）
  (double, double, double, double) _armAngles(V3 s, V3 elbow, V3 wrist, _Frame fr) {
    final hu = (elbow - s).unit;
    final e = m.acos((-hu.dot(fr.u)).clamp(-1.0, 1.0)) / deg;
    final h = m.atan2(-hu.dot(fr.f), hu.dot(fr.r)) / deg;
    final fd = (wrist - elbow).unit;
    final k = m.acos(hu.dot(fd).clamp(-1.0, 1.0)) / deg;
    var f0 = fr.f.perpTo(hu);
    if (f0.length < 0.05) f0 = fr.u.perpTo(hu);
    f0 = f0.unit;
    final u0 = hu.cross(f0);
    final pd = fd.perpTo(hu);
    final r = pd.length < 1e-6 ? 0.0 : m.atan2(pd.dot(u0), pd.dot(f0)) / deg;
    return (e, h, r, k);
  }

  static V3 _ik(V3 a, V3 t, double la, double lb, V3 pole) {
    final d = t - a;
    final dist = d.length.clamp((la - lb).abs() + 1e-4, la + lb - 1e-4);
    final dir = d.unit;
    final c = ((la * la + dist * dist - lb * lb) / (2 * la * dist)).clamp(-1.0, 1.0);
    var p = pole.perpTo(dir);
    if (p.length < 1e-6) p = V3.ez.perpTo(dir);
    return a + dir * (la * c) + p.unit * (la * m.sqrt(1 - c * c));
  }

  /// 構えの手の位置（顔・胸・ベルト）
  V3 _holdTarget(double t, {bool overhead = false}) {
    final fr = _trunkAt(t), n = neckAt(t);
    if (overhead) return n + fr.u * 0.42 + fr.f * 0.06;
    final up = const [0.10, -0.13, -0.36][form.handHold.clamp(0, 2)];
    return n + fr.f * 0.26 + fr.u * up + fr.r * 0.02;
  }

  (double, double, double, double) _holdAngles(double t, {bool overhead = false}) {
    final fr = _trunkAt(t), s = shoulderTAt(t);
    final tg = _holdTarget(t, overhead: overhead);
    final la = body.upperArm, lb = body.forearm + body.handToBall;
    final el = _ik(s, tg, la, lb, fr.r * 0.7 - fr.u * 0.6 - fr.f * 0.2);
    final wr = el + (tg - el).unit * body.forearm;
    final a = _armAngles(s, el, wr, fr);
    var r = a.$3;
    while (r > 180) {
      r -= 360;
    }
    while (r <= -180) {
      r += 360;
    }
    return (a.$1, a.$2, r, a.$4);
  }

  void _buildArm() {
    for (final t in [_ae, _ah, _ar, _ak, _aw]) {
      t._k.clear();
    }
    final f = form, p = ph;
    void key(double t, (double, double, double, double) a) {
      _ae.add(t, a.$1);
      _ah.add(t, a.$2);
      _ar.add(t, a.$3);
      _ak.add(t, a.$4);
    }

    final h0 = _holdAngles(0);
    key(0, h0);
    if (!quick && f.windup == 'ワインドアップ') {
      key(p.liftStart * 0.55, _holdAngles(p.liftStart * 0.55, overhead: true));
    }
    key(p.liftPeak, _holdAngles(p.liftPeak));
    key(p.holdEnd, _holdAngles(p.holdEnd));
    // テイクバック：ロングアーム（下ろして後ろへ大きく）〜ショートアーム（肘から最短で上げる）
    final tb = f.takeback / 100.0;
    double mix(double s, double l) => s + (l - s) * tb;
    final tTB = p.handBreak + (p.ffs - p.handBreak) * 0.45;
    key(tTB, (mix(82, 38), mix(48, 18), mix(25, -35), mix(105, 18)));
    final e = _eBR;
    key(p.ffs, (e * 0.96, 26, 62, 95));
    // 着地 → 最大外旋（体幹が回り、腕が後ろへしなる）
    final ir = 7500 * m.pow(sf, 1.5);
    const rBR = 102.0;
    final dt = p.br - p.mer;
    final kExp = m.max(1.6, ir * dt / (f.merDeg - rBR));
    _ae.add(p.mer, e);
    _ah.add(p.mer, 8);
    _ar.add(p.mer, f.merDeg.toDouble());
    // 最大外旋 → リリース：内旋が加速していき、リリースで約 ir°/s
    for (var i = 1; i <= 10; i++) {
      final u = i / 10;
      _ar.add(p.mer + dt * u, f.merDeg - (f.merDeg - rBR) * m.pow(u, kExp));
    }
    _ar
      ..add(p.br + 0.010, rBR - ir * 0.010 * 0.85)
      ..add(p.br + 0.04, 22)
      ..add(p.br + 0.12, 0)
      ..add(p.end, 8);
    _ae
      ..add(p.br, e)
      ..add(p.br + 0.05, e - 10)
      ..add(p.br + 0.15, 62)
      ..add(p.end, 42);
    _ah
      ..add(p.br, -10 - f.extension * 0.08 - m.max(0, armAngleDeg - 100) * 0.6)
      ..add(p.br + 0.05, -38)
      ..add(p.br + 0.15, -82)
      ..add(p.end, -95);
    // 肘：最大外旋の少し前から伸び、約 2300°/s
    final ek = 2300 * m.pow(sf, 1.5);
    const k0 = 97.0, k1 = 22.0;
    final span = (k0 - k1) * 1.6 / (0.951 * ek);
    final tE0 = p.br - span;
    _ak
      ..add(p.mer - 0.03 < tE0 ? p.mer - 0.03 : tE0 - 0.005, 96)
      ..add(tE0, k0);
    for (var i = 1; i <= 10; i++) {
      final u = i / 10, w = u * 0.8;
      _ak.add(tE0 + span * u, k0 - (k0 - k1) * (w - m.sin(2 * m.pi * w) / (2 * m.pi)) / 0.951);
    }
    _ak
      ..add(p.br + 0.03, 26)
      ..add(p.br + 0.12, 40)
      ..add(p.end, 58);
    // 手首：着地で背屈し始め、最大外旋で約45°、リリースへ向けて一気に返す
    _aw
      ..add(0, 0)
      ..add(p.handBreak, 0)
      ..add(p.ffs, -20)
      ..add(p.mer, -45);
    for (var i = 1; i <= 8; i++) {
      final u = i / 8;
      _aw.add(p.mer + dt * u, -45 + 40 * m.pow(u, 2.5).toDouble());
    }
    _aw
      ..add(p.br + 0.03, 25)
      ..add(p.end, 12);
    for (final t in [_ae, _ah, _ar, _ak, _aw]) {
      t.build();
    }
  }

  (V3, V3, V3) armAt(double t) => _armFK(shoulderTAt(t), _trunkAt(t), _ae.at(t), _ah.at(t), _ar.at(t), _ak.at(t), _aw.at(t));
  V3 ballAt(double t) => armAt(t).$3;

  double _measuredArmAngle(double t) {
    final v = ballAt(t) - shoulderTAt(t);
    return m.atan2(v.x, v.z) / deg; // 捕手から見て、真上から投げる腕の側へ
  }

  void _buildGlove() {
    final p = ph;
    void key(double t, V3 c) {
      _gf.add(t, c.x);
      _gr.add(t, c.y);
      _gu.add(t, c.z);
    }

    V3 rel(double t, V3 w) => _trunkAt(t).toLocal(w - neckAt(t));
    key(p.handBreak, rel(p.handBreak, ballAt(p.handBreak)));
    // 着地：グラブの腕を本塁へ向けて伸ばす → リリースで胸へ引きつける
    final fr = _trunkAt(p.ffs);
    final sg = neckAt(p.ffs) - fr.u * 0.03 + fr.l * (body.shoulderW / 2);
    key(p.ffs, rel(p.ffs, sg + V3(-0.05, 1, 0.05).unit * ((body.upperArm + body.forearm) * 0.88)));
    key(p.mer, const V3(0.30, -0.22, -0.08));
    key(p.br, const V3(0.24, -0.13, -0.14));
    key(p.br + 0.15, const V3(0.20, -0.15, -0.30));
    key(p.end, const V3(0.26, -0.10, -0.24));
    _gf.build();
    _gr.build();
    _gu.build();
  }

  V3 _gloveTarget(double t) {
    if (t <= ph.handBreak) {
      final fr = _trunkAt(t);
      return ballAt(t) + fr.l * 0.035 + fr.f * 0.025;
    }
    return neckAt(t) + _trunkAt(t).fromLocal(V3(_gf.at(t), _gr.at(t), _gu.at(t)));
  }

  /// 踏み出す足の足首の目標（足上げ中は股関節の曲げで、そのあとは着地点へ）
  V3 _leadAnkleAt(double t, V3 hipG) {
    final p = ph;
    if (t >= p.ffs) return _land;
    V3 lifted(double tt, V3 hip) {
      final u = ((tt - p.liftStart) / (p.liftPeak - p.liftStart)).clamp(0.0, 1.0);
      final s = u * u * (3 - 2 * u);
      final a = _liftAlpha * s * deg, k = (12 + (88 + _liftAlpha * 0.15) * s) * deg;
      final fp = _fp(tt);
      final knee = hip + (-V3.ez * m.cos(a) + fp * m.sin(a)) * body.thigh;
      final ank = knee + (-V3.ez * m.cos(a - k) + fp * m.sin(a - k)) * body.shank;
      final g0 = _ankleG0;
      if (u < 0.3) return g0.lerp(ank, u / 0.3);
      return ank;
    }

    if (t <= p.liftStart) return _ankleG0;
    if (t <= p.holdEnd) return lifted(t, hipG);
    final hipH = pelvisAt(p.holdEnd) + _lp(p.holdEnd) * (body.hipW / 2);
    final a0 = lifted(p.holdEnd, hipH);
    final u = (t - p.holdEnd) / (p.ffs - p.holdEnd);
    final s = u * u * (3 - 2 * u);
    final x = a0.x + (_land.x - a0.x) * s, y = a0.y + (_land.y - a0.y) * s;
    final z = _land.z + (a0.z - _land.z) * m.pow(1 - u, 1.6) + 0.04 * m.sin(m.pi * u);
    return V3(x, y, m.max(z, _groundL(y) + body.ankleH));
  }

  /// t 秒の全身の姿勢（本塁基準の座標）
  List<V3> poseAt(double t) => [for (final v in _poseLocal(t)) toWorld(v)];

  List<V3> _poseLocal(double t) {
    final b = body, fr = _trunkAt(t);
    final pel = pelvisAt(t), lp = _lp(t), fp = _fp(t);
    final hipT = pel - lp * (b.hipW / 2), hipG = pel + lp * (b.hipW / 2);
    // 軸足：届かないときはかかとを上げ、それでも届かなければ前へ引きずる
    var aT = V3(_pivotX.at(t), _pivotY.at(t), _pivotZ.at(t));
    final lMax = b.legLen * 0.985;
    if (hipT.distanceTo(aT) > lMax) {
      final dz = hipT.z - aT.z;
      final hor = m.sqrt(m.pow(hipT.x - aT.x, 2) + m.pow(hipT.y - aT.y, 2));
      final needZ = hipT.z - m.sqrt(m.max(0, lMax * lMax - hor * hor));
      final zMax = b.ankleH + b.footLen * 0.55 + _groundL(aT.y);
      final nz = needZ.isNaN ? zMax : m.min(zMax, m.max(aT.z, needZ));
      aT = V3(aT.x, aT.y, nz);
      final d2 = hipT - aT;
      if (d2.length > lMax) {
        final hv = V3(d2.x, d2.y, 0);
        final need = m.sqrt(m.max(0, lMax * lMax - d2.z * d2.z));
        if (hv.length > need) aT = aT + hv.unit * (hv.length - need);
      }
      if (dz.isNaN) aT = _ankleT0;
    }
    final aG = _leadAnkleAt(t, hipG);
    final kT = _ik(hipT, aT, b.thigh, b.shank, fp + V3.ey * 0.3);
    final kG = _ik(hipG, aG, b.thigh, b.shank, fp * 0.6 + V3.ey * 0.5 + V3.ez * 0.3);
    final footDirT = t < ph.br ? fp : V3.ey;
    final closed = 10 * deg;
    final footDirG = t < ph.holdEnd ? fp : V3(m.sin(closed), m.cos(closed), 0);
    V3 toe(V3 a, V3 dir) => V3(a.x, a.y, 0) + dir * (b.footLen * 0.72) + V3(0, 0, m.max(_groundL(a.y) + 0.02, a.z - b.ankleH * 1.6));
    final neck = pel + fr.u * b.trunk;
    final head = neck + fr.u * (b.neck + b.headR * 1.05) + fr.f * 0.02;
    final sT = neck - fr.u * 0.03 + fr.r * (b.shoulderW / 2);
    final sG = neck - fr.u * 0.03 + fr.l * (b.shoulderW / 2);
    final (eT, wT, ball) = _armFK(sT, fr, _ae.at(t), _ah.at(t), _ar.at(t), _ak.at(t), _aw.at(t));
    final gT = _gloveTarget(t);
    final eG = _ik(sG, gT, b.upperArm, b.forearm + b.hand * 0.5, fr.l * 0.8 - fr.u * 0.6);
    final wG = eG + (gT - eG).unit * b.forearm;
    return [pel, hipT, hipG, kT, kG, aT, aG, toe(aT, footDirT), toe(aG, footDirG), neck, head, sT, sG, eT, eG, wT, wG, ball, gT];
  }

  MotionRelease _measure() {
    final p = ph;
    double peak(_Track tr, double a, double b, {bool neg = true}) {
      var best = 0.0, at = a;
      for (var t = a; t <= b; t += 0.0005) {
        final v = neg ? -tr.vel(t) : tr.vel(t);
        if (v > best) {
          best = v;
          at = t;
        }
      }
      _lastAt = at;
      return best;
    }

    final pp = peak(_pYaw, p.holdEnd, p.br + 0.05);
    final tpp = _lastAt;
    final tp = peak(_tYaw, p.holdEnd, p.br + 0.05);
    final ttp = _lastAt;
    final ep = peak(_ak, p.mer - 0.05, p.br + 0.01);
    final tep = _lastAt;
    final ip = peak(_ar, p.mer, p.br + 0.012);
    final tip = _lastAt;
    const h = 0.0005;
    final b0 = toWorld(ballAt(p.br - h)), b1 = toWorld(ballAt(p.br + h));
    final ballL = ballAt(p.br);
    final fr = _trunkAt(p.br), s = shoulderTAt(p.br);
    final hu = (armAt(p.br).$1 - s).unit;
    return MotionRelease(
      pos: toWorld(ballL),
      extension: ballL.y,
      handVel: (b1 - b0) / (2 * h),
      armAngle: _measuredArmAngle(p.br),
      abduction: m.acos((-hu.dot(fr.u)).clamp(-1.0, 1.0)) / deg,
      tilt: _tTilt.at(p.br),
      trunkFlex: _tFlex.at(p.br),
      sepFFS: _tYaw.at(p.ffs) - _pYaw.at(p.ffs),
      pelvisPeak: pp, trunkPeak: tp, elbowPeak: ep, irPeak: ip,
      tPelvisPeak: tpp, tTrunkPeak: ttp, tElbowPeak: tep, tIrPeak: tip,
      leadKneeFFS: _kneeAngle(p.ffs), leadKneeBR: _kneeAngle(p.br),
      merDeg: _ar.at(p.mer), strideM: _land.y - _ankleT0.y,
    );
  }

  double _lastAt = 0;

  /// 踏み出した脚の膝の曲がり（0＝まっすぐ）
  double _kneeAngle(double t) {
    final ps = _poseLocal(t);
    final a = ps[J.hipG.index] - ps[J.kneeG.index], b = ps[J.ankleG.index] - ps[J.kneeG.index];
    return 180 - a.angleTo(b);
  }
}
