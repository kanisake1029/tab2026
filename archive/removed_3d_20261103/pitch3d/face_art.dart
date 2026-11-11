import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'toon_rig.dart';

/// 顔の絵（パワプロ風：鼻と耳は描かない。目が個性の中心で、太い上まぶたの線・色のある大きな黒目・白いハイライト。眉・ひげ・髪型・小物で見分ける）。
///  正面から見た顔の部品だけを、選手ごとに一度だけ画像にする（地は透明。毎コマ部品を描かない）。
///  画像の座標：頭の半径 R を S＝N÷2.6 px とし、中心 (N/2, N/2) が頭の中心。右へ＝キャラクターの左（見る人の右）、上へ＝頭の上。
///  毎コマは、この画像を頭の輪郭で切り抜き、顔の正面の面（頭の中心から前へ 0.66R）に合わせて貼る（puppet2d.dart の _head）
class FaceArt {
  /// variant：0 ふつう 1 まばたき 2 力み（目を鋭く、口を大きく開けて叫ぶ）。n：画像の一辺（px）
  static ui.Image bake(FaceLook f, int variant, int n) {
    final rec = ui.PictureRecorder();
    final cv = Canvas(rec, Rect.fromLTWH(0, 0, n.toDouble(), n.toDouble()));
    draw(cv, f, variant, n.toDouble());
    return rec.endRecording().toImageSync(n, n);
  }

  static const _ink = Color(0xFF1B1B22);

  /// 顔の型ごとの、あごの長さ（頭の半径に対して）・あごの幅・角ばり（puppet2d の頭の形と同じ）
  ///  0 ふつう（丸い） 1 ホームベース（あごがとがる） 2 長方形（ゴツい） 3 面長
  static double chinOf(FaceLook f) =>
      ((switch (f.faceShape) {
                1 => 1.04,
                2 => 0.98,
                3 => 1.12,
                _ => 0.97,
              }) *
              f.chin)
          .clamp(0.88, 1.25);
  static double jawOf(FaceLook f) =>
      ((switch (f.faceShape) {
                1 => 0.84,
                2 => 0.99,
                3 => 0.88,
                _ => 0.94,
              }) *
              f.jaw *
              f.cheek)
          .clamp(0.78, 1.04);
  static double squareOf(FaceLook f) => switch (f.faceShape) {
    1 => 2.1,
    2 => 3.6,
    3 => 2.6,
    _ => 2.8,
  };

  /// もみあげの下の端（頭の中心から下へ、頭の半径に対して。0＝もみあげなし）。パワプロ風に、短髪は帽子の下に髪を見せない（puppet2d の帽子の下の髪と同じ）
  static double sideburnOf(FaceLook f) => switch (f.hairStyle) {
    2 => 0.5,
    3 => 0.3,
    4 => 0.3,
    7 => 0.36,
    _ => 0.0,
  };

  // 目の位置（頭の半径に対して）
  static const eyeZ = -0.28;
  static double eyeX(FaceLook f) => 0.4 * f.eyeGap;
  static const mouthZ = -0.64;

