import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../models/entity_record.dart';
import '../sync/connectivity_service.dart';
import '../theme/app_theme.dart';

/// Coloured chip describing the local sync state of a record.
class SyncStateChip extends StatelessWidget {
  const SyncStateChip(this.state, {super.key, this.compact = false});

  final SyncState state;
  final bool compact;

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
    if (compact) {
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: AppColors.muted),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: TextField(
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search),
          hintText: hint ?? AppLocalizations.of(context).searchHint,
        ),
        textInputAction: TextInputAction.search,
        onChanged: onChanged,
      ),
    );
  }
}

/// Key/value line used in profile headers and reports.
class InfoLine extends StatelessWidget {
  const InfoLine(this.label, this.value, {super.key});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 140, child: Text(label, style: const TextStyle(color: AppColors.muted))),
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
    return Material(
      color: AppColors.surfaceAlt.withValues(alpha: 0.7),
      borderRadius: AppRadius.controlRadius,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.controlRadius,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 18, color: c), const SizedBox(height: 8)],
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: c, height: 1.1),
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
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? AppColors.danger : null,
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
