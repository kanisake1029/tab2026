import 'news_archive_screen.dart';
import '../engine/item_news.dart';
import '../engine/trade_rumor.dart';
import '../engine/offseason_news.dart';
import '../widgets/item_news_card.dart';
import 'settings_menu_screen.dart';
import 'package:flutter/material.dart';
import '../providers/app_state.dart';
import '../engine/roster_engine.dart';
import '../models/player.dart';
import '../models/team.dart';
import '../utils/schedule_generator.dart'; // Match
import '../utils/standings.dart';
import '../utils/grade_utils.dart';
import '../utils/app_theme.dart';
import '../engine/match_simulator.dart';
import '../widgets/condition_face.dart';
import '../widgets/season_report_dialog.dart';
import 'awards_screen.dart';
import 'title_race.dart';
import 'live_game_screen.dart';
import 'pre_game_screen.dart';
import 'standings_screen.dart';
import 'draft_screen.dart';
import 'active_draft_screen.dart';
import 'finance_screens.dart';
import 'camp_screen.dart';
import 'front_screens.dart';
import '../utils/news_kind.dart';
import '../widgets/player_avatar.dart';

/// ホーム（ダッシュボード）
///  今日の試合（対戦・予告先発・今季対戦成績・試合開始）／順位（公式戦・交流戦・オープン戦、両リーグ）
///  これからの7日間（結果つき）／チーム状態（調子・体力・離脱者）／お知らせ
class HomeScreen extends StatefulWidget {
  final AppState appState;
  final void Function(int tab)? onNavigate; // 2=オーダー など
  const HomeScreen({Key? key, required this.appState, this.onNavigate}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _navy = Color(0xFF0B1626);
  static const _navy2 = Color(0xFF12233B);
  static const _lime = Color(0xFFC6F24E);
  static const _muted = Color(0xFF8EA3BF);

  StandingsKind? _kind; // null=日付から自動
  String? _league;
  String? _titleLeague; // タイトル争いのリーグ

  AppState get app => widget.appState;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        if (app.teams.isEmpty) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        final my = app.teams.firstWhere((t) => t.id == app.myTeamId, orElse: () => app.teams.first);
        final kind = _kind ?? _autoKind();
        return Scaffold(
          backgroundColor: const Color(0xFFEEF1F5),
          body: SafeArea(
            child: LayoutBuilder(builder: (context, c) {
              final wide = c.maxWidth >= 1000;
              final pad = c.maxWidth < 600 ? 8.0 : 24.0;
              // 上から：今日の試合 → 対応が必要 → 5つのタブ（お知らせ・順位・7日間・チーム・タイトル）
              final header = _header(my, kind);
              final hero = _todayCard(my);
              final action = _actionCard(my);
              final tabs = _tabsCard(my, kind);
              final post = _postseasonCard();
              if (wide) {
                return SingleChildScrollView(
                  padding: EdgeInsets.all(pad),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    header,
                    const SizedBox(height: 16),
                    if (app.fired) ...[FiredCard(app: app), const SizedBox(height: 16)],
                    if (app.ronin && !app.fired) ...[RoninCard(app: app), const SizedBox(height: 16)],
                    if (post != null) ...[post, const SizedBox(height: 16)],
                    if (action == null)
                      hero
                    else
                      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(flex: 3, child: hero),
                        const SizedBox(width: 16),
                        Expanded(flex: 2, child: action),
                      ]),
                    const SizedBox(height: 16),
                    tabs,
                  ]),
                );
              }
              return ListView(
                padding: EdgeInsets.all(pad),
                children: [
                  header,
                  const SizedBox(height: 8),
                  if (app.fired) ...[FiredCard(app: app), const SizedBox(height: 8)],
                  if (app.ronin && !app.fired) ...[RoninCard(app: app), const SizedBox(height: 8)],
                  if (post != null) ...[post, const SizedBox(height: 8)],
                  hero,
                  const SizedBox(height: 8),
                  if (action != null) ...[action, const SizedBox(height: 8)],
                  tabs,
                ],
              );
            }),
          ),
        );
      },
    );
  }

  /// 日付から順位表の区分を決める（公式戦が始まる前はオープン戦）
  StandingsKind _autoKind() {
    final league = app.matches.where((m) => m.matchType == 'LEAGUE' || m.matchType == 'INTERLEAGUE').toList();
    if (league.isEmpty) return StandingsKind.official;
    final first = league.map((m) => m.date).reduce((a, b) => a.isBefore(b) ? a : b);
    return app.currentDate.isBefore(first) ? StandingsKind.open : StandingsKind.official;
  }

  String _kindLabel(StandingsKind k) => const {StandingsKind.official: '公式戦', StandingsKind.interleague: '交流戦', StandingsKind.open: 'オープン戦'}[k]!;

  // ---------------- ヘッダー ----------------
  Widget _header(Team my, StandingsKind kind) {
    const dows = ['月', '火', '水', '木', '金', '土', '日'];
    final d = app.currentDate;
    final recs = computeStandings(app.teams, app.matches, standingsScope(my.league, kind), kind);
    final idx = recs.indexWhere((r) => r.team.id == my.id);
    final mine = idx >= 0 ? recs[idx] : null;
    final played = app.matches.where((m) => m.homeScore != null && (m.homeTeamId == my.id || m.awayTeamId == my.id) && (kind == StandingsKind.open ? m.matchType == 'OPEN' : m.matchType != 'OPEN')).length;
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('${d.year}年${d.month}月${d.day}日（${dows[d.weekday - 1]}）', style: TextStyle(fontSize: MediaQuery.of(context).size.width < 600 ? 19 : 24, fontWeight: FontWeight.w900)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(99), border: Border.all(color: const Color(0xFFDCE2EA))),
          child: Text('${_kindLabel(kind)} $played試合消化', style: const TextStyle(fontSize: 13, color: Color(0xFF475569))),
        ),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: teamColor(app.teams, my), borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 6),
          Text(my.name, style: const TextStyle(fontSize: 13, color: Color(0xFF64748B))),
        ]),
        // 設定・編集（リーグ編成・チームと選手の編集・ゲームの設定・バックアップ）
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SettingsMenuScreen(appState: app))),
          icon: const Icon(Icons.settings, size: 16),
          label: const Text('設定・編集'),
          style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 10)),
        ),
        if (app.myFin != null)
          Text('資金 ${oku(app.myFin!.funds)}　人気 ${app.myFin!.popularity}　オーナー満足度 ${app.myFin!.ownerSat}',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: app.myFin!.ownerSat < 35 ? const Color(0xFFB91C1C) : const Color(0xFF475569))),
        if (mine != null) ...[
          Text('${mine.w}-${mine.l}-${mine.d}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
          Text('${leagueLabel(standingsScope(my.league, kind))} ${idx + 1}位${idx > 0 ? ' ／ 首位と${gamesBehind(recs.first, mine)}差' : ''}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFFB45309))),
        ],
      ],
    );
  }

  // ---------------- 今日の試合 ----------------
  Match? _nextMatch(Team my) {
    final ms = app.matches.where((m) => m.homeScore == null && (m.homeTeamId == my.id || m.awayTeamId == my.id) && !m.date.isBefore(DateUtils.dateOnly(app.currentDate))).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    return ms.isEmpty ? null : ms.first;
  }

  Widget _todayCard(Team my) {
    final today = app.myMatchToday();
    final next = today ?? _nextMatch(my);
    final hasToday = today != null;
    Team? opp;
    Team? home, away;
    if (next != null) {
      home = app.teams.where((t) => t.id == next.homeTeamId).firstOrNull;
      away = app.teams.where((t) => t.id == next.awayTeamId).firstOrNull;
      opp = home?.id == my.id ? away : home;
    }
    String recOf(Team t) {
      final k = _kind ?? _autoKind();
      final scope = standingsScope(t.league, k);
      final recs = computeStandings(app.teams, app.matches, scope, k);
      final i = recs.indexWhere((r) => r.team.id == t.id);
      if (i < 0) return '${t.wins}-${t.losses}-${t.draws}';
      return '${leagueLabel(scope)} ${i + 1}位　${recs[i].w}-${recs[i].l}-${recs[i].d}';
    }

    // 今季の対戦成績
    String h2h = '';
    if (opp != null) {
      int w = 0, l = 0, dd = 0;
      for (final m in app.matches) {
        if (m.homeScore == null || m.matchType == 'OPEN') continue;
        final mine = m.homeTeamId == my.id ? m.homeScore! : (m.awayTeamId == my.id ? m.awayScore! : null);
        final theirs = m.homeTeamId == opp.id ? m.homeScore! : (m.awayTeamId == opp.id ? m.awayScore! : null);
        if (mine == null || theirs == null) continue;
        if (mine > theirs) { w++; } else if (mine < theirs) { l++; } else { dd++; }
      }
      h2h = '今季対戦 $w勝$l敗${dd > 0 ? '$dd分' : ''}';
    }
    Widget teamSide(Team? t, bool right, {bool compact = false}) {
      if (t == null) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: right ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(height: compact ? 4 : 6, width: compact ? 40 : 60, decoration: BoxDecoration(color: teamColor(app.teams, t), borderRadius: BorderRadius.circular(3))),
          SizedBox(height: compact ? 4 : 6),
          // スマホ幅は短い名前で1行に収める
          Text(compact ? teamShort(t) : t.name, maxLines: compact ? 1 : null, overflow: compact ? TextOverflow.ellipsis : null, textAlign: right ? TextAlign.right : TextAlign.left, style: TextStyle(fontSize: compact ? 18 : 22, fontWeight: FontWeight.w900, color: Colors.white)),
          Text(recOf(t), style: const TextStyle(fontSize: 12, color: _muted)),
        ],
      );
    }

    Widget starter(Team? t) {
      if (t == null) return const SizedBox.shrink();
      final id = t.todaysStarterId;
      final p = id == null ? null : t.players.where((x) => x.id == id).firstOrNull;
      final g = p == null ? '' : GradeUtils.getGrade(p.ovr);
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: _navy2, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Text('${teamShort(t)} 先発', style: const TextStyle(fontSize: 12, color: _muted)),
          const SizedBox(width: 10),
          if (p != null) ConditionFace(level: p.conditionAt(app.currentDate), size: 16),
          const SizedBox(width: 6),
          Expanded(child: Text(p == null ? '未定' : p.listName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis)),
          if (p != null) ...[
            Text(g, style: TextStyle(fontWeight: FontWeight.w900, color: AppTheme.getGradeColor(g))),
            Text(' ${p.ovr}', style: const TextStyle(color: Colors.white)),
            const SizedBox(width: 10),
            Text('${p.seasonStats.wins}勝${p.seasonStats.losses}敗 ${p.seasonStats.era.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12, color: _muted)),
          ],
        ]),
      );
    }

    final off = app.offseasonLabel();
    final dateLabel = next == null ? (off ?? '') : (hasToday ? '今日の試合' : '${off != null ? '$off　' : ''}次の試合 ${next.date.month}/${next.date.day}');
    final typeLabel = next == null ? '' : const {'OPEN': 'オープン戦', 'LEAGUE': '公式戦', 'INTERLEAGUE': '交流戦', 'CS': 'クライマックスシリーズ', 'JS': '日本シリーズ'}[next.matchType] ?? next.matchType;
    return Container(
      padding: EdgeInsets.all(MediaQuery.of(context).size.width < 600 ? 14 : 22),
      decoration: BoxDecoration(color: _navy, borderRadius: BorderRadius.circular(18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(alignment: WrapAlignment.spaceBetween, spacing: 12, runSpacing: 4, children: [
          Text('$dateLabel　$typeLabel', style: const TextStyle(fontSize: 13, letterSpacing: 1.5, color: _lime, fontWeight: FontWeight.w700)),
          Text(h2h, style: const TextStyle(fontSize: 12, color: _muted)),
        ]),
        const SizedBox(height: 14),
        if (next == null)
          Padding(padding: const EdgeInsets.symmetric(vertical: 20), child: Text(app.seasonFinished ? '今季の日程はすべて終了しました' : '今後の試合はありません', style: const TextStyle(color: Colors.white, fontSize: 18)))
        else
          LayoutBuilder(builder: (context, c) {
            final narrow = c.maxWidth < 480;
            final vs = Text('VS', style: TextStyle(fontSize: narrow ? 18 : 30, fontWeight: FontWeight.w900, color: const Color(0xFF3A5578)));
            if (narrow) {
              return Row(children: [Expanded(child: teamSide(away, false, compact: true)), Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: vs), Expanded(child: teamSide(home, true, compact: true))]);
            }
            return Row(children: [Expanded(child: teamSide(away, false)), Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: vs), Expanded(child: teamSide(home, true))]);
          }),
        const SizedBox(height: 6),
        if (MediaQuery.of(context).size.width >= 600) Text(next == null ? '' : 'ビジター（先攻）：${away?.name ?? '-'} ／ ホーム：${home?.name ?? '-'}', style: const TextStyle(fontSize: 11, color: _muted)),
        const SizedBox(height: 12),
        if (next != null && hasToday) ...[
          starter(away),
          const SizedBox(height: 8),
          starter(home),
          const SizedBox(height: 14),
        ],
        Wrap(spacing: 10, runSpacing: 10, children: [
          SizedBox(
            height: MediaQuery.of(context).size.width < 600 ? 44 : 52,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: _lime, foregroundColor: _navy, padding: const EdgeInsets.symmetric(horizontal: 28), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: app.draftPending
                  ? () => _openDraft(context)
                  : app.activeDraftPending
                  ? () => _openActiveDraft(context)
                  : (!hasToday && app.seasonOver && !app.seasonFinished) ? () => _finishSeason(context) : () => _playToday(context),
              icon: Icon(app.draftPending || app.activeDraftPending ? Icons.how_to_vote : (hasToday ? Icons.sports_baseball : ((app.seasonOver && !app.seasonFinished) ? Icons.emoji_events : Icons.fast_forward))),
              label: Text(app.draftPending ? 'ドラフト会議を始める' : app.activeDraftPending ? '現役ドラフトを行う' : (hasToday ? '今日の試合を開始する' : ((app.seasonOver && !app.seasonFinished) ? 'シーズンを終える（成績を確定）' : '${app.nextStopLabel()}まで進める')), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
            ),
          ),
          if (widget.onNavigate != null)
            SizedBox(
              height: MediaQuery.of(context).size.width < 600 ? 44 : 52,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Color(0xFF3A5578)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                onPressed: () => widget.onNavigate!(2),
                child: const Text('オーダー確認'),
              ),
            ),
        ]),
      ]),
    );
  }

  Future<void> _openDraft(BuildContext context) async {
    // 支配下の空きが少ないと本指名ができない（空き0人なら、開いた時点で他球団の本指名が最後まで進み、育成指名だけになる）
    final my = app.myTeam;
    final free = my == null ? 99 : RosterEngine.freeSlots(my);
    if (free < 5) {
      final go = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(free <= 0 ? '支配下に空きがありません' : '支配下の空きは $free人です'),
          content: Text(free <= 0
              ? '支配下が上限の${RosterEngine.maxShihaika}人なので、このまま始めると本指名（支配下）は1人もできず、育成指名だけになります。\n\n先に「フロント → 補強 → 戦力外通告・育成」で枠を空けてから、ドラフト会議を開いてください。'
              : 'このまま始めると、本指名（支配下）は $free人までです。\n\nもっと指名したいときは、先に「フロント → 補強 → 戦力外通告・育成」で枠を空けてください。'),
          actions: [
            FilledButton(onPressed: () => Navigator.pop(c, false), child: const Text('戻って枠を空ける')),
            TextButton(onPressed: () => Navigator.pop(c, true), child: Text(free <= 0 ? '育成指名だけ行う' : 'このまま始める')),
          ],
        ),
      );
      if (go != true || !context.mounted) return;
    }
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => DraftScreen(appState: app)));
  }

  Future<void> _openActiveDraft(BuildContext context) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ActiveDraftScreen(app: app)));
    if (mounted) setState(() {});
  }

  /// シーズンの終わり：記録を残し、成長・衰えを反映して、次の年の日程を作る
  Future<void> _finishSeason(BuildContext context) async {
    final r = await app.finishSeason();
    if (r == null || !context.mounted) return;
    await showSeasonReport(context, app, r);
  }

  /// 今日の試合を進める。自チームの試合があれば、スタメン確認画面でモード（自動/簡易采配/フル采配）を選ぶ
  Future<void> _playToday(BuildContext context) async {
    final my = app.myMatchToday();
    if (my == null) {
      app.playNextDay();
      return;
    }
    final home = app.teams.firstWhere((t) => t.id == my.homeTeamId);
    final away = app.teams.firstWhere((t) => t.id == my.awayTeamId);
    final mode = await Navigator.of(context).push<String>(MaterialPageRoute(
      builder: (_) => PreGameScreen(homeTeam: home, awayTeam: away, myTeamId: app.myTeamId, appState: app, match: my),
    ));
    if (mode == null) return;
    if (mode == 'auto') {
      app.playNextDay();
      return;
    }
    app.playOtherMatchesToday();
    app.prepareLiveGame(my);
    if (!context.mounted) return;
    final result = await Navigator.of(context).push<MatchResult>(MaterialPageRoute(
      builder: (_) => LiveGameScreen(match: my, homeTeam: home, awayTeam: away, myTeamId: app.myTeamId, manage: mode == 'manage' || mode == 'clutch', clutch: mode == 'clutch', appState: app),
    ));
    if (result != null) {
      app.completeMyMatch(my, result);
    } else {
      app.cancelLiveGame();
      app.updateAndSave();
    }
  }

  // ---------------- ポストシーズン・表彰 ----------------
  /// CS・日本シリーズの途中は対戦状況、オフシーズンは表彰への入口。どちらでもなければ null
  Widget? _postseasonCard() {
    if (app.postseason.isEmpty && !app.seasonFinished) {
      // シーズン後のオフ：前の年度の表彰への入口
      if (!app.offAfterSeason) return null;
      final y = app.startYear - 1;
      return _card(
        title: '${y}年シーズン',
        action: TextButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AwardsScreen(appState: app, year: y))), child: const Text('表彰を見る')),
        child: Text(app.myCareer.isNotEmpty && app.myCareer.last['year'] == y ? '${app.myCareer.last['teamName']}：${app.myCareer.last['w']}勝${app.myCareer.last['l']}敗${app.myCareer.last['d']}分　${app.myCareer.last['rank']}位${app.myCareer.last['champion'] == true ? '・日本一' : (app.myCareer.last['pennant'] == true ? '・リーグ優勝' : '')}' : '${y}年のシーズンは終了しました', style: const TextStyle(fontSize: 13)),
      );
    }
    final rows = <Widget>[];
    for (final s in app.postseason) {
      final hi = app.teamById(s.high), lo = s.low.isEmpty ? null : app.teamById(s.low);
      final (h, l, d, _) = s.tally(app.matches);
      final status = s.winner.isNotEmpty
          ? '${teamShort(app.teamById(s.winner)!)} 勝ち抜け'
          : (lo == null ? '相手を待っています' : '${h}勝${l}敗${d > 0 ? '${d}分' : ''}');
      rows.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          SizedBox(width: 196, child: Text(s.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w700))),
          Expanded(child: Text('${hi == null ? '-' : teamShort(hi)} 対 ${lo == null ? '？' : teamShort(lo)}', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700))),
          Text(status, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: s.winner.isNotEmpty ? const Color(0xFFB45309) : const Color(0xFF0F172A))),
        ]),
      ));
    }
    final year = app.startYear;
    return _card(
      title: app.champion != null ? '${year}年 日本一：${app.champion!.name}' : 'ポストシーズン',
      action: app.seasonFinished
          ? TextButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AwardsScreen(appState: app, year: year))), child: const Text('表彰を見る'))
          : null,
      child: rows.isEmpty ? const Text('ポストシーズンの記録はありません', style: TextStyle(color: Color(0xFF64748B))) : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows),
    );
  }

  // ---------------- 順位 ----------------
  Widget _card({required Widget child, String? title, Widget? action}) {
    final narrow = MediaQuery.of(context).size.width < 600;
    return Container(
      padding: EdgeInsets.all(narrow ? 12 : 18),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(narrow ? 12 : 18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15))), if (action != null) action]),
          ),
        child,
      ]),
    );
  }

  // ---------------- タイトル争い ----------------
  /// 各タイトルの上位3人（タップでリーグごとのすべての順位）。公式戦が始まるまでは出さない
  Widget? _titleCard(Team my) {
    final started = app.matches.any((m) => m.homeScore != null && (m.matchType == 'LEAGUE' || m.matchType == 'INTERLEAGUE'));
    if (!started) return null;
    final lg = _titleLeague ?? (my.league == 'PL' ? 'PL' : 'CL');
    final narrow = MediaQuery.of(context).size.width < 600;
    Widget cell(int i) {
      final d = titleDefs[i];
      final list = titleRanking(app.teams, app.matches, lg, d, open: Player.showOpen).take(3).toList();
      return InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TitleRankingScreen(app: app, initial: i, league: lg))),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFE2E8F0))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(d.title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Color(0xFFB45309))),
            if (list.isEmpty) const Text('該当者なし', style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
            for (var k = 0; k < list.length; k++)
              Row(children: [
                SizedBox(width: 14, child: Text('${k + 1}', style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)))),
                Expanded(
                  child: Text('${list[k].$1.listName}（${list[k].$2.initialName.isNotEmpty ? list[k].$2.initialName : teamShort(list[k].$2)}）',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, fontWeight: list[k].$2.id == my.id ? FontWeight.w800 : FontWeight.w500)),
                ),
                Text(d.fmt(list[k].$3), style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()])),
              ]),
          ]),
        ),
      );
    }

    final cols = narrow ? 2 : 4;
    return _card(
      title: 'タイトル争い',
      action: SegmentedButton<String>(
        segments: const [ButtonSegment(value: 'CL', label: Text('A')), ButtonSegment(value: 'PL', label: Text('B'))],
        selected: {lg},
        showSelectedIcon: false,
        style: const ButtonStyle(visualDensity: VisualDensity(horizontal: -4, vertical: -4)),
        onSelectionChanged: (v) => setState(() => _titleLeague = v.first),
      ),
      child: Column(children: [
        for (var r = 0; r < (titleDefs.length / cols).ceil(); r++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (var c = 0; c < cols; c++) ...[
                if (c > 0) const SizedBox(width: 6),
                Expanded(child: r * cols + c < titleDefs.length ? cell(r * cols + c) : const SizedBox.shrink()),
              ],
            ]),
          ),
        const Align(alignment: Alignment.centerRight, child: Text('タップで全順位', style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)))),
      ]),
    );
  }

  Widget _standingsCard(Team my, StandingsKind kind) {
    final leagues = app.teams.map((t) => t.league).where((l) => l == 'CL' || l == 'PL').toSet().toList()..sort();
    final lg = _league ?? my.league;
    final whole = kind != StandingsKind.official; // 交流戦・オープン戦は12球団まとめ
    final recs = computeStandings(app.teams, app.matches, whole ? allLeagues : lg, kind);
    return _card(
      title: '順位',
      action: TextButton(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => StandingsScreen(appState: app, initialKind: kind))),
        child: const Text('すべて見る'),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final k in StandingsKind.values)
            ChoiceChip(label: Text(_kindLabel(k)), selected: k == kind, onSelected: (_) => setState(() => _kind = k), visualDensity: VisualDensity.compact),
        ]),
        const SizedBox(height: 8),
        if (!whole)
          SegmentedButton<String>(
            segments: [for (final l in leagues) ButtonSegment(value: l, label: Text(leagueLabel(l)))],
            selected: {leagues.contains(lg) ? lg : (leagues.isNotEmpty ? leagues.first : lg)},
            showSelectedIcon: false,
            onSelectionChanged: (v) => setState(() => _league = v.first),
          )
        else
          Text('12球団（${_kindLabel(kind)}）', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF64748B))),
        const SizedBox(height: 8),
        Row(children: const [
          SizedBox(width: 26),
          SizedBox(width: 12),
          Expanded(child: Text('球団', style: TextStyle(fontSize: 11, color: Color(0xFF64748B)))),
          SizedBox(width: 26, child: Text('勝', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, color: Color(0xFF64748B)))),
          SizedBox(width: 26, child: Text('敗', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, color: Color(0xFF64748B)))),
          SizedBox(width: 26, child: Text('分', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, color: Color(0xFF64748B)))),
          SizedBox(width: 44, child: Text('勝率', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, color: Color(0xFF64748B)))),
          SizedBox(width: 36, child: Text('差', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, color: Color(0xFF64748B)))),
        ]),
        for (int i = 0; i < recs.length; i++)
          Container(
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            decoration: BoxDecoration(color: recs[i].team.id == my.id ? const Color(0xFFFEF3C7) : null, borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              SizedBox(width: 20, child: Text('${i + 1}', style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w700))),
              Container(width: 4, height: 18, margin: const EdgeInsets.symmetric(horizontal: 6), decoration: BoxDecoration(color: teamColor(app.teams, recs[i].team), borderRadius: BorderRadius.circular(2))),
              Expanded(child: Text(recs[i].team.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis)),
              SizedBox(width: 26, child: Text('${recs[i].w}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 13))),
              SizedBox(width: 26, child: Text('${recs[i].l}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 13))),
              SizedBox(width: 26, child: Text('${recs[i].d}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 13))),
              SizedBox(width: 44, child: Text(recs[i].pctText, textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
              SizedBox(width: 36, child: Text(gamesBehind(recs.first, recs[i]), textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)))),
            ]),
          ),
      ]),
    );
  }

  // ---------------- 7日間 ----------------
  Widget _weekCard(Team my) {
    const dows = ['月', '火', '水', '木', '金', '土', '日'];
    Widget day(int i) {
      final date = app.currentDate.add(Duration(days: i));
      final ms = app.matches.where((m) => DateUtils.isSameDay(m.date, date) && (m.homeTeamId == my.id || m.awayTeamId == my.id)).toList();
      final isToday = i == 0;
      String opp = '移動日';
      String? score;
      bool? won;
      if (ms.isNotEmpty) {
        final m = ms.first;
        final isHome = m.homeTeamId == my.id;
        final o = app.teams.where((t) => t.id == (isHome ? m.awayTeamId : m.homeTeamId)).firstOrNull;
        opp = '${isHome ? 'vs' : '@'} ${o != null ? teamInitial(o) : '?'}';
        if (m.homeScore != null) {
          final a = isHome ? m.homeScore! : m.awayScore!, b = isHome ? m.awayScore! : m.homeScore!;
          score = '$a-$b';
          won = a > b ? true : (a < b ? false : null);
        }
      }
      final dow = dows[date.weekday - 1];
      return Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isToday ? _navy : (ms.isEmpty ? const Color(0xFFF1F5F9) : const Color(0xFFF8FAFC)),
            borderRadius: BorderRadius.circular(10),
            border: ms.isEmpty || isToday ? null : Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(children: [
            Text(dow, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: isToday ? _lime : (dow == '日' ? Colors.red : (dow == '土' ? Colors.blue : const Color(0xFF64748B))))),
            Text('${date.month}/${date.day}', style: TextStyle(fontSize: 10, color: isToday ? _muted : const Color(0xFF94A3B8))),
            const SizedBox(height: 4),
            Text(opp, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: isToday ? Colors.white : (ms.isEmpty ? const Color(0xFF94A3B8) : const Color(0xFF0F172A)))),
            if (score != null) Text(score, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: won == true ? const Color(0xFF2563EB) : (won == false ? const Color(0xFFDC2626) : Colors.grey))),
          ]),
        ),
      );
    }

    return _card(title: 'これからの7日間', child: Row(children: [for (int i = 0; i < 7; i++) day(i)]));
  }

  // ---------------- チーム状態 ----------------
  Widget _conditionCard(Team my) {
    final pmap = {for (final p in my.players) p.id: p};
    final first = my.roster1G.map((id) => pmap[id]).whereType<Player>().toList();
    final counts = <int, int>{};
    for (final p in first) {
      final c = p.conditionAt(app.currentDate);
      counts[c] = (counts[c] ?? 0) + 1;
    }
    double avg(Iterable<Player> ps) => ps.isEmpty ? 0 : ps.map((p) => p.energyRatio).reduce((a, b) => a + b) / ps.length;
    final starters = my.activeRotation.where((e) => e.isNotEmpty).map((id) => pmap[id]).whereType<Player>();
    final relievers = first.where((p) => p.isPitcher && !my.activeRotation.contains(p.id));
    final regulars = my.lineup.map((l) => pmap[l.playerId]).whereType<Player>();
    final injured = my.players.where((p) => p.injuryDays > 0).toList()..sort((a, b) => b.injuryDays.compareTo(a.injuryDays));
    Widget energyRow(String k, double v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            SizedBox(width: 110, child: Text(k, style: const TextStyle(fontSize: 13))),
            Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(3), child: LinearProgressIndicator(value: v, minHeight: 6, backgroundColor: const Color(0xFFE2E8F0), color: v < 0.3 ? Colors.redAccent : (v < 0.5 ? Colors.orange : Colors.green)))),
            SizedBox(width: 44, child: Text('${(v * 100).round()}%', textAlign: TextAlign.right, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: v < 0.5 ? const Color(0xFFB45309) : null))),
          ]),
        );
    return _card(
      title: 'チーム状態（1軍）',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 12, runSpacing: 6, children: [
          for (final c in [2, 1, 0, -1, -2])
            Row(mainAxisSize: MainAxisSize.min, children: [ConditionFace(level: c, size: 16), const SizedBox(width: 4), Text('${ConditionFace.labels[c]} ${counts[c] ?? 0}', style: const TextStyle(fontSize: 12.5))]),
        ]),
        const SizedBox(height: 10),
        energyRow('先発の体力', avg(starters)),
        energyRow('中継ぎの体力', avg(relievers)),
        energyRow('スタメンの体力', avg(regulars)),
        const SizedBox(height: 8),
        Text(injured.isEmpty ? '離脱・故障者なし' : '故障者 ${injured.length}人', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: injured.isEmpty ? const Color(0xFF16A34A) : const Color(0xFFDC2626))),
        for (final p in injured.take(4))
          Text('・${p.listName}　${p.injuryName} 残り${p.injuryDays}日${p.injurySeverity == 1 ? '（強行出場可）' : ''}', style: const TextStyle(fontSize: 12.5, color: Color(0xFF475569))),
      ]),
    );
  }

  // ---------------- お知らせ ----------------

  // ---------------- 対応が必要（案E）----------------
  /// やるべきこと：キャンプの改造の提案・オーダー/ローテの離脱者や空き・企画できるコラボグッズ。無ければ null
  Widget? _actionCard(Team my) {
    final items = <(Color, Color, IconData, String, String, String, VoidCallback)>[];
    if (app.campProposals.isNotEmpty) {
      final coaches = {for (final c in app.campProposals) '${c['coach']}'.split(' ').first}.join('・');
      items.add((const Color(0xFF7C3AED), const Color(0xFFEDE9FE), Icons.lightbulb_outline, '改造の提案が${app.campProposals.length}件', '$coachesから（キャンプ）', '見る', () => _push('キャンプ・練習', CampTab(app: app, team: my, onChanged: () {}))));
    }
    final pm = {for (final p in my.players) p.id: p};
    final hurtLineup = [for (final l in my.lineup) if (pm[l.playerId]?.isInjuredOut ?? false) pm[l.playerId]!];
    final emptyRot = my.rotation.take(my.rotationCount).where((id) => id.isEmpty || (pm[id]?.isInjuredOut ?? true)).length;
    if (hurtLineup.isNotEmpty || emptyRot > 0) {
      final sub = [
        if (hurtLineup.isNotEmpty) 'スタメンに離脱者：${hurtLineup.map((p) => p.registeredName).join('・')}',
        if (emptyRot > 0) '先発ローテに空きが$emptyRot枠',
      ].join('／');
      items.add((const Color(0xFFDC2626), const Color(0xFFFEE2E2), Icons.personal_injury_outlined, 'オーダーを見直してください', sub, 'オーダー', () => widget.onNavigate?.call(2)));
    }
    if (app.makerCollabs.isNotEmpty) {
      final c = app.makerCollabs.first;
      items.add((const Color(0xFF15803D), const Color(0xFFDCFCE7), Icons.storefront_outlined, 'コラボグッズを企画できます', '${c['maker']} × ${c['player']}（${c['title']}）${app.makerCollabs.length > 1 ? ' ほか${app.makerCollabs.length - 1}件' : ''}', '企画', () => _push('メーカー', MakerTab(app: app, team: my))));
    }
    if (items.isEmpty) return null;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFF59E0B), width: 2)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Text('対応が必要', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
          const SizedBox(width: 6),
          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1), decoration: BoxDecoration(color: const Color(0xFFF59E0B), borderRadius: BorderRadius.circular(99)), child: Text('${items.length}件', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white))),
        ]),
        const SizedBox(height: 6),
        for (final (c, bg, icon, title, sub, act, onTap) in items)
          Container(
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              Container(width: 34, height: 34, decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)), child: Icon(icon, size: 19, color: c)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B))),
                ]),
              ),
              const SizedBox(width: 6),
              FilledButton(onPressed: onTap, style: FilledButton.styleFrom(backgroundColor: c, minimumSize: const Size(0, 38), padding: const EdgeInsets.symmetric(horizontal: 12)), child: Text(act, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700))),
            ]),
          ),
      ]),
    );
  }

  void _push(String title, Widget body) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => Scaffold(appBar: AppBar(title: Text(title)), body: body)));

  // ---------------- 下半分の5つのタブ（案F）----------------
  static int _tab = 0; // 開いたタブを覚えておく（次に開いたときも同じタブ）
  static const _tabNames = ['順位', 'タイトル', 'ニュース', 'お知らせ'];

  Widget _tabsCard(Team my, StandingsKind kind) {
    final today = '${app.currentDate.month}/${app.currentDate.day}';
    final todayItems = app.news.where((n) => n.startsWith('$today ')).toList();
    final todayNews = todayItems.where((n) => _isArticle(NewsKind.split(n).$2)).length;
    final todayOther = todayItems.length - todayNews;
    final badges = [0, 0, todayNews, todayOther];
    Widget body;
    switch (_tab) {
      case 1:
        body = _titleCard(my) ?? _card(title: 'タイトル争い', child: const Text('公式戦が始まると、打率・本塁打・防御率などの上位が出ます', style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8))));
      case 2:
        body = _newsArticles();
      case 3:
        // お知らせ（ニュース以外）と、チームの調子・故障
        body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [_newsList(), _conditionCard(my)]);
      default:
        // 順位と、この7日間
        body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [_standingsCard(my, kind), _weekCard(my)]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(14))),
        child: Row(children: [
          for (var i = 0; i < _tabNames.length; i++)
            Expanded(
              child: InkWell(
                onTap: () => setState(() => _tab = i),
                child: Container(
                  height: 46,
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: i == _tab ? const Color(0xFF0B1626) : const Color(0xFFE2E8F0), width: i == _tab ? 3 : 1))),
                  alignment: Alignment.center,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Flexible(child: Text(_tabNames[i], maxLines: 1, overflow: TextOverflow.visible, softWrap: false, style: TextStyle(fontSize: 13, fontWeight: i == _tab ? FontWeight.w900 : FontWeight.w500, color: i == _tab ? const Color(0xFF0F172A) : const Color(0xFF64748B)))),
                    if (badges[i] > 0)
                      Container(
                        margin: const EdgeInsets.only(left: 3),
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        decoration: BoxDecoration(color: const Color(0xFF2563EB), borderRadius: BorderRadius.circular(99)),
                        child: Text('${badges[i]}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
                      ),
                  ]),
                ),
              ),
            ),
        ]),
      ),
      ClipRRect(borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)), child: body),
    ]);
  }

  /// 記事にするお知らせ：移籍・故障・記録で、選手の名前が出てくるもの（まとめのお知らせはお知らせのまま）
  bool _isArticle(String text) {
    if (ItemNews.topicOf(text) == null) return false;
    return playerInText(text, _newsPeople) != null;
  }

  /// 記事の選手を探す範囲：全球団の選手と自由契約の選手
  List<Player> get _newsPeople => [for (final t in app.teams) ...t.players, ...app.freeAgents.map((f) => f.player)];

  /// ニュース：移籍・故障・記録のお知らせを、ネットニュース風の記事にして並べる（押すと記事とコメント）
  Widget _newsArticles() {
    final everyone = _newsPeople;
    Team? teamOf(Player p) {
      for (final t in app.teams) {
        if (t.players.contains(p)) return t;
      }
      return null;
    }

    final today = app.currentDate;
    DateTime dayOf(String md) {
      final p = md.split('/');
      if (p.length != 2) return today;
      final mo = int.tryParse(p[0]) ?? today.month, da = int.tryParse(p[1]) ?? today.day;
      return DateTime(mo > today.month ? today.year - 1 : today.year, mo, da);
    }

    // 大リーグの一流選手（新外国人の記事のコメントで比べる）
    final stars = <MlbStar>[];
    final ow = app.otherWorld;
    if (ow != null) {
      final mlb = [
        for (final t in ow.teamsOf('MLB'))
          for (final p in t.players) (p, t.short.isNotEmpty ? t.short : t.name),
      ]..sort((x, y) => y.$1.ovr.compareTo(x.$1.ovr));
      for (final (p, t) in mlb.take(40)) {
        final note = ow.fromNpb[p.id];
        final m = note == null ? null : RegExp(r'（元(.+?)）').firstMatch(note);
        stars.add((p, t, m?.group(1)));
      }
    }

    final dated = <(DateTime, ItemNews)>[];
    // お知らせから（移籍・故障・記録で選手の名前が出てくるもの）
    for (final n in app.news) {
      final (date, text) = NewsKind.split(n);
      final topic = ItemNews.topicOf(text);
      if (topic == null) continue;
      final p = playerInText(text, everyone);
      if (p == null) continue;
      // トレードは、名前の出てくる全員（今の球団つき）
      final involved = <(Player, Team?)>[];
      if (text.contains('トレード成立')) {
        final seen = <String>{};
        for (final x in everyone) {
          if (x.registeredName.length >= 2 && text.contains(x.registeredName) && seen.add(x.registeredName)) involved.add((x, teamOf(x)));
        }
      }
      dated.add((dayOf(date), ItemNews.of(date, text, topic, player: p, team: teamOf(p), myTeamId: app.myTeamId, stars: stars, involved: involved)));
      if (dated.length >= 40) break;
    }
    // 新外国人の入団（入団の記録から）
    final txRe = RegExp(r'^(\d+)/(\d+)/(\d+) (\S+) (.+?)（外国人(・育成)?・(.+?)）と契約');
    for (final tx in app.transactions.take(300)) {
      final m = txRe.firstMatch(tx);
      if (m == null) continue;
      final d = DateTime(int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!));
      final name = m.group(5)!;
      final p = everyone.where((x) => x.registeredName == name).firstOrNull;
      if (p == null) continue;
      final ik = m.group(6) != null;
      final t = teamOf(p);
      final text = '${m.group(4)}が${ik ? '育成選手として' : ''}新外国人の$name（${p.origin.isEmpty ? '' : '${p.origin}出身・'}${m.group(7)}）と契約した';
      dated.add((d, ItemNews.of('${d.month}/${d.day}', text, NewsTopic.transfer, player: p, team: t, myTeamId: app.myTeamId, stars: stars)));
      if (dated.length >= 60) break;
    }
    // トレード予想（毎週月曜）
    for (final r in TradeRumor.recent(app.teams, today, myTeamId: app.myTeamId, count: 4)) {
      dated.add((dayOf(r.date), r));
    }
    // オフシーズンの去就予想（FA・自由契約・新外国人）
    Player? byId(String id) => everyone.where((p) => p.id == id).firstOrNull;
    dated.addAll(OffseasonNews.predictions(teams: app.teams, faCases: app.faCases, freeAgents: app.freeAgents, foreignPool: app.foreignPool, today: today, playerById: byId, myTeamId: app.myTeamId));
    dated.sort((x, y) => y.$1.compareTo(x.$1));
    final items = [for (final x in dated.take(45)) x.$2];
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (items.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('移籍・故障・記録のニュースはまだありません', style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8)))),
        for (final it in items) ItemNewsCard(news: it, teams: app.teams, myTeamId: app.myTeamId, date: app.currentDate),
      ]),
    );
  }

  /// お知らせ（案1）：「今日／昨日／日付」の見出しで区切り、種類の色アイコンつき。今日の分は太字
  Widget _newsList() {
    final d0 = app.currentDate;
    final today = '${d0.month}/${d0.day}';
    final y = d0.subtract(const Duration(days: 1));
    final yesterday = '${y.month}/${y.day}';
    String head(String d) {
      if (d == today) return '今日　${d.replaceFirst('/', '月')}日';
      if (d == yesterday) return '昨日　${d.replaceFirst('/', '月')}日';
      return d.isEmpty ? 'そのほか' : '${d.replaceFirst('/', '月')}日';
    }

    final rows = <Widget>[];
    var last = '\u0000';
    final everyone = [for (final t in app.teams) ...t.players];
    for (final n in app.news.where((n) => !_isArticle(NewsKind.split(n).$2)).take(30)) {
      final (date, text) = NewsKind.split(n);
      if (date != last) {
        rows.add(Container(
          padding: const EdgeInsets.fromLTRB(0, 10, 0, 4),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0)))),
          child: Text(head(date), style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF64748B))),
        ));
        last = date;
      }
      final k = NewsKind.of(text);
      final fresh = date == today;
      rows.add(Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9)))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // 選手の名前が出てくるお知らせは顔アイコン（種類は右下の小さな印）、ほかは種類のアイコン
          Builder(builder: (_) {
            final who = playerInText(text, everyone);
            if (who == null) return k.tile();
            return SizedBox(
              width: 34,
              height: 34,
              child: Stack(clipBehavior: Clip.none, children: [
                PlayerAvatar(who, size: 32),
                Positioned(right: -3, bottom: -3, child: Container(padding: const EdgeInsets.all(1), decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle), child: Icon(k.icon, size: 12, color: k.color))),
              ]),
            );
          }),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(k.name, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: k.color)),
              Builder(builder: (_) {
                final st = TextStyle(fontSize: 13, height: 1.45, fontWeight: fresh ? FontWeight.w700 : FontWeight.w400, color: fresh ? const Color(0xFF0F172A) : const Color(0xFF334155));
                // 「見出し：A・B・C…」の形は、名前などを小さな札にして並べる
                final i = text.indexOf('：');
                final rest = i > 0 ? text.substring(i + 1) : '';
                final parts = rest.split('、').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(); // 名前の中の「・」では切らない
                if (parts.length < 3 || parts.any((e) => e.length > 24)) return Text(text, style: st);
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(text.substring(0, i), style: st),
                  const SizedBox(height: 3),
                  Wrap(spacing: 4, runSpacing: 3, children: [
                    for (final e in parts)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(4)),
                        child: Text(e, style: const TextStyle(fontSize: 11.5, color: Color(0xFF334155))),
                      ),
                  ]),
                ]);
              }),
            ]),
          ),
        ]),
      ));
    }
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NewsArchiveScreen(app: app))), child: const Text('過去3年分（種類別にも見られます）')),
        ),
        if (app.news.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('新しいお知らせはありません', style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8)))),
        ...rows,
      ]),
    );
  }


}
