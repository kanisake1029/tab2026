import 'dart:math';
import 'package:flutter/material.dart';
import '../engine/fielder_ai.dart';
import '../engine/match_simulator.dart';
import '../engine/physics_engine.dart';
import '../models/player.dart';
import 'game_painters.dart' show pitchResultColor, pitchResultLabel, isHitOutcome, kStrikeColor, kBallColor, kOutColor, kHitColor;
import '../engine/play_resolver.dart';

// =====================================================================
// スコアボード
// =====================================================================

class ScoreBoard extends StatelessWidget {
  final String awayName;
  final String homeName;
  final MatchState st;
  final int awayHits;
  final int homeHits;
  final bool finished;
  final String batterLine;
  final String pitcherLine;
  final int awayErrors;
  final int homeErrors;
  /// スマホでカウント（BSO）と塁の行を出すか（ヘッダーに出すときは false）
  final bool showCount;

  const ScoreBoard({
    super.key,
    required this.awayName,
    required this.homeName,
    required this.st,
    required this.awayHits,
    required this.homeHits,
    required this.finished,
    this.batterLine = '',
    this.pitcherLine = '',
    this.awayErrors = 0,
    this.homeErrors = 0,
    this.showCount = true,
  });

  static const _bg = Color(0xFFFFFFFF);
  static const _cell = Color(0xFFF1F5F9);
  static const _line = Color(0xFFCBD5E1);
  static const _digit = Color(0xFF0F172A);

  @override
  Widget build(BuildContext context) {
    // 試合が終わったら、実際に行われた回まで（9回裏が終わると状態は10回表に進んでいるため）
    final played = st.isTop ? st.inning - 1 : st.inning;
    final n = finished ? max(9, played) : max(9, max(st.awayInningScores.length, st.homeInningScores.length));
    // まだ始まっていない回は空欄（表の途中なら、その回の裏は空欄）
    String sc(List<int> s, int i, bool isTopRow) {
      if (i >= s.length) return '';
      final inn = i + 1;
      if (!finished) {
        if (inn > st.inning) return '';
        if (inn == st.inning && !isTopRow && st.isTop) return '';
      } else {
        if (inn > played) return '';
        // 9回以降の表でホームがリードして終わった：裏は行わない（X）
        if (!isTopRow && inn == played && !st.isTop && st.homeScore > st.awayScore && inn >= 9 && s[i] == 0) return 'X';
      }
      return '${s[i]}';
    }

    bool current(int i, bool topRow) => !finished && st.inning == i + 1 && st.isTop == topRow;

    Widget lamps(String label, int count, int max, Color on, double d) => Row(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(width: 13, child: Text(label, style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 12))),
          for (var i = 0; i < max; i++)
            Container(
              width: d,
              height: d,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < count ? on : const Color(0xFFE2E8F0),
                boxShadow: i < count ? [BoxShadow(color: on.withOpacity(0.7), blurRadius: 6)] : null,
                border: Border.all(color: Colors.black38),
              ),
            ),
        ]);

    return LayoutBuilder(builder: (context, c) {
      final narrow = c.maxWidth < 600;
      // 幅：チーム名・計H E を除いた残りを9回で割る（延長の回は同じ幅で横スクロール）
      final nameW = narrow ? 50.0 : 74.0;
      final rW = narrow ? 26.0 : 32.0, hW = narrow ? 22.0 : 28.0;
      final side = narrow ? 0.0 : 10 + 70 + 10 + 46;
      final avail = c.maxWidth - 16 - side - nameW - rW - hW * 2 - 4 - 10 - 2;
      final cw = (avail / 9 - 2).clamp(16.0, 28.0);
      final rowH = narrow ? 24.0 : 26.0;
      Widget cell(String t, {double? w, bool hi = false, bool head = false, Color? color, bool bold = false}) => Container(
            width: w ?? cw,
            height: head ? 16 : rowH,
            alignment: Alignment.center,
            margin: const EdgeInsets.all(1),
            decoration: BoxDecoration(color: head ? Colors.transparent : (hi ? const Color(0xFFFEF9C3) : _cell), borderRadius: BorderRadius.circular(2), border: hi ? Border.all(color: const Color(0xFF15803D), width: 1.2) : null),
            child: FittedBox(fit: BoxFit.scaleDown, child: Text(t, style: TextStyle(color: color ?? (head ? Color(0xFF64748B) : _digit), fontSize: head ? 10.5 : (narrow ? 14 : 15), fontWeight: bold ? FontWeight.w900 : FontWeight.w700, fontFamily: 'monospace'))),
          );
      Widget name(String n, bool topRow) => Container(
            width: nameW,
            height: rowH,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            margin: const EdgeInsets.all(1),
            decoration: BoxDecoration(color: _cell, borderRadius: BorderRadius.circular(2)),
            child: Row(children: [
              if (!finished && st.isTop == topRow) const Icon(Icons.play_arrow, color: Color(0xFFD97706), size: 11),
              Expanded(child: Text(n, overflow: TextOverflow.ellipsis, style: TextStyle(color: Color(0xFF0F172A), fontSize: narrow ? 11.5 : 13, fontWeight: FontWeight.bold))),
            ]),
          );
      final innings = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [for (var i = 1; i <= n; i++) cell('$i', head: true)]),
        Row(mainAxisSize: MainAxisSize.min, children: [for (var i = 0; i < n; i++) cell(sc(st.awayInningScores, i, true), hi: current(i, true))]),
        Row(mainAxisSize: MainAxisSize.min, children: [for (var i = 0; i < n; i++) cell(sc(st.homeInningScores, i, false), hi: current(i, false))]),
      ]);
      final board = Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Column(mainAxisSize: MainAxisSize.min, children: [SizedBox(width: nameW + 2, height: 18), name(awayName, true), name(homeName, false)]),
        // 9回ぶんの幅。延長はここだけ横スクロール（最新の回が見える）
        SizedBox(
          width: (cw + 2) * 9,
          child: n > 9 ? SingleChildScrollView(scrollDirection: Axis.horizontal, reverse: true, child: innings) : innings,
        ),
        const SizedBox(width: 4),
        Column(mainAxisSize: MainAxisSize.min, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [cell('計', w: rW, head: true), cell('H', w: hW, head: true), cell('E', w: hW, head: true)]),
          Row(mainAxisSize: MainAxisSize.min, children: [cell('${st.awayScore}', w: rW, color: const Color(0xFF15803D), bold: true), cell('$awayHits', w: hW), cell('$awayErrors', w: hW)]),
          Row(mainAxisSize: MainAxisSize.min, children: [cell('${st.homeScore}', w: rW, color: const Color(0xFF15803D), bold: true), cell('$homeHits', w: hW), cell('$homeErrors', w: hW)]),
        ]),
      ]);
      final b0 = finished ? 0 : st.balls, s0 = finished ? 0 : st.strikes, o0 = finished ? 0 : st.outs.clamp(0, 2);
      final diamond = SizedBox(width: narrow ? 34 : 46, height: narrow ? 34 : 46, child: CustomPaint(painter: _MiniDiamond(st.runner1B != null, st.runner2B != null, st.runner3B != null)));
      final info = (batterLine.isNotEmpty || pitcherLine.isNotEmpty)
          ? DefaultTextStyle(
              style: const TextStyle(color: Color(0xFF0F172A), fontSize: 12),
              child: Wrap(spacing: 12, runSpacing: 2, children: [
                if (pitcherLine.isNotEmpty) Text('投 $pitcherLine'),
                if (batterLine.isNotEmpty) Text('打 $batterLine', style: const TextStyle(color: Color(0xFFFFF4C2), fontWeight: FontWeight.bold)),
              ]),
            )
          : null;
      return Container(
        padding: EdgeInsets.all(narrow ? 6 : 8),
        decoration: BoxDecoration(
          color: _bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _line, width: 2),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          if (narrow && !showCount) ...[
            FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: board),
          ] else if (narrow) ...[
            FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: board),
            const SizedBox(height: 4),
            // BSO（横に並べる）と塁
            Row(children: [
              lamps('B', b0, 3, const Color(0xFF4ADE80), 11),
              const SizedBox(width: 6),
              lamps('S', s0, 2, const Color(0xFFFACC15), 11),
              const SizedBox(width: 6),
              lamps('O', o0, 2, const Color(0xFFF87171), 11),
              const SizedBox(width: 8),
              diamond,
              if (info != null) ...[const SizedBox(width: 8), Expanded(child: info)],
            ]),
          ] else ...[
            Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Expanded(child: Align(alignment: Alignment.centerLeft, child: board)),
              const SizedBox(width: 10),
              Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                lamps('B', b0, 3, const Color(0xFF4ADE80), 13),
                const SizedBox(height: 3),
                lamps('S', s0, 2, const Color(0xFFFACC15), 13),
                const SizedBox(height: 3),
                lamps('O', o0, 2, const Color(0xFFF87171), 13),
              ]),
              const SizedBox(width: 10),
              diamond,
            ]),
            if (info != null) ...[
              const SizedBox(height: 6),
              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Colors.black.withOpacity(0.25), borderRadius: BorderRadius.circular(4)), child: info),
            ],
          ],
        ]),
      );
    });
  }
}

