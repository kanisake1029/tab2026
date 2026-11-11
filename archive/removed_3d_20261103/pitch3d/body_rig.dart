import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../../engine/body_model.dart';
import '../../engine/pitch_motion.dart' show J;
import '../../engine/vec3.dart';
import '../../models/uniform.dart';
import 'scene_util.dart';

/// 骨（全員共通の骨格。投球・打撃・守備・走塁の動きは、関節の位置の時系列をこの骨に流す）
class BoneDef {
  final String name;
  final J head, tail;
  final int parent;
  const BoneDef(this.name, this.head, this.tail, this.parent);
}

const bones = <BoneDef>[
  BoneDef('腰', J.pelvis, J.pelvis, -1), // 0（向きは上・左右の股関節）
  BoneDef('胴', J.pelvis, J.neck, 0), // 1
  BoneDef('頭', J.neck, J.head, 1), // 2
  BoneDef('上腕T', J.shoulderT, J.elbowT, 1), // 3
  BoneDef('前腕T', J.elbowT, J.wristT, 3), // 4
  BoneDef('手T', J.wristT, J.ball, 4), // 5
  BoneDef('上腕G', J.shoulderG, J.elbowG, 1), // 6
  BoneDef('前腕G', J.elbowG, J.wristG, 6), // 7
  BoneDef('手G', J.wristG, J.glove, 7), // 8
  BoneDef('太ももT', J.hipT, J.kneeT, 0), // 9
  BoneDef('すねT', J.kneeT, J.ankleT, 9), // 10
  BoneDef('足T', J.ankleT, J.toeT, 10), // 11
  BoneDef('太ももG', J.hipG, J.kneeG, 0), // 12
  BoneDef('すねG', J.kneeG, J.ankleG, 12), // 13
  BoneDef('足G', J.ankleG, J.toeG, 13), // 14
];

/// 体（肌の層）とユニフォーム（服の層）を、同じ骨で動かす
///  体格（BodyModel）から、楕円の断面の筒・楕円体をつないで作る。関節の付近は前後の骨に重みを分けて滑らかに曲げる
class BodyRig {
  final BodyModel body;
  final Uniform uni;
  final int skinColor;
  final bool lefty;
  final Node root = Node();
  final List<Node> joints = [for (var i = 0; i < bones.length; i++) Node()];
  late final List<vm.Matrix4> _bindG;
  late final List<double> _len;

  BodyRig(this.body, this.uni, {required List<V3> bindPose, this.skinColor = 0xFFD9A07A, this.lefty = false}) {
    for (final j in joints) {
      root.add(j);
    }
    _len = [for (final b in bones) b.head == b.tail ? 0.25 : bindPose[b.head.index].distanceTo(bindPose[b.tail.index])];
    pose(bindPose);
    _bindG = [for (final j in joints) j.globalTransform.clone()];
    _buildMeshes();
  }

  // ───── 姿勢 ─────
  final FrameSolver _solver = FrameSolver();

  /// 関節の位置（本塁基準の座標）から、骨の向きを決める
  void pose(List<V3> p) {
    final fr = _solver.solve(p);
    for (var i = 0; i < bones.length; i++) {
      joints[i].localTransform = fr[i];
    }
  }

