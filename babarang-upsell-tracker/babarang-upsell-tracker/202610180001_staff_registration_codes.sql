-- Additive migration for one-time Staff Registration Codes.
-- Does NOT drop or rewrite existing staff, profiles, or upsell_entries.
create table if not exists public.staff_registration_codes (
  id uuid primary key default gen_random_uuid(),
  staff_id uuid not null references public.staff(id) on delete cascade,
  code_hash text not null unique,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '7 days'),
  used_by uuid references auth.users(id),
  used_at timestamptz
);

alter table public.staff_registration_codes enable row level security;
revoke all on public.staff_registration_codes from anon, authenticated;
grant select, insert, update, delete on public.staff_registration_codes to service_role;

create or replace function public.manager_create_staff_registration_code(p_staff_id uuid)
returns text
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_code text;
  v_role text;
begin
  select role into v_role from public.profiles where user_id = auth.uid();
  if v_role is distinct from 'manager' then
    raise exception 'Only managers can create staff registration codes';
  end if;

  if not exists (select 1 from public.staff where id = p_staff_id and active = true) then
    raise exception 'Active staff record not found';
  end if;

  v_code := 'BAB-' || upper(substr(encode(gen_random_bytes(8), 'hex'), 1, 10));
  insert into public.staff_registration_codes (staff_id, code_hash, created_by, expires_at)
  values (
    p_staff_id,
    encode(digest(upper(replace(v_code, '-', '')), 'sha256'), 'hex'),
    auth.uid(),
    now() + interval '7 days'
  );
  return v_code;
end;
$$;

revoke all on function public.manager_create_staff_registration_code(uuid) from public, anon;
grant execute on function public.manager_create_staff_registration_code(uuid) to authenticated;

-- The Edge Function uses the service role to claim a code and create the profile.
-- Client users cannot read registration-code rows or directly assign their own role.


-- Enforce a maximum of 15 active staff records, including concurrent inserts.
create or replace function public.enforce_max_15_active_staff()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  if NEW.active is true and (TG_OP = 'INSERT' or OLD.active is distinct from true) then
    perform pg_advisory_xact_lock(hashtext('babarang_max_active_staff'));
    if (select count(*) from public.staff where active = true and id is distinct from NEW.id) >= 15 then
      raise exception 'Maximum of 15 active staff members reached';
    end if;
  end if;
  return NEW;
end;
$$;
drop trigger if exists enforce_max_15_active_staff_trigger on public.staff;
create trigger enforce_max_15_active_staff_trigger before insert or update of active on public.staff
for each row execute function public.enforce_max_15_active_staff();
