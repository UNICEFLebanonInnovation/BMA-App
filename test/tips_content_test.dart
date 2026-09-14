import 'dart:convert';
import 'dart:io';

import 'package:bma_app/core/config/app_config.dart';
import 'package:bma_app/core/models/user_profile.dart';
import 'package:bma_app/features/tips/tips_content.dart';
import 'package:bma_app/l10n/app_localizations.dart';
import 'package:bma_app/l10n/app_localizations_ar.dart';
import 'package:bma_app/l10n/app_localizations_en.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

/// Every generated getter the wizard and the TipCards use.
final Map<String, String Function(AppLocalizations)> _tipsGetters = {
  'tipsTitle': (l) => l.tipsTitle,
  'tipsStep': (l) => l.tipsStep(1, 7),
  'skip': (l) => l.skip,
  'done': (l) => l.done,
  'gotIt': (l) => l.gotIt,
  'tipsShowAgain': (l) => l.tipsShowAgain,
  'tipsDataReady': (l) => l.tipsDataReady,
  'tipsWelcomeTitle': (l) => l.tipsWelcomeTitle,
  'tipsWelcomeBody': (l) => l.tipsWelcomeBody,
  'tipsDataTitle': (l) => l.tipsDataTitle,
  'tipsDataBody': (l) => l.tipsDataBody,
  'tipsRegisterTitle': (l) => l.tipsRegisterTitle,
  'tipsRegisterBody': (l) => l.tipsRegisterBody,
  'tipsDailyTitle': (l) => l.tipsDailyTitle,
  'tipsDailyBody': (l) => l.tipsDailyBody,
  'tipsPushTitle': (l) => l.tipsPushTitle,
  'tipsPushBody': (l) => l.tipsPushBody,
  'tipsResolveTitle': (l) => l.tipsResolveTitle,
  'tipsResolveBody': (l) => l.tipsResolveBody,
  'tipsSafeTitle': (l) => l.tipsSafeTitle,
  'tipsSafeBody': (l) => l.tipsSafeBody,
  'tipHomeSync': (l) => l.tipHomeSync,
  'tipRegistrationsSearch': (l) => l.tipRegistrationsSearch,
  'tipAttendanceFlow': (l) => l.tipAttendanceFlow,
  'tipSyncCenter': (l) => l.tipSyncCenter,
};

Set<String> _arbKeys(String path) {
  final json = jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
  return json.keys.where((k) => !k.startsWith('@')).toSet();
}

