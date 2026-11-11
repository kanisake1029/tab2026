import 'package:flutter/material.dart';
import 'amateur_screen.dart';
import 'contract_screen.dart';
import '../engine/other_league_engine.dart';
import 'other_leagues_screen.dart' show openOtherPlayer;
import '../widgets/note_box.dart';
import '../ai/ai_facts.dart';
import '../ai/ai_text.dart';
import 'dart:math' show min;
import '../engine/roster_engine.dart';
import '../engine/transfer_engine.dart';
import '../engine/foreign_engine.dart';
import '../engine/draft_engine.dart';
import '../models/prospect.dart';
import '../models/player.dart';
import '../models/team.dart';
import '../providers/app_state.dart';
import '../utils/salary_utils.dart';
import '../utils/standings.dart';
import '../widgets/player_detail_dialog.dart';
import '../widgets/player_row.dart';
import '../widgets/prospect_widgets.dart';

const _ink = Color(0xFF1C1917);
const _sub = Color(0xFF78716C);
const _line = Color(0xFFE7E5E4);
const _bg = Color(0xFFF5F5F4);

Widget _box({required Widget child, EdgeInsets padding = const EdgeInsets.all(12), Color? border}) => Container(
      padding: padding,
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: border ?? _line), borderRadius: BorderRadius.circular(10)),
      child: child,
    );

Widget _note(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: NoteBox(text),
    );

void _toast(BuildContext context, String? err, String ok) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err ?? ok)));
}

/// 選手の1行（名前・位置・年齢・総合・年俸）。タップで詳細
class PlayerLine extends StatelessWidget {
  final AppState app;
  final Player p;
  final String? note;
  final Widget? trailing;
  final bool selected;
  final VoidCallback? onTap;
  const PlayerLine({super.key, required this.app, required this.p, this.note, this.trailing, this.selected = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final tags = [
      if (p.ikusei) '育成',
      if (p.foreignSlot) '外国人',
      if (p.hasFA) 'FA権',
      if (p.injuryDays > 0) '故障',
    ];
    // 共通の1行（オーダー画面と同じ形）。2行目は守備位置・年齢と補足
    return PlayerRow(
      player: p,
      date: app.currentDate,
      leading: SizedBox(width: 26, child: Text(p.uniformText, style: const TextStyle(fontSize: 11.5, color: _sub))),
      tags: [for (final t in tags) PlayerRow.tag(t, const Color(0xFFB45309))],
      sub: '${p.mainPosition}　${p.age}歳${note != null ? '　$note' : ''}',
      right: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [PlayerRow.grade(p.ovr), Text(formatSalary(p.salary), style: const TextStyle(fontSize: 10.5, color: _sub))]),
      trailing: trailing,
      selected: selected,
      onTap: onTap ?? () => showDialog(context: context, builder: (_) => PlayerDetailDialog(player: p, appState: app, team: null, isReadOnly: true, onRosterChanged: () {})),
    );
  }
}

/// 監督室の「補強」タブ
class ReinforceTab extends StatelessWidget {
  final AppState app;
  final Team team;
  final VoidCallback onChanged;
  const ReinforceTab({super.key, required this.app, required this.team, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Future<void> open(Widget w) async {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
      onChanged();
    }

    final sh = RosterEngine.shihaikaCount(team), ik = RosterEngine.ikuseiCount(team);
    final faNote = app.pendingComp.isNotEmpty
        ? '補償の選択が ${app.pendingComp.length}件あります'
        : app.faCases.isNotEmpty
            ? 'FA 宣言 ${app.faCases.length}人${app.faOpen ? '（交渉は12月31日まで）' : '（決定済み）'}'
            : '自球団の FA 権保持者 ${team.players.where((p) => p.hasFA).length}人（宣言は11月の第2月曜日。それまでは残留交渉）';
    final items = <(IconData, String, String, Widget)>[
      (Icons.search, 'ドラフト候補・スカウト', app.prospects.isEmpty ? '候補はまだいません（4月からスカウトが発掘）' : '${app.prospects.first.year}年の候補 ${app.prospects.where((p) => p.knownTo(team.id)).length}人（自球団が調べた選手）　スカウト眼力 ${app.scoutEye(team)}', ScoutScreen(app: app)),
      (Icons.school, 'アマチュア球界', app.amWorld == null ? '' : '${app.amWorld!.year}年度の高校の大会（春・夏・秋）・大学リーグ・都市対抗', AmateurScreen(app: app)),
      (Icons.handshake, 'FA', faNote, FaScreen(app: app)),
      (Icons.request_quote, '契約更改', app.renewalOpen ? '11月が更改の期間です（年俸は50万円単位・1〜12年。転任・引退勧告・自由契約も）' : '11月に、年俸と年数を提示します（12月1日に残りは希望額で）', ContractScreen(app: app)),
      (Icons.recommend, 'スカウトのおすすめ（トレード候補）', '${app.tradeTips.length}人　毎月1日に、他球団で使われていない有望な選手を補強ポイントに合わせて報告', TradeTipsScreen(app: app)),
      (Icons.swap_horiz, 'トレード', app.tradeOpen ? '能力・守備・球種で他球団の選手を探して申し込めます（期限は7月31日）' : '期限（7月31日）を過ぎました。シーズン終了後に再開します', TradeSearchScreen(app: app)),
      (Icons.public, '外国人選手', '海外担当が発掘した選手 ${app.foreignWatch.length}人　自球団の外国人 ${team.players.where((p) => p.foreignSlot).length}人', ForeignScreen(app: app)),
      (Icons.person_search, '自由契約・トライアウト', '${app.freeAgents.length}人（戦力外・育成満了など）', FreeAgentScreen(app: app)),
      (Icons.badge, '戦力外通告・育成', '支配下 $sh / ${RosterEngine.maxShihaika}人　育成 $ik人', RosterManageScreen(app: app)),
      (Icons.history, '入団・移籍・引退の記録', '${app.transactions.length}件', TransactionsScreen(app: app)),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        if (app.pendingComp.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _box(border: const Color(0xFFF59E0B), child: Text('FA の補償を選んでください（${app.pendingComp.length}件）。FA の画面から選べます', style: const TextStyle(fontWeight: FontWeight.w800))),
          ),
        for (final it in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: _line)),
              child: ListTile(
                leading: Icon(it.$1, color: _ink),
                title: Text(it.$2, style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text(it.$3, style: const TextStyle(fontSize: 12)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => open(it.$4),
              ),
            ),
          ),
      ],
    );
  }
}

// ───────── スカウト ─────────

class ScoutScreen extends StatefulWidget {
  final AppState app;
  const ScoutScreen({super.key, required this.app});
  @override
  State<ScoutScreen> createState() => _ScoutScreenState();
}

class _ScoutScreenState extends State<ScoutScreen> {
  bool _ikusei = false;

