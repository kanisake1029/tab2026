import 'dart:math';
import '../engine/abroad_stats.dart';
import '../engine/growth_curve.dart';
import 'player_avatar.dart';
import '../engine/scout_comment.dart';
import '../engine/body_model.dart';
import '../engine/grip_spin.dart';
import '../engine/pitch_motion.dart';
import '../engine/pre_career.dart';
import '../engine/batting_splits.dart';
import '../engine/other_league_engine.dart';
import '../models/other_league.dart';
import '../providers/app_state.dart';
import '../screens/ob_screen.dart' show timelineLine;
import 'package:flutter/material.dart';
import 'body_form_editor.dart';
import '../engine/career_path.dart';
import '../engine/career_engine.dart';
import '../engine/foreign_engine.dart';
import 'pitch_catalog_dialog.dart';
import '../engine/growth_engine.dart';
import '../engine/coach_engine.dart';
import '../models/player.dart';
import '../models/team.dart';
import '../utils/grade_utils.dart';
import '../utils/app_theme.dart';
import '../utils/salary_utils.dart';
import '../utils/standings.dart';
import 'condition_face.dart';
import 'frozen_table.dart';
import '../ai/ai_facts.dart';
import '../ai/ai_text.dart';

/// 選手詳細（閲覧用）。上から：
///  基本情報 → 体力・回復力・怪我しにくさ・才能・向上心など → 左右2列の能力（野手：打撃｜守備走塁、投手：投球｜球種）
///  → 年度別＋通算の成績（横にスクロールする表。1軍／2軍を切り替え）→ 寸評
///  文字と余白を小さくして、スマホでも同じ情報量を詰めて見せる。他球団の選手も同じ画面で見られる
class ScoutReport extends StatefulWidget {
  final Player player;
  final dynamic appState;
  final Team? team;
  final Widget? actions;
  final VoidCallback onClose;
  /// 名前の所を押したとき（自球団の選手：登録名・背番号・ポジション・二刀流の編集）
  final VoidCallback? onEditName;
  const ScoutReport({super.key, required this.player, required this.appState, this.team, this.actions, required this.onClose, this.onEditName});

  @override
  State<ScoutReport> createState() => _ScoutReportState();
}

class _ScoutReportState extends State<ScoutReport> {
  static const _ink = Color(0xFF1C1917);
  static const _sub = Color(0xFF78716C);
  static const _line = Color(0xFFE7E5E4);

  String _mode = '1軍'; // 成績の表：1軍 / 2軍 / 守備（1軍の守備成績）
  int _careerSub = 0; // 経歴の中の小さなタブ（成績・表彰・年表・能力）
  int _splKind = 0; // 打撃の詳しい成績：0 コース・1 打球方向・2 球種・3 球速
  int _splPeriod = 0; // コース・方向の図の期間：0 今季・1 過去3年・2 通算
  int _tab = 0; // 0 能力・1 経歴（年度ごとの所属・成績・タイトルと記録、移籍の歩み）・2 フォーム・道具
  late bool _tblPitch = p.isPitcher; // 二刀流：成績の表を投球にするか
  bool get _farm => _mode == '2軍';
  late Future<List<(int, String, PlayerStats, PlayerStats)>> _history = _loadHistory();
  // ゲーム開始前の年度別の経歴（推定）
  late Future<List<PreYear>> _pre = _loadPre();
  // 年表（入団・移籍・初記録・節目）
  late Future<List<(DateTime, String)>> _timeline = _loadTimeline();
  late Future<(List<(int, String, PlayerStats, PlayerStats)>, List<PreYear>)> _both = _loadBoth();

  Future<List<(int, String, PlayerStats, PlayerStats)>> _loadHistory() =>
      widget.appState.playerHistory(p.id) as Future<List<(int, String, PlayerStats, PlayerStats)>>;
  Future<List<PreYear>> _loadPre() =>
      (widget.appState.preCareers() as Future<Map<String, List<PreYear>>>).then((m) => m[p.id] ?? const <PreYear>[]);
  Future<List<(DateTime, String)>> _loadTimeline() =>
      (widget.appState as AppState).playerTimeline(p);
  Future<(List<(int, String, PlayerStats, PlayerStats)>, List<PreYear>)> _loadBoth() =>
      Future.wait([_history, _pre]).then((v) => (v[0] as List<(int, String, PlayerStats, PlayerStats)>, v[1] as List<PreYear>));

