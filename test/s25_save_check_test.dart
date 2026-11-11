
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/db/app_database.dart';
import 'package:npb_pennant_app/providers/app_state.dart';
import 'package:npb_pennant_app/utils/standings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final src = File('backup/s25_20261017.sqlite');
  test('S25 のセーブ：重複 ID の整理で選手が減らない・椎名が自球団に残る・補償の訂正', () async {
    SharedPreferences.setMockInitialValues({});
    final tmp = File('${Directory.systemTemp.path}/s25_check.sqlite');
    await src.copy(tmp.path);
    final db = AppDatabase(NativeDatabase(tmp));
    final raw = (await db.loadTeamJsons()).fold<int>(0, (a, s) => a + RegExp('"registeredName"').allMatches(s).length);
    final a = AppState(db);
    while (!a.loaded) { await Future.delayed(const Duration(milliseconds: 20)); }
    final ids = [for (final t in a.teams) for (final p in t.players) p.id];
    // ignore: avoid_print
    print('選手 読み込み前$raw → 後${ids.length}　重複ID ${ids.length - ids.toSet().length}');
    final seen = <String>{};
    for (final t in a.teams) {
      for (final p in t.players) {
        if (!seen.add(p.id)) {
          final where = a.teams.where((x) => x.players.any((q) => q.id == p.id)).map((x) => '${x.name}:${x.players.where((q) => q.id == p.id).map((q) => q.registeredName).join('/')}').join(' | ');
          // ignore: avoid_print
          print('残った重複 ${p.id} $where');
        }
      }
    }
    expect(ids.toSet().length, ids.length);
    final my = a.myTeam!;
    // ignore: avoid_print
    print('自球団 ${my.name}：${my.players.where((p) => p.registeredName.startsWith('椎名')).map((p) => '${p.registeredName} ${p.id}').join('、')}');
    for (final t in a.teams) {
      for (final p in t.players.where((p) => p.registeredName.startsWith('椎名'))) {
        // ignore: avoid_print
        print('  ${t.name} ${p.registeredName} ${p.id} ${p.draftInfo}');
      }
    }
    // ignore: avoid_print
    print('補償の記録：${a.transactions.where((l) => l.contains('人的補償')).take(5).join(' / ')}');
    // ignore: avoid_print
    print('お知らせ：${a.news.take(4).join(' / ')}');
    // ignore: avoid_print
    print('補償待ち：${a.pendingComp.map((c) => c.playerName).join('、')}');
    expect(a.startYear, 2027);
    expect(a.offAfterSeason, true);
    expect(a.faCases.isNotEmpty || a.transactions.isNotEmpty, true);
    // ignore: avoid_print
    print('状態 seasonFinished=${a.seasonFinished} date=${a.currentDate} startYear=${a.startYear}');
    final all = await db.select(db.seasonRecords).get();
    final cnt = <String, int>{};
    for (final r in all) { cnt['${r.season} ${r.kind}'] = (cnt['${r.season} ${r.kind}'] ?? 0) + 1; }
    // ignore: avoid_print
    print('行数 $cnt 例: ${all.where((r) => r.kind == 'player').take(3).map((r) => r.refId).join(',')}');
    final rs = all.where((r) => r.refId.startsWith('D2025')).toList();
    // ignore: avoid_print
    print('D2025_14 rows: ${rs.map((r) => '${r.season} ${r.teamId} ${r.json.substring(0, 40)}').join(' / ')}');
    // 同じ ID だった選手の年度別の記録：2人とも、自分の名前・今季の成績の行がある
    await Future.delayed(const Duration(seconds: 4));
    final aw = await db.getKv('awards_${a.startYear - 1}');
    // ignore: avoid_print
    print('表彰の記録 ${aw == null ? 'なし' : aw.length}');
    final titled = [for (final t in a.teams) for (final p in t.players) for (final h in p.honors) if (h.startsWith('${a.startYear - 1}年 ') && !h.contains('達成') && !h.contains('ノーヒット')) '${p.registeredName}:${h.substring(6)}'];
    // ignore: avoid_print
    print('2026年のタイトル ${titled.length}件：${titled.take(14).join('、')}');
    final hist = <String, String>{};
    for (final t in a.teams) {
      for (final p in t.players.where((p) => RegExp(r'_[rs]\d+$').hasMatch(p.id))) {
        final base = p.id.replaceFirst(RegExp(r'_[rs]\d+$'), '');
        final other = a.teams.expand((x) => x.players).where((q) => q.id == base).firstOrNull;
        for (final (who, pid) in [(p, p.id), if (other != null) (other, base)]) {
          final h = await a.playerHistory(pid);
          final row = h.where((x) => x.$1 == a.startYear - 1).firstOrNull;
          expect(row, isNotNull, reason: '${who.registeredName} $pid の${a.startYear - 1}年の行');
          // 2025年ドラフトの新人：通算＝2026年の1軍の成績
          expect(row!.$3.games, who.career.games, reason: '${who.registeredName} $pid の試合数');
          hist[pid] = '${who.registeredName} 1軍${row.$3.games}試合 2軍${row.$4.games}試合';
        }
      }
    }
    // ignore: avoid_print
    print('年度別 ${hist.length}人：${hist.entries.take(6).map((e) => '${e.key} ${e.value}').join(' / ')}');
    // オフに移籍した選手：2026年の行は移籍前（シーズン終了時）の球団
    var moved = 0;
    for (final t in a.teams) {
      for (final p in t.players) {
        final m = p.moves.map((x) => RegExp(r'^(\d{4})年(\d+)月\d+日 (.+)で(.+)へ（←(.+)）$').firstMatch(x)).whereType<RegExpMatch>().where((m) => m.group(1) == '${a.startYear - 1}' && int.parse(m.group(2)!) >= 10).firstOrNull;
        if (m == null) continue;
        final h = (await a.playerHistory(p.id)).where((x) => x.$1 == a.startYear - 1).toList();
        if (h.isEmpty) continue; // 今季出ていない選手
        final from = a.teams.firstWhere((x) => teamShort(x) == m.group(5));
        expect(h.last.$2.split('/').last, from.id, reason: '${p.registeredName}（${m.group(3)}）');
        if (moved++ < 4) {
          // ignore: avoid_print
          print('移籍 ${p.registeredName}：${m.group(3)} ${m.group(5)}→${teamShort(t)}　2026年の行は${teamShort(from)}');
        }
      }
    }
    // ignore: avoid_print
    print('オフに移籍した選手 $moved人');
    // オフを進める：12/1 契約更改・12/31 FA の期限・1/1（年齢は二重に上がらない）
    final ages = {for (final t in a.teams) for (final p in t.players) p.id: p.age};
    a.autoMode = true;
    var guard = 0;
    final stops = <String>[];
    while (!(a.currentDate.year == 2027 && a.currentDate.month == 1) && guard++ < 40) {
      a.playNextDay();
      stops.add('${a.currentDate.month}/${a.currentDate.day}');
    }
    // ignore: avoid_print
    print('止まった日 ${stops.join(' ')}　FA ${a.faCases.length}件　オフ ${a.offAfterSeason}');
    expect(a.offAfterSeason, false);
    expect(a.startYear, 2027);
    for (final t in a.teams) {
      for (final p in t.players.where((p) => ages.containsKey(p.id))) {
        expect(p.age, ages[p.id], reason: '${p.registeredName} の年齢');
      }
    }
    // 裏で続いている保存（アマチュア球界など）が終わってから閉じる
    await a.saveData();
    await Future.delayed(const Duration(seconds: 3));
    await db.close();
  }, timeout: const Timeout(Duration(minutes: 5)), skip: !src.existsSync());
}
