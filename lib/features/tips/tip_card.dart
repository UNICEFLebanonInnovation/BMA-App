import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import 'tips_controller.dart';

/// Dismissible contextual tip. Renders nothing once the signed-in user tapped
/// "Got it" (or when signed out).
class TipCard extends ConsumerWidget {
  const TipCard({super.key, required this.id, required this.text, this.icon = Icons.lightbulb_outline});

  /// One of TipIds.*
  final String id;

  /// Already localised by the caller (l10n.tipHomeSync …).
  final String text;

  final IconData icon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(currentProfileProvider)?.id;
    final dismissed = ref.watch(tipsControllerProvider.select((s) => s.isDismissed(userId, id)));
    if (userId == null || dismissed) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    return Card(
      key: ValueKey('tip-$id'),
      color: AppColors.secondary.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(12, 12, 12, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: AppColors.secondary),
                const SizedBox(width: 12),
                Expanded(child: Text(text)),
              ],
            ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                onPressed: () => ref.read(tipsControllerProvider.notifier).dismissTip(userId, id),
                child: Text(l10n.gotIt),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
