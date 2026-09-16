# Tablet layout

BMA Mobile is **tablet-first for a 9-inch Android tablet** — 1280x800 landscape,
800x1280 portrait, device pixel ratio 2.0 — with the 412x915 phone kept as a
supported, provably unchanged fallback. Both orientations are supported and
there is no orientation lock anywhere in the project.

Everything here lives in [`lib/core/layout/`](../lib/core/layout/):

| File | What it owns |
|---|---|
| `breakpoints.dart` | The width classes and the raw thresholds. No widgets. |
| `app_layout.dart` | `AppLayout`, the token bundle, and `LayoutScope`, the `InheritedWidget` that publishes it. |
| `adaptive.dart` | `AdaptiveBody`, `TwoPane` and the grid helpers that install a scope. |
| `adaptive_shell.dart` | The navigation rail, installed at `MaterialApp.router(builder:)`. |
| `nav_destinations.dart` | The rail's destinations and its pop/push/replace navigation. |
| `current_module.dart` | The module the rail is showing, and `unsavedWorkProvider`. |

---

## 1. The three width classes

`WidthClass` classifies the **box a widget is drawing into** — never the device,
and (below the shell) never the window.

| Class | Width | Examples |
|---|---|---|
| `compact` | < 600 | Phone portrait (412). A 400 px master list pane. A narrow split-screen window. Always one column; always today's layout. |
| `medium` | 600–999 | 9" tablet portrait (800). Phone landscape (915). Half of a 1280 landscape window in Android split-screen (640). |
| `expanded` | >= 1000 | 9" tablet landscape. The only class that unlocks two-pane splits. |

### The arithmetic for the target hardware

```
1280 x 800  landscape  ->  extended rail 212  ->  content box 1067  ->  expanded
 800 x 1280 portrait   ->  no rail (window < 1000) ->  content box 800  ->  medium
 412 x 915  phone      ->  no rail             ->  content box 412   ->  compact
 915 x 412  phone landscape -> no rail (the window is only 412 tall)  ->  medium
```

The phone-landscape row is the reason the rail has a **height** gate as well as
a width gate: 915 px is wide enough for a rail, but eight ~56 px destinations do
not fit in a 412 px-tall window. `Breakpoints.railMinHeight` is 560.

---

## 2. The two-threshold rule

**The shell reads the WINDOW width. Everything below it reads the PANE width it
was handed.**

The rail consumes 212 px. If the rail's own existence were decided from a
pane-derived width class, the rail would be feeding its own width back into the
measurement that decides whether it exists. So `adaptive_shell.dart` is the only
file that reads `MediaQuery.sizeOf(context)`, and it compares against
`Breakpoints.railWindowMin` (1000) and `railExtendedMin` (1200) — window
thresholds that exist separately from the content thresholds precisely so the
two questions can never be confused.

Every screen below the shell derives its class from
`LayoutBuilder`'s `constraints.maxWidth`. On the target tablet in landscape that
is 1067, not 1280, and a form inside a 400 px list pane is `compact` — which is
the correct answer.

A third, separate question: **type size and control density follow the DEVICE**
(`shortestSide >= Breakpoints.tabletShortestSide`, 640), while **columns and
panes follow the BOX**. `isTabletDevice()` is used for modality (a reference
picker is a bottom sheet on a phone and a centred dialog on a tablet) and for
the theme's density, never for how many columns something gets.

640, not 600, because Flutter's default widget-test surface is 800x600, where
`shortestSide >= 600` silently evaluates true in any test that forgets to set
`tester.view.physicalSize`. A 9-inch tablet's shortest side is 800 in both
orientations, so 640 leaves 160 px of margin either way.

---

## 3. `LayoutScope` and the fail-safe default

```dart
static AppLayout of(BuildContext context) =>
    context.dependOnInheritedWidgetOfExactType<LayoutScope>()?.layout ??
        AppLayout.compact;
```

`LayoutScope.of` returns `AppLayout.compact` when **no scope is installed**.
Every `compact` token in `AppLayout.compact` is the literal that was already in
the codebase, so an unconverted screen, a bare widget pumped by a test, or a
dialog built outside the tree renders exactly as it did before this work.