  // ───── 形 ─────
  void _buildMeshes() {
    final b = body;
    final skin = _Builder(this), cloth = _Builder(this), dark = _Builder(this), cap = _Builder(this), glove = _Builder(this), team = _Builder(this);
    const inf = 0.008; // 服のふくらみ
    double lerp(double a, double c, double t) => a + (c - a) * t;
    // 胴：腰（臀囲）→ 腹（腹囲）→ 胸（胸囲）→ 首の付け根
    (double, double) torso(double u) {
      if (u < 0.0) return (b.hipA, b.hipB);
      if (u < 0.45) return (lerp(b.hipA, b.waistA, u / 0.45), lerp(b.hipB, b.waistB, u / 0.45));
      if (u < 0.82) return (lerp(b.waistA, b.chestA, (u - 0.45) / 0.37), lerp(b.waistB, b.chestB, (u - 0.45) / 0.37));
      final k = (u - 0.82) / 0.18;
      return (lerp(b.chestA, b.chestA * 0.55, k * k), lerp(b.chestB, b.chestB * 0.75, k * k));
    }

    List<(int, double)> torsoW(double u) => u < 0.12 ? [(0, 1 - (u + 0.15) / 0.27 * 0.5), (1, (u + 0.15) / 0.27 * 0.5)] : [(1, 1.0)];
    skin.tube(1, -0.15, 1.0, (u) => torso(u), torsoW, rings: 22);
    cloth.tube(1, -0.15, 1.0, (u) {
      final r = torso(u);
      return (r.$1 + inf * 1.5, r.$2 + inf * 1.5);
    }, torsoW, rings: 22);
    // 肩の丸み（胴と上腕に半分ずつ）
    for (final bone in [3, 6]) {
      cloth.ellipsoid(bone, vm.Vector3(0, b.upperArm * 0.05, 0), vm.Vector3(b.upperArmR * 1.55, b.upperArmR * 1.7, b.upperArmR * 1.55), [(bone, 0.6), (1, 0.4)]);
      skin.ellipsoid(bone, vm.Vector3(0, b.upperArm * 0.05, 0), vm.Vector3(b.upperArmR * 1.45, b.upperArmR * 1.6, b.upperArmR * 1.45), [(bone, 0.6), (1, 0.4)]);
    }
    // 首・頭・帽子
    skin.tube(2, -0.1, 0.55, (u) => (b.headR * 0.48, b.headR * 0.5), (u) => u < 0.1 ? [(1, 0.5), (2, 0.5)] : [(2, 1.0)], rings: 6);
    final hc = vm.Vector3(0, b.neck + b.headR * 0.9, 0.01);
    skin.ellipsoid(2, hc, vm.Vector3(b.headR * 0.88, b.headR * 1.12, b.headR * 0.98), [(2, 1.0)]);
    cap.ellipsoid(2, hc + vm.Vector3(0, b.headR * 0.32, 0), vm.Vector3(b.headR * 0.95, b.headR * 0.78, b.headR * 1.04), [(2, 1.0)], upperOnly: true);
    cap.ellipsoid(2, hc + vm.Vector3(0, b.headR * 0.30, -b.headR * 1.05), vm.Vector3(b.headR * 0.75, b.headR * 0.05, b.headR * 0.55), [(2, 1.0)]);
    // 腕（投げる腕・グラブの腕）
    for (final (u, f, h) in [(3, 4, 5), (6, 7, 8)]) {
      final lu = _len[u], lf = _len[f];
      skin.tube(u, 0, 1.0, (t) => (b.upperArmR * lerp(1.05, 0.82, t), b.upperArmR * lerp(1.0, 0.8, t)), (t) => t > 0.88 ? [(u, 1 - (t - 0.88) / 0.24), (f, (t - 0.88) / 0.24)] : [(u, 1.0)], length: lu);
      team.tube(u, 0, 1.0, (t) => (b.upperArmR * lerp(1.05, 0.82, t) + inf, b.upperArmR * lerp(1.0, 0.8, t) + inf), (t) => t > 0.88 ? [(u, 1 - (t - 0.88) / 0.24), (f, (t - 0.88) / 0.24)] : [(u, 1.0)], length: lu);
      cloth.tube(u, 0, 0.55, (t) => (b.upperArmR * lerp(1.05, 0.9, t) + inf * 2, b.upperArmR * lerp(1.0, 0.88, t) + inf * 2), (t) => [(u, 1.0)], length: lu, rings: 8);
      skin.tube(f, 0, 1.0, (t) => (b.forearmR * lerp(1.1, 0.68, t), b.forearmR * lerp(1.0, 0.55, t)), (t) => t < 0.1 ? [(f, 0.5 + t * 5), (u, 0.5 - t * 5)] : (t > 0.9 ? [(f, 1 - (t - 0.9) * 3), (h, (t - 0.9) * 3)] : [(f, 1.0)]), length: lf);
      team.tube(f, 0, 0.92, (t) => (b.forearmR * lerp(1.1, 0.7, t) + inf * 0.6, b.forearmR * lerp(1.0, 0.57, t) + inf * 0.6), (t) => t < 0.1 ? [(f, 0.5 + t * 5), (u, 0.5 - t * 5)] : [(f, 1.0)], length: lf);
      final lh = _len[h];
      if (h == 5) {
        skin.ellipsoid(h, vm.Vector3(0, lh * 0.45, 0), vm.Vector3(b.forearmR * 0.95, lh * 0.55, b.forearmR * 0.45), [(h, 1.0)]);
      } else {
        glove.ellipsoid(h, vm.Vector3(0, lh * 0.55, 0), vm.Vector3(b.forearmR * 1.9, lh * 0.95, b.forearmR * 0.9), [(h, 1.0)]);
      }
    }
    // 脚
    for (final (th, sh, ft) in [(9, 10, 11), (12, 13, 14)]) {
      final lt = _len[th], ls = _len[sh], lft = _len[ft];
      final thighW = (double t) => t < 0.1 ? [(th, 0.5 + t * 5), (0, 0.5 - t * 5)] : (t > 0.9 ? [(th, 1 - (t - 0.9) * 4), (sh, (t - 0.9) * 4)] : [(th, 1.0)]);
      final shankW = (double t) => t < 0.1 ? [(sh, 0.6 + t * 4), (th, 0.4 - t * 4)] : (t > 0.92 ? [(sh, 1 - (t - 0.92) * 5), (ft, (t - 0.92) * 5)] : [(sh, 1.0)]);
      (double, double) thighR(double t) => (b.thighR * lerp(1.05, 0.62, t), b.thighR * lerp(1.1, 0.66, t));
      (double, double) shankR(double t) {
        final calf = math.exp(-math.pow((t - 0.3) / 0.22, 2)) * 0.25;
        return (b.shankR * (lerp(0.95, 0.55, t) + calf * 0.6), b.shankR * (lerp(1.0, 0.55, t) + calf));
      }

      skin.tube(th, 0, 1.0, thighR, thighW, length: lt);
      cloth.tube(th, -0.02, 1.0, (t) {
        final r = thighR(t);
        return (r.$1 + inf * 2.2, r.$2 + inf * 2.2);
      }, thighW, length: lt);
      skin.tube(sh, 0, 1.0, shankR, shankW, length: ls);
      cloth.tube(sh, 0, 0.42, (t) {
        final r = shankR(t);
        return (r.$1 + inf * 1.6, r.$2 + inf * 1.6);
      }, shankW, length: ls, rings: 8);
      team.tube(sh, 0.4, 0.97, (t) {
        final r = shankR(t);
        return (r.$1 + inf * 0.6, r.$2 + inf * 0.6);
      }, shankW, length: ls, rings: 10);
      dark.ellipsoid(ft, vm.Vector3(0, lft * 0.35, 0), vm.Vector3(b.shankR * 0.95, lft * 0.75, b.shankR * 0.75), [(ft, 0.85), (sh, 0.15)]);
    }
    root.add(skin.node(mat(skinColor, rough: 0.55)));
    root.add(cloth.node(mat(uni.base, rough: 0.75)));
    root.add(team.node(mat(uni.undershirt, rough: 0.7)));
    root.add(cap.node(mat(uni.capBase, rough: 0.6)));
    root.add(dark.node(mat(uni.shoes, rough: 0.4)));
    root.add(glove.node(mat(uni.glove, rough: 0.65)));
  }
}