/// ヘッダー用：塁の図と B・S・O のランプ（小さく縦に）
class CountAndBases extends StatelessWidget {
  final MatchState st;
  final bool finished;
  const CountAndBases({super.key, required this.st, this.finished = false});

  @override
  Widget build(BuildContext context) {
    final b0 = finished ? 0 : st.balls, s0 = finished ? 0 : st.strikes, o0 = finished ? 0 : st.outs.clamp(0, 2);
    Widget lamp(String l, int n, int max, Color on) => Row(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(width: 10, child: Text(l, style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)))),
          for (var i = 0; i < max; i++)
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.symmetric(horizontal: 1.2, vertical: 1),
              decoration: BoxDecoration(shape: BoxShape.circle, color: i < n ? on : const Color(0xFFE2E8F0), border: Border.all(color: Colors.black26, width: 0.6)),
            ),
        ]);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(width: 34, height: 34, child: CustomPaint(painter: _MiniDiamond(st.runner1B != null, st.runner2B != null, st.runner3B != null))),
      const SizedBox(width: 4),
      Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        lamp('B', b0, 3, const Color(0xFF4ADE80)),
        lamp('S', s0, 2, const Color(0xFFFACC15)),
        lamp('O', o0, 2, const Color(0xFFF87171)),
      ]),
    ]);
  }
}

class _MiniDiamond extends CustomPainter {
  final bool r1, r2, r3;
  _MiniDiamond(this.r1, this.r2, this.r3);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    void base(Offset c, bool on) {
      final p = Path()
        ..moveTo(c.dx, c.dy - s * 0.15)
        ..lineTo(c.dx + s * 0.15, c.dy)
        ..lineTo(c.dx, c.dy + s * 0.15)
        ..lineTo(c.dx - s * 0.15, c.dy)
        ..close();
      canvas.drawPath(p, Paint()..color = on ? const Color(0xFFFFD54F) : const Color(0xFF0A2A20));
      canvas.drawPath(p, Paint()..color = Colors.white70..style = PaintingStyle.stroke..strokeWidth = 1.2);
    }

    base(Offset(s * 0.5, s * 0.2), r2);
    base(Offset(s * 0.8, s * 0.5), r1);
    base(Offset(s * 0.2, s * 0.5), r3);
  }

  @override
  bool shouldRepaint(covariant _MiniDiamond old) => old.r1 != r1 || old.r2 != r2 || old.r3 != r3;
}

// =====================================================================
// アニメーションの時間配分
// =====================================================================

class PlayTiming {
  static const double pitch = 0.55;     // 投球（リリース→捕手）。アニメ上の秒
  static const double playSpeed = 1.7;  // 打球・走塁・送球は実時間の 1.7 倍速で再生
  /// 打った瞬間からプレーが終わるまでの実時間（秒）
  /// ホームランの一周は早回し（見ていて待たされないように）
  static const double hrTrotSpeed = 2.8;
  static double runScale(PitchEvent e) => e.outcome == 'ホームラン' ? hrTrotSpeed : 1.0;
  static double fieldReal(PitchEvent e) {
    if (e.path.isEmpty && e.runMoves.isEmpty) return 0;
    double t = e.flightTime;
    for (final m in e.runMoves) { t = max(t, m.t1 / runScale(e)); }
    for (final l in e.throwLegs) { t = max(t, l.t1); }
    return t + 0.6;
  }
  static double field(PitchEvent e) => fieldReal(e) / playSpeed;
  static double total(PitchEvent e) => pitch + field(e) + 0.3;
}

