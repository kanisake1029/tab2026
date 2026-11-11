import 'package:flutter/material.dart';
import '../models/team.dart';
import 'schedule_generator.dart';

/// 順位表の種類
enum StandingsKind { official, interleague, open }

/// 1球団の成績（試合結果から集計）
class TeamRecord {
  final Team team;
  int w = 0, l = 0, d = 0;
  int rs = 0, ra = 0;
  int scheduled = 0;          // その区分の総試合数（残り試合の計算用）
  final List<String> results = []; // 'W' / 'L' / 'D'（日付順）
  TeamRecord(this.team);

  int get games => w + l + d;
  int get remaining => (scheduled - games).clamp(0, 999);
  double get pct => (w + l) == 0 ? 0 : w / (w + l);
  String get pctText => pct.toStringAsFixed(3).replaceFirst(RegExp(r'^0'), '');
  int get diff => rs - ra;
  int get saving => w - l; // 貯金（マイナスは借金）

  /// 直近10試合「6-4」
  String get last10 {
    final r = results.length > 10 ? results.sublist(results.length - 10) : results;
    final ww = r.where((x) => x == 'W').length, ll = r.where((x) => x == 'L').length;
    return '$ww-$ll';
  }

  /// 連勝・連敗「3連勝」
  String get streak {
    if (results.isEmpty) return '-';
    final last = results.last;
    if (last == 'D') return '引分';
    int n = 0;
    for (int i = results.length - 1; i >= 0 && results[i] == last; i--) { n++; }
    return '$n${last == 'W' ? '連勝' : '連敗'}';
  }
}

bool _matchKind(Match m, StandingsKind k) {
  switch (k) {
    case StandingsKind.official:
      return m.matchType == 'LEAGUE' || m.matchType == 'INTERLEAGUE';
    case StandingsKind.interleague:
      return m.matchType == 'INTERLEAGUE';
    case StandingsKind.open:
      return m.matchType == 'OPEN';
  }
}

/// 12球団まとめの順位表を表す league の値
const allLeagues = 'ALL';

/// 順位表の範囲：公式戦はリーグ別、交流戦・オープン戦は12球団まとめ
String standingsScope(String league, StandingsKind kind) => kind == StandingsKind.official ? league : allLeagues;

/// 順位表。league は 'CL' / 'PL'、または allLeagues（12球団まとめ）。勝率 → 勝数の順
List<TeamRecord> computeStandings(List<Team> teams, List<Match> matches, String league, StandingsKind kind) {
  final recs = {
    for (final t in teams.where((t) => league == allLeagues ? (t.league == 'CL' || t.league == 'PL') : t.league == league)) t.id: TeamRecord(t),
  };
  final sorted = matches.where((m) => _matchKind(m, kind)).toList()..sort((a, b) => a.date.compareTo(b.date));
  for (final m in sorted) {
    for (final id in [m.homeTeamId, m.awayTeamId]) {
      recs[id]?.scheduled++;
    }
    if (m.homeScore == null || m.awayScore == null) continue;
    final h = recs[m.homeTeamId], a = recs[m.awayTeamId];
    final hs = m.homeScore!, as = m.awayScore!;
    if (h != null) {
      h.rs += hs; h.ra += as;
      if (hs > as) { h.w++; h.results.add('W'); } else if (hs < as) { h.l++; h.results.add('L'); } else { h.d++; h.results.add('D'); }
    }
    if (a != null) {
      a.rs += as; a.ra += hs;
      if (as > hs) { a.w++; a.results.add('W'); } else if (as < hs) { a.l++; a.results.add('L'); } else { a.d++; a.results.add('D'); }
    }
  }
  final list = recs.values.toList()
    ..sort((x, y) {
      final c = y.pct.compareTo(x.pct);
      return c != 0 ? c : y.w.compareTo(x.w);
    });
  return list;
}

/// 首位とのゲーム差（首位は「-」）
String gamesBehind(TeamRecord top, TeamRecord r) {
  if (identical(top, r)) return '-';
  final gb = ((top.w - r.w) + (r.l - top.l)) / 2;
  return gb.toStringAsFixed(1);
}

/// リーグの表示名
String leagueLabel(String league) => league == 'CL' ? 'Aリーグ' : (league == 'PL' ? 'Bリーグ' : (league == allLeagues ? '12球団' : league));

const List<Color> _teamPalette = [
  Color(0xFFF97316), Color(0xFFEAB308), Color(0xFF2563EB), Color(0xFFDC2626), Color(0xFF16A34A), Color(0xFF0EA5E9),
  Color(0xFFF2A900), Color(0xFF38BDF8), Color(0xFF64748B), Color(0xFF9333EA), Color(0xFF1E3A8A), Color(0xFF0E7490),
];

/// 球団の色（データに色がないので、球団の並び順で決まった色を割り当てる）
Color teamColor(List<Team> all, Team t) {
  if (t.uniformColor != 0) return Color(t.uniformColor);
  final i = all.indexWhere((x) => x.id == t.id);
  return _teamPalette[(i < 0 ? t.id.hashCode : i) % _teamPalette.length];
}

