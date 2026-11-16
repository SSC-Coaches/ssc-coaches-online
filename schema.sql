-- SSC Coaches Online — in Supabase SQL Editor ausführen.
-- WICHTIG: Erst nach Ausführung einen ersten Benutzer über Authentication > Users anlegen,
-- anschließend dessen UUID mit dem Admin-Update in README verwenden.
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  email text not null default '',
  role text not null default 'coach' check (role in ('coach','admin')),
  rate_kurs numeric(10,2) not null default 0 check (rate_kurs >= 0),
  rate_privat numeric(10,2) not null default 0 check (rate_privat >= 0),
  rate_office numeric(10,2) not null default 0 check (rate_office >= 0),
  rate_sonstiges numeric(10,2) not null default 0 check (rate_sonstiges >= 0),
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create or replace function public.new_user_profile() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles(id, email, full_name)
  values (new.id, coalesce(new.email,''), coalesce(new.raw_user_meta_data->>'full_name',''));
  return new;
end; $$;
drop trigger if exists create_profile_on_signup on auth.users;
create trigger create_profile_on_signup after insert on auth.users
for each row execute function public.new_user_profile();

create or replace function public.is_ssc_admin() returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.profiles where id = (select auth.uid()) and role = 'admin' and active = true);
$$;

create table if not exists public.time_entries (
  id uuid primary key default gen_random_uuid(),
  coach_id uuid not null references public.profiles(id) on delete restrict,
  work_date date not null,
  start_time time not null,
  end_time time not null,
  break_minutes integer not null default 0 check (break_minutes >= 0),
  course text not null check (course in ('LG1a','LG1a/b','LG1b','LG1c','LG2','LG3','LG4','LG5','LG6','LG7','Andere')),
  training_type text not null check (training_type in ('kurs','privat','off-ice','sonstiges')),
  note text not null default '',
  hourly_rate numeric(10,2) not null default 0 check (hourly_rate >= 0),
  minutes_worked integer not null default 0 check (minutes_worked > 0),
  amount_chf numeric(12,2) not null default 0 check (amount_chf >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id)
);
create index if not exists idx_ssc_time_entries_coach_date on public.time_entries(coach_id,work_date);
create index if not exists idx_ssc_time_entries_date on public.time_entries(work_date);

create or replace function public.calculate_ssc_entry() returns trigger language plpgsql security definer set search_path = '' as $$
declare
  p public.profiles%rowtype;
  total_minutes integer;
  new_rate numeric(10,2);
begin
  if new.end_time <= new.start_time then
    raise exception 'Die Endzeit muss nach der Startzeit liegen (keine Schicht über Mitternacht).';
  end if;
  total_minutes := floor(extract(epoch from (new.end_time - new.start_time))/60)::integer - new.break_minutes;
  if total_minutes <= 0 then
    raise exception 'Die Arbeitszeit nach Pausen muss positiv sein.';
  end if;
  if total_minutes > 960 then
    raise exception 'Ein Eintrag darf höchstens 16 Stunden umfassen.';
  end if;
  select * into p from public.profiles where id = new.coach_id;
  if not found or p.active = false then
    raise exception 'Coach ist nicht aktiv oder existiert nicht.';
  end if;
  if tg_op = 'INSERT' then
    new_rate := case new.training_type
      when 'kurs' then p.rate_kurs
      when 'privat' then p.rate_privat
      when 'off-ice' then p.rate_office
      else p.rate_sonstiges end;
    new.hourly_rate := new_rate;
  elsif new.coach_id is distinct from old.coach_id or
     new.training_type is distinct from old.training_type or
     new.start_time is distinct from old.start_time or
     new.end_time is distinct from old.end_time or
     new.break_minutes is distinct from old.break_minutes then
    new_rate := case new.training_type
      when 'kurs' then p.rate_kurs
      when 'privat' then p.rate_privat
      when 'off-ice' then p.rate_office
      else p.rate_sonstiges end;
    new.hourly_rate := new_rate;
  end if;
  new.minutes_worked := total_minutes;
  new.amount_chf := round((total_minutes::numeric / 60) * new.hourly_rate, 2);
  new.updated_at := now();
  new.updated_by := auth.uid();
  return new;
