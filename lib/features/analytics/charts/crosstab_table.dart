import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../analytics_models.dart';
import 'chart_palette.dart';

/// A two-dimensional cross-tab as a shaded grid: one hue, darker for larger
/// counts, with every count printed in its cell so the shading is a guide and
/// never the only reading. Row and column totals close the table.
///
/// Scrolls sideways when the columns do not fit (a phone with six age groups);
/// stretches to the card when they do.
class CrosstabTable extends StatelessWidget {
  const CrosstabTable({
    super.key,
    required this.crosstab,
    required this.rowHeader,
    required this.columnHeader,
    required this.totalLabel,
  });

  final Crosstab crosstab;
  final String rowHeader;
  final String columnHeader;
  final String totalLabel;

  static const double _labelWidth = 150;
  static const double _cellWidth = 64;
  static const double _rowHeight = 34;

  /// Every cell carries a 1 px margin on each side, so a cell occupies
  /// [_cellWidth] + 2. Leaving it out of the fits-in-the-box test made the
  /// table skip its scroll view at a handful of widths and overflow instead.
  static const double _cellOuterWidth = _cellWidth + 2;

  @override
  Widget build(BuildContext context) {
    final ct = crosstab;
    if (ct.isEmpty) return const SizedBox.shrink();
    final max = ct.maxCount;
    final headerStyle = const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.muted);
    final natural = _labelWidth + (ct.columns.length + 1) * _cellOuterWidth;

    Widget cell(Widget child, {Color? color, double width = _cellWidth}) => Container(
          width: width,
          height: _rowHeight,
          alignment: Alignment.center,
          margin: const EdgeInsets.all(1),
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
          child: child,
        );

    Widget label(String text, {TextStyle? style, double width = _labelWidth}) => Container(
          width: width,
          height: _rowHeight,
          alignment: AlignmentDirectional.centerStart,
          padding: const EdgeInsetsDirectional.only(start: 4, end: 8),
          child: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, style: style ?? const TextStyle(fontSize: 12)),
        );

    final table = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            label('$rowHeader ↓ · $columnHeader →', style: headerStyle),
            for (final c in ct.columns) cell(Text(c, style: headerStyle, textAlign: TextAlign.center, maxLines: 2)),
            cell(Text(totalLabel, style: headerStyle, textAlign: TextAlign.center)),
          ],
        ),
        for (final r in ct.rows)
          Row(
            children: [
              label(r),
              for (final c in ct.columns)
                Builder(builder: (context) {
                  final n = ct.at(r, c);
                  final t = max == 0 || n == 0 ? 0.0 : 0.15 + 0.85 * n / max;
                  return cell(
                    Text(
                      n == 0 ? '·' : '$n',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: n == 0 ? AppColors.muted : ChartPalette.inkOn(t),
                      ),
                    ),
                    color: n == 0 ? ChartPalette.track : ChartPalette.sequentialBlue(t),
                  );
                }),
              cell(
                Text('${ct.rowTotal(r)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                color: AppColors.surfaceAlt,
              ),
            ],
          ),
        Row(
          children: [
            label(totalLabel, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            for (final c in ct.columns)
              cell(
                Text('${ct.columnTotal(c)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                color: AppColors.surfaceAlt,
              ),
            cell(
              Text('${ct.total}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              color: AppColors.surfaceAlt,
            ),
          ],
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (natural <= constraints.maxWidth) return table;
        return SingleChildScrollView(scrollDirection: Axis.horizontal, child: table);
      },
    );
  }
}
