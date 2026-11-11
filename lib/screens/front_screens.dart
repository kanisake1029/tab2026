import 'package:flutter/material.dart';
import '../widgets/note_box.dart';

import '../engine/facility_engine.dart';
import '../engine/weather.dart';
import '../models/equipment.dart';
import '../models/stadium.dart';
import '../models/team.dart';
import '../providers/app_state.dart';

const _ink = Color(0xFF1C1917);
const _sub = Color(0xFF78716C);
const _line = Color(0xFFE7E5E4);
const _accent = Color(0xFF1D4ED8);

String _oku(int man) => man.abs() >= 10000 ? '${(man / 10000).toStringAsFixed(man % 10000 == 0 ? 0 : 1)}億円' : '$man万円';

Widget _card(String title, List<Widget> children, {String? note}) => Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: _line), borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
        if (note != null) NoteBox(note, margin: const EdgeInsets.only(top: 6)),
        const SizedBox(height: 8),
        ...children,
      ]),
    );

void _toast(BuildContext c, String? err, String ok) => ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(err ?? ok)));

/// Lv の目盛り（■■■□□）
Widget _lvBar(int lv, int max) => Row(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < max; i++)
        Container(width: 14, height: 8, margin: const EdgeInsets.only(right: 2), decoration: BoxDecoration(color: i < lv ? _accent : const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(2))),
    ]);

/// フロント「施設・球場」：球団施設への投資（4部門 Lv0〜5）と、本拠地球場の改修（オフに 1 回）
class FacilityTab extends StatefulWidget {
  final AppState app;
  final Team team;
  const FacilityTab({super.key, required this.app, required this.team});
  @override
  State<FacilityTab> createState() => _FacilityTabState();
}

class _FacilityTabState extends State<FacilityTab> {
  AppState get app => widget.app;

  Future<bool> _confirm(String title, String body) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('やめる')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('実行する'))],
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    final t = widget.team;
    final f = app.finOf(t);
    final park = t.park;
    final base = Stadium.byId(t.homeStadium);
    final up = FacilityEngine.upkeep(f.facilities);
    return ListView(padding: const EdgeInsets.fromLTRB(10, 12, 10, 24), children: [
      _card('球団の資金　${_oku(f.funds)}', [
        Text('施設の維持費 年${_oku(up)}（毎月の支出に入ります）', style: const TextStyle(fontSize: 12.5, color: _sub)),
      ], note: '黒字の資金を施設に投じると、練習・回復・スカウト・集客に永く効きます。施設はいつでも改修でき、Lv が上がるほど維持費もかかります。'),
      _card('球団施設・テクノロジー投資', [
        for (final fac in FacilityEngine.all) _facRow(fac, f.fac(fac.key), f.funds),
      ]),
      _card('本拠地球場の改修　${base.name}', [
        Wrap(spacing: 12, runSpacing: 4, children: [
          Text('両翼 ${park.fenceDistance(-45).toStringAsFixed(0)}m・左中間 ${park.fenceDistance(-25).toStringAsFixed(0)}m・中堅 ${park.fenceDistance(0).toStringAsFixed(0)}m', style: const TextStyle(fontSize: 12.5)),
          Text('フェンス ${park.fenceHeight(-25).toStringAsFixed(1)}m${park.oldFence > 0 ? '（テラスあり）' : ''}', style: const TextStyle(fontSize: 12.5)),
          Text('芝 ${park.turf}・${GameWeather.roofLabel(GameWeather.roofOf(park))}', style: const TextStyle(fontSize: 12.5)),
        ]),
        const SizedBox(height: 6),
        Text(
          app.parkWorkSeason ? (app.parkWorkDone ? 'このオフはもう改修しました（次のオフまで）' : '改修できる時期です（オフに1回）') : '改修はオフ（11月〜2月）に1回だけできます',
          style: TextStyle(fontSize: 12, color: app.parkWorkSeason && !app.parkWorkDone ? const Color(0xFF15803D) : _sub, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        for (final w in FacilityEngine.parkWorks) _workRow(t, w),
        const SizedBox(height: 4),
        const NoteBox('改修は試合の計算（打球の飛び・跳ね方）と、3D の試合の写しの芝の色・フェンスの形にすぐ反映されます。'),
      ]),
    ]);
  }

  Widget _facRow(Facility fac, int lv, int funds) {
    final cost = FacilityEngine.nextCost(fac.key, lv);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(fac.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800))),
          _lvBar(lv, FacilityEngine.maxLevel),
          const SizedBox(width: 6),
          Text('Lv$lv', style: const TextStyle(fontWeight: FontWeight.w900)),
        ]),
        Text(fac.effect, style: const TextStyle(fontSize: 12, color: _sub, height: 1.5)),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerRight,
          child: cost == null
              ? const Text('最大 Lv', style: TextStyle(fontSize: 12, color: _sub))
              : FilledButton.tonal(
                  onPressed: funds < cost
                      ? null
                      : () async {
                          if (!await _confirm('${fac.name}を Lv${lv + 1} に', '費用 ${_oku(cost)}。維持費は年${_oku((lv + 1) * fac.upkeepPerLevel)}になります。')) return;
                          if (!mounted) return;
                          _toast(context, app.buildFacility(fac.key), '${fac.name}を Lv${lv + 1} にしました');
                          setState(() {});
                        },
                  child: Text('Lv${lv + 1} にする（${_oku(cost)}）'),
                ),
        ),
      ]),
    );
  }

  Widget _workRow(Team t, (String, String, int, String) w) {
    final (key, name, _, desc) = w;
    final on = switch (key) { 'terrace' => app.hasTerrace(t), 'wall' => app.hasWall(t), _ => false };
    final label = switch (key) {
      'terrace' => on ? 'テラスを撤去' : 'テラスを新設',
      'wall' => on ? 'フェンスを元に戻す' : 'フェンスを高くする',
      _ => '${t.park.turf == '天然芝' ? '人工芝' : '天然芝'}に張り替え',
    };
    final removing = (key == 'terrace' || key == 'wall') && on;
    final cost = FacilityEngine.parkCost(key, removing: removing);
    final can = app.parkWorkSeason && !app.parkWorkDone && app.finOf(t).funds >= cost;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$name${on ? '（いま：あり）' : ''}', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
            Text(desc, style: const TextStyle(fontSize: 11.5, color: _sub, height: 1.45)),
          ]),
        ),
        const SizedBox(width: 8),
        OutlinedButton(
          onPressed: !can
              ? null
              : () async {
                  if (!await _confirm(label, '費用 ${_oku(cost)}。このオフの改修はこれ1回だけです。')) return;
                  if (!mounted) return;
                  _toast(context, app.doParkWork(key), '$labelしました');
                  setState(() {});
                },
          child: Text('$label\n${_oku(cost)}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
        ),
      ]),
    );
  }
}

