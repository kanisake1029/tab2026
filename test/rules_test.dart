import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/engine/match_simulator.dart';
import 'package:npb_pennant_app/engine/physics_engine.dart';

/// 仕様書 第1章：フェア・ファウルの判定（打球の通り道）
void main() {
  Vector3D pt(double x, double y, double z) => Vector3D(x, y, z, 0, 0, 0);
  List<Vector3D> line(List<List<double>> ps) => [for (final p in ps) pt(p[0], p[1], p[2])];

  test('塁より奥に落ちた打球は、落ちた所で決まる', () {
    // 三塁線の内側（フェア）に落ちて、そのあとファウル地域へ転がる → フェア
    expect(MatchSimulator.isFoulTrajectory(line([[0, 0, 1], [-20, 30, 3], [-29, 30, 0], [-40, 33, 0]])), false);
    // 一塁線の外（ファウル）に落ちた → ファウル
    expect(MatchSimulator.isFoulTrajectory(line([[0, 0, 1], [20, 25, 3], [31, 30, 0], [33, 35, 0]])), true);
  });

  test('内野に落ちた打球は、塁を越える前にファウル地域へ出たらファウル', () {
    // 三塁線の内側に落ち、三塁の手前でファウル地域へ転がり出る → ファウル
    expect(MatchSimulator.isFoulTrajectory(line([[0, 0, 1], [-3, 5, 0], [-8, 9, 0], [-12, 11, 0]])), true);
    // フェアのまま三塁を越える → フェア（そのあとファウルへ出てもフェア）
    expect(MatchSimulator.isFoulTrajectory(line([[0, 0, 1], [-3, 5, 0], [-15, 18, 0], [-19, 20, 0], [-25, 22, 0]])), false);
    // フェアで止まる → フェア
    expect(MatchSimulator.isFoulTrajectory(line([[0, 0, 1], [1, 4, 0], [1.5, 6, 0]])), false);
  });

  test('ノーバウンドでフェンスを越えた打球は、越えた所で決まる', () {
    // ポールの外を越える → ファウル
    expect(MatchSimulator.isFoulTrajectory(line([[0, 0, 1], [-40, 50, 30], [-75, 72, 15], [-90, 80, 5]])), true);
    // 中堅を越える → フェア（本塁打）
    expect(MatchSimulator.isFoulTrajectory(line([[0, 0, 1], [0, 60, 30], [0, 125, 12]])), false);
  });
}
