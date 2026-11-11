import 'package:flutter/material.dart';
import '../engine/game_news.dart';
import '../engine/postseason.dart';
import '../providers/app_state.dart';
import '../models/team.dart';
import '../models/player.dart';
import '../utils/schedule_generator.dart';
import '../utils/standings.dart';
import '../utils/grade_utils.dart';
import '../utils/app_theme.dart';
import '../widgets/condition_face.dart';
import 'match_detail_screen.dart';

/// 日程（デザイン案A：月カレンダー＋試合結果）
///  上部のチーム切り替えで、自チーム以外の日程・結果も見られる（「全球団」は全試合の一覧）
///  日付を選ぶと右（狭い画面では下）にその日の試合結果・スコア・相手別の対戦成績
class ScheduleScreen extends StatefulWidget {
  final AppState appState;
  const ScheduleScreen({Key? key, required this.appState}) : super(key: key);

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

const _navy = Color(0xFF0B1626);
const _navy2 = Color(0xFF12233B);
const _lime = Color(0xFFC6F24E);
const _muted = Color(0xFF8EA3BF);
const _bg = Color(0xFFEEF1F5);
const _win = Color(0xFF2563EB);
const _lose = Color(0xFFDC2626);

class _ScheduleScreenState extends State<ScheduleScreen> {
  int _currentMonth = 1;
  late DateTime _displayedDate;
  /// 表示中のチーム（null＝全球団）
  String? _teamId;
  late DateTime _selected;
  /// true＝2軍の日程・結果を見る（2軍は1軍と同じ日程・同じ対戦チームの2軍と試合する）
  int _level = 0; // 0=1軍 1=2軍 2=3軍（3軍は2軍戦のある日に12球団の総当たり）
  bool get _farm => _level > 0;
  bool _narrow = false; // スマホ幅（カレンダーを詰めた表示にする）

  AppState get app => widget.appState;

  List<Match> get _all => _level == 2 ? app.thirdMatches : _farm ? app.farmMatches.where((m) => m.matchType != 'ALLSTAR').toList() : app.matches;

  @override
  void initState() {
    super.initState();
    // 試合のある月（2〜9月）を開く。オフシーズンは、前の年度なら9月、次の年度の準備中なら2月
    final cd = app.currentDate;
    _currentMonth = cd.year < app.startYear || cd.month == 1 ? 2 : (cd.month > 9 ? 9 : cd.month);
    _displayedDate = DateTime(app.startYear, _currentMonth, 1);
    _teamId = app.teams.any((t) => t.id == app.myTeamId) ? app.myTeamId : null;
    _selected = app.currentDate;
    _pickSelected();
  }

  /// 選んだ日に試合がなければ、直近の試合日（まだ1試合も無ければ開幕日）を選んでおく
  void _pickSelected() {
    final ms = _teamMatches();
    if (ms.isEmpty) return;
    if (ms.any((m) => DateUtils.isSameDay(m.date, _selected))) return;
    final last = ms.where((m) => !m.date.isAfter(app.currentDate)).toList();
    if (last.isNotEmpty) {
      _selected = last.last.date;
    } else {
      _selected = (ms.toList()..sort((a, b) => a.date.compareTo(b.date))).first.date;
      _currentMonth = _selected.month;
      _displayedDate = DateTime(app.startYear, _currentMonth, 1);
    }
  }

  void _changeMonth(int delta) {
    setState(() {
      _currentMonth += delta;
      if (_currentMonth > 12) {
        _currentMonth = 1;
      } else if (_currentMonth < 1) {
        _currentMonth = 12;
      }
      _displayedDate = DateTime(app.startYear, _currentMonth, 1);
    });
  }

  Team? _team(String? id) => id == null ? null : app.teamById(id);

  List<Match> _teamMatches() {
    final id = _teamId;
    if (id == null) return _all;
    return _all.where((m) => m.homeTeamId == id || m.awayTeamId == id).toList();
  }

  List<Match> _matchesOn(DateTime d) => _teamMatches().where((m) => DateUtils.isSameDay(m.date, d)).toList()..sort((a, b) => a.dh.compareTo(b.dh));

  /// ポストシーズンの予定（日付は決まっている。対戦は決まりしだい）
  late final Map<DateTime, List<PostPlanDay>> _plan = postPlan(app.startYear);
  List<PostPlanDay> _planOn(DateTime d) => _plan[DateUtils.dateOnly(d)] ?? const [];