/// 骨に重みを付けた頂点を集めて、1つのスキン付きの形にする
class _Builder {
  final BodyRig rig;
  final _v = <double>[];
  final _i = <int>[];
  _Builder(this.rig);
  int get _n => _v.length ~/ 26;

  void _vert(int bone, vm.Vector3 local, vm.Vector3 nLocal, List<(int, double)> w) {
    final g = rig._bindG[bone];
    final p = g.transformed3(local);
    final n = g.getRotation().transformed(nLocal)..normalize();
    final ws = [...w]..sort((a, b) => b.$2.compareTo(a.$2));
    final jj = [0.0, 0.0, 0.0, 0.0], ww = [0.0, 0.0, 0.0, 0.0];
    var sum = 0.0;
    for (var k = 0; k < math.min(4, ws.length); k++) {
      jj[k] = ws[k].$1.toDouble();
      ww[k] = math.max(0.0, ws[k].$2);
      sum += ww[k];
    }
    if (sum <= 0) {
      jj[0] = bone.toDouble();
      ww[0] = 1;
      sum = 1;
    }
    _v.addAll([p.x, p.y, p.z, n.x, n.y, n.z, 0, 0, 0, 0, 1, 1, 1, 1, 1, 0, 0, 1, jj[0], jj[1], jj[2], jj[3], ww[0] / sum, ww[1] / sum, ww[2] / sum, ww[3] / sum]);
  }