  @override
  void initState() {
    super.initState();
    widget.app.preScoutIfNeeded();
  }
  String _pos = '高校'; // 経歴の区分。中は守備位置ごと

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final my = app.myTeam;
    final forecast = app.draftForecast();
    if (my != null) scoutEyeForDetail = app.scoutEye(my);
    prospectPlayerName = (id) => app.teams.expand((t) => t.players).where((x) => x.id == id).map((x) => '${x.registeredName}（${app.teams.firstWhere((t) => t.players.contains(x)).shortName}）').firstOrNull;
    final legacy = app.prospects.any((p) => p.ikuseiTier);
    final tier = app.prospects.where((p) => (!legacy || p.ikuseiTier == _ikusei) && p.knownTo(app.myTeamId)).toList();
    final list = tier.where((p) => p.category == _pos).toList()..sort((a, b) => prospectSortKey(b).compareTo(prospectSortKey(a)));
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(title: const Text('ドラフト候補・スカウト')),
      body: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 24), children: [
        _note('候補は、自球団のスカウトが発掘・調査した選手だけです（4〜10月。地区担当が受け持ちの地区の高校・大学・社会人を強い順に回ります。スカウトの人数と眼力で見つかる人数が変わります。チーム→コーチで雇えます）。毎週月曜に調べた結果を報告します。★注目にした候補を優先して調べます。今の能力は±5の幅、潜在能力はスカウト眼力（${my == null ? '-' : app.scoutEye(my)}）が高いほど正確です。'
            'ドラフト会議は10月31日。長押しで詳しい見立てを見られます。「予想」は他球団が何位で指名しそうかのスカウトの見立てです（眼力が高いほど当たりやすい）。'),
        if (legacy) Wrap(spacing: 8, runSpacing: 6, children: [
          SegmentedButton<bool>(
            segments: const [ButtonSegment(value: false, label: Text('本指名候補')), ButtonSegment(value: true, label: Text('育成候補'))],
            selected: {_ikusei},
            showSelectedIcon: false,
            onSelectionChanged: (v) => setState(() => _ikusei = v.first),
          ),
        ]),
        const SizedBox(height: 6),
        draftCategoryBar(tier, _pos, (v) => setState(() => _pos = v)),
        const SizedBox(height: 6),
        if (tier.isEmpty) const Padding(padding: EdgeInsets.all(20), child: Text('候補はまだいません（4月から、スカウトが高校3年・大学4年・社会人の選手を発掘していきます）', style: TextStyle(color: _sub))),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ...draftPosSections(
              list,
              (p) => ProspectRow(
                p: p,
                forecast: forecast[p.id],
                onTap: () => showProspectDetail(context, p),
                onWatch: () {
                  setState(() => p.watched = !p.watched);
                  app.updateAndSave();
                },
              ),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        if (app.scoutLog.isNotEmpty) ...[
          const Text('スカウトの週報', style: TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          for (final s in app.scoutLog.take(20)) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(s, style: const TextStyle(fontSize: 12, color: Color(0xFF475569)))),
        ],
      ]),
    );
  }
}

// ───────── FA ─────────

class FaScreen extends StatefulWidget {
  final AppState app;
  const FaScreen({super.key, required this.app});
  @override
  State<FaScreen> createState() => _FaScreenState();
}

class _FaScreenState extends State<FaScreen> {
  AppState get app => widget.app;

  @override
  void initState() {
    super.initState();
    widget.app.ensureFaDeclaredIfNeeded();
  }

  String _short(String id) {
    final t = app.teamById(id);
    return t == null ? '-' : teamShort(t);
  }

