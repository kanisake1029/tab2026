import 'dart:math' as m;
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/engine/vec3.dart';
import 'package:npb_pennant_app/widgets/pitch3d/sdf_mesh.dart';

void main() {
  test('球と腕：表面の大きさ・三角形の向き・骨の重み', () {
    final sphere = Ellipsoid.aligned(V3.zero, 0.1, 0.1, 0.1, [(0, 1.0)]);
    final arm = RoundCone(const V3(0.3, 0, 0), const V3(0.6, 0, 0), 0.05, 0.035, (t) => t < 0.5 ? [(1, 1.0)] : [(2, 1.0)]);
    final s = buildSurface([sphere, arm], cell: 0.01);
    expect(s.pos.length, greaterThan(500));
    var bad = 0, tris = 0;
    for (var i = 0; i < s.tri.length; i += 3) {
      final a = s.pos[s.tri[i]], b = s.pos[s.tri[i + 1]], c = s.pos[s.tri[i + 2]];
      final n = (b - a).cross(c - a);
      if (n.length < 1e-12) continue;
      tris++;
      final g = (s.nrm[s.tri[i]] + s.nrm[s.tri[i + 1]] + s.nrm[s.tri[i + 2]]);
      if (n.dot(g) < 0) bad++;
    }
    // ignore: avoid_print
    print('頂点${s.pos.length} 三角形$tris 裏向き$bad');
    expect(bad / tris, lessThan(0.02));
    // 球の上の点は半径 0.1 付近
    final top = s.pos.where((p) => p.x.abs() < 0.02 && p.y.abs() < 0.02 && p.z > 0).toList();
    expect(top.isNotEmpty, true);
    expect(top.map((p) => p.z).reduce(m.max), closeTo(0.1, 0.012));
    // 腕の先の方の頂点は骨2の重みが大きい
    final tip = s.pos.indexWhere((p) => p.x > 0.55);
    expect(s.w[tip].first.$1, 2);
  });
}
