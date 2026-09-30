-- =====================================================================
-- KMR Console — Test data tools (Console › Test data). Needs 0022. Safe to re-run.
--  • Settings backup: KMR's own settings and website content as one JSON file (download / upload to restore)
--  • Full backup: every table of every KMR app, saved to kmr-backups before any clean-out
--  • Clean out: removes customers, orders, app workspaces, HR records and logs — keeps KMR staff, products,
--    prices, seller details, platform settings and all website content
--  • Demo Operations Master for the demo customer
-- All functions are server-only (service role). The Console checks that the person is the owner first.
-- =====================================================================
do $$ begin
  if to_regprocedure('public.kmr_rate_ok(text,integer,integer)') is null then
    raise exception 'Run 0022_hardening.sql first.';
  end if;
end $$;

-- invoice pay links: built-in random (no pgcrypto needed — it lives in another schema on Supabase)
alter table console.invoices alter column pay_token set default (replace(gen_random_uuid()::text, '-', '') || substr(md5(random()::text), 1, 4));

-- ---------- settings kept through a clean-out (restore order: parents first) ----------
create or replace function console.settings_tables() returns text[] language sql immutable as $$
  select array['console.products','console.prices','console.releases','console.billing_settings','console.platform_settings',
               'public.company_info','public.site_settings','public.verticals','public.hero_slides','public.hero_content',
               'public.site_stats','public.home_points','public.product_benefits','public.legal_pages','public.leaders',
               'public.gallery_items','public.compliance_records','public.products','public.job_openings']
$$;

create or replace function console.settings_export() returns jsonb
language plpgsql stable security definer set search_path = console, public as $fn$
declare out jsonb := '{}'::jsonb; t text; rows jsonb; st jsonb;
begin
  foreach t in array console.settings_tables() loop
    if to_regclass(t) is null then continue; end if;
    execute format('select coalesce(jsonb_agg(to_jsonb(x)), ''[]'') from %s x', t) into rows;
    out := out || jsonb_build_object(t, rows);
  end loop;
  -- staff for reference only (logins cannot be moved between projects, so a restore never touches staff)
  select coalesce(jsonb_agg(jsonb_build_object('email', email, 'full_name', full_name, 'role', role, 'active', active)), '[]') into st from console.staff;
  return jsonb_build_object('format', 'kmr-settings', 'version', 1, 'exported_at', now(), 'tables', out, 'staff', st);
end $fn$;

-- upsert rows into a table by its primary key, using only the columns present in the file
create or replace function console.upsert_rows(p_table text, p_rows jsonb) returns integer
language plpgsql security definer set search_path = console, public as $fn$
declare cols text[]; pk text[]; sets text; n integer := 0; rel regclass := to_regclass(p_table);
begin
  if rel is null or p_rows is null or jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) = 0 then return 0; end if;
  select array_agg(a.attname order by a.attnum) into cols
    from pg_attribute a
   where a.attrelid = rel and a.attnum > 0 and not a.attisdropped and a.attgenerated = ''
     and exists (select 1 from jsonb_array_elements(p_rows) r where r ? a.attname);
  select array_agg(a.attname) into pk
    from pg_index i join pg_attribute a on a.attrelid = i.indrelid and a.attnum = any(i.indkey)
   where i.indrelid = rel and i.indisprimary;
  if cols is null or pk is null or not (pk <@ cols) then raise exception 'Cannot restore %: the file has no id column for it.', p_table; end if;
  select string_agg(format('%I = excluded.%I', c, c), ', ') into sets from unnest(cols) c where not (c = any(pk));
  execute format('insert into %s (%s) select %s from jsonb_populate_recordset(null::%s, $1) on conflict (%s) do %s',
                 rel, (select string_agg(quote_ident(c), ', ') from unnest(cols) c), (select string_agg(quote_ident(c), ', ') from unnest(cols) c),
                 rel, (select string_agg(quote_ident(c), ', ') from unnest(pk) c),
                 case when sets is null then 'nothing' else 'update set ' || sets end)
    using p_rows;
  get diagnostics n = row_count;
  return n;
end $fn$;

