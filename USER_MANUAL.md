# The Backdoor — User Manual

Task management for bar staff. Available on **iPhone** and **Web**.

---

## Part 1: For Staff (Bartenders & Servers)

### 1.1 Signing In

1. Open **The Backdoor** app on your iPhone (or go to the web URL on a computer).
2. Enter your **email** and **password**.
3. Tap **Sign in**.

> **First time?** Ask your manager to create your account. You'll get an email invite with a link to set your password.

You'll stay signed in between sessions — no need to log in every shift.

---

### 1.2 The Three Tabs

At the bottom of the screen you'll see three tabs:

| Tab | What it shows |
|---|---|
| **Today** | Every task assigned for today, from every staff member |
| **Mine** | Only tasks assigned to you (or unassigned tasks anyone can do) |
| **Admin** | Only visible to managers — covered in Part 2 |

---

### 1.3 Reading a Task Card

Each task card shows:

```
● Wipe bar top           [👤 Yuki] · 10:32
  バーカウンターを拭く
  Cleaning · high priority
```

- **Dot color** = status
  - 🟡 Yellow = pending
  - 🔵 Blue = in progress
  - 🟢 Green = completed
- **English + Japanese titles** side by side
- **Avatar** = who it's assigned to (no avatar = anyone can do it)
- **Time** = when it was completed (only shown after done)
- **Category & priority** in small gray text

Tasks are **grouped by category** (Opening, Closing, Cleaning, Stock, etc.) and you can scroll through sections.

---

### 1.4 Completing a Task — The Full Flow

**Step 1 — Tap the task card.**
A sheet slides up from the bottom.

**Step 2 — Tap "Start".**
This marks the task as *in progress* so other staff know you're on it. The dot turns blue, and your avatar appears on the card.

> Tip: You can skip "Start" and go straight to "Complete" for quick tasks.

**Step 3 — Do the actual work.** (Wipe the bar, stock the fridge, etc.)

**Step 4 — Come back to the task and tap "Complete".**

**Step 5 (optional) — Add a photo.**
Tap the camera icon.
- **"Take Photo"** → opens the camera
- **"Choose Photo"** → opens your photo library

Photos prove the task was done — useful for cleaning checks or manager review later.

**Step 6 (optional) — Add a note.**
Type any details (e.g. "Ran out of lime garnish, reordered", "Broken glass near table 4 swept up").

**Step 7 — Tap "Done".**
The task is marked complete. Dot turns green. Completion time is recorded.

---

### 1.5 Undoing a Completion

Made a mistake? Tap the completed task card → tap **"Undo"**. It goes back to *in progress*. You can then re-complete it.

---

### 1.6 What "Mine" Means

The **Mine** tab filters down to:
- Tasks specifically assigned to you (admin picked you as the owner), PLUS
- Tasks with no assignee (open for anyone — you can take these)

If a task is assigned to someone else, **it won't show up in your Mine tab**, but you can still see and complete it from the Today tab if you end up doing it.

---

### 1.7 Realtime Updates

You don't need to refresh. When a coworker completes a task, you'll see it update on your screen within a second. Same when admin creates new tasks or edits existing ones.

**Pull down to refresh** manually if you ever feel things are out of sync.

---

### 1.8 Offline Behavior

If you lose Wi-Fi or signal:
- The app keeps working with whatever data was last loaded
- Completing a task will queue the change locally
- When you reconnect, it syncs automatically

Photos uploaded while offline wait until you're back online.

---

### 1.9 Signing Out

Profile icon → **Sign out**. You'll be returned to the login screen.

---

## Part 2: For Admins (Managers)

Admins see everything staff see, **plus** a third tab: **Admin**. Within Admin there are three sub-views.

---

### 2.1 Overview — Your Daily Dashboard

Shows three stats at the top:

- **Total** — how many tasks exist for today
- **Done** — completed count + percentage (green)
- **Open** — remaining count (amber if >0, gray if 0)

Below that: **Per-staff progress bar** for each active team member. Shows:
- Avatar + name
- "3/7 tasks · 43%" completion rate
- A gold progress bar

Use this to see at a glance who's on pace and who might be overloaded mid-shift.

---

### 2.2 Tasks — Managing the Task Library

This is where you create and edit the **templates** that generate daily tasks.

#### Creating a new task

1. Tap the gold **+ button** in the bottom-right corner.
2. Fill in the **Task Editor sheet**:

