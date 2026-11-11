import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';

import '../../engine/ball_spec.dart';
import '../../engine/vec3.dart';
import '../../models/stadium.dart';
import 'scene_util.dart';

/// 球場の 3D（寸法は Stadium から）。グラウンド・マウンド・ベース・白線・外野フェンス・ポール・ファウルエリアのフェンス・ベンチ・スタンドと観客・ビジョン・看板
class StadiumMesh {
  final Stadium st;
  final double fill; // 観客の入り（0〜1）
  final int homeColor, awayColor;
  final math.Random _r = math.Random(7);
  StadiumMesh(this.st, {this.fill = 0.8, this.homeColor = 0xFF1E3A8A, this.awayColor = 0xFFDC2626});

  static const deg = math.pi / 180;
  static V3 polar(double angDeg, double dist, [double z = 0]) => V3(dist * math.sin(angDeg * deg), dist * math.cos(angDeg * deg), z);

  bool get _esc => st.roofRidge > 0; // 屋根で閉じた球場（北の球場）
  bool get _grassIn => _esc || st.infield == 'grass'; // 内野が芝（走路と周りだけ土）
  bool get _cutout => !_esc && st.infield == 'cutout'; // 人工芝で、塁・マウンド・本塁の周りだけ土
  int get _dirt => _esc ? 0xFF8F4E33 : st.dirtColor;
  int get _turf => _esc ? 0xFF33742F : st.turfColor;
  ColorMesh? _u; // 光るもの（LED・ガラス・照明）：光の当たり方に関係なく色のまま

  List<Node> build() {
    final out = <Node>[];
    final u = ColorMesh()..faceTo = const V3(0, 45, 1.5);
    final ceil = ColorMesh()..faceDown = true; // 天井（下向き）
    // 地面・フェンス・スタンド・建物は、光の当たり方を色に焼き込んで光の計算なしで描く（観客が多く、光の計算は重い）
    final g = ColorMesh()
      ..faceUp = true
      ..bake = true; // 地面（頂点の色）
    final w = ColorMesh()
      ..faceTo = const V3(0, 45, 1.5)
      ..bake = true; // フェンス・スタンド・建物（グラウンドの方を向く）
    fillMesh(g, w, u, ceil);
    out.addAll(g.nodes(UnlitMaterial()));
    out.addAll(w.nodes(UnlitMaterial()));
    out.addAll(u.nodes(UnlitMaterial()));
    out.addAll(ceil.nodes(UnlitMaterial()));
    return out;
  }

  /// 形を作る（GPU の物を作らない部分。調べ用のテストからも呼ぶ）
  void fillMesh(ColorMesh g, ColorMesh w, ColorMesh u, ColorMesh ceil) {
    _u = u;
    _ground(g);
    _fence(w);
    final path = _foulPath();
    _foulWall(w, path);
    _foulNet(w, path);
    _dugouts(w, path);
    _stands(w, path);
    _backscreen(w);
    _vision(w);
    if (_esc) _closedRoof(w, ceil, u);
    if (st.domeHeight > 0) _dome(w, ceil, u);
    for (final b in st.buildings) {
      _esc ? _tower(w, u, b) : _building(w, b);
    }
    if (st.outfieldBullpens) _bullpens(w);
    _poles(w);
    _lightTowers(w, u);
    if (st.adRing) _adRing(w, u);
    _scenery(w, u);
  }

  // ───────── 地面 ─────────
  void _ground(ColorMesh m) {
    // 外側の芝（スタンドの下まで）
    m.color(_mixC(_turf, 0xFF000000, 0.18));
    m.quad(const V3(-260, -120, -0.02), const V3(260, -120, -0.02), const V3(260, 260, -0.02), const V3(-260, 260, -0.02));
    // 外野の芝：刈り目の縞（中堅方向に 5m ごと）
    // 格子の刈り目は細かく区切る（升目の境がギザギザにならないように）
    final checker = st.mow == 'checker';
    final n = checker ? 220 : 64;
    final dr = checker ? 1.25 : 5.0;
    for (var i = 0; i < n; i++) {
      final a0 = -45 + 90 * i / n, a1 = -45 + 90 * (i + 1) / n;
      for (var r = 0.0; r < 125; r += dr) {
        final f0 = st.fenceDistance(a0), f1 = st.fenceDistance(a1);
        final r1a = math.min(r + dr, f0 - 4.6), r1b = math.min(r + dr, f1 - 4.6);
        if (r >= r1a && r >= r1b) continue;
        if (st.mow == 'checker') {
          // 格子の刈り目：中堅の向きと直角の向きの 6m ごとの帯の重なり
          final mid = polar((a0 + a1) / 2, r + dr / 2);
          final u1 = ((mid.x + mid.y) / (6 * math.sqrt2)).floor(), u2 = ((mid.y - mid.x) / (6 * math.sqrt2)).floor();
          m.color((u1 + u2).isEven ? _turf : _mixC(_turf, 0xFFFFFFFF, 0.12));
        } else {
          m.color(((r ~/ 5) % 2 == 0) ? _turf : _mixC(_turf, 0xFFFFFFFF, 0.1));
        }
        m.quad(polar(a0, r, 0.001), polar(a1, r, 0.001), polar(a1, math.max(r, r1b), 0.001), polar(a0, math.max(r, r1a), 0.001));
      }
      // 外野の土（ウォーニングトラック 4.6m）
      m.color(st.warningColor ?? (_cutout ? _mixC(_turf, 0xFF000000, 0.3) : _mixC(_dirt, 0xFF000000, 0.15))); // 人工芝の球場は濃い色の芝
      m.quad(polar(a0, st.fenceDistance(a0) - 4.6, 0.002), polar(a1, st.fenceDistance(a1) - 4.6, 0.002), polar(a1, st.fenceDistance(a1), 0.002), polar(a0, st.fenceDistance(a0), 0.002));
    }
    // ファウルゾーンの本塁まわり（バックネットまで）：明るい土色をぼかす（図のとおり）
    for (var k = 0; k < (_esc || _cutout || _grassIn ? 0 : 6); k++) {
      final r = 19.0 - k * 2.6;
      m.color(_mixC(_mixC(_turf, 0xFF000000, 0.18), _dirt, 0.25 + 0.13 * k));
      _disc(m, V3(0, 0.6, 0.0005 + k * 0.0003), r, 56);
    }
    // 内野の土：投手板の中心から半径 95ft（28.96m）の弧。弧はファウルラインと本塁から約 38.9m で交わる（その間は塁間の内側も土）
    const rub = V3(0, 18.44, 0), rr = 28.96;
    final s2 = math.sqrt2 / 2;
    final mu = rub.y * s2;
    final tCross = mu + math.sqrt(mu * mu - rub.y * rub.y + rr * rr); // 弧とファウルラインの交点（本塁から）
    final angEnd = math.atan2(tCross * s2, tCross * s2 - rub.y); // 投手板から見た交点の角度
    m.color(_cutout ? _turf : _dirt); // 人工芝の球場（土は塁の周りだけ）は芝の色
    const segs = 72;
    for (var i = 0; i < segs; i++) {
      final a0 = -angEnd + 2 * angEnd * i / segs, a1 = -angEnd + 2 * angEnd * (i + 1) / segs;
      V3 arc(double a) => V3(rub.x + rr * math.sin(a), rub.y + rr * math.cos(a), 0.003);
      m.tri(const V3(0, 0, 0.003), arc(a1), arc(a0));
    }
    if (st.dirtFoul || st.foulTrack > 0) {
      final path = _foulPath();
      final s2f = math.sqrt2 / 2;
      double along(V3 p) => (p.x.abs() * s2f + p.y * s2f);
      for (var i = 0; i + 1 < path.length; i++) {
        final (pa, na) = path[i];
        final (pb, _) = path[i + 1];
        if (st.dirtFoul && along(pa) < 41 && along(pb) < 41) {
          // ファウルゾーンも土：本塁から客席の前まで（内野の弧が線と交わる所まで）
          m.color(_dirt);
          m.tri(const V3(0, 0, 0.0028), V3(pa.x, pa.y, 0.0028), V3(pb.x, pb.y, 0.0028));
        } else if (st.foulTrack > 0) {
          // 壁ぎわの土の帯
          m.color(_mixC(_dirt, 0xFF000000, 0.05));
          final wa = na * st.foulTrack;
          m.quad(V3(pa.x, pa.y, 0.0026), V3(pb.x, pb.y, 0.0026), V3(pb.x - wa.x, pb.y - wa.y, 0.0026), V3(pa.x - wa.x, pa.y - wa.y, 0.0026));
        }
      }
    }
    if (_grassIn) {
      // 内野の芝（塁間の内側。塁線から 1m 内側まで）と、塁線の外側の走路（0.9m）
      final bb = 27.43, ss = math.sqrt2 / 2, k = 1.0 * math.sqrt2;
      m.color(_mixC(_turf, 0xFF000000, 0.05));
      final h0 = V3(0, k, 0.0035), f1 = V3(bb * ss - k, bb * ss, 0.0035), s2b = V3(0, bb * math.sqrt2 - k, 0.0035), t3 = V3(-(bb * ss - k), bb * ss, 0.0035);
      m.quad(h0, f1, s2b, t3);
      m.color(_dirt);
      for (final sgn in [1.0, -1.0]) {
        final uu = V3(sgn * ss, ss, 0), nn = V3(sgn * ss, -ss, 0) * 0.9;
        final p0 = uu * 3.5 + V3(0, 0, 0.0035), p1 = uu * (bb - 1) + V3(0, 0, 0.0035);
        m.quad(p0, p1, p1 + nn, p0 + nn);
      }
    }
    // 本塁のまわりの円（半径 13ft＝3.96m。本塁の中心から）
    m.color(_cutout && st.cutoutColor != null ? st.cutoutColor! : _mixC(_dirt, 0xFF000000, 0.04));
    _disc(m, const V3(0, 0.22, 0.004), 3.96, 48);
    // 塁のまわりの少し濃い土（走路の踏み跡）
    m.color(_cutout && st.cutoutColor != null ? _mixC(st.cutoutColor!, 0xFF000000, 0.04) : _mixC(_dirt, 0xFF000000, 0.07));
    final b = 27.43;
    for (final c in [V3(b * s2, b * s2, 0.0045), V3(0, b * math.sqrt2, 0.0045), V3(-b * s2, b * s2, 0.0045)]) {
      _disc(m, c, _esc ? 2.6 : (_cutout ? 2.9 : 2.0), 28); // 人工芝の球場は塁の周りの土（カットアウト）が大きい
    }
    // ネクストバッターズサークル（直径 1.52m。本塁の左右後方）
    m.color(0xFFF1F1EE);
    for (final sgn in [1.0, -1.0]) {
      _ring(m, V3(sgn * 11.0, -4.5, 0.006), 0.76, 0.05, 32);
    }
    // コーチャーズボックス（一塁・三塁の外側、6.1m × 3.05m の白線）
    for (final sgn in [1.0, -1.0]) {
      final c = V3(sgn * (b * s2 + 4.0), b * s2 - 4.0, 0.006);
      _rectLine(m, c, 3.05, 6.1, 0.05);
    }
    // スリーフットライン（本塁から一塁の後半、ラインの外 0.91m）
    for (var i = 0; i < 2; i++) {
      final off = i == 0 ? 0.0 : 0.91;
      final p0 = V3(13.7 * s2 + off * s2, 13.7 * s2 - off * s2, 0.007), p1 = V3(b * s2 + off * s2, b * s2 - off * s2, 0.007);
      final n = V3(s2, -s2, 0) * 0.025;
      m.quad(p0 - n, p0 + n, p1 + n, p1 - n);
    }
    m.quad(V3(13.7 * s2, 13.7 * s2, 0.007), V3(13.7 * s2 + 0.91 * s2, 13.7 * s2 - 0.91 * s2, 0.007), V3(13.7 * s2 + 0.91 * s2 + 0.035, 13.7 * s2 - 0.91 * s2 + 0.035, 0.007), V3(13.7 * s2 + 0.035, 13.7 * s2 + 0.035, 0.007));
    const mound = V3(0, 18.29, 0);
    // マウンド（半径 2.74m。投手板の前 15cm から本塁側は 1フィートにつき 1インチ下がる）
    m.color(_cutout && st.cutoutColor != null ? st.cutoutColor! : _mixC(_dirt, 0xFF000000, 0.05));
    const rings = 14, sg = 48;
    double mz(V3 q) {
      final r = math.sqrt(q.x * q.x + (q.y - mound.y) * (q.y - mound.y));
      // 縁へなめらかに下がる。投手板の後ろは平らな頂上のまま（地面の式は後ろで急に 0 になるので使わない）
      final u = ((2.74 - r) / 1.3).clamp(0.0, 1.0);
      final edge = FieldSpec.moundHeight * u * u * (3 - 2 * u);
      final top = q.y >= FieldSpec.rubberFrontY ? FieldSpec.moundHeight : FieldSpec.groundZ(q.y);
      return math.min(top, edge) + 0.006;
    }

    for (var i = 0; i < rings; i++) {
      for (var j = 0; j < sg; j++) {
        V3 pt(int ii, int jj) {
          final r = 2.74 * ii / rings, a = 2 * math.pi * jj / sg;
          final q = V3(r * math.sin(a), mound.y + r * math.cos(a), 0);
          return V3(q.x, q.y, mz(q));
        }

        m.quad(pt(i, j), pt(i + 1, j), pt(i + 1, j + 1), pt(i, j + 1));
      }
    }
    // 投手板・本塁・ベース
    m.color(0xFFF5F5F5);
    m.box(const V3(0, FieldSpec.rubberFrontY + FieldSpec.rubberDepth / 2, FieldSpec.moundHeight + 0.006), FieldSpec.rubberWidth, FieldSpec.rubberDepth, 0.02);
    m.tri(const V3(0, 0, 0.012), const V3(0.2159, 0.2159, 0.012), const V3(-0.2159, 0.2159, 0.012));
    m.quad(const V3(-0.2159, 0.2159, 0.012), const V3(0.2159, 0.2159, 0.012), const V3(0.2159, 0.4318, 0.012), const V3(-0.2159, 0.4318, 0.012));
    for (final c in [V3(b * s2, b * s2, 0.04), V3(0, b * math.sqrt2, 0.04), V3(-b * s2, b * s2, 0.04)]) {
      m.box(c, 0.381, 0.381, 0.08, yaw: math.pi / 4);
    }
    // 白線：ファウルライン（7.6cm）とバッターボックス
    m.color(0xFFF8F8F8);
    for (final sgn in [1.0, -1.0]) {
      final f = st.fenceDistance(45 * sgn);
      final u = V3(sgn * s2, s2, 0), nrm = V3(s2, -sgn * s2, 0) * 0.038;
      m.quad(V3(0, 0, 0.013) + nrm, V3(0, 0, 0.013) - nrm, u * f + V3(0, 0, 0.013) - nrm, u * f + V3(0, 0, 0.013) + nrm);
      // バッターボックス（1.22m × 1.83m、本塁から 15cm）
      final cx = sgn * (0.2159 + 0.152 + 0.61);
      _rectLine(m, V3(cx, 0.2159, 0.014), 1.22, 1.83, 0.05);
    }
    _rectLine(m, const V3(0, -1.2, 0.014), 1.09, 2.44, 0.05); // キャッチャーボックス
  }

