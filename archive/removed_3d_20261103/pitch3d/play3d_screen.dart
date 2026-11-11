import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../../engine/ball_flight.dart';
import '../../engine/ball_spec.dart';
import '../../engine/base_path.dart';
import '../../engine/field_time.dart';
import '../../engine/body_model.dart';
import '../../engine/defense_ai.dart';
import '../../engine/human/gait.dart';
import '../../engine/human/human_body.dart';
import '../../engine/match_simulator.dart';
import '../../engine/pitch_motion.dart';
import '../../engine/play_motion.dart';
import '../../engine/play_resolver.dart';
import '../../engine/vec3.dart';
import '../../models/equipment.dart';
import '../../models/player.dart';
import '../../models/stadium.dart';
import '../../models/uniform.dart';
import 'puppet2d.dart';
import 'toon_rig.dart';
import 'poses.dart';
import 'scene_util.dart';
import 'stadium_mesh.dart';
import 'board_art.dart';
import 'stadium_overlay.dart';

/// 3D でプレーを見る（Android）：投球 → スイング → 打球 → 9人の守備（役割どおり）→ 送球・中継 → 走者
///  plays：1球ずつ（PitchEvent）。左右の矢印で前後の球へ
Future<void> openPlay3D(BuildContext context, List<PitchEvent> plays, {int index = -1, int homeColor = 0xFF1E3A8A, int awayColor = 0xFFDC2626, List<String> sponsors = const []}) async {
  // 全球：打球（軌跡あり）と、物理で投げた球（見逃し・空振り・ボール・ファウル）
  final list = plays.where((e) => e.fielderPlayers.isNotEmpty && (e.path.isNotEmpty || e.phys != null)).toList();
  if (list.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('3D で見られる投球がまだありません')));
    return;
  }
  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => Play3DScreen(plays: list, index: index < 0 ? list.length - 1 : index.clamp(0, list.length - 1), homeColor: homeColor, awayColor: awayColor, sponsors: sponsors)));
}

class Play3DScreen extends StatefulWidget {
  final List<PitchEvent> plays;
  final int index;
  final int homeColor, awayColor;
  const Play3DScreen({super.key, required this.plays, required this.index, required this.homeColor, required this.awayColor, this.sponsors = const []});
  final List<String> sponsors; // ホーム球団と契約しているスポンサー（球場の広告に出す）
  @override
  State<Play3DScreen> createState() => _Play3DScreenState();
}

/// 3D の人（体・動かし方・グラブ）
class _Actor {
  final Node root;
  final void Function(List<V3>) pose;
  PlayerRig? toon; // 体（2.5D：切り絵の 2D 人形）
  final Poser poser;
  final BodyModel body;
  final Node glove;
  double phase = 0;
  V3? last;
  String kind = ''; // いまの動き
  double kindT = 0; // その動きに切り替わった時刻
  List<V3>? shown; // いま見せている姿勢（関節の位置）
  final HumanPd pd = HumanPd(); // Layer 1：関節の PD 制御（重さ・惰性）
  late final Gait gait = Gait(body, sT: poser.lefty ? -1 : 1); // Layer 1：接地の拘束つきの走り
  HumanPose? q; // いま見せている関節の角度
  HumanOut? out;
  double lastT = double.nan;
  _Actor(this.root, this.pose, this.poser, this.body, this.glove);
}

/// 時刻つきの移動（t0 に p0 を出て t1 に p1 に着く）
class _Seg {
  final double t0, t1;
  final V3 p0, p1;
  const _Seg(this.t0, this.t1, this.p0, this.p1);
}

const _roles = ['P', 'C', '1B', '2B', '3B', 'SS', 'LF', 'CF', 'RF'];
const _bases = [V3(0, 0, 0), V3(19.4, 19.4, 0), V3(0, 38.8, 0), V3(-19.4, 19.4, 0), V3(0, 0, 0)];
const _dutyName = {
  Duty.primary: '捕球',
  Duty.secondary: '打球カバー',
  Duty.cover1B: '一塁カバー',
  Duty.cover2B: '二塁カバー',
  Duty.cover3B: '三塁カバー',
  Duty.coverHome: '本塁カバー',
  Duty.cutoff: '中継',
  Duty.trailer: '第2中継',
  Duty.throwBackup: '送球カバー',
  Duty.idle: '待機',
};

class _Play3DScreenState extends State<Play3DScreen> {
  final Scene scene = Scene();
  bool ready = false, loading = true;
  String? error;
  late int idx = widget.index;
  bool _boardCam = false;
  int cam = 0; // 0 自動、1〜7 定位置（camNames）
  // 見せる球場（初めはその試合の球場。改修した本拠地（テラス・フェンス・芝）は一覧にないので −1 でそのまま見せる）
  late int stadiumIdx = Stadium.viewChoices.indexWhere((s) => s.id == widget.plays[widget.index].stadiumId);
  Stadium get _st => stadiumIdx < 0 ? Stadium.byId(widget.plays[widget.index].stadiumId) : Stadium.viewChoices[stadiumIdx];
  final List<Node> _stadiumNodes = [];
  double speed = 1.0;
  bool paused = false;
  bool shadows = true;
  bool detail = false; // 役割などの詳しい表示
  double fps = 0;
  int _frames = 0;
  double _acc = 0;

  final Map<String, _Actor> _cache = {};
  final Map<String, _Actor> actors = {}; // 'P'…'RF'・'B'（打者）・'R1'〜'R3'（走者）・'U'（球審）
  late Node ball, bat;

  // ---- いまのプレー ----
  PitchEvent get ev => widget.plays[idx];
  double t = 0; // 打った瞬間＝0
  double tStart = -2.5, tEnd = 6;
  // 投球
  PitchMotion? motion;
  double pitchPre = 0; // 動き始め → 打った瞬間
  List<V3> pPath = const [];
  List<double> pPathT = const [];
  V3 relFix = V3.zero;
  V3? _relHand; // 放した瞬間の手（ボール）の位置
  V3 _hitFix = V3.zero;
  V3 _contact = const V3(0, 0.5, 0.9); // バットに当たる点
  double pHit = 0.4; // 放してからバットに当たる点まで（秒）

  /// 投球がバットに当たる点（本塁の前縁の少し前）を通る時刻
  double _hitTime() {
    for (var i = 1; i < pPath.length; i++) {
      if (pPath[i].y <= MatchSimulator.contactY) {
        final a = pPath[i - 1], b = pPath[i];
        final f = (a.y - MatchSimulator.contactY) / math.max(1e-6, a.y - b.y);
        return pPathT[i - 1] + (pPathT[i] - pPathT[i - 1]) * f;
      }
    }
    return pPathT.isEmpty ? 0.4 : pPathT.last;
  }
  // 打球
  List<V3> bPath = const [];
  double flight = 0;
  // 動き
  final Map<String, List<_Seg>> segs = {};
  final List<({String from, String to, ThrowLeg leg})> legs = [];
  bool groundPlay = false;
  bool homeRun = false;
  // 打球にならない1球（見逃し・空振り・ボール・ファウル）：捕手が捕って、投手へ返す
  bool noPlay = false, _foul = false, _swing = false;
  double _tCatch = 0.5, _retT0 = 1.5, _retT1 = 2.3; // 捕る・返球を放す・投手が受ける（打った瞬間＝0 からの秒）
  V3 _catchPt = const V3(-0.02, -0.15, 0.78), _foulV = V3.zero, _pSpot = const V3(0, 17.6, 0.25);
  // 盗塁：走者の動き・送球（捕手→ベースに入る野手）・タッチ
  bool _steal = false;
  final List<RunMove> _stealMoves = [];
  String _cover = '2B';
  double _stealRel = 0, _stealArr = 0;
  V3 _stealBase = V3.zero;
  double _foulHitT = 99;
  V3 _foulHitP = V3.zero;
  bool _foulOver = false;

  @override
  void initState() {
    super.initState();
    Scene.initializeStaticResources().then((_) async {
      try {
        await _buildStatic();
        await _load();
        if (mounted) setState(() => ready = true);
      } catch (e, st) {
        debugPrint('$e\n$st');
        if (mounted) setState(() => error = '$e');
      }
    });
  }

  Future<void> _buildStatic() async {
    scene.directionalLight = DirectionalLight(direction: vm.Vector3(-0.35, -1.0, 0.45), intensity: 5.5); // 球場は光を色に焼き込んである（stadium_mesh）。影は 2D で描くので影の計算はしない
    scene.skybox = Skybox(GradientSkySource(zenithColor: vm.Vector3(0.12, 0.30, 0.64), horizonColor: vm.Vector3(0.74, 0.83, 0.94)));
    scene.toneMapping = ToneMappingMode.pbrNeutral;
    scene.environmentIntensity = 0.55;
    _buildStadium();
    ball = nd(mesh: Mesh(SphereGeometry(radius: BallSpec.radius, segments: 18, rings: 12), mat(0xFFF6F4EC, rough: 0.5))); // 実物の大きさ（遠いカメラでは拡大して描く）
    // ボールとバットは 2D の人形と一緒に画面の上に描く（3D の場面には置かない）
    bat = nd(mesh: Mesh(CylinderGeometry(bottomRadius: 0.018, topRadius: 0.033, height: 0.84, radialSegments: 12), mat(0xFF8B5A2B, rough: 0.5)));
  }

  /// 球場の 3D を（作り直して）置く
  void _buildStadium() {
    for (final n in _stadiumNodes) {
      scene.remove(n);
    }
    _stadiumNodes.clear();
    for (final n in StadiumMesh(_st, fill: 0.75, homeColor: widget.homeColor, awayColor: widget.awayColor).build()) {
      n.castsShadows = false;
      scene.add(n);
      _stadiumNodes.add(n);
    }
  }

  /// 選手の 3D の体（同じ選手・同じユニフォームは使い回す）
  Future<_Actor> _actor(Player? p, String fallbackId, int color, {bool home = true, bool? lefty, bool withGlove = true, bool helmet = false}) async {
    final lf = lefty ?? (p?.throws == 'L');
    final key = '${p?.id ?? fallbackId}|$color|$lf|$withGlove|$helmet';
    final c = _cache[key];
    if (c != null) return c;
    await Future<void>.delayed(Duration.zero); // 画面を止めない
    final uni = Uniform.basic(color, home: home);
    final base = p != null ? BodyModel.ofPlayer(p) : BodyModel.of(heightCm: 180, weightKg: 84, armCm: 80);
    final glove = Node(); // グラブは人の形に含まれる（位置だけ覚えておく）
    final face = p != null ? FaceLook.ofPlayer(p) : FaceLook.of(fallbackId);
    // 2.5D：3D の形は作らず、関節を Layer 1 で計算して画面の上に 2D の人形で描く
    final (bulk, slim) = p != null ? PuppetRig.buildOf(heightCm: p.height, weightKg: p.weight, power: p.isPitcher ? p.pitchPower : p.power, run: p.run) : (0.0, 0.0);
    final rig = PuppetRig(face, uni, real: base, lefty: lf, glove: withGlove, helmet: helmet, bulk: bulk, slim: slim)..number = p == null ? '' : (p.uniformNumber < 0 ? '00' : '${p.uniformNumber}')
      ..teamText = fallbackId == 'umpire' ? '' : (home ? ev.homeName : ev.awayName);
    if (p != null) {
      // 用具の見た目（選手ごと）
      final bt = p.bat, gl = p.glove;
      rig.batColor = bt.colors.$1;
      rig.batTipColor = bt.colors.$2;
      rig.batLogo = makerColors[bt.maker] ?? 0xFF1D4ED8;
      rig.gloveColor = gl.colorArgb;
      rig.laceColor = gl.laceArgb;
      rig.web = gl.web;
      rig.gloveLogo = makerColors[gl.maker] ?? 0xFF1D4ED8;
    }
    final a = _Actor(rig.root, rig.pose, Poser(rig.body, lefty: lf), rig.body, glove)..toon = rig;
    _cache[key] = a;
    return a;
  }

