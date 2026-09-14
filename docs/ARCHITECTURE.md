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

## Adding a new form to the app

Nothing to do in the app: register the Django form in
`student_registration/mobile_api/registry.py` (entity key, model, form class,
parent, scope, permission) and it appears under *Add service* on the next
bootstrap, with validation and choices taken from the form.
