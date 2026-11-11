import 'package:flutter/material.dart';
import '../widgets/note_box.dart';
import '../engine/facility_engine.dart';
import '../engine/finance_engine.dart';
import '../models/finance.dart';
import '../models/player.dart';
import '../models/team.dart';
import '../providers/app_state.dart';
import '../utils/salary_utils.dart';
import '../utils/standings.dart';

const _ink = Color(0xFF1C1917);
const _sub = Color(0xFF78716C);
const _line = Color(0xFFE7E5E4);
const _bg = Color(0xFFF5F5F4);
const _green = Color(0xFF15803D);
const _red = Color(0xFFB91C1C);

String oku(int man) => man.abs() >= 10000 ? '${man < 0 ? '−' : ''}${(man.abs() / 10000).toStringAsFixed(1)}億' : '${man < 0 ? '−' : ''}${man.abs()}万';

Widget _box(String title, List<Widget> children, {Widget? action}) => Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: _line), borderRadius: BorderRadius.circular(10)),
      child: Material(
        type: MaterialType.transparency, // 中のスイッチの押した波紋を見せる
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [Expanded(child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900))), if (action != null) action]),
        const SizedBox(height: 6),
        ...children,
      ]),
      ),
    );

Widget _kv(String k, String v, {Color? color}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Expanded(child: Text(k, style: const TextStyle(fontSize: 13, color: _sub))),
        Text(v, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: color ?? _ink, fontFeatures: const [FontFeature.tabularFigures()])),
      ]),
    );

void _toast(BuildContext c, String? err, String ok) => ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(err ?? ok)));

/// 監督室の「経営」タブ
class FinanceTab extends StatefulWidget {
  final AppState app;
  final Team team;
  const FinanceTab({super.key, required this.app, required this.team});
  @override
  State<FinanceTab> createState() => _FinanceTabState();
}

class _FinanceTabState extends State<FinanceTab> {
  String _tier = '全て'; // スポンサー候補の絞り込み
  AppState get app => widget.app;
  double? _price;

  @override
  Widget build(BuildContext context) {
    final f = app.finOf(widget.team);
    final c = app.consultantOf(f);
    final payroll = app.payrollOf(widget.team);
    final income = f.season.entries.where((e) => e.value > 0).toList()..sort((a, b) => b.value.compareTo(a.value));
    final cost = f.season.entries.where((e) => e.value < 0).toList()..sort((a, b) => a.value.compareTo(b.value));
    final price = _price ?? f.ticketPrice.toDouble();
    final estAtt = FinanceEngine.attendance(f, winPct: 0.5, gamesBehind: 6, weekend: false, type: 'LEAGUE', price: price.round());
    return ListView(padding: const EdgeInsets.fromLTRB(10, 10, 10, 24), children: [
      _box('資金と今季の収支', [
        _kv('球団の資金', oku(f.funds), color: f.funds < 0 ? _red : _ink),
        _kv('今季の収支（シーズン終了までの累計）', '${f.seasonProfit >= 0 ? '+' : ''}${oku(f.seasonProfit)}', color: f.seasonProfit >= 0 ? _green : _red),
        _kv('前年の収支', f.lastSeason.isEmpty ? '−' : oku(f.lastSeason.values.fold(0, (a, b) => a + b))),
        _kv('人気', '${f.popularity} / 100'),
        _kv('観客動員（今季の1試合平均）', f.homeGames == 0 ? '−' : '${f.avgAttendance}人（収容 ${f.capacity}人）'),
        _kv('選手の年俸総額', formatSalary(payroll)),
        const Divider(height: 14),
        Wrap(spacing: 14, runSpacing: 4, children: [
          for (final e in income) Text('${e.key} +${oku(e.value)}', style: const TextStyle(fontSize: 12, color: _green)),
          for (final e in cost) Text('${e.key} ${oku(e.value)}', style: const TextStyle(fontSize: 12, color: _red)),
        ]),
        const SizedBox(height: 4),
        const Text('収支は試合ごと（入場料・グッズ飲食・放映権）と毎月1日（年俸・運営費・スポンサー）に動きます。資金がマイナス5億円を下回ると補強（FA・外国人・トレードの金銭）ができません。',
            style: TextStyle(fontSize: 11, color: _sub, height: 1.5)),
      ]),
      _box('チケット価格', [
        Row(children: [
          Text('${price.round()}円', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(width: 10),
          Expanded(child: Text('平日・勝率5割なら1試合 約$estAtt人', style: const TextStyle(fontSize: 12, color: _sub))),
        ]),
        Slider(
          value: price,
          min: 2500,
          max: FacilityEngine.maxTicket(f.fac('stadium')).toDouble(),
          divisions: 18 + 2 * f.fac('stadium'),
          onChanged: f.autoManage ? null : (v) => setState(() => _price = v),
          onChangeEnd: (v) {
            app.setTicketPrice(v.round());
            setState(() => _price = null);
          },
        ),
        Text(f.autoManage ? 'コンサルタントにおまかせ中（毎月見直します）' : '高いほど客は減ります。グッズ・飲食の売上は観客数に比例します',
            style: const TextStyle(fontSize: 11.5, color: _sub)),
      ]),
      _box('スポンサー（${app.sponsorRenewalPeriod ? '来季 ' : ''}${app.sponsorSlotsUsed(f)} / ${FinanceEngine.maxSponsors}社）', [
        for (final s in f.sponsors) _sponsorRow(s, signed: true, onRenew: app.canRenewSponsor(s) ? () => _renew(f, s) : null),
        if (f.sponsors.isEmpty) const Text('契約しているスポンサーはありません', style: TextStyle(color: _sub)),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(app.sponsorRenewalPeriod
              ? '12月は来季の契約の期間です。今年で満了する契約は「更新」でき（額は人気で変わります）、新しい契約は来季（1月1日）から始まります。他球団も12月15日に契約・更新します'
              : '契約は1月1日に1年ずつ減り、満了すると外れます。新しい候補は毎年12月1日に届き、12月から来季の分を契約・更新できます',
              style: const TextStyle(fontSize: 11, color: _sub, height: 1.5)),
        ),
      ], action: TextButton(onPressed: () => _openOffers(f), child: Text('候補 ${app.sponsorOffers.length}社'))),
      _box('グッズ企画', [
        for (final g in f.goods.reversed.take(8))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              Expanded(child: Text('${g.label}（${g.kind}）', style: const TextStyle(fontSize: 13))),
              Text(g.done ? '売上 ${oku(g.revenue)}／費用 ${oku(g.cost)}' : '販売中（${g.endDate.substring(5)}まで）',
                  style: TextStyle(fontSize: 12, color: g.done ? (g.revenue >= g.cost ? _green : _red) : _sub)),
            ]),
          ),
        if (f.goods.isEmpty) const Text('企画はまだありません', style: TextStyle(color: _sub)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 6, children: [
          OutlinedButton(onPressed: () => _playerGoods(), child: const Text('選手グッズ（2000万）')),
          OutlinedButton(onPressed: () => _goods('記念グッズ', null), child: const Text('記念グッズ（3000万）')),
          OutlinedButton(onPressed: () => _goods('限定ユニフォーム', null), child: const Text('限定ユニフォーム（5000万）')),
        ]),
        const SizedBox(height: 4),
        const NoteBox('30日間販売します。売れ行きは選手の人気・球団の人気・運しだい（当たり外れあり）。同時に3つまで'),
      ]),
      _box('経営コンサルタント', [
        if (c == null) const NoteBox('雇っていません。雇うと経営（チケット価格・グッズ）をおまかせにできます。結果は手腕しだいです'),
        if (c != null) ...[
          _kv(c.name, '手腕 ${c.skill}　年俸 ${formatSalary(c.salary)}'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('経営をおまかせにする'),
            value: f.autoManage,
            onChanged: (v) {
              app.setAutoManage(v);
              setState(() {});
            },
          ),
        ],
        Wrap(spacing: 8, children: [
          OutlinedButton(onPressed: _openConsultants, child: Text(c == null ? '雇う' : '替える')),
          if (c != null)
            TextButton(
              onPressed: () {
                app.releaseConsultant();
                setState(() {});
              },
              child: const Text('契約を切る'),
            ),
        ]),
      ]),
    ]);
  }

  static const _tierColor = {'大企業': Color(0xFF1D4ED8), '中企業': Color(0xFF0F766E), '地方企業': Color(0xFFB45309)};

  Widget _sponsorRow(Sponsor s, {required bool signed, VoidCallback? onSign, VoidCallback? onRenew}) {
    final state = !signed
        ? '${s.years}年'
        : s.pending
            ? '来季から${s.years}年'
            : (s.years <= 1 ? '今年で満了' : '残り${s.years}年');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Container(
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(color: (_tierColor[s.tier] ?? _sub).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4)),
          child: Text(s.tier, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: _tierColor[s.tier] ?? _sub)),
        ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.name, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
            Text('年${oku(s.amount)}・$state　${s.conditionText}${s.bonus > 0 ? '（+${oku(s.bonus)}）' : ''}${s.minPopularity > 0 && !signed ? '　人気${s.minPopularity}以上' : ''}',
                style: TextStyle(fontSize: 11.5, color: signed && !s.pending && s.years <= 1 ? _red : _sub)),
          ]),
        ),
        if (onSign != null) FilledButton(onPressed: onSign, style: FilledButton.styleFrom(visualDensity: VisualDensity.compact), child: const Text('契約')),
        if (onRenew != null) OutlinedButton(onPressed: onRenew, style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact), child: const Text('更新')),
      ]),
    );
  }

  /// 今年で満了する契約の更新：来季から何年か（額は人気で変わる）
  Future<void> _renew(TeamFinance f, Sponsor s) async {
    final amount = FinanceEngine.renewAmount(s, f.popularity);
    final years = await showDialog<int>(
      context: context,
      builder: (c) => SimpleDialog(
        title: Text('${s.name}との契約を更新'),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text('来季から年${oku(amount)}（いまは年${oku(s.amount)}。人気${f.popularity}で決まります）。${s.conditionText}${s.minPopularity > 0 ? '　人気${s.minPopularity}以上が条件' : ''}', style: const TextStyle(fontSize: 12.5, color: _sub, height: 1.5)),
          ),
          for (final y in [1, 2, 3]) SimpleDialogOption(onPressed: () => Navigator.pop(c, y), child: Text('$y年で更新')),
        ],
      ),
    );
    if (years == null || !mounted) return;
    _toast(context, app.renewSponsor(s, years), '${s.name}との契約を更新しました');
    setState(() {});
  }

  Future<void> _openOffers(TeamFinance f) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Scaffold(
          backgroundColor: _bg,
          appBar: AppBar(title: const Text('スポンサー候補')),
          body: ListView(padding: const EdgeInsets.all(12), children: [
            Text('いまの人気 ${f.popularity}。大企業（年2億〜5億）・中企業（年1億〜2億）は人気が条件に届かないと契約できません。地方企業（年3000万〜1億）は条件なし。'
                '候補は毎年12月1日に入れ替わり、他球団も契約していきます（12月15日・1月1日）。${app.sponsorRenewalPeriod ? '12月の契約は来季（1月1日）から始まります。' : ''}',
                style: const TextStyle(fontSize: 12.5, color: _sub, height: 1.5)),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [ButtonSegment(value: '全て', label: Text('全て')), ButtonSegment(value: '大企業', label: Text('大企業')), ButtonSegment(value: '中企業', label: Text('中企業')), ButtonSegment(value: '地方企業', label: Text('地方'))],
              selected: {_tier},
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              onSelectionChanged: (v) => set(() => _tier = v.first),
            ),
            const SizedBox(height: 8),
            for (final s in app.sponsorOffers.where((s) => _tier == '全て' || s.tier == _tier).toList()..sort((a, b) => b.amount.compareTo(a.amount)))
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: _line)),
                child: _sponsorRow(s, signed: false, onSign: () {
                  _toast(ctx, app.signSponsor(s), '${s.name}と契約しました');
                  set(() {});
                }),
              ),
            if (app.sponsorOffers.isEmpty) const Padding(padding: EdgeInsets.all(20), child: Text('候補はいません（12月1日に入れ替わります）', style: TextStyle(color: _sub))),
          ]),
        ),
      ),
    ));
    setState(() {});
  }

  Future<void> _openConsultants() async {
    final picked = await Navigator.of(context).push<Consultant>(MaterialPageRoute(
      builder: (ctx) => Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(title: const Text('経営コンサルタント')),
        body: ListView(padding: const EdgeInsets.all(12), children: [
          const NoteBox('手腕が高いほど、チケット価格の決め方・グッズの売り方がうまく、スポンサー収入も少し増えます。一覧は毎年12月1日に入れ替わります。'),
          const SizedBox(height: 8),
          for (final c in app.consultants.where((c) => c.teamId.isEmpty).toList()..sort((a, b) => b.skill.compareTo(a.skill)))
            Card(
              child: ListTile(
                title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text('手腕 ${c.skill}　年俸 ${formatSalary(c.salary)}'),
                trailing: FilledButton(onPressed: () => Navigator.pop(ctx, c), child: const Text('雇う')),
              ),
            ),
        ]),
      ),
    ));
    if (picked == null || !mounted) return;
    _toast(context, app.hireConsultant(picked), '${picked.name}を雇いました');
    setState(() {});
  }

  void _goods(String kind, Player? p) {
    _toast(context, app.launchGoods(kind, p), '「${p == null ? kind : '${p.registeredName} グッズ'}」の販売を始めました（30日間）');
    setState(() {});
  }

  Future<void> _playerGoods() async {
    final list = List.of(widget.team.players)..sort((a, b) => FinanceEngine.playerAppeal(b).compareTo(FinanceEngine.playerAppeal(a)));
    final p = await showDialog<Player>(
      context: context,
      builder: (d) => SimpleDialog(
        title: const Text('誰のグッズを作りますか'),
        children: [
          for (final x in list.take(15))
            SimpleDialogOption(
              onPressed: () => Navigator.pop(d, x),
              child: Text('${x.registeredName}（${x.mainPosition}・総合${x.ovr}）', style: const TextStyle(fontSize: 14)),
            ),
        ],
      ),
    );
    if (p != null) _goods('選手グッズ', p);
  }
}

