import 'package:flutter/material.dart';
import '../models/player.dart';
import '../providers/app_state.dart';
import '../utils/standings.dart';
import '../widgets/frozen_table.dart';

const _ink = Color(0xFF1C1917);
const _sub = Color(0xFF78716C);
const _line = Color(0xFFE7E5E4);
const _bg = Color(0xFFF5F5F4);

/// 1年度の記録：野球界全体（順位表の詳細・タイトル）と、球団ごと（1軍の成績・ベストオーダー・出来事）
///  今の年度は、ここまでの順位と成績・出来事
class TeamYearScreen extends StatefulWidget {
  final AppState app;
  final int year;
  final String teamId;
  const TeamYearScreen({super.key, required this.app, required this.year, required this.teamId});

  @override
  State<TeamYearScreen> createState() => _TeamYearScreenState();
}

/// 1人の1年度の成績（その球団の分）
class _Row {
  final String id, name, pos;
  final bool pitcher;
  final PlayerStats st;
  _Row(this.id, this.name, this.pos, this.pitcher, this.st);
}

class _YearData {
  final Map<String, List<Map<String, dynamic>>> standings; // リーグ → 行
  final Map<String, dynamic>? awards;
  final List<_Row> rows;
  final List<Map<String, dynamic>> events;
  _YearData(this.standings, this.awards, this.rows, this.events);
}

class _TeamYearScreenState extends State<TeamYearScreen> {
  AppState get app => widget.app;
  late String _teamId = widget.teamId;
  late Future<_YearData> _data = _load();
  bool get _current => widget.year == app.startYear;

  Future<_YearData> _load() async {
    // 順位表
    final standings = <String, List<Map<String, dynamic>>>{};
    if (_current) {
      final ts = computeTeamStats(app.teams, app.matches, StandingsKind.official);
      for (final lg in ['CL', 'PL']) {
        final recs = computeStandings(app.teams, app.matches, lg, StandingsKind.official);
        standings[lg] = [
          for (final r in recs)
            {
              'id': r.team.id, 'name': r.team.name, 'w': r.w, 'l': r.l, 'd': r.d, 'pct': r.pctText, 'gb': gamesBehind(recs.first, r), 'rs': r.rs, 'ra': r.ra,
              'era': ts[r.team.id]?.era ?? '-', 'avg': ts[r.team.id]?.avg ?? '-', 'hr': ts[r.team.id]?.hr ?? 0, 'sb': ts[r.team.id]?.sb ?? 0, 'e': ts[r.team.id]?.e ?? 0,
            },
        ];
      }
    } else {
      final saved = await app.loadStandings(widget.year);
      if (saved != null) {
        saved.forEach((k, v) => standings[k] = [for (final e in v as List) Map<String, dynamic>.from(e as Map)]);
      } else {
        // 順位表の詳細を残す前の年度：球団の記録（勝敗・順位）から
        final teamRows = await app.seasonRows(widget.year, 'team');
        for (final lg in ['CL', 'PL']) {
          final l = [
            for (final r in teamRows)
              if (r.$3['league'] == lg) {'id': r.$1, 'name': r.$3['name'], 'w': r.$3['wins'] ?? 0, 'l': r.$3['losses'] ?? 0, 'd': r.$3['draws'] ?? 0, 'rank': r.$3['rank'] ?? 9},
          ]..sort((a, b) => (a['rank'] as int).compareTo(b['rank'] as int));
          if (l.isNotEmpty) {
            final top = l.first;
            for (final e in l) {
              final w = e['w'] as int, lo = e['l'] as int;
              e['pct'] = w + lo == 0 ? '-' : (w / (w + lo)).toStringAsFixed(3).replaceFirst(RegExp(r'^0'), '');
              e['gb'] = identical(e, top) ? '-' : (((top['w'] as int) - w + lo - (top['l'] as int)) / 2).toStringAsFixed(1);
            }
            standings[lg] = l;
          }
        }
      }
    }
    // タイトル
    final awards = _current ? null : await app.loadAwards(widget.year);
    // 球団の1軍の成績
    final rows = <_Row>[];
    if (_current) {
      final t = app.teamById(_teamId);
      if (t != null) {
        for (final (p, st, _) in app.teamSeasonEntries(t, 0)) {
          if (st.games + st.pitchApps > 0) rows.add(_Row(p.id, p.registeredName, p.isPitcher ? '投手' : p.mainPosition, p.isPitcher, st));
        }
      }
    } else {
      for (final r in await app.seasonRows(widget.year, 'player')) {
        final j = r.$3;
        void add(Map? st) {
          if (st == null) return;
          final s = PlayerStats.fromJson(Map<String, dynamic>.from(st));
          if (s.games + s.pitchApps > 0) rows.add(_Row(r.$1, '${j['name'] ?? ''}', '${j['pos'] ?? ''}', j['pos'] == '投手', s));
        }
        if (r.$2 == _teamId) add(j['stats'] as Map?);
        for (final sp in (j['splits'] as List? ?? const [])) {
          if (sp is Map && '${sp['team']}'.split('/').last == _teamId) add(sp['stats'] as Map?);
        }
      }
    }
    // 出来事
    final events = [for (final e in await app.chronicleOf(widget.year)) if (e['team'] == _teamId) e]..sort((a, b) => (a['d'] as String).compareTo(b['d'] as String));
    return _YearData(standings, awards, rows, events);
  }

