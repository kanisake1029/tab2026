import 'dart:math';
import '../models/player.dart';

/// 守備適性の生成（新しい球団・ドラフト・新外国人・他リーグ）。本職は平均63（±9、45〜92）：多くは D〜B、ときどき A。E（45〜49）は守備がかなり苦手な選手
///  型のサブポジション（本職の0.8〜1.0倍）に加えて、ランダムに2つの守備位置を F（35〜50）で守れる（捕手は除く）
///  本職の型ごとに、ほかの守備位置も最低2つは本職×0.8〜1.0 の適性を持つ（それ以上持つこともある）
///   ホットコーナー型（一塁・三塁）：一塁・三塁・左翼・右翼から本職以外を2つ以上
///   内野手型（二塁・遊撃）：一塁・二塁・遊撃・三塁から本職以外を2つ以上
///   外野手型：中堅・右翼は残りの外野2つ、左翼は右翼＋（中堅か一塁）
///   捕手型：三塁・一塁・左翼・右翼から2つ
///  それ以外の守備位置（守れない）と、野手の投手適性は G1（二刀流は別）
class FieldingGen {
  static const positions = ['捕手', '一塁手', '二塁手', '三塁手', '遊撃手', '左翼手', '中堅手', '右翼手'];

  static double _g(Random r) => sqrt(-2 * log(1 - r.nextDouble())) * cos(2 * pi * r.nextDouble());

  /// 本職以外で、本職×0.8〜1.0 の適性を持つ守備位置の候補と、最低いくつ選ぶか
  static (List<String>, int) _subs(String mainPos, Random r) {
    switch (mainPos) {
      case '一塁手' || '三塁手':
        return (['一塁手', '三塁手', '左翼手', '右翼手'].where((p) => p != mainPos).toList(), 2);
      case '二塁手' || '遊撃手':
        return (['一塁手', '二塁手', '遊撃手', '三塁手'].where((p) => p != mainPos).toList(), 2);
      case '中堅手':
        return (['左翼手', '右翼手'], 2);
      case '右翼手':
        return (['左翼手', '中堅手'], 2);
      case '左翼手':
        return (['右翼手', r.nextBool() ? '中堅手' : '一塁手'], 2);
      case '捕手':
        return (['三塁手', '一塁手', '左翼手', '右翼手'], 2);
    }
    return (const <String>[], 0);
  }

  /// メインポジションの適性が G1（守れない）なのに、ほかに得意な位置がある選手は、いちばん得意な位置をメインにする（以前に作った外国人など）
  static bool fixMainPos(Player p) {
    if (p.isPitcher) return false;
    final apt = {
      '捕手': p.fieldC, '一塁手': p.field1B, '二塁手': p.field2B, '三塁手': p.field3B,
      '遊撃手': p.fieldSS, '左翼手': p.fieldLF, '中堅手': p.fieldCF, '右翼手': p.fieldRF,
    };
    final cur = apt[p.mainPosition] ?? 0;
    final best = apt.entries.reduce((a, b) => a.value >= b.value ? a : b);
    if (cur > 10 || best.value <= 20) return false;
    p.mainPos = best.key;
    return true;
  }

  /// 守備の技術（捕球・送球・肩力）の高い選手、守備職人型の選手は、本職の守備適性もある程度高くする（下げることはない）
  ///  守備適性は「試合勘・ポジショニング」で、守備範囲（1歩目）に効く。追いつく速さは走力、捕球・送球はそれぞれの能力が試合で効く
  ///  本職 ＝ max(今の値, 今の値×0.6 ＋ 技術×0.4 ＋ 守備職人型なら5)。型のサブポジション（本職の0.75倍以上）も同じ割合で上げる
  static bool blendSkill(Player p, {bool? craftsman}) {
    if (p.isPitcher) return false;
    final mp = p.mainPosition;
    if (!positions.contains(mp)) return false;
    final old = _get(p, mp);
    if (old <= 1) return false;
    final skill = p.catchSkill * 0.4 + p.throwAccuracy * 0.35 + p.arm * 0.25;
    final craft = craftsman ?? false;
    final nv = max(old, (old * 0.6 + skill * 0.4 + (craft ? 5 : 0)).round()).clamp(1, 95);
    if (nv == old) return false;
    _set(p, mp, nv);
    for (final k in positions) {
      if (k == mp) continue;
      final sv = _get(p, k);
      if (sv >= 20 && sv >= old * 0.75) _set(p, k, min(nv, (sv * nv / old).round()));
    }
    return true;
  }

