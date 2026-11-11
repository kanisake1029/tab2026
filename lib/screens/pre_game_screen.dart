import 'package:flutter/material.dart';
import '../models/stadium.dart';
import '../engine/farm_engine.dart';
import '../models/player.dart';
import '../models/team.dart';
import '../providers/app_state.dart';
import '../utils/app_theme.dart';
import '../utils/grade_utils.dart';
import '../utils/schedule_generator.dart';
import '../utils/standings.dart';
import '../widgets/condition_face.dart';
import '../widgets/player_row.dart' show PitcherLine;
import '../widgets/player_detail_dialog.dart' show showPlayerDetail;
import 'order_screen.dart';
import '../ai/ai_text.dart';
import '../ai/pregame_facts.dart';

/// 試合開始前の画面（デザイン案A：オーダー比較＋モード選択、案Bの「注目のマッチアップ」を融合）
///  両チームのスタメンと先発を並べ、右（狭い画面では下）に注目のマッチアップ、
///  下部で「オーダーを変更」と進行方法（自動試合・簡易采配・フル采配）を選ぶ。
/// 戻り値: 'auto'（自動試合）/ 'simple'（簡易采配）/ 'manage'（フル采配）/ 'clutch'（終盤接戦のみ采配）。戻る操作で null。
class PreGameScreen extends StatefulWidget {
  final Team homeTeam;
  final Team awayTeam;
  final String myTeamId;
  final AppState? appState;
  final Match? match;

  const PreGameScreen({super.key, required this.homeTeam, required this.awayTeam, required this.myTeamId, this.appState, this.match});

  @override
  State<PreGameScreen> createState() => _PreGameScreenState();
}

const _navy = Color(0xFF0B1626);
const _lime = Color(0xFFC6F24E);
const _muted = Color(0xFF8EA3BF);
const _bg = Color(0xFFEEF1F5);

class _PreGameScreenState extends State<PreGameScreen> {
  Team get home => widget.homeTeam;
  Team get away => widget.awayTeam;
  DateTime get _today => widget.appState?.currentDate ?? DateTime.now();

  Player? _find(Team t, String? id) {
    if (id == null || id.isEmpty) return null;
    for (final p in t.players) {
      if (p.id == id) return p;
    }
    return null;
  }

  String _avg(Player p) => p.shownStats.battingAverage.toStringAsFixed(3).replaceFirst(RegExp(r'^0'), '');

  /// 今季の成績（この試合と同じ種類の試合だけ）
  String _record(Team t) {
    final app = widget.appState;
    if (app == null) return '';
    final type = widget.match?.matchType ?? 'LEAGUE';
    int w = 0, l = 0, d = 0;
    for (final m in app.matches) {
      if (!m.isPlayed || (m.homeTeamId != t.id && m.awayTeamId != t.id)) continue;
      final open = m.matchType == 'OPEN';
      if ((type == 'OPEN') != open || m.matchType == 'ALLSTAR') continue;
      final h = m.homeTeamId == t.id;
      final my = (h ? m.homeScore : m.awayScore) ?? 0, op = (h ? m.awayScore : m.homeScore) ?? 0;
      if (my > op) {
        w++;
      } else if (my < op) {
        l++;
      } else {
        d++;
      }
    }
    return '${leagueLabel(t.league)}　$w-$l-$d';
  }

  String _h2h() {
    final app = widget.appState;
    if (app == null) return '';
    int w = 0, l = 0, d = 0;
    final me = widget.myTeamId;
    final opp = home.id == me ? away.id : home.id;
    for (final m in app.matches) {
      if (!m.isPlayed || m.matchType == 'OPEN') continue;
      if (!((m.homeTeamId == me && m.awayTeamId == opp) || (m.homeTeamId == opp && m.awayTeamId == me))) continue;
      final h = m.homeTeamId == me;
      final my = (h ? m.homeScore : m.awayScore) ?? 0, op = (h ? m.awayScore : m.homeScore) ?? 0;
      if (my > op) {
        w++;
      } else if (my < op) {
        l++;
      } else {
        d++;
      }
    }
    return '今季対戦 $w勝$l敗${d > 0 ? '$d分' : ''}';
  }

