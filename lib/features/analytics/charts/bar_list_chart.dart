import 'package:flutter/material.dart';

import '../../../core/layout/app_layout.dart';
import '../../../core/theme/app_theme.dart';
import '../analytics_models.dart';
import 'chart_palette.dart';

/// Horizontal bars, one per category, longest first: the workhorse of every
/// dashboard here, and the form the web's `renderBarChart` /
/// `renderHorizontalBarChart` panels are ported to.
///
/// * bars are scaled to the LARGEST item, so lengths compare magnitudes;
/// * every bar carries its value at the end (direct label), and the optional
///   share of the total, so no reading depends on the axis;
/// * one colour for a single series ([ChartPalette.single]); [colorOf] lets a
///   caller keep an entity's slot colour (a gender, a band) instead;
/// * a list longer than [initialLimit] collapses behind "Show all".
class BarListChart extends StatefulWidget {
  const BarListChart({
    super.key,
    required this.items,
    this.total,
    this.maxValue,
    this.initialLimit = 8,
    this.colorOf,
    this.showShare = false,
    this.valueText,
    this.valueWidth,
    this.showAllLabel,
    this.showLessLabel,
    this.onTap,
  });

  final List<ChartItem> items;

  /// Denominator of the share column; defaults to the sum of the items.
  final int? total;

  /// What a full-length bar means. Defaults to the largest item, which is
  /// right when the values are counts; a percentage chart passes 100 so a
  /// best-of-a-bad-lot 40% does not draw as a full bar.
  final int? maxValue;
  final int initialLimit;
  final Color Function(int index, ChartItem item)? colorOf;
  final bool showShare;

  /// Formats the value at the end of the bar; defaults to the plain count.
  final String Function(ChartItem item)? valueText;

  /// Width of the value column. Defaults to what a count (plus a share, when
  /// one is shown) needs; a caller printing a unit passes more.
  final double? valueWidth;
  final String? showAllLabel;
  final String? showLessLabel;
  final void Function(ChartItem item)? onTap;

  @override
  State<BarListChart> createState() => _BarListChartState();
}

class _BarListChartState extends State<BarListChart> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    if (items.isEmpty) return const SizedBox.shrink();
    final max = widget.maxValue ?? items.fold<int>(0, (m, i) => i.count > m ? i.count : m);
    final total = widget.total ?? totalOf(items);
    final layout = LayoutScope.of(context);
    final visible = _expanded || items.length <= widget.initialLimit ? items : items.take(widget.initialLimit).toList();
    final overflow = items.length > widget.initialLimit;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Label column: the layout token at medium+, capped to 40% of THIS
        // card so three cards abreast keep a bar worth reading.
        final labelWidth = _min(
          layout.width.atLeastMedium ? layout.labelColumnWidth : 120.0,
          constraints.maxWidth * 0.4,
        );
        final valueWidth = widget.valueWidth ?? (widget.showShare ? 92.0 : 44.0);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < visible.length; i++)
              _BarRow(
                item: visible[i],
                fraction: max == 0 ? 0 : visible[i].count / max,
                color: widget.colorOf?.call(i, visible[i]) ?? ChartPalette.single,
                labelWidth: labelWidth,
                valueWidth: valueWidth,
                valueText: widget.valueText?.call(visible[i]) ?? '${visible[i].count}',
                shareText: widget.showShare ? '${percentText(visible[i].count, total)}%' : null,
                onTap: widget.onTap == null ? null : () => widget.onTap!(visible[i]),
              ),
            if (overflow)
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(
                  onPressed: () => setState(() => _expanded = !_expanded),
                  child: Text(
                    _expanded
                        ? (widget.showLessLabel ?? 'Show less')
                        : '${widget.showAllLabel ?? 'Show all'} (${items.length})',
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _BarRow extends StatelessWidget {
  const _BarRow({
    required this.item,
    required this.fraction,
    required this.color,
    required this.labelWidth,
    required this.valueWidth,
    required this.valueText,
    this.shareText,
    this.onTap,
  });

  final ChartItem item;
  final double fraction;
  final Color color;
  final double labelWidth;
  final double valueWidth;
  final String valueText;
  final String? shareText;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: labelWidth,
            child: Text(item.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 12,
              decoration: BoxDecoration(color: ChartPalette.track, borderRadius: BorderRadius.circular(4)),
              // Grows from the START edge, which is the right in Arabic.
              alignment: AlignmentDirectional.centerStart,
              child: FractionallySizedBox(
                widthFactor: fraction.clamp(0.0, 1.0),
                child: Container(
                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: valueWidth,
            child: Text.rich(
              TextSpan(
                text: valueText,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                children: [
                  if (shareText != null)
                    TextSpan(
                      text: '  $shareText',
                      style: const TextStyle(fontWeight: FontWeight.w400, color: AppColors.muted, fontSize: 12),
                    ),
                ],
              ),
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return row;
    return InkWell(onTap: onTap, borderRadius: BorderRadius.circular(6), child: row);
  }
}

double _min(double a, double b) => a < b ? a : b;
