create extension if not exists pgcrypto;

do $$
begin
  create type public.motorcycle_type as enum ('matic', 'bebek', 'sport', 'lainnya');
exception
  when duplicate_object then null;
end $$;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  full_name text not null default '',
  phone text,
  avatar_path text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.motorcycles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  brand text not null,
  model text not null,
  type public.motorcycle_type not null default 'matic',
  year int not null check (
    year between 1980 and extract(year from now())::int + 1
  ),
  plate_number text not null,
  color text,
  odometer_km int not null default 0 check (odometer_km >= 0),
  photo_path text,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists motorcycles_plate_uq
  on public.motorcycles (user_id, upper(regexp_replace(plate_number, '\s+', '', 'g')))
  where deleted_at is null;
create index if not exists motorcycles_user_idx
  on public.motorcycles (user_id, updated_at desc)
  where deleted_at is null;

create table if not exists public.user_settings (
  user_id uuid primary key references auth.users (id) on delete cascade,
  active_motorcycle_id uuid references public.motorcycles (id) on delete set null,
  theme text not null default 'system'
    check (theme in ('system', 'light', 'dark')),
  language text not null default 'id',
  push_enabled boolean not null default true,
  promo_enabled boolean not null default false,
  remind_days_before int not null default 3
    check (remind_days_before between 0 and 30),
  remind_km_before int not null default 200
    check (remind_km_before >= 0),
  updated_at timestamptz not null default now()
);

create table if not exists public.odometer_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  motorcycle_id uuid not null references public.motorcycles (id) on delete cascade,
  km int not null check (km >= 0),
  source text not null default 'manual'
    check (source in ('manual', 'service', 'correction', 'device')),
  recorded_at timestamptz not null default now()
);
create index if not exists odometer_logs_moto_idx
  on public.odometer_logs (motorcycle_id, recorded_at desc);

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, phone)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    new.raw_user_meta_data ->> 'phone'
  )
  on conflict (id) do nothing;

  insert into public.user_settings (user_id)
  values (new.id)
  on conflict (user_id) do nothing;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

drop trigger if exists t_profiles_updated_at on public.profiles;
create trigger t_profiles_updated_at before update on public.profiles
  for each row execute function public.set_updated_at();
drop trigger if exists t_settings_updated_at on public.user_settings;
create trigger t_settings_updated_at before update on public.user_settings
  for each row execute function public.set_updated_at();
drop trigger if exists t_motorcycles_updated_at on public.motorcycles;
create trigger t_motorcycles_updated_at before update on public.motorcycles
  for each row execute function public.set_updated_at();

alter table public.profiles enable row level security;
alter table public.user_settings enable row level security;
alter table public.motorcycles enable row level security;
alter table public.odometer_logs enable row level security;

drop policy if exists profiles_owner on public.profiles;
create policy profiles_owner on public.profiles
  for all to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

drop policy if exists user_settings_owner on public.user_settings;
create policy user_settings_owner on public.user_settings
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

drop policy if exists motorcycles_owner on public.motorcycles;
create policy motorcycles_owner on public.motorcycles
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

drop policy if exists odometer_logs_owner on public.odometer_logs;
create policy odometer_logs_owner on public.odometer_logs
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create or replace function public.rpc_create_motorcycle(
  p_brand text,
  p_model text,
  p_type public.motorcycle_type,
  p_year int,
  p_plate_number text,
  p_color text,
  p_odometer_km int
)
returns public.motorcycles
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_motorcycle public.motorcycles;
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  insert into public.motorcycles (
    user_id, brand, model, type, year, plate_number, color, odometer_km
  )
  values (
    auth.uid(),
    trim(p_brand),
    trim(p_model),
    p_type,
    p_year,
    upper(regexp_replace(trim(p_plate_number), '\s+', '', 'g')),
    nullif(trim(p_color), ''),
    p_odometer_km
  )
  returning * into v_motorcycle;

  insert into public.odometer_logs (user_id, motorcycle_id, km, source)
  values (auth.uid(), v_motorcycle.id, p_odometer_km, 'manual');

  insert into public.user_settings (user_id, active_motorcycle_id)
  values (auth.uid(), v_motorcycle.id)
  on conflict (user_id)
  do update set active_motorcycle_id = excluded.active_motorcycle_id;

  return v_motorcycle;
