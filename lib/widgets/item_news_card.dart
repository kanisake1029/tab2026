import 'package:flutter/material.dart';
import '../engine/game_news.dart' show FanComment;
import '../engine/item_news.dart';
import '../models/team.dart';
import '../utils/standings.dart';
import 'chip_grid.dart';
import 'player_avatar.dart';

const _ink = Color(0xFF0F172A);
const _sub = Color(0xFF64748B);
const _line = Color(0xFFE2E8F0);

/// 見出しを3つに分ける：小見出し（【】の中・頭の球団名）・主見出し・副見出し（全角の空白のあと）
(String?, String, String?) splitHeadline(String h) {
  String? kicker;
  var rest = h;
  final m = RegExp(r'^【(.+?)】').firstMatch(h);
  if (m != null) {
    kicker = m.group(1);
    rest = h.substring(m.end).trim();
  }
  final parts = rest.split('　').where((x) => x.trim().isNotEmpty).toList();
  if (parts.isEmpty) return (kicker, h, null);
  if (parts.length >= 3 && parts.first.length <= 8) {
    kicker = kicker == null ? parts.first : '$kicker・${parts.first}';
    parts.removeAt(0);
  }
  return (kicker, parts.first, parts.length > 1 ? parts.sublist(1).join('　') : null);
}

/// 見出しの表示（小見出し・主見出し・副見出し）
Widget headlineView(String h, {required double size, Color kickerColor = const Color(0xFFDC2626), int? maxLines}) {
  final (k, main, sub) = splitHeadline(h);
  return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
    if (k != null) Text(k, style: TextStyle(fontSize: size * 0.68, fontWeight: FontWeight.w800, color: kickerColor, height: 1.3)),
    Text(main, maxLines: maxLines, overflow: maxLines == null ? null : TextOverflow.ellipsis, style: TextStyle(fontSize: size, fontWeight: FontWeight.w900, height: 1.3, color: _ink)),
    if (sub != null) Padding(padding: const EdgeInsets.only(top: 1), child: Text(sub, maxLines: maxLines == null ? null : 1, overflow: maxLines == null ? null : TextOverflow.ellipsis, style: TextStyle(fontSize: size * 0.78, fontWeight: FontWeight.w700, color: const Color(0xFF475569), height: 1.35))),
  ]);
}

/// 本文の1段落（「■」で始まる段落は小見出し）
Widget bodyParagraph(String p) => p.startsWith('■')
    ? Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 4),
        child: Container(
          padding: const EdgeInsets.only(left: 8),
          decoration: const BoxDecoration(border: Border(left: BorderSide(color: Color(0xFF0F172A), width: 3))),
          child: Text(p.substring(1), style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w900)),
        ),
      )
    : Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(p, style: const TextStyle(fontSize: 14, height: 1.8, color: Color(0xFF1E293B))));

Color topicColor(NewsTopic t) => switch (t) { NewsTopic.transfer => const Color(0xFF2563EB), NewsTopic.injury => const Color(0xFFDC2626), NewsTopic.record => const Color(0xFFB45309), NewsTopic.rumor => const Color(0xFF7C3AED) };

/// ニュース一覧の1件（顔・種類・見出し・日付）。押すと記事とコメントを浮かせて出す
class ItemNewsCard extends StatelessWidget {
  final ItemNews news;
  final List<Team> teams;
  final String? myTeamId;
  final DateTime? date;
  const ItemNewsCard({super.key, required this.news, required this.teams, this.myTeamId, this.date});

