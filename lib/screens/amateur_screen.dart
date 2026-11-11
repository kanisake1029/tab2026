import '../widgets/chip_grid.dart';
import 'package:flutter/material.dart';
import '../engine/amateur_season.dart';
import '../models/amateur.dart';
import '../providers/app_state.dart';
import '../utils/name_data.dart';

const _sub = Color(0xFF78716C);
const _ink = Color(0xFF1C1917);

/// アマチュア球界：今年の高校の大会（春・夏・秋）、大学リーグ、都市対抗。過去の年度は出さない
class AmateurScreen extends StatefulWidget {
  final AppState app;
  const AmateurScreen({super.key, required this.app});

  @override
  State<AmateurScreen> createState() => _AmateurScreenState();
}

class _AmateurScreenState extends State<AmateurScreen> {
  static String _cat = '高校';
  static String _season = '夏';
  static int _pref = 12; // 都道府県大会を見る県（東京）
  static int _region = 2; // 地区（関東）

  AmWorld? get w => widget.app.amWorld;

  @override
  Widget build(BuildContext context) {
    final w = this.w;
    if (w == null) return const Scaffold(body: Center(child: Text('準備しています…', style: TextStyle(color: _sub))));
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F4),
      appBar: AppBar(
        title: Text('アマチュア球界　${w.year}年度'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(40),
          child: Container(
            color: Colors.white,
            child: ChipGrid<String>(items: const [('高校', '高校'), ('大学', '大学'), ('社会人', '社会人')], selected: _cat, onSelect: (c) => setState(() => _cat = c)),
          ),
        ),
      ),
      body: switch (_cat) { '高校' => _highSchool(w), '大学' => _univ(w), _ => _corp(w) },
    );
  }

  // ───────── 高校 ─────────

  Widget _highSchool(AmWorld w) {
    final prefComps = w.comps.where((c) => c.stage == 'pref' && c.season == _season && c.pref == _pref).toList();
    final top = _season == '秋' ? w.comp('秋-region-$_region') : w.comp('$_season-koshien');
    return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
        child: SegmentedButton<String>(
          segments: const [ButtonSegment(value: '春', label: Text('春')), ButtonSegment(value: '夏', label: Text('夏')), ButtonSegment(value: '秋', label: Text('秋'))],
          selected: {_season},
          onSelectionChanged: (s) => setState(() => _season = s.first),
        ),
      ),
      if (_season == '秋') _regionChips(),
      if (top != null) _Tourn(w: w, c: top, app: widget.app, onTeam: _openTeam, big: true),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 4),
        child: Row(children: [
          Text('$_season季 都道府県大会', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
          const Spacer(),
          DropdownButton<int>(
            value: _pref,
            items: [for (var i = 0; i < NameData2.prefectures.length; i++) DropdownMenuItem(value: i, child: Text(NameData2.prefectures[i].$1))],
            onChanged: (v) => setState(() => _pref = v ?? _pref),
          ),
        ]),
      ),
      for (final c in prefComps) _Tourn(w: w, c: c, app: widget.app, onTeam: _openTeam),
    ]);
  }

  Widget _regionChips() => ChipGrid<int>(items: [for (var rg = 0; rg < amRegions.length; rg++) (rg, amRegions[rg])], selected: _region, minWidth: 70, onSelect: (rg) => setState(() => _region = rg));

  // ───────── 大学 ─────────

  Widget _univ(AmWorld w) {
    final cs = w.comps.where((c) => c.isLeague && c.region == _region).toList();
    return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
      _regionChips(),
      for (final c in cs) _League(w: w, c: c, app: widget.app, onTeam: _openTeam),
    ]);
  }

  // ───────── 社会人 ─────────

  Widget _corp(AmWorld w) {
    final main = w.comp('main'), q = w.comp('qual-$_region');
    return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
      if (main != null) _Tourn(w: w, c: main, app: widget.app, onTeam: _openTeam, big: true),
      const Padding(padding: EdgeInsets.fromLTRB(12, 14, 12, 0), child: Text('地区予選（各地区から3チーム＋ほかの地区の4位から5チーム）', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14))),
      _regionChips(),
      if (q != null) _Tourn(w: w, c: q, app: widget.app, onTeam: _openTeam),
    ]);
  }

  /// チーム：今年の試合と、自球団のスカウトが調べた選手
  void _openTeam(String id) {
    final w = this.w!;
    final t = w.team(id);
    if (t == null) return;
    final games = <(String, String)>[]; // (大会名, 行)
    for (final c in w.comps) {
      if (!c.teams.contains(id)) continue;
      if (c.isLeague) {
        final i = c.teams.indexOf(id);
        for (final g in c.games.where((g) => g[3] >= 0 && (g[1] == i || g[2] == i))) {
          final mine = g[1] == i ? g[3] : g[4], their = g[1] == i ? g[4] : g[3];
          final opp = w.team(c.teams[g[1] == i ? g[2] : g[1]])?.name ?? '';
          games.add((c.name, '${mine > their ? '○' : (mine < their ? '●' : '△')} $mine-$their　$opp'));
        }
      } else {
        for (var r = 0; r < c.scores.length; r++) {
          final slots = c.rounds[r];
          final k = slots.indexOf(id);
          if (k < 0) continue;
          final opp = slots[k ^ 1];
          final sc = c.scores[r][k ~/ 2];
          if (opp.isEmpty || sc.isEmpty) continue;
          final mine = k.isEven ? sc[0] : sc[1], their = k.isEven ? sc[1] : sc[0];
          games.add((c.name, '${_roundName(c, r)}　${mine > their ? '○' : '●'} $mine-$their　${w.team(opp)?.name ?? ''}'));
        }
      }
    }
    final my = widget.app.myTeamId;
    final known = w.playersOf(id).where((p) => p.foundBy.contains(my)).toList();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        builder: (c, sc) => ListView(controller: sc, padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
          Text(t.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          Text('${t.kind}・${NameData2.prefectures[t.pref].$1}（${amRegions[t.region]}）　今年 ${t.w}勝${t.l}敗${t.d > 0 ? '${t.d}分' : ''}', style: const TextStyle(color: _sub)),
          const SizedBox(height: 10),
          const Text('スカウトが調べた選手', style: TextStyle(fontWeight: FontWeight.w900)),
          if (known.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 4), child: Text('まだいません', style: TextStyle(color: _sub, fontSize: 12.5))),
          for (final p in known) Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text('${p.player.listName}　${p.player.isPitcher ? '投手' : p.player.mainPosition}　${p.grade}年', style: const TextStyle(fontSize: 13))),
          const SizedBox(height: 10),
          const Text('今年の試合', style: TextStyle(fontWeight: FontWeight.w900)),
          if (games.isEmpty) const Text('まだありません', style: TextStyle(color: _sub, fontSize: 12.5)),
          for (final g in games)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text('${g.$1}　${g.$2}', style: const TextStyle(fontSize: 12.5, fontFeatures: [FontFeature.tabularFigures()])),
            ),
        ]),
      ),
    );
  }
}