/// フロント「メーカー」：用具メーカー（架空）とのアドバイザリー契約と、タイトルを取った選手のコラボグッズ
class MakerTab extends StatefulWidget {
  final AppState app;
  final Team team;
  const MakerTab({super.key, required this.app, required this.team});
  @override
  State<MakerTab> createState() => _MakerTabState();
}

class _MakerTabState extends State<MakerTab> {
  AppState get app => widget.app;

  @override
  Widget build(BuildContext context) {
    final t = widget.team;
    final f = app.finOf(t);
    return ListView(padding: const EdgeInsets.fromLTRB(10, 12, 10, 24), children: [
      if (app.makerCollabs.isNotEmpty)
        _card('企画できるコラボ・レプリカグッズ', [
          for (var i = 0; i < app.makerCollabs.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                Expanded(child: Text('${app.makerCollabs[i]['maker']} × ${app.makerCollabs[i]['player']}\n${app.makerCollabs[i]['year']}年 ${app.makerCollabs[i]['title']}・レプリカ${app.makerCollabs[i]['item']}', style: const TextStyle(fontSize: 13))),
                FilledButton(
                  onPressed: () {
                    _toast(context, app.launchCollab(i), 'コラボグッズを発売しました');
                    setState(() {});
                  },
                  child: const Text('企画する'),
                ),
              ]),
            ),
        ], note: '契約しているメーカーの用具でタイトルを取った選手の記念グッズです。人気に応じて1〜3億円の特別収入になります。'),
      _card('用具メーカーとのアドバイザリー契約（${f.makerDeals.length} / ${EquipOps.maxMakerDeals}社）', [
        for (final m in makers)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Container(width: 10, height: 34, decoration: BoxDecoration(color: Color(makerColors[m] ?? 0xFF64748B), borderRadius: BorderRadius.circular(3))),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(m, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                  Text('1軍で使っている選手 ${app.makerUsers(t, m)}人・契約金 年${app.makerFee(t, m)}万円', style: const TextStyle(fontSize: 12, color: _sub)),
                ]),
              ),
              f.makerDeals.contains(m)
                  ? OutlinedButton(
                      onPressed: () {
                        _toast(context, app.toggleMakerDeal(m), '$mとの契約を解除しました');
                        setState(() {});
                      },
                      child: const Text('解除'))
                  : FilledButton.tonal(
                      onPressed: f.makerDeals.length >= EquipOps.maxMakerDeals
                          ? null
                          : () {
                              _toast(context, app.toggleMakerDeal(m), '$mと契約しました');
                              setState(() {});
                            },
                      child: const Text('契約')),
            ]),
          ),
      ], note: '契約すると、契約金（そのメーカーを使う1軍の選手が多いほど高い）が毎月入ります。契約メーカーのバットで打撃タイトル、グラブで投手タイトル・ゴールデングラブを取ると、オフにコラボグッズを企画できます。選手の用具は「設定・編集 → チーム・選手編集」で変えられます。'),
    ]);
  }
}

/// キャンプでのコーチからの改造の提案（チーム → キャンプの上に出す）
class ProposalList extends StatelessWidget {
  final AppState app;
  final VoidCallback onChanged;
  const ProposalList({super.key, required this.app, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    if (app.campProposals.isEmpty) return const SizedBox.shrink();
    final byId = {for (final p in app.myTeam?.players ?? const []) p.id: p};
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      decoration: BoxDecoration(color: const Color(0xFFFFFBEB), border: Border.all(color: const Color(0xFFFCD34D)), borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('コーチからの改造の提案', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w900, color: _ink)),
        const SizedBox(height: 4),
        for (final c in List.of(app.campProposals))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('${c['date']}　${c['coach']}${byId[c['player']] == null ? '' : '　→ ${byId[c['player']]!.registeredName}'}', style: const TextStyle(fontSize: 11.5, color: _sub)),
              Text('${c['text']}', style: const TextStyle(fontSize: 13, height: 1.5)),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton(
                    onPressed: () {
                      app.answerProposal(c['id'] as String, false);
                      onChanged();
                    },
                    child: const Text('見送る')),
                FilledButton(
                    onPressed: () {
                      _toast(context, app.answerProposal(c['id'] as String, true), '改造しました');
                      onChanged();
                    },
                    child: const Text('改造する')),
              ]),
            ]),
          ),
      ]),
    );
  }
}
