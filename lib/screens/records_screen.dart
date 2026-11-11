import '../widgets/chip_grid.dart';
import 'package:flutter/material.dart';
import '../models/player.dart';
import '../providers/app_state.dart';
import '../utils/standings.dart';
import '../widgets/player_detail_dialog.dart' show showPlayerDetail;
import 'team_year_screen.dart';
import 'ob_screen.dart';
import 'draft_book_view.dart';
import 'record_search_view.dart';

const _ink = Color(0xFF1C1917);
const _sub = Color(0xFF78716C);
const _line = Color(0xFFE7E5E4);

/// 監督室の「記録」タブ：月間MVP・歴代記録・殿堂入り・球団の歴史・自分の戦績
class RecordsTab extends StatefulWidget {
  final AppState app;
  const RecordsTab({super.key, required this.app});

  @override
  State<RecordsTab> createState() => _RecordsTabState();
}

class _RecordsTabState extends State<RecordsTab> {
  String _view = '月間MVP';
  AppState get app => widget.app;

  @override
  Widget build(BuildContext context) {
    const views = ['月間MVP', '歴代記録', '条件で探す', '歴代表彰', 'ドラフト', '殿堂', '球団の歴史', '背番号', 'OB', '自分の戦績'];
    return Column(children: [
      Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        child: ChipGrid<String>(items: [for (final v in views) (v, v)], selected: _view, minWidth: 80, padding: EdgeInsets.zero, onSelect: (v) => setState(() => _view = v)),
      ),
      Expanded(
        child: switch (_view) {
          '月間MVP' => _MonthlyMvpView(app: app),
          '歴代記録' => _AllTimeView(app: app),
          '条件で探す' => RecordSearchView(app: app),
          '歴代表彰' => HistoryAwardsView(app: app),
          '殿堂' => _HallOfFameView(app: app),
          '球団の歴史' => _TeamHistoryView(app: app),
          '背番号' => _NumberHistoryView(app: app),
          'OB' => ObListView(app: app),
          'ドラフト' => DraftBookView(app: app),
          _ => _MyCareerView(app: app),
        },
      ),
    ]);
  }
}

Widget _sectionTitle(String s) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 4),
      child: Text(s, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: _ink)),
    );

// ───────── 月間MVP ─────────
class _MonthlyMvpView extends StatelessWidget {
  final AppState app;
  const _MonthlyMvpView({required this.app});

  @override
  Widget build(BuildContext context) {
    final list = app.monthlyMvps;
    if (list.isEmpty) {
      return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('今季の月間MVPはまだありません（5月1日に3・4月の分が決まります）', style: TextStyle(color: _sub))));
    }
    final months = <String>[];
    for (final e in list) {
      if (!months.contains(e['month'])) months.add(e['month'] as String);
    }
    return ListView(padding: const EdgeInsets.fromLTRB(8, 4, 8, 20), children: [
      for (final m in months) ...[
        _sectionTitle('${app.startYear}年 $m'),
        for (final lg in const ['CL', 'PL'])
          for (final e in list.where((e) => e['month'] == m && e['league'] == lg))
            Container(
              padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 6),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _line))),
              child: Row(children: [
                SizedBox(width: 64, child: Text('${leagueLabel(lg)}\n${e['kind']}', style: const TextStyle(fontSize: 10.5, color: _sub, height: 1.2))),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${e['name']}（${e['teamName']}）', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                    Text('${e['line']}', style: const TextStyle(fontSize: 11.5, color: _sub)),
                  ]),
                ),
              ]),
            ),
      ],
    ]);
  }
}

// ───────── 歴代記録 ─────────
class _Rec {
  final String name, team, year;
  final double value;
  final String shown;
  final Player? player;
  _Rec(this.name, this.team, this.year, this.value, this.shown, [this.player]);
}

class _AllTimeView extends StatefulWidget {
  final AppState app;
  const _AllTimeView({required this.app});

