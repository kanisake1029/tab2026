import 'dart:math' as m;
import '../engine/body_gen.dart';

/// バット（公認野球規則：長さ 106.7cm 以下・太さ 6.6cm 以下。プロは 84〜87cm・850〜950g が主流）
///  重心の位置（バランス）：トップ＝先が重い（当たり負けしない・振り出しが重い）、カウンター＝手元が重い（振り抜きやすい）
class Bat {
  double length; // cm
  double weight; // g
  String balance; // 'トップ'・'ミドル'・'カウンター'
  double choke; // 短く持つ長さ（cm）
  // ── 見た目（3D）──
  String finish; // 塗り：finishes のどれか
  String maker; // メーカー（架空）
  Bat({this.length = 85, this.weight = 900, this.balance = 'ミドル', this.choke = 0, this.finish = 'ナチュラル', this.maker = 'ホクトスポーツ'});

  /// 塗り → (胴の色, 先の色)。ツートンは先が濃い
  static const finishes = {
    'ナチュラル': (0xFFE2B979, 0xFFE2B979),
    'ブラウン': (0xFF8B5A2B, 0xFF8B5A2B),
    '赤茶': (0xFF9C3F22, 0xFF9C3F22),
    '黒': (0xFF1F1F22, 0xFF1F1F22),
    'ツートン': (0xFFE2B979, 0xFF3B2416),
  };
  (int, int) get colors => finishes[finish] ?? finishes['ナチュラル']!;

  static const balances = ['トップ', 'ミドル', 'カウンター'];

  /// グリップの端から重心までの距離（m）
  double get cgFromKnob => length / 100 * switch (balance) { 'トップ' => 0.73, 'カウンター' => 0.64, _ => 0.685 };

  /// 持つ位置（グリップの端から choke）のまわりの慣性モーメント（kg·m²）。細長い棒で近似し、重心の位置で補正
  double get inertia {
    final mkg = weight / 1000, l = length / 100, hold = choke / 100;
    final icg = mkg * l * l / 12 * 0.62; // 木のバットは先が太いので一様な棒より少し小さい
    final d = cgFromKnob - hold - 0.15; // 手で握る点（グリップの端から約15cm）から重心まで
    return icg + mkg * d * d;
  }

  /// 標準（85cm・900g・ミドル）に対するスイングの速さの比：慣性モーメントの −0.27 乗
  double get swingSpeedRatio => m.pow(inertia / Bat().inertia, -0.27).toDouble();

  /// 芯（先から約15cm）での有効質量（当たり負けしにくさ。kg）：1/M_eff = 1/M + b²/I_重心（b は重心から芯まで）
  double get effectiveMass {
    final mkg = weight / 1000, l = length / 100;
    final icg = mkg * l * l / 12 * 0.62;
    final b = (l - 0.15) - cgFromKnob;
    return 1 / (1 / mkg + b * b / icg);
  }

  Map<String, dynamic> toJson() => {'l': length, 'w': weight, 'b': balance, 'c': choke, 'f': finish, 'm': maker};
  factory Bat.fromJson(Map<String, dynamic> j) => Bat(
      length: (j['l'] ?? 85).toDouble(),
      weight: (j['w'] ?? 900).toDouble(),
      balance: j['b'] ?? 'ミドル',
      choke: (j['c'] ?? 0).toDouble(),
      finish: j['f'] ?? 'ナチュラル',
      maker: j['m'] ?? 'ホクトスポーツ');

  /// 自動：パワーが高いほど重く先が重い、ミートが高いほど軽く手元寄り、背が高いほど長い
  factory Bat.auto(String id, {required int power, required int contact, required int height}) {
    final r = m.Random(stableHash(id, 0xba7));
    final w = (900 + (power - 60) * 1.4 - (contact - 60) * 0.7 + (r.nextDouble() - 0.5) * 30).clamp(850.0, 950.0);
    final l = (85 + (height - 180) * 0.06 + (r.nextDouble() - 0.5) * 1.5).clamp(83.0, 87.5);
    final bal = power - contact > 12 ? 'トップ' : (contact - power > 12 ? 'カウンター' : 'ミドル');
    final fin = Bat.finishes.keys.elementAt(const [0, 0, 0, 1, 1, 2, 3, 3, 4][r.nextInt(9)]);
    return Bat(length: (l * 2).round() / 2, weight: (w / 5).round() * 5.0, balance: bal, finish: fin, maker: makers[r.nextInt(makers.length)]);
  }
}

