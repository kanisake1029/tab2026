import '../widgets/chip_grid.dart';
import 'package:flutter/material.dart';
import '../engine/other_league_engine.dart';
import '../models/other_league.dart';
import '../models/player.dart';
import '../providers/app_state.dart';
import '../widgets/frozen_table.dart';
import '../widgets/player_detail_dialog.dart';
import '../utils/salary_utils.dart';

const _ink = Color(0xFF1C1917);
const _sub = Color(0xFF78716C);
const _line = Color(0xFFE7E5E4);

String _r3(double v) => v.toStringAsFixed(3).replaceFirst(RegExp(r'^0'), '');
String _ip(int outs) => '${outs ~/ 3}${outs % 3 == 0 ? '' : '.${outs % 3}'}';

/// 他リーグの選手をタップしたとき：詳細を見るか、獲得を申し込む（声をかける）
/// MLB 球団の傘下（3A・2A・1A の順）
List<OTeam> affiliatesOf(OtherWorld w, OTeam mlb) => [
      for (final lg in const ['AAA', 'AA', 'A'])
        for (final t in w.teams)
          if (t.leagueId == lg && t.org == mlb.id) t,
    ];

Future<void> openOtherPlayer(BuildContext context, AppState app, Player p, VoidCallback changed) async {
  final block = app.otherOfferBlock(p);
  final back = app.otherWorld?.fromNpb[p.id];
  final act = await showModalBottomSheet<String>(
    context: context,
    builder: (c) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
          child: Text('${p.registeredName}（${p.age}歳・${p.mainPosition}・総合${p.ovr}）${back != null ? '\n$back' : ''}', style: const TextStyle(fontWeight: FontWeight.w800, height: 1.4)),
        ),
        ListTile(leading: const Icon(Icons.badge_outlined), title: const Text('詳しく見る（能力・来歴）'), onTap: () => Navigator.pop(c, 'detail')),
        if (block == null) ...[
          ListTile(
            leading: const Icon(Icons.handshake_outlined),
            title: Text('声をかける（支配下・年俸${formatSalary(app.otherSalary(p))}）'),
            subtitle: Text('受けてくれる確率 ${(app.otherAcceptChance(p) * 100).round()}%　支配下は7月31日まで'),
            onTap: () => Navigator.pop(c, 'offer'),
          ),
          ListTile(
            leading: const Icon(Icons.school_outlined),
            title: const Text('育成で声をかける'),
            subtitle: Text('受けてくれる確率 ${(app.otherAcceptChance(p) * 70).round()}%'),
            onTap: () => Navigator.pop(c, 'ikusei'),
          ),
        ] else
          ListTile(leading: const Icon(Icons.info_outline), title: Text(block, style: const TextStyle(fontSize: 13))),
      ]),
    ),
  );
  if (!context.mounted || act == null) return;
  if (act == 'detail') {
    await showPlayerDetail(context, app, p, allowActions: false);
    return;
  }
  final err = app.offerOtherPlayer(p, ikusei: act == 'ikusei');
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err ?? '${p.registeredName}と契約しました')));
  changed();
}

/// 他リーグ調査（6つ目のタブ）：MLB・マイナー・海外・米独立・日本独立リーグの順位表・成績・球団
class OtherLeaguesScreen extends StatefulWidget {
  final AppState appState;
  const OtherLeaguesScreen({super.key, required this.appState});

  @override
  State<OtherLeaguesScreen> createState() => _OtherLeaguesScreenState();
}

class _OtherLeaguesScreenState extends State<OtherLeaguesScreen> {
  static String _group = 'アメリカ';
  static String _league = 'MLB';
  static int _view = 0; // 0 順位 1 成績 2 球団 3 歴代優勝

  AppState get app => widget.appState;