end;
$$;

alter table public.odometer_logs
  add column if not exists note text;

create or replace function public.rpc_update_motorcycle(
  p_motorcycle_id uuid,
  p_brand text,
  p_model text,
  p_type public.motorcycle_type,
  p_year int,
  p_plate_number text,
  p_color text,
  p_odometer_km int,
  p_correction_reason text default null
)
returns public.motorcycles
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_motorcycle public.motorcycles;
  v_previous_km int;
begin
  select * into v_motorcycle
  from public.motorcycles
  where id = p_motorcycle_id and deleted_at is null
  for update;

  if v_motorcycle.id is null then
    raise exception 'MOTORCYCLE_NOT_FOUND';
  end if;

  if p_odometer_km < v_motorcycle.odometer_km
     and nullif(trim(p_correction_reason), '') is null then
    raise exception 'ODOMETER_DECREASE';
  end if;

  v_previous_km := v_motorcycle.odometer_km;

  update public.motorcycles
  set brand = trim(p_brand),
      model = trim(p_model),
      type = p_type,
      year = p_year,
      plate_number = upper(regexp_replace(trim(p_plate_number), '\s+', '', 'g')),
      color = nullif(trim(p_color), ''),
      odometer_km = p_odometer_km
  where id = p_motorcycle_id
  returning * into v_motorcycle;

  if p_odometer_km <> v_previous_km then
    insert into public.odometer_logs (
      user_id, motorcycle_id, km, source, note
    )
    values (
      auth.uid(),
      p_motorcycle_id,
      p_odometer_km,
      case
        when p_odometer_km < v_previous_km then 'correction'
        else 'manual'
      end,
      nullif(trim(p_correction_reason), '')
    );
  end if;

  return v_motorcycle;
end;
$$;

create or replace function public.rpc_update_odometer(
  p_motorcycle_id uuid,
  p_km int
)
returns public.motorcycles
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_motorcycle public.motorcycles;
begin
  select * into v_motorcycle
  from public.motorcycles
  where id = p_motorcycle_id and deleted_at is null
  for update;

  if v_motorcycle.id is null then
    raise exception 'MOTORCYCLE_NOT_FOUND';
  end if;

  if p_km < v_motorcycle.odometer_km then
    raise exception 'ODOMETER_DECREASE';
  end if;

  if p_km > v_motorcycle.odometer_km then
    update public.motorcycles
    set odometer_km = p_km
    where id = p_motorcycle_id
    returning * into v_motorcycle;

    insert into public.odometer_logs (user_id, motorcycle_id, km, source)
    values (auth.uid(), p_motorcycle_id, p_km, 'manual');
  end if;

  return v_motorcycle;
end;
$$;

create or replace function public.rpc_soft_delete_motorcycle(
  p_motorcycle_id uuid
)
returns boolean
language plpgsql
security invoker
set search_path = public
as $$
begin
  update public.motorcycles
  set deleted_at = now()
  where id = p_motorcycle_id and deleted_at is null;

  if not found then
    return false;
  end if;

  update public.user_settings
  set active_motorcycle_id = null
  where user_id = auth.uid()
    and active_motorcycle_id = p_motorcycle_id;

  return true;
end;
$$;

grant usage on schema public to authenticated;
grant select, insert, update, delete on public.profiles to authenticated;
grant select, insert, update, delete on public.user_settings to authenticated;
grant select, insert, update, delete on public.motorcycles to authenticated;
grant select, insert, update, delete on public.odometer_logs to authenticated;
grant execute on function public.rpc_create_motorcycle(
  text, text, public.motorcycle_type, int, text, text, int
) to authenticated;
grant execute on function public.rpc_update_motorcycle(
  uuid, text, text, public.motorcycle_type, int, text, text, int, text
) to authenticated;
grant execute on function public.rpc_update_odometer(uuid, int)
  to authenticated;
grant execute on function public.rpc_soft_delete_motorcycle(uuid)
  to authenticated;

