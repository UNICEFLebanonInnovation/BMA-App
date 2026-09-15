// LANE: sync. Covers the five screens under lib/features/sync at the three
// viewports the tablet work targets — 1280x800 landscape, 800x1280 portrait
// and the 412x915 phone that must not move — plus Arabic RTL at 1.3x.
//
// The screens are pumped directly rather than through the router: none of
// them reads route state to lay itself out, and a direct pump keeps a real
// in-memory SQLite database (the DAOs these screens call) in play without
// dragging the redirect chain in. The MaterialApp mirrors app.dart's builder
// exactly, so the density theme is the production one at 800 px shortest side.
import 'package:bma_app/core/auth/auth_controller.dart';
import 'package:bma_app/core/config/app_config.dart';
import 'package:bma_app/core/db/app_database.dart';
import 'package:bma_app/core/db/entity_dao.dart';
import 'package:bma_app/core/db/sync_dao.dart';
import 'package:bma_app/core/layout/breakpoints.dart';
import 'package:bma_app/core/models/entity_record.dart';
import 'package:bma_app/core/models/sync_models.dart';
import 'package:bma_app/core/sync/connectivity_service.dart';
import 'package:bma_app/core/sync/sync_engine.dart';
import 'package:bma_app/core/theme/app_theme.dart';
import 'package:bma_app/features/sync/conflict_resolution_screen.dart';
import 'package:bma_app/features/sync/duplicate_resolution_screen.dart';
import 'package:bma_app/features/sync/push_report_screen.dart';
import 'package:bma_app/features/sync/sync_center_screen.dart';
import 'package:bma_app/features/sync/sync_history_screen.dart';
import 'package:bma_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/fakes.dart';
import '../support/viewport.dart';

const statusPane = ValueKey('sync-status-pane');
const queue = ValueKey('sync-queue');
const push = ValueKey('sync-push');
const pull = ValueKey('sync-pull');
const dupLocal = ValueKey('dup-local');
const dupApply = ValueKey('dup-apply');
const dupMerge = ValueKey('dup-action-merge');
const dupOverwrite = ValueKey('dup-overwrite');
const conflictTable = ValueKey('conflict-table');
const conflictKeep = ValueKey('conflict-keep-server');
const conflictOver = ValueKey('conflict-overwrite');
const reportSummary = ValueKey('report-summary');

/// Counts are non-zero so the state chips and the queue both render; the real
/// engine's build() would walk the DAO on a microtask.
class _Engine extends SyncEngine {
  @override
  SyncStatus build() => const SyncStatus(
        lastPull: '2026-09-14T08:30:00.000',
        counts: {
          SyncState.pending: 3,
          SyncState.duplicate: 1,
          SyncState.conflict: 1,
          SyncState.error: 1,
        },
      );

  @override
  Future<void> refreshCounts() async {}
}

class Fixture {
  Fixture(this.container, this.duplicate, this.conflict, this.batch);

  final ProviderContainer container;
  final EntityRecord duplicate;
  final EntityRecord conflict;
  final SyncBatch batch;
}

Map<String, dynamic> _child(String first, {required String mother, required String day}) => {
      'center_label': 'Makani Centre',
      'registration_date': '2026-09-01',
      'child': {
        'first_name': first,
        'father_name': 'Ahmad',
        'last_name': 'Sayed',
        'mother_fullname': mother,
        'gender': 'Female',
        'nationality_label': 'Syrian',
        'birthday_year': '2015',
        'birthday_month': '3',
        'birthday_day': day,
        'number': 'ABC-$first',
      },
    };

Map<String, dynamic> _candidate(int i) => {
      'registration_id': 900 + i,
      'child_id': 500 + i,
      'label': 'Amal Ahmad Sayed ($i)',
      'mother_fullname': 'Fatima Nasr',
      'birthday': '2015-03-0$i',
      'gender': 'Female',
      'nationality': 'Syrian',
      'center': 'Makani Centre',
      'round': '2025-2026',
      'number': 'ABC-90$i',
      'match': {'reason': 'name + birthday', 'score': 90 + i},
    };

Map<String, dynamic> _teacher({required String phone, required String role, required String status}) => {
      'first_name': 'Rania',
      'last_name': 'Khoury',
      'primary_phone_number': phone,
      'teacher_assignment': role,
      'employment_status': status,
      'email': 'rania@example.org',
    };

