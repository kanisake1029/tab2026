import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../../engine/body_gen.dart';
import '../../engine/body_model.dart';
import '../../engine/pitch_motion.dart' show J;
import '../../engine/vec3.dart';
import '../../models/player.dart';
import '../../models/uniform.dart';
import 'body_rig.dart' show FrameSolver;
import 'human_asset.dart';
import 'scene_util.dart';

/// 選手の見た目の指定（体格の数値・年齢・国籍・id から決める）
class HumanLook {
  final Map<String, double> weights; // 調整の重み
  final String skin; // 'young_asian' など
  final String hair; // 'hair_short02' など
  final int heightCm, armCm;
  const HumanLook(this.weights, this.skin, this.hair, this.heightCm, this.armCm);

  static const faceFeatures = [
    'head-scale-horiz', 'head-scale-vert', 'head-scale-depth', 'head-fat', 'head-oval', 'head-round', 'head-square', 'head-triangular',
    'nose-scale-horiz', 'nose-scale-vert', 'nose-scale-depth', 'nose-hump', 'nose-curve', 'nose-point-width', 'nose-nostrils-width', 'nose-trans',
    'mouth-scale-horiz', 'mouth-lowerlip-volume', 'mouth-upperlip-volume', 'mouth-trans',
    'eye-scale', 'eye-trans', 'eye-height2', 'eye-epicanthus', 'eye-corner1', 'eye-bag',
    'chin-width', 'chin-prominent', 'chin-height', 'chin-bones', 'cheek-bones', 'cheek-volume', 'ear-scale', 'ear-flap',
    'forehead-scale-vert', 'forehead-nubian', 'eyebrows-trans', 'eyebrows-angle',
  ];

  static double _g(String id, int salt) {
    final r = math.Random(stableHash(id, salt));
    return math.sqrt(-2 * math.log(1 - r.nextDouble())) * math.cos(2 * math.pi * r.nextDouble());
  }

  static void _pm(Map<String, double> w, String name, double v) {
    if (v >= 0) {
      w['$name+'] = (w['$name+'] ?? 0) + v;
    } else {
      w['$name-'] = (w['$name-'] ?? 0) - v;
    }
  }

  factory HumanLook.ofPlayer(Player p) {
    final w = <String, double>{};
    final h = p.height / 100.0;
    final bmi = p.weight / (h * h);
    final strength = p.isPitcher ? p.pitchPower : p.power;
    _pm(w, 'muscle', ((strength - 55) / 35.0 + _g(p.id, 11) * 0.15).clamp(-0.8, 0.9));
    _pm(w, 'weight', ((bmi - 24.5) / 4.0).clamp(-1.0, 1.0));
    _pm(w, 'height', ((p.height - 173) / 70.0).clamp(-0.6, 0.6)); // MPFB の身長の調整は 0.5 で約70cm 変わる（形の比率だけ使い、最後に身長に合わせて縮める）
    final a = 0.5 + (p.age - 25) / 65 * 0.5;
    if (a < 0.5) {
      w['age-'] = ((0.5 - a) / 0.16).clamp(0.0, 1.0);
    } else {
      w['age+'] = ((a - 0.5) / 0.25).clamp(0.0, 1.0);
    }
    // 人種の混ざり方（日本：アジア系。海外：id から）
    final r = (stableHash(p.id, 0x7ace) % 1000) / 1000.0;
    Map<String, double> race;
    if (p.nationality != '海外') {
      race = {'asian': 0.88 + r * 0.12, 'caucasian': (1 - r) * 0.12, 'african': 0};
    } else if (r < 0.35) {
      race = {'african': 0.85 + r * 0.4, 'caucasian': 0.15 - r * 0.4, 'asian': 0};
    } else if (r < 0.8) {
      race = {'caucasian': 0.9, 'african': 0.05, 'asian': 0.05};
    } else {
      race = {'caucasian': 0.55, 'african': 0.45, 'asian': 0};
    }
    race.forEach((k, v) => w['race-$k'] = v.clamp(0.0, 1.0));
    final dom = race.entries.reduce((x, y) => x.value >= y.value ? x : y).key;
    final skin = '${p.age <= 31 ? 'young' : (p.age <= 37 ? 'middleage' : 'old')}_$dom';
    // 体の周り（BMI から決まる分を引いた残り）
    _pm(w, 'measure-bust-circ', ((p.chestGirth - (p.height * 0.52 + (bmi - 22) * 2.4)) / 6.0).clamp(-1.0, 1.0));
    _pm(w, 'measure-waist-circ', ((p.waistGirth - (p.height * 0.43 + (bmi - 22) * 3.2)) / 6.0).clamp(-1.0, 1.0));
    _pm(w, 'measure-hips-circ', ((p.hipGirth - (p.height * 0.52 + (bmi - 22) * 2.2)) / 6.0).clamp(-1.0, 1.0));
    _pm(w, 'head-scale-horiz', ((p.headGirth - 57) / 3.0 * 0.4).clamp(-0.8, 0.8));
    // 顔：id から（同じ選手はいつも同じ顔）
    for (var i = 0; i < faceFeatures.length; i++) {
      _pm(w, faceFeatures[i], (_g(p.id, 0xface + i) * 0.32).clamp(-0.75, 0.75));
    }
    final hs = dom == 'african' ? const ['hair_afro01', 'hair_short04', 'hair_short01'] : const ['hair_short01', 'hair_short02', 'hair_short03', 'hair_short04'];
    final hair = hs[stableHash(p.id, 0x4a1) % hs.length];
    return HumanLook(w, skin, hair, p.height, p.armLength);
  }

