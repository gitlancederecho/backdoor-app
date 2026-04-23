# The Backdoor — Task Management

A mobile-first task management system for The Backdoor bar, with three clients over one shared Supabase backend.

| Client | Stack | Path |
| --- | --- | --- |
| **Web PWA** | Vite + React + TypeScript + Tailwind | [`src/`](src/) |
| **iOS native** | SwiftUI (iOS 17+) | [`backdoor-ios/`](backdoor-ios/) |
| **React Native** | Expo SDK 55 + expo-router + NativeWind | [`mobile/`](mobile/) |
| **Backend** | Supabase (Postgres, Auth, Realtime, Storage) | [`supabase/`](supabase/) |

All three clients read and write the same tables and subscribe to the same Realtime channels, so a completion on the iPhone app shows up on the web in ~200ms and vice versa.

For the full product discussion (user flows, gaps, open questions) see [`APP_FLOW.md`](APP_FLOW.md). For the operator's guide see [`USER_MANUAL.md`](USER_MANUAL.md).

---

## 1. Backend setup (do this first)

All three clients need a Supabase project. Set it up once:

### 1.1 Create the project

1. Go to https://supabase.com, create a free project.
2. In **Settings → API**, copy:
   - Project URL → used as `VITE_SUPABASE_URL` / `EXPO_PUBLIC_SUPABASE_URL` / iOS `Supabase.swift`
   - `anon` public key → used as `VITE_SUPABASE_ANON_KEY` / `EXPO_PUBLIC_SUPABASE_ANON_KEY` / iOS `Supabase.swift`

### 1.2 Run the schema

Open **SQL Editor** in Supabase, paste [`supabase/schema.sql`](supabase/schema.sql), and click **Run**. This creates:

- `staff`, `tasks`, `daily_tasks` tables
- Row-level-security policies (staff see their own data, admins see everything)
- A trigger that auto-creates a `staff` row for every new auth user
- `generate_daily_tasks(target_date date)` — idempotent RPC that materializes today's instances from recurring templates
- The public `task-photos` storage bucket
- Helpers: `is_admin()`, `current_staff()`

*(Optional)* Run [`supabase/seed.sql`](supabase/seed.sql) for a starter set of recurring tasks.

### 1.3 Create the first admin

1. **Authentication → Users → Add user** (enable "Auto Confirm Email").
2. The trigger auto-creates a `staff` row. Promote:
   ```sql
   update staff set role = 'admin' where email = 'you@example.com';
   ```
3. Sign in on any client — the Admin tab now appears.

---

## 2. Web PWA (`src/`)

### Run locally

```bash
cp .env.example .env
# paste VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY
npm install
npm run dev
```

Open http://localhost:5173.

### Deploy

**Vercel:** Import the repo, framework preset **Vite**, build `npm run build`, output `dist`. Add the two `VITE_*` env vars.

**Netlify:** Same, plus a `_redirects` file with `/* /index.html 200` for SPA fallback.

### Scripts

| Command | What it does |
| --- | --- |
| `npm run dev` | Dev server with HMR |
| `npm run build` | Type-check + production build to `dist/` |
| `npm run preview` | Serve the production build locally |
| `npm run lint` | TypeScript project-references check |

---

## 3. iOS app (`backdoor-ios/`)

Native SwiftUI, iOS 17+. Uses the Supabase Swift SDK via Swift Package Manager (resolved in `Package.resolved`).

### Run locally

1. Open `backdoor-ios/Backdoor/Backdoor.xcodeproj` in Xcode 15+.
2. Edit `Backdoor/Config/Supabase.swift` and paste the project URL + anon key.
3. Select an iPhone simulator (or a device with a signing team) and **Run**.

Sessions persist in Keychain via the SDK's default storage, so re-launch drops you back into the app without re-login.

### Structure

```
backdoor-ios/Backdoor/Backdoor/
  Config/        Supabase client, Localization helpers
  Models/        BusinessDay, Venue, shared model types
  ViewModels/    Auth, Task, Admin, Venue (@Observable)
  Views/
    Admin/       Overview, Staff, Tasks, Hours, editor sheet
    Auth/        Login, profile edit
    Tasks/       Board, card, completion sheet
    Components/  Avatar, shared styles
```

---

## 4. React Native app (`mobile/`)

Expo SDK 55 with expo-router, NativeWind (Tailwind on RN), and the Supabase JS SDK with AsyncStorage persistence.

### Run locally

```bash
cd mobile
cp .env.example .env        # if not present, create with the two EXPO_PUBLIC_* vars
npm install
npm start                   # then press i / a, or scan QR with Expo Go / dev client
```

Env vars used by `lib/supabase.ts`:

- `EXPO_PUBLIC_SUPABASE_URL`
- `EXPO_PUBLIC_SUPABASE_ANON_KEY`

### Build with EAS

```bash
npm run build:ios:dev       # development client for simulator/device
npm run build:preview       # internal preview build for both platforms
npm run build:prod          # production build
npm run submit:ios          # submit latest build to App Store Connect
npm run submit:android      # submit latest build to Play Console
```

### Structure

```
mobile/
  app/                expo-router routes
    _layout.tsx       root auth gate
    login.tsx
    (tabs)/           Today, Mine, Admin
  components/
    admin/            TaskEditor
    tasks/            TaskBoard, TaskCard, TaskCompletion
    ui/               BottomSheet
  hooks/              useAuth, useDailyTasks, useStaff, useTaskTemplates
  lib/                supabase.ts, types.ts
  utils/              date.ts
```

---

## 5. Features (shared across clients)

- **Auth** — email/password via Supabase, persistent session, protected routes, admin-only Admin screen
- **Daily task board** — grouped by category (Opening / Bar / Cleaning / Closing / Weekly / Other), color-coded status, bilingual EN+JP titles, priority indicators
- **Realtime sync** — `daily_tasks` changes push to every connected device via Supabase Realtime
- **Completion flow** — start → complete, optional note, optional photo, timestamp captured
- **My Tasks** — filtered to the logged-in user with done/total stats
- **Admin dashboard** — today's overview, per-staff completion rates, task CRUD, staff role/active management
- **PWA specifics (web)** — installable, offline shell, service worker caching

---

## 6. Recurring task generation

`tasks` are *templates*. `daily_tasks` are the *instances* used each day.

`generate_daily_tasks(target_date date)` materializes instances from any active recurring template whose rules include `target_date`. It's idempotent (unique on `task_id, date`).

Each client calls it via RPC on Today-view mount and after an admin saves a task — so tasks appear instantly without a scheduled job. For a server-side daily cron:

```sql
select cron.schedule('generate-daily-tasks', '5 0 * * *', $$select generate_daily_tasks();$$);
```

---

## 7. Repo layout

```
.
├── src/                  Web PWA (Vite + React)
├── backdoor-ios/         Native iOS app (SwiftUI)
├── mobile/               React Native app (Expo)
├── supabase/             schema.sql, seed.sql
├── APP_FLOW.md           product discussion + open questions
├── USER_MANUAL.md        operator's guide
└── README.md
```

---

## 8. Future features (architecture supports them)

- **Clock in / out** — `shifts` table, `useShift` hook, header button
- **Shift schedule / calendar** — new Schedule screen reading from `shifts`
- **Push notifications** — Supabase Edge Function for overdue tasks; Web Push on PWA, APNs on iOS, Expo Notifications on RN
- **Task comments** — `task_comments` table, thread inside the completion sheet
- **Reports export** — Reports screen + CSV util
- **Inventory** — new tables + admin-only screen

All existing realtime channels, RLS helpers, and UI primitives can be reused.
