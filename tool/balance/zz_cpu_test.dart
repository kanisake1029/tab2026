// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
void main() {
  test('cpu', () {
    for (var k = 0; k < 4; k++) {
      final sw = Stopwatch()..start();
      var x = 0;
      for (var i = 0; i < 500000000; i++) { x += i % 7; }
      print('dart 5e8 loop ms ${sw.elapsedMilliseconds} $x');
    }
  });
}
