# BMA Mobile – architecture notes

## Design goals

1. **Replicate the web platform without duplicating its business rules.**
   The Django forms of BMA-NFE remain the single source of truth. The server
   introspects them and serves *schemas*; the app renders forms from those
   schemas and posts values in the exact shape a browser would.
2. **Offline first.** Everything the user is allowed to see is stored in
   SQLite; every write is a local write. Network is only needed to log in the
   first time, download reference data/records and push work.
3. **No silent duplicates.** Offline data is verified by the server on push.
   The user receives a per-record report and decides how to resolve matches.
4. **Auditability.** Every push batch is stored on both sides.

## Layers

```
        AdaptiveShell + LayoutScope (core/layout)   ← width classes & tokens
                         │
UI (features/*)  ──▶  SchemaForm engine (core/forms)  ──▶  EntityDao (core/db)
        │                                                     │
        └── SyncEngine (core/sync) ──▶ BmaApi (core/network) ─┘
```

* `EntityRecord` is the unit of storage: `{uuid, entity, data(JSON), server_id,
  parent_uuid, natural_key, sync_state, op, …}`.
* Identity records (registrations) are stored either in the *server shape*
  (nested `child`/`student` object, as pulled) or the *form shape*
  (flat `child_*` keys, as typed offline). `SyncEngine.flattenIdentityPayload`
  converts both to the form shape used for display, editing and pushing.
* Services, teachers and school activities are stored in the form shape.
* Attendance sheets are stored exactly as the server payload
  (`children_attendance` rows referencing `registration_id` or, for children
  registered offline, `registration_uuid`).
* `features/*` holds one folder per screen group: `auth`, `home`, `settings`,
  `registrations`, `services`, `attendance`, `teachers`, `dashboard`, `sync`,
  `profiles` (NFE centre and ALP school), `setup` (first-run server address
  page) and `tips` (getting-started wizard and the dismissible `TipCard`).
* UI preferences that must outlive the database live in `SharedPreferences`
  and are loaded in `main()` before the first frame: `SettingsController`
  (server URL, whether it was ever confirmed, language) and `TipsController`
  (which accounts have seen the wizard and which screen tips they closed).
  Both survive logout and *Clear local data*.

## Layout

The app is **tablet-first for a 9-inch Android tablet** (1280x800 landscape,
800x1280 portrait, dpr 2.0), with the 412x915 phone as a supported fallback.
Both orientations work and there is no orientation lock.

The full reference is **[docs/TABLET_LAYOUT.md](TABLET_LAYOUT.md)**; the code is
in [`lib/core/layout/`](../lib/core/layout/). The parts that touch the rest of
this document:

* **Three width classes** — `compact` (< 600), `medium` (600–999), `expanded`
  (>= 1000) — derived from the **box a widget is drawing into**, published as an
  `AppLayout` token bundle through the `LayoutScope` `InheritedWidget`.
  `LayoutScope.of` falls back to `AppLayout.compact`, whose every token is the
  literal the codebase already had, so any screen or widget with no scope above
  it renders exactly as it did before.
* **The shell reads the WINDOW, everything below reads its PANE.** The
  navigation rail consumes 212 px, so deciding its existence from a pane-derived
  class would feed its own width back into the measurement. `adaptive_shell.dart`
  is the only file that reads `MediaQuery.sizeOf` for a layout decision.
* **The rail is installed at `MaterialApp.router(builder:)`, above the
  `Navigator`** — so it never re-animates with a page transition. **There is no
  `ShellRoute`**: the route table, every navigation string and the redirect
  logic are untouched, and a `ShellRoute` restructure would have required every
  route string to be re-checked. The rail navigates with pop/push/replace so the
  back stack stays `[Home]` or `[Home, destination]` and Android back still
  means "back to Home".
* **One router change**: `/registrations/:module` accepts a `?sel=` query
  parameter (`Routes.registrationsSelected`). It is the only routed
  master-detail in the app — selecting a child `replace`s the query parameter on
  the same route, so the list's `State` (search text, scroll offset) survives,
  the URL is shareable and rotation keeps the selection. `matchedLocation`
  ignores query strings, so the redirect at the top of the router is unaffected.
  Every other split (attendance, sync centre, the facility profile) is
  intra-screen and owns both halves already.
* **The form engine is width-aware.** `core/forms/field_layout.dart` packs the
  schema's fields into 1–3 columns at the two lines in `schema_form.dart` that
  render every server-driven form. **The packer rearranges, it never filters**:
  `collect()` drops the values of reveal-hidden fields, so changing which fields
  are *visible* would change what gets saved. `ValueKey('field-<name>')` is
  load-bearing for the live `TextEditingController`, not just for tests.
* **The registration wizard's step model is untouched.** Its per-section
  `validate()` and the duplicate check gated on step 0 are unchanged; the
  expanded-width step rail is backward-only, so `_next()` remains the single
  path forwards and the duplicate check cannot be skipped.