  @override
  void didUpdateWidget(covariant ScoutReport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.player.id != widget.player.id) {
      _tblPitch = p.isPitcher;
      _history = _loadHistory();
      _pre = _loadPre();
      _timeline = _loadTimeline();
      _both = _loadBoth();
    }
  }

  Player get p => widget.player;
  dynamic get app => widget.appState;

  /// 他リーグの選手なら、その球団
  OTeam? get _otherTeam => (widget.appState is AppState) ? (widget.appState as AppState).otherPlayer(p.id)?.$1 : null;
  String get _otherLabel {
    final t = _otherTeam;
    if (t == null) return '';
    return '${OtherLeagueEngine.leagues[t.leagueId]?.name ?? ''}・${t.short}';
  }

  String get _otherTableTeam {
    final t = _otherTeam;
    if (t == null) return '−';
    final lg = OtherLeagueEngine.leagues[t.leagueId];
    if (lg?.group == '日本独立') return '${lg!.name.replaceAll('リーグ', '')}・${t.short}';
    return '${lg?.name.replaceAll('リーグ', '') ?? t.leagueId}・${OtherLeagueEngine.teamCode(t)}';
  }

  /// 表示するプロ年数：NPB在籍時はNPBに居た年数、他リーグ在籍時は野球人生としてプロ入りしてからの通算年数
  int get _displayProYears => _otherTeam != null
      ? CareerPath.totalProYears(p, app.startYear as int, inOtherLeague: true)
      : p.proYears;

  void _ensureProHistory([Set<int> extraNpbYears = const {}]) {
    final int sy = app.startYear as int;
    final ot = _otherTeam;
    final int py = max<int>(1, p.proYears);
    final npbSet = <int>{
      ...extraNpbYears,
      if (ot == null)
        for (int y = sy - py + 1; y <= sy; y++) y,
    };
    final indieDefault = (ot != null && OtherLeagueEngine.leagues[ot.leagueId]?.group == '日本独立')
        ? '${OtherLeagueEngine.leagues[ot.leagueId]!.name.replaceAll('リーグ', '')}・${ot.short}'
        : null;
    ForeignEngine.ensureFullProHistory(
      p,
      sy,
      npbYears: npbSet,
      defaultIndieLabel: indieDefault,
      inOtherLeague: ot != null,
    );
  }

  Team? get _team {
    for (final t in (app.teams as List<Team>)) {
      if (t.players.any((x) => x.id == p.id)) return t;
    }
    return widget.team;
  }

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Flexible(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _header(),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: SegmentedButton<int>(
                segments: const [ButtonSegment(value: 0, label: Text('能力')), ButtonSegment(value: 1, label: Text('経歴')), ButtonSegment(value: 2, label: Text('フォーム・道具'))],
                selected: {_tab},
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                onSelectionChanged: (v) => setState(() => _tab = v.first),
              ),
            ),
            const SizedBox(height: 6),
            if (_tab == 1) _careerView() else if (_tab == 2) _formGearView() else ...[
              _profile(),
              const SizedBox(height: 8),
              _bodyRow(),
              const SizedBox(height: 8),
              _abilityColumns(),
              const SizedBox(height: 10),
              _commentSection(),
            ],
          ]),
        ),
      ),
      if (widget.actions != null)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: _line))),
          child: SingleChildScrollView(scrollDirection: Axis.horizontal, reverse: true, child: widget.actions!),
        ),
    ]);
  }

  // ---------------- 共通の部品 ----------------
  Widget _grade(int v, {double size = 14}) {
    final g = GradeUtils.getGrade(v);
    return Text(g, textAlign: TextAlign.center, style: TextStyle(fontSize: size, fontWeight: FontWeight.w900, color: AppTheme.getGradeColor(g), height: 1.1));
  }

  Widget _title(String s, {Widget? trailing}) => Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Row(children: [
          Container(width: 3, height: 13, color: _ink),
          const SizedBox(width: 5),
          Expanded(child: Text(s, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900, color: _ink))),
          if (trailing != null) trailing,
        ]),
      );

  /// 能力の1行（項目・ランク・数値・補足）
  Widget _abilityLine(String label, int v, {String? shown, String note = ''}) => Container(
        padding: const EdgeInsets.symmetric(vertical: 2.5),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF5F5F4)))),
        child: Row(children: [
          Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: _ink))),
          SizedBox(width: 20, child: _grade(v, size: 13)),
          SizedBox(width: 38, child: Text(shown ?? '$v', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()]))),
          if (note.isNotEmpty) ...[const SizedBox(width: 4), Text(note, style: const TextStyle(fontSize: 9.5, color: _sub))],
        ]),
      );

  // ---------------- ヘッダー ----------------
  Widget _header() {
    final t = _team;
    final pos = p.isPitcher ? _pitcherRole() : p.mainPosition;
    return Container(
      padding: const EdgeInsets.only(bottom: 6),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _ink, width: 1.5))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        PlayerAvatar(p, size: 60), // 顔アイコン（球団のユニフォーム・胸のロゴ）
        const SizedBox(width: 10),
        Expanded(
          child: InkWell(
            onTap: widget.onEditName,
            borderRadius: BorderRadius.circular(6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${_otherTeam != null ? _otherLabel : (t == null ? '' : teamShort(t))}　$pos', style: const TextStyle(fontSize: 11, color: _sub), overflow: TextOverflow.ellipsis),
              Row(children: [
                Flexible(child: Text('${_otherTeam != null ? '' : '#${p.uniformText}　'}${p.listName}', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: _ink), overflow: TextOverflow.ellipsis)),
                if (widget.onEditName != null) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.edit, size: 16, color: _sub)),
              ]),
              if (p.registeredName != p.listName || p.nextNumber != null || p.numberPending)
                Text(
                  [
                    if (p.registeredName != p.listName) '登録名：${p.registeredName}',
                    if (p.nextNumber != null) '${p.numberPending ? '決定予定' : '来季'}（開幕前日〜）#${uniformLabel(p.nextNumber!)}',
                    if (p.nextNumber == null && p.numberPending) '仮番号（開幕前日に正式決定）',
                  ].join('　'),
                  style: const TextStyle(fontSize: 10.5, color: _sub),
                ),
            ]),
          ),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          const Text('総合', style: TextStyle(fontSize: 10, color: _sub)),
          Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            _grade(p.ovr, size: 24),
            const SizedBox(width: 4),
            Text('${p.ovr}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          ]),
          Text(_teamRank(t), style: const TextStyle(fontSize: 9.5, color: _sub)),
        ]),
        IconButton(tooltip: '閉じる', onPressed: widget.onClose, icon: const Icon(Icons.close, size: 20), visualDensity: VisualDensity.compact),
      ]),
    );
  }

  String _pitcherRole() {
    final t = _team;
    if (t == null) return '投手';
    final ri = t.activeRotation.indexOf(p.id);
    if (ri >= 0) return '投手（先発${ri + 1}番手）';
    final wi = t.winningPattern.indexOf(p.id);
    if (wi >= 0) return '投手（${const ['7回', '8回', '9回'][wi]}）';
    return t.roster1G.contains(p.id) ? '投手（中継ぎ）' : '投手';
  }

  String _teamRank(Team? t) {
    if (t == null) return '';
    final same = t.players.where((x) => x.isPitcher == p.isPitcher).toList()..sort((a, b) => b.ovr.compareTo(a.ovr));
    final all = same.indexWhere((x) => x.id == p.id) + 1;
    return p.isPitcher ? 'チーム内 投手$all位' : 'チーム内 野手$all位';
  }

  // ---------------- リリース（体格・フォームから計算） ----------------
  List<(String, Widget)> _releaseRows() {
    try {
      final mo = PitchMotion(BodyModel.ofPlayer(p), p.form, armAngleDeg: p.spinAxis, lefty: p.throws == 'L', velocity: p.velocity);
      final r = mo.release;
      final fb = p.pitches.where((x) => x.name == 'ストレート').firstOrNull ?? (p.pitches.isEmpty ? null : p.pitches.first);
      final rows = <(String, Widget)>[
        ('§リリース', const SizedBox()),
        ('高さ', Text('${r.height.toStringAsFixed(2)}m')),
        ('前へ', Text('${r.extension.toStringAsFixed(2)}m')),
        ('横', Text('${(r.pos.x * 100).abs().round()}cm')),
        ('指先の速さ', Text('${(r.handSpeed * 3.6).round()}km/h')),
        ('骨盤', Text('${r.pelvisPeak.round()}°/s')),
        ('体幹', Text('${r.trunkPeak.round()}°/s')),
        ('肘', Text('${r.elbowPeak.round()}°/s')),
        ('肩の内旋', Text('${r.irPeak.round()}°/s')),
        ('捻転差', Text('${r.sepFFS.round()}°')),
        ('前傾', Text('${r.trunkFlex.round()}°')),
      ];
      if (fb != null) {
        final s = GripSpin.of(fb, pos: r.pos, armAngle: p.spinAxis, lefty: p.throws == 'L', velocity: p.velocity, fbSharp: fb.sharpness, fbHeavy: fb.heaviness);
        rows.addAll([
          ('§直球の回転', const SizedBox()),
          ('回転数', Text('${s.rpm.round()}rpm')),
          ('回転の向き', Text(s.clockText)),
          ('効率', Text('${(s.efficiency * 100).round()}%')),
          ('変化 縦', Text('${s.moveV.round()}cm')),
          ('変化 横', Text('${s.moveH.round()}cm')),
        ]);
      }
      return rows;
    } catch (_) {
      return const [];
    }
  }

  // ---------------- 基本情報 ----------------
  Widget _profile() {
    _ensureProHistory();
    final t = _team;
    final cond = p.conditionAt(app.currentDate as DateTime);
    const draft = {'A': '高卒', 'B': '大卒', 'C': '社会人等'};
    final grow = GrowthCurve.label(p);
    final ot = _otherTeam;
    final items = <(String, Widget)>[
      ('年齢', Text('${p.age}歳')),
      ('生年月日', Text(p.birthDate)),
      ('投打', Text('${p.throws == 'L' ? '左' : '右'}投${p.bats == 'L' ? '左' : (p.bats == 'S' ? '両' : '右')}打')),
      ('タイプ', Text(CoachEngine.playerType(p))),
      ('身長', Text('${p.height}cm')),
      ('体重', Text('${p.weight}kg')),
      if (ot == null) ('入団', Text(draft[p.draftType] ?? p.draftType)),
      ('プロ', Text('${_displayProYears}年目')),
      ('出身', Text(p.nationality == '海外' ? (p.origin.isEmpty ? '海外' : p.origin) : (p.birthplace.isNotEmpty ? p.birthplace : p.nationality))),
      if (ot == null && p.nationality == '海外') ('枠', Text(p.foreignSlot ? '外国人枠' : '日本人扱い')),
      if (ot != null) ('リーグ', Text(OtherLeagueEngine.leagues[ot.leagueId]?.name ?? '')),
      if (ot != null) ('球団', Text(ot.name)),
      if (ot != null && ((widget.appState as AppState).otherWorld?.fromNpb[p.id] ?? '').isNotEmpty) ('元NPB', Text((widget.appState as AppState).otherWorld!.fromNpb[p.id]!)),
      if (ot == null) ('年俸', Text(formatSalary(p.salary))),
      if (ot == null) ('契約', Text('残り${p.contractYears}年${p.ikusei ? '（育成${p.ikuseiYears + 1}年目）' : ''}')),
      if (ot == null) ('FA', Text(p.isPartner ? '提携（${p.partnerMlb}）' : (p.hasFA ? '権利あり${p.faService >= Player.overseasFaYears && p.nationality != '海外' ? '（海外も）' : ''}' : '${p.faService}／${p.faNeed}年'))),
      if (ot == null) ('所属', Text(t == null ? '−' : (t.roster1G.contains(p.id) ? (t.active26.contains(p.id) ? '1軍' : '1軍ベンチ外') : (p.ikusei ? '育成' : '2軍')))),
      if (ot == null) ('監督信頼', Text('${p.trust}')),
      if (ot == null) ('チーム愛', Text('${p.teamLove}')),
      ('調子', Row(mainAxisSize: MainAxisSize.min, children: [ConditionFace(level: cond, size: 13), const SizedBox(width: 3), Text(ConditionFace.labels[cond]!)])),
      ('故障', Text(p.injuryDays > 0 ? '${p.injuryName}（残り${p.injuryDays}日）' : 'なし', style: TextStyle(color: p.injuryDays > 0 ? const Color(0xFFDC2626) : null))),
      ('成長', Text(GrowthEngine.phaseOf(p).label)),
      ('全盛期', Text(grow.replaceFirst('全盛期', '').trim())),
      ('練習', Text(GrowthEngine.practiceOptions(p).contains(p.practiceInstruction) && p.practiceInstruction != 'おまかせ' ? p.practiceInstruction : 'おまかせ（${GrowthEngine.autoPractice(p)}）')),
      ('経歴', Text.rich(TextSpan(children: [
        for (var i = 0; i < CareerPath.of(p).length; i++) ...[
          if (i > 0) const TextSpan(text: ' → '),
          TextSpan(
            text: CareerPath.of(p)[i],
            style: TextStyle(color: CareerPath.of(p)[i].endsWith('*') ? _sub : null),
          ),
        ],
      ]))),
    ];
    return _infoGrid(items, wide: const {'経歴', '練習', '元NPB'});
  }

  /// 情報の表：「見出し｜値」を、スマホは1行に2組（広い画面は3組）。wide は1行まるごと。'§' で始まる項目は区切りの見出し
  Widget _infoGrid(List<(String, Widget)> items, {Set<String> wide = const {}}) {
    return LayoutBuilder(builder: (context, c) {
      final per = c.maxWidth >= 560 ? 3 : 2;
      const labelW = 58.0;
      Widget cell(String label, Widget v) => Expanded(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(
                width: labelW,
                color: const Color(0xFFF1F5F9),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                alignment: Alignment.centerLeft,
                child: Text(label, style: const TextStyle(fontSize: 10.5, color: _sub, fontWeight: FontWeight.w600)),
              ),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                  alignment: Alignment.centerLeft,
                  child: DefaultTextStyle.merge(style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _ink, height: 1.3), child: v),
                ),
              ),
            ]),
          );
      Widget line(List<Widget> cells) => Container(
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _line))),
            child: IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: cells)),
          );
      final rows = <Widget>[];
      var buf = <Widget>[];
      void flush() {
        if (buf.isEmpty) return;
        while (buf.length < per) {
          buf.add(const Expanded(child: SizedBox()));
        }
        final cells = <Widget>[];
        for (var i = 0; i < buf.length; i++) {
          if (i > 0) cells.add(const VerticalDivider(width: 1, thickness: 1, color: _line));
          cells.add(buf[i]);
        }
        rows.add(line(cells));
        buf = [];
      }

      for (final it in items) {
        if (it.$1.startsWith('§')) {
          flush();
          rows.add(Container(
            color: const Color(0xFF334155),
            padding: const EdgeInsets.fromLTRB(8, 2, 8, 2),
            child: Text(it.$1.substring(1), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white)),
          ));
        } else if (wide.contains(it.$1)) {
          flush();
          rows.add(line([cell(it.$1, it.$2)]));
        } else {
          buf.add(cell(it.$1, it.$2));
          if (buf.length == per) flush();
        }
      }
      flush();
      return Container(
        decoration: BoxDecoration(border: Border.all(color: _line), borderRadius: BorderRadius.circular(6)),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows),
      );
    });
  }

  // ---------------- 体力・回復力・怪我しにくさ・才能・向上心 ----------------
  Widget _bodyRow() {
    final items = <(String, int, String)>[
      ('体力', p.energyRank, '${p.energy}/${p.maxEnergy}'),
      ('回復力', p.recovery, '${p.recovery}'),
      ('怪我しにくさ', p.durability, '${p.durability}'),
      ('才能', p.talent, '${p.talent}'),
      ('向上心', p.ambition, '${p.ambition}'),
      ('信頼', p.trust, '${p.trust}'),
      ('モチベ', p.motivation, '${p.motivation}'),
    ];
    return Container(
      decoration: BoxDecoration(border: Border.all(color: _line), borderRadius: BorderRadius.circular(6)),
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
      child: Column(children: [
        Row(children: [
          for (final it in items)
            Expanded(
              child: Column(children: [
                FittedBox(fit: BoxFit.scaleDown, child: Text(it.$1, maxLines: 1, style: const TextStyle(fontSize: 9.5, color: _sub))),
                _grade(it.$2, size: 15),
                Text(it.$3, maxLines: 1, style: const TextStyle(fontSize: 9, color: _sub)),
              ]),
            ),
        ]),
        Text('成長率 ×${p.growthRate.toStringAsFixed(2)}（才能 × 向上心）', style: const TextStyle(fontSize: 9.5, color: _sub)),
      ]),
    );
  }

  // ---------------- 左右2列の能力 ----------------
  // ---------------- 左右2つの切り替え式の能力 ----------------
  // 左：野手は 打撃／投球、投手は 投球／打撃。右：野手は 守備／球種、投手は 球種／守備（最初は本職の方を出す）
  late bool _leftBat = !p.isPitcher;
  late bool _rightField = !p.isPitcher;

  Widget _switch(String a, String b, bool first, ValueChanged<bool> onChanged) => SegmentedButton<bool>(
        segments: [ButtonSegment(value: true, label: Text(a)), ButtonSegment(value: false, label: Text(b))],
        selected: {first},
        showSelectedIcon: false,
        style: SegmentedButton.styleFrom(visualDensity: const VisualDensity(horizontal: -4, vertical: -4), textStyle: const TextStyle(fontSize: 11), padding: const EdgeInsets.symmetric(horizontal: 6)),
        onSelectionChanged: (v) => setState(() => onChanged(v.first)),
      );

  /// ランクと数値の小さな札（例：捕 C 62）
  Widget _chip(String label, int v, {bool main = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
        decoration: BoxDecoration(
          color: main ? const Color(0xFFFEF3C7) : Colors.white,
          border: Border.all(color: main ? const Color(0xFFF59E0B) : _line),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: const TextStyle(fontSize: 9.5, color: _sub)),
          const SizedBox(width: 2),
          _grade(v, size: 11.5),
          Text('$v', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()])),
        ]),
      );

  List<Widget> _battingLines() => [
        _abilityLine('弾道', p.trajectory * 25, shown: '${p.trajectory}'),
        _abilityLine('ミート', p.contact),
        _abilityLine('　対左', p.contactLeft),
        _abilityLine('　対右', p.contactRight),
        _abilityLine('パワー', p.power),
        _abilityLine('選球眼', p.eye),
        _abilityLine('チャンス', p.clutch),
        if (BattingSplits.courseSummary(p) != null)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text('コース　${BattingSplits.courseSummary(p)}', style: const TextStyle(fontSize: 10.5, color: _sub)),
          ),
      ];

  List<Widget> _pitchingLines() => [
        _abilityLine('球速', p.velocityNorm, shown: '${p.velocity}km'),
        _abilityLine('球威', p.pitchPower),
        _abilityLine('制球', p.control),
        _abilityLine('スタミナ', p.stamina),
        _abilityLine('ピンチ', p.clutchPitching),
        _abilityLine('クイック', p.quick),
        _abilityLine('腕の角度', 50, shown: '${p.spinAxis}°', note: p.armSlot),
      ];

  List<Widget> _fieldingLines() {
    const posList = [('投', '投手'), ('捕', '捕手'), ('一', '一塁手'), ('二', '二塁手'), ('三', '三塁手'), ('遊', '遊撃手'), ('左', '左翼手'), ('中', '中堅手'), ('右', '右翼手')];
    int apt(String k) => switch (k) { '投' => p.fieldP, '捕' => p.fieldC, '一' => p.field1B, '二' => p.field2B, '三' => p.field3B, '遊' => p.fieldSS, '左' => p.fieldLF, '中' => p.fieldCF, _ => p.fieldRF };
    return [
      _abilityLine('走力', p.run),
      _abilityLine('肩力', p.arm),
      _abilityLine('送球', p.throwAccuracy),
      _abilityLine('捕球', p.catchSkill),
      const Padding(padding: EdgeInsets.only(top: 4, bottom: 2), child: Text('守備適性', style: TextStyle(fontSize: 10, color: _sub))),
      Wrap(spacing: 3, runSpacing: 3, children: [
        for (final pos in posList) _chip(pos.$1, apt(pos.$1), main: pos.$2 == p.mainPosition),
      ]),
    ];
  }

  List<Widget> _pitchLines() => [
        for (final x in p.pitches)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 3),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF5F5F4)))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${x.name}　${x.speed}km・${x.ratio}%', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (x.breakLevel > 0) ...[_chip('変化', x.breakLevel), const SizedBox(width: 3)],
                  _chip('キレ', x.sharpness),
                  const SizedBox(width: 3),
                  _chip('重さ', x.heaviness),
                ]),
              ),
            ]),
          ),
        if (p.pitches.isEmpty) const Text('持ち球なし', style: TextStyle(fontSize: 11, color: _sub)),
      ];

  Widget _abilityColumns() {
    final leftFirst = p.isPitcher ? !_leftBat : _leftBat; // 本職の方が「1つ目」
    final rightFirst = p.isPitcher ? !_rightField : _rightField;
    final left = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: Text(_leftBat ? '打撃' : '投球', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900))),
        p.isPitcher
            ? _switch('投球', '打撃', leftFirst, (v) => _leftBat = !v)
            : _switch('打撃', '投球', leftFirst, (v) => _leftBat = v),
      ]),
      const SizedBox(height: 2),
      ...(_leftBat ? _battingLines() : _pitchingLines()),
    ]);
    final right = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Flexible(child: Text(_rightField ? '守備・走塁' : '球種', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900))),
        if (!_rightField)
          InkWell(
            onTap: () => showPitchCatalog(context),
            borderRadius: BorderRadius.circular(10),
            child: const Padding(padding: EdgeInsets.all(2), child: Icon(Icons.help_outline, size: 15, color: _sub)),
          ),
        const Spacer(),
        p.isPitcher
            ? _switch('球種', '守備', rightFirst, (v) => _rightField = !v)
            : _switch('守備', '球種', rightFirst, (v) => _rightField = v),
      ]),
      const SizedBox(height: 2),
      ...(_rightField ? _fieldingLines() : _pitchLines()),
    ]);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: left),
      const SizedBox(width: 10),
      Expanded(child: right),
    ]);
  }

  // ---------------- 年度別＋通算の成績 ----------------
  static String _rate(double v) => v.toStringAsFixed(3).replaceFirst(RegExp(r'^0'), '');
  static String _ip(int outs) => '${outs ~/ 3}${outs % 3 == 0 ? '' : '.${outs % 3}'}';

  List<String> get _cols => _mode == '守備'
      ? const ['年度', '団', '先発', '守備回', '刺殺', '補殺', '失策', '併殺', '守備率', '盗塁企図', '阻止', '阻止率', '守備位置（イニング）']
      : _tblPitch
          ? const ['年度', '団', '登板', '先発', '勝', '敗', 'H', 'S', '完投', '完封', '投球回', '被安打', '被本', '奪三振', '与四球', '与死球', '自責点', '防御率', 'WHIP']
          : const ['年度', '団', '試合', '打席', '打数', '得点', '安打', '二塁打', '三塁打', '本塁打', '塁打', '打点', '盗塁', '盗塁死', '四球', '死球', '三振', '猛打賞', '打率', '得点圏', '出塁率', '長打率', 'OPS'];

  /// 守備位置ごとのイニング「遊 120.1　二 30」（多い順）
  static String _posInnings(PlayerStats s) {
    final e = s.posOuts.entries.where((x) => x.value > 0).toList()..sort((a, b) => b.value.compareTo(a.value));
    return e.isEmpty ? '-' : e.map((x) => '${x.key} ${_ip(x.value)}').join('　');
  }

  /// 別リーグ（海外・独立）の来歴行を成績表の列へ変換する（古い順）
  List<List<String>> _abroadRows() {
    final out = <List<String>>[];
    final lineRe = RegExp(r'^(\d{4})\s*[　 ]\s*([^　 ]+)\s*[　 ]\s*(.+)$');
    for (var i = p.abroad.length - 1; i >= 0; i--) {
      final line = p.abroad[i];
      final lm = lineRe.firstMatch(line);
      if (lm == null) continue;
      final year = lm.group(1)!, lg = lm.group(2)!, body = lm.group(3)!;
      if (_tblPitch ? !body.contains('防御率') : !body.contains('打率')) continue;
      final s = i < p.abroadStats.length ? p.abroadStats[i] : AbroadStats.fromLine(p, line, isPitcher: _tblPitch);
      final yNum = int.tryParse(year);
      final label = (yNum != null && yNum < 2026 && !lg.endsWith('*')) ? '$lg*' : lg;
      out.add(_cells(year, label, s));
    }
    return out;
  }

  List<String> _cells(String year, String team, PlayerStats s) {
    if (_mode == '守備') {
      final starts = s.posGames.values.fold<int>(0, (a, b) => a + b);
      final ch = s.putouts + s.assists + s.errors;
      return [year, team, '$starts', _ip(s.defOuts), '${s.putouts}', '${s.assists}', '${s.errors}', '${s.dpTurned}', ch == 0 ? '-' : ((s.putouts + s.assists) / ch).toStringAsFixed(3).replaceFirst(RegExp(r'^0'), ''),
        '${s.sbAgainst + s.csAgainst}', '${s.csAgainst}', s.sbAgainst + s.csAgainst == 0 ? '-' : (s.csAgainst / (s.sbAgainst + s.csAgainst)).toStringAsFixed(3).replaceFirst(RegExp(r'^0'), ''),
        _posInnings(s)];
    }
    if (_tblPitch) {
      final ip = s.inningsPitched / 3.0;
      return [year, team, '${s.apps}', '${s.starts}', '${s.wins}', '${s.losses}', '${s.holds}', '${s.saves}', '${s.completeGames}', '${s.shutouts}', _ip(s.inningsPitched), '${s.hitsAllowed}', '${s.hrAllowed}', '${s.pitcherStrikeouts}', '${s.pitcherWalks}', '${s.hbpAllowed}', '${s.earnedRuns}',
        s.inningsPitched == 0 ? '-' : s.era.toStringAsFixed(2), ip == 0 ? '-' : ((s.hitsAllowed + s.pitcherWalks) / ip).toStringAsFixed(2)];
    }
    final pa = s.atBats + s.walks + s.sacFlies + s.hbp;
    final obp = pa == 0 ? 0.0 : (s.hits + s.walks + s.hbp) / pa;
    final tb = s.hits + s.doubles + s.triples * 2 + s.homeRuns * 3;
    final slg = s.atBats == 0 ? 0.0 : tb / s.atBats;
    return [year, team, '${s.games}', '$pa', '${s.atBats}', '${s.runs}', '${s.hits}', '${s.doubles}', '${s.triples}', '${s.homeRuns}', '$tb', '${s.rbi}', '${s.stolenBases}', '${s.caughtStealing}', '${s.walks}', '${s.hbp}', '${s.strikeouts}', '${s.mouda}',
      s.atBats == 0 ? '-' : _rate(s.battingAverage), s.rispAB == 0 ? '-' : _rate(s.rispAvg), pa == 0 ? '-' : _rate(obp), s.atBats == 0 ? '-' : _rate(slg), pa == 0 ? '-' : _rate(obp + slg)];
  }

  /// 球団の略称。同じリーグでシーズン途中に移った分は「東京新聞/神戸」
  String _teamName(String id, {bool initial = false}) {
    String one(String x) {
      for (final t in (app.teams as List<Team>)) {
        if (t.id == x) return initial ? teamInitial(t) : teamShort(t);
      }
      return '−';
    }
    return id.split('/').map(one).join('/');
  }

  Widget _statsTable() {
    final toggle = SegmentedButton<String>(
      segments: const [ButtonSegment(value: '1軍', label: Text('1軍')), ButtonSegment(value: '2軍', label: Text('2軍')), ButtonSegment(value: '3軍', label: Text('3軍')), ButtonSegment(value: '守備', label: Text('守備'))],
      selected: {_mode},
      showSelectedIcon: false,
      style: SegmentedButton.styleFrom(visualDensity: const VisualDensity(horizontal: -4, vertical: -4), textStyle: const TextStyle(fontSize: 11), padding: const EdgeInsets.symmetric(horizontal: 8)),
      onSelectionChanged: (v) => setState(() => _mode = v.first),
    );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _title('年度別成績（${_mode == '守備' ? '1軍・守備' : _mode}）', trailing: toggle),
      if (p.twoWay && _mode != '守備')
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: _switch('打撃', '投球', !_tblPitch, (v) => _tblPitch = !v),
          ),
        ),
      FutureBuilder<(List<(int, String, PlayerStats, PlayerStats)>, List<PreYear>)>(
        future: _both,
        builder: (context, snap) {
          final hist = snap.data?.$1 ?? const [];
          final pre = snap.data?.$2 ?? const <PreYear>[];
          final sy = app.startYear as int;
          _ensureProHistory({for (final h in hist) h.$1, for (final y in pre) y.year});
          final rows = <List<String>>[];
          final total = PlayerStats();
          final known = PlayerStats(); // 年度別の記録がある分の1軍成績（通算との差は「それ以前」）
          for (final h in hist) {
            if (_mode == '3軍') continue; // 3軍は今季の分だけ
            final s = _farm ? h.$4 : h.$3;
            known.add(h.$3);
            if (s.games == 0 && s.pitchApps == 0) continue;
            rows.add(_cells('${h.$1}', _teamName(h.$2, initial: true), s));
            total.add(s);
          }
          final isOpen = _otherTeam == null && (app is AppState) && (app as AppState).openPeriod;
          final now = _mode == '3軍' ? p.thirdStats : (_farm ? p.farmStats : (isOpen ? p.shownStats : p.seasonStats));
          final t = _team;
          if (_mode == '1軍' || _mode == '守備') {
            // ゲーム開始前の経歴：年度別の推定（球団の後ろに＊）。推定が作れないときは推定年度を生成して埋める
            if (pre.isNotEmpty) {
              rows.insertAll(0, [for (final y in pre) _cells('${y.year}', '${_teamName(y.teamId, initial: true)}*', y.stats)]);
              for (final y in pre) {
                total.add(y.stats);
              }
            } else {
              final all = PlayerStats()..add(p.career);
              if (all.games > known.games || all.pitchApps > known.pitchApps) {
                final diff = _minus(all, known);
                rows.insert(0, _cells('〜${hist.isEmpty ? sy - 1 : hist.first.$1 - 1}', '*', diff));
                total.add(diff);
              } else if (_otherTeam == null && p.proYears > 1 && hist.isEmpty && !p.joinedInGame && _mode == '1軍') {
                final estYears = CareerEngine.estimateYears(p);
                final firstY = sy - estYears.length;
                final tid = t?.id ?? '';
                for (var i = 0; i < estYears.length; i++) {
                  rows.add(_cells('${firstY + i}', '${_teamName(tid, initial: true)}*', estYears[i]));
                  total.add(estYears[i]);
                }
              }
            }
          }
          // 今季：他リーグで分けた分は別の行、同じリーグの移籍は「前/今」の球団で1行。
          //  シーズンを締めた後（オフ）は今季の分も年度別の記録にあるので、二重に出さない
          final closed = _mode != '3軍' && hist.any((h) => h.$1 == sy);
          for (final sp in _mode == '3軍' || closed ? const <Map>[] : p.seasonSplits) {
            final m = sp[_farm ? 'farm' : 'stats'];
            if (m is! Map) continue;
            final st = PlayerStats.fromJson(Map<String, dynamic>.from(m));
            if (st.games == 0 && st.pitchApps == 0) continue;
            rows.add(_cells('$sy', _teamName('${sp['team']}', initial: true), st));
            total.add(st);
          }
          if ((now.games > 0 || now.pitchApps > 0) && !closed) {
            final curTeamLabel = _otherTeam != null
                ? _otherTableTeam
                : (t == null ? '−' : _teamName([...p.seasonTeams, t.id].join('/'), initial: true));
            rows.add(_cells(isOpen ? '$sy(OP)' : '$sy', curTeamLabel, now));
            if (!isOpen) total.add(now);
          }
          if (_mode == '1軍' && p.abroad.isNotEmpty) {
            final abRows = _abroadRows();
            final merged = <(int, int, List<String>)>[
              for (var i = 0; i < abRows.length; i++) (int.tryParse(abRows[i][0]) ?? 0, i, abRows[i]),
              for (var i = 0; i < rows.length; i++) (int.tryParse(rows[i][0].replaceAll(RegExp(r'[^0-9]'), '')) ?? 0, 1000 + i, rows[i]),
            ]..sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
            rows
              ..clear()
              ..addAll(merged.map((e) => e.$3));
          }
          final cols = _cols;
          final totalRow = rows.length > 1 || (!_farm && _mode != '3軍') ? _cells('通算', '', total) : null;
          if (rows.isEmpty) {
            return Padding(padding: const EdgeInsets.all(8), child: Text('${_mode}の成績はありません', style: const TextStyle(fontSize: 11.5, color: _sub)));
          }
          const rates = {'打率', '得点圏', '出塁率', '長打率', 'OPS', '防御率', 'WHIP', '守備率', '阻止率'};
          double wOf(String h) => h == '守備位置（イニング）' ? 200 : (rates.contains(h) ? 38 : (h.length <= 2 ? 38 : (h.length == 3 ? 40 : 46)));
          Widget lead(List<String> c, {bool bold = false}) => Row(children: [
                SizedBox(width: 40, child: Text(c[0], maxLines: 1, style: TextStyle(fontSize: 11, fontWeight: bold ? FontWeight.w900 : FontWeight.w800))),
                Expanded(child: Text(c[1], maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, color: c[1].endsWith('*') ? _sub : _ink))),
              ]);
          final boldAll = [for (var i = 2; i < cols.length; i++) const TextStyle(fontWeight: FontWeight.w800)];
          return FrozenTable(
            leadHeader: '年度・団',
            leadWidth: 98,
            rowHeight: 22,
            compact: true,
            headers: cols.sublist(2),
            widths: [for (final h in cols.sublist(2)) wOf(h)],
            rows: [
              for (final r in rows) FrozenRow(lead: lead(r), cells: r.sublist(2)),
              if (totalRow != null) FrozenRow(lead: lead(totalRow, bold: true), cells: totalRow.sublist(2), color: const Color(0xFFFEF9C3), styles: boldAll),
            ],
          );
        },
      ),
      const Text('団＝球団の頭文字。2軍の年度別成績は、このゲームで終えたシーズンの分です', style: TextStyle(fontSize: 9.5, color: _sub)),
      if (_mode == '1軍' && p.abroad.isNotEmpty)
        const Text('他リーグ（海外・独立）の成績は上段に表示しています（NPB通算には含みません）', style: TextStyle(fontSize: 9.5, color: _sub)),
    ]);
  }

  /// 打撃の詳しい成績（1軍）：コース・打球方向・球種・球速ごとに、通算・過去3年・今季を「.275(40-11) HR 1 K 3」で
  ///  pit：投手の被打率（同じ項目の頭に p。コースは打者から見た向き）
  Widget _splitsSection(List<(int, String, PlayerStats, PlayerStats)> hist, {bool pit = false}) {
    final pre = pit ? 'p' : '';
    final y = app.startYear as int;
    final closed = hist.any((h) => h.$1 == y); // オフ：今季の分も年度別の記録にある
    final now = PlayerStats(), past = PlayerStats(), total = PlayerStats();
    for (final h in hist) {
      total.add(h.$3);
      if (h.$1 == y) now.add(h.$3);
      if (h.$1 >= y - 3 && h.$1 <= y - 1) past.add(h.$3);
    }
    if (!closed) {
      final isOpen = _otherTeam == null && (app is AppState) && (app as AppState).openPeriod;
      for (final sp in p.seasonSplits) {
        if (sp['stats'] is Map) {
          final st = PlayerStats.fromJson(Map<String, dynamic>.from(sp['stats'] as Map));
          now.add(st);
          total.add(st);
        }
      }
      now.add(isOpen ? p.shownStats : p.seasonStats);
      if (!isOpen) total.add(p.seasonStats);
    }
    final rows = switch (_splKind) {
      0 => [for (var i = 1; i <= 25; i++) ('$i', '${pre}c$i')],
      1 => [for (var i = 0; i < 5; i++) (BattingSplits.dirNames[i], '${pre}d$i')],
      2 => [for (final t in BattingSplits.typeNames) (t, '${pre}t$t')],
      _ => [for (var i = 0; i < BattingSplits.speedNames.length; i++) (BattingSplits.speedNames[i], '${pre}v$i')],
    };
    final k = _splKind != 1;
    final toggle = SegmentedButton<int>(
      segments: const [ButtonSegment(value: 0, label: Text('コース')), ButtonSegment(value: 1, label: Text('方向')), ButtonSegment(value: 2, label: Text('球種')), ButtonSegment(value: 3, label: Text('球速'))],
      selected: {_splKind},
      showSelectedIcon: false,
      style: SegmentedButton.styleFrom(visualDensity: const VisualDensity(horizontal: -4, vertical: -4), textStyle: const TextStyle(fontSize: 11), padding: const EdgeInsets.symmetric(horizontal: 6)),
      onSelectionChanged: (v) => setState(() => _splKind = v.first),
    );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _title(pit ? '被打率の詳細（1軍）' : '打撃の詳細（1軍）', trailing: toggle),
      if (_splKind <= 1) ...[
        // 期間の切り替え
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: SegmentedButton<int>(
            segments: [const ButtonSegment(value: 0, label: Text('今季')), ButtonSegment(value: 1, label: Text('${y - 3}〜${y - 1}')), const ButtonSegment(value: 2, label: Text('通算'))],
            selected: {_splPeriod},
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(visualDensity: const VisualDensity(horizontal: -4, vertical: -4), textStyle: const TextStyle(fontSize: 11)),
            onSelectionChanged: (v) => setState(() => _splPeriod = v.first),
          ),
        ),
        if (_splKind == 0) _courseGrid([now, past, total][_splPeriod], pre) else _sprayFan([now, past, total][_splPeriod], pre),
      ] else
        FrozenTable(
          leadHeader: const ['コース', '打球方向', '球種', '球速'][_splKind],
          leadWidth: 72,
          rowHeight: 32,
          compact: true,
          cellLines: 2,
          headers: ['通算', '${y - 3}〜${y - 1}', '今季'],
          widths: const [80, 80, 80],
          rows: [
            for (final r in rows)
              FrozenRow(
                lead: Text(r.$1, maxLines: 2, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, height: 1.1)),
                cells: [for (final x in [total, past, now]) BattingSplits.text(x.spl[r.$2], k: k, sep: '\n')],
              ),
          ],
        ),
      Text(
        [
          pit ? '被打率＝打たれた安打÷対戦した打者の打数（打数-安打。HR＝被本塁打・K＝奪三振）。' : '（打数-安打）。',
          if (_splKind == 0) '打者から見たマス（左＝内角・上＝高め。左上の小さな数字が1〜25の番号）。太枠＝ストライクゾーン。色は打率（赤いほど高く、青いほど低い）。打席の最後の1球の位置。',
          if (_splKind == 1) 'フェアゾーンを左から5等分。前に飛んだ打球だけ（三振は入りません）。色は打率。',
          if (_splKind >= 2) '打席の最後の1球の球種・球速。速球系＝ツーシーム・シュートなど。',
          'この記録は今回の更新から数えています（自球団の選手は今季の初めから）。過去の年の分はありません',
        ].join(''),
        style: const TextStyle(fontSize: 9.5, color: _sub),
      ),
    ]);
  }

  /// コース：5×5のマスに打率・（打数-安打）・HR と K を書き込む
  Widget _courseGrid(PlayerStats st, [String pre = '']) {
    const cellH = 58.0, headH = 16.0;
    Widget cell(int n) {
      final v = st.spl['${pre}c$n'];
      final has = v != null && v[0] > 0;
      return Container(
        height: cellH,
        decoration: BoxDecoration(color: splitHeat(v), border: Border.all(color: const Color(0xFFD6D3D1), width: 0.5)),
        child: Stack(children: [
          Positioned(left: 2, top: 1, child: Text('$n', style: const TextStyle(fontSize: 8.5, color: _sub))),
          Center(
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: has
                  ? FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text((v[1] / v[0]).toStringAsFixed(3).replaceFirst(RegExp(r'^0'), ''), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900, height: 1.1)),
                        Text('(${v[0]}-${v[1]})', style: const TextStyle(fontSize: 9.5, height: 1.1)),
                        Text('HR ${v[2]} K ${v[3]}', style: const TextStyle(fontSize: 9, color: Color(0xFF44403C), height: 1.15)),
                      ]),
                    )
                  : const Text('-', style: TextStyle(fontSize: 10, color: _sub)),
            ),
          ),
        ]),
      );
    }

    // ストライクゾーン（真ん中の3×3）を太枠で囲む
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth / 5;
      return Stack(children: [
        Column(children: [
          const SizedBox(
            height: headH,
            child: Row(children: [
              Text('◀ 内角', style: TextStyle(fontSize: 9.5, color: _sub)),
              Expanded(child: Text('▲ 高め（打者から見て）', textAlign: TextAlign.center, style: TextStyle(fontSize: 9.5, color: _sub))),
              Text('外角 ▶', style: TextStyle(fontSize: 9.5, color: _sub)),
            ]),
          ),
          for (var r = 0; r < 5; r++) Row(children: [for (var cc = 0; cc < 5; cc++) Expanded(child: cell(r * 5 + cc + 1))]),
        ]),
        Positioned(left: w, top: headH + cellH, width: w * 3, height: cellH * 3, child: IgnorePointer(child: Container(decoration: BoxDecoration(border: Border.all(color: _ink, width: 2))))),
      ]);
    });
  }

  /// 打球方向：球場を5つに分けた扇形に書き込む
  Widget _sprayFan(PlayerStats st, [String pre = '']) => AspectRatio(
        aspectRatio: 1.45,
        child: CustomPaint(painter: _SprayPainter([for (var i = 0; i < 5; i++) st.spl['${pre}d$i']])),
      );

  /// a − b（通算から、年度別の記録がある分を引いた残り）
  PlayerStats _minus(PlayerStats a, PlayerStats b) {
    final ja = a.toJson(), jb = b.toJson();
    final out = <String, dynamic>{};
    ja.forEach((k, v) {
      if (v is int) {
        final d = v - ((jb[k] ?? 0) as int);
        out[k] = d < 0 ? 0 : d;
      }
      if (v is Map && v.values.every((x) => x is int)) {
        // 守備位置ごとの試合・イニング
        final bm = (jb[k] as Map?) ?? const {};
        out[k] = {for (final e in v.entries) if ((e.value as int) - ((bm[e.key] ?? 0) as int) > 0) e.key: (e.value as int) - ((bm[e.key] ?? 0) as int)};
      }
    });
    return PlayerStats.fromJson(out);
  }


  // ---------------- 表彰・タイトル・記録 ----------------
  static const _posLeaderKeys = ['最多二塁打', '最多三塁打', '最多四球', '最高長打率', '最高OPS', '最多登板'];
  static const _negLeaderKeys = ['最多三振'];
  static bool _isPosLeader(String h) => _posLeaderKeys.any((k) => h.contains(k));
  static bool _isNegLeader(String h) => _negLeaderKeys.any((k) => h.contains(k));
  static bool _isLeaderRecord(String h) => _isPosLeader(h) || _isNegLeader(h);
  static bool _isRecord(String h) => h.contains('達成') || h.contains('プロ初') || _isLeaderRecord(h);
  List<String> get _titles => [for (final h in p.honors) if (!_isRecord(h)) h];

  /// 入団の経緯。記録が無い選手は、プロ年数・出身から推定（ゲーム開始時の球団に入団したとする）
  String _entryText(List<PreYear> pre, List<(int, String, PlayerStats, PlayerStats)> hist) {
    const draft = {'A': '高校', 'B': '大学', 'C': '社会人など'};
    final sy = app.startYear as int;
    if (_otherTeam != null) {
      final startY = CareerPath.proStartYear(p, sy, inOtherLeague: true, knownProYears: [for (final y in pre) y.year, for (final h in hist) h.$1]);
      return '$startY年 プロ入り　プロ${_displayProYears}年目（$_otherLabel）${p.origin.isNotEmpty ? '　${p.origin}出身' : ''}';
    }
    final entry = sy - p.proYears + 1;
    if (p.draftInfo.isNotEmpty) return '${p.draftInfo}　プロ${p.proYears}年目${p.origin.isNotEmpty ? '　${p.origin}出身' : ''}';
    final teamId = pre.isNotEmpty ? pre.first.teamId : (hist.isNotEmpty ? hist.first.$2.split('/').first : (_team?.id ?? ''));
    final tn = _teamName(teamId);
    if (p.nationality == '海外') return '$entry年 来日・$tnに入団（推定）　プロ${p.proYears}年目';
    // 推定のドラフト順位：入団時の能力が高いほど上位（選手ごとに毎回同じ）
    final base = p.baseline['ovr'] ?? p.ovr;
    final rnd = Random(p.id.hashCode ^ 0xd4af);
    final round = (1 + ((76 - base) / 6).round() + rnd.nextInt(3) - 1).clamp(1, 8);
    final rank = p.ikusei ? '育成${(round - 2).clamp(1, 6)}位' : '$round位';
    final indie = CareerPath.indieTeamLabel(p);
    final fromLabel = indie != null ? '独立・$indie' : (draft[p.draftType] ?? p.draftType);
    return '${entry - 1}年 ドラフト$rankで$tnに入団（推定・${fromLabel}から）　プロ${p.proYears}年目${p.origin.isNotEmpty ? '　${p.origin}出身' : ''}';
  }

  // ---------------- フォーム・道具タブ ----------------
  /// 自球団の選手はここでフォーム・道具を変えられる（変えるとすぐ保存）。体格は見るだけ。他球団の選手は見るだけ
  List<(String, Widget)> _formGearItems() => [
        ('§体格', const SizedBox()),
        ('身長', Text('${p.height}cm')),
        ('体重', Text('${p.weight}kg')),
        ('腕の長さ', Text('${p.armLength}cm')),
        ('頭囲', Text('${p.headGirth}cm')),
        ('胸囲', Text('${p.chestGirth}cm')),
        ('腹囲', Text('${p.waistGirth}cm')),
        ('臀囲', Text('${p.hipGirth}cm')),
        ('§用具', const SizedBox()),
        ('バット長', Text('${p.bat.length.toStringAsFixed(1)}cm')),
        ('バット重', Text('${p.bat.weight.round()}g')),
        ('バランス', Text(p.bat.balance)),
        ('グラブ', Text('${p.glove.length.toStringAsFixed(1)}cm')),
        ('ポケット', Text(p.glove.pocket)),
        if (p.canPitch) ...[
          ('§フォーム', const SizedBox()),
          ('腕の位置', Text(p.armSlot)),
          ('腕の角度', Text('${p.spinAxis}°')),
          ('始動', Text(p.form.windup)),
          ('足の上げ方', Text(p.form.legKickType)),
          ('テイクバック', Text(p.form.takebackType)),
          ('体重移動', Text(p.form.driveType)),
          ('踏み出し', Text(p.form.stepType)),
          ('歩幅', Text('${p.form.strideRatio}%')),
          ..._releaseRows(),
        ],
      ];

  Widget _formGearView() {
    final app = widget.appState as AppState;
    final mine = app.myTeam?.players.contains(p) ?? false;
    if (!mine) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _infoGrid(_formGearItems()),
        const SizedBox(height: 6),
        const Text('他球団の選手は見るだけです', style: TextStyle(fontSize: 11, color: _sub)),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _infoGrid(_formGearItems()),
      const SizedBox(height: 8),
      BodyFormEditor(key: ValueKey('fg${p.id}'), player: p, bodyEditable: false, embedded: true, onChanged: () {
        app.updateAndSave();
        setState(() {});
      }),
    ]);
  }

  // ---------------- 経歴タブ ----------------
  /// 経歴タブ（案C）：成績（年度別の表＋通算）・表彰・年表（移籍）・能力の変化の小さなタブ
  Widget _careerView() {
    // 表彰・記録を年ごとに（実際の記録）
    final byYear = <int, List<String>>{};
    for (final h in p.honors) {
      final m = RegExp(r'^(\d{4})年').firstMatch(h);
      byYear.putIfAbsent(m == null ? 0 : int.parse(m.group(1)!), () => []).add(h);
    }
    (String, Color, Color, Color) honorStyle(String h) {
      if (h.contains('保持者') || h.contains('NPB記録') || h.contains('日本記録') || h.contains('歴代1位') || h.contains('シーズン最多')) {
        return ('現1位記録', const Color(0xFFFFE4E6), const Color(0xFFFB7185), const Color(0xFF9F1239));
      }
      if (_isNegLeader(h)) {
        return ('記録(－)', const Color(0xFFE2E8F0), const Color(0xFF94A3B8), const Color(0xFF334155));
      }
      if (_isPosLeader(h)) {
        return ('記録(＋)', const Color(0xFFCCFBF1), const Color(0xFF2DD4BF), const Color(0xFF0F766E));
      }
      if (h.contains('連続')) {
        return ('連続記録', const Color(0xFFDCFCE7), const Color(0xFF4ADE80), const Color(0xFF166534));
      }
      if (h.contains('ベストナイン') || h.contains('ゴールデングラブ') || h.contains('月間MVP') || h.contains('新人王') || h.contains('カムバック賞')) {
        return ('表彰', const Color(0xFFF3E8FF), const Color(0xFFC084FC), const Color(0xFF6B21A8));
      }
      if (h.contains('通算') || h.contains('達成') || h.contains('プロ初') || h.contains('ノーヒット') || h.contains('完全試合') || h.contains('サイクル安打')) {
        return ('通算記録', const Color(0xFFDBEAFE), const Color(0xFF60A5FA), const Color(0xFF1E40AF));
      }
      return ('タイトル', const Color(0xFFFEF3C7), const Color(0xFFF59E0B), const Color(0xFF92400E));
    }

    String enrichLeaderText(String raw, PlayerStats st) {
      if (raw.contains('（')) return raw;
      if (raw.contains('最多二塁打') && st.doubles > 0) return '$raw（${st.doubles}二塁打）';
      if (raw.contains('最多三塁打') && st.triples > 0) return '$raw（${st.triples}三塁打）';
      if (raw.contains('最多四球') && st.walks > 0) return '$raw（${st.walks}四球）';
      if (raw.contains('最高長打率') && st.atBats > 0) return '$raw（${st.slg.toStringAsFixed(3).replaceFirst(RegExp(r'^0'), '')}）';
      if (raw.contains('最高OPS') && st.plateAppearances > 0) return '$raw（${st.ops.toStringAsFixed(3).replaceFirst(RegExp(r'^0'), '')}）';
      if (raw.contains('最多三振') && st.strikeouts > 0) return '$raw（${st.strikeouts}三振）';
      if (raw.contains('最多登板') && st.apps > 0) return '$raw（${st.apps}登板）';
      return raw;
    }

    Widget honorRow(String yearText, String h, PlayerStats st, {bool est = false}) {
      final (cat, bg, border, fg) = honorStyle(h);
      final dm = RegExp(r'^(\d{4})年(?:(\d+)月(\d+)日)?\s*(.*)$').firstMatch(h);
      final dateLabel = dm != null && dm.group(2) != null ? '${dm.group(1)}/${dm.group(2)}/${dm.group(3)}' : yearText;
      final body = enrichLeaderText(dm != null ? dm.group(4)! : h, st);
      final text = body + (est ? '（推定）' : '');
      return Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: est ? Colors.white : bg.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: border.withValues(alpha: 0.7)),
        ),
        child: Row(children: [
          SizedBox(width: 76, child: Text(dateLabel, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800))),
          Container(
            width: 66,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 1),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(3), border: Border.all(color: border)),
            child: Text(cat, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: fg)),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 11.5, color: _ink))),
        ]),
      );
    }

    final total = app.careerTotalOf(p) as PlayerStats;
    return FutureBuilder<(List<(int, String, PlayerStats, PlayerStats)>, List<PreYear>)>(
      future: _both,
      builder: (context, snap) {
        final hist = snap.data?.$1 ?? const <(int, String, PlayerStats, PlayerStats)>[];
        final pre = snap.data?.$2 ?? const <PreYear>[];
        final preYears = {for (final y in pre) y.year};
        final years = <int>{...hist.map((h) => h.$1), app.startYear as int, ...byYear.keys.where((y) => y > 0 && !preYears.contains(y))};
        final first = hist.isEmpty ? app.startYear as int : hist.first.$1;
        final t = _team;
        // タイトル・表彰（実際＋推定）
        final estTitles = [for (final y in pre) for (final h in y.honors) if (!_isRecord(h)) h];
        // ---- 年度別の行（推定＝＊）----
        final rows = <(String, String, PlayerStats, List<String>, bool, bool)>[]; // 年・球団・成績・その年の表彰と記録・推定・今季
        if (pre.isNotEmpty) {
          for (final y in pre) {
            rows.add(('${y.year}＊', _teamName(y.teamId), y.stats, [...byYear[y.year] ?? const <String>[], ...y.honors], true, false));
          }
        } else if (p.career.games > hist.fold<int>(0, (a, h) => a + h.$3.games)) {
          rows.add(('〜${first - 1}', '開始前', _minus(p.career, hist.fold(PlayerStats(), (a, h) => a..add(h.$3))), byYear[0] ?? const <String>[], true, false));
        }
        for (final y in years.toList()..sort()) {
          final rowsY = hist.where((h) => h.$1 == y).toList();
          final hs = byYear[y] ?? const <String>[];
          if (y == app.startYear && rowsY.isEmpty) {
            for (final sp in p.seasonSplits) {
              final st = sp['stats'] is Map ? PlayerStats.fromJson(Map<String, dynamic>.from(sp['stats'] as Map)) : PlayerStats();
              rows.add(('$y', _teamName('${sp['team']}'), st, const <String>[], false, false));
            }
            rows.add(('$y', t == null ? '−' : _teamName(t.id), p.seasonStats, hs, false, true));
          } else if (rowsY.isEmpty) {
            if (hs.isNotEmpty) rows.add(('$y', '', PlayerStats(), hs, false, false));
          } else {
            for (var i = 0; i < rowsY.length; i++) {
              rows.add(('$y', _teamName(rowsY[i].$2), rowsY[i].$3, i == rowsY.length - 1 ? hs : const <String>[], false, false));
            }
          }
        }
        final pit = p.isPitcher && !p.twoWay;
        final statsView = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(_entryText(pre, hist), style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          _statsTable(),
          if (!p.isPitcher || p.twoWay) ...[const SizedBox(height: 8), _splitsSection(hist)],
          if (p.isPitcher || p.twoWay) ...[const SizedBox(height: 8), _splitsSection(hist, pit: true)],
          const SizedBox(height: 4),
          Text(
            pit
                ? '完投${total.completeGames}・完封${total.shutouts}・奪三振${total.pitcherStrikeouts}${total.noHitters + total.perfects > 0 ? '・ノーヒットノーラン${total.noHitters + total.perfects}' : ''}'
                : '安打${total.hits}・二塁打${total.doubles}・三塁打${total.triples}・猛打賞${total.mouda}',
            style: const TextStyle(fontSize: 10.5, color: _sub),
          ),
          if (pre.isNotEmpty)
            const Text('＊はゲーム開始前の推定（開始時の通算と合うように、全盛期と年ごとの調子から配分。所属は開始時の球団。タイトル・表彰は、その年の架空の歴代受賞者を上回ったときだけ）',
                style: TextStyle(fontSize: 9.5, color: _sub)),
          const SizedBox(height: 6),
          _title('記録（回数）'),
          ..._recordLines(total),
        ]);
        (int, int) honorMd(String h) {
          final m = RegExp(r'\d{4}年(\d+)月(\d+)日').firstMatch(h);
          if (m != null) return (int.parse(m.group(1)!), int.parse(m.group(2)!));
          final m2 = RegExp(r'\d{4}年(\d+)').firstMatch(h);
          return m2 != null ? (int.parse(m2.group(1)!), 1) : (11, 30);
        }
        final chronologicalHonors = <(int, int, int, String, String, PlayerStats, bool)>[
          for (final r in rows)
            for (final h in r.$4)
              (int.tryParse(r.$1.replaceAll(RegExp(r'[^0-9]'), '')) ?? 9999, honorMd(h).$1, honorMd(h).$2, r.$1, h, r.$3, r.$5),
        ]..sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : (a.$2 != b.$2 ? a.$2.compareTo(b.$2) : a.$3.compareTo(b.$3)));
        final honorsView = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (_titles.isNotEmpty || estTitles.isNotEmpty) ...[
            _honorsSection(estTitles),
            const SizedBox(height: 8),
          ],
          _title('表彰・記録（時系列）'),
          Wrap(spacing: 6, runSpacing: 4, children: [
            for (final b in const [
              ('タイトル', Color(0xFFFEF3C7), Color(0xFFF59E0B), Color(0xFF92400E)),
              ('表彰', Color(0xFFF3E8FF), Color(0xFFC084FC), Color(0xFF6B21A8)),
              ('記録(＋)', Color(0xFFCCFBF1), Color(0xFF2DD4BF), Color(0xFF0F766E)),
              ('記録(－)', Color(0xFFE2E8F0), Color(0xFF94A3B8), Color(0xFF334155)),
              ('連続記録', Color(0xFFDCFCE7), Color(0xFF4ADE80), Color(0xFF166534)),
              ('通算記録', Color(0xFFDBEAFE), Color(0xFF60A5FA), Color(0xFF1E40AF)),
              ('現1位記録', Color(0xFFFFE4E6), Color(0xFFFB7185), Color(0xFF9F1239)),
            ])
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(color: b.$2, borderRadius: BorderRadius.circular(3), border: Border.all(color: b.$3)),
                child: Text(b.$1, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: b.$4)),
              ),
          ]),
          const SizedBox(height: 6),
          if (chronologicalHonors.isEmpty)
            const Text('表彰・記録はまだありません', style: TextStyle(fontSize: 11.5, color: _sub))
          else
            for (final it in chronologicalHonors) honorRow(it.$4, it.$5, it.$6, est: it.$7),
        ]);
        final timelineView = FutureBuilder<List<(DateTime, String)>>(
          future: _timeline,
          builder: (context, tl) {
            // 記録のある分＋記録の無い分の推定（入団の年・ゲーム開始前のタイトルと節目。年だけ）
            final l = [...?tl.data];
            if (!l.any((x) => x.$2.contains('入団') || x.$2.contains('来日'))) {
              final entry = (app.startYear as int) - p.proYears + (p.nationality == '海外' ? 1 : 0);
              l.add((DateTime(entry, 12, 31, 23, 59), _entryText(pre, hist).split('　').first.replaceFirst(RegExp(r'^\d{4}年 ?'), '')));
            }
            for (final y in pre) {
              for (final h in y.honors) {
                if (_isLeaderRecord(h)) continue;
                l.add((DateTime(y.year, 12, 31, 23, 59), '${h.replaceFirst(RegExp(r'^\d{4}年 ?'), '')}（推定）。'));
              }
            }
            l.sort((a, b) => a.$1.compareTo(b.$1));
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _title(p.nationality == '海外' ? '来日までの経歴' : 'プロに入るまでの経歴'),
              for (final x in CareerPath.of(p)) Text('・$x', style: TextStyle(fontSize: 11.5, height: 1.4, color: x.endsWith('*') ? _sub : _ink)),
              const SizedBox(height: 6),
              _title('年表（入団・移籍・記録）'),
              if (l.isEmpty) const Text('年表の記録はまだありません', style: TextStyle(fontSize: 11, color: _sub)),
              for (final x in l) timelineLine(x.$1, x.$2),
            ]);
          },
        );
        final abilityView = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _title('能力の変化（${p.baselineNote.isEmpty ? '入団時' : p.baselineNote} → 今）'),
          _growthTable(),
        ]);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('成績')),
              ButtonSegment(value: 1, label: Text('表彰')),
              ButtonSegment(value: 2, label: Text('年表')),
              ButtonSegment(value: 3, label: Text('能力')),
            ],
            selected: {_careerSub},
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              textStyle: const TextStyle(fontSize: 12.5),
              selectedBackgroundColor: _ink,
              selectedForegroundColor: Colors.white,
            ),
            onSelectionChanged: (v) => setState(() => _careerSub = v.first),
          ),
          const SizedBox(height: 6),
          switch (_careerSub) {
            1 => honorsView,
            2 => timelineView,
            3 => abilityView,
            _ => statsView,
          },
        ]);
      },
    );
  }

  /// 経歴タブ：回数の記録（今季・通算）。連続記録は記録タブの「条件で探す」へ
  List<Widget> _recordLines(PlayerStats total) {
    final s = p.seasonStats;
    const st = TextStyle(fontSize: 11.5, height: 1.5);

    final lines = <String>[];
    if (!p.isPitcher || p.twoWay) {
      lines.add('マルチヒット 今季${s.multiHit}試合・通算${total.multiHit}試合　猛打賞 今季${s.mouda}・通算${total.mouda}');
      lines.add('2本塁打以上の試合 今季${s.multiHR}・通算${total.multiHR}　サヨナラ打 今季${s.walkoffs}・通算${total.walkoffs}　サイクル安打 通算${total.cycles}');
    }
    if (p.isPitcher || p.twoWay) {
      lines.add('クオリティスタート 今季${s.qs}・通算${total.qs}　2桁奪三振 今季${s.tenK}・通算${total.tenK}　完投 通算${total.completeGames}・完封 通算${total.shutouts}');
    }
    return [
      for (final l in lines) Text('・$l', style: st),
      const Text('連続記録（連続試合安打・連続打数安打・連続無失点など）は、記録タブの「条件で探す」で12球団の選手と並べて見られます', style: TextStyle(fontSize: 9.5, color: _sub)),
    ];
  }

  /// 経歴タブ：入団時（固有12はゲーム開始時）と今の能力
  Widget _growthTable() {
    final base = p.baseline;
    if (base.isEmpty) return const Text('入団時の能力の記録がありません', style: TextStyle(fontSize: 11.5, color: _sub));
    final labels = {'ovr': '総合', for (final s in GrowthEngine.statsOf(p)) s.key: s.label};
    final now = GrowthEngine.abilities(p);
    Widget row(String k) {
      final a = base[k], b = now[k];
      if (a == null || b == null) return const SizedBox.shrink();
      final d = b - a;
      String shown(int v) => k == 'velocity' ? '${v}km' : (k == 'maxEnergy' ? '$v' : '${GradeUtils.getGrade(v)}$v');
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 2),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF5F5F4)))),
        child: Row(children: [
          SizedBox(width: 84, child: Text(labels[k] ?? k, style: TextStyle(fontSize: 11.5, fontWeight: k == 'ovr' ? FontWeight.w900 : FontWeight.w500))),
          SizedBox(width: 60, child: Text(shown(a), textAlign: TextAlign.right, style: const TextStyle(fontSize: 11.5, color: _sub))),
          const SizedBox(width: 18, child: Text('→', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: _sub))),
          SizedBox(width: 60, child: Text(shown(b), textAlign: TextAlign.right, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700))),
          SizedBox(
            width: 50,
            child: Text(d == 0 ? '±0' : (d > 0 ? '+$d' : '$d'), textAlign: TextAlign.right, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: d > 0 ? const Color(0xFF15803D) : (d < 0 ? const Color(0xFFB91C1C) : _sub))),
          ),
        ]),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [for (final k in ['ovr', ...labels.keys.where((x) => x != 'ovr')]) row(k)]);
  }

  Widget _honorsSection([List<String> est = const []]) {
    // 同じ表彰はまとめて回数を出す（例：首位打者 ×3：2027・2028・2031）。推定（ゲーム開始前）の年は「＊」
    final groups = <String, List<String>>{};
    for (final h in [..._titles, ...est.map((e) => '$e＊')]) {
      final m = RegExp(r'^(\d{4})年(\S*?)\s?(.+)$').firstMatch(h);
      final key = m == null ? h : (m.group(2)!.isEmpty ? m.group(3)! : '${m.group(3)}');
      groups.putIfAbsent(key, () => []).add(m == null ? '' : '${m.group(1)}${m.group(2)}');
    }
    final total = app.careerTotalOf(p) as PlayerStats;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _title('タイトル・表彰（＊はゲーム開始前の推定）'),
      Wrap(spacing: 6, runSpacing: 4, children: [
        for (final e in groups.entries)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: const Color(0xFFFEF9C3), borderRadius: BorderRadius.circular(4), border: Border.all(color: const Color(0xFFFDE68A))),
            child: Text('${e.key}${e.value.length > 1 ? ' ×${e.value.length}' : ''}${e.value.first.isNotEmpty ? '（${e.value.join('・')}）' : ''}', style: const TextStyle(fontSize: 10.5)),
          ),
      ]),
      const SizedBox(height: 3),
      Text(
        p.isPitcher
            ? '通算 完投${total.completeGames}・完封${total.shutouts}${total.noHitters + total.perfects > 0 ? '・ノーヒットノーラン${total.noHitters + total.perfects}' : ''}'
            : '通算 猛打賞${total.mouda}・マルチヒット${total.multiHit}',
        style: const TextStyle(fontSize: 10.5, color: _sub),
      ),
    ]);
  }

  // ---------------- 寸評（能力から自動で作る） ----------------
  String _growthNote() {
    final (a, b) = GrowthEngine.peakRange(p);
    if (p.age < a) return 'ピーク $a〜$b歳。まだ伸びしろがある';
    if (p.age <= b) return 'ピーク $a〜$b歳。全盛期';
    return 'ピーク $a〜$b歳。衰えが出始める年齢';
  }

  String _comment() {
    // 体格・フォーム・球種の握り（キレ・重さ・変化量）・成績を組み合わせた寸評（AI なしでも読める文章）
    final lines = <String>[ScoutComment.of(p)];
    final named = {'ミート': p.contact, 'パワー': p.power, '走力': p.run, '選球眼': p.eye, '肩力': p.arm, '捕球': p.catchSkill};
    final weak = p.isPitcher ? <String>[] : named.entries.where((e) => e.value < 45).map((e) => e.key).toList();
    if (weak.isNotEmpty) lines.add('課題は${weak.join('・')}。');
    if (p.recovery < 45) lines.add('回復力が低く、連戦が続くと体力が落ちやすい。');
    if (p.recovery >= 65) lines.add('回復が早く、連戦に強い。');
    if (p.durability < 45) lines.add('故障しやすい点に注意。');
    if (p.talent >= 75) lines.add('才能に恵まれている。');
    if (p.ambition >= 75) lines.add('向上心が強く、練習熱心。');
    if (p.trust < 35) lines.add('監督への信頼が低く、サインを見落とすことがある。');
    lines.add('${GrowthCurve.label(p)}で、${_growthNote().split('。').last}。');
    final cond = p.conditionAt(app.currentDate as DateTime);
    if (cond <= -1) lines.add('いまは${ConditionFace.labels[cond]}で、能力を出し切れていない。');
    if (p.injuryDays > 0) lines.add('${p.injuryName}で残り${p.injuryDays}日。');
    return lines.join('');
  }

  Widget _commentSection() {
    final auto = _comment();
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: const Color(0xFFFAFAF9), border: Border.all(color: _line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('寸評', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: _ink)),
        FutureBuilder<List<(int, String, PlayerStats, PlayerStats)>>(
          future: _history,
          builder: (context, snap) {
            final style = const TextStyle(fontSize: 11.5, height: 1.5, color: Color(0xFF44403C));
            if (snap.connectionState != ConnectionState.done) return Text(auto, style: style);
            // 昨季（終わったシーズンのうち最後の年）
            final year = (app.startYear as int) - 1;
            PlayerStats? last;
            String lastTeam = '';
            for (final (y, tid, st, _) in snap.data ?? const <(int, String, PlayerStats, PlayerStats)>[]) {
              if (y != year) continue;
              last = st;
              lastTeam = ((app.teams as List<Team>).where((t) => t.id == tid).firstOrNull?.name) ?? '';
            }
            return AiText(
              item: AiFacts.player(p, team: _team?.name ?? '所属なし', date: app.currentDate as DateTime, condition: p.conditionAt(app.currentDate as DateTime), last: last, lastYear: year, lastTeam: lastTeam),
              fallback: auto,
              builder: (t) => Text(t, style: style),
            );
          },
        ),
      ]),
    );
  }
}

