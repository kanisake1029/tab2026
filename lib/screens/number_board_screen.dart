import 'package:flutter/material.dart';

import '../models/player.dart';
import '../models/team.dart';
import '../providers/app_state.dart';

/// 背番号の一括変更：選手ごとに「来季（2月1日から）の背番号」を入れる
///  入団・移籍したばかりの選手は、重ならなければすぐ変わる。支配下は 00・0〜99、育成は 100〜999
class NumberBoardScreen extends StatefulWidget {
  final AppState app;
  final Team team;
  const NumberBoardScreen({super.key, required this.app, required this.team});

  @override
  State<NumberBoardScreen> createState() => _NumberBoardScreenState();
}

class _NumberBoardScreenState extends State<NumberBoardScreen> {
  late final Map<String, TextEditingController> _ctl = {
    for (final p in widget.team.players) p.id: TextEditingController(text: uniformLabel(widget.app.numberNextSeason(p))),
  };
  String? _err;

  @override
  void dispose() {
    for (final c in _ctl.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// 入力のいま（重なり・決まり違いの選手 id）
  Set<String> _bad() {
    final out = <String>{};
    final by = <int, List<Player>>{};
    for (final p in widget.team.players) {
      final n = parseUniform(_ctl[p.id]!.text);
      if (n == null || widget.app.numberRule(p, n) != null) {
        out.add(p.id);
        continue;
      }
      by.putIfAbsent(n, () => []).add(p);
    }
    for (final l in by.values) {
      if (l.length > 1) out.addAll(l.map((p) => p.id));
    }
    return out;
  }

  void _save() {
    final next = <String, int>{};
    for (final p in widget.team.players) {
      final n = parseUniform(_ctl[p.id]!.text);
      if (n == null) return setState(() => _err = '${p.registeredName}：背番号は 00・0〜999 で入れてください');
      next[p.id] = n;
    }
    final e = widget.app.setNumbersBulk(widget.team, next);
    if (e != null) return setState(() => _err = e);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.app.isOpeningNumberDay || widget.app.isOffseasonNumberFree ? '背番号を変えました' : '背番号を決めました（2月1日から。入団・移籍したばかりの選手はすぐ）')));
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final bad = _bad();
    final list = widget.team.players.toList()
      ..sort((a, b) => a.ikusei != b.ikusei ? (a.ikusei ? 1 : -1) : uniformSortKey(a.uniformNumber).compareTo(uniformSortKey(b.uniformNumber)));
    Widget row(Player p) {
      final free = app.numberFreeNow(p);
      final changed = parseUniform(_ctl[p.id]!.text) != p.uniformNumber;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFE7E5E4)))),
        child: Row(children: [
          SizedBox(width: 44, child: Text('#${p.uniformText}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900))),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(p.listName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800), overflow: TextOverflow.ellipsis),
              Text('${p.isPitcher ? '投手' : p.mainPosition}　${p.age}歳${p.ikusei ? '　育成' : ''}${free && !app.isOpeningNumberDay && !app.isOffseasonNumberFree ? '　入団直後（すぐ変わる）' : (app.isOffseasonNumberFree ? '　オフ期間（すぐ変わる）' : '')}',
                  style: TextStyle(fontSize: 11, color: free ? const Color(0xFF15803D) : const Color(0xFF78716C))),
            ]),
          ),
          const Icon(Icons.arrow_forward, size: 16, color: Color(0xFF78716C)),
          const SizedBox(width: 6),
          SizedBox(
            width: 72,
            child: TextField(
              controller: _ctl[p.id],
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: bad.contains(p.id) ? Colors.red : (changed ? const Color(0xFF1D4ED8) : const Color(0xFF1C1917))),
              decoration: InputDecoration(
                isDense: true,
                prefixText: '#',
                border: const OutlineInputBorder(),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: bad.contains(p.id) ? Colors.red : (changed ? const Color(0xFF1D4ED8) : const Color(0xFFCBD5E1)))),
              ),
              onChanged: (_) => setState(() => _err = null),
            ),
          ),
        ]),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(app.isOpeningNumberDay ? '背番号の一括変更（今日すぐ）' : '背番号の一括変更')),
      body: Column(children: [
        Container(
          width: double.infinity,
          color: const Color(0xFFF0F9FF),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Text(
              app.isOpeningNumberDay
                  ? '今年だけ特別に、今日（開幕日）は全員の背番号をすぐ変えられます（初期の背番号の扱い。背番号の変遷には変更として残りません）。\n支配下は 00・0〜99、育成は 100〜999。赤は重なり・決まり違い、青は変える番号です。'
                  : '右の欄が来季の背番号です。変更は毎年2月1日に行われます（入団・移籍したばかりの選手は、すぐ変わります）。\n支配下は 00・0〜99、育成は 100〜999。赤は重なり・決まり違い、青は変える番号です。',
              style: const TextStyle(fontSize: 12, color: Color(0xFF334155))),
        ),
        Expanded(child: ListView(children: [for (final p in list) row(p)])),
        if (_err != null) Padding(padding: const EdgeInsets.fromLTRB(12, 6, 12, 0), child: Text(_err!, style: const TextStyle(color: Colors.red, fontSize: 12.5))),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(onPressed: bad.isEmpty ? _save : null, child: Text(bad.isEmpty ? '決める' : '重なり・決まり違いが ${bad.length}人あります')),
            ),
          ),
        ),
      ]),
    );
  }
}