  static void draw(Canvas cv, FaceLook f, int variant, double n) {
    final s = n / 2.6, cx = n / 2, cy = n / 2;
    Offset p(double u, double v) => Offset(cx + u * s, cy - v * s);
    final lw = math.max(1.0, n / 90);
    final skin = Color(f.skin), hair = Color(f.hair);
    final big = n >= 120; // 細かいもの（しわ・二重の線・そばかす）は大きい画像だけ
    final blink = variant == 1, effort = variant == 2;
    final chinL = chinOf(f);
    const ez = eyeZ;
    final ex = eyeX(f);
    final mv = mouthZ - 0.05 * (chinL - 1);

    // ── 若手だけ：ほんのり赤いほお ──
    if (f.archetype == 6) {
      for (final sx in [-1.0, 1.0]) {
        cv.drawOval(Rect.fromCenter(center: p(sx * 0.52, -0.47), width: 0.22 * s, height: 0.1 * s), Paint()..color = const Color(0x24E8735A));
      }
    }
    if (big && f.freckles) {
      for (final sx in [-1.0, 1.0]) {
        for (var i = 0; i < 5; i++) {
          cv.drawCircle(p(sx * (0.38 + 0.05 * (i % 3)), -0.42 - 0.035 * i), lw * 0.7, Paint()..color = const Color(0x66A0522D));
        }
      }
    }

    // （もみあげは顔の絵には描かない。頭の横の立体の帯として puppet2d で描く）

    // ── ひげ（面で塗る。口より先）──
    final beardC = Color.lerp(hair, skin, 0.08)!;
    // ひげの面：ほおの上の線（口のまわりを避ける）から、あごのふちに沿ってあご先まで。
    //  ふちは頭の輪郭（puppet2d と同じ式）の少し内側なので、斜め・横から見ると、あごに沿って丸く終わる
    Path lowerFace() {
      final jw = jawOf(f);
      double edge(double v) {
        final sz = (-v / chinL).clamp(0.0, 1.0);
        return 0.985 * (1 + 0.045 * math.sin(math.pi * math.min(1.0, sz * 1.4))) * (1 - (1 - jw) * math.pow(sz, 2.2)) * math.pow(math.max(0.0, 1 - math.pow(sz, 2.8)), 1 / 2.8);
      }

      const v0 = -0.36;
      final q = [p(-0.84, v0), p(-0.56, -0.6), p(-0.24, -0.56), p(0, -0.53), p(0.24, -0.56), p(0.56, -0.6), p(0.84, v0)];
      final path = Path()
        ..moveTo(p(-edge(v0), v0).dx, p(-edge(v0), v0).dy)
        ..lineTo(q[0].dx, q[0].dy)
        ..quadraticBezierTo(q[1].dx, q[1].dy, q[2].dx, q[2].dy)
        ..quadraticBezierTo(q[3].dx, q[3].dy, q[4].dx, q[4].dy)
        ..quadraticBezierTo(q[5].dx, q[5].dy, q[6].dx, q[6].dy);
      for (var i = 0; i <= 12; i++) {
        final v = v0 + (-chinL - v0) * i / 12;
        path.lineTo(p(edge(v), v).dx, p(edge(v), v).dy);
      }
      for (var i = 12; i >= 0; i--) {
        final v = v0 + (-chinL - v0) * i / 12;
        path.lineTo(p(-edge(v), v).dx, p(-edge(v), v).dy);
      }
      return path..close();
    }

    void goatee() {
      final r = Rect.fromLTRB(p(-0.16, mv - 0.1).dx, p(-0.16, mv - 0.1).dy, p(0.16, -chinL * 1.04).dx, p(0.16, -chinL * 1.04).dy);
      cv.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(0.06 * s)), Paint()..color = beardC);
    }

    void mustache() {
      final m = Path()
        ..moveTo(p(-0.26, mv + 0.02).dx, p(-0.26, mv + 0.02).dy)
        ..quadraticBezierTo(p(-0.12, mv + 0.14).dx, p(-0.12, mv + 0.14).dy, p(0, mv + 0.11).dx, p(0, mv + 0.11).dy)
        ..quadraticBezierTo(p(0.12, mv + 0.14).dx, p(0.12, mv + 0.14).dy, p(0.26, mv + 0.02).dx, p(0.26, mv + 0.02).dy)
        ..quadraticBezierTo(p(0.12, mv + 0.06).dx, p(0.12, mv + 0.06).dy, p(0, mv + 0.05).dx, p(0, mv + 0.05).dy)
        ..quadraticBezierTo(p(-0.12, mv + 0.06).dx, p(-0.12, mv + 0.06).dy, p(-0.26, mv + 0.02).dx, p(-0.26, mv + 0.02).dy)
        ..close();
      cv.drawPath(m, Paint()..color = beardC);
    }

    switch (f.beard) {
      case 1: // 青い無精ひげ（面）
        cv.drawPath(lowerFace(), Paint()..color = Color.lerp(hair, const Color(0xFF4A5A6A), 0.45)!.withValues(alpha: 0.3));
      case 2:
        goatee();
      case 3:
        mustache();
      case 4:
        goatee();
        mustache();
      case 5: // あご全体を覆う濃いひげ
        cv.drawPath(lowerFace(), Paint()..color = beardC);
        if (big) {
          final hl = Paint()
            ..color = Color.lerp(beardC, Colors.white, 0.18)!
            ..strokeWidth = lw * 0.9
            ..strokeCap = StrokeCap.round;
          for (var i = 0; i < 9; i++) {
            final u0 = -0.7 + 0.175 * i;
            cv.drawLine(p(u0, -0.62 - 0.08 * (i % 2)), p(u0 + 0.03, -0.76 - 0.08 * (i % 2)), hl);
          }
        }
    }

    // ── 口（パワプロ風に小さく。力むと大きく開けて叫ぶ）──
    {
      final w = 0.17 * f.mouthWidth;
      if (effort) {
        final r = Rect.fromCenter(center: p(0, mv - 0.02), width: w * 2.1 * s, height: 0.22 * s);
        final o = Path()..addOval(r);
        cv.drawPath(o, Paint()..color = const Color(0xFF7A1E22));
        cv.save();
        cv.clipPath(o);
        cv.drawRect(Rect.fromLTWH(r.left, r.top, r.width, r.height * 0.3), Paint()..color = const Color(0xFFF7F5EE)); // 上の歯
        cv.drawOval(Rect.fromCenter(center: Offset(r.center.dx, r.bottom), width: r.width * 0.7, height: r.height * 0.5), Paint()..color = const Color(0xFFD9575B)); // 舌
        cv.restore();
        cv.drawPath(
          o,
          Paint()
            ..color = _ink
            ..style = PaintingStyle.stroke
            ..strokeWidth = lw * 1.5,
        );
      } else {
        final line = Paint()
          ..color = const Color(0xFF4A2522)
          ..style = PaintingStyle.stroke
          ..strokeWidth = lw * 1.7
          ..strokeCap = StrokeCap.round;
        final (dy0, dyc) = switch (f.mouthShape) {
          1 => (0.035, -0.045),
          2 => (-0.03, 0.035),
          _ => (0.0, -0.012),
        };
        final m = Path()
          ..moveTo(p(-w, mv + dy0).dx, p(-w, mv + dy0).dy)
          ..quadraticBezierTo(p(0, mv + dyc).dx, p(0, mv + dyc).dy, p(w, mv + dy0).dx, p(w, mv + dy0).dy);
        cv.drawPath(m, line);
        if (f.mouthShape == 3) {
          cv.drawOval(Rect.fromCenter(center: p(0, mv - 0.05 * f.lip), width: w * 1.3 * s, height: 0.05 * f.lip * s), Paint()..color = Color.lerp(skin, const Color(0xFFB5524A), 0.4)!);
        }
      }
    }

    // ── アイブラック（目の下の黒塗り）──
    if (f.accessory == 1) {
      for (final sx in [-1.0, 1.0]) {
        final r = Rect.fromCenter(center: p(sx * ex, ez - 0.24), width: 0.32 * s, height: 0.085 * s);
        cv.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(0.02 * s)), Paint()..color = const Color(0xE6141414));
      }
    }

    // ── ほくろ（しわは目の下のくまとして _eye で描く）──
    if (f.mole >= 0) {
      final (mu, mvv) = switch (f.mole) {
        0 => (0.42, ez - 0.26),
        1 => (-0.26, mv - 0.03),
        _ => (0.55, -0.42),
      };
      cv.drawCircle(p(mu, mvv), math.max(1.0, 0.022 * s), Paint()..color = const Color(0xFF3A2A22));
    }

    // ── 目 ──
    if (f.accessory != 2) {
      for (final sx in [-1.0, 1.0]) {
        _eye(cv, f, p, s, lw, sx, ex, ez, blink: blink, effort: effort, big: big);
      }
    } else {
      // スポーツサングラス：両目をおおう 1 枚の暗いレンズと、つやの線
      Offset q(double u, double v) => p(u, ez + v);
      final g = Path()
        ..moveTo(q(-0.8, 0.15).dx, q(-0.8, 0.15).dy)
        ..quadraticBezierTo(q(0, 0.21).dx, q(0, 0.21).dy, q(0.8, 0.15).dx, q(0.8, 0.15).dy)
        ..quadraticBezierTo(q(0.74, -0.14).dx, q(0.74, -0.14).dy, q(0.42, -0.15).dx, q(0.42, -0.15).dy)
        ..quadraticBezierTo(q(0.12, -0.14).dx, q(0.12, -0.14).dy, q(0, -0.03).dx, q(0, -0.03).dy)
        ..quadraticBezierTo(q(-0.12, -0.14).dx, q(-0.12, -0.14).dy, q(-0.42, -0.15).dx, q(-0.42, -0.15).dy)
        ..quadraticBezierTo(q(-0.74, -0.14).dx, q(-0.74, -0.14).dy, q(-0.8, 0.15).dx, q(-0.8, 0.15).dy)
        ..close();
      cv.drawPath(g, Paint()..color = const Color(0xFF1E2430));
      cv.drawPath(
        g,
        Paint()
          ..color = _ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = lw * 1.4,
      );
      cv.drawLine(
        q(-0.55, 0.09),
        q(-0.3, 0.11),
        Paint()
          ..color = const Color(0x8CA8C8E8)
          ..strokeWidth = lw * 1.6
          ..strokeCap = StrokeCap.round,
      );
    }
    if (f.accessory == 4) {
      // メガネ：丸みのある四角い枠と、まん中のブリッジ
      final fr = Paint()
        ..color = const Color(0xFF2B2B33)
        ..style = PaintingStyle.stroke
        ..strokeWidth = lw * 1.7;
      for (final sx in [-1.0, 1.0]) {
        final r = Rect.fromCenter(center: p(sx * ex, ez + 0.01), width: 0.5 * s, height: 0.36 * s);
        cv.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(0.1 * s)), fr);
      }
      cv.drawLine(p(-ex + 0.25, ez + 0.05), p(ex - 0.25, ez + 0.05), fr);
    }

    // ── 眉（目のすぐ上・帽子のつばの下）──
    for (final sx in [-1.0, 1.0]) {
      _brow(cv, f, p, s, lw, sx, ex, ez, effort: effort, color: Color.lerp(hair, Colors.black, 0.2)!);
    }

    // ── 鼻の絆創膏（鼻は描かないが、顔のまん中に貼る）──
    if (f.accessory == 3) {
      final r = Rect.fromCenter(center: p(0, -0.49), width: 0.34 * s, height: 0.085 * s);
      final rr = RRect.fromRectAndRadius(r, Radius.circular(0.03 * s));
      cv.drawRRect(rr, Paint()..color = const Color(0xFFEFD6AE));
      cv.drawRRect(
        rr,
        Paint()
          ..color = const Color(0xFFB89B70)
          ..style = PaintingStyle.stroke
          ..strokeWidth = lw * 0.8,
      );
      for (var i = -2; i <= 2; i++) {
        cv.drawCircle(p(i * 0.035, -0.49), lw * 0.45, Paint()..color = const Color(0xFFC8AA7C));
      }
    }
  }

  /// 目の形（頭の半径に対して）：(横の半分, 上のふくらみ, 下のふくらみ, 傾き°, 黒目の半径, 黒目が上まぶたに隠れる割合, 上を平らに切る高さ（0＝切らない）, 目じりで線が下へ回り込む量 0〜1, 線を目の外へ伸ばす長さ)
  ///  パワプロの男性の目：まつ毛やはねは描かない。太い黒の上まぶたの線が目じりで下へ回り込み、模様のないこげ茶の黒目が上まぶたに少し隠れる。下まぶたの線はない
  static (double, double, double, double, double, double, double, double, double) _eyeShape(int style) => switch (style) {
    1 => (0.23, 0.12, 0.09, 11.0, 0.1, 0.2, 0.0, 0.75, 0.02), // キリッ（つり目）
    2 => (0.22, 0.14, 0.1, -11.0, 0.105, 0.15, 0.0, 0.85, 0.0), // タレ目
    3 => (0.22, 0.15, 0.1, 0.0, 0.105, 0.55, 0.05, 0.35, 0.03), // ジト目（上が平ら＝半目）
    4 => (0.21, 0.1, 0.06, 4.0, 0.0, 0.0, 0.0, 0.0, 0.0), // 細目（線だけ）
    5 => (0.18, 0.16, 0.15, 0.0, 0.115, 0.1, 0.0, 0.5, 0.0), // 丸目
    7 => (0.23, 0.13, 0.11, 5.0, 0.068, 0.12, 0.0, 0.6, 0.0), // 三白眼（黒目が小さい）
    8 => (0.18, 0.15, 0.13, 0.0, 0.135, 0.1, 0.0, 0.5, 0.0), // つぶら（黒目が大きい）
    9 => (0.24, 0.1, 0.07, 16.0, 0.08, 0.2, 0.0, 0.95, 0.03), // 鋭い
    10 => (0.22, 0.13, 0.09, -2.0, 0.1, 0.62, 0.035, 0.15, 0.08), // 眠そう（長く平らな線の下に黒目が半分）
    11 => (0.22, 0.16, 0.12, 4.0, 0.12, 0.18, 0.0, 1.0, 0.0), // 力強い（線が太く、目じりを大きく回り込む）
    _ => (0.21, 0.15, 0.11, 0.0, 0.11, 0.15, 0.0, 0.6, 0.0), // ふつう
  };

  /// 太さの変わる線（筆で描いたような上まぶたの線）。th(u)：線の始まり 0〜終わり 1 での太さ（px）
  static void _ribbon(Canvas cv, List<Offset> pts, double Function(double) th, Color c) {
    if (pts.length < 2) return;
    final l = <Offset>[], r = <Offset>[];
    for (var i = 0; i < pts.length; i++) {
      final a = pts[math.max(0, i - 1)], b = pts[math.min(pts.length - 1, i + 1)];
      final d = b - a;
      final len = math.max(1e-6, d.distance);
      final nrm = Offset(-d.dy / len, d.dx / len);
      final t = th(i / (pts.length - 1)) / 2;
      l.add(pts[i] + nrm * t);
      r.add(pts[i] - nrm * t);
    }
    final path = Path()..addPolygon([...l, ...r.reversed], true);
    cv.drawPath(path, Paint()..color = c);
    // 両端を丸く
    cv.drawCircle(pts.first, th(0) / 2, Paint()..color = c);
    cv.drawCircle(pts.last, th(1) / 2, Paint()..color = c);
  }

  static void _eye(Canvas cv, FaceLook f, Offset Function(double, double) p, double s, double lw, double sx, double ex, double ez, {required bool blink, required bool effort, required bool big}) {
    final k = f.eyeSize;
    final lidT = math.max(lw * 1.9, 0.055 * s) * (f.eyeStyle == 11 ? 1.25 : 1.0); // 上まぶたの線の太さ（px）
    // 点目（パワプロくんの基本の目）：縦長のカプセル。上は黒く下へ青く、まん中に縦の白い光
    if (f.eyeStyle == 6) {
      final c = p(sx * (ex - 0.07), ez + 0.02);
      final w = 0.085 * s * k, h = (effort ? 0.16 : 0.29) * s * k;
      if (blink) {
        _ribbon(cv, [c - Offset(w * 0.9, 0), c + Offset(w * 0.9, 0)], (_) => lidT * 0.8, _ink);
        return;
      }
      final r = RRect.fromRectAndRadius(Rect.fromCenter(center: c, width: w, height: h), Radius.circular(w / 2));
      cv.drawRRect(
        r,
        Paint()..shader = ui.Gradient.linear(Offset(c.dx, c.dy - h / 2), Offset(c.dx, c.dy + h / 2), const [Color(0xFF0E0E16), Color(0xFF111325), Color(0xFF2B4FC4)], const [0, 0.55, 1]),
      );
      cv.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: c + Offset(0, -h * 0.1), width: w * 0.28, height: h * 0.5), Radius.circular(w * 0.14)), Paint()..color = Colors.white);
      return;
    }
    var (w, upH, loH, tilt, irisR, hide, flat, wrap, over) = _eyeShape(f.eyeStyle);
    if (effort) {
      flat = flat > 0 ? flat * 0.6 : upH * 0.5;
      hide = math.max(hide, 0.4);
      tilt += 8;
    }
    w *= k;
    upH *= k;
    loH *= k;
    irisR *= k;
    flat *= k;
    over *= k;
    final t = (tilt + f.eyeTilt * 0.6) * math.pi / 180;
    // (h：−1 目頭 … 1 目じり、v：上が＋、頭の半径が単位) → 画面。sx で左右を鏡に
    Offset at(double h, double v) {
      final x = h * w;
      final xx = x * math.cos(t) - v * math.sin(t), vv = x * math.sin(t) + v * math.cos(t);
      return p(sx * (ex + xx), ez + vv);
    }

    double upV(double h) {
      final v = upH * math.pow(math.max(0.0, 1 - h * h), 0.55).toDouble() * (1 - 0.12 * h); // 目頭側が少し高い
      return flat > 0 ? math.min(v, flat) : v;
    }

    double loV(double h) => -loH * math.pow(math.max(0.0, 1 - h * h), 0.8).toDouble();
    final hs = [for (var i = 0; i <= 18; i++) -1 + 2 * i / 18];
    // 細目・まばたき：少し弧を描く太い線だけ（細目は上へ、まばたきは下へふくらむ）
    if (f.eyeStyle == 4 || blink) {
      final up = f.eyeStyle == 4 && !blink;
      final pts = [for (final h in hs) at(h, up ? 0.035 * k * (1 - h * h) : -0.02 * k - 0.03 * k * (1 - h * h))];
      if (up) pts.add(at(1.1, -0.02 * k));
      _ribbon(cv, pts, (u) => lidT * (0.5 + 0.5 * math.sin(math.pi * math.min(1.0, u * 1.15))).clamp(0.45, 1.0), _ink);
      return;
    }
    // 白目
    final white = Path();
    for (var i = 0; i < hs.length; i++) {
      final q = at(hs[i], upV(hs[i]));
      i == 0 ? white.moveTo(q.dx, q.dy) : white.lineTo(q.dx, q.dy);
    }
    for (final h in hs.reversed) {
      final q = at(h, loV(h));
      white.lineTo(q.dx, q.dy);
    }
    white.close();
    cv.drawPath(white, Paint()..color = const Color(0xFFFCFCFA));
    // 黒目：模様のないこげ茶（外国人は色）。上が少し暗い。上まぶたに少し隠れる。光は左上に小さく 1 つ
    cv.save();
    cv.clipPath(white);
    final top = flat > 0 ? math.min(flat, upH) : upH;
    final ic = at(f.gazeX * sx * 0.5, top - irisR * (1 - hide) * 1.0);
    final ir = irisR * s;
    final irisC = Color.lerp(Color(f.iris), Colors.black, 0.25)!;
    cv.drawOval(
      Rect.fromCenter(center: ic, width: ir * 2, height: ir * 2.15),
      Paint()..shader = ui.Gradient.linear(ic - Offset(0, ir), ic + Offset(0, ir), [Color.lerp(irisC, Colors.black, 0.45)!, irisC]),
    );
    cv.drawCircle(ic + Offset(-ir * 0.34, -ir * (0.38 - hide * 0.5)), ir * 0.24, Paint()..color = Colors.white);
    cv.restore();
    // 上まぶたの太い線：目頭は細く、目じりで太く、目じりを下へ回り込む。眠そう・ジト目は目の外まで伸ばす
    final pts = <Offset>[];
    if (over > 0) pts.add(at(-1 - over / w, upV(-0.8) * 0.75));
    for (final h in hs) {
      pts.add(at(h, upV(h)));
    }
    if (over > 0) pts.add(at(1 + over / w, upV(0.8) * 0.75));
    if (wrap > 0) {
      final n = (6 * wrap).ceil();
      for (var i = 1; i <= n; i++) {
        final h = 1 - 0.5 * wrap * i / n;
        pts.add(at(h, loV(h) * 0.9));
      }
    }
    _ribbon(cv, pts, (u) => lidT * (u < 0.3 ? 0.35 + 0.65 * u / 0.3 : (wrap > 0 && u > 0.8 ? 1 - 0.55 * (u - 0.8) / 0.2 : 1.0)), _ink);
    final shade = Color.lerp(Color(f.skin), const Color(0xFF7A3B2A), 0.5)!;
    // 二重：上まぶたの線の上に、肌の影の色で細く（大きい画像だけ）
    if (big && f.lid == 1 && flat == 0) {
      _ribbon(
        cv,
        [for (var i = 0; i <= 8; i++) at(-0.3 + 1.2 * i / 8, upV(-0.3 + 1.2 * i / 8) + 0.055 * k + lidT / s * 0.5)],
        (u) => lw * 0.9 * math.sin(math.pi * (0.1 + 0.8 * u)),
        shade.withValues(alpha: 0.7),
      );
    }
    // 目の下のくま（ベテラン）
    if (big && f.wrinkle > 0) {
      _ribbon(
        cv,
        [for (var i = 0; i <= 8; i++) at(-0.7 + 1.3 * i / 8, loV(-0.7 + 1.3 * i / 8) - 0.05 * k)],
        (u) => lw * (f.wrinkle >= 2 ? 1.1 : 0.85) * math.sin(math.pi * (0.1 + 0.8 * u)),
        shade.withValues(alpha: 0.75),
      );
    }
  }

  static void _brow(Canvas cv, FaceLook f, Offset Function(double, double) p, double s, double lw, double sx, double ex, double ez, {required bool effort, required Color color}) {
    final st = f.browStyle;
    final len = (st == 9 ? 0.16 : (st == 7 ? 0.24 : 0.38)) * f.browLen;
    final th =
        (0.06 *
                f.browThick *
                switch (st) {
                  1 => 1.6,
                  6 => 1.5,
                  9 => 1.5,
                  2 => 0.55,
                  _ => 1.0,
                })
            .clamp(0.03, 0.15);
    final base = ez + 0.215 + (st == 9 ? 0.05 : 0);
    final inner = st == 9 ? ex - 0.06 : ex - 0.19;
    final ang = (f.browAngle.clamp(-10.0, 10.0) + (effort ? -10 : 0)) * math.pi / 180;
    double y(double h) =>
        switch (st) {
          3 => -0.05 + 0.14 * h, // つり
          4 => 0.1 * (1 - h) - 0.03, // 困り（八の字）
          5 => 0.09 * math.sin(math.pi * h) - 0.02, // への字
          8 => 0.1 * (h < 0.6 ? h / 0.6 : (1 - h) / 0.4), // 角ばった
          9 => 0.0,
          _ => 0.05 * math.sin(math.pi * h),
        } +
        (effort ? -0.06 * (1 - h) : 0);
    double t(double h) => switch (st) {
      9 => th * math.pow(math.sin(math.pi * math.max(0.02, math.min(0.98, h))), 0.5).toDouble(),
      6 => th * (1 - 0.15 * h) * (1 + 0.18 * math.sin(h * 40)), // ゲジゲジ：ふちがぎざぎざ
      _ => th * (1 - 0.35 * h),
    };
    Offset at(double h, double dv) {
      final x = h * len, yy = y(h) + dv;
      final xr = x * math.cos(ang) - yy * math.sin(ang), yr = x * math.sin(ang) + yy * math.cos(ang);
      return p(sx * (inner + xr), base + yr);
    }

    final pts = <Offset>[];
    const k = 16;
    for (var i = 0; i <= k; i++) {
      final h = i / k;
      pts.add(at(h, t(h) / 2));
    }
    for (var i = k; i >= 0; i--) {
      final h = i / k;
      pts.add(at(h, -t(h) / 2));
    }
    cv.drawPath(Path()..addPolygon(pts, true), Paint()..color = color);
  }
}
