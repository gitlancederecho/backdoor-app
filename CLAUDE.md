# Backdoor — project context for Claude sessions

Task management for The Backdoor bar. Three clients share one Supabase backend.

## Clients
- **Web PWA** — `src/` (Vite + React + TS + Tailwind)
- **iOS native** — `backdoor-ios/` (SwiftUI, iOS 17+)
- **React Native** — `mobile/` (Expo SDK 55, expo-router, NativeWind)
- **Backend** — `supabase/schema.sql`, `supabase/seed.sql`

See `README.md` for developer setup, `APP_FLOW.md` for product discussion, `USER_MANUAL.md` for the operator's guide.

## Supabase access

Project: `qtjmwquanwovybvfvegr.supabase.co`

Credentials live in `.env` (gitignored):

| Var | Scope | Use |
| --- | --- | --- |
| `VITE_SUPABASE_URL` | public | Base URL |
| `VITE_SUPABASE_ANON_KEY` | public | Client reads/writes (RLS enforced) |
| `SUPABASE_SERVICE_ROLE_KEY` | **secret** | Admin SQL via PostgREST, bypasses RLS |
| `SUPABASE_MANAGEMENT_PAT` | **secret** | Arbitrary SQL + DDL via Management API |
| `SUPABASE_PROJECT_REF` | config | Project ref string (path segment in URLs) |

### Introspection recipes (read-only)

OpenAPI (full schema — tables, columns, constraints, RPCs):
```bash
source .env
curl -s -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
     -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
     "$VITE_SUPABASE_URL/rest/v1/" > /tmp/openapi.json
```

Read any table with RLS bypassed:
```bash
curl -s -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
     -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
     "$VITE_SUPABASE_URL/rest/v1/<table>?select=*"
```

### DDL + arbitrary SQL via Management API

Use this whenever a change can't go through PostgREST (schema migrations,
reading function bodies, inspecting triggers, RLS audits). Cloudflare
rejects Python's default User-Agent on `api.supabase.com` — `curl` works:

```bash
set -a; source .env; set +a

# Wrap the SQL in a JSON body (single-quotes + backslash escaping is a
# pain, so let Python handle it):
python3 -c "import json,sys; print(json.dumps({'query': sys.argv[1]}))" \
  "select pg_get_functiondef('generate_daily_tasks(date)'::regprocedure)" \
  > /tmp/q.json

curl -s -X POST \
  "https://api.supabase.com/v1/projects/$SUPABASE_PROJECT_REF/database/query" \
  -H "Authorization: Bearer $SUPABASE_MANAGEMENT_PAT" \
  -H "Content-Type: application/json" \
  --data @/tmp/q.json
```

For applying the full schema:
```bash
python3 -c "import json; sql=open('supabase/schema.sql').read(); print(json.dumps({'query': sql}))" > /tmp/schema_payload.json
curl -s -X POST "https://api.supabase.com/v1/projects/$SUPABASE_PROJECT_REF/database/query" \
  -H "Authorization: Bearer $SUPABASE_MANAGEMENT_PAT" \
  -H "Content-Type: application/json" \
  --data @/tmp/schema_payload.json
```

The anon key can't hit `/rest/v1/` root (requires secret key) and RLS
blocks anon reads from `task_events` and most other tables. For any
administrative task, pick the service role key (REST-level) or the
management PAT (SQL-level).

## Schema status

**As of 2026-04-24, `supabase/schema.sql` mirrors the live DB and has been applied.** All previously drifted surfaces are reconciled:

