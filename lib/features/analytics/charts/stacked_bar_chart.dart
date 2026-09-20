import 'package:flutter/material.dart';

import '../../../core/layout/app_layout.dart';
import '../../../core/theme/app_theme.dart';
import '../analytics_models.dart';
import 'chart_card.dart';

/// Horizontal stacked bars: one bar per row, one segment per series, a 2 px
/// surface gap between segments, the row total at the end and a legend on
/// top. Bars are scaled to the largest row total.
///
/// This is the port of the web's `renderStackedBarChart` (children moved
/// between rounds) and the form the gender × age-group panel takes here, where
/// the web draws a pie of "Male - 5-9" style slices that cannot be compared.
class StackedBarListChart extends StatelessWidget {
  const StackedBarListChart({
    super.key,
    required this.rows,
    required this.series,
  });

  final List<StackedRow> rows;

  /// `(label, colour)` per series, in the order of [StackedRow.values].
  final List<(String, Color)> series;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final max = rows.fold(0, (m, r) => r.total > m ? r.total : m);
    final layout = LayoutScope.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final labelWidth = _min(
          layout.width.atLeastMedium ? layout.labelColumnWidth : 120.0,
          constraints.maxWidth * 0.4,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ChartLegend(entries: series),
            const SizedBox(height: 10),
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    SizedBox(
                      width: labelWidth,
                      child: Text(row.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, box) => _Bar(row: row, max: max, width: box.maxWidth, series: series),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 44,
                      child: Text(
                        '${row.total}',
                        textAlign: TextAlign.end,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.row, required this.max, required this.width, required this.series});

  final StackedRow row;
  final int max;
  final double width;
  final List<(String, Color)> series;

  @override
  Widget build(BuildContext context) {
    final segments = <Widget>[];
    final nonZero = row.values.where((v) => v > 0).length;
    final usable = width - 2.0 * (nonZero > 1 ? nonZero - 1 : 0);
    var first = true;
    for (var i = 0; i < row.values.length && i < series.length; i++) {
      final v = row.values[i];
      if (v <= 0) continue;
      final w = max == 0 ? 0.0 : usable * v / max;
      if (!first) segments.add(const SizedBox(width: 2));
      first = false;
      segments.add(Container(
        width: w,
        height: 14,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: series[i].$2, borderRadius: BorderRadius.circular(4)),
        child: w >= 26
            ? Text('$v', style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w600))
            : null,
      ));
    }
    return Container(
      height: 14,
      decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(4)),
      // Segments run from the start edge, mirrored for Arabic by the Row.
      child: Row(children: segments),
    );
  }
}

double _min(double a, double b) => a < b ? a : b;
