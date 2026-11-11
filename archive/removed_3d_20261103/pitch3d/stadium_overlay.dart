import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../engine/vec3.dart';
import '../../models/stadium.dart';
import 'board_art.dart';
import 'stadium_mesh.dart';

/// 球場の 3D の上に 2D で重ねるもの：ビジョンの画面・リボンビジョン・フェンスの広告・フェンスの上の金網。
///  3D の面の四隅を投影して、射影変換（遠近そのまま）で貼る。人形より先（奥）に描く。
///  アプリの 3D 再生と、PC の調べ用の絵（test/stadium_render_test.dart）の両方で使う
class StadiumOverlay {
  final Stadium st;
  final List<(String, int)> ads; // 社名・色
  final String homeName;
  final Color homeColor;
  StadiumOverlay(this.st, {required this.ads, required this.homeName, required this.homeColor});

  static const deg = math.pi / 180;
  late final StadiumMesh _geo = StadiumMesh(st);
  late final List<List<(V3, V3, V3, V3, V3)>> _ribbonStrips = _geo.ribbonStrips();
  final Map<Vision, List<V3>> _lines = {};
  final Map<Vision, ui.Image> _boards = {};
  Object? _dataKey;
  ui.Image? _ribbonImg;
  final Map<String, ui.Image> _adImg = {}, _adImgW = {};

  /// dataKey が変わったら（1球ごと）ビジョンの中身を作り直す
  void paint(Canvas canvas, Offset? Function(V3) project, V3 camPos, {required Object dataKey, required BoardData Function() data}) {
    if (dataKey != _dataKey) {
      _clearBoards();
      _dataKey = dataKey;
    }
    _fenceAds(canvas, project, camPos);
    _fenceNet(canvas, project);
    _ribbons(canvas, project, camPos);
    for (final v in [if (st.showMainVision) st.vision, ...st.moreVisions]) {
      _board(canvas, project, camPos, v, data);
    }
  }

  void _clearBoards() {
    for (final im in _boards.values) {
      im.dispose();
    }
    _boards.clear();
  }

  void dispose() {
    _clearBoards();
    _ribbonImg?.dispose();
    for (final im in [..._adImg.values, ..._adImgW.values]) {
      im.dispose();
    }
  }

  // ───────── 射影変換 ─────────
  /// 単位正方形（左上・右上・右下・左下）→ 画面の四角形 q0..q3 の射影変換 [a b c; d e f; g h 1]（Heckbert）
  static List<double>? homography(Offset q0, Offset q1, Offset q2, Offset q3) {
    final dx1 = q1.dx - q2.dx, dx2 = q3.dx - q2.dx, dx3 = q0.dx - q1.dx + q2.dx - q3.dx;
    final dy1 = q1.dy - q2.dy, dy2 = q3.dy - q2.dy, dy3 = q0.dy - q1.dy + q2.dy - q3.dy;
    final den = dx1 * dy2 - dy1 * dx2;
    if (den.abs() < 1e-9) return null;
    final g = (dx3 * dy2 - dy3 * dx2) / den, hh = (dx1 * dy3 - dy1 * dx3) / den;
    return [
      q1.dx - q0.dx + g * q1.dx, q3.dx - q0.dx + hh * q3.dx, q0.dx, //
      q1.dy - q0.dy + g * q1.dy, q3.dy - q0.dy + hh * q3.dy, q0.dy, //
      g, hh, 1,
    ];
  }

  /// 画像の一部（src）を、画面の四角形（左上・右上・右下・左下）に遠近そのまま貼る
  static void imgQuad(Canvas canvas, ui.Image img, Rect src, Offset q0, Offset q1, Offset q2, Offset q3, Paint paint) {
    final h = homography(q0, q1, q2, q3);
    if (h == null) return;
    final w = src.width, hh = src.height, l = src.left, t = src.top;
    canvas.save();
    canvas.transform(Float64List.fromList([
      h[0] / w, h[3] / w, 0, h[6] / w, //
      h[1] / hh, h[4] / hh, 0, h[7] / hh, //
      0, 0, 1, 0, //
      h[2] - h[0] * l / w - h[1] * t / hh, h[5] - h[3] * l / w - h[4] * t / hh, 0, 1 - h[6] * l / w - h[7] * t / hh,
    ]));
    canvas.drawImageRect(img, src, src, paint);
    canvas.restore();
  }