  /// 選手でない人（捕手・打者の仮の姿）
  factory HumanLook.generic(String id, {int heightCm = 180, int weightKg = 84, bool foreign = false}) {
    final p = Player(id: id, isPitcher: false, height: heightCm, nationality: foreign ? '海外' : '日本');
    p.bodyWeight = weightKg;
    return HumanLook.ofPlayer(p);
  }
}

/// 骨（53本）の動かし方：自分の骨格（15本）のどれについて動くか。背骨は腰と胴の間を補う
class _Owner {
  final int a, b;
  final double f;
  const _Owner(this.a, [this.b = -1, this.f = 0]);
}

/// MPFB の人体を、いまの関節の動き（15本の骨）で動かす
///  体（肌）＋目・眉・まつ毛・髪＋ユニフォームの層（体の形を少しふくらませた服）＋帽子
class HumanRig {
  final HumanAsset asset;
  final HumanLook look;
  final Uniform uni;
  final bool lefty;
  final Node root = Node();
  late final List<Node> joints;
  late final BakedHuman baked;
  late final double scale;
  late final BodyModel body; // 動きの計算に使う体（骨の長さを人体に合わせたもの）
  late final List<V3> restJ; // 立った姿勢の関節（本塁基準の座標の向き。原点に立ち +y を向く）
  final FrameSolver _solver = FrameSolver();
  late final List<_Owner> _own;
  late final List<vm.Matrix4> _offset; // 自分の骨 → 人体の骨
  late final List<vm.Matrix4> _rest; // 人体の骨の立った姿勢（3D の座標）

  HumanRig(this.asset, this.look, this.uni, {required BodyModel base, this.lefty = false}) {
    // 腕の長さを合わせる：上腕・前腕の長さの調整の効き方を骨で測って、1回で解く
    final w = Map<String, double>.from(look.weights);
    final hairPart = look.hair;
    final names = ['body', 'eyes', 'eyebrows', 'eyelashes', hairPart];
    final b0 = asset.bake(w, partNames: const []);
    double armRatio(BakedHuman bh) => bh.dist(bh.headOf('upperarm_r'), bh.tailOf('middle_03_r')) / bh.dist(bh.headOf('head'), bh.headOf('foot_r')).abs();
    final cur = armRatio(b0);
    final wUp = Map<String, double>.from(w)..update('measure-upperarm-length+', (v) => v + 0.5, ifAbsent: () => 0.5)..update('measure-lowerarm-length+', (v) => v + 0.5, ifAbsent: () => 0.5);
    final up = armRatio(asset.bake(wUp, partNames: const []));
    // 平均の体（調整なし）の腕の比が、選手の平均の腕の比（腕の長さ÷身長＝0.448）に当たるとして合わせる
    final r0 = armRatio(asset.bake(const {}, partNames: const []));
    final target = r0 * (look.armCm / look.heightCm) / 0.448;
    if ((up - cur).abs() > 1e-6) {
      final k = ((target - cur) / (up - cur) * 0.5).clamp(-0.8, 0.8);
      _addPm(w, 'measure-upperarm-length', k);
      _addPm(w, 'measure-lowerarm-length', k);
    }
    baked = asset.bake(w, partNames: names);
    scale = look.heightCm / 100.0 / baked.height;
    _buildSkeleton(base);
    _buildMeshes(names);
  }

