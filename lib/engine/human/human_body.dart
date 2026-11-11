import 'dart:math' as m;

import '../body_model.dart';
import '../pitch_motion.dart' show J;
import '../vec3.dart';
import 'rot.dart';

/// 【Layer 1】汎用の人体（野球を知らない）：骨の長さは固定、関節は角度で持ち、解剖学的な可動域で必ず止める
///  ・ひじ・ひざは1軸のちょうつがい（反らない・横に曲がらない・ねじれない）
///  ・手のひらを返す動きは前腕のねじれ（回内・回外）、手首は2軸（掌屈・背屈、撓屈・尺屈）だけ
///  ・肩・股関節は3軸の球関節（範囲で止める）。肩を 90° より上げると鎖骨が上がる（肩甲上腕リズム）
///  ・背骨のひねり・前傾・側屈は腰椎 40%・胸椎 60% に分ける
///  座標は本塁基準（x＝一塁側、y＝中堅、z＝上）。左右は T（投げる腕の側）と G（グラブの側）。xs は T/G の体の左右（右＝＋1）
class JointLimits {
  static const elbow = (0.0, 145.0);
  static const knee = (0.0, 140.0);
  static const pronation = (-90.0, 90.0);
  static const wristFlex = (-70.0, 80.0); // −背屈 〜 ＋掌屈
  static const wristDev = (-20.0, 35.0); // −撓屈（親指側）〜 ＋尺屈（小指側）
  static const shoulderElev = (0.0, 180.0);
  static const shoulderPlane = (-45.0, 135.0); // 0＝真横、90＝正面、−＝後ろ（腕を下ろしているときは後ろへ −100° まで）
  static const shoulderRot = (-90.0, 185.0); // ＋＝外旋（投球の最大外旋 MER まで）
  static const hipFlex = (-20.0, 120.0);
  static const hipAbd = (-15.0, 60.0); // 仕様書は 0〜60。足を交差させる一歩（クロスステップ）のため内へ 15° まで
  static const hipRot = (-45.0, 45.0);
  static const ankle = (-50.0, 30.0); // −底屈 〜 ＋背屈
  static const spineTwist = (-55.0, 55.0);
  static const spineLean = (-30.0, 75.0);
  static const spineSide = (-45.0, 45.0);
  static const neckYaw = (-55.0, 55.0); // 胸郭に対する首の回旋（仕様：左右 ±55°）
  static const neckPitch = (-35.0, 35.0); // 前後 ±35°
  static const neckRoll = 20.0; // 側屈 ±20°（頭を水平に保つ補正の上限）
  static const clavicleMax = 25.0;

  /// 腕を下ろしているときは後ろへ振れる（伸展）。上げるほど水平の範囲（−45°）へ
  /// 腕を下ろしているときは体の前を横切れる（おなかの前）。上げると水平屈曲 135° まで
  static double planeMax(double elev) => elev <= 60 ? 170.0 : (elev >= 90 ? 135.0 : 170.0 - (elev - 60) / 30 * 35);
  static double planeMin(double elev) => elev <= 60 ? -100.0 : (elev >= 90 ? -45.0 : -100.0 + (elev - 60) / 30 * 55);
}

/// 姿勢（関節の角度。度。骨盤の位置だけ m）
class HumanPose {
  V3 root = V3.zero; // 骨盤の中心
  double yaw = 0; // 骨盤の向き（ラジアン。Poser の h と同じ）
  double tilt = 0, roll = 0; // 骨盤ごとの前傾・横傾き（背骨の範囲を超えた分。スライディングなど）
  double spTwist = 0, spLean = 0, spSide = 0; // 背骨の合計（ひねり＝反時計回り＋）
  double nkYaw = 0, nkPitch = 0;
  // [T, G]
  final hipFlex = [0.0, 0.0], hipAbd = [0.0, 0.0], hipRot = [0.0, 0.0], knee = [0.0, 0.0], ankle = [0.0, 0.0];
  final shElev = [0.0, 0.0], shPlane = [0.0, 0.0], shRot = [0.0, 0.0], elbow = [0.0, 0.0];
  final pron = [0.0, 0.0], wFlex = [0.0, 0.0], wDev = [0.0, 0.0];