  Future<void> _offer(FaCase f, Player p) async {
    var salary = (app.faCases.contains(f) && f.offers[app.myTeamId] != null ? f.offers[app.myTeamId]![0] : f.ask).toDouble();
    var years = f.offers[app.myTeamId]?[1] ?? 3;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: Text('${p.registeredName}に条件を出す'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('希望年俸 ${formatSalary(f.ask)}　いまの年俸 ${formatSalary(p.salary)}', style: const TextStyle(color: _sub)),
            const SizedBox(height: 10),
            Text('年俸 ${formatSalary((salary / 100).round() * 100)}', style: const TextStyle(fontWeight: FontWeight.w800)),
            Slider(value: salary, min: f.ask * 0.6, max: f.ask * 1.8, onChanged: (v) => set(() => salary = v)),
            Text('年数 $years年', style: const TextStyle(fontWeight: FontWeight.w800)),
            Slider(value: years.toDouble(), min: 1, max: 5, divisions: 4, onChanged: (v) => set(() => years = v.round())),
            const Text('選手は「年俸×年数」と、元の球団（少し有利）・チームの強さで比べて決めます。', style: TextStyle(fontSize: 12, color: _sub)),
            if (f.fromTeamId != app.myTeamId)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                    f.rank == 'C'
                        ? 'Cランクの選手です。獲得すると、元の球団へ前年の年俸の30%を補償として払います。'
                        : '${f.rank}ランクの選手です。獲得すると、元の球団へ前年の年俸の${f.rank == 'A' ? '50%（指名権を選んだとき）か100%' : '40%（指名権を選んだとき）か80%'}を補償として払います。元の球団は次のドラフトの${f.rank == 'A' ? '1.5位' : '2.5位'}指名権も選べます（リーグが与えるので、こちらの指名権は減りません）。人的補償はありません。',
                    style: const TextStyle(fontSize: 12, color: Color(0xFFB45309))),
              ),
          ]),
          actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('やめる')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('条件を出す'))],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final err = app.offerFa(f, (salary / 100).round() * 100, years);
    _toast(context, err, '条件を出しました（12月31日までに、毎週月曜に決まる選手もいます）');
    setState(() {});
  }

  Future<void> _comp(CompCase c) async {
    final withPick = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('${c.playerName}の補償'),
        content: Text(
          '${c.playerName}（${c.rank}ランク・前年の年俸${formatSalary(c.salary)}）が${_short(c.toTeamId)}へ移籍しました。補償を選んでください。\n\n'
          '① 次のドラフトの${c.pickLabel}指名権（リーグから）＋金銭${formatSalary(c.money(true))}\n'
          '② 金銭のみ ${formatSalary(c.money(false))}\n\n'
          '金銭は${_short(c.toTeamId)}が払います。${c.pickLabel}は${c.rank == 'A' ? '1位と2位の間' : '2位と3位の間'}に、補償の指名権を持つ球団だけで入札します（重複は抽選）。${c.repeat ? '\nこの選手は2回目以降の FA のため、①の金銭は半分です。' : ''}',
          style: const TextStyle(fontSize: 13.5, height: 1.5),
        ),
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(d, false), child: Text('② 金銭のみ')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: Text('① ${c.pickLabel}＋金銭')),
        ],
      ),
    );
    if (withPick == null || !mounted) return;
    final err = app.resolveComp(c, withPick);
    _toast(context, err, '補償を決めました');
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final my = app.myTeam;
    final mine = my == null ? <Player>[] : (my.players.where((p) => p.hasFA).toList()..sort((a, b) => b.ovr.compareTo(a.ovr)));
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(title: const Text('FA')),
      body: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 24), children: [
        _note('国内FA 権は1軍登録145日を1年として8年で取得（FA で移籍すると4年で再取得）。11月の第2月曜日に宣言し、12月31日まで交渉します。各球団は毎週条件を出し、毎週月曜に何人かが行き先を決めます（期限が近いほど決まりやすい）。条件は出し直せます。12月31日までにどこの球団とも契約しなかった選手は自由契約になり、1月31日まで契約できます。'
            'A（球団内の年俸1〜3位）・B（4〜10位）の選手を獲ると、元の球団に補償（人的＋金銭、または金銭のみ）を払います。'),
        for (final c in app.pendingComp)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _box(
              border: const Color(0xFFF59E0B),
              child: Row(children: [
                Expanded(child: Text('${c.playerName}（${c.rank}ランク）が${_short(c.toTeamId)}へ移籍。補償を選んでください', style: const TextStyle(fontWeight: FontWeight.w800))),
                FilledButton(onPressed: () => _comp(c), child: const Text('選ぶ')),
              ]),
            ),
          ),
        // ポスティングの希望（自球団の選手）
        for (final e in app.postingAsk.entries.where((e) => e.value == 'ask'))
          if (my != null && my.players.any((p) => p.id == e.key))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _box(
                border: const Color(0xFF0EA5E9),
                child: Builder(builder: (context) {
                  final p = my.players.firstWhere((p) => p.id == e.key);
                  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text('ポスティング：${p.registeredName}（${p.mainPosition}・${p.age}歳・総合${p.ovr}）が大リーグ挑戦を希望しています', style: const TextStyle(fontWeight: FontWeight.w800)),
                    Text('認めると12月1日に大リーグの球団と交渉し、契約すれば譲渡金（目安${formatSalary(TransferEngine.postingFee(p))}）と提携枠1つを得ます。認めないと監督への信頼が下がります。', style: const TextStyle(fontSize: 12, color: _sub)),
                    const SizedBox(height: 6),
                    Wrap(spacing: 8, alignment: WrapAlignment.end, children: [
                      OutlinedButton(onPressed: () => setState(() => _toast(context, app.decidePosting(p, false), '認めませんでした')), child: const Text('認めない')),
                      FilledButton(onPressed: () => setState(() => _toast(context, app.decidePosting(p, true), '認めました（12月1日に交渉の結果が出ます）')), child: const Text('認める')),
                    ]),
                  ]);
                }),
              ),
            ),
        // 提携期間が終わった選手（優先交渉）
        for (final id in app.partnerStay)
          if (my != null && my.players.any((p) => p.id == id))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _box(
                border: const Color(0xFF0EA5E9),
                child: Builder(builder: (context) {
                  final p = my.players.firstWhere((p) => p.id == id);
                  return Row(children: [
                    Expanded(child: Text('提携期間満了：${p.registeredName}（${p.mainPosition}・${p.age}歳・総合${p.ovr}）が日本に残ることを望んでいます。残すと外国人枠の選手として契約します', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13))),
                    const SizedBox(width: 6),
                    Column(children: [
                      FilledButton(onPressed: () => setState(() => _toast(context, app.decidePartnerStay(p, true), '残留させました')), child: const Text('残す')),
                      TextButton(onPressed: () => setState(() => _toast(context, app.decidePartnerStay(p, false), '手放しました')), child: const Text('手放す')),
                    ]),
                  ]);
                }),
              ),
            ),
        // 提携枠（自球団）
        for (final slot in app.partnerSlots.where((s) => s['team'] == my?.id))
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _box(
              border: const Color(0xFF0EA5E9),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('提携枠：${slot['mlb']}（${slot['from']}の移籍先）のプロスペクトから1人を、3〜5年の期限付きで迎えられます', style: const TextStyle(fontWeight: FontWeight.w800)),
                const Text('外国人枠とは別枠です。期間が短いほど・出場機会があるほど受けてもらいやすくなります。期間が終わると基本は返しますが、日本に残りたい選手とは優先して交渉できます。3月1日までに決まらなければ枠は消えます', style: TextStyle(fontSize: 12, color: _sub)),
                for (final c in app.partnerCands(slot))
                  PlayerLine(
                    app: app,
                    p: c,
                    note: '${c.age}歳　成長率×${c.growthRate.toStringAsFixed(2)}（才能${c.talent}・向上心${c.ambition}）　${(slot['declined'] as List? ?? const []).contains(c.id) ? '断られました' : ''}',
                    onTap: () => showPlayerDetail(context, app, c, allowActions: false),
                    trailing: (slot['declined'] as List? ?? const []).contains(c.id)
                        ? null
                        : PopupMenuButton<int>(
                            tooltip: '期間を選んで申し出る',
                            onSelected: (y) => setState(() => _toast(context, app.offerPartner(slot, c, y), '${c.registeredName}が受けました（$y年）')),
                            itemBuilder: (_) => [for (final y in [3, 4, 5]) PopupMenuItem(value: y, child: Text('$y年で申し出る（受ける確率${(TransferEngine.partnerAcceptChance(my!, c, y) * 100).round()}%）'))],
                            child: const Padding(padding: EdgeInsets.all(6), child: Text('申し出る ▾', style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF0369A1)))),
                          ),
                  ),
              ]),
            ),
          ),
        if (app.tenders.isNotEmpty) ...[
          const Text('育成テンダー', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
          const Text('育成で通算3年、支配下に上がれなかった選手です。他球団が支配下契約を提示でき、元の球団も同じ条件で支配下に上げられます。12月1日に選手が条件（年俸・出場機会・人気）を総合して選びます（元の球団に優先権はありません）。他球団へ移ると元の球団に少額の補償', style: TextStyle(fontSize: 11.5, color: _sub)),
          const SizedBox(height: 6),
          for (final c in app.tenders)
            Builder(builder: (context) {
              final p = app.teams.expand((t) => t.players).where((x) => x.id == c['pid']).firstOrNull;
              if (p == null) return const SizedBox.shrink();
              final mineCase = c['from'] == my?.id;
              final offered = mineCase ? c['match'] == true : (c['offers'] as Map).containsKey(my?.id);
              return PlayerLine(
                app: app,
                p: p,
                note: '${_short('${c['from']}')}　提示${(c['offers'] as Map).length}球団${c['match'] == true ? '・元の球団も支配下に' : ''}　目安${formatSalary(app.tenderSalary(p))}',
                onTap: () => showPlayerDetail(context, app, p, allowActions: false),
                trailing: offered
                    ? const Text('提示済み', style: TextStyle(fontSize: 12, color: _sub))
                    : FilledButton(
                        style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                        onPressed: () => setState(() => _toast(context, app.tenderOffer(c), mineCase ? '支配下に上げる条件を出しました' : '支配下契約を提示しました')),
                        child: Text(mineCase ? '支配下に上げる' : '提示する'),
                      ),
              );
            }),
          const SizedBox(height: 10),
        ],
        if (app.faCases.isNotEmpty) ...[
          const Text('FA 選手との交渉', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
          const SizedBox(height: 2),
          const Text('ランクはリーグ全体の日本人選手の年俸順位（A＝1〜36位・B＝37〜120位・C＝それ以外）。獲った球団は元の球団へ金銭の補償を払います。提示は各球団の条件（年俸×年数）です。', style: TextStyle(fontSize: 11.5, color: _sub)),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Column(children: [
              for (final f in app.faCases)
                Builder(builder: (_) {
                  final p = _faPlayer(f);
                  if (p == null) return const SizedBox.shrink();
                  final myOffer = f.offers[app.myTeamId];
                  final status = f.result.isNotEmpty
                      ? (f.result == '-' ? '未契約→自由契約' : f.result == f.fromTeamId ? '残留' : '${_short(f.result)}へ移籍')
                      : '交渉中';
                  return Container(
                    color: Colors.white,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      PlayerLine(
                        app: app,
                        p: p,
                        note: '元${_short(f.fromTeamId)}　希望 ${formatSalary(f.ask)}　$status',
                        trailing: f.result.isEmpty ? OutlinedButton(onPressed: () => _offer(f, p), style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact), child: Text(myOffer == null ? '条件を出す' : '変える')) : null,
                      ),
                      Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 8), child: _offers(f)),
                      const Divider(height: 1, color: _line),
                    ]),
                  );
                }),
            ]),
          ),
          const SizedBox(height: 14),
        ],
        if (app.faCases.isEmpty) ...[
          Text('残留交渉：自球団の FA 権保持者（${mine.length}人）', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
          const SizedBox(height: 4),
          Text('FA 宣言は${app.faDeclareDate(app.currentDate.year).month}月${app.faDeclareDate(app.currentDate.year).day}日（11月の第2月曜日）。それまでに残留を要請すると、宣言しにくくなります（年俸＋20%・3年契約）。宣言の日から FA 選手との交渉の画面になります。', style: const TextStyle(fontSize: 12, color: _sub)),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Column(children: [
              for (final p in mine)
                PlayerLine(
                  app: app,
                  p: p,
                  note: 'FA 資格 ${p.faService}年${p.retainAsked ? '　残留要請済み' : ''}',
                  trailing: !p.retainAsked
                      ? OutlinedButton(
                          onPressed: () {
                            final err = app.askRetain(p);
                            _toast(context, err, '${p.registeredName}に残留を要請しました');
                            setState(() {});
                          },
                          style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                          child: const Text('残留要請'),
                        )
                      : null,
                ),
            ]),
          ),
        ],
      ]),
    );
  }

  /// FA 宣言した選手（球団にいる、または未契約で自由契約になった）
  Player? _faPlayer(FaCase f) =>
      app.teamOfPlayer(f.playerId)?.players.where((x) => x.id == f.playerId).firstOrNull ?? app.freeAgents.where((x) => x.player.id == f.playerId).firstOrNull?.player;

  /// 各球団の提示（総額の大きい順）
  Widget _offers(FaCase f) {
    final list = f.offers.entries.toList()..sort((a, b) => (b.value[0] * b.value[1]).compareTo(a.value[0] * a.value[1]));
    if (list.isEmpty) return const Text('提示：まだどこからもありません', style: TextStyle(fontSize: 11, color: _sub));
    return Wrap(spacing: 4, runSpacing: 3, children: [
      for (final e in list)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: e.key == app.myTeamId ? const Color(0xFFFEF3C7) : const Color(0xFFF8FAFC),
            border: Border.all(color: e.key == app.myTeamId ? const Color(0xFFF59E0B) : _line),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text('${_short(e.key)}${e.key == f.fromTeamId ? '（残留）' : ''}　${e.value[1]}年 総額${formatSalary(e.value[0] * e.value[1])}（年${formatSalary(e.value[0])}）',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
        ),
    ]);
  }
}