  @override
  Widget build(BuildContext context) {
    final teams = app.teams.where((t) => t.league == 'CL' || t.league == 'PL').toList();
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(title: Text('${widget.year}年${_current ? '（今季）' : ''}の記録')),
      body: FutureBuilder<_YearData>(
        future: _data,
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final d = snap.data!;
          return ListView(padding: const EdgeInsets.fromLTRB(10, 10, 10, 30), children: [
            _h('順位表'),
            for (final e in d.standings.entries) _standings(e.key, e.value),
            if (d.standings.isEmpty) const Text('順位表の記録がありません', style: TextStyle(color: _sub)),
            const SizedBox(height: 12),
            _h('タイトル・表彰'),
            if (d.awards == null) Text(_current ? 'シーズンが終わると決まります' : '表彰の記録がありません', style: const TextStyle(color: _sub, fontSize: 12.5)) else ..._titles(d.awards!),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: _line)),
              child: DropdownButton<String>(
                value: _teamId,
                isExpanded: true,
                underline: const SizedBox.shrink(),
                items: [for (final t in teams) DropdownMenuItem(value: t.id, child: Text(t.name, style: TextStyle(fontWeight: t.id == app.myTeamId ? FontWeight.w900 : FontWeight.w600)))],
                onChanged: (v) => setState(() {
                  _teamId = v ?? _teamId;
                  _data = _load();
                }),
              ),
            ),
            const SizedBox(height: 10),
            _h('ベストオーダー（成績と起用数から）'),
            ..._bestOrder(d.rows),
            const SizedBox(height: 12),
            _h('1軍の成績（打撃）'),
            _batting(d.rows.where((r) => !r.pitcher || r.st.atBats > 0).toList()),
            const SizedBox(height: 12),
            _h('1軍の成績（投手）'),
            _pitching(d.rows.where((r) => r.st.pitchApps > 0).toList()),
            const SizedBox(height: 12),
            _h('出来事（入団・退団・コーチ・初記録・節目・監督）'),
            if (d.events.isEmpty) const Text('この年度の出来事の記録はありません（記録はこの機能を入れた後から残ります）', style: TextStyle(color: _sub, fontSize: 12.5)),
            for (final e in d.events)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(width: 44, child: Text(_md(e['d'] as String), style: const TextStyle(fontSize: 12, color: _sub))),
                  Expanded(child: Text('${e['t']}', style: TextStyle(fontSize: 12.5, height: 1.4, fontWeight: e['k'] == 'manager' || e['k'] == 'milestone' ? FontWeight.w800 : FontWeight.w400))),
                ]),
              ),
          ]);
        },
      ),
    );
  }

  static String _md(String ymd) {
    final p = ymd.split('-');
    return p.length < 3 ? ymd : '${int.parse(p[1])}/${int.parse(p[2])}';
  }

  Widget _h(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          Container(width: 3, height: 14, color: _ink),
          const SizedBox(width: 6),
          Text(s, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
        ]),
      );

  Widget _standings(String lg, List<Map<String, dynamic>> rows) {
    const cols = <(String, double)>[('勝', 38), ('敗', 38), ('分', 32), ('勝率', 50), ('差', 44), ('得点', 44), ('失点', 44), ('防御率', 52), ('打率', 48), ('本塁打', 48), ('盗塁', 40), ('失策', 40)];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(leagueLabel(lg), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        FrozenTable(
          leadHeader: '順位・球団',
          leadWidth: 132,
          headers: [for (final c in cols) c.$1],
          widths: [for (final c in cols) c.$2],
          rowHeight: 30,
          rows: [
            for (var i = 0; i < rows.length; i++)
              FrozenRow(
                color: rows[i]['id'] == _teamId ? const Color(0xFFFEF9C3) : null,
                lead: Text('${i + 1}　${_short(rows[i])}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                cells: [
                  '${rows[i]['w']}', '${rows[i]['l']}', '${rows[i]['d']}', '${rows[i]['pct'] ?? '-'}', '${rows[i]['gb'] ?? '-'}',
                  '${rows[i]['rs'] ?? '-'}', '${rows[i]['ra'] ?? '-'}', '${rows[i]['era'] ?? '-'}', '${rows[i]['avg'] ?? '-'}', '${rows[i]['hr'] ?? '-'}', '${rows[i]['sb'] ?? '-'}', '${rows[i]['e'] ?? '-'}',
                ],
              ),
          ],
        ),
      ]),
    );
  }

  String _short(Map<String, dynamic> r) {
    final t = app.teamById('${r['id']}');
    return t == null ? '${r['name']}' : teamShort(t);
  }

  List<Widget> _titles(Map<String, dynamic> aw) {
    String who(dynamic winners) {
      if (winners is! List || winners.isEmpty) return '該当者なし';
      return winners.map((w) => w is Map ? '${w['name']}（${w['teamName'] ?? ''}）' : '$w').join('・');
    }

    Widget line(String label, String text, {String value = ''}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 1.5),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 108, child: Text(label, style: const TextStyle(fontSize: 12, color: _sub))),
            Expanded(child: Text('$text${value.isEmpty ? '' : '　$value'}', style: const TextStyle(fontSize: 12.5))),
          ]),
        );

    final out = <Widget>[];
    if (aw['champion'] != null) {
      final c = app.teamById('${aw['champion']}');
      out.add(line('日本一', c?.name ?? '${aw['champion']}'));
    }
    for (final s in (aw['series'] as List? ?? const [])) {
      if (s is! Map || '${s['winner']}'.isEmpty) continue;
      final w = app.teamById('${s['winner']}');
      out.add(line('${s['label']}', '${w == null ? s['winner'] : teamShort(w)} 勝ち抜け（${s['score'] ?? ''}）${'${s['mvp'] ?? ''}'.isNotEmpty ? '　MVP ${s['mvp']}' : ''}'));
    }
    final lgs = aw['leagues'];
    if (lgs is Map) {
      for (final e in lgs.entries) {
        final L = e.value;
        if (L is! Map) continue;
        out.add(Padding(padding: const EdgeInsets.only(top: 8, bottom: 2), child: Text(leagueLabel('${e.key}'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5))));
        if (L['mvp'] is Map) out.add(line('MVP', who(L['mvp']['winners'])));
        if (L['rookie'] is Map) out.add(line('新人王', who(L['rookie']['winners'])));
        for (final t in (L['titles'] as List? ?? const [])) {
          if (t is Map) out.add(line('${t['title']}', who(t['winners']), value: '${t['value'] ?? ''}'));
        }
        for (final b in (L['b9'] as List? ?? const [])) {
          if (b is Map) out.add(line('ベストナイン（${b['pos']}）', who(b['winners'])));
        }
        for (final g in (L['gg'] as List? ?? const [])) {
          if (g is Map) out.add(line('ゴールデングラブ（${g['pos']}）', who(g['winners'])));
        }
      }
    }
    if (aw['sawamura'] is Map) out.add(line('沢村賞', who(aw['sawamura']['winners'])));
    if (aw['comeback'] is Map && aw['comeback']['winners'] is List) out.add(line('カムバック賞', who(aw['comeback']['winners'])));
    return out;
  }

  // ───────── ベストオーダー ─────────

  static const _posKeys = {'捕': '捕手', '一': '一塁手', '二': '二塁手', '三': '三塁手', '遊': '遊撃手', '左': '左翼手', '中': '中堅手', '右': '右翼手', 'DH': 'DH'};

  static double _obp(PlayerStats s) {
    final pa = s.atBats + s.walks + s.hbp + s.sacFlies;
    return pa == 0 ? 0 : (s.hits + s.walks + s.hbp) / pa;
  }

  static double _slg(PlayerStats s) => s.atBats == 0 ? 0 : (s.hits + s.doubles + s.triples * 2 + s.homeRuns * 3) / s.atBats;

  List<Widget> _bestOrder(List<_Row> rows) {
    final bat = rows.where((r) => r.st.atBats > 0).toList();
    if (bat.isEmpty) return [const Text('記録がありません', style: TextStyle(color: _sub, fontSize: 12.5))];
    // 守備位置ごとに、その位置で先発した試合の多い選手（同じ選手は1つの位置だけ）
    final picked = <String, _Row>{};
    final used = <String>{};
    final order = ['捕', '遊', '二', '中', '三', '右', '左', '一', 'DH'];
    for (final pos in order) {
      final c = bat.where((r) => !used.contains(r.id) && (r.st.posGames[pos] ?? 0) > 0).toList()..sort((a, b) => (b.st.posGames[pos] ?? 0).compareTo(a.st.posGames[pos] ?? 0));
      if (c.isEmpty) continue;
      picked[pos] = c.first;
      used.add(c.first.id);
    }
    // 打順：1番＝出塁率と足、4番＝長打（OPS）、3・5番＝次の OPS、2番＝次の出塁率、6〜9番＝残りを OPS 順
    final pool = picked.entries.toList();
    final slots = List<MapEntry<String, _Row>?>.filled(9, null);
    MapEntry<String, _Row>? take(double Function(PlayerStats) score) {
      if (pool.isEmpty) return null;
      pool.sort((a, b) => score(b.value.st).compareTo(score(a.value.st)));
      return pool.removeAt(0);
    }

    double ops(PlayerStats s) => _obp(s) + _slg(s);
    slots[3] = take((s) => ops(s) + s.homeRuns * 0.004);
    slots[0] = take((s) => _obp(s) + s.stolenBases * 0.004);
    slots[2] = take(ops);
    slots[4] = take(ops);
    slots[1] = take(_obp);
    for (var i = 5; i < 9; i++) {
      slots[i] = take(ops);
    }
    String avg(PlayerStats s) => s.atBats == 0 ? '-' : s.battingAverage.toStringAsFixed(3).replaceFirst(RegExp(r'^0'), '');
    final out = <Widget>[
      for (var i = 0; i < 9; i++)
        if (slots[i] != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 1.5),
            child: Row(children: [
              SizedBox(width: 22, child: Text('${i + 1}', style: const TextStyle(fontWeight: FontWeight.w900))),
              SizedBox(width: 30, child: Text(slots[i]!.key, style: const TextStyle(fontWeight: FontWeight.w800))),
              Expanded(child: Text(slots[i]!.value.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
              Text('${avg(slots[i]!.value.st)} ${slots[i]!.value.st.homeRuns}本 ${slots[i]!.value.st.rbi}点　${_posKeys[slots[i]!.key]}${slots[i]!.value.st.posGames[slots[i]!.key] ?? 0}試合',
                  style: const TextStyle(fontSize: 11.5, color: _sub)),
            ]),
          ),
    ];
    // 投手：先発（先発の多い順に5人）・抑え（セーブ）・中継ぎ（ホールド）
    final pit = rows.where((r) => r.st.pitchApps > 0).toList();
    String era(PlayerStats s) => s.inningsPitched == 0 ? '-' : s.era.toStringAsFixed(2);
    final sp = [...pit.where((r) => r.st.starts > 0)]..sort((a, b) => b.st.starts.compareTo(a.st.starts));
    final cl = [...pit]..sort((a, b) => b.st.saves.compareTo(a.st.saves));
    final su = [...pit.where((r) => !sp.take(5).contains(r) && (cl.isEmpty || r != cl.first))]..sort((a, b) => b.st.holdPoints.compareTo(a.st.holdPoints));
    Widget pline(String role, _Row r, String note) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 1.5),
          child: Row(children: [
            SizedBox(width: 52, child: Text(role, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800))),
            Expanded(child: Text(r.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
            Text(note, style: const TextStyle(fontSize: 11.5, color: _sub)),
          ]),
        );
    out.add(const SizedBox(height: 6));
    for (var i = 0; i < sp.length && i < 5; i++) {
      out.add(pline('先発${i + 1}', sp[i], '${sp[i].st.wins}勝${sp[i].st.losses}敗 防${era(sp[i].st)}　先発${sp[i].st.starts}'));
    }
    for (final r in su.take(3)) {
      if (r.st.holdPoints > 0) out.add(pline('中継ぎ', r, '${r.st.holds}H 防${era(r.st)}　登板${r.st.apps}'));
    }
    if (cl.isNotEmpty && cl.first.st.saves > 0) out.add(pline('抑え', cl.first, '${cl.first.st.saves}S 防${era(cl.first.st)}　登板${cl.first.st.apps}'));
    return out;
  }

  // ───────── 1軍の成績 ─────────

  Widget _batting(List<_Row> rows) {
    if (rows.isEmpty) return const Text('記録がありません', style: TextStyle(color: _sub, fontSize: 12.5));
    rows.sort((a, b) => (b.st.atBats + b.st.walks).compareTo(a.st.atBats + a.st.walks));
    const cols = <(String, double)>[('試合', 38), ('打数', 40), ('安打', 40), ('本', 32), ('打点', 38), ('盗塁', 38), ('四球', 38), ('三振', 38), ('打率', 46), ('出塁率', 50), ('OPS', 46)];
    String r3(double v) => v.toStringAsFixed(3).replaceFirst(RegExp(r'^0'), '');
    return FrozenTable(
      leadHeader: '選手',
      leadWidth: 118,
      headers: [for (final c in cols) c.$1],
      widths: [for (final c in cols) c.$2],
      rowHeight: 28,
      rows: [
        for (final r in rows)
          FrozenRow(
            lead: Text('${r.pos.isEmpty ? '' : r.pos.substring(0, 1)} ${r.name}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
            cells: [
              '${r.st.games}', '${r.st.atBats}', '${r.st.hits}', '${r.st.homeRuns}', '${r.st.rbi}', '${r.st.stolenBases}', '${r.st.walks}', '${r.st.strikeouts}',
              r.st.atBats == 0 ? '-' : r3(r.st.battingAverage), r3(_obp(r.st)), r3(_obp(r.st) + _slg(r.st)),
            ],
          ),
      ],
    );
  }

  Widget _pitching(List<_Row> rows) {
    if (rows.isEmpty) return const Text('記録がありません', style: TextStyle(color: _sub, fontSize: 12.5));
    rows.sort((a, b) => b.st.inningsPitched.compareTo(a.st.inningsPitched));
    const cols = <(String, double)>[('登板', 38), ('先発', 38), ('勝', 32), ('敗', 32), ('S', 30), ('H', 30), ('投球回', 50), ('奪三振', 46), ('与四球', 46), ('防御率', 50)];
    return FrozenTable(
      leadHeader: '投手',
      leadWidth: 118,
      headers: [for (final c in cols) c.$1],
      widths: [for (final c in cols) c.$2],
      rowHeight: 28,
      rows: [
        for (final r in rows)
          FrozenRow(
            lead: Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
            cells: [
              '${r.st.apps}', '${r.st.starts}', '${r.st.wins}', '${r.st.losses}', '${r.st.saves}', '${r.st.holds}',
              '${r.st.inningsPitched ~/ 3}${r.st.inningsPitched % 3 == 0 ? '' : '.${r.st.inningsPitched % 3}'}', '${r.st.pitcherStrikeouts}', '${r.st.pitcherWalks}',
              r.st.inningsPitched == 0 ? '-' : r.st.era.toStringAsFixed(2),
            ],
          ),
      ],
    );
  }
}

/// 球団の歴史の1年度の行から開く
void openTeamYear(BuildContext context, AppState app, int year, String teamId) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => TeamYearScreen(app: app, year: year, teamId: teamId)));