- `tasks.start_time`, `tasks.end_time`; category is free-form `text` (no CHECK constraint).
- `daily_tasks.start_time`, `.end_time`, `.started_by`, `.started_at`
- `task_events` table + RLS + Realtime + `CHECK` constraint matching `TaskEventType` in Models.swift. `daily_task_id` is nullable for template-level events (deleted, restored).
- `venue_settings` / `venue_schedule` + `updated_at` triggers + RLS + Realtime
- `venue_schedule_override` (per-date exceptions: holidays, special hours) + `effective_venue_hours(date)` resolver that merges the override with the weekly default. `generate_daily_tasks` consults this instead of `venue_schedule` directly, so a date override flips task generation on/off for that specific date. `reason` is a free-form label for the admin UI + (future) venue status pill.
- `categories` table (key pk, label_en, label_ja, sort_order, is_builtin) + RLS + Realtime — admin-editable via Admin → Categories.
- `task_folders` table + `tasks.folder_id` FK — admin organizational bucket (separate from `category`). Soft-delete a folder → cascade nulls `folder_id` on member tasks so they fall back to Unfiled. RLS/Realtime same shape as categories.
- `tasks.recurrence_ends_on` (nullable DATE). `generate_daily_tasks` skips a template once `target_date > recurrence_ends_on`. nil = runs forever (legacy behavior).
- `task_comments` table (daily_task_id, author_id, body, created_at, edited_at) + RLS + Realtime + body-diff edited_at trigger.
- `profile_stats(target uuid default null)` RPC returning jsonb — powers Profile + peer StaffProfileView.
- `generate_daily_tasks` skips closed days and copies `start_time`/`end_time` from the template (verified behaviorally).

Adds use `alter table … add column if not exists` / guarded DO blocks so the schema is safe to re-run against the existing project.

Seed data in `schema.sql` matches real operation: Mon/Thu/Fri/Sat/Sun open 17:00–00:00; Tue+Wed closed; `prep_buffer_minutes` default 510. Categories seeded with the six built-ins (opening, bar, cleaning, closing, weekly, other).

### What I could not verify through REST

The PostgREST surface doesn't expose function bodies, trigger definitions, or existing `CHECK` constraint SQL. If you need the exact live SQL, ask the operator to paste from `\sf generate_daily_tasks` (or the equivalent) in the Supabase SQL editor, or hit the Management API's `database/query` endpoint with `pg_get_functiondef(…)`.

## Hours admin state (in progress)

The iOS Hours tab (`backdoor-ios/.../HoursAdminView.swift`) reads `venue_settings` and `venue_schedule` and uses `BusinessDay.swift` for business-day math. Current live state:

- `venue_settings`: `prep_buffer_minutes=510, grace_period_minutes=120, timezone=Asia/Tokyo`
- `venue_schedule`: Mon/Thu/Fri/Sat/Sun open 17:00–00:00; Tue/Wed closed

Known client-side gaps:
- **Fixed** (2026-04-23): iOS Hours admin has a timezone picker (sheet with searchable IANA list).
- **Fixed** (2026-04-23): `BusinessDay.currentBusinessDayISO` Case 1b compares `nowClock + 1440` against `closeMins + grace` in yesterday-midnight reference frame, closing the early-close false-positive window.
- Web and RN clients have no Hours feature and no business-day math — "today" diverges across platforms for late-night shifts. Not yet addressed.

## One-off task lifecycle policy

Non-recurring (`is_recurring = false`) templates are auto-soft-deleted
when their last non-completed `daily_task` flips to `completed`. The
iOS client (`TaskViewModel.complete` → `maybeAutoRetireOneOff`):

- Sets `tasks.is_active = false`
- Logs a template-level `task_events` row with `daily_task_id = null`,
  `event_type = 'deleted'`, `from_value = templateId`, `note = title`

Symmetric: `TaskViewModel.undo` on a completion calls
`maybeRestoreRetiredOneOff`, which re-fetches the template's current
`is_active` (the in-memory snapshot may be stale), flips it back to
`true` if currently inactive, and logs an `undone` event.

Recurring templates are never touched by this logic.

`AdminViewModel.fetchAll` now relies on the DB-level `is_active = true`
filter alone — the former `hideCompletedOneOffs` client-side pass is
gone.

## Git

- Remote: `git@github.com:gitlancederecho/backdoor-app.git` (SSH; HTTPS credentials not configured).
- Main branch: `main`.
- Commit message style: short present-tense subject, longer body explaining the *why*. See recent commits for examples.

## iOS app surfaces (as of 2026-04-24)

