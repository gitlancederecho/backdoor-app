-- =====================================================================
-- The Backdoor — Supabase schema + RLS + storage
-- Run this in the Supabase SQL editor on a fresh project.
-- =====================================================================

-- ---------- Extensions ---------------------------------------------------
create extension if not exists "pgcrypto";

-- ---------- Tables -------------------------------------------------------

create table if not exists staff (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid unique references auth.users(id) on delete cascade,
  name text not null,
  role text not null default 'staff' check (role in ('admin', 'staff')),
  email text unique not null,
  avatar_url text,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists tasks (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  title_ja text,
  -- Free-form category key. We ship six built-ins via localization, but
  -- admins can coin new ones from the Task editor; the iOS client
  -- falls back to title-casing the raw key for unknown values.
  category text not null,
  assigned_to uuid references staff(id) on delete set null,
  is_recurring boolean not null default false,
  recurrence_type text check (recurrence_type in ('daily','weekly','monthly')),
  recurrence_days int[] default '{}',
  priority text not null default 'normal' check (priority in ('low','normal','high')),
  created_by uuid references staff(id) on delete set null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  -- Optional time-of-day window for when the task should be done.
  start_time time,
  end_time time
);

-- Idempotent add-column guards (for DBs created before these fields existed).
alter table tasks add column if not exists start_time time;
alter table tasks add column if not exists end_time time;

create table if not exists daily_tasks (
  id uuid primary key default gen_random_uuid(),
  task_id uuid references tasks(id) on delete cascade,
  date date not null default current_date,
  assigned_to uuid references staff(id) on delete set null,
  status text not null default 'pending' check (status in ('pending','in_progress','completed')),
  completed_by uuid references staff(id) on delete set null,
  completed_at timestamptz,
  note text,
  photo_url text,
  created_at timestamptz not null default now(),
  -- Inherited from tasks template at generation time.
  start_time time,
  end_time time,
  -- Audit: who tapped Start and when (null if staff skipped straight to Complete).
  started_by uuid references staff(id) on delete set null,
  started_at timestamptz,
  unique (task_id, date)
);

alter table daily_tasks add column if not exists start_time time;
alter table daily_tasks add column if not exists end_time time;
alter table daily_tasks add column if not exists started_by uuid references staff(id) on delete set null;
alter table daily_tasks add column if not exists started_at timestamptz;

-- ---------- Task categories --------------------------------------------
-- Admin-editable list. Tasks.category is a text key that SHOULD match
-- a row here, but there's no FK — deleting a category leaves orphan
-- keys that the iOS client humanizes client-side. Six built-ins ship
-- pre-seeded; admins can add / rename / reorder / delete.
create table if not exists categories (
  key text primary key check (key = lower(key) and length(key) > 0),
  label_en text not null,
  label_ja text,
  sort_order smallint not null default 100,
  is_builtin boolean not null default false,
  updated_at timestamptz not null default now()
);

insert into categories (key, label_en, label_ja, sort_order, is_builtin) values
  ('opening',  'Opening',  'オープン',  1, true),
  ('bar',      'Bar',      'バー',      2, true),
  ('cleaning', 'Cleaning', '清掃',      3, true),
  ('closing',  'Closing',  'クローズ',  4, true),
  ('weekly',   'Weekly',   '週次',      5, true),
  ('other',    'Other',    'その他',    6, true)
on conflict (key) do nothing;

-- ---------- Task events (audit log) -------------------------------------
-- Append-only log of every meaningful change to a daily_task. Written by
-- the iOS client directly (no DB trigger). Enum values correspond to
-- `TaskEventType` in Models.swift.
create table if not exists task_events (
  id uuid primary key default gen_random_uuid(),
  -- Nullable: template-level events (e.g. an admin deletes a template
  -- that has no daily_tasks materialized yet) are logged with
  -- daily_task_id = null. The iOS client puts the template title in
  -- `note` so the History tab can still render the event.
  daily_task_id uuid references daily_tasks(id) on delete cascade,
  actor_id uuid references staff(id) on delete set null,
  event_type text not null check (event_type in (
    'created','started','completed','undone','reassigned',
    'note_added','note_updated','photo_added','deleted'
  )),
  from_value text,
  to_value text,
  note text,
  photo_url text,
  created_at timestamptz not null default now()
);

create index if not exists task_events_daily_task_idx on task_events(daily_task_id, created_at);

-- Idempotent guard for DBs created before daily_task_id was made nullable.
alter table task_events alter column daily_task_id drop not null;

-- Idempotent guard for DBs created with the original category CHECK.
alter table tasks drop constraint if exists tasks_category_check;

create index if not exists daily_tasks_date_idx on daily_tasks(date);
create index if not exists daily_tasks_assigned_idx on daily_tasks(assigned_to);
create index if not exists tasks_active_idx on tasks(is_active) where is_active = true;

-- ---------- Venue operating hours ---------------------------------------
-- Singleton settings row governing business-day math.
-- `prep_buffer_minutes`: how long before open_time the business day begins
--   (so morning prep tasks appear on the same day as the evening shift).
-- `grace_period_minutes`: how long past close_time we still consider part
--   of the same business day (handles bars running late).
create table if not exists venue_settings (
  id smallint primary key check (id = 1),
  timezone text not null default 'Asia/Tokyo',
  -- Default matches the current operator setting (8.5 h of morning prep).
  prep_buffer_minutes smallint not null default 510 check (prep_buffer_minutes between 0 and 720),
  grace_period_minutes smallint not null default 120 check (grace_period_minutes between 0 and 480),
  updated_at timestamptz not null default now()
);

insert into venue_settings (id) values (1) on conflict (id) do nothing;

-- Weekly operating schedule — one row per ISO weekday (1=Mon .. 7=Sun).
-- `close_time` may be earlier than `open_time` to indicate "closes next
-- calendar day" (e.g. 17:00 open, 03:00 close).
create table if not exists venue_schedule (
  weekday smallint primary key check (weekday between 1 and 7),
  is_closed boolean not null default false,
  open_time time,
  close_time time,
  updated_at timestamptz not null default now(),
  check (is_closed or (open_time is not null and close_time is not null))
);

-- Seed default schedule: Mon/Thu/Fri/Sat/Sun open 17:00–00:00; Tue+Wed closed.
-- (Matches The Backdoor's actual operating week as of 2026-04.)
-- close_time 00:00 = midnight (close_time <= open_time → "closes next calendar day").
-- Closed days keep open/close times populated so operators can re-enable the
-- day without re-entering times.
insert into venue_schedule (weekday, is_closed, open_time, close_time) values
  (1, false, '17:00:00', '00:00:00'),
  (2, true,  '17:00:00', '03:00:00'),
  (3, true,  '17:00:00', '03:00:00'),
  (4, false, '17:00:00', '00:00:00'),
  (5, false, '17:00:00', '00:00:00'),
  (6, false, '17:00:00', '00:00:00'),
  (7, false, '17:00:00', '00:00:00')
on conflict (weekday) do nothing;

-- Auto-touch updated_at on any change.
create or replace function set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists venue_settings_updated_at on venue_settings;
create trigger venue_settings_updated_at
  before update on venue_settings
  for each row execute function set_updated_at();

drop trigger if exists venue_schedule_updated_at on venue_schedule;
create trigger venue_schedule_updated_at
  before update on venue_schedule
  for each row execute function set_updated_at();

drop trigger if exists categories_updated_at on categories;
create trigger categories_updated_at
  before update on categories
  for each row execute function set_updated_at();

-- ---------- Helper: current staff row -----------------------------------
create or replace function current_staff()
returns staff
language sql stable security definer
set search_path = public
as $$
  select * from staff where auth_user_id = auth.uid() limit 1;
$$;

create or replace function is_admin()
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from staff
    where auth_user_id = auth.uid() and role = 'admin' and is_active = true
  );
$$;

-- ---------- Auto-provision staff on signup ------------------------------
-- When a new auth.users row is created, insert a matching staff row so the
-- admin doesn't have to do it manually. Admin can later upgrade role.
create or replace function handle_new_auth_user()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  insert into staff (auth_user_id, email, name, role)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'name', split_part(new.email, '@', 1)),
    'staff'
  )
  on conflict (email) do update set auth_user_id = excluded.auth_user_id;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_auth_user();