String _roundName(AmComp c, int r) => switch (c.totalRounds - r) { 1 => '決勝', 2 => '準決勝', 3 => '準々決勝', _ => '${r + 1}回戦' };

String _md(DateTime d) => '${d.month}/${d.day}';

/// トーナメント：回戦ごとの結果（新しい回戦が上）
class _Tourn extends StatelessWidget {
  final AmWorld w;
  final AmComp c;
  final AppState app;
  final void Function(String) onTeam;
  final bool big;
  const _Tourn({required this.w, required this.c, required this.app, required this.onTeam, this.big = false});

  @override
  Widget build(BuildContext context) {
    final champ = c.champion;
    final total = c.totalRounds;
    final head = Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      color: big ? const Color(0xFF0B1626) : Colors.white,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(c.name, style: TextStyle(fontSize: big ? 17 : 14.5, fontWeight: FontWeight.w900, color: big ? const Color(0xFFC6F24E) : _ink)),
        Text(
          c.teams.isEmpty
              ? '${_md(c.start)}開幕　出場${c.stage == 'koshien' ? '50校' : 'チーム'}は前の大会で決まります'
              : champ != null
                  ? '優勝　${w.team(champ)?.name ?? ''}　（${c.teams.length}${c.cat == '高校' ? '校' : 'チーム'}）'
                  : '${c.teams.length}${c.cat == '高校' ? '校' : 'チーム'}　${_md(c.start)}開幕　${c.scores.isEmpty ? '' : '${_roundName(c, c.scores.length - 1)}まで終了'}',
          style: TextStyle(fontSize: 12, color: big ? Colors.white70 : _sub),
        ),
      ]),
    );
    if (c.teams.isEmpty) return head;
    return Card(
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: PageStorageKey<String>('tourn_${c.id}'),
        initiallyExpanded: big,
        tilePadding: EdgeInsets.zero,
        title: head,
        childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        children: [
          for (var r = c.scores.length - 1; r >= 0; r--) ...[
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 2),
              child: Text('${_roundName(c, r)}　${_md(c.start.add(Duration(days: r * c.gap)))}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: _sub)),
            ),
            for (var i = 0; i < c.scores[r].length; i++)
              if (c.scores[r][i].isNotEmpty) _gameRow(c.rounds[r][i * 2], c.rounds[r][i * 2 + 1], c.scores[r][i]),
          ],
          if (!c.done && c.scores.length < total)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('次は${_roundName(c, c.scores.length)}（${_md(c.start.add(Duration(days: c.scores.length * c.gap)))}）　残り${c.rounds.last.where((x) => x.isNotEmpty).length}${c.cat == '高校' ? '校' : 'チーム'}', style: const TextStyle(fontSize: 12, color: _sub)),
            ),
        ],
      ),
    );
  }

  Widget _gameRow(String a, String b, List<int> sc) {
    final aw = sc[0] > sc[1];
    Widget name(String id, bool win) => Expanded(
          child: InkWell(
            onTap: () => onTeam(id),
            child: Text(_label(id), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, fontWeight: win ? FontWeight.w800 : FontWeight.w400, color: win ? _ink : _sub)),
          ),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        name(a, aw),
        SizedBox(width: 56, child: Text('${sc[0]} - ${sc[1]}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()]))),
        name(b, !aw),
      ]),
    );
  }

  /// 全国・地区の大会では、学校名のあとに都道府県（社会人は地区）
  String _label(String id) {
    final t = w.team(id);
    if (t == null) return '';
    if (c.stage == 'pref' || c.stage == 'qual') return t.name;
    if (t.kind == '社会人') return '${t.name}（${amRegions[t.region]}）';
    final p = NameData2.prefectures[t.pref].$1;
    return '${t.name}（${p == '北海道' ? p : p.substring(0, p.length - 1)}）';
  }
}