// ───────── プロテクトリスト ─────────

/// FA の人的補償に備えたプロテクトリスト（31人）。外国人・その年の新人・育成は最初から対象外
class ProtectListScreen extends StatefulWidget {
  final AppState app;
  const ProtectListScreen({super.key, required this.app});
  @override
  State<ProtectListScreen> createState() => _ProtectListScreenState();
}

class _ProtectListScreenState extends State<ProtectListScreen> {
  late final Team? my = widget.app.myTeam;
  late final Set<String> _sel;

  @override
  void initState() {
    super.initState();
    final t = my;
    final year = widget.app.offseasonYear;
    if (t == null) {
      _sel = {};
    } else {
      final elig = TransferEngine.protectEligible(t, year).map((p) => p.id).toSet();
      final cur = t.protectList.where(elig.contains).toSet();
      _sel = cur.isEmpty ? TransferEngine.autoProtect(t, year).toSet() : cur;
    }
  }

  void _save() {
    final t = my;
    if (t == null) return;
    t.protectList = _sel.toList();
    widget.app.updateAndSave();
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final t = my;
    if (t == null) return const Scaffold(body: Center(child: Text('球団が選ばれていません')));
    final elig = TransferEngine.protectEligible(t, app.offseasonYear);
    const max = TransferEngine.protectCount;
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(title: Text('プロテクトリスト ${_sel.length}/$max')),
      body: Column(children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('守りたい選手を31人まで選びます。A・Bランクの FA 選手を獲ったとき、相手球団はここに入っていない選手から1人を人的補償として選べます。外国人・今年の新人・育成選手は最初から対象外です。タップで詳細。',
                style: TextStyle(fontSize: 12, color: _sub, height: 1.4)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, children: [
              OutlinedButton(onPressed: () => setState(() { _sel..clear()..addAll(TransferEngine.autoProtect(t, app.offseasonYear)); _save(); }), child: const Text('自動で選ぶ（価値の高い順）')),
              OutlinedButton(onPressed: () => setState(() { _sel.clear(); _save(); }), child: const Text('全部外す')),
            ]),
          ]),
        ),
        Expanded(
          child: ListView(children: [
            for (final p in elig)
              PlayerLine(
                app: app,
                p: p,
                selected: _sel.contains(p.id),
                note: '${t.roster1G.contains(p.id) ? '1軍' : '2軍'}　価値${RosterEngine.value(p).round()}',
                onTap: () => showPlayerDetail(context, app, p, allowActions: false),
                trailing: Checkbox(
                  value: _sel.contains(p.id),
                  visualDensity: VisualDensity.compact,
                  onChanged: (_) => setState(() {
                    if (_sel.contains(p.id)) {
                      _sel.remove(p.id);
                    } else if (_sel.length < max) {
                      _sel.add(p.id);
                    } else {
                      _toast(context, '31人までです。誰かを外してください', '');
                    }
                    _save();
                  }),
                ),
              ),
          ]),
        ),
      ]),
    );
  }
}

// ───────── トレード ─────────

class TradeScreen extends StatefulWidget {
  final AppState app;
  final Team? partner;   // 最初に選んでおく相手（スカウトのおすすめから）
  final String? getId;   // 最初に「獲る」に入れておく選手
  const TradeScreen({super.key, required this.app, this.partner, this.getId});
  @override
  State<TradeScreen> createState() => _TradeScreenState();
}

class _TradeScreenState extends State<TradeScreen> {
  AppState get app => widget.app;
  Team? _partner;
  final Set<String> _give = {}, _get = {};
  final Set<String> _givePk = {}, _getPk = {}; // 指名権 '巡|元の球団'
  int _money = 0; // 自球団が払う（万円。マイナスは受け取る）
  bool _ikusei = false;

  @override
  void initState() {
    super.initState();
    _partner = widget.partner;
    if (widget.getId != null) _get.add(widget.getId!);
  }

