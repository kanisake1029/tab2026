import 'package:flutter/material.dart';
import '../engine/transfer_engine.dart';
import '../models/player.dart';
import '../models/team.dart';
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
  int _step = 0; // 0=自球団の放出候補選出, 1=事前入札, 2=1巡目・連鎖指名
  String _posFilter = '全て';
  late final Set<String> _myPoolIds = {
    for (final p in widget.app.activeDraftDefaultMyPool()) p.id,
  };
  Player? _preBidSel;
  Player? _roundPickSel;

  // 1巡目・連鎖指名の進行状態
  List<Team> _order = const [];
  Map<String, List<Player>> _pools = const {};
  Map<String, int> _votes = const {};
  Team? _firstTeam;
  Team? _curTeam;
  final Set<String> _picked = {};
  final Set<String> _lost = {};
  final Set<String> _takenIds = {};
  final List<(Team, Team, Player)> _moves = [];
  final List<String> _turnLogs = [];
  bool _committed = false;

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

  void _startRound1() {
    final order = app.activeDraftOrder();
    final pools = app.buildActiveDraftPools(myPoolIds: _myPoolIds);
    final preBids = app.buildActiveDraftPreBids(order, pools, myPreBid: _preBidSel);
    final votes = TransferEngine.tallyActiveDraftVotes(order, preBids);
    final first = TransferEngine.activeDraftFirstTeam(order, votes);
    setState(() {
      _order = order;
      _pools = pools;
      _votes = votes;
      _firstTeam = first;
      _curTeam = first;
      _picked.clear();
      _lost.clear();
      _takenIds.clear();
      _moves.clear();
      _turnLogs.clear();
      _roundPickSel = null;
      _committed = false;
      _posFilter = '全て';
      _step = 2;
    });
    _advanceCpuTurns();
  }

  void _recordPick(Team me, Player? p) {
    _picked.add(me.id);
    Team? next;
    if (p != null) {
      final from = _order.firstWhere((t) => t.players.any((x) => x.id == p.id));
      _lost.add(from.id);
      _takenIds.add(p.id);
      _moves.add((from, me, p));
      final isLoop = _picked.contains(from.id);
      if (!isLoop) {
        next = from;
      } else {
        next = _order.where((t) => !_picked.contains(t.id)).firstOrNull;
      }
      _turnLogs.add(
        '${_moves.length}. ${teamShort(me)} → ${p.registeredName}（${teamShort(from)}・${p.mainPosition}）'
        '${isLoop && next != null ? ' ［ループ→逆ウェーバーで${teamShort(next)}へ］' : ''}',
      );
    } else {
      next = _order.where((t) => !_picked.contains(t.id)).firstOrNull;
      _turnLogs.add('・${teamShort(me)}：指名見送り');
    }
    _curTeam = next;
  }

  void _advanceCpuTurns() {
    while (_curTeam != null && _curTeam!.id != app.myTeamId && _picked.length < _order.length) {
      final me = _curTeam!;
      final cands = TransferEngine.activeDraftTurnCandidates(
        picker: me,
        order: _order,
        teamPools: _pools,
        picked: _picked,
        lost: _lost,
        takenPlayerIds: _takenIds,
      );
      final p = app.pickActiveDraftCpu(me, cands);
      _recordPick(me, p);
    }
    if (_curTeam == null && !_committed) {
      _committed = true;
      app.commitActiveDraftMoves(_moves);
    }
    if (mounted) setState(() {});
  }

  void _pickForMyTeam(List<Player> validCands) {
    final me = _curTeam;
    if (me == null || me.id != app.myTeamId) return;
    final p = (_roundPickSel != null && validCands.any((x) => x.id == _roundPickSel!.id))
        ? validCands.firstWhere((x) => x.id == _roundPickSel!.id)
        : app.pickActiveDraftCpu(me, validCands);
    _recordPick(me, p);
    _roundPickSel = null;
    _advanceCpuTurns();
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
              ok ? '提出リストを確定して事前入札へ（${_myPoolIds.length}名）' : 'あと${req - _myPoolIds.length}名選んでください',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ),
    ]);
  }

  String _teamOf(Player p) {
    for (final t in app.leagueTeams) {
      if (t.players.any((x) => x.id == p.id)) return teamShort(t);
    }
    return '';
  }

  Widget _step2PreBid() {
    final all = app.activeDraftCandidates().where(_matchPos).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        margin: const EdgeInsets.fromLTRB(12, 10, 12, 4),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(10), border: Border.all(color: _line)),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('② 事前入札（人気投票）', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: _navy)),
              Text(
                '自球団からは ${_myPoolIds.length}名 を提出済み。1巡目のみ実施し、「自球団の選手に入った票の総和」が1位の球団から連鎖指名します（ループ時は逆ウェーバー順、同一球団からは1名のみ）。',
                style: const TextStyle(fontSize: 11.5, color: _sub),
              ),
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
                  final picked = _preBidSel?.id == p.id;
                  return ListTile(
                    dense: true,
                    selected: picked,
                    selectedTileColor: const Color(0xFFECFCCB),
                    onTap: () => setState(() => _preBidSel = picked ? null : p),
                    title: InkWell(
                      onTap: () => showPlayerDetail(context, app, p, allowActions: false),
                      child: Text(
                        '${p.registeredName}（${_teamOf(p)}・${p.mainPosition}・${p.age}歳）',
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: _navy, decoration: TextDecoration.underline, decorationColor: Color(0xFFCBD5E1)),
                      ),
                    ),
                    subtitle: Text('OVR ${p.ovr} / 年俸${p.salary}万 / ${_statSummary(p)}', style: const TextStyle(fontSize: 11.5, color: _sub)),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        icon: const Icon(Icons.info_outline, size: 18, color: _sub),
                        onPressed: () => showPlayerDetail(context, app, p, allowActions: false),
                      ),
                      if (picked) const Icon(Icons.how_to_vote, color: Color(0xFF15803D)),
                    ]),
                  );
                },
              ),
      ),
      SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton(
            onPressed: _startRound1,
            style: FilledButton.styleFrom(backgroundColor: _navy, foregroundColor: _lime, padding: const EdgeInsets.symmetric(vertical: 14)),
            child: Text(
              _preBidSel == null ? 'おまかせ事前入札で1巡目を開始' : '${_preBidSel!.registeredName} に事前入札して1巡目を開始',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ),
    ]);
  }

  Widget _voteSummaryBanner() {
    final sorted = List.of(_order)..sort((a, b) => (_votes[b.id] ?? 0).compareTo(_votes[a.id] ?? 0));
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(10), border: Border.all(color: _line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          '③ 1巡目・連鎖指名${_firstTeam == null ? '' : '（事前入札1位：${teamShort(_firstTeam!)}から開始）'}',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: _navy),
        ),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 4, children: [
          for (final t in sorted)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: t.id == _firstTeam?.id ? const Color(0xFFECFCCB) : Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: t.id == app.myTeamId ? _navy : _line),
              ),
              child: Text(
                '${teamShort(t)} ${_votes[t.id] ?? 0}票',
                style: TextStyle(fontSize: 11, fontWeight: t.id == _firstTeam?.id || t.id == app.myTeamId ? FontWeight.w900 : FontWeight.w500),
              ),
            ),
        ]),
        if (_lost.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            '指名済み球団（同一球団から2人目は不可）：${_order.where((t) => _lost.contains(t.id)).map(teamShort).join('・')}',
            style: const TextStyle(fontSize: 11, color: _sub),
          ),
        ],
      ]),
    );
  }

  Widget _step3Round1() {
    if (_committed || _curTeam == null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _voteSummaryBanner(),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            children: [
              const Text('1巡目の指名結果（全12球団）', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: _navy)),
              const SizedBox(height: 6),
              if (_turnLogs.isEmpty)
                const Text('移籍はありませんでした', style: TextStyle(color: _sub))
              else
                for (final l in _turnLogs)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(l, style: const TextStyle(fontSize: 13)),
                  ),
            ],
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: FilledButton(
              onPressed: () => Navigator.pop(context),
              style: FilledButton.styleFrom(backgroundColor: _navy, foregroundColor: _lime, padding: const EdgeInsets.symmetric(vertical: 14)),
              child: const Text('完了して戻る', style: TextStyle(fontWeight: FontWeight.w900)),
            ),
          ),
        ),
      ]);
    }

    final me = _curTeam!;
    final validCands = TransferEngine.activeDraftTurnCandidates(
      picker: me,
      order: _order,
      teamPools: _pools,
      picked: _picked,
      lost: _lost,
      takenPlayerIds: _takenIds,
    );
    final filtered = validCands.where(_matchPos).toList()..sort((a, b) => b.ovr.compareTo(a.ovr));

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _voteSummaryBanner(),
      if (_turnLogs.isNotEmpty)
        Container(
          constraints: const BoxConstraints(maxHeight: 110),
          margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: _line)),
          child: ListView(
            children: [
              for (final l in _turnLogs) Text(l, style: const TextStyle(fontSize: 11.5, color: _sub)),
            ],
          ),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
        child: Text(
          'あなたの番（${teamShort(me)}）：まだ選手を指名されていない球団から1名選んでください',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Color(0xFF15803D)),
        ),
      ),
      _posChips(),
      const Divider(height: 1),
      Expanded(
        child: filtered.isEmpty
            ? const Center(child: Text('該当する候補がいません', style: TextStyle(color: _sub)))
            : ListView.separated(
                itemCount: filtered.length,
                separatorBuilder: (_, _) => const Divider(height: 1, color: _line),
                itemBuilder: (_, i) {
                  final p = filtered[i];
                  final picked = _roundPickSel?.id == p.id;
                  return ListTile(
                    dense: true,
                    selected: picked,
                    selectedTileColor: const Color(0xFFECFCCB),
                    onTap: () => setState(() => _roundPickSel = picked ? null : p),
                    title: InkWell(
                      onTap: () => showPlayerDetail(context, app, p, allowActions: false),
                      child: Text(
                        '${p.registeredName}（${_teamOf(p)}・${p.mainPosition}・${p.age}歳）',
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
            onPressed: () => _pickForMyTeam(validCands),
            style: FilledButton.styleFrom(backgroundColor: _navy, foregroundColor: _lime, padding: const EdgeInsets.symmetric(vertical: 14)),
            child: Text(
              _roundPickSel == null ? 'おまかせで1巡目を指名する' : '${_roundPickSel!.registeredName} を指名する',
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
        title: const Text('現役ドラフト（1巡目・最低20名選出）', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
      ),
      body: _step == 0 ? _step1SelectPool() : (_step == 1 ? _step2PreBid() : _step3Round1()),
    );
  }
}
