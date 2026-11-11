import 'dart:math';
import '../models/player.dart';
import '../utils/name_data.dart';
import '../utils/town_data.dart';

/// プロに入る前の経歴（高校・大学・社会人／独立・海外のリーグ）
///  発掘された選手は実際に通った学校（Player.amPath）。それ以外は出身地と入団の経路から、選手ごとに決まった形で作る
class CareerPath {
  static const _hsSuf = ['', '', '東', '西', '南', '北', '中央', '商業', '工業', '第一', '学園', '学院', '実業', '大附属', '国際', '育英'];
  static const _univSuf = ['大', '学院大', '工業大', '経済大', '国際大', '体育大', '産業大'];
  static const _corp = ['重工', '製鉄', 'ガス', '電機', '自動車', '鉄道', '通運', '生命', '化学', '製紙', '電力', '建設'];

  static String prefShort(String p) => p == '北海道' ? '北海道' : (p.isEmpty ? '' : p.substring(0, p.length - 1));

  static String _town(Random r, int pf) {
    final t = TownData.towns[pf];
    final s = t[r.nextInt(min(t.length, 30))];
    return s.length > 1 ? s : '${prefShort(NameData2.prefectures[pf].$1)}$s';
  }

  /// 経歴の行（古い順）：「高校　枚方商業高（大阪）」「大学　…」「社会人　…」「独立　…」「KBO・ソウル（2019〜2022）」
  static List<String> of(Player p) {
    if (p.amPath.isNotEmpty) return [...p.amPath, ..._abroad(p)];
    if (p.nationality == '海外') {
      final ab = _abroad(p);
      final o = p.origin.isEmpty ? '海外' : p.origin;
      return ['出身　$o', if (ab.isEmpty) '$oのプロリーグ', ...ab];
    }
    // 入団の経路：ドラフトの記録（「（高校・青葉高）」）か、入団の型（A 高卒・B 大卒・C 社会人など）
    final m = RegExp(r'（(高校|大学|社会人|独立)・([^）]+)）').firstMatch(p.draftInfo);
    final r = Random(p.id.hashCode ^ 0x1c3);
    final cat = m?.group(1) ?? switch (p.draftType) { 'A' => '高校', 'B' => '大学', _ => r.nextDouble() < 0.75 ? '社会人' : '独立' };
    return [...derive(p, cat, last: m?.group(2)), ..._abroad(p)];
  }

  /// 入団の経路（cat）から、高校（＋大学）＋最後の所属の行を作る。last は最後の所属の名前（分かっていれば）
  static List<String> derive(Player p, String cat, {String? last}) {
    final r = Random(p.id.hashCode ^ 0x2d7);
    var pf = NameData2.prefectures.indexWhere((x) => x.$1 == p.birthplace);
    if (pf < 0) pf = r.nextInt(NameData2.prefectures.length);
    final out = <String>[];
    final hs = cat == '高校' && last != null ? last : '${_town(r, pf)}${_hsSuf[r.nextInt(_hsSuf.length)]}高';
    out.add('高校　$hs（${prefShort(NameData2.prefectures[pf].$1)}）');
    // 社会人・独立は、大学を経ていることもある
    final univ = cat == '大学' || ((cat == '社会人' || cat == '独立') && r.nextDouble() < 0.45);
    if (univ) {
      final upf = r.nextDouble() < 0.6 ? pf : r.nextInt(NameData2.prefectures.length);
      out.add('大学　${cat == '大学' && last != null ? last : '${_town(r, upf)}${_univSuf[r.nextInt(_univSuf.length)]}'}');
    }
    if (cat == '社会人') out.add('社会人　${last ?? '${_town(r, pf)}${_corp[r.nextInt(_corp.length)]}'}');
    if (cat == '独立') out.add('独立　${last ?? '独立リーグの球団'}');
    return out;
  }

  /// 海外（他リーグ）の所属：来歴の行「2024　KBO・ソウル　…」から、リーグ・球団ごとに年の幅で
  static List<String> _abroad(Player p) {
    final seen = <String, (int, int)>{};
    final order = <String>[];
    for (final l in p.abroad.reversed) {
      final m = RegExp(r'^(\d{4})\s*[　 ]\s*([^　 ]+)').firstMatch(l);
      if (m == null) continue;
      final y = int.parse(m.group(1)!);
      final key = m.group(2)!;
      if (!seen.containsKey(key)) order.add(key);
      final cur = seen[key];
      seen[key] = cur == null ? (y, y) : (min(cur.$1, y), max(cur.$2, y));
    }
    return [for (final k in order) '$k（${seen[k]!.$1 == seen[k]!.$2 ? '${seen[k]!.$1}' : '${seen[k]!.$1}〜${seen[k]!.$2}'}）'];
  }
}