  // ───────── ビジョン：1球ごとに1回、ビジョンごとに1枚の画像にする（毎コマ文字を描くと重く、文字が化けることもある）─────────
  ui.Image _boardImage(Vision v, BoardData Function() data) => _boards.putIfAbsent(v, () {
        final w = (BoardArt.h * v.width / v.height).clamp(80.0, 6000.0);
        final sc = math.min(1.0, 4096 / w); // 画像の幅は 4096 まで（それより横長は少し粗く）
        final pic = BoardArt.paint(v.content, w, data());
        if (sc >= 1) return pic.toImageSync(w.round(), BoardArt.h.round());
        final rec = ui.PictureRecorder();
        final cv = Canvas(rec);
        cv.scale(sc, sc);
        cv.drawPicture(pic);
        return rec.endRecording().toImageSync((w * sc).round(), (BoardArt.h * sc).round());
      });

  /// ビジョンの画面：平らな板は1枚、弧の板は約 2m ごとの区切りに分けて、それぞれ射影変換で貼る（区切りどうしは少し重ねて継ぎ目を消す）
  void _board(Canvas canvas, Offset? Function(V3) project, V3 camPos, Vision v, BoardData Function() data) {
    final line = _lines.putIfAbsent(v, () => _geo.visionLine(v));
    if (line.length < 2) return;
    final flatIn = -V3(line.first.x + line.last.x, line.first.y + line.last.y, 0).unit;
    final mid = v.arc ? line[line.length ~/ 2] : (line.first + line.last) * 0.5;
    final inMid = v.arc ? -V3(mid.x, mid.y, 0).unit : flatIn;
    if ((camPos - mid).dot(inMid) < 0) return; // 画面の裏から
    final z0 = v.bottom, z1 = v.bottom + v.height;
    final img = _boardImage(v, data);
    final iw = img.width.toDouble(), ih = img.height.toDouble();
    final paint = Paint()..filterQuality = FilterQuality.medium;
    final cum = <double>[0];
    for (var i = 1; i < line.length; i++) {
      cum.add(cum.last + line[i].distanceTo(line[i - 1]));
    }
    final total = cum.last;
    for (var i = 0; i + 1 < line.length; i++) {
      final a = line[i], b = line[i + 1];
      final ia = (v.arc ? -V3(a.x, a.y, 0).unit : flatIn) * 0.1, ib = (v.arc ? -V3(b.x, b.y, 0).unit : flatIn) * 0.1;
      if (v.arc && (camPos - (a + b) * 0.5).dot(ia) < 0) continue;
      final p0 = project(a + ia + V3(0, 0, z1)), p1 = project(b + ib + V3(0, 0, z1)), p2 = project(b + ib + V3(0, 0, z0)), p3 = project(a + ia + V3(0, 0, z0));
      if (p0 == null || p1 == null || p2 == null || p3 == null) continue;
      if ((p1 - p0).distance < 0.5 && (p2 - p3).distance < 0.5) continue;
      final u0 = cum[i] / total * iw, u1 = cum[i + 1] / total * iw;
      // 右へ少し（画像で 0.8 px）重ねる
      final ext = i + 2 < line.length ? math.min(0.8, iw - u1) : 0.0;
      final k = ext / math.max(1e-6, u1 - u0);
      imgQuad(canvas, img, Rect.fromLTRB(u0, 0, u1 + ext, ih), p0, p1 + (p1 - p0) * k, p2 + (p2 - p3) * k, p3, paint);
    }
  }