  /// 予定の1行：「Aリーグ CSファーストステージ 第1戦　ソフトクリーム 対 東新」（未定は順位で）
  String _planText(PostPlanDay p) {
    final s = app.postseason.where((x) => x.id == (p.stage == 'JS' ? 'JS' : '${p.stage}_${p.league}')).firstOrNull;
    final lg = p.league == 'CL' ? 'Aリーグ ' : (p.league == 'PL' ? 'Bリーグ ' : '');
    String name(String id) => id.isEmpty ? '' : (app.teamById(id) == null ? id : teamShort(app.teamById(id)!));
    final vs = s != null && s.high.isNotEmpty && s.low.isNotEmpty
        ? '${name(s.homeOf(p.n))} 対 ${name(s.homeOf(p.n) == s.high ? s.low : s.high)}'
        : (s != null && s.high.isNotEmpty ? '${name(s.high)} 対 未定' : '未定（${switch (p.stage) { 'CS1' => '2位 対 3位', 'CSF' => '1位 対 ファースト勝者', _ => '両リーグのCS勝者' }}）');
    final done = s != null && s.winner.isNotEmpty;
    return '$lg${p.stageLabel} 第${p.n + 1}戦${p.ifNeeded ? '（必要なら）' : ''}　${done ? '終了（${name(s.winner)}が勝ち抜け）' : vs}';
  }

  /// その日に雨天中止になった試合（振替で別の日へ移った・打ち切り）がある
  bool _rainedOn(DateTime d) {
    if (_farm || _level == 2) return false;
    final key = '${d.month}/${d.day} 雨天中止';
    return _teamMatches().any((m) => (m.note.startsWith(key) && !DateUtils.isSameDay(m.date, d)) || (m.cancelled && DateUtils.isSameDay(m.date, d)));
  }

  /// 天気のアイコン（今日から 7 日先まで・過去の試合）。ドームは出さない
  String _wIcon(List<Match> ms) {
    if (_farm || _level == 2 || ms.isEmpty) return '';
    final m = ms.first;
    if (DateUtils.dateOnly(m.date).difference(DateUtils.dateOnly(app.currentDate)).inDays > 7) return '';
    return app.weatherIcon(m);
  }

  static const _typeShort = {'OPEN': 'OP', 'INTERLEAGUE': '交流', 'ALLSTAR': '球宴', 'CS': 'CS', 'JS': '日本S'};
  static const _typeLong = {'OPEN': 'オープン戦', 'LEAGUE': '公式戦', 'INTERLEAGUE': '交流戦', 'ALLSTAR': 'オールスター', 'CS': 'クライマックスシリーズ', 'JS': '日本シリーズ'};

  // ───────── 試合の詳細（ボックススコア／一球速報） ─────────

