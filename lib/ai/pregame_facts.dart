import '../models/player.dart';
import '../models/team.dart';
import '../providers/app_state.dart';
import '../utils/schedule_generator.dart';
import '../utils/standings.dart';
import 'ai_facts.dart';
import 'ai_writer.dart';

/// 試合前の「見どころ」に渡す事実：順位・シリーズの状況・両先発の直近の登板・注目打者の直近／この球場／対先発の成績
class AiPregame {
  static String _rate(double v) => v.toStringAsFixed(3).replaceFirst('0.', '.');
  static String _short(Team t) => t.shortName.isNotEmpty ? t.shortName : t.name;
  static const _typeLabel = {'OPEN': 'オープン戦', 'LEAGUE': '公式戦', 'INTERLEAGUE': '交流戦', 'CS': 'クライマックスシリーズ', 'JS': '日本シリーズ'};

  /// 試合のボックススコアから、その球団の選手の行（無ければ null）
  static Map? _line(Match m, Team t, Player p, {required bool pitcher}) {
    final box = m.boxScore;
    if (box == null) return null;
    final side = m.homeTeamId == t.id ? 'home' : (m.awayTeamId == t.id ? 'away' : null);
    if (side == null) return null;
    final rows = box['$side${pitcher ? 'Pitcher' : 'Batters'}'] as Map?;
    return rows?[p.registeredName] as Map?;
  }

  /// イニング表記 "6.2" → 6回2/3
  static String _ip(String s) {
    final a = s.split('.');
    return '${a[0]}回${a.length > 1 && a[1] != '0' ? '${a[1]}/3' : ''}';
  }

  static int _outs(String s) {
    final a = s.split('.');
    return (int.tryParse(a[0]) ?? 0) * 3 + (a.length > 1 ? int.tryParse(a[1]) ?? 0 : 0);
  }

  /// シリーズの状況（CS・日本シリーズ）と順位。after=true なら試合後（この試合の結果を含む）
  static void context(StringBuffer b, AppState app, Match m, Team home, Team away, {bool after = false}) {
    if (after) b.writeln('（以下のシリーズ・順位は、この試合の結果を含む）');
    // シリーズの状況（CS・日本シリーズ）
    for (final s in app.postseason) {
      final pair = {s.high, s.low};
      if (!pair.contains(home.id) || !pair.contains(away.id) || !s.matchIdx.contains(app.matches.indexOf(m))) continue;
      if (s.winner.isNotEmpty && !after) continue;
      final (h, l, d, n) = s.tally(app.matches);
      final hi = s.high == home.id ? home : away, lo = s.high == home.id ? away : home;
      final done = h >= s.winsNeeded ? hi : (l >= s.winsNeeded ? lo : null);
      b.writeln('シリーズ：${s.label}（${s.winsNeeded}勝で勝ち抜け。${s.advantage > 0 ? '上位の${_short(hi)}にアドバンテージ${s.advantage}勝を含む。' : ''}）ここまで${_short(hi)}$h勝・${_short(lo)}$l勝${d > 0 ? '・$d分' : ''}（$n試合消化）');
      if (done != null) b.writeln('　${_short(done)}が勝ち抜けを決めた。');
      if (done == null && h == s.winsNeeded - 1) b.writeln('　${_short(hi)}は勝ち抜けに王手。${l < s.winsNeeded - 1 ? '${_short(lo)}は負ければ敗退（後がない）。' : ''}');
      if (done == null && l == s.winsNeeded - 1) b.writeln('　${_short(lo)}は勝ち抜けに王手。${h < s.winsNeeded - 1 ? '${_short(hi)}は負ければ敗退（後がない）。' : ''}');
    }
    // 順位（公式戦）
    // 試合後は、その試合の直後（翌日まで）に書くときだけ（後から開くと今の順位になってしまうため）
    final fresh = !after || app.currentDate.difference(m.date).inDays <= 1;
    if ((m.matchType == 'LEAGUE' || m.matchType == 'INTERLEAGUE') && fresh) {
      for (final t in [away, home]) {
        final st = computeStandings(app.teams, app.matches, t.league, StandingsKind.official);
        final i = st.indexWhere((r) => r.team.id == t.id);
        if (i < 0) continue;
        final r = st[i], top = st.first;
        final gb = ((top.w - r.w) - (top.l - r.l)) / 2;
        final last10 = r.results.length > 10 ? r.results.sublist(r.results.length - 10) : r.results;
        var streak = 0;
        for (final x in r.results.reversed) {
          if (x != r.results.last) break;
          streak++;
        }
        b.writeln('${_short(t)}：${leagueLabel(t.league)}${i + 1}位 ${r.w}勝${r.l}敗${r.d}分${i > 0 ? '（首位と${gb.toStringAsFixed(1).replaceAll('.0', '')}ゲーム差）' : ''}　直近10試合${last10.where((x) => x == 'W').length}勝${last10.where((x) => x == 'L').length}敗${r.results.isNotEmpty && streak >= 2 ? '　${streak}連${r.results.last == 'W' ? '勝' : (r.results.last == 'L' ? '敗' : '分')}中' : ''}');
      }
    }
  }

