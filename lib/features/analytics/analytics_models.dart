// Value types shared by every analytics dashboard: what a chart is fed with,
// and the filter set the NFE Advanced Analytics endpoints accept.
//
// Everything here is plain Dart on purpose (no Flutter import), so the
// compute layers in nfe/ and alp/ and their unit tests never need a widget
// tree. Labels are resolved by the caller: a [ChartItem] carries the RAW key
// the server would have grouped on (`Male`, a nationality id, a programme
// value) next to the localised label, so colours can follow the entity across
// languages and filters — the web dashboards recolour on every refresh, which
// the data-viz rules this port follows forbid.
import 'package:flutter/foundation.dart' show immutable;

/// One bar, slice or legend entry of a breakdown.
@immutable
class ChartItem {
  const ChartItem({required this.key, required this.label, required this.count});

  /// Stable identity of the category, independent of the interface language.
  final String key;

  /// What the reader sees.
  final String label;
  final int count;

  ChartItem copyWith({String? label, int? count}) =>
      ChartItem(key: key, label: label ?? this.label, count: count ?? this.count);

  @override
  bool operator ==(Object other) =>
      other is ChartItem && other.key == key && other.label == label && other.count == count;

  @override
  int get hashCode => Object.hash(key, label, count);

  @override
  String toString() => 'ChartItem($key=$count)';
}

/// One day of a daily series.
@immutable
class TrendPoint {
  const TrendPoint(this.day, this.count);

  /// Date-only (midnight, local).
  final DateTime day;
  final int count;

  @override
  bool operator ==(Object other) => other is TrendPoint && other.day == day && other.count == count;

  @override
  int get hashCode => Object.hash(day, count);

  @override
  String toString() => 'TrendPoint(${day.toIso8601String().split('T').first}=$count)';
}

/// A two-dimensional count matrix, rows × columns.
@immutable
class Crosstab {
  const Crosstab({required this.rows, required this.columns, required this.counts});

  /// Row labels (already localised) in display order.
  final List<String> rows;

  /// Column labels in display order.
  final List<String> columns;

  /// `counts[row][column]`; a missing entry is zero.
  final Map<String, Map<String, int>> counts;

  int at(String row, String column) => counts[row]?[column] ?? 0;

  int rowTotal(String row) => (counts[row] ?? const {}).values.fold(0, (a, b) => a + b);

  int columnTotal(String column) => rows.fold(0, (sum, r) => sum + at(r, column));

  int get total => rows.fold(0, (sum, r) => sum + rowTotal(r));

  int get maxCount {
    var max = 0;
    for (final r in counts.values) {
      for (final c in r.values) {
        if (c > max) max = c;
      }
    }
    return max;
  }

  bool get isEmpty => rows.isEmpty || columns.isEmpty || total == 0;

  static const empty = Crosstab(rows: [], columns: [], counts: {});
}

/// Attendance recorded on one day: how many rows the sheets held and how many
/// of them were marked absent. Mirrors the `total` / `absent` pair the web
/// heatmap views aggregate.
@immutable
class HeatCell {
  const HeatCell({required this.date, required this.total, required this.absent});

  /// Date-only (midnight, local).
  final DateTime date;
  final int total;
  final int absent;

  int get present => total - absent;

  /// 0..1; zero when nothing was recorded.
  double get rate => total == 0 ? 0 : present / total;

  HeatCell add(int moreTotal, int moreAbsent) =>
      HeatCell(date: date, total: total + moreTotal, absent: absent + moreAbsent);

  @override
  bool operator ==(Object other) =>
      other is HeatCell && other.date == date && other.total == total && other.absent == absent;

  @override
  int get hashCode => Object.hash(date, total, absent);

  @override
  String toString() => 'HeatCell(${date.toIso8601String().split('T').first} $present/$total)';
}

/// One horizontal bar made of several stacked segments (one per series).
@immutable
class StackedRow {
  const StackedRow({required this.key, required this.label, required this.values});

  final String key;
  final String label;

  /// One value per series, in the series order the chart was given.
  final List<int> values;

  int get total => values.fold(0, (a, b) => a + b);
}

/// The filter set of the NFE Advanced Analytics API
/// (`analytics_base_queryset` in BMA-NFE's dashboard/views.py). Every field is
/// optional; an empty filter is the whole scope.
@immutable
class AnalyticsFilters {
  const AnalyticsFilters({
    this.dateFrom,
    this.dateTo,
    this.partnerId,
    this.centerId,
    this.programme,
    this.nationalityId,
    this.gender,
    this.ageMin,
    this.ageMax,
  });

  /// Inclusive, date-only bounds on the registration's `created` timestamp.
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final int? partnerId;
  final int? centerId;

  /// Raw `education_program` value of the latest education service.
  final String? programme;
  final int? nationalityId;

  /// Raw gender value (`Male` / `Female`).
  final String? gender;
  final int? ageMin;
  final int? ageMax;

  static const none = AnalyticsFilters();

  bool get hasDateRange => dateFrom != null || dateTo != null;

  bool get isEmpty =>
      dateFrom == null &&
      dateTo == null &&
      partnerId == null &&
      centerId == null &&
      programme == null &&
      nationalityId == null &&
      gender == null &&
      ageMin == null &&
      ageMax == null;

