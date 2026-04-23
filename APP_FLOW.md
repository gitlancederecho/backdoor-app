# The Backdoor — App Flow & Product Notes

A discussion document for how the app works today, what it's good at, and what it's missing. Flag anything here you want to redesign.

---

## 1. User Roles — Who Uses This App

### Staff (bartenders, servers, kitchen)
- Works a shift (~4–10 hours)
- Needs to see what's on their plate **right now**
- One-handed phone use during service
- Doesn't want to read long screens — tap, tap, done

### Admin (owner, manager, head bartender)
- Sets up task templates during downtime
- Monitors completion during service
- Reviews performance after service
- Uses both phone and computer

### Implicit third role: **System** (automated)
- Generates today's daily tasks from templates each morning
- Cleans up old photos (not implemented yet)
- Reminds staff of overdue tasks (not implemented yet)

---

## 2. Core User Flows (What Works Today)

### Flow A — Staff signs up for the first time

```
1. Staff taps "Sign up" on login screen (not yet wired in iOS app)
2. Enters email + password
3. Supabase creates auth user
4. Postgres trigger auto-creates staff row with:
   - name = email prefix
   - role = staff (default)
   - is_active = true
5. Staff lands in the app on the Today tab
6. Admin sees them in Staff management later, can promote/rename/deactivate
```

**⚠️ Discussion points:**
- **Is self-signup right?** Anyone with the URL could register. For a 7-person bar team, that's wrong — it should be invite-only. Options:
  - (a) Admin pre-creates auth users, sends invite emails from Supabase dashboard
  - (b) Self-signup but require admin approval (new field `is_approved`) before Active
  - (c) A signup code (magic word) that only staff know
- Current system is **open signup**, which is fine for a dev environment but not production.

### Flow B — Staff opens app to start shift

```
1. Launch app → session restored from Keychain (no re-login)
2. ContentView checks isSignedIn → shows MainTabView
3. TaskViewModel.loadToday() runs:
   a. Calls generate_daily_tasks() RPC → materializes today's instances
   b. Fetches all daily_tasks for today
   c. Opens Realtime channel on daily_tasks table
4. Today tab shows all tasks, grouped by category
5. Staff taps "Mine" → same data, filtered to their assignee + unassigned
```

**Timing:** ~1–2 seconds from app launch to seeing tasks (warm session).

### Flow C — Staff completes a task

```
1. Tap task card → bottom sheet appears
2. Tap "Start" (optional) → status becomes in_progress, broadcasted
3. Do the work
4. Tap "Complete" → photo picker (optional) + note field
5. Tap "Done"
   → local state optimistically updates (instant)
   → photo uploaded to Storage (if any)
   → daily_tasks row updated via PATCH
   → Realtime broadcasts to all other clients
6. Other staff + admin see the completion ~200ms later
```

**⚠️ Discussion points:**
- **Should "Start" be required?** Right now it's optional. If it's required, you get an audit trail of "who was working on what, for how long." If optional, staff will skip it and jump straight to Complete. Pros and cons on each.
- **What if two staff start the same task?** Right now either can complete it. No locking. Is that OK for a small team? Probably yes.

### Flow D — Admin creates a recurring task

```
1. Admin tab → Tasks → + button
2. Task Editor sheet slides up
3. Fill English + Japanese titles
4. Pick category, priority
5. Assign to specific staff OR "Anyone"
6. Toggle Recurring on
7. Pick daily / weekly / monthly
   - If weekly: pick days of week (Mon/Wed/Fri etc.)
8. Tap Create
   → INSERT into tasks table
   → Tomorrow morning, generate_daily_tasks() creates daily instances
```

**⚠️ Discussion points:**
- **What if admin wants it to start TODAY?** Currently must wait until tomorrow's generation. Should there be a "Generate now" button?
- **Time-of-day?** Right now tasks are just "today" — not "do this at 5pm" or "during prep hour". Should tasks have a target time window?

### Flow E — Admin promotes a staff member to admin