  HumanPose clone() => HumanPose.fromVec(toVec());

  static const n = 3 + 6 + 2 + 2 * 12;

  /// PD 制御用の並び：位置3・骨盤3（yaw は度）・背骨3・首2・各側 12（脚5・腕7）
  List<double> toVec() => [
        root.x, root.y, root.z, yaw / deg, tilt, roll, spTwist, spLean, spSide, nkYaw, nkPitch,
        for (var s = 0; s < 2; s++) ...[hipFlex[s], hipAbd[s], hipRot[s], knee[s], ankle[s], shElev[s], shPlane[s], shRot[s], elbow[s], pron[s], wFlex[s], wDev[s]],
      ];

  HumanPose();
  HumanPose.fromVec(List<double> v) {
    root = V3(v[0], v[1], v[2]);
    yaw = v[3] * deg;
    tilt = v[4];
    roll = v[5];
    spTwist = v[6];
    spLean = v[7];
    spSide = v[8];
    nkYaw = v[9];
    nkPitch = v[10];
    for (var s = 0; s < 2; s++) {
      final o = 11 + s * 12;
      hipFlex[s] = v[o];
      hipAbd[s] = v[o + 1];
      hipRot[s] = v[o + 2];
      knee[s] = v[o + 3];
      ankle[s] = v[o + 4];
      shElev[s] = v[o + 5];
      shPlane[s] = v[o + 6];
      shRot[s] = v[o + 7];
      elbow[s] = v[o + 8];
      pron[s] = v[o + 9];
      wFlex[s] = v[o + 10];
      wDev[s] = v[o + 11];
    }
  }
}

/// 順運動学の結果：関節の位置（J の並び）と、15本の骨の向き（原点・骨の向き y・横の軸 x）
class HumanOut {
  final List<V3> p;
  final List<V3> org, y, x;
  final List<M3> chest; // [胸郭]
  final M3 head; // 頭（x＝右、y＝顔の正面、z＝上）
  final List<M3> forearm, hand; // [T, G]（前腕はねじる前）
  HumanOut(this.p, this.org, this.y, this.x, this.chest, this.forearm, this.hand, this.head);
}

class HumanBody {
  final BodyModel b;
  final bool lefty;
  HumanBody(this.b, {this.lefty = false});

  double get sT => lefty ? -1.0 : 1.0;
  double xs(int s) => s == 0 ? sT : -sT;

  static const _fl = 0.72; // 足首〜つま先（足の長さに対して）
  V3 get _footRest => V3(0, b.footLen * _fl, -(b.ankleH - 0.02));

  M3 _pelvis(HumanPose q) => M3.heading(q.yaw).mul(M3.rx(-q.tilt)).mul(M3.ry(q.roll));
  (M3, M3) _spine(M3 pel, HumanPose q) {
    final lo = pel.mul(M3.rz(0.4 * q.spTwist)).mul(M3.rx(-0.4 * q.spLean)).mul(M3.ry(0.4 * q.spSide));
    final up = lo.mul(M3.rz(0.6 * q.spTwist)).mul(M3.rx(-0.6 * q.spLean)).mul(M3.ry(0.6 * q.spSide));
    return (lo, up);
  }

  double _clav(double elev) => JointLimits.clavicleMax * clampD((elev - 90) / 90, 0, 1);
  V3 _shoulder(V3 neck, M3 ch, int s, double elev) {
    final c = _clav(elev) * deg, half = b.shoulderW / 2;
    return neck + ch * V3(xs(s) * half * m.cos(c), 0, -0.06 + half * m.sin(c) * 0.6);
  }