-- ---------- Generate daily_tasks from templates -------------------------
-- Call this at the start of the day (or on demand) to materialize recurring
-- task instances for a given date. Safe to re-run (idempotent).
--
-- Skips generation on days where `venue_schedule.is_closed = true` so the
-- Hours admin hint ("tasks won't generate on closed days") is enforced at
-- the source.
create or replace function generate_daily_tasks(target_date date default current_date)
returns int
language plpgsql security definer
set search_path = public
as $$
declare
  dow int := extract(isodow from target_date)::int; -- 1=Mon..7=Sun
  dom int := extract(day from target_date)::int;
  inserted int := 0;
  day_closed boolean;
begin
  -- Honor the weekly schedule: if the venue is closed on this weekday,
  -- don't materialize instances. Falls back to "not closed" if no schedule
  -- row exists, preserving the pre-hours behavior.
  select is_closed into day_closed
  from venue_schedule
  where weekday = dow;

  if coalesce(day_closed, false) then
    return 0;
  end if;

  with eligible as (
    select t.*
    from tasks t
    where t.is_active = true
      and t.is_recurring = true
      and (
        t.recurrence_type = 'daily'
        or (t.recurrence_type = 'weekly' and dow = any(t.recurrence_days))
        or (t.recurrence_type = 'monthly' and (array_length(t.recurrence_days, 1) is null or dom = any(t.recurrence_days)))
      )
  ),
  ins as (
    -- Copy start_time/end_time from the template so daily rows carry the
    -- time window without a join. Clients can still edit them per-instance.
    insert into daily_tasks (task_id, date, assigned_to, status, start_time, end_time)
    select e.id, target_date, e.assigned_to, 'pending', e.start_time, e.end_time
    from eligible e
    on conflict (task_id, date) do nothing
    returning 1
  )
  select count(*) into inserted from ins;
  return inserted;