  void _ring(ColorMesh m, V3 c, double r, double w, int n) {
    for (var i = 0; i < n; i++) {
      final a0 = 2 * math.pi * i / n, a1 = 2 * math.pi * (i + 1) / n;
      V3 at(double rad, double a) => V3(c.x + rad * math.sin(a), c.y + rad * math.cos(a), c.z);
      m.quad(at(r - w, a0), at(r - w, a1), at(r, a1), at(r, a0));
    }
  }

  static int _mixC(int a, int c, double t) {
    int ch(int sh) => (((a >> sh) & 255) * (1 - t) + ((c >> sh) & 255) * t).round().clamp(0, 255);
    return 0xFF000000 | (ch(16) << 16) | (ch(8) << 8) | ch(0);
  }

  void _disc(ColorMesh m, V3 c, double r, int n) {
    for (var i = 0; i < n; i++) {
      final a0 = 2 * math.pi * i / n, a1 = 2 * math.pi * (i + 1) / n;
      m.tri(c, V3(c.x + r * math.sin(a1), c.y + r * math.cos(a1), c.z), V3(c.x + r * math.sin(a0), c.y + r * math.cos(a0), c.z));
    }
  }

  void _rectLine(ColorMesh m, V3 c, double w, double h, double t) {
    final x0 = c.x - w / 2, x1 = c.x + w / 2, y0 = c.y - h / 2, y1 = c.y + h / 2, z = c.z;
    m.quad(V3(x0, y0, z), V3(x1, y0, z), V3(x1, y0 + t, z), V3(x0, y0 + t, z));
    m.quad(V3(x0, y1 - t, z), V3(x1, y1 - t, z), V3(x1, y1, z), V3(x0, y1, z));
    m.quad(V3(x0, y0, z), V3(x0 + t, y0, z), V3(x0 + t, y1, z), V3(x0, y1, z));
    m.quad(V3(x1 - t, y0, z), V3(x1, y0, z), V3(x1, y1, z), V3(x1 - t, y1, z));
  }

  // ───────── 外野フェンス（ラバー）と看板 ─────────
  void _fence(ColorMesh m) {
    const n = 90;
    for (var i = 0; i < n; i++) {
      final a0 = -45 + 90 * i / n, a1 = -45 + 90 * (i + 1) / n;
      final d0 = st.fenceDistance(a0), d1 = st.fenceDistance(a1), h0 = st.fenceHeight(a0), h1 = st.fenceHeight(a1);
      // 看板の色（スポンサーごと）
      final ad = st.ads.where((x) => x.place == '外野フェンス' && a0 >= x.fromAngle && a0 < x.toAngle).firstOrNull;
      if (_esc) {
        // 黒い壁に、間をあけて広告のロゴ（架空）。上に水色の線
        m.color(0xFF0E131B);
        m.quad(polar(a0, d0, 0), polar(a1, d1, 0), polar(a1, d1, h1 * 0.94), polar(a0, d0, h0 * 0.94));
        // 広告（架空）：5区画で1社。左に色のマーク、右に白い社名の帯
        if (i % 5 == 1) {
          m.color(_adColor(i ~/ 5));
          m.quad(polar(a0, d0 - 0.02, h0 * 0.3), polar(a1, d1 - 0.02, h1 * 0.3), polar(a1, d1 - 0.02, h1 * 0.72), polar(a0, d0 - 0.02, h0 * 0.72));
        } else if (i % 5 == 2 || i % 5 == 3) {
          m.color((i ~/ 5).isEven ? 0xFFE5E7EB : _mixC(_adColor(i ~/ 5), 0xFFFFFFFF, 0.55));
          final lo = i % 5 == 2 ? 0.44 : 0.47, hi = i % 5 == 2 ? 0.6 : 0.57;
          m.quad(polar(a0, d0 - 0.02, h0 * lo), polar(a1, d1 - 0.02, h1 * lo), polar(a1, d1 - 0.02, h1 * hi), polar(a0, d0 - 0.02, h0 * hi));
        }
        m.color(0xFF38B6D8);
        m.quad(polar(a0, d0, h0 * 0.94), polar(a1, d1, h1 * 0.94), polar(a1, d1, h1), polar(a0, d0, h0));
        m.color(0xFF0B0F15);
        m.quad(polar(a0, d0, h0), polar(a1, d1, h1), polar(a1, d1 + 0.4, h1), polar(a0, d0 + 0.4, h0));
        continue;
      }
      final ivy = st.id == 'koshien'; // つたの壁（広告なし）
      final net = st.fenceNet;
      final r0 = math.max(0.8, h0 - net), r1 = math.max(0.8, h1 - net); // ラバーの高さ（その上は金網）
      // 足もとの濃い帯
      m.color(_mixC(st.fenceColor, 0xFF000000, 0.28));
      m.quad(polar(a0, d0, 0), polar(a1, d1, 0), polar(a1, d1, 0.25), polar(a0, d0, 0.25));
      // ラバーの面（広告の板・白い字は 2D の側で上に貼る）
      final face = ivy || st.fenceAds != 'color' || ad == null ? st.fenceColor : _adColor(st.ads.indexOf(ad));
      final band = net <= 0 && st.fenceTop != 0 ? 0.12 : 0.0; // 金網がなければ、ラバーの上端に本塁打の目印の線
      m.color(face);
      m.quad(polar(a0, d0 - 0.01, 0.25), polar(a1, d1 - 0.01, 0.25), polar(a1, d1 - 0.01, r1 - band), polar(a0, d0 - 0.01, r0 - band));
      if (band > 0) {
        m.color(st.fenceTop);
        m.quad(polar(a0, d0 - 0.01, r0 - band), polar(a1, d1 - 0.01, r1 - band), polar(a1, d1 - 0.01, r1), polar(a0, d0 - 0.01, r0));
      }
      if (ivy) {
        // つたの葉の濃淡（ところどころ）
        for (var k = 0; k < 3; k++) {
          final z0 = r0 * (0.25 + k * 0.22), f0 = (i * 7 + k * 3) % 5 / 5.0;
          m.color(_mixC(st.fenceColor, k.isEven ? 0xFF000000 : 0xFF7BC96F, 0.2));
          final q0 = a0 + (a1 - a0) * f0, q1 = q0 + (a1 - a0) * 0.45;
          m.quad(polar(q0, d0 - 0.02, z0), polar(q1, d1 - 0.02, z0), polar(q1, d1 - 0.02, z0 + r0 * 0.15), polar(q0, d0 - 0.02, z0 + r0 * 0.15));
        }
      }
      // ラバーの上面（厚み）
      m.color(_mixC(st.fenceColor, 0xFF000000, 0.35));
      m.quad(polar(a0, d0, r0), polar(a1, d1, r1), polar(a1, d1 + 0.35, r1), polar(a0, d0 + 0.35, r0));
      if (net > 0) {
        // 金網：支柱（約 4m ごと）・上の枠（本塁打の目印の色）・中ほどの横の針金。網の目は 2D の側で半透明に描く
        if (i % 2 == 0) {
          m.color(0xFF3F4650);
          m.box(polar(a0, d0 + 0.18, (r0 + h0) / 2), 0.09, 0.09, h0 - r0);
        }
        m.color(st.fenceTop != 0 ? st.fenceTop : 0xFF3F4650);
        m.quad(polar(a0, d0 + 0.18, h0 - 0.1), polar(a1, d1 + 0.18, h1 - 0.1), polar(a1, d1 + 0.18, h1), polar(a0, d0 + 0.18, h0));
        m.color(0xFF4B5563);
        final zm0 = (r0 + h0) / 2, zm1 = (r1 + h1) / 2;
        m.quad(polar(a0, d0 + 0.18, zm0 - 0.02), polar(a1, d1 + 0.18, zm1 - 0.02), polar(a1, d1 + 0.18, zm1 + 0.02), polar(a0, d0 + 0.18, zm0 + 0.02));
      }
      if (st.oldFence > 0) {
        // テラス席（ラグーン・ウイング）の後ろの元のフェンスと、テラスの床
        final g0 = math.max(0.5, st.terraceGap(a0)), g1 = math.max(0.5, st.terraceGap(a1));
        final e0 = d0 + 0.35 + g0, e1 = d1 + 0.35 + g1, oh = st.oldFence;
        m.color(0xFF3A3F47);
        m.quad(polar(a0, d0 + 0.35, 0.04), polar(a1, d1 + 0.35, 0.04), polar(a1, e1, 0.04), polar(a0, e0, 0.04));
        m.color(st.oldFenceColor);
        m.quad(polar(a0, e0, 0), polar(a1, e1, 0), polar(a1, e1, oh * 0.55), polar(a0, e0, oh * 0.55));
        m.color(st.oldFenceUpper != 0 ? st.oldFenceUpper : _mixC(st.oldFenceColor, 0xFFFFFFFF, 0.07));
        m.quad(polar(a0, e0, oh * 0.55), polar(a1, e1, oh * 0.55), polar(a1, e1, oh), polar(a0, e0, oh));
        m.color(_mixC(st.oldFenceColor, 0xFF000000, 0.3));
        m.quad(polar(a0, e0, oh), polar(a1, e1, oh), polar(a1, e1 + 0.4, oh), polar(a0, e0 + 0.4, oh));
      }
    }
  }

  int _adColor(int i) => const [0xFFDC2626, 0xFF1D4ED8, 0xFFF59E0B, 0xFF059669, 0xFF7C3AED, 0xFFDB2777, 0xFF0891B2, 0xFFEA580C, 0xFF16A34A, 0xFF4F46E5, 0xFFB91C1C, 0xFF0F766E][i % 12];

  // ───────── ファウルエリアのフェンス（本塁を回って両ポールまで） ─────────
  /// フェンスの線（本塁基準の座標の点の列。右翼ポール → 一塁 → バックネット → 三塁 → 左翼ポール）と、外向きの向き
  List<(V3, V3)> _foulPath() {
    final pts = <(V3, V3)>[];
    final s2 = math.sqrt2 / 2;
    final rightU = V3(s2, s2, 0), rightN = V3(s2, -s2, 0);
    final leftU = V3(-s2, s2, 0), leftN = V3(-s2, -s2, 0);
    final pole = st.fenceDistance(45);
    double off(double s, double foul) {
      if (s >= 40) return foul + (st.foulCorner - foul) * ((s - 40) / (pole - 40));
      return foul;
    }

    for (var s = pole; s >= 6; s -= 2) {
      pts.add((rightU * s + rightN * off(s, st.foulFirst), rightN));
    }
    // 本塁の後ろ：一塁側の点から、バックネット（本塁の後ろ backstop m）を通って三塁側へ
    final pr = rightU * 6 + rightN * st.foulFirst, pl = leftU * 6 + leftN * st.foulThird;
    final ar = math.atan2(pr.x, pr.y), al = math.atan2(pl.x, pl.y) + 2 * math.pi;
    final rr = pr.length, rl = pl.length;
    for (var i = 1; i < 24; i++) {
      final t = i / 24;
      final a = ar + (al - ar) * t;
      final back = (a - math.pi).abs() < 0.9 ? 1 - ((a - math.pi).abs() / 0.9) : 0.0;
      final r = (rr + (rl - rr) * t) * (1 - back) + st.backstop * back;
      final p = V3(r * math.sin(a), r * math.cos(a), 0);
      pts.add((p, p.unit));
    }
    for (var s = 6.0; s <= st.fenceDistance(-45); s += 2) {
      pts.add((leftU * s + leftN * off(s, st.foulThird), leftN));
    }
    return pts;
  }

  bool _inDugout(V3 p) {
    for (final d in [st.homeDugout, st.awayDugout]) {
      final s2 = math.sqrt2 / 2;
      final u = d.side == 1 ? V3(s2, s2, 0) : V3(-s2, s2, 0);
      final s = p.dot(u);
      final lat = (p - u * s).length;
      if (s >= d.start && s <= d.start + d.length && lat > 5) return true;
    }
    return false;
  }

