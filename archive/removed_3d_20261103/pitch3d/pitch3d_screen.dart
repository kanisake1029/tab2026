import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../../engine/ball_flight.dart';
import '../../engine/ball_spec.dart';
import '../../engine/body_model.dart';
import '../../engine/pitch_engine.dart';
import '../../engine/pitch_motion.dart';
import '../../engine/vec3.dart';
import '../../models/player.dart';
import '../../models/stadium.dart';
import '../../models/uniform.dart';
import 'toon_rig.dart';
import 'poses.dart';
import 'scene_util.dart';
import 'stadium_mesh.dart';

/// 3D の投球を開く（Android）
Future<void> openPitch3D(BuildContext context, Player pitcher, {int teamColor = 0xFF1E3A8A, int oppColor = 0xFFDC2626}) async {
  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => Pitch3DScreen(pitcher: pitcher, teamColor: teamColor, oppColor: oppColor)));
}

class Pitch3DScreen extends StatefulWidget {
  final Player pitcher;
  final int teamColor, oppColor;
  const Pitch3DScreen({super.key, required this.pitcher, required this.teamColor, required this.oppColor});
  @override
  State<Pitch3DScreen> createState() => _Pitch3DScreenState();
}

class _Pitch3DScreenState extends State<Pitch3DScreen> {
  final Scene scene = Scene();
  bool ready = false;
  String? error;
  int cam = 2; // 0 捕手 1 打者 2 中継
  double speed = 1.0;
  bool paused = false;
  double fps = 0;
  int _frames = 0;
  double _acc = 0;

  late PitchMotion motion;
  late BodyModel body;
  late void Function(List<V3>) _posePitcher;
  ToonRig? _pRig; // 投手（手の形＝握りを変える）
  String _pitchName = '';
  V3 _relFix = V3.zero; // 動きの計算のリリース位置と、物理のリリース位置の差（投げた直後になめらかにそろえる）
  late PitcherPhysics phys;
  late Node ball;
  late V3 catcherEye, batterEye;
  bool batRight = true;
  int pitchIdx = 0;
  double t = 0; // 動き始めからの秒
  List<V3> path = const [];
  List<double> pathT = const [];
  V3 omega = V3.zero;
  PitchShot? shot;
  PitchKind? kind;
  final _rand = math.Random();

  Player get p => widget.pitcher;

  @override
  void initState() {
    super.initState();
    Scene.initializeStaticResources().then((_) async {
      try {
        await _build();
        if (mounted) setState(() => ready = true);
      } catch (e, st) {
        debugPrint('$e\n$st');
        if (mounted) setState(() => error = '$e');
      }
    });
  }

  Future<void> _build() async {
    scene.directionalLight = DirectionalLight(direction: vm.Vector3(-0.35, -1.0, 0.45), intensity: 5.5, castsShadow: true, shadowMaxDistance: 45, shadowMapResolution: 2048);
    scene.skybox = Skybox(GradientSkySource(zenithColor: vm.Vector3(0.12, 0.30, 0.64), horizonColor: vm.Vector3(0.74, 0.83, 0.94)));
    scene.toneMapping = ToneMappingMode.pbrNeutral; // 色の濃さ（彩度）を保つ
    scene.environmentIntensity = 0.55; // 空からの回り込む光を抑えて、かすみを取る
    for (final n in StadiumMesh(Stadium.current, fill: 0.75, homeColor: widget.teamColor, awayColor: widget.oppColor).build()) {
      n.castsShadows = false; // 影を落とすのは人とボールだけ（球場の形は影の計算から外して軽くする）
      scene.add(n);
    }
    // 投手・捕手・打者：MPFB の人体（読めなければ簡単な体）
    body = BodyModel.ofPlayer(p);
    final lefty = p.throws == 'L';
    phys = PitcherPhysics.of(p);
    final uni = Uniform.basic(widget.teamColor);
    final away = Uniform.basic(widget.oppColor, home: false);
    final cb0 = BodyModel.of(heightCm: 178, weightKg: 86, armCm: 79), bb0 = BodyModel.of(heightCm: 181, weightKg: 85, armCm: 80);
    batRight = _rand.nextBool();
    // デフォルメした人（約5.7頭身。顔は部品の組み合わせ、指の関節あり）
    final rig = ToonRig(FaceLook.ofPlayer(p), uni, real: body, lefty: lefty);
    _pRig = rig;
    body = rig.body;
    motion = PitchMotion(body, p.form, armAngleDeg: p.spinAxis, lefty: lefty, velocity: p.velocity);
    rig.pose(motion.poseAt(0));
    _posePitcher = rig.pose;
    scene.add(rig.root);
    final catcher = ToonRig(FaceLook.of('catcher${p.id}'), uni, real: cb0);
    catcher.pose(StaticPoses.catcher(catcher.body));
    scene.add(catcher.root);
    catcherEye = StaticPoses.catcherEye(catcher.body);
    final batter = ToonRig(FaceLook.of('batter${p.id}', foreign: _rand.nextBool()), away, real: bb0, lefty: !batRight, glove: false, helmet: true);
    batter.handT = HandPose.fist;
    batter.handG = HandPose.fist;
    final bp = StaticPoses.batter(batter.body, right: batRight);
    batter.pose(bp);
    scene.add(batter.root);
    batterEye = StaticPoses.batterEye(batter.body, right: batRight);
    _bat(bp);
    _relFix = motion.release.pos - phys.normal.pos;
    // ボール（周囲23cm）と縫い目
    ball = nd(mesh: Mesh(SphereGeometry(radius: BallSpec.radius, segments: 28, rings: 18), mat(0xFFF6F4EC, rough: 0.5)));
    final seam = ColorMesh()..color(0xFFC81E1E);
    const n = 160;
    for (var i = 0; i < n; i++) {
      final a = BallSpec.seamPoint(2 * math.pi * i / n), b = BallSpec.seamPoint(2 * math.pi * (i + 1) / n);
      final tan = (b - a).unit;
      final side = a.cross(tan).unit * (BallSpec.seamWidth / 2 / BallSpec.radius);
      final r = 1 + BallSpec.seamHeight / BallSpec.radius;
      V3 q(V3 v) => v.unit * (BallSpec.radius * r);
      // 縫い目の帯（ボールの中心基準。sv で 3D の向きへ）
      seam.quad(q(a - side), q(b - side), q(b + side), q(a + side));
    }
    for (final s in seam.nodes(mat(0xFFC81E1E, rough: 0.7)..doubleSided = true)) {
      ball.add(s);
    }
    scene.add(ball);
    _newPitch();
  }