Bottom tabs (varies by role):
- **Today** — task board for a business day. Rich header: prev/next date chevrons, tappable date → graphical DatePicker, venue status pill (Open / Prep / Closed / Between shifts), Everyone/Mine pills, "Today" shortcut when off-day. Swipe left/right shifts the date. People-search magnifying glass at top-right opens `PeopleSheet`.
- **Admin** (admin only) — three non-scrolling sub-tabs: Overview · Tasks · Categories. Three icon buttons at the top-right of the header open **Staff** (`person.2.fill`), **Hours** (`clock.fill`), and **History** (`clock.arrow.circlepath`) as sheets — each wrapped in a `NavigationStack` with a `Close` toolbar button (cancellationAction). Admin → Tasks is hierarchical: Unfiled tasks at the top of the root list, Folders section below; tapping a folder slides in `FolderTasksView`. Floating `+` is a menu with "New task" / "New folder". Bulk edit everywhere in Admin has **Select All** and, for Tasks, **Move to folder**. A `⋯` menu on the Tasks filter bar opens **Deleted tasks** (soft-deleted templates, single- or bulk-restore). Task editor shows **Created by [name] · [time]** footer for existing rows, and a **recurrence end date** toggle for seasonal recurring tasks.
- **Profile** — identity card, role-specific insight (admin: active staff count / templates created / reassignments; staff: next pending task today), 2×2 stats grid, recent activity, language picker, sign out.

Key reusables in `backdoor-ios/Backdoor/Backdoor/Views/Components/`:
- `AvatarView`, `StatusDot`, `SearchField`, `Styles.swift` (colors + cardStyle/inputStyle/PrimaryButtonStyle/SecondaryButtonStyle).
- `SearchablePickerSheet<RowID>` — generic sheet with a search field + row list. `PickerRow<RowID>` carries label, optional sublabel, optional avatar, and `isSpecial` (for pseudo-rows like "All" / "Anyone" that bypass filtering). Used wherever we had long Menu dropdowns (reassign, assignee/category filters, actor filter, assign-to in task editor).

Admin edit-mode pattern is in place on Tasks, Categories, Staff — `List(selection:)` with per-row `.buttonStyle(.borderless)`, top-right Edit/Done toggle, bottom bulk-action bar. Categories also support drag-to-reorder via `.onMove` persisted to `sort_order`.

## Row-action policy (uniform across the app)

Every list/card row that has per-item actions uses the shared
`RowMenu` component (`Views/Components/RowMenu.swift`) — a
single-button `⋯` menu seeded with `RowAction` values. Presets
cover `edit`, `share`, `reassign`, `move`. Custom actions go
through the free-form initializer.

Delete semantics are codified via `RowDelete` + `RowDeleteBehavior`:

| Case | Confirmation | Undo |
| --- | --- | --- |
| Single-row soft-delete (`is_active = false`) | none | `UndoToast` (5 s) |
| Single-row hard-delete | `.alert` | no |
| Bulk delete (any) | `.alert` | no — use "Show deleted" to restore |

The `UndoToast` component (`Views/Components/UndoToast.swift`) is
the single shared look; host views manage an `UndoSpec` + a
cancellable dismiss `Task`. See `TasksAdminView` and
`FolderTasksView` for the canonical wiring — both implement the
exact same `handleDelete(_:)` / `handleUndo(_:)` / `UndoToast`
presentation so behavior is uniform whether you're at the Unfiled
root or drilled into a folder.

New row surfaces should compose `RowMenu` rather than rolling an
inline row-menu; new delete paths should pick a `RowDeleteBehavior`
and wire the existing toast/alert plumbing rather than inventing
their own.

## View-model mutation policy (no post-write `fetchAll`)

Every mutator on `AdminViewModel` / `VenueViewModel` / `TaskViewModel`
follows this contract:

1. **Apply the local mutation up front** — remove from / append to /
   patch the in-memory array so the UI updates the instant the user
   acts.
2. **Fire the DB write.**
3. **On failure (caught), revert the local change.** Cache the prior
   value before mutating so revert is mechanical.
4. **Realtime brings authoritative state** within ~200ms via the
   subscriptions wired in `start*Realtime` (commit 6728475).

**Do NOT `await fetchAll()` (or `fetchFolders` / `fetchOverrides`)
after a DB write.** That was the old pattern; it adds 200-500ms of
perceptible lag for zero correctness benefit since realtime already
delivers the change. The fix landed across every delete / undo /
move path in commit 6238d69 — match that style for any new mutator.

