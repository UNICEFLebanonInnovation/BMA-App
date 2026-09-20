import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../analytics_models.dart';
import 'chart_palette.dart';

/// Part-to-whole at a glance, for up to eight categories (the caller folds
/// the tail with [foldTail] first). The ring carries the total in its centre;
/// every slice is named in the legend with its count and share, so the ring
/// is never the only way to read the figure.
class DonutChart extends StatelessWidget {
  const DonutChart({
    super.key,
    required this.items,
    this.colorOf,
    this.size = 150,
    this.centerLabel,
  });

  final List<ChartItem> items;

  /// Colour of item [index]; defaults to the categorical slot of that index.
  final Color Function(int index, ChartItem item)? colorOf;
  final double size;

  /// Text under the total in the ring, e.g. "children".
  final String? centerLabel;

  @override
  Widget build(BuildContext context) {
    final total = totalOf(items);
    if (items.isEmpty || total == 0) return const SizedBox.shrink();
    final colors = [for (var i = 0; i < items.length; i++) colorOf?.call(i, items[i]) ?? ChartPalette.series(i)];

    final ring = SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _DonutPainter(items: items, colors: colors, total: total),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$total',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.primary),
              ),
              if (centerLabel != null)
                Text(centerLabel!, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
            ],
          ),
        ),
      ),
    );

    final legend = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: colors[i], borderRadius: BorderRadius.circular(3)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(items[i].label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                ),
                const SizedBox(width: 8),
                Text('${items[i].count}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(width: 6),
                SizedBox(
                  width: 46,
                  child: Text(
                    '${percentText(items[i].count, total)}%',
                    textAlign: TextAlign.end,
                    style: const TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                ),
              ],
            ),
          ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // Ring beside the legend when the card has room (a tablet card), ring
        // above it on the phone.
        if (constraints.maxWidth >= size + 200) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [ring, const SizedBox(width: 16), Expanded(child: legend)],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [Center(child: ring), const SizedBox(height: 12), legend],
        );
      },
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({required this.items, required this.colors, required this.total});

  final List<ChartItem> items;
  final List<Color> colors;
  final int total;

  @override
  void paint(Canvas canvas, Size size) {
    final ring = size.shortestSide * 0.19;
    final radius = size.shortestSide / 2 - ring / 2;
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: radius);
    // A 2 px surface gap between slices, expressed as an angle at this radius.
    final gap = items.length > 1 ? 2.0 / radius : 0.0;
    var start = -math.pi / 2;
    for (var i = 0; i < items.length; i++) {
      final sweep = items[i].count / total * 2 * math.pi;
      if (sweep <= 0) continue;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ring
        ..color = colors[i]
        ..strokeCap = StrokeCap.butt;
      final visible = math.max(sweep - gap, 0.0);
      canvas.drawArc(rect, start + gap / 2, visible, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) => old.items != items || old.colors != colors || old.total != total;
}
