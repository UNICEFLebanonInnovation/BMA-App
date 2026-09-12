# BMA Mobile (BMA-App)

Offline-first Flutter companion of the **BMA-NFE** web platform for the NFE
sector in Lebanon. Partners take a tablet or phone to the field, register
children, record services and take daily attendance **without internet**, then
push everything to BMA-NFE when a connection is available. The server verifies
each record, detects duplicates and returns a report; the field worker decides
whether to merge, link, create or discard.

| Module | What the app covers |
|---|---|
| **Makani / MSCC** | Beneficiary list & search, 3-step registration wizard, child profile, every service form (education, PSS, health & nutrition, youth, inclusion, digital, LEGO, recreational, follow-up, referrals, grading), new round, teachers, daily attendance per programme/section, dashboard |
| **ALP schools** | Registrations, child profile, grading, teachers, school profile, children attendance, teacher attendance, dashboard |
| **CLM Bridging** | Bridging registrations (with pre-test), post/mid assessments, follow-up, services, teachers, clubs/meetings/initiatives/health visits, attendance per level, dashboard |

All forms are **generated from the web platform's Django forms** at runtime:
labels (English/Arabic), choices, required flags, lengths and conditional
sections are downloaded once (`bootstrap`) and cached in SQLite, so the app
never drifts from the website.

## How synchronisation works

```
   device (SQLite)                      BMA-NFE (student_registration.mobile_api)
   ───────────────                      ───────────────────────────────────────
   login ───────────────────────────▶   POST /api/mobile/v1/auth/login/   (token + roles/scope)
   bootstrap ───────────────────────▶   GET  /api/mobile/v1/bootstrap/    (reference lists, choices, form schemas)
   pull (incremental) ──────────────▶   GET  /api/mobile/v1/pull/?since=  (records the user may see)
   work offline: records are stored with sync_state = pending
   push (batches of 200) ───────────▶   POST /api/mobile/v1/push/
                                   ◀─   per-item report: created / updated / merged / linked /
                                        duplicate (+ candidates) / conflict / error / skipped
   resolve duplicates & conflicts, push again
```

* **Duplicate verification** happens on the server for every registration:
  UNICEF unique id (same external service as the website), a local identity
  key (normalised names + birthday + gender, Arabic-aware), identical ID
  numbers, and near matches. Nothing is created silently.
* **Resolutions**: *merge into existing*, *same child – new enrolment (link)*,
  *create anyway*, *discard*; conflicts offer *overwrite server* / *keep server*.
* **Attendance** sheets are idempotent documents keyed on centre/school,
  round, programme/section and date, exactly like the website's
  `get_or_create` logic.
* Every batch is kept locally (Sync history) and on the server (Django admin
  → Mobile sync batches) for audit.

The full contract is documented in
[`docs/mobile_sync_protocol.md`](https://github.com/UNICEFLebanonInnovation/BMA-NFE/blob/main/docs/mobile_sync_protocol.md)
in the BMA-NFE repository.

## Project layout

```
lib/
  main.dart, app.dart, router.dart      entry point, MaterialApp (RTL/Arabic), go_router
  l10n/                                 app_en.arb / app_ar.arb (+ generated AppLocalizations)
  core/
    config/     AppConfig (API prefix, batch sizes), SettingsController (server URL, language)
    auth/       AuthController: token login, offline re-login, session persistence
    db/         AppDatabase (SQLite schema), EntityDao (generic records), ReferenceDao, SyncDao
    models/     EntityRecord, EntitySchema/FieldSpec, ReferenceItem, PushReport, UserProfile
    network/    ApiClient (dio + token), BmaApi (typed endpoints)
    sync/       SyncEngine (bootstrap / pull / push / apply results), connectivity
    forms/      Schema-driven form engine: controller, validation, field widgets, reference pickers
    widgets/    Shared widgets (sync state chip, offline banner, stat tiles …)
  features/
    auth/ home/ settings/ registrations/ services/ attendance/ teachers/ dashboard/ sync/
test/                                    unit tests (form engine, DAO, sync engine, name normalisation)
```

### Local data model

One generic `records` table stores every synchronised entity as a JSON
document plus bookkeeping columns (`entity`, `server_id`, `parent_uuid`,
`natural_key`, `sync_state`, `op`, `server_modified`, `base_modified`,
`duplicates`, `conflict_data`, `resolution`, …). Reference lists, choice
lists and form schemas live in `ref_items`, `choices` and `schemas`; push
history in `sync_batches`.

Local states: `synced`, `pending`, `pushing`, `duplicate`, `conflict`,
`error`, `discarded`.

## Getting started

Requirements: Flutter 3.47+ (Dart 3.13+), Android SDK and/or Xcode.

```bash
flutter pub get            # also generates lib/l10n/app_localizations.dart
flutter analyze
flutter test
flutter run                # pick a device / emulator
```

On first launch enter the server URL (e.g. `https://bma-nfe.example.org`),
username and password of a BMA-NFE account that belongs to one of the MSCC,
ALP or CLM groups. The app downloads reference data and the records visible to
that account, then works offline. Use **Sync centre** to push, pull or run a
full refresh, and to resolve records flagged by the server.

### Server-side requirements

The BMA-NFE deployment must include the `student_registration.mobile_api`
app (branch `claude/kind-brahmagupta-j47zvz` of BMA-NFE) and run its
migration. Token authentication is used; every account that signs in on a
device gets a DRF token.

### Building releases

```bash
flutter build apk --release          # Android
flutter build appbundle --release    # Play Store
flutter build ipa --release          # iOS (macOS + Xcode)
```

The default server URL and app version live in `lib/core/config/app_config.dart`.

## Testing

```bash
flutter test
```

Tests use `sqflite_common_ffi` (no device needed) and an in-memory fake of the
server API to exercise the whole offline → push → resolve → push cycle.

## Licence

GPLv3, same as BMA-NFE.