end;
$$;

-- ---------- Profile stats RPC -------------------------------------------
-- One round-trip for the Profile tab: counts for today / this week /
-- all-time completions plus in-progress right now. Uses auth.uid() via
-- a staff-row lookup so callers don't pass their own id.
create or replace function my_profile_stats()
returns jsonb
language sql stable security definer
set search_path = public
as $$
  with me as (
    select id from staff where auth_user_id = auth.uid() limit 1
  )
  select jsonb_build_object(
    'today_assigned', (
      select count(*)::int from daily_tasks dt
      where dt.date = current_date and dt.assigned_to = (select id from me)
    ),
    'today_completed', (
      select count(*)::int from daily_tasks dt
      where dt.date = current_date and dt.completed_by = (select id from me)
    ),
    'week_completed', (
      select count(*)::int from daily_tasks dt
      where dt.completed_at >= (now() - interval '7 days')
        and dt.completed_by = (select id from me)
    ),
    'all_time_completed', (
      select count(*)::int from daily_tasks dt
      where dt.completed_by = (select id from me)
    ),
    'in_progress_now', (
      select count(*)::int from daily_tasks dt
      where dt.status = 'in_progress'
        and (dt.started_by = (select id from me) or dt.assigned_to = (select id from me))
    )
  );
$$;

-- ---------- Row Level Security ------------------------------------------
alter table staff enable row level security;
alter table tasks enable row level security;
alter table daily_tasks enable row level security;
alter table venue_settings enable row level security;
alter table venue_schedule enable row level security;
alter table task_events enable row level security;
alter table categories enable row level security;

-- staff: everyone authenticated can read; admin can write anything;
-- anyone can update their own row, but NOT change their role or is_active
-- (prevents self-promotion). Admin retains full control via staff_admin_write.
drop policy if exists staff_read on staff;
create policy staff_read on staff
  for select using (auth.role() = 'authenticated');

drop policy if exists staff_admin_write on staff;
create policy staff_admin_write on staff
  for all using (is_admin()) with check (is_admin());

drop policy if exists staff_update_self on staff;
create policy staff_update_self on staff
  for update using (auth_user_id = auth.uid())
  with check (
    auth_user_id = auth.uid()
    and role = (select role from staff where auth_user_id = auth.uid())
    and is_active = (select is_active from staff where auth_user_id = auth.uid())
  );

-- tasks: everyone authenticated can read, only admin can write
drop policy if exists tasks_read on tasks;
create policy tasks_read on tasks
  for select using (auth.role() = 'authenticated');

drop policy if exists tasks_admin_write on tasks;
create policy tasks_admin_write on tasks
  for all using (is_admin()) with check (is_admin());

-- daily_tasks: read all, insert allowed for authenticated (used by generator),
-- update allowed if you're the assignee OR completer OR admin.
drop policy if exists daily_read on daily_tasks;
create policy daily_read on daily_tasks
  for select using (auth.role() = 'authenticated');

