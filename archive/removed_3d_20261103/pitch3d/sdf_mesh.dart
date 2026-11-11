import 'dart:math' as math;

import '../../engine/vec3.dart';

/// 粘土のようになめらかにつながる形（符号付き距離）から、継ぎ目のない表面を作る（Surface Nets）
///  部品（丸い円錐・楕円体）を少しずつ溶かし合わせ（smooth union）、骨の重みは近い部品の重みを距離でなめらかに混ぜる
///  Flutter に依存しない（テストできる）

typedef BoneW = List<(int, double)>;

abstract class SdfPrim {
  final double blend; // ほかの部品と溶かし合わせる幅（m）
  SdfPrim(this.blend);
  double dist(V3 p);
  BoneW weights(V3 p);
  (V3, V3) get bounds;
}

/// 両端の半径が違う丸い円錐（腕・脚・指・胴の芯）。weights は a→b の位置 t（0〜1）で骨の重みを返す
class RoundCone extends SdfPrim {
  final V3 a, b;
  final double ra, rb;
  final BoneW Function(double t) w;
  RoundCone(this.a, this.b, this.ra, this.rb, this.w, {double blend = 0.02}) : super(blend);

  double _t(V3 p) {
    final ba = b - a;
    final l2 = ba.length2;
    return l2 < 1e-12 ? 0 : ((p - a).dot(ba) / l2).clamp(0.0, 1.0);
  }

  @override
  double dist(V3 p) {
    // iq の round cone
    final ba = b - a;
    final l2 = ba.length2;
    final rr = ra - rb;
    final a2 = l2 - rr * rr;
    final il2 = 1.0 / l2;
    final pa = p - a;
    final y = pa.dot(ba);
    final z = y - l2;
    final xv = pa * l2 - ba * y;
    final x2 = xv.length2;
    final y2 = y * y * l2;
    final z2 = z * z * l2;
    final k = rr.sign * rr * rr * x2;
    if (z.sign * a2 * z2 > k) return math.sqrt(x2 + z2) * il2 - rb;
    if (y.sign * a2 * y2 < k) return math.sqrt(x2 + y2) * il2 - ra;
    return (math.sqrt(x2 * a2 * il2) + y * rr) * il2 - ra;
  }

  @override
  BoneW weights(V3 p) => w(_t(p));

  @override
  (V3, V3) get bounds {
    final r = math.max(ra, rb) + blend;
    return (V3(math.min(a.x, b.x) - r, math.min(a.y, b.y) - r, math.min(a.z, b.z) - r), V3(math.max(a.x, b.x) + r, math.max(a.y, b.y) + r, math.max(a.z, b.z) + r));
  }
}

/// 楕円体（軸は単位ベクトル ux, uy, uz と半径）
class Ellipsoid extends SdfPrim {
  final V3 c, ux, uy, uz;
  final double rx, ry, rz;
  final BoneW w;
  Ellipsoid(this.c, this.ux, this.uy, this.uz, this.rx, this.ry, this.rz, this.w, {double blend = 0.02}) : super(blend);

  /// 軸がそろった楕円体
  factory Ellipsoid.aligned(V3 c, double rx, double ry, double rz, BoneW w, {double blend = 0.02}) => Ellipsoid(c, V3.ex, V3.ey, V3.ez, rx, ry, rz, w, blend: blend);

  @override
  double dist(V3 p) {
    final d = p - c;
    final q = V3(d.dot(ux), d.dot(uy), d.dot(uz));
    final k0 = V3(q.x / rx, q.y / ry, q.z / rz).length;
    final k1 = V3(q.x / (rx * rx), q.y / (ry * ry), q.z / (rz * rz)).length;
    if (k1 < 1e-12) return -math.min(rx, math.min(ry, rz));
    return k0 * (k0 - 1.0) / k1;
  }

  @override
  BoneW weights(V3 p) => w;

  @override
  (V3, V3) get bounds {
    final r = math.max(rx, math.max(ry, rz)) + blend;
    return (c - V3(r, r, r), c + V3(r, r, r));
  }
}

/// 表面（頂点・法線・骨の重み・三角形）
class SdfSurface {
  final List<V3> pos = [];
  final List<V3> nrm = [];
  final List<BoneW> w = [];
  final List<int> tri = [];
}