/// 球団の1文字（略称の頭文字）
String teamInitial(Team t) => t.initialName.isNotEmpty ? t.initialName : (t.shortName.isNotEmpty ? t.shortName.substring(0, 1) : t.name.substring(0, 1));

/// 球団の短い名前
String teamShort(Team t) => t.shortName.isNotEmpty ? t.shortName : t.name;

/// チーム成績（順位表の右側）：防御率（先発・救援）・打率・本塁打・盗塁・失策
class TeamStats {
  int outs = 0, er = 0, sOuts = 0, sEr = 0, rOuts = 0, rEr = 0;
  int ab = 0, h = 0, hr = 0, sb = 0, e = 0;
  static String _era(int er, int outs) => outs == 0 ? '-' : (er * 27 / outs).toStringAsFixed(2);
  String get era => _era(er, outs);
  String get starterEra => _era(sEr, sOuts);
  String get reliefEra => _era(rEr, rOuts);
  String get avg => ab == 0 ? '-' : (h / ab).toStringAsFixed(3).replaceFirst(RegExp(r'^0'), '');
}

/// 試合のボックススコアから集計する（先発＝その試合の投手の先頭）。
///  盗塁・失策は、ボックススコアに数が無い以前の試合では実況ログ（「盗成功」「エラー」の行）から数える
Map<String, TeamStats> computeTeamStats(List<Team> teams, List<Match> matches, StandingsKind kind) {
  final out = {for (final t in teams) t.id: TeamStats()};
  int outsOf(Object? ip) {
    final a = '${ip ?? '0'}'.split('.');
    return (int.tryParse(a[0]) ?? 0) * 3 + (a.length > 1 ? int.tryParse(a[1]) ?? 0 : 0);
  }
  for (final m in matches) {
    if (m.homeScore == null || !_matchKind(m, kind)) continue;
    final box = m.boxScore;
    if (box == null) continue;
    // 以前の試合の盗塁・失策（実況ログから。表の攻撃＝ビジターの攻撃、表の失策＝ホームの失策）
    final log = m.playByPlay ?? const <String>[];
    var hSb = 0, aSb = 0, hE = 0, aE = 0;
    if (box['homeSB'] == null || box['homeE'] == null) {
      var top = true;
      final head = RegExp(r'^【(\d+)回(表|裏)');
      for (final l in log) {
        final mm = head.firstMatch(l);
        if (mm != null) {
          top = mm.group(2) == '表';
          continue;
        }
        if (l.contains('盗成功')) {
          if (top) { aSb++; } else { hSb++; }
        }
        if (l.contains('エラー')) {
          if (top) { hE++; } else { aE++; }
        }
      }
    }
    for (final home in [true, false]) {
      final ts = out[home ? m.homeTeamId : m.awayTeamId];
      if (ts == null) continue;
      final pr = box[home ? 'homePitcher' : 'awayPitcher'];
      if (pr is Map) {
        var first = true;
        for (final v in pr.values) {
          final o = outsOf((v as Map)['ip']), e = (v['er'] ?? 0) as int;
          ts.outs += o;
          ts.er += e;
          if (first) {
            ts.sOuts += o;
            ts.sEr += e;
          } else {
            ts.rOuts += o;
            ts.rEr += e;
          }
          first = false;
        }
      }
      final br = box[home ? 'homeBatters' : 'awayBatters'];
      if (br is Map) {
        for (final v in br.values) {
          ts.ab += ((v as Map)['ab'] ?? 0) as int;
          ts.h += (v['h'] ?? 0) as int;
          ts.hr += (v['hr'] ?? 0) as int;
        }
      }
      ts.sb += (box[home ? 'homeSB' : 'awaySB'] as int?) ?? (home ? hSb : aSb);
      ts.e += (box[home ? 'homeE' : 'awayE'] as int?) ?? (home ? hE : aE);
    }
  }
  return out;
}

/// 優勝マジック（公式戦・リーグ別）：首位が残り試合で何勝すれば、ほかのどの球団が残りを全勝しても勝ち数で上回れないか。
///  null＝点灯していない（残り試合より多い、または首位でない）、0以下＝優勝決定
int? magicNumber(List<TeamRecord> recs) {
  if (recs.length < 2) return null;
  final top = recs.first;
  var need = 0;
  for (final r in recs.skip(1)) {
    need = need > (r.w + r.remaining - top.w + 1) ? need : (r.w + r.remaining - top.w + 1);
  }
  if (need <= 0) return 0;
  return need <= top.remaining ? need : null;
}

/// 順位表の「差」の欄：首位はマジック（M12）か「優勝」、優勝の可能性が無くなった球団は「×」を付ける
String gamesBehindLabel(List<TeamRecord> recs, TeamRecord r, {bool official = true}) {
  if (!official || recs.isEmpty) return gamesBehind(recs.first, r);
  final top = recs.first;
  if (identical(top, r)) {
    final m = magicNumber(recs);
    if (m == null) return '-';
    return m <= 0 ? '優勝' : 'M$m';
  }
  final gb = gamesBehind(top, r);
  return r.w + r.remaining < top.w ? '$gb×' : gb;
}
