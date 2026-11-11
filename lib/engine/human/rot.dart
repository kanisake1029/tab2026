import 'dart:math' as m;

import '../vec3.dart';

/// 3×3 の回転（列＝回したあとの x・y・z の軸）。人体の骨の向きの計算用
class M3 {
  final V3 c0, c1, c2;
  const M3(this.c0, this.c1, this.c2);
  static const identity = M3(V3.ex, V3.ey, V3.ez);

  V3 operator *(V3 v) => c0 * v.x + c1 * v.y + c2 * v.z;
  M3 mul(M3 o) => M3(this * o.c0, this * o.c1, this * o.c2);
  M3 get t => M3(V3(c0.x, c1.x, c2.x), V3(c0.y, c1.y, c2.y), V3(c0.z, c1.z, c2.z));

  /// 要素（i 行 j 列）
  double e(int i, int j) {
    final c = j == 0 ? c0 : (j == 1 ? c1 : c2);
    return i == 0 ? c.x : (i == 1 ? c.y : c.z);
  }

  /// x 軸のまわり（度）
  static M3 rx(double d) {
    final a = d * deg, c = m.cos(a), s = m.sin(a);
    return M3(V3.ex, V3(0, c, s), V3(0, -s, c));
  }

  static M3 ry(double d) {
    final a = d * deg, c = m.cos(a), s = m.sin(a);
    return M3(V3(c, 0, -s), V3.ey, V3(s, 0, c));
  }

  static M3 rz(double d) {
    final a = d * deg, c = m.cos(a), s = m.sin(a);
    return M3(V3(c, s, 0), V3(-s, c, 0), V3.ez);
  }

  /// 体の向き h（ラジアン。0＝中堅、＋＝一塁側へ）：x＝右、y＝正面、z＝上
  static M3 heading(double h) => M3(V3(m.cos(h), -m.sin(h), 0), V3(m.sin(h), m.cos(h), 0), V3.ez);

  /// 骨の向き y と x の参照から（z＝x×y の右手系）
  static M3 fromYX(V3 y, V3 xRef) {
    final yy = y.unit;
    var x = xRef.perpTo(yy);
    if (x.length < 1e-6) x = V3.ex.perpTo(yy).length > 1e-3 ? V3.ex.perpTo(yy) : V3.ey.perpTo(yy);
    x = x.unit;
    return M3(x, yy, x.cross(yy));
  }
}

double clampD(double v, double lo, double hi) => v < lo ? lo : (v > hi ? hi : v);

/// 角度（度）を −180〜180 へ
double wrap180(double a) {
  var x = (a + 180) % 360;
  if (x < 0) x += 360;
  return x - 180;
}
