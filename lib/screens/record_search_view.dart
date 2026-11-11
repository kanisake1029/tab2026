import '../widgets/chip_grid.dart';
import 'package:flutter/material.dart';
import '../engine/pre_career.dart';
import '../engine/record_query.dart';
import '../models/player.dart';
import '../models/team.dart';
import '../providers/app_state.dart';
import '../utils/standings.dart';
import '../widgets/player_avatar.dart';
import '../widgets/player_detail_dialog.dart' show showPlayerDetail;

const _ink = Color(0xFF1C1917);
const _sub = Color(0xFF78716C);
const _line = Color(0xFFE7E5E4);

/// 記録タブ「条件で探す」：節目の達成者（何試合目・何歳で）と連続記録を、投打・球団・並び順で絞る
class RecordSearchView extends StatefulWidget {
  final AppState app;
  const RecordSearchView({super.key, required this.app});

  @override
  State<RecordSearchView> createState() => _RecordSearchViewState();
}

class _RecordSearchViewState extends State<RecordSearchView> {
  AppState get app => widget.app;
  bool _streak = false;
  int _kind = 0, _mark = 4, _sKind = 0;
  String _hand = 'すべて';
  bool _mine = false;
  String _sort = '試合数';
  late Future<(GameLogs, Map<String, List<PreYear>>)> _data;

  @override
  void initState() {
    super.initState();
    _data = _load();
  }

  Future<(GameLogs, Map<String, List<PreYear>>)> _load() async => (await app.gameLogs(), await app.preCareers());

  List<(Player, Team?)> get _players => [
        for (final t in app.teams)
          if (!_mine || t.id == app.myTeamId)
            for (final p in t.players) (p, t),
        if (!_mine)
          for (final f in app.freeAgents) (f.player, null),
      ];

  bool _handOk(Player p, bool batter) => switch (_hand) {
        '右' => batter ? p.bats == 'R' : p.throws == 'R',
        '左' => batter ? p.bats == 'L' : p.throws == 'L',
        '両打' => batter && p.bats == 'S',
        _ => true,
      };

  Widget _chips<T>(List<(T, String)> items, T value, ValueChanged<T> on) => Wrap(spacing: 4, runSpacing: 4, children: [
        for (final it in items)
          ChoiceChip(
            label: Text(it.$2, style: const TextStyle(fontSize: 12)),
            selected: it.$1 == value,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onSelected: (_) => setState(() => on(it.$1)),
          ),
      ]);

  Widget _label(String s) => Padding(padding: const EdgeInsets.only(top: 6, bottom: 2), child: Text(s, style: const TextStyle(fontSize: 11, color: _sub)));