  @override
  State<_AllTimeView> createState() => _AllTimeViewState();
}

class _AllTimeViewState extends State<_AllTimeView> {
  bool _career = false; // false=シーズン記録、true=通算記録
  bool _pitch = false;
  String _stat = '安打';
  late final Future<List<(int, String, String, PlayerStats)>> _seasons = widget.app.allPlayerSeasons();
  AppState get app => widget.app;

  static const _batStats = ['安打', '二塁打', '三塁打', '本塁打', '塁打', '打点', '盗塁', '盗塁阻止', '得点', '四球', '死球', '打率', '出塁率', '長打率', 'OPS', '得点圏打率', '猛打賞', 'マルチヒット', '2本塁打以上', 'サヨナラ打', '連続試合安打', '連続試合出塁', '連続試合本塁打', '失策', '補殺', '刺殺'];
  static const _pitStats = ['勝利', 'セーブ', 'ホールド', '奪三振', '防御率', '登板', '投球回', '完投', '完封', 'ノーヒットノーラン', 'QS', '2桁奪三振', '連続イニング無失点', '救援連続無失点'];
  // 連続記録（今季は継続中の記録、通算は自己最高）
  static const _streakKeys = {'連続試合安打': 'hit', '連続試合出塁': 'onBase', '連続試合本塁打': 'hr', '連続イニング無失点': 'scoreless', '救援連続無失点': 'relief'};
  static (double, String)? _streakValue(Player p, String stat, {required bool best}) {
    final k = _streakKeys[stat];
    if (k == null) return null;
    final m = p.streaks[k];
    final v = ((m == null ? null : (best ? m['best'] : m['cur'])) ?? 0) as int;
    if (v == 0) return null;
    if (k == 'scoreless') return (v.toDouble(), '${v ~/ 3}${v % 3 > 0 ? ' ${v % 3}/3' : ''}回');
    final since = best ? '${m?['bestStart'] ?? ''}〜${m?['bestEnd'] ?? ''}' : '${m?['start'] ?? ''}〜';
    return (v.toDouble(), '$v（$since）');
  }
  static const _careerExtra = ['タイトル', '連続試合出場'];

  static String _rate(double v) => v.toStringAsFixed(3).replaceFirst(RegExp(r'^0'), '');

