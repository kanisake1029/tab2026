import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

/// 設定など、小さな値（キー → 文字列）
class KvEntries extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  @override
  Set<Column> get primaryKey => {key};
}

/// チーム1つ＝1行（選手を含むJSON）
class TeamRows extends Table {
  TextColumn get id => text()();
  IntColumn get sort => integer()();
  TextColumn get json => text()();
  @override
  Set<Column> get primaryKey => {id};
}

/// ドラフト候補1人＝1行（スキーマ3から。以前は kv の 'prospects' に1,000人以上を1つのJSONで入れていた）
class ProspectRows extends Table {
  TextColumn get id => text()();
  IntColumn get sort => integer()();
  TextColumn get json => text()();
  @override
  Set<Column> get primaryKey => {id};
}

/// 試合1つ＝1行。シーズンごとに保存し、過去のシーズンも残す
class MatchRows extends Table {
  IntColumn get season => integer()();
  IntColumn get idx => integer()();
  BoolColumn get played => boolean().withDefault(const Constant(false))();
  TextColumn get json => text()();
  @override
  Set<Column> get primaryKey => {season, idx};
}

/// 終わったシーズンの成績（選手ごと・球団ごと）。通算成績やOBの記録のもと
class SeasonRecords extends Table {
  IntColumn get season => integer()();
  TextColumn get kind => text()(); // 'player' / 'team'
  TextColumn get refId => text()(); // 選手ID・球団ID
  TextColumn get teamId => text()();
  TextColumn get json => text()();
  @override
  Set<Column> get primaryKey => {season, kind, refId};
}

/// 1球ごとの記録（コース・球種・打球・守備など）。球団を絞って保存する
class PitchRows extends Table {
  IntColumn get season => integer()();
  IntColumn get matchIdx => integer()();
  IntColumn get seq => integer()(); // 試合の中での通し番号
  IntColumn get paIndex => integer()();
  IntColumn get pitchNo => integer()();
  BoolColumn get battingHome => boolean()();
  TextColumn get batter => text()();
  TextColumn get batterHand => text()();
  TextColumn get pitcher => text()();
  TextColumn get pitchName => text()();
  RealColumn get speed => real()();
  RealColumn get x => real()();
  RealColumn get z => real()();
  BoolColumn get inZone => boolean()();
  IntColumn get balls => integer()();
  IntColumn get strikes => integer()();
  TextColumn get result => text()();
  TextColumn get contact => text()();
  RealColumn get landX => real().nullable()();
  RealColumn get landY => real().nullable()();
  RealColumn get launch => real().nullable()();
  TextColumn get fielder => text()();
  TextColumn get outcome => text()();
  TextColumn get playCode => text()();
  RealColumn get breakDX => real()();
  RealColumn get breakDY => real()();
  @override
  Set<Column> get primaryKey => {season, matchIdx, seq};
}

/// 自動の控え1つ分（スロット画面の「控え」に出す）
class BackupInfo {
  final int slot;
  final int gen; // 0=いちばん新しい、1、2。-1=復元の直前の状態
  final String label;
  final String gameDate; // ゲーム内の日付
  final DateTime savedAt;
  final int bytes;
  final String summary; // スロットの要約（復元したときに書き戻す）
  const BackupInfo(this.slot, this.gen, this.label, this.gameDate, this.savedAt, this.bytes, this.summary);
}

@DriftDatabase(tables: [KvEntries, TeamRows, MatchRows, SeasonRecords, PitchRows, ProspectRows])
class AppDatabase extends _$AppDatabase {
  /// ファイルに保存しているか（テストなどで executor を渡したときは false。詰める処理・控えはファイルのときだけ行う）
  final bool fileBacked;
  final int slot;

  /// fileBacked は、テストでファイルのデータベースを渡すときだけ true にする
  AppDatabase([QueryExecutor? executor, bool? fileBacked])
      : fileBacked = fileBacked ?? (executor == null && !kIsWeb),
        slot = 1,
        super(executor ?? _open(1));

  /// プレイデータの枠（1〜3）ごとの保存。1 は以前からの保存そのもの
  AppDatabase.forSlot(this.slot)
      : fileBacked = !kIsWeb,
        super(_open(slot));

  /// テスト用：データベースと控えを置くフォルダ（null なら、アプリの書類フォルダ）
  static String? documentsPathOverride;
  static Future<String> _docsPath() async => documentsPathOverride ?? (await getApplicationDocumentsDirectory()).path;

  static String _name(int slot) => slot <= 1 ? 'npb_pennant' : 'npb_pennant_s$slot';

