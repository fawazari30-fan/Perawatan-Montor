create table if not exists public.notification_inbox (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  motorcycle_id uuid references public.motorcycles (id) on delete set null,
  schedule_id uuid references public.maintenance_schedules (id) on delete set null,
  title text not null,
  body text not null,
  notification_type text not null
    check (notification_type in ('date', 'odometer', 'overdue', 'system')),
  dedupe_key text not null unique,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists notification_inbox_user_created_idx
  on public.notification_inbox (user_id, created_at desc, id desc);
create index if not exists notification_inbox_unread_idx
  on public.notification_inbox (user_id, created_at desc)
  where read_at is null;

alter table public.notification_inbox enable row level security;
drop policy if exists notification_inbox_owner on public.notification_inbox;
create policy notification_inbox_owner on public.notification_inbox
  for select to authenticated
  using (user_id = (select auth.uid()));
drop policy if exists notification_inbox_mark_read on public.notification_inbox;
create policy notification_inbox_mark_read on public.notification_inbox
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

grant select on public.notification_inbox to authenticated;
grant update (read_at) on public.notification_inbox to authenticated;

create or replace function public.rpc_mark_all_notifications_read()
returns int
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_count int;
begin
  update public.notification_inbox
  set read_at = now()
  where user_id = auth.uid() and read_at is null;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

grant execute on function public.rpc_mark_all_notifications_read()
  to authenticated;

create table if not exists public.device_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  token text not null,
  platform text not null check (platform in ('android', 'ios', 'web')),
  updated_at timestamptz not null default now(),
  unique (user_id, token)
);

create index if not exists device_tokens_user_idx
  on public.device_tokens (user_id, updated_at desc);
alter table public.device_tokens enable row level security;
drop policy if exists device_tokens_owner on public.device_tokens;
create policy device_tokens_owner on public.device_tokens
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
grant select, insert, update, delete on public.device_tokens to authenticated;