**`LayoutScope.of` must never become an assert.** Turning the missing-scope case
into a failure would convert every one of those situations from "renders the
phone layout" into "crashes", and the whole screen-by-screen rollout depends on
the opposite.

Scopes **nest**. `AdaptiveBody` installs one from the box it measures, and each
pane of a `TwoPane` re-installs its own, so content inside a 400 px pane on a
1280 px tablet correctly reports `compact`.

---

## 4. The phone-fallback invariants

These four are what make "the phone layout did not move" a fact rather than a
claim. Each is enforced by a test.

1. **`AppTheme.light(tablet: false) == AppTheme.light()`** —
   `test/layout/theme_invariant_test.dart`.
2. **The form packer's one-column fast path** returns the exact
   `Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children)`
   expression that `schema_form.dart` had before this work, so a compact form
   produces the identical render tree.
3. **`TwoPane` below `expanded` returns its pane verbatim** — no `Row`, no
   `Expanded`, no extra render object.
4. **The rail's hidden branch returns the page child untouched.**
   `adaptive_shell.dart` returns before any `Row` is constructed; the only thing
   above the child is a `Theme`, an `InheritedWidget`, which creates no render
   object at all.

The fifth, empirical check is the screenshot set: regenerate everything and
every 412x915 capture should come back byte-identical. See
[Screenshots](#8-screenshots) below.

---

## 5. The 720 ban

**No layout token anywhere may equal 720.**
`test/layout/breakpoints_test.dart` walks every `double` field of all three
`AppLayout` bundles and asserts none is 720.

The reason is not aesthetic. `test/tips_wizard_test.dart` matches **any**
`ConstrainedBox` with `maxWidth == 720` in the tips subtree and expects to find
exactly one — the tips wizard's own page cap. A shared 720 token introduced
anywhere above it would make that test fail while pointing at a file nobody
changed. The three reading/content caps are 700, 760, 840, 1040 and 1120 for
exactly this reason.

---

## 6. The 800x600 test-surface trap

Flutter's default widget-test surface is **800x600**. 800 resolves to
`WidthClass.medium`, so from this work onwards a widget test that forgets to set
a viewport silently exercises the **tablet** layout while reading like a phone
test.

Use [`test/support/viewport.dart`](../test/support/viewport.dart), which also
resets the view on tear-down:

```dart
phone(tester);           // 412 x 915  @ 2.625 — the fallback device
tabletPortrait(tester);  // 800 x 1280 @ 2.0   — the registration posture
tabletLandscape(tester); // 1280 x 800 @ 2.0   — the desk posture
phoneLandscape(tester);  // 915 x 412  @ 2.625 — wide but short: the rail's height gate
```

Two further testing notes:

* A test that loads real fonts with `FontLoader` pollutes every **later** test
  in the same file — the engine keeps the fonts, so width assertions written for
  the default test font start failing. Keep a font-loading test in its own file.
* `AppDatabase.openInMemory()` opens `:memory:` with sqflite's default
  `singleInstance: true`, so every container in one test **file** shares one
  database. Fixtures must be idempotent or they accumulate.

---

## 7. Touch targets: the physical arithmetic

A logical pixel on this panel is **1/168 inch ≈ 0.151 mm**, which is physically
*smaller* than on the Pixel 7 this replaces (~149 px/inch). Keeping 48dp targets
would therefore ship **physically smaller** buttons to a **bigger** device:

| | Pixel 7 (~149 px/in) | 9" tablet (~168 px/in) |
|---|---|---|
| 48 dp | ~8.2 mm | ~7.3 mm |
| 52 dp | — | ~7.9 mm |
| 56 dp | — | ~8.5 mm |
| 60 dp (attendance segment) | — | ~9.1 mm |

Hence `touchTarget` is 48 / 52 / 56 across the three classes, and the attendance
Present/Absent segment — the control tapped twenty-five times per class — is
60 px tall. **Do not "simplify" 56 back to 48.** It is not a rounding of the
Material default; it is the compensation for a denser panel.

---

## 8. Screenshots

Three device classes, three contact sheets, one aspect ratio each:

```bash
BMA_SCREENSHOTS=1 flutter test test/screenshots/screenshot_generator_test.dart
python3 tool/contact_sheet.py            # all three
python3 tool/contact_sheet.py --mode phone
```

| Sheet | Size | Captures |
|---|---|---|
| `screenshots/contact_sheet_tablet_landscape.png` | 1280x800 | `*_tablet_landscape.png` — the primary set |
| `screenshots/contact_sheet_tablet_portrait.png` | 800x1280 | `*_tablet.png` minus the landscape ones |
| `screenshots/contact_sheet.png` | 412x915 | everything else — the phone fallback |

`tool/contact_sheet.py` resizes every thumbnail with `Image.LANCZOS`, which does
not letterbox a mismatched aspect ratio, it **squashes** it. That is why there
is one sheet per aspect and why the script warns when a capture does not match
the sheet it is going into.

The harness derives the pixel ratio from the device record
(`_shootFor(tester, name, device)`) and asserts the current view matches, so a
capture can no longer be written at the wrong scale without failing.

---

## 9. The navigation rail

The rail lives at `MaterialApp.router(builder:)` — **above the `Navigator`** —
so it does not re-animate with every page transition. There is deliberately no
`ShellRoute`: the route table, every `context.go`/`push` string and the redirect
logic are untouched.

Three consequences of sitting above the `Navigator` that look like mistakes and
are not:

1. **There is no `Scaffold` in the shell.** `ScaffoldMessenger` only presents a
   `SnackBar` in the root registered `Scaffold`, so a `Scaffold` above the
   `Navigator` would re-anchor every `showMessage` in the app to the window
   bottom, sliding it under the rail.
2. **The rail has no `Overlay` ancestor.** The app's only `Overlay` belongs to
   the page `Navigator`, and that `Navigator` is a *sibling* of the rail, so
   the overlay starts after the rail and its divider (`Offset(213, 0)`,
   `1067x800` on the target device). That is why `RailAction` uses `Semantics`
   rather than `Tooltip` — a plain `Tooltip` there throws at runtime, not at
   analyze time — and why the module switcher asks in a **centred dialog**
   rather than an anchored menu. An anchored `showMenu` cannot reach back over
   the rail and cannot be told to try: `_PopupMenuRouteLayout` clamps the menu
   8 px inside the overlay, so window coordinates and overlay coordinates put
   the first item in exactly the same place, clear of the control. A dialog has
   no anchor to get wrong and matches `AppLayout.dialogPickers`, which is
   already true everywhere the rail exists. Keys: `nav-module-menu`,
   `nav-module-option-<module>`.
3. **`currentLocation()` reads `routerDelegate.state.matchedLocation`, not
   `currentConfiguration.uri`.** The uri ignores imperative route matches, so
   after a `push` it still reports `/home` — and a rail that believed it would
   push a second copy of the page it is standing on, growing the back stack on
   every tap.

### Stack discipline

`context.go` was rejected because it replaces the whole stack and would make
Android back exit the app from any destination. Instead the rail keeps the stack
at `[Home]` or `[Home, destination]`:

| Tap | Action |
|---|---|
| Any tap, first | **unwind**: `pop` while the stack is deeper than two |
| To Home | `pop` the remaining destination, `go(Routes.home)` if that did not land on Home |
| From Home to a destination | `push` |
| Destination to destination | `replace` |
| The destination you are on, or the one the unwind landed on | nothing |

The unwind is the part that is easy to leave out and impossible to notice from
the rail alone: six screens push a page of their own ("Register new", a child
profile below `expanded`, a sync queue item, a teacher form). Without it "to
Home" pops one level and lands on the middle page, and a rail-to-rail `replace`
swaps that middle page while the stale destination stays underneath — so the
stack deepens by one on every drill-down for the rest of the session.

So Android back still means "back to Home", exactly as it did on the phone.

### Modes

| Window | Mode | Width |
|---|---|---|
| < 1000 wide, or < 560 tall, or a gate route | `hidden` | 0 — the child is returned untouched |
| >= 1000 | `collapsed` | 72 (`railCollapsedWidth`) |
| >= 1200 | `extended` | 212 (`railExtendedWidth`) |

The gate routes — `/`, `/login`, `/setup`, `/tips` — render with no rail by
design, so a login or tips capture at 1280x800 showing no rail is correct.

The collapsed rail sets `scrollable: true` and `trailingAtBottom: true`. The
label gate (`_chromeHeight + destinations * _labelledDestination`) is a *hint*:
a 72 px rail wraps `Teacher attendance` to three lines, so a labelled
destination is 64-112 px tall rather than 76, and the estimate never sees the
text scaler. `scrollable` makes a wrong guess degrade to a scrolling
destination group instead of laying the last destinations out past the bottom
edge, and `trailingAtBottom` pins Sync centre and Settings in the rail's outer
`Column` — outside that group, genuinely at the bottom. With the Flutter
default (`false`) the trailing block is appended *inside* the shrink-wrapped
group, where an `Align(bottomCenter)` has nothing to align against and the two
app-wide actions float mid-rail — and where they are the first thing an
overflow pushes off the rail.

In Arabic the rail mirrors to the **trailing** (right) edge. That is the single
most visible tablet-specific difference between the two languages, and
`test/layout/rail_test.dart` asserts it mechanically: the rail's top-left x must
be past the window's midpoint *and* equal `1280 - railExtendedWidth`.

Destination keys are on the destination's **icon**, not its label, because the
label is absent from the tree when the label type is `none`: `nav-rail`,
`nav-dest-home`, `nav-dest-facility`, `nav-dest-beneficiaries`,
`nav-dest-attendance`, `nav-dest-teacher-attendance`, `nav-dest-teachers`,
`nav-dest-dashboard`, `nav-dest-sync`, `nav-dest-settings`, `nav-module-switch`.

---

## 10. Protected `ValueKey`s

These keys predate the tablet work and are matched by existing tests and by the
screenshot harness. **A layout change must keep every one of them**, on the same
widget kind, in every width class.

| Key | Where |
|---|---|
| `tips-skip`, `tips-back`, `tips-next` | `lib/features/tips/tips_wizard_screen.dart` |
| `tips-page-wide` | `tips_wizard_screen.dart` — note this one is a plain `Key`, **not** a `ValueKey`; grepping for `ValueKey('tips-page-wide')` reports a false violation |
| `tip-<id>` | `lib/features/tips/tip_card.dart` |
| `home-help` | `lib/features/home/home_shell.dart` |
| `settings-show-tips` | `lib/features/settings/settings_screen.dart` |
| `setup-language`, `setup-url`, `setup-test`, `setup-continue`, `setup-result` | `lib/features/setup/server_setup_screen.dart` |
| `profile-status`, `profile-edit` | `lib/features/profiles/facility_profile_screen.dart` |

---

## 11. Standing rules

* **Never `MediaQuery.of` in an app-level builder.** The Android manifest
  declares `windowSoftInputMode="adjustResize"`, so `viewInsets` changes
  continuously while the soft keyboard animates; `MediaQuery.of` subscribes to
  every aspect and would rebuild the entire app on every keystroke. Use
  `MediaQuery.sizeOf` / `MediaQuery.textScalerOf`.
* **Never use `shortestSide` for a layout decision** — only for modality and
  density. Columns and panes come from the measured box.
* **Never use 720 as a content cap** (see §5).
* **All new padding and alignment is directional.** `EdgeInsetsDirectional` and
  `AlignmentDirectional`, never a hard-coded `left`/`right`, never a bare
  `Positioned(left:)`. Arabic is a first-class locale here, and the codebase's
  historical default (`EdgeInsets.fromLTRB`) is the wrong one.
* **Never add `android:screenOrientation`**, `android:maxAspectRatio`,
  `<supports-screens>` or `SystemChrome.setPreferredOrientations`. Any of them
  silently defeats this work; `test/android_manifest_test.dart` guards the
  manifest half.
* **Theme-level text styles must be derived from the text theme**, never built
  as a bare `TextStyle`: a bare one replaces rather than merges, and loses the
  Arabic font fallback with it.
* **The form packer rearranges, it never filters.** `collect()` drops
  reveal-hidden values, so changing which fields are *visible* would change what
  gets saved.