Screenshots are captured for all three device classes — see
[Screenshots](#screenshots) below and §8 of `TABLET_LAYOUT.md`.

## Screenshots

`screenshots/` holds one PNG per screen per device class, rendered by
`test/screenshots/screenshot_generator_test.dart` from the fixtures in
`test/screenshots/fixtures/`, plus three contact sheets — one per aspect ratio,
because the sheet builder resizes thumbnails and would otherwise squash a
1280x800 capture into phone proportions:

| Sheet | Device | Captures |
|---|---|---|
| `screenshots/contact_sheet_tablet_landscape.png` | 1280x800 | `*_tablet_landscape.png` — the primary set |
| `screenshots/contact_sheet_tablet_portrait.png` | 800x1280 | `*_tablet.png` minus the landscape ones |
| `screenshots/contact_sheet.png` | 412x915 | everything else — the phone fallback |

```bash
BMA_SCREENSHOTS=1 flutter test test/screenshots/screenshot_generator_test.dart
python3 tool/contact_sheet.py                      # all three sheets
python3 tool/contact_sheet.py --mode tablet-landscape
```

Regenerating everything is also the cheapest phone-fallback regression check:
after a layout change, **a 412x915 capture that changes is a regression**, not
churn. (Four captures show a wall-clock timestamp and always differ.)

## Sync engine

| Step | Behaviour |
|---|---|
| `bootstrap()` | Downloads reference lists (nationalities, locations, centres, schools, rounds, programmes …), attendance choice lists and all form schemas for the user's modules. |
| `pull(full:)` | Pages through `/pull/?since=` and upserts records. Rows with unsent local work are never overwritten; the server copy is kept in `conflict_data`. Deleted rows are removed. |
| `push()` | Takes the outbox (pending records, plus resolved duplicates/conflicts), orders parents before children and attendance last, sends batches of 200 with `client_uuid`/`parent_uuid` references, then applies each result: `created/updated/merged/linked` → synced (server ids and generated numbers copied back, children re-parented); `duplicate` → needs resolution with candidate list; `conflict` → needs resolution with server copy; `error` → field errors shown in the form; `skipped` → stays pending (parent failed); `discarded` → read-only. |

Resolutions are stored on the record (`resolution` JSON) and sent with the
next push; the user never re-types data.

## Roles and scope

The login response carries `modules.{mscc,alp,clm}` with `enabled`,
`can_register`, `can_edit`, `can_attend`, `can_manage_teachers` and the
`scope` (`all`, `partner`, `center`, `school`). The UI hides what a user
cannot do; the server re-checks every write and forces centre/school/partner
from the account exactly as the web views do.

## Facility profiles

The MSCC module is presented as **NFE** throughout the interface; `mscc` stays
its key in the API, the database and the entity names, so only the label
changed.

`lib/features/profiles/` builds a profile of the facility the account works at:
`/profile/center` for NFE and `/profile/school` for ALP, both reached from the
programme card on the home screen and both offline-only reads.

`facility_profile.dart` holds the logic and takes its labels from the caller,
so it carries no widgets and is unit-tested directly. It assembles:

* the facts, from the `centers` and `schools` reference lists the bootstrap
  already sends (partner, governorate, district, cadaster, type, programmes,
  coordinates, school number, BMA flag, working days);
* the location names, by resolving the id chain against the `locations`
  reference list in the interface language;
* the figures, by counting local records (registrations, attendance days and
  anything still pending for that module).

Values the server did not send are skipped rather than shown empty, and an
unknown location id falls back to "Not recorded" instead of throwing.

ALP schools additionally have a real form on the server
(`alp.school_profile`, one per school), so the school profile offers an edit
card that opens it through the ordinary schema form engine. That entity has no
parent record, which is why `ServiceFormScreen` accepts a null `parentUuid` and
the router carries a `/form/:entity` route for it.

## First-run server setup

The app is not bound to one deployment: `AppConfig.defaultServerUrl` only
prefills the field. Route `/setup` opens `ServerSetupScreen`
(`lib/features/setup/`), the landing page of a device nobody has set up yet:
the server address, an optional connection check, and the interface language
so a field worker can switch to Arabic before signing in. **Continue** saves
the address with `SettingsController.setServerUrl` (which normalises it and
marks the device configured) and goes to `/login`.

`AppSettings.serverConfigured` is `true` as soon as `server_url` exists in
shared preferences, so devices upgraded from an earlier release keep going
straight to the sign-in screen and the page is never shown twice. Settings
still edits the address afterwards.

`ServerProbe.check` (`lib/core/network/server_probe.dart`) backs the
connection test with an unauthenticated GET on the login endpoint, which only
accepts POST:

| Answer | Result | Shown as |
|---|---|---|
| 405, 401, 403, 200 | `ok` | the deployment runs the mobile API |
| 404 | `notBmaServer` | reachable, but the mobile API is not installed |
| transport error, 5xx | `unreachable` | wrong address, no network or server down |

A failed check never blocks **Continue**: devices are often set up before they
have connectivity. `serverProbeProvider` is overridden in tests
(`FakeServerProbe`) so nothing touches the network.

## First-run tips

Route `/tips` opens `TipsWizardScreen` (`lib/features/tips/`), a `PageView`
of five to seven pages built by `tipPages(l10n, profile)`: welcome
(personalised with the account's name and partner · centre · school), your
data on this device (with a text-only footer: downloading / ready / full
refresh needed), registering a child (only if an enabled module has
`can_register`), services and attendance, push and the report, duplicates and
conflicts (only with `can_register` or `can_edit`) and keeping data safe.
Skip (first run only, hidden on the last page) and Done both mark the tour as
seen for the signed-in account. System back goes to the previous page; on
page 1 it pops only when the wizard was pushed from Home or Settings, and on
a first run it is a no-op so the tour is never marked seen silently.

### Routing

The `redirect` in `lib/router.dart` runs in this order:

1. Auth checks, unchanged: `unknown` → splash, `signedOut` → `/setup` while
   the device has no confirmed server address, otherwise `/login`. Session
   expiry therefore still wins over the wizard.
2. `/tips` itself never redirects, seen or not, so the rule is loop-free and
   a user who has already seen the tour can `context.push(Routes.tips)`.
3. `tipsPendingProvider` (signed in and no `tips_seen` entry for the current
   tips version) sends every other location to `/tips`, deep links included.
4. Splash, login and setup go to home; everything else stays where it is.

Only `ref.read` is used inside `redirect` (a `ref.watch` would rebuild the
`GoRouter` and reset the navigator) and `_AuthListenable` is unchanged: login
and restore already re-run the redirect through `AuthState`, and the wizard
navigates explicitly after `markSeen` (`context.go(Routes.home)` on a first
run, `context.pop()` when pushed from Home or Settings). `markSeen` updates
the state synchronously before persisting, so the redirect triggered by that
navigation already sees `pending == false`.

Accepted consequences: a deep link opened during a pending first run ends on
Home, and accounts on installs upgraded to this release see the tour once.

### Persistence

`TipsController` keeps two `SharedPreferences` string lists, loaded by
`TipsController.load()` in `main()` next to `SettingsController.load()`:

| Key | Entries | Written by |
|---|---|---|
| `tips_seen` | `<user id>:<AppConfig.tipsVersion>` | `markSeen` (Skip or Done) |
| `tips_dismissed` | `<user id>:<tip id>` | `dismissTip` (Got it), `restoreTips` (Show tips again) |

Entries are keyed on `UserProfile.id` because shared tablets host several
accounts. They survive logout and *Clear local data* on purpose: the SQLite
`meta` table is not used because `AppDatabase.clearAll()` wipes it, and
`AppSettings` is not used because `BmaApp` watches the whole settings object.

### Rules

* Bump `AppConfig.tipsVersion` only when the wizard content changes enough
  that every account should see the tour once more; dismissed screen tips are
  kept.
* *Show tips again* (Settings) calls `restoreTips` for the current user and
  pushes `/tips`. It must never clear `tips_seen`: a cleared flag while on
  `/settings` would make the next navigation jump to `/tips` and drop the
  stack.
* `tipsControllerProvider` has a working in-memory default, so tests that do
  not care about tips need no override. `main()` replaces it with the instance
  loaded from `SharedPreferences`; the screenshot harness
  (`_container(tipsSeen:)`) and the tips tests (`test/support/fakes.dart`)
  override it with in-memory state.
* Screen tips are `TipCard(id: TipIds.x, text: l10n.tipX)` widgets rendered as
  `SizedBox.shrink()` once dismissed: Home (under the sync card), Beneficiaries
  list (under the filter, hidden while the keyboard is open because it is a
  fixed child above the list), Attendance (until a roster is loaded) and Sync
  centre (under the status card).
* Stable keys for tests and the harness: `tips-skip`, `tips-back`,
  `tips-next`, `tips-page-wide`, `tip-<id>`, `home-help` and
  `settings-show-tips`.

### Adding a tip

A wizard page:

1. Add `tipsXTitle` / `tipsXBody` to both `lib/l10n/app_en.arb` and
   `app_ar.arb`, then run `flutter gen-l10n`.
2. Add the value to `TipPageKind` and append a `TipPage` in `tipPages()`
   (`lib/features/tips/tips_content.dart`) with its capability gate.
3. Update the page-count expectations in `test/tips_content_test.dart` and
   `test/tips_wizard_test.dart`.
4. Bump `AppConfig.tipsVersion` if existing accounts should see it.

A screen tip:

1. Add `tipY` to both ARB files and run `flutter gen-l10n`.
2. Add a constant to `TipIds`.
3. Place `TipCard(id: TipIds.y, text: l10n.tipY)` at the point of need.
4. Regenerate the screenshots and rebuild the contact sheets
   (`BMA_SCREENSHOTS=1 flutter test
   test/screenshots/screenshot_generator_test.dart`, then
   `python3 tool/contact_sheet.py`).

## Adding a new form to the app

Nothing to do in the app: register the Django form in
`student_registration/mobile_api/registry.py` (entity key, model, form class,
parent, scope, permission) and it appears under *Add service* on the next
bootstrap, with validation and choices taken from the form.
