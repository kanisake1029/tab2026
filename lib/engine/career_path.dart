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
  static const _jpIndyTeams = [
    '四国・徳島', '四国・香川', '四国・愛媛', '四国・高知',
    'BC・新潟', 'BC・信濃', 'BC・富山', 'BC・石川', 'BC・福井', 'BC・群馬', 'BC・埼玉', 'BC・茨城', 'BC・栃木',
    '関西・兵庫', '関西・大阪', '関西・京都', '関西・奈良', '関西・和歌山',
    '北海道・札幌', '北海道・旭川', '北海道・函館',
    '九州・福岡', '九州・熊本', '九州・大分',
    '日本海・鳥取', '日本海・島根', '日本海・山口',
  ];

  static String prefShort(String p) => p == '北海道' ? '北海道' : (p.isEmpty ? '' : p.substring(0, p.length - 1));

  static String _town(Random r, int pf) {
    final t = TownData.towns[pf];
    final s = t[r.nextInt(min(t.length, 30))];
    return s.length > 1 ? s : '${prefShort(NameData2.prefectures[pf].$1)}$s';
  }

  /// アマチュア・独立までの経歴（_abroad を除く）
  static List<String> amateurSteps(Player p) {
    if (p.amPath.isNotEmpty) {
      final list = List<String>.from(p.amPath);
      if (list.any((s) => s.startsWith('独立'))) {
        list.removeWhere((s) => s.startsWith('大学'));
      }
      return list;
    }
    if (p.nationality == '海外') {
      final o = p.origin.isEmpty ? '海外' : p.origin;
      return ['出身　$o'];
    }
    final m = RegExp(r'（(高校|大学|社会人|独立)・([^）]+)）').firstMatch(p.draftInfo);
    final r = Random(p.id.hashCode ^ 0x1c3);
    final cat = m?.group(1) ?? switch (p.draftType) { 'A' => '高校', 'B' => '大学', _ => r.nextDouble() < 0.75 ? '社会人' : '独立' };
    return derive(p, cat, last: m?.group(2));
  }

  /// 大学を経由しているか
  static bool hasUniversity(Player p) => amateurSteps(p).any((s) => s.startsWith('大学'));

  /// 独立リーグを経由している場合、その球団ラベル（例：「四国・徳島」「BC・新潟」）。経由していなければ null
  static String? indieTeamLabel(Player p) {
    if (p.nationality == '海外') return null;
    for (final s in amateurSteps(p)) {
      if (s.startsWith('独立　')) {
        final raw = s.substring(3).trim();
        final m = RegExp(r'^(.+?)（(.+?)）$').firstMatch(raw);
        if (m != null) {
          final lg = m.group(2)!.replaceAll('リーグ', '');
          final tm = m.group(1)!;
          return '$lg・${tm.length > 4 ? tm.substring(0, 2) : tm}';
        }
        return raw.replaceAll(' ', '');
      }
    }
    return null;
  }

  /// 野球人生としてプロ入りした年齢（高卒独立・海外＝19歳、大卒独立＝23歳、その他＝NPB入団年齢）
  static int proStartAge(Player p, {bool inOtherLeague = false}) {
    final int npbEntryAge = (p.age - max(1, p.proYears) + 1).clamp(18, max(18, p.age)).toInt();
    if (p.nationality == '海外') {
      return min<int>(19, min<int>(p.age, inOtherLeague ? p.age : npbEntryAge));
    }
    if (indieTeamLabel(p) != null || (inOtherLeague && p.draftYear == 0 && p.career.games == 0 && p.career.pitchApps == 0)) {
      final int gradProAge = (hasUniversity(p) && p.age >= 23) ? 23 : 19;
      return inOtherLeague ? min<int>(gradProAge, p.age) : min<int>(gradProAge, npbEntryAge);
    }
    return npbEntryAge;
  }

  /// 野球人生としてプロが始まった西暦年
  static int proStartYear(Player p, int currentYear, {bool inOtherLeague = false, Iterable<int> knownProYears = const []}) {
    final startAge = proStartAge(p, inOtherLeague: inOtherLeague);
    var y = currentYear - (p.age - startAge);
    for (final l in p.abroad) {
      final m = RegExp(r'^(\d{4})\s*[　 ]').firstMatch(l);
      if (m != null) {
        final ay = int.parse(m.group(1)!);
        if (ay < y) y = ay;
      }
    }
    for (final ky in knownProYears) {
      if (ky < y) y = ky;
    }
    if (p.nationality != '海外' && indieTeamLabel(p) != null && knownProYears.isNotEmpty) {
      final firstNpb = knownProYears.reduce(min);
      if (y >= firstNpb) y = firstNpb - 1;
    }
    return y;
  }

  /// 野球人生としてプロ入りしてからの通算年数（他リーグ表示用）
  static int totalProYears(Player p, int currentYear, {bool inOtherLeague = false, Iterable<int> knownProYears = const []}) {
    final startY = proStartYear(p, currentYear, inOtherLeague: inOtherLeague, knownProYears: knownProYears);
    return max(1, currentYear - startY + 1);
  }

  /// 経歴の行（古い順）：「高校　枚方商業高（大阪）」「大学　…」「社会人　…」「独立　…」「KBO・ソウル（2019〜2022）」
  static List<String> of(Player p) {
    final ab = _abroad(p);
    if (p.nationality == '海外') {
      final o = p.origin.isEmpty ? '海外' : p.origin;
      return ['出身　$o', if (ab.isEmpty) '$oのプロリーグ', ...ab];
    }
    final steps = amateurSteps(p);
    if (ab.isNotEmpty && steps.isNotEmpty && steps.last.startsWith('独立　')) {
      final indieName = steps.last.substring(3).trim();
      if (ab.any((x) => x.startsWith(indieName) || indieName.contains(x.split('（').first))) {
        steps.removeLast();
      }
    }
    return [...steps, ...ab];
  }

  /// 入団の経路（cat）から、高校（＋大学）＋最後の所属の行を作る。last は最後の所属の名前（分かっていれば）
  static List<String> derive(Player p, String cat, {String? last}) {
    final r = Random(p.id.hashCode ^ 0x2d7);
    var pf = NameData2.prefectures.indexWhere((x) => x.$1 == p.birthplace);
    if (pf < 0) pf = r.nextInt(NameData2.prefectures.length);
    final out = <String>[];
    final hs = cat == '高校' && last != null ? last : '${_town(r, pf)}${_hsSuf[r.nextInt(_hsSuf.length)]}高';
    out.add('高校　$hs（${prefShort(NameData2.prefectures[pf].$1)}）');
    // 社会人のみ、23歳以上なら大学を経ていることもある（独立リーグは高卒扱い＝大学を付けない）
    final univ = cat == '大学' || (cat == '社会人' && p.age >= 23 && r.nextDouble() < 0.45);
    if (univ) {
      final upf = r.nextDouble() < 0.6 ? pf : r.nextInt(NameData2.prefectures.length);
      out.add('大学　${cat == '大学' && last != null ? last : '${_town(r, upf)}${_univSuf[r.nextInt(_univSuf.length)]}'}');
    }
    if (cat == '社会人') out.add('社会人　${last ?? '${_town(r, pf)}${_corp[r.nextInt(_corp.length)]}'}');
    if (cat == '独立') out.add('独立　${last ?? _jpIndyTeams[r.nextInt(_jpIndyTeams.length)]}');
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

  /// 統一経歴フォーマット：
  /// 例：`['大阪高', '大和大', '東新（2024〜2026）', 'MLB・LAA（2027〜2028）', '広島（2029〜2030）']`
  static List<String> unified(
    Player p, {
    List<(int, String)> npbStints = const [],
    String? currentTeamLabel,
    int? currentYear,
  }) {
    final steps = amateurSteps(p);
    final cleanAm = <String>[];
    final hasAbroadData = p.abroad.isNotEmpty;
    for (final s in steps) {
      if (hasAbroadData && s.startsWith('独立　')) continue;
      if (s.startsWith('出身　')) {
        cleanAm.add(s.substring(3).trim());
        continue;
      }
      var body = s.replaceFirst(RegExp(r'^(高校|大学|社会人|独立)[　 ]+'), '').trim();
      if (s.startsWith('高校　')) {
        body = body.replaceFirst(RegExp(r'（[^）]+）$'), '').trim();
      }
      if (body.isNotEmpty) cleanAm.add(body);
    }

    final byYear = <int, List<String>>{};
    void addYear(int y, String label) {
      final clean = label.replaceAll('*', '').trim();
      if (clean.isEmpty) return;
      final list = byYear.putIfAbsent(y, () => []);
      if (!list.contains(clean)) list.add(clean);
    }

    for (final (y, lbl) in npbStints) {
      addYear(y, lbl);
    }
    final lineRe = RegExp(r'^(\d{4})\s*[　 ]\s*([^　 ]+)');
    for (final l in p.abroad.reversed) {
      final m = lineRe.firstMatch(l);
      if (m == null) continue;
      addYear(int.parse(m.group(1)!), m.group(2)!);
    }
    if (currentTeamLabel != null && currentYear != null && !byYear.containsKey(currentYear)) {
      addYear(currentYear, currentTeamLabel);
    }

    if (byYear.isEmpty) return cleanAm;
    final years = byYear.keys.toList()..sort();
    final merged = <(String, int, int)>[];
    for (final y in years) {
      final list = byYear[y]!;
      list.sort((a, b) => _rank(b).compareTo(_rank(a)));
      final lbl = list.join('／');
      if (merged.isNotEmpty && merged.last.$1 == lbl && merged.last.$3 == y - 1) {
        final prev = merged.removeLast();
        merged.add((lbl, prev.$2, y));
      } else {
        merged.add((lbl, y, y));
      }
    }
    return [
      ...cleanAm,
      for (final s in merged) '${s.$1}（${s.$2 == s.$3 ? '${s.$2}' : '${s.$2}〜${s.$3}'}）',
    ];
  }
}
