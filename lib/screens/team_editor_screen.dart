import 'dart:convert';
import 'package:flutter/material.dart';
import '../providers/app_state.dart';
import '../models/team.dart';
import '../models/stadium.dart';
import '../models/player.dart';
import '../utils/app_theme.dart';
import '../utils/grade_utils.dart';
import '../widgets/initial_data_export.dart';
import '../widgets/player_editor.dart';
import '../widgets/condition_face.dart';

/// 初期選手編集（デザイン案B：レポート編集）
///  左：球団の基本情報と、守備位置ごとの選手一覧（検索つき）
///  右：選んだ選手をレポートの見た目のまま編集
///  狭い画面では、上の「選手を選ぶ」から一覧を開く
class TeamEditorScreen extends StatefulWidget {
  final AppState appState;
  final Team team;
  const TeamEditorScreen({Key? key, required this.appState, required this.team}) : super(key: key);

  @override
  State<TeamEditorScreen> createState() => _TeamEditorScreenState();
}

const _ink = Color(0xFF1C1917);
const _sub = Color(0xFF78716C);
const _line = Color(0xFFE7E5E4);

class _TeamEditorScreenState extends State<TeamEditorScreen> {
  /// null＝球団の基本情報
  Player? _selected;
  String _query = '';

  Team get team => widget.team;

  /// 変えた選手（'team' は球団の基本情報）。セーブするまでは保存しない（まとめてセーブ）
  final Set<String> _dirty = {};
  /// 開いたとき（と最後にセーブしたとき）の球団。「セーブせずに戻る」でここに戻す
  late String _snapshot = jsonEncode(team.toJson());

  void _changed() {
    setState(() => _dirty.add(_selected?.id ?? 'team'));
  }