  static void _addPm(Map<String, double> w, String n, double v) {
    if (v >= 0) {
      w['$n+'] = (w['$n+'] ?? 0) + v;
    } else {
      w['$n-'] = (w['$n-'] ?? 0) - v;
    }
  }

  /// Blender の座標 → 本塁基準の向き（原点に立って +y を向く）
  V3 _w(List<double> p) => V3(-p[0] * scale, -p[1] * scale, p[2] * scale);

  /// Blender の向き → 3D の向き：(x, y, z) → (x, z, −y)
  vm.Vector3 _c(double x, double y, double z) => vm.Vector3(x, z, -y);

  String get _t => lefty ? '_l' : '_r';
  String get _gs => lefty ? '_r' : '_l';

  void _buildSkeleton(BodyModel base) {
    final bh = baked;
    V3 hd(String n) => _w(bh.headOf(n));
    V3 tl(String n) => _w(bh.tailOf(n));
    final j = List<V3>.filled(J.values.length, V3.zero);
    j[J.pelvis.index] = hd('pelvis');
    j[J.hipT.index] = hd('thigh$_t');
    j[J.hipG.index] = hd('thigh$_gs');
    j[J.kneeT.index] = hd('calf$_t');
    j[J.kneeG.index] = hd('calf$_gs');
    j[J.ankleT.index] = hd('foot$_t');
    j[J.ankleG.index] = hd('foot$_gs');
    j[J.toeT.index] = tl('ball$_t');
    j[J.toeG.index] = tl('ball$_gs');
    j[J.neck.index] = hd('neck_01');
    j[J.head.index] = (hd('head') + tl('head')) * 0.5;
    j[J.shoulderT.index] = hd('upperarm$_t');
    j[J.shoulderG.index] = hd('upperarm$_gs');
    j[J.elbowT.index] = hd('lowerarm$_t');
    j[J.elbowG.index] = hd('lowerarm$_gs');
    j[J.wristT.index] = hd('hand$_t');
    j[J.wristG.index] = hd('hand$_gs');
    j[J.ball.index] = (hd('middle_01$_t') + tl('middle_03$_t')) * 0.5;
    j[J.glove.index] = (hd('middle_01$_gs') + tl('middle_03$_gs')) * 0.5;
    restJ = j;
    double d(J a, J b) => j[a.index].distanceTo(j[b.index]);
    body = base.copyWith(
      height: look.heightCm / 100.0,
      upperArm: d(J.shoulderT, J.elbowT),
      forearm: d(J.elbowT, J.wristT),
      hand: hd('hand$_t').distanceTo(tl('middle_03$_t')),
      thigh: d(J.hipT, J.kneeT),
      shank: d(J.kneeT, J.ankleT),
      footLen: d(J.ankleT, J.toeT) * 1.15,
      ankleH: j[J.ankleT.index].z,
      hipJointH: j[J.hipT.index].z,
      trunk: d(J.pelvis, J.neck),
      shoulderW: d(J.shoulderT, J.shoulderG),
      hipW: d(J.hipT, J.hipG),
    );
    // 人体の骨 → 自分の骨格の、どの骨について動くか
    _Owner own(String n) {
      final t = n.endsWith(_t), g = n.endsWith(_gs);
      final base2 = n.replaceAll(RegExp(r'_[lr]$'), '');
      if (n == 'Root' || n == 'pelvis') return const _Owner(0);
      if (n == 'spine_01') return const _Owner(0, 1, 0.35);
      if (n == 'spine_02') return const _Owner(0, 1, 0.65);
      if (n == 'spine_03') return const _Owner(0, 1, 0.9);
      if (n == 'neck_01' || n == 'head') return const _Owner(2);
      if (base2 == 'clavicle') return const _Owner(1);
      if (base2 == 'upperarm') return _Owner(t ? 3 : 6);
      if (base2 == 'lowerarm') return _Owner(t ? 4 : 7);
      if (base2 == 'thigh') return _Owner(t ? 9 : 12);
      if (base2 == 'calf') return _Owner(t ? 10 : 13);
      if (base2 == 'foot' || base2 == 'ball') return _Owner(t ? 11 : 14);
      if (t) return const _Owner(5); // 手・指
      if (g) return const _Owner(8);
      return const _Owner(1);
    }

    _own = [for (final b in asset.bones) own(b.name)];
    // 立った姿勢の人体の骨（3D の座標）：骨の向き（y）は頭→尾、x は Blender の骨の x を直交させて
    _rest = [];
    for (var i = 0; i < asset.bones.length; i++) {
      final m = asset.bones[i].matrix;
      final h0 = bh.head(i), t0 = bh.tail(i);
      final o = _c(h0[0], h0[1], h0[2]) * scale;
      var y = _c(t0[0] - h0[0], t0[1] - h0[1], t0[2] - h0[2]);
      if (y.length < 1e-6) y = _c(m[1], m[5], m[9]);
      y.normalize();
      var x = _c(m[0], m[4], m[8]);
      x = x - y * x.dot(y);
      if (x.length < 1e-6) x = vm.Vector3(1, 0, 0) - y * y.x;
      x.normalize();
      final z = x.cross(y)..normalize();
      _rest.add(vm.Matrix4.identity()
        ..setColumn(0, vm.Vector4(x.x, x.y, x.z, 0))
        ..setColumn(1, vm.Vector4(y.x, y.y, y.z, 0))
        ..setColumn(2, vm.Vector4(z.x, z.y, z.z, 0))
        ..setColumn(3, vm.Vector4(o.x, o.y, o.z, 1)));
    }
    final fr = _solver.solve(restJ);
    _offset = [for (var i = 0; i < asset.bones.length; i++) vm.Matrix4.inverted(_ownerMatrix(fr, _own[i])) * _rest[i]];
    joints = [for (var i = 0; i < asset.bones.length; i++) Node()];
    for (var i = 0; i < joints.length; i++) {
      joints[i].localTransform = _rest[i];
      root.add(joints[i]);
    }
  }