PushItemResult _result(String uuid, String status) => PushItemResult(
      clientUuid: uuid,
      entity: Entities.msccRegistration,
      status: status,
      serverId: 1000 + uuid.hashCode % 100,
      message: 'Processed by the server',
      dataAfter: {'label': 'Row $uuid'},
    );

Future<Fixture> fixture(WidgetTester tester, {String lang = 'en'}) async {
  final db = await tester.runAsync(AppDatabase.openInMemory);
  final dao = EntityDao(db!);
  final syncDao = SyncDao(db);
  late EntityRecord duplicate;
  late EntityRecord conflict;
  late SyncBatch batch;
  await tester.runAsync(() async {
    final dup = await dao.createLocal(
        entity: Entities.msccRegistration, data: _child('Amal', mother: 'Fatima Nasr', day: '5'));
    duplicate = dup.copyWith(
      syncState: SyncState.duplicate,
      duplicates: [for (var i = 1; i <= 4; i++) _candidate(i)],
      serverMessage: 'Matches 4 existing children',
    );
    await dao.put(duplicate);

    final con = await dao.createLocal(
        entity: Entities.msccTeacher,
        data: _teacher(phone: '70 111 222', role: 'Facilitator', status: 'Active'));
    conflict = con.copyWith(
      syncState: SyncState.conflict,
      conflictData: _teacher(phone: '70 999 888', role: 'Coordinator', status: 'On leave'),
    );
    await dao.put(conflict);

    final err = await dao.createLocal(
        entity: Entities.msccTeacher, data: _teacher(phone: '70 333 444', role: 'Facilitator', status: 'Active'));
    await dao.put(err.copyWith(
      syncState: SyncState.error,
      lastError: {'primary_phone_number': ['Enter a valid number.']},
    ));

    final results = [for (var i = 0; i < 5; i++) _result('row-$i', i.isEven ? 'created' : 'duplicate')];
    batch = SyncBatch(
      uuid: 'batch-1',
      serverBatchId: 77,
      startedAt: '2026-09-14T08:00:00.000',
      finishedAt: '2026-09-14T08:01:00.000',
      status: 'completed',
      itemCount: results.length,
      summary: const {'created': 3, 'duplicate': 2, 'total': 5},
      report: PushReport(
        batchId: 77,
        batchUuid: 'batch-1',
        status: 'completed',
        summary: const {'created': 3, 'duplicate': 2},
        results: results,
      ),
    );
    await syncDao.put(batch);
    await syncDao.put(SyncBatch(
      uuid: 'batch-0',
      startedAt: '2026-09-13T08:00:00.000',
      finishedAt: '2026-09-13T08:00:30.000',
      status: 'completed',
      itemCount: 2,
      summary: const {'created': 2},
    ));
  });
  final container = ProviderContainer(overrides: [
    appDatabaseProvider.overrideWithValue(db),
    authControllerProvider.overrideWith(() => FakeAuthController(signedIn())),
    syncEngineProvider.overrideWith(_Engine.new),
    connectivityProvider.overrideWith((ref) => Stream.value(true)),
  ]);
  addTearDown(container.dispose);
  addTearDown(() => db.close());
  return Fixture(container, duplicate, conflict, batch);
}

/// Lets the real SQLite futures resolve.
Future<void> settle(WidgetTester tester, {int rounds = 5}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pump(const Duration(milliseconds: 300));
}