  @override
  Widget build(BuildContext context) {
    final n = news;
    final c = topicColor(n.topic);
    return InkWell(
      onTap: () => showItemNews(context, n, teams, myTeamId: myTeamId, date: date),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _line))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (n.player != null)
            PlayerAvatar(n.player!, size: 44, date: date)
          else
            Container(width: 44, height: 44, decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)), child: Icon(Icons.article_outlined, color: c)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3)),
                  child: Text(ItemNews.label(n.topic), style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 6),
                if (n.team != null) ...[
                  Container(width: 3, height: 11, color: teamColor(teams, n.team!)),
                  const SizedBox(width: 3),
                  Text(teamShort(n.team!), style: const TextStyle(fontSize: 10.5, color: _sub)),
                ],
                const Spacer(),
                Text(n.date, style: const TextStyle(fontSize: 10.5, color: _sub)),
              ]),
              const SizedBox(height: 3),
              headlineView(n.headline, size: 14.5, kickerColor: c, maxLines: 2),
              const SizedBox(height: 2),
              Row(children: [
                const Icon(Icons.chat_bubble_outline, size: 12, color: _sub),
                Text(' ${n.teamFans.length + n.otherFans.length}', style: const TextStyle(fontSize: 10.5, color: _sub)),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

Future<void> showItemNews(BuildContext context, ItemNews n, List<Team> teams, {String? myTeamId, DateTime? date}) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (c) => SizedBox(height: MediaQuery.of(c).size.height * 0.85, child: _ItemArticle(n: n, teams: teams, myTeamId: myTeamId, date: date)),
    );

class _ItemArticle extends StatefulWidget {
  final ItemNews n;
  final List<Team> teams;
  final String? myTeamId;
  final DateTime? date;
  const _ItemArticle({required this.n, required this.teams, this.myTeamId, this.date});
  @override
  State<_ItemArticle> createState() => _ItemArticleState();
}

class _ItemArticleState extends State<_ItemArticle> {
  bool _team = true;

  @override
  Widget build(BuildContext context) {
    final n = widget.n;
    final c = topicColor(n.topic);
    final t = n.team;
    final mine = t != null && t.id == widget.myTeamId;
    final tabs = [(true, t == null ? 'ファン' : (mine ? '自球団（${teamShort(t)}）' : '${teamShort(t)}ファン')), (false, '他球団')];
    final List<FanComment> list = _team ? n.teamFans : n.otherFans;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
      Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(color: const Color(0xFFDC2626), borderRadius: BorderRadius.circular(3)),
          child: const Text('ペナントスポーツ', style: TextStyle(fontSize: 10.5, color: Colors.white, fontWeight: FontWeight.w800)),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3)),
          child: Text(ItemNews.label(n.topic), style: const TextStyle(fontSize: 10.5, color: Colors.white, fontWeight: FontWeight.w800)),
        ),
        const SizedBox(width: 8),
        Text(n.date, style: const TextStyle(fontSize: 11.5, color: _sub)),
      ]),
      const SizedBox(height: 6),
      headlineView(n.headline, size: 19.5, kickerColor: c),
      const SizedBox(height: 10),
      if (n.player != null)
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            gradient: LinearGradient(colors: [n.playerTeam == null ? c.withValues(alpha: 0.2) : teamColor(widget.teams, n.playerTeam!).withValues(alpha: 0.25), Colors.white]),
          ),
          child: Row(children: [
            PlayerAvatar(n.player!, size: 64, date: widget.date),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(n.player!.registeredName, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                Text('${n.playerTeam == null ? '' : '${teamShort(n.playerTeam!)}　'}${n.player!.isPitcher ? '投手' : n.player!.mainPosition}　${n.player!.age}歳', style: const TextStyle(fontSize: 12.5, color: _sub)),
              ]),
            ),
          ]),
        ),
      const SizedBox(height: 10),
      for (final p in n.body) bodyParagraph(p),
      const SizedBox(height: 8),
      Row(children: [
        const Icon(Icons.forum_outlined, size: 18),
        const SizedBox(width: 6),
        Text('コメント（${n.teamFans.length + n.otherFans.length}件）', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
      ]),
      const SizedBox(height: 6),
      ChipGrid<bool>(items: tabs, selected: _team, minWidth: 120, padding: EdgeInsets.zero, onSelect: (v) => setState(() => _team = v)),
      const SizedBox(height: 6),
      for (final cm in list)
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _line))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CircleAvatar(radius: 13, backgroundColor: cm.positive ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2), child: Icon(Icons.person, size: 16, color: cm.positive ? const Color(0xFF15803D) : const Color(0xFFB91C1C))),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(child: Text(cm.user, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: _sub, fontWeight: FontWeight.w700))),
                  Text('　${cm.ago}', style: const TextStyle(fontSize: 10.5, color: Color(0xFF94A3B8))),
                ]),
                Text(cm.text, style: const TextStyle(fontSize: 13.5, height: 1.5, color: _ink)),
                Row(children: [
                  const Icon(Icons.thumb_up_alt_outlined, size: 13, color: _sub),
                  Text(' ${cm.likes}', style: const TextStyle(fontSize: 11, color: _sub)),
                ]),
              ]),
            ),
          ]),
        ),
    ]);
  }
}