/// 監督室の「オーナー」タブ
class OwnerTab extends StatelessWidget {
  final AppState app;
  final Team team;
  const OwnerTab({super.key, required this.app, required this.team});

  @override
  Widget build(BuildContext context) {
    final f = app.finOf(team);
    final lgSize = app.teams.where((t) => t.league == team.league).length;
    final exp = FinanceEngine.expectedRank(app.payrollRank(team), lgSize);
    final color = f.ownerSat >= 60 ? _green : (f.ownerSat >= 35 ? const Color(0xFFB45309) : _red);
    return ListView(padding: const EdgeInsets.fromLTRB(10, 10, 10, 24), children: [
      _box('オーナー満足度', [
        Row(children: [
          Text('${f.ownerSat}', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: color)),
          const Text(' / 100', style: TextStyle(color: _sub)),
          const SizedBox(width: 12),
          Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: f.ownerSat / 100, minHeight: 10, color: color, backgroundColor: _line))),
        ]),
        const SizedBox(height: 6),
        Text('期待されている順位：${exp.toStringAsFixed(1)}位（年俸総額がリーグ${app.payrollRank(team)}位）', style: const TextStyle(fontSize: 12.5)),
        const SizedBox(height: 4),
        Text(
          'シーズン中は毎月、期待との順位の差と収支で動き、シーズン終了時に成績（順位・優勝・前年からの伸び）と経営（収支・観客動員・スポンサー）で評価されます。'
          '${app.ownerFiring ? '満足度が20未満、または2年続けて35未満だと解任されます。' : '（解任なしの設定です）'}',
          style: const TextStyle(fontSize: 11.5, color: _sub, height: 1.5),
        ),
      ]),
      if (f.ownerNotes.isNotEmpty)
        _box('前回の評価の理由', [for (final n in f.ownerNotes) Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text(n, style: const TextStyle(fontSize: 12.5)))]),
      if (f.satHistory.isNotEmpty)
        _box('これまでの満足度', [Text(f.satHistory.join(' → '), style: const TextStyle(fontSize: 13))]),
    ]);
  }
}