  Future<void> _openOrder() async {
    final app = widget.appState;
    if (app == null) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => Scaffold(appBar: AppBar(title: const Text('オーダー変更')), body: OrderScreen(appState: app))));
    if (mounted) setState(() {});
  }

  /// 今日の天気（球場・屋根・気温・湿度）と、試合への影響
  Widget _weatherBar() {
    final m = widget.match, a = widget.appState;
    if (m == null || a == null) return const SizedBox.shrink();
    final w = a.weatherOf(m);
    if (w == null) return const SizedBox.shrink();
    final notes = [
      if (m.dh != 0) 'ダブルヘッダー ${m.dhLabel}',
      if (w.wetPlay) '小雨：打球が死にやすく、制球・送球が乱れやすい・観客減',
      if (w.heat) '猛暑：体力の消耗が12%増し',
      if (!w.indoor && w.tempC >= 28) '高温多湿で空気が軽く、打球が伸びる',
      if (m.note.isNotEmpty) m.note,
    ];
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E8F0))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${Stadium.byId(home.homeStadium).name}　${w.text}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        for (final n in notes) Text(n, style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B))),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.match;
    const dows = ['月', '火', '水', '木', '金', '土', '日'];
    final type = m == null ? '' : const {'OPEN': 'オープン戦', 'LEAGUE': '公式戦', 'INTERLEAGUE': '交流戦', 'CS': 'クライマックスシリーズ', 'JS': '日本シリーズ'}[m.matchType] ?? m.matchType;
    final head = m == null ? '' : '${m.date.month}/${m.date.day}（${dows[m.date.weekday - 1]}）　$type';
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _navy,
        elevation: 0,
        title: Text(head.isEmpty ? '${away.name} vs ${home.name}' : head, style: const TextStyle(fontSize: 14, letterSpacing: 2, color: _navy, fontWeight: FontWeight.w700)),
        actions: [Center(child: Padding(padding: const EdgeInsets.only(right: 18), child: Text(_h2h(), style: const TextStyle(fontSize: 13, color: _muted))))],
      ),
      body: LayoutBuilder(builder: (context, c) {
        final wide = c.maxWidth >= 1100;
        final mid = c.maxWidth >= 720;
        final awayCard = _lineupCard(away, 'ビジター');
        final homeCard = _lineupCard(home, 'ホーム');
        final keys = Column(children: [_weatherBar(), _preview(), _matchupPanel()]);
        final pad = mid ? 20.0 : 6.0;
        Widget body;
        if (wide) {
          body = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: awayCard),
            const SizedBox(width: 14),
            Expanded(child: homeCard),
            const SizedBox(width: 14),
            SizedBox(width: 320, child: keys),
          ]);
        } else if (mid) {
          body = Column(children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: awayCard), const SizedBox(width: 12), Expanded(child: homeCard)]),
            const SizedBox(height: 12),
            keys,
          ]);
        } else {
          body = Column(children: [awayCard, const SizedBox(height: 6), homeCard, const SizedBox(height: 6), keys]);
        }
        return Column(children: [
          Expanded(child: SingleChildScrollView(padding: EdgeInsets.fromLTRB(pad, mid ? 16 : 8, pad, mid ? 16 : 8), child: body)),
          _footer(mid),
        ]);
      }),
    );
  }

  // ───────── スタメンのカード ─────────

  Widget _lineupCard(Team t, String side) {
    final sp = _find(t, t.todaysStarterId);
    final isMine = t.id == widget.myTeamId;
    const head = TextStyle(fontSize: 11, color: Color(0xFF64748B));
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(width: 5, height: 32, decoration: BoxDecoration(color: teamColor(widget.appState?.teams ?? [t], t), borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(side, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
              Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, height: 1.2)),
            ]),
          ),
          if (isMine)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: const Color(0xFFDCFCE7), borderRadius: BorderRadius.circular(99)),
              child: const Text('自チーム', style: TextStyle(fontSize: 11, color: Color(0xFF15803D), fontWeight: FontWeight.w800)),
            ),
          const SizedBox(width: 8),
          Text(_record(t), style: const TextStyle(fontSize: 12.5, color: Color(0xFF475569))),
        ]),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.only(bottom: 2),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0)))),
          child: const Row(children: [
            SizedBox(width: 18, child: Text('順', style: head)),
            SizedBox(width: 40, child: Text('守・適', style: head)),
            Expanded(child: Text('選手', style: head)),
            SizedBox(width: 44, child: Text('総合', style: head, textAlign: TextAlign.right)),
            SizedBox(width: 40, child: Text('打率', style: head, textAlign: TextAlign.right)),
            SizedBox(width: 24, child: Text('本', style: head, textAlign: TextAlign.right)),
            SizedBox(width: 28, child: Text('点', style: head, textAlign: TextAlign.right)),
            SizedBox(width: 24, child: Text('盗', style: head, textAlign: TextAlign.right)),
          ]),
        ),
        for (var i = 0; i < t.lineup.length; i++) _row(t, i),
        const SizedBox(height: 6),
        InkWell(
          onTap: sp == null || widget.appState == null ? null : () => showPlayerDetail(context, widget.appState, sp, allowActions: false),
          child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(color: const Color(0xFFF8FAFC), border: Border.all(color: const Color(0xFFE2E8F0)), borderRadius: BorderRadius.circular(10)),
          child: Row(children: [
            const Text('先発', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
            const SizedBox(width: 6),
            if (sp == null) const Expanded(child: Text('未設定', style: TextStyle(fontWeight: FontWeight.w900))) else Expanded(child: PitcherLine(p: sp, s: sp.shownStats, date: _today)),
          ]),
        ),
        ),
        if (t.active26.length != Team.benchSize)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('⚠ ベンチ入りが${t.active26.length}人です（${Team.benchSize}人が基本。1軍の人数を確認してください）', style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
          ),
      ]),
    );
  }

  Widget _row(Team t, int i) {
    final e = t.lineup[i];
    final p = _find(t, e.playerId);
    // タップで選手の詳細（相手チームの選手も見られる）
    return InkWell(
      onTap: p == null || widget.appState == null ? null : () => showPlayerDetail(context, widget.appState, p, allowActions: false),
      child: Container(
      height: 28,
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9)))),
      child: Row(children: [
        SizedBox(width: 18, child: Text('${i + 1}', style: const TextStyle(fontWeight: FontWeight.w800))),
        SizedBox(
          width: 40,
          child: Builder(builder: (_) {
            final apt = p == null || e.position == 'DH' || e.position == '投' ? null : FarmEngine.fieldingAt(p, e.position);
            final g = apt == null ? '' : GradeUtils.getGrade(apt);
            return Text.rich(TextSpan(children: [
              TextSpan(text: posLabel(e.position), style: const TextStyle(fontSize: 12, color: Color(0xFF475569))),
              if (apt != null) TextSpan(text: ' $g', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: apt < 40 ? Colors.red : AppTheme.getGradeColor(g))),
            ]));
          }),
        ),
        if (p != null) ...[ConditionFace(level: p.conditionAt(_today), size: 15), const SizedBox(width: 4)],
        Expanded(
          child: Text(p == null ? '-' : p.listName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
        ),
        if (p != null) ...[
          Text(p.bats == 'L' ? '左' : (p.bats == 'S' ? '両' : '右'), style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
          SizedBox(
            width: 44,
            child: Text.rich(TextSpan(children: [
              TextSpan(text: GradeUtils.getGrade(p.ovr), style: TextStyle(fontWeight: FontWeight.w900, color: AppTheme.getGradeColor(GradeUtils.getGrade(p.ovr)))),
              TextSpan(text: ' ${p.ovr}'),
            ]), textAlign: TextAlign.right, style: const TextStyle(fontSize: 12.5)),
          ),
          SizedBox(width: 40, child: Text(_avg(p), textAlign: TextAlign.right, style: const TextStyle(fontSize: 12.5, fontFeatures: [FontFeature.tabularFigures()]))),
          SizedBox(width: 24, child: Text('${p.shownStats.homeRuns}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12.5))),
          SizedBox(width: 28, child: Text('${p.shownStats.rbi}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12.5))),
          SizedBox(width: 24, child: Text('${p.shownStats.stolenBases}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12.5))),
        ],
      ]),
      ),
    );
  }

  // ───────── 見どころ（開発者版：AI が書く） ─────────

  late final _previewItem = widget.appState == null || widget.match == null ? null : AiPregame.item(widget.appState!, widget.match!, home, away);

  Widget _preview() {
    final item = _previewItem;
    if (item == null) return const SizedBox.shrink();
    return AiText(
      item: item,
      fallback: '',
      builder: (t) => t.isEmpty
          ? const SizedBox.shrink()
          : Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: const Border(left: BorderSide(color: Color(0xFFF59E0B), width: 4))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('見どころ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Color(0xFFB45309))),
                const SizedBox(height: 4),
                Text(t, style: const TextStyle(fontSize: 14, height: 1.75, color: Color(0xFF1E293B))),
              ]),
            ),
    );
  }

  // ───────── 注目のマッチアップ ─────────

  Widget _matchupPanel() {
    final mine = home.id == widget.myTeamId ? home : away;
    final opp = identical(mine, home) ? away : home;
    final items = <(String, String, String)>[];

    // 自チームの4番 × 相手先発
    final oppSp = _find(opp, opp.todaysStarterId);
    if (mine.lineup.length >= 4) {
      final cleanup = _find(mine, mine.lineup[3].playerId);
      if (cleanup != null && oppSp != null) {
        final lefty = oppSp.throws == 'L';
        final vs = lefty ? cleanup.contactLeft : cleanup.contactRight;
        items.add((
          '4番 × 相手先発',
          '${cleanup.lastName} × ${oppSp.lastName}（${lefty ? '左' : '右'}投）',
          '${cleanup.lastName}は打率${_avg(cleanup)}・${cleanup.shownStats.homeRuns}本、対${lefty ? '左' : '右'}ミート ${GradeUtils.getGrade(vs)}$vs。${oppSp.lastName}は防御率${oppSp.shownStats.era.toStringAsFixed(2)}',
        ));
      }
    }
    // 相手の要注意打者（調子と成績から）
    Player? danger;
    double best = -1;
    for (final e in opp.lineup) {
      final p = _find(opp, e.playerId);
      if (p == null || p.isPitcher) continue;
      final s = p.shownStats;
      final double score = p.ovr + p.conditionAt(_today) * 4.0 + (s.atBats >= 20 ? (s.battingAverage - 0.25) * 100 + s.homeRuns * 1.5 : 0.0);
      if (score > best) {
        best = score;
        danger = p;
      }
    }
    if (danger != null) {
      final c = danger.conditionAt(_today);
      items.add((
        '要注意の打者',
        '${danger.listName}（${opp.shortName.isNotEmpty ? opp.shortName : opp.name}）'.trim(),
        '打率${_avg(danger)}・${danger.shownStats.homeRuns}本・${danger.shownStats.rbi}打点。調子は${Player.conditionLabels[c]}',
      ));
    }
    // 体力が少ない自チームのリリーフ
    final tired = mine.active26
        .map((id) => _find(mine, id))
        .whereType<Player>()
        .where((p) => p.isPitcher && p.id != mine.todaysStarterId && p.energyRatio < 0.5 && !mine.activeRotation.contains(p.id))
        .toList()
      ..sort((a, b) => a.energyRatio.compareTo(b.energyRatio));
    if (tired.isNotEmpty) {
      items.add(('体力', '疲れている中継ぎ ${tired.length}人', '${tired.take(3).map((p) => '${p.lastName} ${(p.energyRatio * 100).round()}%').join('、')}。今日は温存を検討'));
    }
    // 自チームの調子
    final counts = <int, int>{};
    for (final e in mine.lineup) {
      final p = _find(mine, e.playerId);
      if (p != null) counts[p.conditionAt(_today)] = (counts[p.conditionAt(_today)] ?? 0) + 1;
    }
    final condLine = [for (final c in [2, 1, 0, -1, -2]) if ((counts[c] ?? 0) > 0) '${Player.conditionLabels[c]}${counts[c]}'].join('・');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE2E8F0))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('注目のマッチアップ', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: _navy)),
        const SizedBox(height: 10),
        if (items.isEmpty) const Text('データがありません', style: TextStyle(color: _muted)),
        for (final it in items)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(it.$1, style: const TextStyle(fontSize: 11, color: Color(0xFF15803D), fontWeight: FontWeight.w700)),
              Text(it.$2, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: _navy)),
              const SizedBox(height: 2),
              Text(it.$3, style: const TextStyle(fontSize: 12.5, height: 1.5, color: Color(0xFF475569))),
            ]),
          ),
        if (condLine.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text('自チームのスタメンの調子：$condLine', style: const TextStyle(fontSize: 12, color: _muted)),
        ],
      ]),
    );
  }

  // ───────── 下部：オーダー変更と進行方法 ─────────

  Widget _footer(bool mid) {
    Widget mode(String value, String title, String sub, String time, Color bg, Color fg) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: SizedBox(
              height: mid ? 84 : 74,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(value),
                style: FilledButton.styleFrom(backgroundColor: bg, foregroundColor: fg, padding: const EdgeInsets.symmetric(horizontal: 6), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(title, style: TextStyle(fontSize: mid ? 18 : 15, fontWeight: FontWeight.w900)),
                  Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5)),
                  if (mid) Text(time, style: TextStyle(fontSize: 10.5, color: fg.withValues(alpha: 0.7))),
                ]),
              ),
            ),
          ),
        );
    final orderBtn = OutlinedButton.icon(
      onPressed: widget.appState == null ? null : _openOrder,
      icon: const Icon(Icons.list_alt),
      label: const Text('オーダーを変更'),
      style: OutlinedButton.styleFrom(foregroundColor: _navy, backgroundColor: Colors.white, side: const BorderSide(color: Color(0xFFCBD5E1)), minimumSize: Size(mid ? 150 : 0, mid ? 84 : 44), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
    );
    const specs = [
      ('auto', '自動試合', '結果だけ見る', '約1秒', Color(0xFF64748B), Colors.white),
      ('simple', '簡易采配', '継投・代打・守備交代', '1人ずつ進む', Color(0xFF2563EB), Colors.white),
      ('manage', 'フル采配', '作戦も指示する', '1球ずつ／1人ずつ', _lime, _navy),
      ('clutch', '終盤のみ', '7回以降の接戦だけ采配', '6回まで自動', Color(0xFF7C3AED), Colors.white),
    ];
    // スマホ：2×2の横長ボタン（名前を左、説明を右に省かずに）
    Widget wideMode((String, String, String, String, Color, Color) x) => Expanded(
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: SizedBox(
              height: 56,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(x.$1),
                style: FilledButton.styleFrom(backgroundColor: x.$5, foregroundColor: x.$6, padding: const EdgeInsets.symmetric(horizontal: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: Row(children: [
                  Text(x.$2, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w900)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(x.$3, maxLines: 1, style: const TextStyle(fontSize: 10.5, height: 1.2))),
                      FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(x.$4, maxLines: 1, style: TextStyle(fontSize: 9.5, height: 1.2, color: x.$6.withValues(alpha: 0.75)))),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        );
    final modes = mid
        ? Row(children: [for (final x in specs) mode(x.$1, x.$2, x.$3, x.$4, x.$5, x.$6)])
        : Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [wideMode(specs[0]), wideMode(specs[1])]),
            Row(children: [wideMode(specs[2]), wideMode(specs[3])]),
          ]);
    return Container(
      padding: EdgeInsets.fromLTRB(mid ? 20 : 8, 10, mid ? 20 : 8, 14),
      child: mid
          ? Row(children: [orderBtn, const SizedBox(width: 8), Expanded(child: modes)])
          : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [orderBtn, const SizedBox(height: 8), modes]),
    );
  }
}