| Field | Purpose |
|---|---|
| **Title (English)** | The main label — required |
| **Title (日本語)** | Japanese label — shown below the English |
| **Category** | Opening / Closing / Cleaning / Stock / Prep / Other |
| **Priority** | Low / Normal / High (high shows in red on cards) |
| **Assign to** | Pick a specific staff member, or "Anyone" |
| **Recurring** | Toggle on for daily/weekly tasks, off for one-offs |
| **Repeats** | Daily / Weekly / Monthly (appears only when Recurring is on) |
| **Days** | For weekly tasks — pick which weekdays |

3. Tap **Create**.

The task enters the library. It will auto-generate in the daily list based on its recurrence rules.

#### Editing a task

Tap **Edit** on any row → same editor appears, pre-filled. Tap **Save**.

Changes apply to **future** daily instances. Already-generated daily tasks for today are not affected.

#### Deleting a task

Tap **Delete** on a row. The task is soft-deleted — it stops generating new daily instances but historical data is preserved.

---

### 2.3 Staff — Managing Team Members

Shows every staff member in your database.

> **Staff sign up through the app** — they appear here automatically once they register. You don't manually create staff accounts.

#### Each staff row has three controls

**Role pill** — Tap to toggle between:
- **staff** (gray pill) — regular worker
- **admin** (gold pill) — full access to Admin tab

**Active pill** — Tap to toggle:
- **Active** (gray "Active") — can sign in and see tasks
- **Off** (amber "Off") — deactivated; retained in database but cannot sign in

**Edit button** — Opens a sheet to change their display name.

#### Promoting a new admin

1. Staff signs up via the app (creates their own account)
2. You see them in the Staff list with role = `staff`
3. Tap the **staff** pill → it flips to **admin**
4. Next time they open the app, they'll see the Admin tab

---

### 2.4 Best Practices for Admins

**Morning setup:**
- Check Overview — verify today's task list looks right
- If a staff member called out, reassign their tasks via Tasks → Edit → Assign to

**During service:**
- Monitor Overview for completion pace
- Watch for "Open" count — if it's not shrinking, check which tasks are blocking

**End of shift:**
- Review completed tasks (photos + notes) for accountability
- Flag any tasks left incomplete

**Weekly:**
- Review the task library — retire templates that are no longer relevant
- Audit staff list — deactivate anyone who's left

---

## Part 3: Photos & Notes

### Where photos are stored

Uploaded photos live in secure Supabase Storage. They're tied to the specific daily task and timestamped.

### Who can see photos

Any signed-in staff or admin. Completion photos show as thumbnails on the task card and open full-size when tapped.

### Privacy

Photos should only be of workplace items (bar top, fridge contents, broken glass, etc.). Do not photograph people or customers.

---

## Part 4: Languages (English / 日本語)

Every task has both an English and a Japanese label. Both are shown simultaneously — there's no language toggle. This is intentional so staff at any fluency level can always read the same task.

When creating a task in the admin editor, always fill in **both** titles.

---

## Part 5: Troubleshooting

### I can't sign in

- Double-check email spelling
- Reset your password via the "Forgot password?" link
- Ask your admin to confirm your account is Active (not Off)

### Tasks aren't showing up

- Pull down on the task list to refresh
- Sign out → sign back in
- If still empty, your admin may not have generated today's tasks yet

### Task didn't sync / seems out of date

- Pull down to refresh
- Check your network connection
- Close the app fully (swipe up from the app switcher) and reopen

### I completed a task but it still shows as pending

- Likely a sync delay; pull to refresh
- If it persists > 30 seconds, you may be offline — check your signal

### Photo upload failed

- Verify you have a data or Wi-Fi connection
- Try a smaller photo (the app will automatically compress, but extremely large originals can time out)

### I accidentally deleted a task as admin

Task deletion is **soft-delete** — the record is hidden but not destroyed. Contact your developer to un-delete from the database.

### I made a new staff member an admin, but they don't see the Admin tab

Ask them to quit and reopen the app. Role changes take effect on the next data refresh.

---

## Part 6: Quick Reference

### Staff cheat sheet

| To... | Do this |
|---|---|
| See all of today's tasks | Today tab |
| See just your tasks | Mine tab |
| Start a task | Tap card → Start |
| Complete with photo | Tap card → Complete → camera icon → Done |
| Undo a completion | Tap completed card → Undo |
| Refresh | Pull down on task list |

### Admin cheat sheet

| To... | Do this |
|---|---|
| See completion rates | Admin → Overview |
| Create a task | Admin → Tasks → + button |
| Edit a task | Admin → Tasks → Edit on row |
| Make someone admin | Admin → Staff → tap their role pill |
| Deactivate someone | Admin → Staff → tap their Active pill |
| Rename a staff member | Admin → Staff → Edit on row |

---

## Questions?

Contact your manager or the developer. Bug reports and feature requests welcome.