  static vm.Matrix4 _ownerMatrix(List<vm.Matrix4> fr, _Owner o) {
    if (o.b < 0) return fr[o.a];
    final a = fr[o.a], b = fr[o.b];
    final qa = vm.Quaternion.fromRotation(a.getRotation()), qb = vm.Quaternion.fromRotation(b.getRotation());
    if (qa.dot(qb) < 0) qb.setValues(-qb.x, -qb.y, -qb.z, -qb.w);
    final q = vm.Quaternion(qa.x + (qb.x - qa.x) * o.f, qa.y + (qb.y - qa.y) * o.f, qa.z + (qb.z - qa.z) * o.f, qa.w + (qb.w - qa.w) * o.f)..normalize();
    final t = a.getTranslation() + (b.getTranslation() - a.getTranslation()) * o.f;
    return vm.Matrix4.compose(t, q, vm.Vector3(1, 1, 1));
  }

  /// 関節の位置（本塁基準の座標）で動かす
  void pose(List<V3> p) {
    final fr = _solver.solve(p);
    for (var i = 0; i < joints.length; i++) {
      joints[i].localTransform = _ownerMatrix(fr, _own[i]) * _offset[i];
    }
  }

  // ───────── 形 ─────────
  void _buildMeshes(List<String> names) {
    final bp = baked.pos['body']!;
    final part = asset.parts['body']!;
    final nrm = _normals(bp, part.idx);
    root.add(_skinned(part, bp, nrm, part.idx, 0, mat(0xFFFFFFFF, rough: 0.55)..vertexColorWeight = 0, texture: 'skin_${look.skin}.png'));
    for (final n in names.skip(1)) {
      final pa = asset.parts[n];
      final pp = baked.pos[n];
      if (pa == null || pp == null) continue;
      final m = mat(n == 'eyes' ? 0xFFFFFFFF : 0xFFFFFFFF, rough: n == 'eyes' ? 0.15 : 0.7);
      if (n != 'eyes') {
        m.alphaMode = AlphaMode.mask;
        m.alphaCutoff = 0.4;
      }
      var idx = pa.idx;
      if (n.startsWith('hair')) {
        final cap = _capShape(bp, part);
        final keep = <int>[];
        for (var t = 0; t < idx.length; t += 3) {
          final zs = [pp[idx[t] * 3 + 2], pp[idx[t + 1] * 3 + 2], pp[idx[t + 2] * 3 + 2]];
          if (zs.reduce(math.max) < cap.cz + 0.008) keep.addAll([idx[t], idx[t + 1], idx[t + 2]]);
        }
        idx = Uint16List.fromList(keep);
      }
      root.add(_skinned(pa, pp, _normals(pp, pa.idx), idx, n.startsWith('hair') ? 0.002 : 0.0, m, texture: pa.tex));
    }
    _uniform(part, bp, nrm);
  }

