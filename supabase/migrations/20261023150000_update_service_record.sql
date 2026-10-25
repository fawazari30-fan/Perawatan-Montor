create or replace function public.rpc_update_service_record(
  p_record_id uuid,
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
  v_record public.service_records;
  v_schedule public.maintenance_schedules;
  v_motorcycle public.motorcycles;
  v_type_id int;
  v_initial_km int;
  v_old_service_km int;
  v_old_service_date date;
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
  if cardinality(coalesce(p_receipt_paths, array[]::text[])) > 5 then
    raise exception 'TOO_MANY_RECEIPTS';
  end if;
  if exists (
    select 1
    from unnest(coalesce(p_receipt_paths, array[]::text[])) as paths(value)
    where split_part(paths.value, '/', 1) <> auth.uid()::text
  ) then
    raise exception 'INVALID_RECEIPT_PATH';
  end if;

  select * into v_record
  from public.service_records
  where id = p_record_id and user_id = auth.uid()
  for update;
  if v_record.id is null then
    raise exception 'SERVICE_RECORD_NOT_FOUND';
  end if;
  v_old_service_km := v_record.odometer_km;
  v_old_service_date := v_record.service_date;

  select * into v_motorcycle
  from public.motorcycles
  where id = v_record.motorcycle_id
    and user_id = auth.uid()
    and deleted_at is null
  for update;
  if v_motorcycle.id is null then
    raise exception 'MOTORCYCLE_NOT_FOUND';
  end if;

  select km into v_initial_km
  from public.odometer_logs
  where motorcycle_id = v_record.motorcycle_id
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

  if v_record.schedule_id is not null then
    select * into v_schedule
    from public.maintenance_schedules
    where id = v_record.schedule_id and user_id = auth.uid()
    for update;
  end if;

  update public.service_records
  set type_id = v_type_id,
      title = trim(p_title),
      service_date = p_service_date,
      odometer_km = p_odometer_km,
      workshop = nullif(trim(p_workshop), ''),
      cost = p_cost,
      notes = nullif(trim(p_notes), ''),
      receipt_paths = coalesce(p_receipt_paths, '{}')
  where id = v_record.id
  returning * into v_record;

  if v_schedule.id is not null
     and v_schedule.last_done_km = v_old_service_km
     and v_schedule.last_done_date = v_old_service_date then
    update public.maintenance_schedules
    set last_done_km = p_odometer_km,
        last_done_date = p_service_date
    where id = v_schedule.id;
  end if;

  if p_odometer_km > v_motorcycle.odometer_km then
    update public.motorcycles
    set odometer_km = p_odometer_km
    where id = v_motorcycle.id;
    insert into public.odometer_logs (
      user_id, motorcycle_id, km, source, note
    ) values (
      auth.uid(), v_motorcycle.id, p_odometer_km, 'service',
      'Odometer diperbarui dari catatan servis yang diedit'
    );
  end if;

  return v_record;
end;
$$;

grant execute on function public.rpc_update_service_record(
  uuid, text, text, date, int, text, numeric, text, text[]
) to authenticated;
revoke all on function public.rpc_update_service_record(
  uuid, text, text, date, int, text, numeric, text, text[]
) from public;