  @override
  Widget build(BuildContext context) {
    final my = app.myTeam;
    if (my == null) return const Scaffold(body: Center(child: Text('球団が選ばれていません')));
    final others = app.teams.where((t) => t.id != my.id).toList();
    _partner ??= others.first;
    final pt = _partner!;
    List<Player> sorted(Team t) => t.players.where((p) => p.ikusei == _ikusei).toList()..sort((a, b) => b.ovr.compareTo(a.ovr));
    final give = my.players.where((p) => _give.contains(p.id)).toList();
    final get = pt.players.where((p) => _get.contains(p.id)).toList();
    (int, String) pk(String k) => (int.parse(k.split('|')[0]), k.split('|')[1]);
    final givePicks = [for (final k in _givePk) pk(k)], getPicks = [for (final k in _getPk) pk(k)];
    final chance = app.tradeChance(pt, give, get, _money, giveRounds: [for (final x in givePicks) x.$1], getRounds: [for (final x in getPicks) x.$1]);
    final empty = give.isEmpty && get.isEmpty && givePicks.isEmpty && getPicks.isEmpty;
    final wait = app.tradeWait(pt);

    Widget side(String title, Team t, Set<String> sel, Set<String> pks) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(padding: const EdgeInsets.fromLTRB(4, 8, 4, 4), child: Text('$title（選手${sel.length}/4）', style: const TextStyle(fontWeight: FontWeight.w900))),
          Expanded(
            child: ListView(children: [
              if (!_ikusei)
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
                  child: Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    const Text('指名権', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF475569))),
                    for (final x in app.tradablePicks(t))
                      FilterChip(
                        visualDensity: VisualDensity.compact,
                        label: Text(x.$2 == t.id ? '${x.$1}位' : '${x.$1}位（${(app.teamById(x.$2) == null ? '' : teamShort(app.teamById(x.$2)!))}から）', style: const TextStyle(fontSize: 12)),
                        selected: pks.contains('${x.$1}|${x.$2}'),
                        onSelected: (v) => setState(() => v ? pks.add('${x.$1}|${x.$2}') : pks.remove('${x.$1}|${x.$2}')),
                      ),
                  ]),
                ),
              for (final p in sorted(t))
                PlayerLine(
                  app: app,
                  p: p,
                  selected: sel.contains(p.id),
                  note: '${t.roster1G.contains(p.id) ? '1軍' : '2軍'}　${p.draftInfo}${t.id != my.id && p.trust < 40 ? '　監督と不仲（放出されやすい）' : ''}',
                  // タップで選手の詳細、右のチェックで出す・獲る選手を選ぶ
                  onTap: () => showPlayerDetail(context, app, p, allowActions: false),
                  trailing: Checkbox(
                    value: sel.contains(p.id),
                    visualDensity: VisualDensity.compact,
                    onChanged: (_) => setState(() {
                      if (sel.contains(p.id)) {
                        sel.remove(p.id);
                      } else if (sel.length < 4) {
                        sel.add(p.id);
                      }
                    }),
                  ),
                ),
            ]),
          ),
        ]);

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(title: const Text('トレード')),
      body: Column(children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Wrap(spacing: 10, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            DropdownButton<Team>(
              value: pt,
              items: [for (final t in others) DropdownMenuItem(value: t, child: Text(teamShort(t)))],
              onChanged: (t) => setState(() {
                _partner = t;
                _get.clear();
                _getPk.clear();
              }),
            ),
            SegmentedButton<bool>(
              segments: const [ButtonSegment(value: false, label: Text('支配下')), ButtonSegment(value: true, label: Text('育成'))],
              selected: {_ikusei},
              showSelectedIcon: false,
              onSelectionChanged: (v) => setState(() {
                _ikusei = v.first;
                _give.clear();
                _get.clear();
              }),
            ),
            DropdownButton<int>(
              value: _money,
              items: [
                for (final m in [-30000, -20000, -10000, -5000, -2000, 0, 2000, 5000, 10000, 20000, 30000])
                  DropdownMenuItem(value: m, child: Text(m == 0 ? '金銭なし' : (m > 0 ? '${formatSalary(m)}を払う' : '${formatSalary(-m)}を受け取る'))),
              ],
              onChanged: (v) => setState(() => _money = v ?? 0),
            ),
            SizedBox(
              width: double.infinity,
              child: Text('相手球団の方針：${TransferEngine.policyLabels[app.policyOf(pt)]}（再建中は若手と指名権を、優勝を狙う球団は即戦力を高く見ます）\n相手監督の見る目：${app.evalStyleText(pt)}\n相手球団の事情：${app.tradeMood(pt).text()}${wait > 0 ? '\n${teamShort(pt)}とは、あと$wait日たたないとトレードできません（同じ球団とは14日あける）' : ''}', style: const TextStyle(fontSize: 11.5, color: Color(0xFF475569))),
            ),
          ]),
        ),
        Expanded(
          child: LayoutBuilder(builder: (context, c) {
            if (c.maxWidth >= 760) {
              return Row(children: [Expanded(child: side('出す（${teamShort(my)}）', my, _give, _givePk)), Container(width: 1, color: _line), Expanded(child: side('獲る（${teamShort(pt)}）', pt, _get, _getPk))]);
            }
            return DefaultTabController(
              length: 2,
              child: Column(children: [
                Material(color: Colors.white, child: TabBar(labelColor: _ink, tabs: [Tab(text: '出す ${_give.length + _givePk.length}'), Tab(text: '獲る ${_get.length + _getPk.length}')])),
                Expanded(child: TabBarView(children: [side('出す（${teamShort(my)}）', my, _give, _givePk), side('獲る（${teamShort(pt)}）', pt, _get, _getPk)])),
              ]),
            );
          }),
        ),
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: SafeArea(
            top: false,
            child: Row(children: [
              Expanded(
                child: Text(
                  !app.tradeOpen
                      ? 'トレードの期限（7月31日）を過ぎています'
                      : (empty ? '最大4人対4人＋指名権（次のドラフトの2〜5位）＋金銭。選手をタップで詳細、右のチェックで選択。CPU は戦力の釣り合い・足りない位置・球団の方針で判断します' : '成功確率 ${(chance * 100).round()}%'),
                  style: TextStyle(fontWeight: FontWeight.w800, color: chance >= 0.75 ? const Color(0xFF15803D) : (chance >= 0.4 ? const Color(0xFFB45309) : _ink)),
                ),
              ),
              FilledButton(
                onPressed: !app.tradeOpen || empty || wait > 0
                    ? null
                    : () {
                        final err = app.proposeTrade(pt, give, get, _money, givePicks: givePicks, getPicks: getPicks);
                        _toast(context, err, 'トレードが成立しました');
                        if (err == null) {
                          setState(() {
                            _give.clear();
                            _get.clear();
                            _givePk.clear();
                            _getPk.clear();
                            _money = 0;
                          });
                        }
                      },
                child: const Text('申し込む'),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

// ───────── トレード：他球団の選手を条件で探す ─────────

/// 探す条件に使える能力（キー・表示・値の取り方・しきい値の候補・以下で絞るか）
class _Cond {
  final String key, label;
  final int Function(Player) value;
  final List<int> steps;
  final bool atMost;
  final bool? pitcher; // null は両方
  const _Cond(this.key, this.label, this.value, this.steps, {this.atMost = false, this.pitcher});
}

const _st = [40, 50, 55, 60, 65, 70, 75, 80, 85, 90];
final _conds = <_Cond>[
  _Cond('ovr', '総合', (p) => p.ovr, _st),
  _Cond('contact', 'ミート', (p) => ((p.contactLeft + p.contactRight) / 2).round(), _st, pitcher: false),
  _Cond('power', 'パワー', (p) => p.power, _st, pitcher: false),
  _Cond('eye', '選球眼', (p) => p.eye, _st, pitcher: false),
  _Cond('clutch', 'チャンス', (p) => p.clutch, _st, pitcher: false),
  _Cond('run', '走力', (p) => p.run, _st, pitcher: false),
  _Cond('arm', '肩力', (p) => p.arm, _st, pitcher: false),
  _Cond('throwAccuracy', '送球', (p) => p.throwAccuracy, _st, pitcher: false),
  _Cond('catchSkill', '捕球', (p) => p.catchSkill, _st, pitcher: false),
  _Cond('velocity', '球速(km)', (p) => p.velocity, [140, 145, 148, 150, 152, 154, 156, 158], pitcher: true),
  _Cond('pitchPower', '球威', (p) => p.pitchPower, _st, pitcher: true),
  _Cond('control', '制球', (p) => p.control, _st, pitcher: true),
  _Cond('stamina', 'スタミナ', (p) => p.stamina, _st, pitcher: true),
  _Cond('clutchPitching', 'ピンチ', (p) => p.clutchPitching, _st, pitcher: true),
  _Cond('ambition', '向上心', (p) => p.ambition, _st),
  _Cond('talent', '才能', (p) => p.talent, _st),
  _Cond('age', '年齢(以下)', (p) => p.age, [22, 24, 26, 28, 30, 32, 34], atMost: true),
];

const _posField = ['捕手', '一塁手', '二塁手', '三塁手', '遊撃手', '左翼手', '中堅手', '右翼手'];
int _fieldOf(Player p, String pos) => switch (pos) {
      '捕手' => p.fieldC,
      '一塁手' => p.field1B,
      '二塁手' => p.field2B,
      '三塁手' => p.field3B,
      '遊撃手' => p.fieldSS,
      '左翼手' => p.fieldLF,
      '中堅手' => p.fieldCF,
      _ => p.fieldRF,
    };

class TradeSearchScreen extends StatefulWidget {
  final AppState app;
  const TradeSearchScreen({super.key, required this.app});
  @override
  State<TradeSearchScreen> createState() => _TradeSearchScreenState();
}

class _TradeSearchScreenState extends State<TradeSearchScreen> {
  AppState get app => widget.app;
  String _kind = '全て'; // 全て・投手・野手
  String _pos = '全て';
  String _pitch = '全て';
  bool _ikusei = false;
  final Map<String, int> _min = {}; // 条件：能力キー → しきい値
  String _addKey = 'contact';
  String _sort = 'ovr';

  @override
  Widget build(BuildContext context) {
    final my = app.myTeam;
    if (my == null) return const Scaffold(body: Center(child: Text('球団が選ばれていません')));
    final others = app.teams.where((t) => t.id != my.id).toList();
    final pitchNames = <String>{for (final t in others) for (final p in t.players) if (p.canPitch) for (final x in p.pitches) x.name}.toList()..sort();
    final byKey = {for (final c in _conds) c.key: c};

    bool ok(Player p) {
      if (p.ikusei != _ikusei) return false;
      if (_kind == '投手' && !p.canPitch) return false;
      if (_kind == '野手' && !p.canBat) return false;
      if (_pos != '全て' && (p.isPitcher && !p.twoWay || (p.mainPosition != _pos && _fieldOf(p, _pos) < 50))) return false;
      if (_pitch != '全て' && !(p.canPitch && p.pitches.any((x) => x.name == _pitch))) return false;
      for (final e in _min.entries) {
        final c = byKey[e.key]!;
        if (c.pitcher == true && !p.canPitch) return false;
        if (c.pitcher == false && !p.canBat) return false;
        final v = c.value(p);
        if (c.atMost ? v > e.value : v < e.value) return false;
      }
      return true;
    }

    final hits = <(Player, Team)>[for (final t in others) for (final p in t.players) if (ok(p)) (p, t)];
    final sc = byKey[_sort] ?? byKey['ovr']!;
    hits.sort((a, b) => sc.atMost ? sc.value(a.$1).compareTo(sc.value(b.$1)) : sc.value(b.$1).compareTo(sc.value(a.$1)));
    final shown = hits.take(150).toList();

    Widget dd<T>(T value, List<T> items, String Function(T) label, void Function(T) set) => DropdownButton<T>(
          value: value,
          isDense: true,
          items: [for (final x in items) DropdownMenuItem(value: x, child: Text(label(x), style: const TextStyle(fontSize: 13)))],
          onChanged: (v) => setState(() => set(v as T)),
        );

    final addable = _conds.where((c) => !_min.containsKey(c.key)).toList();
    if (addable.isNotEmpty && !addable.any((c) => c.key == _addKey)) _addKey = addable.first.key;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(title: const Text('トレード：選手を探す')),
      body: Column(children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Wrap(spacing: 12, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              SegmentedButton<bool>(
                segments: const [ButtonSegment(value: false, label: Text('支配下')), ButtonSegment(value: true, label: Text('育成'))],
                selected: {_ikusei},
                showSelectedIcon: false,
                onSelectionChanged: (v) => setState(() => _ikusei = v.first),
              ),
              dd<String>(_kind, const ['全て', '投手', '野手'], (x) => x, (v) => _kind = v),
              Row(mainAxisSize: MainAxisSize.min, children: [const Text('守備 ', style: TextStyle(fontSize: 12, color: _sub)), dd<String>(_pos, ['全て', ..._posField], (x) => x, (v) => _pos = v)]),
              Row(mainAxisSize: MainAxisSize.min, children: [const Text('球種 ', style: TextStyle(fontSize: 12, color: _sub)), dd<String>(_pitch, ['全て', ...pitchNames], (x) => x, (v) => _pitch = v)]),
            ]),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              for (final e in _min.entries)
                InputChip(
                  label: Text('${byKey[e.key]!.label} ${e.value}${byKey[e.key]!.atMost ? '以下' : '以上'}', style: const TextStyle(fontSize: 12)),
                  onPressed: () async {
                    final c = byKey[e.key]!;
                    final v = await showDialog<int>(
                      context: context,
                      builder: (_) => SimpleDialog(title: Text(c.label), children: [for (final s in c.steps) SimpleDialogOption(onPressed: () => Navigator.pop(context, s), child: Text('$s${c.atMost ? '以下' : '以上'}'))]),
                    );
                    if (v != null) setState(() => _min[e.key] = v);
                  },
                  onDeleted: () => setState(() => _min.remove(e.key)),
                ),
              if (addable.isNotEmpty) ...[
                dd<String>(_addKey, [for (final c in addable) c.key], (k) => byKey[k]!.label, (v) => _addKey = v),
                TextButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('条件を追加'),
                  onPressed: () => setState(() {
                    final c = byKey[_addKey]!;
                    _min[c.key] = c.atMost ? c.steps[c.steps.length ~/ 2] : (c.key == 'velocity' ? 150 : 70);
                  }),
                ),
              ],
            ]),
            Row(children: [
              Expanded(child: Text('${hits.length}人が該当${hits.length > shown.length ? '（上位${shown.length}人を表示）' : ''}　条件のチップをタップで値を変更', style: const TextStyle(fontSize: 11.5, color: _sub))),
              const Text('並び ', style: TextStyle(fontSize: 12, color: _sub)),
              dd<String>(_sort, ['ovr', ..._min.keys.where((k) => k != 'ovr')], (k) => byKey[k]!.label, (v) => _sort = v),
            ]),
          ]),
        ),
        Expanded(
          child: shown.isEmpty
              ? const Center(child: Text('条件に合う選手がいません', style: TextStyle(color: _sub)))
              : ListView(children: [
                  for (final (p, t) in shown)
                    PlayerLine(
                      app: app,
                      p: p,
                      note: '${teamShort(t)} ${t.roster1G.contains(p.id) ? '1軍' : '2軍'}${_min.keys.where((k) => k != 'ovr' && k != 'age').map((k) => '　${byKey[k]!.label.replaceAll('(km)', '')}${byKey[k]!.value(p)}').join()}${p.trust < 40 ? '　監督と不仲' : ''}',
                      // タップでこの選手を「獲る」に入れて、出す選手を選ぶ画面へ
                      onTap: !app.tradeOpen
                          ? () => showPlayerDetail(context, app, p, allowActions: false)
                          : () async {
                              await Navigator.of(context).push(MaterialPageRoute(builder: (_) => TradeScreen(app: app, partner: t, getId: p.id)));
                              if (mounted) setState(() {});
                            },
                      trailing: IconButton(icon: const Icon(Icons.info_outline, size: 20), tooltip: '詳細', onPressed: () => showPlayerDetail(context, app, p, allowActions: false)),
                    ),
                ]),
        ),
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
          child: SafeArea(
            top: false,
            child: Row(children: [
              Expanded(child: Text(app.tradeOpen ? '選手をタップすると「獲る」に入れて、出す選手を選ぶ画面に進みます（右の i で詳細）' : 'トレードの期限（7月31日）を過ぎています。検索と詳細は見られます', style: const TextStyle(fontSize: 11.5, color: _sub))),
              TextButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TradeScreen(app: app))), child: const Text('球団から選ぶ')),
            ]),
          ),
        ),
      ]),
    );
  }
}