  /// プレーを組み立てる（人をそろえ、動きの予定を作る）
  final Set<Node> _added = {}; // 場面に置いている人・グラブ

  void _put(Node n) {
    if (_added.add(n)) scene.add(n);
  }

  /// プレーを組み立てる（読み込みの失敗は画面に出す）
  Future<void> _load() async {
    setState(() => loading = true);
    try {
      await _loadInner();
      _prefetch(idx + 1);
    } catch (e, st) {
      debugPrint('$e $st');
      if (mounted) setState(() => error = '$e');
    }
  }

  /// 次のプレーの人を先に作っておく（「次」をすぐ開けるように）
  Future<void> _prefetch(int i) async {
    if (i >= widget.plays.length) return;
    final e = widget.plays[i];
    final defHome = !e.battingHome;
    final defColor = defHome ? widget.homeColor : widget.awayColor, offColor = defHome ? widget.awayColor : widget.homeColor;
    for (final r in _roles) {
      if (!mounted || loading) return;
      await _actor(e.fielderPlayers[r], 'f$r', defColor, home: defHome);
    }
    final batRight = e.batterHand == 'S' ? true : e.batterHand != 'L';
    if (mounted && !loading) await _actor(e.batterPlayer, 'bat', offColor, home: !defHome, lefty: !batRight, withGlove: false, helmet: true);
    for (var k = 0; k < 3 && mounted && !loading; k++) {
      final rp = e.runnerPlayers.length > k ? e.runnerPlayers[k] : null;
      if (rp != null) await _actor(rp, 'run$k', offColor, home: !defHome, withGlove: false, helmet: true);
    }
  }

  Future<void> _loadInner() async {
    for (final n in _added) {
      scene.remove(n);
    }
    _added.clear();
    actors.clear();
    final e = ev;
    final defHome = !e.battingHome;
    final defColor = defHome ? widget.homeColor : widget.awayColor, offColor = defHome ? widget.awayColor : widget.homeColor;
    for (final r in _roles) {
      actors[r] = await _actor(e.fielderPlayers[r], 'f$r', defColor, home: defHome);
    }
    final batRight = e.batterHand == 'S' ? true : e.batterHand != 'L';
    actors['B'] = await _actor(e.batterPlayer, 'bat', offColor, home: !defHome, lefty: !batRight, withGlove: false, helmet: true);
    for (var i = 0; i < 3; i++) {
      final rp = e.runnerPlayers.length > i ? e.runnerPlayers[i] : null;
      final occ = e.stealFrom > 0 ? rp != null : (rp != null || (e.basesBefore.length > i && e.basesBefore[i]));
      if (occ) actors['R${i + 1}'] = await _actor(rp, 'run$i', offColor, home: !defHome, withGlove: false, helmet: true);
    }
    actors['U'] = await _actor(null, 'umpire', 0xFF1F2937, home: false, withGlove: false);
    for (final a in actors.values) {
      _put(a.root);
    }
    for (final r in _roles) {
      _put(actors[r]!.glove);
    }
    _plan();
    t = tStart;
    if (mounted) setState(() => loading = false);
  }

  // ───────── 動きの予定 ─────────
  void _plan() {
    final e = ev;
    segs.clear();
    _plans.clear();
    _camReset = true; // 新しいプレー：カメラはすぐ合わせる
    legs.clear();
    // 投球：投手の動き（体に合わせて）と、物理で飛ばした球の通り道
    final pp = e.fielderPlayers['P'];
    final pa = actors['P']!;
    motion = null;
    _relHand = null;
    pPath = const [];
    if (pp != null) {
      final mo = PitchMotion(pa.body, pp.form, armAngleDeg: pp.spinAxis, lefty: pp.throws == 'L', velocity: pp.velocity);
      motion = mo;
      final k = e.phys, s = e.shot;
      if (k != null && s != null) {
        final f = BallFlight.fly(k.release, BallFlight.dirOf(s.yaw, s.pitch) * s.speed, k.spin.omega * s.spinScale, seam: k.spin.seam, seamOrient: k.spin.seamOrient, keepPath: true, pathEvery: 5, dt: 0.002);
        pPath = f.path;
        pPathT = f.pathT;
        relFix = mo.release.pos - k.release;
      } else {
        final rel = mo.release.pos;
        final tt = 18.0 / (e.speed / 3.6);
        pPath = [rel, const V3(0, 0.3, 0.8)];
        pPathT = [0, tt];
        relFix = V3.zero;
      }
      pHit = _hitTime();
      pitchPre = mo.ph.br + pHit;
    } else {
      pitchPre = 0.5;
    }
    tStart = -pitchPre - 0.3;
    // 打球：保存した点を、滞空時間に均等に並べる
    bPath = [for (final q in e.path) V3(q[0], q[1], q[2])];
    // バットに当たる点＝投球が来た点。打球は、その点から出て記録の道筋へなめらかに移る（試合の計算の出発点は本塁上 1m）
    _hitFix = V3.zero;
    _contact = pPath.length > 1 ? _ballPitch(pHit) : (bPath.isNotEmpty ? bPath.first : const V3(0, 0.5, 0.9));
    flight = e.flightTime <= 0 ? 1.0 : e.flightTime;
    homeRun = e.outcome == 'ホームラン';
    noPlay = e.result != 'インプレー' && e.path.isEmpty;
    _foul = noPlay && e.result == 'ファウル';
    _swing = noPlay && (e.result == '空振り' || _foul);
    if (noPlay) {
      // 捕手のミットに届く時刻と場所（投球の物理の道筋が y=-0.15 を通る所）
      var tau = pPathT.isEmpty ? pHit + 0.05 : pPathT.last;
      var found = false;
      for (var i = 1; i < pPath.length; i++) {
        if (pPath[i].y <= -0.15) {
          final a = pPath[i - 1], b = pPath[i];
          final fr = (a.y + 0.15) / math.max(1e-6, a.y - b.y);
          tau = pPathT[i - 1] + (pPathT[i] - pPathT[i - 1]) * fr;
          found = true;
          break;
        }
      }
      if (!found && pPath.length >= 2) {
        // 道筋が本塁の上で終わっている：最後の速さでミット（y=−0.15）まで延ばす
        final n = pPath.length;
        final vy = (pPath[n - 1].y - pPath[n - 2].y) / math.max(1e-4, pPathT[n - 1] - pPathT[n - 2]);
        if (vy < -1) tau = pPathT.last + (pPath.last.y + 0.15) / -vy;
      }
      _tCatch = tau - pHit;
      final cp = _ballPitch(tau);
      _catchPt = V3(cp.x.clamp(-0.7, 0.7), -0.15, cp.z.clamp(0.25, 1.45));
      _retT0 = _tCatch + 1.1;
      _retT1 = _retT0 + 0.8;
      // ファウル：後ろのネット・一塁側・三塁側のどれかへ（同じ1球はいつも同じ）
      final k = (e.paIndex * 7 + e.pitchNo * 3) % 4;
      _foulV = const [V3(2, -21, 16), V3(-3, -19, 19), V3(16, 13, 10), V3(-16, 13, 10)][k];
      // ネットに当たる所：ネットの高さより下なら当たって落ちる、上なら越えて客席に落ちる
      _foulHitT = 99;
      _foulOver = false;
      for (var u = 0.02; u < 2.6; u += 0.01) {
        final p = _contact + _foulV * u + V3(0, 0, -4.9 * u * u);
        if (p.z < 0) break;
        if (_st.pastFoulWall(p.x, p.y)) {
          _foulHitT = u;
          _foulHitP = p;
          _foulOver = p.z > _st.netTop(p.x, p.y);
          break;
        }
      }
      flight = _tCatch;
    }
    groundPlay = e.contact == 'ゴロ' || (e.launch ?? 20) < 10;
    final start = <String, V3>{for (final r in _roles) r: _startOf(r)};
    // 野手の移動：捕る野手は打球の処理地点へ、ほかは役割の目標へ
    final plan = e.defense;
    for (final r in _roles) {
      final s0 = start[r]!;
      final list = <_Seg>[];
      if (r == e.fielder && bPath.isNotEmpty) {
        final c = V3(bPath.last.x, bPath.last.y, 0);
        final leg0 = e.throwLegs.isNotEmpty ? e.throwLegs.first : null;
        final toHome = V3(-c.x, -c.y, 0).length > 0.1 ? V3(-c.x, -c.y, 0).unit : const V3(0, -1, 0);
        // 余裕がある打球は、立って待たずに一度下がってから前へ出て捕る（勢いをつけて送球へ）
        final reach = 0.3 + s0.distanceTo(c) / 6.5;
        if (leg0 != null && reach < flight - 1.0) {
          final back = c - toHome * (groundPlay ? 1.4 : 2.0);
          list.add(_Seg(0.3, flight - 0.95, s0, back));
          list.add(_Seg(flight - 0.95, flight, back, c));
        } else {
          list.add(_Seg(0.3, math.max(0.5, flight - 0.05), s0, c));
        }
        // 捕ってから投げるまで：送球先へのステップ（握り替えをしながら）。止まって待たない
        if (leg0 != null) {
          final outF = const {'LF', 'CF', 'RF'}.contains(r);
          final wind = leg0.t0 - 0.6 * (outF ? 1.1 : 0.85);
          if (wind - flight > 0.12) {
            final dir = (V3(leg0.x1, leg0.y1, 0) - c);
            final step = math.min(outF ? 3.5 : 2.4, (wind - flight) * (outF ? 3.0 : 2.2));
            if (dir.length > 1) list.add(_Seg(flight + 0.04, wind, c, c + dir.unit * step));
          }
        }
      } else {
        final d = plan?.duties[r];
        if (d != null && (d.tx - s0.x).abs() + (d.ty - s0.y).abs() > 1.0) {
          final tgt = V3(d.tx, d.ty, 0);
          final arrive = d.tArrive.isFinite ? math.max(0.6, d.tArrive) : 0.3 + s0.distanceTo(tgt) / 7.0;
          list.add(_Seg(0.3, arrive, s0, tgt));
        }
      }
      if (homeRun && const {'LF', 'CF', 'RF'}.contains(r)) list.clear(); // 見送る
      segs[r] = list;
    }
    // 同じ所に2人が重ならないように、あとから来る野手は2m ずらす（捕った野手はそのまま）
    for (final r in _roles) {
      final l = segs[r]!;
      if (l.isEmpty || r == e.fielder) continue;
      final mine = l.last.p1;
      for (final o in _roles) {
        if (o == r) continue;
        final other = (segs[o]!.isEmpty ? start[o]! : segs[o]!.last.p1);
        if (other.distanceTo(mine) < 1.6) {
          var away = (mine - other);
          if (away.length < 0.1) away = V3(-mine.y, mine.x, 0);
          l[l.length - 1] = _Seg(l.last.t0, l.last.t1, l.last.p0, other + away.unit * 2.0);
          break;
        }
      }
    }
    // 送球：投げる人（いま近くにいる野手）と受ける人
    String holder = e.fielder;
    for (final leg in e.throwLegs) {
      final p1 = V3(leg.x1, leg.y1, 0);
      final from = _nearest(V3(leg.x0, leg.y0, 0), leg.t0, exclude: null, prefer: holder);
      final p0 = _posAt(from, leg.t0); // 投げる人の実際の位置（ステップで前へ出ている）
      final to = _nearest(p1, leg.t1, exclude: from);
      // 受ける人は、届くまでにその点へ
      final cur = _posAt(to, leg.t0);
      if (cur.distanceTo(p1) > 0.8) segs[to]!.add(_Seg(leg.t0, math.max(leg.t0 + 0.2, leg.t1 - 0.1), cur, p1));
      legs.add((from: from, to: to, leg: leg));
      // 投げたあとは投げた向きへ 2歩ほど流れて止まる（仕様書 5.3）
      final fwd = (p1 - p0).unit;
      segs[from]!.add(_Seg(leg.t0, leg.t0 + 0.7, p0, p0 + fwd * 1.6));
      holder = to;
    }
    // 自分でベースを踏んでアウト（3A など）：捕った野手がその塁へ走る
    if (legs.isEmpty && e.fielder.isNotEmpty && !const {'LF', 'CF', 'RF'}.contains(e.fielder) && bPath.isNotEmpty) {
      for (final mv in e.runMoves) {
        if (!mv.out || mv.to < 1 || mv.to > 3) continue;
        final from = V3(bPath.last.x, bPath.last.y, 0), base = _bases[mv.to];
        if (from.distanceTo(base) > 0.8) segs[e.fielder]!.add(_Seg(flight + 0.15, math.max(flight + 0.4, mv.t1 - 0.05), from, base));
        break;
      }
    }
    tEnd = math.max(flight, legs.isEmpty ? 0 : legs.last.leg.t1) + 1.6;
    for (final m in e.runMoves) {
      tEnd = math.max(tEnd, m.t1 + 1.0);
    }
    tEnd = math.min(tEnd, homeRun ? 28.0 : 14.0); // 本塁打は一周（約20秒）を見せる
    _steal = false;
    _cHand = null;
    _stealMoves.clear();
    if (noPlay) {
      segs.updateAll((k, v) => <_Seg>[]);
      legs.clear();
      tEnd = _foul ? 2.6 : _retT1 + 0.9;
      if (e.stealFrom > 0 && !_foul) {
        // 盗塁：投手が動き出したらスタート。捕手は捕ってすぐ立ち上がって投げる。成否は試合の計算のとおり
        _steal = true;
        final from = e.stealFrom;
        final r = e.runnerPlayers.length >= from ? e.runnerPlayers[from - 1] : null;
        final t0 = -pHit - 0.15;
        final t1 = t0 + 3.25;
        _stealMoves.add(RunMove(r?.registeredName ?? '', from, from + 1, !e.stealSafe, t0, t1));
        final batRight = e.batterHand == 'S' ? true : e.batterHand != 'L';
        _cover = from == 2 ? '3B' : (batRight ? '2B' : 'SS');
        _stealBase = _bases[from + 1];
        final cPos = const V3(0, -0.5, 0);
        final dist = cPos.distanceTo(_stealBase);
        var arr = e.stealSafe ? t1 + 0.18 : t1 - 0.3;
        var rel = arr - dist / 34;
        if (rel < _tCatch + 0.55) {
          rel = _tCatch + 0.55;
          arr = rel + dist / 34;
        }
        _stealRel = rel;
        _stealArr = arr;
        final off = from == 1 ? const V3(0.5, -0.3, 0) : const V3(0.4, -0.4, 0);
        final tgt = _stealBase + off;
        legs.add((from: 'C', to: _cover, leg: ThrowLeg(cPos.x, cPos.y, tgt.x, tgt.y, rel, arr)));
        final s0 = _startOf(_cover);
        segs[_cover] = [_Seg(t0 + 0.4, arr - 0.25, s0, tgt)];
        tEnd = arr + 1.8;
      }
    }
  }