// =====================================================================
// 投球ビュー（捕手側から見た図）
// =====================================================================

class PitchView extends StatelessWidget {
  final List<PitchEvent> paEvents; // 現在の打席でこれまでに投げた球（アニメ中の球を除く）
  final PitchEvent? animating;     // 投げている途中の球
  final double t;                  // 経過秒
  final String batterHand;
  const PitchView({super.key, required this.paEvents, this.animating, this.t = 0, this.batterHand = 'R'});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _PitchPainter(paEvents, animating, t, batterHand), child: const SizedBox.expand());
  }
}

class _PitchPainter extends CustomPainter {
  final List<PitchEvent> evs;
  final PitchEvent? anim;
  final double t;
  final String hand;
  _PitchPainter(this.evs, this.anim, this.t, this.hand);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    canvas.drawRect(Offset.zero & size, Paint()..shader = const LinearGradient(colors: [Color(0xFF1E3A5F), Color(0xFF2F5D50)], begin: Alignment.topCenter, end: Alignment.bottomCenter).createShader(Offset.zero & size));
    canvas.drawRect(Rect.fromLTWH(0, h * 0.62, w, h * 0.38), Paint()..color = const Color(0xFFB7885A));
    canvas.drawRect(Rect.fromLTWH(0, h * 0.40, w, h * 0.22), Paint()..color = const Color(0xFF3F8F4F));
    canvas.drawOval(Rect.fromCenter(center: Offset(w * 0.5, h * 0.42), width: w * 0.22, height: h * 0.05), Paint()..color = const Color(0xFFC89B6D));
    _figure(canvas, Offset(w * 0.5, h * 0.40), h * 0.11, const Color(0xFFE5E7EB));

    final zc = Offset(w * 0.5, h * 0.66);
    final zw = min(w * 0.26, h * 0.30), zh = zw * 1.25;
    // PitchEvent の x は投手から見て右が＋。捕手側から見る図なので左右を反転する
    Offset map(double x, double z) => Offset(zc.dx - x * zw / 2, zc.dy - z * zh / 2);
    final zone = Rect.fromCenter(center: zc, width: zw, height: zh);
    canvas.drawRect(zone, Paint()..color = Colors.white.withOpacity(0.10));
    final grid = Paint()..color = Colors.white38..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      canvas.drawLine(Offset(zone.left + zone.width * i / 3, zone.top), Offset(zone.left + zone.width * i / 3, zone.bottom), grid);
      canvas.drawLine(Offset(zone.left, zone.top + zone.height * i / 3), Offset(zone.right, zone.top + zone.height * i / 3), grid);
    }
    canvas.drawRect(zone, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 2);
    final hp = Path()
      ..moveTo(zc.dx - zw * 0.5, h * 0.93)
      ..lineTo(zc.dx + zw * 0.5, h * 0.93)
      ..lineTo(zc.dx + zw * 0.5, h * 0.96)
      ..lineTo(zc.dx, h * 0.99)
      ..lineTo(zc.dx - zw * 0.5, h * 0.96)
      ..close();
    canvas.drawPath(hp, Paint()..color = Colors.white);
    final left = hand != 'L';
    _batter(canvas, Offset(left ? zc.dx - zw * 1.35 : zc.dx + zw * 1.35, h * 0.95), zh * 1.45, left);

    void dot(Offset c, Color col, String label) {
      canvas.drawCircle(c, 9, Paint()..color = col);
      canvas.drawCircle(c, 9, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 1.3);
      final tp = TextPainter(text: TextSpan(text: label, style: TextStyle(color: col == kStrikeColor ? Colors.black87 : Colors.white, fontSize: 10, fontWeight: FontWeight.bold)), textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
    }

    for (final e in evs) {
      if (e.pitchName == 'スクイズ') continue;
      dot(map(e.x.clamp(-2.4, 2.4).toDouble(), e.z.clamp(-2.4, 2.4).toDouble()), pitchResultColor(e), '${e.pitchNo}');
    }

    // 投げている球: リリース点から、変化球は曲がりながら手前に来る。通った道筋を点線で残す
    final e = anim;
    if (e != null && e.pitchName != 'スクイズ') {
      final p = (t / PlayTiming.pitch).clamp(0.0, 1.0);
      final release = Offset(w * 0.5, h * 0.36);
      final end = map(e.x.clamp(-2.4, 2.4).toDouble(), e.z.clamp(-2.4, 2.4).toDouble());
      // 曲がり（変化球ベクトル図と同じ向き）。終盤に大きく曲がる
      final bend = Offset(e.breakDX * zw * 0.9, e.breakDY * zh * 0.7);
      Offset at(double q) {
        final qq = q * q; // 手前ほど速く大きく見える
        final straight = Offset.lerp(release, end - bend, qq)!;
        return straight + bend * pow(qq, 2.2).toDouble();
      }

      final trail = Paint()..color = Colors.white70..strokeWidth = 1.6;
      for (double q = 0.05; q <= p; q += 0.05) {
        canvas.drawCircle(at(q), 1.0 + 1.5 * q * q, trail);
      }
      if (p < 1) {
        final pos = at(p);
        final r = 2.5 + 7.5 * p * p;
        canvas.drawCircle(pos, r, Paint()..color = Colors.white);
        canvas.drawCircle(pos, r, Paint()..color = Colors.red.shade300..style = PaintingStyle.stroke..strokeWidth = 1);
      } else {
        dot(end, pitchResultColor(e), '${e.pitchNo}');
      }
      final label = '${e.pitchName}  ${e.speed.toInt()}km/h';
      final tp = TextPainter(text: TextSpan(text: label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold, shadows: [Shadow(blurRadius: 3)])), textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, const Offset(8, 6));
      if (p >= 1 && e.result.isNotEmpty) {
        final rp = TextPainter(text: TextSpan(text: pitchResultLabel(e), style: TextStyle(color: pitchResultColor(e), fontSize: 16, fontWeight: FontWeight.w900, shadows: const [Shadow(blurRadius: 4)])), textDirection: TextDirection.ltr)..layout();
        rp.paint(canvas, Offset(w - rp.width - 8, 6));
      }
    }
    // 凡例
    final legend = [('ストライク', kStrikeColor), ('ボール', kBallColor), ('アウト', kOutColor), ('ヒット', kHitColor)];
    double lx = 8;
    for (final (name, col) in legend) {
      canvas.drawCircle(Offset(lx + 4, h - 10), 4, Paint()..color = col);
      final tp = TextPainter(text: TextSpan(text: name, style: const TextStyle(color: Colors.white, fontSize: 9.5)), textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, Offset(lx + 10, h - 16));
      lx += 16 + tp.width;
    }
  }

  void _figure(Canvas canvas, Offset feet, double height, Color color) {
    final p = Paint()..color = color;
    canvas.drawCircle(feet - Offset(0, height * 0.88), height * 0.12, p);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: feet - Offset(0, height * 0.5), width: height * 0.32, height: height * 0.55), Radius.circular(height * 0.08)), p);
    canvas.drawLine(feet - Offset(height * 0.08, height * 0.25), feet - Offset(height * 0.14, 0), p..strokeWidth = height * 0.08);
    canvas.drawLine(feet - Offset(-height * 0.08, height * 0.25), feet - Offset(-height * 0.14, 0), p);
  }

  void _batter(Canvas canvas, Offset feet, double height, bool leftSide) {
    final body = Paint()..color = const Color(0xFF1F2937);
    final dir = leftSide ? 1.0 : -1.0;
    canvas.drawCircle(feet - Offset(0, height * 0.86), height * 0.075, Paint()..color = const Color(0xFF2563EB));
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: feet - Offset(0, height * 0.55), width: height * 0.2, height: height * 0.42), Radius.circular(height * 0.05)), body);
    final leg = Paint()..color = const Color(0xFF374151)..strokeWidth = height * 0.06..strokeCap = StrokeCap.round;
    canvas.drawLine(feet - Offset(0, height * 0.34), feet + Offset(-height * 0.1, 0), leg);
    canvas.drawLine(feet - Offset(0, height * 0.34), feet + Offset(height * 0.1, 0), leg);
    final hands = feet - Offset(-dir * height * 0.06, height * 0.62);
    canvas.drawLine(hands, hands + Offset(-dir * height * 0.18, -height * 0.32), Paint()..color = const Color(0xFFD4A373)..strokeWidth = height * 0.035..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(covariant _PitchPainter old) => true;
}

