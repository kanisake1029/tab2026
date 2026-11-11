import '../widgets/chip_grid.dart';
import 'package:flutter/material.dart';
import '../widgets/note_box.dart';
import '../engine/coach_engine.dart';
import '../engine/other_league_engine.dart';
import '../models/amateur.dart';
import '../models/coach.dart';
import '../models/team.dart';
import '../providers/app_state.dart';
import '../utils/app_theme.dart';
import '../utils/grade_utils.dart';
import '../utils/salary_utils.dart';
import '../utils/standings.dart';
import 'reinforce_screens.dart';
import 'finance_screens.dart';
import 'camp_screen.dart';
import 'records_screen.dart';
import 'all_teams_tab.dart';
import 'scorer_tab.dart';

/// 監督室：コーチ・補強・経営・オーナー・面談をまとめる場所
///  いま使えるのは「コーチ」（1軍・2軍のスタッフ、OB への打診、相性の確認）。ほかは準備中
class OfficeScreen extends StatefulWidget {
  final AppState appState;
  const OfficeScreen({super.key, required this.appState});

  @override
  State<OfficeScreen> createState() => _OfficeScreenState();
}

const _ink = Color(0xFF1C1917);
const _sub = Color(0xFF78716C);
const _line = Color(0xFFE7E5E4);
const _bg = Color(0xFFF5F5F4);

class _OfficeScreenState extends State<OfficeScreen> with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 9, vsync: this);
  AppState get app => widget.appState;

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final team = app.teams.where((t) => t.id == app.myTeamId).firstOrNull ?? app.teams.first;
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('${teamShort(team)}　監督室', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              TabGrid(controller: _tab, labels: const ['コーチ', 'キャンプ', '補強', '経営', 'オーナー', '記録', '全球団選手', 'スコアラー', '面談・イベント'], minWidth: 76, padding: const EdgeInsets.symmetric(vertical: 6)),
            ]),
          ),
          Expanded(
            child: TabBarView(controller: _tab, children: [
              CoachTab(app: app, team: team, onChanged: () => setState(() {})),
              CampTab(app: app, team: team, onChanged: () => setState(() {})),
              ReinforceTab(app: app, team: team, onChanged: () => setState(() {})),
              FinanceTab(app: app, team: team),
              OwnerTab(app: app, team: team),
              RecordsTab(app: app),
              AllTeamsTab(app: app),
              ScorerTab(app: app, team: team),
              _soon('面談・イベント', '選手との面談（信頼・モチベーションが変わる）、チームのイベント', '今後'),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _soon(String title, String body, String when) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text(body, textAlign: TextAlign.center, style: const TextStyle(color: _sub, height: 1.6)),
            const SizedBox(height: 8),
            Text('準備中（$when）', style: const TextStyle(color: _sub, fontSize: 12)),
          ]),
        ),
      );
}

/// 能力の表示：分かっていれば「B 68」、分からなければ「C〜A」
Widget abilityText(Coach c, String key, {double size = 13}) {
  final v = c.shown(key);
  if (v != null) {
    final g = GradeUtils.getGrade(v);
    return Text.rich(TextSpan(children: [
      TextSpan(text: g, style: TextStyle(fontWeight: FontWeight.w900, fontSize: size, color: AppTheme.getGradeColor(g))),
      TextSpan(text: ' $v', style: TextStyle(fontSize: size - 1, color: _ink)),
    ]));
  }
  final (lo, hi) = c.range(key);
  final gl = GradeUtils.getGrade(lo), gh = GradeUtils.getGrade(hi);
  return Text.rich(TextSpan(children: [
    TextSpan(text: gl, style: TextStyle(fontWeight: FontWeight.w900, fontSize: size, color: AppTheme.getGradeColor(gl))),
    TextSpan(text: '〜', style: TextStyle(fontSize: size - 1, color: _sub)),
    TextSpan(text: gh, style: TextStyle(fontWeight: FontWeight.w900, fontSize: size, color: AppTheme.getGradeColor(gh))),
  ]));
}