  void _foulWall(ColorMesh m, List<(V3, V3)> path) {
    for (var i = 0; i + 1 < path.length; i++) {
      final (a, na) = path[i];
        final (b, nb) = path[i + 1];
      if (_inDugout(a) && _inDugout(b)) continue;
      final back = (a.y < 0 && b.y < 0);
      final h = back ? 1.6 : 1.2;
      if (_esc) {
        // 黒い低い壁と、その上の横長の LED 広告（架空）
        m.color(0xFF101318);
        m.quad(V3(a.x, a.y, 0), V3(b.x, b.y, 0), V3(b.x, b.y, h), V3(a.x, a.y, h));
        _u!.color(const [0xFFF4F4F5, 0xFF0B3D91, 0xFFE11D48, 0xFF0EA5E9, 0xFFFACC15, 0xFF1E293B][(i ~/ 3) % 6]);
        _u!.quad(V3(a.x, a.y, h), V3(b.x, b.y, h), V3(b.x, b.y, h + 0.8), V3(a.x, a.y, h + 0.8));
        if (back) {
          m.color(0xFF2A2D33);
          for (final z in [4.0, 6.5, 9.0]) {
            m.quad(V3(a.x, a.y, z), V3(b.x, b.y, z), V3(b.x, b.y, z + 0.04), V3(a.x, a.y, z + 0.04));
          }
        }
        continue;
      }
      m.color(0xFF1E3A5F);
      m.quad(V3(a.x, a.y, 0), V3(b.x, b.y, 0), V3(b.x, b.y, h), V3(a.x, a.y, h));
      m.color(0xFF152A45);
      m.quad(V3(a.x, a.y, h), V3(b.x, b.y, h), V3(b.x + nb.x * 0.3, b.y + nb.y * 0.3, h), V3(a.x + na.x * 0.3, a.y + na.y * 0.3, h));
      // バックネット（本塁の後ろは高いネット。細い柱と半透明の代わりに暗い格子）
      if (back) {
        m.color(0xFF3F3F46);
        for (final z in [3.0, 5.0, 7.0, 9.0]) {
          m.quad(V3(a.x, a.y, z), V3(b.x, b.y, z), V3(b.x, b.y, z + 0.05), V3(a.x, a.y, z + 0.05));
        }
      }
    }
  }

  // ───────── ファウルゾーンと客席の境のネット（本塁の後ろは高い）：支柱・上と下のワイヤー・網目 ─────────
  void _foulNet(ColorMesh m, List<(V3, V3)> path) {
    var acc = 0.0;
    for (var i = 0; i + 1 < path.length; i++) {
      final (a, na) = path[i];
      final (b, _) = path[i + 1];
      if (_inDugout(a) && _inDugout(b)) continue;
      final ha = st.netTop(a.x, a.y), hb = st.netTop(b.x, b.y);
      final base = (a.y < 0 && b.y < 0) ? 1.6 : 1.2;
      final pa = a + na * 0.15, pb = b + na * 0.15;
      // 網目（細い縦糸を 0.5m ごと、横糸を 0.5m ごと）
      m.color(0xFF3B4048);
      final seg = pa.distanceTo(pb);
      final nV = math.max(1, (seg / 0.5).round());
      for (var k = 0; k < nV; k++) {
        final q = pa.lerp(pb, k / nV);
        final h = ha + (hb - ha) * k / nV;
        final sd = (pb - pa).unit * 0.012;
        m.quad(q - sd + V3(0, 0, base), q + sd + V3(0, 0, base), q + sd + V3(0, 0, h), q - sd + V3(0, 0, h));
      }
      for (var z = base + 0.5; z < math.max(ha, hb); z += 0.5) {
        if (z > math.min(ha, hb)) break;
        m.quad(pa + V3(0, 0, z), pb + V3(0, 0, z), pb + V3(0, 0, z + 0.024), pa + V3(0, 0, z + 0.024));
      }
      // 上のワイヤー（太め）
      m.color(0xFF22262B);
      m.quad(pa + V3(0, 0, ha - 0.05), pb + V3(0, 0, hb - 0.05), pb + V3(0, 0, hb + 0.05), pa + V3(0, 0, ha + 0.05));
      // 支柱（約 10m ごと）
      acc += seg;
      if (acc > 10) {
        acc = 0;
        m.box(pa + na * 0.1 + V3(0, 0, ha / 2), 0.14, 0.14, ha);
      }
    }
  }

  // ───────── ベンチ（掘り下げ・屋根） ─────────
  void _dugouts(ColorMesh m, List<(V3, V3)> path) {
    for (final d in [st.homeDugout, st.awayDugout]) {
      final s2 = math.sqrt2 / 2;
      final u = d.side == 1 ? V3(s2, s2, 0) : V3(-s2, s2, 0);
      final n = d.side == 1 ? V3(s2, -s2, 0) : V3(-s2, -s2, 0);
      final foul = d.side == 1 ? st.foulFirst : st.foulThird;
      final a = u * d.start + n * foul, b = u * (d.start + d.length) + n * foul;
      final a2 = a + n * 3.2, b2 = b + n * 3.2;
      final z0 = -d.depth;
      m.color(0xFF27272A); // 床
      m.quad(V3(a.x, a.y, z0), V3(b.x, b.y, z0), V3(b2.x, b2.y, z0), V3(a2.x, a2.y, z0));
      m.color(0xFF3F3F46); // 奥の壁
      m.quad(V3(a2.x, a2.y, z0), V3(b2.x, b2.y, z0), V3(b2.x, b2.y, 2.2), V3(a2.x, a2.y, 2.2));
      m.color(0xFF52525B); // 前の低い壁（グラウンド側）
      m.quad(V3(a.x, a.y, z0), V3(b.x, b.y, z0), V3(b.x, b.y, 0.0), V3(a.x, a.y, 0.0));
      // ベンチの椅子
      m.color(0xFF1D4ED8);
      final c = (a2 + b2) * 0.5 - n * 0.6;
      m.box(V3(c.x, c.y, z0 + 0.25), d.length * 0.9, 0.45, 0.45, yaw: math.atan2(u.y, u.x));
      if (d.roof) {
        m.color(d == st.homeDugout ? homeColor : awayColor);
        m.quad(V3(a.x - n.x * 0.3, a.y - n.y * 0.3, 2.2), V3(b.x - n.x * 0.3, b.y - n.y * 0.3, 2.2), V3(b2.x, b2.y, 2.2), V3(a2.x, a2.y, 2.2));
      }
      // 両端の壁
      m.color(0xFF3F3F46);
      m.quad(V3(a.x, a.y, z0), V3(a2.x, a2.y, z0), V3(a2.x, a2.y, 2.2), V3(a.x, a.y, 2.2));
      m.quad(V3(b2.x, b2.y, z0), V3(b.x, b.y, z0), V3(b.x, b.y, 2.2), V3(b2.x, b2.y, 2.2));
    }
  }