  void _bat(List<V3> pose) {
    final hands = pose[J.wristT.index];
    final s = batRight ? -1.0 : 1.0;
    final dir = V3(s * 0.25, -0.35, 0.9).unit;
    final c = hands + dir * 0.42;
    final m = Mesh(CylinderGeometry(bottomRadius: 0.018, topRadius: 0.033, height: 0.84, radialSegments: 16), mat(0xFF8B5A2B, rough: 0.5));
    final up = vm.Vector3(0, 1, 0), d = sv(dir);
    final q = vm.Quaternion.fromTwoVectors(up, d);
    scene.add(nd(mesh: m, position: sv(c), rotation: q));
  }

  /// 次の1球：持ち球から選び、ゾーンのどこかを狙って投げる（制球のばらつきつき）
  void _newPitch() {
    final ps = p.pitches.isEmpty ? [Player.fielderStraight(p.velocity)] : p.pitches;
    final pc = ps[pitchIdx % ps.length];
    kind = phys.kind(pc);
    _pitchName = pc.name;
    final k = kind!;
    double g() => math.sqrt(-2 * math.log(1 - _rand.nextDouble())) * math.cos(2 * math.pi * _rand.nextDouble());
    final sigma = 0.12 + (100 - p.control) * 0.0065;
    shot = k.throwAt((_rand.nextDouble() - 0.5) * 1.6, (_rand.nextDouble() - 0.5) * 1.6, speedKmh: pc.speed.toDouble(), sigma: sigma, gauss: g);
    final s = shot!;
    omega = k.spin.omega * s.spinScale;
    final f = BallFlight.fly(k.release, BallFlight.dirOf(s.yaw, s.pitch) * s.speed, omega, seam: k.spin.seam, seamOrient: k.spin.seamOrient, keepPath: true, pathEvery: 1, dt: 0.002);
    path = f.path;
    pathT = f.pathT;
    t = 0;
  }

  double get _endT => motion.ph.br + (pathT.isEmpty ? 0.5 : pathT.last) + 0.9;

  V3 _ballAt(double tau) {
    if (path.isEmpty) return V3.zero;
    if (tau >= pathT.last) return path.last;
    var i = 0;
    while (i + 1 < pathT.length && pathT[i + 1] < tau) {
      i++;
    }
    final f = (tau - pathT[i]) / (pathT[i + 1] - pathT[i]);
    return path[i].lerp(path[i + 1], f);
  }

