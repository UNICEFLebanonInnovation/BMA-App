import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/config/settings_controller.dart';
import '../../../core/db/entity_dao.dart';
import '../../../core/db/providers.dart';
import '../../../core/forms/reference_cache.dart';
import '../../../core/layout/adaptive.dart';
import '../../../core/layout/app_layout.dart';
import '../../../core/layout/breakpoints.dart';
import '../../../core/models/reference_item.dart';
import '../../../core/sync/connectivity_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/ui.dart';
import '../../../l10n/app_localizations.dart';
import '../analytics_models.dart';
import '../charts/chart_card.dart';
import '../widgets/filter_bar.dart';
import 'alp_registration_insights.dart' show AlpAnalyticsEntities;
import 'alp_school_map_data.dart';

/// Whether the map may fetch its background tiles. Tiles are the one part of
/// this app that needs the network, so they are behind a provider a test (and
/// a future "save data" setting) can turn off; the markers are placed from the
/// coordinates the bootstrap already downloaded and work offline either way.
final mapTilesEnabledProvider = Provider<bool>((ref) => true);

/// Lebanon, at the zoom the web page opens on.
const _lebanon = LatLng(33.8547, 35.8623);
const _initialZoom = 8.0;

/// The web platform's ALP school dashboard, computed on the device: four
/// headline figures and the school locations map, filterable by school, with
/// the operational detail of each school behind its marker.
class AlpSchoolDashboardScreen extends ConsumerStatefulWidget {
  const AlpSchoolDashboardScreen({super.key});

  @override
  ConsumerState<AlpSchoolDashboardScreen> createState() => _AlpSchoolDashboardScreenState();
}

class _AlpSchoolDashboardScreenState extends ConsumerState<AlpSchoolDashboardScreen> {
  final MapController _map = MapController();
  int? _schoolId;
  final _memo = ComputeMemo<AlpSchoolSource, (int?, String), AlpSchoolDashboard>();
  Future<AlpSchoolSource>? _future;
  String? _loadKey;

  /// Set after a filter change so the camera is refitted once the new markers
  /// are laid out; doing it during build would move a map mid-frame.
  bool _refitPending = false;

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  Future<AlpSchoolSource> _load(int dataVersion, String language) {
    final key = '$dataVersion|$language';
    if (_future == null || key != _loadKey) {
      _loadKey = key;
      _future = _read(language);
    }
    return _future!;
  }

  Future<AlpSchoolSource> _read(String language) async {
    final dao = ref.read(entityDaoProvider);
    final cache = ref.read(referenceCacheProvider);
    final profile = ref.read(currentProfileProvider);
    final registrations =
        await dao.list(const RecordQuery(entity: AlpAnalyticsEntities.registration, limit: 50000));
    final teachers = await dao.list(const RecordQuery(entity: AlpAnalyticsEntities.teacher, limit: 20000));
    final profiles = await dao.list(const RecordQuery(entity: AlpAnalyticsEntities.schoolProfile, limit: 500));
    final schools = await cache.ensure('schools');
    final locations = await cache.ensure('locations');
    return AlpSchoolSource(
      schools: alpSchoolsInScope(
        schools: schools.values,
        registrations: registrations,
        teachers: teachers,
        accountSchoolId: profile?.school?.id,
      )..sort((a, b) => a.labelFor(language).toLowerCase().compareTo(b.labelFor(language).toLowerCase())),
      registrations: registrations,
      teachers: teachers,
      schoolProfiles: profiles,
      locations: locations,
      language: language,
      defaultSchoolId: profile?.school?.id,
    );
  }

  void _select(int? id) {
    setState(() {
      _schoolId = id;
      _refitPending = true;
    });
  }