Anti-pattern (laggy):
```swift
func deleteThing(_ row: Thing) async throws {
    try await supabase.from("things").delete().eq("id", value: row.id).execute()
    await fetchAll()   // ← 200-500ms before UI updates
}
```

Correct (snappy + correct):
```swift
func deleteThing(_ row: Thing) async throws {
    let prior = things.firstIndex { $0.id == row.id }
    if let pi = prior { things.remove(at: pi) }   // optimistic

    do {
        try await supabase.from("things").delete().eq("id", value: row.id).execute()
    } catch {
        if let pi = prior { things.insert(row, at: min(pi, things.count)) }
        throw error
    }
}
```

For undo/restore flows, the local mutation is the inverse (re-insert
+ resort) and the same revert-on-failure rule applies. See
`AdminViewModel.undoDeleteTask` for the canonical example.

If you ever need a manual refresh path (e.g., pull-to-refresh in a
view that's outside the realtime subscription scope), keep `fetchAll`
public and call it explicitly — but never as a defensive trailing
call inside a mutator.

## Gotchas hit this session

- **Dict-literal duplicate keys trap at runtime.** `Localization.swift` uses `[String: String]` literals; duplicate keys crash with `Fatal error: Dictionary literal contains duplicate keys.` the first time `tr(...)` runs — often "app won't load" in practice. Before adding new keys, grep both `enStrings` and `jaStrings` for the proposed key. A full scan (it's a 500+ line file): `python3 -c "import re; b=open('backdoor-ios/.../Localization.swift').read(); …"` — pattern is in the commit `5cbc27b`.
- **`List` row with multiple Buttons collapses into one tap target.** Default Button style in a List row makes every button inside fire the row's action (or nothing). Fix: `.buttonStyle(.borderless)` on each inner Button. See commit `7a085d3` — was the "assigning tasks to users won't respond" bug.
- **Optional UUID in PostgREST `update` doesn't clear the column.** Swift's default `JSONEncoder` *omits* nil Optionals — Postgres reads that as "no change." To actually unassign (set null), use a custom Encodable that calls `container.encode(_:forKey:)` (not `encodeIfPresent`). See `TaskViewModel.reassign` in commit `f4d4930`.
- **Cloudflare blocks Python's default User-Agent on `api.supabase.com`.** Management API calls must go through `curl`, not `urllib.request`, unless you set a custom UA. Recipe above.
- **Supabase Swift + SwiftUI `.refreshable` cancellation.** SwiftUI cancels the `.refreshable` Task when the view re-renders mid-fetch (Observable mutations trigger re-render). `CancellationError` then lands in the catch-all and clobbers state. Treat it as benign — return silently and keep existing data.
- **Supabase Swift caches channels by topic; re-subscribe throws.** `supabase.channel("some_topic")` returns the *same* `RealtimeChannelV2` instance if a prior `subscribe()` hasn't been released — even if the Swift `Task` iterating it was cancelled. Adding `.postgresChange(...)` to an already-subscribed channel throws `Cannot add "postgres_changes" callbacks for "realtime:<topic>" after subscribe()`. Reproduces when a view-model is re-subscribed for the same inputs, e.g. `TaskViewModel.setDate(d)` to the same date twice, or re-opening `TaskCompletionSheet` on the same task. Fix: hold the `RealtimeChannelV2` reference alongside the `Task` and on teardown call `await supabase.removeChannel(channel)` so the next `supabase.channel(topic)` returns a fresh instance. See commit `587db72`.

## Don'ts

- Don't commit `.env`, `node_modules/`, `dist/`, `xcuserdata/`, or anything under `backdoor-ios/Backdoor/Backdoor.xcodeproj/xcuserdata/`.
- Don't create documentation files (`*.md`) unless the user asks — this file is an exception because the user explicitly asked for a memory note.
- Don't push destructive git operations without explicit confirmation.
- Don't add a new Localization key without grepping both `enStrings` and `jaStrings` first (see Gotchas).
- Don't put multiple Buttons in a `List` row without `.buttonStyle(.borderless)` (see Gotchas).