/// 打率の色（打数が少ないうちは薄く）。赤いほど高く、青いほど低い（.150 青・.275 白・.400 赤）
Color splitHeat(List<int>? v) {
  if (v == null || v[0] == 0) return const Color(0xFFF5F5F4);
  final t = ((v[1] / v[0] - 0.150) / 0.250).clamp(0.0, 1.0);
  final c = t < 0.5 ? Color.lerp(const Color(0xFF93C5FD), Colors.white, t * 2)! : Color.lerp(Colors.white, const Color(0xFFFCA5A5), (t - 0.5) * 2)!;
  return v[0] < 3 ? Color.lerp(c, const Color(0xFFF5F5F4), 0.6)! : c;
}

/// 打球方向の図：本塁から左翼線〜右翼線を5等分した扇形。各区画に打率・（打数-安打）・HR
class _SprayPainter extends CustomPainter {
  final List<List<int>?> v;
  _SprayPainter(this.v);

  @override
  void paint(Canvas canvas, Size size) {
    final home = Offset(size.width / 2, size.height - 6);
    final r = min(size.height - 10, size.width / 2 / sin(pi / 4) - 4);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..color = const Color(0xFF78716C)
      ..strokeWidth = 1;
    for (var i = 0; i < 5; i++) {
      final a0 = -pi / 2 - pi / 4 + i * pi / 10; // 左翼線から右へ
      final path = Path()
        ..moveTo(home.dx, home.dy)
        ..arcTo(Rect.fromCircle(center: home, radius: r), a0, pi / 10, false)
        ..close();
      canvas.drawPath(path, Paint()..color = splitHeat(v[i]));
      canvas.drawPath(path, line);
      final mid = a0 + pi / 20;
      final c = home + Offset(cos(mid), sin(mid)) * r * 0.7;
      final x = v[i];
      final has = x != null && x[0] > 0;
      final tp = TextPainter(
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        text: TextSpan(style: const TextStyle(color: Color(0xFF1C1917), height: 1.15), children: [
          TextSpan(text: '${BattingSplits.dirNames[i]}\n', style: const TextStyle(fontSize: 9.5, color: Color(0xFF57534E))),
          if (has) ...[
            TextSpan(text: '${(x[1] / x[0]).toStringAsFixed(3).replaceFirst(RegExp(r'^0'), '')}\n', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900)),
            TextSpan(text: '(${x[0]}-${x[1]})\nHR ${x[2]}', style: const TextStyle(fontSize: 9.5)),
          ] else
            const TextSpan(text: '-', style: TextStyle(fontSize: 11)),
        ]),
      )..layout();
      tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
    }
    // 内野（小さなダイヤモンド）
    final d = r * 0.16;
    final dia = Path()
      ..moveTo(home.dx, home.dy)
      ..lineTo(home.dx + d, home.dy - d)
      ..lineTo(home.dx, home.dy - 2 * d)
      ..lineTo(home.dx - d, home.dy - d)
      ..close();
    canvas.drawPath(dia, Paint()..color = const Color(0xFFE7D7B8));
    canvas.drawPath(dia, line);
  }

  @override
  bool shouldRepaint(_SprayPainter old) => true;
}
