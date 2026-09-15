import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../layout/app_layout.dart';
import '../models/reference_item.dart';
import 'reference_cache.dart';

/// Bottom sheet with a search box listing the items of a reference kind.
/// Returns the selected item (single) or the selected ids (multi).
class ReferencePickerSheet extends ConsumerStatefulWidget {
  const ReferencePickerSheet({
    super.key,
    required this.kind,
    required this.title,
    required this.languageCode,
    this.multi = false,
    this.selectedIds = const {},
    this.filter,
  });

  final String kind;
  final String title;
  final String languageCode;
  final bool multi;
  final Set<int> selectedIds;
  final bool Function(ReferenceItem item)? filter;

  static Future<Object?> show(
    BuildContext context, {
    required String kind,
    required String title,
    required String languageCode,
    bool multi = false,
    Set<int> selectedIds = const {},
    bool Function(ReferenceItem item)? filter,
  }) {
    final body = ReferencePickerSheet(
      kind: kind,
      title: title,
      languageCode: languageCode,
      multi: multi,
      selectedIds: selectedIds,
      filter: filter,
    );
    // Modality is a DEVICE question, not a box question: a 1280x720 sheet to
    // pick one centre name puts its close button ~1200 px from the field that
    // opened it, and `autofocus` then raises a keyboard over the list.
    //
    // Read WITHOUT registering a dependency — this runs from a tap callback,
    // not from build. A screen that has not been converted yet has no scope
    // above it, and there the device question is all there is to ask.
    final scope = context.getInheritedWidgetOfExactType<LayoutScope>();
    final asDialog = scope == null ? isTabletDevice(context) : scope.layout.dialogPickers;
    if (asDialog) {
      // THE RETURN CONTRACT IS UNCHANGED: ReferenceItem for single, List<int>
      // for multi, null when dismissed. field_widgets.dart casts the result
      // with `(result as dynamic).id as int` and attendance_screen.dart does
      // an `is ReferenceItem` check, so a drift here fails at runtime in a
      // Makani centre, not at analyze time on a laptop.
      return showDialog<Object?>(
        context: context,
        useSafeArea: true,
        builder: (_) => Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
            child: body,
          ),
        ),
      );
    }
    return showModalBottomSheet<Object?>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => FractionallySizedBox(heightFactor: 0.9, child: body),
    );
  }

  @override
  ConsumerState<ReferencePickerSheet> createState() => _ReferencePickerSheetState();
}

class _ReferencePickerSheetState extends ConsumerState<ReferencePickerSheet> {
  late final Set<int> _selected = {...widget.selectedIds};
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(referenceListProvider(widget.kind));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Row(
            children: [
              Expanded(child: Text(widget.title, style: Theme.of(context).textTheme.titleMedium)),
              if (widget.multi)
                TextButton(
                  onPressed: () => Navigator.of(context).pop(_selected.toList()),
                  child: Text(MaterialLocalizations.of(context).okButtonLabel),
                ),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: TextField(
            autofocus: true,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search)),
            onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
          ),
        ),
        Expanded(
          child: items.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text(e.toString())),
            data: (list) {
              final filtered = list.where((item) {
                if (widget.filter != null && !widget.filter!(item)) return false;
                if (_query.isEmpty) return true;
                return item.name.toLowerCase().contains(_query) ||
                    (item.nameEn?.toLowerCase().contains(_query) ?? false) ||
                    item.extra.values.any((v) => v != null && v.toString().toLowerCase().contains(_query));
              }).toList();
              if (filtered.isEmpty) {
                return const Center(child: Text('—'));
              }
              return ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final item = filtered[index];
                  final subtitle = _subtitle(item);
                  if (widget.multi) {
                    return CheckboxListTile(
                      value: _selected.contains(item.id),
                      title: Text(item.labelFor(widget.languageCode)),
                      subtitle: subtitle == null ? null : Text(subtitle),
                      onChanged: (checked) => setState(() {
                        if (checked == true) {
                          _selected.add(item.id);
                        } else {
                          _selected.remove(item.id);
                        }
                      }),
                    );
                  }
                  return ListTile(
                    title: Text(item.labelFor(widget.languageCode)),
                    subtitle: subtitle == null ? null : Text(subtitle),
                    selected: widget.selectedIds.contains(item.id),
                    onTap: () => Navigator.of(context).pop(item),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  String? _subtitle(ReferenceItem item) {
    final number = item.extra['number'];
    final other = widget.languageCode == 'ar' ? item.nameEn : null;
    final parts = [if (number != null) number.toString(), if (other != null && other != item.name) other];
    return parts.isEmpty ? null : parts.join(' · ');
  }
}
