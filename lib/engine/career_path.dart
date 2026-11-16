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

  /// 海外（他リーグ）の所属：来歴の行「2024　MLB・LAD　…」から年ごとの所属を整理し、連続する同球団・同リーグをまとめる
  ///  2025年以前（ゲーム開始前の推定経歴）には末尾に * を付ける
  static List<String> _abroad(Player p) {
    final byYear = <int, List<String>>{};
    for (final l in p.abroad.reversed) {
      final m = RegExp(r'^(\d{4})\s*[　 ]\s*([^　 ]+)').firstMatch(l);
      if (m == null) continue;
      final y = int.parse(m.group(1)!);
      final key = m.group(2)!;
      final list = byYear.putIfAbsent(y, () => []);
      if (!list.contains(key)) list.add(key);
    }
    if (byYear.isEmpty) return const [];
    final years = byYear.keys.toList()..sort();
    // 同じ年に複数リーグ（例: 3A と MLB）があれば両方「MLB・LAD／3A・OKC」として1年にまとめる
    final stints = <(String, int, int, bool)>[]; // (label, fromYear, toYear, estimated)
    for (final y in years) {
      final list = byYear[y]!;
      list.sort((a, b) => _rank(b).compareTo(_rank(a)));
      final label = list.join('／');
      final est = y < 2026;
      if (stints.isNotEmpty && stints.last.$1 == label && stints.last.$4 == est && stints.last.$3 == y - 1) {
        final prev = stints.removeLast();
        stints.add((label, prev.$2, y, est));
      } else {
        stints.add((label, y, y, est));
      }
    }
    return [for (final s in stints) '${s.$1}（${s.$2 == s.$3 ? '${s.$2}' : '${s.$2}〜${s.$3}'}）${s.$4 ? '*' : ''}'];
  }

  static int _rank(String k) {
    if (k.startsWith('MLB')) return 5;
    if (k.startsWith('3A')) return 4;
    if (k.startsWith('2A')) return 3;
    if (k.startsWith('1A')) return 2;
    return 1;
  }
}
