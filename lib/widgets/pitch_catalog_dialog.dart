import 'package:flutter/material.dart';
import '../engine/pitch_catalog.dart';

/// 球種の一覧（38種類）。球速差・変化量・角度・重さ・キレの幅と、変化のしかた
Future<void> showPitchCatalog(BuildContext context) {
  const sub = Color(0xFF64748B);
  const line = Color(0xFFE2E8F0);
  const head = TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: sub);
  const cell = TextStyle(fontSize: 11, fontFeatures: [FontFeature.tabularFigures()]);
  String range(int a, int b) => a == b ? '$a' : '$a〜$b';
  const widths = [96.0, 62.0, 52.0, 58.0, 50.0, 50.0, 40.0, 230.0];
  Widget row(List<String> v, {bool header = false, Color? bg}) => Container(
        color: bg,
        padding: const EdgeInsets.symmetric(vertical: 4),
        decoration: null,
        child: Row(children: [
          for (var i = 0; i < v.length; i++)
            SizedBox(
              width: widths[i],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Text(v[i], style: header ? head : (i == 0 ? cell.copyWith(fontWeight: FontWeight.w700) : cell), softWrap: i == v.length - 1),
              ),
            ),
        ]),
      );
  return showDialog(
    context: context,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.all(12),
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 4, 0),
          child: Row(children: [
            const Expanded(child: Text('球種の一覧', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900))),
            IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
          ]),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(14, 0, 14, 6),
          child: Text('球速差はストレートとの差（km/h）。角度は右投手で 0＝利き腕側（シュート方向）・90＝真下・180＝グラブ側（スライダー方向）。同じ球種なら球速が速いほど変化量は小さくなります。横にスクロールできます。',
              style: TextStyle(fontSize: 11, color: sub, height: 1.4)),
        ),
        Flexible(
          child: SingleChildScrollView(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                row(['球種', '球速差', '変化量', '角度', '重さ', 'キレ', '珍しさ', '変化のしかた'], header: true),
                for (final g in PitchCatalog.groups) ...[
                  Container(
                    width: widths.reduce((a, b) => a + b),
                    color: const Color(0xFFF1F5F9),
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                    child: Text(g, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900)),
                  ),
                  for (final s in PitchCatalog.all.where((s) => s.group == g))
                    Container(
                      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: line))),
                      child: row([
                        s.name,
                        s.dLo == 0 ? '0' : '${s.dLo}〜${s.dHi}',
                        range(s.bLo, s.bHi),
                        s.name == 'ナックル' ? '毎球' : s.name == 'ストレート' ? '—' : range(s.aLo, s.aHi),
                        range(s.hLo, s.hHi),
                        range(s.sLo, s.sHi),
                        s.weight == 0 ? '必須' : s.rarity,
                        s.memo,
                      ]),
                    ),
                ],
              ]),
            ),
          ),
        ),
      ]),
    ),
  );
}