  M3 _thigh(M3 pel, HumanPose q, int s) => pel.mul(M3.rx(q.hipFlex[s])).mul(M3.ry(-xs(s) * q.hipAbd[s])).mul(M3.rz(xs(s) * q.hipRot[s]));
  /// 肩の回旋の基準：腕を下ろしているほど、前後に振っても回旋 0 でひじは前へ曲がる（面の回りを打ち消す）
  static double _tw(double elev) => clampD(m.cos(elev * deg), 0, 1);
  M3 _upperArm(M3 ch, HumanPose q, int s) =>
      ch.mul(M3.rz(xs(s) * q.shPlane[s])).mul(M3.ry(-xs(s) * q.shElev[s])).mul(M3.rz(-xs(s) * (q.shRot[s] + q.shPlane[s] * _tw(q.shElev[s]))));
  M3 _handOf(M3 fa, HumanPose q, int s) => fa.mul(M3.rz(xs(s) * q.pron[s])).mul(M3.ry(xs(s) * q.wFlex[s])).mul(M3.rx(-q.wDev[s]));

  /// 順運動学
  HumanOut fk(HumanPose q) {
    final p = List<V3>.filled(J.values.length, V3.zero);
    final org = List<V3>.filled(15, V3.zero), yy = List<V3>.filled(15, V3.ez), xx = List<V3>.filled(15, V3.ex);
    final pel = _pelvis(q);
    final pc = q.root;
    p[J.pelvis.index] = pc;
    final (lo, ch) = _spine(pel, q);
    final mid = pc + lo * V3(0, 0, b.trunk * 0.4);
    final neck = mid + ch * V3(0, 0, b.trunk * 0.6);
    p[J.neck.index] = neck;
    final hd = levelHead(ch.mul(M3.rz(q.nkYaw)).mul(M3.rx(q.nkPitch)));
    p[J.head.index] = neck + hd * V3(0, 0, b.neck + b.headR);
    org[0] = pc;
    yy[0] = pel * V3.ez;
    xx[0] = pel * V3(-sT, 0, 0);
    org[1] = pc;
    yy[1] = neck - pc;
    xx[1] = ch * V3(-sT, 0, 0);
    org[2] = neck;
    yy[2] = hd * V3.ez;
    xx[2] = hd * V3(-sT, 0, 0);
    final fas = <M3>[], hands = <M3>[];
    for (var s = 0; s < 2; s++) {
      final t = s == 0;
      // 脚
      final hip = pc + pel * V3(xs(s) * b.hipW / 2, 0, 0);
      final th = _thigh(pel, q, s);
      final kn = hip + th * V3(0, 0, -b.thigh);
      final sh = th.mul(M3.rx(-q.knee[s]));
      final an = kn + sh * V3(0, 0, -b.shank);
      final ft = sh.mul(M3.rx(q.ankle[s]));
      final toe = an + ft * _footRest;
      p[(t ? J.hipT : J.hipG).index] = hip;
      p[(t ? J.kneeT : J.kneeG).index] = kn;
      p[(t ? J.ankleT : J.ankleG).index] = an;
      p[(t ? J.toeT : J.toeG).index] = toe;
      final bi = t ? 9 : 12;
      org[bi] = hip;
      yy[bi] = kn - hip;
      xx[bi] = th * V3.ex;
      org[bi + 1] = kn;
      yy[bi + 1] = an - kn;
      xx[bi + 1] = sh * V3.ex;
      org[bi + 2] = an;
      yy[bi + 2] = toe - an;
      xx[bi + 2] = ft * V3.ex;
      // 腕
      final shp = _shoulder(neck, ch, s, q.shElev[s]);
      final ua = _upperArm(ch, q, s);
      final el = shp + ua * V3(0, 0, -b.upperArm);
      final fa = ua.mul(M3.rx(q.elbow[s]));
      final wr = el + fa * V3(0, 0, -b.forearm);
      final fp = fa.mul(M3.rz(xs(s) * q.pron[s]));
      final hm = _handOf(fa, q, s);
      p[(t ? J.shoulderT : J.shoulderG).index] = shp;
      p[(t ? J.elbowT : J.elbowG).index] = el;
      p[(t ? J.wristT : J.wristG).index] = wr;
      p[(t ? J.ball : J.glove).index] = wr + hm * V3(0, 0, -b.hand * 0.5);
      final ai = t ? 3 : 6;
      org[ai] = shp;
      yy[ai] = el - shp;
      xx[ai] = ua * V3.ex;
      org[ai + 1] = el;
      yy[ai + 1] = wr - el;
      xx[ai + 1] = fp * V3.ex;
      org[ai + 2] = wr;
      yy[ai + 2] = hm * const V3(0, 0, -1);
      xx[ai + 2] = hm * V3.ex;
      fas.add(fa);
      hands.add(hm);
    }
    return HumanOut(p, org, yy, xx, [ch], fas, hands, hd);
  }