  /// ボールの回転：投球は物理の回転（軸と回転数）で、放してからの時間ぶん回す。打球はバックスピン。捕ったら止める
  ({V3 axis, double angle, bool four})? _ballSpin() {
    final k = ev.phys, s = ev.shot;
    final four = !RegExp('ツーシーム|シンカー|シュート|スプリット|フォーク').hasMatch(ev.pitchName);
    final tau = t + pHit; // 放してからの秒
    if (tau <= 0) return (axis: const V3(1, 0, 0), angle: 0.0, four: four);
    if (k == null) return null;
    final om = k.spin.omega * (s?.spinScale ?? 1.0);
    final hitPlay = !noPlay;
    if (!hitPlay || t < 0) {
      final tt = noPlay && !_foul ? math.min(tau, _tCatch + pHit) : tau;
      return (axis: om, angle: om.length * tt, four: four);
    }
    // 打球：飛ぶ向きに横向きの軸で回る（2000回転）
    final b0 = _ballNow(t), b1 = _ballNow(t + 0.02);
    final dir = b1 - b0;
    final axis = dir.length > 1e-4 ? dir.cross(V3.ez) : const V3(1, 0, 0);
    final angle = om.length * pHit + 209 * math.min(t, flight);
    return (axis: axis, angle: angle, four: four);
  }

  /// 打球にならない1球のボール：ミットへ → 返球 → 投手のグラブ。ファウルは打った点から飛んでいく
  V3 _ballNoPlay(double tt) {
    if (tt < 0) return _ballPitch(tt + pHit);
    if (_foul) {
      final u = math.min(tt, 2.4);
      if (u > _foulHitT) {
        final du = u - _foulHitT;
        if (!_foulOver) {
          // ネットに当たって、少し跳ね返りながら真下へ落ちる
          final back = V3(-_foulV.x, -_foulV.y, 0).unit * math.min(0.6, du * 1.5);
          final z = _foulHitP.z - 4.9 * du * du;
          return V3(_foulHitP.x + back.x, _foulHitP.y + back.y, math.max(0.04, z));
        }
        // 越えた：客席（段は奥ほど高い）に落ちたら止まる
        final p = _contact + _foulV * u + V3(0, 0, -4.9 * u * u);
        final beyond = math.max(0.0, p.distanceTo(V3(_foulHitP.x, _foulHitP.y, p.z)));
        final seatZ = 1.6 + beyond * 0.47;
        if (p.z <= seatZ) {
          // 落ちた時刻を探して、そこで止める
          var uu = _foulHitT;
          V3 q = _foulHitP;
          while (uu < u) {
            final qq = _contact + _foulV * uu + V3(0, 0, -4.9 * uu * uu);
            final bb = qq.distanceTo(V3(_foulHitP.x, _foulHitP.y, qq.z));
            if (qq.z <= 1.6 + bb * 0.47) break;
            q = qq;
            uu += 0.01;
          }
          return q;
        }
        return p;
      }
      final p = _contact + _foulV * u + V3(0, 0, -4.9 * u * u);
      return p.z < 0 ? V3(p.x, p.y, 0.04) : p;
    }
    if (tt < _tCatch) return _ballPitch(tt + pHit);
    // 捕った瞬間：ボールは来た所（＝ミットを寄せた所）から、ミットの動きへなめらかに移る（ミットが少し遅れても飛び移らない）
    final glove = _lastPose['C']?[J.glove.index] ?? _catchPt;
    final mitt = _catchPt.lerp(glove, ((tt - _tCatch) / 0.12).clamp(0.0, 1.0));
    final hand = actors['C']?.toon?.ballPoint ?? glove;
    // 持ち替え：ミット → 投げる手へ 0.15 秒で
    V3 transfer(double t0) => mitt.lerp(hand, ((tt - t0) / 0.15).clamp(0.0, 1.0));
    if (_steal) {
      if (tt < _tCatch + 0.08) return mitt;
      if (tt < _stealRel) {
        _cHand = transfer(_tCatch + 0.08);
        return _cHand!;
      }
      // 送球は決まった点（ベースの上・野手の胸の前）へ。受ける野手のグラブを追いかけない（追うと互いに引き合って揺れる）
      final aim = _stealBase + const V3(0, 0, 0.75);
      final cg = _lastPose[_cover]?[J.glove.index] ?? aim;
      if (tt < _stealArr) {
        final f = (tt - _stealRel) / (_stealArr - _stealRel);
        final from = _cHand ?? const V3(0.25, -0.5, 1.95); // 放した手の位置から
        return from.lerp(aim, f) + V3(0, 0, 4 * f * (1 - f) * 0.5);
      }
      return aim.lerp(cg, ((tt - _stealArr) / 0.1).clamp(0.0, 1.0));
    }
    if (tt < _retT0 - 0.3) return mitt;
    if (tt < _retT0) {
      _cHand = transfer(_retT0 - 0.3);
      return _cHand!;
    }
    // 返球は投手の胸の前の決まった点へ（投手のグラブを追いかけない：グラブはボールへ伸びるので、互いに追うと揺れる）
    const aim = V3(0.12, 17.25, 1.35);
    final pg = _lastPose['P']?[J.glove.index] ?? aim;
    if (tt < _retT1) {
      final f = (tt - _retT0) / (_retT1 - _retT0);
      final from = _cHand ?? const V3(0.25, -0.85, 1.9);
      return from.lerp(aim, f) + V3(0, 0, 4 * f * (1 - f) * 0.9);
    }
    return aim.lerp(pg, ((tt - _retT1) / 0.1).clamp(0.0, 1.0));
  }

  V3? _cHand; // 捕手が放す直前の手の位置

  /// 捕手（打球にならない1球）：構えたミットを球の来る所へ寄せて捕り、立って投手へ返す
  static List<V3> _mix(List<V3> a, List<V3> b, double f) {
    final c = f.clamp(0.0, 1.0);
    final e = c * c * (3 - 2 * c);
    return [for (var i = 0; i < a.length; i++) a[i].lerp(b[i], e)];
  }

  /// 捕手（打球にならない1球）：構えたミットを球の来る所へ寄せて捕り、立ち上がって投手へ返す。
  ///  姿勢の切り替えは目標どうしを時間でなめらかにつなぐ（切り替えの瞬間に関節が跳ばない）
  (List<V3>, String) _catcherNoPlay(_Actor a, double tt) {
    const cPos = V3(0, -0.9, 0);
    final runners = ev.basesBefore.any((x) => x);
    List<V3> squat(double t2) {
      final f = ((t2 - (_tCatch - 0.32)) / 0.3).clamp(0.0, 1.0);
      final mitt = const V3(-0.02, -0.15, 0.78).lerp(_catchPt, f * f * (3 - 2 * f));
      return StaticPoses.catcher(a.body, mitt: mitt, runners: runners);
    }

    if (_steal && tt > _tCatch + 0.02) {
      // 捕って立ち上がりながら右足を前へ（ジャンプステップ）、二塁（三塁）へ投げる
      final h = _heading(cPos, _stealBase);
      final pre = math.max(0.2, _stealRel - _tCatch);
      final u = tt <= _stealRel ? 0.6 * ((tt - _tCatch) / pre).clamp(0.0, 1.0) : 0.6 + 0.4 * ((tt - _stealRel) / 0.4).clamp(0.0, 1.0);
      final pos = cPos.lerp(const V3(0, -0.45, 0), (u / 0.6).clamp(0.0, 1.0));
      final look = _stealBase + const V3(0, 0, 1.2);
      final thr = a.poser.throwBall(pos, h, u, armSlot: 50, look: look);
      if (tt < _tCatch + 0.17) return (_mix(squat(tt), thr, (tt - _tCatch - 0.02) / 0.15), 'throw');
      if (tt <= _stealRel + 0.4) return (thr, 'throw');
      final end = a.poser.throwBall(const V3(0, -0.45, 0), h, 1.0, armSlot: 50, look: look);
      return (_mix(end, a.poser.stand(const V3(0, -0.45, 0), h, look: _ballNow(tt)), (tt - _stealRel - 0.4) / 0.5), 'stand');
    }
    if (_foul) return (squat(tt), 'squat');
    final h = _heading(cPos, _pSpot);
    final look = _pSpot + const V3(0, 0, 1.5);
    final up0 = _retT0 - 0.75; // 立ち上がり始め
    if (tt < up0) return (squat(tt), 'squat');
    // 立ち上がる（しゃがみ → 投げ始めの構え）
    final thr0 = a.poser.throwBall(cPos, h, 0, armSlot: 40, look: look);
    if (tt < _retT0 - 0.35) return (_mix(squat(tt), thr0, (tt - up0) / 0.4), 'squat');
    if (tt <= _retT0 + 0.3) {
      final u = tt <= _retT0 ? 0.6 * ((tt - (_retT0 - 0.35)) / 0.35).clamp(0.0, 1.0) : 0.6 + 0.4 * ((tt - _retT0) / 0.3).clamp(0.0, 1.0);
      return (a.poser.throwBall(cPos, h, u, armSlot: 40, look: look), 'squat');
    }
    // 投げ終わり → 立つ
    final end = a.poser.throwBall(cPos, h, 1.0, armSlot: 40, look: look);
    return (_mix(end, a.poser.stand(cPos, h, look: look), (tt - _retT0 - 0.3) / 0.5), 'squat');
  }