  Float32List _normals(Float32List p, Uint16List idx) {
    final n = Float32List(p.length);
    for (var t = 0; t < idx.length; t += 3) {
      final a = idx[t] * 3, b = idx[t + 1] * 3, c = idx[t + 2] * 3;
      final ux = p[b] - p[a], uy = p[b + 1] - p[a + 1], uz = p[b + 2] - p[a + 2];
      final vx = p[c] - p[a], vy = p[c + 1] - p[a + 1], vz = p[c + 2] - p[a + 2];
      final nx = uy * vz - uz * vy, ny = uz * vx - ux * vz, nz = ux * vy - uy * vx;
      for (final k in [a, b, c]) {
        n[k] += nx;
        n[k + 1] += ny;
        n[k + 2] += nz;
      }
    }
    for (var i = 0; i < n.length; i += 3) {
      final l = math.sqrt(n[i] * n[i] + n[i + 1] * n[i + 1] + n[i + 2] * n[i + 2]);
      if (l > 0) {
        n[i] /= l;
        n[i + 1] /= l;
        n[i + 2] /= l;
      }
    }
    // 同じ位置で UV が分かれた頂点の法線をそろえる（継ぎ目が見えないように）
    final key = <String, List<int>>{};
    for (var i = 0; i < p.length; i += 3) {
      key.putIfAbsent('${(p[i] * 1e4).round()},${(p[i + 1] * 1e4).round()},${(p[i + 2] * 1e4).round()}', () => []).add(i);
    }
    for (final g in key.values) {
      if (g.length < 2) continue;
      var x = 0.0, y = 0.0, z = 0.0;
      for (final i in g) {
        x += n[i];
        y += n[i + 1];
        z += n[i + 2];
      }
      final l = math.sqrt(x * x + y * y + z * z);
      if (l == 0) continue;
      for (final i in g) {
        n[i] = x / l;
        n[i + 1] = y / l;
        n[i + 2] = z / l;
      }
    }
    return n;
  }

  /// 体の形からスキン付きの形を作る（inflate：法線の向きにふくらませる m）
  Node _skinned(AssetPart part, Float32List pos, Float32List nrm, Uint16List idx, double inflate, PhysicallyBasedMaterial m, {String? texture, List<int>? only}) {
    final verts = only ?? List<int>.generate(part.count, (i) => i);
    final map = <int, int>{};
    final v = <double>[];
    for (final i in verts) {
      map[i] = map.length;
      final c = _c(pos[i * 3] + nrm[i * 3] * inflate / scale, pos[i * 3 + 1] + nrm[i * 3 + 1] * inflate / scale, pos[i * 3 + 2] + nrm[i * 3 + 2] * inflate / scale) * scale;
      final nn = _c(nrm[i * 3], nrm[i * 3 + 1], nrm[i * 3 + 2]);
      v.addAll([c.x, c.y, c.z, nn.x, nn.y, nn.z, part.uv[i * 2], 1 - part.uv[i * 2 + 1], 0, 0, 1, 1, 1, 1, 1, 0, 0, 1,
        part.joints[i * 4].toDouble(), part.joints[i * 4 + 1].toDouble(), part.joints[i * 4 + 2].toDouble(), part.joints[i * 4 + 3].toDouble(),
        part.weights[i * 4], part.weights[i * 4 + 1], part.weights[i * 4 + 2], part.weights[i * 4 + 3]]);
    }
    final ix = <int>[];
    for (var t = 0; t < idx.length; t += 3) {
      final a = map[idx[t]], b = map[idx[t + 1]], c = map[idx[t + 2]];
      if (a != null && b != null && c != null) ix.addAll([a, b, c]);
    }
    final g = SkinnedGeometry();
    final vf = Float32List.fromList(v);
    g.uploadVertexData(vf.buffer.asByteData(), map.length, Uint16List.fromList(ix).buffer.asByteData());
    final s = Skin();
    s.joints.addAll(joints);
    for (final r in _rest) {
      s.inverseBindMatrices.add(vm.Matrix4.inverted(r));
    }
    if (texture != null) HumanTextures.apply(m, 'assets/body/${texture.split('/').last}');
    m.doubleSided = true;
    return Node(mesh: Mesh(g, m))..skin = s;
  }

