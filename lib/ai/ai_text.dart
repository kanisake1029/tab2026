import 'package:flutter/material.dart';
import 'ai_writer.dart';

/// AI の文章（あれば）か、これまでの自動作文（fallback）を出す。
///  AI が書いている間は自動作文を出しておき、できたら差し替える。
class AiText extends StatefulWidget {
  final AiItem item;
  final String fallback;
  final Widget Function(String text) builder;
  final bool dark; // 暗い背景用の色
  const AiText({super.key, required this.item, required this.fallback, required this.builder, this.dark = false});

  @override
  State<AiText> createState() => _AiTextState();
}

class _AiTextState extends State<AiText> {
  String? _ai;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(AiText old) {
    super.didUpdateWidget(old);
    if (old.item.key != widget.item.key) {
      _ai = null;
      _start();
    }
  }

  Future<void> _start() async {
    final w = AiWriter.instance;
    await w.load();
    final key = widget.item.key;
    final c = w.cached(key);
    if (c != null) {
      if (mounted) setState(() => _ai = c);
      return;
    }
    if (!w.active) return;
    if (mounted) setState(() => _loading = true);
    final t = await w.write(widget.item);
    if (!mounted || widget.item.key != key) return;
    setState(() {
      _loading = false;
      _ai = t;
    });
  }

  @override
  Widget build(BuildContext context) {
    final sub = widget.dark ? const Color(0xFF8EA3BF) : const Color(0xFF78716C);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      widget.builder(_ai ?? widget.fallback),
      if (_loading)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(children: [
            SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5, color: sub)),
            const SizedBox(width: 6),
            Text('AI（Haiku）が書いています…', style: TextStyle(fontSize: 10.5, color: sub)),
          ]),
        )
      else if (_ai != null)
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text('✦ AI（Haiku 5.5）が作成', style: TextStyle(fontSize: 10, color: sub)),
        ),
    ]);
  }
}