// =====================================================================
// グラウンドビュー（本塁後方の高い位置から見下ろす遠近図）
//  打球（高さ・影）、処理する野手と塁に入る野手の動き、送球・中継、走者の走塁を再現する
// =====================================================================

class FieldPlayView extends StatelessWidget {
  final PitchEvent? event;        // アニメーション中（または直近）の打球
  final double t;                 // 経過秒（アニメ上。投球アニメの後から打球が動く）
  final bool r1, r2, r3;          // 現在（プレー後）の走者
  final List<bool> before;        // プレー前の走者 [一塁, 二塁, 三塁]
  final List<PitchEvent> recent;  // 直近の打球（落下点の履歴）
  const FieldPlayView({super.key, this.event, this.t = 0, this.r1 = false, this.r2 = false, this.r3 = false, this.before = const [false, false, false], this.recent = const []});

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _FieldPlayPainter(event, t, r1, r2, r3, before, recent), child: const SizedBox.expand());
}

class _Cam {
  // カメラ: 本塁の後方 40m・高さ 80m から、センター方向の地点を見下ろす
  static const cx = 0.0, cy = -40.0, cz = 80.0;
  static const tx = 0.0, ty = 62.0, tz = 0.0;
  late final double fx, fy, fz, ux, uy, uz;
  _Cam() {
    final dx = tx - cx, dy = ty - cy, dz = tz - cz;
    final l = sqrt(dx * dx + dy * dy + dz * dz);
    fx = dx / l; fy = dy / l; fz = dz / l;
    // up = right × forward（right = (1,0,0)）
    ux = 0; uy = -fz; uz = fy;
  }
  /// 投影（画面座標の単位なし値と奥行き）
  (double, double, double) proj(double x, double y, double z) {
    final vx = x - cx, vy = y - cy, vz = z - cz;
    final depth = vx * fx + vy * fy + vz * fz;
    final px = vx; // right=(1,0,0)
    final py = vx * ux + vy * uy + vz * uz;
    return (px / depth, py / depth, depth);
  }
}

class _FieldPlayPainter extends CustomPainter {
  final PitchEvent? e;
  final double t;
  final bool r1, r2, r3;
  final List<bool> before;
  final List<PitchEvent> recent;
  _FieldPlayPainter(this.e, this.t, this.r1, this.r2, this.r3, this.before, this.recent);

  static const _bases = [[0.0, 0.0], [19.4, 19.4], [0.0, 38.8], [-19.4, 19.4], [0.0, 0.0]];
  static final _cam = _Cam();

