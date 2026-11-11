import 'package:flutter/material.dart';
import '../engine/game_news.dart';
import '../models/team.dart';
import '../utils/schedule_generator.dart';
import '../utils/standings.dart';
import 'chip_grid.dart';
import 'item_news_card.dart' show headlineView;

const _ink = Color(0xFF0F172A);
const _sub = Color(0xFF64748B);
const _line = Color(0xFFE2E8F0);

/// 記事のチーム状況（公式戦：開幕戦・試合の前後の順位・連勝連敗）とコーチ名を、保存してある試合から作る
GameNewsContext? newsContext(dynamic app, Match m) {
  if (app == null) return null;
  try {
    final teams = List<Team>.from(app.teams as List);
    final matches = List<Match>.from(app.matches as List);
    const official = {'LEAGUE', 'INTERLEAGUE'};
    final isOfficial = official.contains(m.matchType);
    final opening = <bool, bool>{}, before = <bool, int?>{}, after = <bool, int?>{}, streak = <bool, int>{}, prevStreak = <bool, int>{}, coaches = <bool, Map<String, String>>{};
    var size = 6;
    for (final home in [true, false]) {
      final tid = home ? m.homeTeamId : m.awayTeamId;
      final t = teams.where((x) => x.id == tid).firstOrNull;
      if (t == null) continue;
      final staff = app.staffOf(t) as Map;
      coaches[home] = {
        for (final role in const ['監督', '打撃', '投手'])
          if (staff[role] != null) role: '${(staff[role] as dynamic).name}',
      };
      if (!isOfficial) continue;
      final mine = matches.where((x) => x.isPlayed && official.contains(x.matchType) && x.date.year == m.date.year && (x.homeTeamId == tid || x.awayTeamId == tid)).toList()..sort((a, b) => a.date.compareTo(b.date));
      final idx = mine.indexOf(m);
      if (idx < 0) continue;
      opening[home] = idx == 0;
      // 連勝・連敗（この試合を含めてさかのぼる）
      var s = 0;
      for (var i = idx; i >= 0; i--) {
        final x = mine[i];
        final my = x.homeTeamId == tid ? x.homeScore! : x.awayScore!, op = x.homeTeamId == tid ? x.awayScore! : x.homeScore!;
        final r = my > op ? 1 : (my < op ? -1 : 0);
        if (r == 0 || (s != 0 && r.sign != s.sign)) break;
        s += r;
      }
      streak[home] = s;
      // この試合の前の流れ
      var p = 0;
      for (var i = idx - 1; i >= 0; i--) {
        final x = mine[i];
        final my = x.homeTeamId == tid ? x.homeScore! : x.awayScore!, op = x.homeTeamId == tid ? x.awayScore! : x.homeScore!;
        final r = my > op ? 1 : (my < op ? -1 : 0);
        if (r == 0 || (p != 0 && r.sign != p.sign)) break;
        p += r;
      }
      prevStreak[home] = p;
      // 順位（その日の前とこの試合のあと）
      final lg = t.league;
      final lgTeams = teams.where((x) => x.league == lg).toList();
      size = lgTeams.length;
      int? rankOf(List<Match> ms) {
        final st = computeStandings(lgTeams, ms, lg, StandingsKind.official);
        final i = st.indexWhere((r) => r.team.id == tid);
        return i < 0 ? null : i + 1;
      }

      // 順位は5試合目から（開幕直後は全球団が並ぶため）
      if (idx >= 4) {
        before[home] = rankOf([for (final x in matches) if (x.isPlayed && x.date.isBefore(m.date)) x]);
        after[home] = rankOf([for (final x in matches) if (x.isPlayed && !x.date.isAfter(m.date)) x]);
      }
    }
    return GameNewsContext(opening: opening, rankBefore: before, rankAfter: after, leagueSize: size, streak: streak, prevStreak: prevStreak, coaches: coaches);
  } catch (_) {
    return null;
  }
}

