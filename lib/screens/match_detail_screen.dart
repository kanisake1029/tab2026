import 'package:flutter/material.dart';
import '../models/team.dart';
import '../utils/schedule_generator.dart';
import '../widgets/player_detail_dialog.dart' show showPlayerDetail;
import '../db/app_database.dart' show PitchRow;
import 'replay_screen.dart';
import '../engine/game_summary.dart';
import '../utils/standings.dart' show teamColor;
import '../widgets/game_news_card.dart';
import '../widgets/game_painters.dart' show kStrikeColor, kBallColor, kOutColor, kHitColor;

/// 過去の試合（デザイン案A「新聞のボックススコア」と案B「一球速報」を切り替え）
///  ・上のスコアボードのイニングのセルを押すと、その回の一球速報（案B）を開く
///  ・ボックススコア：打撃成績（打席ごとの結果つき）・投手成績・本塁打・先発
///  ・一球速報：左でイニング、中央で打席ごとの1球、右で選んだ打席の全文
///  試合の記録（1打席ごとの文章）から、イニング・打席・1球に分けて表示する
class MatchDetailScreen extends StatefulWidget {
  final Match match;
  final Team home;
  final Team away;
  final bool farm; // 2軍の試合（1球ごとの記録は無く、試合結果と個人成績だけ）
  final dynamic appState; // 選手名をタップして詳細を開くため
  const MatchDetailScreen({super.key, required this.match, required this.home, required this.away, this.farm = false, this.appState});

  @override
  State<MatchDetailScreen> createState() => _MatchDetailScreenState();
}

const _navy = Color(0xFF0B1626);
const _navy2 = Color(0xFF12233B);
const _lime = Color(0xFFC6F24E);
const _muted = Color(0xFF8EA3BF);
const _bg = Color(0xFFEEF1F5);

// ───────── 記録の読み取り ─────────

enum _Kind { strike, ball, out, hit, other }

class _PitchLine {
  final String text;
  final int no;
  final String kind; // 球種
  final int speed;
  final String result; // 結果の文章
  final _Kind cls;
  _PitchLine(this.text, this.no, this.kind, this.speed, this.result, this.cls);
}

class _Pa {
  final String pitcher;
  final bool relief;
  final int slot;
  final String batter;
  final List<Object> lines = []; // _PitchLine か String（盗塁などの出来事）
  _Pa(this.pitcher, this.relief, this.slot, this.batter);

  List<_PitchLine> get pitches => lines.whereType<_PitchLine>().toList();

  String get situation {
    final ps = pitches;
    if (ps.isEmpty) return '';
    final m = RegExp(r'\[(.+?)\]').firstMatch(ps.first.text);
    return m == null ? '' : m.group(1)!;
  }

  /// 打席の結果（短い表記）と色
  (String, _Kind) get summary {
    final ps = pitches;
    final last = ps.isEmpty ? null : ps.last;
    final notes = lines.whereType<String>().toList();
    if (last != null) {
      final r = last.result;
      if (r.contains('三振') || r.contains('スリーバント失敗')) return ('三振', _Kind.out);
      if (r.contains('四球') || r.contains('押し出し')) return ('四球', _Kind.ball);
      if (r.contains('死球')) return ('死球', _Kind.ball);
      if (r.contains('打撃（') && !r.startsWith('打撃（ファウル）')) return _inPlay(r);
    }
    for (final n in notes.reversed) {
      if (n.contains('スクイズ')) return ('スクイズ', n.contains('失敗') ? _Kind.out : _Kind.hit);
      if (n.contains('バント')) return ('犠打', _Kind.out);
    }
    if (last != null && last.result.contains('アウト')) return ('アウト', _Kind.out);
    return ('', _Kind.other);
  }

  static const _role = {'P': '投', 'C': '捕', '1B': '一', '2B': '二', '3B': '三', 'SS': '遊', 'LF': '左', 'CF': '中', 'RF': '右'};