  @override
  void paint(Canvas canvas, Size size) {
    // 画面に収まるように、フェンスと本塁付近の投影範囲から拡大率を決める
    double minU = 1e9, maxU = -1e9, minV = 1e9, maxV = -1e9;
    void extend(double x, double y, double z) {
      final (u, v, _) = _cam.proj(x, y, z);
      minU = min(minU, u); maxU = max(maxU, u); minV = min(minV, v); maxV = max(maxV, v);
    }
    for (var a = -45.0; a <= 45.0; a += 5) {
      final r = PhysicsConstants.getFenceDistance(a);
      extend(r * sin(a * pi / 180), r * cos(a * pi / 180), 6);
    }
    extend(0, -6, 0);
    final scale = min(size.width / (maxU - minU), size.height / (maxV - minV)) * 0.98;
    final ox = (size.width - (maxU - minU) * scale) / 2 - minU * scale;
    final oy = (size.height - (maxV - minV) * scale) / 2 + maxV * scale;
    Offset p3(double x, double y, [double z = 0]) {
      final (u, v, _) = _cam.proj(x, y, z);
      return Offset(ox + u * scale, oy - v * scale);
    }
    double sizeAt(double x, double y) {
      final (_, _, d) = _cam.proj(x, y, 0);
      return (scale / d).clamp(0.5, 20.0);
    }

    // 空とスタンド
    canvas.drawRect(Offset.zero & size, Paint()..shader = const LinearGradient(colors: [Color(0xFF0F172A), Color(0xFF1E293B)], begin: Alignment.topCenter, end: Alignment.bottomCenter).createShader(Offset.zero & size));
    // フェンス（壁の上端まで）と外野の芝
    final ground = Path(), wallTop = <Offset>[], wallBottom = <Offset>[];
    for (var a = -45.0; a <= 45.0; a += 3) {
      final r = PhysicsConstants.getFenceDistance(a);
      final x = r * sin(a * pi / 180), y = r * cos(a * pi / 180);
      final b = p3(x, y, 0);
      wallBottom.add(b);
      wallTop.add(p3(x, y, PhysicsConstants.getFenceHeight(a)));
      if (a == -45.0) { ground.moveTo(b.dx, b.dy); } else { ground.lineTo(b.dx, b.dy); }
    }
    final home = p3(0, 0);
    ground.lineTo(home.dx, home.dy);
    ground.close();
    // スタンド（フェンスの外側）
    final stand = Path()..moveTo(wallTop.first.dx, wallTop.first.dy);
    for (final q in wallTop) { stand.lineTo(q.dx, q.dy); }
    stand.lineTo(wallTop.last.dx, 0);
    stand.lineTo(wallTop.first.dx, 0);
    stand.close();
    canvas.drawPath(stand, Paint()..color = const Color(0xFF334155));
    canvas.drawPath(ground, Paint()..color = const Color(0xFF2F8F46));
    // 芝目（同心円の帯）
    canvas.save();
    canvas.clipPath(ground);
    for (var r0 = 10.0; r0 < 130; r0 += 16) {
      final band = Path();
      for (var a = -50.0; a <= 50.0; a += 5) {
        final q = p3(r0 * sin(a * pi / 180), r0 * cos(a * pi / 180));
        if (a == -50.0) { band.moveTo(q.dx, q.dy); } else { band.lineTo(q.dx, q.dy); }
      }
      for (var a = 50.0; a >= -50.0; a -= 5) {
        final q = p3((r0 + 8) * sin(a * pi / 180), (r0 + 8) * cos(a * pi / 180));
        band.lineTo(q.dx, q.dy);
      }
      band.close();
      canvas.drawPath(band, Paint()..color = const Color(0xFF38A055).withOpacity(0.55));
    }
    canvas.restore();
    // 外野フェンス（壁）
    final wall = Path()..moveTo(wallBottom.first.dx, wallBottom.first.dy);
    for (final q in wallBottom) { wall.lineTo(q.dx, q.dy); }
    for (final q in wallTop.reversed) { wall.lineTo(q.dx, q.dy); }
    wall.close();
    canvas.drawPath(wall, Paint()..color = const Color(0xFF14532D));
    canvas.drawPath(wall, Paint()..color = const Color(0xFFFDE047).withOpacity(0.7)..style = PaintingStyle.stroke..strokeWidth = 1);
    // 内野の土（本塁を中心にした扇形）
    final dirt = Path();
    for (var a = -45.0; a <= 45.0; a += 3) {
      final q = p3(29.0 * sin(a * pi / 180), 29.0 * cos(a * pi / 180) + 0);
      if (a == -45.0) { dirt.moveTo(home.dx, home.dy); dirt.lineTo(q.dx, q.dy); } else { dirt.lineTo(q.dx, q.dy); }
    }
    dirt.close();
    canvas.drawPath(dirt, Paint()..color = const Color(0xFFC8925E));
    final grass = Path()
      ..moveTo(p3(0, 3).dx, p3(0, 3).dy)
      ..lineTo(p3(16.5, 19.4).dx, p3(16.5, 19.4).dy)
      ..lineTo(p3(0, 35.8).dx, p3(0, 35.8).dy)
      ..lineTo(p3(-16.5, 19.4).dx, p3(-16.5, 19.4).dy)
      ..close();
    canvas.drawPath(grass, Paint()..color = const Color(0xFF2F8F46));
    canvas.drawOval(Rect.fromCenter(center: p3(0, 18.44), width: 5.5 * sizeAt(0, 18.44), height: 3.2 * sizeAt(0, 18.44)), Paint()..color = const Color(0xFFC8925E));
    // ファウルライン・塁間
    final line = Paint()..color = Colors.white..strokeWidth = 1.4;
    final fd = PhysicsConstants.getFenceDistance(45);
    canvas.drawLine(home, p3(fd * sin(pi / 4), fd * cos(pi / 4)), line);
    canvas.drawLine(home, p3(-fd * sin(pi / 4), fd * cos(pi / 4)), line);
    final bl = Paint()..color = Colors.white70..strokeWidth = 1.0..style = PaintingStyle.stroke;
    final dia = Path()..moveTo(home.dx, home.dy);
    for (final b in _bases.skip(1)) { final q = p3(b[0], b[1]); dia.lineTo(q.dx, q.dy); }
    canvas.drawPath(dia, bl);
    for (final b in _bases.take(4)) {
      final c = p3(b[0], b[1]);
      final s = sizeAt(b[0], b[1]) * 0.9;
      canvas.drawRect(Rect.fromCenter(center: c, width: max(5.0, s * 1.2), height: max(3.5, s * 0.7)), Paint()..color = Colors.white);
    }

    // 直近の打球の落下点
    for (final b in recent) {
      if (b.landX == null || identical(b, e)) continue;
      canvas.drawCircle(p3(b.landX!, b.landY!), 3.2, Paint()..color = (isHitOutcome(b.outcome) ? kHitColor : kOutColor).withOpacity(0.75));
    }

    final ev = e;
    // 実時間（打った瞬間=0）
    final rt = ev == null ? -1.0 : (t - PlayTiming.pitch) * PlayTiming.playSpeed;
    final playing = ev != null && rt >= 0 && (ev.path.isNotEmpty || ev.runMoves.isNotEmpty);

    // ---- 守備位置: 打球を処理する野手は打球へ、送球を受ける野手はベースへ走る ----
    final starts = (ev != null && ev.fielderStart.isNotEmpty) ? ev.fielderStart : FielderAI().basePositions;
    final pos = {for (final k in starts.keys) k: [starts[k]![0], starts[k]![1]]};
    final active = <String>{};
    if (playing) {
      var endPt = ev.path.isNotEmpty ? ev.path.last : null;
      if (endPt != null && ev.outcome == 'ホームラン') {
        final a = atan2(endPt[0], endPt[1]);
        final r = PhysicsConstants.getFenceDistance((a * 180 / pi).clamp(-45.0, 45.0)) - 1.5;
        endPt = [r * sin(a), r * cos(a), 0];
      }
      if (endPt != null && ev.fielder.isNotEmpty && pos.containsKey(ev.fielder)) {
        final k = Curves.easeOut.transform(((rt - 0.15) / max(0.3, ev.flightTime - 0.15)).clamp(0.0, 1.0));
        final s = starts[ev.fielder]!;
        pos[ev.fielder] = [s[0] + (endPt[0] - s[0]) * k, s[1] + (endPt[1] - s[1]) * k];
        active.add(ev.fielder);
      }
      // 送球を受ける野手（各送球の到達点に一番近い野手）
      final used = <String>{ev.fielder};
      for (final l in ev.throwLegs) {
        String? who;
        double best = 1e9;
        starts.forEach((role, s) {
          if (used.contains(role)) return;
          final d = sqrt(pow(s[0] - l.x1, 2) + pow(s[1] - l.y1, 2));
          if (d < best) { best = d; who = role; }
        });
        if (who == null) continue;
        used.add(who!);
        final s = starts[who]!;
        final k = (rt / max(0.3, l.t1)).clamp(0.0, 1.0);
        pos[who!] = [s[0] + (l.x1 - s[0]) * k, s[1] + (l.y1 - s[1]) * k];
        active.add(who!);
      }
    }
    // 奥の野手から描く
    final order = pos.keys.toList()..sort((a, b) => pos[b]![1].compareTo(pos[a]![1]));
    for (final role in order) {
      final xy = pos[role]!;
      _fielder(canvas, p3(xy[0], xy[1]), sizeAt(xy[0], xy[1]), role, active.contains(role));
    }

    // ---- 走者 ----
    if (playing) {
      final moved = <int>{};
      for (final m in ev.runMoves) {
        if (m.from > 0) moved.add(m.from);
        final xy = _runnerAt(m, rt * PlayTiming.runScale(ev));
        if (xy == null) continue;
        final outNow = m.out && rt * PlayTiming.runScale(ev) >= m.t1;
        _runner(canvas, p3(xy[0], xy[1]), sizeAt(xy[0], xy[1]), outNow);
      }
      for (int b = 1; b <= 3; b++) {
        if (before[b - 1] && !moved.contains(b)) {
          final bp = _bases[b];
          _runner(canvas, p3(bp[0], bp[1]), sizeAt(bp[0], bp[1]), false);
        }
      }
    } else {
      final occ = [r1, r2, r3];
      for (int b = 1; b <= 3; b++) {
        if (!occ[b - 1]) continue;
        final bp = _bases[b];
        _runner(canvas, p3(bp[0], bp[1]), sizeAt(bp[0], bp[1]), false);
      }
    }

    if (!playing) return;
    // ---- ボール: 打球 → （野手が持つ）→ 送球・中継 ----
    // スタンドの高さ（フェンスの外ほど高い）。フェンスを越えた打球はスタンドに落ちたところで止める
    double standZ(double x, double y) {
      final a = atan2(x, y) * 180 / pi;
      final over = sqrt(x * x + y * y) - PhysicsConstants.getFenceDistance(a.clamp(-45.0, 45.0));
      return over <= 0 ? 0 : PhysicsConstants.getFenceHeight(a.clamp(-45.0, 45.0)) + over * 0.45;
    }

    var path = ev.path;
    var flight = ev.flightTime;
    for (var i = 1; i < path.length; i++) {
      final sz = standZ(path[i][0], path[i][1]);
      if (sz > 0 && path[i][2] <= sz) {
        flight = ev.flightTime * i / max(1, ev.path.length - 1);
        path = [...path.take(i), [path[i][0], path[i][1], sz]];
        break;
      }
    }
    List<double>? ball; // x, y, z
    if (path.isNotEmpty && rt <= flight) {
      final k = (rt / max(0.05, flight)).clamp(0.0, 1.0) * (path.length - 1);
      final i = k.floor().clamp(0, path.length - 1);
      final j = min(i + 1, path.length - 1);
      final f = k - i;
      ball = [
        path[i][0] + (path[j][0] - path[i][0]) * f,
        path[i][1] + (path[j][1] - path[i][1]) * f,
        path[i][2] + (path[j][2] - path[i][2]) * f,
      ];
      // 軌跡（地面の影の線と、空中の線）
      final shadowTrail = Path()..moveTo(home.dx, home.dy);
      final airTrail = Path()..moveTo(home.dx, home.dy);
      for (var q = 0; q <= i; q++) {
        final g = p3(path[q][0], path[q][1], standZ(path[q][0], path[q][1]));
        final a = p3(path[q][0], path[q][1], path[q][2]);
        shadowTrail.lineTo(g.dx, g.dy);
        airTrail.lineTo(a.dx, a.dy);
      }
      canvas.drawPath(shadowTrail, Paint()..color = Colors.black.withOpacity(0.25)..style = PaintingStyle.stroke..strokeWidth = 1.5);
      canvas.drawPath(airTrail, Paint()..color = Colors.white.withOpacity(0.55)..style = PaintingStyle.stroke..strokeWidth = 1.5);
    } else if (path.isNotEmpty || ev.throwLegs.isNotEmpty) {
      // 送球中か、送球を待っている野手が持っている
      ThrowLeg? cur;
      ThrowLeg? last;
      for (final l in ev.throwLegs) {
        if (rt >= l.t0 && rt <= l.t1) cur = l;
        if (rt > l.t1) last = l;
      }
      if (cur != null) {
        final k = ((rt - cur.t0) / max(0.05, cur.t1 - cur.t0)).clamp(0.0, 1.0);
        final dist = sqrt(pow(cur.x1 - cur.x0, 2) + pow(cur.y1 - cur.y0, 2));
        final arc = (dist * 0.06).clamp(0.5, 6.0) * 4 * k * (1 - k);
        ball = [cur.x0 + (cur.x1 - cur.x0) * k, cur.y0 + (cur.y1 - cur.y0) * k, 1.5 + arc];
        final from = p3(cur.x0, cur.y0, 1.5);
        final to = p3(ball[0], ball[1], ball[2]);
        canvas.drawLine(from, to, Paint()..color = Colors.white60..strokeWidth = 1.2);
      } else if (last != null) {
        ball = [last.x1, last.y1, 1.2];
      } else if (path.isNotEmpty && ev.outcome != 'ホームラン') {
        ball = [path.last[0], path.last[1], 1.2];
      }
    }
    if (ball != null) {
      final gz = standZ(ball[0], ball[1]);
      final g = p3(ball[0], ball[1], gz);
      final s = sizeAt(ball[0], ball[1]);
      canvas.drawOval(Rect.fromCenter(center: g, width: max(4.0, s * 0.9), height: max(2.5, s * 0.5)), Paint()..color = Colors.black.withOpacity(0.45));
      final a = p3(ball[0], ball[1], ball[2]);
      if (ball[2] - gz > 2.0) canvas.drawLine(a, g, Paint()..color = Colors.white.withOpacity(0.35)..strokeWidth = 0.8);
      final br = max(2.6, s * 0.38);
      canvas.drawCircle(a, br, Paint()..color = Colors.white);
      canvas.drawCircle(a, br, Paint()..color = Colors.black54..style = PaintingStyle.stroke..strokeWidth = 0.8);
    }
    // 結果表示（プレーの後半）
    if (rt > ev.flightTime + 0.2) {
      final txt = ev.playCode.isNotEmpty && ev.outcome == '併殺' ? '併殺 ${ev.playCode}' : ev.outcome;
      final col = ev.outcome == 'ホームラン' ? const Color(0xFFF87171) : (isHitOutcome(ev.outcome) ? kHitColor : kOutColor);
      final tp = TextPainter(text: TextSpan(text: txt, style: TextStyle(color: col, fontSize: 18, fontWeight: FontWeight.w900, shadows: const [Shadow(blurRadius: 4, color: Colors.black)])), textDirection: TextDirection.ltr)..layout();
      final bg = RRect.fromRectAndRadius(Rect.fromLTWH(size.width / 2 - tp.width / 2 - 8, 6, tp.width + 16, tp.height + 4), const Radius.circular(6));
      canvas.drawRRect(bg, Paint()..color = Colors.white.withOpacity(0.85));
      tp.paint(canvas, Offset(size.width / 2 - tp.width / 2, 8));
    }
  }

