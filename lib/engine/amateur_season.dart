import 'dart:math';
import 'velo.dart';
import '../models/amateur.dart';
import '../models/player.dart';
import '../utils/name_data.dart';
import 'amateur_engine.dart';
import 'quick_game.dart';

/// アマチュア球界の1年の大会・リーグ（日程・組み合わせ・試合・成績の記録）
///  高校：春・夏は都道府県大会→甲子園（50校）、秋は都道府県大会→9地区大会
///  大学：9地区リーグ（6校・各50試合）　社会人：都市対抗（地区予選→本大会32チーム）
class AmateurSeason {
  /// 甲子園に2校出す都道府県（地区を2つに分けて大会をする）
  static const splitPref = {0: ['北北海道', '南北海道'], 12: ['東東京', '西東京'], 26: ['北大阪', '南大阪']};

  static String _prefName(int pf) => NameData2.prefectures[pf].$1;

  /// 年度の始めに、今年の大会・リーグを作る（出場が前の大会で決まるものは、出場チームが空のまま）
  static void setupYear(AmWorld w, Random r) {
    final y = w.year;
    w.comps = [];
    final hsByPref = <int, List<String>>{};
    for (final t in w.ofKind('高校')) {
      hsByPref.putIfAbsent(t.pref, () => []).add(t.id);
    }
    DateTime d(int m, int day) => DateTime(y, m, day);
    // 高校：春・夏の都道府県大会（北海道・東京・大阪は2つに分ける）→ 甲子園
    for (final (season, start, kStart) in [('春', d(4, 6), d(5, 15)), ('夏', d(7, 1), d(8, 6))]) {
      for (final e in hsByPref.entries) {
        final split = splitPref[e.key];
        if (split == null) {
          w.comps.add(_tourn('$season-pref-${e.key}', '$season季${_prefName(e.key)}大会', '高校', 'pref', season, start, 3, e.value, r, pref: e.key, region: amPrefRegion[e.key]));
        } else {
          final ids = List.of(e.value);
          final half = ids.length ~/ 2;
          for (var i = 0; i < 2; i++) {
            final part = i == 0 ? ids.sublist(0, half) : ids.sublist(half);
            w.comps.add(_tourn('$season-pref-${e.key}-$i', '$season季${split[i]}大会', '高校', 'pref', season, start, 3, part, r, pref: e.key, region: amPrefRegion[e.key]));
          }
        }
      }
      w.comps.add(AmComp(id: '$season-koshien', name: '$seasonの甲子園', cat: '高校', stage: 'koshien', season: season, start: kStart, gap: 2));
    }
    // 秋：都道府県大会 → 9地区大会
    for (final e in hsByPref.entries) {
      w.comps.add(_tourn('秋-pref-${e.key}', '秋季${_prefName(e.key)}大会', '高校', 'pref', '秋', d(9, 1), 3, e.value, r, pref: e.key, region: amPrefRegion[e.key]));
    }
    for (var rg = 0; rg < amRegions.length; rg++) {
      w.comps.add(AmComp(id: '秋-region-$rg', name: '秋季${amRegions[rg]}地区大会', cat: '高校', stage: 'region', season: '秋', region: rg, start: d(10, 5), gap: 3));
    }
    // 大学：1地区3リーグ（6校の総当たりを10回＝各50試合）
    for (var rg = 0; rg < amRegions.length; rg++) {
      final all = [for (final t in w.ofKind('大学')) if (t.region == rg) t.id];
      for (var k = 0; k * 6 < all.length; k++) {
        final ids = all.sublist(k * 6, min(all.length, k * 6 + 6));
        w.comps.add(AmComp(id: 'league-$rg-$k', name: '${amRegions[rg]}${const ['第一', '第二', '第三', '第四'][k.clamp(0, 3)]}大学リーグ', cat: '大学', stage: 'league', season: '', region: rg, start: d(4, 5), gap: 4, teams: ids, games: _roundRobin(ids.length, 10)));
      }
    }
    // 社会人：都市対抗の地区予選 → 本大会
    for (var rg = 0; rg < amRegions.length; rg++) {
      final ids = [for (final t in w.ofKind('社会人')) if (t.region == rg) t.id];
      w.comps.add(_tourn('qual-$rg', '都市対抗 ${amRegions[rg]}予選', '社会人', 'qual', '', d(6, 1), 3, ids, r, region: rg));
    }
    w.comps.add(AmComp(id: 'main', name: '都市対抗野球', cat: '社会人', stage: 'main', season: '', start: d(7, 12), gap: 2));
  }