  V3 _startOf(String r) {
    final s = ev.fielderStart[r];
    if (s != null) return V3(s[0], s[1], 0);
    const d = {'P': [0.0, 18.44], 'C': [0.0, -1.0], '1B': [21.0, 27.0], '2B': [11.0, 44.5], '3B': [-20.5, 27.5], 'SS': [-11.0, 44.5], 'LF': [-42.0, 82.0], 'CF': [0.0, 95.0], 'RF': [42.0, 82.0]};
    final q = d[r]!;
    return V3(q[0], q[1], 0);
  }

  String _nearest(V3 p, double tt, {String? exclude, String? prefer}) {
    if (prefer != null && _posAt(prefer, tt).distanceTo(p) < 4) return prefer;
    var best = 'C';
    var bd = double.infinity;
    for (final r in _roles) {
      if (r == exclude) continue;
      final d = _posAt(r, tt).distanceTo(p);
      if (d < bd) {
        bd = d;
        best = r;
      }
    }
    return best;
  }

  /// 野手の位置（予定から）
  V3 _posAt(String r, double tt) {
    var p = _startOf(r);
    if (r == 'C') p = const V3(0, -0.9, 0);
    for (final s in segs[r] ?? const <_Seg>[]) {
      if (tt <= s.t0) return tt < s.t0 && s == (segs[r]!.first) ? p : s.p0;
      if (tt >= s.t1) {
        p = s.p1;
        continue;
      }
      final f = (tt - s.t0) / (s.t1 - s.t0);
      final ease = f < 0.3 ? f * f / 0.6 : (f - 0.15) / 0.85; // 加速してから一定（端はつながる）
      return s.p0.lerp(s.p1, ease.clamp(0.0, 1.0));
    }
    return p;
  }

  /// 走塁の道筋（Layer 2 の BasePath：塁を回ると膨らんで減速、止まり方は4通り）。プレーごとに作って覚えておく
  final Map<RunMove, BaseRun> _plans = {};

  Player? _runnerPlayer(RunMove mv) => mv.from == 0 ? ev.batterPlayer : (ev.runnerPlayers.length >= mv.from ? ev.runnerPlayers[mv.from - 1] : null);

  BaseRun _planOf(RunMove mv, V3 startPos) {
    final c = _plans[mv];
    if (c != null) return c;
    final p = _runnerPlayer(mv);
    final run = p?.run ?? 60;
    final thr = _throwAt(mv.to);
    final close = mv.out || (thr != null && (thr - mv.t1).abs() < 0.5);
    final outfield = const {'LF', 'CF', 'RF'}.contains(ev.fielder);
    // 一塁だけ駆け抜け（内野のゴロなど一塁で勝負）。外野へのヒットは一塁を回って止まり、戻る
    final RunEnd end;
    if (mv.from == 0 && mv.to == 1) {
      end = outfield && !mv.out ? RunEnd.overrun : RunEnd.runThrough;
    } else {
      end = close && !homeRun ? RunEnd.slide : RunEnd.stand;
    }
    final lead = mv.from == 0 ? 0.0 : startPos.distanceTo(_bases[mv.from]) / BasePath.between;
    final sFrom = mv.sStart ?? (mv.from + lead);
    return _plans[mv] = BaseRun(Sprint.of(run), sFrom: sFrom, to: mv.to, end: end, v0: mv.from == 0 ? 0 : 2.0, run: run);
  }

  /// 道筋の時間 ÷ 予定の時間（ホームランの一周などはゆっくり）。帰塁で予定が短すぎる（その場に戻るだけ）ときは実際の時間で
  double _kOf(RunMove mv, BaseRun plan) {
    final dur = math.max(0.1, mv.t1 - mv.t0);
    final back = mv.to < (mv.sStart ?? mv.from + 0.01);
    return back && dur < plan.tArrive ? 1.0 : plan.tArrive / dur;
  }

  /// 走者・打者の位置：予定の到達時刻（mv.t1）に合わせて道筋を進む。着いたあとは道筋の続き（駆け抜け・オーバーラン）→ 歩いて塁へ戻る
  V3 _runnerAt(RunMove mv, double tt, {required V3 startPos}) {
    final s0 = mv.sStart;
    if (s0 != null && mv.from > 0 && tt > 0 && tt <= mv.t0) {
      // 飛び出した走者：打った瞬間からその地点まで走っていた（エンドラン・ライナーの読み違い）
      final sLead = mv.from + startPos.distanceTo(_bases[mv.from]) / BasePath.between;
      final u = (tt / math.max(0.1, mv.t0)).clamp(0.0, 1.0);
      return BasePath.railPos(sLead + (s0 - sLead) * u);
    }
    if (tt <= mv.t0) return startPos;
    final plan = _planOf(mv, startPos);
    // 道筋の時間 ÷ 予定の時間（ホームランの一周などはゆっくり）。帰塁で予定が短すぎる（その場に戻るだけ）ときは実際の時間で
    final k = _kOf(mv, plan);
    final pt = (tt <= mv.t1 || k == 1.0) ? (tt - mv.t0) * k : plan.tArrive + (tt - mv.t1) * math.min(1.0, k);
    var q = plan.posAt(pt);
    // 走り出し：打席・リードの位置から道筋へ寄せる（飛び出した走者は、もうその地点にいる）
    if (s0 == null) {
      final off = startPos - plan.pts.first;
      q = q + off * math.max(0.0, 1 - pt / 0.8);
    }
    // 駆け抜け・オーバーランで止まったら、少しして歩いて塁へ戻る
    if ((plan.end == RunEnd.runThrough || plan.end == RunEnd.overrun) && pt > plan.tEnd + 0.6) {
      final base = _bases[mv.to];
      final far = plan.pts.last;
      final back = math.min(1.0, (pt - plan.tEnd - 0.6) * 1.3 / math.max(0.5, far.distanceTo(base)));
      q = far.lerp(base, back);
    }
    return q;
  }

  V3 _ballPitch(double tau) {
    if (pPath.isEmpty) return V3.zero;
    // 放す前：ボールは投手の手の中（いま見せている体の手の位置）
    if (tau < 0) return actors['P']?.toon?.ballPoint ?? _lastPose['P']?[J.ball.index] ?? pPath.first;
    if (tau >= pPathT.last) {
      // 道筋の終わり（本塁の上）より先：最後の速さのまま進める（ミットまで届くように）
      if (pPath.length < 2) return pPath.last;
      final n = pPath.length;
      final vel = (pPath[n - 1] - pPath[n - 2]) / math.max(1e-4, pPathT[n - 1] - pPathT[n - 2]);
      final fix = _hitFix;
      return pPath.last + vel * (tau - pPathT.last) + fix;
    }
    var i = 0;
    while (i + 1 < pPathT.length && pPathT[i + 1] < tau) {
      i++;
    }
    final f = (tau - pPathT[i]) / math.max(1e-6, pPathT[i + 1] - pPathT[i]);
    // 放した瞬間の手の位置から、物理の軌道へなめらかに寄せる
    final fix = _relHand == null ? relFix : _relHand! - pPath.first;
    return pPath[i].lerp(pPath[i + 1], f) + fix * math.max(0.0, 1 - tau / 0.08) + _hitFix * (tau / math.max(0.05, pHit)).clamp(0.0, 1.0);
  }

  V3 _ballHit(double tt) {
    if (bPath.isEmpty) return V3.zero;
    final f = (tt / flight).clamp(0.0, 1.0) * (bPath.length - 1);
    final i = math.min(bPath.length - 2, f.floor());
    if (bPath.length < 2) return bPath.first;
    final off = (_contact - bPath.first) * math.max(0.0, 1 - tt / 0.25);
    // 点と点の間は Catmull-Rom 曲線でつなぐ（折れ線だと点ごとに向きが変わって揺れて見える）
    final p0 = bPath[math.max(0, i - 1)], p1 = bPath[i], p2 = bPath[i + 1], p3 = bPath[math.min(bPath.length - 1, i + 2)];
    final u = f - i, u2 = u * u, u3 = u2 * u;
    final c = (p1 * 2 + (p2 - p0) * u + (p0 * 2 - p1 * 5 + p2 * 4 - p3) * u2 + (p1 * 3 - p0 - p2 * 3 + p3) * u3) * 0.5;
    return V3(c.x, c.y, math.max(0.0, c.z)) + off;
  }

  /// いまのボールの位置
  V3 _ballNow(double tt) {
    if (noPlay) return _ballNoPlay(tt);
    if (tt < 0) return _ballPitch(tt + pHit);
    if (tt <= flight || homeRun) return _ballHit(tt);
    // 送球中
    for (final l in legs) {
      if (tt >= l.leg.t0 && tt <= l.leg.t1) {
        final f = (tt - l.leg.t0) / math.max(0.05, l.leg.t1 - l.leg.t0);
        // 投げた人の実際の位置（ステップで前に出た所）から
        final st = _posAt(l.from, l.leg.t0);
        final x0 = st.x, y0 = st.y;
        final d = math.sqrt(math.pow(l.leg.x1 - x0, 2) + math.pow(l.leg.y1 - y0, 2));
        final arc = 4 * f * (1 - f) * math.min(6.0, d * 0.05); // 遠投ほど山なり
        return V3(x0 + (l.leg.x1 - x0) * f, y0 + (l.leg.y1 - y0) * f, 1.6 + arc);
      }
    }
    // 持っている人のグラブ
    String h = ev.fielder;
    for (final l in legs) {
      if (tt > l.leg.t1) h = l.to;
    }
    final a = actors[h];
    if (a == null) return bPath.last;
    // 投げる前の握り替え（放す 0.45 秒前から）：ボールは投げる手の中
    if (_holdsToThrow(h, tt)) return a.toon?.ballPoint ?? _gloveOf(h);
    return _gloveOf(h);
  }

  final Map<String, List<V3>> _lastPose = {};

  /// リリースの手のひらの向き（捕手の方＝−y が直球）。グラブ側へ倒すほど横回転（スライダー・カーブ）、腕の側へ返すとシンカー系
  static V3 _releasePalm(String name, bool lefty) {
    final glove = lefty ? -1.0 : 1.0; // グラブの側（右投手は ＋x）
    double side = 0, up = 0;
    if (name.contains('カーブ')) {
      side = 0.85;
      up = 0.35;
    } else if (name.contains('スライダー') || name.contains('スラーブ')) {
      side = 0.7;
    } else if (name.contains('カット')) {
      side = 0.35;
    } else if (name.contains('シンカー') || name.contains('シュート') || name.contains('スクリュー') || name.contains('チェンジ')) {
      side = -0.6;
    }
    return V3(glove * side, -1, up).unit;
  }

  /// いまボールを持っている野手（捕ってから、送球が届くまでは投げた人、届いたら受けた人）。持っていなければ null
  String? _holder(double tt) {
    if (homeRun || tt <= flight || ev.fielder.isEmpty) return null;
    String h = ev.fielder;
    for (final l in legs) {
      if (tt >= l.leg.t0 && tt <= l.leg.t1) return null; // 送球が飛んでいる
      if (tt > l.leg.t1) h = l.to;
    }
    return h;
  }

  /// 送球のために投げる手でボールを握っている（放す 0.45 秒前から放すまで）
  bool _holdsToThrow(String r, double tt) {
    for (final l in legs) {
      if (l.from == r && tt < l.leg.t0 && tt >= l.leg.t0 - 0.45) return true;
    }
    return false;
  }
  V3 _gloveOf(String r) => _lastPose[r]?[J.glove.index] ?? _posAt(r, t);

