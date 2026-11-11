// 遊撃手1人だけを守らせて、守備力別の守備範囲（方向ごとの捕球率）を調べるツール
// 実行: dart run tool/range_test.dart [球速km/h=130] [打球角度=2] [役割=SS]
import 'dart:math';
import 'package:npb_pennant_app/models/player.dart';
import 'package:npb_pennant_app/engine/physics_engine.dart';
import 'package:npb_pennant_app/engine/fielder_ai.dart';

Player _f(int lv) => Player(id: 'x', isPitcher: false, lastName: 'x', trajectory: 2, contactLeft: 60, contactRight: 60, power: 60, run: lv, arm: lv, throwAccuracy: lv, catchSkill: lv, eye: 60, clutch: 60, fieldP: lv, fieldC: lv, field1B: lv, field2B: lv, field3B: lv, fieldSS: lv, fieldLF: lv, fieldCF: lv, fieldRF: lv);

void main(List<String> args) {
  final kmh = args.isNotEmpty ? double.parse(args[0]) : 130.0;
  final angle = args.length > 1 ? double.parse(args[1]) : 2.0;
  final role = args.length > 2 ? args[2] : 'SS';
  final eng = PhysicsEngine();
  print('$role単独の守備範囲  打球 ${kmh.toInt()}km/h 角度${angle.toInt()}°（数字=捕球率%）');
  final dirs = [for (var h = -60.0; h <= 30.0; h += 7.5) h];
  print('守備力 ' + dirs.map((h) => h.toStringAsFixed(0).padLeft(5)).join(''));
  for (final lv in [30, 50, 70, 85, 100]) {
    final row = StringBuffer('${lv.toString().padLeft(5)}  ');
    for (final h in dirs) {
      int caught = 0;
      const n = 60;
      for (var i = 0; i < n; i++) {
        final fielders = FielderAI().initializeFielders({role: _f(lv)});
        final t = eng.simulateTrajectory(HitVector(kmh / 3.6, angle, h, 1000.0 + 40.0 * min(angle, 30.0)));
        if (FielderAI().simulateDefense(t, fielders) != null) caught++;
      }
      row.write((caught * 100 ~/ n).toString().padLeft(5));
    }
    print(row);
  }
}
