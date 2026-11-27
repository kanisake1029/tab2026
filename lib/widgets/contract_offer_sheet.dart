import 'dart:math';
import 'package:flutter/material.dart';
import '../models/player.dart';
import '../providers/app_state.dart';
import '../utils/app_theme.dart';
import '../utils/grade_utils.dart';
import '../utils/salary_utils.dart';
import 'player_detail_dialog.dart' show showPlayerDetail;

const _ink = Color(0xFF1C1917);
const _sub = Color(0xFF78716C);
const _askBlue = Color(0xFF1D4ED8);
const _line = Color(0xFFE7E5E4);

/// 統一契約交渉シートの戻り値
class ContractOfferResult {
  final int salary; // 1年あたりの年俸（万円）
  final int years; // 契約年数
  final bool ikusei; // 育成契約にするか
  const ContractOfferResult({required this.salary, required this.years, this.ikusei = false});
}

/// FA・契約更改・外国人・他リーグ調査・戦力外／自由契約で共通の契約交渉ボトムシート。
/// 年数・1年あたりの年俸・希望額・直近2年の主要成績を統一レイアウトで表示する。
Future<ContractOfferResult?> showContractOfferSheet({
  required BuildContext context,
  required AppState app,
  required Player player,
  required String title,
  String? subtitle,
  required int initialYears,
  int minYears = 1,
  int maxYears = 12,
  int? preferredYears,
  required int Function(int years) askForYears,
  int? initialSalary,
  int minSalary = 450,
  int stepUnit = 50,
  bool allowIkusei = false,
  bool initialIkusei = false,
  int ikuseiMaxSalary = 600,
  bool showCurrentSalaryDiff = false,
  bool showOfferForm = true,
  String submitLabel = '提示する',
  Widget? notice,
  Widget? extraSection,
}) async {
  var years = initialYears.clamp(minYears, maxYears);
  var salary = (initialSalary ?? askForYears(years)).clamp(minSalary, 999950);
  var ikusei = allowIkusei && initialIkusei;

  final recentLines = _recentTwoYearLines(app, player);

  return showModalBottomSheet<ContractOfferResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => StatefulBuilder(builder: (c, set) {
      final ask = askForYears(years);
      final totalSalary = salary * years;
      final askTotal = ask * years;
      final g = GradeUtils.getGrade(player.ovr);

      Widget stepBtn(String label, int delta) => OutlinedButton(
            onPressed: () => set(() {
              final next = ((salary + delta) / stepUnit).round() * stepUnit;
              salary = next.clamp(minSalary, 999950);
            }),
            style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 8)),
            child: Text(label, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
          );

      return SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 20 + MediaQuery.of(c).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // ── ヘッダー ──
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _sub)),
                  Row(children: [
                    Flexible(
                      child: Text(player.registeredName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: _ink)),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(color: AppTheme.getGradeColor(g).withValues(alpha: 0.14), borderRadius: BorderRadius.circular(5)),
                      child: Text('$g ${player.ovr}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: AppTheme.getGradeColor(g))),
                    ),
                  ]),
                ]),
              ),
              TextButton.icon(
                onPressed: () => showPlayerDetail(c, app, player, allowActions: false),
                icon: const Icon(Icons.person_search_outlined, size: 18),
                label: const Text('選手詳細'),
              ),
            ]),
            Text(
              '${player.isPitcher ? '投手' : player.mainPosition}・${player.age}歳・プロ${player.proYears}年${player.salary > 0 ? '　現年俸 ${formatSalary(player.salary)}' : ''}${subtitle != null && subtitle.isNotEmpty ? '\n$subtitle' : ''}',
              style: const TextStyle(fontSize: 12, color: _sub, height: 1.4),
            ),
            const SizedBox(height: 10),

            // ── 直近2年の主要成績 ──
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(10), border: Border.all(color: _line)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('直近2年の主要成績', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: _sub)),
                const SizedBox(height: 4),
                for (final (label, text) in recentLines)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1.5),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      SizedBox(width: 52, child: Text(label, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: _sub))),
                      Expanded(
                        child: Text(
                          text,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _ink, fontFeatures: [FontFeature.tabularFigures()]),
                        ),
                      ),
                    ]),
                  ),
              ]),
            ),
            const SizedBox(height: 12),

            if (showOfferForm) ...[
              if (allowIkusei)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('育成契約にする', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
                  subtitle: Text('年俸上限${formatSalary(ikuseiMaxSalary)}・1年契約', style: const TextStyle(fontSize: 11.5)),
                  value: ikusei,
                  onChanged: (v) => set(() => ikusei = v),
                ),

              if (ikusei) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: const Color(0xFFFEF9C3), borderRadius: BorderRadius.circular(10)),
                  child: Text(
                    '育成契約：年俸 ${formatSalary(min(player.salary > 0 ? player.salary : ikuseiMaxSalary, ikuseiMaxSalary))}・1年契約',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: _ink),
                  ),
                ),
                const SizedBox(height: 12),
              ] else ...[
                // ── 希望額（青字） ──
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFBFDBFE))),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(
                          '希望額（$years年${preferredYears != null ? '・希望$preferredYears年' : ''}）',
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: _askBlue),
                        ),
                        Text(
                          '年俸 ${formatSalary(ask)}${years > 1 ? '（総額 ${formatSalary(askTotal)}）' : ''}',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: _askBlue, fontFeatures: [FontFeature.tabularFigures()]),
                        ),
                      ]),
                    ),
                    TextButton(
                      onPressed: () => set(() => salary = ask.clamp(minSalary, 999950)),
                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                      child: const Text('希望額に合わせる', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
                    ),
                  ]),
                ),
                const SizedBox(height: 10),

                // ── 年数 & 1年あたりの年俸 ──
                Row(children: [
                  const Text('契約年数', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: _sub)),
                  const SizedBox(width: 10),
                  DropdownButton<int>(
                    value: years,
                    isDense: true,
                    items: [for (var y = minYears; y <= maxYears; y++) DropdownMenuItem(value: y, child: Text('$y年', style: const TextStyle(fontWeight: FontWeight.w800)))],
                    onChanged: (v) => set(() => years = v ?? minYears),
                  ),
                  const Spacer(),
                  if (years > 1)
                    Text('総額 ${formatSalary(totalSalary)}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: _sub)),
                ]),
                const SizedBox(height: 6),
                Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                  const Text('1年あたり ', style: TextStyle(fontSize: 12, color: _sub, fontWeight: FontWeight.w700)),
                  Expanded(
                    child: Text(
                      formatSalary(salary),
                      style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: _ink, fontFeatures: [FontFeature.tabularFigures()]),
                    ),
                  ),
                  if (showCurrentSalaryDiff && player.salary > 0)
                    Builder(builder: (_) {
                      final pct = ((salary / player.salary - 1) * 100).round();
                      return Text(
                        '${pct >= 0 ? '+' : ''}$pct%',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: salary >= player.salary ? const Color(0xFF16A34A) : const Color(0xFFDC2626)),
                      );
                    }),
                ]),
                const SizedBox(height: 6),
                Wrap(spacing: 5, runSpacing: 4, children: [
                  stepBtn('−1億', -10000),
                  stepBtn('−1000万', -1000),
                  stepBtn('−100万', -100),
                  if (stepUnit <= 50) stepBtn('−50万', -50),
                  if (stepUnit <= 50) stepBtn('+50万', 50),
                  stepBtn('+100万', 100),
                  stepBtn('+1000万', 1000),
                  stepBtn('+1億', 10000),
                ]),
                const SizedBox(height: 10),
              ],

              if (notice != null) ...[notice, const SizedBox(height: 10)],

              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(c),
                    child: const Text('やめる'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(
                      c,
                      ContractOfferResult(
                        salary: ikusei ? min(player.salary > 0 ? player.salary : ikuseiMaxSalary, ikuseiMaxSalary) : salary,
                        years: ikusei ? 1 : years,
                        ikusei: ikusei,
                      ),
                    ),
                    child: Text(submitLabel, style: const TextStyle(fontWeight: FontWeight.w900)),
                  ),
                ),
              ]),
            ],

            if (extraSection != null) ...[
              const Divider(height: 24),
              extraSection,
            ],
          ]),
        ),
      );
    }),
  );
}