  // ───────── 1コマ ─────────
  double _probeT = -99;
  V3? _probeB, _probeC, _probeV;
  int _perfTick = 0;
  final Stopwatch _perfSw = Stopwatch();
  void _tick(Duration elapsed, double dt) {
    _perfSw
      ..reset()
      ..start();
    _frames++;
    _acc += dt;
    if (_acc >= 1.0) {
      fps = _frames / _acc;
      final pf = math.max(1, PuppetPainter.perfFrames);
      debugPrint('PERF fps=${fps.toStringAsFixed(1)} tick=${(_perfTick / math.max(1, _frames)).round()}us bg=${PuppetPainter.perfBg ~/ pf}us puppets=${PuppetPainter.perfPuppets ~/ pf}us head=${PuppetPainter.perfHead ~/ pf}us parts=${PuppetPainter.perfParts.map((x) => x ~/ pf).join("/")} paints=${PuppetPainter.perfFrames}');
      PuppetPainter.perfBg = 0;
      PuppetPainter.perfPuppets = 0;
      PuppetPainter.perfFrames = 0;
      PuppetPainter.perfHead = 0;
      for (var i = 0; i < 5; i++) {
        PuppetPainter.perfParts[i] = 0;
      }
      _perfTick = 0;
      _frames = 0;
      _acc = 0;
      if (mounted) setState(() {});
    }
    if (loading) return;
    if (!paused) t += dt * speed;
    if (t > tEnd) t = tStart;
    final tPrev = _probeT;
    _poseAll(t, dt * speed);
    // 調べ用：ボール・捕手のミットが1コマで不自然に跳んだら記録する（logcat：PROBE）
    final bNow = _ballNow(t), cg = _lastPose['C']?[J.glove.index];
    final st = t - tPrev;
    if (st > 0 && st < 0.05 && _probeB != null) {
      final v = bNow.distanceTo(_probeB!) / st;
      if (v > 75) debugPrint('PROBE ball idx=$idx t=${t.toStringAsFixed(3)} v=${v.round()} from=$_probeB to=$bNow res=${ev.result} steal=$_steal holder=${_holder(t)}');
      if (cg != null && _probeC != null) {
        final vc = cg.distanceTo(_probeC!) / st;
        if (vc > 12) debugPrint('PROBE mitt idx=$idx t=${t.toStringAsFixed(3)} v=${vc.toStringAsFixed(1)} res=${ev.result}');
      }
    }
    // 返球中のボールの揺れ（速さの向きが急に変わる）
    if (noPlay && !_foul && t > _retT0 + 0.02 && t < _retT1 - 0.02 && st > 0 && st < 0.05 && _probeB != null && _probeV != null) {
      final vNow = (bNow - _probeB!) / st;
      final acc = (vNow - _probeV!).length / st;
      if (acc > 60) debugPrint('PROBE ret idx=$idx t=${t.toStringAsFixed(3)} acc=${acc.round()}');
    }
    if (st > 0 && st < 0.05 && _probeB != null) _probeV = (bNow - _probeB!) / st;
    _probeT = t;
    _probeB = bNow;
    _probeC = cg;
    _camNow = _camera(); // 3D の球場と 2D の人形で同じカメラを使う（1コマに1回だけ計算）
    _perfTick += _perfSw.elapsedMicroseconds;
    _paintTick.value++;
  }

  /// ビジョン・リボンビジョン・フェンスの広告と金網（StadiumOverlay）：人形より先＝奥に描く
  void _drawVision(Canvas canvas, Offset? Function(V3) project, V3 camPos) {
    final st = _st;
    if (_ov == null || _ov!.st != st) {
      _ov?.dispose();
      _ov = StadiumOverlay(st, ads: _ads, homeName: ev.homeName, homeColor: Color(widget.homeColor));
    }
    _ov!.paint(canvas, project, camPos, dataKey: idx, data: _boardData);
  }

  StadiumOverlay? _ov;

  /// ビジョンに映すもの（この1球の時点の得点表など）
  BoardData _boardData() {
    final e = ev;
    final plays = widget.plays;
    final runs = <String, int>{};
    var hH = 0, hA = 0, eH = 0, eA = 0;
    final firstOf = <String, PitchEvent>{};
    for (var i = 0; i <= idx && i < plays.length; i++) {
      final p = plays[i];
      if (p.homeName != e.homeName || p.awayName != e.awayName) continue;
      final key = '${p.inning}${p.top ? 'T' : 'B'}';
      firstOf.putIfAbsent(key, () => p);
      runs[key] = (i == idx ? p.offBefore : p.offAfter) - firstOf[key]!.offBefore;
      if (i < idx && const {'単打', '二塁打', '三塁打', 'ホームラン'}.contains(p.outcome)) {
        if (p.top) {
          hA++;
        } else {
          hH++;
        }
      }
      if (i < idx && p.errorBy.isNotEmpty) {
        if (p.top) {
          eH++;
        } else {
          eA++;
        }
      }
    }
    return BoardData(
        e: e, stadium: _st.name, home: Color(widget.homeColor), away: Color(widget.awayColor), ads: _ads, runs: runs,
        rA: e.top ? e.offBefore : e.defBefore, rH: e.top ? e.defBefore : e.offBefore, hH: hH, hA: hA, eH: eH, eA: eA);
  }

  // ───────── 広告：ホーム球団のスポンサー（契約していなければ架空の会社）─────────
  static const _fakeAds = ['ノースビール', 'ほくと電機', 'はまなす銀行', '北ガス', 'ポプラ製菓', 'ひかり保険', '雪原ミルク', '大地建設'];
  static const _adPalette = [0xFFB91C1C, 0xFF1D4ED8, 0xFF0F766E, 0xFFEA580C, 0xFFDB2777, 0xFF4F46E5, 0xFF0891B2, 0xFF15803D, 0xFF7C3AED, 0xFF111827];
  late final List<(String, int)> _ads = [
    for (final n in (widget.sponsors.isNotEmpty ? widget.sponsors : _fakeAds)) (n, _adPalette[n.codeUnits.fold(0, (a, c) => (a * 31 + c) & 0x7fffffff) % _adPalette.length]),
  ];

  /// 2D の人形を描き直す合図（毎コマ）
  final ValueNotifier<int> _paintTick = ValueNotifier(0);

  List<PuppetItem> _puppets() => [
        for (final e in actors.entries)
          if (e.value.toon is PuppetRig)
            PuppetItem(e.value.toon as PuppetRig, catcherGear: e.key == 'C', batKnob: e.key == 'B' ? _batKnob : null, batTip: e.key == 'B' ? _batTip : null),
      ];

  /// Layer 2 の目標の姿勢 → Layer 1（可動域・IK → PD 制御）で見せる。動きの切り替わり・始まり・終わりは PD の惰性で自然につながる
  ///  投げる・打つ・投球の腕は速い（ω を高く）。走っているときの脚は接地点に合わせる（PD で遅らせると足が滑る）
  /// 運動連鎖の位相のずれ（投球・送球・スイング）：骨盤・脚は 55ms、胸郭と首は 35ms 先の姿勢にし、
  ///  腕は「今の」手首の目標へ届かせ直す。根元が先に回り、胸が遅れてついてきて、最後に腕がムチのようにしなる。
  ///  仕様の「根元 t・末端ほど遅れる」を、手の時刻（リリース・インパクト）を保ったまま根元を前へずらして作る（ボール・バットと手が離れない）
  HumanPose _phaseLead(PlayerRig rig, HumanPose q, List<V3> p, List<V3> Function(double lead) chain, V3? look) {
    final hb = rig.human;
    final qp = hb.fit(chain(0.055), look: look, hint: q);
    final qs = hb.fit(chain(0.035), look: look, hint: q);
    final r = q.clone();
    r.root = qp.root;
    r.yaw = qp.yaw;
    r.tilt = qp.tilt;
    r.roll = qp.roll;
    for (var i = 0; i < 2; i++) {
      r.hipFlex[i] = qp.hipFlex[i];
      r.hipAbd[i] = qp.hipAbd[i];
      r.hipRot[i] = qp.hipRot[i];
      r.knee[i] = qp.knee[i];
      r.ankle[i] = qp.ankle[i];
    }
    r.spTwist = qs.spTwist;
    r.spLean = qs.spLean;
    r.spSide = qs.spSide;
    r.nkYaw = qs.nkYaw;
    r.nkPitch = qs.nkPitch;
    final o = hb.fk(r);
    for (var i = 0; i < 2; i++) {
      final t = i == 0;
      hb.reachArm(r, o, i, p[(t ? J.wristT : J.wristG).index], p[(t ? J.elbowT : J.elbowG).index]);
    }
    rig.orientHands(r);
    return r;
  }

  List<V3> Function(double lead)? _lead; // いまの動きの、少し先の時刻の姿勢（投球・送球・スイングのとき）

  List<V3> _show(_Actor a, String kind, List<V3> p, double tt, double dt, {V3? look, List<V3> Function(double lead)? chain}) {
    final rig = a.toon!;
    if (a.kind != kind) {
      a.kind = kind;
      a.kindT = tt;
    }
    // 巻き戻し・飛ばし（スライダー・繰り返し）は、そのまま目標へ
    if (!a.lastT.isNaN && (tt - a.lastT - dt).abs() > 0.08) a.pd.reset();
    a.lastT = tt;
    var q = rig.prepare(p, look: look ?? a.poser.lastLook);
    if (chain != null) q = _phaseLead(rig, q, p, chain, look ?? a.poser.lastLook);
    // スイングは姿勢の時系列そのものがなめらか。PD で遅らせるとバットが当たる点に遅れて来るので、そのまま見せる
    if (kind == 'swing') a.pd.reset();
    final fast = const {'pitch', 'swing', 'throw', 'squat'}.contains(kind); // 捕手のミットも球へ遅れずに
    final w = HumanPd.omega(arms: fast ? 60 : 24, armT: fast ? 95 : 24, spine: fast ? 60 : 20, pelvis: fast ? 60 : 22, legs: fast ? 70 : 34, neck: 24);
    final s = a.pd.step(q, dt, w, snapLegs: kind == 'run' && tt - a.kindT > 0.25);
    final o = rig.human.fk(s);
    rig.poseOut(o);
    a.q = s;
    a.out = o;
    a.shown = o.p;
    return o.p;
  }

  /// 走りの1コマ（Layer 1 の歩行エンジン）：速さ・加速・曲がる速さは、移動の予定から
  GaitFrame _gaitOf(_Actor a, V3 Function(double) at, double tt, double h) {
    const e = 0.05;
    final p0 = at(tt - e), p1 = at(tt), p2 = at(tt + e);
    final vel = (p2 - p0) / (2 * e);
    final v0 = (p1 - p0).length / e, v1 = (p2 - p1).length / e;
    double hd(V3 d) => math.atan2(d.x, d.y);
    final d0 = p1 - p0, d1 = p2 - p1;
    var turn = 0.0;
    if (d0.length > 0.02 && d1.length > 0.02) {
      var dh = hd(d1) - hd(d0);
      while (dh > math.pi) {
        dh -= 2 * math.pi;
      }
      while (dh < -math.pi) {
        dh += 2 * math.pi;
      }
      turn = dh / e;
    }
    return a.gait.step(tt, p1, vel, (v1 - v0) / e, turn, h);
  }

  /// 顔の動き：力を入れる瞬間（投げる・振る・送球・全力で走る）は歯を食いしばり、ときどきまばたき（人ごとに間隔が違う）
  void _face(_Actor a, String role, String kind, double tt) {
    final rig = a.toon;
    if (rig is! PuppetRig) return;
    var eff = 0.0;
    if (kind == 'pitch' && motion != null) {
      final mt = tt + pitchPre, br = motion!.ph.br;
      eff = (1 - ((mt - (br - 0.05)) / 0.22).abs()).clamp(0.0, 1.0);
    } else if (kind == 'swing') {
      eff = (1 - ((tt + 0.02) / 0.2).abs()).clamp(0.0, 1.0);
    } else if (kind == 'throw') {
      eff = 0.8;
    } else if (kind == 'run') {
      eff = 0.4;
    }
    rig.effort = eff;
    final h = (role.codeUnits.fold(7, (s, c) => (s * 31 + c) & 0xFFFF) % 1000) / 1000.0;
    final period = 2.8 + h * 2.4;
    final ph = (tt + 20 + h * 9) % period;
    rig.blink = eff > 0.5 ? 0.0 : (ph < 0.16 ? 1 - ((ph - 0.08) / 0.08).abs() : 0.0);
  }