  /// 成績から値を出す（null=条件に届かない）
  (double, String)? _value(PlayerStats s, String k) {
    final pa = s.atBats + s.walks + s.sacFlies + s.hbp;
    final minPa = _career ? 3000 : 484;
    final minIp = _career ? 3000 : 468; // アウトの数（シーズン156回・通算1000回）
    final tb = s.hits + s.doubles + s.triples * 2 + s.homeRuns * 3;
    double obp() => pa == 0 ? 0 : (s.hits + s.walks + s.hbp) / pa;
    double slg() => s.atBats == 0 ? 0 : tb / s.atBats;
    switch (k) {
      case '安打': return (s.hits.toDouble(), '${s.hits}');
      case '二塁打': return (s.doubles.toDouble(), '${s.doubles}');
      case '三塁打': return (s.triples.toDouble(), '${s.triples}');
      case '本塁打': return (s.homeRuns.toDouble(), '${s.homeRuns}');
      case '塁打': return (tb.toDouble(), '$tb');
      case '打点': return (s.rbi.toDouble(), '${s.rbi}');
      case '盗塁': return (s.stolenBases.toDouble(), '${s.stolenBases}');
      case '盗塁阻止': return (s.csAgainst.toDouble(), '${s.csAgainst}');
      case '得点': return (s.runs.toDouble(), '${s.runs}');
      case '四球': return (s.walks.toDouble(), '${s.walks}');
      case '死球': return (s.hbp.toDouble(), '${s.hbp}');
      case '打率': return pa < minPa ? null : (s.battingAverage, _rate(s.battingAverage));
      case '出塁率': return pa < minPa ? null : (obp(), _rate(obp()));
      case '長打率': return pa < minPa ? null : (slg(), _rate(slg()));
      case 'OPS': return pa < minPa ? null : (obp() + slg(), _rate(obp() + slg()));
      case '得点圏打率': return pa < minPa || s.rispAB == 0 ? null : (s.rispAvg, '${_rate(s.rispAvg)}（${s.rispH}/${s.rispAB}）');
      case '2本塁打以上': return (s.multiHR.toDouble(), '${s.multiHR}');
      case 'サヨナラ打': return (s.walkoffs.toDouble(), '${s.walkoffs}');
      case 'QS': return (s.qs.toDouble(), '${s.qs}');
      case '2桁奪三振': return (s.tenK.toDouble(), '${s.tenK}');
      case '猛打賞': return (s.mouda.toDouble(), '${s.mouda}');
      case 'マルチヒット': return (s.multiHit.toDouble(), '${s.multiHit}');
      case '失策': return (s.errors.toDouble(), '${s.errors}');
      case '補殺': return (s.assists.toDouble(), '${s.assists}');
      case '刺殺': return (s.putouts.toDouble(), '${s.putouts}');
      case '勝利': return (s.wins.toDouble(), '${s.wins}');
      case 'セーブ': return (s.saves.toDouble(), '${s.saves}');
      case 'ホールド': return (s.holds.toDouble(), '${s.holds}');
      case '奪三振': return (s.pitcherStrikeouts.toDouble(), '${s.pitcherStrikeouts}');
      case '防御率': return s.inningsPitched < minIp ? null : (-s.era, s.era.toStringAsFixed(2));
      case '登板': return (s.apps.toDouble(), '${s.apps}');
      case '投球回': return (s.inningsPitched.toDouble(), '${s.inningsPitched ~/ 3}');
      case '完投': return (s.completeGames.toDouble(), '${s.completeGames}');
      case '完封': return (s.shutouts.toDouble(), '${s.shutouts}');
      case 'ノーヒットノーラン': return ((s.noHitters + s.perfects).toDouble(), '${s.noHitters + s.perfects}${s.perfects > 0 ? '（完全${s.perfects}）' : ''}');
    }
    return null;
  }

  static int _titleCount(List<String> honors) => honors.where((h) => const ['首位打者', '本塁打王', '打点王', '盗塁王', '最高出塁率', '最多安打', '最優秀防御率', '最多勝', '最多奪三振', '最多セーブ', '最優秀中継ぎ', '最高勝率', 'MVP', '沢村賞'].any((t) => h.contains(t)) && !h.contains('月間')).length;

