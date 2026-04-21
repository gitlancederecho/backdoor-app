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
  category text not null check (category in ('opening','closing','bar','cleaning','weekly','other')),
  assigned_to uuid references staff(id) on delete set null,
  is_recurring boolean not null default false,
  recurrence_type text check (recurrence_type in ('daily','weekly','monthly')),
  recurrence_days int[] default '{}',
  priority text not null default 'normal' check (priority in ('low','normal','high')),
  created_by uuid references staff(id) on delete set null,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

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
  unique (task_id, date)
);

create index if not exists daily_tasks_date_idx on daily_tasks(date);
create index if not exists daily_tasks_assigned_idx on daily_tasks(assigned_to);
create index if not exists tasks_active_idx on tasks(is_active) where is_active = true;

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
create or replace function generate_daily_tasks(target_date date default current_date)
returns int
language plpgsql security definer
set search_path = public
as $$
declare
  dow int := extract(isodow from target_date)::int; -- 1=Mon..7=Sun
  dom int := extract(day from target_date)::int;
  inserted int := 0;
begin
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
    insert into daily_tasks (task_id, date, assigned_to, status)
    select e.id, target_date, e.assigned_to, 'pending'
    from eligible e
    on conflict (task_id, date) do nothing
    returning 1
  )
  select count(*) into inserted from ins;
  return inserted;
end;
$$;

-- ---------- Row Level Security ------------------------------------------
alter table staff enable row level security;
alter table tasks enable row level security;
alter table daily_tasks enable row level security;

-- staff: everyone authenticated can read, only admin can write
drop policy if exists staff_read on staff;
create policy staff_read on staff
  for select using (auth.role() = 'authenticated');

drop policy if exists staff_admin_write on staff;
create policy staff_admin_write on staff
  for all using (is_admin()) with check (is_admin());

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

-- ---------- Realtime -----------------------------------------------------
alter publication supabase_realtime add table daily_tasks;
alter publication supabase_realtime add table tasks;
alter publication supabase_realtime add table staff;

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
