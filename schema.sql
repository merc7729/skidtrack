-- SkidTrack | Water Filtration Service Management
-- Run this entire file in Supabase SQL Editor.

create extension if not exists "pgcrypto";

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default 'Employee',
  role text not null default 'technician'
    check (role in ('admin','manager','technician')),
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.skids (
  id uuid primary key default gen_random_uuid(),
  skid_number text not null unique,
  location text,
  system_type text,
  status text not null default 'active'
    check (status in ('active','maintenance','out_of_service')),
  created_at timestamptz not null default now()
);

create table if not exists public.work_records (
  id uuid primary key default gen_random_uuid(),
  skid_id uuid not null references public.skids(id) on delete cascade,
  technician_id uuid not null references public.profiles(id) on delete restrict,
  work_performed text not null,
  time_spent numeric(10,2) not null check (time_spent > 0),
  notes text,
  performed_at timestamptz not null default now()
);

create index if not exists idx_work_records_skid on public.work_records(skid_id);
create index if not exists idx_work_records_technician on public.work_records(technician_id);
create index if not exists idx_work_records_date on public.work_records(performed_at desc);

-- Automatically create a technician profile when a new Auth user is created.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, role, active)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', split_part(new.email, '@', 1), 'Employee'),
    'technician',
    true
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute procedure public.handle_new_user();

alter table public.profiles enable row level security;
alter table public.skids enable row level security;
alter table public.work_records enable row level security;

-- Helper function used by RLS.
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid()
      and role = 'admin'
      and active = true
  );
$$;

-- PROFILES
drop policy if exists "profiles_select_authenticated" on public.profiles;
create policy "profiles_select_authenticated"
on public.profiles for select to authenticated
using (true);

drop policy if exists "profiles_update_admin" on public.profiles;
create policy "profiles_update_admin"
on public.profiles for update to authenticated
using (public.is_admin())
with check (public.is_admin());

-- SKIDS: all authenticated users can view; admins manage.
drop policy if exists "skids_select_authenticated" on public.skids;
create policy "skids_select_authenticated"
on public.skids for select to authenticated
using (true);

drop policy if exists "skids_insert_admin" on public.skids;
create policy "skids_insert_admin"
on public.skids for insert to authenticated
with check (public.is_admin());

drop policy if exists "skids_update_admin" on public.skids;
create policy "skids_update_admin"
on public.skids for update to authenticated
using (public.is_admin())
with check (public.is_admin());

drop policy if exists "skids_delete_admin" on public.skids;
create policy "skids_delete_admin"
on public.skids for delete to authenticated
using (public.is_admin());

-- WORK RECORDS: authenticated users can view; users insert their own records.
drop policy if exists "work_select_authenticated" on public.work_records;
create policy "work_select_authenticated"
on public.work_records for select to authenticated
using (true);

drop policy if exists "work_insert_own" on public.work_records;
create policy "work_insert_own"
on public.work_records for insert to authenticated
with check (technician_id = auth.uid());

drop policy if exists "work_update_own_or_admin" on public.work_records;
create policy "work_update_own_or_admin"
on public.work_records for update to authenticated
using (technician_id = auth.uid() or public.is_admin())
with check (technician_id = auth.uid() or public.is_admin());

drop policy if exists "work_delete_own_or_admin" on public.work_records;
create policy "work_delete_own_or_admin"
on public.work_records for delete to authenticated
using (technician_id = auth.uid() or public.is_admin());

-- IMPORTANT:
-- 1. Create your first user in Authentication > Users.
-- 2. The trigger creates that user's profile automatically.
-- 3. Promote your first user to admin by running:
--
-- update public.profiles
-- set role = 'admin'
-- where id = 'PASTE-YOUR-AUTH-USER-UUID-HERE';
