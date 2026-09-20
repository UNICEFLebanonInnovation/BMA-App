// The NFE Advanced Analytics figures, computed from the records on the
// device. A port of BMA-NFE's `student_registration/dashboard/views.py`
// (`analytics_base_queryset`, `analytics_summary`, `analytics_trend`,
// `analytics_breakdown`, `analytics_teacher_breakdown`, `analytics_crosstab`):
// same filters, same dimensions, same age buckets, same trend window.
//
// Pure Dart: the screen loads the records and reference lists, this file only
// counts. Every rule that mirrors a server line says which one.
import '../../../core/config/app_config.dart';
import '../../../core/models/entity_record.dart';
import '../../../core/models/reference_item.dart';
import '../../registrations/registration_helpers.dart';
import '../analytics_models.dart';

/// Localised words the counts need. Passed in so this file has no
/// AppLocalizations dependency and can be unit-tested with plain strings.
class AnalyticsLabels {
  const AnalyticsLabels({
    required this.unknown,
    required this.male,
    required this.female,
    required this.other,
  });

  final String unknown;
  final String male;
  final String female;
  final String other;

  /// `Male` / `Female` as the server stores them; anything else is shown as is,
  /// and a blank is "Unknown".
  String gender(String raw) => switch (raw) {
        'Male' => male,
        'Female' => female,
        '' => unknown,
        _ => raw,
      };

  static const english = AnalyticsLabels(unknown: 'Unknown', male: 'Male', female: 'Female', other: 'Other');
}

/// The age buckets of `_annotate_age`, in display order. `Unknown` is the
/// server's own key for a missing or malformed birth year.
const nfeAgeGroups = ['0-4', '5-11', '12-14', '15-17', '18+', 'Unknown'];

/// `ExtractYear(Now()) - birth_year`, bucketed exactly as the server does.
/// The web derives age from the YEAR only, which is why this does not reuse
/// `RegistrationView.age` (a full birthday age).
String nfeAgeGroup(int? ageYears) {
  if (ageYears == null) return 'Unknown';
  if (ageYears <= 4) return '0-4';
  if (ageYears <= 11) return '5-11';
  if (ageYears <= 14) return '12-14';
  if (ageYears <= 17) return '15-17';
  return '18+';
}

/// A four-digit birth year, or null — the server's `^\d{4}$` regex.
int? parseBirthYear(Object? value) {
  final text = (value ?? '').toString().trim();
  if (!RegExp(r'^\d{4}$').hasMatch(text)) return null;
  return int.parse(text);
}

/// Everything the NFE analytics count over.
class NfeAnalyticsSource {
  const NfeAnalyticsSource({
    required this.registrations,
    required this.educationServices,
    required this.teachers,
    required this.centers,
    required this.partners,
    required this.nationalities,
    required this.programmeLabels,
    required this.language,
    required this.today,
    this.defaultPartnerId,
    this.defaultCenterId,
  });

  /// `mscc.registration` records, both shapes.
  final List<EntityRecord> registrations;

  /// `mscc.education_service` records, for registrations typed offline whose
  /// latest programme is not embedded in an `education_summary`.
  final List<EntityRecord> educationServices;

  /// `mscc.teacher` records.
  final List<EntityRecord> teachers;
  final Map<int, ReferenceItem> centers;
  final Map<int, ReferenceItem> partners;
  final Map<int, ReferenceItem> nationalities;

  /// `education_program` value → label, from the shared choice list.
  final Map<String, String> programmeLabels;
  final String language;

  /// Date-only. Injected so tests are stable.
  final DateTime today;

  /// The account's partner / centre: what the server would force onto a
  /// record typed offline, so a pending registration counts where it will land.
  final int? defaultPartnerId;
  final int? defaultCenterId;
}

/// One registration reduced to the fields the dashboard groups and filters on.
class NfeRegistrationRow {
  const NfeRegistrationRow({
    required this.created,
    required this.partnerId,
    required this.partnerLabel,
    required this.centerId,
    required this.centerLabel,
    required this.gender,
    required this.nationalityId,
    required this.nationalityLabel,
    required this.ageYears,
    required this.programme,
    required this.programmeLabel,
  });