  static (String, _Kind) _inPlay(String r) {
    final def = r.contains('守備: ') ? r.substring(r.indexOf('守備: ') + 4) : '';
    String pos = '';
    final roles = _role.entries.toList()..sort((a, b) => b.key.length.compareTo(a.key.length)); // CF を C（捕）と取り違えないよう、長い記号から調べる
    for (final e in roles) {
      if (def.startsWith(e.key)) {
        pos = e.value;
        break;
      }
    }
    if (pos.isEmpty) {
      final dir = RegExp(r'打撃（(\S+)').firstMatch(r)?.group(1) ?? '';
      if (dir.contains('レフト') || dir.contains('左')) {
        pos = '左';
      } else if (dir.contains('ライト') || dir.contains('右')) {
        pos = '右';
      } else if (dir.contains('センター') || dir.contains('中')) {
        pos = '中';
      }
    }
    if (r.contains('ホームラン')) return ('$pos本', _Kind.hit);
    if (r.contains('スリーベース') || r.contains('三塁打')) return ('$pos三', _Kind.hit);
    if (r.contains('ツーベース') || r.contains('二塁打')) return ('$pos二', _Kind.hit);
    if (r.contains('ヒット') || r.contains('安打')) return ('$pos安', _Kind.hit);
    if (r.contains('エラー') || r.contains('悪送球')) return ('$pos失', _Kind.hit);
    if (r.contains('犠牲フライ')) return ('$pos犠飛', _Kind.out);
    if (r.contains('ダブルプレー') || r.contains('併殺')) return ('$pos併', _Kind.out);
    if (r.contains('ゴロ')) return ('$posゴ', _Kind.out);
    if (r.contains('ライナー')) return ('$pos直', _Kind.out);
    if (r.contains('フライ')) return ('$pos飛', _Kind.out);
    return ('$posアウト', _Kind.out);
  }
}

class _Half {
  final int inning;
  final bool top;
  final List<_Pa> pas = [];
  final List<String> notes = [];
  _Half(this.inning, this.top);
  String get label => '$inning回${top ? '表' : '裏'}';
}

_Kind _classify(String result) {
  if (result.contains('打撃（') && !result.startsWith('打撃（ファウル）')) {
    final (_, k) = _Pa._inPlay(result);
    return k;
  }
  if (result.contains('三振') || result.contains('スリーバント失敗') || result.contains('(アウト)') || result.contains('アウト')) return _Kind.out;
  if (result.contains('ボール') || result.contains('四球') || result.contains('死球') || result.contains('押し出し')) return _Kind.ball;
  if (result.contains('見逃し') || result.contains('空振り') || result.contains('ファウル')) return _Kind.strike;
  return _Kind.other;
}

List<_Half> _parse(List<String> log) {
  final halves = <_Half>[];
  final head = RegExp(r'^【(\d+)回(表|裏)');
  // 登録名には空白が入ることがある（例「清水 和也」）
  final pa = RegExp(r'^(.+?) (先発|救援) (.+?) vs (.+) (\d+)番 (.+)$');
  final pitch = RegExp(r'^(\d+)球目 (\d+)km/h (\S+)');
  _Pa? cur;
  for (final line in log) {
    final h = head.firstMatch(line);
    if (h != null) {
      halves.add(_Half(int.parse(h.group(1)!), h.group(2) == '表'));
      cur = null;
      continue;
    }
    if (halves.isEmpty) halves.add(_Half(1, true));
    final p = pa.firstMatch(line);
    if (p != null) {
      cur = _Pa(p.group(3)!, p.group(2) == '救援', int.parse(p.group(5)!), p.group(6)!);
      halves.last.pas.add(cur);
      continue;
    }
    final q = pitch.firstMatch(line);
    if (q != null) {
      final idx = line.indexOf('　');
      var result = idx >= 0 ? line.substring(idx + 1) : '';
      final b = result.lastIndexOf(' [');
      if (b >= 0) result = result.substring(0, b);
      final pl = _PitchLine(line, int.parse(q.group(1)!), q.group(3)!, int.parse(q.group(2)!), result.trim(), _classify(result));
      if (cur != null) {
        cur.lines.add(pl);
      } else {
        halves.last.notes.add(line);
      }
      continue;
    }
    if (cur != null) {
      cur.lines.add(line);
    } else {
      halves.last.notes.add(line);
    }
  }
  return halves;
}

Color _kindColor(_Kind k) => switch (k) {
      _Kind.strike => kStrikeColor,
      _Kind.ball => kBallColor,
      _Kind.out => kOutColor,
      _Kind.hit => kHitColor,
      _Kind.other => const Color(0xFF94A3B8),
    };

// ───────── 画面 ─────────

