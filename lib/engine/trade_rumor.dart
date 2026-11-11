import 'dart:math';
import '../models/player.dart';
import '../models/team.dart';
import 'game_news.dart' show FanComment;
import 'item_news.dart';
import 'news_talk.dart';

/// トレード予想（評論家の推測記事）：毎週月曜、トレード期間（11月1日〜7月31日）に1本。
///  各球団の守備位置ごとの層を比べ、「片方が手薄で、相手には余っている」組み合わせを探して記事にする。
///  保存はせず、日付と球団の今の顔ぶれから毎回同じ記事を作る
class TradeRumor {
  static const _groups = ['捕手', '内野手', '外野手', '先発投手', '中継ぎ'];
  static const _k = {'捕手': 2, '内野手': 5, '外野手': 4, '先発投手': 5, '中継ぎ': 6};
  static const _critics = ['山根 誠一', '大川 剛', '佐伯 修', '黒沢 透', '森本 健吾'];

  static String _short(Team t) => t.shortName.isNotEmpty ? t.shortName : t.name;

  static String? groupOf(Team t, Player p) => _group(t, p);
  static Map<String, List<Player>> depthOf(Team t) => _depth(t);
  static double scoreOf(List<Player> l, String g) => _score(l, _k[g] ?? 5);

  static String? _group(Team t, Player p) {
    if (p.isPitcher) return t.rotation.take(t.rotationCount).contains(p.id) ? '先発投手' : '中継ぎ';
    return switch (p.mainPosition) {
      '捕手' => '捕手',
      '一塁手' || '二塁手' || '三塁手' || '遊撃手' => '内野手',
      '左翼手' || '中堅手' || '右翼手' => '外野手',
      _ => null,
    };
  }

  /// 球団の守備位置ごとの選手（総合の高い順）
  static Map<String, List<Player>> _depth(Team t) {
    final out = {for (final g in _groups) g: <Player>[]};
    for (final p in t.players.where((p) => !p.ikusei)) {
      final g = _group(t, p);
      if (g != null) out[g]!.add(p);
    }
    for (final l in out.values) {
      l.sort((a, b) => b.ovr.compareTo(a.ovr));
    }
    return out;
  }

  static double _score(List<Player> l, int k) => l.isEmpty ? 0 : l.take(k).fold<int>(0, (a, p) => a + p.ovr) / min(k, l.length);

  /// 今日までの月曜のうち、新しい順に count 本
  static List<ItemNews> recent(List<Team> teams, DateTime today, {String? myTeamId, int count = 3}) {
    final league = teams.where((t) => t.league == 'CL' || t.league == 'PL').toList();
    if (league.length < 4) return const [];
    // トレード期間の始まり（前の11月1日）
    final start = today.month >= 11 ? DateTime(today.year, 11, 1) : DateTime(today.year - 1, 11, 1);
    final end = DateTime(start.year + 1, 7, 31);
    var d = start;
    while (d.weekday != DateTime.monday) {
      d = d.add(const Duration(days: 1));
    }
    final mondays = <DateTime>[];
    while (!d.isAfter(today) && !d.isAfter(end)) {
      mondays.add(d);
      d = d.add(const Duration(days: 7));
    }
    final out = <ItemNews>[];
    for (var i = mondays.length - 1; i >= 0 && out.length < count; i--) {
      final n = _one(league, mondays[i], i + 1, myTeamId);
      if (n != null) out.add(n);
    }
    return out;
  }

