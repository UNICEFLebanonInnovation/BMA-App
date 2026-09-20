import 'package:flutter/material.dart';

import '../layout/app_layout.dart';
import '../layout/breakpoints.dart';
import '../theme/app_theme.dart';

/// Building blocks shared by the modern screens: headers, tiles, stats and
/// fact rows. All of them are direction-aware and scale with the text size.

/// Section label above a group of cards or rows, with an optional trailing
/// action such as "See all".
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action, this.padding});

  final String title;
  final Widget? action;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? const EdgeInsetsDirectional.fromSTEB(16, 20, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}

/// Rounded, hairline-bordered container. The card equivalent that can also be
/// tapped, tinted and given an arbitrary child.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.color,
    this.borderColor,
    this.padding = const EdgeInsets.all(16),
    this.margin = const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
  });

  final Widget child;
  final VoidCallback? onTap;
  final Color? color;
  final Color? borderColor;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: Material(
        color: color ?? AppColors.surface,
        borderRadius: AppRadius.cardRadius,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.cardRadius,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: AppRadius.cardRadius,
              border: Border.all(color: borderColor ?? AppColors.border),
            ),
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

/// Row of equal-width stat tiles with consistent gaps.
class StatRow extends StatelessWidget {
  const StatRow({super.key, required this.tiles, this.padding = const EdgeInsets.symmetric(horizontal: 12)});

  final List<Widget> tiles;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final layout = LayoutScope.of(context);
    // Compact keeps Expanded: two tiles share 388 px and that reads well.
    // At medium+ the same two tiles would stretch to ~610 px each for a
    // two-digit number, so the tile is capped and the row packs from the
    // start edge instead. statTileWidth is double.infinity at compact, so the
    // isFinite test is also the "no scope installed" test.
    final capped = layout.width.atLeastMedium && layout.statTileWidth.isFinite;
    return Padding(
      padding: padding,
      // IntrinsicHeight bounds the cross axis, so stretch can equalise the
      // tiles instead of asking for infinite height inside a scroll view.
      // It is NOT removable: without it, stretch asks for infinite height.
      child: IntrinsicHeight(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < tiles.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              if (capped)
                SizedBox(width: layout.statTileWidth, child: tiles[i])
              else
                Expanded(child: tiles[i]),
            ],
          ],
        ),
      ),
    );
  }
}

/// Square tonal tile used for the quick actions on the home screen.
class ActionTile extends StatelessWidget {
  const ActionTile({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.color = AppColors.primary,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final tint = enabled ? color : AppColors.muted;
    final layout = LayoutScope.of(context);
    // The compact column of each triple is today's literal, so a tile outside
    // a LayoutScope is pixel-for-pixel what it is now.
    final (circle, glyph, labelSize) = switch (layout.width) {
      WidthClass.compact => (44.0, 22.0, 12.5),
      WidthClass.medium => (52.0, 26.0, 13.5),
      WidthClass.expanded => (56.0, 28.0, 14.0),
    };
    return Material(
      color: AppColors.surface,
      borderRadius: AppRadius.controlRadius,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.controlRadius,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: AppRadius.controlRadius,
            border: Border.all(color: AppColors.border),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: circle,
                  height: circle,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: tint.withValues(alpha: 0.12),
                  ),
                  child: Icon(icon, color: tint, size: glyph),
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: labelSize,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                    color: enabled ? AppColors.primary : AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Circle with the first letters of a name, for list rows without photos.
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar(this.name, {super.key, this.radius = 20, this.color = AppColors.secondary});

  final String name;
  final double radius;
  final Color color;

  static String initialsOf(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts[1].characters.first).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: color.withValues(alpha: 0.14),
      child: Text(
        initialsOf(name),
        style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: radius * 0.7),
      ),
    );
  }
}

/// Small rounded label. Softer than a Chip and cheap to place in dense rows.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, required this.color, this.icon, this.large = false});

  final String label;
  final Color color;
  final IconData? icon;

  /// Opt-in bigger variant for profile headers and the attendance tally, where
  /// the pill is read across a desk rather than skimmed in a list row.
  /// Defaults to false, which is exactly today's pill.
  final bool large;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: large
          ? const EdgeInsets.symmetric(horizontal: 12, vertical: 7)
          : const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: const BorderRadius.all(Radius.circular(999)),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: large ? 15 : 13, color: color),
            SizedBox(width: large ? 6 : 5),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontSize: large ? 14 : 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// Label and value on one line, wrapping to two on narrow screens. The
/// building block of the centre and school profiles.
class FactRow extends StatelessWidget {
  const FactRow({super.key, required this.label, required this.value, this.icon, this.labelWidth});

  final String label;
  final String value;
  final IconData? icon;

  /// Overrides the label column. Null means "follow the layout" — which is
  /// 132 at compact, i.e. today's literal.
  final double? labelWidth;

  @override
  Widget build(BuildContext context) {
    final layout = LayoutScope.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: AppColors.muted),
            const SizedBox(width: 10),
          ],
          SizedBox(
            width: labelWidth ?? layout.labelColumnWidth,
            child: Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}

/// Header band used at the top of the home screen and the profiles.
class HeroHeader extends StatelessWidget {
  const HeroHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.footer,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final layout = LayoutScope.of(context);
    final wide = layout.width.atLeastMedium;
    // gutter is 16 at compact, which is today's horizontal padding. The
    // vertical values are deliberately untouched: the band's height is the
    // same on every device and only its content re-flows.
    final titleSize = switch (layout.width) {
      WidthClass.compact => 20.0,
      WidthClass.medium => 24.0,
      WidthClass.expanded => 26.0,
    };

    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(color: Colors.white, fontSize: titleSize, fontWeight: FontWeight.w700),
        ),
        if (subtitle != null && subtitle!.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(
            subtitle!,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13),
          ),
        ],
      ],
    );

    Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Actions sit on their own line: a long name would otherwise push
        // into them and wrap badly. That is a PHONE constraint — from 600 px
        // up there is room to keep them on the title line.
        if (trailing != null && !wide)
          Align(alignment: AlignmentDirectional.centerEnd, child: trailing!),
        Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 12)],
            Expanded(child: titleBlock),
            if (trailing != null && wide) ...[const SizedBox(width: 16), trailing!],
          ],
        ),
        if (footer != null) ...[const SizedBox(height: 14), footer!],
      ],
    );

    // Only wrap when the cap is real: at compact contentMaxWidth is infinity
    // and the widget tree stays byte-for-byte what it is today.
    if (layout.contentMaxWidth.isFinite) {
      content = Align(
        alignment: AlignmentDirectional.center,
        // heightFactor: 1 keeps the band shrink-wrapped; without it Align asks
        // for the biggest height, which is unbounded here.
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: layout.contentMaxWidth),
          child: content,
        ),
      );
    }

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.primaryBright],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      padding: EdgeInsetsDirectional.fromSTEB(layout.gutter, 12, layout.gutter, 18),
      child: content,
    );
  }
}