create or replace function console.settings_import(p_data jsonb) returns jsonb
language plpgsql security definer set search_path = console, public as $fn$
declare t text; n integer; out jsonb := '{}'::jsonb;
begin
  if p_data ->> 'format' is distinct from 'kmr-settings' then raise exception 'This is not a KMR settings file (Console › Test data › Download settings).'; end if;
  foreach t in array console.settings_tables() loop
    if to_regclass(t) is null or not (p_data -> 'tables' ? t) then continue; end if;
    n := console.upsert_rows(t, p_data -> 'tables' -> t);
    out := out || jsonb_build_object(t, n);
  end loop;
  return out;
end $fn$;

-- ---------- full backup: every table of every app ----------
create or replace function console.full_export() returns jsonb
language plpgsql stable security definer set search_path = console, public as $fn$
declare out jsonb := '{}'::jsonb; r record; rows jsonb;
begin
  for r in select n.nspname, c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
            where c.relkind = 'r' and n.nspname in ('console','public','hrm')
              and c.relname not in ('rate_hits','rate_blocks') order by 1, 2 loop
    execute format('select coalesce(jsonb_agg(to_jsonb(x)), ''[]'') from %I.%I x', r.nspname, r.relname) into rows;
    out := out || jsonb_build_object(r.nspname || '.' || r.relname, rows);
  end loop;
  return jsonb_build_object('format', 'kmr-full-backup', 'version', 1, 'exported_at', now(), 'tables', out);
end $fn$;


-- pause / resume the apps' own row rules (e.g. "at least one admin must remain") during a deliberate removal
create or replace function console.app_triggers(p_prefix text, p_on boolean) returns void
language plpgsql security definer set search_path = console, public as $fn$
declare r record;
begin
  for r in select c.relname from pg_class c join pg_namespace s on s.oid = c.relnamespace
            where s.nspname = 'public' and c.relkind = 'r' and c.relname ~ ('^(' || p_prefix || ')_')
              and exists (select 1 from pg_trigger t where t.tgrelid = c.oid and not t.tgisinternal) loop
    execute format('alter table public.%I %s trigger user', r.relname, case when p_on then 'enable' else 'disable' end);
  end loop;
end $fn$;

