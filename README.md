# BMA Mobile (BMA-App)

Offline-first Flutter companion of the **BMA-NFE** web platform for the NFE
sector in Lebanon. Partners take a tablet or phone to the field, register
children, record services and take daily attendance **without internet**, then
push everything to BMA-NFE when a connection is available. The server verifies
each record, detects duplicates and returns a report; the field worker decides
whether to merge, link, create or discard.

| Module | What the app covers |
|---|---|
| **Makani / MSCC** | Beneficiary list & search, 3-step registration wizard, child profile, every service form (education, PSS, health & nutrition, youth, inclusion, digital, LEGO, recreational, follow-up, referrals, grading), new round, teachers, daily attendance per programme/section, dashboard, advanced analytics |
| **ALP schools** | Registrations, child profile, grading, teachers, school profile, children attendance, teacher attendance, dashboard, four analytics dashboards |
| **CLM Bridging** | Bridging registrations (with pre-test), post/mid assessments, follow-up, services, teachers, clubs/meetings/initiatives/health visits, attendance per level, dashboard |

All forms are **generated from the web platform's Django forms** at runtime:
labels (English/Arabic), choices, required flags, lengths and conditional
sections are downloaded once (`bootstrap`) and cached in SQLite, so the app
never drifts from the website.

## Target device

The app is **tablet-first for a 9-inch Android tablet**: 1280x800 landscape,
800x1280 portrait, device pixel ratio 2.0. **Both orientations are supported and
there is no orientation lock** — rotating never recreates the activity, it just
hands Flutter a new view size.

The **412x915 phone is a supported fallback**, not an afterthought: every
control below 600 px renders exactly as it did before the tablet work, and the
phone screenshot set is regenerated as the proof.

[![Tablet layout](screenshots/contact_sheet_tablet_landscape.png)](screenshots/contact_sheet_tablet_landscape.png)

