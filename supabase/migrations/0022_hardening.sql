-- =====================================================================
-- KMR Console — Milestone 5: hardening. Needs 0021. Safe to re-run.
--  • Rate limits for logins, forms and payment reports (public.kmr_rate_ok, server only)
--  • Activity log: who changed invoices, payments, prices, staff, licences, orders and website content (triggers)
--  • Error log (with de-duplication, so one alert per error per hour) and email log
--  • Backups: the Console backup now also covers customer users, platform settings and all website data;
--    a second nightly file covers the apps' data (Operations Master, Balloon Inspector, Process Documents,
--    Capacity Planner). Both are kept 30 days.
-- =====================================================================
do $$ begin
  if to_regclass('console.leads') is null or to_regprocedure('console.console_export()') is null then
    raise exception 'Run the earlier Console migrations (up to 0021) first.';
  end if;
end $$;

-- ---------- rate limits ----------
create table if not exists console.rate_hits (
  key  text not null,
  at   timestamptz not null default now()
);
create index if not exists rate_hits_key_at on console.rate_hits (key, at desc);
create table if not exists console.rate_blocks (
  key   text primary key,
  first_at timestamptz not null default now(),
  last_at  timestamptz not null default now(),
  blocked  integer not null default 1
);
alter table console.rate_hits enable row level security;
alter table console.rate_blocks enable row level security;

-- true = allowed (and counted); false = over the limit for this window
create or replace function public.kmr_rate_ok(p_key text, p_max integer, p_window_seconds integer) returns boolean
language plpgsql security definer set search_path = console, public as $$
declare n integer; k text := left(coalesce(p_key, ''), 200);
begin
  if k = '' then return true; end if;
  delete from console.rate_hits where key = k and at < now() - make_interval(secs => p_window_seconds);
  if random() < 0.02 then delete from console.rate_hits where at < now() - interval '1 day'; end if;
  select count(*) into n from console.rate_hits where key = k;
  if n >= p_max then
    insert into console.rate_blocks (key) values (k)
    on conflict (key) do update set last_at = now(), blocked = console.rate_blocks.blocked + 1;
    return false;
  end if;
  insert into console.rate_hits (key) values (k);
  return true;
end $$;
revoke all on function public.kmr_rate_ok(text, integer, integer) from public, anon, authenticated;
grant execute on function public.kmr_rate_ok(text, integer, integer) to service_role;

-- ---------- activity log ----------
create table if not exists console.audit_log (
  id        bigserial primary key,
  at        timestamptz not null default now(),
  actor     text,
  tbl       text not null,
  row_id    text,
  action    text not null check (action in ('insert','update','delete')),
  changes   jsonb
);
create index if not exists audit_log_at on console.audit_log (at desc);
create index if not exists audit_log_tbl on console.audit_log (tbl, at desc);
alter table console.audit_log enable row level security;

create or replace function console.audit_row() returns trigger
language plpgsql security definer set search_path = console, public as $$
declare
  who text := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'email',
                       nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', current_user);
  o jsonb; n jsonb; diff jsonb := '{}'::jsonb; k text;
  skip text[] := array['updated_at','created_at','search','fts'];
begin
  if tg_op = 'INSERT' then
    n := to_jsonb(new);
    insert into console.audit_log (actor, tbl, row_id, action, changes)
    values (who, tg_table_schema || '.' || tg_table_name, n ->> 'id', 'insert', n - skip);
    return new;
  elsif tg_op = 'DELETE' then
    o := to_jsonb(old);
    insert into console.audit_log (actor, tbl, row_id, action, changes)
    values (who, tg_table_schema || '.' || tg_table_name, o ->> 'id', 'delete', o - skip);
    return old;
  end if;
  o := to_jsonb(old); n := to_jsonb(new);
  for k in select jsonb_object_keys(n) loop
    if not (k = any(skip)) and (o -> k) is distinct from (n -> k) then
      diff := diff || jsonb_build_object(k, jsonb_build_array(o -> k, n -> k));
    end if;
  end loop;
  if diff <> '{}'::jsonb then
    insert into console.audit_log (actor, tbl, row_id, action, changes)
    values (who, tg_table_schema || '.' || tg_table_name, coalesce(n ->> 'id', n ->> 'code', n ->> 'user_id'), 'update', diff);
  end if;
  return new;
end $$;

do $$
declare t text;
begin
  foreach t in array array[
    'console.staff','console.customers','console.licences','console.prices','console.billing_settings',
    'console.invoices','console.invoice_lines','console.payments','console.platform_settings',
    'public.orders','public.products','public.company_info','public.legal_pages','public.site_settings','public.verticals',
    'public.hero_slides','public.site_stats','public.home_points','public.product_benefits','public.job_openings',
    'public.job_applications','public.leaders','public.gallery_items','public.compliance_records'] loop
    if to_regclass(t) is not null then
      execute format('drop trigger if exists kmr_audit on %s', t);
      execute format('create trigger kmr_audit after insert or update or delete on %s for each row execute function console.audit_row()', t);
    end if;
  end loop;
