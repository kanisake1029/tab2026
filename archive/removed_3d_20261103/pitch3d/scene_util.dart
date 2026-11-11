import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../../engine/vec3.dart';

/// 本塁基準の座標（x＝一塁側、y＝投手の方向、z＝上）→ 3D の座標（x＝三塁側、y＝上、z＝投手の方向）
///  捕手から投手の方を見たとき、一塁側が画面の右になる向き（回転なので左右は反転しない）
vm.Vector3 sv(V3 w) => vm.Vector3(-w.x, w.z, w.y);
vm.Vector3 svXYZ(double x, double y, double z) => vm.Vector3(-x, z, y);

/// 色（0xAARRGGBB。画面の色＝sRGB）→ 光の計算に使う値（リニア）。変換しないと全体が白っぽく浮いて見える
vm.Vector4 rgba(int argb) => vm.Vector4(_lin((argb >> 16) & 255), _lin((argb >> 8) & 255), _lin(argb & 255), ((argb >> 24) & 255) / 255);

double _lin(int c) {
  final v = c / 255.0;
  return v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
}

PhysicallyBasedMaterial mat(int argb, {double rough = 0.8, double metal = 0.0}) => PhysicallyBasedMaterial()
  ..baseColorFactor = rgba(argb | 0xFF000000)
  ..roughnessFactor = rough
  ..metallicFactor = metal;

Node nd({Mesh? mesh, vm.Vector3? position, vm.Vector3? scale, vm.Quaternion? rotation}) {
  final n = Node(mesh: mesh);
  if (position != null) n.position = position;
  if (scale != null) n.scale = scale;
  if (rotation != null) n.rotation = rotation;
  return n;
}

/// 頂点の色つきの形を、6万頂点ごとに分けて作る（16bit の番号に収める）
class ColorMesh {
  final List<GeometryBuilder> _done = [];
  GeometryBuilder _b = GeometryBuilder(deduplicate: false);
  vm.Vector4 _c = vm.Vector4(1, 1, 1, 1);

  /// 面の向きをそろえる：faceUp＝上向きに、faceTo＝この点（本塁基準の座標）の方に向ける（水平に近い面は上向き）。どちらも無ければ点の順のまま
  bool faceUp = false;
  bool faceDown = false; // 下向き（天井）
  V3? faceTo;
  bool _raw = false;

  /// 光の当たり方を頂点の色に焼き込む（光の計算をしない軽い描き方で、これまでの PBR の明るさに合わせる）。
  ///  日差し（Play3D の DirectionalLight：強さ 5.5、本塁の後ろ・三塁側の上から）のランバート＋まわりの明るさ
  bool bake = false;
  static const V3 _sun = V3(-0.304, -0.391, 0.869); // 光の来る向き（本塁基準の座標）
  vm.Vector4 _lit(V3 a, V3 b, V3 c) {
    if (!bake) return _c;
    final n = (b - a).cross(c - a);
    final l = n.length;
    if (l < 1e-12) return _c;
    final nn = n / l;
    final k = 1.75 * math.max(0.0, nn.dot(_sun)) + 0.33 + 0.1 * nn.z;
    return vm.Vector4(_c.x * k, _c.y * k, _c.z * k, _c.w);
  }

  bool _flip(V3 a, V3 b, V3 c) {
    if (_raw) return false;
    final n = (b - a).cross(c - a);
    if (faceDown) return n.z > 0;
    if (faceUp) return n.z < 0;
    final t = faceTo;
    if (t == null) return false;
    if (n.z.abs() > 0.7 * n.length) return n.z < 0; // ほぼ水平な面は上向き
    return n.dot(t - (a + b + c) / 3) < 0;
  }

  /// 調べ用（PC で球場を絵にする）：ここに三角形を記録する（null なら記録しない）
  static List<(V3, V3, V3, int)>? record;
  int _argb = 0xFFFFFFFF;
  void color(int argb) {
    _argb = argb | 0xFF000000;
    _c = rgba(_argb);
  }

