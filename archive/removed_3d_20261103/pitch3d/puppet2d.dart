import 'dart:typed_data';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../../engine/body_model.dart';
import '../../engine/human/human_body.dart';
import '../../engine/pitch_motion.dart' show J;
import '../../models/uniform.dart';
import '../../engine/vec3.dart';
import 'face_art.dart';
import 'toon_rig.dart';

/// 選手の体（3D の形を持つ ToonRig と、2D の切り絵の PuppetRig の共通の使い方）
abstract class PlayerRig {
  Node get root;
  BodyModel get body;
  HumanBody get human;
  HandPose get handT;
  set handT(HandPose v);
  HandPose get handG;
  set handG(HandPose v);
  V3? aimT, aimG, palmT, palmG, fingerT, fingerG;
  void holdBall(PitchGrip? g);
  V3 gripPoint(bool t);
  V3 get ballPoint;
  HumanPose prepare(List<V3> p, {V3? look});
  void orientHands(HumanPose q);
  void poseOut(HumanOut o);
  void pose(List<V3> p, {V3? look});
}

/// 2.5D の選手（切り絵式の 2D 人形）：関節は Layer 1 で計算し、描くのは画面の上（PuppetPainter）
///  体の長さ・太さは体格（BodyModel）から。頭を大きくしたちびキャラの比率（約4頭身）
class PuppetRig implements PlayerRig {
  @override
  final Node root = Node(); // 3D の場面には何も置かない
  @override
  late final BodyModel body;
  @override
  late final HumanBody human;
  final FaceLook face;
  final Uniform uni;
  final bool lefty, glove, helmet;
  late final double headR;
  @override
  HandPose handT = HandPose.relaxed, handG = HandPose.relaxed;
  @override
  V3? aimT, aimG, palmT, palmG, fingerT, fingerG;
  PitchGrip? grip; // 握っているボールの握り（null なら持っていない）
  String number = ''; // 背番号
  String teamText = ''; // 胸のチーム名
  final Map<String, TextPainter> textCache = {}; // 背番号・胸の字（組んだ形を使い回す）
  final Map<int, ui.Image> faceImgs = {}; // 顔の画像（顔の種類×大きさ。FaceArt で一度だけ描く）
  double effort = 0; // 力を入れている度合い（投げる・振る：歯を食いしばる）
  double blink = 0; // まばたき（1＝閉じる）
  // 用具の見た目（選手ごと：Player.bat・glove から）
  int batColor = 0xFFE2B979, batTipColor = 0xFFE2B979, batLogo = 0xFF1D4ED8;
  int? gloveColor, laceColor;
  String web = 'クロス';
  int gloveLogo = 0xFF1D4ED8;
  final Map<int, bool> limbFront = {}; // 手足が胴の前に描かれているか（あそびのため覚えておく）
  HumanOut? out; // いまの姿勢（実寸の骨格。物理・IK・ボールとバットの位置はこれ）
  HumanOut? drawOut; // 描く姿勢（デフォルメ：頭を肩の上に乗せ、肩幅・腕の見た目を広げる）
  HumanOut? get shownOut => drawOut ?? out;
  /// 描くときの頭身（頭の半径＝身長÷頭身÷2）。動きの計算は実寸（約7.3頭身）のまま
  static const heads = 4.0;
  /// 体格の誇張：bulk（0〜1。BMI・パワーが高い）で胸と腹を最大 1.35 倍、slim（0〜1。俊足・細身）で腰を 0.85 倍まで
  final double bulk, slim;
  double get chestF => 1 + 0.35 * bulk;
  double get waistF => 1 + 0.35 * bulk;
  double get hipF => 1 - 0.15 * slim;
  PuppetRig(this.face, this.uni, {required BodyModel real, this.lefty = false, this.glove = true, this.helmet = false, this.bulk = 0, this.slim = 0}) {
    headR = real.height / heads / 2;
    body = real; // 物理・IK の骨格は実寸（Drillis & Contini の比率、体格どおり）
    human = HumanBody(body, lefty: lefty);
  }

  /// 選手の体格・能力から体格の誇張の度合い（bulk, slim）
  static (double, double) buildOf({required int heightCm, required int weightKg, required int power, required int run}) {
    final bmi = weightKg / math.pow(heightCm / 100, 2);
    final bulk = (0.6 * (bmi - 23) / 6 + 0.4 * (power - 55) / 40).clamp(0.0, 1.0);
    final slim = (((run - 60) / 30).clamp(0.0, 1.0) * ((25.5 - bmi) / 4).clamp(0.0, 1.0)).toDouble();
    return (bulk.toDouble(), slim);
  }

  /// 実寸の姿勢 → 描く姿勢（約 4 頭身のデフォルメ）
  ///  ・頭：首の付け根（両肩の中央）の上に乗せる。前後左右のずれは実寸の 35% まで、高さは頭の半径の 0.82 倍（深い前傾でも頭が胸の前へ飛び出さない）
  ///  ・肩幅 +18%、上腕・前腕の見た目の長さ +12%。手首は実寸の位置のまま（バット・ボールと合う）、2本の骨の IK でひじを決め直す
  HumanOut _chibi(HumanOut o) {
    final p = List<V3>.of(o.p);
    final nb = p[J.neck.index], hr = p[J.head.index];
    final d = hr - nb;
    p[J.head.index] = nb + V3(d.x * 0.35, d.y * 0.35, 0.82 * headR);
    final sc = (p[J.shoulderT.index] + p[J.shoulderG.index]) * 0.5;
    final l1 = body.upperArm * 1.12, l2 = body.forearm * 1.12;
    for (final (sh, el, wr) in const [(J.shoulderT, J.elbowT, J.wristT), (J.shoulderG, J.elbowG, J.wristG)]) {
      final s1 = sc + (p[sh.index] - sc) * 1.18;
      final w = p[wr.index], e = p[el.index];
      final (up, _, _) = HumanBody.solve2(s1, w, l1, l2, e - (s1 + w) * 0.5);
      p[sh.index] = s1;
      p[el.index] = s1 + up * l1;
    }
    return HumanOut(p, o.org, o.y, o.x, o.chest, o.forearm, o.hand, o.head);
  }

  @override
  void holdBall(PitchGrip? g) => grip = g;

  /// 手の座標：手首・指の向き・手のひらの向き
  (V3, V3, V3) _hand(int s) {
    final o = out!;
    final hm = o.hand[s];
    final wr = o.p[(s == 0 ? J.wristT : J.wristG).index];
    return (wr, hm * const V3(0, 0, -1), hm * V3(-human.xs(s), 0, 0));
  }

  @override
  V3 gripPoint(bool t) {
    if (out == null) return V3.zero;
    final (wr, d, palm) = _hand(t ? 0 : 1);
    return wr + d * (body.hand * 0.42) + palm * (body.hand * 0.12);
  }

  @override
  V3 get ballPoint {
    if (out == null) return V3.zero;
    final (wr, d, palm) = _hand(0);
    final depth = grip?.depth ?? 0.3;
    return wr + d * (body.hand * (0.62 - 0.14 * depth)) + palm * (0.0366 + body.hand * 0.06);
  }

  HumanPose? _lastQ; // 前のコマの姿勢（探し始めの手がかり）
  @override
  HumanPose prepare(List<V3> p, {V3? look}) {
    final q = human.fit(p, look: look, hint: _lastQ);
    orientHands(q);
    _lastQ = q;
    return q;
  }

  @override
  void orientHands(HumanPose q) {
    if (palmT == null && palmG == null && aimT == null && aimG == null) return;
    final o = human.fk(q);
    for (var hi = 0; hi < 2; hi++) {
      final palm = hi == 0 ? palmT : palmG, aim = hi == 0 ? aimT : aimG;
      final fa = o.forearm[hi] * const V3(0, 0, -1);
      if (palm != null && aim != null) {
        human.orientHand(q, o, hi, palm: palm, aim: aim, wPalm: 0.6, wAim: 1, hint: _lastQ);
      } else if (palm != null) {
        human.orientHand(q, o, hi, palm: palm, finger: (hi == 0 ? fingerT : fingerG) ?? fa, hint: _lastQ);
      } else if (aim != null) {
        final fp = fa.perpTo(aim.unit);
        human.orientHand(q, o, hi, aim: aim, finger: fp.length > 0.2 ? fp.unit : null, wFinger: 0.4, hint: _lastQ);
      }
    }
  }

  @override
  void poseOut(HumanOut o) {
    out = o;
    drawOut = _chibi(o);
  }

  @override
  void pose(List<V3> p, {V3? look}) => poseOut(human.fk(prepare(p, look: look)));
}

/// 1人ぶんの描く材料（毎コマ、画面の側で作る）
class PuppetItem {
  final PuppetRig rig;
  final V3? batKnob, batTip; // 持っているバット
  final bool catcherGear;
  PuppetItem(this.rig, {this.batKnob, this.batTip, this.catcherGear = false});
}

/// 2D の切り絵の人形を、3D の場面の上に描く
///  関節を画面へ投影 → 奥行きの順（遠い手足 → 胴 → 頭 → 近い手足）に、輪郭線つきの図形で重ねる
class PuppetPainter extends CustomPainter {
  final List<PuppetItem> Function() items;
  final Camera Function() camera;
  final V3? Function() ball;
  /// ボールの回転（回転軸・回した角度・フォーシームの向きか）。null なら回さない
  final ({V3 axis, double angle, bool four})? Function()? ballSpin;
  final void Function(Size)? onSize;
  /// 人形より先に描くもの（ビジョンの画面など）。project：世界の点 → 画面の点
  final void Function(Canvas canvas, Offset? Function(V3) project, V3 camPos)? background;
  PuppetPainter({required this.items, required this.camera, required this.ball, this.ballSpin, required Listenable repaint, this.onSize, this.background}) : super(repaint: repaint);

  static const _ink = Color(0xFF1B1B22); // 輪郭線

  late Camera _cam;
  late Size _size;
  late vm.Vector3 _camPos;

  /// 世界の点 → 画面の点（カメラの後ろは null）。カメラの行列は1コマに1回だけ作る（worldToScreen は呼ぶたびに作り直すので重い）
  Offset? _p(V3 w) {
    final m = _vt;
    final x = -w.x, y = w.z, z = w.y; // sv(w)
    final cw = m[3] * x + m[7] * y + m[11] * z + m[15];
    if (cw <= 0) return null;
    final cx = m[0] * x + m[4] * y + m[8] * z + m[12], cy = m[1] * x + m[5] * y + m[9] * z + m[13];
    return Offset((cx / cw + 1) / 2 * _size.width, (1 - cy / cw) / 2 * _size.height);
  }

  late List<double> _vt; // 射影×視点の行列（列優先の 16 個）
  double _dpr = 2.0; // 画面の画素の倍率（顔の画像の大きさを決める）
  int _bakes = 0; // このコマで新しく描いた顔の画像の数（一度に描きすぎて止まらないように）

  /// 選手の顔の画像（variant：0 ふつう 1 まばたき 2 力み）。画面で写る大きさに近い 64・128・256 px のどれかを、選手ごとに一度だけ描く。
  ///  まだ描いていなくて、このコマの上限（3枚）を超えたら、ほかの大きさ・ふつうの顔で代わりにする
  ui.Image? _faceImage(PuppetRig rig, int variant, double sizeLogical) {
    final phys = sizeLogical * _dpr;
    final bucket = phys <= 80 ? 64 : (phys <= 160 ? 128 : 256);
    final key = variant * 1000 + bucket;
    final got = rig.faceImgs[key];
    if (got != null) return got;
    if (_bakes < 3) {
      _bakes++;
      return rig.faceImgs[key] = FaceArt.bake(rig.face, variant, bucket);
    }
    for (final k2 in [variant * 1000 + 128, variant * 1000 + 256, variant * 1000 + 64, 128, 256, 64]) {
      final g = rig.faceImgs[k2];
      if (g != null) return g;
    }
    return null;
  }
  double _dist(V3 w) {
    final dx = -w.x - _camPos.x, dy = w.z - _camPos.y, dz = w.y - _camPos.z;
    return math.sqrt(dx * dx + dy * dy + dz * dz);
  }

