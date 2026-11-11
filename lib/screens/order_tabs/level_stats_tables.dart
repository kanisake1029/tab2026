import 'package:flutter/material.dart';
import '../../models/player.dart';
import '../../models/team.dart';
import '../../providers/app_state.dart';
import '../../utils/standings.dart';
import '../../widgets/frozen_table.dart';
import 'order_shared.dart';

/// チームタブ「成績」：その軍の個人成績（野手・投手）。初めは背番号順。
///  並び順を選ぶ（見出しを押す、または「並び順」）と、その項目の順に並べる。もう一度押すと背番号順に戻る。
///  率の項目（打率・出塁率・長打率・OPS・防御率・WHIP）は、規定に届いた選手をその順に並べ、届かない選手をその下にその順で並べる
class LevelStatsTables extends StatefulWidget {
  final Team team;
  final AppState appState;
  final int level; // 1〜3軍
  final Widget? extra;
  const LevelStatsTables({super.key, required this.team, required this.appState, required this.level, this.extra});

  @override
  State<LevelStatsTables> createState() => _LevelStatsTablesState();
}

class _LevelStatsTablesState extends State<LevelStatsTables> {
  static const _sub = Color(0xFF78716C);
  // 並び順の項目（null＝背番号順）。軍ごとに覚えておく
  static final Map<int, int?> _batSortOf = {}, _pitSortOf = {};
  int? get _batSort => _batSortOf[widget.level];
  int? get _pitSort => _pitSortOf[widget.level];

  static const _batHeads = ['試合', '打席', '打数', '安打', '打率', '得点圏', '本塁打', '打点', '二塁打', '三塁打', '四球', '死球', '犠打', '犠飛', '三振', '併殺', '塁打', '出塁率', '長打率', 'OPS'];
  static const _batWidths = <double>[28, 30, 30, 28, 36, 38, 36, 28, 36, 36, 28, 28, 28, 28, 28, 28, 28, 38, 38, 38];
  static const _batRates = {4, 5, 17, 18, 19}; // 打率・得点圏・出塁率・長打率・OPS
  static const _pitHeads = ['登板', '先発', '投球回', '防御率', '勝', '敗', 'H', 'S', '完投', '完封', '奪三振', '与四球', '被安打', '被本', 'WHIP'];
  static const _pitWidths = <double>[28, 28, 36, 38, 24, 24, 24, 24, 28, 28, 36, 36, 36, 28, 36];
  static const _pitRates = {3, 14}; // 小さいほど良い

  PlayerStats _st(Player p) => switch (widget.level) { 1 => p.shownStats, 3 => p.thirdStats, _ => p.farmStats };

  bool _inLevel(Player p) {
    final t = widget.team;
    return switch (widget.level) {
      1 => t.roster1G.contains(p.id) || p.shownStats.games > 0,
      3 => p.thirdStats.games > 0,
      _ => !t.roster1G.contains(p.id) || p.farmStats.games > 0,
    };
  }

  static int _pa(PlayerStats x) => x.atBats + x.walks + x.hbp + x.sacFlies + x.sacBunts;
  static double _obp(PlayerStats x) {
    final d = x.atBats + x.walks + x.hbp + x.sacFlies;
    return d == 0 ? 0 : (x.hits + x.walks + x.hbp) / d;
  }

  static double _slg(PlayerStats x) => x.atBats == 0 ? 0 : x.totalBases / x.atBats;
  static double _whip(PlayerStats x) => x.inningsPitched == 0 ? 0 : (x.hitsAllowed + x.pitcherWalks) * 3 / x.inningsPitched;
  static String _r3(double v) => v.toStringAsFixed(3).replaceFirst(RegExp(r'^0'), '');
  static String _ip(int outs) => '${outs ~/ 3}${outs % 3 == 0 ? '' : '.${outs % 3}'}';

