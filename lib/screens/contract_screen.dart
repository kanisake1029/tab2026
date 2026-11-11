import 'package:flutter/material.dart';
import '../engine/coach_engine.dart';
import '../engine/other_league_engine.dart';
import '../models/amateur.dart';
import '../models/player.dart';
import '../providers/app_state.dart';
import '../utils/salary_utils.dart';

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

  @override
  Widget build(BuildContext context) {
    final my = app.myTeam;
    if (my == null) return const Scaffold(body: Center(child: Text('球団が選ばれていません')));
    final list = my.players.where((p) => p.ikusei == _ikusei).toList()..sort((a, b) => b.salary.compareTo(a.salary));
    final left = my.players.where((p) => !app.renewalDone(p) && !app.inMultiYear(p) && p.draftYear != app.currentDate.year).length;
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
                ? '11月が契約更改の期間です（まだ $left人）。年俸は50万円単位、年数は1〜12年で提示できます。何度でも提示できますが、断られるたびに信頼が下がり、信頼の低い選手に大きな減俸を出すと退団することがあります。'
                    '12月1日に、まだの選手は希望額（1年）で更改します。年俸の総額 ${formatSalary(total)}'
                : '契約更改は11月です（12月1日に、まだの選手は希望額で更改します）。今は見るだけです。年俸の総額 ${formatSalary(total)}',
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
          if (app.renewalOpen && left > 0)
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
        for (final p in list)
          Card(
            margin: const EdgeInsets.only(bottom: 6),
            child: ListTile(
              title: Text('${p.registeredName}　${p.isPitcher ? '投手' : p.mainPosition}　${p.age}歳', style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(
                '今 ${formatSalary(p.salary)}${app.inMultiYear(p) ? '　複数年契約中（残り${p.contractYears}年）' : app.renewalDone(p) ? '　更改済み${p.contractYears > 1 ? '（${p.contractYears}年）' : ''}' : p.draftYear == app.currentDate.year ? '　新人（来年から）' : '　希望 ${formatSalary(app.renewAsk(p))}'}　信頼 ${p.trust}',
                style: const TextStyle(fontSize: 12),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _open(p),
            ),
          ),
      ]),
    );
  }

  Future<void> _open(Player p) async {
    var salary = app.renewalDone(p) ? p.salary : app.renewAsk(p);
    var years = 1;
    final canRenew = app.renewalOpen && !app.renewalDone(p) && !app.inMultiYear(p) && p.draftYear != app.currentDate.year;
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
            Text(p.registeredName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            Text('${p.isPitcher ? '投手' : p.mainPosition}・${p.age}歳・プロ${p.proYears}年　今の年俸 ${formatSalary(p.salary)}　信頼 ${p.trust}　提示 ${app.renewTries[p.id] ?? 0}回', style: const TextStyle(color: _sub, fontSize: 12.5)),
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