  /// ユニフォームの層：体の形を部位ごとに分けて少しふくらませる（上衣・アンダーシャツ・ベルト・パンツ・ストッキング・スパイク）＋帽子
  void _uniform(AssetPart part, Float32List bp, Float32List nrm) {
    final bi = {for (var i = 0; i < asset.bones.length; i++) asset.bones[i].name: i};
    final bh = baked;
    double along(int vi, String bone) {
      final h = bh.headOf(bone), t = bh.tailOf(bone);
      final dx = t[0] - h[0], dy = t[1] - h[1], dz = t[2] - h[2];
      final l2 = dx * dx + dy * dy + dz * dz;
      return ((bp[vi * 3] - h[0]) * dx + (bp[vi * 3 + 1] - h[1]) * dy + (bp[vi * 3 + 2] - h[2]) * dz) / l2;
    }

    final beltZ = (bh.headOf('pelvis')[2] + bh.headOf('spine_01')[2]) / 2 + 0.01;
    final neckZ = bh.headOf('neck_01')[2] - 0.035;
    // 0 肌 1 上衣 2 アンダー 3 パンツ 4 ストッキング 5 スパイク 6 ベルト
    final cls = Int8List(part.count);
    for (var i = 0; i < part.count; i++) {
      var best = 0, bw = -1.0;
      for (var k = 0; k < 4; k++) {
        if (part.weights[i * 4 + k] > bw) {
          bw = part.weights[i * 4 + k];
          best = part.joints[i * 4 + k];
        }
      }
      final name = asset.bones[best].name.replaceAll(RegExp(r'_[lr]$'), '');
      final z = bp[i * 3 + 2];
      int c;
      switch (name) {
        case 'head' || 'neck_01' || 'hand' || 'thumb_01' || 'thumb_02' || 'thumb_03' || 'index_01' || 'index_02' || 'index_03' || 'middle_01' || 'middle_02' || 'middle_03' || 'ring_01' || 'ring_02' || 'ring_03' || 'pinky_01' || 'pinky_02' || 'pinky_03':
          c = 0;
        case 'lowerarm':
          c = along(i, asset.bones[best].name) > 0.9 ? 0 : 2;
        case 'upperarm':
          c = along(i, asset.bones[best].name) < 0.5 ? 1 : 2;
        case 'clavicle' || 'spine_02' || 'spine_03' || 'spine_01':
          c = z > neckZ ? 0 : 1;
        case 'pelvis' || 'Root':
          c = (z - beltZ).abs() < 0.022 ? 6 : (z > beltZ ? 1 : 3);
        case 'thigh':
          c = 3;
        case 'calf':
          c = along(i, asset.bones[best].name) < 0.55 ? 3 : 4;
        case 'foot' || 'ball':
          c = 5;
        default:
          c = 1;
      }
      if (c == 1 && (z - beltZ).abs() < 0.022) c = 6;
      cls[i] = c;
    }
    final faces = <int, List<int>>{};
    for (var t = 0; t < part.idx.length; t += 3) {
      final a = cls[part.idx[t]], b = cls[part.idx[t + 1]], c = cls[part.idx[t + 2]];
      for (final f in {a, b, c}) {
        if (f == 0) continue;
        faces.putIfAbsent(f, () => []).addAll([part.idx[t], part.idx[t + 1], part.idx[t + 2]]);
      }
    }
    final layer = {1: (uni.base, 0.014, 0.75), 2: (uni.undershirt, 0.006, 0.7), 3: (uni.base, 0.019, 0.75), 4: (uni.socks, 0.007, 0.7), 5: (uni.shoes, 0.013, 0.35), 6: (uni.belt, 0.022, 0.5)};
    faces.forEach((c, ix) {
      final (color, inflate, rough) = layer[c]!;
      final used = ix.toSet().toList();
      root.add(_skinned(part, bp, nrm, Uint16List.fromList(ix), inflate, mat(color, rough: rough), only: used));
    });
    // 帽子：頭の骨に付ける半球（頭のてっぺんの形に合わせて）
    _cap(bi['head']!, bp, part);
  }

  ({double cx, double cy, double cz, double rx, double ry, double top})? _capCache;