```
1. Admin tab → Staff
2. Find the person in the list
3. Tap their role pill (shows "staff" in gray)
4. Pill flips to "admin" in gold
5. UPDATE staff SET role = 'admin' WHERE id = ...
6. That user, on next app launch (or refresh), sees Admin tab
```

Simple. Works.

---

## 3. What the App Can Do (Today)

### ✅ Working features
| Feature | Status | Notes |
|---|---|---|
| Email/password auth | ✅ | via Supabase Auth |
| Persistent sessions | ✅ | Keychain storage |
| Multi-platform sync | ✅ | iOS + web share the same DB |
| Realtime updates | ✅ | websocket-based |
| Daily task generation | ✅ | RPC runs on load |
| Recurring tasks | ✅ | daily, weekly, monthly |
| Task assignment | ✅ | specific user or open |
| Photo upload | ✅ | stored in Supabase Storage |
| Completion notes | ✅ | free text |
| Priority levels | ✅ | low/normal/high |
| Bilingual EN/JP | ✅ | shown side by side |
| Role-based access (RLS) | ✅ | enforced at DB level |
| Soft delete | ✅ | no data loss from mistakes |
| Admin dashboard | ✅ | overview + per-staff progress |
| Staff management | ✅ | promote, deactivate, rename |

---

## 4. What the App Should Do (Missing / Future)

### 🔴 Critical gaps

**1. Time-based task visibility**
Currently all today's tasks appear at once. A bartender shouldn't see "closing tasks" during happy hour. Should tasks have:
- A **suggested start time** (e.g. 5pm for opening, 11pm for closing)?
- Filter tabs: "Now", "Coming up", "Later"?
- Or just a chronological ordering instead of category grouping?

**2. Push notifications**
No alerts right now. Needed for:
- Task assigned to you
- Task is overdue (e.g. still pending 1 hour after expected time)
- Admin messages ("extra prep tonight for private event")

