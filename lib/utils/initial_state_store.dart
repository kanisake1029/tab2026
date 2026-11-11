import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// 球団の「初期状態」：新しいデータ（はじめから）はこの状態から始める。
///  プレイデータ1〜3のどれからも使えるよう、枠の外（アプリの書類フォルダ）に球団ごとに置く
class InitialStateStore {
  InitialStateStore._();
  static final instance = InitialStateStore._();

  /// ファイルが使えないとき（テストなど）はメモリに置く
  final Map<String, String> _mem = {};
  Directory? _dir;
  bool _noFiles = false;

  Future<Directory?> _folder() async {
    if (_noFiles) return null;
    if (_dir != null) return _dir;
    try {
      final d = Directory('${(await getApplicationDocumentsDirectory()).path}/initial_teams');
      if (!await d.exists()) await d.create(recursive: true);
      return _dir = d;
    } catch (_) {
      _noFiles = true;
      return null;
    }
  }

  String _safe(String id) => id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

  /// 球団の初期状態を保存（同じ球団は上書き）
  Future<void> save(String teamId, Map<String, dynamic> json) async {
    final s = jsonEncode(json);
    _mem[teamId] = s;
    final d = await _folder();
    if (d != null) await File('${d.path}/${_safe(teamId)}.json').writeAsString(s);
  }

  Future<void> remove(String teamId) async {
    _mem.remove(teamId);
    final d = await _folder();
    if (d == null) return;
    final f = File('${d.path}/${_safe(teamId)}.json');
    if (await f.exists()) await f.delete();
  }

  /// すべての初期状態（球団ID → 球団のデータ）
  Future<Map<String, Map<String, dynamic>>> loadAll() async {
    final out = <String, Map<String, dynamic>>{};
    final d = await _folder();
    if (d != null) {
      await for (final f in d.list()) {
        if (f is! File || !f.path.endsWith('.json')) continue;
        try {
          final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
          final id = j['id'] as String?;
          if (id != null) out[id] = j;
        } catch (_) {}
      }
    }
    for (final e in _mem.entries) {
      out.putIfAbsent(e.key, () => jsonDecode(e.value) as Map<String, dynamic>);
    }
    return out;
  }
}