  // ───────── スタンドと観客 ─────────
  void _stands(ColorMesh m, List<(V3, V3)> foul) {
    // 外野スタンドの線（フェンスの外側）
    final outfield = <(V3, V3)>[];
    // ポールの少し外（±50°）まで：内野側の席とすき間なくつなぐ
    for (var a = -50.0; a <= 50.0; a += 1.25) {
      final p = polar(a, st.fenceDistance(a.clamp(-45.0, 45.0)) + 0.4);
      outfield.add((p, p.unit));
    }
    for (final t in st.stands) {
      final isOut = t.area == '外野';
      final base = isOut ? outfield : foul;
      // 外野の席は、ポールまでの範囲ならポールの外まで延ばす
      final fromA = isOut && t.fromAngle <= -45 ? -50.0 : t.fromAngle, toA = isOut && t.toAngle >= 45 ? 50.0 : t.toAngle;
      final idx = <int>[];
      for (var i = 0; i < base.length; i++) {
        var ang = math.atan2(base[i].$1.x, base[i].$1.y) / deg;
        if (toA > 180 && ang < 0) ang += 360;
        if (ang >= fromA && ang <= toA) idx.add(i);
      }
      if (idx.isEmpty) continue;
      // となりの段とすき間ができないよう、両端に1点ずつ足す
      final i0 = math.max(0, idx.first - 1), i1 = math.min(base.length - 1, idx.last + 1);
      var pts = base.sublist(i0, i1 + 1);
      if (pts.length < 2) continue;
      final mainOf = isOut && t.setback > 0 && t.baseHeight < 10; // 外野のいちばん下の段（フェンスから下げてある）
      final terrace = isOut && t.rows <= 6 && t.baseHeight < 1.5; // テラス席（フェンスのすぐ後ろの低い席）
      var sb = t.setback;
      if (mainOf && st.oldFence > 0) {
        // テラスのある球場：元のフェンスのすぐ後ろから
        pts = [for (final (p, n) in pts) (p + n * (math.max(0.5, st.terraceGap(math.atan2(p.x, p.y) / deg)) + 0.35), n)];
        sb = 0;
      }
      // 外野の席はフェンスの上から（テラス席＝段の少ない低い席はフェンスの後ろの低い所）
      var fh = 0.0;
      for (final e in pts) {
        fh = math.max(fh, st.fenceHeight(math.atan2(e.$1.x, e.$1.y) / deg));
      }
      final b0 = isOut ? (t.rows > 6 && t.setback < 1 ? math.max(t.baseHeight, fh + 0.2) : t.baseHeight) : t.baseHeight + 0.4;
      for (var r = 0; r < t.rows; r++) {
        final off0 = 0.3 + sb + r * t.rowDepth, off1 = off0 + t.rowDepth;
        final z0 = b0 + r * t.rowRise, z1 = z0 + t.rowRise;
        for (var i = 0; i + 1 < pts.length; i++) {
          final (pa, na) = pts[i];
        final (pb, nb) = pts[i + 1];
          if (!isOut && (_inDugout(pa) || _inDugout(pb)) && r < 3) continue;
          // テラス席は元のフェンスの手前まで
          if (terrace && st.oldFence > 0 && off1 > math.min(st.terraceGap(math.atan2(pa.x, pa.y) / deg), st.terraceGap(math.atan2(pb.x, pb.y) / deg)) - 0.15) continue;
          final mid = (pa + pb) * 0.5;
          final ang = math.atan2(mid.x, mid.y) / deg;
          final aisle = (ang.abs() * 1.7).floor() % 9 == 0;
          // 段の蹴上げ（前の面）と踏み面。通路は明るい階段（蹴上げは少し暗く）
          m.color(aisle ? (_esc ? 0xFF5E646B : 0xFF7B828C) : (r == 0 ? 0xFF334155 : _shade(t.seatColor, r)));
          m.quad(pa + na * off0 + V3(0, 0, z0), pb + nb * off0 + V3(0, 0, z0), pb + nb * off0 + V3(0, 0, z1), pa + na * off0 + V3(0, 0, z1));
          m.color(aisle ? (_esc ? 0xFF9AA0A7 : 0xFF9CA3AF) : (_esc ? 0xFF383D43 : 0xFF64748B));
          m.quad(pa + na * off0 + V3(0, 0, z1), pb + nb * off0 + V3(0, 0, z1), pb + nb * off1 + V3(0, 0, z1), pa + na * off1 + V3(0, 0, z1));
          if (aisle) continue;
          // 座席の背もたれの列（空いた席も席に見えるように）
          m.color(_shade(t.seatColor, r + 1));
          final sb0 = off0 + t.rowDepth * 0.82;
          m.quad(pa + na * sb0 + V3(0, 0, z1), pb + nb * sb0 + V3(0, 0, z1), pb + nb * sb0 + V3(0, 0, z1 + 0.42), pa + na * sb0 + V3(0, 0, z1 + 0.42));
          // 観客：区画ごとの色（NPB：右翼の外野席はホーム、左翼はビジターの応援団。内野は私服が多い）
          final cheer = isOut && ang.abs() > 12; // 応援団
          final team = mid.x > 0 ? homeColor : awayColor;
          final seg = pa.distanceTo(pb);
          final count = (seg / 0.55).floor();
          for (var k = 0; k < count; k++) {
            if (_r.nextDouble() > fill * (cheer ? 1.15 : 1.0)) continue;
            final f = (k + 0.5) / count;
            final p = pa.lerp(pb, f) + na.lerp(nb, f) * (off0 + t.rowDepth * 0.55) + V3(0, 0, z1);
            final roll = _r.nextDouble();
            final shirt = cheer
                ? (roll < 0.82 ? team : (roll < 0.92 ? 0xFFF5F5F5 : 0xFF111827))
                : (roll < 0.28 ? team : const [0xFFF1F1EE, 0xFF1F2937, 0xFF6B7280, 0xFF334155, 0xFFE5E7EB, 0xFF9A3412][_r.nextInt(6)]);
            final side = V3(-na.y, na.x, 0);
            final sc = 0.9 + _r.nextDouble() * 0.18; // 体格の違い
            V3 up(double z) => V3(0, 0, z * sc);
            // 体（肩の張った台形）と両腕（ひじから下は膝の上へ）
            m.color(shirt);
            m.poly([p - side * 0.16 + up(0.05), p + side * 0.16 + up(0.05), p + side * 0.21 * sc + up(0.52), p + side * 0.11 + up(0.6), p - side * 0.11 + up(0.6), p - side * 0.21 * sc + up(0.52)]);
            final arm = _mixC(shirt, 0xFF000000, 0.18);
            m.color(arm);
            for (final sg in [-1.0, 1.0]) {
              final sh = p + side * (0.2 * sc * sg) + up(0.5);
              m.quad(sh, sh + side * (0.065 * sg), sh + side * (0.05 * sg) + up(-0.3), sh + side * (-0.01 * sg) + up(-0.3));
            }
            // 首と頭（八角形）、髪（上半分）
            final skin = const [0xFFE0AC8B, 0xFFC68642, 0xFFD4A276, 0xFFF1C27D][_r.nextInt(4)];
            m.color(skin);
            m.quad(p - side * 0.04 + up(0.58), p + side * 0.04 + up(0.58), p + side * 0.04 + up(0.66), p - side * 0.04 + up(0.66));
            final hc = p + up(0.75);
            m.poly([for (var q = 0; q < 8; q++) hc + side * (0.1 * math.cos(q * math.pi / 4)) + V3(0, 0, 0.115 * math.sin(q * math.pi / 4))]);
            final capOn = _r.nextDouble() < (cheer ? 0.45 : 0.25);
            m.color(capOn ? team : const [0xFF1C1917, 0xFF292524, 0xFF44403C, 0xFF57534E, 0xFF78350F][_r.nextInt(5)]);
            final hc2 = hc + na * -0.01;
            m.poly([hc2 + V3(0, 0, 0.03), for (var q = 0; q <= 4; q++) hc2 + side * (0.108 * math.cos(q * math.pi / 4)) + V3(0, 0, 0.125 * math.sin(q * math.pi / 4) + 0.005)]);
            // 応援団：腕を上げる人
            if (cheer && _r.nextDouble() < 0.3) {
              m.color(shirt);
              for (final sg in [-1.0, 1.0]) {
                final sh = p + side * (0.2 * sg) + V3(0, 0, 0.5);
                m.quad(sh, sh + side * (0.07 * sg), sh + side * (0.12 * sg) + V3(0, 0, 0.45), sh + side * (0.05 * sg) + V3(0, 0, 0.45));
              }
            }
          }
        }
      }
      // 最後列の後ろの壁と屋根のふち
      final zTop = b0 + t.rows * t.rowRise;
      final offTop = 0.3 + sb + t.rows * t.rowDepth;
      for (var i = 0; i + 1 < pts.length; i++) {
        final (pa, na) = pts[i];
        final (pb, nb) = pts[i + 1];
        if (terrace && st.oldFence > 0) continue; // 後ろは元のフェンス
        m.color(_esc ? 0xFF22262C : 0xFF94A3B8);
        // 北の球場：後ろは低い手すりの壁（上の層の前の帯を隠さない）。テラス席の後ろは低い手すり
        final wallTop = _esc && !isOut ? zTop + 1.0 : (terrace ? zTop + 0.9 : zTop + 3);
        m.quad(pa + na * offTop, pb + nb * offTop, pb + nb * offTop + V3(0, 0, wallTop), pa + na * offTop + V3(0, 0, wallTop));
        if (t.roofColor != 0 && st.roofRidge <= 0) {
          // 席の上の屋根：後ろの壁の上から前へ張り出す（甲子園の銀傘・幕張の一周する屋根など）。裏は暗い鉄骨、前のふちに照明
          final rz = zTop + t.roofRise;
          final r0 = V3(0, 0, rz), back = offTop + 1.0;
          final front = 0.3 + sb + (offTop - 0.3 - sb) * (1 - t.roofCover);
          m.color(t.roofColor);
          m.quad(pa + na * back + r0, pb + nb * back + r0, pb + nb * front + r0 + V3(0, 0, -1.2), pa + na * front + r0 + V3(0, 0, -1.2));
          _u!.color(_mixC(t.roofColor, 0xFF000000, 0.62)); // 裏（下から見える面）
          _u!.quad(pa + na * front + r0 + V3(0, 0, -1.6), pb + nb * front + r0 + V3(0, 0, -1.6), pb + nb * back + r0 + V3(0, 0, -0.4), pa + na * back + r0 + V3(0, 0, -0.4));
          m.color(_mixC(t.roofColor, 0xFF000000, 0.35)); // 前のふち
          m.quad(pa + na * front + r0 + V3(0, 0, -1.2), pb + nb * front + r0 + V3(0, 0, -1.2), pb + nb * front + r0 + V3(0, 0, -2.2), pa + na * front + r0 + V3(0, 0, -2.2));
          if (i % 3 == 0) {
            _u!.color(0xFFFFF8E1); // ふちの照明
            final q = pa + na * (front + 0.3) + r0 + V3(0, 0, -2.3);
            _u!.quad(q - (pb - pa) * 0.15, q + (pb - pa) * 0.15, q + (pb - pa) * 0.15 + V3(0, 0, -0.35), q - (pb - pa) * 0.15 + V3(0, 0, -0.35));
          }
          if (i % 12 == 0) {
            m.color(0xFF4B5563); // 屋根の柱
            m.box(pa + na * (offTop + 0.6) + V3(0, 0, rz / 2), 0.5, 0.5, rz);
          }
        }
        // 前のフェンスの下の壁（スタンドの最前列の下）。上の層は手すりの壁（下の層の上に張り出す）
        final fz = t.setback > 0 && !mainOf ? b0 - 2.2 : 0.0; // 外野のいちばん下の段は地面から壁
        if (_esc && t.setback > 0) {
          // 各層の前の光る帯（白と青）
          _u!.color(i % 9 == 0 ? 0xFFDCE6F5 : ((i ~/ 4) % 2 == 0 ? 0xFF1D4FC4 : 0xFF2A63D9));
          _u!.quad(pa + na * (0.3 + t.setback) + V3(0, 0, fz), pb + nb * (0.3 + t.setback) + V3(0, 0, fz), pb + nb * (0.3 + t.setback) + V3(0, 0, b0), pa + na * (0.3 + t.setback) + V3(0, 0, b0));
          // 帯の下：スイート席・ラウンジのガラス（ところどころ明かり）
          _u!.color(i % 3 == 0 ? 0xFF7D735E : 0xFF35404C);
          _u!.quad(pa + na * (0.3 + t.setback + 0.4) + V3(0, 0, fz - 3.0), pb + nb * (0.3 + t.setback + 0.4) + V3(0, 0, fz - 3.0), pb + nb * (0.3 + t.setback + 0.4) + V3(0, 0, fz - 0.3), pa + na * (0.3 + t.setback + 0.4) + V3(0, 0, fz - 0.3));
          // 帯の上の手すり（ガラスの細い線）
          m.color(0xFF4B5563);
          m.quad(pa + na * (0.3 + t.setback) + V3(0, 0, b0 + 0.9), pb + nb * (0.3 + t.setback) + V3(0, 0, b0 + 0.9), pb + nb * (0.3 + t.setback) + V3(0, 0, b0 + 1.0), pa + na * (0.3 + t.setback) + V3(0, 0, b0 + 1.0));
          // 帯の下の暗い面（上の層の床の裏）
          m.color(0xFF15181C);
          m.quad(pa + na * (0.3 + t.setback) + V3(0, 0, fz), pb + nb * (0.3 + t.setback) + V3(0, 0, fz), pb + nb * (0.3 + t.setback + 6) + V3(0, 0, fz), pa + na * (0.3 + t.setback + 6) + V3(0, 0, fz));
          continue;
        }
        if (t.setback > 0 && !isOut) {
          // 2層目の前：広告の帯（光る）と、その下のスイート席・ラウンジのガラスの帯
          _u!.color(const [0xFF1E293B, 0xFFE11D48, 0xFF0EA5E9, 0xFFF4F4F5, 0xFF1D4ED8, 0xFFFACC15][(i ~/ 4) % 6]);
          _u!.quad(pa + na * (0.3 + t.setback) + V3(0, 0, b0 - 1.1), pb + nb * (0.3 + t.setback) + V3(0, 0, b0 - 1.1), pb + nb * (0.3 + t.setback) + V3(0, 0, b0), pa + na * (0.3 + t.setback) + V3(0, 0, b0));
          _u!.color(i % 3 == 0 ? 0xFF8A7E64 : 0xFF2F3A46);
          _u!.quad(pa + na * (0.5 + t.setback) + V3(0, 0, b0 - 4.2), pb + nb * (0.5 + t.setback) + V3(0, 0, b0 - 4.2), pb + nb * (0.5 + t.setback) + V3(0, 0, b0 - 1.4), pa + na * (0.5 + t.setback) + V3(0, 0, b0 - 1.4));
          m.color(0xFF1F2329); // 上の層の床の裏
          m.quad(pa + na * (0.3 + t.setback) + V3(0, 0, b0 - 4.4), pb + nb * (0.3 + t.setback) + V3(0, 0, b0 - 4.4), pb + nb * (0.3 + t.setback + 7) + V3(0, 0, b0 - 4.4), pa + na * (0.3 + t.setback + 7) + V3(0, 0, b0 - 4.4));
          continue;
        }
        if (mainOf && st.oldFence <= 0) {
          // フェンスと外野席の間の床（打球が落ちる所）
          m.color(0xFF2B3038);
          m.quad(pa + V3(0, 0, 0.03), pb + V3(0, 0, 0.03), pb + nb * (0.3 + sb) + V3(0, 0, 0.03), pa + na * (0.3 + sb) + V3(0, 0, 0.03));
        }
        m.color(isOut && !_esc && (mainOf || t.setback <= 0) ? st.wallColor : (t.setback > 0 ? 0xFF1F2937 : (_esc ? 0xFF111418 : 0xFF334155)));
        m.quad(pa + na * (0.3 + sb) + V3(0, 0, fz), pb + nb * (0.3 + sb) + V3(0, 0, fz), pb + nb * (0.3 + sb) + V3(0, 0, b0), pa + na * (0.3 + sb) + V3(0, 0, b0));
      }
    }
  }

  // ───────── バックスクリーン：中堅の外野席の切れ目をふさぐ暗い緑の壁（打者の目の邪魔にならない色）─────────
  void _backscreen(ColorMesh m) {
    if (_esc) return;
    bool covered(double a) => st.stands.any((t) => t.area == '外野' && t.rows > 6 && a >= t.fromAngle && a <= t.toAngle);
    if (covered(0)) return;
    var lo = 0.0, hi = 0.0;
    while (lo > -30 && !covered(lo - 0.5)) {
      lo -= 0.5;
    }
    while (hi < 30 && !covered(hi + 0.5)) {
      hi += 0.5;
    }
    if (lo <= -30 || hi >= 30) return;
    // 高さ：となりの外野席のいちばん上（ビジョンがすぐ後ろにあれば、その下のふちまで）。奥行き：となりの席の後ろまで
    var h = 0.0;
    for (final t in st.stands) {
      if (t.area != '外野' || t.rows <= 6) continue;
      if (!((lo - 1 >= t.fromAngle && lo - 1 <= t.toAngle) || (hi + 1 >= t.fromAngle && hi + 1 <= t.toAngle))) continue;
      h = math.max(h, _frontZ(t) + t.rows * t.rowRise);
    }
    var back = math.max(_standBack(lo - 1) - st.fenceDistance(lo - 1), _standBack(hi + 1) - st.fenceDistance(hi + 1)) - 0.7;
    for (final v in [if (st.showMainVision) st.vision, ...st.moreVisions]) {
      if (v.angle.abs() > 90) continue;
      final line = visionLine(v);
      final angs = [for (final p in line) math.atan2(p.x, p.y) / deg];
      if (angs.reduce(math.max) < lo || angs.reduce(math.min) > hi) continue;
      if (v.behind - 0.8 < back) back = math.max(4.0, v.behind - 0.8);
      if (v.bottom < h && v.behind < 20) h = v.bottom;
    }
    if (h <= 0) return;
    const front = 0.7;
    for (var a = lo; a < hi - 1e-6; a += 0.5) {
      final a1 = math.min(hi, a + 0.5);
      final d0 = st.fenceDistance(a) + front, d1 = st.fenceDistance(a1) + front;
      m.color(0xFF17241C);
      m.quad(polar(a, d0, 0), polar(a1, d1, 0), polar(a1, d1, h), polar(a, d0, h));
      m.color(0xFF243128);
      m.quad(polar(a, d0, h), polar(a1, d1, h), polar(a1, d1 + back, h), polar(a, d0 + back, h));
      m.color(0xFF1B2620);
      m.quad(polar(a, d0 + back, 0), polar(a1, d1 + back, 0), polar(a1, d1 + back, h), polar(a, d0 + back, h));
    }
    // 両端の横の壁（となりの席の切り口をふさぐ）
    m.color(0xFF2A3530);
    for (final a in [lo, hi]) {
      final d = st.fenceDistance(a) + front;
      m.quad(polar(a, d, 0), polar(a, d + back, 0), polar(a, d + back, h), polar(a, d, h));
    }
  }

  int _shade(int c, int row) {
    final k = row.isEven ? 1.0 : 0.88;
    final r = (((c >> 16) & 255) * k).round(), g = (((c >> 8) & 255) * k).round(), b = ((c & 255) * k).round();
    return 0xFF000000 | (r << 16) | (g << 8) | b;
  }

  // ───────── ビジョン（中堅の後ろ・外野席の上・ネット裏）とリボンビジョン ─────────
  void _vision(ColorMesh m) {
    if (st.showMainVision) _visionBoard(m, st.vision);
    for (final v in st.moreVisions) {
      _visionBoard(m, v);
    }
    if (st.ribbons.isEmpty && st.showMainVision && st.vision.ribbon) {
      // （作った球場用）内野スタンドの 2段目の高さに帯
      m.color(0xFF111827);
      for (var a = -135.0; a < -50; a += 2.5) {
        m.quad(polar(a, 52, 9), polar(a + 2.5, 52, 9), polar(a + 2.5, 52, 10.2), polar(a, 52, 10.2));
      }
      for (var a = 50.0; a < 135; a += 2.5) {
        m.quad(polar(a, 52, 9), polar(a + 2.5, 52, 9), polar(a + 2.5, 52, 10.2), polar(a, 52, 10.2));
      }
    }
    // リボンビジョン：光る面の下地（中身は 2D の側で描く）と、上下の細い枠
    for (final strip in ribbonStrips()) {
      for (final (tl, tr, br, bl, inward) in strip) {
        _u!.color(0xFF070B14);
        _u!.quad(bl - inward * 0.02, br - inward * 0.02, tr - inward * 0.02, tl - inward * 0.02);
        m.color(0xFF2A2F37);
        m.quad(tl, tr, tr + const V3(0, 0, 0.12), tl + const V3(0, 0, 0.12));
        m.quad(bl + const V3(0, 0, -0.12), br + const V3(0, 0, -0.12), br, bl);
      }
    }
  }

  /// ビジョンの本塁からの距離（中堅側はフェンスから behind m 後ろ、ネット裏や内野の上は本塁から behind m）
  double visionDist(Vision v, [double? angle]) {
    final a = angle ?? v.angle;
    return v.angle.abs() > 90 ? v.behind : st.fenceDistance(v.arc ? a.clamp(-45.0, 45.0) : a) + v.behind;
  }

