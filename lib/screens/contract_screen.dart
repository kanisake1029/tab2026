import 'package:flutter/material.dart';
import '../engine/coach_engine.dart';
import '../engine/other_league_engine.dart';
import '../engine/transfer_engine.dart';
import '../models/amateur.dart';
import '../models/player.dart';
import '../providers/app_state.dart';
import '../utils/salary_utils.dart';
import '../widgets/player_detail_dialog.dart';

const _sub = Color(0xFF78716C);
const _ink = Color(0xFF1C1917);

/// 契約更改（11月）：年俸（50万円単位）と年数（1〜12年）を提示する。転任・引退勧告・自由契約も打診できる
class ContractScreen extends StatefulWidget {
  final AppState app;
  const ContractScreen({super.key, required this.app});

  @override
  State<ContractScreen> createState() => _ContractScreenState();
}

class _ContractScreenState extends State<ContractScreen> {
  static bool _ikusei = false;
  AppState get app => widget.app;

  void _toast(String s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

  String _statsLine(Player p) {
    final s = app.lastSeasonStatsOf(p);
    final prev = app.priorSeasonStatsOf(p);
    final hasPrev = prev != null && (prev.games > 0 || prev.pitchApps > 0 || prev.inningsPitched > 0);
    if (s == null || (s.games == 0 && s.pitchApps == 0 && s.inningsPitched == 0)) return '前季1軍 出場なし';
    if (p.isPitcher) {
      final ip = s.inningsPitched;
      final ipText = '${ip ~/ 3}${ip % 3 == 0 ? '' : '.${ip % 3}'}';
      final curApps = s.apps > 0 ? s.apps : s.games;
      final yoy = hasPrev ? '（前年 ${prev.apps > 0 ? prev.apps : prev.games}→$curApps登板）' : '';
      return '前季1軍 $curApps登板 ${ipText}回 ${s.wins}勝${s.losses}敗 防${ip == 0 ? '-' : s.era.toStringAsFixed(2)}$yoy';
    }
    final avg = s.atBats == 0 ? '-' : s.battingAverage.toStringAsFixed(3).replaceFirst(RegExp(r'^0'), '');
    final yoy = hasPrev ? '（前年 ${prev.games}→${s.games}試合）' : '';
    return '前季1軍 ${s.games}試合 打率$avg ${s.homeRuns}本 ${s.rbi}点$yoy';
  }

  Widget _badge(String label, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
        child: Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: fg)),
      );

  Widget _sectionHeader(String title, int count, Color color) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 8, 2, 6),
        child: Row(children: [
          Container(width: 4, height: 15, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 6),
          Text(title, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900, color: color)),
          const SizedBox(width: 6),
          _badge('$count人', color.withValues(alpha: 0.12), color),
        ]),
      );

  Widget _playerCard(Player p, {required bool isPending}) {
    final ask = app.renewAsk(p);
    final prefY = app.renewPreferredYears(p);
    final isNew = p.draftYear == app.currentDate.year || p.offJoin == app.offseasonYear;
    final isMulti = app.inMultiYear(p);
    final isDone = app.renewalDone(p) || (app.currentDate.month >= 12 && !isPending && !isMulti && !isNew);

    Widget statusBadge;
    if (app.isPostingFailedRenew(p)) {
      statusBadge = _badge('ポスティング不成立・未更改', const Color(0xFFDBEAFE), const Color(0xFF1D4ED8));
    } else if (isPending) {
      statusBadge = _badge('未更改', const Color(0xFFDBEAFE), const Color(0xFF1D4ED8));
    } else if (isDone) {
      statusBadge = _badge('更改済み${p.contractYears > 1 ? '（${p.contractYears}年）' : ''}', const Color(0xFFDCFCE7), const Color(0xFF15803D));
    } else if (isMulti) {
      statusBadge = _badge('複数年（残${p.contractYears}年）', const Color(0xFFE2E8F0), const Color(0xFF475569));
    } else if (isNew) {
      statusBadge = _badge('新人（来年から）', const Color(0xFFE2E8F0), const Color(0xFF475569));
    } else {
      statusBadge = _badge('対象外', const Color(0xFFE2E8F0), const Color(0xFF475569));
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      color: isPending ? Colors.white : const Color(0xFFF1F5F9),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: isPending ? const Color(0xFF93C5FD) : const Color(0xFFE2E8F0)),
      ),
      child: InkWell(
        onTap: () => _open(p),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
          child: Row(children: [
            if (isPending) ...[
              Container(width: 3.5, height: 42, decoration: BoxDecoration(color: const Color(0xFF2563EB), borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text(
                      '${p.registeredName}　${p.isPitcher ? '投手' : p.mainPosition}　${p.age}歳',
                      style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: isPending ? _ink : _sub),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  statusBadge,
                ]),
                const SizedBox(height: 4),
                Wrap(spacing: 10, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text('今 ${formatSalary(p.salary)}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: _ink)),
                  if (isPending)
                    Text(
                      '希望 ${formatSalary(ask)}（${prefY}年）',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Color(0xFF1D4ED8)),
                    ),
                  Text('信頼 ${p.trust}・愛着 ${p.teamLove}', style: const TextStyle(fontSize: 11.5, color: _sub)),
                ]),
                const SizedBox(height: 2),
                Text(_statsLine(p), style: const TextStyle(fontSize: 11, color: _sub)),
              ]),
            ),
            IconButton(
              icon: const Icon(Icons.person_search_outlined, size: 20),
              tooltip: '選手詳細',
              onPressed: () => showPlayerDetail(context, app, p, allowActions: false),
            ),
            const Icon(Icons.chevron_right, color: _sub),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final my = app.myTeam;
    if (my == null) return const Scaffold(body: Center(child: Text('球団が選ばれていません')));
    final allInTab = my.players.where((p) => p.ikusei == _ikusei && !app.isPostingPending(p)).toList()..sort((a, b) => b.salary.compareTo(a.salary));
    bool isPending(Player p) => app.canRenewPlayer(p);
    final pendingList = allInTab.where(isPending).toList();
    final doneList = allInTab.where((p) => !isPending(p)).toList();
    final left = my.players.where((p) => app.canRenewPlayer(p)).length;
    final hasPostingFailed = my.players.any((p) => app.isPostingFailedRenew(p));
    final total = my.players.fold<int>(0, (a, p) => a + p.salary);
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F4),
      appBar: AppBar(title: const Text('契約更改')),
      body: ListView(padding: const EdgeInsets.fromLTRB(12, 10, 12, 24), children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
          child: Text(
            app.renewalOpen
                ? '11月が契約更改の期間です（まだ $left人）。年俸は50万円単位、年数は1〜12年で提示できます（減額制限：1億超−40%・以下−25%）。信頼の低い選手に大きな減俸を出すと退団することがあります。'
                    '12月1日に、まだの選手は希望額（1年）で更改します。年俸の総額 ${formatSalary(total)}'
                : (hasPostingFailed
                    ? 'ポスティング不成立で残留した選手の契約更改ができます（まだ $left人・12月31日まで）。年俸の総額 ${formatSalary(total)}'
                    : '契約更改は11月です（12月1日に、まだの選手は希望額で更改します）。今は見るだけです。年俸の総額 ${formatSalary(total)}'),
            style: const TextStyle(fontSize: 12, color: _sub, height: 1.5),
          ),
        ),
        const SizedBox(height: 8),
        Row(children: [
          SegmentedButton<bool>(
            segments: const [ButtonSegment(value: false, label: Text('支配下')), ButtonSegment(value: true, label: Text('育成'))],
            selected: {_ikusei},
            showSelectedIcon: false,
            onSelectionChanged: (v) => setState(() => _ikusei = v.first),
          ),
          const Spacer(),
          if (left > 0)
            FilledButton(
              onPressed: () {
                final n = app.renewAllAtAsk();
                _toast('$n人を希望額で更改しました');
                setState(() {});
              },
              child: const Text('残りを希望額で'),
            ),
        ]),
        const SizedBox(height: 8),
        if (app.priorityForeigns.isNotEmpty) ...[
          const Text('契約満了・優先交渉（外国人：12月14日まで）', style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF1E3A8A))),
          const SizedBox(height: 4),
          for (final fa in app.priorityForeigns)
            Card(
              margin: const EdgeInsets.only(bottom: 6),
              color: const Color(0xFFEFF6FF),
              child: ListTile(
                title: Text('${fa.player.registeredName}　${fa.player.isPitcher ? '投手' : fa.player.mainPosition}　${fa.player.age}歳', style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Wrap(spacing: 10, runSpacing: 2, children: [
                    Text('前年 ${formatSalary(fa.player.salary)}', style: const TextStyle(fontSize: 12)),
                    Text('希望 ${formatSalary(app.renewAsk(fa.player))}（${app.renewPreferredYears(fa.player)}年）', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900, color: Color(0xFF1D4ED8))),
                    Text('優先期限 12/14まで　信頼 ${fa.player.trust}・愛着 ${fa.player.teamLove}', style: const TextStyle(fontSize: 12)),
                  ]),
                  Text(_statsLine(fa.player), style: const TextStyle(fontSize: 11, color: _sub)),
                ]),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    icon: const Icon(Icons.person_search_outlined, size: 20),
                    tooltip: '選手詳細',
                    onPressed: () => showPlayerDetail(context, app, fa.player, allowActions: false),
                  ),
                  const Icon(Icons.chevron_right),
                ]),
                onTap: () => _openPriorityForeign(fa),
              ),
            ),
          const SizedBox(height: 8),
        ],
        if (pendingList.isNotEmpty) ...[
          _sectionHeader('未更改選手', pendingList.length, const Color(0xFF1D4ED8)),
          for (final p in pendingList) _playerCard(p, isPending: true),
        ],
        if (doneList.isNotEmpty) ...[
          _sectionHeader('更改済み・対象外', doneList.length, const Color(0xFF475569)),
          for (final p in doneList) _playerCard(p, isPending: false),
        ],
      ]),
    );
  }

  Future<void> _openPriorityForeign(FreeAgent fa) async {
    final p = fa.player;
    var years = app.renewPreferredYears(p).clamp(1, 12);
    var salary = app.renewAskFor(p, years);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(builder: (c, set) {
        Widget step(String label, int d) => OutlinedButton(
              onPressed: () => set(() => salary = (salary + d).clamp(450, 999950)),
              style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 8)),
              child: Text(label, style: const TextStyle(fontSize: 12)),
            );
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 20 + MediaQuery.of(c).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text('${p.registeredName}（優先交渉）', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900))),
              TextButton.icon(
                onPressed: () => showPlayerDetail(c, app, p, allowActions: false),
                icon: const Icon(Icons.person_search_outlined, size: 18),
                label: const Text('選手詳細'),
              ),
            ]),
            Text('${p.isPitcher ? '投手' : p.mainPosition}・${p.age}歳　前年 ${formatSalary(p.salary)}　優先期限：12月14日まで（3回保留で自由契約）', style: const TextStyle(color: _sub, fontSize: 12)),
            Text('信頼 ${p.trust}・愛着 ${p.teamLove}', style: const TextStyle(color: _sub, fontSize: 12)),
            const SizedBox(height: 12),
            Text('希望（$years年なら）：${formatSalary(app.renewAskFor(p, years))}', style: const TextStyle(fontSize: 12.5, color: _sub)),
            const SizedBox(height: 6),
            Text(formatSalary(salary), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: _ink)),
            Wrap(spacing: 6, runSpacing: 4, children: [step('−1億', -10000), step('−1000万', -1000), step('−50万', -50), step('+50万', 50), step('+1000万', 1000), step('+1億', 10000)]),
            const SizedBox(height: 8),
            Row(children: [
              const Text('年数'),
              const SizedBox(width: 10),
              DropdownButton<int>(
                value: years,
                items: [for (var y = 1; y <= 12; y++) DropdownMenuItem(value: y, child: Text('$y年'))],
                onChanged: (v) => set(() => years = v ?? 1),
              ),
              const Spacer(),
              OutlinedButton(
                onPressed: () {
                  final msg = app.offerForeignReSign(fa, 600, 1, ikusei: true);
                  Navigator.pop(c);
                  _toast(msg);
                  setState(() {});
                },
                child: const Text('育成で再契約'),
              ),
              const SizedBox(width: 6),
              FilledButton(
                onPressed: () {
                  final msg = app.offerForeignReSign(fa, salary, years);
                  Navigator.pop(c);
                  _toast(msg);
                  setState(() {});
                },
                child: const Text('再契約を提示'),
              ),
            ]),
          ]),
        );
      }),
    );
  }

  Future<void> _open(Player p) async {
    var years = app.renewPreferredYears(p);
    var salary = app.renewalDone(p) ? p.salary : app.renewAskFor(p, years);
    final canRenew = app.canRenewPlayer(p);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(builder: (c, set) {
        Widget step(String label, int d) => OutlinedButton(
              onPressed: canRenew ? () => set(() => salary = (salary + d).clamp(p.ikusei ? 250 : 450, 999950)) : null,
              style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 8)),
              child: Text(label, style: const TextStyle(fontSize: 12)),
            );
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 20 + MediaQuery.of(c).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(p.registeredName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900))),
              TextButton.icon(
                onPressed: () => showPlayerDetail(c, app, p, allowActions: false),
                icon: const Icon(Icons.person_search_outlined, size: 18),
                label: const Text('選手詳細'),
              ),
            ]),
            Text('${p.isPitcher ? '投手' : p.mainPosition}・${p.age}歳・プロ${p.proYears}年　今の年俸 ${formatSalary(p.salary)}　信頼 ${p.trust}・愛着 ${p.teamLove}　提示 ${app.renewTries[p.id] ?? 0}回', style: const TextStyle(color: _sub, fontSize: 12.5)),
            const SizedBox(height: 12),
            if (canRenew) ...[
              Text('希望（$years年なら）：${formatSalary(app.renewAskFor(p, years))}', style: const TextStyle(fontSize: 12.5, color: _sub)),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(child: Text(formatSalary(salary), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: _ink))),
                Text('${((salary / p.salary - 1) * 100).round() >= 0 ? '+' : ''}${((salary / p.salary - 1) * 100).round()}%', style: TextStyle(color: salary >= p.salary ? const Color(0xFF16A34A) : const Color(0xFFDC2626), fontWeight: FontWeight.w800)),
              ]),
              Wrap(spacing: 6, runSpacing: 4, children: [step('−1億', -10000), step('−1000万', -1000), step('−50万', -50), step('+50万', 50), step('+1000万', 1000), step('+1億', 10000)]),
              const SizedBox(height: 8),
              Row(children: [
                const Text('年数'),
                const SizedBox(width: 10),
                DropdownButton<int>(
                  value: years,
                  items: [for (var y = 1; y <= 12; y++) DropdownMenuItem(value: y, child: Text('$y年'))],
                  onChanged: (v) => set(() => years = v ?? 1),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: () {
                    final msg = app.offerRenewal(p, salary, years);
                    Navigator.pop(c);
                    _toast(msg);
                    setState(() {});
                  },
                  child: const Text('提示する'),
                ),
              ]),
              const Divider(height: 24),
            ],
            const Text('ほかの打診', style: TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 6, children: [
              if (!p.ikusei && app.canReSignIkusei)
                OutlinedButton(
                  onPressed: () async {
                    if (!await _confirm('${p.registeredName}と育成選手として再契約しますか？（年俸上限600万円・背番号3桁）')) return;
                    final err = app.reSignIkusei(p);
                    if (c.mounted) Navigator.pop(c);
                    _toast(err ?? '${p.registeredName}と育成再契約しました');
                    setState(() {});
                  },
                  child: const Text('育成で再契約'),
                ),
              OutlinedButton(onPressed: () => _role(c, p, coach: true), child: const Text('コーチに転任')),
              OutlinedButton(onPressed: () => _role(c, p, coach: false), child: const Text('スカウトに転任')),
              OutlinedButton(
                onPressed: () async {
                  if (!await _confirm('${p.registeredName}に引退を勧めますか？（断られると信頼が下がり、信頼が低いと退団します）')) return;
                  final msg = app.adviseRetire(p);
                  if (c.mounted) Navigator.pop(c);
                  _toast(msg);
                  setState(() {});
                },
                child: const Text('引退勧告'),
              ),
              OutlinedButton(
                onPressed: () async {
                  if (!await _confirm('${p.registeredName}を自由契約にしますか？')) return;
                  final err = app.releasePlayer(p);
                  if (c.mounted) Navigator.pop(c);
                  _toast(err ?? '${p.registeredName}を自由契約にしました');
                  setState(() {});
                },
                style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFDC2626)),
                child: const Text('自由契約'),
              ),
            ]),
            const SizedBox(height: 6),
            const Text('転任・引退は、ベテランほど受け入れやすく、信頼が高いほど受け入れやすい。主力は断りやすい。育成への切り替えは、これまでどおり自動です。', style: TextStyle(fontSize: 11, color: _sub)),
          ]),
        );
      }),
    );
  }

  Future<bool> _confirm(String q) async =>
      await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(content: Text(q), actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('やめる')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('打診する'))]),
      ) ==
      true;

  /// 転任の役職を選ぶ
  Future<void> _role(BuildContext sheet, Player p, {required bool coach}) async {
    final roles = coach
        ? [...CoachEngine.roles1G, ...CoachEngine.roles2G, ...CoachEngine.roles3G]
        : [
            'チーフスカウト',
            for (final rg in amRegions) '${CoachEngine.regionScoutPrefix}$rg',
            for (final l in OtherLeagueEngine.leagues.values) '${CoachEngine.overseasScoutPrefix}${l.id}',
          ];
    String label(String r) => r.startsWith(CoachEngine.overseasScoutPrefix) ? '海外スカウト（${OtherLeagueEngine.leagues[r.substring(CoachEngine.overseasScoutPrefix.length)]?.name}）' : (coach && !r.startsWith('2軍') && !r.startsWith('3軍') ? '$rコーチ' : r);
    final role = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => ListView(children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: Text('${p.registeredName}を${coach ? 'コーチ' : 'スカウト'}に（今その役職の人は外れます。3軍コーチ・スカウトは人数に空きがあれば加わります）', style: const TextStyle(fontSize: 12, color: _sub))),
        for (final r in roles) ListTile(dense: true, title: Text(label(r)), onTap: () => Navigator.pop(c, r)),
      ]),
    );
    if (role == null) return;
    final msg = app.offerStaffRole(p, role);
    if (sheet.mounted) Navigator.pop(sheet);
    _toast(msg);
    setState(() {});
  }
}
