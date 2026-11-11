import 'package:flutter/material.dart';
import '../engine/growth_engine.dart';
import '../models/team.dart';
import '../providers/app_state.dart';
import '../screens/awards_screen.dart';

/// シーズンが終わったときの年度更新のまとめ（順位・リーグの記録・自球団の成長と衰え）
Future<void> showSeasonReport(BuildContext context, AppState app, SeasonReport r) {
  final my = app.teams.where((t) => t.id == app.myTeamId).toList();
  final Team? myTeam = my.isEmpty ? null : my.first;
  final rank = myTeam == null ? null : r.ranks[myTeam.id];
  final mine = r.changes.where((c) => c.teamId == app.myTeamId && (myTeam?.players.contains(c.player) ?? false)).toList();
  final up = (mine.where((c) => c.ovrDiff > 0).toList()..sort((a, b) => b.ovrDiff.compareTo(a.ovrDiff))).take(8).toList();
  final down = (mine.where((c) => c.ovrDiff < 0).toList()..sort((a, b) => a.ovrDiff.compareTo(b.ovrDiff))).take(8).toList();
  final s = r.summary;
  final rec = myTeam == null ? <int>[0, 0, 0] : (r.records[myTeam.id] ?? <int>[0, 0, 0]);

  Widget row(GrowthChange c) {
    final top = (c.deltas.entries.toList()..sort((a, b) => b.value.abs().compareTo(a.value.abs()))).take(3);
    final detail = top.map((e) => '${e.key}${e.value > 0 ? '+' : ''}${e.value}').join('　');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        SizedBox(width: 108, child: Text(c.player.registeredName, style: const TextStyle(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis)),
        SizedBox(width: 62, child: Text('${c.ovrBefore}→${c.ovrAfter}', style: TextStyle(fontWeight: FontWeight.w900, color: c.ovrDiff > 0 ? const Color(0xFF15803D) : const Color(0xFFB91C1C)))),
        SizedBox(width: 50, child: Text(c.reverted ? '${c.phase.label}↺' : c.phase.label, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)))),
        Expanded(child: Text(detail, style: const TextStyle(fontSize: 12, color: Color(0xFF475569)), overflow: TextOverflow.ellipsis)),
      ]),
    );
  }

  Widget section(String title, List<GrowthChange> list) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(top: 12, bottom: 4), child: Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14))),
        if (list.isEmpty) const Text('いません', style: TextStyle(color: Color(0xFF64748B))) else ...list.map(row),
      ]);

  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (c) => AlertDialog(
      title: Text('${r.year}年シーズンが終わりました'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (app.champion != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('日本一：${app.champion!.name}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Color(0xFFB45309))),
              ),
            if (myTeam != null)
              Text('${myTeam.name}　${rec[0]}勝${rec[1]}敗${rec[2]}分　${myTeam.league == 'CL' ? 'Aリーグ' : 'Bリーグ'}${rank ?? '-'}位。この成績は年度別の記録として保存しました。',
                  style: const TextStyle(fontSize: 13, height: 1.5)),
            const SizedBox(height: 8),
            Text('リーグ全体：得点 ${(s['runsPerTeamGame'] as num).toStringAsFixed(2)}／試合　打率 ${(s['avg'] as num).toStringAsFixed(3)}　本塁打 ${(s['hrPerTeamGame'] as num).toStringAsFixed(2)}／試合',
                style: const TextStyle(fontSize: 12, color: Color(0xFF475569))),
            Text('1軍の平均能力：野手 ${(s['avgOvrBat'] as num).toStringAsFixed(1)}→${(s['avgOvrBatAfter'] as num).toStringAsFixed(1)}　投手 ${(s['avgOvrPit'] as num).toStringAsFixed(1)}→${(s['avgOvrPitAfter'] as num).toStringAsFixed(1)}',
                style: const TextStyle(fontSize: 12, color: Color(0xFF475569))),
            if (r.finance != null) ...[
              const SizedBox(height: 8),
              Text('経営：今季の収支 ${r.finance!.profit >= 0 ? '+' : ''}${(r.finance!.profit / 10000).toStringAsFixed(1)}億円　オーナー満足度 ${r.finance!.sat}',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: r.finance!.fired ? const Color(0xFFB91C1C) : const Color(0xFF0F172A))),
              for (final n in r.finance!.notes.skip(1).take(6)) Text('　$n', style: const TextStyle(fontSize: 11.5, color: Color(0xFF475569))),
              if (r.finance!.fired) const Text('オーナーから解任されました。ホームで次の行き先を選んでください', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Color(0xFFB91C1C))),
            ],
            section('成長した選手', up),
            section('衰えた選手', down),
            Padding(padding: const EdgeInsets.only(top: 12, bottom: 4), child: const Text('引退', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14))),
            Text(r.retired.isEmpty ? 'いません' : r.retired.join('、'), style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 10),
            Text('このあとはオフシーズンです：10/31 ドラフト会議 → 11月第2月曜 FA 宣言（12/31 まで交渉）→ 11月 秋季キャンプ → 12/1 契約更改・外国人選手の一覧 → 1/1 年度更新（全員が1つ歳をとり、${r.year + 1}年の日程ができる）→ 1月 春季キャンプ。'
                '戦力外通告・トレード・外国人の獲得は、フロントの「補強」からできます。', style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), height: 1.5)),
          ]),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(c).push(MaterialPageRoute(builder: (_) => AwardsScreen(appState: app, year: r.year))),
          child: const Text('表彰を見る'),
        ),
        FilledButton(onPressed: () => Navigator.pop(c), child: const Text('オフシーズンへ')),
      ],
    ),
  );
}
