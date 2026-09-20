import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../../core/theme/app_theme.dart';
import '../analytics_models.dart';
import 'chart_palette.dart';

/// The attendance heatmap of the web platform: one row per month, one column
/// per day of the month, each cell shaded by that day's attendance rate.
///
/// One `CustomPaint` rather than 372 boxes, so a page with an overall map and
/// one per programme stays cheap. Cells are 14–24 px depending on the width;
/// below the width the 31 columns need, the grid scrolls sideways, as the web
/// container does. Tapping a cell selects it and prints its figures under the
/// grid, which is this widget's tooltip.
class AttendanceHeatmap extends StatefulWidget {
  const AttendanceHeatmap({
    super.key,
    required this.year,
    required this.cells,
    required this.detailText,
    this.rateLabel,
  });

  final int year;

  /// Keyed on date-only [DateTime]s within [year].
  final Map<DateTime, HeatCell> cells;

  /// Caption for a selected cell.
  final String Function(HeatCell cell) detailText;

  /// Legend caption, e.g. "Attendance rate".
  final String? rateLabel;

  @override
  State<AttendanceHeatmap> createState() => _AttendanceHeatmapState();
}

class _AttendanceHeatmapState extends State<AttendanceHeatmap> {
  DateTime? _selected;

  static const double _labelWidth = 44;
  static const double _headerHeight = 18;

  @override
  void didUpdateWidget(AttendanceHeatmap old) {
    super.didUpdateWidget(old);
    if (old.cells != widget.cells || old.year != widget.year) _selected = null;
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.maybeLocaleOf(context)?.toString();
    final months = [for (var m = 1; m <= 12; m++) _month(m, locale)];
    final selected = _selected == null ? null : widget.cells[_selected!];

    return LayoutBuilder(
      builder: (context, constraints) {
        final fit = (constraints.maxWidth - _labelWidth) / 31;
        final cell = fit.clamp(14.0, 24.0);
        final gridWidth = _labelWidth + 31 * cell;
        final gridHeight = _headerHeight + 12 * cell;
        final grid = SizedBox(
          width: gridWidth,
          height: gridHeight,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) => _tap(d.localPosition, cell),
            child: CustomPaint(
              painter: _HeatmapPainter(
                year: widget.year,
                cells: widget.cells,
                months: months,
                cell: cell,
                labelWidth: _labelWidth,
                headerHeight: _headerHeight,
                selected: _selected,
                textDirection: Directionality.of(context),
              ),
            ),
          ),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (gridWidth > constraints.maxWidth)
              SingleChildScrollView(scrollDirection: Axis.horizontal, child: grid)
            else
              grid,
            const SizedBox(height: 8),
            _Legend(label: widget.rateLabel),
            const SizedBox(height: 4),
            Text(
              selected == null ? ' ' : widget.detailText(selected),
              key: const ValueKey('heatmap-detail'),
              style: const TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600),
            ),
          ],
        );
      },
    );
  }

  void _tap(Offset position, double cell) {
    final column = ((position.dx - _labelWidth) / cell).floor();
    final row = ((position.dy - _headerHeight) / cell).floor();
    if (column < 0 || column > 30 || row < 0 || row > 11) return;
    final month = row + 1;
    final day = column + 1;
    if (day > DateUtils.getDaysInMonth(widget.year, month)) return;
    final date = DateTime(widget.year, month, day);
    setState(() => _selected = widget.cells.containsKey(date) ? date : null);
  }

  static String _month(int month, String? locale) {
    try {
      return DateFormat.MMM(locale).format(DateTime(2000, month));
    } catch (_) {
      return const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][month - 1];
    }
  }
}

class _HeatmapPainter extends CustomPainter {
  _HeatmapPainter({
    required this.year,
    required this.cells,
    required this.months,
    required this.cell,
    required this.labelWidth,
    required this.headerHeight,
    required this.selected,
    required this.textDirection,
  });

  final int year;
  final Map<DateTime, HeatCell> cells;
  final List<String> months;
  final double cell;
  final double labelWidth;
  final double headerHeight;
  final DateTime? selected;
  final TextDirection textDirection;

  @override
  void paint(Canvas canvas, Size size) {
    final labelStyle = const TextStyle(fontSize: 10, color: AppColors.muted);
    // Day numbers across the top.
    for (var d = 1; d <= 31; d++) {
      if (d != 1 && d % 5 != 0 && d != 31) continue;
      _text(canvas, '$d', labelStyle, Offset(labelWidth + (d - 1) * cell + cell / 2, headerHeight / 2), center: true);
    }
    final border = Paint()
      ..color = ChartPalette.gridline
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final highlight = Paint()
      ..color = AppColors.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (var m = 1; m <= 12; m++) {
      final y = headerHeight + (m - 1) * cell;
      _text(canvas, months[m - 1], labelStyle, Offset(labelWidth - 6, y + cell / 2), alignEnd: true);
      final days = DateUtils.getDaysInMonth(year, m);
      for (var d = 1; d <= days; d++) {
        final x = labelWidth + (d - 1) * cell;
        final rect = RRect.fromRectAndRadius(Rect.fromLTWH(x + 1, y + 1, cell - 2, cell - 2), const Radius.circular(2));
        final data = cells[DateTime(year, m, d)];
        final fill = data == null || data.total == 0 ? ChartPalette.track : ChartPalette.sequentialGreen(data.rate);
        canvas.drawRRect(rect, Paint()..color = fill);
        canvas.drawRRect(rect, border);
        if (selected != null && selected!.year == year && selected!.month == m && selected!.day == d) {
          canvas.drawRRect(rect, highlight);
        }
      }
    }
  }

  void _text(Canvas canvas, String text, TextStyle style, Offset at, {bool center = false, bool alignEnd = false}) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: textDirection,
      maxLines: 1,
    )..layout();
    final dx = center
        ? at.dx - painter.width / 2
        : alignEnd
            ? at.dx - painter.width
            : at.dx;
    painter.paint(canvas, Offset(dx, at.dy - painter.height / 2));
  }

  @override
  bool shouldRepaint(_HeatmapPainter old) =>
      old.cells != cells || old.year != year || old.cell != cell || old.selected != selected || old.months != months;
}

/// The light-to-dark scale bar with 0% and 100% at its ends.
///
/// A Wrap, not a Row: "Attendance rate" plus the 120 px scale and its two
/// end labels need ~366 px, which a 348 px phone card does not have — and a
/// Row there overflows rather than dropping the caption to its own line.
class _Legend extends StatelessWidget {
  const _Legend({this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (label != null) Text(label!, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('0%', style: TextStyle(fontSize: 10, color: AppColors.muted)),
            const SizedBox(width: 4),
            Container(
              width: 120,
              height: 8,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                gradient: LinearGradient(
                  colors: [for (final t in [0.0, 0.25, 0.5, 0.75, 1.0]) ChartPalette.sequentialGreen(t)],
                ),
              ),
            ),
            const SizedBox(width: 4),
            const Text('100%', style: TextStyle(fontSize: 10, color: AppColors.muted)),
          ],
        ),
      ],
    );
  }
}
