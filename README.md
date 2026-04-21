# The Backdoor — Task Management

A mobile-first PWA for daily task management at The Backdoor bar.

Built with Vite + React + TypeScript + Tailwind + Supabase.

---

## Quick start (local dev)

### 1. Create a Supabase project

1. Go to https://supabase.com, create a free project.
2. In the project dashboard → **Settings → API**, copy:
   - Project URL → `VITE_SUPABASE_URL`
   - `anon` public key → `VITE_SUPABASE_ANON_KEY`

### 2. Run the schema

Open **SQL Editor** in Supabase, paste the contents of [`supabase/schema.sql`](supabase/schema.sql), and click **Run**.

This creates the tables, row-level-security policies, a trigger that auto-creates a `staff` row for every new auth user, a helper function to materialize recurring daily tasks, and the public `task-photos` storage bucket.

*(Optional)* Run [`supabase/seed.sql`](supabase/seed.sql) for a starter set of recurring tasks.

### 3. Configure env vars

```bash
cp .env.example .env
# then edit .env and paste the two values from step 1
```

### 4. Install and run

```bash
npm install
npm run dev
```

Open http://localhost:5173.

### 5. Create the first admin

1. On the login screen, sign up the first account via Supabase **Authentication → Users → Add user** (enable "Auto Confirm Email").
2. The trigger auto-creates a `staff` row. Promote them to admin:
   ```sql
   update staff set role = 'admin' where email = 'you@example.com';
   ```
3. Log in through the app. The Admin tab will appear in the bottom nav.
4. Add the other staff the same way (or let them sign up themselves) and manage them from the Admin → Staff tab.

---

## Features

- **Auth** – email/password via Supabase, persistent session, protected routes, admin-only Admin page
- **Daily task board** – tasks grouped by category (Opening / Bar / Cleaning / Closing / Weekly / Other), color-coded status, bilingual (EN + JP) titles, priority indicators
- **Realtime sync** – `daily_tasks` updates push to every connected device via Supabase Realtime
- **Task completion flow** – tap a task → start → mark done, optional note, optional photo (camera or upload), timestamp captured
- **My Tasks** – filtered view of the logged-in user's tasks with "done/total" stats
- **Admin dashboard** – today's overview stats, per-staff completion rates, task CRUD, staff role/active management
- **PWA** – installable to home screen, icons, offline shell caching, service worker for cached API responses

---

## Project structure

```
src/
  components/
    admin/       StaffManager, TaskEditor
    auth/        ProtectedRoute
    layout/      AppShell (header + bottom nav)
    tasks/       TaskBoard, TaskCard, TaskCompletion
    ui/          Modal
  hooks/         useAuth, useDailyTasks, useStaff, useTaskTemplates
  lib/           supabase.ts, types.ts
  pages/         Login, Today, MyTasks, Admin
  utils/         date.ts
supabase/
  schema.sql     full schema + RLS + triggers + storage setup
  seed.sql       optional starter tasks
```

The structure cleanly separates page routes from reusable components, so the future features (clock-in, shift scheduling, push notifications, reports, inventory) listed in the project brief can be added without restructuring.

---

## Recurring task generation

`tasks` are *templates*. `daily_tasks` are the *instances* used each day.

The SQL function `generate_daily_tasks(target_date date)` materializes instances from any active recurring template whose recurrence rules include `target_date`. It's idempotent (unique constraint on `task_id, date`).

The client calls this via RPC whenever the Today view mounts or when an admin saves a task — so tasks appear instantly without any scheduled job. If you want a server-side daily cron, schedule this in Supabase's pg_cron:

```sql
select cron.schedule('generate-daily-tasks', '5 0 * * *', $$select generate_daily_tasks();$$);
```

---

## Deploy

### Vercel

1. Push to GitHub.
2. Import the repo at https://vercel.com/new.
3. Framework preset: **Vite**. Build command `npm run build`, output `dist`.
4. Add env vars **VITE_SUPABASE_URL** and **VITE_SUPABASE_ANON_KEY**.
5. Deploy.

### Netlify

Same idea: build command `npm run build`, publish directory `dist`, same two env vars. Add a `_redirects` file with `/* /index.html 200` if Netlify doesn't auto-handle SPA fallback (Vercel does).

---

## Scripts

| Command | What it does |
| --- | --- |
| `npm run dev` | Local dev server with HMR |
| `npm run build` | Type-check + production build to `dist/` |
| `npm run preview` | Serve the production build locally |
| `npm run lint` | Run the TypeScript project-references check |

---

## Future features (not built yet, but the architecture supports them)

- **Clock in / out** – add a `shifts` table, new `useShift` hook, "Clock in" button in header
- **Shift schedule / calendar** – new `pages/Schedule.tsx` reading from `shifts`, add nav item
- **Push notifications** – Supabase Edge Function to watch for overdue tasks, Web Push via the existing service worker
- **Task comments / thread** – new `task_comments` table, comment list inside `TaskCompletion`
- **Weekly/monthly reports export** – `pages/Reports.tsx` + `utils/csv.ts`
- **Inventory** – new tables + `pages/Inventory.tsx`, nav entry for admins

All existing realtime channels, RLS helpers (`is_admin()`, `current_staff()`) and UI primitives (`Modal`, `btn-*`) can be reused.
