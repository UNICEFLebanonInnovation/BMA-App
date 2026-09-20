import 'package:flutter/material.dart';

import '../../../core/layout/app_layout.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';

/// The frame every chart sits in: a title, an optional one-line hint, the
/// plot. Same [Card] the offline dashboard's breakdown cards use, so a page
/// that mixes the two reads as one system.
class ChartCard extends StatelessWidget {
  const ChartCard({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;

  /// Below this the header's controls take a line of their own: a title and
  /// a pair of pickers do not both fit across a phone card, and a Row there
  /// overflows rather than giving way.
  static const double _inlineTrailing = 420;

  @override
  Widget build(BuildContext context) {
    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        if (subtitle != null && subtitle!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              subtitle!,
              style: const TextStyle(color: AppColors.muted, fontSize: 12, height: 1.3),
            ),
          ),
      ],
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final stacked = trailing != null && constraints.maxWidth < _inlineTrailing;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (stacked) ...[
                  titleBlock,
                  const SizedBox(height: 6),
                  Align(alignment: AlignmentDirectional.centerStart, child: trailing),
                ] else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: titleBlock),
                      if (trailing != null) ...[const SizedBox(width: 8), trailing!],
                    ],
                  ),
                const SizedBox(height: 10),
                child,
              ],
            );
          },
        ),
      ),
    );
  }
}

/// What a chart shows when its filter set leaves nothing to draw.
class EmptyChart extends StatelessWidget {
  const EmptyChart({super.key, required this.message, this.icon = Icons.bar_chart_outlined});

  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Row(
        children: [
          Icon(icon, color: ChartPaletteInk.muted, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: const TextStyle(color: AppColors.muted, fontSize: 13))),
        ],
      ),
    );
  }
}

/// Muted ink shared by the chart chrome.
class ChartPaletteInk {
  ChartPaletteInk._();

  static const Color muted = AppColors.muted;
}

/// A colour swatch beside a label, repeated for every series. Present for
/// every chart with two or more series, so identity is never colour alone.
class ChartLegend extends StatelessWidget {
  const ChartLegend({super.key, required this.entries});

  /// `(label, colour)` in series order.
  final List<(String, Color)> entries;

  @override
  Widget build(BuildContext context) {
    // A Wrap hands each child ITS OWN max width, and a `mainAxisSize.min`
    // Row cannot shrink below its children: a long series name at a 1.3 text
    // scale ("Moved from an earlier round") overflowed the card rather than
    // ellipsizing. The ConstrainedBox gives the entry a ceiling and the
    // Flexible lets the label give way inside it.
    return LayoutBuilder(
      builder: (context, constraints) => Wrap(
        spacing: 14,
        runSpacing: 6,
        children: [
          for (final (label, color) in entries)
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: AppColors.muted),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// One chart in a [ChartGrid]; `wide: true` asks for the whole row.
class ChartTile {
  const ChartTile({required this.child, this.wide = false});

  final Widget child;
  final bool wide;
}

/// Lays chart cards out in one column at compact, two at medium and three at
/// expanded — the same rule the offline dashboard uses for its breakdowns —
/// with a `wide` tile spanning every column. Wrap rather than GridView so each
/// card keeps its natural height instead of stretching to the tallest.
class ChartGrid extends StatelessWidget {
  const ChartGrid({super.key, required this.tiles, this.maxColumns = 3});

  final List<ChartTile> tiles;

  /// Cap on the column count at expanded, for pages whose charts are dense.
  final int maxColumns;

  @override
  Widget build(BuildContext context) {
    final layout = LayoutScope.of(context);
    final columns = (layout.width.isExpanded
            ? 3
            : layout.width.atLeastMedium
                ? 2
                : 1)
        .clamp(1, maxColumns);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final children = <Widget>[];
        var run = <Widget>[];
        void flush() {
          if (run.isEmpty) return;
          children.add(Wrap(children: run));
          run = <Widget>[];
        }

        for (final tile in tiles) {
          if (tile.wide || columns == 1) {
            flush();
            children.add(SizedBox(width: width, child: tile.child));
          } else {
            run.add(SizedBox(width: width / columns, child: tile.child));
          }
        }
        flush();
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
      },
    );
  }
}

/// The headline band: [StatTile]s in the extent-based grid the offline
/// dashboard settled on (one readable row of ~200 px tiles on the tablet, the
/// phone's two-across grid at 412).
class KpiGrid extends StatelessWidget {
  const KpiGrid({super.key, required this.tiles});

  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    return GridView(
      // EdgeInsets.zero, not null: a null padding makes BoxScrollView adopt
      // the ambient MediaQuery vertical padding, and this grid is nested
      // inside a ListView that has not stripped it — so on a phone with
      // gesture navigation the KPI band grew a 48 px band of empty space.
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        childAspectRatio: 1.6,
      ),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: tiles,
    );
  }
}

/// A KPI tile: value, label and an optional caption line under the label
/// ("72% of teachers", "years"). Thin wrapper over [StatTile] so the tiles of
/// every dashboard look alike.
class KpiTile extends StatelessWidget {
  const KpiTile({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.color,
    this.caption,
  });

  final String label;
  final String value;
  final IconData? icon;
  final Color? color;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    return StatTile(
      label: caption == null || caption!.isEmpty ? label : '$label · $caption',
      value: value,
      icon: icon,
      color: color,
    );
  }
}

/// A one-line note above a dashboard: where the figures come from.
class SourceNote extends StatelessWidget {
  const SourceNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 16, color: AppColors.muted),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(color: AppColors.muted, fontSize: 12, height: 1.3))),
        ],
      ),
    );
  }
}
