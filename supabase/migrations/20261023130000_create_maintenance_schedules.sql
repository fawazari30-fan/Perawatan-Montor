alter table public.motorcycles
  add constraint motorcycles_id_user_uq unique (id, user_id);

create table if not exists public.maintenance_types (
  id serial primary key,
  code text unique not null,
  name text not null,
  default_interval_km int,
  default_interval_days int,
  weight numeric(3,2) not null default 0.10
);

insert into public.maintenance_types
  (code, name, default_interval_km, default_interval_days, weight)
values
  ('oil', 'Ganti Oli Mesin', 2000, 60, 0.25),
  ('brake', 'Pemeriksaan Rem', 8000, 180, 0.25),
  ('battery', 'Pemeriksaan Aki', null, 365, 0.15),
  ('tire', 'Pemeriksaan Ban', 10000, 365, 0.15),
  ('air_filter', 'Ganti Filter Udara', 8000, 365, 0.10),
  ('service', 'Servis Berkala', 3000, 90, 0.10),
  ('other', 'Lainnya', null, null, 0.10)
on conflict (code) do update set
  name = excluded.name,
  default_interval_km = excluded.default_interval_km,
  default_interval_days = excluded.default_interval_days,
  weight = excluded.weight;

create table if not exists public.maintenance_schedules (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  motorcycle_id uuid not null,
  type_id int not null references public.maintenance_types (id),
  title text not null,
  interval_km int check (interval_km > 0),
  interval_days int check (interval_days > 0),
  last_done_km int not null default 0 check (last_done_km >= 0),
  last_done_date date not null default current_date,
  snoozed_until date,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint schedule_has_interval
    check (interval_km is not null or interval_days is not null),
  constraint schedule_title_not_empty check (length(trim(title)) > 0),
  constraint schedule_motor_owner_fk
    foreign key (motorcycle_id, user_id)
    references public.motorcycles (id, user_id) on delete cascade
);

create index if not exists schedules_moto_idx
  on public.maintenance_schedules (motorcycle_id, is_active);
create index if not exists schedules_user_idx
  on public.maintenance_schedules (user_id, updated_at desc);

drop trigger if exists t_schedules_updated_at on public.maintenance_schedules;
create trigger t_schedules_updated_at before update
  on public.maintenance_schedules
  for each row execute function public.set_updated_at();

alter table public.maintenance_types enable row level security;
alter table public.maintenance_schedules enable row level security;

drop policy if exists types_read on public.maintenance_types;
create policy types_read on public.maintenance_types
  for select to authenticated using (true);

drop policy if exists schedules_owner on public.maintenance_schedules;
create policy schedules_owner on public.maintenance_schedules
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create or replace view public.v_schedule_status
with (security_invoker = true)
as
select
  x.*,
  case
    when x.snoozed_until is not null and x.snoozed_until >= current_date
      then 'snoozed'
    when (x.next_due_km is not null and x.odometer_km >= x.next_due_km)
      or (x.next_due_date is not null and current_date > x.next_due_date)
      or x.remaining_pct <= 0
      then 'overdue'
    when x.remaining_pct < 0.15 then 'urgent'
    when x.remaining_pct < 0.40 then 'due_soon'
    else 'upcoming'
  end as status
from (
  select
    s.*,
    t.code as type_code,
    t.weight,
    m.odometer_km,
    case when s.interval_km is null then null
      else s.last_done_km + s.interval_km end as next_due_km,
    case when s.interval_days is null then null
      else s.last_done_date + s.interval_days end as next_due_date,
    least(
      coalesce(
        greatest(
          0,
          1 - (m.odometer_km - s.last_done_km)::numeric
            / nullif(s.interval_km, 0)
        ),
        1
      ),
      coalesce(
        greatest(
          0,
          1 - (current_date - s.last_done_date)::numeric
            / nullif(s.interval_days, 0)
        ),
        1
      )
    ) as remaining_pct
  from public.maintenance_schedules s
  join public.motorcycles m on m.id = s.motorcycle_id
  join public.maintenance_types t on t.id = s.type_id
  where s.is_active and m.deleted_at is null
) x;