String _fmtStatLine(Player p, PlayerStats? s) {
  if (s == null || (s.games == 0 && s.pitchApps == 0 && s.inningsPitched == 0 && s.atBats == 0)) {
    return '1軍出場なし';
  }
  if (p.isPitcher) {
    final ip = '${s.inningsPitched ~/ 3}${s.inningsPitched % 3 == 0 ? '' : '.${s.inningsPitched % 3}'}';
    final era = s.inningsPitched == 0 ? '-' : s.era.toStringAsFixed(2);
    return '${s.apps}登板 ${s.wins}勝${s.losses}敗 ${s.holds}H${s.saves}S ${ip}回 防$era';
  }
  final avg = s.atBats == 0 ? '-' : s.battingAverage.toStringAsFixed(3).replaceFirst('0.', '.');
  final pa = s.atBats + s.walks + s.sacFlies + s.hbp;
  final obp = pa == 0 ? 0.0 : (s.hits + s.walks + s.hbp) / pa;
  final slg = s.atBats == 0 ? 0.0 : s.totalBases / s.atBats;
  final ops = pa == 0 ? '-' : (obp + slg).toStringAsFixed(3).replaceFirst('0.', '.');
  return '${s.games}試合 打率$avg ${s.homeRuns}本 ${s.rbi}打点 OPS$ops';
}

List<(String, String)> _recentTwoYearLines(AppState app, Player p) {
  final last = app.lastSeasonStatsOf(p);
  final prev = app.priorSeasonStatsOf(p);
  final hasNpb = (last != null && (last.games > 0 || last.pitchApps > 0 || last.inningsPitched > 0)) ||
      (prev != null && (prev.games > 0 || prev.pitchApps > 0 || prev.inningsPitched > 0));
  if (hasNpb) {
    return [
      ('直近季', _fmtStatLine(p, last)),
      ('2年前', _fmtStatLine(p, prev)),
    ];
  }
  // 外国人・他リーグ選手：今季他リーグ成績＋abroad 直近行
  final rows = <(String, String)>[];
  if (p.seasonStats.games > 0 || p.seasonStats.pitchApps > 0 || p.seasonStats.inningsPitched > 0) {
    rows.add(('今季', _fmtStatLine(p, p.seasonStats)));
  }
  final lineRe = RegExp(r'^(\d{4})\s*[　 ]\s*([^　 ]+)\s*[　 ]\s*(.+)$');
  for (final l in p.abroad) {
    if (rows.length >= 2) break;
    final m = lineRe.firstMatch(l);
    if (m != null) {
      rows.add(('${m.group(1)}年', '${m.group(2)} ${m.group(3)}'));
    }
  }
  if (rows.isEmpty) {
    return const [('直近季', '1軍出場なし'), ('2年前', '1軍出場なし')];
  }
  return rows;
}