  /// その点での 1m の画面上の長さ（ピクセル）
  double _ppm(V3 w) {
    final a = _p(w), b = _p(w + _rightW * 1.0);
    if (a == null || b == null) return 0;
    return (b - a).distance;
  }

  late V3 _rightW; // カメラの右（世界の座標）

  @override
  void paint(Canvas canvas, Size size) {
    _bakes = 0;
    _dpr = ui.PlatformDispatcher.instance.implicitView?.devicePixelRatio ?? 2.0;
    _cam = camera();
    _size = size;
    _vt = _cam.getViewTransform(size).storage;
    onSize?.call(size);
    _camPos = _cam.position;
    final r = _cam.right;
    _rightW = V3(-r.x, r.z, r.y).unit;
    final sw = Stopwatch()..start();
    background?.call(canvas, _p, V3(-_camPos.x, _camPos.z, _camPos.y));
    perfBg += sw.elapsedMicroseconds;
    sw.reset();
    final list = [for (final it in items()) if (it.rig.out != null) it];
    // 影（先に全員ぶん）
    for (final it in list) {
      final pel = it.rig.out!.p[J.pelvis.index];
      _shadow(canvas, V3(pel.x, pel.y, 0.01), 0.32);
    }
    final b = ball();
    if (b != null && b.z > 0.05) _shadow(canvas, V3(b.x, b.y, 0.01), 0.05);
    // 遠い人から
    list.sort((a, c) => _dist(c.rig.out!.p[J.pelvis.index]).compareTo(_dist(a.rig.out!.p[J.pelvis.index])));
    // ボールは奥行きの順に（体より奥なら先に描いて体に隠れる、手前なら後で）
    var ballDone = b == null;
    for (final it in list) {
      if (!ballDone) {
        final pp = it.rig.out!.p;
        final td = _dist(pp[J.neck.index]) * 0.5 + _dist(pp[J.pelvis.index]) * 0.5;
        if (_dist(b!) > td) {
          _drawBall(canvas, b);
          ballDone = true;
        }
      }
      _drawPuppet(canvas, it);
    }
    if (!ballDone) _drawBall(canvas, b!);
    perfPuppets += sw.elapsedMicroseconds;
    perfFrames++;
  }

  /// 調べ用：描くのにかかった時間（マイクロ秒の合計）とコマ数
  static int perfBg = 0, perfPuppets = 0, perfFrames = 0, perfHead = 0;
  static final List<int> perfParts = [0, 0, 0, 0, 0];
  static final _faceShaders = Expando<ImageShader>(); // 顔の画像ごとの貼り付け用シェーダ
  static final _ident = Float64List.fromList([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]);

  void _shadow(Canvas canvas, V3 g, double rad) {
    final c = _p(g);
    if (c == null) return;
    final s = _ppm(g);
    // 地面に沿った楕円：カメラの前の向き（地面へ投影）に半径ぶん進めた点の、画面上のずれが縦の半径
    final fw = V3(-_rightW.y, _rightW.x, 0);
    final a = _p(g + fw * rad);
    final ry = a == null ? s * rad * 0.4 : math.min(math.max(1.0, (a - c).distance), math.max(1.0, s * rad));
    canvas.drawOval(Rect.fromCenter(center: c, width: s * rad * 2, height: ry * 2), Paint()..color = const Color(0x2E000000));
  }

  void _drawBall(Canvas canvas, V3 b) {
    final c = _p(b);
    if (c == null) return;
    // 見える大きさは距離とズームに比例（遠い・引いた画面ほど小さい）。消えないように最小 1px だけ
    final rr = math.max(1.0, _ppm(b) * 0.0366 * 1.2);
    canvas.drawCircle(c, rr + (rr * 0.3).clamp(0.4, 1.2), Paint()..color = _ink);
    canvas.drawCircle(c, rr, Paint()..color = const Color(0xFFFBFAF5));
    if (rr > 3.5) _seams(canvas, b, rr);
  }

  /// 縫い目：硬球の縫い目の曲線（球の上の閉じた曲線）を、回転させて投影する。手前の半分だけ。赤い糸の線と縫い目の V 字
  void _seams(Canvas canvas, V3 b, double rr) {
    final sp = ballSpin?.call();
    var ax = sp?.axis ?? const V3(1, 0, 0);
    if (ax.length < 1e-6) ax = const V3(1, 0, 0);
    final e1 = ax.unit;
    final ref = e1.z.abs() < 0.9 ? V3.ez : V3.ex;
    final e2 = e1.cross(ref).unit, e3 = e1.cross(e2);
    final th = sp?.angle ?? 0.0, four = sp?.four ?? true;
    final ct = math.cos(th), st = math.sin(th);
    const a = 0.7, bb = 0.3;
    final cz = 2 * math.sqrt(a * bb);
    final camW = V3(-_camPos.x, _camPos.z, _camPos.y);
    final toCam = (camW - b).unit;
    const n = 96;
    final pts = <Offset?>[];
    final vis = <bool>[];
    const rad = 0.0366 * 1.01; // 球の半径
    for (var i = 0; i <= n; i++) {
      final t = 2 * math.pi * i / n;
      final x = a * math.cos(t) + bb * math.cos(3 * t), y = a * math.sin(t) - bb * math.sin(3 * t), z = cz * math.sin(2 * t);
      // 曲線の軸の割り当て（フォーシーム：x が回転軸、ツーシーム：z が回転軸）
      final c1 = four ? x : z, c2 = four ? y : x, c3 = four ? z : y;
      final q = e1 * c1 + e2 * (c2 * ct - c3 * st) + e3 * (c2 * st + c3 * ct);
      vis.add(q.dot(toCam) > 0.05);
      pts.add(_p(b + q * rad));
    }
    final thread = Paint()
      ..color = const Color(0xFFD0342C)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(0.8, rr * 0.075);
    final stitch = Paint()
      ..color = const Color(0xFFB3261E)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(0.6, rr * 0.05);
    for (var i = 0; i < n; i++) {
      final p0 = pts[i], p1 = pts[i + 1];
      if (p0 == null || p1 == null || !vis[i] || !vis[i + 1]) continue;
      canvas.drawLine(p0, p1, thread);
      // 縫い目の V 字（大きく見えるときだけ）
      if (rr > 9 && i.isEven) {
        final d = p1 - p0;
        if (d.distance < 0.1) continue;
        final nn = Offset(-d.dy, d.dx) / d.distance * (rr * 0.11);
        final m = (p0 + p1) / 2;
        canvas.drawLine(m + nn, m + d * 0.6, stitch);
        canvas.drawLine(m - nn, m + d * 0.6, stitch);
      }
    }
  }

  /// つながった手足（輪郭線を先に全部描いてから塗る：つなぎ目に線が出ない）。segs：(始点・終点・太さ・色)
  /// 胴の手前に描く手足の付け根の輪郭を消す範囲（付け根の点のまわりで、胴と重なる所）
  Path? _rootCut;

  /// 描く段階：0＝輪郭だけ（体全体の外形の線を先に全部）、1＝塗りだけ、2＝輪郭と塗り（手前の手足）
  int _pass = 2;

  /// パワプロ風の顔：耳と鼻は描かない
  static const showEars = false, showNose = false;
  double _innerInk = 1; // 手前の手足を描くとき 0.55（胴の上に出る内側の線を細く。外形の線は段階 0 で描いた太い線が残る）
  void _chain(Canvas canvas, List<(Offset, Offset, double, Color)> segs, double ink, {int rootSeg = -1}) {
    if (_pass != 1) {
      for (var i = 0; i < segs.length; i++) {
        final sg = segs[i];
        final cut = _rootCut != null && i == rootSeg ? _rootCut : null;
        if (cut != null) {
          canvas.save();
          canvas.clipPath(cut); // 胴の外だけ（evenOdd：大きな四角＋胴の形）
        }
        canvas.drawLine(sg.$1, sg.$2, Paint()
          ..color = _ink
          ..strokeWidth = sg.$3 + ink * 2 * (_pass == 2 ? _innerInk : 1)
          ..strokeCap = StrokeCap.round);
        if (cut != null) canvas.restore();
      }
    }
    if (_pass == 0) return;
    for (final sg in segs) {
      canvas.drawLine(sg.$1, sg.$2, Paint()
        ..color = sg.$4
        ..strokeWidth = sg.$3
        ..strokeCap = StrokeCap.round);
    }
  }

  /// 手足全体で1本につながった影（光＝左上と反対の側）。pts：関節の点の列、w：太さ、c：色
  void _shade(Canvas canvas, List<Offset> pts, double w, Color c) {
    if (pts.length < 2) return;
    final dir = pts.last - pts.first;
    if (dir.distance < 1) return;
    var n = Offset(-dir.dy, dir.dx) / dir.distance;
    if (n.dx + n.dy < 0) n = -n;
    final path = Path()..moveTo(pts.first.dx + n.dx * w * 0.27, pts.first.dy + n.dy * w * 0.27);
    for (final p in pts.skip(1)) {
      path.lineTo(p.dx + n.dx * w * 0.27, p.dy + n.dy * w * 0.27);
    }
    canvas.drawPath(path, Paint()
      ..color = Color.lerp(c, Colors.black, 0.18)!
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.34
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round);
  }

  /// 輪郭線つきの太い線（手足）
  void _limb(Canvas canvas, Offset a, Offset b, double w, Color c, {double ink = 2.2}) {
    final o = Paint()
      ..color = _ink
      ..strokeWidth = w + ink * 2
      ..strokeCap = StrokeCap.round;
    final f = Paint()
      ..color = c
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(a, b, o);
    canvas.drawLine(a, b, f);
  }

  void _blob(Canvas canvas, Path path, Color c, {double ink = 2.2}) {
    canvas.drawPath(
        path,
        Paint()
          ..color = _ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = ink * 2
          ..strokeJoin = StrokeJoin.round);
    canvas.drawPath(path, Paint()..color = c);
  }