  @override
  Widget build(BuildContext context) {
    final w = app.otherWorld;
    if (w == null) {
      return const Scaffold(body: Center(child: Text('他リーグを準備しています…', style: TextStyle(color: _sub))));
    }
    final lg = OtherLeagueEngine.leagues[_league]!;
    final inGroup = OtherLeagueEngine.leagues.values.where((l) => l.group == _group).toList();
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F4),
      appBar: AppBar(
        title: const Text('他リーグ調査'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(84),
          child: Column(children: [
            ChipGrid<String>(
              items: [for (final g in [...OtherLeagueEngine.groups, '元NPB', 'リーグ比較']) (g, g)],
              selected: _group,
              minWidth: 70,
              onSelect: (g) => setState(() {
                _group = g;
                if (g != '元NPB' && g != 'リーグ比較') _league = OtherLeagueEngine.leagues.values.firstWhere((l) => l.group == g).id;
              }),
            ),
            if (inGroup.isNotEmpty)
              ChipGrid<String>(items: [for (final l in inGroup) (l.id, l.name)], selected: _league, minWidth: 70, selectedColor: const Color(0xFF15803D), onSelect: (id) => setState(() => _league = id)),
          ]),
        ),
      ),
      body: Column(children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          child: Row(children: [
            Expanded(
              child: Text(
                '${lg.name}　${lg.divisions.length > 1 ? '${lg.divisions.length}地区' : '1リーグ'}${w.teamsOf(lg.id).length}球団　${lg.games}試合（${OLeague.opening(w.simDate.year).month}/${OLeague.opening(w.simDate.year).day}〜${lg.endM}/${lg.endD}）${lg.inSeason(w.simDate) ? '' : '　シーズン外'}',
                style: const TextStyle(fontSize: 11.5, color: _sub),
              ),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
          child: _group == '元NPB' || _group == 'リーグ比較' ? const SizedBox.shrink() : SegmentedButton<int>(
            segments: const [ButtonSegment(value: 0, label: Text('順位')), ButtonSegment(value: 1, label: Text('成績')), ButtonSegment(value: 2, label: Text('球団')), ButtonSegment(value: 3, label: Text('歴代'))],
            selected: {_view},
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            onSelectionChanged: (v) => setState(() => _view = v.first),
          ),
        ),
        Expanded(
          child: _group == '元NPB' ? _fromNpb(w) : _group == 'リーグ比較' ? _compare(w) : switch (_view) {
            0 => _standings(w, lg),
            1 => _leaders(w, lg),
            2 => _teams(w, lg),
            _ => _history(w, lg),
          },
        ),
      ]),
    );
  }

  /// NPB から移った選手（ポスティング・海外FA・戦力外・退団）の今と去就
  Widget _fromNpb(OtherWorld w) {
    final l = [
      for (final e in w.fromNpb.entries)
        if (w.teamOfPlayer(e.key) case final t?) (t, t.players.firstWhere((p) => p.id == e.key), e.value),
    ];
    if (l.isEmpty) {
      return const Padding(padding: EdgeInsets.all(16), child: Text('NPB から他リーグへ移った選手はまだいません。ポスティング・海外FA・戦力外（自由契約のまま1月31日を過ぎた選手）・外国人の退団で移った選手がここに出ます', style: TextStyle(color: _sub)));
    }
    String line(Player p) {
      final s = p.seasonStats;
      if (p.isPitcher) return '${s.pitchApps}試合 ${s.wins}勝${s.losses}敗${s.saves > 0 ? '${s.saves}S' : ''} 防御率${s.inningsPitched == 0 ? '-' : s.era.toStringAsFixed(2)}';
      return '${s.games}試合 打率${s.atBats == 0 ? '-' : _r3(s.battingAverage)} ${s.homeRuns}本 ${s.rbi}打点';
    }

    return ListView(padding: const EdgeInsets.only(bottom: 20), children: [
      const Padding(
        padding: EdgeInsets.fromLTRB(12, 6, 12, 4),
        child: Text('今季の成績と去就。タップすると詳しく見たり、声をかけて日本球界へ呼び戻せます（3A でくすぶっている選手などは受けてくれやすい）', style: TextStyle(fontSize: 11, color: _sub)),
      ),
      for (final (t, p, note) in l)
        ListTile(
          dense: true,
          title: Text('${p.registeredName}（${p.age}歳・${p.mainPosition}）', style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text('${OtherLeagueEngine.leagues[t.leagueId]?.name}　${t.name}　${line(p)}\n$note', style: const TextStyle(fontSize: 11.5, height: 1.4)),
          isThreeLine: true,
          onTap: () => openOtherPlayer(context, app, p, () => setState(() {})),
        ),
    ]);
  }

  /// リーグ比較：力（OVR）の平均・上位層と、年齢層の割合。NPB の1軍・2軍も並べる
  Widget _compare(OtherWorld w) {
    final rows = <(String, List<Player>)>[
      ('NPB 1軍', [for (final t in app.teams) for (final p in t.players) if (t.roster1G.contains(p.id)) p]),
      ('NPB 2軍', [for (final t in app.teams) for (final p in t.players) if (!t.roster1G.contains(p.id) && !p.ikusei) p]),
      ('NPB 育成', [for (final t in app.teams) for (final p in t.players) if (p.ikusei) p]),
      for (final lg in OtherLeagueEngine.leagues.values) (lg.name, [for (final t in w.teamsOf(lg.id)) ...t.players]),
    ];
    return ListView(padding: const EdgeInsets.only(bottom: 20), children: [
      const Padding(
        padding: EdgeInsets.fromLTRB(12, 6, 12, 4),
        child: Text('力（総合 OVR）の平均・上位10%・上位3%の平均・最高と、年齢層の割合（%）。調整したいリーグと目標の値を伝えてください', style: TextStyle(fontSize: 11, color: _sub)),
      ),
      _card(
        'リーグごとの顔ぶれ',
        FrozenTable(
          leadHeader: 'リーグ',
          leadWidth: 92,
          rowHeight: 24,
          compact: true,
          headers: const ['人数', '平均', '上位10%', '上位3%', '最高', '〜22', '23〜26', '27〜30', '31〜34', '35〜'],
          widths: const [34, 34, 46, 44, 32, 32, 42, 42, 42, 32],
          rows: [
            for (final (name, ps) in rows)
              () {
                final pr = OtherLeagueEngine.profile(ps);
                return FrozenRow(
                  color: name.startsWith('NPB') ? const Color(0xFFFEF9C3) : null,
                  lead: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                  cells: ['${ps.length}', pr.avg.toStringAsFixed(1), pr.top10.toStringAsFixed(1), pr.top3.toStringAsFixed(1), '${pr.max}', for (final a in pr.ages) '$a'],
                );
              }(),
          ],
        ),
      ),
    ]);
  }

  Widget _card(String title, Widget child) => Container(
        margin: const EdgeInsets.fromLTRB(6, 4, 6, 6),
        padding: const EdgeInsets.fromLTRB(2, 6, 2, 4),
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: _line), borderRadius: BorderRadius.circular(8)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(padding: const EdgeInsets.fromLTRB(6, 0, 6, 4), child: Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5))),
          child,
        ]),
      );

  /// 順位表（地区ごと）
  Widget _standings(OtherWorld w, OLeague lg) {
    final ts = w.teamsOf(lg.id);
    return ListView(padding: const EdgeInsets.only(bottom: 20), children: [
      for (var div = 0; div < lg.divisions.length; div++)
        () {
          final dt = ts.where((t) => t.division == div).toList()..sort((a, b) => b.pct.compareTo(a.pct));
          final top = dt.isEmpty ? null : dt.first;
          return _card(
            lg.divisions[div].isEmpty ? '順位' : lg.divisions[div],
            FrozenTable(
              leadHeader: '球団',
              leadWidth: 130,
              rowHeight: 26,
              compact: true,
              headers: const ['試合', '勝', '敗', '分', '勝率', '差'],
              widths: const [32, 30, 30, 26, 40, 34],
              rows: [
                for (final t in dt)
                  FrozenRow(
                    onTap: () => _openTeam(t),
                    lead: Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                    cells: [
                      '${t.w + t.l + t.d}', '${t.w}', '${t.l}', '${t.d}', t.w + t.l == 0 ? '-' : _r3(t.pct),
                      top == null || t == top ? '-' : (((top.w - t.w) + (t.l - top.l)) / 2).toStringAsFixed(1),
                    ],
                  ),
              ],
            ),
          );
        }(),
      const Padding(
        padding: EdgeInsets.fromLTRB(10, 2, 10, 0),
        child: Text('球団をタップすると選手と成績を見られます。シーズンが終わると、成績は選手の来歴に残ります', style: TextStyle(fontSize: 10.5, color: _sub)),
      ),
    ]);
  }

  /// 個人成績の上位（規定：打席は試合数×3.1、投球回は試合数×1.0）
  Widget _leaders(OtherWorld w, OLeague lg) {
    final ts = w.teamsOf(lg.id);
    final games = ts.isEmpty ? 0 : ts.map((t) => t.w + t.l + t.d).reduce((a, b) => a > b ? a : b);
    final all = [for (final t in ts) for (final p in t.players) (t, p)];
    int pa(PlayerStats s) => s.atBats + s.walks + s.sacFlies;
    Widget top(String title, List<(OTeam, Player)> l, String Function(PlayerStats) v) => _card(
          title,
          Column(children: [
            for (var i = 0; i < l.length && i < 10; i++)
              InkWell(
                onTap: () => openOtherPlayer(context, app, l[i].$2, () => setState(() {})),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  child: Row(children: [
                    SizedBox(width: 22, child: Text('${i + 1}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800))),
                    Expanded(child: Text('${l[i].$2.registeredName}（${l[i].$1.short}）', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5))),
                    Text(v(l[i].$2.seasonStats), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()])),
                  ]),
                ),
              ),
            if (l.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('まだ記録がありません', style: TextStyle(color: _sub, fontSize: 12))),
          ]),
        );
    List<(OTeam, Player)> by(bool Function(Player) f, num Function(PlayerStats) v, {bool low = false}) {
      final l = all.where((x) => f(x.$2)).toList()..sort((a, b) => low ? v(a.$2.seasonStats).compareTo(v(b.$2.seasonStats)) : v(b.$2.seasonStats).compareTo(v(a.$2.seasonStats)));
      return l;
    }

    final qPa = (games * 3.1).floor(), qOuts = games * 3;
    return ListView(padding: const EdgeInsets.only(bottom: 20), children: [
      top('打率（規定打席$qPa）', by((p) => !p.isPitcher && pa(p.seasonStats) >= qPa && qPa > 0, (s) => s.battingAverage), (s) => _r3(s.battingAverage)),
      top('本塁打', by((p) => !p.isPitcher && p.seasonStats.homeRuns > 0, (s) => s.homeRuns), (s) => '${s.homeRuns}'),
      top('打点', by((p) => !p.isPitcher && p.seasonStats.rbi > 0, (s) => s.rbi), (s) => '${s.rbi}'),
      top('盗塁', by((p) => !p.isPitcher && p.seasonStats.stolenBases > 0, (s) => s.stolenBases), (s) => '${s.stolenBases}'),
      top('防御率（規定投球回${_ip(qOuts)}）', by((p) => p.isPitcher && p.seasonStats.inningsPitched >= qOuts && qOuts > 0, (s) => s.era, low: true), (s) => s.era.toStringAsFixed(2)),
      top('勝利', by((p) => p.isPitcher && p.seasonStats.wins > 0, (s) => s.wins), (s) => '${s.wins}'),
      top('セーブ', by((p) => p.isPitcher && p.seasonStats.saves > 0, (s) => s.saves), (s) => '${s.saves}'),
      top('奪三振', by((p) => p.isPitcher && p.seasonStats.pitcherStrikeouts > 0, (s) => s.pitcherStrikeouts), (s) => '${s.pitcherStrikeouts}'),
    ]);
  }

  Widget _teams(OtherWorld w, OLeague lg) {
    final ts = w.teamsOf(lg.id);
    return ListView(padding: const EdgeInsets.only(bottom: 20), children: [
      for (final t in ts)
        ListTile(
          dense: true,
          title: Text(t.name, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text('${lg.divisions[t.division].isEmpty ? '' : '${lg.divisions[t.division]}　'}${t.w}勝${t.l}敗${t.d > 0 ? '${t.d}分' : ''}${t.org.isNotEmpty ? '　${w.teams.firstWhere((x) => x.id == t.org).name}傘下' : ''}${t.leagueId == 'MLB' ? '\n傘下：${affiliatesOf(w, t).map((a) => '${OtherLeagueEngine.leagues[a.leagueId]!.level} ${a.name}').join('・')}' : ''}', style: const TextStyle(fontSize: 11.5)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _openTeam(t),
        ),
    ]);
  }

  /// 歴代：年ごとの順位表とタイトル（開いて見る）。記録を始める前の年は優勝球団だけ
  Widget _history(OtherWorld w, OLeague lg) {
    final l = w.champions.where((c) => c.contains('　${lg.name}　')).toList();
    final ss = w.seasons[lg.id] ?? const [];
    final years = {for (final s in ss) s['y'] as int};
    return ListView(padding: const EdgeInsets.all(10), children: [
      const Text('歴代の記録（年をタップすると順位表とタイトル）', style: TextStyle(fontWeight: FontWeight.w900)),
      const SizedBox(height: 4),
      if (l.isEmpty && ss.isEmpty) const Text('まだありません（このゲームで終えたシーズンから記録します）', style: TextStyle(color: _sub, fontSize: 12)),
      for (final s in ss)
        Card(
          margin: const EdgeInsets.only(bottom: 6),
          child: ExpansionTile(
            key: PageStorageKey<String>('olHist_${lg.id}_${s['y']}'),
            dense: true,
            title: Text(l.firstWhere((c) => c.startsWith('${s['y']}　'), orElse: () => '${s['y']}'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('順位', style: TextStyle(fontSize: 11.5, color: _sub, fontWeight: FontWeight.w800)),
              for (final x in (s['st'] as List)) Text('$x', style: const TextStyle(fontSize: 12, height: 1.5, fontFeatures: [FontFeature.tabularFigures()])),
              const SizedBox(height: 6),
              const Text('タイトル（上位3人）', style: TextStyle(fontSize: 11.5, color: _sub, fontWeight: FontWeight.w800)),
              for (final x in (s['ld'] as List)) Text('$x', style: const TextStyle(fontSize: 12, height: 1.5)),
            ],
          ),
        ),
      for (final c in l)
        if (!years.contains(int.tryParse(c.split('　').first))) Text(c, style: const TextStyle(fontSize: 12.5, height: 1.6)),
    ]);
  }

  void _openTeam(OTeam t) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => OtherTeamScreen(app: app, team: t)));
}

