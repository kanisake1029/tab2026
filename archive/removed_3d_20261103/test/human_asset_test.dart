import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/widgets/pitch3d/human_asset.dart';

void main() {
  test('人体（body.bin）を読み、体格の調整で形と骨が変わる', () {
    final a = HumanAsset.parse(File('assets/body/body.bin').readAsBytesSync());
    expect(a.bones.length, 53);
    expect(a.parts['body']!.count, greaterThan(10000));
    expect(a.deltas.length, greaterThan(100));
    final base = a.bake(const {}, partNames: const ['body']);
    final tall = a.bake(const {'height+': 1.0}, partNames: const ['body']);
    final big = a.bake(const {'muscle+': 1.0, 'weight+': 1.0}, partNames: const ['body']);
    // ignore: avoid_print
    print('高さ 基準${base.height.toStringAsFixed(3)} 長身${tall.height.toStringAsFixed(3)}  肩幅 ${base.dist(base.headOf('upperarm_l'), base.headOf('upperarm_r')).toStringAsFixed(3)} → ${big.dist(big.headOf('upperarm_l'), big.headOf('upperarm_r')).toStringAsFixed(3)}');
    expect(tall.height, greaterThan(base.height + 0.1));
    expect(a.skins.length, 9);
  });
}