  static int _get(Player p, String k) => switch (k) {
        '捕手' => p.fieldC, '一塁手' => p.field1B, '二塁手' => p.field2B, '三塁手' => p.field3B,
        '遊撃手' => p.fieldSS, '左翼手' => p.fieldLF, '中堅手' => p.fieldCF, _ => p.fieldRF,
      };
  static void _set(Player p, String k, int v) {
    switch (k) {
      case '捕手': p.fieldC = v;
      case '一塁手': p.field1B = v;
      case '二塁手': p.field2B = v;
      case '三塁手': p.field3B = v;
      case '遊撃手': p.fieldSS = v;
      case '左翼手': p.fieldLF = v;
      case '中堅手': p.fieldCF = v;
      default: p.fieldRF = v;
    }
  }

  /// 選手に守備適性を入れる（本職 mainPosition から）
  static void apply(Player p, Random r) {
    final f = generate(p.isPitcher ? '投手' : p.mainPosition, r);
    p.fieldP = f['投手']!;
    p.fieldC = f['捕手']!;
    p.field1B = f['一塁手']!;
    p.field2B = f['二塁手']!;
    p.field3B = f['三塁手']!;
    p.fieldSS = f['遊撃手']!;
    p.fieldLF = f['左翼手']!;
    p.fieldCF = f['中堅手']!;
    p.fieldRF = f['右翼手']!;
    blendSkill(p);
  }

  /// 守備位置 → 適性（'投手' も含む）
  static Map<String, int> generate(String mainPos, Random r) {
    final out = <String, int>{};
    if (mainPos == '投手') {
      out['投手'] = (60 + _g(r) * 12).round().clamp(35, 90);
      for (final p in positions) {
        out[p] = 1; // 守れない（G1）
      }
      return out;
    }
    final main = (63 + _g(r) * 9).round().clamp(45, 92);
    out[mainPos] = main;
    out['投手'] = 1; // G1（二刀流は別に決める）
    final (cands, need) = _subs(mainPos, r);
    final pool = List.of(cands)..shuffle(r);
    // 最低 need 個。ときどき（25%）もう1つ
    final take = min(pool.length, need + (r.nextDouble() < 0.25 ? 1 : 0));
    final good = pool.take(take).toSet();
    // 左翼手型は右翼を必ず
    if (mainPos == '左翼手' && !good.contains('右翼手')) good
      ..remove(good.first)
      ..add('右翼手');
    // 型のサブポジションのほかに、ランダムに2つ（F 35〜50。捕手は除く）
    final extra = (positions.where((p) => p != mainPos && p != '捕手' && !good.contains(p)).toList()..shuffle(r)).take(2).toSet();
    for (final p in positions) {
      if (p == mainPos) continue;
      if (good.contains(p)) {
        out[p] = (main * (0.8 + r.nextDouble() * 0.2)).round().clamp(10, 90);
        continue;
      }
      if (extra.contains(p)) {
        out[p] = min(35 + r.nextInt(16), main - 3);
        continue;
      }
      out[p] = 1; // 守れない（G1）
    }
    return out;
  }

  /// 以前に作った選手の守備を新しい基準に寄せる：本職が63未満なら底上げ（最低45）、守れる位置が少なければランダムに足す（F 35〜50）
  static bool upgrade(Player p, Random r) {
    if (p.isPitcher) return false;
    int get(String k) => switch (k) {
          '捕手' => p.fieldC, '一塁手' => p.field1B, '二塁手' => p.field2B, '三塁手' => p.field3B,
          '遊撃手' => p.fieldSS, '左翼手' => p.fieldLF, '中堅手' => p.fieldCF, _ => p.fieldRF,
        };
    void set(String k, int v) {
      switch (k) {
        case '捕手': p.fieldC = v;
        case '一塁手': p.field1B = v;
        case '二塁手': p.field2B = v;
        case '三塁手': p.field3B = v;
        case '遊撃手': p.fieldSS = v;
        case '左翼手': p.fieldLF = v;
        case '中堅手': p.fieldCF = v;
        default: p.fieldRF = v;
      }
    }

    final mp = p.mainPosition;
    if (!positions.contains(mp)) return false;
    var changed = false;
    final v = get(mp);
    if (v < 63) {
      final nv = max(45, (63 - (63 - v) * 0.75).round());
      if (nv != v) {
        set(mp, nv);
        changed = true;
        // 型のサブポジション（本職の0.75倍以上の位置）も同じ割合で上げる（本職を超えない）
        for (final k in positions) {
          if (k == mp) continue;
          final sv = get(k);
          if (sv >= 20 && v > 0 && sv >= v * 0.75) set(k, min(nv, (sv * nv / v).round()));
        }
      }
    }
    final main = get(mp);
    final others = positions.where((k) => k != mp && get(k) >= 35).length;
    if (others < 4) {
      final cand = positions.where((k) => k != mp && k != '捕手' && get(k) < 35).toList()..shuffle(r);
      for (final k in cand.take(4 - others)) {
        set(k, min(35 + r.nextInt(16), main - 3));
        changed = true;
      }
    }
    return changed;
  }
}