  /// 頭の水平を保つ（前庭動眼反射）：体が傾いても、両目を結ぶ線を世界の水平へ 85% 戻す。
  ///  顔の正面の軸のまわりに回すだけ（見る向きは変えない）。胸郭に対しての側屈は ±20° まで
  static M3 levelHead(M3 hd) {
    final f = hd * V3.ey;
    final lv = f.cross(V3.ez);
    if (lv.length < 0.2) return hd; // 真上・真下を向いているときはそのまま
    final want = lv.unit;
    double rollOf(M3 h) {
      final rr = h * V3.ex;
      return m.atan2(rr.cross(want).dot(f), rr.dot(want));
    }

    final ang = rollOf(hd);
    final a = clampD(0.85 * ang.abs() / deg, 0, JointLimits.neckRoll);
    if (a < 0.05) return hd;
    final c1 = hd.mul(M3.ry(a)), c2 = hd.mul(M3.ry(-a));
    return rollOf(c1).abs() <= rollOf(c2).abs() ? c1 : c2;
  }

  /// 2本の骨の解析的 IK（ポールベクトル付き）：根元 a → 目標 t。上の骨の向き・中間の曲げ角（度）・ポールの向き
  static (V3, double, V3) solve2(V3 a, V3 t, double l1, double l2, V3 pole) {
    var d = t - a;
    var len = d.length;
    final dh = len < 1e-6 ? const V3(0, 0, -1) : d / len;
    len = clampD(len, (l1 - l2).abs() + 1e-3, (l1 + l2) * 0.9995);
    final cosA = clampD((l1 * l1 + len * len - l2 * l2) / (2 * l1 * len), -1, 1);
    final aa = m.acos(cosA);
    var pp = pole.perpTo(dh);
    if (pp.length < 1e-5) pp = V3.ez.perpTo(dh).length > 1e-3 ? V3.ez.perpTo(dh) : V3.ey.perpTo(dh);
    pp = pp.unit;
    final up = dh * m.cos(aa) + pp * m.sin(aa);
    final cosB = clampD((l1 * l1 + l2 * l2 - len * len) / (2 * l1 * l2), -1, 1);
    return (up, 180 - m.acos(cosB) / deg, pp);
  }