  static ItemNews? _one(List<Team> teams, DateTime day, int no, String? myTeamId) {
    final r = Random(day.millisecondsSinceEpoch ~/ 86400000 * 31 + 7);
    final depth = {for (final t in teams) t.id: _depth(t)};
    final avg = {for (final g in _groups) g: teams.map((t) => _score(depth[t.id]![g]!, _k[g]!)).reduce((a, b) => a + b) / teams.length};
    // 候補：A は g1 が手薄・g2 に余裕、B はその逆
    final cands = <(double, Team, Team, String, String)>[];
    for (final a in teams) {
      for (final b in teams) {
        if (a == b) continue;
        for (final g1 in _groups) {
          for (final g2 in _groups) {
            if (g1 == g2) continue;
            final sA1 = _score(depth[a.id]![g1]!, _k[g1]!), sB1 = _score(depth[b.id]![g1]!, _k[g1]!);
            final sA2 = _score(depth[a.id]![g2]!, _k[g2]!), sB2 = _score(depth[b.id]![g2]!, _k[g2]!);
            if (sA1 >= avg[g1]! || sB1 <= avg[g1]! || sB2 >= avg[g2]! || sA2 <= avg[g2]!) continue;
            if (depth[b.id]![g1]!.length <= _k[g1]! || depth[a.id]![g2]!.length <= _k[g2]!) continue;
            cands.add(((avg[g1]! - sA1) + (sB1 - avg[g1]!) + (avg[g2]! - sB2) + (sA2 - avg[g2]!), a, b, g1, g2));
          }
        }
      }
    }
    if (cands.isEmpty) return null;
    cands.sort((x, y) => y.$1.compareTo(x.$1));
    // 毎週ちがう球団を主役に（球団の並びを週ごとに1つずつ回す）。その球団が絡む組み合わせが無ければ全体から
    // 主役の球団：その週の球団に組み合わせが無ければ次の球団へ
    var pool = <(double, Team, Team, String, String)>[];
    for (var k = 0; k < teams.length && pool.isEmpty; k++) {
      final focus = teams[(no + k) % teams.length].id;
      pool = cands.where((c) => c.$2.id == focus || c.$3.id == focus).toList();
    }
    // 相手の球団が偏らないよう、相手ごとに1つずつ（いちばん良い組み合わせ）にしてから選ぶ
    final byPartner = <String, (double, Team, Team, String, String)>{};
    for (final c in pool) {
      final key = '${c.$2.id}-${c.$3.id}';
      byPartner.putIfAbsent(key, () => c);
    }
    final opts = byPartner.values.toList();
    final (_, a, b, g1, g2) = opts[r.nextInt(opts.length)];
    // 出す選手：レギュラーのすぐ下（控えに回っている実力者）
    Player pick(List<Player> l, int k, Set<Player> used) {
      final bench = l.skip(k).where((p) => !used.contains(p)).take(3).toList();
      if (bench.isNotEmpty) return bench[r.nextInt(bench.length)];
      return l.lastWhere((p) => !used.contains(p), orElse: () => l.last);
    }

    // 世代交代を図る球団（その位置のレギュラーが高齢）は、ベテランを出す。そうでなければ控えの実力者
    final regB = depth[b.id]![g1]!.take(_k[g1]!).toList();
    final oldB = regB.fold<int>(0, (s, p) => s + p.age) / regB.length >= 29.5 && regB.any((p) => p.age >= 31);
    final used = <Player>{};
    final p1 = oldB ? (regB.where((p) => p.age >= 31).toList()..sort((x, y) => y.age.compareTo(x.age))).first : pick(depth[b.id]![g1]!, _k[g1]!, used); // B → A
    used.add(p1);
    final p2 = pick(depth[a.id]![g2]!, _k[g2]!, used); // A → B
    used.add(p2);
    // ときどき複数対複数（2対2・2対3など）：B は若手の控え、A は別の位置の控えを足す
    final fromB = [p1], fromA = [p2];
    final shape = r.nextInt(10); // 0〜4：1対1、5〜7：2対2、8〜9：2対3
    if (shape >= 5) {
      final extraA = [for (final g in _groups) if (g != g1) ...depth[a.id]![g]!.skip(_k[g]!)].where((p) => !used.contains(p) && p.age <= 27).toList();
      final extraB = [for (final g in _groups) if (g != g2) ...depth[b.id]![g]!.skip(_k[g]!)].where((p) => !used.contains(p) && p.age <= 27).toList();
      if (extraA.isNotEmpty) fromA.add(extraA[r.nextInt(extraA.length)]);
      if (extraB.isNotEmpty) fromB.add(extraB[r.nextInt(extraB.length)]);
      used.addAll([...fromA, ...fromB]);
      if (shape >= 8) {
        final more = extraB.where((p) => !used.contains(p)).toList();
        if (more.isNotEmpty) fromB.add(more[r.nextInt(more.length)]);
      }
    }
    final critic = _critics[r.nextInt(_critics.length)];
    final reasonB = oldB ? '世代交代を図る${_short(b)}' : '$g2を補強したい${_short(b)}';
    String names(List<Player> ps) => ps.map((p) => p.registeredName).join('・');
    final big = fromA.length + fromB.length >= 4;
    final headline = '【トレード予想 第$no弾】${_short(a)}と${_short(b)}が${fromA.length}対${fromB.length}の${big ? '大型' : ''}トレードか　評論家が占う';
    final body = [
      '野球評論家の$critic氏が、トレード市場の動きを占った。',
      '${_short(a)}は$g1の層が薄く、レギュラーを脅かす選手が見当たらない。一方で$g2には控えにも力のある選手がそろう。',
      oldB
          ? '${_short(b)}は$g1で若手の台頭があり、ベテランを放出してでも、手薄な$g2を埋めたい事情がある。'
          : '${_short(b)}は$g1に控えに回るほど人材が豊富だが、$g2は手薄だ。',
      '■${_short(a)}が出しそうな選手',
      for (final p in fromA) '${NewsTalk.prof(p)}　${NewsTalk.stats(p)}${NewsTalk.insight(p, r)}。',
      '■${_short(b)}が出しそうな選手',
      for (final p in fromB) '${NewsTalk.prof(p)}　${NewsTalk.stats(p)}${NewsTalk.insight(p, r)}。',
      '「$g1の層が薄い${_short(a)}と、$reasonBの間で思惑が一致すれば、${names(fromB)}と${names(fromA)}の${fromA.length + fromB.length > 2 ? '複数選手を絡めた' : ''}交換が成立してもおかしくない」と$critic氏。',
      'あくまで評論家の見立てで、両球団からの発表はない。',
    ];
    // コメント：A のファンと B のファン（自球団が絡めば自球団を先に）
    final mineIsB = b.id == myTeamId;
    final first = mineIsB ? b : a, second = mineIsB ? a : b;
    final ins = mineIsB ? fromA : fromB, outs = mineIsB ? fromB : fromA;
    List<FanComment> fans(bool firstSide) {
      final rr = Random(day.millisecondsSinceEpoch ~/ 86400000 + (firstSide ? 1 : 2));
      final inP = firstSide ? ins : outs, outP = firstSide ? outs : ins;
      final lines = [
        for (final p in inP) ...['${p.registeredName}来てくれたら最高やけど', '${p.registeredName}ならうちでレギュラー取れる'],
        for (final p in outP) ...['${p.registeredName}出すのはちょっと反対', '${p.registeredName}は出番ないし、新天地の方が幸せかも'],
        for (final p in [...inP, ...outP]) ...NewsTalk.fanInsight(p, rr),
        'このトレードはありやな',
        '評論家の妄想やろ',
        '実現したらおもろい',
        if (inP.length != outP.length) '${outP.length}対${inP.length}は釣り合ってるんか？',
        if (big) 'これだけ動いたら大ニュースやな',
      ];
      final names = ['名無しの${_short(firstSide ? first : second)}ファン', '現地組', 'ライトスタンドの民', '野球好きの会社員', 'トレード大好き'];
      return ItemNews.fanList(rr, lines, names, positive: true, extra: 1);
    }

    return ItemNews(NewsTopic.rumor, '${day.month}/${day.day}', headline, headline, body, ins.first, first, fans(true), fans(false), playerTeam: mineIsB ? a : b);
  }
}
