import 'dart:math';
import 'package:flutter/material.dart';
import '../providers/app_state.dart';
import 'settings_menu_screen.dart';
import 'settings_screen.dart';
import '../models/team.dart';
import '../utils/standings.dart';
import '../utils/grade_utils.dart';
import '../utils/app_theme.dart';
import '../utils/salary_utils.dart';
import '../widgets/chip_grid.dart';

/// スタート画面（ステップ式）
///  左: タイトル・ステップ表示・続きから・設定・編集
///  右: STEP1 開始年度 → STEP2 球団 → STEP3 確認して「はじめから」
/// 画面が狭いときは、左の帯を上部にまとめて縦に並べる
class StartScreen extends StatefulWidget {
  final AppState appState;
  final Widget mainAppScreen;
  /// 空いたプレイデータで新しく始める（「続きから」を出さない）
  final bool newOnly;

  const StartScreen({super.key, required this.appState, required this.mainAppScreen, this.newOnly = false});

  @override
  State<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen> {
  static const _green = Color(0xFF0F2A1D);
  static const _greenMid = Color(0xFF1C4430);
  static const _greenLine = Color(0xFF3F6B53);
  static const _greenText = Color(0xFF9CC7AE);
  static const _gold = Color(0xFFF2C230);

  int _step = 0; // 0=リーグ設定（12球団） 1=自球団 2=年度・試合数・資金
  int _selectedYear = 2026;
  String? _selectedTeamId;
  String _league = 'CL';
  int _funds = 150; // 自球団の初期の資金（億円）。50〜200億円を10億円単位で選ぶ
  int _games = 143; // 公式戦の試合数（120・143・156）

  AppState get app => widget.appState;

  List<Team> _selectable() {
    final t = app.teams.where((t) => t.league == 'CL' || t.league == 'PL').toList();
    return t.isEmpty ? app.teams : t;
  }

  Team? get _selectedTeam {
    for (final t in app.teams) {
      if (t.id == _selectedTeamId) return t;
    }
    return null;
  }

  void _continue() {
    final saved = app.teams.any((t) => t.id == app.myTeamId) ? app.myTeamId : _selectedTeamId!;
    app.myTeamId = saved;
    app.onTeamChosen();
    app.updateAndSave();
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => widget.mainAppScreen));
  }

  Future<void> _startNew() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(widget.newOnly ? '新しく始める' : 'はじめから'),
        content: Text(widget.newOnly ? 'プレイデータ${app.slot} で新しく始めます。球団は「初期状態」から始まります。' : 'プレイデータ${app.slot} の成績・試合結果・移籍などがすべてリセットされ、球団は「初期状態」から始まります。はじめからスタートしますか？'),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('キャンセル')),
          TextButton(onPressed: () => Navigator.of(c).pop(true), child: Text(widget.newOnly ? '開始する' : 'リセットして開始', style: const TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (!mounted || confirm != true) return;
    app.myTeamId = _selectedTeamId!;
    app.startYear = _selectedYear;
    app.seasonGames = _games;
    app.weatherSeed = Random().nextInt(1 << 30);
    await app.resetToInitialTeams(); // 新しいデータは初期12球団の状態から（前のデータの移籍・入団は残さない）
    app.setSeasonGames(_games);
    app.finOf(app.teams.firstWhere((t) => t.id == app.myTeamId)).funds = _funds * 10000; // 万円
    app.onTeamChosen();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => widget.mainAppScreen));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          if (app.teams.isEmpty) return const Center(child: CircularProgressIndicator());
          final teams = _selectable();
          if (_selectedTeamId == null || !teams.any((t) => t.id == _selectedTeamId)) {
            final saved = teams.where((t) => t.id == app.myTeamId);
            _selectedTeamId = saved.isNotEmpty ? saved.first.id : teams.first.id;
            _league = _selectedTeam?.league ?? 'CL';
          }
          return LayoutBuilder(builder: (context, c) {
            final wide = c.maxWidth >= 900;
            final side = _sidePanel(wide);
            final main = Padding(padding: EdgeInsets.all(wide ? 40 : 16), child: _stepContent(teams, wide));
            if (wide) {
              return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [SizedBox(width: 360, child: side), Expanded(child: main)]);
            }
            // 手順を変えたら上から（key を替えてスクロールの位置を戻す）
            return SingleChildScrollView(key: ValueKey('step$_step'), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [side, main]));
          });
        },
      ),
    );
  }

  // ---------------- 左の帯 ----------------
  Widget _sidePanel(bool wide) {
    final saved = app.teams.where((t) => t.id == app.myTeamId).toList();
    final savedTeam = saved.isNotEmpty ? saved.first : null;
    final d = app.currentDate;
    final continueSub = savedTeam != null
        ? '${teamShort(savedTeam)} ／ ${d.year}年${d.month}月${d.day}日 ／ ${savedTeam.wins}勝${savedTeam.losses}敗${savedTeam.draws}分'
        : '${d.year}年${d.month}月${d.day}日から';

    final steps = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _stepRow(0, 'リーグ設定', 'Aリーグ ${app.clTeams.length}／6・Bリーグ ${app.plTeams.length}／6'),
        _stepRow(1, '自球団', _selectedTeam != null ? teamShort(_selectedTeam!) : '未選択'),
        _stepRow(2, '年度・試合数・資金', '$_selectedYear年・$_games試合・$_funds億円'),
      ],
    );
    final buttons = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: _greenText, padding: EdgeInsets.zero),
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back, size: 16),
            label: Text('プレイデータの選択へ（いま：プレイデータ${app.slot}）', style: const TextStyle(fontSize: 12)),
          ),
        ),
        if (!widget.newOnly) ...[
        const Text('前回のつづき', style: TextStyle(fontSize: 12, color: _greenText)),
        const SizedBox(height: 8),
        Material(
          color: _gold,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _continue,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('続きから', style: TextStyle(color: _green, fontSize: 17, fontWeight: FontWeight.w900)),
                Text(continueSub, style: const TextStyle(color: _green, fontSize: 12)),
              ]),
            ),
          ),
        ),
        ],
        const SizedBox(height: 10),
        OutlinedButton(
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46), side: const BorderSide(color: _greenLine), foregroundColor: const Color(0xFFEAF5EE), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SettingsMenuScreen(appState: app))),
          child: const Text('設定・編集', style: TextStyle(fontSize: 14)),
        ),
      ],
    );
    final title = Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
      Text('The Authentic', style: TextStyle(color: Color(0xFFEAF5EE), fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
      Text('Baseball 2026', style: TextStyle(color: Color(0xFFEAF5EE), fontSize: 36, fontWeight: FontWeight.w900, letterSpacing: 1.2, height: 1.1)),
      Text('プロ野球ペナントシミュレーション', style: TextStyle(color: _greenText, fontSize: 13)),
    ]);
    return Container(
      color: _green,
      padding: EdgeInsets.all(wide ? 36 : 16),
      child: wide
          ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [title, const SizedBox(height: 28), steps, const Spacer(), buttons])
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [title, const SizedBox(height: 12), buttons, const SizedBox(height: 12), steps]),
    );
  }

  Widget _stepRow(int i, String title, String sub) {
    final cur = _step == i;
    final done = _step > i;
    return Material(
      color: cur ? _greenMid : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: i <= _step || (i == 1) || (i == 2 && _selectedTeamId != null) ? () => setState(() => _step = i) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: cur ? _gold : (done ? _greenLine : Colors.transparent),
                border: cur || done ? null : Border.all(color: _greenLine),
              ),
              child: Text('${i + 1}', style: TextStyle(fontWeight: FontWeight.w900, color: cur ? _green : (done ? const Color(0xFFEAF5EE) : _greenText))),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(color: Color(0xFFEAF5EE), fontWeight: FontWeight.w700, fontSize: 15)),
                Text(sub, style: const TextStyle(color: _greenText, fontSize: 12), overflow: TextOverflow.ellipsis),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  // ---------------- 右の内容 ----------------
  Widget _stepContent(List<Team> teams, bool wide) {
    switch (_step) {
      case 0:
        return _leagueStep(wide);
      case 1:
        return _teamStep(teams, wide);
      default:
        return _confirmStep(wide);
    }
  }

  Widget _heading(String s) => Text(s, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)));

  /// STEP 1：リーグの12球団を決める（新規作成チームも入れられる。外した球団はドラフトなどに参加しない）
  Widget _leagueStep(bool wide) {
    final ok = app.clTeams.length == 6 && app.plTeams.length == 6;
    final col = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _heading('STEP 1　リーグの12球団を決める'),
        const SizedBox(height: 6),
        const Text('枠を押して球団を入れ替えます。新規作成チームは「設定・編集」の初期選手編集で作れます', style: TextStyle(color: Color(0xFF64748B), fontSize: 12.5)),
        const SizedBox(height: 10),
        SettingsScreen(appState: app, bare: true, onChanged: () => setState(() {})),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _green, minimumSize: const Size(220, 50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            onPressed: ok
                ? () => setState(() {
                      _step = 1;
                      if (_selectedTeam == null || (_selectedTeam!.league != 'CL' && _selectedTeam!.league != 'PL')) _selectedTeamId = null;
                    })
                : null,
            child: Text(ok ? '次へ（自球団を選ぶ）' : '両リーグ6球団ずつにしてください', style: const TextStyle(fontWeight: FontWeight.w900)),
          ),
        ),
      ],
    );
    return wide ? SingleChildScrollView(child: col) : col;
  }

  Widget _teamStep(List<Team> teams, bool wide) {
    final leagues = teams.map((t) => t.league).toSet().toList()..sort();
    final shown = teams.where((t) => t.league == _league || !leagues.contains(_league)).toList();
    final list = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [for (final t in shown) _teamRow(t)],
    );
    final preview = _selectedTeam != null ? _teamPreview(_selectedTeam!) : const SizedBox.shrink();
    final header = Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: 10,
      spacing: 12,
      children: [
        _heading('STEP 2　自球団を選ぶ'),
        SegmentedButton<String>(
          segments: [for (final lg in leagues) ButtonSegment(value: lg, label: Text(leagueLabel(lg)))],
          selected: {leagues.contains(_league) ? _league : leagues.first},
          showSelectedIcon: false,
          onSelectionChanged: (v) => setState(() => _league = v.first),
        ),
      ],
    );
    if (wide) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        header,
        const SizedBox(height: 18),
        Expanded(
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: SingleChildScrollView(child: list)),
            const SizedBox(width: 20),
            SizedBox(width: 340, child: SingleChildScrollView(child: preview)),
          ]),
        ),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [header, const SizedBox(height: 12), list, const SizedBox(height: 12), preview]);
  }

  Widget _teamRow(Team t) {
    final sel = t.id == _selectedTeamId;
    final color = teamColor(app.teams, t);
    final ovr = _avg(t.lineup.map((l) => _p(t, l.playerId)?.ovr ?? 0));
    final g = GradeUtils.getGrade(ovr);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: sel ? const Color(0xFFFFFBEB) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: sel ? _gold : const Color(0xFFE2E8F0), width: sel ? 2 : 1)),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => setState(() => _selectedTeamId = t.id),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(children: [
              Container(width: 36, height: 36, alignment: Alignment.center, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)), child: Text(teamInitial(t), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900))),
              const SizedBox(width: 14),
              Expanded(child: Text(t.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15), overflow: TextOverflow.ellipsis)),
              Text(g, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: AppTheme.getGradeColor(g))),
              const SizedBox(width: 4),
              Text('$ovr', style: const TextStyle(fontSize: 16)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _teamPreview(Team t) {
    final fielders = _avg(t.lineup.map((l) => _p(t, l.playerId)?.ovr ?? 0));
    final pitchers = _avg(t.activeRotation.where((e) => e.isNotEmpty).map((id) => _p(t, id)?.ovr ?? 0));
    final pay = t.players.fold<int>(0, (s, p) => s + p.salary);
    String nameOf(String? id) {
      final p = id == null ? null : _p(t, id);
      return p == null ? '−' : '${p.listName}　${GradeUtils.getGrade(p.ovr)} ${p.ovr}';
    }

    final ace = t.activeRotation.where((e) => e.isNotEmpty).map((id) => _p(t, id)).whereType<dynamic>().toList()..sort((a, b) => b.ovr.compareTo(a.ovr));
    final cleanup = t.lineup.length >= 4 ? t.lineup[3].playerId : null;
    Widget stat(String k, String v, [String? g]) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(10)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(k, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
              Row(children: [
                if (g != null) Text('$g ', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: AppTheme.getGradeColor(g))),
                Flexible(child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(v, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)))),
              ]),
            ]),
          ),
        );
    Widget line(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [Text(k, style: const TextStyle(color: Color(0xFF64748B))), const Spacer(), Flexible(child: Text(v, style: const TextStyle(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis))]),
        );
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE2E8F0)), borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(height: 8, decoration: BoxDecoration(color: teamColor(app.teams, t), borderRadius: BorderRadius.circular(4))),
        const SizedBox(height: 12),
        Text(t.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
        Text('${leagueLabel(t.league)}　選手${t.players.length}人', style: const TextStyle(color: Color(0xFF64748B), fontSize: 12)),
        const SizedBox(height: 12),
        Row(children: [
          stat('野手', '$fielders', GradeUtils.getGrade(fielders)),
          const SizedBox(width: 8),
          stat('投手', '$pitchers', GradeUtils.getGrade(pitchers)),
          const SizedBox(width: 8),
          stat('年俸総額', formatSalary(pay)),
        ]),
        const SizedBox(height: 8),
        line('エース', ace.isNotEmpty ? nameOf(ace.first.id) : '−'),
        const Divider(height: 1),
        line('4番', nameOf(cleanup)),
        const Divider(height: 1),
        line('守護神', nameOf(t.winningPattern.length > 2 ? t.winningPattern[2] : null)),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: OutlinedButton(style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), onPressed: () => setState(() => _step = 0), child: const Text('戻る'))),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _green, minimumSize: const Size.fromHeight(48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: () => setState(() => _step = 2),
              child: const Text('この球団で次へ', style: TextStyle(fontWeight: FontWeight.w900)),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _confirmStep(bool wide) {
    final t = _selectedTeam;
    // 見出しの下に選ぶボタン（スマホでも窮屈にならない）
    Widget sec(String title, Widget child, {String? note}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF334155))),
            const SizedBox(height: 6),
            child,
            if (note != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(note, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)))),
          ]),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _heading('STEP 3　開始年度・試合数・資金'),
        const SizedBox(height: 10),
        if (t != null)
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFE2E8F0))),
            child: Row(children: [
              Container(width: 6, height: 34, color: teamColor(app.teams, t)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                  Text(leagueLabel(t.league), style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                ]),
              ),
            ]),
          ),
        Container(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            sec(
              '開始年度',
              ChipGrid<int>(items: [for (final y in const [2024, 2025, 2026, 2027, 2028]) (y, '$y年')], selected: _selectedYear, minWidth: 60, padding: EdgeInsets.zero, selectedColor: _green, onSelect: (y) => setState(() => _selectedYear = y)),
              note: '監督就任は前年10月31日（ドラフト会議の日）から',
            ),
            const Divider(height: 1),
            sec(
              '公式戦の試合数',
              ChipGrid<int>(items: const [(120, '120試合 短期'), (143, '143試合 標準'), (156, '156試合 タフ')], selected: _games, minWidth: 90, padding: EdgeInsets.zero, selectedColor: _green, onSelect: (g) => setState(() => _games = g)),
            ),
            const Divider(height: 1),
            sec(
              '初期の資金',
              Row(children: [
                IconButton(onPressed: _funds > 50 ? () => setState(() => _funds -= 10) : null, icon: const Icon(Icons.remove_circle_outline)),
                Text('$_funds億円', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                IconButton(onPressed: _funds < 200 ? () => setState(() => _funds += 10) : null, icon: const Icon(Icons.add_circle_outline)),
              ]),
              note: '50〜200億円。他球団は150億円',
            ),
          ]),
        ),
        if (!widget.newOnly) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFFECACA))),
            child: Text('このプレイデータ（${app.slot}）の成績・試合結果・移籍はすべてリセットされます', style: const TextStyle(color: Color(0xFFB91C1C), fontSize: 12.5)),
          ),
        ],
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: OutlinedButton(style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), onPressed: () => setState(() => _step = 1), child: const Text('戻る'))),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: widget.newOnly ? _green : const Color(0xFFB91C1C), minimumSize: const Size.fromHeight(50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: t == null ? null : _startNew,
              child: Text(widget.newOnly ? 'この内容で始める' : 'この内容ではじめから', style: const TextStyle(fontWeight: FontWeight.w900)),
            ),
          ),
        ]),
      ],
    );
  }

  // ---------------- 補助 ----------------
  dynamic _p(Team t, String id) {
    for (final p in t.players) {
      if (p.id == id) return p;
    }
    return null;
  }

  int _avg(Iterable<int> xs) {
    final l = xs.where((x) => x > 0).toList();
    if (l.isEmpty) return 0;
    return (l.reduce((a, b) => a + b) / l.length).round();
  }
}
