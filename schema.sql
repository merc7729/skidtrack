-- Run in Supabase SQL Editor
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  role text not null default 'technician' check (role in ('admin','manager','technician')),
  created_at timestamptz default now()
);
create table if not exists public.skids (
  id uuid primary key default gen_random_uuid(),
  skid_number text not null unique,
  location text,
  system_type text,
  status text default 'Active',
  created_at timestamptz default now()
);
create table if not exists public.work_records (
  id uuid primary key default gen_random_uuid(),
  skid_id uuid references public.skids(id) on delete set null,
  skid_number text not null,
  work_performed text not null,
  hours numeric(8,2) not null check(hours >= 0),
  technician_id uuid references public.profiles(id),
  technician_name text,
  notes text,
  created_at timestamptz default now()
);
alter table public.profiles enable row level security;
alter table public.skids enable row level security;
alter table public.work_records enable row level security;
create policy "authenticated profiles read" on public.profiles for select to authenticated using (true);
create policy "users update own profile" on public.profiles for update to authenticated using (id=auth.uid()) with check (id=auth.uid());
create policy "authenticated skids read" on public.skids for select to authenticated using (true);
create policy "managers manage skids" on public.skids for all to authenticated using ((select role from public.profiles where id=auth.uid()) in ('admin','manager')) with check ((select role from public.profiles where id=auth.uid()) in ('admin','manager'));
create policy "authenticated work read" on public.work_records for select to authenticated using (true);
create policy "authenticated insert work" on public.work_records for insert to authenticated with check (true);
create policy "managers update work" on public.work_records for update to authenticated using ((select role from public.profiles where id=auth.uid()) in ('admin','manager'));
create policy "managers delete work" on public.work_records for delete to authenticated using ((select role from public.profiles where id=auth.uid()) in ('admin','manager'));
-- After creating your first Auth user, insert that user's UUID below and set role to admin:
-- insert into public.profiles(id,full_name,role) values ('USER_UUID','Administrator','admin');
