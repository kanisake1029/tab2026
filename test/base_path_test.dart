import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/engine/base_path.dart';
import 'package:npb_pennant_app/engine/field_time.dart';
import 'package:npb_pennant_app/engine/vec3.dart';

/// 走塁の道筋（仕様書 2.1）：塁を回ると膨らむ・曲がると遅くなる・止まり方で時間が変わる・一塁だけ駆け抜け・帰塁は塁を踏み直す
void main() {
  final sp = Sprint.of(60);
  test('一塁の駆け抜け：まっすぐの全力と同じ時間で踏み、ファウル側へ減速して止まる', () {
    final r = BaseRun(sp, sFrom: 0, to: 1, end: RunEnd.runThrough);
    expect(r.tArrive, closeTo(sp.time(BasePath.between), 0.05));
    expect(r.v[r.touchIndex], greaterThan(sp.vTop * 0.95)); // 減速せずに踏む
    final last = r.pts.last;
    expect(last.distanceTo(BasePath.bases[1]), inInclusiveRange(7, 12.5));
    expect(last.x, greaterThan(BasePath.bases[1].x)); // ファウル側（一塁線の外）
    // 二塁で「駆け抜け」は選べない（スライディングになる）
    expect(BaseRun(sp, sFrom: 1.15, to: 2, end: RunEnd.runThrough).end, RunEnd.slide);
  });

  test('塁を回る：外へ膨らみ、内側の角を踏み、曲がる所で遅くなる', () {
    final r = BaseRun(sp, sFrom: 0, to: 2, end: RunEnd.slide);
    // 一塁の手前で一塁線より外（ファウル側）へ膨らむ
    var maxOut = 0.0;
    for (final p in r.pts) {
      if (p.y < 19.4 && p.y > 8) {
        final out = (p.x - p.y) / 1.4142; // 一塁線（x=y）から外へ
        if (out > maxOut) maxOut = out;
      }
    }
    expect(maxOut, inInclusiveRange(1.0, 3.5));
    // 一塁を踏む（どこかの点が塁の上）
    expect(r.pts.any((p) => p.distanceTo(BasePath.bases[1]) < 0.05), true);
    // 曲がる所の最低速度は最高速より遅い
    final vmin = [for (var i = 5; i < r.v.length - 30; i++) r.v[i]].reduce((a, b) => a < b ? a : b);
    expect(vmin, lessThan(sp.vTop * 0.85));
    // 回る分だけ、まっすぐ 2 塁間より時間がかかる（0.2〜0.6秒）
    final straight = sp.time(BasePath.between * 2);
    // ignore: avoid_print
    print('二塁まで ${r.tArrive.toStringAsFixed(2)}秒（まっすぐ ${straight.toStringAsFixed(2)}） 最低速度 ${vmin.toStringAsFixed(1)}m/s 膨らみ ${maxOut.toStringAsFixed(1)}m');
    expect(r.tArrive - straight, inInclusiveRange(0.3, 0.8)); // 回る分＋二塁のスライディング
  });

  test('止まり方：スライディングは4m手前から減速、立って止まると遅い', () {
    final slide = BaseRun(sp, sFrom: 1.13, to: 2, end: RunEnd.slide, v0: 2);
    final stand = BaseRun(sp, sFrom: 1.13, to: 2, end: RunEnd.stand, v0: 2);
    expect(slide.v[slide.touchIndex], inInclusiveRange(4.0, 8.0)); // 塁に足が届くときもまだ速い
    expect(stand.v[stand.touchIndex], lessThan(0.7));
    expect(stand.tArrive, greaterThan(slide.tArrive + 0.1));
    // ignore: avoid_print
    print('一塁→二塁 スライディング ${slide.tArrive.toStringAsFixed(2)}秒 立って止まる ${stand.tArrive.toStringAsFixed(2)}秒');
  });

  test('帰塁：二塁を越えた走者が一塁へ戻るときは、二塁を踏み直す', () {
    final r = BaseRun(sp, sFrom: 2.3, to: 1);
    expect(r.pts.any((p) => p.distanceTo(BasePath.bases[2]) < 0.05), true);
    expect(r.pts.last.distanceTo(BasePath.bases[1]), lessThan(0.05));
    expect(r.posAt(r.tArrive).distanceTo(BasePath.bases[1]), lessThan(0.05));
  });

  test('オーバーラン：回って少し先で止まる', () {
    final r = BaseRun(sp, sFrom: 0, to: 1, end: RunEnd.overrun);
    expect(r.v.last, lessThan(0.01));
    expect(r.pts.last.distanceTo(BasePath.bases[1]), inInclusiveRange(3.0, 7.0));
    expect(r.pts.last.y, greaterThan(19.4)); // 二塁の方へ
    expect(r.posAt(-1).distanceTo(V3.zero), lessThan(1e-9));
  });
}