  /// トーナメントを作る（不戦勝の枠はランダムなチームに）
  static AmComp _tourn(String id, String name, String cat, String stage, String season, DateTime start, int gap, List<String> teams, Random r, {int pref = -1, int region = -1}) {
    final c = AmComp(id: id, name: name, cat: cat, stage: stage, season: season, pref: pref, region: region, start: start, gap: gap, teams: List.of(teams));
    c.rounds = [_bracket(teams, r)];
    return c;
  }

  /// 組み合わせ：2のべき乗の枠に入れる。空き（不戦勝）はランダムなチームの相手に（空き同士にはしない）
  static List<String> _bracket(List<String> teams, Random r) {
    var size = 1;
    while (size < teams.length) {
      size *= 2;
    }
    final ts = List.of(teams)..shuffle(r);
    final byes = size - ts.length;
    final pairs = <List<String>>[
      for (var i = 0; i < byes; i++) [ts[i], ''],
      for (var i = byes; i + 1 < ts.length; i += 2) [ts[i], ts[i + 1]],
    ]..shuffle(r);
    return [for (final p in pairs) ...p];
  }

  /// 総当たり（円の方法）を cycles 回：[節, a, b, -1, -1]
  static List<List<int>> _roundRobin(int n, int cycles) {
    final out = <List<int>>[];
    final idx = List.generate(n, (i) => i);
    var round = 0;
    for (var c = 0; c < cycles; c++) {
      final rot = List.of(idx);
      for (var k = 0; k < n - 1; k++) {
        for (var i = 0; i < n ~/ 2; i++) {
          final a = rot[i], b = rot[n - 1 - i];
          out.add(c.isEven ? [round, a, b, -1, -1] : [round, b, a, -1, -1]);
        }
        round++;
        rot.insert(1, rot.removeLast()); // 0番は固定して回す
      }
    }
    return out;
  }

  // ───────── 毎日の試合 ─────────

  /// その日の試合をする
  static void playDay(AmWorld w, DateTime d) {
    final r = Random(d.year * 10000 + d.month * 100 + d.day);
    for (final c in w.comps) {
      if (c.done) continue;
      if (c.teams.isEmpty && _sameDay(c.start, d)) _fill(w, c, r);
      if (c.teams.isEmpty) continue;
      final k = c.roundOn(d);
      if (k < 0) continue;
      if (c.isLeague) {
        _playLeagueRound(w, c, k, r);
      } else if (c.rounds.length == k + 1 && c.scores.length == k) {
        _playTournRound(w, c, k, r);
      }
    }
  }

  static bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  /// 前の大会の結果で出場チームを決める（甲子園・地区大会・都市対抗の本大会）
  static void _fill(AmWorld w, AmComp c, Random r) {
    List<AmComp> of(String prefix) => w.comps.where((x) => x.id.startsWith(prefix)).toList();
    // 勝ち進んだ順（同じなら強いほう）
    List<String> ranked(AmComp x) {
      final l = List.of(x.teams)..shuffle(r);
      l.sort((a, b) {
        final c1 = x.reached(b).compareTo(x.reached(a));
        return c1 != 0 ? c1 : (w.team(b)?.strength ?? 0).compareTo(w.team(a)?.strength ?? 0);
      });
      return l;
    }

    switch (c.stage) {
      case 'koshien':
        c.teams = [for (final x in of('${c.season}-pref-')) if (x.champion != null) x.champion!];
      case 'region':
        final prefs = [for (var i = 0; i < amPrefRegion.length; i++) if (amPrefRegion[i] == c.region) i];
        final per = AmateurEngine.hsPerPref();
        final tot = prefs.fold<int>(0, (a, p) => a + per[p]);
        c.teams = [
          for (final p in prefs)
            if (w.comp('秋-pref-$p') case final x?) ...ranked(x).take(max(1, (16 * per[p] / tot).round())),
        ];
      case 'main':
        final quals = of('qual-');
        final extra = <String>[];
        for (final q in quals) {
          final rk = ranked(q);
          c.teams.addAll(rk.take(3)); // 優勝・準優勝・ベスト4のうち1つ
          if (rk.length > 3) extra.add(rk[3]);
        }
        extra.shuffle(r);
        c.teams.addAll(extra.take(32 - c.teams.length));
    }
    if (!c.isLeague && c.teams.length > 1) c.rounds = [_bracket(c.teams, r)];
  }

