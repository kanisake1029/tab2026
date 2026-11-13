import 'dart:async';
import 'package:flutter/material.dart';
import '../widgets/draft_lottery.dart';
import '../engine/draft_engine.dart';
import '../engine/roster_engine.dart';
import '../models/prospect.dart';
import '../providers/app_state.dart';
import '../utils/standings.dart';
import '../widgets/prospect_widgets.dart';

/// ドラフト会議（10月31日）
///  1位は全球団が同時に入札し、重複したら抽選。外れたら再入札。2位以降はウェーバー、最後に育成ドラフト
class DraftScreen extends StatefulWidget {
  final AppState appState;
  const DraftScreen({super.key, required this.appState});

  @override
  State<DraftScreen> createState() => _DraftScreenState();
}

const _bg = Color(0xFFEEF1F5);
const _ink = Color(0xFF0F172A);
const _sub = Color(0xFF64748B);
const _line = Color(0xFFE2E8F0);
const _navy = Color(0xFF0B1626);
const _lime = Color(0xFFC6F24E);

class _DraftScreenState extends State<DraftScreen> {
  late final DraftSession s = widget.appState.createDraftSession();
  Prospect? _sel;
  String _pos = '高校'; // 経歴の区分（高校・大学・社会人・独立）。中は守備位置ごと
  bool _watchedOnly = false;
  bool _applied = false;
  /// 補償の巡（1.5位・2.5位）の自球団の入札：候補 ID → 重ねる枠の数
  final Map<String, int> _compBids = {};
  /// 会議場のビジョン：発表済みの指名の数（1件ずつ順に発表する）
  int _shown = 0;
  /// ビジョンで見ている巡（null は最新の巡）
  String? _visionRound;
  Timer? _ticker;

  AppState get app => widget.appState;
  String get my => app.myTeamId;

  String _short(String id) {
    final t = app.teamById(id);
    return t == null ? id : teamShort(t);
  }

  /// いまの段階で選べる候補（本指名は育成候補を除く）
  List<Prospect> get _pool => s.pool.where((p) => p.knownTo(my) && (s.stage == 'ikusei' || !p.ikuseiTier) && (!_watchedOnly || p.watched)).toList();

  List<Prospect> get _list {
    final l = _pool.where((p) => p.category == _pos).toList()
      ..sort((a, b) => prospectSortKey(b).compareTo(prospectSortKey(a)));
    return l;
  }

  @override
  void initState() {
    super.initState();
    _advance();
    // 指名を1件ずつ発表していく（ビジョンに順に表示）
    _startTicker();
  }