  // ───────── リボンビジョン（帯状の光る広告）：画像を縦横比のまま横に繰り返す ─────────
  void _ribbons(Canvas canvas, Offset? Function(V3) project, V3 camPos) {
    if (_ribbonStrips.isEmpty) return;
    final img = _ribbonImg ??= BoardArt.ribbon(homeName.isEmpty ? st.name : homeName, homeColor, ads);
    final iw = img.width.toDouble(), ih = img.height.toDouble();
    final paint = Paint()..filterQuality = FilterQuality.medium;
    for (final strip in _ribbonStrips) {
      var u = 0.0;
      for (final (tl, tr, br, bl, inw) in strip) {
        final du = tl.distanceTo(tr) / math.max(0.05, tl.distanceTo(bl)) * ih;
        final mid = (tl + br) * 0.5;
        final p0 = (camPos - mid).dot(inw) > 0 ? project(tl) : null;
        final p1 = p0 == null ? null : project(tr), p2 = p0 == null ? null : project(br), p3 = p0 == null ? null : project(bl);
        if (p0 != null && p1 != null && p2 != null && p3 != null) {
          final u0 = u % iw;
          if (u0 + du <= iw) {
            final k = math.min(0.8, iw - u0 - du) / math.max(1e-6, du);
            imgQuad(canvas, img, Rect.fromLTRB(u0, 0, u0 + du + k * du, ih), p0, p1 + (p1 - p0) * k, p2 + (p2 - p3) * k, p3, paint);
          } else {
            // 画像の端をまたぐ：2つに分ける
            final f = (iw - u0) / du, rest = du - (iw - u0);
            final m0 = Offset.lerp(p0, p1, f)!, m1 = Offset.lerp(p3, p2, f)!;
            imgQuad(canvas, img, Rect.fromLTRB(u0, 0, iw, ih), p0, m0, m1, p3, paint);
            imgQuad(canvas, img, Rect.fromLTRB(0, 0, rest, ih), m0, p1, p2, m1, paint);
          }
        }
        u += du;
      }
    }
  }

  // ───────── 外野フェンスの広告 ─────────
  /// 広告の板の絵（色の地に白い社名）
  ui.Image _adImage(String name, int color) => _adImg.putIfAbsent(name, () {
        final rec = ui.PictureRecorder();
        final cv = Canvas(rec, const Rect.fromLTWH(0, 0, 512, 96));
        cv.drawRect(const Rect.fromLTWH(0, 0, 512, 96), Paint()..color = Color(color));
        cv.drawRect(const Rect.fromLTWH(0, 84, 512, 12), Paint()..color = Colors.white24);
        _name(cv, name, 58, 44, 480);
        return rec.endRecording().toImageSync(512, 96);
      });

  /// 白い字の広告（フェンスに直接書いた字：幕張・横浜など）。地は透明
  ui.Image _adImageWhite(String name) => _adImgW.putIfAbsent(name, () {
        final rec = ui.PictureRecorder();
        final cv = Canvas(rec, const Rect.fromLTWH(0, 0, 512, 96));
        _name(cv, name, 64, 48, 470, spacing: 2);
        return rec.endRecording().toImageSync(512, 96);
      });

  static void _name(Canvas cv, String name, double size, double cy, double maxW, {double spacing = 0}) {
    final tp = TextPainter(
        text: TextSpan(text: name, style: TextStyle(fontFamily: BoardArt.font, fontSize: size, color: Colors.white, fontWeight: FontWeight.w900, height: 1.0, letterSpacing: spacing)),
        textDirection: TextDirection.ltr,
        maxLines: 1)
      ..layout();
    final sc = math.min(1.0, maxW / tp.width);
    cv.save();
    cv.translate(256, cy);
    cv.scale(sc, 1);
    tp.paint(cv, Offset(-tp.width / 2, -tp.height / 2));
    cv.restore();
  }