  void _drawPuppet(Canvas canvas, PuppetItem it) {
    final rig = it.rig;
    final o = rig.shownOut!;
    final p = o.p;
    Offset? s(J j) => _p(p[j.index]);
    final pel = p[J.pelvis.index];
    if (_dist(p[J.head.index]) < 1.3) return; // カメラがその人の目の位置（捕手目線・打者目線）
    final k = _ppm(pel);
    if (k < 0.5) return;
    final ink = (rig.headR * k * 0.08).clamp(1.0, 3.2); // 輪郭線：画面上の頭の半径 × 0.08（1〜3.2）
    final uni = rig.uni;
    final jersey = Color(uni.base), under = Color(uni.undershirt), socks = Color(uni.socks), shoes = Color(uni.shoes), belt = Color(uni.belt);
    final skin = Color(rig.face.skin);
    final pants = it.catcherGear ? jersey : jersey;
    // ── 部品ごとの描き方 ──
    void leg(bool t) {
      final hip = s(t ? J.hipT : J.hipG), kn = s(t ? J.kneeT : J.kneeG), an = s(t ? J.ankleT : J.ankleG), toe = s(t ? J.toeT : J.toeG);
      if (hip == null || kn == null || an == null || toe == null) return;
      // ロングパンツはくるぶしの近くまで（ストッキングはわずかに見える）、ショートはすねの中ほどまで
      final long = uni.pants != 'ショート';
      final mid = Offset.lerp(kn, an, long ? 0.82 : 0.45)!;
      // スパイク（輪郭の段階でも外形に入れる）
      final d = toe - an;
      final len = math.max(d.distance, k * 0.12);
      final shoe = RRect.fromRectAndRadius(Rect.fromLTWH(-k * 0.05, -k * 0.055, len + k * 0.07, k * 0.11), Radius.circular(k * 0.05));
      if (_pass == 0) {
        _chain(canvas, [(mid, an, k * 0.13, socks), (hip, kn, k * 0.2, pants), (kn, mid, k * 0.17, pants)], ink);
        canvas.save();
        canvas.translate(an.dx, an.dy);
        canvas.rotate(d.direction);
        canvas.drawRRect(shoe.inflate(ink), Paint()..color = _ink);
        canvas.restore();
        return;
      }
      _chain(canvas, [(mid, an, k * 0.13, socks), (hip, kn, k * 0.2, pants), (kn, mid, k * 0.17, pants)], ink, rootSeg: 1);
      _shade(canvas, [hip, kn, mid], k * 0.18, pants);
      if (it.catcherGear) {
        // すね当て：ひざの上から足の甲まで。ひざの丸い当てと縦の筋
        const gear = Color(0xFF1C1F24);
        final top = Offset.lerp(kn, hip, 0.18)!;
        final foot = Offset.lerp(an, toe, 0.45)!;
        _chain(canvas, [(top, an, k * 0.21, gear), (an, foot, k * 0.15, gear)], ink);
        canvas.drawCircle(kn, k * 0.105 + ink, Paint()..color = _ink);
        canvas.drawCircle(kn, k * 0.105, Paint()..color = const Color(0xFF2B2F35));
        canvas.drawLine(Offset.lerp(kn, an, 0.25)!, Offset.lerp(kn, an, 0.9)!, Paint()
          ..color = const Color(0xFF3A3F47)
          ..strokeWidth = math.max(1.0, k * 0.025)
          ..strokeCap = StrokeCap.round);
      }
      // スパイク：足首からつま先へ、丸い靴
      canvas.save();
      canvas.translate(an.dx, an.dy);
      canvas.rotate(d.direction);
      if (_pass == 2) canvas.drawRRect(shoe.inflate(ink), Paint()..color = _ink);
      canvas.drawRRect(shoe, Paint()..color = shoes);
      // 白い靴底
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(-k * 0.05, k * 0.03, len + k * 0.07, k * 0.025), Radius.circular(k * 0.012)), Paint()..color = const Color(0xFFEDEDED));
      canvas.restore();
    }

    void arm(bool t) {
      final sh = s(t ? J.shoulderT : J.shoulderG), el = s(t ? J.elbowT : J.elbowG), wr = s(t ? J.wristT : J.wristG);
      if (sh == null || el == null || wr == null) return;
      final sleeve = Offset.lerp(sh, el, 0.55)!;
      _chain(canvas, [(sleeve, el, k * 0.125, under), (el, wr, k * 0.115, under), (sh, sleeve, k * 0.155, jersey)], ink, rootSeg: 2); // 半袖とアンダーシャツ
      if (_pass == 0) return;
      _shade(canvas, [sleeve, el, wr], k * 0.12, under);
      // カメラへ向かって伸びる腕：画面の長さが実際より大きく縮んでいたら、ひじと袖口に楕円の弧（しわ）を入れて奥行きを見せる
      {
        final sh3 = p[(t ? J.shoulderT : J.shoulderG).index], el3 = p[(t ? J.elbowT : J.elbowG).index], wr3 = p[(t ? J.wristT : J.wristG).index];
        void fold(Offset c, Offset a, Offset b, double len3, double w) {
          final d = b - a;
          final ratio = d.distance / math.max(1e-3, k * len3);
          if (ratio > 0.5) return;
          canvas.save();
          canvas.translate(c.dx, c.dy);
          canvas.rotate(d.direction);
          final rr2 = Rect.fromCenter(center: Offset.zero, width: w * (0.25 + 0.5 * ratio), height: w);
          canvas.drawArc(rr2, -math.pi / 2, math.pi, false, Paint()
            ..color = Color.lerp(under, Colors.black, 0.45)!
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(0.8, ink * 0.6));
          canvas.restore();
        }

        fold(el, sh, el, (el3 - sh3).length, k * 0.125);
        fold(sleeve, el, wr, (wr3 - el3).length, k * 0.15);
      }
      // 袖口のライン（球団の色）
      final sd = el - sh;
      if (sd.distance > 1) {
        final nn = Offset(-sd.dy, sd.dx) / sd.distance * (k * 0.078);
        canvas.drawLine(sleeve + nn, sleeve - nn, Paint()
          ..color = Color(uni.socks)
          ..strokeWidth = math.max(1.0, k * 0.022));
      }
      final hasGlove = !t && rig.glove;
      if (hasGlove) {
        _glove(canvas, rig, k, ink);
      } else {
        _hand(canvas, rig, t, k, ink, skin);
      }
    }

    // 胴の立体の向き（torsoPath で決める。前立て・ベルトを胴の表面にそって描くのに使う）
    V3 tFwdC = V3.ey, tFwdH = V3.ey, tAcrH = V3.ex, tUpH = V3.ez, tSc3 = V3.zero, tHc3 = V3.zero;
    Path? torsoPath() {
      final shT = s(J.shoulderT), shG = s(J.shoulderG), hipT = s(J.hipT), hipG = s(J.hipG), nk = s(J.neck), pl = s(J.pelvis);
      if (shT == null || shG == null || hipT == null || hipG == null || nk == null || pl == null) return null;
      // 胴を立体として：肩・胸・腰・お尻の高さの楕円（横の半径・前後の半径）を画面へ投影し、全部を囲む形（凸包）を外形にする。
      //  横から見ても胸の厚み・お尻の丸みが出る（関節の点だけで作ると、横からは棒になる）
      final bm = rig.body;
      final shT3 = p[J.shoulderT.index], shG3 = p[J.shoulderG.index], hT3 = p[J.hipT.index], hG3 = p[J.hipG.index];
      final nk3 = p[J.neck.index], pl3 = p[J.pelvis.index];
      final ch = o.chest[0];
      final fwdC = ch * V3.ey;
      final acrC = (shT3 - shG3).length > 1e-3 ? (shT3 - shG3).unit : ch * V3.ex;
      var acrH = (hT3 - hG3).length > 1e-3 ? (hT3 - hG3).unit : acrC;
      final upH = (nk3 - pl3).unit;
      var fwdH = acrH.cross(upH).unit;
      if (fwdH.dot(fwdC) < 0) fwdH = -fwdH;
      final sc3 = (shT3 + shG3) * 0.5, hc3 = (hT3 + hG3) * 0.5;
      final shW = (shT3 - shG3).length / 2;
      tFwdC = fwdC;
      tFwdH = fwdH;
      tAcrH = acrH;
      tUpH = upH;
      tSc3 = sc3;
      tHc3 = hc3;
      final cF = rig.chestF, wF = rig.waistF, hF = rig.hipF;
      final pts = <Offset>[];
      void ring(V3 c, V3 ax, V3 fw, double ra, double rb) {
        for (var i = 0; i < 18; i++) {
          final t = 2 * math.pi * i / 18;
          final q = _p(c + ax * (ra * math.cos(t)) + fw * (rb * math.sin(t)));
          if (q != null) pts.add(q);
        }
      }

      ring(sc3 - upH * 0.02 + fwdC * 0.0, acrC, fwdC, shW + bm.upperArmR * 0.9, bm.chestB * 1.05 * cF); // 肩の高さ（肩の丸みまで）
      ring(sc3.lerp(hc3, 0.3), acrC, fwdC, bm.chestA * 1.08 * cF, bm.chestB * 1.12 * cF); // 胸（胸郭）
      ring(sc3.lerp(hc3, 0.65), acrC.lerp(acrH, 0.5).unit, fwdC.lerp(fwdH, 0.5).unit, bm.waistA * 1.08 * wF, bm.waistB * 1.1 * wF); // 腹（ベルトの上）
      ring(hc3 - upH * 0.04, acrH, fwdH, bm.hipA * 1.05 * hF, bm.hipB * 1.1); // 腰・お尻（細身は絞って逆三角形）
      if (pts.length < 6) return null;
      // 凸包（Andrew の方法）
      pts.sort((u, v) => u.dx != v.dx ? u.dx.compareTo(v.dx) : u.dy.compareTo(v.dy));
      double cr(Offset o2, Offset a2, Offset b2) => (a2.dx - o2.dx) * (b2.dy - o2.dy) - (a2.dy - o2.dy) * (b2.dx - o2.dx);
      final lower = <Offset>[], upper = <Offset>[];
      for (final q in pts) {
        while (lower.length >= 2 && cr(lower[lower.length - 2], lower.last, q) <= 0) {
          lower.removeLast();
        }
        lower.add(q);
      }
      for (final q in pts.reversed) {
        while (upper.length >= 2 && cr(upper[upper.length - 2], upper.last, q) <= 0) {
          upper.removeLast();
        }
        upper.add(q);
      }
      final hull = [...lower..removeLast(), ...upper..removeLast()];
      if (hull.length < 3) return null;
      // 角を丸く：辺の中点を通る2次曲線
      final path = Path();
      Offset mid(int i) => (hull[i % hull.length] + hull[(i + 1) % hull.length]) / 2;
      path.moveTo(mid(0).dx, mid(0).dy);
      for (var i = 1; i <= hull.length; i++) {
        final cpt = hull[i % hull.length], e = mid(i);
        path.quadraticBezierTo(cpt.dx, cpt.dy, e.dx, e.dy);
      }
      path.close();
      if (nk.dx.isNaN || pl.dx.isNaN || hipT.dx.isNaN || hipG.dx.isNaN || shT.dx.isNaN || shG.dx.isNaN) return null;
      return path;
    }

    final tPath = torsoPath();

    void torso() {
      final shT = s(J.shoulderT), shG = s(J.shoulderG), hipT = s(J.hipT), hipG = s(J.hipG), nk = s(J.neck), pl = s(J.pelvis);
      if (shT == null || shG == null || hipT == null || hipG == null || nk == null || pl == null || tPath == null) return;
      Offset out(Offset a, Offset c, double m) {
        final d = a - c;
        return d.distance < 1e-3 ? a : a + d / d.distance * m;
      }

      final sc = (shT + shG) / 2, hc = (hipT + hipG) / 2;
      final a = out(shT, sc, k * 0.085), b = out(shG, sc, k * 0.085);
      final c = out(hipG, hc, k * 0.07), d = out(hipT, hc, k * 0.07);
      final path = tPath;
      canvas.drawPath(path, Paint()..color = jersey); // 外形の線は輪郭の段階で描いた（手足との境目に線を出さない）
      // 縦じま（あれば）
      final pin = uni.pinstripe;
      if (pin != null) {
        canvas.save();
        canvas.clipPath(path);
        final sp = Paint()
          ..color = Color(pin.color)
          ..strokeWidth = math.max(0.8, k * 0.006);
        final up = (sc - hc);
        final across = Offset(-up.dy, up.dx) / math.max(1e-3, up.distance);
        for (var i = -8; i <= 8; i++) {
          final o0 = hc + across * (i * k * 0.045);
          canvas.drawLine(o0 - up * 0.2, o0 + up * 1.3, sp);
        }
        canvas.restore();
      }
      // 胸がこちらを向いているか（背中なら背番号）
      final ch = o.chest[0];
      final camW = V3(-_camPos.x, _camPos.z, _camPos.y);
      final chestFront = (ch * V3.ey).dot((camW - p[J.neck.index]).unit);
      final upS = sc - hc;
      final upU = upS / math.max(1e-3, upS.distance);
      if (chestFront > 0.15) {
        // 襟（V ネック、アンダーシャツの色）とボタンの列
        final v0 = nk + upU * (-k * 0.01);
        final acr = Offset(-upU.dy, upU.dx);
        final vee = Path()
          ..moveTo(v0.dx + acr.dx * k * 0.06, v0.dy + acr.dy * k * 0.06)
          ..lineTo(v0.dx - acr.dx * k * 0.06, v0.dy - acr.dy * k * 0.06)
          ..lineTo(v0.dx - upU.dx * k * 0.1, v0.dy - upU.dy * k * 0.1)
          ..close();
        _blob(canvas, vee, under, ink: ink * 0.5);
        // 前立て（ボタンの列）：胸椎の正面から骨盤の正面へ、胴の表面にそって曲がる（胴のひねりが一目で分かる）
        final bm = rig.body;
        final top3 = tSc3 - tUpH * 0.07, belt3 = tHc3.lerp(tSc3, 0.12);
        final placket = Path();
        var started = false;
        final buttons = <Offset>[];
        for (var i = 0; i <= 12; i++) {
          final t = i / 12;
          final n3 = tFwdC.lerp(tFwdH, t * t).unit;
          final dep = bm.chestB * 1.1 * rig.chestF * (1 - t) + bm.waistB * 1.08 * rig.waistF * t;
          final q = _p(top3.lerp(belt3, t) + n3 * dep);
          if (q == null) continue;
          started ? placket.lineTo(q.dx, q.dy) : placket.moveTo(q.dx, q.dy);
          started = true;
          if (i == 3 || i == 6 || i == 9) buttons.add(q);
        }
        canvas.drawPath(placket, Paint()
          ..color = Color.lerp(jersey, Colors.black, 0.3)!
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.0, ink * 0.55));
        for (final bq in buttons) {
          canvas.drawCircle(bq, math.max(0.8, k * 0.008), Paint()..color = Color.lerp(jersey, Colors.black, 0.35)!);
        }
        // 胸のチーム名（胸の面に貼る）
        if (rig.teamText.isNotEmpty && k > 25) _planeText(canvas, rig, o, p, rig.teamText, 0.085, 0.74, true, path, Color(uni.socks));
      } else if (chestFront < -0.2 && rig.number.isNotEmpty && k > 25) {
        // 背番号：背中の面に貼った形で描く（斜めから見れば細く、横からは見えない）。胴の形からはみ出さない
        final pl3 = p[J.pelvis.index], nk3 = p[J.neck.index];
        final fwd3 = ch * V3.ey;
        var acr3 = ch * V3.ex;
        final up3 = (nk3 - pl3).unit;
        final c3 = pl3.lerp(nk3, 0.6) - fwd3 * (rig.body.chestB);
        final c2 = _p(c3), ax0 = _p(c3 + acr3 * 0.1), ay0 = _p(c3 + up3 * 0.1);
        if (c2 != null && ax0 != null && ay0 != null) {
          var ax = ax0 - c2;
          final ay = ay0 - c2;
          // 画面は左右を反転して見せるので、文字の横の向きは反転前の画面で左向きにする（見る人には左から右へ読める）
          if (ax.dx > 0) ax = -ax;
          const fs = 100.0;
          final tp = rig.textCache.putIfAbsent('num|${rig.number}|${uni.socks}', () => TextPainter(
                text: TextSpan(text: rig.number, style: TextStyle(fontSize: fs, fontWeight: FontWeight.w900, color: Color(uni.socks), height: 1.0, shadows: const [Shadow(color: Colors.white, blurRadius: 0, offset: Offset(5, 5)), Shadow(color: Colors.white, blurRadius: 0, offset: Offset(-5, -5))])),
                textDirection: TextDirection.ltr,
              )..layout());
          // 字の高さ 0.2m：文字の 1単位 = 0.2/100 m。軸は 0.1m あたりの画面のずれ
          const sc3 = 0.2 / fs / 0.1;
          canvas.save();
          canvas.clipPath(path);
          canvas.transform(Float64List.fromList([ax.dx * sc3, ax.dy * sc3, 0, 0, -ay.dx * sc3, -ay.dy * sc3, 0, 0, 0, 0, 1, 0, c2.dx, c2.dy, 0, 1]));
          tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
          canvas.restore();
        }
      }
      // 捕手の胸当て：首の下から股の上まで、肩当て付き（こちらを向いているとき）
      if (it.catcherGear && chestFront > -0.15) {
        const gear = Color(0xFF1C1F24);
        final t0 = nk + upU * (-k * 0.03);
        final l0 = Offset.lerp(a, sc, 0.25)!, r0 = Offset.lerp(b, sc, 0.25)!;
        final bot = hc - upU * (k * 0.07);
        final lb = Offset.lerp(d, hc, 0.3)! - upU * (k * 0.02), rb2 = Offset.lerp(c, hc, 0.3)! - upU * (k * 0.02);
        final cp = Path()
          ..moveTo(l0.dx, l0.dy)
          ..quadraticBezierTo(t0.dx, t0.dy - k * 0.02, r0.dx, r0.dy)
          ..lineTo(rb2.dx, rb2.dy)
          ..quadraticBezierTo(bot.dx, bot.dy + k * 0.03, lb.dx, lb.dy)
          ..close();
        _blob(canvas, cp, gear, ink: ink);
        final ln = Paint()
          ..color = const Color(0xFF3A3F47)
          ..strokeWidth = math.max(1.0, k * 0.02);
        for (final f2 in [0.35, 0.55, 0.75]) {
          canvas.drawLine(Offset.lerp(l0, lb, f2)!, Offset.lerp(r0, rb2, f2)!, ln);
        }
      }
      // ベルトとバックル：骨盤の高さで、腹の楕円の見えている側の半周にそって（骨盤の向き・ひねりが分かる）
      {
        final bm = rig.body;
        final beltC = tHc3.lerp(tSc3, 0.12);
        final pelFront = tFwdH.dot((camW - beltC).unit);
        final ra = bm.waistA * 1.1 * rig.waistF, rb = bm.waistB * 1.12 * rig.waistF;
        final pts = <Offset>[];
        for (var i = 0; i <= 14; i++) {
          final ang = (-90 + 180 * i / 14) * math.pi / 180 + (pelFront >= 0 ? 0 : math.pi);
          final q = _p(beltC + tAcrH * (ra * math.sin(ang)) + tFwdH * (rb * math.cos(ang)));
          if (q != null) pts.add(q);
        }
        if (pts.length > 2) {
          final bp = Path()..addPolygon(pts, false);
          canvas.save();
          canvas.clipPath(path);
          canvas.drawPath(bp, Paint()
            ..color = _ink
            ..style = PaintingStyle.stroke
            ..strokeWidth = k * 0.045 + ink * 1.2);
          canvas.drawPath(bp, Paint()
            ..color = belt
            ..style = PaintingStyle.stroke
            ..strokeWidth = k * 0.045);
          canvas.restore();
          if (pelFront > 0.15) {
            // バックル：骨盤の正面の法線の上
            final bq = _p(beltC + tFwdH * (rb + 0.005)), bx = _p(beltC + tFwdH * (rb + 0.005) + tAcrH * 0.03);
            if (bq != null && bx != null) {
              canvas.save();
              canvas.translate(bq.dx, bq.dy);
              canvas.rotate((bx - bq).direction);
              canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: math.max(2.0, (bx - bq).distance * 1.6), height: k * 0.035), Paint()..color = const Color(0xFFD9D9D9));
              canvas.restore();
            }
          }
        }
      }
    }

    // 奥行き：手足ごとの、カメラからの距離（胴より遠いものは胴の前に描く）
    final torsoD = _dist(p[J.neck.index]) * 0.5 + _dist(pel) * 0.5;
    final parts = <(double, void Function(), int)>[
      (_dist((p[J.kneeT.index] + p[J.hipT.index]) * 0.5), () => leg(true), 0),
      (_dist((p[J.kneeG.index] + p[J.hipG.index]) * 0.5), () => leg(false), 1),
      (_dist((p[J.elbowT.index] + p[J.wristT.index]) * 0.5), () => arm(true), 2),
      (_dist((p[J.elbowG.index] + p[J.wristG.index]) * 0.5), () => arm(false), 3),
    ]..sort((a, c) => c.$1.compareTo(a.$1));
    // 胴の前か後ろか：境目で毎コマ入れ替わらないよう、あそび（±5cm）をもたせる
    final front = <int, bool>{};
    for (var i = 0; i < 4; i++) {
      final dd = parts.where((x) => x.$3 == i).first.$1 - torsoD;
      final was = rig.limbFront[i];
      front[i] = was == null ? dd <= 0.02 : (was ? dd <= 0.07 : dd <= -0.03);
      rig.limbFront[i] = front[i]!;
    }
    // バット：体より奥か手前かで、胴の前後に描く（手前のときは手より先に描いて、手が握って見えるように）
    final kn = it.batKnob, tp = it.batTip;
    void drawBat() {
      if (kn == null || tp == null) return;
      final a = _p(kn), c = _p(tp);
      if (a == null || c == null) return;
      final path = _taper(a, c, k * 0.035, k * 0.068);
      _blob(canvas, path, Color(rig.batColor), ink: ink * 0.8);
      canvas.save();
      canvas.clipPath(path);
      if (rig.batTipColor != rig.batColor) {
        // ツートン：先の 4 割が濃い
        final m0 = Offset.lerp(a, c, 0.6)!;
        final d = c - a;
        final n = Offset(-d.dy, d.dx) / math.max(1e-3, d.distance) * (k * 0.1);
        canvas.drawPath(Path()..addPolygon([m0 + n, m0 - n, c - n + d * 0.1, c + n + d * 0.1], true), Paint()..color = Color(rig.batTipColor));
      }
      // メーカーのロゴ（胴の中ほどに色の帯）とグリップのテープ
      final l0 = Offset.lerp(a, c, 0.62)!, l1 = Offset.lerp(a, c, 0.72)!;
      canvas.drawLine(l0, l1, Paint()
        ..color = Color(rig.batLogo)
        ..strokeWidth = k * 0.03
        ..strokeCap = StrokeCap.round);
      canvas.drawLine(a, Offset.lerp(a, c, 0.22)!, Paint()
        ..color = Colors.black.withValues(alpha: 0.35)
        ..strokeWidth = k * 0.05);
      canvas.restore();
    }

    final batD = kn != null && tp != null ? _dist((kn + tp) * 0.5) : null;
    final batFront = batD != null && batD <= torsoD;
    // ① 体全体の外形の線（胴と4本の手足）。② 塗る：奥の手足 → 胴 → 頭 → 手前の手足（手前の手足だけ輪郭も。付け根の区間は胴の外だけ）
    //   こうすると、肩・腰・股・背中の境目に線が出ず、外側の形だけが1本の線で囲まれる
    _pass = 0;
    if (tPath != null) {
      canvas.drawPath(tPath, Paint()
        ..color = _ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = ink * 2
        ..strokeJoin = StrokeJoin.round);
    }
    for (final pt in parts) {
      pt.$2();
    }
    _pass = 1;
    for (final pt in parts.where((x) => !front[x.$3]!)) {
      pt.$2();
    }
    _pass = 2;
    if (batD != null && !batFront) drawBat();
    torso();
    final hsw = Stopwatch()..start();
    _head(canvas, rig, k, ink, skin, it.catcherGear);
    perfHead += hsw.elapsedMicroseconds;
    if (batD != null && batFront) drawBat();
    _innerInk = 0.55;
    for (final pt in parts.where((x) => front[x.$3]!)) {
      // 胴の手前の手足：付け根（肩・股関節）の輪郭の丸い端が胴の上に線として出ないように消す
      if (tPath != null) {
        // 付け根の区間の輪郭は、胴の外の部分だけ（evenOdd：大きな四角と胴の形が重なる所＝胴の中は描かない。図形の合成は使わない）
        _rootCut = Path()
          ..fillType = PathFillType.evenOdd
          ..addRect(const Rect.fromLTWH(-1e5, -1e5, 2e5, 2e5))
          ..addPath(tPath, Offset.zero);
      }
      pt.$2();
      _rootCut = null;
    }
    _innerInk = 1;
  }

  /// 胴の前（front）か背中の面に字を貼る。h：字の高さ（m）、at：腰→首の何割の高さ
  void _planeText(Canvas canvas, PuppetRig rig, HumanOut o, List<V3> p, String text, double h, double at, bool front, Path clip, Color col) {
    final ch = o.chest[0];
    final pl3 = p[J.pelvis.index], nk3 = p[J.neck.index];
    final fwd3 = ch * V3.ey, acr3 = ch * V3.ex, up3 = (nk3 - pl3).unit;
    final c3 = pl3.lerp(nk3, at) + fwd3 * (front ? rig.body.chestB : -rig.body.chestB);
    final c2 = _p(c3), ax0 = _p(c3 + acr3 * 0.1), ay0 = _p(c3 + up3 * 0.1);
    if (c2 == null || ax0 == null || ay0 == null) return;
    var ax = ax0 - c2;
    final ay = ay0 - c2;
    if (ax.dx > 0) ax = -ax;
    const fs = 100.0;
    // 字の形は選手ごとに1回だけ組む（毎コマ組むと重い）
    final tp = rig.textCache.putIfAbsent('chest|$text|${col.toARGB32()}', () => TextPainter(
          text: TextSpan(text: text, style: TextStyle(fontSize: fs, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic, color: col, height: 1.0, shadows: const [Shadow(color: Colors.white, offset: Offset(4, 4)), Shadow(color: Colors.white, offset: Offset(-4, -4))])),
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout());
    final sc3 = h / fs / 0.1;
    // 胸の幅に収める
    final maxW = rig.body.chestA * 1.5 / h * fs;
    final shrink = tp.width > maxW ? maxW / tp.width : 1.0;
    canvas.save();
    canvas.clipPath(clip);
    canvas.transform(Float64List.fromList([ax.dx * sc3 * shrink, ax.dy * sc3 * shrink, 0, 0, -ay.dx * sc3, -ay.dy * sc3, 0, 0, 0, 0, 1, 0, c2.dx, c2.dy, 0, 1]));
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
  }

  /// 細い所 w0 から太い所 w1 へ（バット）
  Path _taper(Offset a, Offset b, double w0, double w1) {
    final d = b - a;
    final n = Offset(-d.dy, d.dx) / math.max(1e-3, d.distance);
    return Path()
      ..moveTo(a.dx + n.dx * w0 / 2, a.dy + n.dy * w0 / 2)
      ..lineTo(b.dx + n.dx * w1 / 2, b.dy + n.dy * w1 / 2)
      ..arcToPoint(Offset(b.dx - n.dx * w1 / 2, b.dy - n.dy * w1 / 2), radius: Radius.circular(w1 / 2))
      ..lineTo(a.dx - n.dx * w0 / 2, a.dy - n.dy * w0 / 2)
      ..close();
  }

  /// 手：手のひら（角の丸い板）と指のかたまり・親指。握ると丸い拳に指の節の線。輪郭は細め
  void _hand(Canvas canvas, PuppetRig rig, bool t, double k, double ink, Color skin) {
    final o = rig.shownOut!;
    final s = t ? 0 : 1;
    final wr = o.p[(t ? J.wristT : J.wristG).index];
    final hm = o.hand[s];
    final d = hm * const V3(0, 0, -1), side = hm * const V3(0, 1, 0);
    final pose = t ? rig.handT : rig.handG;
    final curl = pose.curl[2][0] + pose.curl[2][1];
    final fist = curl > 1.5;
    final hl = rig.body.hand;
    final w0 = _p(wr), tip = _p(wr + d * (hl * (fist ? 0.62 : 0.95))), sd = _p(wr + d * (hl * 0.35) + side * 0.045);
    if (w0 == null || tip == null || sd == null) return;
    final ax = tip - w0;
    final len = math.max(ax.distance, k * 0.07);
    final wid = math.max((sd - _p(wr + d * (hl * 0.35))!).distance * 2, k * 0.075);
    final shade = Color.lerp(skin, const Color(0xFF7A3B2A), 0.25)!;
    canvas.save();
    canvas.translate(w0.dx, w0.dy);
    canvas.rotate(ax.direction);
    final lw = ink * 0.8;
    if (fist) {
      final r = RRect.fromRectAndRadius(Rect.fromLTWH(-len * 0.05, -wid * 0.55, len * 1.05, wid * 1.1), Radius.circular(wid * 0.45));
      canvas.drawRRect(r.inflate(lw), Paint()..color = _ink);
      canvas.drawRRect(r, Paint()..color = skin);
      // 指の節（3本の線）
      final kn = Paint()
        ..color = shade
        ..strokeWidth = math.max(0.7, lw * 0.7);
      for (var i = 1; i <= 3; i++) {
        final y = -wid * 0.55 + wid * 1.1 * i / 4;
        canvas.drawLine(Offset(len * 0.62, y), Offset(len * 0.95, y), kn);
      }
    } else {
      // 手のひら＋そろえた指（先が少し細い）
      final path = Path()
        ..moveTo(0, -wid * 0.45)
        ..lineTo(len * 0.55, -wid * 0.5)
        ..quadraticBezierTo(len * 1.02, -wid * 0.42, len * 1.02, 0)
        ..quadraticBezierTo(len * 1.02, wid * 0.42, len * 0.55, wid * 0.5)
        ..lineTo(0, wid * 0.45)
        ..close();
      canvas.drawPath(path, Paint()
        ..color = _ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = lw * 2
        ..strokeJoin = StrokeJoin.round);
      canvas.drawPath(path, Paint()..color = skin);
      final fl = Paint()
        ..color = shade
        ..strokeWidth = math.max(0.6, lw * 0.6);
      for (var i = 1; i <= 3; i++) {
        final y = -wid * 0.5 + wid * i / 4;
        canvas.drawLine(Offset(len * 0.58, y), Offset(len * 0.95, y * 0.8), fl);
      }
    }
    canvas.restore();
    // 親指（手首の横から斜め前へ）
    final th0 = _p(wr + d * (hl * 0.2) + side * 0.03), th1 = _p(wr + d * (hl * 0.5) + side * 0.055);
    if (th0 != null && th1 != null) _limb(canvas, th0, th1, wid * 0.42, skin, ink: lw);
  }

  /// グラブ：大きな丸い革。ポケットがこちらを向いていれば中の色と指の線を見せる
  void _glove(Canvas canvas, PuppetRig rig, double k, double ink) {
    final o = rig.shownOut!;
    final wr = o.p[J.wristG.index];
    final hm = o.hand[1];
    final d = hm * const V3(0, 0, -1), across = hm * const V3(0, 1, 0);
    final palm = hm * V3(-rig.human.xs(1), 0, 0);
    final c3 = wr + d * (rig.body.hand * 0.55);
    final c = _p(c3), tipP = _p(c3 + d * 0.16), sideP = _p(c3 + across * 0.12);
    if (c == null || tipP == null || sideP == null) return;
    final ax = tipP - c, ay = sideP - c;
    final lenA = math.max(ax.distance, k * 0.06), lenB = math.max(ay.distance, k * 0.06);
    final col = Color(rig.gloveColor ?? rig.uni.glove);
    final laceC = Color(rig.laceColor ?? rig.gloveColor ?? rig.uni.glove);
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(ax.direction);
    // 手のひらの土手＋指先の4つのふくらみ＋親指
    final shape = Path()..addOval(Rect.fromCenter(center: Offset(-lenA * 0.15, 0), width: lenA * 1.8, height: lenB * 2.0));
    for (var i = 0; i < 4; i++) {
      final yy = (-0.62 + 0.41 * i) * lenB;
      shape.addOval(Rect.fromCenter(center: Offset(lenA * 0.62, yy), width: lenA * 0.95, height: lenB * 0.5));
    }
    shape.addOval(Rect.fromCenter(center: Offset(-lenA * 0.05, lenB * 0.95), width: lenA * 1.1, height: lenB * 0.55));
    canvas.drawPath(shape, Paint()
      ..color = _ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = ink * 2);
    canvas.drawPath(shape, Paint()..color = col);
    final toCam = V3(_camPos.x * -1, _camPos.z, _camPos.y) - c3; // 世界の座標でのカメラの方向
    final facing = palm.dot(toCam.unit);
    final lines = Paint()
      ..color = _ink.withValues(alpha: 0.55)
      ..strokeWidth = math.max(1.0, ink * 0.6)
      ..style = PaintingStyle.stroke;
    if (facing > 0.1) {
      canvas.drawOval(Rect.fromCenter(center: Offset(-lenA * 0.15, 0), width: lenA * 1.2, height: lenB * 1.2), Paint()..color = Color.lerp(col, Colors.black, 0.28)!);
    }
    for (var i = -1; i <= 1; i++) {
      canvas.drawLine(Offset(lenA * 0.25, (i * 0.41 - 0.2) * lenB), Offset(lenA * 1.0, (i * 0.41 - 0.2) * lenB), lines);
    }
    // ウェブ（親指と人差し指の間の網）：形は選手ごと
    final wc = Offset(lenA * 0.55, lenB * 0.82);
    final wbR = Rect.fromCenter(center: wc, width: lenA * 0.62, height: lenB * 0.5);
    final webPaint = Paint()..color = Color.lerp(col, Colors.black, 0.12)!;
    canvas.drawRRect(RRect.fromRectAndRadius(wbR, Radius.circular(lenB * 0.1)), webPaint);
    final wl = Paint()
      ..color = laceC
      ..strokeWidth = math.max(1.0, ink * 0.7)
      ..style = PaintingStyle.stroke;
    switch (rig.web) {
      case 'クロス':
        canvas.drawLine(wbR.topLeft, wbR.bottomRight, wl);
        canvas.drawLine(wbR.bottomLeft, wbR.topRight, wl);
      case 'H':
        canvas.drawLine(wbR.centerLeft, wbR.centerRight, wl);
        canvas.drawLine(wbR.topCenter + Offset(-wbR.width * 0.25, 0), wbR.bottomCenter + Offset(-wbR.width * 0.25, 0), wl);
        canvas.drawLine(wbR.topCenter + Offset(wbR.width * 0.25, 0), wbR.bottomCenter + Offset(wbR.width * 0.25, 0), wl);
      case 'バスケット':
        for (var i = 1; i < 4; i++) {
          canvas.drawLine(Offset(wbR.left + wbR.width * i / 4, wbR.top), Offset(wbR.left + wbR.width * i / 4, wbR.bottom), wl);
          canvas.drawLine(Offset(wbR.left, wbR.top + wbR.height * i / 4), Offset(wbR.right, wbR.top + wbR.height * i / 4), wl);
        }
      case 'トラップ':
        canvas.drawLine(wbR.topCenter, wbR.bottomCenter, wl..strokeWidth = math.max(1.4, ink));
        canvas.drawLine(wbR.centerLeft, wbR.centerRight, wl);
      default: // 一枚（中が見えない）
        canvas.drawRRect(RRect.fromRectAndRadius(wbR.deflate(lenB * 0.04), Radius.circular(lenB * 0.08)), wl);
    }
    // ひも（土手の縁と指先）
    final lacePaint = Paint()
      ..color = laceC
      ..strokeWidth = math.max(1.0, ink * 0.8)
      ..style = PaintingStyle.stroke;
    canvas.drawArc(Rect.fromCenter(center: Offset(-lenA * 0.15, 0), width: lenA * 1.5, height: lenB * 1.7), math.pi * 0.6, math.pi * 0.8, false, lacePaint);
    for (var i = 0; i < 4; i++) {
      final yy = (-0.62 + 0.41 * i) * lenB;
      canvas.drawLine(Offset(lenA * 1.02, yy - lenB * 0.12), Offset(lenA * 1.02, yy + lenB * 0.12), lacePaint);
    }
    // メーカーのロゴ（甲の側＝こちらに背を向けているとき、手首の近くに）
    if (facing < 0.1) {
      canvas.drawOval(Rect.fromCenter(center: Offset(-lenA * 0.35, -lenB * 0.1), width: lenA * 0.42, height: lenB * 0.3), Paint()..color = Color(rig.gloveLogo));
    }
    canvas.restore();
  }

  /// 頭：輪郭（あごの幅・長さ）・耳・髪（帽子の下）・顔の部品（目・眉・鼻・口・ひげ）を選手ごとの値で描き分ける
  /// 小さく写る頭：丸い頭・目・帽子（またはヘルメット・マスク）だけ
  void _tinyHead(Canvas canvas, PuppetRig rig, V3 hc3, V3 fwd, V3 up, Offset c, double rr, Offset upS, Offset faceDir, double front, double ink, Color skin, bool mask) {
    final R = rig.headR;
    final shadeC = Color.lerp(skin, const Color(0xFF7A3B2A), 0.18)!;
    final nkP = _p(rig.out!.p[J.neck.index]), nbP = _p(hc3 - fwd * (0.12 * R) - up * (0.62 * R));
    if (nkP != null && nbP != null) _limb(canvas, nkP, nbP, rr * 0.62, Color.lerp(skin, shadeC, 0.35)!, ink: ink);
    final down = -upS, acr = Offset(-upS.dy, upS.dx);
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(upS.direction + math.pi / 2);
    _blob(canvas, Path()..addOval(Rect.fromCenter(center: Offset(0, rr * 0.1), width: rr * 1.95, height: rr * 2.2)), skin, ink: ink);
    canvas.restore();
    final capC = Color(mask ? 0xFF1C1F24 : (rig.helmet ? rig.uni.helmet : rig.uni.capBase));
    if (mask) {
      if (front > -0.05) {
        canvas.save();
        final fc = c + faceDir * 0.6 + down * (rr * 0.15);
        canvas.translate(fc.dx, fc.dy);
        canvas.rotate(upS.direction + math.pi / 2);
        canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: rr * 1.3 * (0.4 + 0.6 * front.clamp(0.0, 1.0)), height: rr * 1.5), Paint()..color = const Color(0xFF15171A));
        canvas.restore();
      }
    } else if (front > 0.25 && rr >= 3) {
      final e0 = c + faceDir * 0.75 + down * (rr * 0.18);
      final sq = 0.4 + 0.6 * front;
      final eyeP = Paint()..color = _ink;
      for (final sgn in [-1.0, 1.0]) {
        canvas.drawCircle(e0 + acr * (sgn * rr * 0.3 * sq), math.max(0.6, rr * 0.085), eyeP);
      }
    }
    final capPath = Path()..addArc(Rect.fromCircle(center: c, radius: rr * 1.05), upS.direction - 1.25, 2.5);
    capPath.close();
    _blob(canvas, capPath, capC, ink: ink);
    if (!mask) {
      // つば：横向きなら前へ、正面なら額の帯
      final b0 = c + upS * (rr * 0.32);
      final brimP = Paint()
        ..color = Color(rig.helmet ? rig.uni.helmet : rig.uni.capBrim)
        ..strokeWidth = math.max(1.0, rr * (rig.helmet ? 0.2 : 0.26))
        ..strokeCap = StrokeCap.round;
      if (faceDir.distance > rr * 0.35) {
        canvas.drawLine(b0 + faceDir * 0.3, b0 + faceDir * (rig.helmet ? 1.15 : 1.4), brimP);
      } else if (front > 0) {
        canvas.drawLine(b0 - acr * (rr * 0.75) + faceDir * 0.6, b0 + acr * (rr * 0.75) + faceDir * 0.6, brimP);
      }
    }
  }

  /// 帽子のふち・耳の横・えり足から、頭の輪郭の外へ飛び出す毛束（ツンツン跳ね髪・ウェーブの長髪・長いえり足・短髪の毛先）。
  ///  頭を塗る前に描くので、頭に重なる所は隠れ、輪郭の外へ出た所だけが見える
  void _hairTufts(Canvas canvas, PuppetRig rig, V3 hc3, V3 right, V3 fwd, V3 up, double R, double ink, Offset? Function(V3) sp) {
    final f = rig.face;
    final zb = ((rig.helmet ? 0.1 : 0.3) - 0.03) * R;
    V3 ar(double th, double z, double sx, double grow) {
      final rz = math.sqrt(math.max(0.0, R * R * 1.03 - z * z)) * grow;
      return hc3 + right * (sx * rz * math.sin(th * deg)) + fwd * (rz * math.cos(th * deg)) + up * z;
    }

    // (角度, 幅°, 先の高さ, 外への伸び)
    final List<(double, double, double, double)> tufts = switch (f.hairStyle) {
      6 => [for (final double th in [100, 118, 136, 154, 172]) (th, 8.0, zb - 0.26 * R, 1.2)],
      7 => [for (final double th in [96, 114, 132, 150, 168, 184]) (th, 10.0, -0.62 * R, 1.16)],
      4 => [for (final double th in [140, 156, 172]) (th, 9.0, -0.78 * R, 1.08)],
      0 => [for (final double th in [112, 136, 160]) (th, 7.0, zb - 0.13 * R, 1.13)],
      2 => [(84.0, 7.0, -0.5 * R, 1.06)],
      _ => const [],
    };
    if (tufts.isEmpty) return;
    final fill = Paint()..color = Color(f.hair);
    final line = Paint()
      ..color = _ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = ink * 1.6
      ..strokeJoin = StrokeJoin.round;
    for (final sx in [-1.0, 1.0]) {
      for (final (th, w, zt, grow) in tufts) {
        final a = sp(ar(th - w, zb, sx, 1.0)), b = sp(ar(th + w, zb, sx, 1.0)), tip = sp(ar(th + (f.hairStyle == 7 ? 6 : 3), zt, sx, grow));
        if (a == null || b == null || tip == null) continue;
        final m = (a + b) / 2;
        // 少しふくらんだ毛先（二次曲線）
        final bulge = (tip - m) * 0.45 + Offset(-(tip - m).dy, (tip - m).dx) * (f.hairStyle == 7 ? 0.22 : 0.12);
        final path = Path()
          ..moveTo(a.dx, a.dy)
          ..quadraticBezierTo(m.dx + bulge.dx, m.dy + bulge.dy, tip.dx, tip.dy)
          ..quadraticBezierTo((m + (tip - m) * 0.4).dx, (m + (tip - m) * 0.4).dy, b.dx, b.dy)
          ..close();
        canvas.drawPath(path, line);
        canvas.drawPath(path, fill);
      }
    }
  }

  void _head(Canvas canvas, PuppetRig rig, double k, double ink, Color skin, bool mask) {
    final o = rig.shownOut!;
    final hc3 = o.p[J.head.index];
    final c = _p(hc3);
    if (c == null) return;
    final rr = rig.headR * k;
    final f = rig.face;
    final hd = o.head;
    final fwd = hd * V3.ey, up = hd * V3.ez, right = hd * V3.ex;
    final camW = V3(-_camPos.x, _camPos.z, _camPos.y);
    final toCam = (camW - hc3).unit;
    final front = fwd.dot(toCam); // 1＝こちらを向く、−1＝背中
    Offset? sp(V3 w) => _p(w);
    final faceC = sp(hc3 + fwd * rig.headR * 0.9);
    final topP = sp(hc3 + up * rig.headR);
    final rS = sp(hc3 + right * rig.headR);
    if (faceC == null || topP == null || rS == null) return;
    final upS = (topP - c) / math.max(1e-3, (topP - c).distance);
    final faceDir = faceC - c; // 顔の正面の画面上のずれ（横を向くほど大きい）
    if (rr < 7) {
      // 遠くて小さく写る：顔の細かい部品は見えないので軽い描き方（毎コマ十数人ぶん描くので）
      _tinyHead(canvas, rig, hc3, fwd, up, c, rr, upS, faceDir, front, ink, skin, mask);
      return;
    }
    // ───────── 頭と顔：頭の立体（頭蓋の球＋顔の下半分）の表面の上に顔の部品を置き、1点ずつ投影して描く ─────────
    //  横を向けば目や口は細く・鼻は横に出っぱる。部品の形・大きさ・位置は選手ごと（FaceLook）
    final R = rig.headR;
    final hair = Color(f.hair);
    final shadeC = Color.lerp(skin, const Color(0xFF7A3B2A), 0.18)!;
    final rot = upS.direction + math.pi / 2; // 帽子・耳当てで使う（ローカル：−y が上）
    V3 L(double x, double y, double z) => hc3 + right * x + fwd * y + up * z;
    // 顔の形
    // 顔の型（ふつう・ホームベース・長方形・面長）と、計測の統計から選手ごとに決めたあごの幅・長さ（FaceArt と同じ式）
    final jawW = FaceArt.jawOf(f), chinL = FaceArt.chinOf(f);
    final sqE = FaceArt.squareOf(f); // 顔の下半分の角ばり（超楕円の指数）
    double sm(double x) {
      final c = x.clamp(0.0, 1.0);
      return c * c * (3 - 2 * c);
    }

    double sOf(double z) => (-z / (R * chinL)).clamp(0.0, 1.0); // 0＝顔のまん中の高さ … 1＝あご先
    // 角ばり（超楕円の指数）：頭の上は丸（2）、ほおから下へ顔の型の値へなめらかに
    double eAt(double z) => z >= 0 ? 2.0 : 2.0 + (sqE - 2.0) * sm(sOf(z) / 0.35);
    // 横幅：ほおで少しふくらみ（下ぶくれ）、あご先へ向けて顔の型のあご幅へ
    double rxAt(double z) => R * 0.97 * (z >= 0 ? 1.0 : (1 + 0.045 * math.sin(math.pi * math.min(1.0, sOf(z) * 1.4))) * (1.0 - (1.0 - jawW) * math.pow(sOf(z), 2.2)));
    double rzAt(double z) => z >= 0 ? R : R * chinL;
    double tAt(double x, double z) {
      final e = eAt(z);
      return (1 - math.pow((x / rxAt(z)).abs(), e) - math.pow((z / rzAt(z)).abs(), e)).toDouble();
    }

    // 顔の前後の厚み：顔の下半分は前が平ら（パワプロの広く平らな顔）
    double surfY(double x, double z) => R * 0.98 * math.pow(math.max(0.0, tAt(x, z)), z >= 0 ? 0.5 : 0.5 - 0.06 * sm(sOf(z) / 0.35)).toDouble();
    // その高さでの顔の横のふち（頭の中心からの横の距離）
    double xbAt(double z) {
      final e = eAt(z);
      return rxAt(z) * math.pow(math.max(0.0, 1 - math.pow((z / rzAt(z)).abs(), e)), 1 / e).toDouble();
    }
    V3 sPt(double x, double z, [double lift = 0.002]) => L(x, surfY(x, z) + lift, z);
    Offset? pp(double x, double z, [double lift = 0.002]) => sp(sPt(x, z, lift));
    Path? poly(List<(double, double)> pts, {bool close = true, double lift = 0.002}) {
      final path = Path();
      for (var i = 0; i < pts.length; i++) {
        final q = pp(pts[i].$1, pts[i].$2, lift);
        if (q == null) return null;
        i == 0 ? path.moveTo(q.dx, q.dy) : path.lineTo(q.dx, q.dy);
      }
      if (close) path.close();
      return path;
    }

    // ── 首（胴と頭のつなぎ目）──
    final nkP = _p(rig.out!.p[J.neck.index]), nbP = sp(L(0, -0.12 * R, -0.62 * R));
    if (nkP != null && nbP != null) _limb(canvas, nkP, nbP, rr * 0.62, Color.lerp(skin, shadeC, 0.35)!, ink: ink);
    final psw = Stopwatch()..start();
    int lap() { final v = psw.elapsedMicroseconds; psw.reset(); return v; }
    // ── 輪郭：頭蓋（投影した円）と、顔の下半分（あご・ほお・あご先）の点を囲む形 ──
    final skC = sp(L(0, -0.04 * R, 0.05 * R));
    if (skC == null) return;
    final cand = <Offset>[for (var i = 0; i < 32; i++) skC + Offset(math.cos(2 * math.pi * i / 32), math.sin(2 * math.pi * i / 32)) * (rr * 1.0)];
    for (var i = 0; i <= 10; i++) {
      final z = -R * chinL * i / 10 * 0.995;
      final xb = xbAt(z);
      for (final (x, y) in [(xb, 0.0), (-xb, 0.0), (xb * 0.92, -0.32 * R), (-xb * 0.92, -0.32 * R), (0.0, surfY(0, z)), (xb * 0.6, surfY(xb * 0.6, z)), (-xb * 0.6, surfY(-xb * 0.6, z))]) {
        final q = sp(L(x, y, z));
        if (q != null) cand.add(q);
      }
    }
    cand.sort((a, b) => a.dx != b.dx ? a.dx.compareTo(b.dx) : a.dy.compareTo(b.dy));
    double crs(Offset o2, Offset a2, Offset b2) => (a2.dx - o2.dx) * (b2.dy - o2.dy) - (a2.dy - o2.dy) * (b2.dx - o2.dx);
    final lo = <Offset>[], hi = <Offset>[];
    for (final q in cand) {
      while (lo.length >= 2 && crs(lo[lo.length - 2], lo.last, q) <= 0) {
        lo.removeLast();
      }
      lo.add(q);
    }
    for (final q in cand.reversed) {
      while (hi.length >= 2 && crs(hi[hi.length - 2], hi.last, q) <= 0) {
        hi.removeLast();
      }
      hi.add(q);
    }
    final hull = [...lo..removeLast(), ...hi..removeLast()];
    final head = Path();
    Offset mid(int i) => (hull[i % hull.length] + hull[(i + 1) % hull.length]) / 2;
    head.moveTo(mid(0).dx, mid(0).dy);
    for (var i = 1; i <= hull.length; i++) {
      head.quadraticBezierTo(hull[i % hull.length].dx, hull[i % hull.length].dy, mid(i).dx, mid(i).dy);
    }
    head.close();
    perfParts[0] += lap();
    if (!mask) _hairTufts(canvas, rig, hc3, right, fwd, up, R, ink, sp);
    canvas.drawPath(head, Paint()
      ..color = _ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = ink * 2.2
      ..strokeJoin = StrokeJoin.round);
    canvas.drawPath(head, Paint()..color = shadeC);
    canvas.save();
    canvas.clipPath(head);
    // 光の当たる側（左上）は明るく、反対側に影
    canvas.drawPath(head.shift(Offset(-rr * 0.09, -rr * 0.07)), Paint()..color = skin);
    final capBand = (rig.helmet || mask ? 0.1 : 0.3) * R;
    // つばの影：額の上（帽子のふちの下）
    if (!mask && front > 0) {
      final sh = poly([for (var i = 0; i <= 12; i++) ((-0.85 + 1.7 * i / 12) * R, capBand + 0.02 * R), for (var i = 12; i >= 0; i--) ((-0.8 + 1.6 * i / 12) * R, capBand - (rig.helmet ? 0.08 : 0.16) * R * (1 - 0.4 * ((-1 + 2 * i / 12).abs())))]);
      if (sh != null) canvas.drawPath(sh, Paint()..color = const Color(0x2A000000));
    }
    // ── 帽子の下の髪（パワプロ風：短髪は帽子の下に髪を見せず肌のまま。長いもみあげ・えり足・長髪・アフロだけ描く）──
    //  頭のまわりを角度で回って（正面＝0°、真横＝90°、後ろ＝180°）、帽子のふちから生えぎわまでを塗る。生えぎわは段のないなめらかな線
    final hairC = f.hairStyle == 5 ? Color.lerp(hair, skin, 0.45)! : hair;
    final sbLen = FaceArt.sideburnOf(f); // 0＝もみあげなし
    final nape = switch (f.hairStyle) { 4 => -0.72 * R, 7 => -0.85 * R, 3 => -0.5 * R, _ => 0.0 }; // えり足の下の端（0＝なし）

    V3 around(double th, double z, double sx) {
      final rz = math.sqrt(math.max(0.0, R * R * 1.03 - z * z));
      return L(sx * rz * math.sin(th * deg), rz * math.cos(th * deg), z);
    }

    void band(double sx, double th0, double th1, double Function(double) bottom) {
      final ths = [for (var i = 0; i <= 16; i++) th0 + (th1 - th0) * i / 16];
      final pth = Path();
      final pts3 = [for (final th in ths) around(th, capBand + 0.02 * R, sx), for (final th in ths.reversed) around(th, bottom(th), sx)];
      for (var i = 0; i < pts3.length; i++) {
        final q = sp(pts3[i]);
        if (q == null) return;
        i == 0 ? pth.moveTo(q.dx, q.dy) : pth.lineTo(q.dx, q.dy);
      }
      canvas.drawPath(pth..close(), Paint()..color = hairC);
    }

    for (final sx in [-1.0, 1.0]) {
      if (right.dot(toCam) * sx < 0.12 && front > -0.2) continue; // 向こう側の髪は顔に重なるので描かない（後ろ向きは両方）
      // もみあげ（耳の前の細い帯。幅は頭の半径の約 2 割）
      if (sbLen > 0) band(sx, 74, 96, (th) => capBand + (-sbLen * R - capBand) * (1 - sm((th - 88) / 8)));
      // えり足（耳の後ろから後ろの下へ）
      if (nape < 0) band(sx, 96, 180, (th) => capBand + (nape - capBand) * sm((th - 98) / 40));
    }
    perfParts[1] += lap();
    // ── 顔：選手ごとに前もって描いた顔の画像（FaceArt）を、頭の表面に沿って貼る。
    //  画像を 16×16 のます目に分け、ます目の角を頭の立体の表面（正面から見た位置そのまま、奥行きは表面）に置いて投影し、三角形ごとに画像を貼る。
    //  向こうを向いた三角形は描かない。頭のふちより外の絵は、ふちに寄せてつぶす（見えない）
    if (front > -0.45) {
      final variant = rig.blink > 0.5 ? 1 : (rig.effort > 0.45 ? 2 : 0);
      final img = _faceImage(rig, variant, rr * 2.6);
      if (img != null) {
        final nImg = img.width.toDouble();
        const gn = 16, gw = gn + 1;
        final pos = List<Offset?>.filled(gw * gw, null);
        final w3 = List<V3>.filled(gw * gw, V3.zero);
        for (var j = 0; j <= gn; j++) {
          final z = (R * (1.3 - 2.6 * j / gn)).clamp(-R * chinL * 0.999, R * 0.999);
          final xb = xbAt(z);
          for (var i = 0; i <= gn; i++) {
            final x = (-R * (-1.3 + 2.6 * i / gn)).clamp(-xb, xb); // 画像の右＝キャラクターの左（−right）
            final w = L(x, surfY(x, z) + 0.003 * R, z);
            w3[j * gw + i] = w;
            pos[j * gw + i] = sp(w);
          }
        }
        final sg = right.cross(up).dot(fwd) > 0 ? 1.0 : -1.0; // ます目の並びの三角形の、表向きの向き
        final vp = <Offset>[], vt = <Offset>[];
        Offset tex(int k) => Offset(nImg * (k % gw) / gn, nImg * (k ~/ gw) / gn);
        for (var j = 0; j < gn; j++) {
          for (var i = 0; i < gn; i++) {
            final ia = j * gw + i, ib = ia + 1, ic = ia + gw, id = ic + 1;
            for (final (k0, k1, k2) in [(ia, ib, ic), (ib, id, ic)]) {
              final pa = pos[k0], pb = pos[k1], pc = pos[k2];
              if (pa == null || pb == null || pc == null) continue;
              final n = (w3[k1] - w3[k0]).cross(w3[k2] - w3[k0]);
              if (n.length2 < 1e-14 || n.dot(camW - w3[k0]) * sg <= 0) continue;
              vp
                ..add(pa)
                ..add(pb)
                ..add(pc);
              vt
                ..add(tex(k0))
                ..add(tex(k1))
                ..add(tex(k2));
            }
          }
        }
        if (vp.isNotEmpty) {
          final sh = _faceShaders[img] ??= ImageShader(img, TileMode.clamp, TileMode.clamp, _ident, filterQuality: FilterQuality.medium);
          canvas.drawVertices(ui.Vertices(ui.VertexMode.triangles, vp, textureCoordinates: vt), BlendMode.srcOver, Paint()..shader = sh);
        }
      }
    }
    canvas.restore(); // 顔の切り抜きを戻す
    // 横顔の鼻：パワプロ風の顔は鼻を描かないので出さない（showNose で切り替え）
    if (showNose && rr >= 6 && front > -0.1) {
      final r3 = right.dot(toCam).abs();
      if (r3 > 0.766) {
        final nl = f.noseLen;
        final nz = -0.42 * R - 0.05 * R * (nl - 1);
        final protr = R * (f.noseType == 0 ? 0.08 : 0.12) * f.noseSize * math.sqrt(nl);
        final tip = sp(L(0, surfY(0, nz) + protr, nz + (f.noseType == 3 ? -0.02 * R : 0)));
        final top = sp(sPt(0, (-0.18 * R)));
        final mid = sp(L(0, surfY(0, ((-0.18 * R) + nz) / 2) + protr * (f.noseType == 3 ? 0.75 : 0.45), ((-0.18 * R) + nz) / 2));
        final base = sp(L(0, surfY(0, nz - 0.07 * R) + 0.004, nz - 0.07 * R));
        if (tip != null && top != null && mid != null && base != null) {
          final np = Path()
            ..moveTo(top.dx, top.dy)
            ..quadraticBezierTo(mid.dx, mid.dy, tip.dx, tip.dy)
            ..lineTo(base.dx, base.dy)
            ..close();
          canvas.drawPath(np, Paint()..color = skin);
          canvas.drawPath(
              Path()
                ..moveTo(mid.dx, mid.dy)
                ..quadraticBezierTo(Offset.lerp(mid, tip, 0.6)!.dx, Offset.lerp(mid, tip, 0.6)!.dy, tip.dx, tip.dy)
                ..lineTo(base.dx, base.dy),
              Paint()
                ..color = _ink
                ..style = PaintingStyle.stroke
                ..strokeWidth = ink * 1.1
                ..strokeJoin = StrokeJoin.round
                ..strokeCap = StrokeCap.round);
        }
      }
    }
    // アフロ：帽子の下から横・後ろへふくらむ
    if (f.hairStyle == 3) {
      final hl = Color.lerp(hair, Colors.white, 0.12)!;
      for (final (y, z) in const [(-0.2, 0.22), (-0.55, 0.2), (-0.85, 0.1)]) {
        for (final sx in [-1.0, 1.0]) {
          if (right.dot(toCam) * sx < -0.3) continue;
          final q = sp(L(sx * R * 1.0, y * R, z * R));
          if (q != null) {
            canvas.drawCircle(q, rr * 0.19 + ink, Paint()..color = _ink);
            canvas.drawCircle(q, rr * 0.19, Paint()..color = hair);
            canvas.drawCircle(q - Offset(rr * 0.05, rr * 0.05), rr * 0.07, Paint()..color = hl);
          }
        }
      }
    }
    perfParts[2] += lap();
    // ── 耳：頭の横の立体の位置。横から見ると大きく、正面からは細い。マスク・ヘルメットの耳当ての側は描かない ──
    final flapSide = rig.lefty ? 1.0 : -1.0; // ヘルメットの耳当て：投手側の耳（右打者は左耳＝−x）
    for (final sgn in [-1.0, 1.0]) {
      final visE = right.dot(toCam) * sgn;
      if (!showEars || visE < -0.05 || mask) continue; // パワプロ風の顔は耳を描かない
      if (rig.helmet && sgn == flapSide) continue;
      final e3 = hc3 + right * (sgn * R * 0.98) - up * (R * 0.12) - fwd * (R * 0.06);
      final e = sp(e3), eu = sp(e3 + up * 0.05);
      if (e == null || eu == null) continue;
      final ang = (eu - e).direction + math.pi / 2;
      final ew = rr * 0.25 * f.ear * (0.3 + 0.7 * visE.clamp(0.0, 1.0)), eh = rr * 0.38 * f.ear;
      canvas.save();
      canvas.translate(e.dx, e.dy);
      canvas.rotate(ang);
      final earR = Rect.fromCenter(center: Offset.zero, width: ew, height: eh);
      canvas.drawOval(earR.inflate(ink * 0.6), Paint()..color = _ink);
      canvas.drawOval(earR, Paint()..color = skin);
      if (visE > 0.4) {
        canvas.drawArc(earR.deflate(ew * 0.22), -math.pi * 0.4, math.pi * 1.1, false, Paint()
          ..color = shadeC
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(0.8, ew * 0.14));
      }
      canvas.restore();
    }
    perfParts[3] += lap();
    // ── 帽子・ヘルメット：頭の立体の上に貼る（帯の輪を投影した楕円より上が帽子）──
    final hb = rig.helmet || mask ? 0.12 : 0.30; // 帯の高さ（頭の中心から、半径に対して）
    final ringR = math.sqrt(1 - hb * hb) * 1.05;
    final ring = <Offset>[];
    for (var i = 0; i < 28; i++) {
      final a = 2 * math.pi * i / 28;
      final q = sp(hc3 + up * (R * hb) + (right * math.cos(a) + fwd * math.sin(a)) * (R * ringR));
      if (q != null) ring.add(q);
    }
    final headDisk = Path()..addOval(Rect.fromCircle(center: c, radius: rr * 1.06));
    final capC = Color(mask ? 0xFF1C1F24 : (rig.helmet ? rig.uni.helmet : rig.uni.capBase));
    if (ring.length > 8 && rr < 9) {
      // 小さく写るとき：軽い描き方（頭の上の弧）
      final capPath = Path()..addArc(Rect.fromCircle(center: c, radius: rr * 1.05), upS.direction - 1.25, 2.5);
      capPath.close();
      _blob(canvas, capPath, capC, ink: ink);
    } else if (ring.length > 8) {
      final ringPath = Path()..addPolygon(ring, true);
      var ec = Offset.zero;
      for (final q in ring) {
        ec += q;
      }
      ec = ec / ring.length.toDouble();
      final n = Offset(-upS.dy, upS.dx);
      final half = Path()
        ..addPolygon([ec + n * 1e3, ec + n * 1e3 + upS * 1e3, ec - n * 1e3 + upS * 1e3, ec - n * 1e3], true);
      final crown = Path.combine(PathOperation.intersect, headDisk, Path.combine(PathOperation.union, ringPath, half));
      _blob(canvas, crown, capC, ink: ink);
      // 縫い目（てっぺんから前後へ）とボタン
      final top3 = hc3 + up * (R * 1.05);
      final tp2 = sp(top3);
      if (tp2 != null && !mask) {
        final seam = Paint()
          ..color = Color.lerp(capC, Colors.black, 0.25)!
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(0.7, ink * 0.5);
        for (final dir in [fwd, right, -right]) {
          final pts = <Offset>[];
          for (var j = 0; j <= 6; j++) {
            final th = (math.pi / 2) * j / 6;
            final q = sp(hc3 + up * (R * 1.05 * math.cos(th) * (1 - (1 - hb) * j / 6 * 0)) + dir * (R * 1.05 * math.sin(th)));
            if (q != null) pts.add(q);
          }
          final vis = (dir).dot(toCam) > -0.2;
          if (vis && pts.length > 2) {
            canvas.save();
            canvas.clipPath(crown);
            canvas.drawPath(Path()..addPolygon(pts, false), seam);
            canvas.restore();
          }
        }
        if (up.dot(toCam) > -0.2) canvas.drawCircle(tp2, math.max(1.2, rr * 0.07), Paint()..color = Color.lerp(capC, Colors.black, 0.2)!);
      }
      // つや
      canvas.save();
      canvas.clipPath(crown);
      canvas.drawArc(Rect.fromCircle(center: c, radius: rr * 0.86), upS.direction - 0.9, 0.55, false, Paint()
        ..color = Colors.white.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = rr * 0.08
        ..strokeCap = StrokeCap.round);
      canvas.restore();
    }
    // ヘルメットの耳当て（投手側の耳を覆う）
    if (rig.helmet && !mask) {
      final vis = right.dot(toCam) * flapSide;
      if (vis > -0.1) {
        final e3 = hc3 + right * (flapSide * R * 1.0) - up * (R * 0.12) - fwd * (R * 0.05);
        final e = sp(e3);
        if (e != null) {
          final w = rr * 0.55 * (0.35 + 0.65 * vis.clamp(0.0, 1.0)), h = rr * 0.62;
          canvas.save();
          canvas.translate(e.dx, e.dy);
          canvas.rotate(rot);
          final fr = Rect.fromCenter(center: Offset.zero, width: w, height: h);
          canvas.drawOval(fr.inflate(ink), Paint()..color = _ink);
          canvas.drawOval(fr, Paint()..color = capC);
          canvas.drawOval(Rect.fromCenter(center: Offset(0, -h * 0.05), width: w * 0.35, height: h * 0.3), Paint()..color = Color.lerp(capC, Colors.black, 0.45)!); // 耳の穴
          canvas.restore();
        }
      }
    }
    // つば：帯の前（±75°）から前へ伸びる立体の板。少し下へ反る。横から見れば細く、上から見れば広い。後ろ向きのときは頭に隠れる所を描かない
    if (!mask) {
      final L = R * (rig.helmet ? 0.5 : 0.66);
      final pts = <Offset>[];
      for (var i = 0; i <= 12; i++) {
        final a = -58 + 116 * i / 12;
        final d = fwd * math.cos(a * deg) + right * math.sin(a * deg);
        final q = sp(hc3 + up * (R * (hb - 0.02)) + d * (R * ringR));
        if (q != null) pts.add(q);
      }
      for (var i = 12; i >= 0; i--) {
        final a = -58 + 116 * i / 12;
        final d = fwd * math.cos(a * deg) + right * math.sin(a * deg);
        // つばは前へまっすぐ伸びる板（前のふちは平らに近い弧）。横へは広がらない
        final reach = L * math.pow(math.cos(a * deg), 0.5);
        final q = sp(hc3 + up * (R * (hb - 0.02) - L * 0.12 * math.cos(a * deg)) + d * (R * ringR * 0.97) + fwd * reach);
        if (q != null) pts.add(q);
      }
      if (pts.length > 10) {
        var brim = Path()..addPolygon(pts, true);
        if (front < 0.05 && rr >= 9) brim = Path.combine(PathOperation.difference, brim, headDisk);
        final brimC = Color(rig.helmet ? rig.uni.helmet : rig.uni.capBrim);
        _blob(canvas, brim, brimC, ink: ink * 0.9);
        // つばの下（影）：つばより低い所から見るとき（帽子のつばの裏は暗い）
        final brimC3 = hc3 + up * (R * hb) + fwd * (R * 0.9 + L * 0.4);
        if (up.dot(camW - brimC3) < 0) {
          canvas.save();
          canvas.clipPath(brim);
          canvas.drawRect(brim.getBounds(), Paint()..color = Colors.black.withValues(alpha: 0.32));
          canvas.restore();
        }
      }
    }
    perfParts[4] += lap();
    // 捕手のマスク：顔の前の黒い枠と格子・のど当て（顔の向きに合わせて横に詰める）
    if (mask && front > -0.05) {
      final squeeze = (0.35 + 0.65 * front.clamp(0.0, 1.0));
      final fc = c + faceDir * 0.62;
      canvas.save();
      canvas.translate(fc.dx, fc.dy);
      canvas.rotate(rot);
      canvas.scale(squeeze, 1);
      final frame = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(0, rr * 0.18), width: rr * 1.55, height: rr * 1.75), Radius.circular(rr * 0.55));
      canvas.drawRRect(frame, Paint()
        ..color = const Color(0xFF15171A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(2.0, rr * 0.13));
      final bar = Paint()
        ..color = const Color(0xFF2A2D31)
        ..strokeWidth = math.max(1.4, rr * 0.08)
        ..strokeCap = StrokeCap.round;
      for (final y in [-0.08, 0.22, 0.5]) {
        canvas.drawLine(Offset(-rr * 0.72, rr * y), Offset(rr * 0.72, rr * y), bar);
      }
      for (final x in [-0.22, 0.22]) {
        canvas.drawLine(Offset(rr * x, -rr * 0.08), Offset(rr * x, rr * 0.95), bar);
      }
      // 額とあごのパッド
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(0, -rr * 0.62), width: rr * 1.3, height: rr * 0.24), Radius.circular(rr * 0.1)), Paint()..color = const Color(0xFF1C1F24));
      // のど当て
      final tg = Path()
        ..moveTo(-rr * 0.28, rr * 1.0)
        ..lineTo(rr * 0.28, rr * 1.0)
        ..lineTo(rr * 0.18, rr * 1.42)
        ..lineTo(-rr * 0.18, rr * 1.42)
        ..close();
      _blob(canvas, tg, const Color(0xFF1C1F24), ink: ink * 0.6);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

