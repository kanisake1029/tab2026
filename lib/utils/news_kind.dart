import 'package:flutter/material.dart';

/// お知らせの種類（文の言葉から決める）。ホームのお知らせと、過去3年分の種類別の表示で使う
class NewsKind {
  final String name;
  final Color color, bg;
  final IconData icon;
  const NewsKind(this.name, this.color, this.bg, this.icon);

  static const injury = NewsKind('怪我', Color(0xFFDC2626), Color(0xFFFEE2E2), Icons.personal_injury_outlined);
  static const weather = NewsKind('天候', Color(0xFF0369A1), Color(0xFFE0F2FE), Icons.cloud_outlined);
  static const proposal = NewsKind('提案', Color(0xFF7C3AED), Color(0xFFEDE9FE), Icons.lightbulb_outline);
  static const finance = NewsKind('経営', Color(0xFF15803D), Color(0xFFDCFCE7), Icons.bar_chart);
  static const roster = NewsKind('登録', Color(0xFF2563EB), Color(0xFFDBEAFE), Icons.swap_horiz);
  static const record = NewsKind('記録', Color(0xFFB45309), Color(0xFFFEF3C7), Icons.star_outline);
  static const league = NewsKind('リーグ', Color(0xFF475569), Color(0xFFE2E8F0), Icons.gavel_outlined);
  static const other = NewsKind('その他', Color(0xFF57534E), Color(0xFFF5F5F4), Icons.notes);

  static const all = [injury, proposal, weather, roster, record, finance, league, other];

  static NewsKind of(String t) {
    bool has(List<String> ws) => ws.any(t.contains);
    if (has(['リーグ規定', 'ポストシーズン', '日本シリーズ', 'クライマックス'])) return league;
    if (has(['負傷', '悪化', '全治', '故障'])) return injury;
    if (has(['雨天', 'ダブルヘッダー', '振替'])) return weather;
    if (has(['提案', 'キャンプ', 'モデルチェンジ', '改造'])) return proposal;
    if (has(['億円', '万円', 'スポンサー', 'グッズ', '施設', '改修', 'メーカー', 'コラボ', '資金', 'オーナー', '球場'])) return finance;
    if (has(['登録', '抹消', '昇格', '2軍', '1軍', 'トレード', 'FA', '入団', '退団', '戦力外', '獲得', '移籍', 'ドラフト', '引退', '契約'])) return roster;
    if (has(['勝目', '本塁打', '記録', '達成', '猛打', '完封', 'サヨナラ', 'MVP', 'タイトル', '連勝', '安打'])) return record;
    return other;
  }

  static final _dateRe = RegExp(r'^(\d{1,2}/\d{1,2}) (.*)$');

  /// 「5/14 本文」→（'5/14', '本文'）。日付が無ければ（'', 全体）
  static (String, String) split(String n) {
    final m = _dateRe.firstMatch(n);
    return m == null ? ('', n) : (m.group(1)!, m.group(2)!);
  }

  /// 種類のアイコン（色つきの角丸の四角）
  Widget tile({double size = 30}) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(size * 0.3)),
        child: Icon(icon, size: size * 0.58, color: color),
      );

  Widget chip() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
        child: Text(name, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: color)),
      );
}