/// ネットニュース風の試合記事（一覧の1枚）。押すと記事とコメント欄を浮かせて出す
class GameNewsCard extends StatelessWidget {
  final Match match;
  final Team home, away;
  final List<Team> teams;
  final String? myTeamId;
  final dynamic app;
  const GameNewsCard({super.key, required this.match, required this.home, required this.away, required this.teams, this.myTeamId, this.app});

  @override
  Widget build(BuildContext context) {
    final n = GameNews.of(match, home, away, myTeamId: myTeamId, ctx: newsContext(app, match));
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showGameNews(context, match, home, away, teams, myTeamId: myTeamId, app: app),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _banner(match, home, away, teams, small: true),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(color: const Color(0xFFDC2626), borderRadius: BorderRadius.circular(3)),
                  child: const Text('ペナントスポーツ', style: TextStyle(fontSize: 9.5, color: Colors.white, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 6),
                Text('${match.date.month}/${match.date.day} 試合速報', style: const TextStyle(fontSize: 10.5, color: _sub)),
                const Spacer(),
                const Icon(Icons.chat_bubble_outline, size: 13, color: _sub),
                Text(' ${n.awayFans.length + n.homeFans.length}', style: const TextStyle(fontSize: 11, color: _sub)),
              ]),
              const SizedBox(height: 4),
              headlineView(n.headline, size: 15.5),
              const SizedBox(height: 4),
              Text(n.lead, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, height: 1.5, color: Color(0xFF334155))),
              const SizedBox(height: 4),
              const Text('記事とコメントを読む ›', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF2563EB))),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// 記事の上の帯（両軍の色とスコア）
Widget _banner(Match m, Team home, Team away, List<Team> teams, {bool small = false}) {
  final ac = teamColor(teams, away), hc = teamColor(teams, home);
  final st = TextStyle(fontSize: small ? 15 : 18, fontWeight: FontWeight.w900, color: Colors.white);
  return Container(
    height: small ? 54 : 72,
    decoration: BoxDecoration(gradient: LinearGradient(colors: [ac, ac.withValues(alpha: 0.85), hc.withValues(alpha: 0.85), hc], stops: const [0, 0.48, 0.52, 1])),
    padding: const EdgeInsets.symmetric(horizontal: 14),
    child: Row(children: [
      Expanded(child: Text(away.shortName.isNotEmpty ? away.shortName : away.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: st)),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        decoration: BoxDecoration(color: const Color(0xCC0B1626), borderRadius: BorderRadius.circular(6)),
        child: Text('${m.awayScore ?? 0} − ${m.homeScore ?? 0}', style: st.copyWith(fontSize: small ? 18 : 24, fontFeatures: const [FontFeature.tabularFigures()])),
      ),
      Expanded(child: Text(home.shortName.isNotEmpty ? home.shortName : home.name, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.right, style: st)),
    ]),
  );
}

/// 記事を浮かせて出す：本文・MVP のコメント・下にファンのコメント（自球団／他球団の2タブ）
Future<void> showGameNews(BuildContext context, Match m, Team home, Team away, List<Team> teams, {String? myTeamId, dynamic app}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    builder: (c) => SizedBox(height: MediaQuery.of(c).size.height * 0.88, child: _Article(m: m, home: home, away: away, teams: teams, myTeamId: myTeamId, app: app)),
  );
}

class _Article extends StatefulWidget {
  final Match m;
  final Team home, away;
  final List<Team> teams;
  final String? myTeamId;
  final dynamic app;
  const _Article({required this.m, required this.home, required this.away, required this.teams, this.myTeamId, this.app});
  @override
  State<_Article> createState() => _ArticleState();
}

class _ArticleState extends State<_Article> {
  late final GameNews n = GameNews.of(widget.m, widget.home, widget.away, myTeamId: widget.myTeamId, ctx: newsContext(widget.app, widget.m));
  // 自球団の試合なら「自球団」を先に。そうでなければホーム
  late bool _homeTab = widget.myTeamId == widget.away.id ? false : true;

