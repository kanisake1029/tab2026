import 'package:flutter/material.dart';

/// 注釈（案A）：色の囲み・情報アイコン・箇条書き。大事な語（数字＋単位、「」の語、**で囲んだ語）を太字にする
///  text をそのまま渡すと「。」ごとに箇条書きに分ける。points を渡すとその並びで出す
class NoteBox extends StatelessWidget {
  final String? text;
  final List<String>? points;
  final Color color; // 文字・アイコンの色
  final Color bg;
  final EdgeInsetsGeometry margin;
  const NoteBox(this.text, {super.key, this.points, this.color = const Color(0xFF1E3A8A), this.bg = const Color(0xFFEFF6FF), this.margin = EdgeInsets.zero});

  /// 注意（オレンジ）
  const NoteBox.warn(this.text, {super.key, this.points, this.margin = EdgeInsets.zero})
      : color = const Color(0xFF9A3412),
        bg = const Color(0xFFFFF7ED);

  static List<String> sentences(String t) {
    final out = <String>[];
    final buf = StringBuffer();
    var depth = 0; // 括弧の中の「。」では切らない
    for (final ch in t.split('')) {
      if ('（(「『'.contains(ch)) depth++;
      if ('）)」』'.contains(ch) && depth > 0) depth--;
      if (ch == '\n') {
        if (buf.toString().trim().isNotEmpty) out.add(buf.toString().trim());
        buf.clear();
        continue;
      }
      buf.write(ch);
      if (ch == '。' && depth == 0) {
        out.add(buf.toString().trim());
        buf.clear();
      }
    }
    if (buf.toString().trim().isNotEmpty) out.add(buf.toString().trim());
    // 最後の「。」は箇条書きでは外す
    return [for (final s in out) s.endsWith('。') ? s.substring(0, s.length - 1) : s];
  }

  static final _strong = RegExp(r'\*\*(.+?)\*\*|「[^」]{1,20}」|[0-9０-９][0-9０-９.,〜~・]*(?:億円|万円|円|人|日|年|か月|月|週|回|件|位|試合|km|％|%|枠|倍|段階|打席|球)');

  List<InlineSpan> _spans(String s) {
    final spans = <InlineSpan>[];
    var i = 0;
    for (final m in _strong.allMatches(s)) {
      if (m.start > i) spans.add(TextSpan(text: s.substring(i, m.start)));
      spans.add(TextSpan(text: m.group(1) ?? m.group(0), style: const TextStyle(fontWeight: FontWeight.w800)));
      i = m.end;
    }
    if (i < s.length) spans.add(TextSpan(text: s.substring(i)));
    return spans;
  }

  @override
  Widget build(BuildContext context) => _NoteBody(owner: this);
}

/// 注釈の中身：文ごとに小さな札にして並べる（短い札は1行に2つ）。4つ以上は「続き」で開く
class _NoteBody extends StatefulWidget {
  final NoteBox owner;
  const _NoteBody({required this.owner});
  @override
  State<_NoteBody> createState() => _NoteBodyState();
}

class _NoteBodyState extends State<_NoteBody> {
  bool _open = false;

  /// 「見出し：中身」の形なら分ける
  static (String?, String) _split(String s) {
    final i = s.indexOf('：');
    if (i > 0 && i <= 10) return (s.substring(0, i), s.substring(i + 1));
    return (null, s);
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.owner;
    final items = o.points ?? NoteBox.sentences(o.text ?? '');
    final color = o.color;
    final style = TextStyle(fontSize: 11.5, height: 1.4, color: color);
    const fold = 3;
    final shown = _open || items.length <= fold + 1 ? items : items.take(fold).toList();
    return Container(
      margin: o.margin,
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
      decoration: BoxDecoration(color: o.bg, borderRadius: BorderRadius.circular(8)),
      child: LayoutBuilder(builder: (context, c) {
        final half = (c.maxWidth - 4) / 2;
        Widget tile(String t, {required bool first}) {
          final (label, body) = _split(t);
          final short = items.length > 1 && t.length <= (c.maxWidth >= 500 ? 40 : 22);
          return Container(
            width: short ? half : c.maxWidth,
            padding: const EdgeInsets.fromLTRB(7, 4, 7, 5),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.75), borderRadius: BorderRadius.circular(5)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (first) Padding(padding: const EdgeInsets.only(top: 1, right: 4), child: Icon(Icons.info_outline, size: 14, color: color)),
              Expanded(
                child: label == null
                    ? Text.rich(TextSpan(style: style, children: o._spans(body)))
                    : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: color.withValues(alpha: 0.8))),
                        Text.rich(TextSpan(style: style, children: o._spans(body))),
                      ]),
              ),
            ]),
          );
        }

        return Wrap(spacing: 4, runSpacing: 4, children: [
          for (var i = 0; i < shown.length; i++) tile(shown[i], first: i == 0),
          if (items.length > fold + 1)
            InkWell(
              onTap: () => setState(() => _open = !_open),
              child: Container(
                width: c.maxWidth,
                padding: const EdgeInsets.symmetric(vertical: 2),
                alignment: Alignment.center,
                child: Text(_open ? '閉じる ▲' : '続きを見る（あと${items.length - fold}つ）▼', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: color)),
              ),
            ),
        ]);
      }),
    );
  }
}
