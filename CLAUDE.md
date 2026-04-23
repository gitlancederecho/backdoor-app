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

**As of 2026-04-23, `supabase/schema.sql` mirrors the live DB and has been applied.** All previously drifted surfaces are reconciled:

- `tasks.start_time`, `tasks.end_time`
- `daily_tasks.start_time`, `.end_time`, `.started_by`, `.started_at`
- `task_events` table + RLS + Realtime + `CHECK` constraint matching `TaskEventType` in Models.swift
- `venue_settings` / `venue_schedule` + `updated_at` triggers + RLS + Realtime
- `generate_daily_tasks` skips closed days and copies `start_time`/`end_time` from the template (verified behaviorally — calling it for a Tue/Wed returns 0 on the live DB)

Adds use `alter table … add column if not exists` so the schema is safe to re-run against the existing project.

Seed data in `schema.sql` matches real operation: Mon/Thu/Fri/Sat/Sun open 17:00–00:00; Tue+Wed closed; `prep_buffer_minutes` default 510.

### What I could not verify through REST

The PostgREST surface doesn't expose function bodies, trigger definitions, or existing `CHECK` constraint SQL. For the live project I know *behaviorally* that:

- `generate_daily_tasks` currently does skip closed days (test: calling it for a closed Tuesday returned 0 with 0 rows inserted; calling for an open Thursday returned 2 with start/end times populated).
- `task_events` allows the iOS client to insert the 8 enum values listed in `TaskEventType` (at least `completed`, `undone`, `reassigned` confirmed in live data).

If you need the exact live SQL (e.g. before a destructive `create or replace`), ask the operator to paste from `\sf generate_daily_tasks` in the Supabase SQL editor.

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

## Don'ts

- Don't commit `.env`, `node_modules/`, `dist/`, `xcuserdata/`, or anything under `backdoor-ios/Backdoor/Backdoor.xcodeproj/xcuserdata/`.
- Don't create documentation files (`*.md`) unless the user asks — this file is an exception because the user explicitly asked for a memory note.
- Don't push destructive git operations without explicit confirmation.