  void _tick(Duration elapsed, double dt) {
    _frames++;
    _acc += dt;
    if (_acc >= 1.0) {
      fps = _frames / _acc;
      _frames = 0;
      _acc = 0;
      if (mounted) setState(() {});
    }
    if (!paused) t += dt * speed;
    if (t > _endT) {
      pitchIdx++;
      _newPitch();
      if (mounted) setState(() {});
    }
    final mt = math.min(t, motion.ph.end);
    final pose = motion.poseAt(mt);
    // 握り：投げるまでは球種の握り、離した直後は開き、そのあと力を抜く
    final rg = _pRig;
    if (rg != null) {
      if (mt < motion.ph.br) {
        rg.holdBall(PitchGrip.ofPitch(_pitchName)); // 球種の握りで、指をボールに沿わせる（仕様書 2.2 ②）
      } else {
        rg.holdBall(null);
        rg.handT = mt < motion.ph.br + 0.25 ? HandPose.open : HandPose.relaxed;
      }
    }
    _posePitcher(pose);
    final tau = t - motion.ph.br;
    if (tau < 0) {
      ball.position = sv(rg?.ballPoint ?? pose[J.ball.index]); // 握った指の中（体を動かしたあとの同じコマ）
      ball.rotation = vm.Quaternion.identity();
    } else {
      ball.position = sv(_ballAt(tau) + _relFix * math.max(0.0, 1 - tau / 0.08));
      final w = sv(omega);
      final wl = w.length;
      if (wl > 0) ball.rotation = vm.Quaternion.axisAngle(w / wl, wl * math.min(tau, pathT.isEmpty ? 0 : pathT.last));
    }
  }

  Camera _camera() {
    switch (cam) {
      case 0:
        return PerspectiveCamera(position: sv(catcherEye), target: svXYZ(0, 17.5, 1.3), fovRadiansY: 30 * vm.degrees2Radians);
      case 1:
        return PerspectiveCamera(position: sv(batterEye), target: svXYZ(0, 17.5, 1.45), fovRadiansY: 36 * vm.degrees2Radians);
      default:
        return PerspectiveCamera(position: svXYZ(-1.9, 42, 4.6), target: svXYZ(0, 0.2, 1.0), fovRadiansY: 11.5 * vm.degrees2Radians);
    }
  }

  @override
  Widget build(BuildContext context) {
    final k = kind, s = shot;
    final rel = phys.normal;
    const ts = TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700, shadows: [Shadow(blurRadius: 3)]);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: Text('${p.registeredName}　3D 投球'), backgroundColor: Colors.black, foregroundColor: Colors.white),
      body: Stack(children: [
        // 3D の描画は左手系なので、本塁基準の座標を写すと左右が逆になる。画面ごと左右を反転する
        if (ready) Positioned.fill(child: Transform.flip(flipX: true, child: SceneView(scene, cameraBuilder: (_) => _camera(), onTick: _tick))),
        if (!ready && error == null) const Center(child: CircularProgressIndicator()),
        if (error != null) Center(child: Padding(padding: const EdgeInsets.all(20), child: Text('3D を表示できませんでした\n$error', style: const TextStyle(color: Colors.white)))),
        if (ready && k != null && s != null)
          Positioned(
            left: 8,
            top: 8,
            right: 8,
            child: Text(
              '${k.spin.name}　${(s.speed * 3.6).round()}km/h　${k.spin.rpm.round()}rpm・${k.spin.clockText}・効率${(k.spin.efficiency * 100).round()}%\n'
              '変化 縦${k.spin.moveV.round()}cm 横${k.spin.moveH.round()}cm　到達 ${(s.time).toStringAsFixed(2)}秒　'
              'リリース 高さ${rel.height.toStringAsFixed(2)}m 前へ${rel.extension.toStringAsFixed(2)}m　'
              '${s.x.abs() <= 1 && s.z.abs() <= 1 ? 'ストライク' : 'ボール'}\n'
              'fps ${fps.toStringAsFixed(0)}　${const ['捕手目線', '打者目線', '中継'][cam]}　${speed == 1 ? '等速' : 'スロー×1/4'}',
              style: ts,
            ),
          ),
        Positioned(
          bottom: 16,
          left: 0,
          right: 0,
          child: Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: [
            for (var i = 0; i < 3; i++)
              FilledButton.tonal(onPressed: () => setState(() => cam = i), style: FilledButton.styleFrom(backgroundColor: cam == i ? Colors.amber : null), child: Text(const ['捕手', '打者', '中継'][i])),
            FilledButton.tonal(onPressed: () => setState(() => speed = speed == 1 ? 0.25 : 1), child: Text(speed == 1 ? 'スロー' : '等速')),
            FilledButton.tonal(onPressed: () => setState(() => t = 0), child: const Text('もう一度')),
            FilledButton.tonal(
                onPressed: () => setState(() {
                      pitchIdx++;
                      _newPitch();
                    }),
                child: const Text('次の球')),
            FilledButton.tonal(onPressed: () => setState(() => paused = !paused), child: Text(paused ? '再生' : '一時停止')),
          ]),
        ),
      ]),
    );
  }
}