  static void _playTournRound(AmWorld w, AmComp c, int k, Random r) {
    final slots = c.rounds[k];
    final next = <String>[], sc = <List<int>>[];
    for (var i = 0; i + 1 < slots.length; i += 2) {
      final a = slots[i], b = slots[i + 1];
      if (a.isEmpty || b.isEmpty) {
        next.add(a.isEmpty ? b : a);
        sc.add(const []);
        continue;
      }
      var (sa, sb) = _game(w, a, b, r);
      if (sa == sb) {
        // タイブレーク
        if (r.nextBool()) {
          sa++;
        } else {
          sb++;
        }
      }
      _result(w, a, b, sa, sb);
      next.add(sa > sb ? a : b);
      sc.add([sa, sb]);
    }
    c.scores.add(sc);
    c.rounds.add(next);
    if (next.length == 1) _finish(w, c);
  }

  static void _playLeagueRound(AmWorld w, AmComp c, int k, Random r) {
    var any = false;
    for (final g in c.games) {
      if (g[0] != k || g[3] >= 0) continue;
      final (sa, sb) = _game(w, c.teams[g[1]], c.teams[g[2]], r);
      g[3] = sa;
      g[4] = sb;
      _result(w, c.teams[g[1]], c.teams[g[2]], sa, sb);
      any = true;
    }
    if (any && c.games.every((g) => g[3] >= 0)) _finish(w, c);
  }

  static void _result(AmWorld w, String a, String b, int sa, int sb) {
    for (final (id, mine, theirs) in [(a, sa, sb), (b, sb, sa)]) {
      final t = w.team(id);
      if (t == null) continue;
      if (mine > theirs) {
        t.w++;
      } else if (mine < theirs) {
        t.l++;
      } else {
        t.d++;
      }
    }
  }

  /// リーグの順位表：[(チーム id, 勝, 敗, 分)]（勝率の順）
  static List<(String, int, int, int)> standings(AmComp c) {
    final w = List.filled(c.teams.length, 0), l = List.filled(c.teams.length, 0), d = List.filled(c.teams.length, 0);
    for (final g in c.games) {
      if (g[3] < 0) continue;
      if (g[3] > g[4]) {
        w[g[1]]++;
        l[g[2]]++;
      } else if (g[3] < g[4]) {
        w[g[2]]++;
        l[g[1]]++;
      } else {
        d[g[1]]++;
        d[g[2]]++;
      }
    }
    double pct(int i) => w[i] + l[i] == 0 ? 0 : w[i] / (w[i] + l[i]);
    final idx = List.generate(c.teams.length, (i) => i)..sort((a, b) => pct(b).compareTo(pct(a)));
    return [for (final i in idx) (c.teams[i], w[i], l[i], d[i])];
  }