drop policy if exists daily_insert on daily_tasks;
create policy daily_insert on daily_tasks
  for insert with check (auth.role() = 'authenticated');

drop policy if exists daily_update on daily_tasks;
create policy daily_update on daily_tasks
  for update using (
    is_admin()
    or assigned_to = (select id from staff where auth_user_id = auth.uid())
    or assigned_to is null -- unassigned: anyone can claim
  ) with check (
    is_admin()
    or completed_by = (select id from staff where auth_user_id = auth.uid())
    or assigned_to = (select id from staff where auth_user_id = auth.uid())
    or assigned_to is null
  );

drop policy if exists daily_delete on daily_tasks;
create policy daily_delete on daily_tasks
  for delete using (is_admin());

-- venue_settings: everyone authenticated can read; only admin can write.
drop policy if exists venue_settings_read on venue_settings;
create policy venue_settings_read on venue_settings
  for select using (auth.role() = 'authenticated');

drop policy if exists venue_settings_admin_write on venue_settings;
create policy venue_settings_admin_write on venue_settings
  for all using (is_admin()) with check (is_admin());

-- venue_schedule: everyone authenticated can read; only admin can write.
drop policy if exists venue_schedule_read on venue_schedule;
create policy venue_schedule_read on venue_schedule
  for select using (auth.role() = 'authenticated');

drop policy if exists venue_schedule_admin_write on venue_schedule;
create policy venue_schedule_admin_write on venue_schedule
  for all using (is_admin()) with check (is_admin());

-- categories: everyone authenticated reads; only admin can write.
drop policy if exists categories_read on categories;
create policy categories_read on categories
  for select using (auth.role() = 'authenticated');

drop policy if exists categories_admin_write on categories;
create policy categories_admin_write on categories
  for all using (is_admin()) with check (is_admin());

-- task_events: append-only audit log.
-- Everyone authenticated can read. Authenticated users can insert as long
-- as actor_id is null (system) or matches their own staff.id (no
-- impersonation). Only admin can update or delete — rewriting the log
-- should be exceptional.
drop policy if exists task_events_read on task_events;
create policy task_events_read on task_events
  for select using (auth.role() = 'authenticated');

drop policy if exists task_events_insert on task_events;
create policy task_events_insert on task_events
  for insert with check (
    actor_id is null
    or actor_id = (select id from staff where auth_user_id = auth.uid())
  );

drop policy if exists task_events_admin_update on task_events;
create policy task_events_admin_update on task_events
  for update using (is_admin()) with check (is_admin());

drop policy if exists task_events_admin_delete on task_events;
create policy task_events_admin_delete on task_events
  for delete using (is_admin());

-- ---------- Realtime -----------------------------------------------------
-- Guarded publication adds — safe to re-run. Every table that a client
-- subscribes to via Supabase Realtime goes here.
do $$
begin
  begin alter publication supabase_realtime add table staff;
    exception when duplicate_object then null;
  end;
  begin alter publication supabase_realtime add table tasks;
    exception when duplicate_object then null;
  end;
  begin alter publication supabase_realtime add table daily_tasks;
    exception when duplicate_object then null;
  end;
  begin alter publication supabase_realtime add table task_events;
    exception when duplicate_object then null;
  end;
  begin alter publication supabase_realtime add table categories;
    exception when duplicate_object then null;
  end;
  begin alter publication supabase_realtime add table venue_settings;
    exception when duplicate_object then null;
  end;
  begin alter publication supabase_realtime add table venue_schedule;
    exception when duplicate_object then null;
  end;
end $$;

-- ---------- Storage bucket ----------------------------------------------
insert into storage.buckets (id, name, public)
values ('task-photos', 'task-photos', true)
on conflict (id) do nothing;

-- Authenticated users can upload; everyone can read (bucket is public).
drop policy if exists "task-photos upload" on storage.objects;
create policy "task-photos upload" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'task-photos');

drop policy if exists "task-photos read" on storage.objects;
create policy "task-photos read" on storage.objects
  for select using (bucket_id = 'task-photos');

drop policy if exists "task-photos delete own" on storage.objects;
create policy "task-photos delete own" on storage.objects
  for delete to authenticated
  using (bucket_id = 'task-photos' and owner = auth.uid());

-- =====================================================================
-- Done. Create your first admin by signing up via the app, then run:
--   update staff set role = 'admin' where email = 'you@example.com';
-- =====================================================================