/// Mirrors app.dart: same delegates, same density builder, so a test at
/// 800x1280 sees exactly the theme the device does.
Future<void> open(
  WidgetTester tester,
  Fixture fx,
  Widget screen, {
  String lang = 'en',
  double scale = 1.0,
}) async {
  await tester.pumpWidget(UncontrolledProviderScope(
    container: fx.container,
    child: MaterialApp(
      theme: AppTheme.light(),
      locale: Locale(lang),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => Theme(
        data: AppTheme.cached(
          tablet: MediaQuery.sizeOf(context).shortestSide >= Breakpoints.tabletShortestSide,
        ),
        child: MediaQuery.withNoTextScaling(
          child: scale == 1.0
              ? child!
              : MediaQuery(
                  data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
        ),
      ),
      home: screen,
    ),
  ));
  await settle(tester);
}

Rect rectOf(WidgetTester tester, Key key) => tester.getRect(find.byKey(key));

/// Scrolls the leading scrollable until [key] is built and laid out. The
/// action list sits below the fold of a tall fixture, and a ListView never
/// builds what it has not reached.
Future<void> reveal(WidgetTester tester, Key key) async {
  await tester.scrollUntilVisible(
    find.byKey(key),
    200,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 40,
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('the phone fallback, ar at 1.3x', () {
    // Every screen in this lane at 412x915 in Arabic at 1.3x. The compact
    // branches are meant to be today's trees; this is the cheap check that
    // none of them started overflowing while the tablet branches were added.
    testWidgets('no screen in this lane overflows', (tester) async {
      phone(tester);
      final fx = await fixture(tester);
      for (final screen in <Widget>[
        const SyncCenterScreen(),
        DuplicateResolutionScreen(uuid: fx.duplicate.uuid),
        ConflictResolutionScreen(uuid: fx.conflict.uuid),
        const PushReportScreen(batchUuid: 'batch-1'),
        const SyncHistoryScreen(),
      ]) {
        await open(tester, fx, screen, lang: 'ar', scale: 1.3);
        expect(tester.takeException(), isNull, reason: '${screen.runtimeType} overflowed at 412x915 in ar');
      }
    });
  });

  group('sync centre', () {
    testWidgets('1280x800: the queue sits beside a 420 px status pane', (tester) async {
      tabletLandscape(tester);
      final fx = await fixture(tester);
      await open(tester, fx, const SyncCenterScreen());

      final status = rectOf(tester, statusPane);
      final work = rectOf(tester, queue);
      // Leading pane first, queue second: the actual work is no longer below
      // the fold, it is the majority of the screen.
      expect(status.right, lessThanOrEqualTo(420));
      expect(work.left, greaterThanOrEqualTo(420));
      expect(work.width, greaterThan(status.width * 1.5));
      // The heading above the queue does not scroll with it.
      expect(find.text('Records needing your decision'), findsOneWidget);
      // All three attention records are in the queue pane.
      expect(find.byKey(ValueKey('sync-queue-${fx.duplicate.uuid}')), findsOneWidget);
      expect(find.byKey(ValueKey('sync-queue-${fx.conflict.uuid}')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('1280x800: the sync actions are inside the pane, not stretched across the window', (tester) async {
      tabletLandscape(tester);
      final fx = await fixture(tester);
      await open(tester, fx, const SyncCenterScreen());

      final pushRect = rectOf(tester, push);
      final pullRect = rectOf(tester, pull);
      // A 420 px pane is a COMPACT box by the two-threshold model, so the pane
      // keeps the phone's two equal buttons — but they are ~170 px, not the
      // ~620 px they would be in a full-width single column at 1280.
      expect(pushRect.width, lessThan(240));
      expect(pullRect.width, pushRect.width);
      // Side by side on one line: their vertical extents overlap (the two
      // buttons differ in height under the test font, so equal tops is not
      // the question).
      expect(pushRect.right, lessThan(pullRect.left));
      expect(pushRect.top, lessThan(pullRect.bottom));
      expect(pullRect.top, lessThan(pushRect.bottom));
      expect(pullRect.right, lessThanOrEqualTo(420));
      expect(tester.takeException(), isNull);
    });

    testWidgets('800x1280: the sync actions become intrinsic width, not two ~370 px halves', (tester) async {
      tabletPortrait(tester);
      final fx = await fixture(tester);
      await open(tester, fx, const SyncCenterScreen());

      final pushRect = rectOf(tester, push);
      final pullRect = rectOf(tester, pull);
      final status = rectOf(tester, statusPane);
      // Intrinsic: neither button is half the 736 px card, and the row of
      // three does not start at the card's far edges.
      expect(pushRect.width, lessThan(status.width / 2));
      expect(pullRect.width, isNot(pushRect.width));
      expect(tester.takeException(), isNull);
    });

    testWidgets('800x1280: one column, centred at contentMaxWidth with a real gutter', (tester) async {
      tabletPortrait(tester);
      final fx = await fixture(tester);
      await open(tester, fx, const SyncCenterScreen());

      final status = rectOf(tester, statusPane);
      final work = rectOf(tester, queue);
      // Stacked, not split.
      expect(work.top, greaterThan(status.bottom));
      // 800 less the 2x24 gutter and the ListView's 2x8 padding. (A Card's
      // rect includes its 12 px side margin, so the margin is not subtracted.)
      expect(status.width, 800 - 48 - 16);
      expect(status.left, 24 + 8);
      expect(tester.takeException(), isNull);
    });

    testWidgets('412x915: the phone keeps two half-width buttons and no gutter', (tester) async {
      phone(tester);
      final fx = await fixture(tester);
      await open(tester, fx, const SyncCenterScreen());

      final status = rectOf(tester, statusPane);
      // 412 less the ListView's 2x8 padding: today's value, no gutter added.
      expect(status.width, 412 - 16);
      expect(status.left, 8);
      final pushRect = rectOf(tester, push);
      final pullRect = rectOf(tester, pull);
      // Today's two Expandeds: equal halves of the card, on one line.
      expect(pushRect.width, pullRect.width);
      expect(pushRect.width, greaterThan(150));
      expect(pushRect.right, lessThan(pullRect.left));
      expect(pushRect.top, lessThan(pullRect.bottom));
      expect(pullRect.top, lessThan(pushRect.bottom));
      expect(tester.takeException(), isNull);
    });

    testWidgets('ar at 1.3x, 1280x800: the status pane is on the RIGHT', (tester) async {
      tabletLandscape(tester);
      final fx = await fixture(tester);
      await open(tester, fx, const SyncCenterScreen(), lang: 'ar', scale: 1.3);

      final status = rectOf(tester, statusPane);
      final work = rectOf(tester, queue);
      // A takeException-is-null assertion passes happily on a pane that
      // rendered on the wrong side, so assert the mirror mechanically.
      expect(status.right, greaterThanOrEqualTo(1280 - 30));
      expect(work.right, lessThanOrEqualTo(status.left));
      expect(tester.takeException(), isNull);
    });
  });

  group('duplicate resolution', () {
    testWidgets('1280x800: local version and every candidate are on screen at once', (tester) async {
      tabletLandscape(tester);
      final fx = await fixture(tester);
      await open(tester, fx, DuplicateResolutionScreen(uuid: fx.duplicate.uuid));

      final local = rectOf(tester, dupLocal);
      expect(local.right, lessThanOrEqualTo(400));
      // The whole comparison without scrolling back and forth: the decision
      // side is fixed and all four candidates are beside it.
      for (var i = 1; i <= 4; i++) {
        final candidate = rectOf(tester, ValueKey('dup-candidate-${900 + i}'));
        expect(candidate.left, greaterThanOrEqualTo(400));
        expect(candidate.bottom, lessThanOrEqualTo(800));
      }
      // Apply is pinned, not scrolled away.
      expect(rectOf(tester, dupApply).bottom, lessThanOrEqualTo(800));
      expect(tester.takeException(), isNull);
    });

    testWidgets('800x1280: the stack is kept and capped at readingMaxWidth', (tester) async {
      tabletPortrait(tester);
      final fx = await fixture(tester);
      await open(tester, fx, DuplicateResolutionScreen(uuid: fx.duplicate.uuid));

      final local = rectOf(tester, dupLocal);
      final first = rectOf(tester, const ValueKey('dup-candidate-901'));
      expect(first.top, greaterThan(local.top));
      // 700 reading cap, centred: 2x24 gutter and the ListView's 2x12 padding.
      expect(local.width, 700 - 48 - 24);
      expect(local.center.dx, 400);
      expect(tester.takeException(), isNull);
    });

    testWidgets('412x915: the phone stack is unchanged and uncapped', (tester) async {
      phone(tester);
      final fx = await fixture(tester);
      await open(tester, fx, DuplicateResolutionScreen(uuid: fx.duplicate.uuid));

      final local = rectOf(tester, dupLocal);
      expect(local.width, 412 - 24);
      expect(local.left, 12);
      expect(rectOf(tester, const ValueKey('dup-candidate-901')).top, greaterThan(local.top));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the overwrite switch is indented from the START edge in both directions', (tester) async {
      // The live RTL bug the spec names: EdgeInsets.only(left: 32) indents the
      // nested switch to the wrong side in Arabic.
      tabletPortrait(tester);
      final fx = await fixture(tester);
      await open(tester, fx, DuplicateResolutionScreen(uuid: fx.duplicate.uuid));
      await reveal(tester, dupOverwrite);
      expect(rectOf(tester, dupOverwrite).left, rectOf(tester, dupMerge).left + 32);
      expect(rectOf(tester, dupOverwrite).right, rectOf(tester, dupMerge).right);
      expect(tester.takeException(), isNull);

      await open(tester, fx, DuplicateResolutionScreen(uuid: fx.duplicate.uuid), lang: 'ar', scale: 1.3);
      await reveal(tester, dupOverwrite);
      expect(rectOf(tester, dupOverwrite).right, rectOf(tester, dupMerge).right - 32);
      expect(rectOf(tester, dupOverwrite).left, rectOf(tester, dupMerge).left);
      expect(tester.takeException(), isNull);
    });

    testWidgets('ar at 1.3x, 1280x800: the decision pane is on the right and nothing overflows', (tester) async {
      tabletLandscape(tester);
      final fx = await fixture(tester);
      await open(tester, fx, DuplicateResolutionScreen(uuid: fx.duplicate.uuid), lang: 'ar', scale: 1.3);

      expect(rectOf(tester, dupLocal).right, greaterThanOrEqualTo(1280 - 400));
      expect(rectOf(tester, const ValueKey('dup-candidate-901')).right, lessThanOrEqualTo(1280 - 400));
      expect(tester.takeException(), isNull);
    });
  });

  group('conflict resolution', () {
    testWidgets('1280x800: a three-column table with a pinned header, capped at readingMaxWidth', (tester) async {
      tabletLandscape(tester);
      final fx = await fixture(tester);
      await open(tester, fx, ConflictResolutionScreen(uuid: fx.conflict.uuid));

      final table = rectOf(tester, conflictTable);
      expect(table.width, 760 - 64); // readingMaxWidth less the 32 px gutter.
      expect(find.byType(Card), findsOneWidget); // one table, not one card per field.

      // Each differing field is ONE row: name, local value and server value
      // share a baseline instead of stacking into a ~620 px wide cell.
      // Three fields differ, so three rows, all the same height and the full
      // width of the table. (The test font is an em-square per glyph, so a
      // row is taller here than on a device; the invariant is that the rows
      // agree, i.e. nothing reflows per field.)
      final heights = <double>{};
      for (final field in ['employment_status', 'primary_phone_number', 'teacher_assignment']) {
        final row = rectOf(tester, ValueKey('conflict-row-$field'));
        expect(row.width, table.width);
        heights.add(row.height);
      }
      expect(heights, hasLength(1));
      final phoneRow = rectOf(tester, const ValueKey('conflict-row-primary_phone_number'));
      final local = tester.getRect(find.text('70 111 222'));
      final server = tester.getRect(find.text('70 999 888'));
      expect(local.top, server.top);
      expect(local.left, greaterThan(phoneRow.left + 200)); // past the label column
      expect(server.left, greaterThan(local.left));
      expect(tester.takeException(), isNull);
    });

    testWidgets('1280x800: the footer buttons are intrinsic width and trailing aligned', (tester) async {
      tabletLandscape(tester);
      final fx = await fixture(tester);
      await open(tester, fx, ConflictResolutionScreen(uuid: fx.conflict.uuid));

      final keep = rectOf(tester, conflictKeep);
      final over = rectOf(tester, conflictOver);
      // Intrinsic: two Expandeds would make these exactly equal, as they still
      // are at compact.
      expect(keep.width, isNot(over.width));
      // Trailing aligned inside the capped content (12 px of footer padding),
      // not at the window corner 1280 px apart.
      final table = rectOf(tester, conflictTable);
      expect(over.right, closeTo(table.right - 12, 1));
      expect(keep.right, closeTo(table.right - 12, 1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('800x1280: the table is kept and capped at 700', (tester) async {
      tabletPortrait(tester);
      final fx = await fixture(tester);
      await open(tester, fx, ConflictResolutionScreen(uuid: fx.conflict.uuid));

      final table = rectOf(tester, conflictTable);
      expect(table.width, 700 - 48);
      expect(table.center.dx, 400);
      expect(tester.takeException(), isNull);
    });

    testWidgets('412x915: the phone keeps one card per field and two half-width buttons', (tester) async {
      phone(tester);
      final fx = await fixture(tester);
      await open(tester, fx, ConflictResolutionScreen(uuid: fx.conflict.uuid));

      expect(find.byKey(conflictTable), findsNothing);
      // Three differing fields, three cards, both labels repeated in each.
      expect(find.byType(Card), findsNWidgets(3));
      expect(find.text('Your version'), findsNWidgets(3));
      final keep = rectOf(tester, conflictKeep);
      final over = rectOf(tester, conflictOver);
      expect(keep.width, over.width);
      expect(keep.width, greaterThan(150));
      expect(tester.takeException(), isNull);
    });

    testWidgets('ar at 1.3x, 1280x800: the label column is on the right and rows do not overflow', (tester) async {
      tabletLandscape(tester);
      final fx = await fixture(tester);
      await open(tester, fx, ConflictResolutionScreen(uuid: fx.conflict.uuid), lang: 'ar', scale: 1.3);

      final row = rectOf(tester, const ValueKey('conflict-row-primary_phone_number'));
      final label = tester.getRect(find.text('primary_phone_number'));
      final local = tester.getRect(find.text('70 111 222'));
      final server = tester.getRect(find.text('70 999 888'));
      expect(label.right, closeTo(row.right - 12, 1));
      expect(local.right, lessThan(label.left));
      expect(server.right, lessThan(local.left));
      expect(tester.takeException(), isNull);
    });
  });

  group('push report', () {
    testWidgets('1280x800: result tiles two per row under a full-width summary', (tester) async {
      tabletLandscape(tester);
      final fx = await fixture(tester);
      await open(tester, fx, const PushReportScreen(batchUuid: 'batch-1'));

      final summary = rectOf(tester, reportSummary);
      expect(summary.width, 1120 - 64 - 16); // contentMaxWidth, gutter, list padding.
      final first = rectOf(tester, const ValueKey('report-result-row-0'));
      final second = rectOf(tester, const ValueKey('report-result-row-1'));
      final third = rectOf(tester, const ValueKey('report-result-row-2'));
      expect(first.top, second.top);
      expect(second.left, greaterThan(first.left));
      expect(third.top, greaterThan(first.bottom - 1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('800x1280: one tile per row, centred at contentMaxWidth', (tester) async {
      tabletPortrait(tester);
      final fx = await fixture(tester);
      await open(tester, fx, const PushReportScreen(batchUuid: 'batch-1'));

      final first = rectOf(tester, const ValueKey('report-result-row-0'));
      final second = rectOf(tester, const ValueKey('report-result-row-1'));
      expect(second.top, greaterThan(first.bottom - 1));
      expect(first.left, second.left);
      expect(rectOf(tester, reportSummary).center.dx, 400);
      expect(tester.takeException(), isNull);
    });

    testWidgets('412x915: unchanged full-bleed list', (tester) async {
      phone(tester);
      final fx = await fixture(tester);
      await open(tester, fx, const PushReportScreen(batchUuid: 'batch-1'));

      expect(rectOf(tester, reportSummary).width, 412 - 16);
      final first = rectOf(tester, const ValueKey('report-result-row-0'));
      expect(rectOf(tester, const ValueKey('report-result-row-1')).top, greaterThan(first.bottom - 1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('ar at 1.3x, 1280x800: two columns mirror and nothing overflows', (tester) async {
      tabletLandscape(tester);
      final fx = await fixture(tester);
      await open(tester, fx, const PushReportScreen(batchUuid: 'batch-1'), lang: 'ar', scale: 1.3);

      final first = rectOf(tester, const ValueKey('report-result-row-0'));
      final second = rectOf(tester, const ValueKey('report-result-row-1'));
      expect(first.top, second.top);
      expect(second.right, lessThan(first.right));
      expect(tester.takeException(), isNull);
    });
  });

  group('sync history', () {
    testWidgets('1280x800: rows capped at readingMaxWidth', (tester) async {
      tabletLandscape(tester);
      final fx = await fixture(tester);
      await open(tester, fx, const SyncHistoryScreen());

      final row = rectOf(tester, const ValueKey('history-batch-1'));
      expect(row.width, 760 - 64);
      expect(row.center.dx, 640);
      expect(tester.takeException(), isNull);
    });

    testWidgets('412x915: rows stay full bleed', (tester) async {
      phone(tester);
      final fx = await fixture(tester);
      await open(tester, fx, const SyncHistoryScreen());

      expect(rectOf(tester, const ValueKey('history-batch-1')).width, 412);
      expect(tester.takeException(), isNull);
    });

    testWidgets('ar at 1.3x, 800x1280: capped, centred and no overflow', (tester) async {
      tabletPortrait(tester);
      final fx = await fixture(tester);
      await open(tester, fx, const SyncHistoryScreen(), lang: 'ar', scale: 1.3);

      final row = rectOf(tester, const ValueKey('history-batch-1'));
      expect(row.width, 700 - 48);
      expect(row.center.dx, 400);
      expect(tester.takeException(), isNull);
    });
  });
}
