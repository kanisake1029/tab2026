import 'dart:math';
import '../models/player.dart';

/// 選手ごとの成長曲線：全盛期が始まる年齢と、成長期・全盛期・過渡期の長さ。
///  標準は 成長期25〜26歳（2年）→ 全盛期27〜30歳（4年）→ 過渡期31〜32歳（2年）→ 衰退期33歳〜。
///  まれに、全盛期が長い選手（大卒即戦力で30代半ばまで）や、遅咲き（30代で花開き40歳近くまで）がいる。
class GrowthCurve {
  static const stdPrimeStart = 27, stdRise = 2, stdPrime = 4, stdTrans = 2;

  /// 新しい選手の曲線を決める。bias：'早熟' なら全盛期が早め、'晩成' なら遅め（固有12の元の成長タイプ）
  static void generate(Player p, Random r, {String bias = ''}) {
    double g() => sqrt(-2.0 * log(1.0 - r.nextDouble())) * cos(2.0 * pi * r.nextDouble());
    final mean = bias == '早熟' ? 25.7 : (bias == '晩成' ? 28.3 : stdPrimeStart.toDouble());
    var start = (mean + g() * 1.3).round();
    final x = r.nextDouble();
    if (x < 0.03) start = 21 + r.nextInt(3); // まれに早咲き（21〜23歳）
    if (x > 0.97) start = 30 + r.nextInt(3); // まれに遅咲き（30〜32歳）
    p.primeStart = start.clamp(20, 33);
    final y = r.nextDouble();
    p.riseLen = y < 0.2 ? 1 : (y < 0.8 ? 2 : 3);
    p.primeLen = _pick(r, const {1: 2, 2: 8, 3: 20, 4: 36, 5: 17, 6: 9, 7: 4, 8: 2, 9: 1, 10: 1});
    if (p.primeStart >= 30 && r.nextDouble() < 0.5) p.primeLen += 2; // 遅咲きは息が長いことが多い
    final z = r.nextDouble();
    p.transLen = z < 0.25 ? 1 : (z < 0.75 ? 2 : 3);
  }

  static int _pick(Random r, Map<int, int> w) {
    final total = w.values.reduce((a, b) => a + b);
    var x = r.nextInt(total);
    for (final e in w.entries) {
      if (x < e.value) return e.key;
      x -= e.value;
    }
    return w.keys.last;
  }

  /// 以前の成長タイプ（早熟・普通・晩成）での開始年齢（成長期・全盛期・過渡期・衰退期）。曲線を持たない選手を移すときだけ使う
  static const _oldStarts = {
    '早熟': [22, 24, 29, 32],
    '普通': [25, 27, 32, 35],
    '晩成': [28, 30, 35, 38],
  };

  /// 曲線を持たない選手（以前のセーブ・初期データ）に曲線を付ける。
  ///  選手の id から決めるので何度やっても同じ。いまの成長フェーズは変えない（いま全盛期の選手は全盛期のまま）
  static void migrate(Player p) {
    final old = _oldStarts[p.growthType] ?? _oldStarts['普通']!;
    final oldAge = p.age - (p.id.hashCode.abs() % 3 - 1) - p.phaseShift;
    int phaseIdx(List<int> s, int a) => a < s[0] ? 0 : (a < s[1] ? 1 : (a < s[2] ? 2 : (a < s[3] ? 3 : 4)));
    final want = phaseIdx(old, oldAge);
    generate(p, Random(p.id.hashCode ^ 0x5c3a), bias: p.growthType);
    final target = p.primeStart;
    // いまのフェーズが変わらない範囲で、決めた年齢にいちばん近い全盛期の開始年齢を選ぶ
    int? best;
    for (var s = 16; s <= 45; s++) {
      final st = [s - p.riseLen, s, s + p.primeLen, s + p.primeLen + p.transLen];
      if (phaseIdx(st, p.age) != want) continue;
      if (best == null || (s - target).abs() < (best - target).abs()) best = s;
    }
    p.primeStart = best ?? target;
    p.phaseShift = 0;
  }

  /// 開始年齢（成長期・全盛期・過渡期・衰退期）
  static List<int> starts(Player p) {
    if (p.primeStart <= 0) migrate(p);
    final s = p.primeStart;
    return [s - p.riseLen, s, s + p.primeLen, s + p.primeLen + p.transLen];
  }

  /// 全盛期の年齢（実際の年齢。フェーズが戻った分を足す）
  static (int, int) primeRange(Player p) {
    final s = starts(p);
    return (s[1] + p.phaseShift, s[2] - 1 + p.phaseShift);
  }

  /// 円熟（約2割）：過渡期に入っても技術（ミート・制球など）が伸び続け、衰退期も技術の衰えが半分
  static bool mature(Player p) {
    var h = 0x811c9dc5;
    for (final c in p.id.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0xffffffff;
    }
    return h % 100 < 20;
  }

  /// 目立つ曲線の印（早咲き・遅咲き・息が長い・短命・円熟）。標準なら ''
  static List<String> tags(Player p) {
    starts(p);
    return [
      if (p.primeStart <= 23) '早咲き',
      if (p.primeStart >= 30) '遅咲き',
      if (p.primeLen >= 7) '息が長い',
      if (p.primeLen <= 2) '短命',
      if (mature(p)) '円熟',
    ];
  }

  /// 「全盛期 27〜30歳（息が長い）」
  static String label(Player p) {
    final (a, b) = primeRange(p);
    final t = tags(p);
    return '全盛期 $a〜$b歳${t.isEmpty ? '' : '（${t.join('・')}）'}';
  }
}
