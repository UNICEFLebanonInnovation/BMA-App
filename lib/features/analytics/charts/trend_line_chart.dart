import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../../core/theme/app_theme.dart';
import '../analytics_models.dart';
import 'chart_palette.dart';

/// A daily series as a 2 px line over a light area, three recessive
/// gridlines, and the first / middle / last dates under the plot.
///
/// The plot is laid out LEFT-TO-RIGHT in both languages: a time axis runs
/// forward in reading order on the web dashboard this mirrors, and mirroring
/// only the labels would put the newest day under the oldest point. Tapping
/// (or dragging across) the plot selects the nearest day and prints its figure
/// under the chart — the tooltip layer, in a form that works on a touch screen.
class TrendLineChart extends StatefulWidget {
  const TrendLineChart({
    super.key,
    required this.points,
    this.height = 170,
    this.color = ChartPalette.single,
    this.detailText,
  });

  final List<TrendPoint> points;
  final double height;
  final Color color;

  /// Formats the caption for a selected point; defaults to "date · count".
  final String Function(TrendPoint point)? detailText;

  @override
  State<TrendLineChart> createState() => _TrendLineChartState();
}

class _TrendLineChartState extends State<TrendLineChart> {
  int? _selected;

  @override
  void didUpdateWidget(TrendLineChart old) {
    super.didUpdateWidget(old);
    if (old.points != widget.points) _selected = null;
  }

  @override
  Widget build(BuildContext context) {
    final points = widget.points;
    if (points.isEmpty) return const SizedBox.shrink();
    final locale = Localizations.maybeLocaleOf(context)?.toString();
    final maxCount = points.fold(0, (m, p) => p.count > m ? p.count : m);
    final top = _niceCeiling(maxCount);
    final selected = _selected == null || _selected! >= points.length ? null : points[_selected!];

    String date(DateTime d) => _format(d, locale);

    // Directionality.ltr on the plot only: the caption below keeps the page's
    // direction.
    final plot = Directionality(
      textDirection: TextDirection.ltr,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: widget.height,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 36,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _axisText('$top'),
                      _axisText('${top ~/ 2}'),
                      _axisText('0'),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) => GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (d) => _select(d.localPosition.dx, constraints.maxWidth),
                      onHorizontalDragUpdate: (d) => _select(d.localPosition.dx, constraints.maxWidth),
                      child: CustomPaint(
                        painter: _TrendPainter(
                          points: points,
                          top: top,
                          color: widget.color,
                          selected: _selected,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 42),
            // Flexible, not bare Text: `overflow: ellipsis` only bites once
            // the Text has a bounded width, and three localised dates at a
            // 1.3 text scale are wider than a phone's plot.
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(child: _axisText(date(points.first.day))),
                if (points.length > 2) Flexible(child: _axisText(date(points[points.length ~/ 2].day))),
                if (points.length > 1) Flexible(child: _axisText(date(points.last.day))),
              ],
            ),
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        plot,
        const SizedBox(height: 6),
        Text(
          selected == null
              ? ' '
              : widget.detailText?.call(selected) ?? '${date(selected.day)} · ${selected.count}',
          key: const ValueKey('trend-detail'),
          style: const TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  void _select(double dx, double width) {
    final n = widget.points.length;
    if (n == 0 || width <= 0) return;
    final index = n == 1 ? 0 : (dx / width * (n - 1)).round().clamp(0, n - 1);
    if (index != _selected) setState(() => _selected = index);
  }

  static Widget _axisText(String text) =>
      Text(text, style: const TextStyle(fontSize: 10, color: AppColors.muted), maxLines: 1, overflow: TextOverflow.ellipsis);

  static String _format(DateTime d, String? locale) {
    try {
      return DateFormat.MMMd(locale).format(d);
    } catch (_) {
      return '${d.month}/${d.day}';
    }
  }
}

/// The smallest of 1, 2, 5 × 10^k (and their doubles) at or above [value],
/// so the axis top is a round number and the midline reads as a whole one.
int _niceCeiling(int value) {
  if (value <= 2) return 2;
  final magnitude = math.pow(10, (math.log(value) / math.ln10).floor()).toInt();
  for (final step in [1, 2, 4, 5, 10]) {
    final candidate = step * magnitude;
    if (candidate >= value && candidate.isEven) return candidate;
  }
  return 10 * magnitude;
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({required this.points, required this.top, required this.color, required this.selected});

  final List<TrendPoint> points;
  final int top;
  final Color color;
  final int? selected;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = ChartPalette.gridline
      ..strokeWidth = 1;
    for (final f in [0.0, 0.5, 1.0]) {
      final y = size.height * f;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final n = points.length;
    Offset at(int i) {
      final x = n == 1 ? size.width / 2 : size.width * i / (n - 1);
      final y = size.height - (top == 0 ? 0 : points[i].count / top * size.height);
      return Offset(x, y);
    }

    final line = Path();
    final area = Path();
    for (var i = 0; i < n; i++) {
      final p = at(i);
      if (i == 0) {
        line.moveTo(p.dx, p.dy);
        area.moveTo(p.dx, size.height);
        area.lineTo(p.dx, p.dy);
      } else {
        line.lineTo(p.dx, p.dy);
        area.lineTo(p.dx, p.dy);
      }
    }
    area.lineTo(at(n - 1).dx, size.height);
    area.close();
    canvas.drawPath(area, Paint()..color = color.withValues(alpha: 0.12));
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );
    if (n == 1) {
      canvas.drawCircle(at(0), 4, Paint()..color = color);
    }

    final s = selected;
    if (s != null && s < n) {
      final p = at(s);
      canvas.drawLine(
        Offset(p.dx, 0),
        Offset(p.dx, size.height),
        Paint()
          ..color = color.withValues(alpha: 0.5)
          ..strokeWidth = 1,
      );
      canvas.drawCircle(p, 6, Paint()..color = Colors.white);
      canvas.drawCircle(p, 4, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_TrendPainter old) =>
      old.points != points || old.top != top || old.color != color || old.selected != selected;
}