  /// 関節の目標の位置（Layer 2 の Poser が作る）→ 可動域内の角度
  ///  ひざ・ひじの向き（ポール）は、目標のひざ・ひじの位置。look：見る点
  ///  hint：前のコマの姿勢（あれば、そこから探し始める。毎コマ別の答えに飛ぶガタつきを防ぐ）
  HumanPose fit(List<V3> p, {V3? look, HumanPose? hint}) {
    final q = HumanPose();
    q.root = p[J.pelvis.index];
    final hr = (p[J.hipT.index] - p[J.hipG.index]) * sT;
    final hh = V3(hr.x, hr.y, 0);
    q.yaw = hh.length < 1e-6 ? 0 : m.atan2(-hh.y, hh.x);
    // 背骨：胴の傾き（前・横）。範囲を超えた分は骨盤ごと傾ける
    final base = M3.heading(q.yaw);
    final u = (base.t * (p[J.neck.index] - q.root)).unit;
    final lean = m.atan2(u.y, u.z) / deg, side = m.asin(clampD(u.x, -1, 1)) / deg;
    q.spLean = clampD(lean, JointLimits.spineLean.$1, JointLimits.spineLean.$2);
    q.tilt = lean - q.spLean;
    q.spSide = clampD(side, JointLimits.spineSide.$1, JointLimits.spineSide.$2);
    q.roll = clampD(side - q.spSide, -30, 30);
    final noTw = _pelvis(q).mul(M3.rx(-q.spLean)).mul(M3.ry(q.spSide));
    final sr = noTw.t * ((p[J.shoulderT.index] - p[J.shoulderG.index]) * sT);
    q.spTwist = clampD(m.atan2(sr.y, sr.x) / deg, JointLimits.spineTwist.$1, JointLimits.spineTwist.$2);
    _refineSpine(q, p, hint);
    final pel = _pelvis(q);
    final (lo, ch) = _spine(pel, q);
    final neck = q.root + lo * V3(0, 0, b.trunk * 0.4) + ch * V3(0, 0, b.trunk * 0.6);
    // 首：見る点へ（顔の向き）。目も動くので首は 6 割
    if (look != null) {
      final l = ch.t * (look - neck);
      final hz = m.sqrt(l.x * l.x + l.y * l.y);
      q.nkYaw = clampD(m.atan2(-l.x, l.y) / deg * 0.9, JointLimits.neckYaw.$1, JointLimits.neckYaw.$2);
      // 体が前に傾いても、目線は見る点へ（首で 85%・残りは目の動き）
      q.nkPitch = clampD(m.atan2(l.z, hz) / deg * 0.85, JointLimits.neckPitch.$1, JointLimits.neckPitch.$2);
    }
    for (var s = 0; s < 2; s++) {
      final t = s == 0;
      _legIK(q, pel, s, p[(t ? J.ankleT : J.ankleG).index], p[(t ? J.kneeT : J.kneeG).index], p[(t ? J.toeT : J.toeG).index]);
      final wr = p[(t ? J.wristT : J.wristG).index], el = p[(t ? J.elbowT : J.elbowG).index];
      // 肩の位置は鎖骨（腕の上げ具合）で変わるので2回
      for (var k = 0; k < 2; k++) {
        final shp = _shoulder(neck, ch, s, q.shElev[s]);
        _armIK(q, ch, s, shp, wr, el - (shp + wr) * 0.5);
      }
      // 手：前腕の向きのまま（ねじり・手首は 0）。手の向きの指定は orientHand
    }
    return q;
  }