class _MatchDetailScreenState extends State<MatchDetailScreen> {
  late final List<_Half> _halves = _parse(widget.match.playByPlay ?? const []);
  bool _pitchView = false; // false=ボックススコア / true=一球速報
  int _half = 0;
  int _pa = -1;
  bool _pitStats = false; // 成績のタブ：false=野手 / true=投手
  /// 投手ごとの球数（実況の1球ずつの記録から数える。以前の試合にも出る）。ボックススコアに球数があればそちら
  /// 投手ごとの対戦打者・被安打・被本塁打・死球と、回の途中で降板したか（実況から数える）
  late final Map<String, ({int bf, int h, int hr, int hbp})> _pitStat = () {
    final out = <String, ({int bf, int h, int hr, int hbp})>{};
    for (final half in _halves) {
      for (final p in half.pas) {
        final s = p.summary.$1;
        if (s.isEmpty) continue;
        final c = out[p.pitcher] ?? (bf: 0, h: 0, hr: 0, hbp: 0);
        final hit = s.endsWith('安') || s.endsWith('二') || s.endsWith('三') || s.endsWith('本');
        out[p.pitcher] = (bf: c.bf + 1, h: c.h + (hit ? 1 : 0), hr: c.hr + (s.endsWith('本') ? 1 : 0), hbp: c.hbp + (s == '死球' ? 1 : 0));
      }
    }
    return out;
  }();

  /// 回の途中で降板した投手（最後に投げた回で、あとに別の投手が投げている）
  late final Set<String> _midExit = () {
    final last = <String, int>{};
    for (var i = 0; i < _halves.length; i++) {
      for (final p in _halves[i].pas) {
        last[p.pitcher] = i;
      }
    }
    final out = <String>{};
    last.forEach((name, i) {
      final pas = _halves[i].pas;
      final j = pas.lastIndexWhere((p) => p.pitcher == name);
      if (pas.skip(j + 1).any((p) => p.pitcher != name)) out.add(name);
    });
    return out;
  }();

  late final Map<String, int> _pitchCount = () {
    final out = <String, int>{};
    for (final h in _halves) {
      for (final p in h.pas) {
        out[p.pitcher] = (out[p.pitcher] ?? 0) + p.pitches.length;
      }
    }
    return out;
  }();

  Match get m => widget.match;
  String _short(Team t) => t.shortName.isNotEmpty ? t.shortName : t.name;

  void _openHalf(int inning, bool top) {
    final i = _halves.indexWhere((h) => h.inning == inning && h.top == top);
    if (i < 0) return;
    setState(() {
      _pitchView = true;
      _half = i;
      _pa = -1;
    });
  }

  /// 打者ごとの打席結果（ボックススコア用）
  Map<String, List<(String, _Kind)>> _resultsBy(bool top) {
    final map = <String, List<(String, _Kind)>>{};
    for (final h in _halves.where((h) => h.top == top)) {
      for (final p in h.pas) {
        final s = p.summary;
        if (s.$1.isEmpty) continue;
        map.putIfAbsent(p.batter, () => []).add(s);
      }
    }
    return map;
  }