  /// Date-only `created`, or null when nothing dates the record.
  final DateTime? created;
  final int? partnerId;
  final String partnerLabel;
  final int? centerId;
  final String centerLabel;

  /// Raw `Male` / `Female` / `''`.
  final String gender;
  final int? nationalityId;
  final String nationalityLabel;
  final int? ageYears;

  /// Raw `education_program` of the latest education service, or `Unknown`.
  final String programme;
  final String programmeLabel;

  String get ageGroup => nfeAgeGroup(ageYears);
}

class NfeTeacherRow {
  const NfeTeacherRow({
    required this.created,
    required this.partnerId,
    required this.centerId,
    required this.centerLabel,
    required this.sex,
    required this.nationalityId,
    required this.nationalityLabel,
  });

  final DateTime? created;
  final int? partnerId;
  final int? centerId;
  final String centerLabel;
  final String sex;
  final int? nationalityId;
  final String nationalityLabel;
}

class NfeSummary {
  const NfeSummary({
    required this.totalRegistrations,
    required this.totalTeachers,
    required this.partners,
    required this.centers,
    required this.programmes,
  });

  final int totalRegistrations;
  final int totalTeachers;
  final int partners;
  final int centers;
  final int programmes;
}

class NfeAnalytics {
  const NfeAnalytics({
    required this.summary,
    required this.trend,
    required this.trendIsWindow,
    required this.trendDays,
    required this.byCenter,
    required this.byGender,
    required this.byNationality,
    required this.byPartner,
    required this.byProgramme,
    required this.byAgeGroup,
    required this.teachersBySex,
    required this.teachersByNationality,
    required this.teachersByCenter,
    required this.programmeByAgeGroup,
  });

  final NfeSummary summary;
  final List<TrendPoint> trend;

  /// True when no date range was set and the trend shows the last
  /// [trendDays] days, as the web page does by default.
  final bool trendIsWindow;
  final int trendDays;
  final List<ChartItem> byCenter;
  final List<ChartItem> byGender;
  final List<ChartItem> byNationality;
  final List<ChartItem> byPartner;
  final List<ChartItem> byProgramme;
  final List<ChartItem> byAgeGroup;
  final List<ChartItem> teachersBySex;
  final List<ChartItem> teachersByNationality;
  final List<ChartItem> teachersByCenter;
  final Crosstab programmeByAgeGroup;

  bool get isEmpty => summary.totalRegistrations == 0 && summary.totalTeachers == 0;
}

int? _int(Object? value) => value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');

DateTime? _createdOf(EntityRecord record) {
  final created = parseDate(record.data['created']) ?? parseDate(record.createdAt) ?? parseDate(record.data['registration_date']);
  return created == null ? null : dateOnly(created);
}