  void _showMatchDetails(Match m) {
    if (!m.isPlayed) return;
    final home = _team(m.homeTeamId), away = _team(m.awayTeamId);
    if (home == null || away == null) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => MatchDetailScreen(match: m, home: home, away: away, farm: _farm, appState: app)));
  }

  // ───────── 画面 ─────────

  @override
  Widget build(BuildContext context) {
    if (app.matches.isEmpty) {
      return const Scaffold(backgroundColor: _bg, body: Center(child: Text('日程が生成されていません', style: TextStyle(fontSize: 18))));
    }
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: LayoutBuilder(builder: (context, c) {
          final wide = c.maxWidth >= 1000;
          _narrow = c.maxWidth < 600;
          final pad = wide ? 24.0 : (_narrow ? 8.0 : 16.0);
          if (wide) {
            return Padding(
              padding: EdgeInsets.fromLTRB(pad, 18, pad, 18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _header(wide),
                const SizedBox(height: 10),
                _teamSwitcher(),
                const SizedBox(height: 12),
                Expanded(
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: LayoutBuilder(builder: (context, cc) => _calendar(cc.maxHeight))),
                    const SizedBox(width: 16),
                    SizedBox(width: 340, child: SingleChildScrollView(child: _sidePanel())),
                  ]),
                ),
              ]),
            );
          }
          return ListView(
            padding: EdgeInsets.fromLTRB(pad, _narrow ? 8 : 14, pad, 24),
            children: [
              _header(wide),
              SizedBox(height: _narrow ? 6 : 10),
              _teamSwitcher(),
              SizedBox(height: _narrow ? 6 : 12),
              _calendar(null),
              SizedBox(height: _narrow ? 10 : 16),
              _sidePanel(),
            ],
          );
        }),
      ),
    );
  }

  Widget _header(bool wide) {
    final t = _team(_teamId);
    int w = 0, l = 0, d = 0;
    if (t != null) {
      for (final m in _teamMatches()) {
        if (!m.isPlayed || m.date.month != _currentMonth || m.matchType == 'ALLSTAR') continue;
        final home = m.homeTeamId == t.id;
        final my = (home ? m.homeScore : m.awayScore) ?? 0, op = (home ? m.awayScore : m.homeScore) ?? 0;
        if (my > op) {
          w++;
        } else if (my < op) {
          l++;
        } else {
          d++;
        }
      }
    }
    Widget navBtn(IconData i, String label, VoidCallback f) => SizedBox(
          width: _narrow ? 32 : 40, height: _narrow ? 32 : 40,
          child: OutlinedButton(
            onPressed: f,
            style: OutlinedButton.styleFrom(padding: EdgeInsets.zero, backgroundColor: Colors.white, side: const BorderSide(color: Color(0xFFCBD5E1)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: Icon(i, size: 20, color: const Color(0xFF0F172A), semanticLabel: label),
          ),
        );
    Widget legend(Color c, String s, {bool outline = false}) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 11, height: 11, decoration: BoxDecoration(color: outline ? null : c, border: outline ? Border.all(color: c, width: 2) : null, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 4),
          Text(s, style: const TextStyle(fontSize: 12, color: Color(0xFF475569))),
        ]);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: _narrow ? 6 : 12,
      runSpacing: _narrow ? 4 : 8,
      children: [
        SegmentedButton<int>(
          segments: const [ButtonSegment(value: 0, label: Text('1軍')), ButtonSegment(value: 1, label: Text('2軍')), ButtonSegment(value: 2, label: Text('3軍'))],
          selected: {_level},
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(selectedBackgroundColor: _navy, selectedForegroundColor: _lime, backgroundColor: Colors.white, visualDensity: VisualDensity.compact),
          onSelectionChanged: (v) => setState(() {
            _level = v.first;
            _pickSelected();
          }),
        ),
        navBtn(Icons.chevron_left, '前の月', () => _changeMonth(-1)),
        Text('${app.startYear}年 $_currentMonth月${_farm ? '（${_level + 1}軍）' : ''}', style: TextStyle(fontSize: _narrow ? 18 : 24, fontWeight: FontWeight.w900)),
        navBtn(Icons.chevron_right, '次の月', () => _changeMonth(1)),
        if (t != null)
          Text.rich(TextSpan(children: [
            TextSpan(text: '${teamShort(t)} 月間 ', style: const TextStyle(color: Color(0xFF475569))),
            TextSpan(text: '$w勝$l敗${d > 0 ? '$d分' : ''}', style: const TextStyle(fontWeight: FontWeight.w800)),
          ]), style: TextStyle(fontSize: _narrow ? 12.5 : 14)),
        if (wide) const SizedBox(width: 20),
        Wrap(spacing: 12, children: [legend(_win, '勝ち'), legend(_lose, '負け'), legend(const Color(0xFF0F172A), 'ホーム', outline: true)]),
      ],
    );
  }

  /// 球団の切り替え：リーグの12球団を略称で 2段×6（Aリーグ・Bリーグ）。左に「全球団」。リーグから外した球団は出さない
  Widget _teamSwitcher() {
    Widget cell(String? id, String label, Color? color, {double h = 30}) {
      final sel = _teamId == id;
      final mine = id != null && id == app.myTeamId;
      return Material(
        color: sel ? _navy : Colors.white,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => setState(() => _teamId = id),
          child: Container(
            height: h,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: sel ? _navy : const Color(0xFFDCE2EA)),
            ),
            child: Row(children: [
              if (color != null) Container(width: 4, decoration: BoxDecoration(color: color, borderRadius: const BorderRadius.horizontal(left: Radius.circular(6)))),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('$label${mine ? '★' : ''}', maxLines: 1, style: TextStyle(fontSize: 12, color: sel ? Colors.white : const Color(0xFF0F172A), fontWeight: sel || mine ? FontWeight.w800 : FontWeight.w500)),
                  ),
                ),
              ),
            ]),
          ),
        ),
      );
    }

    Widget line(String lg) => Row(children: [
          for (final t in app.teams.where((t) => t.league == lg)) ...[
            Expanded(child: cell(t.id, teamInitial(t), teamColor(app.teams, t))),
            const SizedBox(width: 3),
          ],
        ]);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 44, child: cell(null, '全球団', null, h: 63)),
      const SizedBox(width: 3),
      Expanded(child: Column(children: [line('CL'), const SizedBox(height: 3), line('PL')])),
    ]);
  }

  // ───────── カレンダー ─────────

  Widget _calendar(double? height) {
    final daysInMonth = DateUtils.getDaysInMonth(_displayedDate.year, _displayedDate.month);
    final firstWeekday = _displayedDate.weekday;
    final weeks = ((daysInMonth + firstWeekday - 1) / 7).ceil();
    final headH = _narrow ? 18.0 : 22.0, gap = _narrow ? 3.0 : 6.0;
    final minCell = _narrow ? (_teamId == null ? 46.0 : 50.0) : (_teamId == null ? 96.0 : 90.0);
    double cellH = minCell;
    if (height != null) {
      cellH = ((height - headH - gap * weeks) / weeks).clamp(minCell, 160.0);
    }
    const dows = ['月', '火', '水', '木', '金', '土', '日'];
    final grid = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(
        height: headH,
        child: Row(children: [
          for (int i = 0; i < 7; i++)
            Expanded(child: Text(dows[i], textAlign: TextAlign.center, style: TextStyle(fontSize: _narrow ? 11 : 12, color: i == 5 ? _win : (i == 6 ? _lose : const Color(0xFF64748B))))),
        ]),
      ),
      for (int w = 0; w < weeks; w++)
        Padding(
          padding: EdgeInsets.only(top: gap),
          child: SizedBox(
            height: cellH,
            child: Row(children: [
              for (int i = 0; i < 7; i++) ...[
                if (i > 0) SizedBox(width: gap),
                Expanded(child: _dayCell(w * 7 + i - firstWeekday + 2, daysInMonth)),
              ],
            ]),
          ),
        ),
    ]);
    if (height == null) return grid;
    return SingleChildScrollView(child: grid);
  }

  Widget _dayCell(int day, int daysInMonth) {
    if (day < 1 || day > daysInMonth) return const SizedBox.shrink();
    if (_narrow) return _dayCellNarrow(day);
    final date = DateTime(_displayedDate.year, _displayedDate.month, day);
    final isToday = DateUtils.isSameDay(date, app.currentDate);
    final isSel = DateUtils.isSameDay(date, _selected);
    final ms = _matchesOn(date);
    final t = _team(_teamId);

    Color bg = Colors.white;
    Border border = Border.all(color: const Color(0xFFE2E8F0));
    if (ms.isEmpty) bg = const Color(0xFFF1F5F9);
    final List<Widget> body = [];
    if (ms.isEmpty && _planOn(date).isNotEmpty) {
      bg = const Color(0xFFFFFBEB);
      body.add(Text(_planOn(date).first.shortLabel, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Color(0xFFB45309))));
    }

    if (t != null && ms.isNotEmpty) {
      final m = ms.first;
      final home = m.homeTeamId == t.id;
      final opp = _team(home ? m.awayTeamId : m.homeTeamId);
      if (home) border = Border.all(color: const Color(0xFF0F172A), width: 1.5);
      body.add(Text('${home ? 'vs' : '@'} ${opp == null ? '?' : teamShort(opp)}',
          maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)));
      if (m.isPlayed) {
        final my = (home ? m.homeScore : m.awayScore) ?? 0, op = (home ? m.awayScore : m.homeScore) ?? 0;
        final res = my > op ? '○' : (my < op ? '●' : '△');
        body.add(Text('$res $my-$op', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: my > op ? _win : (my < op ? _lose : const Color(0xFF64748B)))));
        final sp = _starterName(m, home);
        if (sp != null) body.add(Text('先発 $sp', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: Color(0xFF64748B))));
      } else if (isToday) {
        body.add(const Text('今日', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF65A30D))));
      }
    } else if (t == null) {
      for (final m in ms) {
        final a = _team(m.awayTeamId), h = _team(m.homeTeamId);
        final mine = m.homeTeamId == app.myTeamId || m.awayTeamId == app.myTeamId;
        final s = m.isPlayed ? '${a == null ? '?' : teamInitial(a)} ${m.awayScore}-${m.homeScore} ${h == null ? '?' : teamInitial(h)}' : '${a == null ? '?' : teamInitial(a)} - ${h == null ? '?' : teamInitial(h)}';
        body.add(Text(s, maxLines: 1, overflow: TextOverflow.clip,
            style: TextStyle(fontSize: 10.5, height: 1.25, fontWeight: mine ? FontWeight.w800 : FontWeight.w400, color: mine ? const Color(0xFF1E3A8A) : const Color(0xFF0F172A))));
      }
    }
    if (t != null && ms.length >= 2) {
      // ダブルヘッダー：第2試合の結果
      final m = ms[1];
      final home = m.homeTeamId == t.id;
      if (m.isPlayed) {
        final my = (home ? m.homeScore : m.awayScore) ?? 0, op = (home ? m.awayScore : m.homeScore) ?? 0;
        body.add(Text('第2 ${my > op ? '○' : (my < op ? '●' : '△')} $my-$op', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: my > op ? _win : (my < op ? _lose : const Color(0xFF64748B)))));
      } else {
        body.add(const Text('ダブルヘッダー', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFF7C3AED))));
      }
    }
    if (ms.isEmpty && _rainedOn(date)) body.add(const Text('☔ 雨天中止', style: TextStyle(fontSize: 11, color: Color(0xFF2563EB), fontWeight: FontWeight.w700)));
    if (ms.isEmpty && !_rainedOn(date)) body.add(const Text('試合なし', style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8))));

    if (isToday) {
      bg = const Color(0xFFF7FEE7);
      border = Border.all(color: _navy, width: 2);
    }
    if (isSel) border = Border.all(color: _win, width: 2.5);

    String tag = '';
    if (ms.isNotEmpty) {
      final m = ms.first;
      tag = _typeShort[m.matchType] ?? '';
      if (t != null && tag.isEmpty) tag = m.homeTeamId == t.id ? 'ホーム' : 'ビジター';
    }
    return Material(
      color: bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => setState(() => _selected = date),
        onDoubleTap: ms.length == 1 && ms.first.isPlayed ? () => _showMatchDetails(ms.first) : null,
        child: Container(
          decoration: BoxDecoration(border: border, borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.fromLTRB(8, 5, 8, 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('$day', style: TextStyle(fontSize: 13, fontWeight: isToday ? FontWeight.w800 : FontWeight.w500, color: ms.isEmpty ? const Color(0xFF94A3B8) : const Color(0xFF475569))),
              if (_wIcon(ms).isNotEmpty) Text(' ${_wIcon(ms)}', style: const TextStyle(fontSize: 11)),
              const Spacer(),
              if (tag.isNotEmpty) Flexible(child: Text(tag, maxLines: 1, overflow: TextOverflow.clip, style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)))),
            ]),
            Expanded(child: ClipRect(child: SingleChildScrollView(physics: const NeverScrollableScrollPhysics(), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: body)))),
          ]),
        ),
      ),
    );
  }

  /// スマホ幅の日付マス：日付・対戦相手の1文字（ビジターは @）・結果（勝ちは青、負けは赤）だけを詰めて出す
  Widget _dayCellNarrow(int day) {
    final date = DateTime(_displayedDate.year, _displayedDate.month, day);
    final isToday = DateUtils.isSameDay(date, app.currentDate);
    final isSel = DateUtils.isSameDay(date, _selected);
    final ms = _matchesOn(date);
    final t = _team(_teamId);
    Color bg = ms.isEmpty ? (_planOn(date).isNotEmpty ? const Color(0xFFFFFBEB) : const Color(0xFFF1F5F9)) : Colors.white;
    Border border = Border.all(color: const Color(0xFFE2E8F0));
    Widget? main;
    Widget? sub;
    if (ms.isEmpty && _planOn(date).isNotEmpty) {
      main = Text(_planOn(date).first.stage == 'JS' ? '日S' : 'CS', maxLines: 1, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFFB45309), height: 1.1));
    }
    if (t != null && ms.isNotEmpty) {
      final m = ms.first;
      final home = m.homeTeamId == t.id;
      final opp = _team(home ? m.awayTeamId : m.homeTeamId);
      if (home) border = Border.all(color: const Color(0xFF0F172A), width: 1.3);
      main = Text('${home ? '' : '@'}${opp == null ? '?' : teamInitial(opp)}', maxLines: 1, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, height: 1.1));
      if (m.isPlayed) {
        final my = (home ? m.homeScore : m.awayScore) ?? 0, op = (home ? m.awayScore : m.homeScore) ?? 0;
        final c = my > op ? _win : (my < op ? _lose : const Color(0xFF64748B));
        bg = my > op ? const Color(0xFFEFF6FF) : (my < op ? const Color(0xFFFEF2F2) : Colors.white);
        sub = Text('$my-$op', maxLines: 1, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: c, fontFeatures: const [FontFeature.tabularFigures()]));
      } else if (isToday) {
        sub = const Text('今日', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF65A30D)));
      }
    } else if (t == null && ms.isNotEmpty) {
      main = Text('${ms.length}試合', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700));
    }
    if (t != null && ms.length >= 2) sub = Text('W', style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: Color(0xFF7C3AED)));
    if (ms.isEmpty && _rainedOn(date)) main = const Text('☔', style: TextStyle(fontSize: 13));
    if (isToday) border = Border.all(color: _navy, width: 2);
    if (isSel) border = Border.all(color: _win, width: 2.2);
    final tag = ms.isEmpty ? '' : (_typeShort[ms.first.matchType] ?? '');
    return Material(
      color: bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => setState(() => _selected = date),
        onDoubleTap: ms.length == 1 && ms.first.isPlayed ? () => _showMatchDetails(ms.first) : null,
        child: Container(
          decoration: BoxDecoration(border: border, borderRadius: BorderRadius.circular(6)),
          padding: const EdgeInsets.fromLTRB(3, 2, 2, 2),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('$day', style: TextStyle(fontSize: 10, height: 1.1, fontWeight: isToday ? FontWeight.w800 : FontWeight.w500, color: ms.isEmpty ? const Color(0xFF94A3B8) : const Color(0xFF475569))),
              if (_wIcon(ms).isNotEmpty) Text(_wIcon(ms), style: const TextStyle(fontSize: 8.5, height: 1.1)),
              const Spacer(),
              if (tag.isNotEmpty) Text(tag.substring(0, 1), style: const TextStyle(fontSize: 8.5, height: 1.1, color: Color(0xFF94A3B8))),
            ]),
            if (main != null) Expanded(child: Center(child: FittedBox(fit: BoxFit.scaleDown, child: main))),
            if (sub != null) Center(child: sub),
          ]),
        ),
      ),
    );
  }

  /// 試合の結果の表：見出し（勝ち投手・敗戦投手・セーブ・先発・本塁打・MVP）をそろえ、球団の色と名前、その時点の成績
  Widget _resultTable(Match m, Team away, Team home) {
    const lbl = TextStyle(fontSize: 11.5, color: Color(0xFF8FA3BC));
    const val = TextStyle(fontSize: 12.5, color: Colors.white, fontWeight: FontWeight.w700);
    const rec = TextStyle(fontSize: 11.5, color: Color(0xFFB8C6D8));
    Widget row(String label, List<Widget> lines) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 64, child: Padding(padding: const EdgeInsets.only(top: 1), child: Text(label, style: lbl))),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: lines)),
          ]),
        );
    Widget who(Team t, String name, [String? tail]) => Padding(
          padding: const EdgeInsets.only(bottom: 1),
          child: Row(children: [
            Container(width: 4, height: 13, margin: const EdgeInsets.only(right: 6), decoration: BoxDecoration(color: teamColor(app.teams, t), borderRadius: BorderRadius.circular(2))),
            Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: val)),
            if (tail != null) Text('　$tail', style: rec),
          ]),
        );
    // 勝・敗・S の投手（投手成績の 'dec'）
    (Team, String)? dec(String d) {
      for (final (side, t) in [('awayPitcher', away), ('homePitcher', home)]) {
        final ps = m.boxScore?[side];
        if (ps is Map) {
          for (final e in ps.entries) {
            if (e.value is Map && (e.value as Map)['dec'] == d) return (t, e.key.toString());
          }
        }
      }
      return null;
    }

    final rows = <Widget>[];
    for (final (d, label) in const [('勝', '勝ち投手'), ('敗', '敗戦投手'), ('S', 'セーブ')]) {
      final x = dec(d);
      if (x != null) rows.add(row(label, [who(x.$1, x.$2, '（${_decRecord(m, x.$1.id, x.$2)}）')]));
    }
    final sa = _starterName(m, false), sh = _starterName(m, true);
    if (sa != null || sh != null) {
      rows.add(row('先発', [if (sa != null) who(away, sa), if (sh != null) who(home, sh)]));
    }
    final hrs = <Widget>[];
    for (final (side, t) in [('awayBatters', away), ('homeBatters', home)]) {
      final bs = m.boxScore?[side];
      if (bs is Map) {
        bs.forEach((k, v) {
          final hr = (v is Map ? v['hr'] : 0) ?? 0;
          if (hr is int && hr > 0) hrs.add(who(t, '$k', hr > 1 ? '${hr}本' : null));
        });
      }
    }
    rows.add(row('本塁打', hrs.isEmpty ? [const Text('なし', style: rec)] : hrs));
    final mvp = _farm ? null : GameNews.mvpOf(m);
    if (mvp != null) rows.add(row('MVP', [who(mvp.home ? home : away, mvp.name, mvp.line.isEmpty ? null : '（${mvp.line}）')]));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
  }

  /// その試合までの投手の勝敗・ホールド・セーブ（同じ種類の試合：公式戦・オープン戦・ポストシーズン）。例：5勝4敗1H4S
  String _decRecord(Match m, String teamId, String name) {
    const official = {'LEAGUE', 'INTERLEAGUE'};
    bool same(String t) => official.contains(m.matchType) ? official.contains(t) : t == m.matchType;
    var w = 0, l = 0, h = 0, sv = 0;
    for (final x in (_farm ? app.farmMatches : app.matches)) {
      if (!x.isPlayed || x.date.year != m.date.year || x.date.isAfter(m.date) || !same(x.matchType)) continue;
      final side = x.homeTeamId == teamId ? 'homePitcher' : (x.awayTeamId == teamId ? 'awayPitcher' : null);
      if (side == null) continue;
      final row = (x.boxScore?[side] as Map?)?[name];
      final d = row is Map ? row['dec'] : null;
      if (d == '勝') w++;
      if (d == '敗') l++;
      if (d == 'H') h++;
      if (d == 'S') sv++;
    }
    return '${w}勝${l}敗${h > 0 ? '${h}H' : ''}${sv > 0 ? '${sv}S' : ''}';
  }

  /// その試合で先発した投手（投手成績の最初の行）
  String? _starterName(Match m, bool home) {
    final ps = m.boxScore?[home ? 'homePitcher' : 'awayPitcher'];
    if (ps is Map && ps.isNotEmpty) return ps.keys.first.toString();
    return null;
  }

  // ───────── 右パネル ─────────

  Widget _sidePanel() {
    final ms = _matchesOn(_selected);
    final plan = _planOn(_selected);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (ms.isEmpty && plan.isNotEmpty)
        _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${_selected.month}/${_selected.day}　ポストシーズンの予定', style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          for (final p in plan) Padding(padding: const EdgeInsets.only(bottom: 2), child: Text(_planText(p), style: const TextStyle(fontSize: 12.5))),
        ]))
      else if (ms.isEmpty)
        _card(Text('${_selected.month}/${_selected.day}　試合はありません', style: const TextStyle(color: Color(0xFF64748B))))
      else
        for (final m in ms) Padding(padding: const EdgeInsets.only(bottom: 10), child: _gameCard(m, compact: ms.length > 1)),
      if (_teamId != null) ...[
        const SizedBox(height: 2),
        _vsCard(),
      ],
    ]);
  }

  Widget _card(Widget child) => Container(
        padding: EdgeInsets.all(_narrow ? 10 : 16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: child,
      );

  Widget _gameCard(Match m, {bool compact = false}) {
    final away = _team(m.awayTeamId), home = _team(m.homeTeamId);
    if (away == null || home == null) return const SizedBox.shrink();
    const dows = ['月', '火', '水', '木', '金', '土', '日'];
    final head = '${m.date.month}/${m.date.day}（${dows[m.date.weekday - 1]}）　${_level == 2 ? '3軍戦' : '${_farm ? '2軍・' : ''}${_typeLong[m.matchType] ?? m.matchType}'}${m.dh != 0 && !_farm ? '　${m.dhLabel}' : ''}';
    final wx = _farm || _level == 2 ? null : app.weatherOf(m);
    final children = <Widget>[
      Text(head, style: const TextStyle(fontSize: 12, letterSpacing: 2, color: _lime, fontWeight: FontWeight.w700)),
      if (wx != null && DateUtils.dateOnly(m.date).difference(DateUtils.dateOnly(app.currentDate)).inDays <= 7) Text('${wx.text}${m.note.isNotEmpty ? '　${m.note}' : ''}${m.cancelled ? '　（中止）' : ''}', style: const TextStyle(fontSize: 11.5, color: Color(0xFFB8C6D8))),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: _teamName(away, false)),
        Text(m.isPlayed ? '${m.awayScore} − ${m.homeScore}' : 'vs',
            style: TextStyle(fontSize: m.isPlayed ? (_narrow ? 24 : 30) : (_narrow ? 18 : 22), fontWeight: FontWeight.w800, color: m.isPlayed ? Colors.white : const Color(0xFF3A5578), fontFeatures: const [FontFeature.tabularFigures()])),
        Expanded(child: _teamName(home, true)),
      ]),
    ];
    if (m.isPlayed && !compact) {
      children.add(const SizedBox(height: 10));
      children.add(_lineScore(m, away, home));
      children.add(const SizedBox(height: 8));
      if (_level < 2) {
        children.add(_resultTable(m, away, home));
      } else {
        children.add(const Text('3軍戦は能力・調子による簡易計算です（個人成績は選手詳細・スコアラーの3軍で見られます）', style: TextStyle(fontSize: 12, height: 1.6, color: Color(0xFFB8C6D8))));
      }
    }
    if (!m.isPlayed && !_farm && DateUtils.isSameDay(m.date, app.currentDate)) {
      children.add(const SizedBox(height: 10));
      children.add(_starterRow(away));
      children.add(const SizedBox(height: 6));
      children.add(_starterRow(home));
    }
    if (m.isPlayed && _level < 2) {
      children.add(const SizedBox(height: 10));
      children.add(OutlinedButton(
        onPressed: () => _showMatchDetails(m),
        style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Color(0xFF3A5578)), minimumSize: const Size.fromHeight(40), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
        child: Text(_farm ? '試合の詳細（ボックススコア・個人成績）を見る' : '試合の詳細・一球速報を見る'),
      ));
    }
    return Container(
      padding: EdgeInsets.all(_narrow ? 10 : 16),
      decoration: BoxDecoration(color: _navy, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }

  Widget _teamName(Team t, bool right) => Column(
        crossAxisAlignment: right ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(width: 36, height: 4, decoration: BoxDecoration(color: teamColor(app.teams, t), borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 4),
          Text(teamShort(t), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
        ],
      );

  Widget _lineScore(Match m, Team away, Team home) {
    final n = [9, m.homeInningScores?.length ?? 0, m.awayInningScores?.length ?? 0].reduce((a, b) => a > b ? a : b);
    String cell(List<int>? s, int i, bool isHome) {
      if (s != null && i < s.length) return '${s[i]}';
      // サヨナラ・9回裏なしは x
      if (isHome && i >= (s?.length ?? 0) && i < n) return 'x';
      return '';
    }
    const st = TextStyle(fontSize: 12.5, color: Colors.white, fontFeatures: [FontFeature.tabularFigures()]);
    const hd = TextStyle(fontSize: 10.5, color: _muted);
    Widget row(String name, List<Widget> cells) => Row(children: [
          SizedBox(width: 44, child: Text(name, maxLines: 1, overflow: TextOverflow.clip, style: st.copyWith(fontSize: 12))),
          ...cells.map((w) => Expanded(child: Center(child: w))),
        ]);
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: SizedBox(
        width: 44.0 + (n + 3) * 22,
        child: Column(children: [
          row('', [for (int i = 0; i < n; i++) Text('${i + 1}', style: hd), const Text('計', style: hd), const Text('H', style: hd), const Text('E', style: hd)]),
          const SizedBox(height: 3),
          row(teamShort(away), [for (int i = 0; i < n; i++) Text(cell(m.awayInningScores, i, false), style: st), Text('${m.awayScore}', style: st.copyWith(color: _lime, fontWeight: FontWeight.w800)), Text('${m.awayHits ?? 0}', style: st), Text('${m.boxScore?['awayE'] ?? '-'}', style: st)]),
          const SizedBox(height: 2),
          row(teamShort(home), [for (int i = 0; i < n; i++) Text(cell(m.homeInningScores, i, true), style: st), Text('${m.homeScore}', style: st.copyWith(color: _lime, fontWeight: FontWeight.w800)), Text('${m.homeHits ?? 0}', style: st), Text('${m.boxScore?['homeE'] ?? '-'}', style: st)]),
        ]),
      ),
    );
  }

  Widget _starterRow(Team t) {
    final id = t.todaysStarterId;
    final Player? p = id == null ? null : t.players.where((x) => x.id == id).firstOrNull;
    final g = p == null ? '' : GradeUtils.getGrade(p.ovr);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(color: _navy2, borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        Text('${teamShort(t)} 予告先発', style: const TextStyle(fontSize: 11.5, color: _muted)),
        const SizedBox(width: 8),
        if (p != null) ...[ConditionFace(level: p.conditionAt(app.currentDate), size: 15), const SizedBox(width: 5)],
        Expanded(child: Text(p == null ? '未定' : p.listName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13))),
        if (p != null) Text(g, style: TextStyle(fontWeight: FontWeight.w900, color: AppTheme.getGradeColor(g))),
        if (p != null) Text(' ${p.ovr}', style: const TextStyle(color: Colors.white, fontSize: 13)),
      ]),
    );
  }

  /// 表示中チームの相手別成績（オープン戦・オールスターを除く）
  Widget _vsCard() {
    final t = _team(_teamId);
    if (t == null) return const SizedBox.shrink();
    final rec = <String, List<int>>{}; // opp -> [w, l, d, remaining]
    for (final m in _teamMatches()) {
      if (m.matchType == 'OPEN' || m.matchType == 'ALLSTAR') continue;
      final home = m.homeTeamId == t.id;
      final opp = home ? m.awayTeamId : m.homeTeamId;
      final r = rec.putIfAbsent(opp, () => [0, 0, 0, 0]);
      if (!m.isPlayed) {
        r[3]++;
        continue;
      }
      final my = (home ? m.homeScore : m.awayScore) ?? 0, op = (home ? m.awayScore : m.homeScore) ?? 0;
      r[my > op ? 0 : (my < op ? 1 : 2)]++;
    }
    final opps = app.teams.where((o) => rec.containsKey(o.id)).toList()
      ..sort((a, b) => (a.league == t.league ? 0 : 1).compareTo(b.league == t.league ? 0 : 1));
    return _card(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('${teamShort(t)}の対戦成績（今季）', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
      const SizedBox(height: 8),
      for (final o in opps)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Container(width: 4, height: 16, decoration: BoxDecoration(color: teamColor(app.teams, o), borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 8),
            Expanded(child: Text('${teamShort(o)}${o.league != t.league ? '（交流）' : ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
            SizedBox(width: 64, child: Text('${rec[o.id]![0]}-${rec[o.id]![1]}-${rec[o.id]![2]}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()]))),
            SizedBox(width: 60, child: Text('残り${rec[o.id]![3]}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)))),
          ]),
        ),
    ]));
  }
}
