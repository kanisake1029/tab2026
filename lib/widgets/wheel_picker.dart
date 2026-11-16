import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// 回転式ピッカー（ドラムロール）で候補から1つ選ぶボトムシート
Future<T?> showWheelPicker<T>(
  BuildContext context, {
  required String title,
  required List<T> items,
  required T initial,
  required String Function(T) label,
}) {
  if (items.isEmpty) return Future.value(null);
  var idx = items.indexOf(initial);
  if (idx < 0) idx = 0;
  final ctl = FixedExtentScrollController(initialItem: idx);
  return showModalBottomSheet<T>(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: SizedBox(
        height: 270,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
            child: Row(children: [
              TextButton(onPressed: () => Navigator.pop(c), child: const Text('キャンセル')),
              Expanded(child: Text(title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14))),
              FilledButton(onPressed: () => Navigator.pop(c, items[idx]), child: const Text('決定')),
            ]),
          ),
          const Divider(height: 1),
          Expanded(
            child: CupertinoPicker(
              scrollController: ctl,
              itemExtent: 38,
              onSelectedItemChanged: (i) => idx = i,
              children: [
                for (final it in items) Center(child: Text(label(it), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
              ],
            ),
          ),
        ]),
      ),
    ),
  );
}

/// 大きさを揃えた選択ボタンの並び（横幅・高さを統一）
Widget uniformChipRow<T>(
  List<(T, String)> items,
  T value,
  ValueChanged<T> onSelect, {
  double height = 30,
  double? minWidth,
}) {
  return Wrap(
    spacing: 5,
    runSpacing: 5,
    children: [
      for (final it in items)
        InkWell(
          onTap: () => onSelect(it.$1),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            height: height,
            constraints: BoxConstraints(minWidth: minWidth ?? 58),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: it.$1 == value ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: it.$1 == value ? const Color(0xFF0F172A) : const Color(0xFFCBD5E1)),
            ),
            child: Text(
              it.$2,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: it.$1 == value ? Colors.white : const Color(0xFF334155),
              ),
            ),
          ),
        ),
    ],
  );
}
