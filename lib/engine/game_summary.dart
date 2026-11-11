import 'dart:math';
import '../models/team.dart';
import '../utils/schedule_generator.dart';

/// 試合総評（アプリ内で自動作文）：試合の記録（1打席ごとの文章・ボックススコア・イニングの得点）から、
/// 試合の流れ・勝負所・投打の主役をまとめる。同じ試合はいつも同じ文章になる
class GameSummary {
  static String _short(Team t) => t.shortName.isNotEmpty ? t.shortName : t.name;

  static String generate(Match m, Team home, Team away) {
    final hs = m.homeScore ?? 0, as = m.awayScore ?? 0;
    final r = Random(Object.hash(m.date.millisecondsSinceEpoch, m.homeTeamId, m.awayTeamId));
    String pick(List<String> xs) => xs[r.nextInt(xs.length)];
    final homeWin = hs > as, draw = hs == as;
    final win = homeWin ? home : away, lose = homeWin ? away : home;
    final ws = max(hs, as), ls = min(hs, as);
    final hIn = m.homeInningScores ?? const <int>[], aIn = m.awayInningScores ?? const <int>[];
    final innings = max(hIn.length, aIn.length);
    final events = _events(m.playByPlay ?? const [], home, away, hIn, aIn);
    final log = (m.playByPlay ?? const []).join('\n');
    final walkOff = log.contains('サヨナラ');

    // ---- 得点の流れ（先制・同点・逆転・決勝点） ----
    var h = 0, a = 0;
    _Ev? first, decisive;
    var leadChanges = 0;
    var maxDeficitWinner = 0;
    int? lastLeader;
    for (final e in events) {
      final before = (h - a).sign;
      if (e.homeBat) {
        h += e.runs;
      } else {
        a += e.runs;
      }
      first ??= e;
      final after = (h - a).sign;
      if (after != before && after != 0 && lastLeader != null && lastLeader != after) leadChanges++;
      if (after != 0) lastLeader = after;
      final winnerDiff = homeWin ? h - a : a - h;
      if (!draw && winnerDiff < -maxDeficitWinner) maxDeficitWinner = -winnerDiff;
      // 勝った側がリードを奪った瞬間を、決勝点の候補にする（最後に奪ったものが決勝点）
      if (!draw && ((homeWin && after == 1 && before != 1) || (!homeWin && after == -1 && before != -1))) decisive = e;
    }

    // ---- 見出し ----
    String headline;
    if (draw) {
      headline = '${_short(away)} $as−$hs ${_short(home)}　${innings > 9 ? '延長$innings回、' : ''}引き分け';
    } else {
      final kind = walkOff
          ? 'サヨナラ勝ち'
          : ls == 0
              ? '完封勝ち'
              : maxDeficitWinner >= 3
                  ? '${maxDeficitWinner}点差をひっくり返す大逆転勝ち'
                  : maxDeficitWinner >= 1
                      ? '逆転勝ち'
                      : ws - ls >= 6
                          ? '大勝'
                          : ws + ls >= 14
                              ? '打撃戦を制す'
                              : ws <= 2
                                  ? '投手戦を制す'
                                  : ws - ls == 1
                                      ? '接戦を制す'
                                      : '勝利';
      headline = '${_short(win)}、${innings > 9 ? '延長$innings回の末に' : ''}$kind（$ws−$ls）';
    }

    final paras = <String>[];

    // ---- 流れ ----
    final flow = <String>[];
    if (events.isEmpty && ws + ls == 0) {
      flow.add(pick(['両軍の投手が譲らず、スコアボードに0が並んだ。', '最後まで両チームとも得点を奪えなかった。']));
    } else if (first != null) {
      final t = first.homeBat ? home : away;
      final half = '${first.inning}回${first.homeBat ? '裏' : '表'}';
      flow.add(r.nextBool()
          ? '$half、${_short(t)}が${first.what}で${first.runs}点を先制。'
          : '試合が動いたのは$half。${_short(t)}が${first.what}で先制点を奪った。');
    }
    final lastEv = events.isNotEmpty ? events.last : null;
    final walkOffDecisive = walkOff && !draw && lastEv != null && lastEv.homeBat && identical(decisive, lastEv);
    if (walkOffDecisive) {
      if (!identical(decisive, first)) flow.add(pick(['同点で迎えた', 'もつれた展開で迎えた']) + '${lastEv.inning}回裏、${lastEv.what}でサヨナラ勝ちを決めた。');
      if (identical(decisive, first)) flow.add('このサヨナラの一打が、試合唯一の得点だった。'.replaceAll('唯一の得点', ls == 0 ? '唯一の得点' : '決勝点'));
    } else if (!draw && decisive != null && !identical(decisive, first)) {
      final t = decisive.homeBat ? home : away;
      final verb = maxDeficitWinner > 0 ? pick(['逆転', 'ひっくり返した']) : (leadChanges > 0 ? '勝ち越し' : 'リードを広げた');
      flow.add('${decisive.inning}回${decisive.homeBat ? '裏' : '表'}、${_short(t)}は${decisive.what}${decisive.batter.isEmpty ? 'の得点' : ''}で${verb == 'リードを広げた' ? '${decisive.runs}点を加えて$verb' : verb}。この一打が決勝点となった。');
    } else if (!draw && decisive != null && identical(decisive, first)) {
      flow.add(pick(['この先制点を最後まで守り切った。', '先制点がそのまま決勝点となった。']));
    }
    if (walkOff && !draw && !walkOffDecisive && lastEv != null && lastEv.homeBat) flow.add('最後は${lastEv.inning}回裏、${lastEv.what}で試合を決めた。');
    // 大量点のイニング
    for (var i = 0; i < innings; i++) {
      final ar = i < aIn.length ? aIn[i] : 0, hr = i < hIn.length ? hIn[i] : 0;
      if (ar >= 4) flow.add('${i + 1}回表には${_short(away)}が打者一巡の攻撃などで${ar}点のビッグイニングを作った。');
      if (hr >= 4) flow.add('${i + 1}回裏には${_short(home)}が一挙${hr}点を挙げた。');
    }
    if (flow.isNotEmpty) paras.add(flow.join(''));

    // ---- 投手 ----
    final box = m.boxScore ?? const {};
    final pit = <String>[];
    Map<String, dynamic> rowsOf(String key) => Map<String, dynamic>.from((box[key] as Map?) ?? const {});
    final wp = rowsOf(homeWin ? 'homePitcher' : 'awayPitcher'), lp = rowsOf(homeWin ? 'awayPitcher' : 'homePitcher');
    String ip(Object? x) {
      final t = '${x ?? '0'}'.trim();
      final m2 = RegExp(r'^(\d+)\.(\d)$').firstMatch(t);
      if (m2 != null) {
        if (m2.group(2) == '0') return '${m2.group(1)}回';
        return m2.group(1) == '0' ? '${m2.group(2)}/3回' : '${m2.group(1)}回${m2.group(2)}/3';
      }
      return t.contains('回') ? t : '$t回';
    }

    String line(Map v) {
      final i = ip(v['ip']);
      return '$i${i.endsWith('回') ? '' : 'を投げ'}${v['er'] ?? 0}失点${(v['so'] ?? 0) > 0 ? '・${v['so']}奪三振' : ''}';
    }
    if (!draw) {
      final wName = wp.entries.where((e) => e.value is Map && e.value['dec'] == '勝').map((e) => e.key).firstOrNull;
      final sName = wp.entries.where((e) => e.value is Map && e.value['dec'] == 'S').map((e) => e.key).firstOrNull;
      final lName = lp.entries.where((e) => e.value is Map && e.value['dec'] == '敗').map((e) => e.key).firstOrNull;
      if (wName != null) {
        final v = wp[wName] as Map;
        final starter = wp.keys.first == wName;
        final er = (v['er'] ?? 0) as int;
        final inn = double.tryParse('${v['ip']}'.split(' ').first) ?? 0;
        final good = er <= 1 && inn >= 7;
        final made = inn >= 6 && er <= 3; // クオリティスタート
        pit.add(starter
            ? '${_short(win)}先発の$wNameは${line(v)}${good ? pick(['の好投', 'と相手打線を封じ込め']) : made ? 'で試合をつくり' : er >= 4 ? 'と苦しみながらも打線の援護に恵まれ' : 'と粘りの投球を見せ'}、勝ち投手に。'
            : '${_short(win)}は救援の$wNameに勝ちがついた（${line(v)}）。');
      }
      if (wName != null && ls == 0 && wp.length == 1) pit.add('$wNameは最後まで一人で投げ抜く完封劇だった。');
      if (sName != null) pit.add('最後は$sNameが${pick(['締めてセーブを挙げた', '反撃を断ってセーブを挙げた'])}。');
      if (lName != null) {
        final v = lp[lName] as Map;
        pit.add('${_short(lose)}の$lNameは${line(v)}で負け投手となった。');
      }
    } else {
      final hsP = rowsOf('homePitcher'), asP = rowsOf('awayPitcher');
      if (hsP.isNotEmpty && asP.isNotEmpty) pit.add('先発は${_short(away)}の${asP.keys.first}が${line(asP.values.first as Map)}、${_short(home)}の${hsP.keys.first}が${line(hsP.values.first as Map)}。');
    }
    if (pit.isNotEmpty) paras.add(pit.join(''));

    // ---- 打者の主役 ----
    final bat = <String>[];
    List<(String, Map)> heroes(String key) {
      final rows = rowsOf(key).entries.where((e) => e.value is Map).map((e) => (e.key, e.value as Map)).toList();
      double sc(Map v) => ((v['hr'] ?? 0) as int) * 3.0 + ((v['rbi'] ?? 0) as int) * 1.5 + ((v['h'] ?? 0) as int) * 1.0;
      rows.sort((x, y) => sc(y.$2).compareTo(sc(x.$2)));
      return rows.where((x) => sc(x.$2) >= 3).toList();
    }

    String feat(String name, Map v) {
      final h0 = (v['h'] ?? 0) as int, hr = (v['hr'] ?? 0) as int, rbi = (v['rbi'] ?? 0) as int, ab = (v['ab'] ?? 0) as int;
      final parts = <String>['$ab打数$h0安打'];
      if (hr > 0) parts.add(hr >= 2 ? '$hr本塁打' : '本塁打');
      if (rbi > 0) parts.add('$rbi打点');
      final tail = hr >= 2
          ? '1試合$hr発の大暴れ'
          : h0 >= 4
              ? '固め打ちの大当たり'
              : h0 >= 3
                  ? pick(['猛打賞の活躍', '3安打と大当たり'])
                  : hr == 1 && rbi >= 3
                      ? '値千金の一発'
                      : hr == 1
                          ? pick(['一発を放った', 'アーチをかけた'])
                          : rbi >= 3
                              ? '勝負強さを見せた'
                              : h0 >= 2
                                  ? pick(['マルチ安打と気を吐いた', '2安打で打線を引っ張った'])
                                  : '存在感を示した';
      return '$name（${parts.join('・')}）が$tail';
    }

    final wh = heroes(homeWin ? 'homeBatters' : 'awayBatters'), lh = heroes(homeWin ? 'awayBatters' : 'homeBatters');
    if (draw) {
      if (wh.isNotEmpty) bat.add('${_short(home)}は${feat(wh.first.$1, wh.first.$2)}。');
      if (lh.isNotEmpty) bat.add('${_short(away)}は${feat(lh.first.$1, lh.first.$2)}。');
    } else {
      if (wh.isNotEmpty) bat.add('打っては${feat(wh.first.$1, wh.first.$2)}。');
      if (wh.length > 1) bat.add('${pick(['さらに', 'また', ''])}${feat(wh[1].$1, wh[1].$2)}。');
      if (lh.isNotEmpty) {
        final v = lh.first.$2;
        bat.add('${_short(lose)}は${lh.first.$1}（${v['ab'] ?? 0}打数${v['h'] ?? 0}安打${(v['hr'] ?? 0) > 0 ? '・本塁打' : ''}${(v['rbi'] ?? 0) > 0 ? '・${v['rbi']}打点' : ''}）が${pick(['奮闘したが', '気を吐いたが', '意地を見せたが'])}、${pick(['あと一本が出なかった', '反撃は及ばなかった', '勝利にはつながらなかった'])}。');
      }
      if (wh.isEmpty && lh.isEmpty && ws <= 3) bat.add('両軍とも打線は${pick(['湿りがち', '沈黙気味'])}で、少ないチャンスをものにした${_short(win)}に軍配が上がった。');
    }
    if (bat.isNotEmpty) paras.add(bat.join(''));

    // ---- 締め ----
    final hits = '安打数は${_short(away)}${m.awayHits ?? 0}本、${_short(home)}${m.homeHits ?? 0}本。';
    paras.add(hits);
    return '$headline\n\n${paras.join('\n')}';
  }

