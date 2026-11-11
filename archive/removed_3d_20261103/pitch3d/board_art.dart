import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../engine/match_simulator.dart';

/// ビジョンに映すもの（この1球の時点）：得点表の集計・チームの色・広告
class BoardData {
  final PitchEvent e;
  final String stadium;
  final Color home, away;
  final List<(String, int)> ads; // 社名・色
  final Map<String, int> runs; // '3T'（3回表）→ 得点
  final int rH, rA, hH, hA, eH, eA;
  const BoardData({required this.e, required this.stadium, required this.home, required this.away, required this.ads, required this.runs, required this.rH, required this.rA, required this.hH, required this.hA, required this.eH, required this.eA});

  /// 打順の行（'守備|名前|背番号|打率|本塁打'）から、名前の行を探す
  List<String> cellOf(String name) {
    for (final l in [...e.homeLine, ...e.awayLine]) {
      final ps = l.split('|');
      if (ps.length > 1 && ps[1] == name) return ps;
    }
    return const [];
  }
}

/// ビジョンの画面の絵（高さ 320 で、幅はビジョンの縦横比に合わせる）。実物の写真・中継を参考にした架空のデザイン：
///  濃い青の地に白い字、見出しは水色、いまの打者は黄色、チームは各球団の色
class BoardArt {
  static const double h = 320;
  static String? font; // 字体（null＝端末の標準。PC のテストで日本語の字体を指定する）
  static const bg0 = Color(0xFF0B1B48), bg1 = Color(0xFF14317E), line = Color(0xFF2B4C9E), head = Color(0xFF9EC5FF), hi = Color(0xFFFFD84D), led = Color(0xFF050B1E);