  void _fit(List<MappedSchool> schools) {
    if (schools.isEmpty) return;
    final points = [for (final s in schools) LatLng(s.latitude, s.longitude)];
    if (points.length == 1) {
      _map.move(points.single, 13);
      return;
    }
    _map.fitCamera(CameraFit.bounds(
      bounds: LatLngBounds.fromPoints(points),
      padding: const EdgeInsets.all(40),
      maxZoom: 15,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final dataVersion = ref.watch(dataVersionProvider);
    final language = ref.watch(settingsControllerProvider).locale.languageCode;
    final tiles = ref.watch(mapTilesEnabledProvider) && ref.watch(isOnlineProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.alpSchoolDashboard)),
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(
            child: FutureBuilder<AlpSchoolSource>(
              future: _load(dataVersion, language),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return EmptyState(message: snapshot.error.toString(), icon: Icons.error_outline);
                }
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                final source = snapshot.data!;
                final dashboard = _memo.of(
                  source,
                  (_schoolId, l10n.unknown),
                  () => computeAlpSchoolDashboard(
                    source,
                    schoolId: _schoolId,
                    labels: AlpSchoolLabels(unknown: l10n.unknown, notRecorded: l10n.notRecorded),
                  ),
                );
                if (_refitPending) {
                  _refitPending = false;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _fit(dashboard.mappedSchools);
                  });
                }
                return AdaptiveBody(
                  gutter: false,
                  child: ListView(
                    key: const ValueKey('alp-school-list'),
                    padding: const EdgeInsets.all(8),
                    children: [
                      SourceNote(l10n.offlineFiguresNote),
                      _Filters(schools: source.schools, language: language, value: _schoolId, onChanged: _select),
                      const SizedBox(height: 4),
                      _Kpis(dashboard: dashboard),
                      const SizedBox(height: 4),
                      ChartCard(
                        key: const ValueKey('chart-school-map'),
                        title: l10n.schoolLocations,
                        subtitle: l10n.schoolsMapped(dashboard.mappedSchools.length),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (!tiles) ...[
                              Row(
                                children: [
                                  const Icon(Icons.cloud_off, size: 16, color: AppColors.muted),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      l10n.mapTilesOffline,
                                      style: const TextStyle(color: AppColors.muted, fontSize: 12, height: 1.3),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                            ],
                            if (dashboard.mappedSchools.isEmpty)
                              EmptyChart(message: l10n.noMappedSchools, icon: Icons.location_off_outlined)
                            else
                              _Map(
                                map: _map,
                                schools: dashboard.mappedSchools,
                                tiles: tiles,
                                onTap: (school) => _openDetails(context, school),
                              ),
                          ],
                        ),
                      ),
                      for (final school in dashboard.mappedSchools)
                        AppCard(
                          key: ValueKey('school-row-${school.id}'),
                          onTap: () {
                            _map.move(LatLng(school.latitude, school.longitude), 14);
                            _openDetails(context, school);
                          },
                          child: Row(
                            children: [
                              const Icon(Icons.location_on_outlined, color: AppColors.primary),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(school.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 2),
                                    Text(
                                      [
                                        if (school.number != null) '${l10n.cerdNumber} ${school.number}',
                                        '${l10n.students}: ${school.students}',
                                        '${l10n.teachers}: ${school.teachers}',
                                      ].join(' · '),
                                      style: const TextStyle(color: AppColors.muted, fontSize: 13),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right, color: AppColors.muted),
                            ],
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// A bottom sheet on the phone and a centred dialog from 600 px up: the
  /// same [AppLayout.dialogPickers] answer every picker in this app gives.
  ///
  /// Read the way `ReferencePickerSheet.show` reads it — through the
  /// inherited widget WITHOUT registering a dependency, because this runs
  /// from a tap callback rather than from a build, with the device question
  /// as the fallback for a context that has no scope above it.
  Future<void> _openDetails(BuildContext context, MappedSchool school) {
    final scope = context.getInheritedWidgetOfExactType<LayoutScope>();
    final wide = scope == null ? isTabletDevice(context) : scope.layout.dialogPickers;
    final details = _SchoolDetails(school: school);
    if (wide) {
      return showDialog<void>(
        context: context,
        builder: (context) => Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(child: details),
          ),
        ),
      );
    }
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(child: SingleChildScrollView(child: details)),
    );
  }
}

class _Filters extends StatelessWidget {
  const _Filters({required this.schools, required this.language, required this.value, required this.onChanged});

  final List<ReferenceItem> schools;
  final String language;
  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Card(
      key: const ValueKey('alp-school-filters'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.filter_alt_outlined, size: 18, color: AppColors.muted),
                const SizedBox(width: 8),
                Expanded(child: Text(l10n.filters, style: Theme.of(context).textTheme.titleSmall)),
                if (value != null)
                  TextButton(
                    key: const ValueKey('alp-school-filters-reset'),
                    onPressed: () => onChanged(null),
                    child: Text(l10n.resetFilters),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            FilterBar(
              children: [
                FilterDropdown<int>(
                  key: const ValueKey('alp-school-filter-school'),
                  label: l10n.selectSchool,
                  allLabel: l10n.allSchools,
                  value: value,
                  options: [for (final s in schools) (s.id, s.labelFor(language))],
                  onChanged: onChanged,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Kpis extends StatelessWidget {
  const _Kpis({required this.dashboard});

  final AlpSchoolDashboard dashboard;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return KpiGrid(
      key: const ValueKey('alp-school-kpis'),
      tiles: [
        KpiTile(
          label: l10n.accessibleSchools,
          value: '${dashboard.accessibleSchools}',
          icon: Icons.school_outlined,
          caption: l10n.inReportingScope,
        ),
        KpiTile(
          label: l10n.mappedSchools,
          value: '${dashboard.mappedSchools.length}',
          icon: Icons.location_on_outlined,
          color: AppColors.secondary,
          caption: l10n.withGpsCoordinates,
        ),
        KpiTile(
          label: l10n.alpStudents,
          value: '${dashboard.students}',
          icon: Icons.people_outline,
          caption: l10n.activeRegistrations,
        ),
        KpiTile(
          label: l10n.alpTeachers,
          value: '${dashboard.teachers}',
          icon: Icons.badge_outlined,
          color: AppColors.success,
          caption: l10n.acrossMappedSchools,
        ),
      ],
    );
  }
}

class _Map extends StatelessWidget {
  const _Map({required this.map, required this.schools, required this.tiles, required this.onTap});

  final MapController map;
  final List<MappedSchool> schools;
  final bool tiles;
  final ValueChanged<MappedSchool> onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final layout = LayoutScope.of(context);
    final height = switch (layout.width) {
      WidthClass.compact => 320.0,
      WidthClass.medium => 420.0,
      WidthClass.expanded => 480.0,
    };
    final points = [for (final s in schools) LatLng(s.latitude, s.longitude)];
    return SizedBox(
      height: height,
      child: ClipRRect(
        borderRadius: AppRadius.controlRadius,
        child: FlutterMap(
          key: const ValueKey('alp-school-map'),
          mapController: map,
          options: MapOptions(
            initialCenter: _lebanon,
            initialZoom: _initialZoom,
            // One school gives a zero-size bounds, which no camera can fit:
            // it is centred at a readable zoom instead.
            initialCameraFit: points.length < 2
                ? null
                : CameraFit.bounds(
                    bounds: LatLngBounds.fromPoints(points),
                    padding: const EdgeInsets.all(40),
                    maxZoom: 15,
                  ),
            backgroundColor: AppColors.surfaceAlt,
          ),
          children: [
            if (tiles)
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'org.unicef.bma_app',
              ),
            MarkerLayer(
              markers: [
                for (final school in schools)
                  Marker(
                    key: ValueKey('school-marker-${school.id}'),
                    point: LatLng(school.latitude, school.longitude),
                    width: 44,
                    height: 44,
                    alignment: Alignment.topCenter,
                    child: GestureDetector(
                      onTap: () => onTap(school),
                      child: Tooltip(
                        message: school.name,
                        child: Icon(
                          Icons.location_on,
                          size: 36,
                          color: school.isClosed ? AppColors.muted : AppColors.primary,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            if (tiles)
              SimpleAttributionWidget(
                source: Text(l10n.mapAttribution, style: const TextStyle(fontSize: 10)),
              ),
          ],
        ),
      ),
    );
  }
}

/// What a marker or a row opens: the facts the web popup lists, minus the
/// ones the mobile API does not send.
class _SchoolDetails extends StatelessWidget {
  const _SchoolDetails({required this.school});

  final MappedSchool school;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final facts = <(String, String)>[
      if (school.number != null) (l10n.cerdNumber, school.number!),
      if (school.type != null) (l10n.facilityType, school.type!),
      if (school.placeLabel != null) (l10n.locationLabel, school.placeLabel!),
      if (school.governorate != null) (l10n.governorate, school.governorate!),
      (l10n.students, '${school.students}'),
      (l10n.teachers, '${school.teachers}'),
      (l10n.bmaSchool, school.isBma ? l10n.yes : l10n.no),
      (l10n.coordinates, school.coordinates),
      if (school.operatingShift != null) (l10n.operatingShift, school.operatingShift!),
      if (school.directorName != null) (l10n.directorName, school.directorName!),
      if (school.phone != null) (l10n.phoneLabel, school.phone!),
      if (school.digitalHub != null) (l10n.digitalHub, school.digitalHub!),
      if (school.adminStaff != null) (l10n.adminStaff, school.adminStaff!),
    ];
    return Padding(
      key: const ValueKey('school-details'),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(school.name, style: Theme.of(context).textTheme.titleMedium)),
              StatusPill(
                label: school.isClosed ? l10n.schoolClosed : l10n.schoolOpen,
                color: school.isClosed ? AppColors.muted : AppColors.success,
                icon: school.isClosed ? Icons.pause_circle_outline : Icons.check_circle_outline,
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final (label, value) in facts) FactRow(label: label, value: value),
          const SizedBox(height: 12),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.close)),
          ),
        ],
      ),
    );
  }
}
