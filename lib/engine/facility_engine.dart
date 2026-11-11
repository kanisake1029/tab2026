/// 改修2：球団施設・テクノロジー投資（4部門・Lv.0〜5）と、本拠地球場の改修（テラス・高いフェンス・芝）
///  金額の単位は万円（10000＝1億円）
class Facility {
  final String key;
  final String name;
  final String effect;
  final List<int> costs; // Lv1〜5 にするための費用
  final int upkeepPerLevel; // 1 Lv あたりの年間の維持費
  const Facility(this.key, this.name, this.effect, this.costs, this.upkeepPerLevel);
}

class FacilityEngine {
  static const maxLevel = 5;

  static const all = [
    Facility('bio', 'バイオメカニクス解析ラボ', '練習・試合の経験値：投手の球威・制球・変化球のキレ、打者のミート・パワーが +5%/Lv（最大+25%）', [50000, 100000, 150000, 200000, 250000], 4000),
    Facility('medical', 'メディカル＆リカバリーセンター', '毎日の体力の回復 +4%/Lv、怪我の起こりやすさ −6%/Lv、治るまでの日数 −5%/Lv（最大−25%）', [50000, 100000, 150000, 200000, 250000], 4000),
    Facility('scout', 'スカウト情報網＆データ分析室', 'ドラフト・外国人候補の隠れた素質（才能・向上心・環境適応力）の見立ての幅が Lv ごとに狭まる（スカウト眼力 +10/Lv）', [30000, 60000, 90000, 120000, 150000], 2500),
    Facility('stadium', 'スタジアム集客・グッズショップ', 'チケットの高値でも客が減りにくく（価格の上限 +500円/Lv）、グッズ・飲食収入 +6%/Lv', [50000, 110000, 170000, 230000, 300000], 5000),
  ];

  static Facility byKey(String k) => all.firstWhere((f) => f.key == k);

  /// 次の Lv にする費用（最大なら null）
  static int? nextCost(String key, int level) {
    final f = byKey(key);
    return level >= maxLevel ? null : f.costs[level];
  }

  /// 年間の維持費の合計
  static int upkeep(Map<String, int> lv) => all.fold(0, (s, f) => s + (lv[f.key] ?? 0) * f.upkeepPerLevel);

  // ───── 効果 ─────
  /// 練習の経験値の倍率（ラボの対象の能力だけ）
  static double labMult(int lv, String statKey) {
    if (lv <= 0) return 1.0;
    const keys = {'pitchPower', 'control', 'contactLeft', 'contactRight', 'power'};
    if (keys.contains(statKey) || (statKey.startsWith('pitch:') && statKey.endsWith(':sharpness'))) return 1 + 0.05 * lv;
    return 1.0;
  }

  /// スカウトの眼力の上乗せ
  static int scoutBonus(int lv) => 10 * lv;

  /// チケットの価格の上限
  static int maxTicket(int stadiumLv) => 7000 + 500 * stadiumLv;

  /// グッズ・飲食の倍率
  static double goodsMult(int stadiumLv) => 1 + 0.06 * stadiumLv;

  // ───── 球場の改修（オフ 11〜2月に 1 回）─────
  /// 改修の種類：(キー, 名前, 費用, 説明)
  static const parkWorks = [
    ('terrace', 'ホームランテラス', 150000, '左中間・右中間のフェンスを最大 3m 前へ出し、フェンスを 2.5m に下げる（本塁打が出やすい）。もう一度選ぶと撤去'),
    ('wall', '高層フェンス（モンスターウォール）', 120000, 'フェンスを 1.5m 高くする（本塁打が出にくい）。もう一度選ぶと元の高さへ'),
    ('turf', '芝の張り替え', 200000, '天然芝 ⇄ 人工芝。人工芝はよく跳ねて打球が速く（ゴロが抜けやすい）、天然芝は打球が死にやすい'),
  ];

  static int parkCost(String key, {bool removing = false}) {
    final c = parkWorks.firstWhere((w) => w.$1 == key).$3;
    return removing ? (c * 0.6).round() : c; // 撤去は少し安い
  }
}
