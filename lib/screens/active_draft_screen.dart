import 'package:flutter/material.dart';
import '../models/player.dart';
import '../providers/app_state.dart';
import '../utils/standings.dart';
import '../widgets/player_detail_dialog.dart' show showPlayerDetail;

const _navy = Color(0xFF0B1626);
const _lime = Color(0xFFC6F24E);
const _sub = Color(0xFF78716C);
const _line = Color(0xFFE7E5E4);

/// 現役ドラフト画面：
/// ステップ1：自球団から最低20名を放出候補として選出（選ばなかった主力・若手は守られる）
/// ステップ2：他球団の提出リストから1名指名して実行
class ActiveDraftScreen extends StatefulWidget {
  final AppState app;
  const ActiveDraftScreen({super.key, required this.app});

  @override
  State<ActiveDraftScreen> createState() => _ActiveDraftScreenState();
}

class _ActiveDraftScreenState extends State<ActiveDraftScreen> {
  int _step = 0; // 0=自球団の放出候補選出, 1=他球団から指名
  String _posFilter = '全て';
  late final Set<String> _myPoolIds = {
    for (final p in widget.app.activeDraftDefaultMyPool()) p.id,
  };
  Player? _sel;

  AppState get app => widget.app;

  bool _matchPos(Player p) {
    if (_posFilter == '全て') return true;
    if (_posFilter == '投手') return p.isPitcher;
    if (_posFilter == '捕手') return p.mainPosition == '捕手';
    if (_posFilter == '内野') return const {'一塁手', '二塁手', '三塁手', '遊撃手'}.contains(p.mainPosition);
    if (_posFilter == '外野') return const {'左翼手', '中堅手', '右翼手'}.contains(p.mainPosition);
    return true;
  }

  String _statSummary(Player p) {
    final s = p.seasonStats;
    final hasSeason = s.games > 0 || s.pitchApps > 0 || s.inningsPitched > 0;
    if (!hasSeason) {
      return p.isPitcher ? '前季1軍 ${p.prevInnings ~/ 3}回' : '前季1軍 ${p.prevGames}試合';
    }
    if (p.isPitcher) {
      return '${s.apps}登板 ${s.inningsPitched ~/ 3}回 ${s.wins}勝${s.losses}敗 防${s.inningsPitched == 0 ? '-' : s.era.toStringAsFixed(2)}';
    }
    return '${s.games}試合 ${s.atBats}打数 打率${s.atBats == 0 ? '-' : s.battingAverage.toStringAsFixed(3).replaceFirst('0.', '.')} ${s.homeRuns}本';
  }