  /// content：'main'・'video'・'score'・'ads'・'lineupHome'・'lineupAway'・'speed'
  static ui.Picture paint(String content, double w, BoardData d) {
    final rec = ui.PictureRecorder();
    final cv = Canvas(rec, Rect.fromLTWH(0, 0, w, h));
    cv.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = led);
    switch (content) {
      case 'video':
        _video(cv, 0, w, d);
      case 'score':
        _score(cv, w, d);
      case 'ads':
        _adTiles(cv, 0, w, d, 0);
      case 'lineupHome':
        _lineupRow(cv, w, d, true);
      case 'lineupAway':
        _lineupRow(cv, w, d, false);
      case 'speed':
        _speed(cv, 0, w, d);
      default:
        if (w < 1500) {
          _compact(cv, w, d);
        } else if (w <= 2300) {
          final x0 = (w - 1720) / 2;
          if (x0 > 4) {
            _adTiles(cv, 0, x0, d, 3);
            _adTiles(cv, w - x0, x0, d, 5);
          }
          cv.save();
          cv.translate(x0, 0);
          _wide(cv, d);
          cv.restore();
        } else {
          // とても横長（外野席の上ほぼ全体）：左に打者の紹介、中央に得点表、右に投手と球速
          final side = (w - 1720) / 2;
          _video(cv, 0, side - 8, d);
          cv.save();
          cv.translate(side, 0);
          _wide(cv, d);
          cv.restore();
          _speed(cv, w - side + 8, side - 8, d);
        }
    }
    return rec.endRecording();
  }

  // ───── 部品 ─────
  static void _panel(Canvas cv, Rect r) {
    cv.drawRect(r, Paint()..shader = ui.Gradient.linear(r.topCenter, r.bottomCenter, const [bg1, bg0]));
    cv.drawRect(r, Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2);
  }

  static void _txt(Canvas cv, String t, double x, double y, double size, Color col, {FontWeight fw = FontWeight.w800, double? maxW, TextAlign align = TextAlign.left, bool digits = false}) {
    final tp = TextPainter(
        text: TextSpan(text: t, style: TextStyle(fontFamily: font, fontSize: size, color: col, fontWeight: fw, height: 1.0, letterSpacing: digits ? 0.5 : 0, fontFeatures: const [ui.FontFeature.tabularFigures()])),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…')
      ..layout(maxWidth: maxW ?? 4000);
    final dx = align == TextAlign.right ? x - tp.width : (align == TextAlign.center ? x - tp.width / 2 : x);
    tp.paint(cv, Offset(dx, y));
  }

  /// 文字を幅に収まるよう横だけ縮めて描く（看板の社名など）
  static void _fit(Canvas cv, String t, Offset c, double size, Color col, double maxW, {FontWeight fw = FontWeight.w900}) {
    final tp = TextPainter(text: TextSpan(text: t, style: TextStyle(fontFamily: font, fontSize: size, color: col, fontWeight: fw, height: 1.0)), textDirection: TextDirection.ltr, maxLines: 1)..layout();
    final sc = math.min(1.0, maxW / math.max(1.0, tp.width));
    cv.save();
    cv.translate(c.dx, c.dy);
    cv.scale(sc, 1);
    tp.paint(cv, Offset(-tp.width / 2, -tp.height / 2));
    cv.restore();
  }

  static void _bases(Canvas cv, Offset c, double s, List<bool> on) {
    for (var i = 0; i < 3; i++) {
      final b = on.length > i && on[i];
      final pos = c + [Offset(s * 1.2, 0), Offset(0, -s * 1.2), Offset(-s * 1.2, 0)][i];
      cv.save();
      cv.translate(pos.dx, pos.dy);
      cv.rotate(math.pi / 4);
      final r = Rect.fromCenter(center: Offset.zero, width: s, height: s);
      cv.drawRect(r, Paint()..color = b ? hi : const Color(0xFF1B2A55));
      cv.drawRect(r, Paint()
        ..color = Colors.white54
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5);
      cv.restore();
    }
  }

  static void _bso(Canvas cv, double x, double y, double size, double gap, PitchEvent e) {
    for (final (row, label, n, max, on) in [(0, 'B', e.balls, 3, const Color(0xFF22C55E)), (1, 'S', e.strikes, 2, hi), (2, 'O', e.outsBefore, 2, const Color(0xFFEF4444))]) {
      final yy = y + row * gap;
      _txt(cv, label, x, yy, size, Colors.white, align: TextAlign.center);
      for (var i = 0; i < max; i++) {
        cv.drawCircle(Offset(x + size * 1.5 + i * size * 1.35, yy + size / 2), size * 0.5, Paint()..color = i < n ? on : const Color(0xFF1B2A55));
      }
    }
  }

  /// イニングごとの得点表（2行）。x, y の左上から幅 w・高さ hh
  static void _lineScore(Canvas cv, double x, double y, double w, double hh, BoardData d, {bool heads = true}) {
    final e = d.e;
    final th = heads ? hh * 0.2 : 0.0;
    final rowH = (hh - th) / 2;
    final tw = w * 0.14, cw = (w - tw) / 12.6;
    if (heads) {
      cv.drawRect(Rect.fromLTWH(x, y, w, th), Paint()..color = const Color(0xFF0A1636));
      for (var i = 0; i < 9; i++) {
        _txt(cv, '${i + 1}', x + tw + i * cw + cw / 2, y + th * 0.15, th * 0.7, head, align: TextAlign.center, digits: true);
      }
      for (final (j, lab) in [(0, 'R'), (1, 'H'), (2, 'E')]) {
        _txt(cv, lab, x + tw + 9 * cw + (j + 0.5) * cw * 1.2, y + th * 0.15, th * 0.7, head, align: TextAlign.center);
      }
    }
    for (final (row, team, col, top) in [(0, e.awayName, d.away, true), (1, e.homeName, d.home, false)]) {
      final yy = y + th + row * rowH;
      cv.drawRect(Rect.fromLTWH(x, yy + 2, tw - 6, rowH - 4), Paint()..color = col);
      _fit(cv, team.isEmpty ? '' : team.characters.take(team.characters.length > 3 ? 2 : 3).toString(), Offset(x + (tw - 6) / 2, yy + rowH / 2), rowH * 0.55, Colors.white, tw - 14);
      for (var i = 0; i < 9; i++) {
        final r = d.runs['${i + 1}${top ? 'T' : 'B'}'];
        final now = e.inning == i + 1 && e.top == top;
        if (now) {
          cv.drawRect(Rect.fromLTWH(x + tw + i * cw + 2, yy + 2, cw - 4, rowH - 4), Paint()
            ..color = hi
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);
        }
        _txt(cv, r == null ? '' : '$r', x + tw + i * cw + cw / 2, yy + rowH * 0.18, rowH * 0.66, Colors.white, align: TextAlign.center, digits: true);
      }
      final vals = top ? [d.rA, d.hA, d.eA] : [d.rH, d.hH, d.eH];
      for (var j = 0; j < 3; j++) {
        _txt(cv, '${vals[j]}', x + tw + 9 * cw + (j + 0.5) * cw * 1.2, yy + rowH * 0.18, rowH * 0.66, j == 0 ? hi : Colors.white, align: TextAlign.center, digits: true);
      }
    }
  }

  // ───── 横長のメイン（1720×320）：左＝ホーム（縦のチーム名・打者/投手のカード・打順）、中央＝題・塁と B S O・得点表・球種と球速、右＝ビジター、下＝広告の帯 ─────
  static void _wide(Canvas cv, BoardData d) {
    const bw = 1720.0;
    final e = d.e;
    void side(bool right, String team, List<String> lineup, Color tc, bool batting) {
      final x0 = right ? bw - 472 : 0.0;
      double X(double x, double w) => right ? x0 + 472 - x - w : x0 + x; // 左右対称に置く
      final strip = Rect.fromLTWH(X(0, 34), 0, 34, 286);
      cv.drawRect(strip, Paint()..color = tc);
      cv.save();
      cv.translate(strip.center.dx, strip.center.dy);
      cv.rotate(-math.pi / 2);
      _txt(cv, team, 0, -12, 24, Colors.white, align: TextAlign.center, maxW: 280);
      cv.restore();
      final card = Rect.fromLTWH(X(38, 140), 0, 140, 286);
      _panel(cv, card);
      final who = batting ? e.batter : e.pitcher;
      final cx = card.center.dx;
      cv.drawRect(Rect.fromLTWH(card.left + 6, 6, 128, 150), Paint()..color = const Color(0xFF0A1636));
      cv.drawCircle(Offset(cx, 66), 30, Paint()..color = tc.withValues(alpha: 0.9));
      cv.drawRRect(RRect.fromRectAndCorners(Rect.fromCenter(center: Offset(cx, 132), width: 112, height: 48), topLeft: const Radius.circular(40), topRight: const Radius.circular(40)), Paint()..color = tc.withValues(alpha: 0.9));
      cv.drawRect(Rect.fromLTWH(card.left + 6, 160, 128, 30), Paint()..color = Colors.white);
      _txt(cv, who, cx, 165, 21, const Color(0xFF0B1B48), align: TextAlign.center, maxW: 124);
      if (batting) {
        final c = d.cellOf(e.batter);
        _txt(cv, '打率', card.left + 10, 198, 16, head);
        _txt(cv, c.length > 3 ? c[3] : '', card.right - 10, 196, 28, Colors.white, align: TextAlign.right, digits: true);
        _txt(cv, '本塁打', card.left + 10, 236, 16, head);
        _txt(cv, c.length > 4 ? c[4] : '', card.right - 10, 234, 28, Colors.white, align: TextAlign.right, digits: true);
      } else {
        _txt(cv, '球数', card.left + 10, 198, 16, head);
        _txt(cv, '${e.pitcherCount}', card.right - 10, 196, 28, Colors.white, align: TextAlign.right, digits: true);
        _txt(cv, '今日', card.left + 10, 236, 16, head);
        _txt(cv, e.pitchName, card.right - 10, 238, 20, Colors.white, align: TextAlign.right, maxW: 90);
      }
      final lr = Rect.fromLTWH(X(182, 290), 0, 290, 286);
      _panel(cv, lr);
      _lineupList(cv, lr, lineup, batting ? e.batter : '');
    }

    side(false, e.homeName, e.homeLine, d.home, !e.top);
    side(true, e.awayName, e.awayLine, d.away, e.top);
    const cr = Rect.fromLTWH(476, 0, bw - 952, 286);
    _panel(cv, cr);
    for (final (i, t) in [(0, d.stadium), (1, '${e.inning}回${e.top ? '表' : '裏'}　${e.awayName} 対 ${e.homeName}')]) {
      final r = Rect.fromLTWH(cr.left + 24, 12.0 + i * 40, 430, 32);
      cv.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(6)), Paint()..color = Colors.white);
      _txt(cv, t, r.center.dx, r.top + 6, 20, const Color(0xFF0B1B48), align: TextAlign.center, maxW: 420);
    }
    _bases(cv, Offset(cr.left + 540, 48), 22, e.basesBefore);
    _bso(cv, cr.left + 620, 8, 22, 30, e);
    _lineScore(cv, cr.left + 24, 106, 76 + 9 * 44 + 3 * 52, 122, d);
    for (final (i, lab) in [(0, 'H'), (1, 'E'), (2, 'Fc')]) {
      final x = cr.left + 24 + i * 56.0;
      cv.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, 236, 48, 34), const Radius.circular(4)), Paint()..color = const Color(0xFF1B2A55));
      _txt(cv, lab, x + 24, 243, 20, Colors.white38, align: TextAlign.center);
    }
    _txt(cv, e.pitchName, cr.right - 200, 244, 22, head, align: TextAlign.right, maxW: 200);
    _txt(cv, '${e.speed.round()}', cr.right - 70, 226, 46, Colors.white, align: TextAlign.right, digits: true);
    _txt(cv, 'km/h', cr.right - 14, 250, 18, head, align: TextAlign.right);
    // 下の広告の帯
    const aw = bw / 8;
    for (var i = 0; i < 8; i++) {
      final ad = d.ads[i % d.ads.length];
      final x = i * aw;
      cv.drawRect(Rect.fromLTWH(x + 1, 291, aw - 2, 28), Paint()..color = i.isEven ? Colors.white : Color(ad.$2));
      _txt(cv, ad.$1, x + aw / 2, 295, 20, i.isEven ? Color(ad.$2) : Colors.white, align: TextAlign.center, maxW: aw - 8);
    }
  }

  /// 打順の表（番号・守備・名前・打率・本塁打）。いまの打者は黄色
  static void _lineupList(Canvas cv, Rect lr, List<String> lineup, String now) {
    final lx = lr.left, w = lr.width, rowH = (lr.height - 28) / 9;
    final fs = math.min(20.0, rowH * 0.72);
    final narrow = w < 270; // 狭い表：本塁打の列を省いて名前を広く
    final avgX = narrow ? w - 8 : w - 54;
    _txt(cv, 'LINEUP', lx + 10, lr.top + 6, 15, head);
    _txt(cv, 'AVG', lx + avgX, lr.top + 6, 15, head, align: TextAlign.right);
    if (!narrow) _txt(cv, 'HR', lx + w - 10, lr.top + 6, 15, head, align: TextAlign.right);
    for (var i = 0; i < 9 && i < lineup.length; i++) {
      final ps = lineup[i].split('|');
      final y = lr.top + 28.0 + i * rowH;
      final cur = ps.length > 1 && ps[1] == now;
      if (cur) cv.drawRect(Rect.fromLTWH(lx + 3, y - 1, w - 6, rowH - 1), Paint()..color = hi);
      final c1 = cur ? const Color(0xFF0B1B48) : Colors.white;
      _txt(cv, '${i + 1}', lx + (narrow ? 13 : 18), y + 2, fs, c1, align: TextAlign.center, digits: true);
      _txt(cv, ps.isNotEmpty ? ps[0] : '', lx + (narrow ? 34 : 44), y + 2, fs * 0.95, cur ? c1 : const Color(0xFF7DD3FC), align: TextAlign.center);
      final nx = narrow ? 48.0 : 62.0;
      _txt(cv, ps.length > 1 ? ps[1] : '', lx + nx, y + 2, fs, c1, maxW: avgX - nx - fs * 2.6);
      _txt(cv, ps.length > 3 ? ps[3] : '', lx + avgX, y + 3, fs * 0.9, c1, align: TextAlign.right, digits: true);
      if (!narrow) _txt(cv, ps.length > 4 ? ps[4] : '', lx + w - 10, y + 3, fs * 0.9, c1, align: TextAlign.right, digits: true);
      if (i < 8) cv.drawLine(Offset(lx + 6, y + rowH - 1), Offset(lx + w - 6, y + rowH - 1), Paint()..color = line.withValues(alpha: 0.5));
    }
  }

  // ───── 縦横比の小さいメイン（屋外の球場のスコアボード）：上に得点表、左に先攻・右に後攻の打順、中央に打者・カウント・球速 ─────
  static void _compact(Canvas cv, double w, BoardData d) {
    final e = d.e;
    // 上：題と得点表
    final top = Rect.fromLTWH(4, 4, w - 8, 112);
    _panel(cv, top);
    _lineScore(cv, top.left + 8, top.top + 6, top.width - 16, top.height - 12, d);
    // 下：打順（先攻・後攻）と中央
    final colW = (w * 0.31).clamp(200.0, 380.0);
    final la = Rect.fromLTWH(4, 122, colW, h - 126), lh = Rect.fromLTWH(w - 4 - colW, 122, colW, h - 126);
    _panel(cv, la);
    _panel(cv, lh);
    cv.drawRect(Rect.fromLTWH(la.left, la.top, 6, la.height), Paint()..color = d.away);
    cv.drawRect(Rect.fromLTWH(lh.right - 6, lh.top, 6, lh.height), Paint()..color = d.home);
    _lineupList(cv, la.deflate(4), e.awayLine, e.top ? e.batter : '');
    _lineupList(cv, lh.deflate(4), e.homeLine, e.top ? '' : e.batter);
    final mid = Rect.fromLTRB(la.right + 6, 122, lh.left - 6, h - 4);
    _panel(cv, mid);
    final mx = mid.center.dx, mw = mid.width;
    final c = d.cellOf(e.batter);
    _txt(cv, e.top ? e.awayName : e.homeName, mx, mid.top + 8, 16, head, align: TextAlign.center, maxW: mw - 12);
    _fit(cv, e.batter, Offset(mx, mid.top + 46), 34, Colors.white, mw - 16);
    _txt(cv, '${c.isNotEmpty ? c[0] : ''}  打率 ${c.length > 3 ? c[3] : ''}  本 ${c.length > 4 ? c[4] : ''}', mx, mid.top + 72, 16, Colors.white70, align: TextAlign.center, maxW: mw - 12, digits: true);
    // 左に B S O、右に塁・球種・球速
    final s = math.min(18.0, mw / 14);
    _bso(cv, mid.left + 18, mid.top + 98, s, s * 1.4, e);
    _bases(cv, Offset(mid.right - s * 2.8, mid.top + 124), s * 0.95, e.basesBefore);
    _txt(cv, e.pitchName, mid.left + 14, mid.bottom - s * 1.45, s * 0.95, head, maxW: mw * 0.45);
    _txt(cv, '${e.speed.round()}', mid.right - 12 - s * 2.4, mid.bottom - s * 2.6, s * 2.2, Colors.white, align: TextAlign.right, digits: true);
    _txt(cv, 'km/h', mid.right - 10, mid.bottom - s * 1.2, s * 0.75, head, align: TextAlign.right);
  }

  // ───── 打者の紹介（映像のかわり）：チームの色の地、背番号・名前・守備・今日の成績 ─────
  static void _video(Canvas cv, double x0, double w, BoardData d) {
    final e = d.e;
    final tc = e.top ? d.away : d.home;
    final r = Rect.fromLTWH(x0, 0, w, h);
    cv.drawRect(r, Paint()..shader = ui.Gradient.linear(r.topLeft, r.bottomRight, [tc, Color.lerp(tc, const Color(0xFF050B1E), 0.75)!]));
    // 斜めの光の帯
    final band = Path()
      ..moveTo(x0 + w * 0.55, 0)
      ..lineTo(x0 + w * 0.75, 0)
      ..lineTo(x0 + w * 0.45, h)
      ..lineTo(x0 + w * 0.25, h)
      ..close();
    cv.drawPath(band, Paint()..color = Colors.white.withValues(alpha: 0.07));
    final c = d.cellOf(e.batter);
    final num = c.length > 2 ? c[2] : '';
    final tall = w < h * 1.6;
    if (tall) {
      _fit(cv, num, Offset(x0 + w / 2, h * 0.3), h * 0.36, Colors.white.withValues(alpha: 0.95), w - 16);
      _fit(cv, e.batter, Offset(x0 + w / 2, h * 0.6), h * 0.11, Colors.white, w - 16);
      _txt(cv, '${c.isNotEmpty ? c[0] : ''}  ${c.length > 3 ? c[3] : ''}', x0 + w / 2, h * 0.7, h * 0.07, Colors.white70, align: TextAlign.center, maxW: w - 12, digits: true);
      _txt(cv, e.batterToday, x0 + w / 2, h * 0.82, h * 0.06, hi, align: TextAlign.center, maxW: w - 12);
      return;
    }
    // 横長：左に大きな背番号、右に名前と成績
    _txt(cv, 'NOW BATTING', x0 + w * 0.06, h * 0.08, h * 0.07, Colors.white70);
    _fit(cv, num, Offset(x0 + w * 0.2, h * 0.55), h * 0.62, Colors.white.withValues(alpha: 0.92), w * 0.3);
    final tx = x0 + w * 0.4;
    _txt(cv, e.top ? e.awayName : e.homeName, tx, h * 0.12, h * 0.08, Colors.white70, maxW: w * 0.56);
    _txt(cv, e.batter, tx, h * 0.24, h * 0.17, Colors.white, maxW: w * 0.56);
    cv.drawRect(Rect.fromLTWH(tx, h * 0.47, w * 0.54, 3), Paint()..color = Colors.white54);
    final stats = [('打率', c.length > 3 ? c[3] : '-'), ('本塁打', c.length > 4 ? c[4] : '-'), ('守備', c.isNotEmpty ? (_posName[c[0]] ?? c[0]) : '-')];
    for (var i = 0; i < (w < 900 ? 2 : stats.length); i++) {
      final sx = tx + i * w * 0.18;
      _txt(cv, stats[i].$1, sx, h * 0.53, h * 0.065, head);
      _txt(cv, stats[i].$2, sx, h * 0.62, h * 0.13, Colors.white, digits: true, maxW: w * 0.17);
    }
    if (e.batterToday.isNotEmpty) _txt(cv, '今日　${e.batterToday}', tx, h * 0.84, h * 0.07, hi, maxW: w * 0.56);
  }

  static const _posName = {'投': '投手', '捕': '捕手', '一': '一塁手', '二': '二塁手', '三': '三塁手', '遊': '遊撃手', '左': '左翼手', '中': '中堅手', '右': '右翼手', '指': '指名打者'};

  // ───── 投手と球速 ─────
  static void _speed(Canvas cv, double x0, double w, BoardData d) {
    final e = d.e;
    final tc = e.top ? d.home : d.away;
    final r = Rect.fromLTWH(x0, 0, w, h);
    cv.drawRect(r, Paint()..shader = ui.Gradient.linear(r.topRight, r.bottomLeft, [Color.lerp(tc, const Color(0xFF050B1E), 0.35)!, const Color(0xFF050B1E)]));
    _txt(cv, 'PITCHER', x0 + w * 0.06, h * 0.08, h * 0.07, Colors.white70);
    _txt(cv, e.pitcher, x0 + w * 0.06, h * 0.18, h * 0.14, Colors.white, maxW: w * 0.5);
    _txt(cv, '球数 ${e.pitcherCount}', x0 + w * 0.06, h * 0.38, h * 0.08, head, digits: true);
    _txt(cv, e.pitchName, x0 + w * 0.06, h * 0.62, h * 0.12, hi, maxW: w * 0.4);
    _txt(cv, '${e.speed.round()}', x0 + w * 0.8, h * 0.3, h * 0.5, Colors.white, align: TextAlign.right, digits: true);
    _txt(cv, 'km/h', x0 + w * 0.95, h * 0.68, h * 0.1, head, align: TextAlign.right);
  }

  // ───── 得点表だけ（ネット裏のサブスコアボード）─────
  static void _score(Canvas cv, double w, BoardData d) {
    final e = d.e;
    final sw = math.min(w * 0.68, 2200.0);
    _panel(cv, Rect.fromLTWH(2, 2, sw, h - 4));
    _lineScore(cv, 12, 10, sw - 20, h - 20, d);
    final rx = sw + 10, rw = w - rx - 4;
    _panel(cv, Rect.fromLTWH(rx, 2, rw, h - 4));
    final s = math.min(40.0, rw / 9);
    _bso(cv, rx + s, 18, s, s * 1.45, e);
    _bases(cv, Offset(rx + rw * 0.62, h * 0.32), s * 1.1, e.basesBefore);
    _txt(cv, '${e.speed.round()}', rx + rw - 14, h * 0.55, s * 2.2, Colors.white, align: TextAlign.right, digits: true);
    _txt(cv, 'km/h', rx + rw - 14, h * 0.55 + s * 2.3, s * 0.7, head, align: TextAlign.right);
    _txt(cv, e.pitcher, rx + s * 0.6, h * 0.62, s * 0.9, Colors.white, maxW: rw * 0.45);
    _txt(cv, e.pitchName, rx + s * 0.6, h * 0.62 + s * 1.2, s * 0.9, hi, maxW: rw * 0.45);
  }

  // ───── 1チームの打順を横に並べる（ウイングビジョン）─────
  static void _lineupRow(Canvas cv, double w, BoardData d, bool home) {
    final e = d.e;
    final lineup = home ? e.homeLine : e.awayLine;
    final tc = home ? d.home : d.away;
    final batting = home ? !e.top : e.top;
    final tw = w * 0.1;
    cv.drawRect(Rect.fromLTWH(0, 0, tw, h), Paint()..color = tc);
    cv.save();
    cv.translate(tw / 2, h / 2);
    _fit(cv, home ? e.homeName : e.awayName, Offset.zero, h * 0.16, Colors.white, tw - 12);
    cv.restore();
    final cw = (w - tw) / 9;
    for (var i = 0; i < 9; i++) {
      final ps = i < lineup.length ? lineup[i].split('|') : const <String>[];
      final r = Rect.fromLTWH(tw + i * cw + 2, 4, cw - 4, h - 8);
      final cur = batting && ps.length > 1 && ps[1] == e.batter;
      if (cur) {
        cv.drawRect(r, Paint()..color = hi);
      } else {
        _panel(cv, r);
      }
      final c1 = cur ? const Color(0xFF0B1B48) : Colors.white;
      _txt(cv, '${i + 1}', r.left + 10, r.top + 8, h * 0.16, cur ? c1 : head, digits: true);
      _txt(cv, ps.isNotEmpty ? ps[0] : '', r.right - 10, r.top + 12, h * 0.11, cur ? c1 : const Color(0xFF7DD3FC), align: TextAlign.right);
      _fit(cv, ps.length > 1 ? ps[1] : '', Offset(r.center.dx, r.top + h * 0.5), h * 0.17, c1, r.width - 12);
      _txt(cv, ps.length > 3 ? ps[3] : '', r.center.dx, r.top + h * 0.7, h * 0.12, c1, align: TextAlign.center, digits: true);
    }
  }

  /// 広告を並べる（幅に合わせて1〜数枚。縦長なら縦書き）
  static void _adTiles(Canvas cv, double x0, double w, BoardData d, int start) {
    if (d.ads.isEmpty || w < 4) return;
    final n = math.max(1, (w / (h * 2.2)).round());
    final tw = w / n;
    for (var i = 0; i < n; i++) {
      final ad = d.ads[(start + i) % d.ads.length];
      final r = Rect.fromLTWH(x0 + i * tw + 3, 3, tw - 6, h - 6);
      final inv = (start + i).isOdd;
      cv.drawRect(r, Paint()..color = inv ? Colors.white : Color(ad.$2));
      final col = inv ? Color(ad.$2) : Colors.white;
      if (r.width < r.height * 0.8) {
        // 縦書き
        final chars = ad.$1.characters.toList();
        final fs = math.min(r.width * 0.7, (r.height - 20) / math.max(1, chars.length));
        for (var k = 0; k < chars.length; k++) {
          _fit(cv, chars[k], Offset(r.center.dx, r.top + 10 + fs * (k + 0.5)), fs, col, r.width - 8);
        }
      } else {
        _fit(cv, ad.$1, r.center, math.min(r.height * 0.42, r.width * 0.2), col, r.width - 20);
        cv.drawRect(Rect.fromLTWH(r.left, r.bottom - 10, r.width, 10), Paint()..color = (inv ? Color(ad.$2) : Colors.white).withValues(alpha: 0.35));
      }
    }
  }

  /// リボンビジョンの帯（2048×64 を横に繰り返す）：チーム名と広告を交互に
  static ui.Image ribbon(String homeTeam, Color home, List<(String, int)> ads) {
    const w = 2048.0, hh = 64.0;
    final rec = ui.PictureRecorder();
    final cv = Canvas(rec, const Rect.fromLTWH(0, 0, w, hh));
    cv.drawRect(const Rect.fromLTWH(0, 0, w, hh), Paint()..color = const Color(0xFF05070D));
    const n = 8, cw = w / n;
    for (var i = 0; i < n; i++) {
      final r = Rect.fromLTWH(i * cw + 2, 4, cw - 4, hh - 8);
      if (i % 4 == 0) {
        cv.drawRect(r, Paint()..color = home);
        _fit(cv, homeTeam, r.center, 38, Colors.white, r.width - 16);
      } else {
        final ad = ads.isEmpty ? ('', 0xFF1D4ED8) : ads[i % ads.length];
        final inv = i.isOdd;
        if (inv) cv.drawRect(r, Paint()..color = Color(ad.$2));
        _fit(cv, ad.$1, r.center, 36, inv ? Colors.white : Color.lerp(Color(ad.$2), Colors.white, 0.35)!, r.width - 16);
      }
    }
    return rec.endRecording().toImageSync(w.toInt(), hh.toInt());
  }
}