/// Reduces the source records to rows. Public so the reduction (the part
/// that reads two record shapes) can be tested on its own.
List<NfeRegistrationRow> nfeRegistrationRows(NfeAnalyticsSource src, AnalyticsLabels labels) {
  // EVERY education service, grouped by parent — not one "latest" per parent.
  // Collapsing them here with a rule of its own would decide the answer
  // before the candidate sort below can: a pulled service carries a server id
  // and a locally typed one does not, so "highest id wins" would drop the
  // local row that is in fact the newest thing on the device.
  final servicesByParentUuid = <String, List<EntityRecord>>{};
  final servicesByParentId = <int, List<EntityRecord>>{};
  for (final s in src.educationServices) {
    if (s.deleted || s.syncState == SyncState.discarded) continue;
    if (s.parentUuid != null) servicesByParentUuid.putIfAbsent(s.parentUuid!, () => []).add(s);
    if (s.parentServerId != null) servicesByParentId.putIfAbsent(s.parentServerId!, () => []).add(s);
  }

  final rows = <NfeRegistrationRow>[];
  for (final record in src.registrations) {
    if (record.deleted || record.syncState == SyncState.discarded) continue;
    final view = RegistrationView(record);
    final data = record.data;

    // THE LATEST EDUCATION SERVICE, wherever it is stored. The server takes
    // the one with the highest id (`_latest_programme_subquery`); on the
    // device that row can live in three places: the `education_summary` the
    // pull embeds, a pulled `mscc.education_service` record, or one typed
    // offline that has no id yet. A service typed offline is by construction
    // newer than anything pulled before it, so it wins — reading the embedded
    // summary first left a child who was moved to a new programme in the
    // field counted under the old one until the next push.
    final candidates = <({String value, int id, bool isLocal})>[
      for (final entry in view.educationSummary)
        if ((entry['education_program']?.toString() ?? '').isNotEmpty)
          (value: entry['education_program'].toString(), id: _int(entry['id']) ?? -1, isLocal: false),
      for (final service in {
        ...?servicesByParentUuid[record.uuid],
        if (record.serverId != null) ...?servicesByParentId[record.serverId!],
      })
        if ((service.data['education_program']?.toString() ?? '').isNotEmpty)
          (
            value: service.data['education_program'].toString(),
            id: _int(service.data['id']) ?? -1,
            isLocal: service.serverId == null,
          ),
    ];
    candidates.sort((a, b) {
      if (a.isLocal != b.isLocal) return a.isLocal ? 1 : -1;
      return a.id.compareTo(b.id);
    });
    final programme = candidates.isEmpty ? 'Unknown' : candidates.last.value;

    // THE ACCOUNT'S SCOPE IS A DEFAULT FOR LOCAL WORK ONLY. The server forces
    // its centre and partner onto anything typed offline, so a pending record
    // is counted where it will land. A record that HAS reached the server and
    // still carries no centre genuinely has none, and inventing one here would
    // move rows into a centre the website's own count leaves out.
    final local = record.serverId == null;
    final centerId = _int(data['center']) ?? (local ? src.defaultCenterId : null);
    final center = centerId == null ? null : src.centers[centerId];
    final partnerId =
        _int(data['partner']) ?? _int(center?.extra['partner_id']) ?? (local ? src.defaultPartnerId : null);
    final partner = partnerId == null ? null : src.partners[partnerId];
    final nationalityId = _int(view.nationalityId);
    final nationality = nationalityId == null ? null : src.nationalities[nationalityId];
    final birthYear = parseBirthYear(view.person?['birthday_year'] ?? view.flat['child_birthday_year']);

    rows.add(NfeRegistrationRow(
      created: _createdOf(record),
      partnerId: partnerId,
      partnerLabel: partner?.labelFor(src.language) ?? data['partner_label']?.toString() ?? labels.unknown,
      centerId: centerId,
      centerLabel: center?.labelFor(src.language) ?? data['center_label']?.toString() ?? labels.unknown,
      gender: (view.gender ?? '').trim(),
      nationalityId: nationalityId,
      nationalityLabel: nationality?.labelFor(src.language) ??
          ((view.nationalityLabel?.isNotEmpty ?? false) ? view.nationalityLabel! : labels.unknown),
      ageYears: birthYear == null ? null : src.today.year - birthYear,
      programme: programme,
      programmeLabel: programme == 'Unknown' ? labels.unknown : (src.programmeLabels[programme] ?? programme),
    ));
  }
  return rows;
}

List<NfeTeacherRow> nfeTeacherRows(NfeAnalyticsSource src, AnalyticsLabels labels) {
  final rows = <NfeTeacherRow>[];
  for (final record in src.teachers) {
    if (record.deleted || record.syncState == SyncState.discarded) continue;
    final data = record.data;
    // Same rule as the registrations above. The partner comes only from the
    // centre, exactly as `center__partner_id` does: a teacher whose centre is
    // not on this device matches no partner rather than the account's.
    final local = record.serverId == null;
    final centerId = _int(data['center']) ?? (local ? src.defaultCenterId : null);
    final center = centerId == null ? null : src.centers[centerId];
    final partnerId = _int(center?.extra['partner_id']) ?? (local ? src.defaultPartnerId : null);
    final nationalityId = _int(data['nationality']);
    final nationality = nationalityId == null ? null : src.nationalities[nationalityId];
    final label = data['nationality_label']?.toString();
    rows.add(NfeTeacherRow(
      created: _createdOf(record),
      partnerId: partnerId,
      centerId: centerId,
      centerLabel: center?.labelFor(src.language) ?? data['center_label']?.toString() ?? labels.unknown,
      sex: (data['sex'] ?? data['gender'] ?? '').toString().trim(),
      nationalityId: nationalityId,
      nationalityLabel: nationality?.labelFor(src.language) ?? ((label?.isNotEmpty ?? false) ? label! : labels.unknown),
    ));
  }
  return rows;
}

