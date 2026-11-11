import 'package:flutter/material.dart';

/// 選ぶボタンを、横にすべらせずに画面の幅で折り返して並べる（同じ幅の札）
class ChipGrid<T> extends StatelessWidget {
  final List<(T, String)> items;
  final T? selected;
  final ValueChanged<T> onSelect;

  /// 札1枚の最小の幅（これで1行の枚数が決まる）
  final double minWidth;
  final EdgeInsetsGeometry padding;
  final Color selectedColor;
  const ChipGrid({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelect,
    this.minWidth = 64,
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    this.selectedColor = const Color(0xFF0F172A),
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: LayoutBuilder(builder: (context, c) {
          final cols = (c.maxWidth / minWidth).floor().clamp(1, items.isEmpty ? 1 : items.length);
          final rows = (items.length / cols).ceil();
          final perRow = rows == 0 ? 1 : (items.length / rows).ceil(); // 行ごとの枚数をそろえる
          final w = (c.maxWidth - (perRow - 1) * 4) / perRow;
          return Wrap(spacing: 4, runSpacing: 4, children: [
            for (final (v, label) in items)
              _tile(label, v == selected, () => onSelect(v), w),
          ]);
        }),
      );

  Widget _tile(String label, bool on, VoidCallback tap, double w) => InkWell(
        onTap: tap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: w,
          height: 28,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            color: on ? selectedColor : Colors.white,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: on ? selectedColor : const Color(0xFFCBD5E1)),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(label, maxLines: 1, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: on ? Colors.white : const Color(0xFF0F172A))),
          ),
        ),
      );
}

/// タブを、横にすべらせずに折り返して並べる（TabController と連動）
class TabGrid extends StatelessWidget {
  final TabController controller;
  final List<String> labels;
  final double minWidth;
  final EdgeInsetsGeometry padding;
  const TabGrid({super.key, required this.controller, required this.labels, this.minWidth = 72, this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 4)});

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: controller,
        builder: (context, _) => ChipGrid<int>(
          items: [for (var i = 0; i < labels.length; i++) (i, labels[i])],
          selected: controller.index,
          onSelect: (i) => controller.animateTo(i),
          minWidth: minWidth,
          padding: padding,
        ),
      );
}

/// 年度を選ぶ：◀ 年度（一覧から選ぶ）▶
class YearStepper extends StatelessWidget {
  final List<int> years; // 並び順のまま
  final int selected;
  final ValueChanged<int> onSelect;
  final String Function(int)? label;
  const YearStepper({super.key, required this.years, required this.selected, required this.onSelect, this.label});

  @override
  Widget build(BuildContext context) {
    final i = years.indexOf(selected);
    String lb(int y) => label?.call(y) ?? '$y年';
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.chevron_left), onPressed: i > 0 ? () => onSelect(years[i - 1]) : null),
      DropdownButton<int>(
        value: years.contains(selected) ? selected : null,
        isDense: true,
        underline: const SizedBox(),
        items: [for (final y in years) DropdownMenuItem(value: y, child: Text(lb(y), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)))],
        onChanged: (v) => v == null ? null : onSelect(v),
      ),
      IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.chevron_right), onPressed: i >= 0 && i < years.length - 1 ? () => onSelect(years[i + 1]) : null),
    ]);
  }
}