void main() {
  final en = AppLocalizationsEn();
  final ar = AppLocalizationsAr();

  group('tipPages', () {
    test('null profile yields all 7 pages in order with unique titles', () {
      final pages = tipPages(en, null);
      expect(pages.map((p) => p.kind).toList(), [
        TipPageKind.welcome,
        TipPageKind.data,
        TipPageKind.register,
        TipPageKind.daily,
        TipPageKind.push,
        TipPageKind.resolve,
        TipPageKind.safe,
      ]);
      final titles = pages.map((p) => p.title).toList();
      expect(titles.toSet().length, 7, reason: 'titles must be unique');
      for (final page in pages) {
        expect(page.title, isNotEmpty);
        expect(page.body, isNotEmpty);
      }
      expect(pages.map((p) => p.icon).toList(), [
        Icons.cloud_off,
        Icons.cloud_download,
        Icons.person_add,
        Icons.fact_check,
        Icons.cloud_upload,
        Icons.call_merge,
        Icons.verified_user,
      ]);
    });

    test('a profile with every capability sees all 7 pages', () {
      expect(tipPages(en, profileWith()).length, 7);
    });

    test('attendance-only profile sees 5 pages without register/resolve', () {
      final profile = profileWith(modules: {BmaModule.mscc: caps(register: false, edit: false)});
      final kinds = tipPages(en, profile).map((p) => p.kind).toList();
      expect(kinds, [
        TipPageKind.welcome,
        TipPageKind.data,
        TipPageKind.daily,
        TipPageKind.push,
        TipPageKind.safe,
      ]);
      expect(kinds, isNot(contains(TipPageKind.register)));
      expect(kinds, isNot(contains(TipPageKind.resolve)));
    });

    test('edit-only profile sees 6 pages: resolve present, register absent', () {
      final profile = profileWith(modules: {BmaModule.mscc: caps(register: false, edit: true)});
      final kinds = tipPages(en, profile).map((p) => p.kind).toList();
      expect(kinds.length, 6);
      expect(kinds, contains(TipPageKind.resolve));
      expect(kinds, isNot(contains(TipPageKind.register)));
    });

    test('profile with no enabled modules sees 5 pages', () {
      final profile = profileWith(modules: const {BmaModule.mscc: ModuleCapabilities.none});
      expect(profile.enabledModules, isEmpty);
      expect(tipPages(en, profile).length, 5);
      expect(tipPages(en, profileWith(modules: const {})).length, 5);
    });

    test('a disabled module with canRegister does not count', () {
      const disabledRegistrar = ModuleCapabilities(
        enabled: false,
        canRegister: true,
        canEdit: true,
        canAttend: true,
        canManageTeachers: true,
        scope: 'center',
      );
      final profile = profileWith(modules: const {BmaModule.alp: disabledRegistrar});
      expect(tipPages(en, profile).length, 5);
    });

    test('capabilities on any enabled module are enough', () {
      final profile = profileWith(modules: {
        BmaModule.mscc: caps(register: false, edit: false),
        BmaModule.clm: caps(register: true, edit: false),
      });
      final kinds = tipPages(en, profile).map((p) => p.kind).toList();
      expect(kinds, contains(TipPageKind.register));
      expect(kinds, contains(TipPageKind.resolve));
    });

    test('Arabic pages carry the Arabic titles', () {
      final pages = tipPages(ar, null);
      expect(pages.first.title, 'يعمل دون إنترنت');
      expect(pages.last.title, 'حافظ على أمان بياناتك');
    });
  });

  group('TipIds', () {
    test('are stable and unique', () {
      expect(TipIds.homeSync, 'home.sync');
      expect(TipIds.registrationsSearch, 'registrations.search');
      expect(TipIds.attendanceFlow, 'attendance.flow');
      expect(TipIds.syncCenter, 'sync.center');
      expect(
        {TipIds.homeSync, TipIds.registrationsSearch, TipIds.attendanceFlow, TipIds.syncCenter}.length,
        4,
      );
    });
  });

  group('localisation', () {
    test('covers the 25 new keys', () {
      expect(_tipsGetters.length, 25);
    });

    test('every tips string is non-empty and differs between EN and AR', () {
      for (final entry in _tipsGetters.entries) {
        final english = entry.value(en);
        final arabic = entry.value(ar);
        expect(english, isNotEmpty, reason: '${entry.key} EN is empty');
        expect(arabic, isNotEmpty, reason: '${entry.key} AR is empty');
        expect(arabic, isNot(equals(english)), reason: '${entry.key} AR is a copy of EN');
      }
    });

    test('tipsStep interpolates both numbers', () {
      expect(en.tipsStep(2, 5), 'Step 2 of 5');
      expect(ar.tipsStep(2, 5), 'الخطوة 2 من 5');
    });

    test('ARB files have identical key sets and contain the new keys', () {
      final enKeys = _arbKeys('lib/l10n/app_en.arb');
      final arKeys = _arbKeys('lib/l10n/app_ar.arb');
      expect(arKeys, equals(enKeys), reason: 'app_ar.arb must mirror app_en.arb');
      expect(enKeys, containsAll(_tipsGetters.keys));
      expect(arKeys, containsAll(_tipsGetters.keys));
      expect(enKeys.length, greaterThanOrEqualTo(205));
    });
  });
}
