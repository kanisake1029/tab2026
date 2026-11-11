import 'package:flutter/material.dart';
import '../providers/app_state.dart';
import '../models/team.dart';
import '../utils/standings.dart';

const _ink = Color(0xFF1C1917);
const _sub = Color(0xFF78716C);
const _line = Color(0xFFE7E5E4);

/// リーグ編成：Aリーグ・Bリーグに6球団ずつ。枠をタップして球団を選ぶ（ほかのリーグにいる球団を選ぶと入れ替え）
class SettingsScreen extends StatefulWidget {
  final AppState appState;
  /// 設定・編集メニューの右側に埋め込むときは true（戻るボタンを出さない）
  final bool embedded;
  /// 画面の一部として中身だけ出す（はじめの手順）。変えたら onChanged
  final bool bare;
  final VoidCallback? onChanged;
  const SettingsScreen({Key? key, required this.appState, this.embedded = false, this.bare = false, this.onChanged}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  AppState get app => widget.appState;

  @override
  Widget build(BuildContext context) {
    final cl = app.teams.where((t) => t.league == 'CL').toList();
    final pl = app.teams.where((t) => t.league == 'PL').toList();
    final free = app.teams.where((t) => t.league != 'CL' && t.league != 'PL').toList();
    final ok = cl.length == 6 && pl.length == 6;
    final body = LayoutBuilder(builder: (context, c) {
        final wide = c.maxWidth >= 720;
        final a = _league('Aリーグ', 'CL', cl, const Color(0xFF16A34A));
        final b = _league('Bリーグ', 'PL', pl, const Color(0xFF2563EB));
        final children = <Widget>[
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: ok ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(8)),
            child: Text(
              ok ? '両リーグとも6球団がそろっています' : 'Aリーグ ${cl.length}/6・Bリーグ ${pl.length}/6 球団。枠をタップして球団を入れてください',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 10),
          if (wide) Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: a), const SizedBox(width: 12), Expanded(child: b)]) else ...[a, const SizedBox(height: 12), b],
          const SizedBox(height: 14),
          Text('未所属の球団（${free.length}）', style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          if (free.isEmpty) const Text('ありません（「初期選手編集」で新しい球団を作れます）', style: TextStyle(fontSize: 12, color: _sub)),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final t in free) Chip(avatar: CircleAvatar(backgroundColor: teamColor(app.teams, t), radius: 6), label: Text(t.name, style: const TextStyle(fontSize: 12))),
          ]),
        ];
        if (widget.bare) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
        return ListView(padding: const EdgeInsets.fromLTRB(12, 10, 12, 24), children: children);
      });
    if (widget.bare) return body;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F4),
      appBar: AppBar(title: const Text('リーグ編成'), automaticallyImplyLeading: !widget.embedded),
      body: body,
    );
  }

  Widget _league(String title, String code, List<Team> ts, Color color) => Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: _line)),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            color: color,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text('$title　${ts.length}/6', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
          ),
          for (var i = 0; i < 6; i++) _slot(code, i, i < ts.length ? ts[i] : null),
        ]),
      );

  Widget _slot(String code, int i, Team? t) => InkWell(
        onTap: () => _pick(code, t),
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: _line))),
          child: Row(children: [
            SizedBox(width: 22, child: Text('${i + 1}', style: const TextStyle(color: _sub, fontWeight: FontWeight.w700))),
            if (t != null) ...[
              Container(width: 6, height: 30, color: teamColor(app.teams, t)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, color: _ink)),
                  Text('${t.year > 0 ? '${t.year}年・' : ''}${t.players.where((p) => !p.ikusei).length}人', style: const TextStyle(fontSize: 11, color: _sub)),
                ]),
              ),
              const Icon(Icons.swap_horiz, color: _sub, size: 20),
            ] else
              const Expanded(child: Text('空き枠（タップして球団を選ぶ）', style: TextStyle(color: _sub))),
          ]),
        ),
      );

  /// 枠に入れる球団を選ぶ（ほかのリーグの球団なら入れ替え）
  Future<void> _pick(String code, Team? current) async {
    var q = '';
    final picked = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        final list = app.teams.where((t) => t != current && (q.isEmpty || t.name.contains(q))).toList()
          ..sort((a, b) => (a.league == code ? 2 : (a.league.isEmpty ? 0 : 1)).compareTo(b.league == code ? 2 : (b.league.isEmpty ? 0 : 1)));
        return SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.75,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Row(children: [
                Expanded(child: Text(current == null ? '枠に入れる球団を選ぶ' : '${current.name} と入れ替える球団を選ぶ', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15))),
                if (current != null) TextButton(onPressed: () => Navigator.pop(ctx, 'clear'), child: const Text('枠を空ける', style: TextStyle(color: Colors.red))),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                decoration: const InputDecoration(isDense: true, prefixIcon: Icon(Icons.search, size: 20), hintText: '球団名で探す', border: OutlineInputBorder()),
                onChanged: (s) => set(() => q = s),
              ),
            ),
            Expanded(
              child: ListView(children: [
                for (final t in list)
                  ListTile(
                    dense: true,
                    leading: CircleAvatar(backgroundColor: teamColor(app.teams, t), radius: 8),
                    title: Text(t.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text('${t.year > 0 ? '${t.year}年　' : ''}${t.league == 'CL' ? 'Aリーグ' : t.league == 'PL' ? 'Bリーグ' : '未所属'}${t.league.isNotEmpty && t.league != code ? '（入れ替え）' : (t.league == code ? '（同じリーグ）' : '')}'),
                    onTap: () => Navigator.pop(ctx, t),
                  ),
              ]),
            ),
          ]),
        );
      }),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (picked == 'clear') {
        current?.league = '';
      } else if (picked is Team) {
        final from = picked.league;
        picked.league = code;
        // 選んだ球団がいた枠には、今の球団を入れる（入れ替え）。未所属から選んだなら今の球団は未所属へ
        if (current != null) current.league = from == code ? code : from;
      }
    });
    app.updateAndSave();
    widget.onChanged?.call();
  }
}