/// 解任されたときのカード（ホームに出す）
/// 浪人中のホーム：日付だけ進める（試合結果・順位・ニュースは見られる）
class RoninCard extends StatefulWidget {
  final AppState app;
  const RoninCard({super.key, required this.app});

  @override
  State<RoninCard> createState() => _RoninCardState();
}

class _RoninCardState extends State<RoninCard> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFFF1F5F9), border: Border.all(color: const Color(0xFF94A3B8)), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('浪人中', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        Text('${app.myTeam?.name ?? ''}は CPU の監督が率いています。試合には関わらず、日付だけが進みます。順位表・日程・記録・ニュースは見られます。シーズンが終わると、監督を交代した球団から打診が届きます。', style: const TextStyle(fontSize: 12, height: 1.5)),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: _busy
              ? null
              : () async {
                  setState(() => _busy = true);
                  await app.roninAdvance();
                  if (mounted) setState(() => _busy = false);
                },
          icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.fast_forward),
          label: Text(_busy ? '進めています…' : 'シーズンの終わりまで進める'),
        ),
      ]),
    );
  }
}

class FiredCard extends StatelessWidget {
  final AppState app;
  const FiredCard({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFFFEF2F2), border: Border.all(color: _red), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(app.roninReturn ? '浪人明け：監督の打診が届きました' : 'オーナーから解任されました', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: _red)),
        const SizedBox(height: 6),
        if (!app.roninReturn) Text(app.myFin?.ownerNotes.take(4).join('\n') ?? '', style: const TextStyle(fontSize: 12, height: 1.5)),
        if (app.roninReturn) const Text('今季、監督を交代した球団からの打診です。受ける球団を選んでください。', style: TextStyle(fontSize: 12, height: 1.5)),
        const SizedBox(height: 10),
        const Text('次の行き先を選んでください', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        for (final id in app.firedOffers)
          Builder(builder: (_) {
            final t = app.teamById(id);
            if (t == null) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: FilledButton(
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (d) => AlertDialog(
                      title: Text('${t.name}の監督になりますか？'),
                      content: const Text('いまの球団を離れ、オファーをくれた球団で続きを遊びます。'),
                      actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('やめる')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('就任する'))],
                    ),
                  );
                  if (ok == true) app.acceptOffer(id);
                },
                child: Text('${teamShort(t)}からのオファーを受ける'),
              ),
            );
          }),
        if (!app.roninReturn)
          OutlinedButton(
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (d) => AlertDialog(
                  title: const Text('1年浪人しますか？'),
                  content: const Text('次のシーズンは試合に関わらず、日付だけが進みます（試合結果やニュースは見られます）。元の球団は CPU の監督が率います。オフに、監督を交代した球団から打診が来ます。'),
                  actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('やめる')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('浪人する'))],
                ),
              );
              if (ok == true) app.goRonin();
            },
            child: const Text('1年浪人する（オフの打診を待つ）'),
          ),
        const SizedBox(height: 6),
        OutlinedButton(
          onPressed: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (d) => AlertDialog(
                title: const Text('はじめからやり直しますか？'),
                content: const Text('固有12球団を初期データに戻し、経営もやり直します（新しく作った球団は残ります）。'),
                actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('やめる')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('やり直す'))],
              ),
            );
            if (ok == true) await app.restartAfterFired();
          },
          child: const Text('はじめからやり直す'),
        ),
      ]),
    );
  }
}