  /// 走者の位置（塁間を進む）。アウトになった走者は少し残して消す
  List<double>? _runnerAt(RunMove m, double rt) {
    if (m.out && rt > m.t1 + 0.8) return null;
    if (!m.out && m.to == 4 && rt > m.t1 + 0.6) return null; // 生還した走者は本塁を駆け抜けて消える
    final k = ((rt - m.t0) / max(0.05, m.t1 - m.t0)).clamp(0.0, 1.0);
    final legs = (m.to - m.from).toDouble();
    if (legs <= 0) return [_bases[m.from][0], _bases[m.from][1]];
    final s = k * legs;
    final i = s.floor().clamp(0, m.to - m.from - 1);
    final f = s - i;
    final a = _bases[m.from + i], b = _bases[m.from + i + 1];
    return [a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f];
  }

  void _fielder(Canvas canvas, Offset c, double s, String role, bool active) {
    final r = max(4.0, s * 0.75);
    canvas.drawOval(Rect.fromCenter(center: c + Offset(0, r * 0.6), width: r * 2, height: r * 0.8), Paint()..color = Colors.black38);
    final body = c - Offset(0, r * 0.9);
    canvas.drawCircle(body, r, Paint()..color = active ? const Color(0xFFFFD54F) : const Color(0xFF3B82F6));
    canvas.drawCircle(body, r, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 1.1);
    final tp = TextPainter(text: TextSpan(text: role, style: TextStyle(color: Colors.white, fontSize: max(7.5, r * 0.95), fontWeight: FontWeight.bold, shadows: const [Shadow(blurRadius: 2)])), textDirection: TextDirection.ltr)..layout();
    tp.paint(canvas, body + Offset(r + 1, -tp.height / 2));
  }

