import 'package:flutter/material.dart';
import '../providers/app_state.dart';
import 'team_roster_screen.dart';
import '../utils/standings.dart';
import '../widgets/frozen_table.dart';

/// 順位表（新聞の順位表スタイル）
///  順位・球団を左に固定し、右側を横スクロール：試合・勝・敗・分・勝率・ゲーム差・残り・得点・失点・得失点差・直近10試合・連勝連敗
///  → チーム成績（防御率と先発・救援の防御率・打率・本塁打・盗塁・失策）
///  公式戦 / 交流戦 / オープン戦 を切り替え
class StandingsScreen extends StatefulWidget {
  final AppState appState;
  final StandingsKind initialKind;
  const StandingsScreen({super.key, required this.appState, this.initialKind = StandingsKind.official});

  @override
  State<StandingsScreen> createState() => _StandingsScreenState();
}

class _StandingsScreenState extends State<StandingsScreen> {
  late StandingsKind _kind = widget.initialKind;
  int _level = 0; // 0=1軍 1=2軍 2=3軍
  List<dynamic> get _ms => _level == 0 ? app.matches : (_level == 1 ? app.farmMatches : app.thirdMatches);
  AppState get app => widget.appState;

  // 右側（横スクロール）の列：順位の数字 → チーム成績
  static const _cols = <(String, double)>[
    ('試合', 46), ('勝', 40), ('敗', 40), ('分', 36), ('勝率', 56), ('差', 48), ('残り', 46),
    ('得点', 48), ('失点', 48), ('得失', 52), ('直近10', 62), ('連続', 60),
    ('防御率', 58), ('先発', 54), ('救援', 54), ('打率', 54), ('本塁打', 52), ('盗塁', 46), ('失策', 46),
  ];

  @override
  Widget build(BuildContext context) {
    final d = app.currentDate;
    final leagues = app.teams.map((t) => t.league).where((l) => l == 'CL' || l == 'PL').toSet().toList()..sort();
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('順位表'), backgroundColor: Colors.white, foregroundColor: const Color(0xFF111827), elevation: 0),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.only(bottom: 10),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFF111827), width: 3))),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                Text('${d.year}年${d.month}月${d.day}日 時点', style: const TextStyle(fontSize: 14, color: Color(0xFF6B7280))),
                SegmentedButton<int>(
                  segments: const [ButtonSegment(value: 0, label: Text('1軍')), ButtonSegment(value: 1, label: Text('2軍')), ButtonSegment(value: 2, label: Text('3軍'))],
                  selected: {_level},
                  showSelectedIcon: false,
                  onSelectionChanged: (v) => setState(() {
                    _level = v.first;
                    if (_level == 2) _kind = StandingsKind.official;
                  }),
                ),
                if (_level < 2)
                SegmentedButton<StandingsKind>(
                  segments: const [
                    ButtonSegment(value: StandingsKind.official, label: Text('公式戦')),
                    ButtonSegment(value: StandingsKind.interleague, label: Text('交流戦')),
                    ButtonSegment(value: StandingsKind.open, label: Text('オープン戦')),
                  ],
                  selected: {_kind},
                  showSelectedIcon: false,
                  onSelectionChanged: (v) => setState(() => _kind = v.first),
                ),
              ],
            ),
          ),
          // 公式戦はリーグ別、交流戦・オープン戦は12球団まとめ
          if (_kind == StandingsKind.official && _level < 2) for (final lg in leagues) _leagueTable(lg) else _leagueTable(allLeagues),
          const SizedBox(height: 10),
          const Text(
            '表は右にスクロールできます。差＝首位とのゲーム差（首位は優勝マジック「M」、優勝が決まると「優勝」、優勝の可能性が無くなった球団に×）　残り＝残り試合数　得失＝得点−失点　直近10＝最近10試合の勝-敗　連続＝連勝・連敗　'
            '先発・救援＝先発投手・救援投手だけの防御率　自チームは黄色で表示　交流戦・オープン戦は12球団まとめ（A・Bは所属リーグ）　'
            '2軍は1軍と同じ日程・同じ対戦の2軍戦。3軍は2軍戦のある日に12球団の総当たりで組む3軍戦（結果は能力・調子による簡易計算。打撃はチーム合計のみ）。2軍・3軍にマジックは出しません',
            style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
          ),
        ],
      ),
    );
  }

  Widget _leagueTable(String lg) {
    final recs = computeStandings(app.teams, _ms.cast(), lg, _kind);
    final ts = computeTeamStats(app.teams, _ms.cast(), _kind);
    const blue = TextStyle(color: Color(0xFF1D4ED8)), red = TextStyle(color: Color(0xFFB91C1C)), grey = TextStyle(color: Color(0xFF6B7280)), bold = TextStyle(fontWeight: FontWeight.w800);
    return LayoutBuilder(builder: (context, c) {
      final leadW = (c.maxWidth * 0.34).clamp(118.0, 260.0);
      final rows = <FrozenRow>[];
      for (int i = 0; i < recs.length; i++) {
        final r = recs[i];
        final t = ts[r.team.id] ?? TeamStats();
        final diff = r.diff;
        rows.add(FrozenRow(
          color: r.team.id == app.myTeamId ? const Color(0xFFFEF9C3) : null,
          // タップでその球団の選手一覧
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TeamRosterScreen(appState: app, team: r.team))),
          lead: Row(children: [
            SizedBox(width: 22, child: Text('${i + 1}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
            Container(width: 5, height: 20, decoration: BoxDecoration(color: teamColor(app.teams, r.team), borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 6),
            Expanded(child: Text(leadW > 200 ? r.team.name : teamShort(r.team), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
            if (_kind != StandingsKind.official || _level == 2) Text(r.team.league == 'CL' ? 'A' : 'B', style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
          ]),
          cells: [
            '${r.games}', '${r.w}', '${r.l}', '${r.d}', r.pctText, gamesBehindLabel(recs, r, official: _level == 0 && _kind == StandingsKind.official && lg != allLeagues), '${r.remaining}',
            '${r.rs}', '${r.ra}', '${diff > 0 ? '+' : ''}$diff', r.last10, r.streak,
            t.era, t.starterEra, t.reliefEra, t.avg, '${t.hr}', '${t.sb}', '${t.e}',
          ],
          styles: [null, null, null, null, bold, null, grey, null, null, diff >= 0 ? blue : red, null, null, bold, null, null, bold, null, null, null],
        ));
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(padding: const EdgeInsets.fromLTRB(0, 16, 0, 6), child: Text('${_level == 0 ? '' : '${_level + 1}軍　'}${leagueLabel(lg)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900))),
        FrozenTable(
          leadHeader: '順位・球団',
          leadWidth: leadW,
          headers: [for (final x in _cols) x.$1],
          widths: [for (final x in _cols) x.$2],
          rows: rows,
          rowHeight: 40,
        ),
      ]);
    });
  }
}
