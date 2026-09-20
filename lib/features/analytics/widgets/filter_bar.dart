import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../../core/layout/app_layout.dart';
import '../../../core/theme/app_theme.dart';

/// The filter controls of a dashboard in one band above the charts: stacked
/// full-width on the phone, a wrapping row of 240 px fields from 600 px up.
class FilterBar extends StatelessWidget {
  const FilterBar({super.key, required this.children, this.trailing});

  final List<Widget> children;

  /// Reset and friends, kept at the end of the band.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final layout = LayoutScope.of(context);
    if (!layout.width.atLeastMedium) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final child in children) Padding(padding: const EdgeInsets.only(bottom: 8), child: child),
          if (trailing != null) Align(alignment: AlignmentDirectional.centerEnd, child: trailing),
        ],
      );
    }
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final child in children) SizedBox(width: 240, child: child),
        ?trailing,
      ],
    );
  }
}

/// A "pick one or all" dropdown. `null` is the "all" choice.
class FilterDropdown<T> extends StatelessWidget {
  const FilterDropdown({
    super.key,
    required this.label,
    required this.allLabel,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String allLabel;
  final T? value;

  /// `(value, label)` pairs.
  final List<(T, String)> options;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    // A value that is no longer among the options (the partner changed and
    // the centre list shrank) falls back to "all" rather than asserting.
    final effective = value != null && options.any((o) => o.$1 == value) ? value : null;
    return DropdownButtonFormField<T?>(
      initialValue: effective,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        DropdownMenuItem<T?>(value: null, child: Text(allLabel, overflow: TextOverflow.ellipsis)),
        for (final (v, text) in options)
          DropdownMenuItem<T?>(value: v, child: Text(text, overflow: TextOverflow.ellipsis)),
      ],
      onChanged: onChanged,
    );
  }
}

/// From / To date pickers with a clear action on each.
class DateRangeFilter extends StatelessWidget {
  const DateRangeFilter({
    super.key,
    required this.fromLabel,
    required this.toLabel,
    required this.anyLabel,
    required this.from,
    required this.to,
    required this.onChanged,
  });

  final String fromLabel;
  final String toLabel;
  final String anyLabel;
  final DateTime? from;
  final DateTime? to;
  final void Function(DateTime? from, DateTime? to) onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _DateField(
            key: const ValueKey('filter-date-from'),
            label: fromLabel,
            anyLabel: anyLabel,
            value: from,
            onPick: (d) => onChanged(d, to),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _DateField(
            key: const ValueKey('filter-date-to'),
            label: toLabel,
            anyLabel: anyLabel,
            value: to,
            onPick: (d) => onChanged(from, d),
          ),
        ),
      ],
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({super.key, required this.label, required this.anyLabel, required this.value, required this.onPick});

  final String label;
  final String anyLabel;
  final DateTime? value;
  final ValueChanged<DateTime?> onPick;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.maybeLocaleOf(context)?.toString();
    String text(DateTime d) {
      try {
        return DateFormat.yMMMd(locale).format(d);
      } catch (_) {
        return d.toIso8601String().split('T').first;
      }
    }

    return InkWell(
      onTap: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? now,
          firstDate: DateTime(2010),
          lastDate: DateTime(now.year + 1, 12, 31),
        );
        if (picked != null) onPick(DateTime(picked.year, picked.month, picked.day));
      },
      borderRadius: AppRadius.controlRadius,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: value == null
              ? const Icon(Icons.calendar_today_outlined, size: 18)
              : IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  tooltip: anyLabel,
                  onPressed: () => onPick(null),
                ),
        ),
        child: Text(
          value == null ? anyLabel : text(value!),
          style: TextStyle(color: value == null ? AppColors.muted : null),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

/// Simple numeric field for the age bounds.
class NumberFilterField extends StatelessWidget {
  const NumberFilterField({super.key, required this.label, required this.value, required this.onChanged});

  final String label;
  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: value?.toString() ?? '',
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label),
      onChanged: (text) => onChanged(int.tryParse(text.trim())),
    );
  }
}