  /// 並べ替えに使う値（率は、分母が0なら一番下）
  List<num> _batVals(PlayerStats x) => [
        x.games, _pa(x), x.atBats, x.hits, x.atBats == 0 ? -1 : x.battingAverage, x.rispAB == 0 ? -1 : x.rispAvg, x.homeRuns, x.rbi, x.doubles, x.triples, x.walks, x.hbp, x.sacBunts, x.sacFlies,
        x.strikeouts, x.gidp, x.totalBases, _pa(x) == 0 ? -1 : _obp(x), x.atBats == 0 ? -1 : _slg(x), _pa(x) == 0 ? -1 : _obp(x) + _slg(x),
      ];
  List<num> _pitVals(PlayerStats x) => [
        x.apps, x.starts, x.inningsPitched, x.inningsPitched == 0 ? 999 : x.era, x.wins, x.losses, x.holds, x.saves, x.completeGames, x.shutouts,
        x.pitcherStrikeouts, x.pitcherWalks, x.hitsAllowed, x.hrAllowed, x.inningsPitched == 0 ? 999 : _whip(x),
      ];

  /// 背番号順（00 は 0 の前）
  static int _byNumber(Player a, Player b) => a.uniformNumber.compareTo(b.uniformNumber);

  void _setBat(int? i) => setState(() => _batSortOf[widget.level] = _batSort == i ? null : i);
  void _setPit(int? i) => setState(() => _pitSortOf[widget.level] = _pitSort == i ? null : i);