/// 他リーグの1球団：選手と今季成績（投手・野手）、過去の順位
class OtherTeamScreen extends StatelessWidget {
  final AppState app;
  final OTeam team;
  const OtherTeamScreen({super.key, required this.app, required this.team});

  /// 組織：MLB 球団と傘下の 3A・2A・1A（タップでその球団へ）。選手は毎年、組織の中で力の順に昇格・降格する
  Widget _orgBox(BuildContext context, OtherWorld w) {
    final mlb = team.leagueId == 'MLB' ? team : w.teams.firstWhere((x) => x.id == team.org, orElse: () => team);
    final chain = [mlb, ...affiliatesOf(w, mlb)];
    return Container(
      margin: const EdgeInsets.fromLTRB(2, 0, 2, 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: _line), borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('${mlb.name}の組織（MLB と傘下のマイナー）', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
        const Text('若手はマイナーで育ち、毎年の入れ替えで力の順に上がっていきます', style: TextStyle(fontSize: 10.5, color: _sub)),
        const SizedBox(height: 4),
        for (final t in chain)
          InkWell(
            onTap: t.id == team.id ? null : () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => OtherTeamScreen(app: app, team: t))),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                SizedBox(width: 36, child: Text(OtherLeagueEngine.leagues[t.leagueId]!.level, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: _sub))),
                Expanded(child: Text(t.name, style: TextStyle(fontSize: 13, fontWeight: t.id == team.id ? FontWeight.w900 : FontWeight.w600, color: t.id == team.id ? _ink : const Color(0xFF1D4ED8)))),
                Text('${t.w}勝${t.l}敗', style: const TextStyle(fontSize: 11.5, color: _sub)),
                if (t.id != team.id) const Icon(Icons.chevron_right, size: 16, color: _sub),
              ]),
            ),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lg = OtherLeagueEngine.leagues[team.leagueId]!;
    final bats = team.players.where((p) => !p.isPitcher).toList()..sort((a, b) => b.seasonStats.atBats.compareTo(a.seasonStats.atBats));
    final pits = team.players.where((p) => p.isPitcher).toList()..sort((a, b) => b.seasonStats.inningsPitched.compareTo(a.seasonStats.inningsPitched));
    Widget lead(Player p) => Row(children: [
          Expanded(child: Text(p.registeredName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700))),
          Text('${p.age}', style: const TextStyle(fontSize: 10, color: _sub)),
        ]);
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F4),
      appBar: AppBar(title: Text(team.name)),
      body: ListView(padding: const EdgeInsets.fromLTRB(4, 6, 4, 20), children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
          child: Text('${lg.name}${lg.divisions[team.division].isEmpty ? '' : '・${lg.divisions[team.division]}'}　${team.w}勝${team.l}敗${team.d > 0 ? '${team.d}分' : ''}${team.history.isNotEmpty ? '\n${team.history.take(3).join('\n')}' : ''}',
              style: const TextStyle(fontSize: 12, color: _ink, height: 1.5)),
        ),
        if (app.otherWorld != null && (team.leagueId == 'MLB' || team.org.isNotEmpty)) _orgBox(context, app.otherWorld!),
        Container(
          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: _line), borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.fromLTRB(2, 6, 2, 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Padding(padding: EdgeInsets.fromLTRB(6, 0, 6, 4), child: Text('野手', style: TextStyle(fontWeight: FontWeight.w900))),
            FrozenTable(
              leadHeader: '選手・年齢',
              leadWidth: 118,
              rowHeight: 24,
              compact: true,
              headers: const ['守', '総合', '試合', '打数', '安打', '打率', '本', '点', '盗', 'OPS'],
              widths: const [26, 30, 30, 32, 30, 38, 26, 28, 26, 40],
              rows: [
                for (final p in bats)
                  () {
                    final s = p.seasonStats, pa = s.atBats + s.walks + s.sacFlies;
                    final obp = pa == 0 ? 0.0 : (s.hits + s.walks) / pa, slg = s.atBats == 0 ? 0.0 : s.totalBases / s.atBats;
                    return FrozenRow(
                      onTap: () => openOtherPlayer(context, app, p, () {}),
                      lead: lead(p),
                      cells: [p.mainPosition.substring(0, 1), '${p.ovr}', '${s.games}', '${s.atBats}', '${s.hits}', s.atBats == 0 ? '-' : _r3(s.battingAverage), '${s.homeRuns}', '${s.rbi}', '${s.stolenBases}', pa == 0 ? '-' : _r3(obp + slg)],
                    );
                  }(),
              ],
            ),
          ]),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: _line), borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.fromLTRB(2, 6, 2, 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Padding(padding: EdgeInsets.fromLTRB(6, 0, 6, 4), child: Text('投手', style: TextStyle(fontWeight: FontWeight.w900))),
            FrozenTable(
              leadHeader: '選手・年齢',
              leadWidth: 118,
              rowHeight: 24,
              compact: true,
              headers: const ['総合', '登板', '先発', '勝', '敗', 'S', '投球回', '防御率', '奪三振'],
              widths: const [30, 30, 30, 24, 24, 24, 38, 40, 36],
              rows: [
                for (final p in pits)
                  FrozenRow(
                    onTap: () => openOtherPlayer(context, app, p, () {}),
                    lead: lead(p),
                    cells: [
                      '${p.ovr}', '${p.seasonStats.pitchApps}', '${p.seasonStats.starts}', '${p.seasonStats.wins}', '${p.seasonStats.losses}', '${p.seasonStats.saves}',
                      _ip(p.seasonStats.inningsPitched), p.seasonStats.inningsPitched == 0 ? '-' : p.seasonStats.era.toStringAsFixed(2), '${p.seasonStats.pitcherStrikeouts}',
                    ],
                  ),
              ],
            ),
          ]),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(8, 6, 8, 0),
          child: Text('選手をタップすると、能力と来歴（過去のシーズンの成績）を見たり、声をかけたりできます', style: TextStyle(fontSize: 10.5, color: _sub)),
        ),
      ]),
    );
  }
}
