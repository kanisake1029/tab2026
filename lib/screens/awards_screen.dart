import 'package:flutter/material.dart';
import '../providers/app_state.dart';
import '../utils/standings.dart';

/// 年間の表彰（優勝・日本シリーズ・タイトル・MVP・新人王・ベストナイン・ゴールデングラブ・沢村賞など）
class AwardsScreen extends StatefulWidget {
  final AppState appState;
  final int year;
  const AwardsScreen({super.key, required this.appState, required this.year});

  @override
  State<AwardsScreen> createState() => _AwardsScreenState();
}

const _navy = Color(0xFF0B1626);
const _lime = Color(0xFFC6F24E);
const _bg = Color(0xFFEEF1F5);
const _sub = Color(0xFF64748B);
const _gold = Color(0xFFB45309);

class _AwardsScreenState extends State<AwardsScreen> {
  String _lg = 'CL';
  late final Future<Map<String, dynamic>?> _future = widget.appState.loadAwards(widget.year);

  AppState get app => widget.appState;

  String _teamName(String? id) {
    if (id == null || id.isEmpty) return '-';
    final t = app.teamById(id);
    return t == null ? id : teamShort(t);
  }

  Widget _card(String title, List<Widget> children, {Widget? trailing}) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [Expanded(child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900))), if (trailing != null) trailing]),
          const SizedBox(height: 8),
          ...children,
        ]),
      );

  String _names(dynamic winners) {
    if (winners is! List || winners.isEmpty) return '該当者なし';
    return winners.map((w) => '${w['name']}（${w['teamName']}）').join('・');
  }

  Widget _row(String label, String name, String value, {Color? labelColor}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 104, child: Text(label, style: TextStyle(fontSize: 13, color: labelColor ?? _sub, fontWeight: FontWeight.w700))),
          Expanded(child: Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
          const SizedBox(width: 8),
          Text(value, style: const TextStyle(fontSize: 13, color: _sub, fontFeatures: [FontFeature.tabularFigures()])),
        ]),
      );

  /// 投票の結果（1位〜4位と得票数）
  Widget _voteBlock(String title, Map<String, dynamic>? v) {
    final ranking = (v?['ranking'] as List?) ?? const [];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(title, style: const TextStyle(fontSize: 13, color: _gold, fontWeight: FontWeight.w900)),
      if (ranking.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 4), child: Text('該当者なし', style: TextStyle(color: _sub))),
      for (var i = 0; i < ranking.length; i++)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            SizedBox(width: 24, child: Text('${i + 1}', style: TextStyle(fontWeight: FontWeight.w900, color: i == 0 ? _gold : _sub))),
            Expanded(child: Text('${ranking[i]['name']}（${ranking[i]['teamName']}）', style: TextStyle(fontSize: 13.5, fontWeight: i == 0 ? FontWeight.w800 : FontWeight.w400))),
            Text('${ranking[i]['votes']}票', style: const TextStyle(fontSize: 12.5, color: _sub)),
          ]),
        ),
      const SizedBox(height: 8),
    ]);
  }

  Widget _posList(List? items) {
    const posLabel = {'投': '投手', '捕': '捕手', '一': '一塁手', '二': '二塁手', '三': '三塁手', '遊': '遊撃手', '外': '外野手', 'DH': '指名打者'};
    final rows = <Widget>[];
    for (final b in items ?? const []) {
      final ws = (b['winners'] as List?) ?? const [];
      if (ws.isEmpty) {
        rows.add(_row(posLabel[b['pos']] ?? '${b['pos']}', '該当者なし', ''));
        continue;
      }
      for (final w in ws) {
        rows.add(_row(posLabel[b['pos']] ?? '${b['pos']}', '${w['name']}（${w['teamName']}）', '${w['votes']}票'));
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(backgroundColor: _navy, foregroundColor: Colors.white, title: Text('${widget.year}年 表彰・記録', style: const TextStyle(color: Colors.white))),
      body: FutureBuilder<Map<String, dynamic>?>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          final aw = snap.data;
          if (aw == null) return const Center(child: Text('この年の表彰はまだありません', style: TextStyle(color: _sub)));
          final leagues = (aw['leagues'] as Map?) ?? const {};
          final L = (leagues[_lg] as Map?)?.cast<String, dynamic>();
          final series = (aw['series'] as List?) ?? const [];
          final saw = (aw['sawamura'] as Map?)?.cast<String, dynamic>();
          final cb = (aw['comeback'] as Map?)?.cast<String, dynamic>();
          return ListView(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 30),
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(color: _navy, borderRadius: BorderRadius.circular(14)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('日本一', style: TextStyle(color: _lime, fontSize: 12, letterSpacing: 2, fontWeight: FontWeight.w700)),
                      Text(aw['champion'] == null ? '−' : (app.teamById(aw['champion'] as String)?.name ?? '-'), style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 8),
                      Text('リーグ優勝　Aリーグ：${_teamName(leagues['CL']?['pennant'] as String?)}　／　Bリーグ：${_teamName(leagues['PL']?['pennant'] as String?)}', style: const TextStyle(color: Color(0xFFB8C6D8), fontSize: 13)),
                    ]),
                  ),
                  if (series.isNotEmpty)
                    _card('ポストシーズン', [
                      for (final s in series)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${s['label']}', style: const TextStyle(fontSize: 12, color: _sub, fontWeight: FontWeight.w700)),
                            Text('${_teamName(s['winner'] as String?)}が勝ち抜け（${_teamName(s['high'] as String?)} 対 ${_teamName(s['low'] as String?)}：${s['score'] ?? ''}）', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                            if ((s['mvp'] as String? ?? '').isNotEmpty) Text('MVP　${s['mvp']}', style: const TextStyle(fontSize: 12.5, color: _gold)),
                          ]),
                        ),
                    ]),
                  SegmentedButton<String>(
                    segments: const [ButtonSegment(value: 'CL', label: Text('Aリーグ')), ButtonSegment(value: 'PL', label: Text('Bリーグ'))],
                    selected: {_lg},
                    showSelectedIcon: false,
                    style: SegmentedButton.styleFrom(selectedBackgroundColor: _navy, selectedForegroundColor: _lime, backgroundColor: Colors.white),
                    onSelectionChanged: (v) => setState(() => _lg = v.first),
                  ),
                  const SizedBox(height: 14),
                  if (L != null) ...[
                    _card('タイトル', [
                      for (final t in (L['titles'] as List? ?? const [])) _row('${t['title']}', _names(t['winners']), '${t['value']}', labelColor: _navy),
                      const SizedBox(height: 4),
                      Text('規定打席 ${L['qualifiedPa']}・規定投球回 ${L['qualifiedIp']}（チーム${L['games']}試合）。最高勝率は14勝以上。最優秀中継ぎはホールド数で判定', style: const TextStyle(fontSize: 11, color: _sub)),
                    ]),
                    _card('MVP・最優秀新人（記者300人の投票）', [
                      _voteBlock('最優秀選手（MVP）', (L['mvp'] as Map?)?.cast<String, dynamic>()),
                      _voteBlock('最優秀新人', (L['rookie'] as Map?)?.cast<String, dynamic>()),
                    ]),
                    _card('ベストナイン', [_posList(L['b9'] as List?)], trailing: const Text('得票数／300', style: TextStyle(fontSize: 11, color: _sub))),
                    _card('ゴールデングラブ賞', [_posList(L['gg'] as List?)], trailing: const Text('得票数／300', style: TextStyle(fontSize: 11, color: _sub))),
                  ],
                  _card('両リーグ', [
                    _row('沢村賞', saw == null || saw['none'] == true ? '該当者なし' : '${saw['name']}（${saw['teamName']}）', saw?['value'] as String? ?? ''),
                    _row('カムバック賞', cb == null || cb['none'] == true ? '該当者なし' : '${cb['name']}（${cb['teamName']}）', cb?['value'] as String? ?? ''),
                    for (final (i, m) in ((aw['allStarMvp'] as List?) ?? const []).indexed) _row('球宴MVP 第${i + 1}戦', '$m', ''),
                  ]),
                ]),
              ),
            ],
          );
        },
      ),
    );
  }
}
