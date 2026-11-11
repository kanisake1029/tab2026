import 'package:flutter/material.dart';

/// 表の1行：左の固定部分（名前など）と、横にスクロールする数字のセル
class FrozenRow {
  final Widget lead;
  final List<String> cells;
  final Color? color;
  final VoidCallback? onTap;
  final List<TextStyle?>? styles; // セルごとの文字の形（null ならふつう）
  const FrozenRow({required this.lead, required this.cells, this.color, this.onTap, this.styles});
}

/// 左の列を固定し、右の列だけを横にスクロールする表（順位表・成績表）。
///  見出しを押すと onSort(列の番号) を呼ぶ（並べ替えは呼んだ側で行う）。sortCol の見出しに▼を付ける
class FrozenTable extends StatelessWidget {
  final String leadHeader;
  final double leadWidth;
  final List<String> headers;
  final List<double> widths; // 右の列ごとの幅
  final List<FrozenRow> rows;
  final int? sortCol;
  final ValueChanged<int>? onSort;
  final double rowHeight;
  final String? caption; // 見出しの上の小さな説明（列のまとまり）
  final bool compact; // 詰めた表示（文字・見出し・余白を小さく）
  final int cellLines; // セルの行数（2なら「率」と「内訳」を2段に）

  const FrozenTable({
    super.key,
    required this.leadHeader,
    required this.leadWidth,
    required this.headers,
    required this.widths,
    required this.rows,
    this.sortCol,
    this.onSort,
    this.rowHeight = 38,
    this.caption,
    this.compact = false,
    this.cellLines = 1,
  });

  static const _head = TextStyle(fontSize: 11, color: Color(0xFF6B7280), fontWeight: FontWeight.w700);
  static const _num = TextStyle(fontSize: 14, fontFeatures: [FontFeature.tabularFigures()]);
  static const _headBg = Color(0xFFF3F4F6);
  static const _line = Color(0xFFE5E7EB);

  @override
  Widget build(BuildContext context) {
    Widget headCell(int i) {
      final sel = sortCol == i;
      final t = Container(
        width: widths[i],
        height: compact ? 22 : 30,
        alignment: Alignment.centerRight,
        padding: EdgeInsets.only(right: compact ? 3 : 6),
        child: Text('${headers[i]}${sel ? '▼' : ''}', maxLines: 1, style: _head.copyWith(color: sel ? const Color(0xFF1D4ED8) : null, fontSize: compact ? 10 : null)),
      );
      return onSort == null ? t : InkWell(onTap: () => onSort!(i), child: t);
    }

    BoxDecoration rowDeco(FrozenRow r) => BoxDecoration(color: r.color, border: const Border(bottom: BorderSide(color: _line)));

    final left = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(height: compact ? 22 : 30, color: _headBg, padding: EdgeInsets.symmetric(horizontal: compact ? 3 : 8), alignment: Alignment.centerLeft, child: Text(leadHeader, style: compact ? _head.copyWith(fontSize: 10) : _head)),
      for (final r in rows)
        InkWell(
          onTap: r.onTap,
          child: Container(height: rowHeight, padding: EdgeInsets.symmetric(horizontal: compact ? 3 : 8), alignment: Alignment.centerLeft, decoration: rowDeco(r), child: r.lead),
        ),
    ]);
    final right = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(color: _headBg, child: Row(children: [for (var i = 0; i < headers.length; i++) headCell(i)])),
      for (final r in rows)
        InkWell(
          onTap: r.onTap,
          child: Container(
            height: rowHeight,
            decoration: rowDeco(r),
            child: Row(children: [
              for (var i = 0; i < headers.length; i++)
                Container(
                  width: widths[i],
                  alignment: Alignment.centerRight,
                  padding: EdgeInsets.only(right: compact ? 3 : 6),
                  child: Text(i < r.cells.length ? r.cells[i] : '', maxLines: cellLines, textAlign: TextAlign.right, style: (compact ? _num.copyWith(fontSize: cellLines > 1 ? 11 : 12, height: cellLines > 1 ? 1.15 : null) : _num).merge(r.styles != null && i < r.styles!.length ? r.styles![i] : null)),
                ),
            ]),
          ),
        ),
    ]);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      if (caption != null) Padding(padding: const EdgeInsets.only(bottom: 2), child: Text(caption!, style: const TextStyle(fontSize: 10.5, color: Color(0xFF9CA3AF)))),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: leadWidth,
          decoration: const BoxDecoration(border: Border(right: BorderSide(color: Color(0xFFD1D5DB)))),
          child: left,
        ),
        Expanded(child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: right)),
      ]),
    ]);
  }
}