  Future<void> _run() async {
    final lines = app.runActiveDraft(_sel, myPoolIds: _myPoolIds);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('現役ドラフトの結果'),
        content: SizedBox(
          width: 420,
          child: lines.isEmpty
              ? const Text('移籍はありませんでした')
              : SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final l in lines)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Text(l, style: const TextStyle(fontSize: 13)),
                        ),
                    ],
                  ),
                ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
      ),
    );
    if (mounted) Navigator.pop(context);
  }

  Widget _posChips() {
    const filters = ['全て', '投手', '捕手', '内野', '外野'];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
      child: Row(children: [
        for (final f in filters)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              label: Text(f, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              selected: _posFilter == f,
              onSelected: (_) => setState(() => _posFilter = f),
              visualDensity: VisualDensity.compact,
            ),
          ),
      ]),
    );
  }

  Widget _step1SelectPool() {
    final my = app.myTeam;
    final eligible = app.activeDraftMyEligible();
    final req = my == null ? 0 : app.activeDraftRequiredCount(my);
    final filtered = eligible.where(_matchPos).toList();
    final ok = _myPoolIds.length >= req;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        margin: const EdgeInsets.fromLTRB(12, 10, 12, 4),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(10), border: Border.all(color: _line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(
                '① 自球団の放出候補を選出（最低$req名）',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: _navy),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: ok ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '選択中 ${_myPoolIds.length} / 最低$req名',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: ok ? const Color(0xFF166534) : const Color(0xFFB45309)),
              ),
            ),
          ]),
          const SizedBox(height: 4),
          const Text(
            '支配下・日本人扱い・FA権なし（新規入団除く）から最低20名を提出します。選ばなかった主力・若手は他球団に指名されません。',
            style: TextStyle(fontSize: 11.5, color: _sub),
          ),
          const SizedBox(height: 6),
          Row(children: [
            OutlinedButton.icon(
              onPressed: () => setState(() {
                _myPoolIds
                  ..clear()
                  ..addAll(app.activeDraftDefaultMyPool().map((p) => p.id));
              }),
              icon: const Icon(Icons.auto_fix_high, size: 16),
              label: Text('おまかせ選出（$req名）', style: const TextStyle(fontSize: 12)),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => setState(() => _myPoolIds.clear()),
              child: const Text('すべて解除', style: TextStyle(fontSize: 12)),
            ),
          ]),
        ]),
      ),
      _posChips(),
      const Divider(height: 1),
      Expanded(
        child: filtered.isEmpty
            ? const Center(child: Text('該当する選手がいません', style: TextStyle(color: _sub)))
            : ListView.separated(
                itemCount: filtered.length,
                separatorBuilder: (_, _) => const Divider(height: 1, color: _line),
                itemBuilder: (_, i) {
                  final p = filtered[i];
                  final checked = _myPoolIds.contains(p.id);
                  return CheckboxListTile(
                    dense: true,
                    value: checked,
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        _myPoolIds.add(p.id);
                      } else {
                        _myPoolIds.remove(p.id);
                      }
                    }),
                    title: Row(children: [
                      Expanded(
                        child: InkWell(
                          onTap: () => showPlayerDetail(context, app, p, allowActions: false),
                          child: Text(
                            '${p.registeredName}（${p.mainPosition}・${p.age}歳・プロ${p.proYears}年）',
                            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: _navy, decoration: TextDecoration.underline, decorationColor: Color(0xFFCBD5E1)),
                          ),
                        ),
                      ),
                    ]),
                    subtitle: Text(
                      'OVR ${p.ovr} / 年俸${p.salary}万 / ${_statSummary(p)}',
                      style: const TextStyle(fontSize: 11.5, color: _sub),
                    ),
                    secondary: IconButton(
                      icon: const Icon(Icons.info_outline, size: 18, color: _sub),
                      onPressed: () => showPlayerDetail(context, app, p, allowActions: false),
                    ),
                  );
                },
              ),
      ),
      SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton(
            onPressed: ok ? () => setState(() => _step = 1) : null,
            style: FilledButton.styleFrom(backgroundColor: _navy, foregroundColor: _lime, padding: const EdgeInsets.symmetric(vertical: 14)),
            child: Text(
              ok ? '提出リストを確定して指名へ（${_myPoolIds.length}名）' : 'あと${req - _myPoolIds.length}名選んでください',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ),
    ]);
  }

  Widget _step2PickOther() {
    final all = app.activeDraftCandidates().where(_matchPos).toList();
    String teamOf(Player p) {
      for (final t in app.leagueTeams) {
        if (t.players.any((x) => x.id == p.id)) return teamShort(t);
      }
      return '';
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        margin: const EdgeInsets.fromLTRB(12, 10, 12, 4),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(10), border: Border.all(color: _line)),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('② 他球団の提出リストから1名指名', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: _navy)),
              Text('自球団からは ${_myPoolIds.length}名 を提出済み（各球団の候補から1人ずつ入れ替わり）', style: const TextStyle(fontSize: 11.5, color: _sub)),
            ]),
          ),
          TextButton.icon(
            onPressed: () => setState(() => _step = 0),
            icon: const Icon(Icons.arrow_back, size: 16),
            label: const Text('選び直す', style: TextStyle(fontSize: 12)),
          ),
        ]),
      ),
      _posChips(),
      const Divider(height: 1),
      Expanded(
        child: all.isEmpty
            ? const Center(child: Text('該当する候補がいません', style: TextStyle(color: _sub)))
            : ListView.separated(
                itemCount: all.length,
                separatorBuilder: (_, _) => const Divider(height: 1, color: _line),
                itemBuilder: (_, i) {
                  final p = all[i];
                  final picked = _sel?.id == p.id;
                  return ListTile(
                    dense: true,
                    selected: picked,
                    selectedTileColor: const Color(0xFFECFCCB),
                    onTap: () => setState(() => _sel = picked ? null : p),
                    title: InkWell(
                      onTap: () => showPlayerDetail(context, app, p, allowActions: false),
                      child: Text(
                        '${p.registeredName}（${teamOf(p)}・${p.mainPosition}・${p.age}歳）',
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: _navy, decoration: TextDecoration.underline, decorationColor: Color(0xFFCBD5E1)),
                      ),
                    ),
                    subtitle: Text('OVR ${p.ovr} / 年俸${p.salary}万 / ${_statSummary(p)}', style: const TextStyle(fontSize: 11.5, color: _sub)),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        icon: const Icon(Icons.info_outline, size: 18, color: _sub),
                        onPressed: () => showPlayerDetail(context, app, p, allowActions: false),
                      ),
                      if (picked) const Icon(Icons.check_circle, color: Color(0xFF15803D)),
                    ]),
                  );
                },
              ),
      ),
      SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton(
            onPressed: _run,
            style: FilledButton.styleFrom(backgroundColor: _navy, foregroundColor: _lime, padding: const EdgeInsets.symmetric(vertical: 14)),
            child: Text(
              _sel == null ? '指名はおまかせで現役ドラフトを行う' : '${_sel!.registeredName} を指名して現役ドラフトを行う',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        title: const Text('現役ドラフト（最低20名選出方式）', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
      ),
      body: _step == 0 ? _step1SelectPool() : _step2PickOther(),
    );
  }
}
