alter table public.maintenance_schedules
  add constraint schedules_id_user_motorcycle_uq
  unique (id, user_id, motorcycle_id);

create table if not exists public.service_records (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  motorcycle_id uuid not null,
  schedule_id uuid,
  type_id int not null references public.maintenance_types (id),
  title text not null check (length(trim(title)) > 0),
  service_date date not null default current_date check (service_date <= current_date),
  odometer_km int not null check (odometer_km >= 0),
  workshop text,
  cost numeric(12,0) not null default 0 check (cost >= 0),
  notes text,
  receipt_paths text[] not null default '{}',
  schedule_previous_km int,
  schedule_previous_date date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint service_record_motor_owner_fk
    foreign key (motorcycle_id, user_id)
    references public.motorcycles (id, user_id) on delete cascade,
  constraint service_record_schedule_owner_fk
    foreign key (schedule_id, user_id, motorcycle_id)
    references public.maintenance_schedules (id, user_id, motorcycle_id)
    on delete set null (schedule_id)
);

create index if not exists service_records_motor_date_idx
  on public.service_records (motorcycle_id, service_date desc, id desc);
create index if not exists service_records_user_date_idx
  on public.service_records (user_id, service_date desc);
create index if not exists service_records_schedule_date_idx
  on public.service_records (schedule_id, service_date desc)
  where schedule_id is not null;

create trigger t_service_records_updated_at before update
  on public.service_records
  for each row execute function public.set_updated_at();

alter table public.service_records enable row level security;
drop policy if exists service_records_owner on public.service_records;
create policy service_records_owner on public.service_records
  for select to authenticated
  using (user_id = (select auth.uid()));

grant select on public.service_records to authenticated;

drop function if exists public.rpc_create_service_record(
  uuid, uuid, text, text, date, int, text, numeric, text
);
create or replace function public.rpc_create_service_record(
  p_motorcycle_id uuid,
  p_schedule_id uuid,
  p_type_code text,
  p_title text,
  p_service_date date,
  p_odometer_km int,
  p_workshop text,
  p_cost numeric,
  p_notes text,
  p_receipt_paths text[] default '{}'
)
returns public.service_records
language plpgsql
security definer
set search_path = public
as $$
declare
  v_type_id int;
  v_motorcycle public.motorcycles;
  v_initial_km int;
  v_schedule public.maintenance_schedules;
  v_record public.service_records;
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUIRED';
  end if;
  if nullif(trim(p_title), '') is null then
    raise exception 'SERVICE_TITLE_REQUIRED';
  end if;
  if p_service_date is null or p_service_date > current_date then
    raise exception 'SERVICE_DATE_IN_FUTURE';
  end if;
  if p_odometer_km is null or p_odometer_km < 0 then
    raise exception 'INVALID_SERVICE_ODOMETER';
  end if;
  if p_cost is null or p_cost < 0 then
    raise exception 'INVALID_SERVICE_COST';
  end if;

  select * into v_motorcycle
  from public.motorcycles
  where id = p_motorcycle_id and user_id = auth.uid() and deleted_at is null
  for update;
  if v_motorcycle.id is null then
    raise exception 'MOTORCYCLE_NOT_FOUND';
  end if;

  select km into v_initial_km
  from public.odometer_logs
  where motorcycle_id = p_motorcycle_id
  order by recorded_at asc
  limit 1;
  if p_odometer_km < coalesce(v_initial_km, 0) then
    raise exception 'SERVICE_ODOMETER_BELOW_INITIAL';
  end if;

  select id into v_type_id
  from public.maintenance_types
  where code = p_type_code;
  if v_type_id is null then
    raise exception 'MAINTENANCE_TYPE_NOT_FOUND';
  end if;

  if p_schedule_id is not null and not exists (
    select 1 from public.maintenance_schedules
    where id = p_schedule_id and user_id = auth.uid()
      and motorcycle_id = p_motorcycle_id and is_active
  ) then
    raise exception 'SCHEDULE_NOT_FOUND';
  end if;

  if exists (
    select 1
    from unnest(coalesce(p_receipt_paths, array[]::text[])) as paths(value)
    where split_part(paths.value, '/', 1) <> auth.uid()::text
  ) then
    raise exception 'INVALID_RECEIPT_PATH';
  end if;
  if cardinality(coalesce(p_receipt_paths, array[]::text[])) > 5 then
    raise exception 'TOO_MANY_RECEIPTS';
  end if;

  if p_schedule_id is not null then
    select * into v_schedule
    from public.maintenance_schedules
    where id = p_schedule_id and user_id = auth.uid()
    for update;
  end if;

  insert into public.service_records (
    user_id, motorcycle_id, schedule_id, type_id, title, service_date,
    odometer_km, workshop, cost, notes, receipt_paths,
    schedule_previous_km, schedule_previous_date
  ) values (
    auth.uid(), p_motorcycle_id, p_schedule_id, v_type_id, trim(p_title),
    p_service_date, p_odometer_km, nullif(trim(p_workshop), ''), p_cost,
    nullif(trim(p_notes), ''), coalesce(p_receipt_paths, '{}'),
    v_schedule.last_done_km, v_schedule.last_done_date
  ) returning * into v_record;

  if p_odometer_km > v_motorcycle.odometer_km then
    update public.motorcycles
    set odometer_km = p_odometer_km
    where id = p_motorcycle_id;

    insert into public.odometer_logs (user_id, motorcycle_id, km, source, note)
    values (auth.uid(), p_motorcycle_id, p_odometer_km, 'service',
      'Odometer diperbarui dari catatan servis');
  end if;

  if p_schedule_id is not null then
    update public.maintenance_schedules
    set last_done_km = p_odometer_km,
        last_done_date = p_service_date,
        snoozed_until = null
    where id = p_schedule_id;
  end if;

  return v_record;