-- ---------- clean out ----------
-- p_parts: customers | shop | catalogue | apps | logs.  p_keep_hrm: the HRM company to keep (KMR's own), by short name.
create or replace function console.platform_flush(p_parts text[], p_keep_hrm text default null) returns jsonb
language plpgsql security definer set search_path = console, public as $fn$
declare out jsonb := '{}'::jsonb; n integer; r record; keep uuid[]; w integer := 0;
begin
  if 'customers' = any(p_parts) then
    delete from console.payments;        get diagnostics n = row_count; out := out || jsonb_build_object('payments', n);
    delete from console.invoice_lines;
    delete from console.invoices;        get diagnostics n = row_count; out := out || jsonb_build_object('invoices', n);
    update console.invoice_counters set last_no = 0;
    delete from console.ticket_messages;
    delete from console.tickets;         get diagnostics n = row_count; out := out || jsonb_build_object('tickets', n);
    delete from console.leads;           get diagnostics n = row_count; out := out || jsonb_build_object('enquiries', n);
    delete from console.customers;       get diagnostics n = row_count; out := out || jsonb_build_object('customers', n);   -- + licences, users, Operations Master
  end if;

  if 'shop' = any(p_parts) then
    if to_regclass('public.orders') is not null then delete from public.orders; get diagnostics n = row_count; out := out || jsonb_build_object('orders', n); end if;
    if to_regclass('public.job_applications') is not null then delete from public.job_applications; get diagnostics n = row_count; out := out || jsonb_build_object('applications', n); end if;
  end if;

  if 'catalogue' = any(p_parts) then
    if to_regclass('public.orders') is not null then delete from public.orders; end if;
    if to_regclass('public.job_applications') is not null then delete from public.job_applications; end if;
    if to_regclass('public.products') is not null then delete from public.products; get diagnostics n = row_count; out := out || jsonb_build_object('website_products', n); end if;
    if to_regclass('public.job_openings') is not null then delete from public.job_openings; get diagnostics n = row_count; out := out || jsonb_build_object('job_openings', n); end if;
  end if;

  if 'apps' = any(p_parts) then
    perform console.app_triggers('bi|pd|cp', false);
    -- Balloon Inspector, Process Documents, Capacity Planner: everything under each workspace, then the workspaces
    for r in select c.relname from pg_class c join pg_namespace s on s.oid = c.relnamespace
              where s.nspname = 'public' and c.relkind = 'r' and c.relname ~ '^(bi|pd|cp)_' and c.relname !~ '(_orgs|_platform_admins)$' loop
      execute format('delete from public.%I', r.relname);
    end loop;
    for r in select unnest(array['bi_orgs','pd_orgs','cp_orgs']) t loop
      if to_regclass('public.' || r.t) is not null then execute format('delete from public.%I', r.t); get diagnostics n = row_count; w := w + n; end if;
    end loop;
    out := out || jsonb_build_object('app_workspaces', w);
    perform console.app_triggers('bi|pd|cp', true);
    -- the HRM change-log would try to record rows of companies being deleted: pause it for this transaction only
    for r in select t.tgrelid::regclass::text rel, t.tgname from pg_trigger t join pg_proc p on p.oid = t.tgfoid
              where p.proname = 'audit_row' and p.pronamespace = 'hrm'::regnamespace and not t.tgisinternal loop
      execute format('alter table %s disable trigger %I', r.rel, r.tgname);
    end loop;
    -- HRM: every company except KMR's own; KMR's own keeps its settings and administrators, loses employees and HR records
    select coalesce(array_agg(id), '{}') into keep from hrm.tenants
     where (p_keep_hrm is not null and slug = lower(p_keep_hrm))
        or id in (select tenant_id from hrm.app_users where role = 'platform_admin');
    delete from hrm.tenants where not (id = any(keep)); get diagnostics n = row_count; out := out || jsonb_build_object('hrm_companies', n);
    delete from hrm.app_users where tenant_id = any(keep) and employee_id is not null and role not in ('platform_admin','company_admin');
    update hrm.app_users set employee_id = null where tenant_id = any(keep);
    delete from hrm.onboarding_invites where tenant_id = any(keep);
    delete from hrm.attendance_punches where tenant_id = any(keep);
    delete from hrm.attendance_days where tenant_id = any(keep);
    delete from hrm.regularisation_requests where tenant_id = any(keep);
    delete from hrm.leave_ledger where tenant_id = any(keep);
    delete from hrm.leave_requests where tenant_id = any(keep);
    delete from hrm.employees where tenant_id = any(keep); get diagnostics n = row_count; out := out || jsonb_build_object('hrm_employees_of_kmr', n);
    delete from hrm.notifications where tenant_id = any(keep);
    delete from hrm.audit_log where tenant_id = any(keep);
    update hrm.tenants set emp_code_seq = 0 where id = any(keep);
    for r in select t.tgrelid::regclass::text rel, t.tgname from pg_trigger t join pg_proc p on p.oid = t.tgfoid
              where p.proname = 'audit_row' and p.pronamespace = 'hrm'::regnamespace and not t.tgisinternal loop
      execute format('alter table %s enable trigger %I', r.rel, r.tgname);
    end loop;
  end if;

  if 'logs' = any(p_parts) then
    delete from console.audit_log; delete from console.email_log; delete from console.app_errors;
    delete from console.rate_hits; delete from console.rate_blocks;
    out := out || jsonb_build_object('logs', 'cleared');
  end if;
  return out;
end $fn$;

-- logins nobody uses any more (after a clean-out): the Console deletes them through the Supabase admin API
drop function if exists console.orphan_logins();
create or replace function console.orphan_logins() returns table (user_id uuid, email text)
language plpgsql stable security definer set search_path = console, public, auth as $fn$
-- builds the "still in use" list only from tables and columns that exist in this project (the apps differ slightly)
declare ids uuid[] := '{}'; mails text[] := '{}'; t text; c text; more uuid[]; m text[];
begin
  foreach t in array array['console.staff','hrm.app_users','console.customer_members','public.staff_profiles',
                           'public.bi_platform_admins','public.pd_platform_admins','public.bi_members','public.pd_members','public.cp_members'] loop
    if to_regclass(t) is null then continue; end if;
    foreach c in array array['user_id','id'] loop
      if exists (select 1 from pg_attribute where attrelid = to_regclass(t) and attname = c and not attisdropped and atttypid = 'uuid'::regtype)
         and not (c = 'id' and t in ('console.customer_members')) then
        execute format('select coalesce(array_agg(%I), ''{}'') from %s', c, t) into more;
        ids := ids || more;
      end if;
    end loop;
    if exists (select 1 from pg_attribute where attrelid = to_regclass(t) and attname = 'email' and not attisdropped) then
      execute format('select coalesce(array_agg(lower(email::text)), ''{}'') from %s', t) into m;
      mails := mails || m;
    end if;
  end loop;
  return query select u.id, u.email::text from auth.users u
    where not (u.id = any(ids)) and not (lower(coalesce(u.email, '')) = any(mails));
end $fn$;

-- ---------- demo: Operations Master sample for one customer ----------
create or replace function console.ops_demo_load(p_customer uuid) returns integer
language plpgsql security definer set search_path = console, public as $fn$
declare r jsonb; n integer := 0; k integer;
begin
  for r in select * from jsonb_array_elements(console.ops_sample()) loop
    insert into console.ops_records (customer_id, kind, code, name, data, active, sample, updated_by)
    values (p_customer, r ->> 'kind', r ->> 'code', coalesce(r ->> 'name', ''), console.ops_sample_dates(r -> 'data'), true, true, 'KMR demo data')
    on conflict (customer_id, kind, code) do nothing;
    get diagnostics k = row_count; n := n + k;
  end loop;
  return n;
end $fn$;

revoke all on function console.settings_tables(), console.settings_export(), console.upsert_rows(text, jsonb), console.settings_import(jsonb),
  console.full_export(), console.platform_flush(text[], text), console.orphan_logins(), console.ops_demo_load(uuid) from public, anon, authenticated;
grant execute on function console.settings_tables(), console.settings_export(), console.upsert_rows(text, jsonb), console.settings_import(jsonb),
  console.full_export(), console.platform_flush(text[], text), console.orphan_logins(), console.ops_demo_load(uuid) to service_role;

-- ---------- delete one HRM company / one app workspace (used to remove the demo) ----------
create or replace function console.hrm_delete_company(p_tenant uuid) returns boolean
language plpgsql security definer set search_path = console, public as $fn$
declare r record; n integer;
begin
  for r in select t.tgrelid::regclass::text rel, t.tgname from pg_trigger t join pg_proc p on p.oid = t.tgfoid
            where p.proname = 'audit_row' and p.pronamespace = 'hrm'::regnamespace and not t.tgisinternal loop
    execute format('alter table %s disable trigger %I', r.rel, r.tgname);
  end loop;
  delete from hrm.tenants where id = p_tenant; get diagnostics n = row_count;
  for r in select t.tgrelid::regclass::text rel, t.tgname from pg_trigger t join pg_proc p on p.oid = t.tgfoid
            where p.proname = 'audit_row' and p.pronamespace = 'hrm'::regnamespace and not t.tgisinternal loop
    execute format('alter table %s enable trigger %I', r.rel, r.tgname);
  end loop;
  return n > 0;
end $fn$;

create or replace function console.workspace_delete(p_product text, p_id uuid) returns boolean
language plpgsql security definer set search_path = console, public as $fn$
declare pre text := case p_product when 'balloon' then 'bi' when 'pd' then 'pd' when 'capacity' then 'cp' end; r record; n integer;
begin
  if pre is null then raise exception 'Unknown product %', p_product; end if;
  perform console.app_triggers(pre, false);
  for r in select c.relname from pg_class c join pg_namespace s on s.oid = c.relnamespace join pg_attribute a on a.attrelid = c.oid
            where s.nspname = 'public' and c.relkind = 'r' and c.relname like pre || '\_%' and c.relname <> pre || '_orgs'
              and a.attname = 'org_id' and not a.attisdropped loop
    execute format('delete from public.%I where org_id = $1', r.relname) using p_id;
  end loop;
  execute format('delete from public.%I where id = $1', pre || '_orgs') using p_id;
  get diagnostics n = row_count;
  perform console.app_triggers(pre, true);
  return n > 0;
end $fn$;
revoke all on function console.app_triggers(text, boolean), console.hrm_delete_company(uuid), console.workspace_delete(text, uuid) from public, anon, authenticated;
grant execute on function console.app_triggers(text, boolean), console.hrm_delete_company(uuid), console.workspace_delete(text, uuid) to service_role;