  @override
  Widget build(BuildContext context) {
    final stats = [..._pitch ? _pitStats : _batStats, if (_career && !_pitch) ..._careerExtra];
    if (!stats.contains(_stat)) _stat = stats.first;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 2),
        child: Row(children: [
          SegmentedButton<bool>(
            segments: const [ButtonSegment(value: false, label: Text('シーズン')), ButtonSegment(value: true, label: Text('通算'))],
            selected: {_career},
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(visualDensity: VisualDensity.compact),
            onSelectionChanged: (v) => setState(() => _career = v.first),
          ),
          const SizedBox(width: 8),
          SegmentedButton<bool>(
            segments: const [ButtonSegment(value: false, label: Text('打撃')), ButtonSegment(value: true, label: Text('投手'))],
            selected: {_pitch},
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(visualDensity: VisualDensity.compact),
            onSelectionChanged: (v) => setState(() => _pitch = v.first),
          ),
        ]),
      ),
      ChipGrid<String>(items: [for (final s in stats) (s, s)], selected: _stat, minWidth: 52, onSelect: (s) => setState(() => _stat = s)),
      Expanded(
        child: FutureBuilder<List<(int, String, String, PlayerStats)>>(
          future: _seasons,
          builder: (context, snap) {
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final recs = <_Rec>[];
            String tn(String id) => app.teamById(id) == null ? '−' : teamShort(app.teamById(id)!);
            if (!_career) {
              for (final h in snap.data!) {
                final v = _value(h.$4, _stat);
                if (v != null && v.$1 != 0) recs.add(_Rec(h.$3, tn(h.$2), '${h.$1}', v.$1, v.$2));
              }
              for (final t in app.teams) {
                for (final p in t.players) {
                  final v = _streakKeys.containsKey(_stat) ? _streakValue(p, _stat, best: false) : _value(p.seasonStats, _stat);
                  if (v != null && v.$1 != 0) recs.add(_Rec(p.registeredName, teamShort(t), _streakKeys.containsKey(_stat) ? '継続中' : '${app.startYear}（今季）', v.$1, v.$2, p));
                }
              }
            } else {
              for (final t in app.teams) {
                for (final p in t.players) {
                  final total = app.careerTotalOf(p);
                  final (double, String)? v = switch (_stat) {
                    'タイトル' => (_titleCount(p.honors).toDouble(), '${_titleCount(p.honors)}'),
                    '連続試合安打' => (p.hitStreakBest.toDouble(), '${p.hitStreakBest}'),
                    '連続試合出場' => (p.playStreakBest.toDouble(), '${p.playStreakBest}'),
                    _ when _streakKeys.containsKey(_stat) => _streakValue(p, _stat, best: true),
                    _ => _value(total, _stat),
                  };
                  if (v != null && v.$1 != 0) recs.add(_Rec(p.registeredName, teamShort(t), '現役', v.$1, v.$2, p));
                }
              }
              for (final e in app.retirees) {
                final c = PlayerStats.fromJson(Map<String, dynamic>.from(e['career'] as Map));
                final honors = List<String>.from(e['honors'] as List? ?? const []);
                final (double, String)? v = switch (_stat) {
                  'タイトル' => (_titleCount(honors).toDouble(), '${_titleCount(honors)}'),
                  '連続試合安打' => ((e['hitStreakBest'] as num? ?? 0).toDouble(), '${e['hitStreakBest'] ?? 0}'),
                  '連続試合出場' => ((e['playStreakBest'] as num? ?? 0).toDouble(), '${e['playStreakBest'] ?? 0}'),
                  _ => _value(c, _stat),
                };
                if (v != null && v.$1 != 0) recs.add(_Rec('${e['name']}', '${e['teamName']}', '${e['year']}年引退', v.$1, v.$2));
              }
            }
            recs.sort((a, b) => b.value.compareTo(a.value));
            final top = recs.take(10).toList();
            if (top.isEmpty) return const Center(child: Text('記録がありません', style: TextStyle(color: _sub)));
            return ListView(padding: const EdgeInsets.fromLTRB(8, 0, 8, 20), children: [
              for (var i = 0; i < top.length; i++)
                InkWell(
                  onTap: top[i].player == null ? null : () => showPlayerDetail(context, app, top[i].player!),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _line))),
                    child: Row(children: [
                      SizedBox(width: 26, child: Text('${i + 1}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900))),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(top[i].name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                          Text('${top[i].team}　${top[i].year}', style: const TextStyle(fontSize: 11, color: _sub)),
                        ]),
                      ),
                      Text(top[i].shown, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()])),
                    ]),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(_career ? '通算の率は3000打席以上・1000投球回以上。引退した選手は1軍30試合以上の選手が対象。連続記録は自己最高（このゲームの中の記録）' : '率はシーズン484打席以上・156投球回以上。このゲームで終えたシーズンと今季が対象。連続記録は今続いている記録',
                    style: const TextStyle(fontSize: 10.5, color: _sub)),
              ),
            ]);
          },
        ),
      ),
    ]);
  }
}

// ───────── 殿堂 ─────────
class _HallOfFameView extends StatelessWidget {
  final AppState app;
  const _HallOfFameView({required this.app});

