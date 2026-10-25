alter table public.user_settings
  add column if not exists remind_hour int not null default 7;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'user_settings_remind_hour_check'
      and conrelid = 'public.user_settings'::regclass
  ) then
    alter table public.user_settings
      add constraint user_settings_remind_hour_check
      check (remind_hour between 0 and 23);
  end if;
end;
$$;