  /// 背骨の3つの角度（腰椎4割・胸椎6割に分けた合計）を、首と両肩の位置が目標に合うように探し直す（可動域の中で）
  ///  近似のままだと肩が数 cm ずれ、腕の長さの計算が狂ってひじの曲がりが変わる
  void _refineSpine(HumanPose q, List<V3> p, [HumanPose? hint]) {
    final nT = p[J.neck.index], sTt = p[J.shoulderT.index], sGt = p[J.shoulderG.index];
    double cost() {
      final pel = _pelvis(q);
      final (lo, ch) = _spine(pel, q);
      final neck = q.root + lo * V3(0, 0, b.trunk * 0.4) + ch * V3(0, 0, b.trunk * 0.6);
      final shT = _shoulder(neck, ch, 0, 0), shG = _shoulder(neck, ch, 1, 0);
      return (neck - nT).length2 + 0.5 * ((shT - sTt).length2 + (shG - sGt).length2);
    }

    var best = cost();
    if (hint != null) {
      // 前のコマの背骨から始めたほうが合うなら、そちらから
      final save = (q.spTwist, q.spLean, q.spSide);
      q.spTwist = hint.spTwist;
      q.spLean = hint.spLean;
      q.spSide = hint.spSide;
      final c = cost();
      if (c <= best + 1e-4) {
        best = c;
      } else {
        q.spTwist = save.$1;
        q.spLean = save.$2;
        q.spSide = save.$3;
      }
    }
    const lims = [JointLimits.spineTwist, JointLimits.spineLean, JointLimits.spineSide];
    double get(int i) => i == 0 ? q.spTwist : (i == 1 ? q.spLean : q.spSide);
    void set(int i, double v) {
      if (i == 0) {
        q.spTwist = v;
      } else if (i == 1) {
        q.spLean = v;
      } else {
        q.spSide = v;
      }
    }

    for (var step = 8.0; step >= 0.25; step /= 2) {
      var moved = true, guard = 0;
      while (moved && guard++ < 10) {
        moved = false;
        for (var i = 0; i < 3; i++) {
          for (final d in [step, -step]) {
            final old = get(i);
            set(i, clampD(old + d, lims[i].$1, lims[i].$2));
            final c = cost();
            if (c < best - 1e-10) {
              best = c;
              moved = true;
            } else {
              set(i, old);
            }
          }
        }
      }
    }
  }

  void _legIK(HumanPose q, M3 pel, int s, V3 ankle, V3 kneePole, V3 toe) {
    final hip = q.root + pel * V3(xs(s) * b.hipW / 2, 0, 0);
    // ポール：ひざの目標（なければつま先の向き）
    var pole = kneePole - (hip + ankle) * 0.5;
    final td = V3(toe.x - ankle.x, toe.y - ankle.y, 0);
    if (pole.length < 1e-4) pole = td.length > 1e-4 ? td : pel * V3.ey;
    final (up, flex, pp) = solve2(hip, ankle, b.thigh, b.shank, pole);
    final z = -up;
    final y = pp.perpTo(up).unit;
    final x = y.cross(z);
    final loc = pel.t.mul(M3(x, y, z));
    final beta = m.asin(clampD(loc.e(0, 2), -1, 1)) / deg;
    final f = m.atan2(-loc.e(1, 2), loc.e(2, 2)) / deg;
    final g = m.atan2(-loc.e(0, 1), loc.e(0, 0)) / deg;
    q.hipFlex[s] = clampD(f, JointLimits.hipFlex.$1, JointLimits.hipFlex.$2);
    q.hipAbd[s] = clampD(-xs(s) * beta, JointLimits.hipAbd.$1, JointLimits.hipAbd.$2);
    q.hipRot[s] = clampD(xs(s) * g, JointLimits.hipRot.$1, JointLimits.hipRot.$2);
    q.knee[s] = clampD(flex, JointLimits.knee.$1, JointLimits.knee.$2);
    // 足首：つま先の目標へ
    final th = _thigh(pel, q, s);
    final sh = th.mul(M3.rx(-q.knee[s]));
    final an = hip + th * V3(0, 0, -b.thigh) + sh * V3(0, 0, -b.shank);
    final tl = sh.t * (toe - an);
    final fr = _footRest;
    final a = (m.atan2(tl.z, tl.y) - m.atan2(fr.z, fr.y)) / deg;
    q.ankle[s] = clampD(wrap180(a), JointLimits.ankle.$1, JointLimits.ankle.$2);
  }

  void _armIK(HumanPose q, M3 ch, int s, V3 sh, V3 wrist, V3 pole) {
    final (up, flex, pp) = solve2(sh, wrist, b.upperArm, b.forearm, pole);
    final z = -up;
    final y = (-pp).perpTo(up).unit; // 前腕はポールと反対へ曲がる（ひじがポールの側）
    final x = y.cross(z);
    _setShoulder(q, ch.t.mul(M3(x, y, z)), s);
    q.elbow[s] = clampD(flex, JointLimits.elbow.$1, JointLimits.elbow.$2);
  }