/// 大学リーグ：順位表と、最後の節の結果
class _League extends StatelessWidget {
  final AmWorld w;
  final AmComp c;
  final AppState app;
  final void Function(String) onTeam;
  const _League({required this.w, required this.c, required this.app, required this.onTeam});

  @override
  Widget build(BuildContext context) {
    final st = AmateurSeason.standings(c);
    final played = c.games.where((g) => g[3] >= 0).toList();
    final lastRound = played.isEmpty ? -1 : played.map((g) => g[0]).reduce((a, b) => a > b ? a : b);
    final nextRound = c.games.where((g) => g[3] < 0).map((g) => g[0]).fold<int?>(null, (a, b) => a == null || b < a ? b : a);
    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(c.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
          Text('6校　各50試合（${_md(c.start)}〜${_md(c.start.add(Duration(days: 49 * c.gap)))}）${c.done ? '　全日程終了' : nextRound == null ? '' : '　次は第${nextRound + 1}節（${_md(c.start.add(Duration(days: nextRound * c.gap)))}）'}', style: const TextStyle(fontSize: 12, color: _sub)),
          const SizedBox(height: 8),
          Table(
            columnWidths: const {0: FixedColumnWidth(28), 1: FlexColumnWidth(), 2: FixedColumnWidth(40), 3: FixedColumnWidth(40), 4: FixedColumnWidth(32), 5: FixedColumnWidth(52)},
            children: [
              const TableRow(children: [Text('位', style: TextStyle(fontSize: 11, color: _sub)), Text('大学', style: TextStyle(fontSize: 11, color: _sub)), Text('勝', style: TextStyle(fontSize: 11, color: _sub)), Text('敗', style: TextStyle(fontSize: 11, color: _sub)), Text('分', style: TextStyle(fontSize: 11, color: _sub)), Text('勝率', style: TextStyle(fontSize: 11, color: _sub))]),
              for (var i = 0; i < st.length; i++)
                TableRow(children: [
                  Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Text('${i + 1}', style: const TextStyle(fontWeight: FontWeight.w800))),
                  InkWell(onTap: () => onTeam(st[i].$1), child: Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Text(w.team(st[i].$1)?.name ?? '', style: const TextStyle(fontWeight: FontWeight.w700)))),
                  Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Text('${st[i].$2}')),
                  Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Text('${st[i].$3}')),
                  Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Text('${st[i].$4}')),
                  Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Text(st[i].$2 + st[i].$3 == 0 ? '-' : (st[i].$2 / (st[i].$2 + st[i].$3)).toStringAsFixed(3).replaceFirst('0.', '.'))),
                ]),
            ],
          ),
          if (lastRound >= 0) ...[
            const SizedBox(height: 10),
            Text('第${lastRound + 1}節の結果', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: _sub)),
            for (final g in played.where((g) => g[0] == lastRound))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text('${w.team(c.teams[g[1]])?.name}　${g[3]} - ${g[4]}　${w.team(c.teams[g[2]])?.name}', style: const TextStyle(fontSize: 12.5)),
              ),
          ],
        ]),
      ),
    );
  }
}