// ───────── スカウトのおすすめ（トレード候補） ─────────

class TradeTipsScreen extends StatefulWidget {
  final AppState app;
  const TradeTipsScreen({super.key, required this.app});
  @override
  State<TradeTipsScreen> createState() => _TradeTipsScreenState();
}

class _TradeTipsScreenState extends State<TradeTipsScreen> {
  @override
  void initState() {
    super.initState();
    widget.app.ensureTradeTips();
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final tips = app.currentTradeTips();
    final my = app.myTeam;
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(title: const Text('スカウトのおすすめ')),
      body: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 24), children: [
        _note('毎月1日に、スカウトが他球団で十分に使われていない選手の中から、能力・才能・向上心が高く、自球団の補強ポイントに合う選手を報告します（スカウト眼力 ${my == null ? '-' : app.scoutEye(my)}。眼力が低いと見立てがずれます）。'
            '${app.tradeOpen ? '' : 'いまはトレードの期限（7月31日）を過ぎています。シーズン後に再開します。'}'),
        if (tips.isEmpty) const Padding(padding: EdgeInsets.all(20), child: Text('今月のおすすめはありません', style: TextStyle(color: _sub))),
        for (final (p, t, comment, date) in tips)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _box(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: const Color(0xFFF59E0B), borderRadius: BorderRadius.circular(4)),
                    child: const Text('おすすめ！', style: TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w900)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(p.listName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900))),
                  PlayerRow.grade(p.ovr, size: 15),
                ]),
                const SizedBox(height: 2),
                Text('${teamShort(t)}　${p.mainPosition}　${p.age}歳　${t.roster1G.contains(p.id) ? '1軍' : '2軍'}　年俸 ${formatSalary(p.salary)}', style: const TextStyle(fontSize: 12, color: _sub)),
                const SizedBox(height: 6),
                AiText(
                  item: AiFacts.trade(p, team: t.name, myTeam: my?.name ?? '', onFarm: !t.roster1G.contains(p.id), autoComment: comment, date: date),
                  fallback: comment,
                  builder: (x) => Text(x, style: const TextStyle(fontSize: 13, height: 1.55)),
                ),
                const SizedBox(height: 6),
                Row(children: [
                  Text('$date の報告', style: const TextStyle(fontSize: 11, color: _sub)),
                  const Spacer(),
                  TextButton(onPressed: () => showPlayerDetail(context, app, p, allowActions: false), child: const Text('詳細')),
                  FilledButton(
                    onPressed: () async {
                      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => TradeScreen(app: app, partner: t, getId: p.id)));
                      if (mounted) setState(() {});
                    },
                    child: const Text('トレードを検討'),
                  ),
                ]),
              ]),
            ),
          ),
      ]),
    );
  }
}