  /// 胸郭から見た上腕の回転 → 肩の3つの角度（Rz(面)·Ry(挙上)·Rz(回旋)）を可動域で止める
  void _setShoulder(HumanPose q, M3 loc, int s) {
    final x = xs(s);
    final elev = m.acos(clampD(loc.e(2, 2), -1, 1)) / deg;
    final sb = m.sin(-x * elev * deg);
    double a, c;
    if (sb.abs() < 1e-4) {
      a = 0;
      c = elev < 90 ? m.atan2(loc.e(1, 0), loc.e(0, 0)) / deg : m.atan2(loc.e(1, 0), loc.e(1, 1)) / deg;
    } else {
      a = m.atan2(loc.e(1, 2) / sb, loc.e(0, 2) / sb) / deg;
      c = m.atan2(loc.e(2, 1) / sb, -loc.e(2, 0) / sb) / deg;
    }
    var plane = wrap180(x * a);
    final raw = -x * c; // 面の回りを含んだねじれ
    final e = clampD(elev, JointLimits.shoulderElev.$1, JointLimits.shoulderElev.$2);
    // 範囲の外なら、円周上で近いほうの限界へ（体の内側へ大きく回した腕が ±180° をまたいで「後ろ」の限界に止まらないように）
    final pMin = JointLimits.planeMin(e), pMax = JointLimits.planeMax(e);
    if (plane < pMin || plane > pMax) {
      final dMin = (wrap180(pMin - plane)).abs(), dMax = (wrap180(plane - pMax)).abs();
      plane = dMin < dMax ? pMin : pMax;
    }
    var rot = raw - plane * _tw(e); // 面を止めても、ねじれ（ひじの向き）はそのまま
    rot = wrap180(rot);
    if (rot < JointLimits.shoulderRot.$1 && rot + 360 <= JointLimits.shoulderRot.$2) rot += 360;
    q.shElev[s] = e;
    q.shPlane[s] = plane;
    q.shRot[s] = clampD(rot, JointLimits.shoulderRot.$1, JointLimits.shoulderRot.$2);
  }

  /// 片腕だけ手首の目標へ届かせ直す（バットの上の手など）。pole：ひじを向ける点
  void reachArm(HumanPose q, HumanOut out, int s, V3 wrist, V3 pole) {
    final ch = out.chest[0];
    final neck = out.p[J.neck.index];
    for (var k = 0; k < 2; k++) {
      final shp = _shoulder(neck, ch, s, q.shElev[s]);
      _armIK(q, ch, s, shp, wrist, pole - (shp + wrist) * 0.5);
    }
  }

