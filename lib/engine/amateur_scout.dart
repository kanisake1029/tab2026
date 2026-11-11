import 'dart:math';
import '../models/amateur.dart';
import 'amateur_engine.dart';
import 'draft_engine.dart';
import 'career_path.dart';
import '../utils/name_data.dart';

/// 1球団のスカウト網（地区ごとの地区担当の眼力）
class ScoutNet {
  final String teamId;
  final Map<int, List<int>> regionEyes; // 地区の番号 → 地区担当の眼力（0〜2人）
  const ScoutNet(this.teamId, this.regionEyes);
}

/// 発掘・知った出来事（AppState がドラフト候補にする）
class Discovery {
  final AmPlayer player;
  final String teamId;
  final bool isNew; // 新しく生まれた原石（false はすでにいた選手を知った）
  const Discovery(this.player, this.teamId, this.isNew);
}

/// スカウトの発掘：地区担当は毎週、受け持ちの地区のチームを強い順（パイプがあれば先に）に回る。
///  各チームには今年の「隠れた原石」の数があり（強いほど多い）、見つけたときに選手が生まれる（発掘＝生成）。
///  ほかの球団がすでに見つけた選手は、回ったときに知ることができる
class AmateurScout {
  static double _g(Random r) => sqrt(-2 * log(1 - r.nextDouble())) * cos(2 * pi * r.nextDouble());

  /// 隠れた原石の数の目安（強さ s）
  static double hiddenMean(AmTeam t) {
    final x = t.strength / 100;
    return switch (t.kind) { '高校' => 0.015 + 1.8 * x * x * x, '大学' => 0.25 + 2.5 * x * x * x, _ => 0.35 + 2.5 * x * x * x };
  }

  /// 今年の隠れた原石の数（年とチームで決まる）
  static int hiddenOf(AmWorld w, AmTeam t) {
    if (t.hid >= 0) return t.hid;
    final r = Random(w.year * 7919 + t.id.hashCode);
    final m = hiddenMean(t);
    // ポアソン分布
    var k = 0;
    var p = exp(-m), s = p;
    final u = r.nextDouble();
    while (u > s && k < 8) {
      k++;
      p *= m / k;
      s += p;
    }
    t.hid = k;
    return k;
  }

  /// 卒業の学年か（社会人は入社2年目から指名できる）
  static bool eligible(AmPlayer ap, AmTeam t) => t.kind == '社会人' ? ap.grade >= 2 : ap.grade >= AmateurEngine.finalGrade(t.kind);

  /// 回る順：強さ（大学・社会人は先に回る）＋パイプ
  static double _priority(AmTeam t, String teamId) => t.strength + (t.kind == '高校' ? 0 : 12) + (t.pipe[teamId] ?? 0) * 15;

  /// 1週間分の発掘（全球団）
  static List<Discovery> week(AmWorld w, List<ScoutNet> nets, DateTime d, Random r) {
    final out = <Discovery>[];
    final byRegion = <int, List<AmTeam>>{};
    for (final t in w.teams) {
      byRegion.putIfAbsent(t.region, () => []).add(t);
    }
    for (final net in nets) {
      final visited = w.visits.putIfAbsent(net.teamId, () => {});
      for (final e in net.regionEyes.entries) {
        final eyes = List.of(e.value)..sort((a, b) => b.compareTo(a));
        if (eyes.isEmpty) continue;
        // 回る校数：1人目 2＋眼力/30、2人目は7割
        var n = 0.0;
        for (var i = 0; i < eyes.length; i++) {
          n += (2 + eyes[i] / 30) * (i == 0 ? 1.0 : 0.7);
        }
        final eye = eyes.first;
        var cand = byRegion[e.key]!.where((t) => !visited.contains(t.id)).toList();
        if (cand.isEmpty) {
          // 地区を回り終えたら、もう一度強い順から
          visited.removeAll(byRegion[e.key]!.map((t) => t.id));
          cand = List.of(byRegion[e.key]!);
        }
        cand.sort((a, b) => (_priority(b, net.teamId) + r.nextDouble() * 6).compareTo(_priority(a, net.teamId) + r.nextDouble() * 6));
        for (final t in cand.take(n.round())) {
          visited.add(t.id);
          out.addAll(visit(w, t, net.teamId, eye, r));
        }
      }
    }
    return out;
  }