  @override
  Widget build(BuildContext context) {
    final mk = MilestoneKind.all[_kind];
    final sk = StreakKind.all[_sKind];
    final batter = _streak ? sk.batter : mk.batter;
    final mark = mk.marks[_mark.clamp(0, mk.marks.length - 1)];
    return FutureBuilder<(GameLogs, Map<String, List<PreYear>>)>(
      future: _data,
      builder: (context, snap) {
        final filters = Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SegmentedButton<bool>(
              segments: const [ButtonSegment(value: false, label: Text('節目の達成')), ButtonSegment(value: true, label: Text('連続記録'))],
              selected: {_streak},
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(visualDensity: VisualDensity.compact),
              onSelectionChanged: (v) => setState(() => _streak = v.first),
            ),
            _label('記録'),
            if (!_streak) ...[
              _chips([for (var i = 0; i < MilestoneKind.all.length; i++) (i, MilestoneKind.all[i].label)], _kind, (v) {
                _kind = v;
                _mark = _mark.clamp(0, MilestoneKind.all[v].marks.length - 1);
              }),
              _label('通算'),
              _chips([for (var i = 0; i < mk.marks.length; i++) (i, '${mk.marks[i]}')], _mark, (v) => _mark = v),
            ] else
              _chips([for (var i = 0; i < StreakKind.all.length; i++) (i, StreakKind.all[i].label)], _sKind, (v) => _sKind = v),
            _label('条件'),
            Wrap(spacing: 12, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              _chips([('すべて', 'すべて'), ('右', batter ? '右打' : '右投'), ('左', batter ? '左打' : '左投'), if (batter) ('両打', '両打')], _hand, (v) => _hand = v),
              _chips([(false, '12球団'), (true, '自球団')], _mine, (v) => _mine = v),
            ]),
            if (!_streak) ...[
              _label('並び順'),
              _chips([('試合数', batter ? '少ない試合で' : '少ない登板で'), ('年齢', '若い年齢で'), ('日付', '早く達成した順')], _sort, (v) => _sort = v),
            ],
          ]),
        );
        if (!snap.hasData) return Column(children: [filters, const Expanded(child: Center(child: CircularProgressIndicator()))]);
        final (logs, teamGames) = snap.data!.$1;
        final pre = snap.data!.$2;
        final rows = <Widget>[];
        if (!_streak) {
          final hits = <(MilestoneHit, Team?)>[];
          for (final (p, t) in _players) {
            if (p.isPitcher == batter && !(batter && p.twoWay)) continue;
            if (!_handOk(p, batter)) continue;
            final h = RecordQuery.milestone(p, mk, mark, app.careerTotalOf(p), logs[p.id] ?? const [], pre[p.id] ?? const []);
            if (h != null) hits.add((h, t));
          }
          int dateKey(MilestoneHit h) => h.date != null ? h.date!.millisecondsSinceEpoch : DateTime(h.year == 0 ? 1900 : h.year, 12, 31).millisecondsSinceEpoch;
          hits.sort((a, b) => switch (_sort) {
                '年齢' => a.$1.age != b.$1.age ? a.$1.age.compareTo(b.$1.age) : a.$1.gameNo.compareTo(b.$1.gameNo),
                '日付' => dateKey(a.$1).compareTo(dateKey(b.$1)),
                _ => a.$1.gameNo.compareTo(b.$1.gameNo),
              });
          rows.add(Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
            child: Text('通算$mark${mk.label}の達成者 ${hits.length}人', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
          ));
          for (var i = 0; i < hits.length; i++) {
            final h = hits[i].$1;
            final when = h.date != null ? '${h.date!.year}/${h.date!.month}/${h.date!.day}' : (h.year > 0 ? '${h.year}年（推定）' : 'ゲーム開始前');
            rows.add(_row(i + 1, h.p, hits[i].$2, '${h.gameNo}${batter ? '試合目' : '登板目'}', '$when・${h.age}歳'));
          }
          if (hits.isEmpty) rows.add(const Padding(padding: EdgeInsets.all(16), child: Text('条件に合う選手はいません', style: TextStyle(color: _sub))));
        } else {
          final list = <(StreakHit, Team?)>[];
          final minLen = sk.unit == '回' ? 27 : (sk.label == '連続試合出場' ? 50 : (sk.label == '連続試合本塁打' ? 3 : 8));
          for (final (p, t) in _players) {
            if (p.isPitcher == batter && !(batter && p.twoWay)) continue;
            if (!_handOk(p, batter)) continue;
            for (final s in RecordQuery.streaks(p, sk, logs[p.id] ?? const [], teamGames, minLen)) {
              list.add((s, t));
            }
          }
          list.sort((a, b) => b.$1.len.compareTo(a.$1.len));
          String n(int v) => sk.unit == '回' ? '${v ~/ 3}${v % 3 > 0 ? ' ${v % 3}/3' : ''}回' : '$v${sk.unit}';
          String d(DateTime x) => '${x.year}/${x.month}/${x.day}';
          rows.add(Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
            child: Text('${sk.label}（${n(minLen)}以上）${list.length}件', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
          ));
          for (var i = 0; i < list.length && i < 100; i++) {
            final s = list[i].$1;
            rows.add(_row(i + 1, s.p, list[i].$2, n(s.len), '${d(s.start)}〜${s.active ? '継続中' : d(s.end)}'));
          }
          if (list.isEmpty) rows.add(const Padding(padding: EdgeInsets.all(16), child: Text('条件に合う記録はありません', style: TextStyle(color: _sub))));
          rows.add(const Padding(padding: EdgeInsets.all(10), child: Text('連続記録はゲームの中の公式戦から数えます（ゲーム開始前の分は含みません）', style: TextStyle(fontSize: 10.5, color: _sub))));
        }
        return Column(children: [
          filters,
          const Divider(height: 1),
          Expanded(child: ListView(padding: const EdgeInsets.only(bottom: 20), children: rows)),
        ]);
      },
    );
  }

  Widget _row(int rank, Player p, Team? t, String main, String sub) => InkWell(
        onTap: () => showPlayerDetail(context, app, p, allowActions: false),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _line))),
          child: Row(children: [
            SizedBox(width: 28, child: Text('$rank', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14))),
            PlayerAvatar(p, size: 28),
            const SizedBox(width: 6),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${p.listName}${t == null ? '（FA）' : '（${teamShort(t)}）'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _ink)),
                Text(sub, style: const TextStyle(fontSize: 11, color: _sub)),
              ]),
            ),
            Text(main, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
          ]),
        ),
      );
}

/// 記録タブ「歴代表彰」：ゲーム開始前は架空の歴史（今いる選手が取った年は名前の横に印）、ゲームの中は実際の表彰
class HistoryAwardsView extends StatefulWidget {
  final AppState app;
  const HistoryAwardsView({super.key, required this.app});

  @override
  State<HistoryAwardsView> createState() => _HistoryAwardsViewState();
}

class _HistoryAwardsViewState extends State<HistoryAwardsView> {
  int? _year;
  late final Future<void> _ready = widget.app.preCareers();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _ready,
      builder: (context, snap) {
        final h = widget.app.leagueHistory;
        if (snap.connectionState != ConnectionState.done || h == null) return const Center(child: CircularProgressIndicator());
        final years = h.years.keys.toList()..sort((a, b) => b.compareTo(a));
        if (years.isEmpty) return const Center(child: Text('ゲーム開始前の歴史はありません', style: TextStyle(color: _sub)));
        final y = _year ?? years.first;
        final data = h.years[y] ?? const {};
        return Column(children: [
          YearStepper(years: years, selected: y, onSelect: (x) => setState(() => _year = x)),
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(10, 0, 10, 20), children: [
              for (final lg in [...data.keys.where((k) => k != '両リーグ'), if (data.containsKey('両リーグ')) '両リーグ'])
                ...[
                  Padding(padding: const EdgeInsets.only(top: 10, bottom: 4), child: Text('$y年 ${lg == '両リーグ' ? '両リーグ' : leagueLabel(lg)}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14))),
                  for (final e in data[lg]!.entries)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _line))),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        SizedBox(width: 150, child: Text(e.key, style: const TextStyle(fontSize: 11.5, color: _sub))),
                        Expanded(
                          child: Text(e.value.text,
                              style: TextStyle(fontSize: 12, fontWeight: e.value.playerId != null ? FontWeight.w800 : FontWeight.w400, color: e.value.playerId != null ? const Color(0xFF1D4ED8) : _ink)),
                        ),
                      ]),
                    ),
                ],
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text('ゲーム開始前の表彰は架空の歴史です。青字は今いる選手（推定の成績が、その年の受賞者を上回った年）', style: TextStyle(fontSize: 10.5, color: _sub)),
              ),
            ]),
          ),
        ]);
      },
    );
  }
}