  /// 大会が終わった：発掘済みの選手の成績を「アマ時代の成績」に、目立つ成績はチームの記録（表示しない）に残す
  static void _finish(AmWorld w, AmComp c) {
    c.done = true;
    final rankOf = <String, String>{};
    if (c.isLeague) {
      final st = standings(c);
      for (var i = 0; i < st.length; i++) {
        rankOf[st[i].$1] = '${i + 1}位（${st[i].$2}勝${st[i].$3}敗${st[i].$4 > 0 ? '${st[i].$4}分' : ''}）';
      }
    } else {
      for (final id in c.teams) {
        rankOf[id] = c.resultOf(id);
      }
    }
    final label = '${w.year} ${c.name}';
    for (final id in c.teams) {
      final res = rankOf[id] ?? '';
      final t = w.team(id);
      final notable = c.stage != 'pref' && c.stage != 'qual' || res == '優勝' || res == '準優勝' || res == 'ベスト4';
      if (t != null && notable) {
        t.history.add('$label $res');
        if (t.history.length > 30) t.history.removeAt(0);
      }
      for (final ap in w.playersOf(id)) {
        if (ap.cur.games > 0) ap.record.add('$label $res　${statLine(ap.player, ap.cur)}');
        ap.cur = PlayerStats();
      }
    }
  }

  /// 成績の短い行（打者：試合・打率・本塁打・打点、投手：試合・勝敗・防御率・奪三振）
  static String statLine(Player p, PlayerStats s) {
    if (p.isPitcher) {
      return '${s.pitchApps}試合 ${s.wins}勝${s.losses}敗 防御率${s.inningsPitched == 0 ? '-' : s.era.toStringAsFixed(2)} ${s.pitcherStrikeouts}奪三振';
    }
    final avg = s.atBats == 0 ? '-' : s.battingAverage.toStringAsFixed(3).replaceFirst('0.', '.');
    return '${s.games}試合 打率$avg ${s.homeRuns}本 ${s.rbi}打点';
  }

  // ───────── 試合（無名の部員は学校の強さに合った「型」） ─────────

  static final Map<String, List<Player>> _tmpl = {};
  static final PlayerStats _dummy = PlayerStats();

  /// 無名の部員の型（種類×強さの段階×先攻後攻）：打者9人＋投手4人
  static List<Player> _template(String kind, int strength, int side) {
    final b = (strength ~/ 5).clamp(0, 19);
    return _tmpl.putIfAbsent('$kind$b-$side', () {
      final s = b * 5 + 2;
      final ovr = switch (kind) { '高校' => 18 + s * 0.32, '大学' => 28 + s * 0.3, _ => 33 + s * 0.3 };
      final r = Random(b * 31 + side * 7 + kind.hashCode);
      int v(double m) => (m + (r.nextDouble() - 0.5) * 12).round().clamp(5, 95);
      return [
        for (var i = 0; i < 9; i++)
          Player(id: 'G$kind$b-$side-$i', isPitcher: false)
            ..contactLeft = v(ovr)
            ..contactRight = v(ovr)
            ..power = v(ovr - 3)
            ..eye = v(ovr + 8)
            ..run = v(ovr + 3)
            ..arm = v(ovr)
            ..catchSkill = v(ovr),
        for (var i = 0; i < 4; i++)
          Player(id: 'G$kind$b-$side-P$i', isPitcher: true)
            ..pitchPower = v(ovr - i * 2)
            ..control = v(ovr - i * 2)
            ..stamina = i == 0 ? 70 : 45
            ..velocity = Velo.lift((120 + v(ovr - i * 2) / 2).round(), amateur: true)
            ..clutchPitching = v(ovr),
      ];
    });
  }

  static QuickSide _side(AmWorld w, String teamId, int side) {
    final t = w.team(teamId)!;
    final tm = _template(t.kind, t.strength, side);
    final found = w.playersOf(teamId).map((a) => a.player).toList()..sort((a, b) => b.ovr.compareTo(a.ovr));
    final bats = [...found.where((p) => !p.isPitcher), ...tm.where((p) => !p.isPitcher)].take(9).toList();
    final pits = [...found.where((p) => p.isPitcher), ...tm.where((p) => p.isPitcher)].take(4).toList();
    return QuickSide(bats, pits.first, pits.sublist(1), null);
  }

  /// 1試合：(a の得点, b の得点)。a が先攻
  static (int, int) _game(AmWorld w, String a, String b, Random r) {
    final cur = {for (final x in [...w.playersOf(a), ...w.playersOf(b)]) x.id: x.cur};
    final g = QuickGame(r, (p) => cur[p.id] ?? _dummy, hitAdj: 0.03);
    return g.play(_side(w, a, 0), _side(w, b, 1));
  }
}