  @override
  Widget build(BuildContext context) {
    final inducted = app.retirees.where((e) => e['hof'] == true).toList()..sort((a, b) => ((b['hofYear'] ?? 0) as num).compareTo((a['hofYear'] ?? 0) as num));
    final cands = app.retirees.where((e) => e['hof'] != true && ((e['ballots'] ?? 0) as num) > 0 && ((e['ballots'] ?? 0) as num) < 15).toList()
      ..sort((a, b) => ((b['lastPct'] ?? 0) as num).compareTo((a['lastPct'] ?? 0) as num));
    String line(Map<String, dynamic> e) {
      final c = PlayerStats.fromJson(Map<String, dynamic>.from(e['career'] as Map));
      return e['pitcher'] == true ? '通算 ${c.wins}勝 ${c.saves}S ${c.pitcherStrikeouts}奪三振' : '通算 ${c.hits}安打 ${c.homeRuns}本 打率${c.battingAverage.toStringAsFixed(3).replaceFirst(RegExp(r'^0'), '')}';
    }
    return ListView(padding: const EdgeInsets.fromLTRB(8, 0, 8, 20), children: [
      _sectionTitle('殿堂入り（${inducted.length}人）'),
      if (inducted.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('まだいません。引退から5年たった選手が、記者投票で75%以上を集めると殿堂入りします', style: TextStyle(fontSize: 12, color: _sub))),
      for (final e in inducted)
        ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          leading: const Icon(Icons.emoji_events, color: Color(0xFFB45309)),
          title: Text('${e['name']}（元${e['teamName']}）', style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text('${e['hofYear']}年 殿堂入り（得票率${e['lastPct']}%）　${line(e)}'),
        ),
      _sectionTitle('殿堂入りの候補（前回の得票率）'),
      if (cands.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('候補はいません', style: TextStyle(fontSize: 12, color: _sub))),
      for (final e in cands)
        ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          title: Text('${e['name']}（元${e['teamName']}・${e['year']}年引退）'),
          subtitle: Text('${line(e)}　投票${e['ballots']}回目'),
          trailing: Text('${e['lastPct']}%', style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
    ]);
  }
}

// ───────── 球団の歴史 ─────────
class _TeamHistoryView extends StatefulWidget {
  final AppState app;
  const _TeamHistoryView({required this.app});

  @override
  State<_TeamHistoryView> createState() => _TeamHistoryViewState();
}

class _TeamHistoryViewState extends State<_TeamHistoryView> {
  late String _teamId = widget.app.myTeamId.isNotEmpty ? widget.app.myTeamId : widget.app.teams.first.id;
  AppState get app => widget.app;