  /// 手の向きの指定（前腕のねじり＋手首の2軸を可動域の中で）：palm＝手のひらの向き、finger＝指の向き、aim＝親指の側（握りの穴の向き）
  void orientHand(HumanPose q, HumanOut out, int s, {V3? palm, V3? finger, V3? aim, double wPalm = 1, double wFinger = 0.6, double wAim = 1, HumanPose? hint}) {
    if (palm == null && finger == null && aim == null) return;
    final fa = out.forearm[s];
    final x = xs(s);
    final pl = palm == null ? null : fa.t * palm.unit, fl = finger == null ? null : fa.t * finger.unit, al = aim == null ? null : fa.t * aim.unit;
    double cost(double pr, double wf, double dv) {
      final h = M3.rz(x * pr).mul(M3.ry(x * wf)).mul(M3.rx(-dv));
      var c = 0.0;
      if (pl != null) c += wPalm * (h * V3(-x, 0, 0) - pl).length2;
      if (fl != null) c += wFinger * (h * const V3(0, 0, -1) - fl).length2;
      if (al != null) c += wAim * (h * V3.ey - al).length2;
      return c;
    }

    var v = [0.0, 0.0, 0.0];
    const lim = [JointLimits.pronation, JointLimits.wristFlex, JointLimits.wristDev];
    // 回内・回外の初期値：手のひらの向きを前腕のまわりで合わせる
    var best = cost(0, 0, 0);
    for (var pr = -90.0; pr <= 90; pr += 30) {
      final c = cost(pr, 0, 0);
      if (c < best) {
        best = c;
        v = [pr, 0, 0];
      }
    }
    // 前のコマの手首から始めて、ほぼ同じくらい合うならそちら（候補の間を行き来しない）
    if (hint != null) {
      final hv = [hint.pron[s], hint.wFlex[s], hint.wDev[s]];
      final hc = cost(hv[0], hv[1], hv[2]);
      if (hc <= best + 0.05) {
        best = hc;
        v = hv;
      }
    }
    for (var step = 16.0; step >= 0.5; step /= 2) {
      var moved = true;
      var guard = 0;
      while (moved && guard++ < 12) {
        moved = false;
        for (var i = 0; i < 3; i++) {
          for (final d in [step, -step]) {
            final t = List<double>.of(v);
            t[i] = clampD(t[i] + d, lim[i].$1, lim[i].$2);
            final c = cost(t[0], t[1], t[2]);
            if (c < best - 1e-9) {
              best = c;
              v = t;
              moved = true;
            }
          }
        }
      }
    }
    q.pron[s] = v[0];
    q.wFlex[s] = v[1];
    q.wDev[s] = v[2];
  }
}

/// 関節の PD 制御（臨界減衰：θ'' = kp(θ目標 − θ) − 2√kp θ'）。動きの始まりと終わりに重さと惰性が出る
///  ω（＝√kp、1/秒）は部位ごと。骨盤の位置は予定どおり（PD なし）
class HumanPd {
  List<double>? _x, _v;
  /// 部位ごとの ω。index は HumanPose.toVec の並び
  static List<double> omega({double arms = 26, double armT = 26, double legs = 40, double spine = 22, double neck = 14, double pelvis = 24}) => [
        0, 0, 0, pelvis, pelvis, pelvis, spine, spine, spine, neck, neck,
        for (var s = 0; s < 2; s++) ...[legs, legs, legs, legs, legs, s == 0 ? armT : arms, s == 0 ? armT : arms, s == 0 ? armT : arms, s == 0 ? armT : arms, arms, arms, arms],
      ];

  void reset() {
    _x = null;
    _v = null;
  }

  /// 1コマ進める。dt が負・大きすぎる（巻き戻し・飛ばし）ときは目標へ合わせる
  HumanPose step(HumanPose target, double dt, List<double> w, {bool snapLegs = false}) {
    final tv = target.toVec();
    if (_x == null || dt <= 0 || dt > 0.25) {
      _x = List<double>.of(tv);
      _v = List<double>.filled(tv.length, 0);
      return target;
    }
    final x = _x!, v = _v!;
    // 角度の目標は近い回り方へ（yaw・ねじれ）
    for (var i = 3; i < tv.length; i++) {
      tv[i] = x[i] + wrap180(tv[i] - x[i]);
    }
    x[0] = tv[0];
    x[1] = tv[1];
    x[2] = tv[2];
    final wMax = w.reduce(m.max);
    final n = m.max(1, (dt * wMax / 0.35).ceil());
    final h = dt / n;
    for (var k = 0; k < n; k++) {
      for (var i = 3; i < tv.length; i++) {
        final om = w[i];
        if (om <= 0) {
          x[i] = tv[i];
          v[i] = 0;
          continue;
        }
        final a = om * om * (tv[i] - x[i]) - 2 * om * v[i];
        v[i] += a * h;
        x[i] += v[i] * h;
      }
    }
    if (snapLegs) {
      for (var s = 0; s < 2; s++) {
        for (var i = 0; i < 5; i++) {
          x[11 + s * 12 + i] = tv[11 + s * 12 + i];
          v[11 + s * 12 + i] = 0;
        }
      }
    }
    return HumanPose.fromVec(x);
  }
}