  /// ビジョンの画面の下のふちの点（地面の高さ。グラウンドから見て左から右）。平らな板は2点、弧の板はフェンスにそって細かく
  List<V3> visionLine(Vision v) {
    if (!v.arc) {
      final c = polar(v.angle, visionDist(v));
      final side = V3(math.cos(v.angle * deg), -math.sin(v.angle * deg), 0);
      return [c - side * (v.width / 2), c + side * (v.width / 2)];
    }
    // 弧：中央から左右へ、長さが横幅の半分になるまで 0.25° ずつ進む
    List<V3> walk(double dir) {
      final out = <V3>[polar(v.angle, visionDist(v))];
      var len = 0.0, a = v.angle;
      while (len < v.width / 2 && out.length < 2000) {
        a += 0.25 * dir;
        final p = polar(a, visionDist(v, a));
        final step = p.distanceTo(out.last);
        if (len + step >= v.width / 2) {
          out.add(out.last.lerp(p, (v.width / 2 - len) / step));
          break;
        }
        len += step;
        out.add(p);
      }
      return out;
    }

    final left = walk(-1), right = walk(1);
    final all = [...left.reversed, ...right.skip(1)];
    // 区切りは約 2m ごと（遠近の形を保ったまま、描く数を減らす）
    final res = <V3>[all.first];
    var acc = 0.0;
    for (var i = 1; i < all.length; i++) {
      acc += all[i].distanceTo(all[i - 1]);
      if (acc >= 2.0 || i == all.length - 1) {
        res.add(all[i]);
        acc = 0;
      }
    }
    return res;
  }

  /// 大型ビジョンの枠・裏・柱（画面の文字は 2D の側で描く：Play3DScreen の _drawBoard）
  void _visionBoard(ColorMesh m, Vision v) {
    final line = visionLine(v);
    final z0 = v.bottom, z1 = v.bottom + v.height;
    final dome = st.domeHeight > 0 || _esc;
    for (var i = 0; i + 1 < line.length; i++) {
      final a = line[i], b = line[i + 1];
      final inA = -V3(a.x, a.y, 0).unit, inB = -V3(b.x, b.y, 0).unit; // 本塁の方（ネット裏の板はグラウンドの方）
      final ia = v.arc ? inA : -V3(line.first.x + line.last.x, line.first.y + line.last.y, 0).unit, ib = v.arc ? inB : ia;
      // 枠（画面の外へ 0.6m）と裏の箱（厚み 1.2m）
      m.color(v.frame);
      final fa = i == 0 ? (b - a).unit * -0.6 : V3.zero, fb = i + 2 == line.length ? (b - a).unit * 0.6 : V3.zero;
      m.quad(a + fa - ia * 0.3 + V3(0, 0, z0 - 0.6), b + fb - ib * 0.3 + V3(0, 0, z0 - 0.6), b + fb - ib * 0.3 + V3(0, 0, z1 + 0.6), a + fa - ia * 0.3 + V3(0, 0, z1 + 0.6));
      m.color(_mixC(v.frame, 0xFF000000, 0.25));
      m.quad(a + fa - ia * 0.3 + V3(0, 0, z1 + 0.6), b + fb - ib * 0.3 + V3(0, 0, z1 + 0.6), b + fb - ib * 1.5 + V3(0, 0, z1 + 0.6), a + fa - ia * 1.5 + V3(0, 0, z1 + 0.6));
      m.quad(a + fa - ia * 0.3 + V3(0, 0, z0 - 0.6), b + fb - ib * 0.3 + V3(0, 0, z0 - 0.6), b + fb - ib * 1.5 + V3(0, 0, z0 - 0.6), a + fa - ia * 1.5 + V3(0, 0, z0 - 0.6));
      m.quad(a + fa - ia * 1.5 + V3(0, 0, z0 - 0.6), b + fb - ib * 1.5 + V3(0, 0, z0 - 0.6), b + fb - ib * 1.5 + V3(0, 0, z1 + 0.6), a + fa - ia * 1.5 + V3(0, 0, z1 + 0.6));
      // 画面（暗い LED の地）
      m.color(0xFF06122B);
      m.quad(a + ia * 0.05 + V3(0, 0, z0), b + ib * 0.05 + V3(0, 0, z0), b + ib * 0.05 + V3(0, 0, z1), a + ia * 0.05 + V3(0, 0, z1));
    }
    // 屋外の板は2本の柱で立てる（ドームの板は壁・天井から下げる）
    if (!dome && !v.arc) {
      final l = line.first, r = line.last, side = (r - l).unit, back = -(-V3((l.x + r.x) / 2, (l.y + r.y) / 2, 0).unit);
      m.color(_mixC(v.frame, 0xFF6B7280, 0.25));
      for (final p in [l + side * (v.width * 0.18), r - side * (v.width * 0.18)]) {
        m.box(p + back * 0.9 + V3(0, 0, v.bottom / 2), 1.3, 1.3, v.bottom);
      }
      // 裏の骨組み（横の梁）
      m.color(_mixC(v.frame, 0xFF000000, 0.2));
      for (final zz in [v.bottom * 0.35, v.bottom * 0.7]) {
        m.quad(l + back * 0.9 + V3(0, 0, zz), r + back * 0.9 + V3(0, 0, zz), r + back * 0.9 + V3(0, 0, zz + 0.5), l + back * 0.9 + V3(0, 0, zz + 0.5));
      }
    }
  }

  /// 外野のいちばん下の段（その角度の、段の多い席）
  StandTier? _ofMain(double a) {
    StandTier? best;
    for (final t in st.stands) {
      if (t.area != '外野' || t.rows <= 6) continue;
      final from = t.fromAngle <= -45 ? -50.0 : t.fromAngle, to = t.toAngle >= 45 ? 50.0 : t.toAngle;
      if (a < from || a > to) continue;
      if (best == null || t.baseHeight < best.baseHeight) best = t;
    }
    return best;
  }

  /// その段の最前列の高さ（_stands と同じ決め方）
  double _frontZ(StandTier t) {
    if (t.area != '外野') return t.baseHeight + 0.4;
    if (!(t.rows > 6 && t.setback < 1)) return t.baseHeight;
    var fh = 0.0;
    for (var a = -50.0; a <= 50.0; a += 1.25) {
      final from = t.fromAngle <= -45 ? -50.0 : t.fromAngle, to = t.toAngle >= 45 ? 50.0 : t.toAngle;
      if (a < from - 1.25 || a > to + 1.25) continue;
      fh = math.max(fh, st.fenceHeight(a));
    }
    return math.max(t.baseHeight, fh + 0.2);
  }

  /// リボンビジョンの帯：リボンごとに、細い区切り（左上・右上・右下・左下・グラウンドの方の向き）の列（グラウンドから見て左から右）
  List<List<(V3, V3, V3, V3, V3)>> ribbonStrips() {
    final foul = _foulPath();
    final res = <List<(V3, V3, V3, V3, V3)>>[];
    for (final rb in st.ribbons) {
      final line = <(V3, double, double, V3)>[]; // 点・下端・上端・グラウンドの方
      if (rb.place == 'ofFront') {
        // 外野席の最前列の前の壁（フェンスの上に見える所）
        for (var a = rb.fromAngle; a <= rb.toAngle + 1e-6; a += 1.0) {
          final t = _ofMain(a);
          if (t == null) continue;
          final top = _frontZ(t) - 0.12;
          var d = st.fenceDistance(a.clamp(-45.0, 45.0)) + 0.4 + 0.3 - 0.05;
          d += st.oldFence > 0 && t.setback > 0 ? math.max(0.5, st.terraceGap(a)) + 0.35 : t.setback;
          final p = polar(a, d);
          line.add((p, top - rb.height, top, -p.unit));
        }
      } else {
        for (final (p, n) in foul) {
          var ang = math.atan2(p.x, p.y) / deg;
          if (rb.toAngle > 180 && ang < 0) ang += 360;
          if (ang < rb.fromAngle || ang > rb.toAngle) continue;
          StandTier? pick;
          for (final t in st.stands) {
            if (t.area == '外野') continue;
            var a2 = ang;
            if (t.toAngle > 180 && a2 < 0) a2 += 360;
            if (a2 < t.fromAngle || a2 > t.toAngle) continue;
            if (rb.place == 'tier') {
              if (t.setback <= 0) continue;
              if (pick == null || t.baseHeight < pick.baseHeight) pick = t;
            } else {
              if (t.setback > 0) continue;
              if (pick == null || t.rows > pick.rows) pick = t;
            }
          }
          if (pick == null) continue;
          final b0 = pick.baseHeight + 0.4;
          if (rb.place == 'tier') {
            // 上の段の前の帯（_stands の光る帯と同じ所）
            line.add((p + n * (0.3 + pick.setback - 0.05), b0 - math.min(1.1, rb.height), b0, -n));
          } else {
            // 内野席のいちばん後ろの壁（屋根の下）
            final zTop = b0 + pick.rows * pick.rowRise, offTop = 0.3 + pick.rows * pick.rowDepth;
            line.add((p + n * (offTop - 0.06), zTop + 0.6, zTop + 0.6 + rb.height, -n));
          }
        }
      }
      final strip = <(V3, V3, V3, V3, V3)>[];
      for (var i = 0; i + 1 < line.length; i++) {
        final (pa, za0, za1, ia) = line[i];
        final (pb, zb0, zb1, ib) = line[i + 1];
        if (pa.distanceTo(pb) > 12) continue; // 離れた所（段の切れ目）はつながない
        strip.add((V3(pa.x, pa.y, za1), V3(pb.x, pb.y, zb1), V3(pb.x, pb.y, zb0), V3(pa.x, pa.y, za0), (ia + ib).unit));
      }
      res.add(strip);
    }
    return res;
  }

  // ───────── 閉じた屋根（三角屋根）：棟は本塁〜中堅の向き、左翼側 20°・右翼側 17° の勾配。外野側の妻面はガラスの壁 ─────────
  static const _y0 = -70.0, _y1 = 150.0, _xw = 108.0;
  double _roofZ(double x) => st.roofRidge - (x < 0 ? math.tan(20 * deg) * (-x) : math.tan(17 * deg) * x);