class CoachTab extends StatelessWidget {
  final AppState app;
  final Team team;
  final VoidCallback onChanged;
  const CoachTab({super.key, required this.app, required this.team, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final staff = app.staffOf(team);
    final total = app.coaches.where((c) => c.teamId == team.id && c.role != null).fold<int>(0, (s, c) => s + c.salary);
    return LayoutBuilder(builder: (context, c) {
      final narrow = c.maxWidth < 700;
      return ListView(
        padding: EdgeInsets.fromLTRB(narrow ? 10 : 16, 12, narrow ? 10 : 16, 24),
        children: [
          NoteBox(
            null,
            points: [
              'コーチは練習の効果を変える（**指導力・相性・人望**）',
              '相性は選手とコーチのタイプで決まる：同じタイプ **◎×1.2**、近い **○×1.05**、遠い **××0.9**',
              '雇う前の能力は通算成績から予想した幅だけ。**1シーズン雇うと本当の値**が分かる',
              'コーチの年俸総額 **${formatSalary(total)}**',
            ],
          ),
          const SizedBox(height: 12),
          _group(context, '1軍スタッフ', CoachEngine.roles1G, staff, narrow),
          const SizedBox(height: 12),
          _group(context, '2軍スタッフ', CoachEngine.roles2G, staff, narrow),
          const SizedBox(height: 12),
          _thirdGroup(context, narrow),
          const SizedBox(height: 12),
          _scoutGroup(context, narrow),
          const SizedBox(height: 12),
          _rivals(context),
        ],
      );
    });
  }

  Widget _box(String title, List<Widget> children) => Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(side: const BorderSide(color: _line), borderRadius: BorderRadius.circular(10)),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(padding: const EdgeInsets.fromLTRB(12, 10, 12, 6), child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900))),
          ...children,
          const SizedBox(height: 8),
        ]),
      );

  /// 数字の札（見出し＋値）
  Widget _stat(String label, String value, {Color color = _ink}) => Container(
        padding: const EdgeInsets.fromLTRB(8, 3, 8, 4),
        decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(6), border: Border.all(color: _line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: const TextStyle(fontSize: 9.5, color: _sub)),
          Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: color)),
        ]),
      );

  Widget _stats(List<Widget> l) => Padding(padding: const EdgeInsets.fromLTRB(10, 0, 10, 6), child: Wrap(spacing: 4, runSpacing: 4, children: l));

  Widget _group(BuildContext context, String title, List<String> roles, Map<String, Coach> staff, bool narrow) => _box(title, [
        _grid([for (final role in roles) _card(context, role, staff[role])]),
      ]);

  /// 3軍スタッフ（育成選手の練習を見る）：打撃・投手・守備走塁は何人でも雇える
  Widget _thirdGroup(BuildContext context, bool narrow) {
    final ik = team.players.where((p) => p.ikusei).length;
    final n = app.thirdCoachCount(team);
    final lf = CoachEngine.loadFactor(ik, n);
    return _box('3軍スタッフ（育成選手の練習）', [
      _stats([
        _stat('育成選手', '$ik／${app.ikuseiCap(team)}人'),
        _stat('負荷', n == 0 ? '-' : '${(ik / (n * CoachEngine.perThirdCoach) * 100).round()}%'),
        _stat('練習効果', '×${lf.toStringAsFixed(2)}', color: lf >= 1 ? const Color(0xFF15803D) : const Color(0xFFB91C1C)),
      ]),
      const NoteBox(null, points: ['上限：設備の基本枠＋3軍コーチ1人につき5人', '1人で${CoachEngine.perThirdCoach}人まで見る', '何人でも雇える（指導力は平均）', 'シーズン中の招聘は年俸1.5倍'], margin: EdgeInsets.fromLTRB(10, 0, 10, 6)),
      _grid([
        for (final role in CoachEngine.roles3G) ...[
          for (final c in app.staffListOf(team, role))
            _card(context, role, c, onRelease: () {
              app.releaseCoach(c);
              onChanged();
            }),
          _card(context, role, null, add: true),
        ],
      ]),
    ]);
  }

  /// スカウト網：チーフ（1〜3人）・地区担当（地区ごとに最大2人）・海外担当（リーグごとに最大2人）
  Widget _scoutGroup(BuildContext context, bool narrow) {
    final scouts = app.coaches.where((c) => c.teamId == team.id && CoachEngine.isScout(c.role)).toList();
    final pay = scouts.fold<int>(0, (a, c) => a + c.salary);
    final regionN = scouts.where((c) => c.role!.startsWith(CoachEngine.regionScoutPrefix)).length;
    final abroadN = scouts.where((c) => c.role!.startsWith(CoachEngine.overseasScoutPrefix)).length;
    List<Widget Function(double w)> cards(String role, {int min = 0}) {
      final l = scouts.where((c) => c.role == role).toList();
      return [
        for (final c in l)
          _card(context, role, c, onRelease: l.length <= min
              ? null
              : () {
                  app.releaseCoach(c);
                  onChanged();
                }),
        if (l.length < CoachEngine.maxOf(role)) _card(context, role, null, add: l.isNotEmpty),
      ];
    }

    Widget section(String title, String note, List<Widget> children) => ExpansionTile(
          key: PageStorageKey<String>('scoutSection_$title'), // 開いた状態を、スクロール位置とは別に覚える
          title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
          subtitle: Text(note, style: const TextStyle(fontSize: 11.5, color: _sub)),
          childrenPadding: const EdgeInsets.only(bottom: 6),
          children: children,
        );
    return _box('スカウト（ドラフト候補・海外の選手）', [
      _stats([
        _stat('チーフ', '${scouts.where((c) => c.role == 'チーフスカウト').length}人'),
        _stat('地区担当', '$regionN人'),
        _stat('海外担当', '$abroadN人'),
        _stat('年俸の合計', formatSalary(pay)),
      ]),
      const NoteBox(null, points: ['チーフ：見立ての正確さ', '地区担当：毎週、地区の学校・社会人を回って原石を発掘（1地区2人まで）', '海外担当：受け持ちリーグの選手を調べる（1リーグ2人まで）'], margin: EdgeInsets.fromLTRB(10, 0, 10, 6)),
      _grid(cards('チーフスカウト', min: 1)),
      section('地区担当', '${amRegions.where((rg) => scouts.any((c) => c.role == '${CoachEngine.regionScoutPrefix}$rg')).length}／9地区に担当がいます', [
        _grid([for (final rg in amRegions) ...cards('${CoachEngine.regionScoutPrefix}$rg')]),
      ]),
      section('海外担当', '${OtherLeagueEngine.leagues.values.where((l) => scouts.any((c) => c.role == '${CoachEngine.overseasScoutPrefix}${l.id}')).length}リーグに担当がいます', [
        _grid([for (final l in OtherLeagueEngine.leagues.values) ...cards('${CoachEngine.overseasScoutPrefix}${l.id}')]),
      ]),
    ]);
  }

  /// 他球団の監督（CPU。傾向と手腕）
  Widget _rivals(BuildContext context) => Container(
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: _line), borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('他球団の監督', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          for (final t in app.teams.where((t) => t.id != team.id))
            Builder(builder: (_) {
              final m = app.staffOf(t)['監督'];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Text(m == null ? '${teamShort(t)}：未定' : '${teamShort(t)}：${m.name}（${m.age}歳・在任${m.seasonsWithTeam}年）　${CoachEngine.styleText(m.style)}',
                    style: const TextStyle(fontSize: 12.5)),
              );
            }),
        ]),
      );

  /// 担当する選手との相性（◎○×の人数）
  String _fit(Coach c, String role) {
    if (CoachEngine.isScout(role)) return '';
    final farm = role.startsWith('2軍'), third = role.startsWith('3軍');
    final players = team.players.where((p) => third ? p.ikusei : (team.roster1G.contains(p.id) != farm && !(farm && p.ikusei))).where((p) => CoachEngine.pitcherRole(role) ? p.isPitcher : (role.endsWith('打撃') || role.endsWith('守備走塁') ? !p.isPitcher : true));
    var good = 0, bad = 0;
    for (final p in players) {
      final a = CoachEngine.affinity(c.type, CoachEngine.playerType(p));
      if (a >= 1.05) good++;
      if (a <= 0.9) bad++;
    }
    return '合う$good人・合わない$bad人';
  }

  /// コーチの札を、画面の幅に合わせて並べる（スマホは1行に3枚）
  Widget _grid(List<Widget Function(double w)> cards) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: LayoutBuilder(builder: (context, c) {
          final cols = (c.maxWidth / 118).floor().clamp(3, 8);
          final w = (c.maxWidth - (cols - 1) * 4) / cols;
          return Wrap(spacing: 4, runSpacing: 4, children: [for (final f in cards) f(w)]);
        }),
      );

  String _roleName(String role) => role.startsWith(CoachEngine.regionScoutPrefix)
      ? role.substring(CoachEngine.regionScoutPrefix.length)
      : role.startsWith(CoachEngine.overseasScoutPrefix)
          ? (OtherLeagueEngine.leagues[role.substring(CoachEngine.overseasScoutPrefix.length)]?.name ?? '')
          : role;

  /// 能力の見出しを短く（札が細いので）
  static const _short = {'代打判断': '代打', '継投判断': '継投', '守備交代判断': '守備交代', '球速球威': '球威', '走塁判断': '走判断', 'スカウト眼力': '眼力'};

  /// コーチ1人の小さな札：役割の帯（右に交代・外す）・名前・年齢とタイプ・能力（1行に2つ）・年俸と在任
  Widget Function(double w) _card(BuildContext context, String role, Coach? c, {bool add = false, VoidCallback? onRelease}) => (w) {
        final keys = CoachEngine.keysOf(role);
        Future<void> pick() async {
          final picked = await Navigator.of(context).push<Coach>(MaterialPageRoute(builder: (_) => _ObListScreen(app: app, team: team, role: role)));
          if (picked != null) {
            if (c != null && CoachEngine.multiRole(role)) app.releaseCoach(c); // 3軍：このコーチと交代
            app.hireCoach(team, role, picked);
            onChanged();
          }
        }

        Widget icon(IconData i, VoidCallback on, String tip) => InkWell(
              onTap: on,
              child: Tooltip(message: tip, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2), child: Icon(i, size: 14, color: Colors.white))),
            );
        final band = Container(
          height: 20,
          color: c == null ? const Color(0xFF94A3B8) : const Color(0xFF0F172A),
          padding: const EdgeInsets.only(left: 5),
          child: Row(children: [
            Expanded(child: Text(_roleName(role), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white))),
            if (c != null) icon(Icons.swap_horiz, pick, '交代'),
            if (onRelease != null) icon(Icons.close, onRelease, '外す'),
          ]),
        );
        if (c == null) {
          return InkWell(
            onTap: pick,
            child: Container(
              width: w,
              decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(6), border: Border.all(color: const Color(0xFFCBD5E1))),
              clipBehavior: Clip.antiAlias,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                band,
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(add ? '＋ 追加で打診' : '空席　＋打診', textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF2563EB))),
                ),
              ]),
            ),
          );
        }
        final fit = _fitCounts(c, role);
        return Container(
          width: w,
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6), border: Border.all(color: _line)),
          clipBehavior: Clip.antiAlias,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            band,
            Padding(
              padding: const EdgeInsets.fromLTRB(5, 3, 5, 4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, height: 1.2)),
                Text('${c.age}歳 ${c.type}${c.pitcherBg ? ' 投' : ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9.5, color: _sub)),
                const SizedBox(height: 2),
                Wrap(spacing: 0, runSpacing: 1, children: [
                  for (final k in keys)
                    SizedBox(
                      width: ((w - 14) / 2).floorToDouble(),
                      child: Row(children: [
                        Flexible(child: Text(_short[k] ?? k, maxLines: 1, overflow: TextOverflow.clip, style: const TextStyle(fontSize: 9.5, color: _sub))),
                        const SizedBox(width: 2),
                        abilityText(c, k, size: 11),
                      ]),
                    ),
                ]),
                const SizedBox(height: 2),
                Row(children: [
                  Expanded(child: Text(formatSalary(c.salary), maxLines: 1, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700))),
                  Text('${c.seasonsWithTeam}年目', style: const TextStyle(fontSize: 9, color: _sub)),
                ]),
                if (fit != null)
                  Text('相性 ◎${fit.$1} ×${fit.$2}', style: const TextStyle(fontSize: 9, color: _sub)),
                if (!c.known) const Text('能力は予想', style: TextStyle(fontSize: 9, color: Color(0xFFB45309))),
              ]),
            ),
          ]),
        );
      };

  /// 担当する選手との相性（合う・合わないの人数）。スカウトは無し
  (int, int)? _fitCounts(Coach c, String role) {
    final t = _fit(c, role);
    final m = RegExp(r'合う(\d+)人・合わない(\d+)人').firstMatch(t);
    return m == null ? null : (int.parse(m.group(1)!), int.parse(m.group(2)!));
  }
}

