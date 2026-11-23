import 'package:flutter/material.dart';
import '../models/player.dart';
import '../providers/app_state.dart';
import '../utils/standings.dart';
import '../widgets/player_detail_dialog.dart' show showPlayerDetail;

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
const _line = Color(0xFFE2E8F0);

class _AwardsScreenState extends State<AwardsScreen> {
  String _lg = 'CL';
  late final Future<Map<String, dynamic>?> _future = widget.appState.loadAwards(widget.year);

  AppState get app => widget.appState;

  static const _pitTitles = {'最優秀防御率', '最多勝利', '最多奪三振', '最高勝率', '最多セーブ', '最優秀中継ぎ'};

  Player? _findPlayer({String? id, String? name}) {
    final all = <Player>[
      for (final t in app.teams) ...t.players,
      for (final fa in app.freeAgents) fa.player,
    ];
    if (id != null && id.isNotEmpty) {
      final byId = all.where((p) => p.id == id).firstOrNull;
      if (byId != null) return byId;
    }
    if (name != null && name.isNotEmpty) {
      final clean = name.split('（').first.trim();
      return all.where((p) => p.registeredName == clean || p.listName == clean).firstOrNull;
    }
    return null;
  }

  String _teamName(String? id) {
    if (id == null || id.isEmpty) return '-';
    final t = app.teamById(id);
    return t == null ? id : teamShort(t);
  }

  /// 賞の種別ごとの色付きタグ（背景・枠線・文字色）
  (Color, Color, Color) _tagPalette(String kind) => switch (kind) {
        'major' => (const Color(0xFFFEF3C7), const Color(0xFFF59E0B), const Color(0xFFB45309)),
        'special' => (const Color(0xFFDCFCE7), const Color(0xFF34D399), const Color(0xFF166534)),
        'batTitle' => (const Color(0xFFFFFBEB), const Color(0xFFFBBF24), const Color(0xFF92400E)),
        'pitTitle' => (const Color(0xFFEFF6FF), const Color(0xFF60A5FA), const Color(0xFF1E40AF)),
        'b9' => (const Color(0xFFF3E8FF), const Color(0xFFC084FC), const Color(0xFF6B21A8)),
        'gg' => (const Color(0xFFFEF9C3), const Color(0xFFEAB308), const Color(0xFF854D0E)),
        'event' => (const Color(0xFFFFE4E6), const Color(0xFFFB7185), const Color(0xFF9F1239)),
        _ => (const Color(0xFFF1F5F9), const Color(0xFFCBD5E1), const Color(0xFF334155)),
      };

