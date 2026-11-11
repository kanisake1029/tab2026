import 'package:flutter/material.dart';

import '../engine/growth_engine.dart';
import '../models/player.dart';

/// 練習メニューを選ぶシート。能力のまとまりごとに、今の値を添えて並べる
///  専門外（投手の打撃・守備、野手の投球）も選べる
Future<String?> showPracticePicker(BuildContext context, Player p) {
  final opts = GrowthEngine.practiceOptions(p);
  final own = GrowthEngine.ownMenus(p).toSet();
  final cur = opts.contains(p.practiceInstruction) ? p.practiceInstruction : 'おまかせ';
  final groups = <(String, List<String>)>[
    ('打撃', ['対左ミート', '対右ミート', 'パワー', '選球眼', 'チャンス']),
    ('走塁・守備', ['走力', '肩力', '送球', '捕球', '守備']),
    ('投球', GrowthEngine.pitcherMenu),
    ('球種', [GrowthEngine.pitchSharp, GrowthEngine.pitchHeavy, GrowthEngine.pitchBreak]),
    ('体', GrowthEngine.bodyMenu),
  ];
  // 専門のまとまりを先に
  groups.sort((a, b) => (a.$2.any(own.contains) ? 0 : 1).compareTo(b.$2.any(own.contains) ? 0 : 1));
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (c) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * 0.8),
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), shrinkWrap: true, children: [
          Text('${p.listName} の練習メニュー', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          _tile(c, 'おまかせ', '自動で選ぶ（いまは「${GrowthEngine.autoPractice(p)}」）', cur == 'おまかせ'),
          for (final g in groups)
            if (g.$2.any(opts.contains)) ...[
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 6),
                child: Row(children: [
                  Text(g.$1, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Color(0xFF334155))),
                  if (!g.$2.any(own.contains)) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(4)),
                      child: const Text('専門外', style: TextStyle(fontSize: 10.5, color: Color(0xFF64748B), fontWeight: FontWeight.w700)),
                    ),
                  ],
                ]),
              ),
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                childAspectRatio: 2.3,
                children: [
                  for (final m in g.$2.where(opts.contains)) _cell(c, m, GrowthEngine.menuValue(p, m), cur == m),
                ],
              ),
            ],
        ]),
      ),
    ),
  );
}

Widget _tile(BuildContext c, String m, String sub, bool sel) => InkWell(
      onTap: () => Navigator.pop(c, m),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: sel ? const Color(0xFFDCFCE7) : Colors.white,
          border: Border.all(color: sel ? const Color(0xFF15803D) : const Color(0xFFCBD5E1), width: sel ? 2 : 1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: [
          Text(m, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
          const SizedBox(width: 10),
          Expanded(child: Text(sub, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)), overflow: TextOverflow.ellipsis)),
        ]),
      ),
    );

Widget _cell(BuildContext c, String m, String v, bool sel) => InkWell(
      onTap: () => Navigator.pop(c, m),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: sel ? const Color(0xFFDCFCE7) : Colors.white,
          border: Border.all(color: sel ? const Color(0xFF15803D) : const Color(0xFFCBD5E1), width: sel ? 2 : 1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          FittedBox(fit: BoxFit.scaleDown, child: Text(m.replaceAll('（全球種）', '').replaceAll('（変化球）', ''), maxLines: 1, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800))),
          if (v.isNotEmpty) Text(v, style: const TextStyle(fontSize: 11.5, color: Color(0xFF475569), fontWeight: FontWeight.w700)),
        ]),
      ),
    );