double _smin(double a, double b, double k) {
  if (k <= 0) return math.min(a, b);
  final h = (0.5 + 0.5 * (b - a) / k).clamp(0.0, 1.0);
  return b + (a - b) * h - k * h * (1 - h);
}

/// 部品をすべて溶かし合わせた距離
double sdfOf(List<SdfPrim> prims, V3 p) {
  var d = 1e9;
  for (final s in prims) {
    d = _smin(d, s.dist(p), s.blend);
  }
  return d;
}

/// Surface Nets：格子（cell m）で表面を取り出す。maxCells を超えるときは格子を粗くする
SdfSurface buildSurface(List<SdfPrim> prims, {double cell = 0.012, int maxCells = 260000, double weightSoft = 0.025}) {
  final out = SdfSurface();
  if (prims.isEmpty) return out;
  var lo = prims.first.bounds.$1, hi = prims.first.bounds.$2;
  for (final s in prims) {
    final (a, b) = s.bounds;
    lo = V3(math.min(lo.x, a.x), math.min(lo.y, a.y), math.min(lo.z, a.z));
    hi = V3(math.max(hi.x, b.x), math.max(hi.y, b.y), math.max(hi.z, b.z));
  }
  var h = cell;
  int nx, ny, nz;
  while (true) {
    nx = ((hi.x - lo.x) / h).ceil() + 2;
    ny = ((hi.y - lo.y) / h).ceil() + 2;
    nz = ((hi.z - lo.z) / h).ceil() + 2;
    if (nx * ny * nz <= maxCells) break;
    h *= 1.15;
  }
  final o = lo - V3(h, h, h);
  V3 at(int i, int j, int k) => V3(o.x + i * h, o.y + j * h, o.z + k * h);
  // 格子点の距離（部品の範囲外はその部品を飛ばして速くする）
  final field = List<double>.filled((nx + 1) * (ny + 1) * (nz + 1), 1e9);
  int gi(int i, int j, int k) => (k * (ny + 1) + j) * (nx + 1) + i;
  for (final s in prims) {
    final (a, b) = s.bounds;
    final i0 = math.max(0, ((a.x - o.x) / h).floor() - 1), i1 = math.min(nx, ((b.x - o.x) / h).ceil() + 1);
    final j0 = math.max(0, ((a.y - o.y) / h).floor() - 1), j1 = math.min(ny, ((b.y - o.y) / h).ceil() + 1);
    final k0 = math.max(0, ((a.z - o.z) / h).floor() - 1), k1 = math.min(nz, ((b.z - o.z) / h).ceil() + 1);
    for (var k = k0; k <= k1; k++) {
      for (var j = j0; j <= j1; j++) {
        for (var i = i0; i <= i1; i++) {
          final idx = gi(i, j, k);
          field[idx] = _smin(field[idx], s.dist(at(i, j, k)), s.blend);
        }
      }
    }
  }
  // 表面をまたぐ格子のマスに1つの頂点（12本の辺の交点の平均）
  final cellVert = <int, int>{};
  int ci(int i, int j, int k) => (k * ny + j) * nx + i;
  const corners = [
    [0, 0, 0], [1, 0, 0], [0, 1, 0], [1, 1, 0], [0, 0, 1], [1, 0, 1], [0, 1, 1], [1, 1, 1],
  ];
  const edges = [
    [0, 1], [2, 3], [4, 5], [6, 7], [0, 2], [1, 3], [4, 6], [5, 7], [0, 4], [1, 5], [2, 6], [3, 7],
  ];
  V3 grad(V3 p) {
    final e = h * 0.5;
    return V3(
      sdfOf(prims, p + V3(e, 0, 0)) - sdfOf(prims, p - V3(e, 0, 0)),
      sdfOf(prims, p + V3(0, e, 0)) - sdfOf(prims, p - V3(0, e, 0)),
      sdfOf(prims, p + V3(0, 0, e)) - sdfOf(prims, p - V3(0, 0, e)),
    ).unit;
  }

  for (var k = 0; k < nz; k++) {
    for (var j = 0; j < ny; j++) {
      for (var i = 0; i < nx; i++) {
        final v = [for (final c in corners) field[gi(i + c[0], j + c[1], k + c[2])]];
        var neg = 0;
        for (final x in v) {
          if (x < 0) neg++;
        }
        if (neg == 0 || neg == 8) continue;
        var sum = V3.zero;
        var cnt = 0;
        for (final e in edges) {
          final a = v[e[0]], b = v[e[1]];
          if ((a < 0) == (b < 0)) continue;
          final t = a / (a - b);
          final ca = corners[e[0]], cb = corners[e[1]];
          final pa = at(i + ca[0], j + ca[1], k + ca[2]), pb = at(i + cb[0], j + cb[1], k + cb[2]);
          sum = sum + pa.lerp(pb, t);
          cnt++;
        }
        final p = sum / cnt.toDouble();
        cellVert[ci(i, j, k)] = out.pos.length;
        out.pos.add(p);
        out.nrm.add(grad(p));
        out.w.add(_blendWeights(prims, p, weightSoft));
      }
    }
  }
  // 表面をまたぐ格子の辺ごとに、まわりの4つのマスの頂点で四角形
  void quad(int a, int b, int c, int d, bool flip) {
    if (!flip) {
      out.tri.addAll([a, c, b, a, d, c]);
    } else {
      out.tri.addAll([a, b, c, a, c, d]);
    }
  }

  for (var k = 1; k < nz; k++) {
    for (var j = 1; j < ny; j++) {
      for (var i = 0; i < nx; i++) {
        // x の辺 (i,j,k)-(i+1,j,k)
        final a = field[gi(i, j, k)], b = field[gi(i + 1, j, k)];
        if ((a < 0) == (b < 0)) continue;
        final v0 = cellVert[ci(i, j - 1, k - 1)], v1 = cellVert[ci(i, j, k - 1)], v2 = cellVert[ci(i, j, k)], v3 = cellVert[ci(i, j - 1, k)];
        if (v0 == null || v1 == null || v2 == null || v3 == null) continue;
        quad(v0, v1, v2, v3, a < 0);
      }
    }
  }
  for (var k = 1; k < nz; k++) {
    for (var j = 0; j < ny; j++) {
      for (var i = 1; i < nx; i++) {
        // y の辺
        final a = field[gi(i, j, k)], b = field[gi(i, j + 1, k)];
        if ((a < 0) == (b < 0)) continue;
        final v0 = cellVert[ci(i - 1, j, k - 1)], v1 = cellVert[ci(i, j, k - 1)], v2 = cellVert[ci(i, j, k)], v3 = cellVert[ci(i - 1, j, k)];
        if (v0 == null || v1 == null || v2 == null || v3 == null) continue;
        quad(v0, v1, v2, v3, b < 0);
      }
    }
  }
  for (var k = 0; k < nz; k++) {
    for (var j = 1; j < ny; j++) {
      for (var i = 1; i < nx; i++) {
        // z の辺
        final a = field[gi(i, j, k)], b = field[gi(i, j, k + 1)];
        if ((a < 0) == (b < 0)) continue;
        final v0 = cellVert[ci(i - 1, j - 1, k)], v1 = cellVert[ci(i, j - 1, k)], v2 = cellVert[ci(i, j, k)], v3 = cellVert[ci(i - 1, j, k)];
        if (v0 == null || v1 == null || v2 == null || v3 == null) continue;
        quad(v0, v1, v2, v3, a < 0);
      }
    }
  }
  return out;
}

/// 近い部品ほど強く：部品の骨の重みを距離でなめらかに混ぜ、大きい4つまで
BoneW _blendWeights(List<SdfPrim> prims, V3 p, double soft) {
  final ds = [for (final s in prims) s.dist(p)];
  final dmin = ds.reduce(math.min);
  final acc = <int, double>{};
  for (var i = 0; i < prims.length; i++) {
    final a = math.exp(-(ds[i] - dmin) / soft);
    if (a < 0.02) continue;
    for (final (bone, wt) in prims[i].weights(p)) {
      acc[bone] = (acc[bone] ?? 0) + wt * a;
    }
  }
  final l = acc.entries.toList()..sort((x, y) => y.value.compareTo(x.value));
  final top = l.take(4).toList();
  final sum = top.fold(0.0, (s, e) => s + e.value);
  return [for (final e in top) (e.key, sum > 0 ? e.value / sum : 0.0)];
}