  void _runner(Canvas canvas, Offset c, double s, bool out) {
    final r = max(4.0, s * 0.7);
    final body = c - Offset(0, r * 0.9);
    canvas.drawOval(Rect.fromCenter(center: c + Offset(0, r * 0.5), width: r * 1.8, height: r * 0.7), Paint()..color = Colors.black38);
    canvas.drawCircle(body, r, Paint()..color = out ? Colors.grey : const Color(0xFFEF4444));
    canvas.drawCircle(body, r, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 1.1);
    if (out) {
      final tp = TextPainter(text: const TextSpan(text: 'OUT', style: TextStyle(color: Color(0xFFEF4444), fontSize: 10, fontWeight: FontWeight.w900, shadows: [Shadow(blurRadius: 2, color: Colors.white)])), textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, body - Offset(tp.width / 2, r + tp.height + 1));
    }
  }

  @override
  bool shouldRepaint(covariant _FieldPlayPainter old) => true;
}

/// 打者・投手の短い紹介
String batterSummary(Player p, int slot) => '${slot + 1}番 ${p.lastName}${p.firstName.isNotEmpty ? ' ${p.firstName}' : ''}  ${p.bats == 'L' ? '左' : (p.bats == 'S' ? '両' : '右')}打  ミ${p.contact} パ${p.power} 走${p.run}  今季 ${p.seasonStats.battingAverage.toStringAsFixed(3).replaceFirst('0.', '.')} ${p.seasonStats.homeRuns}本';
String pitcherSummary(Player p, int pitches) => '${p.lastName}${p.firstName.isNotEmpty ? ' ${p.firstName}' : ''}  ${p.throws == 'L' ? '左' : '右'}投  $pitches球  球速${p.velocity} 制${p.control} スタ${p.stamina}';

// =====================================================================
// 変化の詳細（横から見た図と上から見た図）
//  点線＝変化しなかった場合の軌道、実線＝実際の軌道。曲がり始めの位置と最終的な変化量（目安）を出す
// =====================================================================

/// 変化量（breakDX/DY の大きさ1.0）を何cmとして表示するか。投球アニメの曲がり幅と合わせた目安
const double kBreakCmPerUnit = 40;

class PitchBreakView extends StatelessWidget {
  final PitchEvent? event;
  final double progress; // 0〜1（投げている途中なら途中まで描く）
  const PitchBreakView({super.key, required this.event, this.progress = 1});