  void _poseAll(double tt, double dt) {
    final e = ev;
    final ballPos = _ballNow(tt);
    // 野手
    for (final r in _roles) {
      final a = actors[r]!;
      List<V3> p;
      String kind;
      _lead = null;
      if (r == 'P' && tt < 0.35 && motion != null) {
        final mo = motion!;
        p = mo.poseAt(math.min(mo.ph.end, tt + pitchPre));
        _lead = (ld) => mo.poseAt(math.min(mo.ph.end, tt + pitchPre + ld));
        kind = 'pitch';
      } else if (r == 'C' && noPlay) {
        final cp = _catcherNoPlay(a, tt);
        p = cp.$1;
        kind = cp.$2;
      } else if (r == 'P' && noPlay) {
        // 投げ終わったら、捕手の返球を受ける
        final pos = _pSpot;
        final h = _heading(pos, const V3(0, -0.9, 0));
        if (!_foul && !_steal && tt >= _retT1 - 0.35 && tt <= _retT1 + 0.2) {
          p = a.poser.catchFly(pos, h, ballPos);
          kind = 'recv';
        } else {
          p = a.poser.stand(pos, h, look: ballPos);
          kind = 'stand';
        }
      } else if (r == 'C' && tt < 0.75) {
        // 打った直後：しゃがみから、守備の動き（立つ・走る）へ 0.4 秒でつなぐ
        final sq = StaticPoses.catcher(a.body, runners: e.basesBefore.any((x) => x));
        if (tt < 0.35) {
          p = sq;
          kind = 'squat';
        } else {
          final fp = _fielderPose(r, a, tt, dt, ballPos);
          p = _mix(sq, fp.$1, (tt - 0.35) / 0.4);
          kind = 'squat';
        }
      } else {
        final fp = _fielderPose(r, a, tt, dt, ballPos);
        p = fp.$1;
        kind = fp.$2;
      }
      // グラブ（G の手）のポケットをボールへ正対させる（捕る・受けるとき）。ゴロは指先を下、フライは上
      final tg = a.toon;
      if (tg != null) {
        if (kind == 'ground' || kind == 'fly' || kind == 'recv') {
          final gpos = p[J.glove.index];
          final toBall = ballPos - gpos;
          tg.palmG = toBall.length > 0.05 ? toBall.unit : Poser.fwdOf(0);
          tg.fingerG = kind == 'ground' ? const V3(0, 0, -1) : const V3(0, 0, 1);
        } else if (kind == 'ready') {
          // 構え：グラブを開いて打球の来る方（打者）へ向ける
          final gpos = p[J.glove.index];
          final toB = V3(-gpos.x, -gpos.y, 0);
          tg.palmG = (toB.unit + const V3(0, 0, 0.25)).unit;
          tg.fingerG = const V3(0, 0, 1);
        } else if (_holder(tt) == r && !_holdsToThrow(r, tt)) {
          // ボールを持っている：ポケットを上・自分の胸の方へ向けて、ボールを包んだまま
          final gpos = p[J.glove.index];
          final chest = p[J.neck.index] - const V3(0, 0, 0.25);
          final toChest = chest - gpos;
          tg.palmG = (V3(toChest.x, toChest.y, 0).unit * 0.6 + const V3(0, 0, 0.8)).unit;
          tg.fingerG = (V3(-toChest.x, -toChest.y, 0).unit * 0.3 + const V3(0, 0, 1)).unit;
        } else {
          tg.palmG = null;
          tg.fingerG = null;
        }
      }
      // 手の形：投手は投げるまで球種の握り、送球はボールの握り、走るときは軽く握る
      final tn = a.toon;
      if (tn != null) {
        if (kind == 'pitch' && motion != null) {
          final mt = tt + pitchPre;
          // リリースの手の向き（球種の回転軸）：放す 0.12 秒前から手のひらを決まった向きへ
          if (mt > motion!.ph.br - 0.12 && mt < motion!.ph.br + 0.03) {
            final lefty = e.fielderPlayers['P']?.throws == 'L';
            tn.palmT = _releasePalm(e.pitchName, lefty);
            tn.fingerT = const V3(0, -0.35, 1).unit;
          } else {
            tn.palmT = null;
            tn.fingerT = null;
          }
          if (mt < motion!.ph.br) {
            tn.holdBall(PitchGrip.ofPitch(e.pitchName)); // 球種の握りで、指をボールに沿わせる
          } else {
            tn.holdBall(null);
            tn.handT = mt < motion!.ph.br + 0.25 ? HandPose.open : HandPose.relaxed;
          }
        } else if (_holdsToThrow(r, tt)) {
          tn.holdBall(PitchGrip.fourSeam); // 送球：握り替えてから放すまで
        } else {
          tn.holdBall(null);
          tn.handT = switch (kind) { 'throw' => HandPose.open, 'run' => HandPose.looseFist, 'recv' || 'fly' || 'ground' => HandPose.open, _ => HandPose.relaxed };
        }
      }
      // 見る点：投手は放すまで捕手のミット、捕手はボール（ほかの動きは Poser が決めた点）
      final V3? lookAt = kind == 'pitch' ? (motion != null && tt + pitchPre < motion!.ph.br ? const V3(0, -0.6, 0.8) : ballPos) : (kind == 'squat' ? ballPos : null);
      final shownF = _show(a, kind, p, tt, dt, look: lookAt, chain: kind == 'pitch' || kind == 'throw' ? _lead : null);
      if (kind == 'pitch' && motion != null && tt + pitchPre <= motion!.ph.br) _relHand = a.toon?.ballPoint ?? shownF[J.ball.index];
      _lastPose[r] = shownF;
      a.glove.position = sv(shownF[J.glove.index]);
      _face(a, r, kind, tt);
    }
    // 打者：構え → スイング（0.6でミート）→ フィニッシュ → バットを置いて走る
    final batRight = e.batterHand == 'S' ? true : e.batterHand != 'L';
    final ba = actors['B']!;
    final s = batRight ? -1.0 : 1.0;
    final bMove = e.runMoves.where((m) => m.from == 0).toList();
    if (bMove.isEmpty && !homeRun && !noPlay) bMove.add(RunMove(e.batter, 0, 1, true, 0.55, 0.55 + 5.2)); // 捕られても一塁へ走る
    List<V3> bp;
    String bk;
    V3? batDir; // スイング中のバットの向き（握りの穴を通す）
    final runStart = bMove.isEmpty ? 99.0 : math.max(bMove.first.t0, 0.5);
    V3? palmTop, palmBottom;
    if (tt < runStart) {
      // 仕様書 2.3 の6段階：インパクト（t=0）でバットの芯が打球の出発点に来る
      final hitAt = _contact;
      final look = tt > 0.05 ? ballPos : hitAt;
      // 見送る球は踏み出しまでで止める（バットは出さない）
      final st = noPlay && !_swing ? math.min(tt, -0.32) : tt;
      final sw = ba.poser.swingAt(right: batRight, t: st, contact: hitAt, spray: e.spray, look: look);
      final take = noPlay && !_swing;
      _lead = (ld) => ba.poser.swingAt(right: batRight, t: take ? math.min(tt + ld, -0.32) : tt + ld, contact: hitAt, spray: e.spray, look: look).p;
      bk = 'swing';
      batDir = sw.bat;
      palmTop = sw.palmTop;
      palmBottom = sw.palmBottom;
      bp = sw.p;
    } else {
      bp = _runnerPose(ba, bMove.first, tt, dt, startPos: V3(s * 0.9, 0.3, 0)).$1;
      bk = 'run';
      _batKnob = V3(s * 1.1, 0.5, 0.03); // 置いたバット
      _batTip = V3(s * 1.1, 1.34, 0.03);
      bat.position = sv(V3(s * 1.1, 0.9, 0.03));
      bat.rotation = vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), math.pi / 2);
    }
    final bt = ba.toon;
    if (bt != null) {
      bt.handT = bk == 'swing' ? HandPose.fist : HandPose.looseFist;
      bt.handG = bt.handT;
      // 両手の握りの穴をバットの向きにそろえる（親指の側がバットの先）
      bt.aimT = batDir;
      bt.aimG = batDir;
      // 仕様書 2.3 ④：インパクトまでは上の手のひらが上・下の手のひらが下（手首を返さない）、押し込みのあとで返す
      bt.palmT = palmTop;
      bt.palmG = palmBottom;
    }
    _show(ba, bk, bp, tt, dt, chain: bk == 'swing' ? _lead : null);
    _lead = null;
    _face(ba, 'B', bk == 'swing' && (!noPlay || _swing) ? 'swing' : (bk == 'swing' ? 'stance' : bk), tt);
    if (batDir != null) {
      if (bt != null) {
        // 仕様書 2.2：バットは下の手（G＝右打者の左手）に付き、グリップエンドから 3.5cm 上を握る。
        //  上の手（T）は、バット上の 10cm 先の握りの位置へ腕を届かせ直す（両手が離れない）
        final gG = bt.gripPoint(false);
        final want = gG + batDir * 0.10;
        final gT = bt.gripPoint(true);
        final q2 = ba.q!.clone();
        final o1 = ba.out!;
        bt.human.reachArm(q2, o1, 0, o1.p[J.wristT.index] + (want - gT), o1.p[J.elbowT.index]);
        bt.orientHands(q2);
        final o2 = bt.human.fk(q2);
        bt.poseOut(o2);
        ba.shown = o2.p;
        _placeBat(gG - batDir * 0.035, batDir);
      } else {
        _placeBat((bp[J.wristT.index] + bp[J.wristG.index]) * 0.5, batDir);
      }
    }
    // 走者
    for (var i = 0; i < 3; i++) {
      final a = actors['R${i + 1}'];
      if (a == null) continue;
      final base = i + 1;
      final mv = [...e.runMoves, ..._stealMoves].where((m) => m.from == base).toList();
      final next = _bases[base + 1];
      final lead = _bases[base] + (next - _bases[base]).unit * (base == 3 ? 3.5 : 3.8);
      final rp = mv.isEmpty
          ? (a.poser.lead(lead, _heading(lead, const V3(0, 18.4, 0)), look: tt < 0 ? const V3(0, 18.4, 1.6) : ballPos), 'lead')
          : _runnerPose(a, mv.first, tt, dt, startPos: lead);
      final rt = a.toon;
      if (rt != null) {
        rt.handT = rp.$2 == 'run' ? HandPose.looseFist : HandPose.relaxed;
        rt.handG = rt.handT;
      }
      _show(a, rp.$2, rp.$1, tt, dt);
      _face(a, 'R$i', rp.$2, tt);
    }
    // 球審：構えて、打ったあとは打球を見る
    final um = actors['U']!;
    const up0 = V3(0, -2.6, 0);
    final upose = tt < 0.3 ? um.poser.ready(up0, 0, crouch: 0.55, look: const V3(0, 9, 1.0)) : um.poser.stand(up0, _heading(up0, ballPos), look: ballPos);
    _show(um, tt < 0.3 ? 'ump' : 'umpUp', upose, tt, dt);
    _face(um, 'U', '', tt);
    // ボール：体を動かしたあとの同じコマの手・グラブから（1コマ遅れると、腕を振る速さで数十 cm 手から離れて見える）
    ball.position = sv(_ballNow(tt));
    final far = !(_camUsed == 5 || _camUsed == 6);
    ball.scale = vm.Vector3.all(far ? 1.6 : 1.0);
  }

  /// 速さ（予定から。前後0.05秒の位置の差）
  double _speedOf(V3 Function(double) at, double tt) => at(tt + 0.05).distanceTo(at(tt - 0.05)) / 0.1;

  /// その塁への送球が届く時刻（なければ null）。走者との差でスライディングか立ったまま止まるかを決める
  double? _throwAt(int base) {
    final b = _bases[math.min(4, base)];
    double? t;
    for (final l in legs) {
      if (V3(l.leg.x1, l.leg.y1, 0).distanceTo(b) < 3) t = l.leg.t1;
    }
    return t;
  }

  /// 走者の止まり方（仕様書 2.1）：一塁だけ駆け抜け、余裕があれば 3.5m 手前から制動して立ったまま、際どければ 4m 手前からスライディング、
  ///  外野へのヒットの打者は一塁を回って止まる、飛び出した走者はレールを戻る（越えた塁は踏み直す）
  (List<V3>, String) _runnerPose(_Actor a, RunMove mv, double tt, double dt, {required V3 startPos}) {
    V3 at(double x) => _runnerAt(mv, x, startPos: startPos);
    final pos = at(tt);
    a.last = pos;
    final v = _speedOf(at, tt);
    final target = _bases[math.min(4, mv.to)];
    final ahead = at(tt + 0.1);
    final h = ahead.distanceTo(pos) > 0.01 ? _heading(pos, ahead) : _heading(pos, target);
    if (tt <= mv.t0 && !(mv.sStart != null && tt > 0)) return (a.poser.lead(pos, _heading(pos, target), look: _ballNow(tt)), 'lead');
    final plan = _planOf(mv, startPos);
    final k = _kOf(mv, plan);
    final pt = (tt <= mv.t1 || k == 1.0) ? (tt - mv.t0) * k : plan.tArrive + (tt - mv.t1);
    // スライディング：塁の 4m 手前から。着いてからも少し倒れたまま
    if (plan.end == RunEnd.slide && pt <= plan.tArrive + 0.5 && plan.distToBase(math.min(pt, plan.tArrive)) <= 4.0) {
      final hs = _heading(pos, target);
      return (a.poser.slide(pos - Poser.fwdOf(hs) * 0.5, hs), 'slide');
    }
    if (v > 0.5) return (a.poser.runGait(pos, h, _gaitOf(a, at, tt, h), look: tt > mv.t1 ? _ballNow(tt) : target + const V3(0, 0, 1.0)), 'run');
    if (tt > mv.t0 + 0.2 && tt >= mv.t1 - 0.05) {
      // 着いた（アウトならベンチの方を向く）
      return mv.out ? (a.poser.stand(pos, _heading(pos, const V3(-30, 0, 0))), 'standOut') : (a.poser.stand(pos, _heading(pos, V3.zero), look: _ballNow(tt)), 'stand');
    }
    return (a.poser.runGait(pos, h, _gaitOf(a, at, tt, h), look: target + const V3(0, 0, 1.0)), 'run');
  }

  (List<V3>, String) _fielderPose(String r, _Actor a, double tt, double dt, V3 ballPos) {
    final pos = _posAt(r, tt);
    a.last = pos;
    final v = _speedOf((x) => _posAt(r, x), tt);
    // 送球：0.6 でリリース。外野手はクロウホップの分だけ長い
    final outfield = const {'LF', 'CF', 'RF'}.contains(r);
    final dur = outfield ? 1.1 : 0.85;
    double prevCatch = flight; // この送球の前にボールを持った時刻
    for (final l in legs) {
      // 捕ってから握り替えて（0.12秒〜）投げる。時間がなければ、テイクバックを短くして素早く
      final rel = l.leg.t0;
      final start = math.max(rel - 0.6 * dur, prevCatch + 0.12);
      final pre = math.max(0.15, rel - start); // リリースまで
      if (l.from == r && tt >= start && tt <= rel + 0.4 * dur) {
        final tgt = V3(l.leg.x1, l.leg.y1, 0);
        final u = tt <= rel ? 0.6 * (tt - start) / pre : 0.6 + 0.4 * (tt - rel) / (0.4 * dur);
        double uAt(double t2) => t2 <= rel ? 0.6 * ((t2 - start) / pre).clamp(0.0, 1.0) : 0.6 + 0.4 * ((t2 - rel) / (0.4 * dur)).clamp(0.0, 1.0);
        final hd = _heading(pos, tgt);
        _lead = (ld) => a.poser.throwBall(pos, hd, uAt(tt + ld), armSlot: outfield ? 15 : 35, look: tgt + const V3(0, 0, 1.5));
        return (a.poser.throwBall(pos, hd, u, armSlot: outfield ? 15 : 35, look: tgt + const V3(0, 0, 1.5)), 'throw');
      }
      prevCatch = l.leg.t1;
      if (l.to == r && tt >= l.leg.t1 - 0.3 && tt <= l.leg.t1 + 0.2) {
        return (a.poser.catchFly(pos, _heading(pos, V3(l.leg.x0, l.leg.y0, 0)), ballPos), 'recv');
      }
    }
    // 盗塁：ベースに入った野手が捕ってタッチ（グラブを塁の前へ下ろす）
    if (_steal && r == _cover && tt > _stealArr + 0.05 && tt < _stealArr + 0.6) {
      return (a.poser.fieldGround(pos, _heading(pos, _bases[ev.stealFrom]), 0.6, look: _bases[ev.stealFrom + 1]), 'ground');
    }
    // 打球の処理（捕る瞬間の前後）
    if (r == ev.fielder && !homeRun && tt >= flight - 0.45 && tt <= flight + 0.12) {
      final h = _heading(pos, V3.zero);
      if (groundPlay || (ev.path.isNotEmpty && ev.path.last[2] < 0.3 && ev.outcome != 'アウト')) {
        return (a.poser.fieldGround(pos, h, (tt - flight + 0.45) / 0.85 * 0.9, look: ballPos), 'ground');
      }
      return (a.poser.catchFly(pos, h, ballPos), 'fly');
    }
    if (v > 0.8) {
      final ahead = _posAt(r, tt + 0.1);
      final h = ahead.distanceTo(pos) > 0.01 ? _heading(pos, ahead) : _heading(pos, ballPos);
      // ボールを持って送球へ向かうステップ：送球先を見る
      V3 lk = ballPos;
      if (_holder(tt) == r) {
        for (final l in legs) {
          if (l.from == r && l.leg.t0 >= tt) {
            lk = V3(l.leg.x1, l.leg.y1, 1.5);
            break;
          }
        }
      }
      return (a.poser.runGait(pos, h, _gaitOf(a, (x) => _posAt(r, x), tt, h), look: lk), 'run');
    }
    if (tt < 0) return (a.poser.ready(pos, _heading(pos, V3.zero), crouch: 0.55, look: const V3(0, 0.5, 1.0)), 'ready');
    if (tt < flight) return (a.poser.ready(pos, _heading(pos, ballPos), crouch: 0.35, look: ballPos), 'ready');
    // プレーが落ち着いたら、立ってボールを見る（自分が持っているなら内野の方を見る）
    final mineBall = ballPos.distanceTo(pos + const V3(0, 0, 1)) < 1.5;
    final lk = mineBall ? const V3(0, 20, 1.2) : ballPos;
    return (a.poser.stand(pos, _heading(pos, lk), look: lk), 'stand');
  }

  double _heading(V3 from, V3 to) {
    final d = to - from;
    if (d.x.abs() + d.y.abs() < 1e-3) return 0;
    return math.atan2(d.x, d.y);
  }

  Camera? _camNow;
  Camera _camShared() => _camNow ??= _camera();
 // 斜め上のカメラが見ている所（なめらかに追う）
  V3? _batKnob, _batTip; // 2D で描くバット（グリップの端・先）
  void _placeBat(V3 hands, V3 dir) {
    _batKnob = hands;
    _batTip = hands + dir * 0.84;
    final c = hands + dir * 0.42; // hands：グリップの端（バット 0.84m の中心はその 0.42m 先）
    bat.position = sv(c);
    bat.rotation = vm.Quaternion.fromTwoVectors(vm.Vector3(0, 1, 0), sv(dir));
  }

  // ───────── カメラ：6つの定位置（位置は動かさず、向きとズームで追う）─────────
  //  0 自動（場面で ①②③⑥ を切り替える）、1 ①中継（投手の斜め後方）、2 ②一塁側、3 ②三塁側（エキサイトシート付近）、
  //  4 ③バックネット裏、5 ④捕手目線、6 ⑤打者目線、7 ⑥バックネット裏上方
  static const camNames = ['自動', '中継', '一塁側', '三塁側', 'ネット裏', '捕手', '打者', 'ネット裏上'];

  /// 定位置（本塁基準の座標）
  V3 _camPosOf(int c) {
    final batRight = ev.batterHand == 'S' ? true : ev.batterHand != 'L';
    final s = batRight ? -1.0 : 1.0;
    return switch (c) {
      1 => const V3(-5.5, 118, 13), // センター後方のやや左から、投手の斜め後ろ越しに本塁を
      2 => const V3(24.0, 18.4, 1.2), // 一塁線の外 4m（本塁から 30m）、地面に近い（エキサイトシート）
      3 => const V3(-24.0, 18.4, 1.2),
      4 => V3(0, -math.min(15.0, _st.backstop - 1.5), 2.4),
      5 => const V3(0, -1.05, 0.95), // 捕手の目の高さ
      6 => V3(s * 0.85, 0.25, 1.55), // 打者の目の高さ
      _ => _st.roofRidge > 0 ? const V3(0, -31, 22) : _highCam(), // 上方（屋根の球場は2層目の前の高さ）
    };
  }

  /// ネット裏上方：本塁の後ろの席に屋根があれば、屋根の前のふちの下・少し前（甲子園の銀傘、幕張・神宮・広島の屋根）
  V3 _highCam() {
    var y = -38.0, z = 30.0;
    for (final t in _st.stands) {
      if (t.area != 'バックネット裏' || t.roofColor == 0) continue;
      final zTop = t.baseHeight + 0.4 + t.rows * t.rowRise;
      final offTop = 0.3 + t.setback + t.rows * t.rowDepth;
      final front = 0.3 + t.setback + (offTop - 0.3 - t.setback) * (1 - t.roofCover);
      y = math.max(y, -(_st.backstop + front - 1.5));
      z = math.min(z, zTop + t.roofRise - 3.5);
    }
    return V3(0, y, z);
  }

  /// 自動：投球は①、打ったあとは打球の種類と送球先で ②③⑥ を切り替える（テレビ中継のように、切り替えは一瞬）
  int _autoCam(double tt) {
    if (noPlay) return _foul && tt > 0.3 ? 7 : (_steal && tt > _tCatch + 0.15 ? 7 : 1);
    if (tt < 0.15) return 1;
    // 送球が始まったら、送球先の塁の側から
    ThrowLeg? cur;
    for (final l in legs) {
      if (tt >= l.leg.t0 - 0.3) cur = l.leg;
    }
    if (cur != null) {
      final x = cur.x1, y = cur.y1;
      if (y < 6) return 4; // 本塁
      if (x > 8) return 2; // 一塁
      if (x < -8) return 3; // 三塁
      return 7; // 二塁
    }
    final far = bPath.isNotEmpty && math.sqrt(bPath.last.x * bPath.last.x + bPath.last.y * bPath.last.y) > 45;
    if (homeRun || far || !groundPlay) return 7; // 外野への打球・フライ
    return 4; // 内野のゴロ
  }

  int _camUsed = 1;
  double _viewAspect = 0.62; // 3D の画面の 横÷縦（描くたびに更新）
  bool _camReset = true;
  V3? _camLook; // いま向いている点（なめらかに追う）
  double? _camFov;

  Camera _camera() {
    final c = cam == 0 ? _autoCam(t) : cam;
    final cut = c != _camUsed || _camReset; // 切り替えた瞬間・新しいプレーは、なめらかにせずすぐ合わせる
    _camReset = false;
    _camUsed = c;
    if (c == 6) return _batterEye(cut);
    if (_boardCam && _st.moreVisions.isNotEmpty) {
      // 確認用：左のビジョンを正面から（本塁の少し前から）
      final v = _st.moreVisions.first;
      final d = _st.fenceDistance(v.angle) + v.behind;
      final ctr = V3(d * math.sin(v.angle * deg), d * math.cos(v.angle * deg), v.bottom + v.height / 2);
      final pos = ctr * 0.25 + const V3(0, 0, 8);
      final dist = pos.distanceTo(ctr);
      final fovX = 2 * math.atan(v.width * 0.55 / dist);
      final fov = 2 * math.atan(math.tan(fovX / 2) / _viewAspect);
      return PerspectiveCamera(position: sv(pos), target: sv(ctr), fovRadiansY: fov);
    }
    final pos = _camPosOf(c);
    // 見る点と、写したい広さ（m）
    V3 look;
    double span;
    if (noPlay && !_foul && !_steal && t > _tCatch + 0.6) {
      // 打球にならない1球：捕手から投手への返球（投手と捕手が入る広さ）
      look = const V3(0, 9, 1.2);
      span = switch (c) { 1 => 9.0, 2 || 3 => 26.0, 7 => 28.0, _ => 24.0 };
    } else if (t < 0.12 || (noPlay && !_foul && !(_steal && t > _tCatch))) {
      // 投球：投手と打者を
      look = switch (c) { 5 || 6 => const V3(0, 18.4, 1.7), 1 => const V3(0, 3, 1.2), _ => const V3(0, 9, 1.0) };
      span = switch (c) { 1 => 5.5, 2 || 3 => 24.0, 5 || 6 => 7.0, 7 => 26.0, _ => 22.0 };
    } else {
      final b = _ballNow(t);
      final h = _holder(t);
      // 持っている野手がいればその人、いなければボール（高いフライは少し下を見て、捕る野手も入れる）
      final focus = h != null ? _posAt(h, t) + const V3(0, 0, 1.0) : V3(b.x, b.y, b.z * 0.7 + 0.5);
      look = focus;
      final d = pos.distanceTo(focus);
      span = 9 + d * 0.12 + b.z * 0.5;
    }
    final prevL = _camLook, prevF = _camFov;
    final dist = math.max(1.0, pos.distanceTo(look));
    // span は横の広さ：縦長の画面では、横の画角から縦の画角を求める
    final fovX = 2 * math.atan(span / 2 / dist);
    final fov = (2 * math.atan(math.tan(fovX / 2) / _viewAspect)).clamp(2.0 * vm.degrees2Radians, 85 * vm.degrees2Radians);
    _camLook = cut || prevL == null ? look : prevL + (look - prevL) * 0.15;
    _camFov = cut || prevF == null ? fov : prevF + (fov - prevF) * 0.08;
    return PerspectiveCamera(position: sv(pos), target: sv(_camLook!), fovRadiansY: _camFov!);
  }

  /// ⑤打者の目：打者の頭の中（目の高さ）から、投手の手 → 来る球 → 打球を目で追う。画角は人の目に近い広さで固定
  V3? _eyePos;
  Camera _batterEye(bool cut) {
    final sh = actors['B']?.shown;
    final head = sh == null ? _camPosOf(6) : sh[J.head.index];
    // 目はスイング中も大きくはぶれない（頭の動きをならす）
    _eyePos = cut || _eyePos == null ? head : _eyePos! + (head - _eyePos!) * 0.2;
    final rel = -pHit; // 放す時刻（t の目盛り：打つ瞬間＝0）
    V3 want;
    final mitt = _catchPt + const V3(0, 0.05, 0);
    if (t < rel) {
      want = const V3(0, 17.4, 1.9); // 放す前：投手の手のあたり
    } else if (noPlay && !_swing) {
      // 見逃し：ミットに収まるまで球を追い、少し見てから投手へ
      want = t < _tCatch ? _ballNow(t) : (t < _tCatch + 0.5 ? mitt : _pSpot + const V3(0, 0, 1.5));
    } else if (t <= 0) {
      want = _ballNow(t); // スイング：当てる点（打者が予測した点）まで追う
    } else if (!noPlay || _foul) {
      want = _ballNow(t); // 当たった：打球の方向へ
    } else {
      // 空振り：振り切るまでは当てるはずだった点の先を見て、そこへ打球が飛ばないのを確かめてからミットへ
      want = t < 0.35 ? _contact + (_contact - const V3(0, 18.4, 1.8)).unit * -4.0 : (t < _tCatch + 0.6 ? mitt : _pSpot + const V3(0, 0, 1.5));
    }
    if (want.distanceTo(_eyePos!) < 0.6) want = _eyePos! + const V3(0, 3, 0);
    final eye = _eyePos! + (want - _eyePos!).unit * 0.09 + const V3(0, 0, 0.02);
    final prevL = _camLook;
    _camLook = cut || prevL == null ? want : prevL + (want - prevL) * 0.45;
    _camFov = 44 * vm.degrees2Radians;
    return PerspectiveCamera(position: sv(eye), target: sv(_camLook!), fovRadiansY: _camFov!);
  }

  Future<void> _go(int d) async {
    if (loading) return; // 読み込み中は受け付けない
    final n = (idx + d).clamp(0, widget.plays.length - 1);
    if (n == idx) return;
    setState(() => idx = n);
    await _load();
  }

  String _info() {
    final e = ev;
    final dist = bPath.isEmpty ? 0 : math.sqrt(bPath.last.x * bPath.last.x + bPath.last.y * bPath.last.y);
    final bases = [for (var i = 0; i < 3; i++) if (e.basesBefore.length > i && e.basesBefore[i]) '${i + 1}'].join('');
    final env = e.env;
    if (noPlay) {
      return '${e.inning}回${e.top ? '表' : '裏'} ${e.outsBefore}死${bases.isEmpty ? '' : ' 走者$bases塁'}　${e.pitcher} → ${e.batter}\n'
          '${e.balls}-${e.strikes}から ${e.pitchName} ${e.speed.round()}km/h　${e.result}';
    }
    return '${e.inning}回${e.top ? '表' : '裏'} ${e.outsBefore}死${bases.isEmpty ? '' : ' 走者$bases塁'}　${e.pitcher} → ${e.batter}\n'
        '${e.pitchName} ${e.speed.round()}km/h　打球 ${(e.exitSpeed * 3.6).round()}km/h・${(e.launch ?? 0).round()}°・${e.spray >= 0 ? '右' : '左'}${e.spray.abs().round()}°　${e.contact} ${dist.round()}m・${flight.toStringAsFixed(1)}秒\n'
        '${env == null ? '' : '${env.tempC.round()}℃ ${env.windText}　'}${e.call.isEmpty ? '' : '${e.call}　'}${e.outcome}${e.playCode.isEmpty ? '' : '（${e.playCode}）'}';
  }

  String _duties() {
    final plan = ev.defense;
    if (plan == null) return '';
    return [for (final r in _roles) if (plan.duties[r] != null) '$r ${_dutyName[plan.duties[r]!.duty]}'].join('・');
  }

  @override
  Widget build(BuildContext context) {
    const ts = TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700, shadows: [Shadow(blurRadius: 3)]);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: Text('3D プレー（${idx + 1}/${widget.plays.length}）'), backgroundColor: Colors.black, foregroundColor: Colors.white),
      body: Stack(children: [
        // 3D の描画は左手系（x 右・y 上・z 奥）なので、本塁基準の座標（右手系）を写すと左右が逆になる。画面ごと左右を反転して正しい向きに
        if (ready) Positioned.fill(child: Transform.flip(flipX: true, child: SceneView(scene, cameraBuilder: (_) => _camShared(), onTick: _tick))),
        if (ready && !loading)
          Positioned.fill(
            child: IgnorePointer(
              child: Transform.flip(
                flipX: true,
                child: CustomPaint(painter: PuppetPainter(items: _puppets, camera: _camShared, ball: () => homeRun && t > flight + 0.5 ? null : _ballNow(t), ballSpin: _ballSpin, repaint: _paintTick, onSize: (sz) => _viewAspect = sz.width / math.max(1.0, sz.height), background: _drawVision)),
              ),
            ),
          ),
        if ((!ready || loading) && error == null) const Center(child: CircularProgressIndicator()),
        if (error != null) Center(child: Padding(padding: const EdgeInsets.all(20), child: Text('3D を表示できませんでした\n$error', style: const TextStyle(color: Colors.white)))),
        if (ready && !loading)
          Positioned(
            left: 8,
            top: 8,
            right: 8,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_info(), style: ts, maxLines: detail ? 4 : 2, overflow: TextOverflow.ellipsis),
              if (detail) const SizedBox(height: 2),
              if (detail) Text(ev.desc.replaceAll(RegExp(r'\[.*?\]'), ''), style: ts.copyWith(fontSize: 11, color: Colors.amberAccent), maxLines: 3, overflow: TextOverflow.ellipsis),
              if (detail) Text(_duties(), style: ts.copyWith(fontSize: 10.5, color: Colors.lightBlueAccent), maxLines: 3),
              Text('${t < 0 ? '投球' : '${t.toStringAsFixed(1)}秒'}　fps ${fps.toStringAsFixed(0)}　${cam == 0 ? '自動（${camNames[_camUsed]}）' : camNames[cam]}　${speed == 1 ? '等速' : (speed == 0.25 ? 'スロー×1/4' : 'スロー×1/10')}', style: ts.copyWith(fontSize: 11)),
            ]),
          ),
        Positioned(
          bottom: 14,
          left: 0,
          right: 0,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // 時間を動かして1コマずつ見る（動かすと止まる）
            if (ready && !loading)
              Slider(
                value: t.clamp(tStart, tEnd),
                min: tStart,
                max: tEnd,
                onChanged: (v) => setState(() {
                  paused = true;
                  t = v;
                }),
              ),
            Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: [
            FilledButton.tonal(onPressed: idx > 0 && !loading ? () => _go(-1) : null, child: const Text('◀ 前')),
            FilledButton.tonal(
                onLongPress: () => setState(() => _boardCam = !_boardCam), // 確認用：ビジョンを正面から
                onPressed: () => setState(() {
                      stadiumIdx = (stadiumIdx + 1) % Stadium.viewChoices.length;
                      _buildStadium();
                    }),
                child: Text('球場：${_st.name}')),
            for (var i = 0; i < camNames.length; i++)
              FilledButton.tonal(onPressed: () => setState(() => cam = i), style: FilledButton.styleFrom(backgroundColor: cam == i ? Colors.amber : null, padding: const EdgeInsets.symmetric(horizontal: 10)), child: Text(camNames[i])),
            FilledButton.tonal(onPressed: () => setState(() => speed = speed == 1 ? 0.25 : (speed == 0.25 ? 0.1 : 1)), child: Text(speed == 1 ? 'スロー' : (speed == 0.25 ? 'もっと遅く' : '等速'))),
            FilledButton.tonal(onPressed: () => setState(() => t = tStart), child: const Text('もう一度')),
            FilledButton.tonal(onPressed: () => setState(() => paused = !paused), child: Text(paused ? '再生' : '停止')),
            FilledButton.tonal(
                onPressed: () => setState(() {
                      shadows = !shadows;
                      scene.directionalLight = DirectionalLight(direction: vm.Vector3(-0.35, -1.0, 0.45), intensity: 5.5, castsShadow: shadows, shadowMaxDistance: 60, shadowMapResolution: 2048);
                    }),
                child: Text(shadows ? '影なし' : '影あり')),
            FilledButton.tonal(onPressed: () => setState(() => detail = !detail), child: Text(detail ? '表示を減らす' : '詳しく')),
            FilledButton.tonal(onPressed: idx < widget.plays.length - 1 && !loading ? () => _go(1) : null, child: const Text('次 ▶')),
          ]),
          ]),
        ),
      ]),
    );
  }
}