  Future<List<(int, Map<String, dynamic>, List<String>)>> _load() async {
    final hist = await app.teamHistory(_teamId);
    final out = <(int, Map<String, dynamic>, List<String>)>[];
    for (final h in hist) {
      final aw = await app.loadAwards(h.$1);
      final notes = <String>[];
      void scan(dynamic winners, String label) {
        if (winners is! List) return;
        for (final w in winners) {
          if (w is Map && w['team'] == _teamId) notes.add('$label ${w['name']}');
        }
      }
      final lg = (aw?['leagues'] as Map?)?[h.$2['league']];
      if (lg is Map) {
        for (final t in (lg['titles'] as List? ?? const [])) {
          if (t is Map) scan(t['winners'], '${t['title']}');
        }
        if (lg['mvp'] is Map) scan(lg['mvp']['winners'], 'MVP');
        if (lg['rookie'] is Map) scan(lg['rookie']['winners'], '新人王');
      }
      out.add((h.$1, h.$2, notes));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final teams = app.teams.where((t) => t.league == 'CL' || t.league == 'PL').toList();
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
        child: DropdownButton<String>(
          value: _teamId,
          isExpanded: true,
          items: [for (final t in teams) DropdownMenuItem(value: t.id, child: Text(t.name, overflow: TextOverflow.ellipsis))],
          onChanged: (v) => setState(() => _teamId = v ?? _teamId),
        ),
      ),
      Expanded(
        child: FutureBuilder<List<(int, Map<String, dynamic>, List<String>)>>(
          key: ValueKey(_teamId),
          future: _load(),
          builder: (context, snap) {
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final rows = snap.data!.reversed.toList();
            return ListView(padding: const EdgeInsets.fromLTRB(8, 0, 8, 20), children: [
              const Padding(padding: EdgeInsets.fromLTRB(4, 0, 4, 6), child: Text('年度をタップすると、その年の順位表・タイトル、球団の1軍成績・ベストオーダー・出来事を見られます', style: TextStyle(fontSize: 11.5, color: _sub))),
              InkWell(
                onTap: () => openTeamYear(context, app, app.startYear, _teamId),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _line))),
                  child: Row(children: [
                    SizedBox(width: 48, child: Text('${app.startYear}', style: const TextStyle(fontWeight: FontWeight.w900))),
                    const Expanded(child: Text('今季（ここまでの順位・成績・出来事）', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
                    const Icon(Icons.chevron_right, size: 18, color: _sub),
                  ]),
                ),
              ),
              if (rows.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('まだ終えたシーズンがありません', style: TextStyle(color: _sub))),
              for (final r in rows)
                InkWell(onTap: () => openTeamYear(context, app, r.$1, _teamId), child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                  decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _line))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      SizedBox(width: 48, child: Text('${r.$1}', style: const TextStyle(fontWeight: FontWeight.w900))),
                      Text('${r.$2['rank'] ?? '-'}位　${r.$2['wins'] ?? 0}勝${r.$2['losses'] ?? 0}敗${r.$2['draws'] ?? 0}分',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                      if (r.$2['champion'] == true) const Text('　★日本一', style: TextStyle(fontSize: 12, color: Color(0xFFB45309), fontWeight: FontWeight.w900)),
                      if (r.$2['rank'] == 1 && r.$2['champion'] != true) const Text('　リーグ優勝', style: TextStyle(fontSize: 12, color: Color(0xFF15803D), fontWeight: FontWeight.w800)),
                    ]),
                    if ((r.$2['manager'] ?? '').toString().isNotEmpty) Text('監督：${r.$2['manager']}', style: const TextStyle(fontSize: 11, color: _sub)),
                    if (r.$3.isNotEmpty) Text(r.$3.join('　'), style: const TextStyle(fontSize: 11.5)),
                  ]),
                )),
            ]);
          },
        ),
      ),
    ]);
  }
}

// ───────── 自分の戦績 ─────────
class _MyCareerView extends StatelessWidget {
  final AppState app;
  const _MyCareerView({required this.app});

