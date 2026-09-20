# Field validation

Every form in the app enforces the same rules as the BMA-NFE website, from the
same source: the Django form definitions. Nothing is hand-copied into Dart.

```
Django form field                 schema.py            bootstrap        SQLite
  required=True                →  required          →           →          →
  max_length / min_length      →  max_length …      →           →          →
  min_value / max_value        →  min_value …       →  schemas  →  schemas →  FieldSpec
  validators=[RegexValidator]  →  patterns[]        →           →          →      │
  ChoiceField.choices          →  choices           →           →          →      │
                                                                                  ▼
                                                                    SchemaFormController
```

## Why this exists

The export used to read a field's *arguments* (`max_length`, `min_value`) and
its *class* (`EmailField`), but not its `validators` list. Thirteen fields on
the child registration are letters-only on the website through
`only_letters_validator`, and the app enforced nothing on them: a name typed
with a digit saved on the device and failed on push, in a report the worker
reads hours later with the family long gone.

Attendance had the same shape of problem for a different reason: it shipped
`fields: []`, so the rules lived only in `engine._validate_attendance_common`,
on the far side of a sync. The child sheet re-implemented three of the five by
hand; the teacher sheet implemented none.

## What travels

| Django | Schema key | Enforced by the app as |
|---|---|---|
| `required=True` | `required` | non-empty; for a checkbox, **ticked** |
| `CharField(max_length=, min_length=)` | `max_length`, `min_length` | length bounds |
| `IntegerField(min_value=, max_value=)` | `min_value`, `max_value` | numeric bounds |
| `DecimalField(max_digits=, decimal_places=)` | `max_digits`, `decimal_places` | digits and places |
| `validators=[RegexValidator(...)]` | `patterns[]` | regex, **with the server's own message** |
| `validators=[MinLengthValidator(3)]` etc. | `min_length` … | the same bound, whichever way it is declared |
| `ChoiceField` / `ModelChoiceField` | `choices` / `ref` | the value is one of the options |
| `EmailField` | `type: email` | looks like an address |
| `checkArabicOnly` in JS | `script: "arabic"` | Arabic block or space (see below) |
| (attendance only) | `max_date: today` | not in the future |

`URLValidator` and `EmailValidator` patterns are deliberately **not** shipped:
the app has a type for each, and their regexes are enormous and not portable to
Dart's `RegExp`.

## Arabic bio data

The website requires a child's and a caregiver's name in **Arabic**. That rule
is not a Django validator: it is `checkArabicOnly()` in
`static/js/validator.js`, bound on blur to the `arabic_fields` lists in
`mscc.js`, `alp.js`, `registrations.js`, `bridging.js` and `project.js`. It
accepts `U+0600`–`U+06FF` or a space — the whole Arabic block, so Arabic-Indic
digits and Arabic punctuation are in — and silently discards everything else.

The schema names those fields with `script: "arabic"`. There are two tiers and
a field is in one or the other, never both: Arabic-only implies letters-only,
so the export drops the weaker `only_letters_validator` pattern from a field it
marks Arabic, and the worker sees one complaint per character rather than two.

**The app blocks rather than strips.** The website deletes the offending
characters when the field loses focus, which empties the field completely if
the whole name was typed in Latin. On the web that is a re-typed field; on an
offline tablet it is lost data with no indication anything happened. So
`ArabicOnlyFormatter` stops the keystroke instead — the end state is identical
(only Arabic is ever stored) and nothing already on screen is rewritten
underneath the worker. Because a blocked keystroke is silent, every field with
the flag shows an "Arabic only" hint.

**The rule applies to what the worker types, not to what the server holds.**
Django accepts a Latin name, and the JavaScript only fires on a field the
worker focused, so an untouched record saves unchanged on the website. Twelve
of the twenty-eight name values in the captured fixture are Latin. Enforcing
the rule on them would be *stricter than the website* and would stop someone
correcting a birth date on a record whose name they never touched, so
`SchemaFormController` skips a script rule on a value that is unchanged from
the one the form opened with. Edit it and the rule applies from then on.

## Three deliberate refusals to reject

The app is offline-first, so "I cannot check this" must never read as "this is
wrong":

1. **An unknown choice list is accepted.** If a reference list has not been
   pulled yet, `AllowedValuesResolver` returns null and membership is not
   checked. The alternative is a form of errors that no amount of typing fixes.
2. **A pattern Dart cannot compile is ignored.** The server still enforces it.
3. **A rule the server never sent is not invented.** The one exception is
   attendance, below.

## Conditional requirements

A reveal rule may carry `require: true`, meaning the fields it shows are
*required while it holds*. This is how a close reason is required only on a day
off, and a reason for absence only for a child marked absent — the same two
conditions `engine._validate_attendance_common` checks. Without it those fields
would have to be `required: true` and then hidden, which would block every
sheet that is not a day off.

## Attendance

The sheet is not *rendered* by the schema engine — a roster of thirty children
is a table, not a column of fields — but it is *validated* by it.
`attendance_schema()` describes the header and one row, and
`validateAttendance()` runs the ordinary controller over the header and over
each row.

`attendanceSchemaOrFallback()` supplies the identical description when the
schema arrives empty. That is not defensive padding: a device pulls its schemas
from whatever server it is pointed at, and a server that predates `row_fields`
sends `fields: []`. Without the fallback, upgrading the app would *remove* the
three rules the child sheet used to check by hand. There is one set of rules,
not a schema path and a legacy path.

A child row and a teacher row are different tables and do not share field
names: a child row carries `attended` (`Yes`/`No`) and is required; a teacher
row carries `status` (`Present`/`Absent`) and is not, because
`create_teacher_attendance` applies no required check either.

## Messages

`validationMessages()` builds the whole set from `AppLocalizations`, so a form
cannot be wired up with a partial one — the three schema forms used to pass
four messages each and let the rest fall back to the English defaults compiled
into `ValidationMessages`, which is why an Arabic worker saw an English
"Invalid format.".

Where the server attaches its own message to a validator, that message wins: it
says what to do ("Only alphabetic characters are allowed.") where a generic
"Invalid format." leaves the worker guessing. Those messages are translated on
the server, so a string that has no Arabic translation there shows in English
here too — `only_letters_validator` is currently one of them.

## Where the tests are

| File | Covers |
|---|---|
| `student_registration/mobile_api/tests/test_schema_rules.py` (BMA-NFE) | what `field_spec` and `attendance_schema` promise |
| `test/schema_validation_test.dart` | every rule the controller enforces |
| `test/attendance_validation_test.dart` | the five attendance rules, both sheets |
| `test/arabic_only_test.dart` | the Arabic rule, the formatter and the untouched-value case |
| `test/registration_rules_test.dart` | the whole chain, through the real wizard |