  static QueryExecutor _open(int slot) => driftDatabase(
        name: _name(slot),
        web: DriftWebOptions(
          sqlite3Wasm: Uri.parse('sqlite3.wasm'),
          driftWorker: Uri.parse('drift_worker.js'),
        ),
      );

  // ───────── ファイルの整理（空きページを詰める） ─────────

  /// 空きページが多いときだけ、ファイルを詰める（VACUUM）。詰めたら true。
  ///  年度替わりに前のシーズンの記録を消したあとや、起動時に呼ぶ。数秒かかることがある
  Future<bool> vacuumIfBloated({double ratio = 0.30, int minPages = 2000}) async {
    if (!fileBacked) return false;
    try {
      final pages = (await customSelect('PRAGMA page_count').getSingle()).data.values.first as int;
      final free = (await customSelect('PRAGMA freelist_count').getSingle()).data.values.first as int;
      if (pages < minPages || free / pages < ratio) return false;
      final sw = Stopwatch()..start();
      await customStatement('VACUUM');
      debugPrint('VACUUM: $pages → ${pages - free} ページ（${sw.elapsedMilliseconds}ms）');
      return true;
    } catch (e) {
      debugPrint('VACUUM ERROR: $e');
      return false;
    }
  }

  // ───────── 自動の控え（ドラフト・年度替わり・契約更改の直前） ─────────

  static const backupGenerations = 3;