  @override
  Widget build(BuildContext context) {
    final list = app.myCareer.reversed.toList();
    if (list.isEmpty) return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('シーズンを終えると、ここに監督としての戦績が残ります', style: TextStyle(color: _sub))));
    int sum(String k) => list.fold<int>(0, (s, e) => s + ((e[k] ?? 0) as num).toInt());
    final w = sum('w'), l = sum('l'), d = sum('d');
    final pennants = list.where((e) => e['pennant'] == true).length;
    final champs = list.where((e) => e['champion'] == true).length;
    final best = (List.of(list)..sort((a, b) {
          double pct(Map e) => ((e['w'] ?? 0) as num) / (((e['w'] ?? 0) as num) + ((e['l'] ?? 0) as num)).clamp(1, 999);
          return pct(b).compareTo(pct(a));
        })).first;
    final teamsManaged = <String>[];
    for (final e in app.myCareer) {
      if (!teamsManaged.contains(e['teamName'])) teamsManaged.add(e['teamName'] as String);
    }
    return ListView(padding: const EdgeInsets.fromLTRB(8, 4, 8, 20), children: [
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: const Color(0xFF0B1626), borderRadius: BorderRadius.circular(10)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('監督通算 ${list.length}年　$w勝$l敗$d分（勝率${(w / (w + l).clamp(1, 99999)).toStringAsFixed(3).replaceFirst(RegExp(r'^0'), '')}）',
              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900)),
          Text('リーグ優勝 $pennants回　日本一 $champs回', style: const TextStyle(color: Color(0xFFC6F24E), fontSize: 13, fontWeight: FontWeight.w700)),
          Text('率いた球団：${teamsManaged.join('、')}', style: const TextStyle(color: Color(0xFFB8C6D8), fontSize: 12)),
          Text('最もよかったシーズン：${best['year']}年 ${best['teamName']}（${best['w']}勝${best['l']}敗・${best['rank']}位）', style: const TextStyle(color: Color(0xFFB8C6D8), fontSize: 12)),
        ]),
      ),
      _sectionTitle('年度ごと'),
      for (final e in list)
        Container(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _line))),
          child: Row(children: [
            SizedBox(width: 48, child: Text('${e['year']}', style: const TextStyle(fontWeight: FontWeight.w900))),
            Expanded(child: Text('${e['teamName']}', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5))),
            Text('${e['rank']}位　${e['w']}-${e['l']}-${e['d']}${e['champion'] == true ? '　★日本一' : (e['pennant'] == true ? '　優勝' : '')}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
          ]),
        ),
    ]);
  }
}


// ───────── 背番号の変遷 ─────────
/// 球団ごとの背番号の移り変わり（2026年2月から。入団・支配下登録・変更・退団）。番号順に、その番号をつけた選手を古い順に
class _NumberHistoryView extends StatefulWidget {
  final AppState app;
  const _NumberHistoryView({required this.app});
  @override
  State<_NumberHistoryView> createState() => _NumberHistoryViewState();
}

class _NumberHistoryViewState extends State<_NumberHistoryView> {
  late String _team = widget.app.myTeamId.isNotEmpty ? widget.app.myTeamId : widget.app.leagueTeams.first.id;

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final t = app.teamById(_team) ?? app.leagueTeams.first;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
        child: ChipGrid<String>(items: [for (final x in app.leagueTeams) (x.id, teamShort(x))], selected: t.id, minWidth: 56, padding: EdgeInsets.zero, onSelect: (v) => setState(() => _team = v)),
      ),
      Expanded(
        child: FutureBuilder<Map<int, List<(String, String, String)>>>(
          future: app.numberHistory(t),
          builder: (context, snap) {
            final h = snap.data;
            if (h == null) return const Center(child: CircularProgressIndicator());
            final keys = h.keys.toList()..sort((a, b) => uniformSortKey(a).compareTo(uniformSortKey(b)));
            // いまの番号（記録の続き）
            final now = {for (final p in t.players) p.uniformNumber: p};
            return ListView(padding: const EdgeInsets.fromLTRB(10, 0, 10, 16), children: [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Text('2026年2月からの記録です（それより前からつけている番号は載せていません）。背番号の変更は毎年2月1日に行われます。', style: TextStyle(fontSize: 11.5, color: _sub)),
              ),
              if (keys.isEmpty) const Text('まだ記録がありません', style: TextStyle(color: _sub)),
              for (final n in keys)
                Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFE7E5E4))),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(width: 52, child: Text('#${uniformLabel(n)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: _ink))),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        for (final e in h[n]!)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 1),
                            child: Text('${e.$1.replaceAll('-', '/')}　${e.$2}　${e.$3}', style: const TextStyle(fontSize: 12.5, color: _ink)),
                          ),
                        if (now[n] != null) Text('いま：${now[n]!.listName}', style: const TextStyle(fontSize: 11.5, color: _sub, fontWeight: FontWeight.w700)),
                      ]),
                    ),
                  ]),
                ),
            ]);
          },
        ),
      ),
    ]);
  }
}