iOS supports via APNs + Supabase Edge Functions. Requires Apple Developer account for device push (simulator doesn't do real push).

**3. Invite-only signup**
See Flow A discussion. Open signup is a security hole in production.

**4. Archive / history view**
Staff can't see what they did yesterday. Admin can't see last week's completion rates. The data is in the database but there's no UI for it. Needs:
- "My History" screen (staff — last 7/30 days)
- "Reports" screen (admin — weekly rollup, per-staff stats)

### 🟡 Nice-to-have gaps

**5. Shift check-in / check-out**
No concept of "I'm on shift now." Could power:
- Auto-assigning unassigned tasks to whoever's checked in
- Payroll / hours tracking
- Knowing who's available for emergency tasks

**6. Task templates library**
Right now each task template is one-off. Could add:
- Duplicate a task (clone + edit)
- Task bundles ("Opening Routine" = 8 tasks at once)
- Import/export templates as JSON

**7. Comments / communication**
No way to say "hey, fridge is broken" inside the app. Options:
- A separate "Messages" tab with channels per category
- Comments attached to specific tasks
- Integration with an existing tool (Slack/Line/Discord webhook)

**8. Offline-first with conflict resolution**
Today the app handles short network drops OK, but doesn't queue multiple offline completions. If two people complete offline and sync later, what wins? Currently "last write wins" — fine for now.

**9. Photo retention / storage costs**
Photos accumulate forever. Supabase Storage is ~$0.021/GB/month. At 50 photos/day × 500KB each × 365 days = ~9GB/year = $2.30/year. Negligible for a small bar, but worth a retention policy (delete after 30/90 days).

**10. Analytics / insights**
- Which tasks take longest?
- Which staff have the best completion rate?
- Which days are understaffed?
Data's there, just needs charts.

### 🟢 Quality-of-life

**11. Dark/light mode toggle**
Forced dark right now. Most bar/restaurant apps are dark, but some staff may want light mode for outdoor/bright scenarios.

**12. Customizable categories**
Hardcoded to Opening/Closing/Cleaning/Stock/Prep/Other. Each bar is different. Should be editable.

**13. Tablet UX**
iPad runs the iPhone app right now (scaled). A real iPad layout (sidebar + detail) would be nice for a back-office tablet at the bar.

**14. Drag-and-drop reordering**
Can't reorder tasks within a category. SwiftUI supports it, would take ~30 minutes to add.

**15. Search**
As the task library grows past ~30 templates, admin will want a search bar.

---

## 5. Fundamental Questions to Discuss

### Q1: Is this a task app or a shift app?

Right now it's purely task-focused — "here are the things to do today." But bar operations are inherently **shift-based** — people clock in and out, and tasks happen during specific shifts.

**Option A: Keep it task-focused.** Simpler. Tasks stand alone, assigned to individuals.

**Option B: Pivot to shift-focused.** Every task belongs to a shift. Shifts have start/end times, staff rosters, and associated task lists.

Option B is more realistic to how bars actually work but doubles the complexity. **Recommend sticking with A for MVP, revisit later.**

### Q2: Who "owns" an unassigned task?

Right now, "Anyone" tasks are first-come-first-serve — whoever taps Complete first owns it. This works for small teams (7 people) where social pressure handles it. At 20+ people it would break.

**Alternative:** explicit claiming. Staff has to tap "I'll do this" first, then complete. Adds a step but prevents confusion.

For your team size: **claiming is overkill, keep first-come-first-serve.**

### Q3: What's the relationship between template and instance?

When admin edits a task template, should:
- (a) All future daily instances reflect the change, existing today's don't
- (b) All instances (including today's) reflect the change
- (c) Nothing auto-updates; edits apply only to *new* templates

**Current behavior:** (a) — which is mostly what people expect, but can surprise staff ("the task changed mid-shift!"). Worth documenting clearly.

### Q4: How long should daily tasks persist?

Right now `daily_tasks` rows are never deleted. Good for history, bad for long-term storage cost and query speed.

**Recommend:** Keep 90 days of daily_tasks, then archive to a compressed table or delete. Nightly cron job.

### Q5: Should there be a "night shift" vs "day shift" distinction?

Bars often have two distinct shifts with different task sets. The current model treats every day as one unit. Do you need:
- Morning crew tasks (prep, inventory)
- Evening crew tasks (service, closing)

Could model this as **category + time window**, OR as **two separate "days"** (day shift date = April 22 morning, night shift date = April 22 evening).

---

## 6. Design Principles (Proposed)

These aren't locked in — discuss and push back.

1. **One-thumb-operable on iPhone.** Every action during service should work with the phone in one hand. No tiny tap targets, no long forms.

2. **Realtime by default.** The app should feel like one shared surface, not individual copies. If two staff are both looking at Today, they see the exact same state instantly.

3. **Optimistic UI.** Taps should feel instant. Network failures roll back gracefully but shouldn't block interaction.

4. **Admin-light.** Staff rarely interact with admin features. Admin tab only appears for admins; staff UI is completely unaware of it.

5. **Bilingual always.** Never choose one language over the other — show both.

6. **Forgiving.** Any action can be undone. Delete is soft-delete. Complete can be reverted.

7. **Photos over words.** For completion proof, a photo is faster and clearer than a typed note. Make photos 1 tap, not 3.

---

## 7. What to Decide Next (Priority Order)

1. **Signup model** — invite-only or open? → affects Part 1 of user manual
2. **Time-of-day on tasks** — worth adding? → affects task card UI
3. **Push notifications** — yes/no? → needs Apple Developer account planning
4. **History view** — design it? → needs new screens
5. **Categories — hardcoded or editable?** → small code change
6. **Photo retention policy** → Supabase Edge Function

Let's pick one and flesh it out in detail.

---

## 8. What's Not in Scope (and shouldn't be)

To keep this focused, explicitly NOT building:

- Payroll integration
- Customer-facing reservations
- POS / payments
- Inventory management (beyond "task: restock limes")
- Employee scheduling (who works when)
- HR features

If any of these come up, they deserve their own app or a third-party tool.

---

Tell me which sections jump out — we can go deep on any of them.