  /// 1チームを回る：すでにいる選手を知る／まだ見つかっていない原石を発掘する
  static List<Discovery> visit(AmWorld w, AmTeam t, String teamId, int eye, Random r) {
    final out = <Discovery>[];
    final pipe = t.pipe[teamId] ?? 0;
    var q = (0.25 * (0.5 + eye / 100) * (1 + 0.5 * pipe)).clamp(0.05, 0.9);
    // 弱いチームの逸材は、眼力が高くないと見つからない
    if (t.strength < 45) q *= ((eye - 40) / 50).clamp(0.1, 1.0);
    for (final ap in w.playersOf(t.id).toList()) {
      if (!eligible(ap, t) || ap.foundBy.contains(teamId)) continue;
      if (r.nextDouble() < min(0.95, q * 1.6)) {
        ap.foundBy.add(teamId);
        out.add(Discovery(ap, teamId, false));
      }
    }
    final left = hiddenOf(w, t) - t.gen;
    for (var i = 0; i < left; i++) {
      if (r.nextDouble() >= q) continue;
      final ap = discover(w, t, r);
      w.players.add(ap);
      ap.foundBy.add(teamId);
      out.add(Discovery(ap, teamId, true));
    }
    return out;
  }

  /// 原石が生まれる：力はチームの強さで決まる（弱いチームの逸材は、まれに大きく外れる）
  static AmPlayer discover(AmWorld w, AmTeam t, Random r) {
    t.gen++;
    final s = t.strength;
    final x = r.nextDouble();
    final tier = s >= 75
        ? (x < 0.15 ? 2 : (x < 0.6 ? 1 : 0))
        : s >= 55
            ? (x < 0.05 ? 2 : (x < 0.35 ? 1 : (x < 0.85 ? 0 : -1)))
            : (x < 0.03 ? 2 : (x < 0.18 ? 1 : (x < 0.58 ? 0 : -1)));
    final pr = DraftEngine.makeTier(r, w.year, 'AM${w.year}_${w.nextId++}', t.kind, tier);
    final grade = switch (t.kind) { '高校' => 3, '大学' => 4, _ => 2 + r.nextInt(3) };
    // 経歴：高校はその学校（出身地もたいていその県）。大学・社会人は、その前の高校（大学）から
    final p = pr.player;
    final pref = NameData2.prefectures[t.pref].$1;
    if (t.kind == '高校' || r.nextDouble() < 0.6) p.birthplace = pref;
    p.amPath = switch (t.kind) {
      '高校' => ['高校　${t.name}（${CareerPath.prefShort(pref)}）'],
      '大学' => [CareerPath.derive(p, '高校').first, '大学　${t.name}'],
      _ => CareerPath.derive(p, '社会人', last: t.name),
    };
    return AmPlayer(player: pr.player, teamId: t.id, grade: grade, record: DraftEngine.amateurRecord(pr.player, t.kind, t.name, r));
  }

  /// 甲子園でベスト8に入ったチームの選手は、全球団が知る（担当のいない地区でも話題になる）。隠れた原石も見つかる
  static List<Discovery> koshienBuzz(AmWorld w, AmComp c, List<String> teamIds, Random r) {
    final out = <Discovery>[];
    for (final id in c.teams) {
      final res = c.resultOf(id);
      if (!const ['優勝', '準優勝', 'ベスト4', 'ベスト8'].contains(res)) continue;
      final t = w.team(id)!;
      // 原石の半分ほどが表に出る
      final left = hiddenOf(w, t) - t.gen;
      for (var i = 0; i < left; i++) {
        if (r.nextDouble() < 0.5) w.players.add(discover(w, t, r));
      }
      for (final ap in w.playersOf(id)) {
        if (!eligible(ap, t)) continue;
        for (final tid in teamIds) {
          if (ap.foundBy.add(tid)) out.add(Discovery(ap, tid, false));
        }
      }
    }
    return out;
  }

  static double gauss(Random r) => _g(r);
}