// ───────── 外国人選手 ─────────

class ForeignScreen extends StatefulWidget {
  final AppState app;
  const ForeignScreen({super.key, required this.app});
  @override
  State<ForeignScreen> createState() => _ForeignScreenState();
}

class _ForeignScreenState extends State<ForeignScreen> {
  bool _ikusei = false;
  String _filter = '全て';

  Future<void> _sign(Player p) async {
    final app = widget.app;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('${p.registeredName}と${p.ikusei ? '育成' : ''}契約しますか？'),
        content: Text('年俸 ${formatSalary(p.salary)}・1年契約${p.ikusei ? '' : '\n入団すると環境適応力に応じて、打撃・投球の能力に倍率がかかります。'}'),
        actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('やめる')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('契約する'))],
      ),
    );
    if (ok != true || !mounted) return;
    _toast(context, app.signForeign(p), '${p.registeredName}と契約しました');
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final my = app.myTeam;
    final eye = my == null ? 50 : app.scoutEye(my);
    scoutEyeForDetail = eye;
    final year = app.currentDate.month >= 12 ? app.currentDate.year + 1 : app.currentDate.year;
    final views = [
      for (final p in app.foreignPool)
        if (app.foreignWatch.contains(p.id) && p.ikusei == _ikusei && (_filter == '全て' || (_filter == '投手') == p.isPitcher)) ForeignEngine.view(p, eye, year),
    ];
    // 追っているが今年の一覧にいない選手（他リーグでプレー中。声をかけられる）
    final inPool = {for (final p in app.foreignPool) p.id};
    final ow = app.otherWorld;
    final tracked = [
      if (ow != null)
        for (final id in app.foreignWatch)
          if (!inPool.contains(id))
            if (ow.teamOfPlayer(id) case final t?) (t, t.players.firstWhere((p) => p.id == id)),
    ]..sort((a, b) => b.$2.ovr.compareTo(a.$2.ovr));
    double key(Prospect v) {
      if (_ikusei) return prospectSortKey(v);
      final (lo, hi) = DraftEngine.curRange(v);
      final (al, ah) = ForeignEngine.adaptRange(v.player, eye);
      return (lo + hi) / 2 * ForeignEngine.adaptMult(((al + ah) / 2).round());
    }

    views.sort((x, y) => key(y).compareTo(key(x)));
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(title: const Text('外国人選手')),
      body: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 24), children: [
        _note('一覧に出るのは、自球団の海外担当スカウトが発掘した選手だけです（チーム→コーチで、リーグごとに2人まで雇えます。一度見つけた選手は追い続けます）。毎年12月1日に、契約に前向きな選手の一覧が届きます。支配下はシーズン中も7月31日まで契約できます。1軍に登録できる外国人は5人まで、ベンチ入りは4人までです。年俸は希望額です。'
            '支配下の今の能力は±5の幅、環境適応力はスカウトの眼力（$eye）に応じた幅で分かります。適応力は入団時に打撃・投球の能力へ倍率としてかかります（D50×0.8・C60×0.9・B70×1.0）。育成はドラフトと同じく才能・向上心の見立てです。タップで詳しい見立てと海外での成績。'),
        Wrap(spacing: 8, runSpacing: 6, children: [
          SegmentedButton<bool>(
            segments: const [ButtonSegment(value: false, label: Text('支配下候補')), ButtonSegment(value: true, label: Text('育成候補'))],
            selected: {_ikusei},
            showSelectedIcon: false,
            onSelectionChanged: (v) => setState(() => _ikusei = v.first),
          ),
          SegmentedButton<String>(
            segments: const [ButtonSegment(value: '全て', label: Text('全て')), ButtonSegment(value: '投手', label: Text('投手')), ButtonSegment(value: '野手', label: Text('野手'))],
            selected: {_filter},
            showSelectedIcon: false,
            onSelectionChanged: (v) => setState(() => _filter = v.first),
          ),
        ]),
        const SizedBox(height: 8),
        if (views.isEmpty) const Padding(padding: EdgeInsets.all(20), child: Text('契約できる選手はいません（海外担当が発掘した選手のうち、12月1日の一覧に載った選手がここに出ます）', style: TextStyle(color: _sub))),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Column(children: [
            for (final v in views)
              Builder(builder: (_) {
                final p = v.player;
                final adapt = p.ikusei ? null : ForeignEngine.adaptRange(p, eye);
                void detail() => showProspectDetail(context, v,
                    adapt: adapt,
                    memoTitle: '海外での成績（出身：${p.origin}）',
                    note: p.ikusei
                        ? null
                        : '今の能力は実際の値の±5の幅で分かります。環境適応力はスカウトの眼力が高いほど狭い幅で見抜けます（眼力D50で±20、S100で±5）。入団すると、適応力に応じた倍率が打撃・投球の能力にかかります（球速・走力・肩・守備・スタミナは変わりません）。');
                return ProspectRow(
                  p: v,
                  onTap: detail,
                  onLongPress: detail,
                  traits: adapt == null
                      ? null
                      : SizedBox(width: 70, child: Column(children: [const Text('適応力', style: TextStyle(fontSize: 9.5, color: _sub)), gradeRange(adapt.$1, adapt.$2, size: 12)])),
                  trailing: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(formatSalary(p.salary), style: const TextStyle(fontSize: 10.5, color: _sub)),
                    FilledButton(onPressed: () => _sign(p), style: FilledButton.styleFrom(visualDensity: VisualDensity.compact), child: const Text('契約')),
                  ]),
                );
              }),
          ]),
        ),
        if (tracked.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text('追っている選手（今年の一覧の外・${tracked.length}人）', style: const TextStyle(fontWeight: FontWeight.w900)),
          const Text('他リーグでプレー中。タップすると詳しく見たり、声をかけたりできます', style: TextStyle(fontSize: 11.5, color: _sub)),
          const SizedBox(height: 4),
          for (final (t, p) in tracked.take(80))
            ListTile(
              dense: true,
              title: Text(p.registeredName, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('${OtherLeagueEngine.leagues[t.leagueId]?.name ?? ''}・${t.name}　${p.isPitcher ? '投手' : p.mainPosition}　${p.age}歳　${p.origin}', style: const TextStyle(fontSize: 11.5)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => openOtherPlayer(context, app, p, () => setState(() {})),
            ),
        ],
      ]),
    );
  }
}

