import 'package:flutter/material.dart';
import '../models/player.dart';
import '../models/team.dart';
import '../providers/app_state.dart';
import '../utils/standings.dart';
import '../widgets/frozen_table.dart';
import '../widgets/player_detail_dialog.dart';

/// スコアラー「選手成績」：球団ごとの選手の今季成績（1軍・公式戦）。選手詳細の成績表と同じ項目。
///  見出しを押すとその項目で並べ替え。率の項目（打率・防御率など）は規定に届いた選手を先に、届かない選手をその後に並べる
class TeamStatsView extends StatefulWidget {
  final AppState app;
  final Team initial;
  const TeamStatsView({super.key, required this.app, required this.initial});

  @override
  State<TeamStatsView> createState() => _TeamStatsViewState();
}

class _TeamStatsViewState extends State<TeamStatsView> {
  late Team _team = widget.initial;
  bool _pitch = false;
  int _level = 0; // 0=1軍 1=2軍 2=3軍
  int _sortBat = 16; // 打率
  int _sortPit = 15; // 防御率

  static String _rate(double v) => v.toStringAsFixed(3).replaceFirst(RegExp(r'^0'), '');
  static String _ip(int outs) => '${outs ~/ 3}${outs % 3 == 0 ? '' : '.${outs % 3}'}';

  static const _batCols = ['試合', '打席', '打数', '得点', '安打', '二塁打', '三塁打', '本塁打', '塁打', '打点', '盗塁', '盗塁死', '四球', '死球', '三振', '猛打賞', '打率', '出塁率', '長打率', 'OPS', '得点圏'];
  static const _pitCols = ['登板', '先発', '勝', '敗', 'H', 'S', '完投', '完封', '投球回', '被安打', '被本', '奪三振', '与四球', '与死球', '自責点', '防御率', 'WHIP'];
  // 率の項目（規定で分ける）と、小さいほど良い項目
  static const _batRates = {16, 17, 18, 19, 20};
  static const _pitRates = {15, 16};
  static const _pitLowGood = {15, 16}; // 防御率・WHIP は小さい順

  int _pa(PlayerStats s) => s.atBats + s.walks + s.sacFlies + s.hbp;

  List<num> _batVals(PlayerStats s) {
    final pa = _pa(s);
    final tb = s.hits + s.doubles + s.triples * 2 + s.homeRuns * 3;
    final obp = pa == 0 ? 0.0 : (s.hits + s.walks + s.hbp) / pa;
    final slg = s.atBats == 0 ? 0.0 : tb / s.atBats;
    return [s.games, pa, s.atBats, s.runs, s.hits, s.doubles, s.triples, s.homeRuns, tb, s.rbi, s.stolenBases, s.caughtStealing, s.walks, s.hbp, s.strikeouts, s.mouda, s.battingAverage, obp, slg, obp + slg, s.rispAvg];
  }

  List<String> _batCells(PlayerStats s) {
    final v = _batVals(s);
    return [for (var i = 0; i < 16; i++) '${v[i]}', for (var i = 16; i < 20; i++) s.atBats == 0 ? '-' : _rate(v[i].toDouble()), s.rispAB == 0 ? '-' : _rate(s.rispAvg)];
  }

  List<num> _pitVals(PlayerStats s) {
    final ip = s.inningsPitched / 3.0;
    return [s.apps, s.starts, s.wins, s.losses, s.holds, s.saves, s.completeGames, s.shutouts, s.inningsPitched, s.hitsAllowed, s.hrAllowed, s.pitcherStrikeouts, s.pitcherWalks, s.hbpAllowed, s.earnedRuns,
      s.inningsPitched == 0 ? 99.0 : s.era, ip == 0 ? 99.0 : (s.hitsAllowed + s.pitcherWalks) / ip];
  }

