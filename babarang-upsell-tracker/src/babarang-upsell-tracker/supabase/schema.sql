-- Babarang Upsell Points Tracker
-- Run this file in Supabase SQL Editor before using the app.
create extension if not exists pgcrypto;

create table if not exists public.staff (
  id uuid primary key default gen_random_uuid(),
  full_name text not null,
  position text not null default 'Service Staff',
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null,
  role text not null check (role in ('manager','staff')),
  staff_id uuid references public.staff(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.upsell_entries (
  id uuid primary key default gen_random_uuid(),
  business_date date not null default current_date,
  staff_id uuid not null references public.staff(id),
  invoice_no text not null,
  original_amount numeric(10,2) not null default 0 check (original_amount >= 0),
  final_amount numeric(10,2) not null default 0 check (final_amount >= 0),
  upsell_amount numeric(10,2) generated always as (greatest(final_amount - original_amount, 0)) stored,
  points integer generated always as (case when greatest(final_amount - original_amount, 0) < 10 then 0 else floor(greatest(final_amount - original_amount, 0) / 10)::integer end) stored,
  status text not null default 'pending' check (status in ('pending','verified','rejected')),
  notes text,
  created_by uuid not null references auth.users(id),
  verified_by uuid references auth.users(id),
  verified_at timestamptz,
  rejection_reason text,
  created_at timestamptz not null default now(),
  unique (invoice_no)
);

create index if not exists upsell_entries_business_date_idx on public.upsell_entries (business_date desc);
create index if not exists upsell_entries_staff_date_idx on public.upsell_entries (staff_id, business_date desc);
create index if not exists upsell_entries_status_idx on public.upsell_entries (status);

create or replace function public.current_user_role()
returns text language sql stable security definer set search_path = public
as $$ select role from public.profiles where user_id = auth.uid() limit 1 $$;

create or replace function public.current_staff_id()
returns uuid language sql stable security definer set search_path = public
as $$ select staff_id from public.profiles where user_id = auth.uid() limit 1 $$;

alter table public.staff enable row level security;
alter table public.profiles enable row level security;
alter table public.upsell_entries enable row level security;

-- Profiles: users can read their own profile; managers can manage profiles.
drop policy if exists "profile self read" on public.profiles;
create policy "profile self read" on public.profiles for select to authenticated
using (user_id = auth.uid() or public.current_user_role() = 'manager');
drop policy if exists "manager manage profiles" on public.profiles;
create policy "manager manage profiles" on public.profiles for all to authenticated
using (public.current_user_role() = 'manager') with check (public.current_user_role() = 'manager');

-- Staff directory is visible to authenticated users; only managers can change it.
drop policy if exists "authenticated read staff" on public.staff;
create policy "authenticated read staff" on public.staff for select to authenticated using (true);
drop policy if exists "manager manage staff" on public.staff;
create policy "manager manage staff" on public.staff for all to authenticated
using (public.current_user_role() = 'manager') with check (public.current_user_role() = 'manager');

-- Managers can review all entries. Staff can see their own entries and submit entries only for themselves.
drop policy if exists "read own or manager entries" on public.upsell_entries;
create policy "read own or manager entries" on public.upsell_entries for select to authenticated
using (public.current_user_role() = 'manager' or staff_id = public.current_staff_id());
drop policy if exists "staff create own pending entry" on public.upsell_entries;
create policy "staff create own pending entry" on public.upsell_entries for insert to authenticated
with check (created_by = auth.uid() and staff_id = public.current_staff_id() and status = 'pending');
drop policy if exists "manager create entries" on public.upsell_entries;
create policy "manager create entries" on public.upsell_entries for insert to authenticated
with check (public.current_user_role() = 'manager');

drop policy if exists "manager update entries" on public.upsell_entries;
create policy "manager update entries" on public.upsell_entries for update to authenticated
using (public.current_user_role() = 'manager') with check (public.current_user_role() = 'manager');
drop policy if exists "manager delete entries" on public.upsell_entries;
create policy "manager delete entries" on public.upsell_entries for delete to authenticated
using (public.current_user_role() = 'manager');

-- IMPORTANT: create Auth users in Supabase Dashboard, then insert their profile records.
-- First create a staff record, copy its UUID, then add profile rows as shown in README.md.