/// OB 一覧（打診する相手を選ぶ）
class _ObListScreen extends StatefulWidget {
  final AppState app;
  final Team team;
  final String role;
  const _ObListScreen({required this.app, required this.team, required this.role});

  @override
  State<_ObListScreen> createState() => _ObListScreenState();
}

class _ObListScreenState extends State<_ObListScreen> {
  bool _pitchers = false;

  @override
  void initState() {
    super.initState();
    _pitchers = CoachEngine.pitcherRole(widget.role);
    if (CoachEngine.isScout(widget.role)) widget.app.ensureScoutMarket(); // 眼力C以上の候補はいつでもいる
  }

  @override
  Widget build(BuildContext context) {
    final keys = CoachEngine.keysOf(widget.role);
    final scout = CoachEngine.isScout(widget.role);
    final list = widget.app.obList.where((c) => scout || c.pitcherBg == _pitchers).toList()
      ..sort((a, b) => (b.expected[keys.first] ?? 0).compareTo(a.expected[keys.first] ?? 0));
    final cur = widget.app.staffOf(widget.team)[widget.role];
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(title: Text('${widget.role}コーチに打診'.replaceAll('2軍監督コーチ', '2軍監督'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          if (cur != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('いまのコーチ：${cur.name}（雇うと、いまのコーチは OB 一覧へ戻ります）', style: const TextStyle(fontSize: 12.5, color: _sub)),
            ),
          if (scout) const NoteBox('スカウトの候補：眼力C以上の人がいつもいます。眼力が高い人ほど年俸が高くなります（600万〜2,800万）'),
          if (!scout) SegmentedButton<bool>(
            segments: const [ButtonSegment(value: false, label: Text('野手出身')), ButtonSegment(value: true, label: Text('投手出身'))],
            selected: {_pitchers},
            showSelectedIcon: false,
            onSelectionChanged: (v) => setState(() => _pitchers = v.first),
          ),
          const SizedBox(height: 6),
          const NoteBox('能力は通算成績から予想した幅です（雇って1シーズン経つと本当の値が分かります）。古巣でない OB は年俸 ×1.3'),
          const SizedBox(height: 8),
          for (final c in list) _obCard(context, c, keys),
          if (list.isEmpty) const Padding(padding: EdgeInsets.all(20), child: Text('OB がいません', style: TextStyle(color: _sub))),
        ],
      ),
    );
  }

  Widget _obCard(BuildContext context, Coach c, List<String> keys) {
    final own = c.formerTeamId == widget.team.id;
    final ask = CoachEngine.askingSalary(c, widget.team.id);
    final former = widget.app.teamById(c.formerTeamId);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: own ? const Color(0xFF86EFAC) : _line), borderRadius: BorderRadius.circular(10)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text.rich(TextSpan(children: [
              TextSpan(text: c.name, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
              TextSpan(text: '　${c.age}歳　${c.type}　古巣：${former == null ? 'なし' : teamShort(former)}${own ? '（自球団）' : ''}', style: const TextStyle(fontSize: 11.5, color: _sub)),
            ])),
            Text(c.careerText, style: const TextStyle(fontSize: 12, color: Color(0xFF475569))),
            const SizedBox(height: 3),
            Wrap(spacing: 12, runSpacing: 2, children: [
              for (final k in {...keys, ...Coach.teachKeys.where((k) => c.pitcherBg ? ['球速球威', '制球', 'スタミナ', '変化球'].contains(k) : ['打撃', '守備', '走塁'].contains(k)), '人望'})
                Row(mainAxisSize: MainAxisSize.min, children: [Text('$k ', style: const TextStyle(fontSize: 11.5, color: _sub)), abilityText(c, k)]),
            ]),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(formatSalary(ask), style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          FilledButton(
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (d) => AlertDialog(
                  title: Text('${c.name}に打診しますか？'),
                  content: Text('${widget.role}として年俸 ${formatSalary(ask)} で迎えます。${own ? '' : '（古巣ではないため、年俸は1.3倍です）'}'),
                  actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('やめる')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('打診する'))],
                ),
              );
              if (ok == true && context.mounted) Navigator.pop(context, c);
            },
            style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
            child: const Text('打診'),
          ),
        ]),
      ]),
    );
  }
}