end $$;

-- ---------- error log (one alert per error per hour) ----------
create table if not exists console.app_errors (
  id       bigserial primary key,
  first_at timestamptz not null default now(),
  last_at  timestamptz not null default now(),
  app      text not null,
  path     text,
  message  text not null,
  digest   text,
  detail   text,
  count    integer not null default 1
);
create index if not exists app_errors_last on console.app_errors (last_at desc);
alter table console.app_errors enable row level security;

-- returns true when this is a new error (or the same error again after an hour) — the caller then sends one alert
create or replace function public.kmr_log_error(p_app text, p_path text, p_message text, p_digest text default null, p_detail text default null) returns boolean
language plpgsql security definer set search_path = console, public as $$
declare e console.app_errors; msg text := left(coalesce(p_message, 'Unknown error'), 1000);
begin
  select * into e from console.app_errors
   where app = left(p_app, 40) and message = msg and coalesce(path, '') = coalesce(left(p_path, 300), '')
   order by last_at desc limit 1;
  if e.id is not null and e.last_at > now() - interval '1 hour' then
    update console.app_errors set count = count + 1, last_at = now() where id = e.id;
    return false;
  end if;
  insert into console.app_errors (app, path, message, digest, detail)
  values (left(p_app, 40), left(p_path, 300), msg, left(p_digest, 100), left(p_detail, 4000));
  delete from console.app_errors where last_at < now() - interval '90 days';
  return true;
end $$;
revoke all on function public.kmr_log_error(text, text, text, text, text) from public, anon, authenticated;
grant execute on function public.kmr_log_error(text, text, text, text, text) to service_role;

-- ---------- email log ----------
create table if not exists console.email_log (
  id      bigserial primary key,
  at      timestamptz not null default now(),
  app     text not null,
  kind    text not null,
  to_addr text not null,
  subject text,
  status  text not null check (status in ('sent','skipped','failed')),
  error   text,
  ref     text
);
create index if not exists email_log_at on console.email_log (at desc);
alter table console.email_log enable row level security;

-- ---------- backups ----------
create or replace function console.console_export() returns jsonb
language plpgsql stable security definer set search_path = console, public as $fn$
declare out jsonb := '{}'::jsonb; t text; rows jsonb;
begin
  foreach t in array array['console.products','console.customers','console.customer_members','console.licences','console.licence_events',
                           'console.releases','console.tickets','console.ticket_messages','console.leads','console.staff',
                           'console.prices','console.billing_settings','console.invoice_counters','console.invoices','console.invoice_lines',
                           'console.payments','console.platform_settings',
                           'public.company_info','public.site_settings','public.verticals','public.hero_slides','public.site_stats',
                           'public.home_points','public.product_benefits','public.products','public.orders','public.legal_pages',
                           'public.job_openings','public.job_applications','public.leaders','public.gallery_items','public.compliance_records',
                           'public.hero_content'] loop
    if to_regclass(t) is null then continue; end if;
    execute format('select coalesce(jsonb_agg(to_jsonb(x)), ''[]'') from %s x', t) into rows;
    out := out || jsonb_build_object(t, rows);
  end loop;
  return jsonb_build_object('format', 'kmr-console-backup', 'version', 2, 'exported_at', now(), 'tables', out);
end $fn$;

-- the customers' app data (kept separate: it can be large, and it is the customers' own data)
create or replace function console.apps_export() returns jsonb
language plpgsql stable security definer set search_path = console, public as $fn$
declare out jsonb := '{}'::jsonb; t text; rows jsonb;
begin
  foreach t in array array['console.ops_records','public.bi_orgs','public.bi_members','public.bi_reports','public.pd_orgs','public.pd_members',
                           'public.pd_projects','public.pd_masters','public.cp_orgs','public.cp_members','public.cp_plans'] loop
    if to_regclass(t) is null then continue; end if;
    execute format('select coalesce(jsonb_agg(to_jsonb(x)), ''[]'') from %s x', t) into rows;
    out := out || jsonb_build_object(t, rows);
  end loop;
  return jsonb_build_object('format', 'kmr-apps-backup', 'version', 1, 'exported_at', now(), 'tables', out);
end $fn$;
revoke all on function console.console_export(), console.apps_export() from public, anon, authenticated;
grant execute on function console.console_export(), console.apps_export() to service_role;
update storage.buckets set file_size_limit = 209715200 where id = 'kmr-backups';