  /// 帽子の形（Blender の座標）：頭の骨に付く頂点の範囲から、髪ごと頭の上を覆う大きさ
  ({double cx, double cy, double cz, double rx, double ry, double top}) _capShape(Float32List bp, AssetPart part) {
    if (_capCache != null) return _capCache!;
    final headBone = asset.boneIndex('head');
    var minX = 1e9, maxX = -1e9, minY = 1e9, maxY = -1e9, maxZ = -1e9, minZ = 1e9;
    for (var i = 0; i < part.count; i++) {
      if (part.joints[i * 4] != headBone || part.weights[i * 4] < 0.9) continue;
      minX = math.min(minX, bp[i * 3]);
      maxX = math.max(maxX, bp[i * 3]);
      minY = math.min(minY, bp[i * 3 + 1]);
      maxY = math.max(maxY, bp[i * 3 + 1]);
      minZ = math.min(minZ, bp[i * 3 + 2]);
      maxZ = math.max(maxZ, bp[i * 3 + 2]);
    }
    final rz = maxZ - minZ;
    return _capCache = (cx: (minX + maxX) / 2, cy: (minY + maxY) / 2 + 0.008, cz: maxZ - rz * 0.40, rx: (maxX - minX) / 2 * 1.17, ry: (maxY - minY) / 2 * 1.13, top: maxZ + 0.03);
  }

  void _cap(int headBone, Float32List bp, AssetPart part) {
    final c = _capShape(bp, part);
    final cx = c.cx, cy = c.cy, cz = c.cz, rx = c.rx, ry = c.ry;
    final hz = c.top - cz;
    final v = <double>[];
    final ix = <int>[];
    const rings = 10, seg = 24;
    void vert(double bx, double by, double bz, double nx, double ny, double nz) {
      final c = _c(bx, by, bz) * scale;
      final nn = _c(nx, ny, nz)..normalize();
      v.addAll([c.x, c.y, c.z, nn.x, nn.y, nn.z, 0, 0, 0, 0, 1, 1, 1, 1, 1, 0, 0, 1, headBone.toDouble(), 0, 0, 0, 1, 0, 0, 0]);
    }

    for (var i = 0; i <= rings; i++) {
      final th = 0.5 * math.pi * i / rings;
      for (var j = 0; j <= seg; j++) {
        final ph = 2 * math.pi * j / seg;
        final dx = math.sin(th) * math.cos(ph), dy = math.sin(th) * math.sin(ph), dz = math.cos(th);
        vert(cx + dx * rx, cy + dy * ry, cz + dz * hz, dx / rx, dy / ry, dz / hz);
      }
    }
    for (var i = 0; i < rings; i++) {
      for (var j = 0; j < seg; j++) {
        final a = i * (seg + 1) + j, b = a + seg + 1;
        ix.addAll([a, b, a + 1, a + 1, b, b + 1]);
      }
    }
    // つば（前＝−Y）
    final base = v.length ~/ 26;
    for (var j = 0; j <= 12; j++) {
      final ph = math.pi * (0.15 + 0.7 * j / 12);
      final dx = math.cos(ph), dy = -math.sin(ph);
      vert(cx + dx * rx, cy + dy * ry, cz + 0.004, 0, 0, 1);
      vert(cx + dx * rx * 1.05, cy + dy * (ry + 0.075), cz - 0.012, 0, 0, 1);
    }
    for (var j = 0; j < 12; j++) {
      final a = base + j * 2;
      ix.addAll([a, a + 1, a + 2, a + 2, a + 1, a + 3]);
    }
    final g = SkinnedGeometry();
    g.uploadVertexData(Float32List.fromList(v).buffer.asByteData(), v.length ~/ 26, Uint16List.fromList(ix).buffer.asByteData());
    final s = Skin();
    s.joints.addAll(joints);
    for (final r in _rest) {
      s.inverseBindMatrices.add(vm.Matrix4.inverted(r));
    }
    final m = mat(uni.capBase, rough: 0.6)..doubleSided = true;
    root.add(Node(mesh: Mesh(g, m))..skin = s);
  }
}

/// 画像（肌・目・髪）の読み込み（同じ画像は1回だけ）
class HumanTextures {
  static final _cache = <String, Future<GpuTextureSource?>>{};
  static void apply(PhysicallyBasedMaterial m, String asset) {
    final f = _cache.putIfAbsent(asset, () async {
      try {
        return GpuTextureSource(await gpuTextureFromAsset(asset));
      } catch (_) {
        return null;
      }
    });
    f.then((t) {
      if (t != null) m.baseColorTexture = t;
    });
  }
}