bool _inDateRange(DateTime? day, AnalyticsFilters f) {
  if (f.dateFrom == null && f.dateTo == null) return true;
  if (day == null) return false;
  if (f.dateFrom != null && day.isBefore(dateOnly(f.dateFrom!))) return false;
  if (f.dateTo != null && day.isAfter(dateOnly(f.dateTo!))) return false;
  return true;
}

/// `analytics_base_queryset`: every filter the endpoints accept.
bool nfeRowMatches(NfeRegistrationRow row, AnalyticsFilters f) {
  if (!_inDateRange(row.created, f)) return false;
  if (f.partnerId != null && row.partnerId != f.partnerId) return false;
  if (f.centerId != null && row.centerId != f.centerId) return false;
  if (f.programme != null && row.programme != f.programme) return false;
  if (f.nationalityId != null && row.nationalityId != f.nationalityId) return false;
  if (f.gender != null && row.gender != f.gender) return false;
  // `age_years__gte` / `__lte`: a null age never satisfies a bound.
  if (f.ageMin != null && (row.ageYears == null || row.ageYears! < f.ageMin!)) return false;
  if (f.ageMax != null && (row.ageYears == null || row.ageYears! > f.ageMax!)) return false;
  return true;
}

/// `teacher_analytics_base_queryset`: date range, partner (through the
/// centre) and centre only.
bool nfeTeacherMatches(NfeTeacherRow row, AnalyticsFilters f) {
  if (!_inDateRange(row.created, f)) return false;
  if (f.partnerId != null && row.partnerId != f.partnerId) return false;
  if (f.centerId != null && row.centerId != f.centerId) return false;
  return true;
}