/// 用具のメーカー（架空）と、ロゴの色
const makers = ['ホクトスポーツ', 'ナガレ', 'カタナ', 'アークライン', 'ヤマセ', 'ルーセント'];
const makerColors = {'ホクトスポーツ': 0xFF1D4ED8, 'ナガレ': 0xFFDC2626, 'カタナ': 0xFF111827, 'アークライン': 0xFF0F766E, 'ヤマセ': 0xFFEA580C, 'ルーセント': 0xFF7C3AED};

/// グラブ（全長 33.0cm 以下）。大きいほど届く範囲が広いが、ポケットが深いほど握り替えが遅い
class Glove {
  double length; // cm
  String pocket; // '浅い'・'ふつう'・'深い'
  // ── 見た目（3D）──
  String color; // 革の色：colors のどれか
  String lace; // ひもの色：colors のどれか
  String web; // ウェブ（網）：webs のどれか
  String maker;
  Glove({this.length = 30, this.pocket = 'ふつう', this.color = 'キャメル', this.lace = 'キャメル', this.web = 'クロス', this.maker = 'ホクトスポーツ'});

  static const colors = {'キャメル': 0xFFC98A4B, 'ブラウン': 0xFF7A4A2A, 'ブラック': 0xFF1E1E22, 'オレンジ': 0xFFE07B2E, 'レッド': 0xFFB3261E, 'ネイビー': 0xFF1E2A4A, 'イエロー': 0xFFD9A93A};
  static const webs = ['クロス', 'H', 'バスケット', 'トラップ', '一枚'];
  int get colorArgb => colors[color] ?? colors['キャメル']!;
  int get laceArgb => colors[lace] ?? colorArgb;

  static const pockets = ['浅い', 'ふつう', '深い'];

  /// 捕れる範囲の広がり（m）：標準 30cm からの差がそのまま
  double get reachBonus => (length - 30) / 100;

  /// 握り替えにかかる時間の増え方（秒）：深いほど遅い
  double get transferDelay => switch (pocket) { '浅い' => 0.0, '深い' => 0.09, _ => 0.04 } + m.max(0.0, length - 30) * 0.008;

  Map<String, dynamic> toJson() => {'l': length, 'p': pocket, 'c': color, 'la': lace, 'wb': web, 'm': maker};
  factory Glove.fromJson(Map<String, dynamic> j) => Glove(
      length: (j['l'] ?? 30).toDouble(),
      pocket: j['p'] ?? 'ふつう',
      color: j['c'] ?? 'キャメル',
      lace: j['la'] ?? 'キャメル',
      web: j['wb'] ?? 'クロス',
      maker: j['m'] ?? 'ホクトスポーツ');

  /// 自動：守備位置ごとの標準（二遊間は小さく浅い、外野・一塁は大きく深い）
  factory Glove.auto(String id, String position) {
    final r = m.Random(stableHash(id, 0x6c0));
    final (lo, hi, pocket) = switch (position) {
      '二塁手' || '遊撃手' => (28.5, 29.3, '浅い'),
      '三塁手' => (29.5, 30.5, 'ふつう'),
      '一塁手' => (31.5, 33.0, '深い'),
      '捕手' => (31.0, 32.5, '深い'),
      '投手' => (30.0, 31.0, 'ふつう'),
      _ => (31.5, 33.0, '深い'),
    };
    final cs = Glove.colors.keys.toList();
    final col = cs[const [0, 0, 0, 1, 1, 2, 2, 3, 4, 5, 6][r.nextInt(11)]];
    final lace = r.nextDouble() < 0.6 ? col : cs[r.nextInt(cs.length)];
    // 内野手はクロスや一枚、外野手はトラップ、投手は中が見えない一枚やバスケット
    final web = switch (position) {
      '投手' => r.nextBool() ? '一枚' : 'バスケット',
      '二塁手' || '遊撃手' || '三塁手' => r.nextBool() ? 'クロス' : 'H',
      '捕手' || '一塁手' => '一枚',
      _ => r.nextBool() ? 'トラップ' : 'H',
    };
    return Glove(length: ((lo + (hi - lo) * r.nextDouble()) * 2).round() / 2, pocket: pocket, color: col, lace: lace, web: web, maker: makers[r.nextInt(makers.length)]);
  }
}
