import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

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

@DriftDatabase(tables: [KvEntries, TeamRows, MatchRows, SeasonRecords, PitchRows])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _open(1));

  /// プレイデータの枠（1〜3）ごとの保存。1 は以前からの保存そのもの
  AppDatabase.forSlot(int slot) : super(_open(slot));

  static QueryExecutor _open(int slot) => driftDatabase(
        name: slot <= 1 ? 'npb_pennant' : 'npb_pennant_s$slot',
        web: DriftWebOptions(
          sqlite3Wasm: Uri.parse('sqlite3.wasm'),
          driftWorker: Uri.parse('drift_worker.js'),
        ),
      );

  /// このプレイデータを消す（すべての表を空にする）
  Future<void> wipeAll() => transaction(() async {
        for (final t in allTables) {
          await delete(t).go();
        }
      });

  /// 保存があるか（球団のデータが1つでもあるか）
  Future<bool> hasData() async => (await (select(teamRows)..limit(1)).get()).isNotEmpty;

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) await m.createTable(pitchRows);
        },
      );

  Future<String?> getKv(String key) async {
    final r = await (select(kvEntries)..where((t) => t.key.equals(key))).getSingleOrNull();
    return r?.value;
  }

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

  /// 終わったシーズンを要約だけにする：1球ごとの記録を消し、試合の実況テキストを外す（スコア・ボックススコアは残す）
  Future<void> compactSeason(int season) => transaction(() async {
        await (delete(pitchRows)..where((t) => t.season.isSmallerOrEqualValue(season))).go();
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