  @override
  Widget build(BuildContext context) {
    final e = event;
    if (e == null || e.pitchName == 'スクイズ') {
      return const Center(child: Text('投球が始まると変化の軌道を表示します', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF8EA3BF), fontSize: 12)));
    }
    // 捕手から見て右が＋になるよう、投球アニメと同じ向きで表示する
    final hx = (e.breakDX * kBreakCmPerUnit).round();
    final vy = (e.breakDY * kBreakCmPerUnit).round();
    final hText = hx == 0 ? '横 0cm' : '横 ${hx > 0 ? '→' : '←'}${hx.abs()}cm';
    final vText = vy == 0 ? '縦 0cm' : '縦 ${vy > 0 ? '↓' : '↑'}${vy.abs()}cm';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: Text('${e.pitchNo}球目  ${e.pitchName}', overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13))),
        Text('${e.speed.toInt()}km/h', style: const TextStyle(color: Color(0xFFC6F24E), fontWeight: FontWeight.w800, fontSize: 13)),
      ]),
      const SizedBox(height: 2),
      Text('$hText　$vText（目安）', style: const TextStyle(color: Color(0xFFB8C6D8), fontSize: 11.5)),
      const SizedBox(height: 4),
      Expanded(child: _diagram('横から', CustomPaint(painter: _BreakPainter(e, progress, side: true), child: const SizedBox.expand()))),
      const SizedBox(height: 4),
      Expanded(child: _diagram('上から', CustomPaint(painter: _BreakPainter(e, progress, side: false), child: const SizedBox.expand()))),
    ]);
  }

  Widget _diagram(String label, Widget child) => Container(
        decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(6), border: Border.all(color: const Color(0xFFCBD5E1))),
        child: Stack(children: [
          Positioned.fill(child: child),
          Positioned(left: 6, top: 3, child: Text(label, style: const TextStyle(color: Color(0xFF8EA3BF), fontSize: 10))),
        ]),
      );
}

class _BreakPainter extends CustomPainter {
  final PitchEvent e;
  final double progress;
  final bool side; // true=横から（縦の変化）/ false=上から（横の変化）
  _BreakPainter(this.e, this.progress, {required this.side});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final x0 = w * 0.08, x1 = w * 0.90; // 投手 → 本塁
    final mid = h * 0.55;
    // 縦・横の軸の倍率（変化量1.0 → 高さの35%）
    final amp = h * 0.35;
    // 到達点（ゾーン座標）。横から＝高さ z、上から＝左右 x（捕手から見た向きに反転）
    final endOff = side ? -e.z.clamp(-2.0, 2.0) * h * 0.14 : e.x.clamp(-2.0, 2.0) * h * 0.14;
    // breakDY は＋が落ちる向き、breakDX は＋が捕手から見て右（上から見た図では画面の上）
    final bend = side ? e.breakDY * amp : -e.breakDX * amp;
    final start = Offset(x0, side ? h * 0.30 : mid);
    final end = Offset(x1, mid + endOff);
    // 投球アニメと同じ曲がり方（終盤に大きく曲がる）
    Offset at(double q) {
      final straight = Offset.lerp(start, end - Offset(0, bend), q)!;
      return straight + Offset(0, bend * pow(q, 2.2).toDouble());
    }

    // 地面・ゾーンの目印
    final guide = Paint()..color = const Color(0xFF1E3350)..strokeWidth = 1;
    if (side) {
      canvas.drawLine(Offset(0, h * 0.92), Offset(w, h * 0.92), guide);
      // ストライクゾーンの高さ
      final zt = mid - h * 0.14, zb = mid + h * 0.14;
      canvas.drawRect(Rect.fromLTRB(x1 - 3, zt, x1 + 3, zb), Paint()..color = const Color(0x558EA3BF));
    } else {
      final zl = mid - h * 0.14, zr = mid + h * 0.14;
      canvas.drawRect(Rect.fromLTRB(x1 - 3, zl, x1 + 3, zr), Paint()..color = const Color(0x558EA3BF));
    }
    // 投手と本塁
    canvas.drawCircle(start, 3.5, Paint()..color = const Color(0xFF8EA3BF));
    _label(canvas, '投', Offset(x0 - 4, side ? h * 0.30 + 6 : mid + 6));
    _label(canvas, '本塁', Offset(x1 - 10, h - 13));

    // 変化しなかった場合（点線）
    final straightEnd = end - Offset(0, bend);
    final dash = Paint()..color = Colors.white38..strokeWidth = 1.2;
    const n = 26;
    for (int i = 0; i < n; i += 2) {
      canvas.drawLine(Offset.lerp(start, straightEnd, i / n)!, Offset.lerp(start, straightEnd, (i + 1) / n)!, dash);
    }
    // 実際の軌道（途中まで）
    final col = e.result.isEmpty || progress < 1 ? Colors.white : pitchResultColor(e);
    final path = Path()..moveTo(start.dx, start.dy);
    final pmax = progress.clamp(0.0, 1.0);
    for (double q = 0.02; q <= pmax + 1e-9; q += 0.02) {
      final p = at(q);
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path, Paint()..color = col..style = PaintingStyle.stroke..strokeWidth = 2.4..strokeCap = StrokeCap.round);
    final head = at(pmax);
    canvas.drawCircle(head, 4.5, Paint()..color = col);
    // 変化量の矢印（到達後）
    if (pmax >= 1 && bend.abs() > 2) {
      final a = Paint()..color = const Color(0xFFC6F24E)..strokeWidth = 1.4;
      canvas.drawLine(Offset(x1 + 8, straightEnd.dy), Offset(x1 + 8, end.dy), a);
      final dir = end.dy > straightEnd.dy ? 1.0 : -1.0;
      canvas.drawLine(Offset(x1 + 8, end.dy), Offset(x1 + 5, end.dy - dir * 4), a);
      canvas.drawLine(Offset(x1 + 8, end.dy), Offset(x1 + 11, end.dy - dir * 4), a);
      // 曲がり始め（変化の半分を超えるあたり）
      final kink = at(0.55);
      canvas.drawCircle(kink, 2.5, Paint()..color = const Color(0xFFC6F24E));
    }
  }

  void _label(Canvas canvas, String s, Offset o) {
    final tp = TextPainter(text: TextSpan(text: s, style: const TextStyle(color: Color(0xFF8EA3BF), fontSize: 9.5)), textDirection: TextDirection.ltr)..layout();
    tp.paint(canvas, o);
  }

  @override
  bool shouldRepaint(covariant _BreakPainter old) => old.e != e || old.progress != progress;
}