  Future<void> _openReplay() async {
    final app = widget.appState;
    final idx = (app.matches as List).indexOf(m);
    final rows = await app.db.loadPitches(app.startYear as int, idx) as List<PitchRow>;
    if (!mounted) return;
    if (rows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('この試合の1球ごとの記録はありません（記録しているのは今季の自球団の試合です）')));
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReplayScreen(rows: rows, title: '${_short(widget.away)} vs ${_short(widget.home)} を振り返る')));
  }

  @override
  Widget build(BuildContext context) {
    const dows = ['月', '火', '水', '木', '金', '土', '日'];
    final type = const {'OPEN': 'オープン戦', 'LEAGUE': '公式戦', 'INTERLEAGUE': '交流戦', 'ALLSTAR': 'オールスター', 'CS': 'クライマックスシリーズ', 'JS': '日本シリーズ'}[m.matchType] ?? m.matchType;
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 8,
        title: Text('${m.date.month}/${m.date.day}（${dows[m.date.weekday - 1]}）${widget.farm ? '2軍・' : ''}$type　${_short(widget.away)} ${m.awayScore} − ${m.homeScore} ${_short(widget.home)}',
            overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
        actions: [
          // 今季の自球団の試合は、1球ごとの記録からアニメで振り返れる
          if (!widget.farm && widget.appState != null && (widget.appState.matches as List).contains(m))
            IconButton(tooltip: 'アニメで振り返る', icon: const Icon(Icons.movie_outlined), onPressed: _openReplay),
        ],
      ),
      body: LayoutBuilder(builder: (context, c) {
        final wide = c.maxWidth >= 1000;
        final pad = wide ? 20.0 : 10.0;
        final toggle = SegmentedButton<bool>(
          segments: const [ButtonSegment(value: false, label: Text('ボックススコア')), ButtonSegment(value: true, label: Text('一球速報'))],
          selected: {_pitchView},
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(selectedBackgroundColor: _navy, selectedForegroundColor: _lime, backgroundColor: Colors.white, visualDensity: VisualDensity.compact),
          onSelectionChanged: (v) => setState(() => _pitchView = v.first),
        );
        final top = Padding(
          padding: EdgeInsets.fromLTRB(pad, 12, pad, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _scoreboard(),
            const SizedBox(height: 8),
            if (widget.farm)
              const Text('2軍の試合：試合結果と個人成績を表示（1球速報はありません）', style: TextStyle(fontSize: 12, color: Color(0xFF64748B)))
            else
              Row(children: [toggle, const SizedBox(width: 8), const Expanded(child: Text('回を押すとその回の一球速報', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))))]),
          ]),
        );
        if (!_pitchView || widget.farm) {
          final app = widget.appState;
          return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
            top,
            if (m.boxScore != null) Padding(padding: EdgeInsets.fromLTRB(pad, 0, pad, 10), child: _resultTable()),
            Padding(padding: EdgeInsets.symmetric(horizontal: pad), child: _statTabs(wide)),
            if (!widget.farm && m.homeScore != null)
              Padding(
                padding: EdgeInsets.fromLTRB(pad, 12, pad, 0),
                child: GameNewsCard(match: m, home: widget.home, away: widget.away, teams: app == null ? [widget.home, widget.away] : List<Team>.from(app.teams as List), myTeamId: app?.myTeamId as String?, app: app),
              ),
          ]);
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          top,
          Expanded(child: Padding(padding: EdgeInsets.fromLTRB(pad, 0, pad, pad), child: _pitchByPitch(wide))),
        ]);
      }),
    );
  }

  // ───────── スコアボード（セルを押すとその回へ） ─────────

  Widget _scoreboard() {
    final n = [9, m.homeInningScores?.length ?? 0, m.awayInningScores?.length ?? 0].reduce((a, b) => a > b ? a : b);
    final sel = _pitchView && _half < _halves.length ? _halves[_half] : null;
    return LayoutBuilder(builder: (context, c) {
    // 幅に収める：チーム名 52・計/H/E・回のマスを等分
    final cw = ((c.maxWidth - 16 - 54 - 4 - 3 * 28) / n - 2).clamp(14.0, 30.0);
    final fs = cw < 20 ? 12.0 : 15.0;
    Widget cell(String t, {bool head = false, bool hi = false, VoidCallback? onTap, Color? color, double? w}) {
      w ??= cw;
      final box = Container(
        width: w,
        height: head ? 18 : 28,
        alignment: Alignment.center,
        margin: const EdgeInsets.all(1),
        decoration: head
            ? null
            : BoxDecoration(color: hi ? const Color(0xFF18324F) : _navy2, borderRadius: BorderRadius.circular(3), border: hi ? Border.all(color: _lime, width: 1.5) : null),
        child: Text(t, style: TextStyle(color: color ?? (head ? _muted : Colors.white), fontSize: head ? 10.5 : fs, fontWeight: FontWeight.w700, fontFeatures: const [FontFeature.tabularFigures()])),
      );
      if (onTap == null) return box;
      return MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(onTap: onTap, child: box));
    }

    Widget row(String name, List<int>? s, int? r, int? h, int? e, bool top) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 52,
            height: 28,
            margin: const EdgeInsets.all(1),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(color: _navy2, borderRadius: BorderRadius.circular(3)),
            child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(name, maxLines: 1, style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700))),
          ),
          for (int i = 0; i < n; i++)
            () {
              final has = s != null && i < s.length;
              final txt = has ? '${s[i]}' : (!top && i < n ? 'x' : '');
              final exists = _halves.any((x) => x.inning == i + 1 && x.top == top);
              return cell(txt, hi: sel != null && sel.inning == i + 1 && sel.top == top, onTap: exists ? () => _openHalf(i + 1, top) : null);
            }(),
          const SizedBox(width: 4),
          cell('${r ?? 0}', color: _lime, w: 26),
          cell('${h ?? 0}', w: 26),
          cell(e == null ? '-' : '$e', w: 26),
        ]);

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: _navy, borderRadius: BorderRadius.circular(12)),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(width: 54),
          for (int i = 1; i <= n; i++) cell('$i', head: true),
          const SizedBox(width: 4),
          cell('計', head: true, w: 26),
          cell('H', head: true, w: 26),
          cell('E', head: true, w: 26),
        ]),
        row(_short(widget.away), m.awayInningScores, m.awayScore, m.awayHits, m.boxScore?['awayE'] as int?, true),
        row(_short(widget.home), m.homeInningScores, m.homeScore, m.homeHits, m.boxScore?['homeE'] as int?, false),
      ]),
    );
    });
  }

  // ───────── 結果の表（勝敗・セーブ・本塁打。ビジターとホームに列を分ける） ─────────

  Widget _resultTable() {
    final box = m.boxScore!;
    final teams = widget.appState == null ? [widget.home, widget.away] : List<Team>.from(widget.appState.teams as List);
    (Team, String)? dec(String d) {
      for (final (key, t) in [('awayPitcher', widget.away), ('homePitcher', widget.home)]) {
        final ps = box[key];
        if (ps is! Map) continue;
        for (final e in ps.entries) {
          if (e.value is Map && (e.value as Map)['dec'] == d) return (t, '${e.key}');
        }
      }
      return null;
    }

    // 本塁打：ビジターを打った順、その下にホームを打った順
    final hrs = <(Team, String)>[];
    if (widget.farm) {
      for (final (key, t) in [('awayBatters', widget.away), ('homeBatters', widget.home)]) {
        final bs = box[key];
        if (bs is Map) {
          bs.forEach((k, v) {
            final n = (v is Map ? v['hr'] : 0) ?? 0;
            if (n is int && n > 0) hrs.add((t, n > 1 ? '$k（${n}本）' : '$k'));
          });
        }
      }
    } else {
      final all = GameSummary.homeRuns(m, widget.home, widget.away);
      for (final homeSide in [false, true]) {
        for (final h in all.where((h) => h.$1 == homeSide)) {
          hrs.add((homeSide ? widget.home : widget.away, '${h.$2}（${h.$3}）'));
        }
      }
    }
    const lbl = TextStyle(fontSize: 11.5, color: Color(0xFF64748B), fontWeight: FontWeight.w700);
    const val = TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Color(0xFF0F172A));
    Widget line(String label, Team? t, String text, {bool first = true}) => Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(border: first ? const Border(top: BorderSide(color: Color(0xFFE2E8F0))) : null),
          child: Row(children: [
            SizedBox(width: 64, child: Text(first ? label : '', style: lbl)),
            if (t != null) ...[
              Container(width: 4, height: 16, decoration: BoxDecoration(color: teamColor(teams, t), borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 6),
            ],
            Expanded(child: Text(text, style: val)),
            if (t != null) Text(_short(t), style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
          ]),
        );
    final rows = <Widget>[];
    for (final (d, label) in const [('勝', '勝利投手'), ('敗', '敗戦投手'), ('S', 'セーブ')]) {
      final x = dec(d);
      if (x != null) rows.add(line(label, x.$1, x.$2));
    }
    if (hrs.isEmpty) {
      rows.add(line('本塁打', null, 'なし'));
    } else {
      for (var i = 0; i < hrs.length; i++) {
        rows.add(line('本塁打', hrs[i].$1, hrs[i].$2, first: i == 0));
      }
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows),
    );
  }

  // ───────── 野手成績・投手成績（タブ。ビジター→ホームの順） ─────────

  Widget _statTabs(bool wide) {
    final box = m.boxScore;
    if (box == null) return const Padding(padding: EdgeInsets.all(20), child: Text('成績データがありません'));
    Widget tab(bool v, String label) => Expanded(
          child: InkWell(
            onTap: () => setState(() => _pitStats = v),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 9),
              alignment: Alignment.center,
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: _pitStats == v ? _navy : const Color(0xFFE2E8F0), width: _pitStats == v ? 3 : 1))),
              child: Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: _pitStats == v ? _navy : const Color(0xFF94A3B8))),
            ),
          ),
        );
    final teams = [
      (widget.away, box['awayBatters'], box['awayPitcher'], _resultsBy(true)),
      (widget.home, box['homeBatters'], box['homePitcher'], _resultsBy(false)),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [tab(false, '野手成績'), tab(true, '投手成績')]),
        const SizedBox(height: 8),
        for (final (t, bats, pits, res) in teams) ...[
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 4),
            child: Text('${t.name}${t == widget.away ? '（ビジター）' : '（ホーム）'}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
          ),
          if (_pitStats) _pitTable(t, pits) else _batTable(t, bats, res),
          const SizedBox(height: 10),
        ],
      ]),
    );
  }

  Widget _batTable(Team t, dynamic batters, Map<String, List<(String, _Kind)>> results) {
    const head = TextStyle(fontSize: 11, color: Color(0xFF6B7280));
    const num = TextStyle(fontSize: 13, fontFeatures: [FontFeature.tabularFigures()]);
    Widget hcell(String s) => SizedBox(width: 22, child: Text(s, textAlign: TextAlign.right, style: head));
    Widget ncell(Object? v) => SizedBox(width: 22, child: Text('${v ?? 0}', textAlign: TextAlign.right, style: num));
    final rows = <Widget>[
      Container(
        padding: const EdgeInsets.only(bottom: 3),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFF111827)))),
        child: Row(children: [const Expanded(child: Text('選手', style: head)), hcell('打'), hcell('安'), hcell('本'), hcell('点'), hcell('四'), hcell('振')]),
      ),
    ];
    if (batters is Map) {
      batters.forEach((name, v) {
        final r = results[name] ?? const [];
        rows.add(Container(
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF3F4F6)))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: _nameTap(t, '$name', Text('$name', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)))),
              ncell(v['ab']), ncell(v['h']), ncell(v['hr']), ncell(v['rbi']), ncell(v['bb']), ncell(v['so']),
            ]),
            if (r.isNotEmpty)
              Wrap(spacing: 5, runSpacing: 1, children: [
                for (final x in r)
                  Text(x.$1, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: x.$2 == _Kind.hit ? const Color(0xFF1D4ED8) : (x.$2 == _Kind.ball ? const Color(0xFF15803D) : const Color(0xFF6B7280)))),
              ]),
          ]),
        ));
      });
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
  }

  /// 投球回：回の途中で降板したら、アウトを取れていなくても「7.0」のように書く（8回途中で降板と分かるように）
  String _ipText(String name, Object? ip) {
    final t = '${ip ?? 0}';
    return _midExit.contains(name) && !t.contains('.') ? '$t.0' : t;
  }

  /// 投手成績：いちばん左に勝・敗・H・S
  Widget _pitTable(Team t, dynamic pitchers) {
    const head = TextStyle(fontSize: 11, color: Color(0xFF6B7280));
    const num = TextStyle(fontSize: 13, fontFeatures: [FontFeature.tabularFigures()]);
    Widget hcell(String s, double w) => SizedBox(width: w, child: Text(s, textAlign: TextAlign.right, style: head));
    Widget ncell(Object? v, double w) => SizedBox(width: w, child: Text('${v ?? 0}', textAlign: TextAlign.right, style: num));
    const decColor = {'勝': Color(0xFFDC2626), '敗': Color(0xFF2563EB), 'S': Color(0xFF7C3AED), 'H': Color(0xFF15803D)};
    final rows = <Widget>[
      Container(
        padding: const EdgeInsets.only(bottom: 3),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFF111827)))),
        child: Row(children: [
          const SizedBox(width: 26, child: Text('', style: head)),
          const Expanded(child: Text('投手', style: head)),
          hcell('回', 30), hcell('打者', 26), hcell('球', 28), hcell('安', 20), hcell('本', 20), hcell('振', 20), hcell('四', 20), hcell('死', 20), hcell('責', 20),
        ]),
      ),
    ];
    if (pitchers is Map) {
      pitchers.forEach((name, v) {
        final d = v is Map ? v['dec'] as String? : null;
        rows.add(Container(
          padding: const EdgeInsets.symmetric(vertical: 5),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF3F4F6)))),
          child: Row(children: [
            SizedBox(
              width: 26,
              child: d == null
                  ? const SizedBox()
                  : Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: 20,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: decColor[d] ?? const Color(0xFF64748B), borderRadius: BorderRadius.circular(3)),
                        child: Text(d, style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w900)),
                      ),
                    ),
            ),
            Expanded(child: _nameTap(t, '$name', Text('$name', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)))),
            ncell(_ipText('$name', v['ip']), 30),
            ncell(_pitStat['$name']?.bf ?? '-', 26),
            ncell(v['np'] ?? _pitchCount['$name'] ?? '-', 28),
            ncell(_pitStat['$name']?.h ?? '-', 20),
            ncell(_pitStat['$name']?.hr ?? '-', 20),
            ncell(v['so'], 20),
            ncell(v['bb'], 20),
            ncell(_pitStat['$name']?.hbp ?? '-', 20),
            ncell(v['er'], 20),
          ]),
        ));
      });
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
  }

  /// 選手名をタップで詳細（ボックススコアは登録名なので、球団の選手から探す）
  Widget _nameTap(Team t, String name, Widget child) {
    if (widget.appState == null) return child;
    final p = t.players.where((x) => x.registeredName == name).firstOrNull;
    if (p == null) return child;
    return InkWell(onTap: () => showPlayerDetail(context, widget.appState, p, allowActions: false), child: child);
  }

  // ───────── 案B：一球速報 ─────────

  Widget _pitchByPitch(bool wide) {
    if (_halves.isEmpty) return const Center(child: Text('一球ごとの記録がありません'));
    final half = _halves[_half.clamp(0, _halves.length - 1)];
    final runs = half.top ? m.awayInningScores : m.homeInningScores;
    final r = runs != null && half.inning - 1 < runs.length ? runs[half.inning - 1] : null;
    final offense = half.top ? widget.away : widget.home;

    final list = ListView(children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text.rich(TextSpan(children: [
          TextSpan(text: '${half.label}　${_short(offense)}の攻撃', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
          if (r != null) TextSpan(text: '　$r点', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: r > 0 ? const Color(0xFFDC2626) : const Color(0xFF64748B))),
        ])),
      ),
      for (final n in half.notes) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(n, style: const TextStyle(fontSize: 12.5, color: Color(0xFF475569)))),
      for (int i = 0; i < half.pas.length; i++) _paCard(half.pas[i], i, wide),
    ]);

    final innings = wide
        ? SizedBox(
            width: 112,
            child: Container(
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
              child: ListView(padding: const EdgeInsets.all(6), children: [for (int i = 0; i < _halves.length; i++) _halfTile(i)]),
            ),
          )
        : _halfGrid(); // スマホ：表・裏の2段に、回ごとに並べる（横にすべらせない）

    final detail = _paDetail(half);
    if (wide) {
      return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        innings,
        const SizedBox(width: 12),
        Expanded(child: list),
        const SizedBox(width: 12),
        SizedBox(width: 330, child: detail),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      innings,
      const SizedBox(height: 8),
      Expanded(child: list),
    ]);
  }

  /// 表・裏の2段 × 回の表（スコアボードと同じ並び）
  Widget _halfGrid() {
    final n = _halves.fold<int>(9, (a, h) => h.inning > a ? h.inning : a);
    Widget line(bool top) => Row(children: [
          SizedBox(width: 22, child: Text(top ? '表' : '裏', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF64748B)))),
          for (var inn = 1; inn <= n; inn++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(1.5),
                child: Builder(builder: (_) {
                  final i = _halves.indexWhere((h) => h.inning == inn && h.top == top);
                  if (i < 0) return const SizedBox(height: 30);
                  final runs = top ? m.awayInningScores : m.homeInningScores;
                  final r = runs != null && inn - 1 < runs.length ? runs[inn - 1] : 0;
                  final sel = i == _half;
                  return InkWell(
                    onTap: () => setState(() {
                      _half = i;
                      _pa = -1;
                    }),
                    child: Container(
                      height: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: sel ? _navy : Colors.white, borderRadius: BorderRadius.circular(5), border: Border.all(color: const Color(0xFFE2E8F0))),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Text('$inn', style: TextStyle(fontSize: 11.5, height: 1.1, fontWeight: FontWeight.w800, color: sel ? Colors.white : const Color(0xFF0F172A))),
                        if (r > 0) Text('$r点', style: TextStyle(fontSize: 9, height: 1.1, fontWeight: FontWeight.w800, color: sel ? const Color(0xFFFCA5A5) : const Color(0xFFDC2626))),
                      ]),
                    ),
                  );
                }),
              ),
            ),
        ]);
    return Column(mainAxisSize: MainAxisSize.min, children: [line(true), line(false)]);
  }

  Widget _halfTile(int i, {bool compact = false}) {
    final h = _halves[i];
    final runs = h.top ? m.awayInningScores : m.homeInningScores;
    final r = runs != null && h.inning - 1 < runs.length ? runs[h.inning - 1] : 0;
    final sel = i == _half;
    return Material(
      color: sel ? _navy : (compact ? Colors.white : Colors.transparent),
      borderRadius: BorderRadius.circular(7),
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: () => setState(() {
          _half = i;
          _pa = -1;
        }),
        child: Container(
          height: compact ? 40 : 30,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          alignment: Alignment.center,
          child: Row(mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max, children: [
            Text(h.label, style: TextStyle(fontSize: 12.5, color: sel ? _lime : const Color(0xFF0F172A), fontWeight: sel ? FontWeight.w800 : FontWeight.w500)),
            if (!compact) const Spacer() else const SizedBox(width: 6),
            if (r > 0) Text('$r', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: sel ? _lime : const Color(0xFFDC2626))),
          ]),
        ),
      ),
    );
  }

  Widget _paCard(_Pa p, int i, bool wide) {
    final (res, kind) = p.summary;
    final sel = i == _pa;
    final chips = <Widget>[];
    for (final x in p.lines) {
      if (x is _PitchLine) {
        final c = _kindColor(x.cls);
        final dark = x.cls == _Kind.strike || x.cls == _Kind.ball;
        final shortRes = x.result.startsWith('打撃（') && !x.result.startsWith('打撃（ファウル）') ? '打球' : x.result.split(' ').first;
        chips.add(Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(color: c.withValues(alpha: dark ? 0.85 : 0.9), borderRadius: BorderRadius.circular(6)),
          child: Text('${x.no} ${x.kind} ${x.speed} $shortRes', style: TextStyle(fontSize: 11.5, color: dark ? const Color(0xFF0B1626) : Colors.white, fontWeight: FontWeight.w600)),
        ));
      } else if (x is String) {
        chips.add(Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(6), border: Border.all(color: const Color(0xFFE2E8F0))),
          child: Text(x, style: const TextStyle(fontSize: 11.5, color: Color(0xFF475569))),
        ));
      }
    }
    final info = SizedBox(
      width: wide ? 200 : double.infinity,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${p.slot}番　投手 ${p.pitcher}${p.relief ? '（救援）' : ''}', style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
        Text(p.batter, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
        if (res.isNotEmpty) Text(res, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: kind == _Kind.hit ? const Color(0xFF1D4ED8) : (kind == _Kind.ball ? const Color(0xFF15803D) : const Color(0xFFB91C1C)))),
        if (p.situation.isNotEmpty) Text(p.situation, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
      ]),
    );
    final content = wide
        ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [info, const SizedBox(width: 12), Expanded(child: Wrap(spacing: 4, runSpacing: 4, children: chips))])
        : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [info, const SizedBox(height: 6), Wrap(spacing: 4, runSpacing: 4, children: chips)]);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: sel ? _navy : const Color(0xFFE2E8F0), width: sel ? 2 : 1)),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            setState(() => _pa = i);
            if (!wide) _showPaSheet(p);
          },
          child: Padding(padding: const EdgeInsets.all(12), child: content),
        ),
      ),
    );
  }

  /// 選んだ打席の全文（1球ずつの説明）
  Widget _paDetail(_Half half) {
    final p = _pa >= 0 && _pa < half.pas.length ? half.pas[_pa] : null;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: p == null
          ? const Center(child: Text('打席を選ぶと、1球ずつの詳しい内容を表示します', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF64748B))))
          : _paDetailBody(p),
    );
  }

  Widget _paDetailBody(_Pa p) {
    final (res, _) = p.summary;
    return ListView(children: [
      Text('${p.batter}　vs　${p.pitcher}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
      Text('${p.pitches.length}球${res.isNotEmpty ? '　$res' : ''}', style: const TextStyle(fontSize: 12.5, color: Color(0xFF475569))),
      const SizedBox(height: 10),
      for (final x in p.lines)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 20,
              height: 20,
              margin: const EdgeInsets.only(right: 8, top: 1),
              alignment: Alignment.center,
              decoration: BoxDecoration(shape: BoxShape.circle, color: x is _PitchLine ? _kindColor(x.cls) : const Color(0xFFE2E8F0)),
              child: Text(x is _PitchLine ? '${x.no}' : '・', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Color(0xFF0B1626))),
            ),
            Expanded(child: Text(x is _PitchLine ? x.text : '$x', style: const TextStyle(fontSize: 12.5, height: 1.5))),
          ]),
        ),
    ]);
  }

  void _showPaSheet(_Pa p) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (c) => SizedBox(height: MediaQuery.of(c).size.height * 0.6, child: Padding(padding: const EdgeInsets.all(16), child: _paDetailBody(p))),
    );
  }
}