  /// 骨に沿った筒（u は骨の長さに対する位置。radius は楕円の半径 x・z）
  void tube(int bone, double u0, double u1, (double, double) Function(double u) radius, List<(int, double)> Function(double u) weights, {double? length, int rings = 14, int seg = 16}) {
    final len = length ?? rig._len[bone];
    final start = _n;
    for (var i = 0; i <= rings; i++) {
      final u = u0 + (u1 - u0) * i / rings;
      final (rx, rz) = radius(u);
      final w = weights(u);
      for (var j = 0; j <= seg; j++) {
        final a = j / seg * math.pi * 2;
        final c = math.cos(a), s = math.sin(a);
        _vert(bone, vm.Vector3(rx * c, u * len, rz * s), vm.Vector3(c / rx, 0, s / rz), w);
      }
    }
    for (var i = 0; i < rings; i++) {
      for (var j = 0; j < seg; j++) {
        final a = start + i * (seg + 1) + j, b2 = a + seg + 1;
        _i.addAll([a, b2, a + 1, a + 1, b2, b2 + 1]);
      }
    }
    // 両端のふた
    for (final (u, flip) in [(u0, true), (u1, false)]) {
      final (rx, rz) = radius(u);
      final w = weights(u);
      final c0 = _n;
      _vert(bone, vm.Vector3(0, u * len, 0), vm.Vector3(0, flip ? -1 : 1, 0), w);
      for (var j = 0; j <= seg; j++) {
        final a = j / seg * math.pi * 2;
        _vert(bone, vm.Vector3(rx * math.cos(a), u * len, rz * math.sin(a)), vm.Vector3(0, flip ? -1 : 1, 0), w);
      }
      for (var j = 0; j < seg; j++) {
        _i.addAll(flip ? [c0, c0 + 1 + j, c0 + 2 + j] : [c0, c0 + 2 + j, c0 + 1 + j]);
      }
    }
  }

  /// 楕円体（upperOnly：上半分だけ＝帽子）
  void ellipsoid(int bone, vm.Vector3 c, vm.Vector3 r, List<(int, double)> w, {bool upperOnly = false, int rings = 12, int seg = 18}) {
    final start = _n;
    for (var i = 0; i <= rings; i++) {
      final th = (upperOnly ? 0.5 * i / rings : i / rings) * math.pi; // 0＝上
      for (var j = 0; j <= seg; j++) {
        final ph = j / seg * math.pi * 2;
        final d = vm.Vector3(math.sin(th) * math.cos(ph), math.cos(th), math.sin(th) * math.sin(ph));
        _vert(bone, c + vm.Vector3(d.x * r.x, d.y * r.y, d.z * r.z), vm.Vector3(d.x / r.x, d.y / r.y, d.z / r.z), w);
      }
    }
    for (var i = 0; i < rings; i++) {
      for (var j = 0; j < seg; j++) {
        final a = start + i * (seg + 1) + j, b2 = a + seg + 1;
        _i.addAll([a, a + 1, b2, a + 1, b2 + 1, b2]);
      }
    }
  }