  /// 並び順を選ぶ小さなメニュー
  Widget _sortMenu(List<String> heads, int? cur, void Function(int?) on) => PopupMenuButton<int>(
        tooltip: '並び順',
        initialValue: cur ?? -1,
        onSelected: (v) => on(v < 0 ? null : v),
        itemBuilder: (_) => [
          const PopupMenuItem(value: -1, height: 32, child: Text('背番号順', style: TextStyle(fontSize: 13))),
          for (var i = 0; i < heads.length; i++) PopupMenuItem(value: i, height: 32, child: Text('${heads[i]}順', style: const TextStyle(fontSize: 13))),
        ],
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(border: Border.all(color: const Color(0xFFD6D3D1)), borderRadius: BorderRadius.circular(4)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.sort, size: 14, color: _sub),
            const SizedBox(width: 3),
            Text(cur == null ? '背番号順' : '${heads[cur]}順', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
            const Icon(Icons.arrow_drop_down, size: 16, color: _sub),
          ]),
        ),
      );

  Widget _card(String title, Widget trailing, Widget child, {String? note}) => Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.fromLTRB(2, 4, 2, 2),
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: const Color(0xFFE7E5E4)), borderRadius: BorderRadius.circular(8)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 2, 3),
            child: Row(children: [Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13))), trailing]),
          ),
          child,
          if (note != null) Padding(padding: const EdgeInsets.fromLTRB(4, 3, 4, 2), child: Text(note, style: const TextStyle(fontSize: 10, color: _sub))),
        ]),
      );

  Widget _lead(Player p, {bool dim = false}) => Row(children: [
        SizedBox(width: 20, child: Text(p.uniformText, style: const TextStyle(fontSize: 10.5, color: _sub))),
        Expanded(child: Text(p.listName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: dim ? const Color(0xFF78716C) : null))),
      ]);

  @override
  Widget build(BuildContext context) {
    final app = widget.appState, team = widget.team, lv = widget.level;
    // 規定：1軍は 試合数×3.1 打席・×1.0 投球回、2軍・3軍は ×2.7 打席・×0.8 投球回（その軍の公式戦の消化試合数）
    final ms = switch (lv) { 1 => app.matches, 3 => app.thirdMatches, _ => app.farmMatches };
    final g = computeStandings(app.teams, ms, lv == 3 ? allLeagues : team.league, StandingsKind.official).where((r) => r.team.id == team.id).firstOrNull?.games ?? 0;
    final qPa = (g * (lv == 1 ? 3.1 : 2.7)).floor();
    final qOuts = (g * (lv == 1 ? 3 : 2.4)).round();

    // ---- 野手 ----
    final bats = team.players.where((p) => !p.isPitcher && _inLevel(p)).toList();
    final bs = _batSort;
    bool bq(Player p) => _pa(_st(p)) >= qPa;
    bats.sort((a, b) {
      if (bs == null) return _byNumber(a, b);
      if (_batRates.contains(bs) && bq(a) != bq(b)) return bq(a) ? -1 : 1; // 規定に届いた選手が先
      final c = _batVals(_st(b))[bs].compareTo(_batVals(_st(a))[bs]);
      return c != 0 ? c : _byNumber(a, b);
    });
    final batRate = bs != null && _batRates.contains(bs);
    final batTable = FrozenTable(
      leadHeader: '背番号・選手',
      leadWidth: 100,
      rowHeight: 22,
      compact: true,
      headers: _batHeads,
      widths: _batWidths,
      sortCol: bs,
      onSort: _setBat,
      rows: [
        for (final p in bats)
          () {
            final x = _st(p), pa = _pa(x), off = batRate && !bq(p);
            return FrozenRow(
              onTap: () => selectedOrderPlayer.value = p,
              color: off ? const Color(0xFFF5F5F4) : null,
              lead: _lead(p, dim: off),
              cells: [
                '${x.games}', '$pa', '${x.atBats}', '${x.hits}', x.atBats == 0 ? '-' : _r3(x.battingAverage), x.rispAB == 0 ? '-' : _r3(x.rispAvg), '${x.homeRuns}', '${x.rbi}',
                '${x.doubles}', '${x.triples}', '${x.walks}', '${x.hbp}', '${x.sacBunts}', '${x.sacFlies}', '${x.strikeouts}', '${x.gidp}', '${x.totalBases}',
                pa == 0 ? '-' : _r3(_obp(x)), x.atBats == 0 ? '-' : _r3(_slg(x)), pa == 0 ? '-' : _r3(_obp(x) + _slg(x)),
              ],
              styles: const [null, null, null, null, TextStyle(fontWeight: FontWeight.w700)],
            );
          }(),
      ],
    );

    // ---- 投手 ----
    final pits = team.players.where((p) => p.isPitcher && _inLevel(p)).toList();
    final ps = _pitSort;
    bool pq(Player p) => _st(p).inningsPitched >= qOuts;
    pits.sort((a, b) {
      if (ps == null) return _byNumber(a, b);
      if (_pitRates.contains(ps)) {
        if (pq(a) != pq(b)) return pq(a) ? -1 : 1;
        final c = _pitVals(_st(a))[ps].compareTo(_pitVals(_st(b))[ps]); // 小さいほど上
        return c != 0 ? c : _byNumber(a, b);
      }
      final c = _pitVals(_st(b))[ps].compareTo(_pitVals(_st(a))[ps]);
      return c != 0 ? c : _byNumber(a, b);
    });
    final pitRate = ps != null && _pitRates.contains(ps);
    final pitTable = FrozenTable(
      leadHeader: '背番号・選手',
      leadWidth: 100,
      rowHeight: 22,
      compact: true,
      headers: _pitHeads,
      widths: _pitWidths,
      sortCol: ps,
      onSort: _setPit,
      rows: [
        for (final p in pits)
          () {
            final x = _st(p), off = pitRate && !pq(p);
            return FrozenRow(
              onTap: () => selectedOrderPlayer.value = p,
              color: off ? const Color(0xFFF5F5F4) : null,
              lead: _lead(p, dim: off),
              cells: [
                '${x.apps}', '${x.starts}', _ip(x.inningsPitched), x.inningsPitched == 0 ? '-' : x.era.toStringAsFixed(2), '${x.wins}', '${x.losses}', '${x.holds}', '${x.saves}',
                '${x.completeGames}', '${x.shutouts}', '${x.pitcherStrikeouts}', '${x.pitcherWalks}', '${x.hitsAllowed}', '${x.hrAllowed}', x.inningsPitched == 0 ? '-' : _whip(x).toStringAsFixed(2),
              ],
              styles: const [null, null, null, TextStyle(fontWeight: FontWeight.w700)],
            );
          }(),
      ],
    );

    return ListView(padding: const EdgeInsets.fromLTRB(2, 4, 2, 24), children: [
      _card('$lv軍の個人成績（野手）', _sortMenu(_batHeads, bs, _setBat), batTable,
          note: batRate ? '規定打席 $qPa（チーム$g試合）に届いた選手が先。灰色は規定未達' : '見出しを押すとその順に並べ替え（もう一度押すと背番号順）'),
      _card('$lv軍の個人成績（投手）', _sortMenu(_pitHeads, ps, _setPit), pitTable,
          note: pitRate ? '規定投球回 ${_ip(qOuts)}（チーム$g試合）に届いた選手が先。灰色は規定未達' : null),
      ?widget.extra,
    ]);
  }
}