  Widget _tag(String label, String kind, {double? width, IconData? icon}) {
    final (bg, border, fg) = _tagPalette(kind);
    final inner = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[Icon(icon, size: 12, color: fg), const SizedBox(width: 3)],
        Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, color: fg))),
      ],
    );
    return Container(
      width: width,
      alignment: width != null ? Alignment.center : null,
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: border),
      ),
      child: inner,
    );
  }

  Widget _card(String title, List<Widget> children, {Widget? trailing, IconData? icon, Color accent = _gold}) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _line),
          boxShadow: const [BoxShadow(color: Color(0x08000000), blurRadius: 8, offset: Offset(0, 2))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(width: 4, height: 16, decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 8),
            if (icon != null) ...[Icon(icon, size: 17, color: accent), const SizedBox(width: 5)],
            Expanded(child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: _navy))),
            if (trailing != null) trailing,
          ]),
          const SizedBox(height: 10),
          ...children,
        ]),
      );

  /// 受賞者1人分のタップ可能なチップ／テキスト
  Widget _winnerLink(Map w, {bool bold = true, double fontSize = 13.5}) {
    final p = _findPlayer(id: '${w['id'] ?? ''}', name: '${w['name'] ?? ''}');
    final t = app.teamById('${w['team'] ?? ''}');
    final label = '${w['name']}（${w['teamName']}）';
    final child = Row(mainAxisSize: MainAxisSize.min, children: [
      if (t != null) ...[
        Container(width: 3, height: 13, decoration: BoxDecoration(color: teamColor(app.teams, t), borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 5),
      ],
      Flexible(
        child: Text(
          label,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
            color: _navy,
            decoration: p != null ? TextDecoration.underline : null,
            decorationColor: const Color(0xFFCBD5E1),
          ),
        ),
      ),
    ]);
    if (p == null) return child;
    return InkWell(
      onTap: () => showPlayerDetail(context, app, p, allowActions: false),
      borderRadius: BorderRadius.circular(4),
      child: Padding(padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2), child: child),
    );
  }

  Widget _winnersWidget(dynamic winners) {
    if (winners is! List || winners.isEmpty) {
      return const Text('該当者なし', style: TextStyle(fontSize: 13, color: _sub));
    }
    if (winners.length == 1 && winners.first is Map) {
      return _winnerLink(winners.first as Map);
    }
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [for (final w in winners.whereType<Map>()) _winnerLink(w)],
    );
  }

  Widget _titleRow(String label, dynamic winners, String value, {required String kind}) => Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9)))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          _tag(label, kind, width: 96),
          const SizedBox(width: 10),
          Expanded(child: _winnersWidget(winners)),
          if (value.isNotEmpty) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(5), border: Border.all(color: _line)),
              child: Text(value, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: _navy, fontFeatures: [FontFeature.tabularFigures()])),
            ),
          ],
        ]),
      );

  /// 沢村賞・カムバック賞・球宴MVPなど成績文字列が長い特別表彰カード（名前が縦に潰れない2段レイアウト）
  Widget _specialAwardTile({
    required String label,
    required String kind,
    required Map<String, dynamic>? data,
    String? fallbackText,
    IconData? icon,
  }) {
    final none = data == null || data['none'] == true;
    final val = data?['value'] as String? ?? '';
    final met = data?['met'];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: BoxDecoration(
        color: none ? const Color(0xFFF8FAFC) : const Color(0xFFFFFBEB).withValues(alpha: kind == 'major' ? 0.55 : 0.0),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: !none && kind == 'major' ? const Color(0xFFFDE68A) : _line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _tag(label, kind, width: 96, icon: icon),
          const SizedBox(width: 10),
          Expanded(
            child: none
                ? Text(fallbackText ?? '該当者なし', style: const TextStyle(fontSize: 13, color: _sub))
                : _winnerLink(data, fontSize: 14.5),
          ),
          if (!none && met != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(4)),
              child: Text('基準$met項目達成', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: _gold)),
            ),
        ]),
        if (!none && val.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(6), border: Border.all(color: _line)),
              child: Text(val, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFF334155), fontFeatures: [FontFeature.tabularFigures()])),
            ),
          ),
      ]),
    );
  }

  /// 投票の結果（1位を大きく強調＋2位〜4位と得票数）
  Widget _voteBlock(String title, String kind, Map<String, dynamic>? v) {
    final ranking = (v?['ranking'] as List?) ?? const [];
    final top = ranking.isNotEmpty && ranking.first is Map ? ranking.first as Map : null;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          _tag(title, kind, icon: kind == 'major' ? Icons.emoji_events : Icons.auto_awesome),
          const SizedBox(width: 8),
          Expanded(
            child: top == null
                ? const Text('該当者なし', style: TextStyle(fontSize: 13, color: _sub))
                : _winnerLink(top, fontSize: 15),
          ),
          if (top != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(5), border: Border.all(color: const Color(0xFFFCD34D))),
              child: Text('${top['votes']}票', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: _gold, fontFeatures: [FontFeature.tabularFigures()])),
            ),
        ]),
        if (ranking.length > 1) ...[
          const Divider(height: 14, color: _line),
          for (var i = 1; i < ranking.length; i++)
            if (ranking[i] is Map)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2.5),
                child: Row(children: [
                  SizedBox(width: 24, child: Text('${i + 1}位', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: _sub))),
                  Expanded(child: _winnerLink(ranking[i] as Map, bold: false, fontSize: 13)),
                  Text('${ranking[i]['votes']}票', style: const TextStyle(fontSize: 12, color: _sub, fontFeatures: [FontFeature.tabularFigures()])),
                ]),
              ),
        ],
      ]),
    );
  }

  Widget _posList(List? items, {required String kind}) {
    const posLabel = {'投': '投手', '捕': '捕手', '一': '一塁手', '二': '二塁手', '三': '三塁手', '遊': '遊撃手', '外': '外野手', 'DH': '指名打者'};
    final rows = <Widget>[];
    for (final b in items ?? const []) {
      final pos = posLabel[b['pos']] ?? '${b['pos']}';
      final ws = (b['winners'] as List?) ?? const [];
      if (ws.isEmpty) {
        rows.add(_titleRow(pos, const [], '', kind: kind));
        continue;
      }
      for (final w in ws) {
        if (w is Map) rows.add(_titleRow(pos, [w], '${w['votes']}票', kind: kind));
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
  }

  Widget _nameOrPlain(String raw) {
    final p = _findPlayer(name: raw);
    if (p == null) return Text(raw, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: _navy));
    return InkWell(
      onTap: () => showPlayerDetail(context, app, p, allowActions: false),
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text(raw, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: _navy, decoration: TextDecoration.underline, decorationColor: Color(0xFFCBD5E1))),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(backgroundColor: _navy, foregroundColor: Colors.white, title: Text('${widget.year}年 表彰・タイトル発表', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900))),
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
          final allStarMvps = (aw['allStarMvp'] as List?) ?? const [];
          return ListView(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 30),
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFF0B1626), Color(0xFF1E293B)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF334155)),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        _tag('日本一', 'major', icon: Icons.emoji_events),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${widget.year} SEASON CHAMPIONS',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: _lime, fontSize: 11, letterSpacing: 1.5, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 8),
                      Text(aw['champion'] == null ? '−' : (app.teamById(aw['champion'] as String)?.name ?? '-'), style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 8),
                      Text('リーグ優勝　Aリーグ：${_teamName(leagues['CL']?['pennant'] as String?)}　／　Bリーグ：${_teamName(leagues['PL']?['pennant'] as String?)}', style: const TextStyle(color: Color(0xFFB8C6D8), fontSize: 13)),
                    ]),
                  ),
                  if (series.isNotEmpty)
                    _card('ポストシーズン', [
                      for (final s in series)
                        Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                          decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(8), border: Border.all(color: _line)),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${s['label']}', style: const TextStyle(fontSize: 11.5, color: _sub, fontWeight: FontWeight.w800)),
                            const SizedBox(height: 2),
                            Text('${_teamName(s['winner'] as String?)}が勝ち抜け（${_teamName(s['high'] as String?)} 対 ${_teamName(s['low'] as String?)}：${s['score'] ?? ''}）', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
                            if ((s['mvp'] as String? ?? '').isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Row(children: [
                                  _tag('シリーズMVP', 'event', icon: Icons.star),
                                  const SizedBox(width: 8),
                                  Expanded(child: _nameOrPlain('${s['mvp']}')),
                                ]),
                              ),
                          ]),
                        ),
                    ], icon: Icons.military_tech, accent: const Color(0xFF9F1239)),
                  _card('両リーグ特別表彰', [
                    _specialAwardTile(label: '沢村賞', kind: 'major', data: saw, icon: Icons.emoji_events),
                    _specialAwardTile(label: 'カムバック賞', kind: 'special', data: cb, icon: Icons.trending_up),
                    for (final (i, m) in allStarMvps.indexed)
                      Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                        decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(8), border: Border.all(color: _line)),
                        child: Row(children: [
                          _tag('球宴MVP 第${i + 1}戦', 'event', width: 108),
                          const SizedBox(width: 10),
                          Expanded(child: _nameOrPlain('$m')),
                        ]),
                      ),
                  ], icon: Icons.workspace_premium, accent: _gold),
                  SegmentedButton<String>(
                    segments: const [ButtonSegment(value: 'CL', label: Text('Aリーグ')), ButtonSegment(value: 'PL', label: Text('Bリーグ'))],
                    selected: {_lg},
                    showSelectedIcon: false,
                    style: SegmentedButton.styleFrom(selectedBackgroundColor: _navy, selectedForegroundColor: _lime, backgroundColor: Colors.white),
                    onSelectionChanged: (v) => setState(() => _lg = v.first),
                  ),
                  const SizedBox(height: 14),
                  if (L != null) ...[
                    _card('MVP・最優秀新人（記者300人の投票）', [
                      _voteBlock('最優秀選手（MVP）', 'major', (L['mvp'] as Map?)?.cast<String, dynamic>()),
                      _voteBlock('最優秀新人', 'special', (L['rookie'] as Map?)?.cast<String, dynamic>()),
                    ], icon: Icons.emoji_events, accent: _gold),
                    _card('個人タイトル', [
                      for (final t in (L['titles'] as List? ?? const []))
                        _titleRow(
                          '${t['title']}',
                          t['winners'],
                          '${t['value']}',
                          kind: _pitTitles.contains('${t['title']}') ? 'pitTitle' : 'batTitle',
                        ),
                      const SizedBox(height: 6),
                      Text('規定打席 ${L['qualifiedPa']}・規定投球回 ${L['qualifiedIp']}（チーム${L['games']}試合）。最高勝率は14勝以上。最優秀中継ぎはホールドポイントで判定。選手名をタップすると詳細を開けます',
                          style: const TextStyle(fontSize: 11, color: _sub)),
                    ], icon: Icons.stars, accent: const Color(0xFF1E40AF)),
                    _card('ベストナイン', [_posList(L['b9'] as List?, kind: 'b9')],
                        icon: Icons.groups, accent: const Color(0xFF6B21A8), trailing: const Text('得票数／300', style: TextStyle(fontSize: 11, color: _sub))),
                    _card('ゴールデングラブ賞', [_posList(L['gg'] as List?, kind: 'gg')],
                        icon: Icons.shield, accent: const Color(0xFF854D0E), trailing: const Text('得票数／300', style: TextStyle(fontSize: 11, color: _sub))),
                  ],
                ]),
              ),
            ],
          );
        },
      ),
    );
  }
}