  Node node(Material m) {
    final g = SkinnedGeometry();
    final v = Float32List.fromList(_v);
    assert(_n < 65536);
    final ix = Uint16List.fromList(_i);
    g.uploadVertexData(v.buffer.asByteData(), _n, ix.buffer.asByteData());
    final s = Skin();
    s.joints.addAll(rig.joints);
    for (final b in rig._bindG) {
      s.inverseBindMatrices.add(vm.Matrix4.inverted(b));
    }
    m.doubleSided = true;
    return Node(mesh: Mesh(g, m))..skin = s;
  }
}

/// 関節の位置から骨の向きを決める（前の姿勢の向きを覚えておき、腕が伸びきったときなどに向きが飛ばないようにする）
class FrameSolver {
  final List<vm.Vector3> _prevX = List.generate(bones.length, (_) => vm.Vector3(1, 0, 0));
  /// 関節の位置（本塁基準の座標）→ 15本の骨の向き（3D の座標の行列。x＝曲げる面の法線、y＝骨の向き）
  List<vm.Matrix4> solve(List<V3> p) {
    vm.Vector3 at(J j) => sv(p[j.index]);
    final frames = List<vm.Matrix4?>.filled(bones.length, null);
    vm.Vector3 xOf(int i) => frames[i] == null ? _prevX[i] : frames[i]!.getColumn(0).xyz;
    for (var i = 0; i < bones.length; i++) {
      final b = bones[i];
      final o = at(b.head);
      vm.Vector3 y;
      vm.Vector3 xRef;
      switch (i) {
        case 0:
          y = vm.Vector3(0, 1, 0);
          xRef = at(J.hipG) - at(J.hipT);
        case 1:
          y = at(J.neck) - o;
          xRef = at(J.shoulderG) - at(J.shoulderT);
        case 2:
          y = at(J.head) - o;
          xRef = xOf(1);
        case 5 || 8 || 11 || 14:
          y = at(b.tail) - o;
          xRef = xOf(b.parent);
        default:
          // 腕・脚：曲げる面の法線
          final mid = at(b.tail);
          final child = bones.indexWhere((c) => c.parent == i && c.head == b.tail);
          final isUpper = child >= 0 && i != 4 && i != 7 && i != 10 && i != 13;
          final a = isUpper ? o : at(bones[b.parent].head);
          final m = isUpper ? mid : o;
          final e = isUpper ? at(bones[child].tail) : mid;
          y = mid - o;
          xRef = (m - a).cross(e - m);
          if (xRef.length < 1e-4) xRef = _prevX[i];
          if (xRef.dot(_prevX[i]) < 0) xRef = -xRef;
      }
      y.normalize();
      var x = xRef - y * xRef.dot(y);
      if (x.length < 1e-5) x = _prevX[i] - y * _prevX[i].dot(y);
      x.normalize();
      final z = x.cross(y)..normalize();
      _prevX[i] = x.clone();
      final mtx = vm.Matrix4.identity()
        ..setColumn(0, vm.Vector4(x.x, x.y, x.z, 0))
        ..setColumn(1, vm.Vector4(y.x, y.y, y.z, 0))
        ..setColumn(2, vm.Vector4(z.x, z.y, z.z, 0))
        ..setColumn(3, vm.Vector4(o.x, o.y, o.z, 1));
      frames[i] = mtx;
    }
    return [for (final m in frames) m!];
  }
}