  /// 試合寸評に足す状況（シリーズ・順位）
  static String contextText(AppState app, Match m, Team home, Team away) {
    final b = StringBuffer();
    context(b, app, m, home, away, after: true);
    final t = b.toString();
    return t.split('\n').where((l) => l.trim().isNotEmpty).length <= 1 ? '' : t;
  }

  static AiItem item(AppState app, Match m, Team home, Team away) {
    final b = StringBuffer();
    final played = [for (final x in app.matches) if (x.homeScore != null && x.date.isBefore(m.date) && x.matchType != 'ALLSTAR') x]..sort((a, c) => c.date.compareTo(a.date));
    b.writeln('試合：${m.date.month}月${m.date.day}日　${_typeLabel[m.matchType] ?? m.matchType}　${away.name}（ビジター）対 ${home.name}（ホーム・${_short(home)}の本拠地）');

    context(b, app, m, home, away);
    // 今季の対戦成績
    var hw = 0, aw = 0, dd = 0;
    for (final x in played) {
      if (x.matchType == 'OPEN' || !({x.homeTeamId, x.awayTeamId}.containsAll({home.id, away.id}))) continue;
      final hs = x.homeTeamId == home.id ? x.homeScore! : x.awayScore!, as = x.homeTeamId == home.id ? x.awayScore! : x.homeScore!;
      if (hs > as) {
        hw++;
      } else if (as > hs) {
        aw++;
      } else {
        dd++;
      }
    }
    if (hw + aw + dd > 0) b.writeln('今季の直接対決：${_short(home)}$hw勝・${_short(away)}$aw勝${dd > 0 ? '・$dd分' : ''}');
    // 直前の直接対決
    final prev = played.where((x) => {x.homeTeamId, x.awayTeamId}.containsAll({home.id, away.id})).firstOrNull;
    if (prev != null) {
      final ph = prev.homeTeamId == home.id;
      b.writeln('前回の対戦（${prev.date.month}月${prev.date.day}日${m.date.difference(prev.date).inDays <= 1 ? '・前日' : ''}）：${_short(home)} ${ph ? prev.homeScore : prev.awayScore} - ${ph ? prev.awayScore : prev.homeScore} ${_short(away)}');
    }

    // 両先発
    Player? find(Team t, String? id) => id == null ? null : t.players.where((p) => p.id == id).firstOrNull;
    final book = app.matchups;
    for (final (t, opp) in [(away, home), (home, away)]) {
      final sp = find(t, t.todaysStarterId);
      if (sp == null) continue;
      final s = sp.seasonStats;
      b.writeln('${_short(t)}の今日の先発：${sp.listName}（${sp.throws == 'L' ? '左' : '右'}投・${sp.age}歳）今季${AiFacts.pitchLine(s)}');
      final apps = <String>[];
      var outs = 0, er = 0, so = 0;
      for (final x in played) {
        if (apps.length >= 4) break;
        final l = _line(x, t, sp, pitcher: true);
        if (l == null) continue;
        final rows = (x.boxScore?[x.homeTeamId == t.id ? 'homePitcher' : 'awayPitcher'] as Map?) ?? const {};
        final role = rows.keys.isNotEmpty && rows.keys.first == sp.registeredName ? '先発' : '救援';
        apps.add('${x.date.month}/${x.date.day} $role ${_ip('${l['ip']}')} 自責${l['er']} ${l['so']}奪三振${l['dec'] != null ? '【${l['dec']}】' : ''}');
        outs += _outs('${l['ip']}');
        er += (l['er'] ?? 0) as int;
        so += (l['so'] ?? 0) as int;
      }
      if (apps.isNotEmpty) b.writeln('　直近${apps.length}登板（先発か救援かは各登板の記述どおり）：${apps.join('、')}（計${outs ~/ 3}回${outs % 3 > 0 ? '${outs % 3}/3' : ''} 自責$er $so奪三振）');
      // この相手との今季
      var vo = 0, ve = 0, vn = 0;
      for (final x in played) {
        if (!{x.homeTeamId, x.awayTeamId}.contains(opp.id)) continue;
        final l = _line(x, t, sp, pitcher: true);
        if (l == null) continue;
        vn++;
        vo += _outs('${l['ip']}');
        ve += (l['er'] ?? 0) as int;
      }
      if (vn > 0) b.writeln('　${_short(opp)}戦は今季$vn登板 ${vo ~/ 3}回${vo % 3 > 0 ? '${vo % 3}/3' : ''} 自責$ve（防御率${vo == 0 ? '-' : (ve * 27 / vo).toStringAsFixed(2)}）');
    }

    // 注目打者（各球団2人）：今季・直近5試合・この球場・相手先発との対戦
    for (final (t, opp) in [(away, home), (home, away)]) {
      final oppSp = find(opp, opp.todaysStarterId);
      final bats = [for (final e in t.lineup) find(t, e.playerId)].whereType<Player>().where((p) => !p.isPitcher || p.twoWay).toList()
        ..sort((a, c) {
          double sc(Player p) => p.ovr + (p.seasonStats.atBats >= 30 ? (p.seasonStats.ops - 0.7) * 60 + p.seasonStats.homeRuns * 0.8 : 0);
          return sc(c).compareTo(sc(a));
        });
      for (final p in bats.take(2)) {
        b.writeln('${_short(t)}の注目打者：${p.listName}（${p.mainPosition}）今季${AiFacts.batLine(p.seasonStats)}');
        var ab = 0, h = 0, hr = 0, rbi = 0, g = 0;
        var pab = 0, ph = 0, phr = 0;
        String? lastGame;
        for (final x in played) {
          final l = _line(x, t, p, pitcher: false);
          if (l == null) continue;
          if (lastGame == null) {
            lastGame = '${x.date.month}/${x.date.day} ${l['ab']}打数${l['h']}安打${(l['hr'] ?? 0) > 0 ? ' ${l['hr']}本塁打' : ''}${(l['rbi'] ?? 0) > 0 ? ' ${l['rbi']}打点' : ''}';
          }
          if (g < 5) {
            ab += (l['ab'] ?? 0) as int;
            h += (l['h'] ?? 0) as int;
            hr += (l['hr'] ?? 0) as int;
            rbi += (l['rbi'] ?? 0) as int;
            g++;
          }
          if (x.homeTeamId == home.id && x.matchType != 'OPEN') {
            pab += (l['ab'] ?? 0) as int;
            ph += (l['h'] ?? 0) as int;
            phr += (l['hr'] ?? 0) as int;
          }
        }
        if (lastGame != null) b.writeln('　前の試合：$lastGame');
        if (g > 0) b.writeln('　直近$g試合：$ab打数$h安打 $hr本塁打 $rbi打点');
        if (pab >= 8) b.writeln('　${_short(home)}の本拠地では今季 $pab打数$ph安打（打率${_rate(ph / pab)}）$phr本塁打');
        if (oppSp != null) {
          final v = book.of(oppSp.id, p.id);
          if (v.pa > 0) b.writeln('　今日の相手先発${oppSp.lastName}との今季対戦：${v.pa}打席 ${v.summary}（打率${v.avgText}）');
        }
      }
    }
    final key = 'pregame:${m.date.toIso8601String().substring(0, 10)}:${m.homeTeamId}:${m.awayTeamId}:${home.todaysStarterId}:${away.todaysStarterId}';
    return AiItem(key, 'pregame', b.toString(), features: {
      'date': m.date.toIso8601String().substring(0, 10),
      'type': m.matchType,
      'home': home.id,
      'away': away.id,
      'homeStarter': home.todaysStarterId,
      'awayStarter': away.todaysStarterId,
    });
  }}
