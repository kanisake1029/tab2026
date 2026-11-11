import 'dart:math' as m;

/// 3次元のベクトル（物理・運動の計算用。Flutter に依存しない）
///  座標（本塁基準・捕手から見て）：x＝右（一塁側）、y＝投手の方向、z＝上。原点は本塁の後ろの角の地面
class V3 {
  final double x, y, z;
  const V3(this.x, this.y, this.z);
  static const zero = V3(0, 0, 0);
  static const ex = V3(1, 0, 0), ey = V3(0, 1, 0), ez = V3(0, 0, 1);

  V3 operator +(V3 o) => V3(x + o.x, y + o.y, z + o.z);
  V3 operator -(V3 o) => V3(x - o.x, y - o.y, z - o.z);
  V3 operator *(double k) => V3(x * k, y * k, z * k);
  V3 operator /(double k) => V3(x / k, y / k, z / k);
  V3 operator -() => V3(-x, -y, -z);
  double dot(V3 o) => x * o.x + y * o.y + z * o.z;
  V3 cross(V3 o) => V3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);
  double get length2 => x * x + y * y + z * z;
  double get length => m.sqrt(length2);
  V3 get unit {
    final l = length;
    return l < 1e-12 ? V3.zero : this / l;
  }

  /// o に垂直な成分（o は単位ベクトル）
  V3 perpTo(V3 o) => this - o * dot(o);
  V3 lerp(V3 o, double t) => this + (o - this) * t;
  double distanceTo(V3 o) => (this - o).length;

  /// 単位ベクトル axis のまわりに ang（ラジアン）回す（ロドリゲスの式）
  V3 rotate(V3 axis, double ang) {
    final c = m.cos(ang), s = m.sin(ang);
    return this * c + axis.cross(this) * s + axis * (axis.dot(this) * (1 - c));
  }

  V3 get mirrorX => V3(-x, y, z);

  /// 2つの向きのなす角（度）
  double angleTo(V3 o) {
    final d = (unit.dot(o.unit)).clamp(-1.0, 1.0);
    return m.acos(d) * 180 / m.pi;
  }

  @override
  String toString() => '(${x.toStringAsFixed(3)}, ${y.toStringAsFixed(3)}, ${z.toStringAsFixed(3)})';
}

const deg = m.pi / 180;