  /// ラバーの面に貼る。'color'＝色の看板、'white'＝白い字だけ、'none'＝なし（つたの壁など）
  void _fenceAds(Canvas canvas, Offset? Function(V3) project, V3 camPos) {
    if (st.id == 'koshien' || st.fenceAds == 'none' || ads.isEmpty) return;
    final white = st.fenceAds == 'white';
    final paint = Paint()..filterQuality = FilterQuality.medium;
    final n = white ? 10 : 12;
    final span = 90.0 / n;
    for (var i = 0; i < n; i++) {
      final a0 = -45 + span * i + 0.5, a1 = -45 + span * (i + 1) - 0.5;
      V3 at(double a, double fz) {
        final d = st.fenceDistance(a) - 0.04, r = math.max(0.8, st.fenceHeight(a) - st.fenceNet);
        return V3(d * math.sin(a * deg), d * math.cos(a * deg), 0.25 + (r - 0.25) * fz);
      }

      final mid = at((a0 + a1) / 2, 0.5);
      if ((camPos - mid).dot(-V3(mid.x, mid.y, 0).unit) < 0) continue;
      final lo = white ? 0.22 : 0.12, hi = white ? 0.82 : 0.86;
      // 3つに区切って貼る（フェンスの曲がりにそわせる）
      const parts = 3;
      final ad = ads[i % ads.length];
      final img = white ? _adImageWhite(ad.$1) : _adImage(ad.$1, ad.$2);
      for (var k = 0; k < parts; k++) {
        final b0 = a0 + (a1 - a0) * k / parts, b1 = a0 + (a1 - a0) * (k + 1) / parts;
        final p0 = project(at(b0, hi)), p1 = project(at(b1, hi)), p2 = project(at(b1, lo)), p3 = project(at(b0, lo));
        if (p0 == null || p1 == null || p2 == null || p3 == null) continue;
        if ((p1 - p0).distance < 1) continue;
        final more = k + 1 < parts;
        final ext = more ? 0.8 / (512 / parts) : 0.0;
        imgQuad(canvas, img, Rect.fromLTRB(512.0 * k / parts, 0, 512.0 * (k + 1) / parts + (more ? 0.8 : 0), 96), p0, p1 + (p1 - p0) * ext, p2 + (p2 - p3) * ext, p3, paint);
      }
    }
  }

  /// フェンスの上の金網：網は半透明の帯（近くで大きく見えるときは、ひし形の網の目も）
  void _fenceNet(Canvas canvas, Offset? Function(V3) project) {
    if (st.fenceNet <= 0) return;
    final top = <Offset?>[], bot = <Offset?>[];
    for (var a = -45.0; a <= 45.0 + 1e-6; a += 1.5) {
      final d = st.fenceDistance(a) + 0.18, h = st.fenceHeight(a);
      top.add(project(StadiumMesh.polar(a, d, h - 0.1)));
      bot.add(project(StadiumMesh.polar(a, d, math.max(0.8, h - st.fenceNet))));
    }
    final path = Path();
    var i = 0;
    while (i < top.length) {
      while (i < top.length && (top[i] == null || bot[i] == null)) {
        i++;
      }
      final s = i;
      while (i < top.length && top[i] != null && bot[i] != null) {
        i++;
      }
      if (i - s < 2) continue;
      path.moveTo(top[s]!.dx, top[s]!.dy);
      for (var k = s + 1; k < i; k++) {
        path.lineTo(top[k]!.dx, top[k]!.dy);
      }
      for (var k = i - 1; k >= s; k--) {
        path.lineTo(bot[k]!.dx, bot[k]!.dy);
      }
      path.close();
    }
    canvas.drawPath(path, Paint()..color = const Color(0x3A1F252D));
    var px = 0.0;
    for (var k = 0; k < top.length; k++) {
      if (top[k] != null && bot[k] != null) px = math.max(px, (top[k]! - bot[k]!).distance);
    }
    final step = px / st.fenceNet * 0.12; // 網の目 12cm
    if (step < 4) return;
    final b = path.getBounds();
    canvas.save();
    canvas.clipPath(path);
    final ln = Paint()
      ..color = const Color(0x40C8CED6)
      ..strokeWidth = math.min(1.2, step * 0.08);
    for (var x = b.left - b.height; x < b.right; x += step) {
      canvas.drawLine(Offset(x, b.bottom), Offset(x + b.height, b.top), ln);
      canvas.drawLine(Offset(x, b.top), Offset(x + b.height, b.bottom), ln);
    }
    canvas.restore();
  }
}