*Every 1280x800 screen on one page. The phone sheet is
[`screenshots/contact_sheet.png`](screenshots/contact_sheet.png); see
[Screenshots](#screenshots) for all three, and
[docs/TABLET_LAYOUT.md](docs/TABLET_LAYOUT.md) for how the layout decides what
to show.*

## Analytics

Every programme card carries an **Analytics** action (and the tablet rail an
Analytics destination) that opens the dashboards of the web platform, computed
**from the records already on the device** — no extra endpoint, and they work
in the field with no connection. Figures therefore describe what this account
has downloaded and typed, which the page says once at the top.

| Dashboard | Mirrors | What it shows |
|---|---|---|
| **NFE · Advanced analytics** | `/dashboard/advanced-analytics/` | Registrations, teachers, partners, centres and programmes; the daily registration trend; registrations by centre, gender and nationality; teacher gender, nationality and centre; a cross-tab that pairs any two of the six dimensions the analytics API names, opening on programme × age group. Filters: date range, partner, centre, programme, and — behind *More filters* — nationality, gender and an age band. |
| **ALP · Registration insights** | `alp:dashboard_registration` | Registrations, active schools, partners and programme rounds; the learning-outcome block (children assessed, average achievement, follow-ups, children improving, latest performance, progress since the first assessment, achievement by subject); gender, gender × age group, nationality, source of identification, registrations per round, family status, disability type, cash support, referral to formal education and children moved between rounds. Filters: school, round, programme. |
| **ALP · Teacher dashboard** | `alp:dashboard_teacher` | Teachers, active schools, teachers trained (with the share), average experience and training, contact coverage; gender, nationality, assignment, teachers by school and round, subjects, grade levels, training topics, teaching hours and extra coaching. Filters: school, round. |
| **ALP · Attendance dashboard** | `alp:dashboard_attendance` | The month × day attendance heatmap of the selected year, overall and one per programme, with a year selector. |
| **ALP · School dashboard** | `alp:dashboard_school` | Accessible and mapped schools, ALP students and teachers; the school locations map with a school filter and the operational detail of each school. |

The arithmetic is ported from the Django views rather than re-invented, so a
figure on the tablet matches the website's: the age buckets, the "latest
programme" subquery, `Avg` ignoring nulls, the distinct-children-per-round
count and the ±0.5 point progress thresholds are all reproduced, and the
`test/analytics/` suites pin them. The map needs a connection only for its
background tiles; the school markers come from the coordinates the bootstrap
already downloaded, so an offline map still places every school.

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
    layout/     Width classes, layout tokens, LayoutScope, AdaptiveBody/TwoPane, the navigation rail
    widgets/    Shared widgets (sync state chip, offline banner, stat tiles …)
  features/
    auth/ home/ settings/ registrations/ services/ attendance/ teachers/ dashboard/ sync/
    profiles/ setup/ tips/
                                    profiles/ = NFE centre and ALP school profiles
                                       setup/ = first-run server address page
                                        tips/ = getting-started wizard + dismissible screen tips
                                   analytics/ = the five web dashboards, computed offline
                                                (charts/ widgets/ nfe/ alp/)
test/                                    unit tests (form engine, DAO, sync engine, name normalisation, tips), tips_wizard_test / tips_redirect_test
  layout/                                width classes, tokens, the rail and one file per screen group at 412 / 800 / 1280
  support/viewport.dart                  phone / tabletPortrait / tabletLandscape viewport helpers
  screenshots/                           the capture harness and its server fixtures
tool/contact_sheet.py                    builds one contact sheet per device class
docs/TABLET_LAYOUT.md                    the tablet-first layout reference
docs/VALIDATION.md                       how the website's field rules reach the app
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
builds the release APK, then attaches `bma-app.apk` and its `.sha256` to the
release.

Every push to `main` refreshes the rolling **field-test** pre-release. The
asset is called `bma-app.apk` in every build, so this URL always downloads the
newest one and never changes — it is the link to give partners:

```
https://github.com/UNICEFLebanonInnovation/BMA-App/releases/download/field-test/bma-app.apk
```

The release page beside it lists the commit each build came from:

```
https://github.com/UNICEFLebanonInnovation/BMA-App/releases/tag/field-test
```

The rolling release is deleted and recreated on each run, so the link 404s for
the couple of minutes a build takes. To refresh it without pushing, run the
workflow by hand (**Actions → Release → Run workflow**) and leave the tag
empty.

For a real version, tag the commit; the tag name becomes the release:

```bash
git tag v0.1.0
git push origin v0.1.0
```

Tags with a suffix (`v0.1.0-beta.1`) are published as pre-releases.

#### Signing the field-test APK

A phone installs a new build over the old one only when the same key signed
both. Without a key of its own the build falls back to the Android debug key,
which the Gradle plugin generates the first time it is missing — and every CI
runner is a fresh machine, so each build would carry a different key and the
next install would fail with `INSTALL_FAILED_UPDATE_INCOMPATIBLE`. The tester's
only way out is to uninstall, which erases registrations the device has not yet
synchronised. The release notes say which key signed the build.

Give the project one key once, and every build after it installs cleanly:

```bash
keytool -genkey -v -keystore upload-keystore.jks -storetype JKS \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload

gh secret set ANDROID_KEYSTORE_BASE64 < <(base64 -w0 upload-keystore.jks)
gh secret set ANDROID_KEYSTORE_PASSWORD   # the store password you just chose
gh secret set ANDROID_KEY_ALIAS           # upload
gh secret set ANDROID_KEY_PASSWORD        # the key password, if it differs
```

Keep `upload-keystore.jks` somewhere safe and out of the repository. Losing it
means no later build can update an installed one. To sign locally, put the
keystore in `android/app/` and write `android/key.properties`:

```properties
storeFile=upload-keystore.jks
storePassword=…
keyAlias=upload
keyPassword=…
```

`android/.gitignore` already excludes both files. `android/app/build.gradle.kts`
uses them when they are there and the debug key when they are not, so
`flutter run --release` still works on a machine with no key.

#### APK from GitHub Actions

Every push runs `.github/workflows/build.yml`, which analyses and tests the
code and then builds a release APK. Open the run under **Actions → Build** and
download the `bma-app-apk` artifact (kept for 90 days). The workflow can also
be started by hand (**Run workflow**) with `build_type` = `release` or `debug`.
This workflow signs with the debug key, so its artifact is for a developer
checking a change rather than for a tester who already has the app installed.
Anything handed to the field should come from the release link above, which
uses the project's own key — see **Signing the field-test APK**.

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
Regenerate them and rebuild the three contact sheets with:

```bash
BMA_SCREENSHOTS=1 flutter test test/screenshots/screenshot_generator_test.dart
python3 tool/contact_sheet.py                        # all three sheets
python3 tool/contact_sheet.py --mode tablet-landscape
python3 tool/contact_sheet.py --mode tablet-portrait
python3 tool/contact_sheet.py --mode phone
```

There is one sheet per device class because the sheet builder resizes every
thumbnail: mixing aspect ratios does not letterbox them, it squashes them.

### 9-inch tablet, landscape (1280x800) — the primary layout

[`screenshots/contact_sheet_tablet_landscape.png`](screenshots/contact_sheet_tablet_landscape.png)
shows all twenty-one landscape screens on one page.

| | |
|---|---|
| ![Home](screenshots/32_home_tablet_landscape.png) | ![Beneficiaries, two pane](screenshots/33_beneficiaries_two_pane_tablet_landscape.png) |
| ![Child profile](screenshots/34_child_profile_tablet_landscape.png) | ![Attendance](screenshots/35_attendance_tablet_landscape.png) |
| ![Attendance, a child marked absent](screenshots/36_attendance_absent_tablet_landscape.png) | ![Registration wizard: caregivers](screenshots/37_registration_wizard_caregivers_tablet_landscape.png) |
| ![Registration wizard: review](screenshots/38_registration_wizard_review_tablet_landscape.png) | ![Health & nutrition service form](screenshots/39_service_form_health_tablet_landscape.png) |
| ![Teacher form](screenshots/40_teacher_form_tablet_landscape.png) | ![Teacher attendance](screenshots/41_teacher_attendance_tablet_landscape.png) |
| ![Teachers](screenshots/42_teachers_grid_tablet_landscape.png) | ![Dashboard](screenshots/43_dashboard_tablet_landscape.png) |
| ![Analytics](screenshots/59_analytics_hub_tablet_landscape.png) | ![Advanced analytics](screenshots/60_advanced_analytics_tablet_landscape.png) |
| ![Sync centre, two pane](screenshots/44_sync_center_two_pane_tablet_landscape.png) | ![Duplicate resolution, two pane](screenshots/45_duplicate_resolution_two_pane_tablet_landscape.png) |

Arabic, where the navigation rail and every pane mirror to the other edge:

| | |
|---|---|
| ![Home (Arabic)](screenshots/46_home_ar_tablet_landscape.png) | ![Beneficiaries, two pane (Arabic)](screenshots/47_beneficiaries_two_pane_ar_tablet_landscape.png) |
| ![Attendance (Arabic)](screenshots/48_attendance_ar_tablet_landscape.png) | ![Registration wizard (Arabic)](screenshots/49_registration_wizard_ar_tablet_landscape.png) |
| ![Sync centre (Arabic)](screenshots/50_sync_center_ar_tablet_landscape.png) | |

### 9-inch tablet, portrait (800x1280) — the registration posture

No navigation rail (the window is below the 1000 px threshold) and no panes:
the win here is two-column forms and a two-across filter grid.
[`screenshots/contact_sheet_tablet_portrait.png`](screenshots/contact_sheet_tablet_portrait.png)
has all seven.

| | | |
|---|---|---|
| ![Home on tablet](screenshots/51_home_tablet.png) | ![Beneficiaries on tablet](screenshots/17_beneficiaries_tablet.png) | ![Registration wizard on tablet](screenshots/53_registration_wizard_identity_tablet.png) |
| ![PSS service form on tablet](screenshots/54_service_form_tablet.png) | ![Attendance on tablet](screenshots/16_attendance_tablet.png) | ![Centre profile on tablet](screenshots/56_center_profile_tablet.png) |
| ![Getting started on tablet](screenshots/27_tips_welcome_tablet.png) | | |

### Phone (412x915) — the supported fallback

The phone layout is unchanged by the tablet work, and these captures are the
evidence: after a layout change a 412x915 capture that moves is a regression.
[`screenshots/contact_sheet.png`](screenshots/contact_sheet.png) shows every
phone screen on one page.

| | | |
|---|---|---|
| ![Server setup](screenshots/28_server_setup.png) | ![Login](screenshots/01_login.png) | ![Home](screenshots/02_home.png) |
| ![Beneficiaries](screenshots/03_beneficiaries.png) | ![Child profile](screenshots/04_child_profile.png) | ![Services](screenshots/05_child_services.png) |
| ![Registration wizard](screenshots/06_registration_wizard_identity.png) | ![Caregivers step](screenshots/07_registration_wizard_caregivers.png) | ![PSS service form](screenshots/08_service_form_pss.png) |
| ![Teachers](screenshots/09_teachers.png) | ![Dashboard](screenshots/10_dashboard.png) | ![Sync centre](screenshots/11_sync_center.png) |
| ![Analytics](screenshots/57_analytics_hub.png) | ![Advanced analytics](screenshots/58_advanced_analytics.png) | |
| ![Push report](screenshots/12_push_report.png) | ![Duplicate resolution](screenshots/13_duplicate_resolution.png) | ![Sync history](screenshots/14_sync_history.png) |
| ![Settings](screenshots/15_settings.png) | ![NFE centre profile](screenshots/30_center_profile.png) | |
| ![Getting started](screenshots/22_tips_welcome.png) | ![Tips: registering](screenshots/23_tips_register.png) | ![Tips: push](screenshots/24_tips_push.png) |
| ![Server setup (Arabic)](screenshots/29_server_setup_arabic.png) | ![Home (Arabic)](screenshots/18_home_arabic.png) | ![Beneficiaries (Arabic)](screenshots/19_beneficiaries_arabic.png) |
| ![Registration wizard (Arabic)](screenshots/20_registration_wizard_arabic.png) | ![Getting started (Arabic)](screenshots/25_tips_welcome_arabic.png) | ![Tips: push (Arabic)](screenshots/26_tips_push_arabic.png) |
| ![Sync centre (Arabic)](screenshots/21_sync_center_arabic.png) | ![Centre profile (Arabic)](screenshots/31_center_profile_arabic.png) | |

## Licence

GPLv3, same as BMA-NFE.