end;
$$;

grant execute on function public.rpc_create_service_record(
  uuid, uuid, text, text, date, int, text, numeric, text, text[]
) to authenticated;
revoke all on function public.rpc_create_service_record(
  uuid, uuid, text, text, date, int, text, numeric, text, text[]
) from public;

create or replace function public.rpc_delete_service_record(p_record_id uuid)
returns text[]
language plpgsql
security definer
set search_path = public
as $$
declare
  v_record public.service_records;
  v_schedule public.maintenance_schedules;
  v_previous public.service_records;
  v_paths text[];
begin
  select * into v_record
  from public.service_records
  where id = p_record_id and user_id = auth.uid()
  for update;
  if v_record.id is null then
    raise exception 'SERVICE_RECORD_NOT_FOUND';
  end if;

  if v_record.schedule_id is not null then
    select * into v_schedule
    from public.maintenance_schedules
    where id = v_record.schedule_id and user_id = auth.uid()
    for update;

    if v_schedule.id is not null
       and v_schedule.last_done_km = v_record.odometer_km
       and v_schedule.last_done_date = v_record.service_date then
      select * into v_previous
      from public.service_records
      where schedule_id = v_record.schedule_id
        and id <> v_record.id and user_id = auth.uid()
      order by service_date desc, created_at desc
      limit 1;

      if v_previous.id is not null then
        update public.maintenance_schedules
        set last_done_km = v_previous.odometer_km,
            last_done_date = v_previous.service_date
        where id = v_schedule.id;
      else
        update public.maintenance_schedules
        set last_done_km = coalesce(v_record.schedule_previous_km, 0),
            last_done_date = coalesce(
              v_record.schedule_previous_date,
              v_schedule.created_at::date
            )
        where id = v_schedule.id;
      end if;
    end if;
  end if;

  v_paths := v_record.receipt_paths;
  delete from public.service_records where id = v_record.id;
  return coalesce(v_paths, '{}');
end;
$$;

grant execute on function public.rpc_delete_service_record(uuid)
  to authenticated;
revoke all on function public.rpc_delete_service_record(uuid) from public;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'service-receipts', 'service-receipts', false, 1048576,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists service_receipts_read on storage.objects;
create policy service_receipts_read on storage.objects
  for select to authenticated
  using (
    bucket_id = 'service-receipts'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );
drop policy if exists service_receipts_insert on storage.objects;
create policy service_receipts_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'service-receipts'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );
drop policy if exists service_receipts_delete on storage.objects;
create policy service_receipts_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'service-receipts'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );
