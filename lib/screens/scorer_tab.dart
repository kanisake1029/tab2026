import '../widgets/chip_grid.dart';
import 'package:flutter/material.dart';
import '../engine/matchup_book.dart';
import '../models/player.dart';
import '../models/team.dart';
import '../providers/app_state.dart';
import '../utils/standings.dart';
import '../widgets/player_detail_dialog.dart';
import 'team_stats_view.dart';

const _ink = Color(0xFF1C1917);
const _sub = Color(0xFF78716C);
const _line = Color(0xFFE7E5E4);

/// 監督室の「スコアラー」：自球団の選手ごとに、今季の公式戦で相手選手と対戦した結果（実際の記録だけ）
class ScorerTab extends StatefulWidget {
  final AppState app;
  final Team team;
  const ScorerTab({super.key, required this.app, required this.team});

  @override
  State<ScorerTab> createState() => _ScorerTabState();
}

class _ScorerTabState extends State<ScorerTab> {
  bool _pitchers = false;
  bool _stats = true; // 選手成績（各球団の今季成績の表）／対戦成績

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
        child: SegmentedButton<bool>(
          segments: const [ButtonSegment(value: true, label: Text('選手成績（各球団）')), ButtonSegment(value: false, label: Text('対戦成績（自球団）'))],
          selected: {_stats},
          showSelectedIcon: false,
          onSelectionChanged: (v) => setState(() => _stats = v.first),
        ),
      ),
      Expanded(child: _stats ? TeamStatsView(app: widget.app, initial: widget.team) : _matchups(context)),
    ]);
  }

  Widget _matchups(BuildContext context) {
    final app = widget.app;
    final book = app.matchups;
    final rows = <(Player, VsLine)>[];
    for (final p in widget.team.players) {
      if (_pitchers ? !p.canPitch : !p.canBat) continue;
      final m = _pitchers ? book.vsBatters(p.id) : book.vsPitchers(p.id);
      final total = VsLine();
      for (final v in m.values) {
        total.add(v);
      }
      rows.add((p, total));
    }
    rows.sort((a, b) => b.$2.pa.compareTo(a.$2.pa));
    return ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 24), children: [
      Row(children: [
        Expanded(
          child: SegmentedButton<bool>(
            segments: const [ButtonSegment(value: false, label: Text('野手（対投手）')), ButtonSegment(value: true, label: Text('投手（対打者）'))],
            selected: {_pitchers},
            showSelectedIcon: false,
            onSelectionChanged: (v) => setState(() => _pitchers = v.first),
          ),
        ),
      ]),
      const SizedBox(height: 8),
      Text(
        app.matchupsReady ? '今季の公式戦で、自球団の試合の記録から集計しています。選手をタップすると、相手選手ごとの対戦成績を見られます。' : '記録を読み込み中…',
        style: const TextStyle(fontSize: 11.5, color: _sub),
      ),
      const SizedBox(height: 8),
      ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Material(
          color: Colors.white,
          child: Column(children: [
            for (final (p, t) in rows)
              InkWell(
                onTap: t.pa == 0 ? null : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ScorerDetailScreen(app: app, player: p, asPitcher: _pitchers))),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _line))),
                  child: Row(children: [
                    SizedBox(width: 34, child: Text(p.mainPosition, style: const TextStyle(fontSize: 12, color: _sub))),
                    Expanded(child: Text(p.listName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800))),
                    Text(t.pa == 0 ? '対戦なし' : '${t.pa}打席　${_pitchers ? '被打率' : '打率'} ${t.avgText}', style: TextStyle(fontSize: 12.5, color: t.pa == 0 ? _sub : _ink)),
                    Icon(Icons.chevron_right, size: 18, color: t.pa == 0 ? Colors.transparent : _sub),
                  ]),
                ),
              ),
          ]),
        ),
      ),
    ]);
  }
}

/// 1人の選手の、相手選手ごとの対戦成績
class ScorerDetailScreen extends StatefulWidget {
  final AppState app;
  final Player player;
  final bool asPitcher;
  const ScorerDetailScreen({super.key, required this.app, required this.player, required this.asPitcher});

  @override
  State<ScorerDetailScreen> createState() => _ScorerDetailScreenState();
}

class _ScorerDetailScreenState extends State<ScorerDetailScreen> {
  String _teamFilter = ''; // '' = 全球団
  String _sort = 'pa';

