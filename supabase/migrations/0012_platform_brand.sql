-- =====================================================================
-- KMR Console — KMR's own branding (logo), shown on the Console sign-in, its main screen and favicon,
-- and on the general KMR Apps page. Customers' logos stay on each customer. Safe to re-run.
-- =====================================================================
create table if not exists console.platform_settings (
  key        text primary key,
  value      jsonb not null,
  updated_at timestamptz not null default now()
);
alter table console.platform_settings enable row level security;
drop policy if exists platform_settings_staff on console.platform_settings;
create policy platform_settings_staff on console.platform_settings for all to authenticated using (console.is_staff()) with check (console.is_staff());

create or replace function public.kmr_platform_brand() returns jsonb
language sql stable security definer set search_path = console, public as $$
  select coalesce((select value from console.platform_settings where key = 'brand'), '{}'::jsonb)
$$;
grant execute on function public.kmr_platform_brand() to anon, authenticated;