  List<String> _pitCells(PlayerStats s) {
    final v = _pitVals(s);
    return [for (var i = 0; i < 8; i++) '${v[i]}', _ip(s.inningsPitched), for (var i = 9; i < 15; i++) '${v[i]}',
      s.inningsPitched == 0 ? '-' : s.era.toStringAsFixed(2), s.inningsPitched == 0 ? '-' : (v[16] as double).toStringAsFixed(2)];
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    // 規定：試合数 × 3.1 打席、試合数 × 1.0 投球回（公式戦の消化試合数で）
    final rec = computeStandings(app.teams, _level == 0 ? app.matches : (_level == 1 ? app.farmMatches : app.thirdMatches), _level == 2 ? allLeagues : _team.league, StandingsKind.official).where((r) => r.team.id == _team.id).firstOrNull;
    final g = rec?.games ?? 0;
    final qPa = (g * 3.1).floor(), qOuts = g * 3;
    // その球団でプレーした分（今いる選手は今の球団での分、移った選手はこの球団にいた間の分）
    final ps = app.teamSeasonEntries(_team, _level).where((e) => _pitch ? (e.$1.canPitch && e.$2.apps > 0) : (e.$1.canBat && _pa(e.$2) > 0)).toList();
    final col = _pitch ? _sortPit : _sortBat;
    final isRate = (_pitch ? _pitRates : _batRates).contains(col);
    final low = _pitch && _pitLowGood.contains(col);
    bool qual((Player, PlayerStats, bool) e) => _pitch ? e.$2.inningsPitched >= qOuts : _pa(e.$2) >= qPa;
    num val((Player, PlayerStats, bool) e) => (_pitch ? _pitVals(e.$2) : _batVals(e.$2))[col];
    ps.sort((a, b) {
      if (isRate && qual(a) != qual(b)) return qual(a) ? -1 : 1; // 規定到達者が先
      final c = low ? val(a).compareTo(val(b)) : val(b).compareTo(val(a));
      return c != 0 ? c : _pa(b.$2).compareTo(_pa(a.$2));
    });
    final cols = _pitch ? _pitCols : _batCols;
    final firstNonQual = isRate ? ps.indexWhere((p) => !qual(p)) : -1;
    final rows = <FrozenRow>[
      for (var i = 0; i < ps.length; i++)
        FrozenRow(
          color: i == firstNonQual && i > 0 ? const Color(0xFFF5F5F4) : (isRate && !qual(ps[i]) ? const Color(0xFFFAFAF9) : null),
          onTap: () => showPlayerDetail(context, app, ps[i].$1, allowActions: _team.id == app.myTeamId && !ps[i].$3),
          lead: Row(children: [
            SizedBox(width: 26, child: Text(ps[i].$1.mainPosition.isEmpty ? '' : ps[i].$1.mainPosition.substring(0, 1), style: const TextStyle(fontSize: 11, color: Color(0xFF78716C)))),
            Expanded(child: Text(ps[i].$1.listName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: (isRate && !qual(ps[i])) || ps[i].$3 ? const Color(0xFF78716C) : null))),
            if (ps[i].$3) const Text('移籍', style: TextStyle(fontSize: 9.5, color: Color(0xFFB45309), fontWeight: FontWeight.w700)),
          ]),
          cells: _pitch ? _pitCells(ps[i].$2) : _batCells(ps[i].$2),
        ),
    ];
    return ListView(padding: const EdgeInsets.fromLTRB(12, 10, 12, 24), children: [
      Wrap(spacing: 10, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        DropdownButton<Team>(
          value: _team,
          items: [for (final t in app.teams) DropdownMenuItem(value: t, child: Text(t.name, style: TextStyle(fontWeight: t.id == app.myTeamId ? FontWeight.w900 : FontWeight.w500)))],
          onChanged: (t) => setState(() => _team = t ?? _team),
        ),
        SegmentedButton<int>(
          segments: const [ButtonSegment(value: 0, label: Text('1軍')), ButtonSegment(value: 1, label: Text('2軍')), ButtonSegment(value: 2, label: Text('3軍'))],
          selected: {_level},
          showSelectedIcon: false,
          onSelectionChanged: (v) => setState(() => _level = v.first),
        ),
        SegmentedButton<bool>(
          segments: const [ButtonSegment(value: false, label: Text('打撃')), ButtonSegment(value: true, label: Text('投手'))],
          selected: {_pitch},
          showSelectedIcon: false,
          onSelectionChanged: (v) => setState(() => _pitch = v.first),
        ),
      ]),
      const SizedBox(height: 4),
      Text('今季の${_level + 1}軍${_level == 0 ? '・公式戦' : (_level == 2 ? '（3軍戦は簡易計算）' : '')}。規定：${_pitch ? '$g投球回' : '$qPa打席'}（$g試合消化）。この球団でプレーした分（「移籍」は今季この球団にいて移った選手の、この球団での成績）。見出しを押すと並べ替え。率の項目は規定に届いた選手が先、届いていない選手（灰色）はその後',
          style: const TextStyle(fontSize: 11, color: Color(0xFF78716C))),
      const SizedBox(height: 6),
      if (ps.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('今季の成績はまだありません', style: TextStyle(color: Color(0xFF78716C)))),
      if (ps.isNotEmpty)
        LayoutBuilder(
          builder: (context, c) => FrozenTable(
            leadHeader: '選手',
            leadWidth: (c.maxWidth * 0.32).clamp(118.0, 200.0),
            headers: cols,
            widths: [for (final h in cols) h.length >= 3 ? 52.0 : 44.0],
            rows: rows,
            rowHeight: 34,
            sortCol: col,
            onSort: (i) => setState(() {
              if (_pitch) {
                _sortPit = i;
              } else {
                _sortBat = i;
              }
            }),
          ),
        ),
    ]);
  }
}