  @override
  Widget build(BuildContext context) {
    final app = widget.app, p = widget.player;
    final m = widget.asPitcher ? app.matchups.vsBatters(p.id) : app.matchups.vsPitchers(p.id);
    // 相手選手（いまの所属）を引く
    final who = <String, (Player, Team)>{};
    for (final t in app.teams) {
      for (final x in t.players) {
        if (m.containsKey(x.id)) who[x.id] = (x, t);
      }
    }
    var ids = m.keys.where((id) => _teamFilter.isEmpty || who[id]?.$2.id == _teamFilter).toList();
    int cmp(String a, String b) {
      final x = m[a]!, y = m[b]!;
      switch (_sort) {
        case 'avg':
          final c = (widget.asPitcher ? x.avg.compareTo(y.avg) : y.avg.compareTo(x.avg));
          return c != 0 ? c : y.pa.compareTo(x.pa);
        case 'hr':
          return y.hr != x.hr ? y.hr.compareTo(x.hr) : y.pa.compareTo(x.pa);
        case 'so':
          return y.so != x.so ? y.so.compareTo(x.so) : y.pa.compareTo(x.pa);
        default:
          return y.pa.compareTo(x.pa);
      }
    }

    ids.sort(cmp);
    final total = VsLine();
    for (final id in ids) {
      total.add(m[id]!);
    }
    final teams = {for (final id in m.keys) if (who[id] != null) who[id]!.$2};
    const h = TextStyle(fontSize: 11, color: _sub, fontWeight: FontWeight.w700);
    const c = TextStyle(fontSize: 12.5);
    Widget cell(String s, double w, {TextStyle st = c, TextAlign a = TextAlign.right}) => SizedBox(width: w, child: Text(s, textAlign: a, style: st));
    Widget row(String name, String team, VsLine v, {bool bold = false, VoidCallback? onTap}) {
      final st = bold ? c.copyWith(fontWeight: FontWeight.w900) : c;
      return InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(color: bold ? const Color(0xFFFEF3C7) : null, border: const Border(bottom: BorderSide(color: _line))),
          child: Row(children: [
            Expanded(
              child: Text.rich(TextSpan(children: [
                TextSpan(text: name, style: st.copyWith(fontWeight: FontWeight.w800)),
                if (team.isNotEmpty) TextSpan(text: '  $team', style: const TextStyle(fontSize: 11, color: _sub)),
              ]), overflow: TextOverflow.ellipsis),
            ),
            cell('${v.pa}', 30, st: st),
            cell('${v.ab}', 30, st: st),
            cell('${v.h}', 30, st: st),
            cell('${v.hr}', 26, st: st),
            cell('${v.so}', 30, st: st),
            cell('${v.bb + v.hbp}', 30, st: st),
            cell(v.avgText, 44, st: st.copyWith(fontWeight: FontWeight.w800)),
          ]),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text('スコアラー：${p.listName}（${widget.asPitcher ? '対打者' : '対投手'}）', style: const TextStyle(fontSize: 16))),
      body: ListView(padding: const EdgeInsets.fromLTRB(10, 10, 10, 24), children: [
        ChipGrid<String>(items: [('', '全球団'), for (final t in teams) (t.id, teamShort(t))], selected: _teamFilter, minWidth: 56, padding: EdgeInsets.zero, onSelect: (id) => setState(() => _teamFilter = id)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, children: [
          for (final (k, l) in [('pa', '打席順'), ('avg', widget.asPitcher ? '被打率の低い順' : '打率順'), ('hr', '本塁打順'), ('so', '三振順')])
            ChoiceChip(label: Text(l, style: const TextStyle(fontSize: 12)), visualDensity: VisualDensity.compact, selected: _sort == k, onSelected: (_) => setState(() => _sort = k)),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Material(
            color: Colors.white,
            child: Column(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                color: const Color(0xFFF5F5F4),
                child: Row(children: [
                  Expanded(child: Text(widget.asPitcher ? '打者' : '投手', style: h)),
                  cell('打席', 30, st: h),
                  cell('打数', 30, st: h),
                  cell('安打', 30, st: h),
                  cell('本', 26, st: h),
                  cell('三振', 30, st: h),
                  cell('四死', 30, st: h),
                  cell(widget.asPitcher ? '被打率' : '打率', 44, st: h),
                ]),
              ),
              row('合計', '', total, bold: true),
              for (final id in ids)
                row(
                  who[id]?.$1.listName ?? '（退団した選手）',
                  who[id] == null ? '' : teamShort(who[id]!.$2),
                  m[id]!,
                  onTap: who[id] == null ? null : () => showPlayerDetail(context, app, who[id]!.$1, allowActions: who[id]!.$2.id == app.myTeamId),
                ),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        const Text('今季の公式戦（自球団の試合）の実際の対戦結果です。四死＝四球＋死球。送りバントは打数に数えません。', style: TextStyle(fontSize: 11, color: _sub)),
      ]),
    );
  }
}