  @override
  Widget build(BuildContext context) {
    final m = widget.m;
    final mine = widget.myTeamId;
    String tabName(Team t) => t.id == mine ? '自球団（${teamShort(t)}）' : (mine == widget.home.id || mine == widget.away.id ? '他球団（${teamShort(t)}）' : '${teamShort(t)}ファン');
    final firstHome = mine != widget.away.id;
    final tabs = firstHome ? [(true, tabName(widget.home)), (false, tabName(widget.away))] : [(false, tabName(widget.away)), (true, tabName(widget.home))];
    final list = _homeTab ? n.homeFans : n.awayFans;
    final mvpTeam = n.mvp == null ? null : (n.mvp!.home ? widget.home : widget.away);
    return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
      Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(color: const Color(0xFFDC2626), borderRadius: BorderRadius.circular(3)),
          child: const Text('ペナントスポーツ', style: TextStyle(fontSize: 10.5, color: Colors.white, fontWeight: FontWeight.w800)),
        ),
        const SizedBox(width: 8),
        Text('${m.date.year}/${m.date.month}/${m.date.day} 試合速報', style: const TextStyle(fontSize: 11.5, color: _sub)),
      ]),
      const SizedBox(height: 6),
      headlineView(n.headline, size: 20),
      const SizedBox(height: 10),
      ClipRRect(borderRadius: BorderRadius.circular(8), child: _banner(m, widget.home, widget.away, widget.teams)),
      const SizedBox(height: 10),
      Text(n.lead, style: const TextStyle(fontSize: 14.5, height: 1.75, fontWeight: FontWeight.w700, color: _ink)),
      const SizedBox(height: 6),
      for (final p in n.body) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(p, style: const TextStyle(fontSize: 14, height: 1.8, color: Color(0xFF1E293B)))),
      if (n.mvp != null) ...[
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFFFFFBEB), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFFCD34D))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(color: const Color(0xFFB45309), borderRadius: BorderRadius.circular(3)),
                child: const Text('試合MVP', style: TextStyle(fontSize: 10.5, color: Colors.white, fontWeight: FontWeight.w900)),
              ),
              const SizedBox(width: 8),
              if (mvpTeam != null) Container(width: 4, height: 16, color: teamColor(widget.teams, mvpTeam)),
              const SizedBox(width: 4),
              Expanded(child: Text('${n.mvp!.name}${mvpTeam == null ? '' : '（${teamShort(mvpTeam)}）'}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900))),
            ]),
            if (n.mvp!.line.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(n.mvp!.line, style: const TextStyle(fontSize: 12.5, color: Color(0xFF92400E), fontWeight: FontWeight.w700))),
            if (n.quote != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(n.quote!, style: const TextStyle(fontSize: 13.5, height: 1.6, color: _ink))),
          ]),
        ),
      ],
      const SizedBox(height: 16),
      Row(children: [
        const Icon(Icons.forum_outlined, size: 18),
        const SizedBox(width: 6),
        Text('コメント（${n.awayFans.length + n.homeFans.length}件）', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
      ]),
      const SizedBox(height: 6),
      ChipGrid<bool>(items: tabs, selected: _homeTab, minWidth: 120, padding: EdgeInsets.zero, onSelect: (v) => setState(() => _homeTab = v)),
      const SizedBox(height: 6),
      for (final c in list)
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _line))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CircleAvatar(radius: 13, backgroundColor: c.positive ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2), child: Icon(Icons.person, size: 16, color: c.positive ? const Color(0xFF15803D) : const Color(0xFFB91C1C))),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(child: Text(c.user, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: _sub, fontWeight: FontWeight.w700))),
                  Text('　${c.ago}', style: const TextStyle(fontSize: 10.5, color: Color(0xFF94A3B8))),
                ]),
                Text(c.text, style: const TextStyle(fontSize: 13.5, height: 1.5, color: _ink)),
                Row(children: [
                  const Icon(Icons.thumb_up_alt_outlined, size: 13, color: _sub),
                  Text(' ${c.likes}', style: const TextStyle(fontSize: 11, color: _sub)),
                ]),
              ]),
            ),
          ]),
        ),
      if (list.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('コメントはまだありません', style: TextStyle(color: _sub))),
    ]);
  }
}
