import '../models/player.dart';
import 'pitch_catalog.dart';

/// 改修5.1：AI なしでも読める「体格 × フォーム × 球種の握り（キレ・重さ・変化量）× 成績」を組み合わせたスカウト寸評
///  例：「身長188cmの恵まれた体格と長いリーチから、角度のある154km/hの重いストレートを投げ下ろす本格派右腕。…」
class ScoutComment {
  static String _rate(double v) => v.toStringAsFixed(3).replaceFirst('0.', '.');

  /// 変化量を 1〜7 の段階で（パワプロの変化量の感覚）
  static int breakStep(int breakLevel) => (breakLevel / 14.3).round().clamp(1, 7);

  static String pitcher(Player p) {
    final hand = p.throws == 'L' ? '左腕' : '右腕';
    final h = p.height;
    final slot = p.armSlot;
    final tall = h >= 186, small = h <= 172;
    final body = tall
        ? '身長${h}cmの恵まれた体格${p.armLength >= 75 ? 'と長いリーチ' : ''}から'
        : (small ? '身長${h}cmと小柄ながら、全身を大きく使ったフォームから' : '${p.weight >= 92 ? 'がっしりとした体格から' : 'しなやかな腕の振りから'}');
    final fast = p.pitches.where((x) => PitchCatalog.isFastLike(x)).toList();
    final st = fast.isEmpty ? null : fast.first;
    final adj = [
      if (slot == 'オーバー' && tall) '角度のある',
      if (slot == 'サイド') '横手から右打者の外へ逃げる軌道の',
      if (slot == 'アンダー') '下手から浮き上がるような',
      if (st != null && st.heaviness >= 70) '重い',
      if (st != null && st.sharpness >= 72 && (st.heaviness < 70)) '手元で伸びる',
    ].join('、');
    final verb = slot == 'オーバー' && tall ? '投げ下ろす' : (slot == 'アンダー' || slot == 'サイド' ? '投げ込む' : '投げ込む');
    final style = p.velocity >= 150 && p.pitchPower >= 65
        ? '本格派'
        : (p.control >= 72 ? '制球力で勝負する技巧派' : (p.velocity < 140 ? '緩急で打たせて取る軟投派' : '力で押す'));
    final shift = p.styleShift == '技巧派' ? '（ベテランになって技巧派に転向）' : '';
    final lines = <String>['$body、$adj${p.velocity}km/hの${st?.name ?? 'ストレート'}を$verb$style$hand$shift。'];
    final brk = p.pitches.where((x) => !PitchCatalog.isFastLike(x) && x.breakLevel > 0).toList()..sort((a, b) => (b.breakLevel + b.sharpness).compareTo(a.breakLevel + a.sharpness));
    if (brk.isNotEmpty) {
      final b = brk.first;
      final kind = b.sharpness >= 70 ? '手元で鋭く変化するキレ味抜群の' : (b.breakLevel >= 70 ? '大きく曲がる' : '');
      final s = p.seasonStats;
      final kRate = s.inningsPitched >= 60 ? s.pitcherStrikeouts / (s.inningsPitched / 3) : 0.0;
      final res = kRate >= 1.0 ? 'で三振の山を築く' : (b.sharpness >= 70 ? 'は空振り率が高い' : 'でカウントを整える');
      lines.add('特に$kind${b.name}（変化量${breakStep(b.breakLevel)}）$res${brk.length >= 3 ? '。ほかに${brk.skip(1).take(2).map((x) => x.name).join('・')}も操る' : ''}。');
    }
    if (p.clutchPitching >= 70) {
      lines.add('ピンチの場面でも動じない精神力を持つ。');
    } else if (p.control < 50) {
      lines.add('制球にばらつきがあり、四球から崩れる場面もある。');
    }
    lines.add(p.stamina >= 68 ? '長いイニングを任せられるスタミナがある。' : (p.stamina < 45 ? '短いイニングで全力を出すリリーフ向き。' : ''));
    final s = p.seasonStats;
    if (s.inningsPitched >= 45) {
      final hr9 = s.hrAllowed / (s.inningsPitched / 3) * 9;
      final bb9 = s.pitcherWalks / (s.inningsPitched / 3) * 9;
      lines.add('今季は防御率${s.era.toStringAsFixed(2)}${bb9 < 2.2 ? '、与四球率${bb9.toStringAsFixed(1)}と制球が安定' : ''}${hr9 >= 1.3 ? '。被本塁打が多く、一発に課題' : ''}。');
    }
    return lines.where((l) => l.isNotEmpty).join('');
  }

  static String batter(Player p) {
    final pos = p.mainPosition.replaceAll('手', '');
    final b = p.bat, g = p.glove;
    final contact = p.contact;
    final grip = b.choke > 0 || b.balance == 'カウンター' ? 'バットを短く持ち、' : (b.balance == 'トップ' && b.weight >= 920 ? '重いトップバランスのバットを振り抜き、' : '');
    String type;
    if (p.power >= 75 && p.trajectory >= 3) {
      type = '${grip}高い弾道で外野の頭を越える打球を放つ長距離砲の$pos手';
    } else if (contact >= 72 && p.eye >= 68) {
      type = '${grip.startsWith('重い') ? '' : grip}卓越した選球眼とミート力で広角にライナーを打ち分ける巧打の$pos手';
    } else if (contact >= 72) {
      type = '${grip}バットコントロールにすぐれた好打の$pos手';
    } else if (p.run >= 78) {
      type = '${grip.startsWith('重い') ? '' : grip}俊足を生かして内野安打をもぎ取るスピードスターの$pos手';
    } else if (p.power >= 68) {
      type = '${grip}一発のある中距離打者の$pos手';
    } else {
      type = '${grip}粘り強い打撃が持ち味の$pos手';
    }
    if (p.styleShift == '職人') type += '（ベテランになって職人肌に転向）';
    final lines = <String>['$type。'];
    // 守備（用具まで）
    if ((p.mainPosition == '二塁手' || p.mainPosition == '遊撃手') && g.pocket == '浅い') {
      lines.add('ポケットの浅い小型グラブを操る握り替えの速さ${p.catchSkill >= 70 ? 'はリーグ屈指で' : 'で'}、併殺奪取に貢献している。');
    } else if (p.arm >= 75 && p.throwAccuracy >= 65) {
      lines.add('強肩・正確な送球で、走者の進塁を許さない。');
    } else if (p.catchSkill >= 72) {
      lines.add('堅実な守備で投手陣を助ける。');
    } else if (p.catchSkill < 45) {
      lines.add('守備には課題が残る。');
    }
    if (p.run >= 75 && !lines.first.contains('俊足')) lines.add('足も速く、次の塁を積極的に狙う。');
    // 成績
    final s = p.seasonStats;
    if (s.plateAppearances >= 120) {
      final k = s.strikeouts / s.plateAppearances, bb = s.walks / s.plateAppearances;
      final risp = s.rispAB >= 25 ? s.rispH / s.rispAB : null;
      final parts = <String>['今季は打率${_rate(s.battingAverage)}・${s.homeRuns}本塁打'];
      if (risp != null && risp >= 0.320) parts.add('得点圏打率${_rate(risp)}と勝負強い');
      if (risp != null && risp < 0.200) parts.add('得点圏では${_rate(risp)}と好機で結果を残せていない');
      if (bb >= 0.12) parts.add('四球を選べる');
      if (k >= 0.25) parts.add('三振の多さ（三振率${(k * 100).round()}%）が課題');
      lines.add('${parts.join('、')}。');
    } else if (p.clutch >= 72) {
      lines.add('チャンスに強い。');
    }
    return lines.join('');
  }

  static String of(Player p) => p.isPitcher ? pitcher(p) : batter(p);
}
