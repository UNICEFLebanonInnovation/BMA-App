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
* **First-run tips wizard**, per account and per tips version, EN/AR.

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
    profiles/ setup/ tips/
                                    profiles/ = NFE centre and ALP school profiles
                                       setup/ = first-run server address page
                                        tips/ = getting-started wizard + dismissible screen tips
test/                                    unit tests (form engine, DAO, sync engine, name normalisation, tips), tips_wizard_test / tips_redirect_test
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

The programme the web platform calls Makani appears here as **NFE**, matching
the sector's own naming.

NFE accounts get a **Centre profile** and ALP accounts a **School profile**,
reached from the programme card on the home screen. Both show the facility's
partner, location chain, type and programmes from the reference data, plus the
work held on the device, and both work offline. The ALP one also opens the
editable school profile form that the web platform has.

A device that has never been set up opens a **Set up the server** page first:
enter the address of the BMA-NFE deployment (e.g. `https://bma-nfe.example.org`),
optionally tap **Test connection** to confirm the deployment runs the mobile
API, and choose the interface language. The address is saved on the device and
can be changed later in **Settings**; the page is not shown again.

Then sign in with the username and password of a BMA-NFE account that belongs
to one of the MSCC, ALP or CLM groups. The app downloads reference data and the
records visible to that account, then works offline. Use **Sync centre** to
push, pull or run a full refresh, and to resolve records flagged by the server.

The first time an account signs in on a device the app opens a short
**Getting started** tour (offline work, registration, attendance, push and
duplicate resolution); reopen it any time from the ? icon on Home or
**Settings → Show tips again**, which also brings back the dismissible tips
shown on Home, Beneficiaries, Attendance and Sync centre.

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

#### Releases (permanent download link)

`.github/workflows/release.yml` publishes the APK as a GitHub release asset,
which anyone can download without a GitHub account. It analyses, tests and
builds the release APK, then attaches `bma-app-<version>.apk` and its `.sha256`
to the release.

Every push to the field-test branch refreshes the rolling **field-test**
pre-release, so partners keep one permanent link:

```
https://github.com/UNICEFLebanonInnovation/BMA-App/releases/tag/field-test
```

For a real version, tag the commit; the tag name becomes the release:

```bash
git tag v0.1.0
git push origin v0.1.0
```

Tags with a suffix (`v0.1.0-beta.1`) are published as pre-releases.

#### APK from GitHub Actions

Every push runs `.github/workflows/build.yml`, which analyses and tests the
code and then builds a release APK. Open the run under **Actions → Build** and
download the `bma-app-apk` artifact (kept for 90 days). The workflow can also
be started by hand (**Run workflow**) with `build_type` = `release` or `debug`.
The release APK is signed with the debug key so it installs on any device for
field testing; configure a proper upload key in `android/app/build.gradle.kts`
before publishing to a store.

## Testing

```bash
flutter test
```

Tests use `sqflite_common_ffi` (no device needed) and an in-memory fake of the
server API to exercise the whole offline → push → resolve → push cycle.

## Screenshots

The images in `screenshots/` are rendered by a widget test from fixtures that
were captured from a real BMA-NFE server running the mobile API
(`test/screenshots/fixtures/`, produced by
`python -m student_registration.mobile_api.tests.make_fixtures` in BMA-NFE).
Regenerate them with:

```bash
BMA_SCREENSHOTS=1 flutter test test/screenshots/screenshot_generator_test.dart
```

| | | |
|---|---|---|
| ![Server setup](screenshots/28_server_setup.png) | ![Login](screenshots/01_login.png) | ![Home](screenshots/02_home.png) |
| ![Beneficiaries](screenshots/03_beneficiaries.png) | ![Child profile](screenshots/04_child_profile.png) | ![Services](screenshots/05_child_services.png) |
| ![Registration wizard](screenshots/06_registration_wizard_identity.png) | ![Caregivers step](screenshots/07_registration_wizard_caregivers.png) | ![PSS service form](screenshots/08_service_form_pss.png) |
| ![Teachers](screenshots/09_teachers.png) | ![Dashboard](screenshots/10_dashboard.png) | ![Sync centre](screenshots/11_sync_center.png) |
| ![Push report](screenshots/12_push_report.png) | ![Duplicate resolution](screenshots/13_duplicate_resolution.png) | ![Sync history](screenshots/14_sync_history.png) |
| ![Settings](screenshots/15_settings.png) | ![NFE centre profile](screenshots/30_center_profile.png) | |
| ![Getting started](screenshots/22_tips_welcome.png) | ![Tips: registering](screenshots/23_tips_register.png) | ![Tips: push](screenshots/24_tips_push.png) |
| ![Server setup (Arabic)](screenshots/29_server_setup_arabic.png) | ![Home (Arabic)](screenshots/18_home_arabic.png) | ![Beneficiaries (Arabic)](screenshots/19_beneficiaries_arabic.png) |
| ![Registration wizard (Arabic)](screenshots/20_registration_wizard_arabic.png) | ![Getting started (Arabic)](screenshots/25_tips_welcome_arabic.png) | ![Tips: push (Arabic)](screenshots/26_tips_push_arabic.png) |
| ![Sync centre (Arabic)](screenshots/21_sync_center_arabic.png) | ![Centre profile (Arabic)](screenshots/31_center_profile_arabic.png) | |

Tablet layout (attendance sheet, beneficiaries list and the Getting started
tour):

| | | |
|---|---|---|
| ![Attendance on tablet](screenshots/16_attendance_tablet.png) | ![Beneficiaries on tablet](screenshots/17_beneficiaries_tablet.png) | ![Getting started on tablet](screenshots/27_tips_welcome_tablet.png) |

`screenshots/contact_sheet.png` shows every phone screen on one page. Rebuild it
after regenerating the captures with `python3 tool/contact_sheet.py` (needs
Pillow).

## Licence

GPLv3, same as BMA-NFE.