  /// 球団の基本情報を変えた（入力中でも安全に印を付ける）
  void _markTeam() {
    if (_dirty.add('team')) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    }
  }

  /// 変更をまとめてセーブ（画面はそのまま）
  /// 変えたものの説明（例：選手3人・球団の基本情報）
  String _what() {
    final n = _dirty.where((x) => x != 'team').length;
    return [if (n > 0) '選手$n人', if (_dirty.contains('team')) '球団の基本情報'].join('・');
  }

  /// この球団の今の状態（選手・設定）を「初期状態」にする。新しいデータ（はじめから）はこの状態から始まる
  Future<void> _setInitial() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('初期状態にする'),
        content: Text('${team.name} の今の選手・設定を「初期状態」にします。新しいデータ（はじめから）では、この状態から始まります。\n（試合を進めたあとだと、移籍で入った選手もそのまま初期状態に入ります）'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('やめる')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('初期状態にする')),
        ],
      ),
    );
    if (ok != true) return;
    if (_dirty.isNotEmpty) _saveAll();
    await widget.appState.saveInitialState(team);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${team.name} の今の状態を初期状態にしました')));
  }

  void _saveAll() {
    if (_dirty.isEmpty) return;
    final what = _what();
    widget.appState.updateAndSave();
    _snapshot = jsonEncode(team.toJson());
    setState(() => _dirty.clear());
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('セーブしました（$what）')));
  }

  /// セーブせずに戻す：開いたときの状態に球団を作り直す
  void _discard() {
    final t = Team.fromJson(jsonDecode(_snapshot) as Map<String, dynamic>, Player.fromJson);
    final teams = widget.appState.teams;
    final i = teams.indexOf(team);
    if (i >= 0) teams[i] = t;
  }

  /// 戻るとき：セーブしていない変更があれば聞く
  Future<void> _leave() async {
    if (_dirty.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    final a = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('セーブしていない変更があります'),
        content: Text('${_what()}を変えています。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, 'cancel'), child: const Text('編集を続ける')),
          TextButton(onPressed: () => Navigator.pop(c, 'discard'), child: const Text('セーブせずに戻る', style: TextStyle(color: Colors.red))),
          FilledButton(onPressed: () => Navigator.pop(c, 'save'), child: const Text('セーブして戻る')),
        ],
      ),
    );
    if (!mounted || a == null || a == 'cancel') return;
    if (a == 'save') {
      _saveAll();
    } else {
      _discard();
      _dirty.clear();
    }
    Navigator.of(context).pop();
  }

  /// 一覧の見出し：9つの守備位置（主な守備位置で分ける）
  static const _positions = ['投手', '捕手', '一塁手', '二塁手', '三塁手', '遊撃手', '左翼手', '中堅手', '右翼手'];

  List<(String, List<Player>)> _groups() {
    final q = _query.trim();
    bool hit(Player p) => q.isEmpty || '${p.lastName}${p.firstName}'.contains(q) || p.registeredName.contains(q) || p.uniformText == q;
    final map = <String, List<Player>>{for (final k in _positions) k: []};
    for (final p in team.players.where(hit)) {
      map[p.isPitcher ? '投手' : (map.containsKey(p.mainPosition) ? p.mainPosition : '一塁手')]!.add(p);
    }
    for (final l in map.values) {
      l.sort(compareByUniform);
    }
    return [for (final e in map.entries) if (e.value.isNotEmpty) (e.key, e.value)];
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
      backgroundColor: const Color(0xFFF5F5F4),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _ink,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: _leave),
        title: Text('${team.name}　初期選手編集', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.flag_outlined, size: 18),
            label: const Text('初期状態にする'),
            onPressed: _setInitial,
          ),
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            tooltip: '固有12の初期データを書き出し（開発者用）',
            onPressed: () => showInitialDataExport(context, widget.appState),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              onPressed: _dirty.isEmpty ? null : _saveAll,
              style: FilledButton.styleFrom(backgroundColor: _ink, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              child: Text(_dirty.isEmpty ? 'セーブ済み' : 'まとめてセーブ（${_dirty.length}）'),
            ),
          ),
        ],
      ),
      body: LayoutBuilder(builder: (context, c) {
        final wide = c.maxWidth >= 860;
        final main = _selected == null
            ? _teamSettings()
            : PlayerEditor(key: ValueKey(_selected!.id), player: _selected!, appState: widget.appState, onChanged: _changed);
        if (wide) {
          return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              width: 270,
              decoration: const BoxDecoration(color: Colors.white, border: Border(right: BorderSide(color: _line))),
              child: _playerList(),
            ),
            Expanded(child: main),
          ]);
        }
        return Column(children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: OutlinedButton.icon(
              onPressed: _openListSheet,
              icon: const Icon(Icons.people_alt_outlined),
              label: Text(_selected == null ? '球団の基本情報（タップで選手を選ぶ）' : '#${_selected!.uniformText} ${_selected!.listName}（タップで選手を選ぶ）', overflow: TextOverflow.ellipsis),
              style: OutlinedButton.styleFrom(foregroundColor: _ink, minimumSize: const Size.fromHeight(44), alignment: Alignment.centerLeft),
            ),
          ),
          Expanded(child: main),
        ]);
      }),
    ),
    );
  }

  void _openListSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.8,
        child: StatefulBuilder(builder: (ctx, setSheet) => _playerList(onPicked: () => Navigator.of(ctx).pop(), refresh: () => setSheet(() {}))),
      ),
    );
  }

  Widget _playerList({VoidCallback? onPicked, VoidCallback? refresh}) {
    final groups = _groups();
    void pick(Player? p) {
      setState(() => _selected = p);
      onPicked?.call();
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
        child: TextField(
          decoration: const InputDecoration(
            labelText: '選手を探す（名前・背番号）',
            isDense: true,
            prefixIcon: Icon(Icons.search, size: 20),
            border: OutlineInputBorder(),
          ),
          onChanged: (s) {
            setState(() => _query = s);
            refresh?.call();
          },
        ),
      ),
      Expanded(
        child: ListView(children: [
          _listTile(
            selected: _selected == null,
            onTap: () => pick(null),
            child: const Row(children: [Icon(Icons.flag_outlined, size: 18, color: _sub), SizedBox(width: 8), Text('球団の基本情報', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700))]),
          ),
          for (final g in groups) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text('${g.$1}（${g.$2.length}）', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: _sub)),
            ),
            for (final p in g.$2)
              _listTile(
                selected: identical(_selected, p),
                onTap: () => pick(p),
                child: Row(children: [
                  SizedBox(width: 30, child: Text(p.uniformText, style: const TextStyle(fontSize: 12.5, color: _sub))),
                  ConditionFace(level: p.conditionAt(widget.appState.currentDate), size: 15),
                  const SizedBox(width: 6),
                  Expanded(child: Text(p.listName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5))),
                  if (_dirty.contains(p.id)) const Padding(padding: EdgeInsets.only(right: 4), child: Icon(Icons.edit, size: 13, color: Color(0xFFEA580C))),
                  if (!team.roster1G.contains(p.id)) const Padding(padding: EdgeInsets.only(right: 6), child: Text('2軍', style: TextStyle(fontSize: 10.5, color: _sub))),
                  Text(GradeUtils.getGrade(p.ovr), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5, color: AppTheme.getGradeColor(GradeUtils.getGrade(p.ovr)))),
                  SizedBox(width: 24, child: Text('${p.ovr}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12.5))),
                ]),
              ),
          ],
        ]),
      ),
    ]);
  }

  Widget _listTile({required bool selected, required VoidCallback onTap, required Widget child}) => Material(
        color: selected ? const Color(0xFFFEF3C7) : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Container(height: 38, padding: const EdgeInsets.symmetric(horizontal: 16), alignment: Alignment.centerLeft, child: child),
        ),
      );

  Widget _teamSettings() {
    InputDecoration deco(String l) => InputDecoration(labelText: l, border: const OutlineInputBorder(), isDense: true);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              padding: const EdgeInsets.only(bottom: 10),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _ink, width: 2))),
              child: const Text('球団の基本情報', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
            ),
            const SizedBox(height: 20),
            TextFormField(
              initialValue: team.year.toString(),
              decoration: deco('年度タグ (例: 2026)'),
              keyboardType: TextInputType.number,
              onChanged: (val) {
                final v = int.tryParse(val);
                if (v != null) {
                  team.year = v;
                  _markTeam();
                }
              },
            ),
            const SizedBox(height: 14),
            TextFormField(initialValue: team.name, decoration: deco('球団名'), onChanged: (val) {
              team.name = val;
              _changed();
            }),
            const SizedBox(height: 14),
            TextFormField(initialValue: team.shortName, decoration: deco('略球団名 (例: 阪神)'), onChanged: (val) {
              team.shortName = val;
              _markTeam();
            }),
            const SizedBox(height: 14),
            TextFormField(initialValue: team.initialName, decoration: deco('1文字球団名 (例: 神)'), onChanged: (val) {
              team.initialName = val;
              _markTeam();
            }),
            const SizedBox(height: 14),
            // 本拠地：ホームの試合はこの球場で行う（広さ・フェンス・屋根・風が打球に効く）
            DropdownButtonFormField<String>(
              initialValue: team.homeStadium,
              decoration: deco('本拠地の球場（ホームの試合で使う）'),
              items: [
                for (final st in Stadium.all)
                  DropdownMenuItem(value: st.id, child: Text('${st.name}（両翼${st.fenceDistance(-45).toStringAsFixed(0)}m・中堅${st.fenceDistance(0).toStringAsFixed(0)}m・${st.roof}）')),
              ],
              onChanged: (v) => setState(() {
                team.stadiumId = v ?? '';
                _markTeam();
              }),
            ),
            const SizedBox(height: 14),
            // ユニフォームの色・胸のロゴ（顔アイコンのユニフォーム、順位表などの球団の色）
            TextFormField(
              initialValue: team.logo,
              decoration: deco('胸のロゴ（英語のチーム名。例：Titans）'),
              onChanged: (v) {
                team.logoText = v.trim();
                _markTeam();
              },
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              const Text('ユニフォームの色', style: TextStyle(fontSize: 13)),
              for (final c in const [0, 0xFFF97316, 0xFFF2A900, 0xFFEAB308, 0xFFDC2626, 0xFFB91C1C, 0xFF2563EB, 0xFF1E3A8A, 0xFF0EA5E9, 0xFF16A34A, 0xFF0E7490, 0xFF9333EA, 0xFF111827, 0xFF64748B])
                InkWell(
                  onTap: () => setState(() {
                    team.uniformColor = c;
                    _dirty.add('team');
                  }),
                  child: Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: c == 0 ? Colors.white : Color(c),
                      shape: BoxShape.circle,
                      border: Border.all(color: team.uniformColor == c ? Colors.black : const Color(0xFFCBD5E1), width: team.uniformColor == c ? 3 : 1),
                    ),
                    child: c == 0 ? const Text('自動', style: TextStyle(fontSize: 9)) : null,
                  ),
                ),
            ]),
            const SizedBox(height: 14),
            // 本拠地の所在地（都道府県）：初期値は本拠地の球場の所在地。天候（気温・梅雨・台風）の地域差に使う
            DropdownButtonFormField<String>(
              key: ValueKey('pref-${team.id}-${team.homeStadium}'),
              initialValue: team.homePrefecture,
              decoration: deco('本拠地の所在地（都道府県）'),
              items: [for (final p in Stadium.prefectures) DropdownMenuItem(value: p, child: Text(p))],
              onChanged: (v) => setState(() {
                team.prefecture = v ?? '';
                _markTeam();
              }),
            ),
            const SizedBox(height: 18),
            Text('選手 ${team.players.length}人（1軍 ${team.roster1G.length}人）　左の一覧から選ぶと編集できます', style: const TextStyle(fontSize: 12.5, color: _sub)),
          ]),
        ),
      ),
    );
  }
}
