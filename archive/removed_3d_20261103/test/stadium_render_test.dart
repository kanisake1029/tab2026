// 球場の 3D の形を、PC で絵にして確かめるためのテスト（実機がなくても写真と見比べられる）。
//  形の三角形を記録して、奥行きの記憶（Zバッファ）つきで1画素ずつ塗る簡易な描き方。光は面の向きで明るさを変えるだけ。
//  flutter test test/stadium_render_test.dart --dart-define=OUT=<フォルダ> [--dart-define=PARKS=koshien,tokyo] [--dart-define=VIEWS=center,first]
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/engine/match_simulator.dart';
import 'package:npb_pennant_app/widgets/pitch3d/board_art.dart';
import 'package:npb_pennant_app/widgets/pitch3d/stadium_overlay.dart';
import 'package:npb_pennant_app/engine/vec3.dart';
import 'package:npb_pennant_app/models/stadium.dart';
import 'package:npb_pennant_app/widgets/pitch3d/scene_util.dart';
import 'package:npb_pennant_app/widgets/pitch3d/stadium_mesh.dart';

void main() {
  test('球場を絵にする', () async {
    const out = String.fromEnvironment('OUT');
    if (out.isEmpty) return;
    Directory(out).createSync(recursive: true);
    // ビジョンの字：PC の日本語の字体（テストの初期の字体は四角になる）
    final fl = FontLoader('NotoJP')..addFont(Future.value(ByteData.sublistView(File('C:/Windows/Fonts/NotoSansJP-VF.ttf').readAsBytesSync())));
    await fl.load();
    BoardArt.font = 'NotoJP';
    final data = sampleBoard();
    const only = String.fromEnvironment('PARKS'), onlyV = String.fromEnvironment('VIEWS');
    final parks = Stadium.all.where((s) => only.isEmpty || only.split(',').contains(s.id)).toList();
    // カメラ：中継（中堅後方から本塁）・ネット裏の上・一塁側の低い所から外野・三塁側の内野席から・真上に近い所から
    final views = <(String, V3, V3, double)>[
      ('center', const V3(-5.5, 118, 13), const V3(0, 3, 1.2), 32),
      ('backhigh', const V3(0, -36, 26), const V3(0, 60, 4), 70),
      ('first', const V3(28, 20, 4), const V3(-25, 70, 10), 80),
      ('third', const V3(-38, 5, 16), const V3(20, 60, 6), 80),
      ('air', const V3(0, -120, 170), const V3(0, 45, 0), 60),
    ].where((v) => onlyV.isEmpty || onlyV.split(',').contains(v.$1)).toList();
    for (final st in parks) {
      ColorMesh.record = [];
      final m = StadiumMesh(st, fill: 0.75, homeColor: 0xFFE67E22, awayColor: 0xFF1D4ED8);
      m.fillMesh(ColorMesh()..faceUp = true, ColorMesh()..faceTo = const V3(0, 45, 1.5), ColorMesh()..faceTo = const V3(0, 45, 1.5), ColorMesh()..faceDown = true);
      final tris = ColorMesh.record!;
      ColorMesh.record = null;
      for (final (vn, cam, look, fovDeg) in views) {
        const w = 1000, h = 620;
        final fwd = (look - cam).unit;
        final right = fwd.cross(V3.ez).unit;
        final up = right.cross(fwd);
        final f = (w / 2) / math.tan(fovDeg * math.pi / 360);
        final depth = Float32List(w * h)..fillRange(0, w * h, 1e9);
        final px = Uint32List(w * h);
        // 空（上ほど濃い青）
        for (var y = 0; y < h; y++) {
          final t = y / h;
          final r = (120 + 60 * t).round(), g = (160 + 50 * t).round(), b = (215 + 25 * t).round();
          for (var x = 0; x < w; x++) {
            px[y * w + x] = 0xFF000000 | (b << 16) | (g << 8) | r; // RGBA の並び（リトルエンディアン）
          }
        }
        const light = V3(-0.35, -0.45, 0.82);
        const near = 0.3;
        for (final (a, b, c, col) in tris) {
          // カメラの座標へ
          List<double> cs(V3 p) {
            final d = p - cam;
            return [d.dot(right), d.dot(up), d.dot(fwd)];
          }

          var poly = [cs(a), cs(b), cs(c)];
          if (poly.every((q) => q[2] < near)) continue;
          // 手前の面で切る
          if (poly.any((q) => q[2] < near)) {
            final np = <List<double>>[];
            for (var i = 0; i < poly.length; i++) {
              final p0 = poly[i], p1 = poly[(i + 1) % poly.length];
              final in0 = p0[2] >= near, in1 = p1[2] >= near;
              if (in0) np.add(p0);
              if (in0 != in1) {
                final t = (near - p0[2]) / (p1[2] - p0[2]);
                np.add([p0[0] + (p1[0] - p0[0]) * t, p0[1] + (p1[1] - p0[1]) * t, near]);
              }
            }
            poly = np;
          }
          final n = (b - a).cross(c - a);
          final nl = n.length;
          final shade = nl > 1e-12 ? 0.70 + 0.30 * (n / nl).dot(light).abs() : 1.0;
          final cr = (((col >> 16) & 255) * shade).round().clamp(0, 255), cg = (((col >> 8) & 255) * shade).round().clamp(0, 255), cb = ((col & 255) * shade).round().clamp(0, 255);
          final pix = 0xFF000000 | (cb << 16) | (cg << 8) | cr;
          // 画面へ（x, y, 1/z）
          final sp = [for (final q in poly) [w / 2 + q[0] * f / q[2], h / 2 - q[1] * f / q[2], 1 / q[2]]];
          for (var i = 1; i + 1 < sp.length; i++) {
            final p0 = sp[0], p1 = sp[i], p2 = sp[i + 1];
            final minX = math.max(0, [p0[0], p1[0], p2[0]].reduce(math.min).floor()), maxX = math.min(w - 1, [p0[0], p1[0], p2[0]].reduce(math.max).ceil());
            final minY = math.max(0, [p0[1], p1[1], p2[1]].reduce(math.min).floor()), maxY = math.min(h - 1, [p0[1], p1[1], p2[1]].reduce(math.max).ceil());
            if (minX > maxX || minY > maxY) continue;
            final area = (p1[0] - p0[0]) * (p2[1] - p0[1]) - (p1[1] - p0[1]) * (p2[0] - p0[0]);
            if (area.abs() < 1e-9) continue;
            for (var y = minY; y <= maxY; y++) {
              final yc = y + 0.5;
              for (var x = minX; x <= maxX; x++) {
                final xc = x + 0.5;
                final w0 = ((p1[0] - xc) * (p2[1] - yc) - (p1[1] - yc) * (p2[0] - xc)) / area;
                final w1 = ((p2[0] - xc) * (p0[1] - yc) - (p2[1] - yc) * (p0[0] - xc)) / area;
                final w2 = 1 - w0 - w1;
                if (w0 < -1e-6 || w1 < -1e-6 || w2 < -1e-6) continue;
                final iz = w0 * p0[2] + w1 * p1[2] + w2 * p2[2];
                final z = 1 / iz;
                final k = y * w + x;
                if (z < depth[k]) {
                  depth[k] = z;
                  px[k] = pix;
                }
              }
            }
          }
        }
        final c = Completer<ui.Image>();
        ui.decodeImageFromPixels(px.buffer.asUint8List(), w, h, ui.PixelFormat.rgba8888, c.complete);
        final img0 = await c.future;
        // 2D で重ねるもの（ビジョン・リボン・フェンスの広告と金網）：アプリと同じ StadiumOverlay
        final rec = ui.PictureRecorder();
        final cv = Canvas(rec);
        cv.drawImage(img0, Offset.zero, Paint());
        Offset? project(V3 p) {
          final d = p - cam;
          final z = d.dot(fwd);
          if (z < near) return null;
          return Offset(w / 2 + d.dot(right) * f / z, h / 2 - d.dot(up) * f / z);
        }

        StadiumOverlay(st, ads: data.ads, homeName: data.e.homeName, homeColor: data.home).paint(cv, project, cam, dataKey: 0, data: () => data);
        final img = rec.endRecording().toImageSync(w, h);
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        File('$out/${st.id}_$vn.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      }
    }
  }, timeout: const Timeout(Duration(minutes: 30)));
}

/// ビジョンに映す見本（4回表・1死一三塁）
BoardData sampleBoard() {
  final e = PitchEvent(paIndex: 12, pitchNo: 3, battingHome: false, batter: '佐々木 健太', batterHand: 'R', pitcher: '高橋 翔', pitchName: 'スライダー', speed: 138, x: 0, z: 0, inZone: true, balls: 2, strikes: 1)
    ..inning = 4
    ..top = true
    ..outsBefore = 1
    ..basesBefore = [true, false, true]
    ..offBefore = 3
    ..defBefore = 2
    ..pitcherCount = 57
    ..homeName = '神戸'
    ..awayName = 'ラクテル'
    ..batterToday = '2打数1安打'
    ..homeLine = [for (var i = 0; i < 9; i++) '${['中', '二', '右', '一', '左', '三', '遊', '捕', '投'][i]}|山田 太郎$i|${i + 1}|.2${80 + i}|${i * 2}']
    ..awayLine = [for (var i = 0; i < 9; i++) '${['遊', '中', '左', '一', '右', '三', '二', '捕', '投'][i]}|${i == 3 ? '佐々木 健太' : '鈴木 一郎$i'}|${i + 10}|.3${i}1|${i + 3}'];
  return BoardData(
      e: e, stadium: '球場', home: const Color(0xFFFACC15), away: const Color(0xFF7F1D2D),
      ads: const [('ノースビール', 0xFFB91C1C), ('ほくと電機', 0xFF1D4ED8), ('はまなす銀行', 0xFF0F766E), ('北ガス', 0xFFEA580C), ('ポプラ製菓', 0xFFDB2777), ('ひかり保険', 0xFF4F46E5)],
      runs: const {'1T': 0, '1B': 1, '2T': 2, '2B': 0, '3T': 1, '3B': 1, '4T': 0}, rH: 2, rA: 3, hH: 5, hA: 7, eH: 0, eA: 1);
}
