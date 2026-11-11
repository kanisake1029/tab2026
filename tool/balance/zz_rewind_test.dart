// ignore_for_file: avoid_print
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter/material.dart' show DateUtils;
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/db/app_database.dart';
import 'package:npb_pennant_app/providers/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 開発者版スロット1の写しを開幕日の試合前に戻す → backup/s25_opening.sqlite
void main() {
  test('rewind', () async {
    SharedPreferences.setMockInitialValues({});
    final out = File('backup/s25_opening.sqlite');
    if (out.existsSync()) out.deleteSync();
    await File('backup/s25_20261108.sqlite').copy(out.path);
    var db = AppDatabase(NativeDatabase(out));
    var a = AppState(db);
    while (!a.loaded) { await Future.delayed(const Duration(milliseconds: 20)); }
    final my = a.myTeam!;
    final f0 = {for (final t in a.leagueTeams) t.id: a.finOf(t).funds};
    final r1 = my.roster1G.toList();
    print(await a.rewindToOpening());
    print(await a.reconcileHistory());
    for (final e in a.draftBook[2025]!.where((e) => e['team'] == 'C0' || e['name'] == '小西 智' || e['name'] == '島川 恭介')) { print('指名 ${e['team']} ${e['label']} ${e['name']}'); }
    for (final l in a.transactions.where((l) => l.contains('小西') || l.contains('島川') || l.contains('ジョンソン') || l.contains('ストーン'))) { print('取引 $l'); }
    for (final n in ['小西 智', '島川 恭介', 'イバン・ジョンソン', 'カーティス・ストーン']) { for (final t in a.leagueTeams) { for (final p in t.players.where((p) => p.registeredName == n)) { print('選手 ${t.id} $n プロ${p.proYears}年 FA${p.faService} 「${p.draftInfo}」 ${p.moves}'); } } }
    print('資金の差 ${[for (final t in a.leagueTeams) '${t.id}:${a.finOf(t).funds - f0[t.id]!}'].join(' ')}');
    print('1軍 ${my.roster1G.length}人 変化なし=${r1.join() == my.roster1G.join()}');
    print('お知らせ ${a.news.take(8).join(' / ')}');
    print('取引 ${a.transactions.take(6).join(' / ')}');
    for (final p in my.players.where((p) => p.moves.isNotEmpty && p.moves.any((m) => m.startsWith('2026')))) { print('歩み ${p.registeredName} ${p.moves.where((m) => m.startsWith('2026')).join(' / ')}'); }
    for (final t in a.leagueTeams) { for (final p in t.players.where((p) => p.injuryDays > 0)) { print('怪我 ${t.name} ${p.registeredName} ${p.injuryName} 残${p.injuryDays}'); } }
    await Future.delayed(const Duration(seconds: 3));
    await db.close();
    // 読み込み直す
    SharedPreferences.setMockInitialValues({});
    final tmp = File('${Directory.systemTemp.path}/s25_open2.sqlite');
    await out.copy(tmp.path);
    db = AppDatabase(NativeDatabase(tmp));
    a = AppState(db);
    while (!a.loaded) { await Future.delayed(const Duration(milliseconds: 20)); }
    final played = a.matches.where((m) => m.homeScore != null && m.matchType != 'OPEN').length;
    print('読み込み直し：日付 ${a.currentDate} 終わった公式戦 $played 東新 ${a.myTeam!.wins}-${a.myTeam!.losses} 成績例 ${a.myTeam!.players.first.seasonStats.games}');
    final today = a.matches.where((m) => DateUtils.isSameDay(m.date, a.currentDate)).length;
    print('今日の試合 $today');
    a.playNextDay();
    final p2 = a.matches.where((m) => m.homeScore != null && m.matchType != 'OPEN').length;
    print('1日進めた：日付 ${a.currentDate} 終わった公式戦 $p2');
    await Future.delayed(const Duration(seconds: 2));
  }, timeout: const Timeout(Duration(minutes: 20)));
}
