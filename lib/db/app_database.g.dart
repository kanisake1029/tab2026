// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $KvEntriesTable extends KvEntries
    with TableInfo<$KvEntriesTable, KvEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $KvEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'kv_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<KvEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  KvEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return KvEntry(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $KvEntriesTable createAlias(String alias) {
    return $KvEntriesTable(attachedDatabase, alias);
  }
}

class KvEntry extends DataClass implements Insertable<KvEntry> {
  final String key;
  final String value;
  const KvEntry({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  KvEntriesCompanion toCompanion(bool nullToAbsent) {
    return KvEntriesCompanion(key: Value(key), value: Value(value));
  }

  factory KvEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return KvEntry(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  KvEntry copyWith({String? key, String? value}) =>
      KvEntry(key: key ?? this.key, value: value ?? this.value);
  KvEntry copyWithCompanion(KvEntriesCompanion data) {
    return KvEntry(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('KvEntry(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is KvEntry && other.key == this.key && other.value == this.value);
}

class KvEntriesCompanion extends UpdateCompanion<KvEntry> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const KvEntriesCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  KvEntriesCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<KvEntry> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  KvEntriesCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return KvEntriesCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('KvEntriesCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TeamRowsTable extends TeamRows with TableInfo<$TeamRowsTable, TeamRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TeamRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sortMeta = const VerificationMeta('sort');
  @override
  late final GeneratedColumn<int> sort = GeneratedColumn<int>(
    'sort',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _jsonMeta = const VerificationMeta('json');
  @override
  late final GeneratedColumn<String> json = GeneratedColumn<String>(
    'json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, sort, json];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'team_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<TeamRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('sort')) {
      context.handle(
        _sortMeta,
        sort.isAcceptableOrUnknown(data['sort']!, _sortMeta),
      );
    } else if (isInserting) {
      context.missing(_sortMeta);
    }
    if (data.containsKey('json')) {
      context.handle(
        _jsonMeta,
        json.isAcceptableOrUnknown(data['json']!, _jsonMeta),
      );
    } else if (isInserting) {
      context.missing(_jsonMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TeamRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TeamRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      sort: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort'],
      )!,
      json: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}json'],
      )!,
    );
  }

  @override
  $TeamRowsTable createAlias(String alias) {
    return $TeamRowsTable(attachedDatabase, alias);
  }
}

class TeamRow extends DataClass implements Insertable<TeamRow> {
  final String id;
  final int sort;
  final String json;
  const TeamRow({required this.id, required this.sort, required this.json});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['sort'] = Variable<int>(sort);
    map['json'] = Variable<String>(json);
    return map;
  }

  TeamRowsCompanion toCompanion(bool nullToAbsent) {
    return TeamRowsCompanion(
      id: Value(id),
      sort: Value(sort),
      json: Value(json),
    );
  }

  factory TeamRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TeamRow(
      id: serializer.fromJson<String>(json['id']),
      sort: serializer.fromJson<int>(json['sort']),
      json: serializer.fromJson<String>(json['json']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'sort': serializer.toJson<int>(sort),
      'json': serializer.toJson<String>(json),
    };
  }

  TeamRow copyWith({String? id, int? sort, String? json}) => TeamRow(
    id: id ?? this.id,
    sort: sort ?? this.sort,
    json: json ?? this.json,
  );
  TeamRow copyWithCompanion(TeamRowsCompanion data) {
    return TeamRow(
      id: data.id.present ? data.id.value : this.id,
      sort: data.sort.present ? data.sort.value : this.sort,
      json: data.json.present ? data.json.value : this.json,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TeamRow(')
          ..write('id: $id, ')
          ..write('sort: $sort, ')
          ..write('json: $json')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, sort, json);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TeamRow &&
          other.id == this.id &&
          other.sort == this.sort &&
          other.json == this.json);
}

class TeamRowsCompanion extends UpdateCompanion<TeamRow> {
  final Value<String> id;
  final Value<int> sort;
  final Value<String> json;
  final Value<int> rowid;
  const TeamRowsCompanion({
    this.id = const Value.absent(),
    this.sort = const Value.absent(),
    this.json = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TeamRowsCompanion.insert({
    required String id,
    required int sort,
    required String json,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       sort = Value(sort),
       json = Value(json);
  static Insertable<TeamRow> custom({
    Expression<String>? id,
    Expression<int>? sort,
    Expression<String>? json,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sort != null) 'sort': sort,
      if (json != null) 'json': json,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TeamRowsCompanion copyWith({
    Value<String>? id,
    Value<int>? sort,
    Value<String>? json,
    Value<int>? rowid,
  }) {
    return TeamRowsCompanion(
      id: id ?? this.id,
      sort: sort ?? this.sort,
      json: json ?? this.json,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (sort.present) {
      map['sort'] = Variable<int>(sort.value);
    }
    if (json.present) {
      map['json'] = Variable<String>(json.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TeamRowsCompanion(')
          ..write('id: $id, ')
          ..write('sort: $sort, ')
          ..write('json: $json, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MatchRowsTable extends MatchRows
    with TableInfo<$MatchRowsTable, MatchRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MatchRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _seasonMeta = const VerificationMeta('season');
  @override
  late final GeneratedColumn<int> season = GeneratedColumn<int>(
    'season',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idxMeta = const VerificationMeta('idx');
  @override
  late final GeneratedColumn<int> idx = GeneratedColumn<int>(
    'idx',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _playedMeta = const VerificationMeta('played');
  @override
  late final GeneratedColumn<bool> played = GeneratedColumn<bool>(
    'played',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("played" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _jsonMeta = const VerificationMeta('json');
  @override
  late final GeneratedColumn<String> json = GeneratedColumn<String>(
    'json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [season, idx, played, json];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'match_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<MatchRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('season')) {
      context.handle(
        _seasonMeta,
        season.isAcceptableOrUnknown(data['season']!, _seasonMeta),
      );
    } else if (isInserting) {
      context.missing(_seasonMeta);
    }
    if (data.containsKey('idx')) {
      context.handle(
        _idxMeta,
        idx.isAcceptableOrUnknown(data['idx']!, _idxMeta),
      );
    } else if (isInserting) {
      context.missing(_idxMeta);
    }
    if (data.containsKey('played')) {
      context.handle(
        _playedMeta,
        played.isAcceptableOrUnknown(data['played']!, _playedMeta),
      );
    }
    if (data.containsKey('json')) {
      context.handle(
        _jsonMeta,
        json.isAcceptableOrUnknown(data['json']!, _jsonMeta),
      );
    } else if (isInserting) {
      context.missing(_jsonMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {season, idx};
  @override
  MatchRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MatchRow(
      season: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}season'],
      )!,
      idx: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}idx'],
      )!,
      played: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}played'],
      )!,
      json: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}json'],
      )!,
    );
  }

  @override
  $MatchRowsTable createAlias(String alias) {
    return $MatchRowsTable(attachedDatabase, alias);
  }
}

class MatchRow extends DataClass implements Insertable<MatchRow> {
  final int season;
  final int idx;
  final bool played;
  final String json;
  const MatchRow({
    required this.season,
    required this.idx,
    required this.played,
    required this.json,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['season'] = Variable<int>(season);
    map['idx'] = Variable<int>(idx);
    map['played'] = Variable<bool>(played);
    map['json'] = Variable<String>(json);
    return map;
  }

  MatchRowsCompanion toCompanion(bool nullToAbsent) {
    return MatchRowsCompanion(
      season: Value(season),
      idx: Value(idx),
      played: Value(played),
      json: Value(json),
    );
  }

  factory MatchRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MatchRow(
      season: serializer.fromJson<int>(json['season']),
      idx: serializer.fromJson<int>(json['idx']),
      played: serializer.fromJson<bool>(json['played']),
      json: serializer.fromJson<String>(json['json']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'season': serializer.toJson<int>(season),
      'idx': serializer.toJson<int>(idx),
      'played': serializer.toJson<bool>(played),
      'json': serializer.toJson<String>(json),
    };
  }

  MatchRow copyWith({int? season, int? idx, bool? played, String? json}) =>
      MatchRow(
        season: season ?? this.season,
        idx: idx ?? this.idx,
        played: played ?? this.played,
        json: json ?? this.json,
      );
  MatchRow copyWithCompanion(MatchRowsCompanion data) {
    return MatchRow(
      season: data.season.present ? data.season.value : this.season,
      idx: data.idx.present ? data.idx.value : this.idx,
      played: data.played.present ? data.played.value : this.played,
      json: data.json.present ? data.json.value : this.json,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MatchRow(')
          ..write('season: $season, ')
          ..write('idx: $idx, ')
          ..write('played: $played, ')
          ..write('json: $json')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(season, idx, played, json);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MatchRow &&
          other.season == this.season &&
          other.idx == this.idx &&
          other.played == this.played &&
          other.json == this.json);
}

class MatchRowsCompanion extends UpdateCompanion<MatchRow> {
  final Value<int> season;
  final Value<int> idx;
  final Value<bool> played;
  final Value<String> json;
  final Value<int> rowid;
  const MatchRowsCompanion({
    this.season = const Value.absent(),
    this.idx = const Value.absent(),
    this.played = const Value.absent(),
    this.json = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MatchRowsCompanion.insert({
    required int season,
    required int idx,
    this.played = const Value.absent(),
    required String json,
    this.rowid = const Value.absent(),
  }) : season = Value(season),
       idx = Value(idx),
       json = Value(json);
  static Insertable<MatchRow> custom({
    Expression<int>? season,
    Expression<int>? idx,
    Expression<bool>? played,
    Expression<String>? json,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (season != null) 'season': season,
      if (idx != null) 'idx': idx,
      if (played != null) 'played': played,
      if (json != null) 'json': json,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MatchRowsCompanion copyWith({
    Value<int>? season,
    Value<int>? idx,
    Value<bool>? played,
    Value<String>? json,
    Value<int>? rowid,
  }) {
    return MatchRowsCompanion(
      season: season ?? this.season,
      idx: idx ?? this.idx,
      played: played ?? this.played,
      json: json ?? this.json,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (season.present) {
      map['season'] = Variable<int>(season.value);
    }
    if (idx.present) {
      map['idx'] = Variable<int>(idx.value);
    }
    if (played.present) {
      map['played'] = Variable<bool>(played.value);
    }
    if (json.present) {
      map['json'] = Variable<String>(json.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MatchRowsCompanion(')
          ..write('season: $season, ')
          ..write('idx: $idx, ')
          ..write('played: $played, ')
          ..write('json: $json, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SeasonRecordsTable extends SeasonRecords
    with TableInfo<$SeasonRecordsTable, SeasonRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SeasonRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _seasonMeta = const VerificationMeta('season');
  @override
  late final GeneratedColumn<int> season = GeneratedColumn<int>(
    'season',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _refIdMeta = const VerificationMeta('refId');
  @override
  late final GeneratedColumn<String> refId = GeneratedColumn<String>(
    'ref_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _teamIdMeta = const VerificationMeta('teamId');
  @override
  late final GeneratedColumn<String> teamId = GeneratedColumn<String>(
    'team_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _jsonMeta = const VerificationMeta('json');
  @override
  late final GeneratedColumn<String> json = GeneratedColumn<String>(
    'json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [season, kind, refId, teamId, json];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'season_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<SeasonRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('season')) {
      context.handle(
        _seasonMeta,
        season.isAcceptableOrUnknown(data['season']!, _seasonMeta),
      );
    } else if (isInserting) {
      context.missing(_seasonMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('ref_id')) {
      context.handle(
        _refIdMeta,
        refId.isAcceptableOrUnknown(data['ref_id']!, _refIdMeta),
      );
    } else if (isInserting) {
      context.missing(_refIdMeta);
    }
    if (data.containsKey('team_id')) {
      context.handle(
        _teamIdMeta,
        teamId.isAcceptableOrUnknown(data['team_id']!, _teamIdMeta),
      );
    } else if (isInserting) {
      context.missing(_teamIdMeta);
    }
    if (data.containsKey('json')) {
      context.handle(
        _jsonMeta,
        json.isAcceptableOrUnknown(data['json']!, _jsonMeta),
      );
    } else if (isInserting) {
      context.missing(_jsonMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {season, kind, refId};
  @override
  SeasonRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SeasonRecord(
      season: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}season'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      refId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ref_id'],
      )!,
      teamId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}team_id'],
      )!,
      json: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}json'],
      )!,
    );
  }

  @override
  $SeasonRecordsTable createAlias(String alias) {
    return $SeasonRecordsTable(attachedDatabase, alias);
  }
}

class SeasonRecord extends DataClass implements Insertable<SeasonRecord> {
  final int season;
  final String kind;
  final String refId;
  final String teamId;
  final String json;
  const SeasonRecord({
    required this.season,
    required this.kind,
    required this.refId,
    required this.teamId,
    required this.json,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['season'] = Variable<int>(season);
    map['kind'] = Variable<String>(kind);
    map['ref_id'] = Variable<String>(refId);
    map['team_id'] = Variable<String>(teamId);
    map['json'] = Variable<String>(json);
    return map;
  }

  SeasonRecordsCompanion toCompanion(bool nullToAbsent) {
    return SeasonRecordsCompanion(
      season: Value(season),
      kind: Value(kind),
      refId: Value(refId),
      teamId: Value(teamId),
      json: Value(json),
    );
  }

  factory SeasonRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SeasonRecord(
      season: serializer.fromJson<int>(json['season']),
      kind: serializer.fromJson<String>(json['kind']),
      refId: serializer.fromJson<String>(json['refId']),
      teamId: serializer.fromJson<String>(json['teamId']),
      json: serializer.fromJson<String>(json['json']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'season': serializer.toJson<int>(season),
      'kind': serializer.toJson<String>(kind),
      'refId': serializer.toJson<String>(refId),
      'teamId': serializer.toJson<String>(teamId),
      'json': serializer.toJson<String>(json),
    };
  }

  SeasonRecord copyWith({
    int? season,
    String? kind,
    String? refId,
    String? teamId,
    String? json,
  }) => SeasonRecord(
    season: season ?? this.season,
    kind: kind ?? this.kind,
    refId: refId ?? this.refId,
    teamId: teamId ?? this.teamId,
    json: json ?? this.json,
  );
  SeasonRecord copyWithCompanion(SeasonRecordsCompanion data) {
    return SeasonRecord(
      season: data.season.present ? data.season.value : this.season,
      kind: data.kind.present ? data.kind.value : this.kind,
      refId: data.refId.present ? data.refId.value : this.refId,
      teamId: data.teamId.present ? data.teamId.value : this.teamId,
      json: data.json.present ? data.json.value : this.json,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SeasonRecord(')
          ..write('season: $season, ')
          ..write('kind: $kind, ')
          ..write('refId: $refId, ')
          ..write('teamId: $teamId, ')
          ..write('json: $json')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(season, kind, refId, teamId, json);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SeasonRecord &&
          other.season == this.season &&
          other.kind == this.kind &&
          other.refId == this.refId &&
          other.teamId == this.teamId &&
          other.json == this.json);
}

class SeasonRecordsCompanion extends UpdateCompanion<SeasonRecord> {
  final Value<int> season;
  final Value<String> kind;
  final Value<String> refId;
  final Value<String> teamId;
  final Value<String> json;
  final Value<int> rowid;
  const SeasonRecordsCompanion({
    this.season = const Value.absent(),
    this.kind = const Value.absent(),
    this.refId = const Value.absent(),
    this.teamId = const Value.absent(),
    this.json = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SeasonRecordsCompanion.insert({
    required int season,
    required String kind,
    required String refId,
    required String teamId,
    required String json,
    this.rowid = const Value.absent(),
  }) : season = Value(season),
       kind = Value(kind),
       refId = Value(refId),
       teamId = Value(teamId),
       json = Value(json);
  static Insertable<SeasonRecord> custom({
    Expression<int>? season,
    Expression<String>? kind,
    Expression<String>? refId,
    Expression<String>? teamId,
    Expression<String>? json,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (season != null) 'season': season,
      if (kind != null) 'kind': kind,
      if (refId != null) 'ref_id': refId,
      if (teamId != null) 'team_id': teamId,
      if (json != null) 'json': json,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SeasonRecordsCompanion copyWith({
    Value<int>? season,
    Value<String>? kind,
    Value<String>? refId,
    Value<String>? teamId,
    Value<String>? json,
    Value<int>? rowid,
  }) {
    return SeasonRecordsCompanion(
      season: season ?? this.season,
      kind: kind ?? this.kind,
      refId: refId ?? this.refId,
      teamId: teamId ?? this.teamId,
      json: json ?? this.json,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (season.present) {
      map['season'] = Variable<int>(season.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (refId.present) {
      map['ref_id'] = Variable<String>(refId.value);
    }
    if (teamId.present) {
      map['team_id'] = Variable<String>(teamId.value);
    }
    if (json.present) {
      map['json'] = Variable<String>(json.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SeasonRecordsCompanion(')
          ..write('season: $season, ')
          ..write('kind: $kind, ')
          ..write('refId: $refId, ')
          ..write('teamId: $teamId, ')
          ..write('json: $json, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PitchRowsTable extends PitchRows
    with TableInfo<$PitchRowsTable, PitchRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PitchRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _seasonMeta = const VerificationMeta('season');
  @override
  late final GeneratedColumn<int> season = GeneratedColumn<int>(
    'season',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _matchIdxMeta = const VerificationMeta(
    'matchIdx',
  );
  @override
  late final GeneratedColumn<int> matchIdx = GeneratedColumn<int>(
    'match_idx',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _seqMeta = const VerificationMeta('seq');
  @override
  late final GeneratedColumn<int> seq = GeneratedColumn<int>(
    'seq',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _paIndexMeta = const VerificationMeta(
    'paIndex',
  );
  @override
  late final GeneratedColumn<int> paIndex = GeneratedColumn<int>(
    'pa_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pitchNoMeta = const VerificationMeta(
    'pitchNo',
  );
  @override
  late final GeneratedColumn<int> pitchNo = GeneratedColumn<int>(
    'pitch_no',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _battingHomeMeta = const VerificationMeta(
    'battingHome',
  );
  @override
  late final GeneratedColumn<bool> battingHome = GeneratedColumn<bool>(
    'batting_home',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("batting_home" IN (0, 1))',
    ),
  );
  static const VerificationMeta _batterMeta = const VerificationMeta('batter');
  @override
  late final GeneratedColumn<String> batter = GeneratedColumn<String>(
    'batter',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _batterHandMeta = const VerificationMeta(
    'batterHand',
  );
  @override
  late final GeneratedColumn<String> batterHand = GeneratedColumn<String>(
    'batter_hand',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pitcherMeta = const VerificationMeta(
    'pitcher',
  );
  @override
  late final GeneratedColumn<String> pitcher = GeneratedColumn<String>(
    'pitcher',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pitchNameMeta = const VerificationMeta(
    'pitchName',
  );
  @override
  late final GeneratedColumn<String> pitchName = GeneratedColumn<String>(
    'pitch_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _speedMeta = const VerificationMeta('speed');
  @override
  late final GeneratedColumn<double> speed = GeneratedColumn<double>(
    'speed',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _xMeta = const VerificationMeta('x');
  @override
  late final GeneratedColumn<double> x = GeneratedColumn<double>(
    'x',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _zMeta = const VerificationMeta('z');
  @override
  late final GeneratedColumn<double> z = GeneratedColumn<double>(
    'z',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _inZoneMeta = const VerificationMeta('inZone');
  @override
  late final GeneratedColumn<bool> inZone = GeneratedColumn<bool>(
    'in_zone',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("in_zone" IN (0, 1))',
    ),
  );
  static const VerificationMeta _ballsMeta = const VerificationMeta('balls');
  @override
  late final GeneratedColumn<int> balls = GeneratedColumn<int>(
    'balls',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _strikesMeta = const VerificationMeta(
    'strikes',
  );
  @override
  late final GeneratedColumn<int> strikes = GeneratedColumn<int>(
    'strikes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _resultMeta = const VerificationMeta('result');
  @override
  late final GeneratedColumn<String> result = GeneratedColumn<String>(
    'result',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contactMeta = const VerificationMeta(
    'contact',
  );
  @override
  late final GeneratedColumn<String> contact = GeneratedColumn<String>(
    'contact',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _landXMeta = const VerificationMeta('landX');
  @override
  late final GeneratedColumn<double> landX = GeneratedColumn<double>(
    'land_x',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _landYMeta = const VerificationMeta('landY');
  @override
  late final GeneratedColumn<double> landY = GeneratedColumn<double>(
    'land_y',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _launchMeta = const VerificationMeta('launch');
  @override
  late final GeneratedColumn<double> launch = GeneratedColumn<double>(
    'launch',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _fielderMeta = const VerificationMeta(
    'fielder',
  );
  @override
  late final GeneratedColumn<String> fielder = GeneratedColumn<String>(
    'fielder',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _outcomeMeta = const VerificationMeta(
    'outcome',
  );
  @override
  late final GeneratedColumn<String> outcome = GeneratedColumn<String>(
    'outcome',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _playCodeMeta = const VerificationMeta(
    'playCode',
  );
  @override
  late final GeneratedColumn<String> playCode = GeneratedColumn<String>(
    'play_code',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _breakDXMeta = const VerificationMeta(
    'breakDX',
  );
  @override
  late final GeneratedColumn<double> breakDX = GeneratedColumn<double>(
    'break_d_x',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _breakDYMeta = const VerificationMeta(
    'breakDY',
  );
  @override
  late final GeneratedColumn<double> breakDY = GeneratedColumn<double>(
    'break_d_y',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    season,
    matchIdx,
    seq,
    paIndex,
    pitchNo,
    battingHome,
    batter,
    batterHand,
    pitcher,
    pitchName,
    speed,
    x,
    z,
    inZone,
    balls,
    strikes,
    result,
    contact,
    landX,
    landY,
    launch,
    fielder,
    outcome,
    playCode,
    breakDX,
    breakDY,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pitch_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<PitchRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('season')) {
      context.handle(
        _seasonMeta,
        season.isAcceptableOrUnknown(data['season']!, _seasonMeta),
      );
    } else if (isInserting) {
      context.missing(_seasonMeta);
    }
    if (data.containsKey('match_idx')) {
      context.handle(
        _matchIdxMeta,
        matchIdx.isAcceptableOrUnknown(data['match_idx']!, _matchIdxMeta),
      );
    } else if (isInserting) {
      context.missing(_matchIdxMeta);
    }
    if (data.containsKey('seq')) {
      context.handle(
        _seqMeta,
        seq.isAcceptableOrUnknown(data['seq']!, _seqMeta),
      );
    } else if (isInserting) {
      context.missing(_seqMeta);
    }
    if (data.containsKey('pa_index')) {
      context.handle(
        _paIndexMeta,
        paIndex.isAcceptableOrUnknown(data['pa_index']!, _paIndexMeta),
      );
    } else if (isInserting) {
      context.missing(_paIndexMeta);
    }
    if (data.containsKey('pitch_no')) {
      context.handle(
        _pitchNoMeta,
        pitchNo.isAcceptableOrUnknown(data['pitch_no']!, _pitchNoMeta),
      );
    } else if (isInserting) {
      context.missing(_pitchNoMeta);
    }
    if (data.containsKey('batting_home')) {
      context.handle(
        _battingHomeMeta,
        battingHome.isAcceptableOrUnknown(
          data['batting_home']!,
          _battingHomeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_battingHomeMeta);
    }
    if (data.containsKey('batter')) {
      context.handle(
        _batterMeta,
        batter.isAcceptableOrUnknown(data['batter']!, _batterMeta),
      );
    } else if (isInserting) {
      context.missing(_batterMeta);
    }
    if (data.containsKey('batter_hand')) {
      context.handle(
        _batterHandMeta,
        batterHand.isAcceptableOrUnknown(data['batter_hand']!, _batterHandMeta),
      );
    } else if (isInserting) {
      context.missing(_batterHandMeta);
    }
    if (data.containsKey('pitcher')) {
      context.handle(
        _pitcherMeta,
        pitcher.isAcceptableOrUnknown(data['pitcher']!, _pitcherMeta),
      );
    } else if (isInserting) {
      context.missing(_pitcherMeta);
    }
    if (data.containsKey('pitch_name')) {
      context.handle(
        _pitchNameMeta,
        pitchName.isAcceptableOrUnknown(data['pitch_name']!, _pitchNameMeta),
      );
    } else if (isInserting) {
      context.missing(_pitchNameMeta);
    }
    if (data.containsKey('speed')) {
      context.handle(
        _speedMeta,
        speed.isAcceptableOrUnknown(data['speed']!, _speedMeta),
      );
    } else if (isInserting) {
      context.missing(_speedMeta);
    }
    if (data.containsKey('x')) {
      context.handle(_xMeta, x.isAcceptableOrUnknown(data['x']!, _xMeta));
    } else if (isInserting) {
      context.missing(_xMeta);
    }
    if (data.containsKey('z')) {
      context.handle(_zMeta, z.isAcceptableOrUnknown(data['z']!, _zMeta));
    } else if (isInserting) {
      context.missing(_zMeta);
    }
    if (data.containsKey('in_zone')) {
      context.handle(
        _inZoneMeta,
        inZone.isAcceptableOrUnknown(data['in_zone']!, _inZoneMeta),
      );
    } else if (isInserting) {
      context.missing(_inZoneMeta);
    }
    if (data.containsKey('balls')) {
      context.handle(
        _ballsMeta,
        balls.isAcceptableOrUnknown(data['balls']!, _ballsMeta),
      );
    } else if (isInserting) {
      context.missing(_ballsMeta);
    }
    if (data.containsKey('strikes')) {
      context.handle(
        _strikesMeta,
        strikes.isAcceptableOrUnknown(data['strikes']!, _strikesMeta),
      );
    } else if (isInserting) {
      context.missing(_strikesMeta);
    }
    if (data.containsKey('result')) {
      context.handle(
        _resultMeta,
        result.isAcceptableOrUnknown(data['result']!, _resultMeta),
      );
    } else if (isInserting) {
      context.missing(_resultMeta);
    }
    if (data.containsKey('contact')) {
      context.handle(
        _contactMeta,
        contact.isAcceptableOrUnknown(data['contact']!, _contactMeta),
      );
    } else if (isInserting) {
      context.missing(_contactMeta);
    }
    if (data.containsKey('land_x')) {
      context.handle(
        _landXMeta,
        landX.isAcceptableOrUnknown(data['land_x']!, _landXMeta),
      );
    }
    if (data.containsKey('land_y')) {
      context.handle(
        _landYMeta,
        landY.isAcceptableOrUnknown(data['land_y']!, _landYMeta),
      );
    }
    if (data.containsKey('launch')) {
      context.handle(
        _launchMeta,
        launch.isAcceptableOrUnknown(data['launch']!, _launchMeta),
      );
    }
    if (data.containsKey('fielder')) {
      context.handle(
        _fielderMeta,
        fielder.isAcceptableOrUnknown(data['fielder']!, _fielderMeta),
      );
    } else if (isInserting) {
      context.missing(_fielderMeta);
    }
    if (data.containsKey('outcome')) {
      context.handle(
        _outcomeMeta,
        outcome.isAcceptableOrUnknown(data['outcome']!, _outcomeMeta),
      );
    } else if (isInserting) {
      context.missing(_outcomeMeta);
    }
    if (data.containsKey('play_code')) {
      context.handle(
        _playCodeMeta,
        playCode.isAcceptableOrUnknown(data['play_code']!, _playCodeMeta),
      );
    } else if (isInserting) {
      context.missing(_playCodeMeta);
    }
    if (data.containsKey('break_d_x')) {
      context.handle(
        _breakDXMeta,
        breakDX.isAcceptableOrUnknown(data['break_d_x']!, _breakDXMeta),
      );
    } else if (isInserting) {
      context.missing(_breakDXMeta);
    }
    if (data.containsKey('break_d_y')) {
      context.handle(
        _breakDYMeta,
        breakDY.isAcceptableOrUnknown(data['break_d_y']!, _breakDYMeta),
      );
    } else if (isInserting) {
      context.missing(_breakDYMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {season, matchIdx, seq};
  @override
  PitchRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PitchRow(
      season: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}season'],
      )!,
      matchIdx: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}match_idx'],
      )!,
      seq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}seq'],
      )!,
      paIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}pa_index'],
      )!,
      pitchNo: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}pitch_no'],
      )!,
      battingHome: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}batting_home'],
      )!,
      batter: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}batter'],
      )!,
      batterHand: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}batter_hand'],
      )!,
      pitcher: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pitcher'],
      )!,
      pitchName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pitch_name'],
      )!,
      speed: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}speed'],
      )!,
      x: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}x'],
      )!,
      z: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}z'],
      )!,
      inZone: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}in_zone'],
      )!,
      balls: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}balls'],
      )!,
      strikes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}strikes'],
      )!,
      result: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}result'],
      )!,
      contact: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}contact'],
      )!,
      landX: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}land_x'],
      ),
      landY: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}land_y'],
      ),
      launch: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}launch'],
      ),
      fielder: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}fielder'],
      )!,
      outcome: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}outcome'],
      )!,
      playCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}play_code'],
      )!,
      breakDX: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}break_d_x'],
      )!,
      breakDY: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}break_d_y'],
      )!,
    );
  }

  @override
  $PitchRowsTable createAlias(String alias) {
    return $PitchRowsTable(attachedDatabase, alias);
  }
}

class PitchRow extends DataClass implements Insertable<PitchRow> {
  final int season;
  final int matchIdx;
  final int seq;
  final int paIndex;
  final int pitchNo;
  final bool battingHome;
  final String batter;
  final String batterHand;
  final String pitcher;
  final String pitchName;
  final double speed;
  final double x;
  final double z;
  final bool inZone;
  final int balls;
  final int strikes;
  final String result;
  final String contact;
  final double? landX;
  final double? landY;
  final double? launch;
  final String fielder;
  final String outcome;
  final String playCode;
  final double breakDX;
  final double breakDY;
  const PitchRow({
    required this.season,
    required this.matchIdx,
    required this.seq,
    required this.paIndex,
    required this.pitchNo,
    required this.battingHome,
    required this.batter,
    required this.batterHand,
    required this.pitcher,
    required this.pitchName,
    required this.speed,
    required this.x,
    required this.z,
    required this.inZone,
    required this.balls,
    required this.strikes,
    required this.result,
    required this.contact,
    this.landX,
    this.landY,
    this.launch,
    required this.fielder,
    required this.outcome,
    required this.playCode,
    required this.breakDX,
    required this.breakDY,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['season'] = Variable<int>(season);
    map['match_idx'] = Variable<int>(matchIdx);
    map['seq'] = Variable<int>(seq);
    map['pa_index'] = Variable<int>(paIndex);
    map['pitch_no'] = Variable<int>(pitchNo);
    map['batting_home'] = Variable<bool>(battingHome);
    map['batter'] = Variable<String>(batter);
    map['batter_hand'] = Variable<String>(batterHand);
    map['pitcher'] = Variable<String>(pitcher);
    map['pitch_name'] = Variable<String>(pitchName);
    map['speed'] = Variable<double>(speed);
    map['x'] = Variable<double>(x);
    map['z'] = Variable<double>(z);
    map['in_zone'] = Variable<bool>(inZone);
    map['balls'] = Variable<int>(balls);
    map['strikes'] = Variable<int>(strikes);
    map['result'] = Variable<String>(result);
    map['contact'] = Variable<String>(contact);
    if (!nullToAbsent || landX != null) {
      map['land_x'] = Variable<double>(landX);
    }
    if (!nullToAbsent || landY != null) {
      map['land_y'] = Variable<double>(landY);
    }
    if (!nullToAbsent || launch != null) {
      map['launch'] = Variable<double>(launch);
    }
    map['fielder'] = Variable<String>(fielder);
    map['outcome'] = Variable<String>(outcome);
    map['play_code'] = Variable<String>(playCode);
    map['break_d_x'] = Variable<double>(breakDX);
    map['break_d_y'] = Variable<double>(breakDY);
    return map;
  }

  PitchRowsCompanion toCompanion(bool nullToAbsent) {
    return PitchRowsCompanion(
      season: Value(season),
      matchIdx: Value(matchIdx),
      seq: Value(seq),
      paIndex: Value(paIndex),
      pitchNo: Value(pitchNo),
      battingHome: Value(battingHome),
      batter: Value(batter),
      batterHand: Value(batterHand),
      pitcher: Value(pitcher),
      pitchName: Value(pitchName),
      speed: Value(speed),
      x: Value(x),
      z: Value(z),
      inZone: Value(inZone),
      balls: Value(balls),
      strikes: Value(strikes),
      result: Value(result),
      contact: Value(contact),
      landX: landX == null && nullToAbsent
          ? const Value.absent()
          : Value(landX),
      landY: landY == null && nullToAbsent
          ? const Value.absent()
          : Value(landY),
      launch: launch == null && nullToAbsent
          ? const Value.absent()
          : Value(launch),
      fielder: Value(fielder),
      outcome: Value(outcome),
      playCode: Value(playCode),
      breakDX: Value(breakDX),
      breakDY: Value(breakDY),
    );
  }

  factory PitchRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PitchRow(
      season: serializer.fromJson<int>(json['season']),
      matchIdx: serializer.fromJson<int>(json['matchIdx']),
      seq: serializer.fromJson<int>(json['seq']),
      paIndex: serializer.fromJson<int>(json['paIndex']),
      pitchNo: serializer.fromJson<int>(json['pitchNo']),
      battingHome: serializer.fromJson<bool>(json['battingHome']),
      batter: serializer.fromJson<String>(json['batter']),
      batterHand: serializer.fromJson<String>(json['batterHand']),
      pitcher: serializer.fromJson<String>(json['pitcher']),
      pitchName: serializer.fromJson<String>(json['pitchName']),
      speed: serializer.fromJson<double>(json['speed']),
      x: serializer.fromJson<double>(json['x']),
      z: serializer.fromJson<double>(json['z']),
      inZone: serializer.fromJson<bool>(json['inZone']),
      balls: serializer.fromJson<int>(json['balls']),
      strikes: serializer.fromJson<int>(json['strikes']),
      result: serializer.fromJson<String>(json['result']),
      contact: serializer.fromJson<String>(json['contact']),
      landX: serializer.fromJson<double?>(json['landX']),
      landY: serializer.fromJson<double?>(json['landY']),
      launch: serializer.fromJson<double?>(json['launch']),
      fielder: serializer.fromJson<String>(json['fielder']),
      outcome: serializer.fromJson<String>(json['outcome']),
      playCode: serializer.fromJson<String>(json['playCode']),
      breakDX: serializer.fromJson<double>(json['breakDX']),
      breakDY: serializer.fromJson<double>(json['breakDY']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'season': serializer.toJson<int>(season),
      'matchIdx': serializer.toJson<int>(matchIdx),
      'seq': serializer.toJson<int>(seq),
      'paIndex': serializer.toJson<int>(paIndex),
      'pitchNo': serializer.toJson<int>(pitchNo),
      'battingHome': serializer.toJson<bool>(battingHome),
      'batter': serializer.toJson<String>(batter),
      'batterHand': serializer.toJson<String>(batterHand),
      'pitcher': serializer.toJson<String>(pitcher),
      'pitchName': serializer.toJson<String>(pitchName),
      'speed': serializer.toJson<double>(speed),
      'x': serializer.toJson<double>(x),
      'z': serializer.toJson<double>(z),
      'inZone': serializer.toJson<bool>(inZone),
      'balls': serializer.toJson<int>(balls),
      'strikes': serializer.toJson<int>(strikes),
      'result': serializer.toJson<String>(result),
      'contact': serializer.toJson<String>(contact),
      'landX': serializer.toJson<double?>(landX),
      'landY': serializer.toJson<double?>(landY),
      'launch': serializer.toJson<double?>(launch),
      'fielder': serializer.toJson<String>(fielder),
      'outcome': serializer.toJson<String>(outcome),
      'playCode': serializer.toJson<String>(playCode),
      'breakDX': serializer.toJson<double>(breakDX),
      'breakDY': serializer.toJson<double>(breakDY),
    };
  }

  PitchRow copyWith({
    int? season,
    int? matchIdx,
    int? seq,
    int? paIndex,
    int? pitchNo,
    bool? battingHome,
    String? batter,
    String? batterHand,
    String? pitcher,
    String? pitchName,
    double? speed,
    double? x,
    double? z,
    bool? inZone,
    int? balls,
    int? strikes,
    String? result,
    String? contact,
    Value<double?> landX = const Value.absent(),
    Value<double?> landY = const Value.absent(),
    Value<double?> launch = const Value.absent(),
    String? fielder,
    String? outcome,
    String? playCode,
    double? breakDX,
    double? breakDY,
  }) => PitchRow(
    season: season ?? this.season,
    matchIdx: matchIdx ?? this.matchIdx,
    seq: seq ?? this.seq,
    paIndex: paIndex ?? this.paIndex,
    pitchNo: pitchNo ?? this.pitchNo,
    battingHome: battingHome ?? this.battingHome,
    batter: batter ?? this.batter,
    batterHand: batterHand ?? this.batterHand,
    pitcher: pitcher ?? this.pitcher,
    pitchName: pitchName ?? this.pitchName,
    speed: speed ?? this.speed,
    x: x ?? this.x,
    z: z ?? this.z,
    inZone: inZone ?? this.inZone,
    balls: balls ?? this.balls,
    strikes: strikes ?? this.strikes,
    result: result ?? this.result,
    contact: contact ?? this.contact,
    landX: landX.present ? landX.value : this.landX,
    landY: landY.present ? landY.value : this.landY,
    launch: launch.present ? launch.value : this.launch,
    fielder: fielder ?? this.fielder,
    outcome: outcome ?? this.outcome,
    playCode: playCode ?? this.playCode,
    breakDX: breakDX ?? this.breakDX,
    breakDY: breakDY ?? this.breakDY,
  );
  PitchRow copyWithCompanion(PitchRowsCompanion data) {
    return PitchRow(
      season: data.season.present ? data.season.value : this.season,
      matchIdx: data.matchIdx.present ? data.matchIdx.value : this.matchIdx,
      seq: data.seq.present ? data.seq.value : this.seq,
      paIndex: data.paIndex.present ? data.paIndex.value : this.paIndex,
      pitchNo: data.pitchNo.present ? data.pitchNo.value : this.pitchNo,
      battingHome: data.battingHome.present
          ? data.battingHome.value
          : this.battingHome,
      batter: data.batter.present ? data.batter.value : this.batter,
      batterHand: data.batterHand.present
          ? data.batterHand.value
          : this.batterHand,
      pitcher: data.pitcher.present ? data.pitcher.value : this.pitcher,
      pitchName: data.pitchName.present ? data.pitchName.value : this.pitchName,
      speed: data.speed.present ? data.speed.value : this.speed,
      x: data.x.present ? data.x.value : this.x,
      z: data.z.present ? data.z.value : this.z,
      inZone: data.inZone.present ? data.inZone.value : this.inZone,
      balls: data.balls.present ? data.balls.value : this.balls,
      strikes: data.strikes.present ? data.strikes.value : this.strikes,
      result: data.result.present ? data.result.value : this.result,
      contact: data.contact.present ? data.contact.value : this.contact,
      landX: data.landX.present ? data.landX.value : this.landX,
      landY: data.landY.present ? data.landY.value : this.landY,
      launch: data.launch.present ? data.launch.value : this.launch,
      fielder: data.fielder.present ? data.fielder.value : this.fielder,
      outcome: data.outcome.present ? data.outcome.value : this.outcome,
      playCode: data.playCode.present ? data.playCode.value : this.playCode,
      breakDX: data.breakDX.present ? data.breakDX.value : this.breakDX,
      breakDY: data.breakDY.present ? data.breakDY.value : this.breakDY,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PitchRow(')
          ..write('season: $season, ')
          ..write('matchIdx: $matchIdx, ')
          ..write('seq: $seq, ')
          ..write('paIndex: $paIndex, ')
          ..write('pitchNo: $pitchNo, ')
          ..write('battingHome: $battingHome, ')
          ..write('batter: $batter, ')
          ..write('batterHand: $batterHand, ')
          ..write('pitcher: $pitcher, ')
          ..write('pitchName: $pitchName, ')
          ..write('speed: $speed, ')
          ..write('x: $x, ')
          ..write('z: $z, ')
          ..write('inZone: $inZone, ')
          ..write('balls: $balls, ')
          ..write('strikes: $strikes, ')
          ..write('result: $result, ')
          ..write('contact: $contact, ')
          ..write('landX: $landX, ')
          ..write('landY: $landY, ')
          ..write('launch: $launch, ')
          ..write('fielder: $fielder, ')
          ..write('outcome: $outcome, ')
          ..write('playCode: $playCode, ')
          ..write('breakDX: $breakDX, ')
          ..write('breakDY: $breakDY')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    season,
    matchIdx,
    seq,
    paIndex,
    pitchNo,
    battingHome,
    batter,
    batterHand,
    pitcher,
    pitchName,
    speed,
    x,
    z,
    inZone,
    balls,
    strikes,
    result,
    contact,
    landX,
    landY,
    launch,
    fielder,
    outcome,
    playCode,
    breakDX,
    breakDY,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PitchRow &&
          other.season == this.season &&
          other.matchIdx == this.matchIdx &&
          other.seq == this.seq &&
          other.paIndex == this.paIndex &&
          other.pitchNo == this.pitchNo &&
          other.battingHome == this.battingHome &&
          other.batter == this.batter &&
          other.batterHand == this.batterHand &&
          other.pitcher == this.pitcher &&
          other.pitchName == this.pitchName &&
          other.speed == this.speed &&
          other.x == this.x &&
          other.z == this.z &&
          other.inZone == this.inZone &&
          other.balls == this.balls &&
          other.strikes == this.strikes &&
          other.result == this.result &&
          other.contact == this.contact &&
          other.landX == this.landX &&
          other.landY == this.landY &&
          other.launch == this.launch &&
          other.fielder == this.fielder &&
          other.outcome == this.outcome &&
          other.playCode == this.playCode &&
          other.breakDX == this.breakDX &&
          other.breakDY == this.breakDY);
}

class PitchRowsCompanion extends UpdateCompanion<PitchRow> {
  final Value<int> season;
  final Value<int> matchIdx;
  final Value<int> seq;
  final Value<int> paIndex;
  final Value<int> pitchNo;
  final Value<bool> battingHome;
  final Value<String> batter;
  final Value<String> batterHand;
  final Value<String> pitcher;
  final Value<String> pitchName;
  final Value<double> speed;
  final Value<double> x;
  final Value<double> z;
  final Value<bool> inZone;
  final Value<int> balls;
  final Value<int> strikes;
  final Value<String> result;
  final Value<String> contact;
  final Value<double?> landX;
  final Value<double?> landY;
  final Value<double?> launch;
  final Value<String> fielder;
  final Value<String> outcome;
  final Value<String> playCode;
  final Value<double> breakDX;
  final Value<double> breakDY;
  final Value<int> rowid;
  const PitchRowsCompanion({
    this.season = const Value.absent(),
    this.matchIdx = const Value.absent(),
    this.seq = const Value.absent(),
    this.paIndex = const Value.absent(),
    this.pitchNo = const Value.absent(),
    this.battingHome = const Value.absent(),
    this.batter = const Value.absent(),
    this.batterHand = const Value.absent(),
    this.pitcher = const Value.absent(),
    this.pitchName = const Value.absent(),
    this.speed = const Value.absent(),
    this.x = const Value.absent(),
    this.z = const Value.absent(),
    this.inZone = const Value.absent(),
    this.balls = const Value.absent(),
    this.strikes = const Value.absent(),
    this.result = const Value.absent(),
    this.contact = const Value.absent(),
    this.landX = const Value.absent(),
    this.landY = const Value.absent(),
    this.launch = const Value.absent(),
    this.fielder = const Value.absent(),
    this.outcome = const Value.absent(),
    this.playCode = const Value.absent(),
    this.breakDX = const Value.absent(),
    this.breakDY = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PitchRowsCompanion.insert({
    required int season,
    required int matchIdx,
    required int seq,
    required int paIndex,
    required int pitchNo,
    required bool battingHome,
    required String batter,
    required String batterHand,
    required String pitcher,
    required String pitchName,
    required double speed,
    required double x,
    required double z,
    required bool inZone,
    required int balls,
    required int strikes,
    required String result,
    required String contact,
    this.landX = const Value.absent(),
    this.landY = const Value.absent(),
    this.launch = const Value.absent(),
    required String fielder,
    required String outcome,
    required String playCode,
    required double breakDX,
    required double breakDY,
    this.rowid = const Value.absent(),
  }) : season = Value(season),
       matchIdx = Value(matchIdx),
       seq = Value(seq),
       paIndex = Value(paIndex),
       pitchNo = Value(pitchNo),
       battingHome = Value(battingHome),
       batter = Value(batter),
       batterHand = Value(batterHand),
       pitcher = Value(pitcher),
       pitchName = Value(pitchName),
       speed = Value(speed),
       x = Value(x),
       z = Value(z),
       inZone = Value(inZone),
       balls = Value(balls),
       strikes = Value(strikes),
       result = Value(result),
       contact = Value(contact),
       fielder = Value(fielder),
       outcome = Value(outcome),
       playCode = Value(playCode),
       breakDX = Value(breakDX),
       breakDY = Value(breakDY);
  static Insertable<PitchRow> custom({
    Expression<int>? season,
    Expression<int>? matchIdx,
    Expression<int>? seq,
    Expression<int>? paIndex,
    Expression<int>? pitchNo,
    Expression<bool>? battingHome,
    Expression<String>? batter,
    Expression<String>? batterHand,
    Expression<String>? pitcher,
    Expression<String>? pitchName,
    Expression<double>? speed,
    Expression<double>? x,
    Expression<double>? z,
    Expression<bool>? inZone,
    Expression<int>? balls,
    Expression<int>? strikes,
    Expression<String>? result,
    Expression<String>? contact,
    Expression<double>? landX,
    Expression<double>? landY,
    Expression<double>? launch,
    Expression<String>? fielder,
    Expression<String>? outcome,
    Expression<String>? playCode,
    Expression<double>? breakDX,
    Expression<double>? breakDY,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (season != null) 'season': season,
      if (matchIdx != null) 'match_idx': matchIdx,
      if (seq != null) 'seq': seq,
      if (paIndex != null) 'pa_index': paIndex,
      if (pitchNo != null) 'pitch_no': pitchNo,
      if (battingHome != null) 'batting_home': battingHome,
      if (batter != null) 'batter': batter,
      if (batterHand != null) 'batter_hand': batterHand,
      if (pitcher != null) 'pitcher': pitcher,
      if (pitchName != null) 'pitch_name': pitchName,
      if (speed != null) 'speed': speed,
      if (x != null) 'x': x,
      if (z != null) 'z': z,
      if (inZone != null) 'in_zone': inZone,
      if (balls != null) 'balls': balls,
      if (strikes != null) 'strikes': strikes,
      if (result != null) 'result': result,
      if (contact != null) 'contact': contact,
      if (landX != null) 'land_x': landX,
      if (landY != null) 'land_y': landY,
      if (launch != null) 'launch': launch,
      if (fielder != null) 'fielder': fielder,
      if (outcome != null) 'outcome': outcome,
      if (playCode != null) 'play_code': playCode,
      if (breakDX != null) 'break_d_x': breakDX,
      if (breakDY != null) 'break_d_y': breakDY,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PitchRowsCompanion copyWith({
    Value<int>? season,
    Value<int>? matchIdx,
    Value<int>? seq,
    Value<int>? paIndex,
    Value<int>? pitchNo,
    Value<bool>? battingHome,
    Value<String>? batter,
    Value<String>? batterHand,
    Value<String>? pitcher,
    Value<String>? pitchName,
    Value<double>? speed,
    Value<double>? x,
    Value<double>? z,
    Value<bool>? inZone,
    Value<int>? balls,
    Value<int>? strikes,
    Value<String>? result,
    Value<String>? contact,
    Value<double?>? landX,
    Value<double?>? landY,
    Value<double?>? launch,
    Value<String>? fielder,
    Value<String>? outcome,
    Value<String>? playCode,
    Value<double>? breakDX,
    Value<double>? breakDY,
    Value<int>? rowid,
  }) {
    return PitchRowsCompanion(
      season: season ?? this.season,
      matchIdx: matchIdx ?? this.matchIdx,
      seq: seq ?? this.seq,
      paIndex: paIndex ?? this.paIndex,
      pitchNo: pitchNo ?? this.pitchNo,
      battingHome: battingHome ?? this.battingHome,
      batter: batter ?? this.batter,
      batterHand: batterHand ?? this.batterHand,
      pitcher: pitcher ?? this.pitcher,
      pitchName: pitchName ?? this.pitchName,
      speed: speed ?? this.speed,
      x: x ?? this.x,
      z: z ?? this.z,
      inZone: inZone ?? this.inZone,
      balls: balls ?? this.balls,
      strikes: strikes ?? this.strikes,
      result: result ?? this.result,
      contact: contact ?? this.contact,
      landX: landX ?? this.landX,
      landY: landY ?? this.landY,
      launch: launch ?? this.launch,
      fielder: fielder ?? this.fielder,
      outcome: outcome ?? this.outcome,
      playCode: playCode ?? this.playCode,
      breakDX: breakDX ?? this.breakDX,
      breakDY: breakDY ?? this.breakDY,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (season.present) {
      map['season'] = Variable<int>(season.value);
    }
    if (matchIdx.present) {
      map['match_idx'] = Variable<int>(matchIdx.value);
    }
    if (seq.present) {
      map['seq'] = Variable<int>(seq.value);
    }
    if (paIndex.present) {
      map['pa_index'] = Variable<int>(paIndex.value);
    }
    if (pitchNo.present) {
      map['pitch_no'] = Variable<int>(pitchNo.value);
    }
    if (battingHome.present) {
      map['batting_home'] = Variable<bool>(battingHome.value);
    }
    if (batter.present) {
      map['batter'] = Variable<String>(batter.value);
    }
    if (batterHand.present) {
      map['batter_hand'] = Variable<String>(batterHand.value);
    }
    if (pitcher.present) {
      map['pitcher'] = Variable<String>(pitcher.value);
    }
    if (pitchName.present) {
      map['pitch_name'] = Variable<String>(pitchName.value);
    }
    if (speed.present) {
      map['speed'] = Variable<double>(speed.value);
    }
    if (x.present) {
      map['x'] = Variable<double>(x.value);
    }
    if (z.present) {
      map['z'] = Variable<double>(z.value);
    }
    if (inZone.present) {
      map['in_zone'] = Variable<bool>(inZone.value);
    }
    if (balls.present) {
      map['balls'] = Variable<int>(balls.value);
    }
    if (strikes.present) {
      map['strikes'] = Variable<int>(strikes.value);
    }
    if (result.present) {
      map['result'] = Variable<String>(result.value);
    }
    if (contact.present) {
      map['contact'] = Variable<String>(contact.value);
    }
    if (landX.present) {
      map['land_x'] = Variable<double>(landX.value);
    }
    if (landY.present) {
      map['land_y'] = Variable<double>(landY.value);
    }
    if (launch.present) {
      map['launch'] = Variable<double>(launch.value);
    }
    if (fielder.present) {
      map['fielder'] = Variable<String>(fielder.value);
    }
    if (outcome.present) {
      map['outcome'] = Variable<String>(outcome.value);
    }
    if (playCode.present) {
      map['play_code'] = Variable<String>(playCode.value);
    }
    if (breakDX.present) {
      map['break_d_x'] = Variable<double>(breakDX.value);
    }
    if (breakDY.present) {
      map['break_d_y'] = Variable<double>(breakDY.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PitchRowsCompanion(')
          ..write('season: $season, ')
          ..write('matchIdx: $matchIdx, ')
          ..write('seq: $seq, ')
          ..write('paIndex: $paIndex, ')
          ..write('pitchNo: $pitchNo, ')
          ..write('battingHome: $battingHome, ')
          ..write('batter: $batter, ')
          ..write('batterHand: $batterHand, ')
          ..write('pitcher: $pitcher, ')
          ..write('pitchName: $pitchName, ')
          ..write('speed: $speed, ')
          ..write('x: $x, ')
          ..write('z: $z, ')
          ..write('inZone: $inZone, ')
          ..write('balls: $balls, ')
          ..write('strikes: $strikes, ')
          ..write('result: $result, ')
          ..write('contact: $contact, ')
          ..write('landX: $landX, ')
          ..write('landY: $landY, ')
          ..write('launch: $launch, ')
          ..write('fielder: $fielder, ')
          ..write('outcome: $outcome, ')
          ..write('playCode: $playCode, ')
          ..write('breakDX: $breakDX, ')
          ..write('breakDY: $breakDY, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ProspectRowsTable extends ProspectRows
    with TableInfo<$ProspectRowsTable, ProspectRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProspectRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sortMeta = const VerificationMeta('sort');
  @override
  late final GeneratedColumn<int> sort = GeneratedColumn<int>(
    'sort',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _jsonMeta = const VerificationMeta('json');
  @override
  late final GeneratedColumn<String> json = GeneratedColumn<String>(
    'json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, sort, json];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'prospect_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProspectRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('sort')) {
      context.handle(
        _sortMeta,
        sort.isAcceptableOrUnknown(data['sort']!, _sortMeta),
      );
    } else if (isInserting) {
      context.missing(_sortMeta);
    }
    if (data.containsKey('json')) {
      context.handle(
        _jsonMeta,
        json.isAcceptableOrUnknown(data['json']!, _jsonMeta),
      );
    } else if (isInserting) {
      context.missing(_jsonMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ProspectRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProspectRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      sort: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort'],
      )!,
      json: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}json'],
      )!,
    );
  }

  @override
  $ProspectRowsTable createAlias(String alias) {
    return $ProspectRowsTable(attachedDatabase, alias);
  }
}

class ProspectRow extends DataClass implements Insertable<ProspectRow> {
  final String id;
  final int sort;
  final String json;
  const ProspectRow({required this.id, required this.sort, required this.json});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['sort'] = Variable<int>(sort);
    map['json'] = Variable<String>(json);
    return map;
  }

  ProspectRowsCompanion toCompanion(bool nullToAbsent) {
    return ProspectRowsCompanion(
      id: Value(id),
      sort: Value(sort),
      json: Value(json),
    );
  }

  factory ProspectRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProspectRow(
      id: serializer.fromJson<String>(json['id']),
      sort: serializer.fromJson<int>(json['sort']),
      json: serializer.fromJson<String>(json['json']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'sort': serializer.toJson<int>(sort),
      'json': serializer.toJson<String>(json),
    };
  }

  ProspectRow copyWith({String? id, int? sort, String? json}) => ProspectRow(
    id: id ?? this.id,
    sort: sort ?? this.sort,
    json: json ?? this.json,
  );
  ProspectRow copyWithCompanion(ProspectRowsCompanion data) {
    return ProspectRow(
      id: data.id.present ? data.id.value : this.id,
      sort: data.sort.present ? data.sort.value : this.sort,
      json: data.json.present ? data.json.value : this.json,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProspectRow(')
          ..write('id: $id, ')
          ..write('sort: $sort, ')
          ..write('json: $json')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, sort, json);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProspectRow &&
          other.id == this.id &&
          other.sort == this.sort &&
          other.json == this.json);
}

class ProspectRowsCompanion extends UpdateCompanion<ProspectRow> {
  final Value<String> id;
  final Value<int> sort;
  final Value<String> json;
  final Value<int> rowid;
  const ProspectRowsCompanion({
    this.id = const Value.absent(),
    this.sort = const Value.absent(),
    this.json = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProspectRowsCompanion.insert({
    required String id,
    required int sort,
    required String json,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       sort = Value(sort),
       json = Value(json);
  static Insertable<ProspectRow> custom({
    Expression<String>? id,
    Expression<int>? sort,
    Expression<String>? json,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sort != null) 'sort': sort,
      if (json != null) 'json': json,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProspectRowsCompanion copyWith({
    Value<String>? id,
    Value<int>? sort,
    Value<String>? json,
    Value<int>? rowid,
  }) {
    return ProspectRowsCompanion(
      id: id ?? this.id,
      sort: sort ?? this.sort,
      json: json ?? this.json,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (sort.present) {
      map['sort'] = Variable<int>(sort.value);
    }
    if (json.present) {
      map['json'] = Variable<String>(json.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProspectRowsCompanion(')
          ..write('id: $id, ')
          ..write('sort: $sort, ')
          ..write('json: $json, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $KvEntriesTable kvEntries = $KvEntriesTable(this);
  late final $TeamRowsTable teamRows = $TeamRowsTable(this);
  late final $MatchRowsTable matchRows = $MatchRowsTable(this);
  late final $SeasonRecordsTable seasonRecords = $SeasonRecordsTable(this);
  late final $PitchRowsTable pitchRows = $PitchRowsTable(this);
  late final $ProspectRowsTable prospectRows = $ProspectRowsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    kvEntries,
    teamRows,
    matchRows,
    seasonRecords,
    pitchRows,
    prospectRows,
  ];
}

typedef $$KvEntriesTableCreateCompanionBuilder = KvEntriesCompanion Function({
  required String key,
  required String value,
  Value<int> rowid,
});
typedef $$KvEntriesTableUpdateCompanionBuilder = KvEntriesCompanion Function({
  Value<String> key,
  Value<String> value,
  Value<int> rowid,
});

class $$KvEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $KvEntriesTable> {
  $$KvEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$KvEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $KvEntriesTable> {
  $$KvEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$KvEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $KvEntriesTable> {
  $$KvEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$KvEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $KvEntriesTable,
          KvEntry,
          $$KvEntriesTableFilterComposer,
          $$KvEntriesTableOrderingComposer,
          $$KvEntriesTableAnnotationComposer,
          $$KvEntriesTableCreateCompanionBuilder,
          $$KvEntriesTableUpdateCompanionBuilder,
          (KvEntry, BaseReferences<_$AppDatabase, $KvEntriesTable, KvEntry>),
          KvEntry,
          PrefetchHooks Function()
        > {
  $$KvEntriesTableTableManager(_$AppDatabase db, $KvEntriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$KvEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$KvEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$KvEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> key = const Value.absent(),
            Value<String> value = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) => KvEntriesCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback: ({
            required String key,
            required String value,
            Value<int> rowid = const Value.absent(),
          }) => KvEntriesCompanion.insert(key: key, value: value, rowid: rowid),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$KvEntriesTable, KvEntry>(table),
                  BaseReferences<_$AppDatabase, $KvEntriesTable, KvEntry>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$KvEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $KvEntriesTable,
      KvEntry,
      $$KvEntriesTableFilterComposer,
      $$KvEntriesTableOrderingComposer,
      $$KvEntriesTableAnnotationComposer,
      $$KvEntriesTableCreateCompanionBuilder,
      $$KvEntriesTableUpdateCompanionBuilder,
      (KvEntry, BaseReferences<_$AppDatabase, $KvEntriesTable, KvEntry>),
      KvEntry,
      PrefetchHooks Function()
    >;
typedef $$TeamRowsTableCreateCompanionBuilder = TeamRowsCompanion Function({
  required String id,
  required int sort,
  required String json,
  Value<int> rowid,
});
typedef $$TeamRowsTableUpdateCompanionBuilder = TeamRowsCompanion Function({
  Value<String> id,
  Value<int> sort,
  Value<String> json,
  Value<int> rowid,
});

class $$TeamRowsTableFilterComposer
    extends Composer<_$AppDatabase, $TeamRowsTable> {
  $$TeamRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sort => $composableBuilder(
    column: $table.sort,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TeamRowsTableOrderingComposer
    extends Composer<_$AppDatabase, $TeamRowsTable> {
  $$TeamRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sort => $composableBuilder(
    column: $table.sort,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TeamRowsTableAnnotationComposer
    extends Composer<_$AppDatabase, $TeamRowsTable> {
  $$TeamRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get sort =>
      $composableBuilder(column: $table.sort, builder: (column) => column);

  GeneratedColumn<String> get json =>
      $composableBuilder(column: $table.json, builder: (column) => column);
}

class $$TeamRowsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TeamRowsTable,
          TeamRow,
          $$TeamRowsTableFilterComposer,
          $$TeamRowsTableOrderingComposer,
          $$TeamRowsTableAnnotationComposer,
          $$TeamRowsTableCreateCompanionBuilder,
          $$TeamRowsTableUpdateCompanionBuilder,
          (TeamRow, BaseReferences<_$AppDatabase, $TeamRowsTable, TeamRow>),
          TeamRow,
          PrefetchHooks Function()
        > {
  $$TeamRowsTableTableManager(_$AppDatabase db, $TeamRowsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TeamRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TeamRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TeamRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<int> sort = const Value.absent(),
            Value<String> json = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) => TeamRowsCompanion(id: id, sort: sort, json: json, rowid: rowid),
          createCompanionCallback:
              ({
                required String id,
                required int sort,
                required String json,
                Value<int> rowid = const Value.absent(),
              }) => TeamRowsCompanion.insert(
                id: id,
                sort: sort,
                json: json,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$TeamRowsTable, TeamRow>(table),
                  BaseReferences<_$AppDatabase, $TeamRowsTable, TeamRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TeamRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TeamRowsTable,
      TeamRow,
      $$TeamRowsTableFilterComposer,
      $$TeamRowsTableOrderingComposer,
      $$TeamRowsTableAnnotationComposer,
      $$TeamRowsTableCreateCompanionBuilder,
      $$TeamRowsTableUpdateCompanionBuilder,
      (TeamRow, BaseReferences<_$AppDatabase, $TeamRowsTable, TeamRow>),
      TeamRow,
      PrefetchHooks Function()
    >;
typedef $$MatchRowsTableCreateCompanionBuilder = MatchRowsCompanion Function({
  required int season,
  required int idx,
  Value<bool> played,
  required String json,
  Value<int> rowid,
});
typedef $$MatchRowsTableUpdateCompanionBuilder = MatchRowsCompanion Function({
  Value<int> season,
  Value<int> idx,
  Value<bool> played,
  Value<String> json,
  Value<int> rowid,
});

class $$MatchRowsTableFilterComposer
    extends Composer<_$AppDatabase, $MatchRowsTable> {
  $$MatchRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get season => $composableBuilder(
    column: $table.season,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get idx => $composableBuilder(
    column: $table.idx,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get played => $composableBuilder(
    column: $table.played,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MatchRowsTableOrderingComposer
    extends Composer<_$AppDatabase, $MatchRowsTable> {
  $$MatchRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get season => $composableBuilder(
    column: $table.season,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get idx => $composableBuilder(
    column: $table.idx,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get played => $composableBuilder(
    column: $table.played,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MatchRowsTableAnnotationComposer
    extends Composer<_$AppDatabase, $MatchRowsTable> {
  $$MatchRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get season =>
      $composableBuilder(column: $table.season, builder: (column) => column);

  GeneratedColumn<int> get idx =>
      $composableBuilder(column: $table.idx, builder: (column) => column);

  GeneratedColumn<bool> get played =>
      $composableBuilder(column: $table.played, builder: (column) => column);

  GeneratedColumn<String> get json =>
      $composableBuilder(column: $table.json, builder: (column) => column);
}

class $$MatchRowsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MatchRowsTable,
          MatchRow,
          $$MatchRowsTableFilterComposer,
          $$MatchRowsTableOrderingComposer,
          $$MatchRowsTableAnnotationComposer,
          $$MatchRowsTableCreateCompanionBuilder,
          $$MatchRowsTableUpdateCompanionBuilder,
          (MatchRow, BaseReferences<_$AppDatabase, $MatchRowsTable, MatchRow>),
          MatchRow,
          PrefetchHooks Function()
        > {
  $$MatchRowsTableTableManager(_$AppDatabase db, $MatchRowsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MatchRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MatchRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MatchRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> season = const Value.absent(),
                Value<int> idx = const Value.absent(),
                Value<bool> played = const Value.absent(),
                Value<String> json = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MatchRowsCompanion(
                season: season,
                idx: idx,
                played: played,
                json: json,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int season,
                required int idx,
                Value<bool> played = const Value.absent(),
                required String json,
                Value<int> rowid = const Value.absent(),
              }) => MatchRowsCompanion.insert(
                season: season,
                idx: idx,
                played: played,
                json: json,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$MatchRowsTable, MatchRow>(table),
                  BaseReferences<_$AppDatabase, $MatchRowsTable, MatchRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MatchRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MatchRowsTable,
      MatchRow,
      $$MatchRowsTableFilterComposer,
      $$MatchRowsTableOrderingComposer,
      $$MatchRowsTableAnnotationComposer,
      $$MatchRowsTableCreateCompanionBuilder,
      $$MatchRowsTableUpdateCompanionBuilder,
      (MatchRow, BaseReferences<_$AppDatabase, $MatchRowsTable, MatchRow>),
      MatchRow,
      PrefetchHooks Function()
    >;
typedef $$SeasonRecordsTableCreateCompanionBuilder =
    SeasonRecordsCompanion Function({
      required int season,
      required String kind,
      required String refId,
      required String teamId,
      required String json,
      Value<int> rowid,
    });
typedef $$SeasonRecordsTableUpdateCompanionBuilder =
    SeasonRecordsCompanion Function({
      Value<int> season,
      Value<String> kind,
      Value<String> refId,
      Value<String> teamId,
      Value<String> json,
      Value<int> rowid,
    });

class $$SeasonRecordsTableFilterComposer
    extends Composer<_$AppDatabase, $SeasonRecordsTable> {
  $$SeasonRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get season => $composableBuilder(
    column: $table.season,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get refId => $composableBuilder(
    column: $table.refId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get teamId => $composableBuilder(
    column: $table.teamId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SeasonRecordsTableOrderingComposer
    extends Composer<_$AppDatabase, $SeasonRecordsTable> {
  $$SeasonRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get season => $composableBuilder(
    column: $table.season,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get refId => $composableBuilder(
    column: $table.refId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get teamId => $composableBuilder(
    column: $table.teamId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SeasonRecordsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SeasonRecordsTable> {
  $$SeasonRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get season =>
      $composableBuilder(column: $table.season, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get refId =>
      $composableBuilder(column: $table.refId, builder: (column) => column);

  GeneratedColumn<String> get teamId =>
      $composableBuilder(column: $table.teamId, builder: (column) => column);

  GeneratedColumn<String> get json =>
      $composableBuilder(column: $table.json, builder: (column) => column);
}

class $$SeasonRecordsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SeasonRecordsTable,
          SeasonRecord,
          $$SeasonRecordsTableFilterComposer,
          $$SeasonRecordsTableOrderingComposer,
          $$SeasonRecordsTableAnnotationComposer,
          $$SeasonRecordsTableCreateCompanionBuilder,
          $$SeasonRecordsTableUpdateCompanionBuilder,
          (
            SeasonRecord,
            BaseReferences<_$AppDatabase, $SeasonRecordsTable, SeasonRecord>,
          ),
          SeasonRecord,
          PrefetchHooks Function()
        > {
  $$SeasonRecordsTableTableManager(_$AppDatabase db, $SeasonRecordsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SeasonRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SeasonRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SeasonRecordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> season = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> refId = const Value.absent(),
                Value<String> teamId = const Value.absent(),
                Value<String> json = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SeasonRecordsCompanion(
                season: season,
                kind: kind,
                refId: refId,
                teamId: teamId,
                json: json,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int season,
                required String kind,
                required String refId,
                required String teamId,
                required String json,
                Value<int> rowid = const Value.absent(),
              }) => SeasonRecordsCompanion.insert(
                season: season,
                kind: kind,
                refId: refId,
                teamId: teamId,
                json: json,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SeasonRecordsTable, SeasonRecord>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $SeasonRecordsTable,
                    SeasonRecord
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SeasonRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SeasonRecordsTable,
      SeasonRecord,
      $$SeasonRecordsTableFilterComposer,
      $$SeasonRecordsTableOrderingComposer,
      $$SeasonRecordsTableAnnotationComposer,
      $$SeasonRecordsTableCreateCompanionBuilder,
      $$SeasonRecordsTableUpdateCompanionBuilder,
      (
        SeasonRecord,
        BaseReferences<_$AppDatabase, $SeasonRecordsTable, SeasonRecord>,
      ),
      SeasonRecord,
      PrefetchHooks Function()
    >;
typedef $$PitchRowsTableCreateCompanionBuilder = PitchRowsCompanion Function({
  required int season,
  required int matchIdx,
  required int seq,
  required int paIndex,
  required int pitchNo,
  required bool battingHome,
  required String batter,
  required String batterHand,
  required String pitcher,
  required String pitchName,
  required double speed,
  required double x,
  required double z,
  required bool inZone,
  required int balls,
  required int strikes,
  required String result,
  required String contact,
  Value<double?> landX,
  Value<double?> landY,
  Value<double?> launch,
  required String fielder,
  required String outcome,
  required String playCode,
  required double breakDX,
  required double breakDY,
  Value<int> rowid,
});
typedef $$PitchRowsTableUpdateCompanionBuilder = PitchRowsCompanion Function({
  Value<int> season,
  Value<int> matchIdx,
  Value<int> seq,
  Value<int> paIndex,
  Value<int> pitchNo,
  Value<bool> battingHome,
  Value<String> batter,
  Value<String> batterHand,
  Value<String> pitcher,
  Value<String> pitchName,
  Value<double> speed,
  Value<double> x,
  Value<double> z,
  Value<bool> inZone,
  Value<int> balls,
  Value<int> strikes,
  Value<String> result,
  Value<String> contact,
  Value<double?> landX,
  Value<double?> landY,
  Value<double?> launch,
  Value<String> fielder,
  Value<String> outcome,
  Value<String> playCode,
  Value<double> breakDX,
  Value<double> breakDY,
  Value<int> rowid,
});

class $$PitchRowsTableFilterComposer
    extends Composer<_$AppDatabase, $PitchRowsTable> {
  $$PitchRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get season => $composableBuilder(
    column: $table.season,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get matchIdx => $composableBuilder(
    column: $table.matchIdx,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get seq => $composableBuilder(
    column: $table.seq,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get paIndex => $composableBuilder(
    column: $table.paIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get pitchNo => $composableBuilder(
    column: $table.pitchNo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get battingHome => $composableBuilder(
    column: $table.battingHome,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get batter => $composableBuilder(
    column: $table.batter,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get batterHand => $composableBuilder(
    column: $table.batterHand,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get pitcher => $composableBuilder(
    column: $table.pitcher,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get pitchName => $composableBuilder(
    column: $table.pitchName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get speed => $composableBuilder(
    column: $table.speed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get x => $composableBuilder(
    column: $table.x,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get z => $composableBuilder(
    column: $table.z,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get inZone => $composableBuilder(
    column: $table.inZone,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get balls => $composableBuilder(
    column: $table.balls,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get strikes => $composableBuilder(
    column: $table.strikes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get result => $composableBuilder(
    column: $table.result,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contact => $composableBuilder(
    column: $table.contact,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get landX => $composableBuilder(
    column: $table.landX,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get landY => $composableBuilder(
    column: $table.landY,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get launch => $composableBuilder(
    column: $table.launch,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fielder => $composableBuilder(
    column: $table.fielder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get outcome => $composableBuilder(
    column: $table.outcome,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get playCode => $composableBuilder(
    column: $table.playCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get breakDX => $composableBuilder(
    column: $table.breakDX,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get breakDY => $composableBuilder(
    column: $table.breakDY,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PitchRowsTableOrderingComposer
    extends Composer<_$AppDatabase, $PitchRowsTable> {
  $$PitchRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get season => $composableBuilder(
    column: $table.season,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get matchIdx => $composableBuilder(
    column: $table.matchIdx,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get seq => $composableBuilder(
    column: $table.seq,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get paIndex => $composableBuilder(
    column: $table.paIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get pitchNo => $composableBuilder(
    column: $table.pitchNo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get battingHome => $composableBuilder(
    column: $table.battingHome,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get batter => $composableBuilder(
    column: $table.batter,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get batterHand => $composableBuilder(
    column: $table.batterHand,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pitcher => $composableBuilder(
    column: $table.pitcher,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pitchName => $composableBuilder(
    column: $table.pitchName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get speed => $composableBuilder(
    column: $table.speed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get x => $composableBuilder(
    column: $table.x,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get z => $composableBuilder(
    column: $table.z,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get inZone => $composableBuilder(
    column: $table.inZone,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get balls => $composableBuilder(
    column: $table.balls,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get strikes => $composableBuilder(
    column: $table.strikes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get result => $composableBuilder(
    column: $table.result,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contact => $composableBuilder(
    column: $table.contact,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get landX => $composableBuilder(
    column: $table.landX,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get landY => $composableBuilder(
    column: $table.landY,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get launch => $composableBuilder(
    column: $table.launch,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fielder => $composableBuilder(
    column: $table.fielder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get outcome => $composableBuilder(
    column: $table.outcome,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get playCode => $composableBuilder(
    column: $table.playCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get breakDX => $composableBuilder(
    column: $table.breakDX,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get breakDY => $composableBuilder(
    column: $table.breakDY,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PitchRowsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PitchRowsTable> {
  $$PitchRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get season =>
      $composableBuilder(column: $table.season, builder: (column) => column);

  GeneratedColumn<int> get matchIdx =>
      $composableBuilder(column: $table.matchIdx, builder: (column) => column);

  GeneratedColumn<int> get seq =>
      $composableBuilder(column: $table.seq, builder: (column) => column);

  GeneratedColumn<int> get paIndex =>
      $composableBuilder(column: $table.paIndex, builder: (column) => column);

  GeneratedColumn<int> get pitchNo =>
      $composableBuilder(column: $table.pitchNo, builder: (column) => column);

  GeneratedColumn<bool> get battingHome => $composableBuilder(
    column: $table.battingHome,
    builder: (column) => column,
  );

  GeneratedColumn<String> get batter =>
      $composableBuilder(column: $table.batter, builder: (column) => column);

  GeneratedColumn<String> get batterHand => $composableBuilder(
    column: $table.batterHand,
    builder: (column) => column,
  );

  GeneratedColumn<String> get pitcher =>
      $composableBuilder(column: $table.pitcher, builder: (column) => column);

  GeneratedColumn<String> get pitchName =>
      $composableBuilder(column: $table.pitchName, builder: (column) => column);

  GeneratedColumn<double> get speed =>
      $composableBuilder(column: $table.speed, builder: (column) => column);

  GeneratedColumn<double> get x =>
      $composableBuilder(column: $table.x, builder: (column) => column);

  GeneratedColumn<double> get z =>
      $composableBuilder(column: $table.z, builder: (column) => column);

  GeneratedColumn<bool> get inZone =>
      $composableBuilder(column: $table.inZone, builder: (column) => column);

  GeneratedColumn<int> get balls =>
      $composableBuilder(column: $table.balls, builder: (column) => column);

  GeneratedColumn<int> get strikes =>
      $composableBuilder(column: $table.strikes, builder: (column) => column);

  GeneratedColumn<String> get result =>
      $composableBuilder(column: $table.result, builder: (column) => column);

  GeneratedColumn<String> get contact =>
      $composableBuilder(column: $table.contact, builder: (column) => column);

  GeneratedColumn<double> get landX =>
      $composableBuilder(column: $table.landX, builder: (column) => column);

  GeneratedColumn<double> get landY =>
      $composableBuilder(column: $table.landY, builder: (column) => column);

  GeneratedColumn<double> get launch =>
      $composableBuilder(column: $table.launch, builder: (column) => column);

  GeneratedColumn<String> get fielder =>
      $composableBuilder(column: $table.fielder, builder: (column) => column);

  GeneratedColumn<String> get outcome =>
      $composableBuilder(column: $table.outcome, builder: (column) => column);

  GeneratedColumn<String> get playCode =>
      $composableBuilder(column: $table.playCode, builder: (column) => column);

  GeneratedColumn<double> get breakDX =>
      $composableBuilder(column: $table.breakDX, builder: (column) => column);

  GeneratedColumn<double> get breakDY =>
      $composableBuilder(column: $table.breakDY, builder: (column) => column);
}

class $$PitchRowsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PitchRowsTable,
          PitchRow,
          $$PitchRowsTableFilterComposer,
          $$PitchRowsTableOrderingComposer,
          $$PitchRowsTableAnnotationComposer,
          $$PitchRowsTableCreateCompanionBuilder,
          $$PitchRowsTableUpdateCompanionBuilder,
          (PitchRow, BaseReferences<_$AppDatabase, $PitchRowsTable, PitchRow>),
          PitchRow,
          PrefetchHooks Function()
        > {
  $$PitchRowsTableTableManager(_$AppDatabase db, $PitchRowsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PitchRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PitchRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PitchRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> season = const Value.absent(),
                Value<int> matchIdx = const Value.absent(),
                Value<int> seq = const Value.absent(),
                Value<int> paIndex = const Value.absent(),
                Value<int> pitchNo = const Value.absent(),
                Value<bool> battingHome = const Value.absent(),
                Value<String> batter = const Value.absent(),
                Value<String> batterHand = const Value.absent(),
                Value<String> pitcher = const Value.absent(),
                Value<String> pitchName = const Value.absent(),
                Value<double> speed = const Value.absent(),
                Value<double> x = const Value.absent(),
                Value<double> z = const Value.absent(),
                Value<bool> inZone = const Value.absent(),
                Value<int> balls = const Value.absent(),
                Value<int> strikes = const Value.absent(),
                Value<String> result = const Value.absent(),
                Value<String> contact = const Value.absent(),
                Value<double?> landX = const Value.absent(),
                Value<double?> landY = const Value.absent(),
                Value<double?> launch = const Value.absent(),
                Value<String> fielder = const Value.absent(),
                Value<String> outcome = const Value.absent(),
                Value<String> playCode = const Value.absent(),
                Value<double> breakDX = const Value.absent(),
                Value<double> breakDY = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PitchRowsCompanion(
                season: season,
                matchIdx: matchIdx,
                seq: seq,
                paIndex: paIndex,
                pitchNo: pitchNo,
                battingHome: battingHome,
                batter: batter,
                batterHand: batterHand,
                pitcher: pitcher,
                pitchName: pitchName,
                speed: speed,
                x: x,
                z: z,
                inZone: inZone,
                balls: balls,
                strikes: strikes,
                result: result,
                contact: contact,
                landX: landX,
                landY: landY,
                launch: launch,
                fielder: fielder,
                outcome: outcome,
                playCode: playCode,
                breakDX: breakDX,
                breakDY: breakDY,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int season,
                required int matchIdx,
                required int seq,
                required int paIndex,
                required int pitchNo,
                required bool battingHome,
                required String batter,
                required String batterHand,
                required String pitcher,
                required String pitchName,
                required double speed,
                required double x,
                required double z,
                required bool inZone,
                required int balls,
                required int strikes,
                required String result,
                required String contact,
                Value<double?> landX = const Value.absent(),
                Value<double?> landY = const Value.absent(),
                Value<double?> launch = const Value.absent(),
                required String fielder,
                required String outcome,
                required String playCode,
                required double breakDX,
                required double breakDY,
                Value<int> rowid = const Value.absent(),
              }) => PitchRowsCompanion.insert(
                season: season,
                matchIdx: matchIdx,
                seq: seq,
                paIndex: paIndex,
                pitchNo: pitchNo,
                battingHome: battingHome,
                batter: batter,
                batterHand: batterHand,
                pitcher: pitcher,
                pitchName: pitchName,
                speed: speed,
                x: x,
                z: z,
                inZone: inZone,
                balls: balls,
                strikes: strikes,
                result: result,
                contact: contact,
                landX: landX,
                landY: landY,
                launch: launch,
                fielder: fielder,
                outcome: outcome,
                playCode: playCode,
                breakDX: breakDX,
                breakDY: breakDY,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PitchRowsTable, PitchRow>(table),
                  BaseReferences<_$AppDatabase, $PitchRowsTable, PitchRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PitchRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PitchRowsTable,
      PitchRow,
      $$PitchRowsTableFilterComposer,
      $$PitchRowsTableOrderingComposer,
      $$PitchRowsTableAnnotationComposer,
      $$PitchRowsTableCreateCompanionBuilder,
      $$PitchRowsTableUpdateCompanionBuilder,
      (PitchRow, BaseReferences<_$AppDatabase, $PitchRowsTable, PitchRow>),
      PitchRow,
      PrefetchHooks Function()
    >;
typedef $$ProspectRowsTableCreateCompanionBuilder =
    ProspectRowsCompanion Function({
      required String id,
      required int sort,
      required String json,
      Value<int> rowid,
    });
typedef $$ProspectRowsTableUpdateCompanionBuilder =
    ProspectRowsCompanion Function({
      Value<String> id,
      Value<int> sort,
      Value<String> json,
      Value<int> rowid,
    });

class $$ProspectRowsTableFilterComposer
    extends Composer<_$AppDatabase, $ProspectRowsTable> {
  $$ProspectRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sort => $composableBuilder(
    column: $table.sort,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ProspectRowsTableOrderingComposer
    extends Composer<_$AppDatabase, $ProspectRowsTable> {
  $$ProspectRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sort => $composableBuilder(
    column: $table.sort,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ProspectRowsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ProspectRowsTable> {
  $$ProspectRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get sort =>
      $composableBuilder(column: $table.sort, builder: (column) => column);

  GeneratedColumn<String> get json =>
      $composableBuilder(column: $table.json, builder: (column) => column);
}

class $$ProspectRowsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ProspectRowsTable,
          ProspectRow,
          $$ProspectRowsTableFilterComposer,
          $$ProspectRowsTableOrderingComposer,
          $$ProspectRowsTableAnnotationComposer,
          $$ProspectRowsTableCreateCompanionBuilder,
          $$ProspectRowsTableUpdateCompanionBuilder,
          (
            ProspectRow,
            BaseReferences<_$AppDatabase, $ProspectRowsTable, ProspectRow>,
          ),
          ProspectRow,
          PrefetchHooks Function()
        > {
  $$ProspectRowsTableTableManager(_$AppDatabase db, $ProspectRowsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProspectRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProspectRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProspectRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<int> sort = const Value.absent(),
                Value<String> json = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProspectRowsCompanion(
                id: id,
                sort: sort,
                json: json,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required int sort,
                required String json,
                Value<int> rowid = const Value.absent(),
              }) => ProspectRowsCompanion.insert(
                id: id,
                sort: sort,
                json: json,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ProspectRowsTable, ProspectRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $ProspectRowsTable,
                    ProspectRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ProspectRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ProspectRowsTable,
      ProspectRow,
      $$ProspectRowsTableFilterComposer,
      $$ProspectRowsTableOrderingComposer,
      $$ProspectRowsTableAnnotationComposer,
      $$ProspectRowsTableCreateCompanionBuilder,
      $$ProspectRowsTableUpdateCompanionBuilder,
      (
        ProspectRow,
        BaseReferences<_$AppDatabase, $ProspectRowsTable, ProspectRow>,
      ),
      ProspectRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$KvEntriesTableTableManager get kvEntries =>
      $$KvEntriesTableTableManager(_db, _db.kvEntries);
  $$TeamRowsTableTableManager get teamRows =>
      $$TeamRowsTableTableManager(_db, _db.teamRows);
  $$MatchRowsTableTableManager get matchRows =>
      $$MatchRowsTableTableManager(_db, _db.matchRows);
  $$SeasonRecordsTableTableManager get seasonRecords =>
      $$SeasonRecordsTableTableManager(_db, _db.seasonRecords);
  $$PitchRowsTableTableManager get pitchRows =>
      $$PitchRowsTableTableManager(_db, _db.pitchRows);
  $$ProspectRowsTableTableManager get prospectRows =>
      $$ProspectRowsTableTableManager(_db, _db.prospectRows);
}