// ───────── 自由契約・トライアウト ─────────

class FreeAgentScreen extends StatefulWidget {
  final AppState app;
  const FreeAgentScreen({super.key, required this.app});
  @override
  State<FreeAgentScreen> createState() => _FreeAgentScreenState();
}

class _FreeAgentScreenState extends State<FreeAgentScreen> {
  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final list = List.of(app.freeAgents)..sort((a, b) => b.player.ovr.compareTo(a.player.ovr));
    String from(String id) {
      final t = app.teamById(id);
      return t == null ? '-' : teamShort(t);
    }

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(title: const Text('自由契約・トライアウト')),
      body: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 24), children: [
        _note('戦力外・育成満了などで自由契約になった選手です。11月12日のトライアウトと1月15日に他球団も獲得します。1月31日までに契約がなければ引退します（FA で未契約の選手も含む）。戦力外の選手は年俸が安くなりやすい（×0.7）。'),
        if (list.isEmpty) const Padding(padding: EdgeInsets.all(20), child: Text('自由契約の選手はいません', style: TextStyle(color: _sub))),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Column(children: [
            for (final fa in list)
              PlayerLine(
                app: app,
                p: fa.player,
                note: '${fa.reason}（元${from(fa.fromTeamId)}）　${fa.player.draftInfo}',
                trailing: Column(mainAxisSize: MainAxisSize.min, children: [
                  FilledButton(
                    onPressed: () {
                      _toast(context, app.signFreeAgent(fa, ikusei: false), '${fa.player.registeredName}と契約しました');
                      setState(() {});
                    },
                    style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                    child: const Text('支配下'),
                  ),
                  TextButton(
                    onPressed: () {
                      _toast(context, app.signFreeAgent(fa, ikusei: true), '${fa.player.registeredName}と育成契約しました');
                      setState(() {});
                    },
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                    child: const Text('育成'),
                  ),
                ]),
              ),
          ]),
        ),
      ]),
    );
  }
}

// ───────── 戦力外通告・育成 ─────────

class RosterManageScreen extends StatefulWidget {
  final AppState app;
  const RosterManageScreen({super.key, required this.app});
  @override
  State<RosterManageScreen> createState() => _RosterManageScreenState();
}

class _RosterManageScreenState extends State<RosterManageScreen> {
  bool _ikusei = false;

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final my = app.myTeam;
    if (my == null) return const Scaffold(body: Center(child: Text('球団が選ばれていません')));
    final list = my.players.where((p) => p.ikusei == _ikusei).toList()..sort((a, b) => RosterEngine.value(a).compareTo(RosterEngine.value(b)));
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(title: const Text('戦力外通告・育成')),
      body: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 24), children: [
        _note('支配下 ${RosterEngine.shihaikaCount(my)} / ${RosterEngine.maxShihaika}人、育成 ${RosterEngine.ikuseiCount(my)}人。ドラフトで指名できるのは支配下の空きの分だけです。'
            '育成選手は2軍の試合に出られますが、1軍に上がるには支配下登録（7月31日まで）が必要です。育成契約は3年。育成枠は資金が続く限り何人でも持てます。オフシーズンには「育成再契約」（支配下→育成、育成満了→再契約）ができます。並びは「残す価値」の低い順です。'),
        SegmentedButton<bool>(
          segments: const [ButtonSegment(value: false, label: Text('支配下')), ButtonSegment(value: true, label: Text('育成'))],
          selected: {_ikusei},
          showSelectedIcon: false,
          onSelectionChanged: (v) => setState(() => _ikusei = v.first),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Column(children: [
            for (final p in list)
              PlayerLine(
                app: app,
                p: p,
                note: '${p.draftInfo.isEmpty ? 'プロ${p.proYears}年目' : p.draftInfo}${p.ikusei ? '　育成${p.ikuseiYears}年目${p.ikuseiYears >= 3 ? '（満了）' : ''}' : ''}　今季 ${p.isPitcher ? p.seasonStats.appsText : '${p.seasonStats.games}試合'}',
                trailing: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (p.ikusei)
                    FilledButton(
                      onPressed: () {
                        _toast(context, app.promoteIkusei(p), '${p.registeredName}を支配下登録しました');
                        setState(() {});
                      },
                      style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                      child: const Text('支配下登録'),
                    ),
                  TextButton(
                    onPressed: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (d) => AlertDialog(
                          title: Text('${p.registeredName}に戦力外を通告しますか？'),
                          content: const Text('自由契約の一覧に移ります。どこの球団とも契約しなければ、1月31日を過ぎると引退します。'),
                          actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('やめる')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('通告する'))],
                        ),
                      );
                      if (ok != true || !context.mounted) return;
                      _toast(context, app.releasePlayer(p), '戦力外を通告しました');
                      setState(() {});
                    },
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: Colors.redAccent),
                    child: const Text('戦力外'),
                  ),
                  // 育成再契約：支配下の選手、または育成満了（3年）の選手。オフシーズンだけ
                  if (!p.ikusei || p.ikuseiYears >= 3)
                    TextButton(
                      onPressed: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (d) => AlertDialog(
                            title: Text('${p.registeredName}と育成再契約しますか？'),
                            content: Text(p.ikusei
                                ? '育成契約が満了した選手と、育成選手として結び直します（育成3年をやり直し・年俸${formatSalary(min(p.salary, 600))}）。'
                                : 'いったん自由契約にして、育成選手として結び直します。支配下の枠が1つ空き、背番号は3桁になります（年俸${formatSalary(min(p.salary, 600))}）。1軍に戻すには支配下登録が必要です。'),
                            actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('やめる')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('再契約する'))],
                          ),
                        );
                        if (ok != true || !context.mounted) return;
                        _toast(context, app.reSignIkusei(p), '${p.registeredName}と育成再契約しました');
                        setState(() {});
                      },
                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: app.canReSignIkusei ? const Color(0xFF0F766E) : _sub),
                      child: const Text('育成再契約'),
                    ),
                ]),
              ),
          ]),
        ),
      ]),
    );
  }
}

// ───────── 記録 ─────────

class TransactionsScreen extends StatelessWidget {
  final AppState app;
  const TransactionsScreen({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(title: const Text('入団・移籍・引退の記録')),
      body: app.transactions.isEmpty
          ? const Center(child: Text('記録はまだありません', style: TextStyle(color: _sub)))
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: app.transactions.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) => Padding(padding: const EdgeInsets.symmetric(vertical: 7), child: Text(app.transactions[i], style: const TextStyle(fontSize: 13))),
            ),
    );
  }
}
