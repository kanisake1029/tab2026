import 'dart:math';
import '../models/team.dart';
import '../utils/schedule_generator.dart';

/// 終わった試合の実況ログから、勝利・敗戦・セーブ・ホールドと自責点を、今の規則で付け直す（以前のセーブ用）。
///  試合中の判定（MatchSimulator._settlePa / _decide）と同じ考え方：
///  得点は先の塁の走者（＝引き継いだ走者）から入ったとみなし、その自責点は走者を出した投手に付く。
///  決勝点の走者を出した投手が敗戦投手。
class DecisionRebuild {
  static final _head = RegExp(r'^【(\d+)回(表|裏)');
  static final _pa = RegExp(r'^(.+?) (先発|救援) (.+?) vs (.+) (\d+)番 (.+)$');
  static final _change = RegExp(r'^【投手交代】(.+?): (.+?) → (.+)$');
  static final _bases = RegExp(r'\[(ランナー無し|[^\]]*塁[^\]]*)\]\s*$');
  static final _runs = RegExp(r'\((\d+)点追加\)');

  /// 結果：投手名（ホーム／ビジター別）→ 新しい判定（'勝'/'敗'/'S'/'H'/''）と自責点。救援勝利の投手
  static RebuildResult? run(Match m, Team home, Team away) {
    final log = m.playByPlay;
    final box = m.boxScore;
    if (log == null || log.isEmpty || box == null || m.homeScore == null) return null;
    final hIn = m.homeInningScores ?? const <int>[], aIn = m.awayInningScores ?? const <int>[];
    Map<String, dynamic> rowsOf(bool homeSide) => Map<String, dynamic>.from((box[homeSide ? 'homePitcher' : 'awayPitcher'] as Map?) ?? const {});
    final rows = {true: rowsOf(true), false: rowsOf(false)};
    int outsOf(bool side, String name) {
      final ip = '${(rows[side]![name] as Map?)?['ip'] ?? '0'}'.split('.');
      return (int.tryParse(ip[0]) ?? 0) * 3 + (ip.length > 1 ? int.tryParse(ip[1]) ?? 0 : 0);
    }
    final er = {for (final side in [true, false]) side: {for (final e in rows[side]!.entries) e.key: ((e.value as Map)['er'] ?? 0) as int}};
    final pitchers = {true: <String>[], false: <String>[]};
    final cur = <bool, String?>{true: null, false: null};
    final entry = {true: <String, List<int>>{}, false: <String, List<int>>{}};
    final exit = {true: <String, List<int>>{}, false: <String, List<int>>{}};
    final entryRunners = {true: <String, int>{}, false: <String, int>{}};
    final inherit = {true: <String, List<String>>{}, false: <String, List<String>>{}};
    final winCand = <bool, String>{}, loseCand = <bool, String>{}; // キー：リードした側がホームか
    var hs = 0, as = 0;

    // ---- 半イニングごとに、出来事（打席・投手交代）を集める ----
    final halves = <_Half>[];
    _Half? half;
    _Ev? lastPa;
    var pendingChange = <_Ev>[]; // 次の1球の塁の状態で、引き継ぐ走者の数が決まる
    for (final line in log) {
      final h = _head.firstMatch(line);
      if (h != null) {
        half = _Half(int.parse(h.group(1)!), h.group(2) == '表');
        halves.add(half);
        lastPa = null;
        continue;
      }
      final c = _change.firstMatch(line);
      if (c != null) {
        final teamName = c.group(1)!;
        final side = teamName == home.name ? true : (teamName == away.name ? false : null);
        if (side == null) continue;
        final ev = _Ev.change(side, c.group(2)!, c.group(3)!);
        if (half != null) {
          half.events.add(ev);
        } else {
          halves.add(_Half(0, true)..events.add(ev)); // 試合前（念のため）
        }
        pendingChange.add(ev);
        continue;
      }
      if (half == null) continue;
      final p = _pa.firstMatch(line);
      if (p != null) {
        final ev = _Ev.pa(p.group(3)!);
        half.events.add(ev);
        lastPa = ev;
        continue;
      }
      final b = _bases.firstMatch(line);
      if (b != null) {
        final n = b.group(1) == 'ランナー無し' ? 0 : '塁'.allMatches(b.group(1)!).length;
        if (lastPa != null && lastPa.basesBefore < 0) lastPa.basesBefore = n;
        for (final ev in pendingChange) {
          ev.basesBefore = n;
        }
        pendingChange = [];
      }
      if (lastPa != null) {
        var r = 0;
        final rm = _runs.firstMatch(line);
        if (rm != null) r = int.parse(rm.group(1)!);
        if (r == 0 && line.contains('押し出し')) r = 1;
        if (r == 0 && line.contains('スクイズ') && line.contains('成功')) r = 1;
        lastPa.runs += r;
        lastPa.erRuns += r; // 記録の文章に出る得点は自責点（暴投などで入った点は付け替えない）
      }
    }
    // 記録の文章に無い得点（暴投など）は、イニングの得点との差を、その半イニングの最後の打席に足す
    for (final hf in halves) {
      if (hf.inning == 0) continue;
      final pas = hf.events.where((e) => !e.isChange).toList();
      if (pas.isEmpty) continue;
      final got = pas.fold<int>(0, (s, e) => s + e.runs);
      final list = hf.top ? aIn : hIn;
      final actual = hf.inning <= list.length ? list[hf.inning - 1] : got;
      if (actual > got) pas.last.runs += actual - got;
      if (actual < got) {
        // 読み過ぎ（まれ）：後ろの打席から減らす
        var over = got - actual;
        for (final e in pas.reversed) {
          final d = min(over, e.runs);
          e.runs -= d;
          over -= d;
          if (over == 0) break;
        }
      }
    }

    // ---- 順に判定する ----
    for (final hf in halves) {
      final defSide = hf.top; // 表の攻撃ならホームが守り
      final evs = hf.events;
      for (var i = 0; i < evs.length; i++) {
        final ev = evs[i];
        if (ev.isChange) {
          final side = ev.side!;
          final my = side ? hs : as, opp = side ? as : hs;
          final old = cur[side] ?? ev.oldName!;
          if (!pitchers[side]!.contains(old)) pitchers[side]!.add(old);
          exit[side]![old] = [my, opp];
          entry[side]![ev.newName!] = [my, opp];
          if (!pitchers[side]!.contains(ev.newName)) pitchers[side]!.add(ev.newName!);
          final n = (side == defSide && hf.inning > 0 && ev.basesBefore > 0) ? ev.basesBefore : 0;
          final q = List<String>.of(inherit[side]![old] ?? const []);
          if (q.length > n) q.removeRange(n, q.length);
          while (q.length < n) {
            q.add(old);
          }
          inherit[side]![ev.newName!] = q;
          entryRunners[side]![ev.newName!] = n;
          cur[side] = ev.newName;
          continue;
        }
        // 打席
        final dp = ev.pitcher!;
        if (cur[defSide] == null) {
          cur[defSide] = dp;
          entry[defSide]![dp] = [0, 0];
        }
        if (!pitchers[defSide]!.contains(dp)) pitchers[defSide]!.add(dp);
        final off0 = hf.top ? as : hs, def0 = hf.top ? hs : as;
        final runs = ev.runs;
        final q = inherit[defSide]![dp] ?? <String>[];
        final consumed = runs > 0 ? q.take(runs).toList() : <String>[];
        if (consumed.isNotEmpty) q.removeRange(0, consumed.length);
        var movable = min(consumed.length, ev.erRuns);
        for (final r in consumed) {
          if (movable <= 0) break;
          movable--;
          if (r == dp) continue;
          if ((er[defSide]![dp] ?? 0) > 0) {
            er[defSide]![dp] = er[defSide]![dp]! - 1;
            er[defSide]![r] = (er[defSide]![r] ?? 0) + 1;
          }
        }
        if (hf.top) {
          as += runs;
        } else {
          hs += runs;
        }
        final off1 = off0 + runs;
        if (off0 <= def0 && off1 > def0) {
          final k = def0 - off0 + 1;
          final resp = k <= consumed.length ? consumed[k - 1] : dp;
          final offSide = !defSide;
          winCand[offSide] = cur[offSide] ?? '';
          loseCand[offSide] = resp;
        }
        // 次の打席の前の塁の走者（同じ半イニングの次の打席。無ければ 0）
        var after = 0;
        for (var j = i + 1; j < evs.length; j++) {
          if (!evs[j].isChange) {
            after = max(0, evs[j].basesBefore);
            break;
          }
        }
        if (q.length > after) q.removeRange(after, q.length);
        inherit[defSide]![dp] = q;
      }
    }
    // 先発（実況ログに投手が出てこない場合はボックススコアの先頭）
    for (final side in [true, false]) {
      if (pitchers[side]!.isEmpty && rows[side]!.isNotEmpty) pitchers[side]!.add(rows[side]!.keys.first);
    }

    // ---- 勝敗・セーブ・ホールド ----
    final res = RebuildResult(er);
    final d = m.homeScore! - m.awayScore!;
    String? winner, loser, saver;
    final wSide = d > 0;
    if (d != 0) {
      final wp = pitchers[wSide]!;
      int outs(String n) => outsOf(wSide, n);
      int e(String n) => er[wSide]![n] ?? 0;
      String? best(Iterable<String> ps) {
        String? b;
        for (final p in ps) {
          if (b == null || outs(p) - e(p) * 3 > outs(b) - e(b) * 3) b = p;
        }
        return b;
      }

      final starter = wp.first;
      winner = winCand[wSide] ?? starter;
      if (winner.isEmpty || !wp.contains(winner)) winner = starter;
      if (winner == starter) {
        if (outs(starter) < 15 && wp.length > 1) winner = best(wp.skip(1))!;
      } else {
        final i = wp.indexOf(winner);
        if (outs(winner) < 3 && e(winner) >= 1 && i + 1 < wp.length) winner = best(wp.skip(i + 1))!;
      }
      final lp = pitchers[!wSide]!;
      loser = loseCand[wSide];
      if (loser == null || !lp.contains(loser)) loser = lp.isEmpty ? null : lp.first;
      res.dec[(wSide, winner)] = '勝';
      if (winner != starter) res.reliefWin = (wSide, winner);
      if (loser != null) res.dec[(!wSide, loser)] = '敗';
      final last = wp.last;
      if (last != winner && last != starter && outs(last) >= 1) {
        final en = entry[wSide]![last] ?? [0, 0];
        final lead = en[0] - en[1];
        final runners = entryRunners[wSide]![last] ?? 0;
        if (lead >= 1 && ((lead <= 3 && outs(last) >= 3) || lead <= runners + 2 || outs(last) >= 9)) {
          saver = last;
          res.dec[(wSide, last)] = 'S';
        }
      }
    }
    for (final side in [true, false]) {
      final ps = pitchers[side]!;
      for (var i = 1; i < ps.length; i++) {
        final p = ps[i];
        if ((side == wSide && (p == winner || p == saver)) || (side != wSide && p == loser) || p == ps.last) continue;
        if (d != 0 && side == wSide && p == winner) continue;
        final en = entry[side]![p], x = exit[side]![p];
        if (en == null || x == null) continue;
        final leadIn = en[0] - en[1], leadOut = x[0] - x[1];
        final o = outsOf(side, p);
        final runners = entryRunners[side]![p] ?? 0;
        final saveSit = leadIn >= 1 && (leadIn <= 3 || leadIn <= runners + 2 || o >= 9);
        final tieHold = leadIn == 0 && leadOut >= 0 && x[1] == en[1];
        if (o >= 1 && ((saveSit && leadOut >= 1) || tieHold)) res.dec[(side, p)] = 'H';
      }
    }
    return res;
  }
}

class RebuildResult {
  /// (ホームか, 投手名) → 新しい判定
  final Map<(bool, String), String> dec = {};
  /// ホームか → 投手名 → 新しい自責点
  final Map<bool, Map<String, int>> er;
  (bool, String)? reliefWin;
  RebuildResult(this.er);
}

class _Half {
  final int inning;
  final bool top;
  final List<_Ev> events = [];
  _Half(this.inning, this.top);
}

class _Ev {
  final bool isChange;
  final bool? side; // 投手交代：ホームの交代か
  final String? oldName, newName, pitcher;
  int runs = 0;
  int erRuns = 0;
  int basesBefore = -1; // この出来事の直後の1球の時点の塁の走者の数
  _Ev.pa(this.pitcher) : isChange = false, side = null, oldName = null, newName = null;
  _Ev.change(this.side, this.oldName, this.newName) : isChange = true, pitcher = null;
}