/// Computes every panel of the dashboard for [filters].
NfeAnalytics computeNfeAnalytics(
  NfeAnalyticsSource src,
  AnalyticsFilters filters, {
  AnalyticsLabels labels = AnalyticsLabels.english,
  int trendDays = 30,
}) {
  final rows = nfeRegistrationRows(src, labels).where((r) => nfeRowMatches(r, filters)).toList();
  final teachers = nfeTeacherRows(src, labels).where((t) => nfeTeacherMatches(t, filters)).toList();

  // --- summary: `values(field).distinct().count()` counts a null as a value.
  final summary = NfeSummary(
    totalRegistrations: rows.length,
    totalTeachers: teachers.length,
    partners: rows.map((r) => r.partnerId).toSet().length,
    centers: rows.map((r) => r.centerId).toSet().length,
    programmes: rows.map((r) => r.programme).toSet().length,
  );

  // --- trend: last N days unless a date range was given; the series runs
  // from the first to the last day that has a count, or the window when none.
  final windowed = !filters.hasDateRange;
  // Calendar arithmetic, not a Duration: subtracting 29x24h from a local
  // midnight lands on 01:00 of the intended day across an autumn fall-back,
  // and the `isBefore` below would then drop that whole day from the trend.
  final windowStart = DateTime(src.today.year, src.today.month, src.today.day - (trendDays - 1));
  final byDay = <DateTime, int>{};
  for (final r in rows) {
    final day = r.created;
    if (day == null) continue;
    if (windowed && day.isBefore(windowStart)) continue;
    byDay.update(day, (v) => v + 1, ifAbsent: () => 1);
  }
  DateTime start;
  DateTime end;
  if (byDay.isEmpty) {
    end = src.today;
    start = windowStart;
  } else {
    start = byDay.keys.reduce((a, b) => a.isBefore(b) ? a : b);
    end = byDay.keys.reduce((a, b) => a.isAfter(b) ? a : b);
  }
  final trend = <TrendPoint>[];
  for (var d = start; !d.isAfter(end); d = DateTime(d.year, d.month, d.day + 1)) {
    trend.add(TrendPoint(d, byDay[d] ?? 0));
  }

  // --- breakdowns, `order_by('-count', field)`.
  List<ChartItem> breakdown(String Function(NfeRegistrationRow) key, String Function(NfeRegistrationRow) label) {
    final tally = <String, int>{};
    final labelOf = <String, String>{};
    for (final r in rows) {
      final k = key(r);
      tally.update(k, (v) => v + 1, ifAbsent: () => 1);
      labelOf[k] = label(r);
    }
    return itemsFromTally(tally, (k) => labelOf[k] ?? k);
  }

  List<ChartItem> teacherBreakdown(String Function(NfeTeacherRow) key, String Function(NfeTeacherRow) label) {
    final tally = <String, int>{};
    final labelOf = <String, String>{};
    for (final t in teachers) {
      final k = key(t);
      tally.update(k, (v) => v + 1, ifAbsent: () => 1);
      labelOf[k] = label(t);
    }
    return itemsFromTally(tally, (k) => labelOf[k] ?? k);
  }

  String genderKey(String raw) => raw.isEmpty ? 'Unknown' : raw;

  // --- cross-tab, programme rows by size, age groups in bucket order.
  final counts = <String, Map<String, int>>{};
  final programmeLabelOf = <String, String>{};
  for (final r in rows) {
    programmeLabelOf[r.programme] = r.programmeLabel;
    counts.putIfAbsent(r.programme, () => {}).update(r.ageGroup, (v) => v + 1, ifAbsent: () => 1);
  }
  final programmeOrder = counts.keys.toList()
    ..sort((a, b) {
      final ta = counts[a]!.values.fold(0, (x, y) => x + y);
      final tb = counts[b]!.values.fold(0, (x, y) => x + y);
      return tb != ta ? tb.compareTo(ta) : a.compareTo(b);
    });
  final presentGroups = {for (final c in counts.values) ...c.keys};
  final ageLabel = {for (final g in nfeAgeGroups) g: g == 'Unknown' ? labels.unknown : g};
  final crosstab = Crosstab(
    rows: [for (final p in programmeOrder) programmeLabelOf[p]!],
    columns: [for (final g in nfeAgeGroups) if (presentGroups.contains(g)) ageLabel[g]!],
    counts: {
      for (final p in programmeOrder)
        programmeLabelOf[p]!: {for (final e in counts[p]!.entries) ageLabel[e.key]!: e.value},
    },
  );

  return NfeAnalytics(
    summary: summary,
    trend: trend,
    trendIsWindow: windowed,
    trendDays: trendDays,
    byCenter: breakdown((r) => '${r.centerId ?? ''}', (r) => r.centerLabel),
    byGender: breakdown((r) => genderKey(r.gender), (r) => labels.gender(r.gender)),
    byNationality: breakdown((r) => '${r.nationalityId ?? ''}', (r) => r.nationalityLabel),
    byPartner: breakdown((r) => '${r.partnerId ?? ''}', (r) => r.partnerLabel),
    byProgramme: breakdown((r) => r.programme, (r) => r.programmeLabel),
    byAgeGroup: breakdown((r) => r.ageGroup, (r) => ageLabel[r.ageGroup]!),
    teachersBySex: teacherBreakdown((t) => genderKey(t.sex), (t) => labels.gender(t.sex)),
    teachersByNationality: teacherBreakdown((t) => '${t.nationalityId ?? ''}', (t) => t.nationalityLabel),
    teachersByCenter: teacherBreakdown((t) => '${t.centerId ?? ''}', (t) => t.centerLabel),
    programmeByAgeGroup: crosstab,
  );
}

/// The entity keys this dashboard reads, for the loader.
class NfeAnalyticsEntities {
  NfeAnalyticsEntities._();

  static const registration = Entities.msccRegistration;
  static const educationService = Entities.msccEducationService;
  static const teacher = Entities.msccTeacher;
}
