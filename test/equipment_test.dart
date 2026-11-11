import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/engine/environment.dart';
import 'package:npb_pennant_app/models/equipment.dart';
import 'package:npb_pennant_app/models/stadium.dart';

void main() {
  test('バット：軽い・短く持つほど速く振れ、重い・先が重いほど当たり負けしない', () {
    final std = Bat();
    final choke = Bat(choke: 3), heavy = Bat(weight: 950, balance: 'トップ'), light = Bat(weight: 860, balance: 'カウンター');
    // ignore: avoid_print
    print('慣性モーメント 標準${std.inertia.toStringAsFixed(4)} 3cm短く${choke.inertia.toStringAsFixed(4)}（${((1 - choke.inertia / std.inertia) * 100).toStringAsFixed(0)}%減）'
        ' 有効質量 標準${(std.effectiveMass * 1000).round()}g 重いトップ${(heavy.effectiveMass * 1000).round()}g 軽いカウンター${(light.effectiveMass * 1000).round()}g');
    expect(std.swingSpeedRatio, closeTo(1, 1e-9));
    expect(1 - choke.inertia / std.inertia, inInclusiveRange(0.08, 0.22)); // 3cm 短く持つと約15%減
    expect(choke.swingSpeedRatio, greaterThan(1));
    expect(heavy.swingSpeedRatio, lessThan(1));
    expect(heavy.effectiveMass, greaterThan(std.effectiveMass));
    expect(light.effectiveMass, lessThan(std.effectiveMass));
  });

  test('グラブ：大きいほど届き、深いほど握り替えが遅い', () {
    expect(Glove(length: 32.5).reachBonus, closeTo(0.025, 1e-9));
    expect(Glove(pocket: '深い').transferDelay, greaterThan(Glove(pocket: '浅い').transferDelay));
    expect(Glove.auto('a', '遊撃手').length, lessThan(Glove.auto('a', '中堅手').length));
  });

  test('地面：内野の土・芝・ウォーニングトラック', () {
    final st = Stadium.standard;
    expect(Surface.at(st, 0, 3).name, '土'); // 本塁のまわり
    expect(Surface.at(st, 0, 12).name, isNot('土')); // 内野の芝
    expect(Surface.at(st, 10, 30).name, '土'); // 二遊間の後ろの土
    expect(Surface.at(st, 0, 70).name, isNot('土')); // 外野の芝
    expect(Surface.at(st, 0, 119).name, '土'); // 中堅のウォーニングトラック
  });
}
