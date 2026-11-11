// 守備AIの動作確認：固定の打球を多数回打ち、捕球率・捕球者を方向別に表示する
import 'dart:math';
import 'package:npb_pennant_app/models/player.dart';
import 'package:npb_pennant_app/engine/physics_engine.dart';
import 'package:npb_pennant_app/engine/fielder_ai.dart';

Player _f(String id) => Player(id: id, isPitcher: false, lastName: id, trajectory: 2, contactLeft: 60, contactRight: 60, power: 60, run: 60, arm: 60, throwAccuracy: 60, catchSkill: 60, eye: 60, clutch: 60, fieldP: 60, fieldC: 60, field1B: 60, field2B: 60, field3B: 60, fieldSS: 60, fieldLF: 60, fieldCF: 60, fieldRF: 60);

void main() {
  final roles = ['P', 'C', '1B', '2B', '3B', 'SS', 'LF', 'CF', 'RF'];
  final eng = PhysicsEngine();
  final scen = <List<dynamic>>[
    [30.0, 0.0, 'ゴロ 108km/h'], [36.0, 2.0, 'ゴロ 130km/h'], [42.0, 3.0, 'ゴロ 150km/h'],
    [34.0, 14.0, 'ライナー 122km/h'], [38.0, 24.0, 'フライ 137km/h/24°'], [40.0, 32.0, '大飛球 144km/h/32°'], [28.0, 60.0, 'ポップ 100km/h/60°'],
  ];
  for (final s in scen) {
    print('--- ${s[2]} ---');
    for (var h = -45.0; h <= 45.0; h += 7.5) {
      final res = <String, int>{};
      const n = 100;
      double dist = 0;
      for (var i = 0; i < n; i++) {
        final fielders = FielderAI().initializeFielders({for (final r in roles) r: _f(r)});
        final t = eng.simulateTrajectory(HitVector(s[0] as double, s[1] as double, h, 1000.0 + 40.0 * min(s[1] as double, 30.0)));
        int bi = t.indexWhere((p) => p.z <= 0); if (bi < 0) bi = t.length - 1;
        dist += sqrt(t[bi].x * t[bi].x + t[bi].y * t[bi].y);
        final c = FielderAI().simulateDefense(t, fielders);
        final k = c == null ? '抜けた' : c.fielderRole;
        res[k] = (res[k] ?? 0) + 1;
      }
      final top = res.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      print('方向${h.toStringAsFixed(1).padLeft(6)}° 落下${(dist / n).toStringAsFixed(0).padLeft(3)}m: ${top.map((e) => '${e.key}${e.value}').join(' ')}');
    }
  }
}