  /// 試合展開のデータ（AI の文章と組にして貯め、将来 AI なしで総評を書く材料にする）
  static Map<String, dynamic> features(Match m, Team home, Team away) {
    final hIn = m.homeInningScores ?? const <int>[], aIn = m.awayInningScores ?? const <int>[];
    final evs = _events(m.playByPlay ?? const [], home, away, hIn, aIn);
    final box = m.boxScore ?? const <String, dynamic>{};
    // 点差の動き（先制・同点・逆転）
    var h = 0, a = 0, leadChanges = 0, ties = 0;
    int? leader;
    final flow = <Map<String, dynamic>>[];
    for (final e in evs) {
      if (e.homeBat) {
        h += e.runs;
      } else {
        a += e.runs;
      }
      final now = (h - a).sign;
      String tag = '';
      if (leader == null && now != 0) {
        tag = '先制';
      } else if (now == 0) {
        tag = '同点';
        ties++;
      } else if (leader != null && leader != 0 && now != leader) {
        tag = '逆転';
        leadChanges++;
      } else if (leader == 0 && now != 0) {
        tag = '勝ち越し';
      } else {
        tag = '追加点';
      }
      leader = now;
      flow.add({'inning': e.inning, 'half': e.homeBat ? '裏' : '表', 'team': e.homeBat ? 'home' : 'away', 'runs': e.runs, 'batter': e.batter, 'what': e.what, 'tag': tag, 'away': a, 'home': h});
    }
    List<Map<String, dynamic>> rows(String key, String side) => [
          for (final e in ((box[key] as Map?) ?? const {}).entries) {'team': side, 'name': e.key, ...Map<String, dynamic>.from(e.value as Map)},
        ];
    return {
      'date': m.date.toIso8601String().substring(0, 10),
      'type': m.matchType,
      'home': {'id': home.id, 'name': home.name, 'score': m.homeScore, 'hits': m.homeHits, 'innings': hIn},
      'away': {'id': away.id, 'name': away.name, 'score': m.awayScore, 'hits': m.awayHits, 'innings': aIn},
      'walkOff': (m.playByPlay ?? const []).any((l) => l.contains('サヨナラ')),
      'leadChanges': leadChanges,
      'ties': ties,
      'scoring': flow,
      'pitchers': [...rows('awayPitcher', 'away'), ...rows('homePitcher', 'home')],
      'batters': [...rows('awayBatters', 'away'), ...rows('homeBatters', 'home')].where((b) => (b['ab'] ?? 0) + (b['bb'] ?? 0) > 0).toList(),
      'mvp': box['mvp'],
    };
  }

