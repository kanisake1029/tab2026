import '../widgets/chip_grid.dart';
import 'package:flutter/material.dart';
import '../providers/app_state.dart';
import '../utils/news_kind.dart';
import '../widgets/player_avatar.dart';

/// お知らせの記録（過去3年）。年ごと・新しい順。言葉で絞り込める
///  表示：時系列（日付ごと）／種類別（怪我・提案・天候・登録・記録・経営…の絞り込みと折りたたみ）
class NewsArchiveScreen extends StatefulWidget {
  final AppState app;
  const NewsArchiveScreen({super.key, required this.app});
  @override
  State<NewsArchiveScreen> createState() => _NewsArchiveScreenState();
}

class _NewsArchiveScreenState extends State<NewsArchiveScreen> {
  late int _year = widget.app.currentDate.year;
  String _q = '';
  bool _byKind = true;
  NewsKind? _only; // 種類の絞り込み（null＝すべて）
  final Set<String> _open = {'怪我', '提案', '天候'}; // 開いている種類

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final years = [for (var y = app.currentDate.year; y >= app.currentDate.year - 2; y--) y];
    final list = (app.newsLog[_year] ?? const <String>[]).where((n) => _q.isEmpty || n.contains(_q)).toList();
    final kinds = {for (final k in NewsKind.all) k.name: <(String, String)>[]};
    for (final n in list) {
      final (d, t) = NewsKind.split(n);
      kinds[NewsKind.of(t).name]!.add((d, t));
    }
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F4),
      appBar: AppBar(title: const Text('お知らせ（過去3年）')),
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: Wrap(spacing: 10, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SegmentedButton<int>(
              segments: [for (final y in years) ButtonSegment(value: y, label: Text('$y年'))],
              selected: {_year},
              showSelectedIcon: false,
              onSelectionChanged: (v) => setState(() => _year = v.first),
            ),
            SegmentedButton<bool>(
              segments: const [ButtonSegment(value: false, label: Text('時系列')), ButtonSegment(value: true, label: Text('種類別'))],
              selected: {_byKind},
              showSelectedIcon: false,
              onSelectionChanged: (v) => setState(() => _byKind = v.first),
            ),
            SizedBox(width: 160, child: TextField(decoration: const InputDecoration(isDense: true, hintText: '言葉で絞り込む', prefixIcon: Icon(Icons.search, size: 18)), onChanged: (v) => setState(() => _q = v.trim()))),
          ]),
        ),
        if (_byKind)
          ChipGrid<String>(
            items: [('', 'すべて ${list.length}'), for (final k in NewsKind.all) if (kinds[k.name]!.isNotEmpty) (k.name, '${k.name} ${kinds[k.name]!.length}')],
            selected: _only?.name ?? '',
            minWidth: 84,
            onSelect: (n) => setState(() {
              _only = n.isEmpty || _only?.name == n ? null : NewsKind.all.firstWhere((k) => k.name == n);
              if (_only != null) _open.add(_only!.name);
            }),
          ),
        Expanded(
          child: list.isEmpty
              ? const Center(child: Text('この年のお知らせはありません（記録はこの機能を入れた後から残ります）', style: TextStyle(color: Color(0xFF78716C))))
              : _byKind
                  ? _kindView(kinds)
                  : _timeView(list),
        ),
      ]),
    );
  }

  /// 時系列：日付ごとの見出しと、種類の色アイコン
  Widget _timeView(List<String> list) {
    final rows = <Widget>[];
    final everyone = [for (final t in widget.app.teams) ...t.players];
    var last = '\u0000';
    for (final n in list) {
      final (d, t) = NewsKind.split(n);
      if (d != last) {
        rows.add(Padding(padding: const EdgeInsets.fromLTRB(0, 10, 0, 2), child: Text(d.isEmpty ? 'そのほか' : '${d.replaceFirst('/', '月')}日', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF64748B)))));
        last = d;
      }
      final k = NewsKind.of(t);
      rows.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Builder(builder: (_) {
            final who = playerInText(t, everyone);
            return who == null ? k.tile(size: 26) : PlayerAvatar(who, size: 26);
          }),
          const SizedBox(width: 8),
          Expanded(child: Text(t, style: const TextStyle(fontSize: 12.5, height: 1.45, color: Color(0xFF292524)))),
        ]),
      ));
    }
    return ListView(padding: const EdgeInsets.fromLTRB(14, 0, 14, 24), children: rows);
  }

  /// 種類別：種類ごとに件数と最新の日付、タップで開く・閉じる
  Widget _kindView(Map<String, List<(String, String)>> kinds) {
    final shown = [for (final k in NewsKind.all) if (kinds[k.name]!.isNotEmpty && (_only == null || _only == k)) k];
    return ListView(padding: const EdgeInsets.fromLTRB(12, 4, 12, 24), children: [
      for (final k in shown)
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => setState(() => _open.contains(k.name) ? _open.remove(k.name) : _open.add(k.name)),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(children: [
                  k.tile(size: 28),
                  const SizedBox(width: 10),
                  Text(k.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
                  const SizedBox(width: 8),
                  Text('${kinds[k.name]!.length}件・最新 ${kinds[k.name]!.first.$1}', style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                  const Spacer(),
                  Icon(_open.contains(k.name) ? Icons.expand_less : Icons.expand_more, color: const Color(0xFF64748B)),
                ]),
              ),
            ),
            if (_open.contains(k.name))
              for (final (d, t) in kinds[k.name]!)
                Container(
                  padding: const EdgeInsets.fromLTRB(48, 6, 12, 6),
                  decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFF1F5F9)))),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(width: 40, child: Text(d, style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)))),
                    Expanded(child: Text(t, style: const TextStyle(fontSize: 12.5, height: 1.45))),
                  ]),
                ),
          ]),
        ),
    ]);
  }
}