create or replace function public.rpc_create_schedule(
  p_motorcycle_id uuid,
  p_type_code text,
  p_title text,
  p_interval_km int,
  p_interval_days int,
  p_last_done_km int,
  p_last_done_date date
)
returns public.maintenance_schedules
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_type_id int;
  v_motorcycle public.motorcycles;
  v_schedule public.maintenance_schedules;
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUIRED';
  end if;
  if p_interval_km is null and p_interval_days is null then
    raise exception 'SCHEDULE_INTERVAL_REQUIRED';
  end if;
  if nullif(trim(p_title), '') is null then
    raise exception 'SCHEDULE_TITLE_REQUIRED';
  end if;
  if p_last_done_km < 0 or p_last_done_date > current_date then
    raise exception 'INVALID_LAST_MAINTENANCE';
  end if;

  select * into v_motorcycle
  from public.motorcycles
  where id = p_motorcycle_id and deleted_at is null
  for update;
  if v_motorcycle.id is null then
    raise exception 'MOTORCYCLE_NOT_FOUND';
  end if;
  if p_last_done_km > v_motorcycle.odometer_km then
    raise exception 'LAST_MAINTENANCE_KM_EXCEEDS_ODOMETER';
  end if;

  select id into v_type_id
  from public.maintenance_types
  where code = p_type_code;
  if v_type_id is null then
    raise exception 'MAINTENANCE_TYPE_NOT_FOUND';
  end if;

  insert into public.maintenance_schedules (
    user_id, motorcycle_id, type_id, title, interval_km, interval_days,
    last_done_km, last_done_date
  )
  values (
    auth.uid(), p_motorcycle_id, v_type_id, trim(p_title),
    p_interval_km, p_interval_days, p_last_done_km, p_last_done_date
  )
  returning * into v_schedule;

  return v_schedule;
end;
$$;

create or replace function public.rpc_update_schedule(
  p_schedule_id uuid,
  p_type_code text,
  p_title text,
  p_interval_km int,
  p_interval_days int,
  p_last_done_km int,
  p_last_done_date date
)
returns public.maintenance_schedules
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_schedule public.maintenance_schedules;
  v_motorcycle public.motorcycles;
  v_type_id int;
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUIRED';
  end if;
  if nullif(trim(p_title), '') is null then
    raise exception 'SCHEDULE_TITLE_REQUIRED';
  end if;
  if p_interval_km is null and p_interval_days is null then
    raise exception 'SCHEDULE_INTERVAL_REQUIRED';
  end if;
  if p_last_done_km < 0 or p_last_done_date > current_date then
    raise exception 'INVALID_LAST_MAINTENANCE';
  end if;

  select * into v_schedule
  from public.maintenance_schedules
  where id = p_schedule_id and user_id = auth.uid() and is_active
  for update;
  if v_schedule.id is null then
    raise exception 'SCHEDULE_NOT_FOUND';
  end if;

  select * into v_motorcycle
  from public.motorcycles
  where id = v_schedule.motorcycle_id
    and user_id = auth.uid() and deleted_at is null;
  if v_motorcycle.id is null then
    raise exception 'MOTORCYCLE_NOT_FOUND';
  end if;
  if p_last_done_km > v_motorcycle.odometer_km then
    raise exception 'LAST_MAINTENANCE_KM_EXCEEDS_ODOMETER';
  end if;

  select id into v_type_id
  from public.maintenance_types
  where code = p_type_code;
  if v_type_id is null then
    raise exception 'MAINTENANCE_TYPE_NOT_FOUND';
  end if;

  update public.maintenance_schedules
  set type_id = v_type_id,
      title = trim(p_title),
      interval_km = p_interval_km,
      interval_days = p_interval_days,
      last_done_km = p_last_done_km,
      last_done_date = p_last_done_date
  where id = p_schedule_id
  returning * into v_schedule;
  return v_schedule;
end;
$$;

create or replace function public.rpc_snooze_schedule(
  p_schedule_id uuid,
  p_days int
)
returns date
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_snoozed_until date;
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUIRED';
  end if;
  if p_days not in (1, 3, 7) then
    raise exception 'INVALID_SNOOZE_DURATION';
  end if;
  update public.maintenance_schedules
  set snoozed_until = current_date + p_days
  where id = p_schedule_id and user_id = auth.uid() and is_active
  returning snoozed_until into v_snoozed_until;
  if v_snoozed_until is null then
    raise exception 'SCHEDULE_NOT_FOUND';
  end if;
  return v_snoozed_until;
end;
$$;

create or replace function public.rpc_deactivate_schedule(p_schedule_id uuid)
returns boolean
language plpgsql
security invoker
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUIRED';
  end if;
  update public.maintenance_schedules
  set is_active = false, snoozed_until = null
  where id = p_schedule_id and user_id = auth.uid() and is_active;
  return found;
end;
$$;

grant select on public.maintenance_types to authenticated;
grant select, insert, update, delete on public.maintenance_schedules to authenticated;
grant select on public.v_schedule_status to authenticated;
grant usage, select on sequence public.maintenance_types_id_seq to authenticated;
grant execute on function public.rpc_create_schedule(
  uuid, text, text, int, int, int, date
) to authenticated;
grant execute on function public.rpc_update_schedule(
  uuid, text, text, int, int, int, date
) to authenticated;
grant execute on function public.rpc_snooze_schedule(uuid, int)
  to authenticated;
grant execute on function public.rpc_deactivate_schedule(uuid)
  to authenticated;