  /// `copyWith` that can also CLEAR a field: pass `clearX: true`.
  AnalyticsFilters copyWith({
    DateTime? dateFrom,
    bool clearDateFrom = false,
    DateTime? dateTo,
    bool clearDateTo = false,
    int? partnerId,
    bool clearPartner = false,
    int? centerId,
    bool clearCenter = false,
    String? programme,
    bool clearProgramme = false,
    int? nationalityId,
    bool clearNationality = false,
    String? gender,
    bool clearGender = false,
    int? ageMin,
    bool clearAgeMin = false,
    int? ageMax,
    bool clearAgeMax = false,
  }) =>
      AnalyticsFilters(
        dateFrom: clearDateFrom ? null : (dateFrom ?? this.dateFrom),
        dateTo: clearDateTo ? null : (dateTo ?? this.dateTo),
        partnerId: clearPartner ? null : (partnerId ?? this.partnerId),
        centerId: clearCenter ? null : (centerId ?? this.centerId),
        programme: clearProgramme ? null : (programme ?? this.programme),
        nationalityId: clearNationality ? null : (nationalityId ?? this.nationalityId),
        gender: clearGender ? null : (gender ?? this.gender),
        ageMin: clearAgeMin ? null : (ageMin ?? this.ageMin),
        ageMax: clearAgeMax ? null : (ageMax ?? this.ageMax),
      );

  @override
  bool operator ==(Object other) =>
      other is AnalyticsFilters &&
      other.dateFrom == dateFrom &&
      other.dateTo == dateTo &&
      other.partnerId == partnerId &&
      other.centerId == centerId &&
      other.programme == programme &&
      other.nationalityId == nationalityId &&
      other.gender == gender &&
      other.ageMin == ageMin &&
      other.ageMax == ageMax;

  @override
  int get hashCode =>
      Object.hash(dateFrom, dateTo, partnerId, centerId, programme, nationalityId, gender, ageMin, ageMax);

  @override
  String toString() =>
      'AnalyticsFilters($dateFrom..$dateTo p=$partnerId c=$centerId prog=$programme nat=$nationalityId '
      'g=$gender age=$ageMin..$ageMax)';
}

// ----------------------------------------------------------------- helpers

/// Midnight of [d] in the local zone, so two timestamps of one day compare equal.
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Parses the ISO strings the server sends (`2026-09-12T21:43:26.028938`,
/// `2026-09-12`) and anything `DateTime.tryParse` accepts. Null for blanks.
DateTime? parseDate(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  if (text.isEmpty) return null;
  return DateTime.tryParse(text);
}

/// Turns a `{key: count}` tally into chart items sorted by count (largest
/// first) and then by label, which is the `order_by('-count', field)` the
/// breakdown endpoints use.
List<ChartItem> itemsFromTally(Map<String, int> tally, String Function(String key) labelOf) {
  final items = [for (final e in tally.entries) ChartItem(key: e.key, label: labelOf(e.key), count: e.value)];
  items.sort((a, b) {
    final byCount = b.count.compareTo(a.count);
    return byCount != 0 ? byCount : a.label.toLowerCase().compareTo(b.label.toLowerCase());
  });
  return items;
}

/// Keeps the [keep] largest items and folds the rest into one `Other` entry.
///
/// The data-viz rule behind it: a categorical palette has eight slots and a
/// ninth hue is never generated, so a donut or a legend past that folds its
/// tail. Bars are not folded — a long bar list is scrollable and reads fine.
List<ChartItem> foldTail(List<ChartItem> items, {int keep = 7, required String otherLabel}) {
  if (items.length <= keep + 1) return items;
  final head = items.take(keep).toList();
  final rest = items.skip(keep).fold(0, (sum, i) => sum + i.count);
  return [...head, ChartItem(key: '__other__', label: otherLabel, count: rest)];
}

/// Sum of the counts.
int totalOf(Iterable<ChartItem> items) => items.fold(0, (sum, i) => sum + i.count);

/// Percentage with one decimal, as the web dashboards print it (`72.3`).
String percentText(num part, num whole) {
  if (whole == 0) return '0';
  final value = part * 100 / whole;
  final rounded = (value * 10).round() / 10;
  return rounded == rounded.roundToDouble() ? rounded.toInt().toString() : rounded.toStringAsFixed(1);
}

/// One-slot memo for a dashboard's computed figures.
///
/// The screens recompute inside a `FutureBuilder`'s builder, which runs on
/// every frame the page rebuilds — a dropdown opening, a keyboard animating,
/// a snackbar sliding. Reducing a few thousand registrations eleven ways is
/// ~10 ms, enough to drop frames through an animation but nothing to fear
/// once per filter change, so the answer is kept until its inputs differ.
///
/// Deliberately one slot: a dashboard shows one filter set at a time, and a
/// growing cache of results the user has walked past is a memory leak with
/// extra steps. [source] is compared by IDENTITY (it is the loaded record
/// set, replaced wholesale when the data version moves) and [key] by value.
class ComputeMemo<S, K, V> {
  S? _source;
  K? _key;
  V? _value;

  /// Explicit rather than inferred from `_value != null`: a computation whose
  /// answer is legitimately null would otherwise re-run on every frame.
  bool _filled = false;

  V of(S source, K key, V Function() compute) {
    if (_filled && identical(_source, source) && _key == key) return _value as V;
    final value = compute();
    _source = source;
    _key = key;
    _value = value;
    _filled = true;
    return value;
  }
}
