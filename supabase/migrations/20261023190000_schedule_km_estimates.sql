drop view public.v_schedule_status;

create view public.v_schedule_status
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
  end as status,
  case
    when x.next_due_date is null then estimates.km_due_date
    when estimates.km_due_date is null then x.next_due_date
    else least(x.next_due_date, estimates.km_due_date)
  end as effective_due_date,
  km_stats.avg_km_per_day
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
) x
left join lateral (
  select case
    when max(logs.recorded_at) - min(logs.recorded_at) >= interval '7 days'
      and (array_agg(logs.km order by logs.recorded_at desc))[1]
        >= (array_agg(logs.km order by logs.recorded_at))[1]
    then (
      (array_agg(logs.km order by logs.recorded_at desc))[1]
      - (array_agg(logs.km order by logs.recorded_at))[1]
    )::numeric / nullif(
      extract(epoch from max(logs.recorded_at) - min(logs.recorded_at)) / 86400,
      0
    )
  end as avg_km_per_day
  from public.odometer_logs logs
  where logs.motorcycle_id = x.motorcycle_id
    and logs.recorded_at >= now() - interval '30 days'
    and logs.source <> 'correction'
) km_stats on true
left join lateral (
  select case
    when x.next_due_km is not null and km_stats.avg_km_per_day > 0
    then current_date + ceil(
      greatest(0, x.next_due_km - x.odometer_km)::numeric
        / km_stats.avg_km_per_day
    )::int
  end as km_due_date
) estimates on true;

grant select on public.v_schedule_status to authenticated;