  void _closedRoof(ColorMesh w, ColorMesh c, ColorMesh u) {
    // 天井（暗い面）
    for (var y = _y0; y < _y1; y += 11) {
      final yb = math.min(_y1, y + 11);
      for (var x = -_xw; x < _xw - 0.1; x += 12) {
        final xb = math.min(_xw, x + 12);
        final mid = x < 0 && xb > 0;
        c.color(0xFF16191D);
        if (mid) {
          c.quad(V3(x, y, _roofZ(x)), V3(0, y, _roofZ(0)), V3(0, yb, _roofZ(0)), V3(x, yb, _roofZ(x)));
          c.quad(V3(0, y, _roofZ(0)), V3(xb, y, _roofZ(xb)), V3(xb, yb, _roofZ(xb)), V3(0, yb, _roofZ(0)));
        } else {
          c.quad(V3(x, y, _roofZ(x)), V3(xb, y, _roofZ(xb)), V3(xb, yb, _roofZ(xb)), V3(x, yb, _roofZ(x)));
        }
      }
    }
    // 鉄骨：棟の向きの梁（11m ごと）と、横に渡した大きなトラス（11m ごと、深さ 3m）
    for (var x = -99.0; x <= 99; x += 11) {
      c.color(0xFF3A3F47);
      final z = _roofZ(x) - 1.2;
      c.quad(V3(x - 0.45, _y0, z), V3(x + 0.45, _y0, z), V3(x + 0.45, _y1, z), V3(x - 0.45, _y1, z));
    }
    for (var y = _y0 + 11; y < _y1; y += 11) {
      for (final seg in [(-_xw, 0.0), (0.0, _xw)]) {
        final (xa, xb) = seg;
        u.color(0xFF2B3037); // 縦の面（トラスの腹）
        u.quad(V3(xa, y, _roofZ(xa) - 0.3), V3(xb, y, _roofZ(xb) - 0.3), V3(xb, y, _roofZ(xb) - 3.0), V3(xa, y, _roofZ(xa) - 3.0));
        c.color(0xFF464C55); // 下の弦材
        c.quad(V3(xa, y - 0.4, _roofZ(xa) - 3.0), V3(xb, y - 0.4, _roofZ(xb) - 3.0), V3(xb, y + 0.4, _roofZ(xb) - 3.0), V3(xa, y + 0.4, _roofZ(xa) - 3.0));
        // 斜めの材（トラスの腹の筋）
        u.color(0xFF4A505A);
        for (var x = xa; x < xb - 0.1; x += 5.5) {
          final x2 = x + 5.5;
          u.quad(V3(x, y - 0.05, _roofZ(x) - 0.3), V3(x + 0.5, y - 0.05, _roofZ(x + 0.5) - 0.3), V3(x2 + 0.5, y - 0.05, _roofZ(x2 + 0.5) - 3.0), V3(x2, y - 0.05, _roofZ(x2) - 3.0));
        }
      }
    }
    // 照明の列（白い点が並ぶ帯）
    c.color(0xFFFFFCF0);
    for (final x in [-62.0, -40.0, -20.0, 20.0, 40.0, 62.0]) {
      for (var y = -45.0; y < 135; y += 2.6) {
        final z = _roofZ(x) - 3.2;
        c.quad(V3(x - 0.8, y, z), V3(x + 0.8, y, z), V3(x + 0.8, y + 1.2, z), V3(x - 0.8, y + 1.2, z));
      }
    }
    // 横の壁（軒の下まで）と本塁の後ろの壁
    w.color(0xFF1D2126);
    for (final x in [-_xw, _xw]) {
      w.quad(V3(x, _y0, 0), V3(x, _y1, 0), V3(x, _y1, _roofZ(x)), V3(x, _y0, _roofZ(x)));
    }
    w.color(0xFF181B20);
    w.quad(V3(-_xw, _y0, 0), V3(0, _y0, 0), V3(0, _y0, _roofZ(0)), V3(-_xw, _y0, _roofZ(-_xw)));
    w.quad(V3(0, _y0, 0), V3(_xw, _y0, 0), V3(_xw, _y0, _roofZ(_xw)), V3(0, _y0, _roofZ(0)));
    // 外野の裏の床（ガラスの壁の手前）と、中堅の後ろの2階建てのデッキ
    w.color(0xFF23272D);
    w.quad(V3(-_xw, 60, -0.01), V3(_xw, 60, -0.01), V3(_xw, _y1, -0.01), V3(-_xw, _y1, -0.01));
    w.color(0xFF1C2026);
    w.box(const V3(0, 139, 3.5), 64, 22, 7);
    // デッキの窓：1枚ずつ（明かりのついた窓と暗い窓）
    for (final z in [1.2, 4.4]) {
      for (var x = -30.0; x < 30; x += 3.2) {
        u.color(((x * 7 + z * 3).round() % 3 == 0) ? 0xFF2E3640 : 0xFF6F6553);
        u.quad(V3(x + 0.2, 127.9, z), V3(x + 3.0, 127.9, z), V3(x + 3.0, 127.9, z + 1.7), V3(x + 0.2, 127.9, z + 1.7));
      }
    }
    // ガラスの壁（外の光で明るい。上ほど明るい）と太い格子
    const cols = 24, bands = 8;
    for (var i = 0; i < cols; i++) {
      final xa = -_xw + 2 * _xw * i / cols, xb = -_xw + 2 * _xw * (i + 1) / cols;
      final xm = (xa < 0 && xb > 0) ? 0.0 : null;
      void col(double x0, double x1) {
        final t0 = _roofZ(x0), t1 = _roofZ(x1);
        for (var k = 0; k < bands; k++) {
          final f0 = k / bands, f1 = (k + 1) / bands;
          u.color(_mixC(0xFFAFC4D3, 0xFFE4EDF4, (k + 0.5) / bands));
          u.quad(V3(x0, _y1, t0 * f0), V3(x1, _y1, t1 * f0), V3(x1, _y1, t1 * f1), V3(x0, _y1, t0 * f1));
        }
      }

      if (xm != null) {
        col(xa, 0);
        col(0, xb);
      } else {
        col(xa, xb);
      }
    }
    u.color(0xFF2A2F36);
    for (var i = 0; i <= cols; i++) {
      final x = -_xw + 2 * _xw * i / cols;
      final wd = i % 4 == 0 ? 0.9 : 0.45;
      u.quad(V3(x - wd, _y1 - 0.3, 0), V3(x + wd, _y1 - 0.3, 0), V3(x + wd, _y1 - 0.3, _roofZ(x + wd)), V3(x - wd, _y1 - 0.3, _roofZ(x - wd)));
    }
    u.quad(V3(-0.9, _y1 - 0.3, 0), V3(0.9, _y1 - 0.3, 0), V3(0.9, _y1 - 0.3, _roofZ(0.9)), V3(-0.9, _y1 - 0.3, _roofZ(-0.9)));
    for (var z = 5.0; z < st.roofRidge; z += 5) {
      final wd = (z % 15 == 0) ? 0.55 : 0.22;
      // その高さでガラスのある範囲（屋根の線の内側）
      final xl = -(st.roofRidge - z) / math.tan(20 * deg), xr = (st.roofRidge - z) / math.tan(17 * deg);
      final x0 = math.max(-_xw, xl), x1 = math.min(_xw, xr);
      if (x1 <= x0) continue;
      u.quad(V3(x0, _y1 - 0.35, z - wd), V3(x1, _y1 - 0.35, z - wd), V3(x1, _y1 - 0.35, z + wd), V3(x0, _y1 - 0.35, z + wd));
    }
    // 屋根のふち（ガラスの上の太い枠）
    u.color(0xFF111418);
    for (final seg in [(-_xw, 0.0), (0.0, _xw)]) {
      final (xa, xb) = seg;
      u.quad(V3(xa, _y1 - 0.4, _roofZ(xa) - 2.2), V3(xb, _y1 - 0.4, _roofZ(xb) - 2.2), V3(xb, _y1 - 0.4, _roofZ(xb) + 0.2), V3(xa, _y1 - 0.4, _roofZ(xa) + 0.2));
    }
  }

  // ───────── ドーム：球場全体をおおう丸い天井（膜の継ぎ目の放射状の骨と、輪の照明）。横が開いたドームは屋根と客席の間から木々が見える ─────────
  void _dome(ColorMesh w, ColorMesh c, ColorMesh u) {
    const cy = 48.0;
    const na = 72;
    // 天井のふちは、いちばん高い客席・ビジョンより上（横が開いたドームは客席との間を大きくあける）
    var standTop = 0.0;
    for (final t in st.stands) {
      standTop = math.max(standTop, t.baseHeight + t.rows * t.rowRise);
    }
    var boardTop = 0.0;
    for (final v in [if (st.showMainVision) st.vision, ...st.moreVisions]) {
      boardTop = math.max(boardTop, v.bottom + v.height + 1.5);
    }
    final open = st.domeOpenSides;
    final edge = math.max(22.0, math.max(standTop + (open ? 9 : 4), boardTop));
    final top = math.max(st.domeHeight, edge + 12);
    // 屋根のふちの形：角度ごとに、スタンドのいちばん後ろ（とビジョン）の少し外
    final rEdge = List<double>.filled(na, 0);
    void put(V3 p, double margin) {
      final th = math.atan2(p.x, p.y - cy);
      final j = ((th / (2 * math.pi) * na).round()) % na;
      final r = math.sqrt(p.x * p.x + (p.y - cy) * (p.y - cy)) + margin;
      for (final k in [j - 1, j, j + 1]) {
        final kk = (k + na) % na;
        rEdge[kk] = math.max(rEdge[kk], r);
      }
    }

    for (final p in _backPoints()) {
      put(p, open ? 1.5 : 2.5);
    }
    for (final v in [if (st.showMainVision) st.vision, ...st.moreVisions]) {
      for (final p in visionLine(v)) {
        put(p, 2.5);
      }
    }
    for (var j = 0; j < na; j++) {
      if (rEdge[j] == 0) rEdge[j] = 100;
    }
    // なめらかに（となりと平均）
    final sm = [for (var j = 0; j < na; j++) math.max(rEdge[j], (rEdge[(j + na - 1) % na] + 2 * rEdge[j] + rEdge[(j + 1) % na]) / 4)];
    double rAt(double th) {
      var f = th / (2 * math.pi) * na;
      f = f % na;
      if (f < 0) f += na;
      final j0 = f.floor() % na, j1 = (j0 + 1) % na, t = f - f.floor();
      return sm[j0] + (sm[j1] - sm[j0]) * t;
    }

    double z(double f) => edge + (top - edge) * (1 - f * f);
    // f：中心からふちまでの割合（0〜1）、a：中心から見た角度
    V3 pol(double f, double a, [double dz = 0]) {
      final r = rAt(a) * f;
      return V3(r * math.sin(a), cy + r * math.cos(a), z(f) + dz);
    }

    V3 at(double x, double y, [double dz = 0]) {
      final th = math.atan2(x, y - cy);
      final f = math.min(1.0, math.sqrt(x * x + (y - cy) * (y - cy)) / rAt(th));
      return pol(f, th, dz);
    }

    // 曲線にそった細い帯（骨・格子・ケーブル）
    void strip(List<V3> pts, double wd, int col) {
      c.color(col);
      for (var i = 0; i + 1 < pts.length; i++) {
        final d = pts[i + 1] - pts[i];
        if (d.length < 1e-6) continue;
        final n = d.cross(V3.ez).unit * (wd / 2);
        c.quad(pts[i] - n, pts[i] + n, pts[i + 1] + n, pts[i + 1] - n);
      }
    }

    const nr = 12;
    final style = st.domeStyle;
    final dark = style != 'membrane';
    // 横が開いたドーム（狭山）：中央は白い膜、客席の上は金属の輪の屋根（ドーナツ形）
    const ringF = 0.74;
    // 面
    for (var i = 0; i < nr; i++) {
      final f0 = i / nr, f1 = (i + 1) / nr;
      for (var j = 0; j < na; j++) {
        final a0 = 2 * math.pi * j / na, a1 = 2 * math.pi * (j + 1) / na;
        int col;
        if (style == 'ring') {
          // 内側の大きな円盤は明るい灰色、外側は濃い鉄骨の輪
          col = f1 <= 0.44 ? _mixC(st.domeColor, 0xFFFFFFFF, 0.1 - 0.1 * i / nr) : 0xFF2A2E35;
        } else if (dark) {
          col = _mixC(st.domeColor, 0xFF1A1D22, 0.1 + 0.35 * i / nr);
        } else if (open && f0 >= ringF - 1e-6) {
          col = _mixC(0xFF8E959E, 0xFF5E656E, (f0 - ringF) / (1 - ringF));
        } else {
          col = _mixC(st.domeColor, 0xFF9AA2AC, 0.05 + 0.3 * i / nr); // 白い膜：ふちほど影
        }
        c.color(col);
        c.quad(pol(f0, a0), pol(f1, a0), pol(f1, a1), pol(f0, a1));
      }
    }
    if (style == 'membrane') {
      // ケーブルの格子（平面で見て四角。東京は斜め 45°、狭山は縦横）
      final rot = st.id == 'tokyo' ? math.pi / 4 : 0.0;
      final cr = math.cos(rot), sr = math.sin(rot);
      const rd = 140.0;
      for (var k = -rd; k <= rd; k += 10) {
        for (final dir in [0, 1]) {
          final pts = <V3>[];
          for (var t = -rd; t <= rd; t += 4) {
            final lx = dir == 0 ? k : t, ly = dir == 0 ? t : k;
            final x = lx * cr - ly * sr, y = lx * sr + ly * cr;
            final th = math.atan2(x, y);
            final lim = rAt(th) * (open ? ringF : 1.0);
            if (x * x + y * y > lim * lim * 0.98) {
              if (pts.length > 1) strip(pts, 0.45, _mixC(st.domeColor, 0xFF6B7280, 0.45));
              pts.clear();
              continue;
            }
            pts.add(at(x, cy + y, -0.2));
          }
          if (pts.length > 1) strip(pts, 0.45, _mixC(st.domeColor, 0xFF6B7280, 0.45));
        }
      }
      if (open) {
        // 金属の輪の屋根：放射状の骨と、内側のふち（膜との境）の太い輪
        for (var j = 0; j < na; j += 2) {
          final a0 = 2 * math.pi * j / na;
          strip([for (var i = 0; i <= 6; i++) pol(ringF + (1 - ringF) * i / 6, a0, -0.4)], 0.9, 0xFF4A5059);
        }
        strip([for (var j = 0; j <= na; j++) pol(ringF, 2 * math.pi * j / na, -0.5)], 2.0, 0xFFD9DEE3);
        strip([for (var j = 0; j <= na; j++) pol(0.995, 2 * math.pi * j / na, -0.5)], 1.6, 0xFFE5E7EB);
      }
    } else if (style == 'lattice') {
      // 鉄骨の格子：放射状の骨・同心の輪・その間の斜めの筋（三角形）
      const nRad = 36, nRing = 9;
      final col = _mixC(st.domeColor, 0xFF9AA3AD, 0.35);
      for (var j = 0; j < nRad; j++) {
        final a0 = 2 * math.pi * j / nRad;
        strip([for (var i = 0; i <= nRing; i++) pol(i / nRing, a0, -0.3)], 0.7, col);
      }
      for (var i = 1; i <= nRing; i++) {
        strip([for (var j = 0; j <= na; j++) pol(i / nRing, 2 * math.pi * j / na, -0.3)], 0.6, col);
      }
      for (var i = 0; i < nRing; i++) {
        for (var j = 0; j < nRad; j++) {
          final a0 = 2 * math.pi * j / nRad, a1 = 2 * math.pi * (j + 1) / nRad;
          strip([pol(i / nRing, a0, -0.35), pol((i + 1) / nRing, a1, -0.35)], 0.35, col);
          strip([pol(i / nRing, a1, -0.35), pol((i + 1) / nRing, a0, -0.35)], 0.35, col);
        }
      }
    } else {
      // ring：内側の円盤の白いふちと、外側の輪の放射状の鉄骨
      strip([for (var j = 0; j <= na; j++) pol(0.44, 2 * math.pi * j / na, -0.3)], 2.2, 0xFFF1F5F9);
      for (var j = 0; j < 48; j++) {
        final a0 = 2 * math.pi * j / 48;
        strip([for (var i = 0; i <= 8; i++) pol(0.44 + 0.56 * i / 8, a0, -0.4)], 0.8, 0xFF5B6270);
      }
      for (final rr in [0.6, 0.75, 0.9]) {
        strip([for (var j = 0; j <= na; j++) pol(rr, 2 * math.pi * j / na, -0.4)], 0.6, 0xFF5B6270);
      }
    }
    // 照明の輪（白い点）
    c.color(0xFFFFFCF0);
    for (final rr in style == 'ring' ? [0.5, 0.66, 0.82] : (open ? [0.62, 0.8, 0.92] : [0.62, 0.9])) {
      for (var j = 0; j < 96; j++) {
        final a = 2 * math.pi * j / 96;
        final q = pol(rr, a, -0.8);
        final t = V3(math.cos(a), -math.sin(a), 0) * 0.9, rad = V3(math.sin(a), math.cos(a), 0) * 0.5;
        c.quad(q - t - rad, q + t - rad, q + t + rad, q - t + rad);
      }
    }
    // 天井のふちから地面まで
    for (var j = 0; j < na; j++) {
      final a0 = 2 * math.pi * j / na, a1 = 2 * math.pi * (j + 1) / na;
      V3 p(double a, double zz) {
        final r = rAt(a);
        return V3(r * math.sin(a), cy + r * math.cos(a), zz);
      }

      if (open) {
        // 屋根と客席の間は壁がなく、外の森が見える。屋根はスタンドの後ろの柱（白い鉄骨）で支える
        w.color(0xFF9AA1AA); // 屋根のふちの鼻先（厚み）
        w.quad(p(a0, edge - 1.8), p(a1, edge - 1.8), p(a1, edge), p(a0, edge));
        if (j % 3 == 0) {
          final q = p(a0, 0), inn = -V3(math.sin(a0), math.cos(a0), 0);
          w.color(0xFFE2E6EA);
          w.box(q + V3(0, 0, edge / 2), 1.3, 1.3, edge);
          // 柱の上の斜めの支え（屋根の内側へ）
          w.color(0xFFCBD2D9);
          final b0 = q + V3(0, 0, edge - 7), b1 = q + inn * 6 + V3(0, 0, edge - 0.6);
          final sd = V3(-inn.y, inn.x, 0) * 0.35;
          w.quad(b0 - sd, b0 + sd, b1 + sd, b1 - sd);
        }
      } else {
        // 客席の上の壁：上の通路の明かりと、広告の帯（光る）
        w.color(0xFF3E444D);
        w.quad(p(a0, 0), p(a1, 0), p(a1, edge), p(a0, edge));
        final inn = -V3(math.sin((a0 + a1) / 2), math.cos((a0 + a1) / 2), 0) * 0.2;
        u.color(j.isEven ? 0xFF1E293B : const [0xFFE11D48, 0xFF0EA5E9, 0xFFF4F4F5, 0xFF1D4ED8, 0xFFFACC15][(j ~/ 2) % 5]);
        u.quad(p(a0, edge - 4.2) + inn, p(a1, edge - 4.2) + inn, p(a1, edge - 1.6) + inn, p(a0, edge - 1.6) + inn);
        u.color(0xFF8A7E64);
        u.quad(p(a0, edge - 7.4) + inn, p(a1, edge - 7.4) + inn, p(a1, edge - 5.4) + inn, p(a0, edge - 5.4) + inn);
      }
    }
  }

  // ───────── 左翼の奥のタワー（木目の外壁とガラス、5階建て・ホテルと温泉） ─────────
  void _tower(ColorMesh m, ColorMesh u, Building b) {
    final c = polar(b.angle, b.distance);
    final face = -c.unit, side = V3(-face.y, face.x, 0);
    final yaw = math.atan2(side.y, side.x);
    m.color(0xFF2B2F35);
    m.box(c + V3(0, 0, b.height / 2), b.width, b.depth, b.height, yaw: yaw);
    final front = c + face * (b.depth / 2 + 0.05);
    const floors = 5;
    final fh = b.height / floors;
    for (var f = 0; f < floors; f++) {
      final z0 = f * fh;
      // 窓（上の2階はホテルの暖かい明かり）
      u.color(f >= 3 ? 0xFFF1D9A6 : 0xFF9DB2C2);
      u.quad(front - side * (b.width * 0.47) + V3(0, 0, z0 + 0.4), front + side * (b.width * 0.47) + V3(0, 0, z0 + 0.4), front + side * (b.width * 0.47) + V3(0, 0, z0 + fh * 0.62), front - side * (b.width * 0.47) + V3(0, 0, z0 + fh * 0.62));
      // 木目の帯（床の厚み）
      m.color(b.color);
      m.quad(front + face * 0.1 - side * (b.width / 2) + V3(0, 0, z0 + fh * 0.62), front + face * 0.1 + side * (b.width / 2) + V3(0, 0, z0 + fh * 0.62), front + face * 0.1 + side * (b.width / 2) + V3(0, 0, z0 + fh), front + face * 0.1 - side * (b.width / 2) + V3(0, 0, z0 + fh));
      // バルコニーの手すり
      m.color(0xFF1F2328);
      m.quad(front + face * 0.9 - side * (b.width / 2) + V3(0, 0, z0 + fh * 0.62), front + face * 0.9 + side * (b.width / 2) + V3(0, 0, z0 + fh * 0.62), front + face * 0.9 + side * (b.width / 2) + V3(0, 0, z0 + fh * 0.62 + 1.0), front + face * 0.9 - side * (b.width / 2) + V3(0, 0, z0 + fh * 0.62 + 1.0));
    }
    // 縦の木のルーバー
    m.color(_mixC(b.color, 0xFFFFFFFF, 0.12));
    for (var k = -b.width / 2 + 2; k < b.width / 2; k += 3.5) {
      m.box(front + side * k + face * 0.4 + V3(0, 0, b.height / 2), 0.45, 0.8, b.height, yaw: yaw);
    }
  }

  // ───────── 外野の奥の建物：窓の並び ─────────
  void _building(ColorMesh m, Building b) {
    final c = polar(b.angle, b.distance);
    final face = -c.unit, side = V3(-face.y, face.x, 0);
    final front = c + face * (b.depth / 2);
    m.color(b.color);
    m.box(c + V3(0, 0, b.height / 2), b.width, b.depth, b.height, yaw: math.atan2(side.y, side.x));
    // 窓（階ごとに明るい帯）
    final floors = (b.height / 4.2).floor();
    for (var fl = 0; fl < floors; fl++) {
      final z0 = 1.6 + fl * 4.2, z1 = z0 + 1.8;
      m.color(0xFFF3E7C9);
      m.quad(front + face * 0.05 - side * (b.width * 0.45) + V3(0, 0, z0), front + face * 0.05 + side * (b.width * 0.45) + V3(0, 0, z0), front + face * 0.05 + side * (b.width * 0.45) + V3(0, 0, z1), front + face * 0.05 - side * (b.width * 0.45) + V3(0, 0, z1));
    }
  }

  // ───────── 外野フェンスのすぐ外のブルペン（見える所） ─────────
  void _bullpens(ColorMesh m) {
    if (_esc) {
      // 両翼ポール際：外野席をくり抜いたブルペン（人工芝・黒い壁・木のベンチ）。本塁の方から見えるように、フェンスの外に
      for (final sg in [-1.0, 1.0]) {
        final a = sg * 40.5;
        final d = st.fenceDistance(a);
        final c = polar(a, d + 4.0, 0.02);
        final face = -c.unit, side = V3(-face.y, face.x, 0);
        m.color(0xFF3E7F3A);
        m.quad(c - side * 8 - face * 3.6, c + side * 8 - face * 3.6, c + side * 8 + face * 3.6, c - side * 8 + face * 3.6);
        // 投手板と本塁の白い印（2組）
        m.color(0xFFF5F5F5);
        for (final k in [-3.0, 3.0]) {
          m.box(c + side * k + face * 2.6 + V3(0, 0, 0.02), 0.6, 0.15, 0.03, yaw: math.atan2(side.y, side.x));
          m.box(c + side * k - face * 2.6 + V3(0, 0, 0.02), 0.43, 0.43, 0.03, yaw: math.atan2(side.y, side.x));
        }
        // 奥の黒い壁（上は一段高い客席）と、架空の広告
        final back = c - face * 3.6;
        m.color(0xFF101318);
        m.quad(back - side * 8, back + side * 8, back + side * 8 + const V3(0, 0, 4.5), back - side * 8 + const V3(0, 0, 4.5));
        m.color(0xFF16A34A);
        m.quad(back + face * 0.05 - side * 3 + const V3(0, 0, 2.6), back + face * 0.05 + side * 3 + const V3(0, 0, 2.6), back + face * 0.05 + side * 3 + const V3(0, 0, 3.4), back + face * 0.05 - side * 3 + const V3(0, 0, 3.4));
        // 木のベンチ（壁ぞい）
        m.color(0xFFB98552);
        m.box(back + face * 0.6 + const V3(0, 0, 0.25), 0.7, 14, 0.45, yaw: math.atan2(face.y, face.x));
        // 横の黒い壁
        m.color(0xFF15181C);
        for (final e in [-8.0, 8.0]) {
          final p = c + side * e;
          m.quad(p - face * 3.6, p + face * 3.6, p + face * 3.6 + const V3(0, 0, 4.5), p - face * 3.6 + const V3(0, 0, 4.5));
        }
      }
      return;
    }
    for (final sg in [-1.0, 1.0]) {
      final a = sg * 36.0;
      final d = st.fenceDistance(a) + 1.0;
      final c = polar(a, d + 4.5, 0.01);
      final face = -c.unit, side = V3(-face.y, face.x, 0);
      m.color(0xFF4A9744);
      m.quad(c - side * 13 - face * 4.5, c + side * 13 - face * 4.5, c + side * 13 + face * 4.5, c - side * 13 + face * 4.5);
      for (final k in [-6.0, 0.0, 6.0]) {
        m.color(0xFFC9935F);
        _disc(m, c + side * k + V3(0, 0, 0.01), 1.6, 20);
        m.color(0xFFF5F5F5);
        m.box(c + side * k + V3(0, 0, 0.05), 0.6, 0.15, 0.04);
      }
    }
  }

  // ───────── ポール・照明 ─────────
  void _poles(ColorMesh m) {
    m.color(0xFFFACC15);
    for (final a in [-45.0, 45.0]) {
      final p = polar(a, st.fenceDistance(a) + 0.2);
      m.box(p + const V3(0, 0, 13), 0.35, 0.35, 26);
    }
  }

  // ───────── 照明塔：鉄骨の格子（甲子園・宮城）か、柱の上に四角いライト（横浜・神宮・広島）。塔に広告を縦に積む ─────────
  void _lightTowers(ColorMesh m, ColorMesh u) {
    if (_esc || st.domeHeight > 0) return; // 屋根の中：照明は天井
    for (final l in st.lights) {
      // 塔はスタンドの後ろのふちの上に立てる（スタンドの外の地面に立たないように）
      final p = polar(l.angle, math.max(l.distance * 0.0, _standBack(l.angle) + 1.5));
      final face = -V3(p.x, p.y, 0).unit, side = V3(-face.y, face.x, 0);
      final yaw = math.atan2(side.y, side.x);
      if (l.style == 'lattice') {
        // 4本の脚と、斜めの筋かい（上ほど細い）
        m.color(0xFF8B939E);
        for (final sx in [-1.0, 1.0]) {
          for (final sy in [-1.0, 1.0]) {
            final b = p + side * (sx * 2.2) + face * (sy * 1.6), t = p + side * (sx * 1.0) + face * (sy * 0.8) + V3(0, 0, l.height - 4);
            final d = (t - b).unit * 0.0;
            m.quad(b - side * 0.15 + d, b + side * 0.15, t + side * 0.15, t - side * 0.15);
          }
        }
        m.color(0xFF6B7380);
        for (var z = 3.0; z < l.height - 5; z += 4) {
          final w = 2.2 - 1.2 * z / l.height;
          m.quad(p - side * w + V3(0, 0, z), p + side * w + V3(0, 0, z + 3.6), p + side * w + V3(0, 0, z + 3.9), p - side * w + V3(0, 0, z + 0.3));
          m.quad(p + side * w + V3(0, 0, z), p - side * w + V3(0, 0, z + 3.6), p - side * w + V3(0, 0, z + 3.9), p + side * w + V3(0, 0, z + 0.3));
        }
      } else {
        // 柱
        m.color(0xFF9CA3AF);
        m.box(p + V3(0, 0, (l.height - 3) / 2), 1.1, 1.1, l.height - 3);
      }
      // ライトの板（本塁の方を向き、少し下を向く）
      final top = p + V3(0, 0, l.height - 3);
      m.color(0xFF4B5563);
      m.quad(top - side * 6 + face * -0.3 + V3(0, 0, -1), top + side * 6 + face * -0.3 + V3(0, 0, -1), top + side * 6 + face * -0.6 + V3(0, 0, 5), top - side * 6 + face * -0.6 + V3(0, 0, 5));
      u.color(0xFFFFFBEB);
      for (var r = 0; r < 4; r++) {
        for (var c = 0; c < 8; c++) {
          final q = top - side * 5.4 + side * (c * 1.55) + face * (-0.25) + V3(0, 0, -0.5 + r * 1.35);
          u.quad(q, q + side * 1.2, q + side * 1.2 + V3(0, 0, 1.0), q + V3(0, 0, 1.0));
        }
      }
      // 塔の広告（縦に積む）
      for (var k = 0; k < l.ads; k++) {
        final z = 8.0 + k * 4.2;
        u.color(_adColor(k + l.angle.round()));
        final q = p + face * 2.0 + V3(0, 0, z);
        u.quad(q - side * 3.6, q + side * 3.6, q + side * 3.6 + V3(0, 0, 3.2), q - side * 3.6 + V3(0, 0, 3.2));
        u.color(0xFFF8FAFC);
        u.quad(q - side * 2.4 + face * 0.05 + V3(0, 0, 1.1), q + side * 2.4 + face * 0.05 + V3(0, 0, 1.1), q + side * 2.4 + face * 0.05 + V3(0, 0, 2.1), q - side * 2.4 + face * 0.05 + V3(0, 0, 2.1));
      }
      m.box(p + V3(0, 0, 0.5), 0.1, 0.1, 0.1, yaw: yaw);
    }
  }

  /// スタンドのいちばん後ろのふちの点（段ごと・角度ごと）。屋根のふち・照明塔・外の木の置き場所に使う
  List<V3>? _backCache;
  List<V3> _backPoints() {
    final cached = _backCache;
    if (cached != null) return cached;
    final foul = _foulPath();
    final outfield = <(V3, V3)>[];
    for (var a = -50.0; a <= 50.0; a += 1.25) {
      final p = polar(a, st.fenceDistance(a.clamp(-45.0, 45.0)) + 0.4);
      outfield.add((p, p.unit));
    }
    final res = <V3>[];
    for (final t in st.stands) {
      final isOut = t.area == '外野';
      final base = isOut ? outfield : foul;
      final fromA = isOut && t.fromAngle <= -45 ? -50.0 : t.fromAngle, toA = isOut && t.toAngle >= 45 ? 50.0 : t.toAngle;
      for (final (p, n) in base) {
        var ang = math.atan2(p.x, p.y) / deg;
        if (toA > 180 && ang < 0) ang += 360;
        if (ang < fromA || ang > toA) continue;
        var sb = t.setback;
        if (isOut && st.oldFence > 0 && t.setback > 0 && t.baseHeight < 10) sb = math.max(0.5, st.terraceGap(ang.clamp(-45.0, 45.0))) + 0.35;
        res.add(p + n * (0.3 + sb + t.rows * t.rowDepth + 0.4));
      }
    }
    return _backCache = res;
  }

  /// スタンド・ビジョンのいちばん外（外の景色はこれより外に置く）
  double _outerEdge(double ang) {
    var d = _standBack(ang);
    for (final v in [if (st.showMainVision) st.vision, ...st.moreVisions]) {
      final line = visionLine(v);
      final angs = [for (final p in line) math.atan2(p.x, p.y) / deg];
      final lo = angs.reduce(math.min) - 3, hi = angs.reduce(math.max) + 3;
      if (ang >= lo && ang <= hi) {
        for (final p in line) {
          d = math.max(d, p.length + 3);
        }
      }
    }
    return d;
  }

  /// その角度（本塁から見た向き）でのスタンドの後ろのふちまでの本塁からの距離（いちばん後ろの段）
  double _standBack(double ang) {
    var best = 0.0;
    for (final p in _backPoints()) {
      var d = (math.atan2(p.x, p.y) / deg - ang) % 360;
      if (d > 180) d -= 360;
      if (d.abs() <= 2.0) best = math.max(best, p.length);
    }
    return best == 0 ? 130 : best;
  }

  // ───────── 外野席の上の広告の看板（甲子園・宮城）─────────
  void _adRing(ColorMesh m, ColorMesh u) {
    for (final t in st.stands.where((x) => x.area == '外野')) {
      final zTop = t.baseHeight + t.rows * t.rowRise;
      for (var a = t.fromAngle; a < t.toAngle - 1; a += 4.5) {
        final d0 = st.fenceDistance(a) + 0.7 + t.setback + t.rows * t.rowDepth, d1 = st.fenceDistance(a + 4.0) + 0.7 + t.setback + t.rows * t.rowDepth;
        final p0 = polar(a, d0, zTop + 3.4), p1 = polar(a + 4.0, d1, zTop + 3.4);
        m.color(0xFF2B2F35);
        m.quad(p0 + const V3(0, 0, -0.4), p1 + const V3(0, 0, -0.4), p1 + const V3(0, 0, 4.4), p0 + const V3(0, 0, 4.4));
        u.color(_adColor((a * 3).round()));
        final inn = -V3(p0.x, p0.y, 0).unit * 0.1;
        u.quad(p0 + inn, p1 + inn, p1 + inn + const V3(0, 0, 4.0), p0 + inn + const V3(0, 0, 4.0));
        u.color(0xFFF8FAFC);
        final c0 = p0.lerp(p1, 0.15) + inn * 2, c1 = p0.lerp(p1, 0.85) + inn * 2;
        u.quad(c0 + const V3(0, 0, 1.4), c1 + const V3(0, 0, 1.4), c1 + const V3(0, 0, 2.6), c0 + const V3(0, 0, 2.6));
      }
    }
  }

  // ───────── 球場の外の景色：観覧車（宮城）・赤白の塔（横浜）・ビル・山・木々・海 ─────────
  void _scenery(ColorMesh m, ColorMesh u) {
    final rnd = math.Random(st.id.hashCode);
    for (final sc in st.scenery) {
      switch (sc) {
        case 'ferris':
          // 左翼席の奥の観覧車（直径 36m）：前後2枚の白い輪・スポーク・輪の間の筋かい・16個のゴンドラ・A の字の脚4本・夜の明かり
          final c = polar(-38, _standBack(-38) + 22, 23);
          final face = -V3(c.x, c.y, 0).unit, side = V3(-face.y, face.x, 0);
          const n = 16, rr = 18.0, gap = 1.6;
          V3 rim(double a, double r, double dz) => c + side * (r * math.cos(a)) + V3(0, 0, r * math.sin(a)) + face * dz;
          for (final dz in [-gap, gap]) {
            for (var i = 0; i < 48; i++) {
              final a0 = 2 * math.pi * i / 48, a1 = 2 * math.pi * (i + 1) / 48;
              m.color(0xFFF1F5F9);
              m.quad(rim(a0, rr, dz), rim(a1, rr, dz), rim(a1, rr - 0.7, dz), rim(a0, rr - 0.7, dz));
              m.color(0xFFD1D5DB);
              m.quad(rim(a0, rr * 0.55, dz), rim(a1, rr * 0.55, dz), rim(a1, rr * 0.55 - 0.35, dz), rim(a0, rr * 0.55 - 0.35, dz));
              if (i.isEven) {
                u.color(i % 4 == 0 ? 0xFFFFE08A : 0xFF9AD8FF); // 輪の明かり
                final q = rim(a0, rr + 0.15, dz + (dz < 0 ? -0.05 : 0.05));
                u.quad(q - side * 0.25, q + side * 0.25, q + side * 0.25 + V3(0, 0, 0.5), q - side * 0.25 + V3(0, 0, 0.5));
              }
            }
          }
          for (var i = 0; i < n; i++) {
            final a = 2 * math.pi * i / n;
            for (final dz in [-gap, gap]) {
              // スポーク（中心から外の輪へ、少しずらして2本）
              m.color(0xFFE5E7EB);
              final h = c + face * (dz * 0.4);
              final o = rim(a + 0.05, rr - 0.4, dz), o2 = rim(a - 0.05, rr - 0.4, dz);
              final nn = (o - h).cross(face).unit * 0.12;
              m.quad(h - nn, h + nn, o + nn, o - nn);
              m.quad(h - nn, h + nn, o2 + nn, o2 - nn);
            }
            // 前後の輪をつなぐ筋かい
            m.color(0xFFCBD5E1);
            final pf = rim(a, rr - 0.35, -gap), pb = rim(a, rr - 0.35, gap), pf2 = rim(a + 2 * math.pi / n, rr - 0.35, gap);
            m.quad(pf + V3(0, 0, -0.12), pb + V3(0, 0, -0.12), pb + V3(0, 0, 0.12), pf + V3(0, 0, 0.12));
            m.quad(pf + V3(0, 0, -0.1), pf2 + V3(0, 0, -0.1), pf2 + V3(0, 0, 0.1), pf + V3(0, 0, 0.1));
            // ゴンドラ（輪の外の点から下がる。色とりどり、窓）
            final hang = rim(a, rr + 0.4, 0);
            final col = const [0xFFE11D48, 0xFFFACC15, 0xFF22C55E, 0xFF3B82F6, 0xFFF97316, 0xFFA855F7, 0xFFEC4899, 0xFF14B8A6][i % 8];
            m.color(0xFF9CA3AF);
            m.box(hang + V3(0, 0, -0.6), 0.12, 0.12, 1.2);
            m.color(col);
            m.box(hang + V3(0, 0, -2.4), 2.2, 2.0, 2.4, yaw: math.atan2(side.y, side.x));
            u.color(0xFFBFE3F5);
            final wq = hang + face * 1.02 + V3(0, 0, -2.3);
            u.quad(wq - side * 0.85, wq + side * 0.85, wq + side * 0.85 + V3(0, 0, 0.9), wq - side * 0.85 + V3(0, 0, 0.9));
          }
          // 中心の軸
          m.color(0xFF6B7280);
          m.box(c, 2.2, 2.2, 2.2, yaw: math.atan2(side.y, side.x));
          // A の字の脚（前後に2組）と、地面の乗り場
          m.color(0xFF9CA3AF);
          for (final dz in [-gap - 0.6, gap + 0.6]) {
            for (final sx in [-1.0, 1.0]) {
              final t0 = c + face * dz, b0 = c + face * (dz * 2.2) + side * (sx * 12) + V3(0, 0, -c.z);
              final nn = (b0 - t0).cross(face).unit * 0.45;
              m.quad(t0 - nn, t0 + nn, b0 + nn, b0 - nn);
            }
            final mid0 = c + face * dz + V3(0, 0, -c.z * 0.55);
            m.quad(mid0 - side * 6.6 + V3(0, 0, -0.25), mid0 + side * 6.6 + V3(0, 0, -0.25), mid0 + side * 6.6 + V3(0, 0, 0.25), mid0 - side * 6.6 + V3(0, 0, 0.25));
          }
          m.color(0xFF7F1D2D);
          m.box(c + V3(0, 0, -c.z + 2), 14, 8, 4, yaw: math.atan2(side.y, side.x));
        case 'forest':
          // 球場の周りの森（狭山丘陵）：丸い木の頭（2段の箱をずらして重ねる）と、奥のなだらかな丘
          for (var i = 0; i < 220; i++) {
            final a = -180 + 360 * rnd.nextDouble();
            final h = 12 + rnd.nextDouble() * 14, wd = 7 + rnd.nextDouble() * 6;
            final p = polar(a, _outerEdge(a) + 4 + wd * 0.75 + rnd.nextDouble() * 70);
            m.color(0xFF4A3B2C);
            m.box(p + V3(0, 0, h * 0.25), 0.8, 0.8, h * 0.5);
            final g = _mixC(0xFF234D27, 0xFF4E7F37, rnd.nextDouble());
            m.color(g);
            m.box(p + V3(0, 0, h * 0.62), wd, wd, h * 0.5, yaw: a * deg);
            m.color(_mixC(g, 0xFF9CCB6A, 0.18));
            m.box(p + V3(0, 0, h * 0.86), wd * 0.68, wd * 0.68, h * 0.3, yaw: a * deg + math.pi / 4);
          }
          for (var i = 0; i < 12; i++) {
            final a0 = -180 + i * 30.0 + rnd.nextDouble() * 8;
            m.color(_mixC(0xFF2F5A33, 0xFF6F8F78, 0.35 + rnd.nextDouble() * 0.2));
            m.tri(polar(a0 - 10, 520), polar(a0 + 40, 520), polar(a0 + 15, 520, 45 + rnd.nextDouble() * 35));
          }
        case 'marineTower':
          // 左翼の奥の赤白の塔（高さ約 100m の格子の塔と展望台）
          final p = polar(-38, 330);
          for (var k = 0; k < 10; k++) {
            m.color(k.isEven ? 0xFFDC2626 : 0xFFF1F5F9);
            final w0 = 7.0 - k * 0.55, w1 = 7.0 - (k + 1) * 0.55;
            final face = -V3(p.x, p.y, 0).unit, side = V3(-face.y, face.x, 0);
            m.quad(p - side * w0 + V3(0, 0, k * 9.0), p + side * w0 + V3(0, 0, k * 9.0), p + side * w1 + V3(0, 0, (k + 1) * 9.0), p - side * w1 + V3(0, 0, (k + 1) * 9.0));
          }
          m.color(0xFFE5E7EB);
          m.box(p + const V3(0, 0, 93), 10, 10, 5);
        case 'skyline':
          // 外野の奥のビル群（窓の帯）
          for (var i = 0; i < 26; i++) {
            final a = -80 + 160 * rnd.nextDouble();
            final d = 200 + rnd.nextDouble() * 160;
            final h = 25 + rnd.nextDouble() * 90;
            final p = polar(a, d);
            final w = 14 + rnd.nextDouble() * 16;
            m.color(_mixC(0xFF94A3B8, 0xFF475569, rnd.nextDouble()));
            m.box(p + V3(0, 0, h / 2), w, w, h, yaw: a * deg);
            final face = -V3(p.x, p.y, 0).unit, side = V3(-face.y, face.x, 0);
            u.color(0xFFCBD5E1);
            for (var z = 4.0; z < h - 3; z += 6) {
              final q = p + face * (w / 2 + 0.1) + V3(0, 0, z);
              u.quad(q - side * (w * 0.42), q + side * (w * 0.42), q + side * (w * 0.42) + V3(0, 0, 1.6), q - side * (w * 0.42) + V3(0, 0, 1.6));
            }
          }
        case 'town':
          for (var i = 0; i < 40; i++) {
            final a = -180 + 360 * rnd.nextDouble();
            final p = polar(a, 175 + rnd.nextDouble() * 80);
            final h = 6 + rnd.nextDouble() * 22, w = 10 + rnd.nextDouble() * 14;
            m.color(_mixC(0xFFB8B2A7, 0xFF6B7280, rnd.nextDouble()));
            m.box(p + V3(0, 0, h / 2), w, w * 0.8, h, yaw: a * deg);
          }
        case 'mountains':
          // 外野の向こうの山並み（遠くてかすむ）
          for (var i = 0; i < 9; i++) {
            final a0 = -75 + i * 18.0 + rnd.nextDouble() * 6;
            final peak = polar(a0 + 9, 900, 120 + rnd.nextDouble() * 110);
            m.color(_mixC(0xFF5B7A6A, 0xFFB7C6CF, 0.45 + rnd.nextDouble() * 0.2));
            m.tri(polar(a0 - 6, 900), polar(a0 + 24, 900), peak);
          }
        case 'trees':
          for (var i = 0; i < 70; i++) {
            final a = -180 + 360 * rnd.nextDouble();
            final p = polar(a, 150 + rnd.nextDouble() * 30);
            final h = 10 + rnd.nextDouble() * 10;
            m.color(_mixC(0xFF2F5D31, 0xFF4F7D3A, rnd.nextDouble()));
            m.box(p + V3(0, 0, h * 0.6), 9, 9, h * 0.8, yaw: a * deg);
          }
        case 'sea':
          // 外野の奥の海（地平線まで）
          m.color(0xFF2E6E9E);
          for (var a = -90.0; a < 90; a += 15) {
            m.quad(polar(a, 190, -0.5), polar(a + 15, 190, -0.5), polar(a + 15, 1500, -0.5), polar(a, 1500, -0.5));
          }
      }
    }
  }
}
