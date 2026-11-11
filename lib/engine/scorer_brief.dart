import 'dart:math' as m;

import '../models/player.dart';

/// スコアラーの 1 球の記録（保存してある今季の 1 球ごとの記録と、この試合の 1 球から作る）
class ScoutPitch {
  final String pitcher, batter, hand, pitch, result;
  final double x, z; // x は打者の内角が＋になるよう直した値
  final int pitchNo, balls, strikes;
  final double? landX, landY;
  ScoutPitch({required this.pitcher, required this.batter, required this.hand, required this.pitch, required this.result, required double rawX, required this.z, required this.pitchNo, required this.balls, required this.strikes, this.landX, this.landY})
      : x = hand == 'L' ? -rawX : rawX;

  bool get strike => result != 'ボール' && result != '死球';
  bool get swing => result == '空振り' || result == 'ファウル' || result == 'インプレー';
  bool get fast => pitch.contains('ストレート') || pitch.contains('ツーシーム') || pitch.contains('シュート') || pitch.contains('カット');
}

/// 試合中の采配画面に出す、スコアラーの 1〜2 行の助言（エンジンの配球・打者の傾向を、記録から数える）
class ScorerBrief {
  static String _zone(ScoutPitch p) {
    final w = p.x > 0.33 ? '内角' : (p.x < -0.33 ? '外角' : '');
    final h = p.z > 0.33 ? '高め' : (p.z < -0.33 ? '低め' : '');
    return (w.isEmpty && h.isEmpty) ? '真ん中' : '$w$h';
  }

  static String _pct(num v) => '${(v * 100).round()}%';

  /// 攻撃中：相手投手の配球（初球のストライク率と中心の球、2 ストライク後の決め球）
  static String pitcher(List<ScoutPitch> all, Player p) {
    final rows = all.where((r) => r.pitcher == p.registeredName).toList();
    if (rows.length < 25) {
      // 記録が少ない：持ち球の割合から
      final ps = [...p.pitches]..sort((a, b) => b.ratio.compareTo(a.ratio));
      final mix = ps.take(3).map((x) => '${x.name}${x.ratio}%').join('・');
      return '📊 スコアラー：${p.registeredName}は対戦データが少ない（${rows.length}球）。持ち球は$mix${p.control >= 70 ? '。制球が良く、初球から積極的にストライクを取りに来る' : (p.control < 50 ? '。制球に不安があり、甘い球を待てる' : '')}';
    }
    final first = rows.where((r) => r.pitchNo == 1).toList();
    final fs = first.isEmpty ? 0.0 : first.where((r) => r.strike).length / first.length;
    final ff = first.isEmpty ? 0.0 : first.where((r) => r.fast).length / first.length;
    final fin = first.isEmpty ? 0.0 : first.where((r) => r.x > 0.33).length / first.length;
    final style = ff >= 0.55 ? (fin >= 0.4 ? '内角速球中心' : '速球中心') : '変化球から入る';
    final two = rows.where((r) => r.strikes == 2).toList();
    var tail = '';
    if (two.length >= 8) {
      final cnt = <String, int>{};
      for (final r in two) {
        final k = '${_zone(r)}${r.pitch}';
        cnt[k] = (cnt[k] ?? 0) + 1;
      }
      final top = cnt.entries.reduce((a, b) => a.value >= b.value ? a : b);
      final byPitch = <String, int>{};
      for (final r in two) {
        byPitch[r.pitch] = (byPitch[r.pitch] ?? 0) + 1;
      }
      final tp = byPitch.entries.reduce((a, b) => a.value >= b.value ? a : b);
      tail = top.value / two.length >= 0.3 ? '。2ストライク後は${top.key}が${_pct(top.value / two.length)}' : '。2ストライク後は${tp.key}が${_pct(tp.value / two.length)}';
    }
    return '📊 スコアラー：相手投手は初球ストライク率${_pct(fs)}（$style）$tail';
  }

  /// 守備中：相手打者の傾向（打球の方向、高めの速球への空振り、苦手なコース）
  static String batter(List<ScoutPitch> all, Player b) {
    final rows = all.where((r) => r.batter == b.registeredName).toList();
    final bip = rows.where((r) => r.result == 'インプレー' && r.landX != null && r.landY != null && (r.landX!.abs() + r.landY!.abs()) > 5).toList();
    if (rows.length < 25 || bip.length < 6) {
      final c = (b.contactLeft + b.contactRight) / 2;
      final type = b.power >= 70 ? '長打力があり、甘い球は一発に注意' : (c >= 70 ? '巧打者で、広角に打ち返してくる' : (b.eye >= 65 ? '選球眼が良く、ボール球には手を出さない' : '積極的に振ってくる'));
      return '📊 スコアラー：${b.registeredName}は対戦データが少ない（${rows.length}球）。$type';
    }
    // 引っ張り：右打者は左方向（x が三塁側＝負）、左打者は右方向
    var pull = 0, oppo = 0;
    for (final r in bip) {
      final ang = m.atan2(r.landX!, r.landY!) * 180 / m.pi; // ＋＝一塁側
      final toLeft = ang < -15, toRight = ang > 15;
      final pulled = r.hand == 'L' ? toRight : toLeft;
      final opposite = r.hand == 'L' ? toLeft : toRight;
      if (pulled) pull++;
      if (opposite) oppo++;
    }
    final side = bip.first.hand == 'L' ? '右方向' : '左方向';
    final pr = pull / bip.length;
    final dir = pr >= 0.5 ? '引っ張り傾向強（$side${_pct(pr)}）' : (oppo / bip.length >= 0.35 ? '逆方向にも打てる（逆方向${_pct(oppo / bip.length)}）' : '広角に打つ（$side${_pct(pr)}）');
    final hi = rows.where((r) => r.fast && r.z > 0.33 && r.swing).toList();
    final hiWhiff = hi.isEmpty ? null : hi.where((r) => r.result == '空振り').length / hi.length;
    // 空振りが多いコース
    final zw = <String, (int, int)>{};
    for (final r in rows.where((r) => r.swing)) {
      final k = _zone(r);
      final v = zw[k] ?? (0, 0);
      zw[k] = (v.$1 + (r.result == '空振り' ? 1 : 0), v.$2 + 1);
    }
    final weak = zw.entries.where((e) => e.value.$2 >= 6).toList()..sort((a, b) => (b.value.$1 / b.value.$2).compareTo(a.value.$1 / a.value.$2));
    final parts = <String>[dir];
    if (hiWhiff != null && hi.length >= 5) parts.add('高めの速球に対して空振り率${_pct(hiWhiff)}');
    if (weak.isNotEmpty && weak.first.key != '真ん中') parts.add('${weak.first.key}の空振り率${_pct(weak.first.value.$1 / weak.first.value.$2)}');
    return '📊 スコアラー：この打者は${parts.take(2).join('。')}';
  }
}