  static Future<Directory> _backupDir() async {
    final d = Directory(p.join(await _docsPath(), 'backups'));
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static String _bakName(int slot, int gen) => 'slot${slot}_$gen';

  /// 今の保存を、詰めた形で控えに残す（古い控えは1つずつ繰り下げ、3世代まで）。失敗しても保存は続ける
  Future<bool> backupSlot({required String label, required String gameDate, String summary = ''}) async {
    if (!fileBacked) return false;
    try {
      final dir = await _backupDir();
      File f(int g, String ext) => File(p.join(dir.path, '${_bakName(slot, g)}.$ext'));
      for (var g = backupGenerations - 1; g >= 0; g--) {
        for (final ext in const ['sqlite', 'json']) {
          final src = f(g, ext);
          if (!await src.exists()) continue;
          if (g == backupGenerations - 1) {
            await src.delete();
          } else {
            await src.rename(f(g + 1, ext).path);
          }
        }
      }
      final dest = f(0, 'sqlite');
      await customStatement('VACUUM INTO ?', [dest.path]);
      await f(0, 'json').writeAsString(jsonEncode({'label': label, 'gameDate': gameDate, 'savedAt': DateTime.now().toIso8601String(), 'bytes': await dest.length(), 'summary': summary}));
      return true;
    } catch (e) {
      debugPrint('BACKUP ERROR: $e');
      return false;
    }
  }

  /// その枠の控えをすべて消す（プレイデータを消去したとき）
  static Future<void> deleteBackups(int slot) async {
    if (kIsWeb) return;
    try {
      final dir = await _backupDir();
      for (final f in dir.listSync().whereType<File>()) {
        if (p.basename(f.path).startsWith('slot${slot}_')) await f.delete();
      }
    } catch (e) {
      debugPrint('DELETE BACKUP ERROR: $e');
    }
  }

  /// その枠の控えの一覧（新しい順。復元の直前の状態があれば最後に）
  static Future<List<BackupInfo>> listBackups(int slot) async {
    if (kIsWeb) return const [];
    final out = <BackupInfo>[];
    try {
      final dir = await _backupDir();
      for (var g = 0; g < backupGenerations; g++) {
        final m = File(p.join(dir.path, '${_bakName(slot, g)}.json'));
        final s = File(p.join(dir.path, '${_bakName(slot, g)}.sqlite'));
        if (!await m.exists() || !await s.exists()) continue;
        final j = jsonDecode(await m.readAsString()) as Map<String, dynamic>;
        out.add(BackupInfo(slot, g, '${j['label'] ?? ''}', '${j['gameDate'] ?? ''}', DateTime.tryParse('${j['savedAt']}') ?? DateTime.now(), await s.length(), '${j['summary'] ?? ''}'));
      }
      final m = File(p.join(dir.path, 'slot${slot}_undo.json'));
      final s = File(p.join(dir.path, 'slot${slot}_undo.sqlite'));
      if (await m.exists() && await s.exists()) {
        final j = jsonDecode(await m.readAsString()) as Map<String, dynamic>;
        out.add(BackupInfo(slot, -1, '復元の直前の状態', '${j['gameDate'] ?? ''}', DateTime.tryParse('${j['savedAt']}') ?? DateTime.now(), await s.length(), '${j['summary'] ?? ''}'));
      }
    } catch (e) {
      debugPrint('LIST BACKUP ERROR: $e');
    }
    return out;
  }

  /// 控えに戻す。この枠のデータベースを開いていないときに呼ぶ（スロット画面から）。戻す前の状態は「復元の直前の状態」に残す
  static Future<bool> restoreBackup(BackupInfo b, {String currentSummary = '', String currentGameDate = ''}) async {
    if (kIsWeb) return false;
    try {
      final dir = await _backupDir();
      final live = File(p.join(await _docsPath(), '${_name(b.slot)}.sqlite'));
      final src = File(p.join(dir.path, b.gen < 0 ? 'slot${b.slot}_undo.sqlite' : '${_bakName(b.slot, b.gen)}.sqlite'));
      if (!await src.exists()) return false;
      final tmp = File('${live.path}.restore');
      await src.copy(tmp.path); // 先に別名へ。途中で失敗しても今のデータは変えない
      if (await live.exists()) {
        final undo = File(p.join(dir.path, 'slot${b.slot}_undo.sqlite'));
        if (b.gen >= 0) {
          await live.copy(undo.path);
          await File(p.join(dir.path, 'slot${b.slot}_undo.json')).writeAsString(jsonEncode({'gameDate': currentGameDate, 'savedAt': DateTime.now().toIso8601String(), 'summary': currentSummary}));
        }
        await live.delete();
      }
      for (final ext in const ['-journal', '-wal', '-shm']) {
        final extra = File('${live.path}$ext');
        if (await extra.exists()) await extra.delete();
      }
      await tmp.rename(live.path);
      return true;
    } catch (e) {
      debugPrint('RESTORE ERROR: $e');
      return false;
    }
  }

  /// このプレイデータを消す（すべての表を空にする）
  Future<void> wipeAll() => transaction(() async {
        for (final t in allTables) {
          await delete(t).go();
        }
      });

  /// 保存があるか（球団のデータが1つでもあるか）
  Future<bool> hasData() async => (await (select(teamRows)..limit(1)).get()).isNotEmpty;

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) await m.createTable(pitchRows);
          if (from < 3) await m.createTable(prospectRows);
        },
      );

  Future<String?> getKv(String key) async {
    final r = await (select(kvEntries)..where((t) => t.key.equals(key))).getSingleOrNull();
    return r?.value;
  }

  Future<void> deleteKv(String key) => (delete(kvEntries)..where((t) => t.key.equals(key))).go();

  /// 変わった候補だけ書き込み、無くなった候補は消す
  Future<void> syncProspects(List<ProspectRowsCompanion> changed, List<String> allIds) => transaction(() async {
        if (changed.isNotEmpty) await batch((b) => b.insertAllOnConflictUpdate(prospectRows, changed));
        if (allIds.isEmpty) {
          await delete(prospectRows).go();
        } else {
          await (delete(prospectRows)..where((t) => t.id.isNotIn(allIds))).go();
        }
      });

  Future<List<ProspectRow>> loadProspectRows() => (select(prospectRows)..orderBy([(t) => OrderingTerm.asc(t.sort)])).get();

  Future<void> setKv(String key, String value) =>
      into(kvEntries).insertOnConflictUpdate(KvEntriesCompanion.insert(key: key, value: value));

  Future<void> setKvBatch(Map<String, String> entries) async {
    if (entries.isEmpty) return;
    await batch((b) {
      b.insertAllOnConflictUpdate(kvEntries, [
        for (final e in entries.entries) KvEntriesCompanion.insert(key: e.key, value: e.value),
      ]);
    });
  }

  Future<Map<String, String>> allKv() async {
    final rows = await select(kvEntries).get();
    return {for (final r in rows) r.key: r.value};
  }

  /// チームを丸ごと入れ替える
  Future<void> saveTeams(List<MapEntry<String, String>> idJson) => transaction(() async {
        await delete(teamRows).go();
        await batch((b) {
          b.insertAll(teamRows, [
            for (var i = 0; i < idJson.length; i++) TeamRowsCompanion.insert(id: idJson[i].key, sort: i, json: idJson[i].value),
          ]);
        });
      });

  /// 変わったチームだけ書き込み、無くなったチームは消す
  Future<void> syncTeams(List<TeamRowsCompanion> changed, List<String> allIds) => transaction(() async {
        if (changed.isNotEmpty) await batch((b) => b.insertAllOnConflictUpdate(teamRows, changed));
        await (delete(teamRows)..where((t) => t.id.isNotIn(allIds))).go();
      });

  Future<List<String>> loadTeamJsons() async {
    final rows = await (select(teamRows)..orderBy([(t) => OrderingTerm.asc(t.sort)])).get();
    return rows.map((r) => r.json).toList();
  }

  /// そのシーズンの全試合を入れ替える（日程を作り直したとき）
  Future<void> replaceMatches(int season, Map<int, String> jsons, Map<int, bool> played) => transaction(() async {
        await (delete(matchRows)..where((t) => t.season.equals(season))).go();
        await batch((b) {
          b.insertAll(matchRows, [
            for (final e in jsons.entries) MatchRowsCompanion.insert(season: season, idx: e.key, played: Value(played[e.key] ?? false), json: e.value),
          ]);
        });
      });

  /// 結果が付いた試合だけ上書きする
  Future<void> upsertMatches(int season, Map<int, String> idxJson, Map<int, bool> played) => transaction(() async {
        await batch((b) {
          b.insertAllOnConflictUpdate(matchRows, [
            for (final e in idxJson.entries) MatchRowsCompanion.insert(season: season, idx: e.key, played: Value(played[e.key] ?? true), json: e.value),
          ]);
        });
      });

  Future<List<MatchRow>> loadMatchRows(int season) => (select(matchRows)
        ..where((t) => t.season.equals(season))
        ..orderBy([(t) => OrderingTerm.asc(t.idx)]))
      .get();

  Future<void> savePitches(List<PitchRowsCompanion> rows) => transaction(() async {
        await batch((b) => b.insertAllOnConflictUpdate(pitchRows, rows));
      });

  /// シーズンの1球ごとの記録をすべて（対戦成績の集計に使う）
  Future<List<PitchRow>> loadSeasonPitches(int season) => (select(pitchRows)..where((t) => t.season.equals(season))).get();

  Future<List<PitchRow>> loadPitches(int season, int matchIdx) => (select(pitchRows)
        ..where((t) => t.season.equals(season) & t.matchIdx.equals(matchIdx))
        ..orderBy([(t) => OrderingTerm.asc(t.seq)]))
      .get();

  /// 終わったシーズンを要約だけにする：試合の実況テキストを外す（スコア・ボックススコアは残す）。
  ///  1球ごとの記録は keepPitchSeasons シーズンぶん（終わったシーズンを含む）残し、それより古いものを消す
  Future<void> compactSeason(int season, {int keepPitchSeasons = 2}) => transaction(() async {
        await (delete(pitchRows)..where((t) => t.season.isSmallerOrEqualValue(season - keepPitchSeasons))).go();
        final rows = await (select(matchRows)..where((t) => t.season.isSmallerOrEqualValue(season))).get();
        await batch((b) {
          for (final r in rows) {
            if (!r.json.contains('"playByPlay":[') && !r.json.contains('"pitchByPitch":[')) continue;
            final m = jsonDecode(r.json) as Map<String, dynamic>;
            m['playByPlay'] = null;
            m['pitchByPitch'] = null;
            b.update(matchRows, MatchRowsCompanion(json: Value(jsonEncode(m))), where: (t) => t.season.equals(r.season) & t.idx.equals(r.idx));
          }
        });
      });

  /// はじめから：これまでの年度の記録・試合・1球ごとの記録と、年度ごとの表彰・順位などを消す（設定・球団は残す）
  Future<void> wipeHistory() => transaction(() async {
        await delete(seasonRecords).go();
        await delete(pitchRows).go();
        await delete(matchRows).go();
        for (final p in const ['awards_', 'summary_', 'standings_', 'monthlyMvp_', 'chron_', 'news_']) {
          await (delete(kvEntries)..where((t) => t.key.like('$p%'))).go();
        }
      });

  /// 記録を何行か書き換える（同じ年度・種類・ID の行は置き換え）
  Future<void> upsertRecords(List<SeasonRecordsCompanion> rows) => batch((b) => b.insertAllOnConflictUpdate(seasonRecords, rows));

  Future<void> saveRecords(int season, List<SeasonRecordsCompanion> rows) => transaction(() async {
        await (delete(seasonRecords)..where((t) => t.season.equals(season))).go();
        await batch((b) => b.insertAllOnConflictUpdate(seasonRecords, rows)); // 同じ ID が2行あっても全体が失敗しないように
      });
}