  /// AI 総評に渡す事実（スコア・得点経過・投手成績・活躍した打者・自動作文の総評）
  static String facts(Match m, Team home, Team away) {
    final b = StringBuffer();
    final hIn = m.homeInningScores ?? const <int>[], aIn = m.awayInningScores ?? const <int>[];
    b.writeln('試合：${m.date.year}年${m.date.month}月${m.date.day}日　${away.name}（ビジター）${m.awayScore ?? 0} - ${m.homeScore ?? 0} ${home.name}（ホーム）');
    b.writeln('イニング：${_short(away)} ${aIn.join(' ')} ／ ${_short(home)} ${hIn.join(' ')}　安打 ${_short(away)}${m.awayHits ?? 0} ${_short(home)}${m.homeHits ?? 0}');
    final evs = _events(m.playByPlay ?? const [], home, away, hIn, aIn);
    if (evs.isNotEmpty) b.writeln('得点経過：${evs.map((e) => '${e.inning}回${e.homeBat ? '裏' : '表'}${_short(e.homeBat ? home : away)}${e.runs}点（${e.what}）').join('、')}');
    final box = m.boxScore ?? const <String, dynamic>{};
    for (final (key, t) in [('awayPitcher', away), ('homePitcher', home)]) {
      final ps = (box[key] as Map?) ?? const {};
      final first = ps.keys.isEmpty ? null : ps.keys.first;
      b.writeln('${_short(t)}の投手（登板順。先頭が先発、ほかは救援）：${ps.entries.map((e) {
        final v = e.value as Map;
        final role = e.key == first ? '（先発）' : '（救援）';
        final dec = v['dec'] == null ? '' : '【${v['dec']}】';
        final ip = '${v['ip']}'.split('.');
        return '${e.key}$role$dec ${ip[0]}回${ip.length > 1 && ip[1] != '0' ? '${ip[1]}/3' : ''} 自責${v['er']} ${v['so']}K ${v['bb']}四球';
      }).join('、')}');
    }
    for (final (key, t) in [('awayBatters', away), ('homeBatters', home)]) {
      final bs = (box[key] as Map?) ?? const {};
      final good = bs.entries.where((e) {
        final v = e.value as Map;
        return (v['h'] ?? 0) >= 2 || (v['hr'] ?? 0) > 0 || (v['rbi'] ?? 0) >= 2;
      }).map((e) {
        final v = e.value as Map;
        return '${e.key} ${v['ab']}打数${v['h']}安打${(v['hr'] ?? 0) > 0 ? ' ${v['hr']}本塁打' : ''}${(v['rbi'] ?? 0) > 0 ? ' ${v['rbi']}打点' : ''}';
      }).toList();
      if (good.isNotEmpty) b.writeln('${_short(t)}の主な打者：${good.join('、')}');
    }
    if (box['mvp'] != null) b.writeln('MVP：${box['mvp']}');
    b.writeln('参考（自動作文の総評。事実はこれと上の記録に合わせる）：${generate(m, home, away).replaceAll('\n', ' ')}');
    return b.toString();
  }

  /// 本塁打の一覧（打った順）：(ホームの攻撃か, 打者, 「3回表3ラン」のような説明)
  static List<(bool, String, String)> homeRuns(Match m, Team home, Team away) {
    final evs = _events(m.playByPlay ?? const [], home, away, m.homeInningScores ?? const [], m.awayInningScores ?? const []);
    return [
      for (final e in evs.where((e) => e.hr))
        (e.homeBat, e.batter, '${e.inning}回${e.homeBat ? '裏' : '表'}${e.runs == 4 ? '満塁' : (e.runs == 1 ? 'ソロ' : '${e.runs}ラン')}'),
    ];
  }

  /// 得点した打席（記録の文章から）
  static List<_Ev> _events(List<String> log, Team home, Team away, List<int> hIn, List<int> aIn) {
    final head = RegExp(r'^【(\d+)回(表|裏)');
    final pa = RegExp(r'^(.+?) (先発|救援) (.+?) vs (.+) (\d+)番 (.+)$');
    final runsRe = RegExp(r'\((\d+)点追加\)');
    var inning = 1;
    var top = true;
    var batter = '';
    final out = <_Ev>[];
    for (final line in log) {
      final h = head.firstMatch(line);
      if (h != null) {
        inning = int.parse(h.group(1)!);
        top = h.group(2) == '表';
        continue;
      }
      final p = pa.firstMatch(line);
      if (p != null) {
        batter = p.group(6)!;
        continue;
      }
      var runs = 0;
      final rm = runsRe.firstMatch(line);
      if (rm != null) runs = int.parse(rm.group(1)!);
      if (runs == 0 && line.contains('押し出し')) runs = 1;
      if (runs == 0 && line.contains('スクイズ') && line.contains('成功')) runs = 1;
      if (runs == 0) continue;
      out.add(_Ev(inning, !top, batter, runs, _what(line, batter, runs), hr: line.contains('ホームラン')));
    }
    // 記録の文章に無い得点（押し出し・暴投など）を、イニングの得点との差から補う（その回の最後に置く）
    final fixed = <_Ev>[];
    final n = max(hIn.length, aIn.length);
    for (var i = 1; i <= n; i++) {
      for (final homeBat in [false, true]) {
        final evs = out.where((e) => e.inning == i && e.homeBat == homeBat).toList();
        fixed.addAll(evs);
        final actual = homeBat ? (i <= hIn.length ? hIn[i - 1] : 0) : (i <= aIn.length ? aIn[i - 1] : 0);
        final got = evs.fold<int>(0, (a, e) => a + e.runs);
        if (actual > got) fixed.add(_Ev(i, homeBat, '', actual - got, '押し出しや暴投など'));
      }
    }
    return fixed;
  }

  static String _what(String line, String batter, int runs) {
    if (line.contains('ホームラン')) {
      final kind = runs == 4 ? '満塁ホームラン' : (runs == 1 ? 'ソロホームラン' : '$runsランホームラン');
      return '$batterの$kind';
    }
    if (line.contains('押し出し')) return '押し出しの四球';
    if (line.contains('スクイズ')) return '$batterのスクイズ';
    if (line.contains('犠牲フライ')) return '$batterの犠牲フライ';
    if (line.contains('エラー') || line.contains('悪送球')) return '相手のエラー';
    if (line.contains('ダブルプレー') || line.contains('併殺')) return '併殺崩れの間';
    if (line.contains('スリーベース') || line.contains('三塁打')) return '$batterのタイムリースリーベース';
    if (line.contains('ツーベース') || line.contains('二塁打')) return '$batterのタイムリーツーベース';
    if (line.contains('ヒット') || line.contains('安打')) return '$batterのタイムリー';
    if (line.contains('ゴロ')) return '$batterの内野ゴロの間';
    return '$batterの打席';
  }
}

class _Ev {
  final int inning;
  final bool homeBat;
  final String batter;
  final int runs;
  final String what;
  final bool hr;
  _Ev(this.inning, this.homeBat, this.batter, this.runs, this.what, {this.hr = false});
}