  void _room(int n) {
    if (_b.vertexCount + n > 60000) {
      _done.add(_b);
      _b = GeometryBuilder(deduplicate: false);
    }
  }

  /// 4点（本塁基準の座標）の四角。法線は自動（向きは a→b→c の右回り/左回りに従う）
  void quad(V3 a, V3 b, V3 c, V3 d) {
    if (_flip(a, b, c)) {
      final t = b;
      b = d;
      d = t;
    }
    record?.add((a, b, c, _argb));
    record?.add((a, c, d, _argb));
    _room(4);
    final pa = sv(a), pb = sv(b), pc = sv(c), pd = sv(d);
    final n = (pb - pa).cross(pc - pa)..normalize();
    _b.color(_lit(a, b, c)).normal(n);
    final i0 = _b.addVertex(pa), i1 = _b.addVertex(pb), i2 = _b.addVertex(pc), i3 = _b.addVertex(pd);
    _b.addTriangle(i0, i1, i2);
    _b.addTriangle(i0, i2, i3);
  }

  /// 凸多角形（点の順に一周）。頂点は1回ずつ足して、扇形に三角形を張る（観客など数の多いものの頂点を減らす）
  void poly(List<V3> pts) {
    if (pts.length < 3) return;
    final p = _flip(pts[0], pts[1], pts[2]) ? pts.reversed.toList() : pts;
    for (var i = 1; i + 1 < p.length; i++) {
      record?.add((p[0], p[i], p[i + 1], _argb));
    }
    _room(p.length);
    final sp = [for (final q in p) sv(q)];
    final n = (sp[1] - sp[0]).cross(sp[2] - sp[0])..normalize();
    _b.color(_lit(p[0], p[1], p[2])).normal(n);
    final idx = [for (final q in sp) _b.addVertex(q)];
    for (var i = 1; i + 1 < idx.length; i++) {
      _b.addTriangle(idx[0], idx[i], idx[i + 1]);
    }
  }

  void tri(V3 a, V3 b, V3 c) {
    if (_flip(a, b, c)) {
      final t = b;
      b = c;
      c = t;
    }
    record?.add((a, b, c, _argb));
    _room(3);
    final pa = sv(a), pb = sv(b), pc = sv(c);
    final n = (pb - pa).cross(pc - pa)..normalize();
    _b.color(_lit(a, b, c)).normal(n);
    _b.addTriangle(_b.addVertex(pa), _b.addVertex(pb), _b.addVertex(pc));
  }

  /// 箱（中心 c・大きさ・z 軸まわりの向き）
  void box(V3 c, double sx, double sy, double sz, {double yaw = 0}) {
    final cs = _cos(yaw), sn = _sin(yaw);
    V3 p(double x, double y, double z) => V3(c.x + x * cs - y * sn, c.y + x * sn + y * cs, c.z + z);
    _raw = true;
    final hx = sx / 2, hy = sy / 2, hz = sz / 2;
    final v = [p(-hx, -hy, -hz), p(hx, -hy, -hz), p(hx, hy, -hz), p(-hx, hy, -hz), p(-hx, -hy, hz), p(hx, -hy, hz), p(hx, hy, hz), p(-hx, hy, hz)];
    quad(v[4], v[5], v[6], v[7]); // 上
    quad(v[3], v[2], v[1], v[0]); // 下
    quad(v[0], v[1], v[5], v[4]);
    quad(v[1], v[2], v[6], v[5]);
    quad(v[2], v[3], v[7], v[6]);
    quad(v[3], v[0], v[4], v[7]);
    _raw = false;
  }

  static double _cos(double a) => math.cos(a);
  static double _sin(double a) => math.sin(a);

  List<Node> nodes(Material m) {
    final all = [..._done, _b];
    return [
      for (final b in all)
        if (b.vertexCount > 0) Node(mesh: Mesh(b.build(), m)),
    ];
  }
}
