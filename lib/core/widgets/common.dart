import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../layout/app_layout.dart';
import '../layout/breakpoints.dart';
import '../models/entity_record.dart';
import '../sync/connectivity_service.dart';
import '../theme/app_theme.dart';

/// Coloured chip describing the local sync state of a record.
class SyncStateChip extends StatelessWidget {
  const SyncStateChip(this.state, {super.key, this.compact = false, this.forceIcon = false});

  final SyncState state;

  /// Asks for the bare icon. Honoured at compact width only: from 600 px up
  /// there is room for the label, and a hover tooltip is not a label on a
  /// touch device (nor is an 18 px icon a touch target).
  final bool compact;

  /// Escape hatch for the one caller that needs a glyph at every width: the
  /// counters on the sync centre put this INSIDE another Chip's avatar slot,
  /// which cannot hold a Chip. Defaults to false.
  final bool forceIcon;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final (label, color, icon) = switch (state) {
      SyncState.synced => (l10n.synced, AppColors.success, Icons.cloud_done),
      SyncState.pending => (l10n.pending, AppColors.warning, Icons.cloud_upload),
      SyncState.pushing => (l10n.pushing, AppColors.secondary, Icons.sync),
      SyncState.duplicate => (l10n.duplicate, AppColors.danger, Icons.people),
      SyncState.conflict => (l10n.conflict, AppColors.danger, Icons.call_split),
      SyncState.error => (l10n.error, AppColors.danger, Icons.error_outline),
      SyncState.discarded => (l10n.discarded, AppColors.muted, Icons.delete_outline),
    };
    if (forceIcon || (compact && !LayoutScope.of(context).width.atLeastMedium)) {
      return Tooltip(message: label, child: Icon(icon, size: 18, color: color));
    }
    return Chip(
      avatar: Icon(icon, size: 16, color: color),
      label: Text(label, style: TextStyle(color: color)),
      side: BorderSide(color: color.withValues(alpha: 0.4)),
      backgroundColor: color.withValues(alpha: 0.08),
      visualDensity: VisualDensity.compact,
    );
  }
}

/// Shown at the top of screens while the device has no connectivity.
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(isOnlineProvider);
    if (online) return const SizedBox.shrink();
    return MaterialBanner(
      backgroundColor: AppColors.warning.withValues(alpha: 0.15),
      leading: const Icon(Icons.cloud_off, color: AppColors.warning),
      content: Text(AppLocalizations.of(context).offlineBanner),
      actions: const [SizedBox.shrink()],
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.message, this.icon = Icons.inbox_outlined, this.action});

  final String message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final layout = LayoutScope.of(context);
    // emptyStateIcon is 56 at compact — today's literal.
    Widget text = Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted));
    // This is the "nothing selected" placeholder of every detail pane, so a
    // 1280 px-wide sentence is the common case at tablet width, not the odd
    // one. At compact 412 - 64 of padding is 348, already under the cap, so
    // the branch is skipped rather than made a no-op ConstrainedBox.
    if (layout.width.atLeastMedium) {
      text = ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: text);
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: layout.emptyStateIcon, color: AppColors.muted),
            const SizedBox(height: 12),
            text,
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

class SearchField extends StatelessWidget {
  const SearchField({super.key, required this.onChanged, this.hint});

  final ValueChanged<String> onChanged;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final layout = LayoutScope.of(context);
    Widget field = TextField(
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search),
        hintText: hint ?? AppLocalizations.of(context).searchHint,
      ),
      textInputAction: TextInputAction.search,
      onChanged: onChanged,
    );
    // searchMaxWidth is double.infinity at compact, so the isFinite test is
    // also the "no scope installed" test and the phone keeps a full-bleed
    // field. A 1256 px search box for a three-letter name is not a feature.
    if (layout.searchMaxWidth.isFinite) {
      field = Align(
        alignment: AlignmentDirectional.centerStart,
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: layout.searchMaxWidth),
          child: field,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 12, 4),
      child: field,
    );
  }
}

/// Key/value line used in profile headers and reports.
class InfoLine extends StatelessWidget {
  const InfoLine(this.label, this.value, {super.key, this.labelWidth});

  final String label;
  final String? value;

  /// Overrides the label column. Null means "follow the layout".
  final double? labelWidth;

  @override
  Widget build(BuildContext context) {
    final layout = LayoutScope.of(context);
    // CAREFUL: labelColumnWidth is 132 at compact because that is FactRow's
    // literal, but InfoLine's is 140. Widening the token at medium+ is the
    // change; the compact branch must stay 140 or every profile header on the
    // phone shifts by 8 px.
    final width = labelWidth ?? (layout.width.atLeastMedium ? layout.labelColumnWidth : 140.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: width, child: Text(label, style: const TextStyle(color: AppColors.muted))),
          Expanded(child: Text(value == null || value!.isEmpty ? '—' : value!)),
        ],
      ),
    );
  }
}

/// Small numeric tile. Tonal rather than a card, so rows of them read as one
/// group; the caller decides the width (grid cell or Expanded).
class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.value, this.color, this.icon, this.onTap});

  final String label;
  final String value;
  final Color? color;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.primary;
    final layout = LayoutScope.of(context);
    final (valueSize, pad) = switch (layout.width) {
      WidthClass.compact => (22.0, 12.0),
      WidthClass.medium => (26.0, 14.0),
      WidthClass.expanded => (30.0, 16.0),
    };
    return Material(
      color: AppColors.surfaceAlt.withValues(alpha: 0.7),
      borderRadius: AppRadius.controlRadius,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.controlRadius,
        child: Padding(
          padding: EdgeInsets.all(pad),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 18, color: c), const SizedBox(height: 8)],
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: valueSize, fontWeight: FontWeight.w700, color: c, height: 1.1),
              ),
              const SizedBox(height: 2),
              Flexible(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows a snackbar with [message].
void showMessage(BuildContext context, String message, {bool error = false}) {
  // getInheritedWidgetOfExactType, not dependOnInheritedWidgetOfExactType:
  // this runs from a callback, not a build, so it must not register a
  // dependency on a context it does not own.
  final layout = context.getInheritedWidgetOfExactType<LayoutScope>()?.layout ?? AppLayout.compact;
  // SnackBar asserts that `width` is only set for floating behaviour, and the
  // app theme sets floating globally — but showMessage is called from screens
  // that a test may pump under a bare ThemeData, so ask rather than assume.
  final floating = Theme.of(context).snackBarTheme.behavior == SnackBarBehavior.floating;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? AppColors.danger : null,
      // Null at compact: today's snackbar spans the phone, which is right.
      // 1280 px of chrome for "Saved" is not.
      width: floating && layout.width.atLeastMedium ? 520 : null,
    ));
}

Future<bool> confirmDialog(BuildContext context, String message, {String? title}) async {
  final l10n = AppLocalizations.of(context);
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: title == null ? null : Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l10n.cancel)),
        FilledButton(onPressed: () => Navigator.of(context).pop(true), child: Text(l10n.confirm)),
      ],
    ),
  );
  return result == true;
}