  /// 発表の速さ（×0.7〜×1.5。×1.0 は1人1.3秒）
  static double _visionSpeed = 1.0;
  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(Duration(milliseconds: (1300 / _visionSpeed).round()), (_) {
      if (mounted && _shown < s.picks.length) setState(() => _shown++);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// 自球団の判断が要らない間は、CPU の入札・指名を進める
  void _advance() {
    var guard = 0;
    while (s.stage == 'first' && !s.myFirstPending && guard++ < 20) {
      s.bidFirst(null);
    }
    s.runUntilMine();
  }

  void _after() {
    _advance();
    setState(() {
      if (_sel != null && !s.pool.contains(_sel)) _sel = null;
    });
  }

  Future<void> _bid() async {
    final p = _sel;
    if (p == null) return;
    final entries = s.bidFirst(p);
    setState(() => _sel = null);
    final mine = entries.where((e) => e.bidders.contains(my)).firstOrNull;
    final lots = entries.where((e) => e.bidders.length > 1).toList();
    if (mine != null && mine.bidders.length > 1 && mounted) {
      await showDraftLottery(context,
          title: s.lotteries.length == 1 ? '1位指名　抽選' : '外れ1位（${s.lotteries.length}回目）　抽選',
          player: '${mine.prospect.player.listName}（${mine.prospect.school}）',
          tickets: {for (final b in mine.bidders) _short(b): 1},
          mine: _short(my),
          winner: _short(mine.winner));
    }
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(s.lotteries.length == 1 ? '1位指名の結果' : '外れ1位（${s.lotteries.length}回目）の結果'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (mine != null)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(color: mine.winner == my ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2), borderRadius: BorderRadius.circular(10)),
                child: Text(
                  mine.winner == my
                      ? '${mine.prospect.player.listName}の交渉権を獲得！${mine.bidders.length > 1 ? '（${mine.bidders.length}球団の抽選）' : '（単独指名）'}'
                      : '${mine.prospect.player.lastName}は${mine.bidders.length}球団の抽選で${_short(mine.winner)}が獲得。外れ1位を選びます',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            if (lots.isNotEmpty) const Text('抽選', style: TextStyle(fontWeight: FontWeight.w800)),
            for (final e in lots) Text('${e.prospect.player.lastName}（${e.prospect.school}）：${e.bidders.map(_short).join('・')} → ${_short(e.winner)}', style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 8),
            const Text('単独指名', style: TextStyle(fontWeight: FontWeight.w800)),
            for (final e in entries.where((e) => e.bidders.length == 1)) Text('${_short(e.winner)}：${e.prospect.player.lastName}（${e.prospect.player.mainPosition}・${e.prospect.school}）', style: const TextStyle(fontSize: 13)),
          ]),
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(d), child: const Text('次へ'))],
      ),
    );
    _after();
  }

  int get _compFree => (s.compLeft[my] ?? 0) - _compBids.values.fold<int>(0, (a, b) => a + b);

  /// 選んだ候補に補償の枠を1つ入れる（同じ候補に重ねられる）
  void _addCompBid() {
    final p = _sel;
    if (p == null || _compFree <= 0) return;
    setState(() => _compBids[p.id] = (_compBids[p.id] ?? 0) + 1);
  }

  /// 補償の巡の入札（bids が空なら残りの枠を使わない）
  Future<void> _bidComp({bool skip = false}) async {
    final label = s.compLabel;
    final lots = s.bidComp(skip ? null : Map.of(_compBids));
    setState(() {
      _compBids.clear();
      _sel = null;
    });
    if (!skip) {
      final mine = lots.where((e) => e.tickets.containsKey(my)).toList();
      for (final e in mine.where((e) => e.tickets.length > 1)) {
        if (!mounted) return;
        await showDraftLottery(context,
            title: '$label　抽選',
            player: '${e.prospect.player.listName}（${e.prospect.school}）',
            tickets: {for (final t in e.tickets.entries) _short(t.key): t.value},
            mine: _short(my),
            winner: _short(e.winner));
      }
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (d) => AlertDialog(
          title: Text('$label入札の結果'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final e in mine)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(color: e.winner == my ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2), borderRadius: BorderRadius.circular(10)),
                  child: Text(
                    e.winner == my
                        ? '${e.prospect.player.listName}の交渉権を獲得！（くじ${e.tickets[my]}本／全${e.tickets.values.fold<int>(0, (a, b) => a + b)}本）'
                        : '${e.prospect.player.lastName}は${_short(e.winner)}が獲得（こちらのくじ${e.tickets[my]}本は残り、再入札できます）',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              const Text('ほかの入札', style: TextStyle(fontWeight: FontWeight.w800)),
              for (final e in lots.where((e) => !e.tickets.containsKey(my)))
                Text('${e.prospect.player.lastName}（${e.prospect.school}）：${e.tickets.entries.map((t) => '${_short(t.key)}${t.value > 1 ? '×${t.value}' : ''}').join('・')} → ${_short(e.winner)}', style: const TextStyle(fontSize: 13)),
            ]),
          ),
          actions: [FilledButton(onPressed: () => Navigator.pop(d), child: const Text('次へ'))],
        ),
      );
    }
    _after();
  }

  void _pick() {
    final p = _sel;
    if (p == null || !s.myTurn) return;
    s.pick(p);
    _sel = null;
    _after();
  }

  void _pass() {
    if (!s.myTurn) return;
    s.pass();
    _after();
  }

  void _auto() {
    s.runAll();
    setState(() => _sel = null);
  }

  /// やり直す：ここまでの指名を捨てて会議を閉じる（確定するまではセーブに反映していない）。もう一度開けば、同じ候補で最初から
  Future<void> _redo() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('ドラフト会議をやり直しますか？'),
        content: const Text('ここまでの指名（他球団の指名・抽選の結果も）をすべて取り消して、会議を閉じます。\nもう一度開くと、同じ候補で最初からやり直せます。他球団の指名や抽選の結果は変わることがあります。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('続ける')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('やり直す')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    _applied = true; // 戻るのを止めない（結果は反映しない）
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) Navigator.of(context).pop(); });
  }

  void _finish() {
    if (_applied) return;
    _applied = true;
    app.applyDraft(s);
    Navigator.of(context).pop();
  }

  String get _status {
    switch (s.stage) {
      case 'first':
        return s.myFirstPending ? (s.lotteries.isEmpty ? '1位入札：候補を選んで入札してください（全球団が同時に入札、重複は抽選）' : '外れ1位：もう一度入札してください') : '1位の入札を待っています';
      case 'comp':
        return s.myCompPending
            ? '${s.compLabel}入札（補償の指名権）：残り${s.compLeft[my]}枠。候補を選んで枠を入れてください（同じ選手に重ねると当たりやすい。当たれば重ねた枠は使い切り、外れた枠は残る）'
            : '${s.compLabel}（補償の指名権を持つ球団の入札）を待っています';
      case 'main':
        return s.myTurn ? '${s.round}巡目：あなたの指名です（ウェーバー）' : '${s.round}巡目：${_short(s.currentTeamId ?? '')}が指名中';
      case 'ikusei':
        return s.myTurn ? '育成ドラフト ${s.round}巡目：あなたの指名です' : '育成ドラフト：${_short(s.currentTeamId ?? '')}が指名中';
      default:
        return 'すべての指名が終わりました。結果を確定してください';
    }
  }

  @override
  Widget build(BuildContext context) {
    final team = app.teamById(my);
    if (team != null) scoutEyeForDetail = app.scoutEye(team);
    prospectPlayerName = (id) => app.teams.expand((t) => t.players).where((x) => x.id == id).map((x) => x.registeredName).firstOrNull;
    final slots = s.slots[my] ?? 0;
    return PopScope(
      canPop: s.stage == 'done' || _applied || (s.stage == 'first' && s.lotteries.isEmpty),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ドラフト会議の途中です。「残りをおまかせ」で最後まで進めるか、「やり直す」で最初からやり直せます')));
      },
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(title: Text('${s.year}年 ドラフト会議'), automaticallyImplyLeading: s.stage == 'done' || (s.stage == 'first' && s.lotteries.isEmpty)),
        body: LayoutBuilder(builder: (context, c) {
          final wide = c.maxWidth >= 900;
          final head = _header(team == null ? '' : teamShort(team), slots);
          if (wide) {
            return Column(children: [
              head,
              Expanded(
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(flex: 3, child: _candidates()),
                  Container(width: 1, color: _line),
                  Expanded(flex: 2, child: _vision()),
                ]),
              ),
              _actions(),
            ]);
          }
          return DefaultTabController(
            length: 2,
            child: Column(children: [
              head,
              const Material(color: Colors.white, child: TabBar(labelColor: _ink, tabs: [Tab(text: '候補'), Tab(text: 'ビジョン')])),
              Expanded(child: TabBarView(children: [_candidates(), _vision()])),
              _actions(),
            ]),
          );
        }),
      ),
    );
  }

  Widget _header(String name, int slots) => Container(
        width: double.infinity,
        color: _navy,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_status, style: const TextStyle(color: _lime, fontWeight: FontWeight.w800, fontSize: 14)),
          const SizedBox(height: 4),
          const SizedBox(height: 2),
          Text(slots > 0 ? '本指名 あと $slots人' : '本指名の枠なし', style: TextStyle(color: slots > 0 ? _lime : const Color(0xFFFCA5A5), fontWeight: FontWeight.w900, fontSize: 20)),
          Text('$name　指名済み ${s.picksOf(my).where((x) => !x.ikusei).length}人（育成 ${s.picksOf(my).where((x) => x.ikusei).length}人）　支配下の上限${RosterEngine.maxShihaika}人', style: const TextStyle(color: Color(0xFF8EA3BF), fontSize: 12)),
          const Text('本指名は、支配下の枠が許す限り何人でもできます。候補は長押しで詳細', style: TextStyle(color: Color(0xFF8EA3BF), fontSize: 11)),
          if (slots < 6 && s.stage == 'first' && s.lotteries.isEmpty)
            const Text('枠が足りなければ、会議の前に戦力外通告で空けられます（いったん戻って フロント → 補強 → 戦力外通告・育成）。育成指名は枠に関係なくできます',
                style: TextStyle(color: Color(0xFFFDE68A), fontSize: 12)),
        ]),
      );

  Widget _candidates() {
    final list = _list;
    final fc = s.round == 1 && s.stage == 'first' ? widget.appState.draftForecast() : const <String, String>{};
    return Column(children: [
      Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          draftCategoryBar(_pool, _pos, (v) => setState(() => _pos = v)),
          Row(children: [
            FilterChip(label: const Text('★注目のみ'), selected: _watchedOnly, visualDensity: VisualDensity.compact, onSelected: (v) => setState(() => _watchedOnly = v)),
            const SizedBox(width: 8),
            Text('${list.length}人（守備位置ごと）', style: const TextStyle(color: _sub, fontSize: 12)),
          ]),
        ]),
      ),
      Expanded(
        child: ListView(children: [
          ...draftPosSections(
            list,
            (p) => ProspectRow(
              p: p,
              forecast: fc[p.id],
              selected: identical(p, _sel),
              onTap: () => setState(() => _sel = identical(p, _sel) ? null : p),
              onWatch: () => setState(() => p.watched = !p.watched),
            ),
          ),
        ]),
      ),
    ]);
  }

  /// 会議場のビジョン（白い盤面）：12球団の枠に、その巡の選択希望選手を発表した順に出す。巡は切り替えて見られる（ふだんは最新の巡）
  Widget _vision() {
    final shown = s.picks.take(_shown.clamp(0, s.picks.length)).toList();
    final rounds = <String>[];
    for (final pk in shown) {
      if (!rounds.contains(pk.label)) rounds.add(pk.label);
    }
    final last = shown.isEmpty ? null : shown.last;
    final round = (_visionRound != null && rounds.contains(_visionRound)) ? _visionRound! : (last?.label ?? '1位');
    final teams = s.waiver.reversed.toList();
    final year = s.year;
    Widget cell(String tid) {
      final team = app.teamById(tid);
      final pk = shown.where((x) => x.label == round && x.teamId == tid).toList();
      final isLast = last != null && pk.contains(last);
      final color = team == null ? _sub : teamColor(app.teams, team);
      return Container(
        decoration: BoxDecoration(
          color: isLast ? const Color(0xFFFFF7D6) : Colors.white,
          border: Border.all(color: const Color(0xFFCBD5E1), width: 0.8),
        ),
        padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Container(width: 14, height: 9, color: color),
            const SizedBox(width: 4),
            Expanded(child: Text(_short(tid), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 9.5, color: tid == my ? const Color(0xFFB45309) : _sub, fontWeight: FontWeight.w700))),
          ]),
          const SizedBox(height: 4),
          if (pk.isEmpty) const SizedBox(height: 22),
          for (final x in pk) ...[
            Text(x.prospect.player.listName.replaceAll(' ', '　'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: _ink, letterSpacing: 1)),
            Text('${draftPosOf(x.prospect)}・${x.prospect.school}${x.lottery ? '（抽選）' : ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 8.5, color: _sub)),
          ],
        ]),
      );
    }

    return Container(
      color: const Color(0xFFE5E7EB),
      child: ListView(padding: const EdgeInsets.fromLTRB(10, 10, 10, 20), children: [
        // ビジョンの盤面
        Container(
          decoration: BoxDecoration(color: const Color(0xFFF8FAFC), border: Border.all(color: const Color(0xFF94A3B8)), boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 8, offset: Offset(0, 2))]),
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('$year　プロ野球ドラフト会議', textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: _ink, letterSpacing: 1)),
            const SizedBox(height: 2),
            Text('第${round.replaceAll('位', '')}巡　選択希望選手', textAlign: TextAlign.center, style: const TextStyle(fontSize: 11.5, color: _sub, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            LayoutBuilder(builder: (context, c) {
              final cols = c.maxWidth >= 640 ? 4 : 3;
              return GridView.count(
                crossAxisCount: cols,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: c.maxWidth / cols / 62,
                children: [for (final t in teams) cell(t)],
              );
            }),
          ]),
        ),
        const SizedBox(height: 8),
        // 発表の読み上げ・巡の切り替え
        if (last != null)
          Text('${_short(last.teamId)}　第${last.label.replaceAll('位', '')}巡選択希望選手　${last.prospect.player.listName}　${draftPosOf(last.prospect)}　${last.prospect.school}',
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: _ink)),
        Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          for (final r in rounds)
            ChoiceChip(
              label: Text(r, style: const TextStyle(fontSize: 11.5)),
              selected: r == round,
              visualDensity: VisualDensity.compact,
              onSelected: (_) => setState(() => _visionRound = r == rounds.last ? null : r),
            ),
          if (_shown < s.picks.length) TextButton(onPressed: () => setState(() => _shown = s.picks.length), child: Text('発表を飛ばす（残り${s.picks.length - _shown}）')),
          // 発表の速さ
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Text('速さ ', style: TextStyle(fontSize: 11.5, color: _sub)),
            for (final v in const [0.7, 1.0, 1.2, 1.5])
              Padding(
                padding: const EdgeInsets.only(right: 3),
                child: ChoiceChip(
                  label: Text('×$v', style: const TextStyle(fontSize: 11)),
                  selected: _visionSpeed == v,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  onSelected: (_) => setState(() {
                    _visionSpeed = v;
                    _startTicker();
                  }),
                ),
              ),
          ]),
        ]),
      ]),
    );
  }

  Widget _actions() {
    final buttons = <Widget>[];
    if (s.stage == 'done') {
      buttons.add(TextButton(onPressed: _redo, child: const Text('やり直す')));
      buttons.add(FilledButton.icon(onPressed: _finish, icon: const Icon(Icons.check), label: const Text('結果を確定する')));
    } else {
      if (s.stage == 'first' && s.myFirstPending) {
        buttons.add(FilledButton(onPressed: _sel == null ? null : _bid, child: Text(_sel == null ? '候補を選んでください' : '${_sel!.player.lastName}を1位で入札')));
      }
      if (s.myCompPending) {
        final byId = {for (final p in s.pool) p.id: p};
        for (final e in _compBids.entries)
          buttons.add(InputChip(
            label: Text('${byId[e.key]?.player.lastName ?? ''}×${e.value}'),
            onDeleted: () => setState(() => _compBids.remove(e.key)),
          ));
        buttons.add(OutlinedButton(onPressed: _sel == null || _compFree <= 0 ? null : _addCompBid, child: Text(_sel == null ? '候補を選んでください' : '${_sel!.player.lastName}に1枠（残り$_compFree）')));
        buttons.add(FilledButton(onPressed: _compBids.isEmpty ? null : () => _bidComp(), child: Text('${s.compLabel}で入札')));
        buttons.add(TextButton(onPressed: () => _bidComp(skip: true), child: const Text('残りの枠を使わない')));
      }
      if ((s.stage == 'main' || s.stage == 'ikusei') && s.myTurn) {
        buttons.add(FilledButton(onPressed: _sel == null ? null : _pick, child: Text(_sel == null ? '候補を選んでください' : '${_sel!.player.lastName}を指名')));
        buttons.add(OutlinedButton(onPressed: _pass, child: Text(s.stage == 'main' ? '本指名を終える' : '育成指名を終える')));
      }
      buttons.add(TextButton(onPressed: _redo, child: const Text('やり直す')));
      buttons.add(TextButton(onPressed: _auto, child: const Text('残りをおまかせ')));
    }
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: SafeArea(top: false, child: Wrap(spacing: 10, runSpacing: 8, alignment: WrapAlignment.end, children: buttons)),
    );
  }
}