end; $$;
drop trigger if exists set_ssc_entry_calculated on public.time_entries;
create trigger set_ssc_entry_calculated before insert or update on public.time_entries
for each row execute function public.calculate_ssc_entry();

-- Änderungsprotokoll (nur Administratoren können lesen)
create table if not exists public.time_entry_audit (
  id bigint generated always as identity primary key,
  entry_id uuid not null,
  action text not null,
  actor_id uuid,
  changed_at timestamptz not null default now(),
  old_data jsonb,
  new_data jsonb
);
create or replace function public.audit_ssc_entry() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.time_entry_audit(entry_id,action,actor_id,old_data,new_data)
  values (coalesce(new.id,old.id),tg_op,auth.uid(),
          case when tg_op = 'INSERT' then null else to_jsonb(old) end,
          case when tg_op = 'DELETE' then null else to_jsonb(new) end);
  return coalesce(new,old);
end; $$;
drop trigger if exists audit_ssc_changes on public.time_entries;
create trigger audit_ssc_changes after insert or update or delete on public.time_entries
for each row execute function public.audit_ssc_entry();

alter table public.profiles enable row level security;
alter table public.time_entries enable row level security;
alter table public.time_entry_audit enable row level security;

drop policy if exists "profiles read self or admin" on public.profiles;
create policy "profiles read self or admin" on public.profiles for select to authenticated
using (id = (select auth.uid()) or public.is_ssc_admin());
drop policy if exists "profiles admin update" on public.profiles;
create policy "profiles admin update" on public.profiles for update to authenticated
using (public.is_ssc_admin()) with check (public.is_ssc_admin());

drop policy if exists "entries read own or admin" on public.time_entries;
create policy "entries read own or admin" on public.time_entries for select to authenticated
using (coach_id = (select auth.uid()) or public.is_ssc_admin());
drop policy if exists "entries insert own or admin" on public.time_entries;
create policy "entries insert own or admin" on public.time_entries for insert to authenticated
with check (coach_id = (select auth.uid()) or public.is_ssc_admin());
drop policy if exists "entries update own or admin" on public.time_entries;
create policy "entries update own or admin" on public.time_entries for update to authenticated
using (coach_id = (select auth.uid()) or public.is_ssc_admin())
with check (coach_id = (select auth.uid()) or public.is_ssc_admin());
drop policy if exists "entries delete own or admin" on public.time_entries;
create policy "entries delete own or admin" on public.time_entries for delete to authenticated
using (coach_id = (select auth.uid()) or public.is_ssc_admin());

drop policy if exists "audit admin read" on public.time_entry_audit;
create policy "audit admin read" on public.time_entry_audit for select to authenticated
using (public.is_ssc_admin());

revoke all on public.profiles from anon, authenticated;
revoke all on public.time_entries from anon, authenticated;
revoke all on public.time_entry_audit from anon, authenticated;
grant select on public.profiles to authenticated;
grant update(full_name,rate_kurs,rate_privat,rate_office,rate_sonstiges,active) on public.profiles to authenticated;
grant select,insert,delete on public.time_entries to authenticated;
-- Nur bearbeitbare Felder: Berechnungen werden serverseitig bestimmt.
grant update(coach_id,work_date,start_time,end_time,break_minutes,course,training_type,note) on public.time_entries to authenticated;
grant select on public.time_entry_audit to authenticated;
-- Sicherheitsgrenze: clientseitige Rollen-Änderung und Änderungen der errechneten Beträge sind verboten.
-- Rollenvergabe ausschliesslich durch SQL Editor / Supabase Dashboard (service_role).
