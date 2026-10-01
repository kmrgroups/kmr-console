-- =====================================================================
-- Grand Master (KMR Apps › Masters › Grand Master, company administrators): three cards
--   1. Real Data     — every app's real data (not sample): one JSON download, upload (restore), flush (backup first)
--   2. Sample Data   — every app's sample data: load all, flush all
--   3. Administration — company details & logo, users & access, invoices & payments: download, upload, flush
-- Invoices and payments are KMR's numbered tax records: company administrators can download them; only KMR staff can
-- flush or upload them. Logins themselves are never deleted. Needs 0028 (and HRM 0005). Safe to re-run.
-- =====================================================================
do $$ begin
  if to_regprocedure('public.kmr_balloon_own_load(text,jsonb)') is null then raise exception 'Run 0028_balloon_card_data.sql first.'; end if;
end $$;

-- the customer, for a company administrator only
create or replace function console.grand_customer(p_slug text) returns uuid
language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or not console.is_customer_admin(cid) then raise exception 'Only your company administrator can use the Grand Master.'; end if;
  return cid;
end $$;
revoke all on function console.grand_customer(text) from public, anon, authenticated;

create or replace function console.grand_ref(p_cid uuid, p_app text) returns uuid
language sql stable security definer set search_path = console, public as $$
  select product_ref from console.licences where customer_id = p_cid and product_code = p_app and product_ref is not null limit 1
$$;
revoke all on function console.grand_ref(uuid, text) from public, anon, authenticated;

-- ---------- HRM: real = every employee except the sample ones (@demo.kmr.test) ----------
create or replace function hrm.real_flush(p_tenant uuid) returns integer
language plpgsql security definer set search_path = hrm, public as $fn$
declare n int; demo uuid[];
begin
  select coalesce(array_agg(id), '{}') into demo from hrm.employees where tenant_id = p_tenant and coalesce(email, '') like '%@demo.kmr.test';
  if cardinality(demo) = 0 then return (hrm.company_flush(p_tenant, false) ->> 'employees')::int; end if;
  delete from hrm.app_users where tenant_id = p_tenant and role = 'employee' and (employee_id is null or not employee_id = any(demo));
  update hrm.app_users set employee_id = null where tenant_id = p_tenant and employee_id is not null and not employee_id = any(demo);
  update hrm.employees set reporting_manager_id = null where tenant_id = p_tenant and reporting_manager_id is not null and not reporting_manager_id = any(demo);
  delete from hrm.attendance_punches where tenant_id = p_tenant and (employee_id is null or not employee_id = any(demo));
  delete from hrm.employees where tenant_id = p_tenant and not id = any(demo);       -- their attendance, leave, payroll lines, loans … go with them
  get diagnostics n = row_count;
  if to_regclass('hrm.payroll_runs') is not null then
    delete from hrm.payroll_runs r where r.tenant_id = p_tenant and not exists (select 1 from hrm.payroll_lines l where l.run_id = r.id);
  end if;
  return n;
end $fn$;
revoke all on function hrm.real_flush(uuid) from public, anon, authenticated;

-- ---------- overview ----------
create or replace function public.kmr_grand_overview(p_slug text) returns jsonb
language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.grand_customer(p_slug); r uuid; real_ jsonb := '{}'; smp jsonb := '{}'; t text; n bigint; k bigint; c console.customers%rowtype;
begin
  r := console.grand_ref(cid, 'hrm');
  if r is not null then
    select count(*) filter (where coalesce(email, '') not like '%@demo.kmr.test'), count(*) filter (where coalesce(email, '') like '%@demo.kmr.test')
      into n, k from hrm.employees where tenant_id = r;
    real_ := real_ || jsonb_build_object('hrm', n); smp := smp || jsonb_build_object('hrm', k);
  end if;
  r := console.grand_ref(cid, 'balloon');
  if r is not null and to_regclass('public.bi_reports') is not null then
    execute 'select count(*) filter (where coalesce(file_path, '''') not like ''static:%''), count(*) filter (where file_path like ''static:%'') from public.bi_reports where org_id = $1'
      into n, k using r;
    real_ := real_ || jsonb_build_object('balloon', n); smp := smp || jsonb_build_object('balloon', k);
  end if;
  foreach t in array array['pd','capacity'] loop
    r := console.grand_ref(cid, t);
    if r is null then continue; end if;
    n := 0;
    declare tb text; m bigint; begin
      foreach tb in array console.data_tables(t) loop
        execute format('select count(*) from public.%I where org_id = $1', tb) into m using r; n := n + m;
      end loop;
    end;
    real_ := real_ || jsonb_build_object(t, n);
  end loop;
  select count(*) filter (where not sample), count(*) filter (where sample) into n, k from console.ops_records where customer_id = cid;
  real_ := real_ || jsonb_build_object('ops', n); smp := smp || jsonb_build_object('ops', k);
  select * into c from console.customers where id = cid;
  return jsonb_build_object('real', real_, 'sample', smp, 'staff', console.is_staff(),
    'admin', jsonb_build_object(
      'company', c.name, 'logo', coalesce(c.logo_url, '') <> '',
      'details', (select count(*) from unnest(array[c.legal_name, c.tax_id, c.address, c.city, c.state, c.postal_code, c.contact_phone]) v where coalesce(v, '') <> ''),
      'users', (select count(*) from console.customer_members where customer_id = cid),
      'invoices', (select count(*) from console.invoices where customer_id = cid),
      'payments', (select count(*) from console.payments p join console.invoices i on i.id = p.invoice_id where i.customer_id = cid)));
end $$;
revoke all on function public.kmr_grand_overview(text) from public, anon;
grant execute on function public.kmr_grand_overview(text) to authenticated;

-- ---------- 1. Real data ----------
create or replace function public.kmr_grand_real_export(p_slug text) returns jsonb
language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.grand_customer(p_slug); apps jsonb := '{}'; t text;
begin
  foreach t in array array['hrm','pd','capacity'] loop
    if console.grand_ref(cid, t) is not null then apps := apps || jsonb_build_object(t, public.kmr_data_export(p_slug, t)); end if;
  end loop;
  if console.grand_ref(cid, 'balloon') is not null and to_regclass('public.bi_reports') is not null then
    apps := apps || jsonb_build_object('balloon', public.kmr_balloon_own_export(p_slug));
  end if;
  apps := apps || jsonb_build_object('ops', jsonb_build_object('format', 'kmr-ops-own', 'records',
    coalesce((select jsonb_agg(jsonb_build_object('kind', r.kind, 'code', r.code, 'name', r.name, 'data', r.data, 'active', r.active) order by r.kind, r.code)
                from console.ops_records r where r.customer_id = cid and not r.sample), '[]')));
  return jsonb_build_object('format', 'kmr-real-data', 'version', 1, 'company', lower(p_slug), 'exported_at', now(), 'apps', apps);
end $$;
revoke all on function public.kmr_grand_real_export(text) from public, anon;
grant execute on function public.kmr_grand_real_export(text) to authenticated;

create or replace function public.kmr_grand_real_flush(p_slug text) returns jsonb
language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.grand_customer(p_slug); out jsonb := '{}'; r uuid; t text; n int;
begin
  r := console.grand_ref(cid, 'hrm');
  if r is not null then out := out || jsonb_build_object('hrm', hrm.real_flush(r)); end if;
  if console.grand_ref(cid, 'balloon') is not null and to_regclass('public.bi_reports') is not null then
    out := out || jsonb_build_object('balloon', public.kmr_balloon_own_flush(p_slug));
  end if;
  foreach t in array array['pd','capacity'] loop
    r := console.grand_ref(cid, t);
    if r is not null then out := out || jsonb_build_object(t, console.data_clear(t, cid, r)); end if;
  end loop;
  delete from console.ops_records where customer_id = cid and not sample; get diagnostics n = row_count;
  return out || jsonb_build_object('ops', n);
end $$;
revoke all on function public.kmr_grand_real_flush(text) from public, anon;
grant execute on function public.kmr_grand_real_flush(text) to authenticated;

-- puts every app in the file back as it was in the backup (all in one go: if one app fails, nothing changes)
create or replace function public.kmr_grand_real_import(p_slug text, p_data jsonb) returns jsonb
language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.grand_customer(p_slug); out jsonb := '{}'; t text; a jsonb; n int; me text := lower(coalesce(auth.jwt() ->> 'email', ''));
begin
  if p_data ->> 'format' is distinct from 'kmr-real-data' then raise exception 'This is not a Grand Master real-data file.'; end if;
  if lower(coalesce(p_data ->> 'company', '')) <> lower(p_slug) then
    raise exception 'This file is a backup of another company (%).', p_data ->> 'company';
  end if;
  foreach t in array array['hrm','pd','capacity'] loop
    a := p_data -> 'apps' -> t;
    if a is null or console.grand_ref(cid, t) is null then continue; end if;
    out := out || jsonb_build_object(t, public.kmr_data_import(p_slug, t, a) -> 'restored');
  end loop;
  a := p_data -> 'apps' -> 'balloon';
  if a is not null and console.grand_ref(cid, 'balloon') is not null then
    perform public.kmr_balloon_own_flush(p_slug);
    if jsonb_array_length(coalesce(a -> 'tables' -> 'bi_reports', '[]')) > 0 then
      out := out || jsonb_build_object('balloon', public.kmr_balloon_own_load(p_slug, a));
    else out := out || jsonb_build_object('balloon', 0); end if;
  end if;
  a := p_data -> 'apps' -> 'ops';
  if a is not null then
    delete from console.ops_records where customer_id = cid and not sample;
    insert into console.ops_records (customer_id, kind, code, name, data, active, sample, updated_by)
    select cid, x ->> 'kind', x ->> 'code', coalesce(x ->> 'name', x ->> 'code'), coalesce(x -> 'data', '{}'), coalesce((x ->> 'active')::boolean, true), false, me
      from jsonb_array_elements(coalesce(a -> 'records', '[]')) x
     where coalesce(x ->> 'kind', '') <> '' and coalesce(x ->> 'code', '') <> ''
    on conflict (customer_id, kind, code) do update set name = excluded.name, data = excluded.data, active = excluded.active, sample = false, updated_by = me;
    get diagnostics n = row_count; out := out || jsonb_build_object('ops', n);
  end if;
  return out;
end $$;
revoke all on function public.kmr_grand_real_import(text, jsonb) from public, anon;
grant execute on function public.kmr_grand_real_import(text, jsonb) to authenticated;

-- ---------- 2. Sample data ----------
create or replace function public.kmr_grand_sample(p_slug text, p_action text) returns jsonb
language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.grand_customer(p_slug); out jsonb := '{}'; r uuid; n int;
begin
  if p_action not in ('load','flush') then raise exception 'Unknown action.'; end if;
  r := console.grand_ref(cid, 'hrm');
  if r is not null then
    if p_action = 'load' then
      if exists (select 1 from hrm.employees where tenant_id = r and email like '%@demo.kmr.test') then n := 0;
      else n := hrm.demo_load(r); perform hrm.demo_payroll(r); end if;
    else n := hrm.demo_flush(r); end if;
    out := out || jsonb_build_object('hrm', n, 'hrm_tenant', r);
  end if;
  if console.grand_ref(cid, 'balloon') is not null and to_regclass('public.bi_reports') is not null then
    out := out || jsonb_build_object('balloon', public.kmr_ops_sample_drawing(p_slug, p_action));
  end if;
  if p_action = 'load' then out := out || jsonb_build_object('ops', (public.kmr_ops_sample_load(p_slug) ->> 'added')::int);
  else out := out || jsonb_build_object('ops', public.kmr_ops_sample_flush(p_slug)); end if;
  return out;
end $$;
revoke all on function public.kmr_grand_sample(text, text) from public, anon;
grant execute on function public.kmr_grand_sample(text, text) to authenticated;

-- the HRM company of a customer, for the HRM app to finish the sample attendance (company administrators only)
create or replace function public.kmr_grand_hrm_tenant(p_slug text) returns uuid
language sql stable security definer set search_path = console, public as $$
  select console.grand_ref(console.grand_customer(p_slug), 'hrm')
$$;
revoke all on function public.kmr_grand_hrm_tenant(text) from public, anon;
grant execute on function public.kmr_grand_hrm_tenant(text) to authenticated;

-- ---------- 3. Administration data ----------
create or replace function public.kmr_grand_admin_export(p_slug text) returns jsonb
language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.grand_customer(p_slug); c console.customers%rowtype;
begin
  select * into c from console.customers where id = cid;
  return jsonb_build_object('format', 'kmr-admin-data', 'version', 1, 'company', lower(p_slug), 'exported_at', now(),
    'company_details', jsonb_build_object('name', c.name, 'legal_name', c.legal_name, 'tax_id', c.tax_id, 'address', c.address, 'city', c.city,
        'state', c.state, 'postal_code', c.postal_code, 'country', c.country, 'contact_name', c.contact_name, 'contact_email', c.contact_email,
        'contact_phone', c.contact_phone, 'logo_url', c.logo_url),
    'users', coalesce((select jsonb_agg(jsonb_build_object('email', m.email, 'full_name', m.full_name, 'is_admin', m.is_admin, 'roles', m.roles,
        'login_owned', m.login_owned) order by m.email) from console.customer_members m where m.customer_id = cid), '[]'),
    'invoices', coalesce((select jsonb_agg(to_jsonb(i) || jsonb_build_object(
        'lines', coalesce((select jsonb_agg(to_jsonb(l) - 'id' order by l.sort) from console.invoice_lines l where l.invoice_id = i.id), '[]'),
        'payments', coalesce((select jsonb_agg(to_jsonb(p)) from console.payments p where p.invoice_id = i.id), '[]')) order by i.created_at)
      from console.invoices i where i.customer_id = cid), '[]'));
end $$;
revoke all on function public.kmr_grand_admin_export(text) from public, anon;
grant execute on function public.kmr_grand_admin_export(text) to authenticated;

-- tools show the company logo too: clear it there when the company's logo is flushed
create or replace function console.grand_clear_logos(p_cid uuid) returns void
language plpgsql security definer set search_path = console, public as $$
declare l record;
begin
  for l in select product_code, product_ref from console.licences where customer_id = p_cid and product_ref is not null loop
    if l.product_code = 'balloon' and exists (select 1 from pg_attribute where attrelid = 'public.bi_orgs'::regclass and attname = 'logo' and not attisdropped) then
      execute 'update public.bi_orgs set logo = null where id = $1' using l.product_ref;
    elsif l.product_code = 'pd' and exists (select 1 from pg_attribute where attrelid = 'public.pd_orgs'::regclass and attname = 'logo' and not attisdropped) then
      execute 'update public.pd_orgs set logo = null where id = $1' using l.product_ref;
    elsif l.product_code = 'capacity' then
      execute 'update public.cp_orgs set settings = coalesce(settings, ''{}''::jsonb) - ''logo'' where id = $1' using l.product_ref;
    elsif l.product_code = 'hrm' then update hrm.tenants set logo_path = null where id = l.product_ref;
    end if;
  end loop;
end $$;
revoke all on function console.grand_clear_logos(uuid) from public, anon, authenticated;

-- p_parts: any of 'company', 'users', 'invoices'
create or replace function public.kmr_grand_admin_flush(p_slug text, p_parts text[]) returns jsonb
language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.grand_customer(p_slug); out jsonb := '{}'; me text := lower(coalesce(auth.jwt() ->> 'email', '')); m record; n int := 0;
begin
  if 'invoices' = any(p_parts) and not console.is_staff() then
    raise exception 'Invoices and payments are KMR''s tax records: only KMR staff can flush them. You can download them.';
  end if;
  if 'company' = any(p_parts) then
    update console.customers set legal_name = null, tax_id = null, address = null, city = null, state = null, postal_code = null,
           contact_phone = null, logo_url = null, updated_at = now() where id = cid;
    perform console.grand_clear_logos(cid);
    out := out || jsonb_build_object('company', true);
  end if;
  if 'users' = any(p_parts) then
    -- everyone except you and the company's main contact; their access in every app goes too (logins stay)
    for m in select email from console.customer_members where customer_id = cid and email <> me
               and email <> (select lower(coalesce(contact_email, '')) from console.customers where id = cid) loop
      delete from console.customer_members where customer_id = cid and email = m.email;
      perform console.sync_member(cid, m.email);
      n := n + 1;
    end loop;
    out := out || jsonb_build_object('users', n);
  end if;
  if 'invoices' = any(p_parts) then
    delete from console.payments where invoice_id in (select id from console.invoices where customer_id = cid); get diagnostics n = row_count;
    out := out || jsonb_build_object('payments', n);
    delete from console.invoices where customer_id = cid; get diagnostics n = row_count;
    out := out || jsonb_build_object('invoices', n);
  end if;
  return out;
end $$;
revoke all on function public.kmr_grand_admin_flush(text, text[]) from public, anon;
grant execute on function public.kmr_grand_admin_flush(text, text[]) to authenticated;

create or replace function public.kmr_grand_admin_import(p_slug text, p_data jsonb) returns jsonb
language plpgsql security definer set search_path = console, public, auth as $$
declare cid uuid := console.grand_customer(p_slug); out jsonb := '{}'; d jsonb; u jsonb; i jsonb; n int := 0; ni int := 0; np int := 0;
  me text := lower(coalesce(auth.jwt() ->> 'email', '')); em text; skipped int := 0;
begin
  if p_data ->> 'format' is distinct from 'kmr-admin-data' then raise exception 'This is not a Grand Master administration file.'; end if;
  if lower(coalesce(p_data ->> 'company', '')) <> lower(p_slug) then raise exception 'This file is a backup of another company (%).', p_data ->> 'company'; end if;
  d := p_data -> 'company_details';
  if d is not null then
    update console.customers set
      name = coalesce(nullif(trim(d ->> 'name'), ''), name), legal_name = nullif(d ->> 'legal_name', ''), tax_id = nullif(d ->> 'tax_id', ''),
      address = nullif(d ->> 'address', ''), city = nullif(d ->> 'city', ''), state = nullif(d ->> 'state', ''),
      postal_code = nullif(d ->> 'postal_code', ''), contact_phone = nullif(d ->> 'contact_phone', ''), logo_url = nullif(d ->> 'logo_url', ''),
      updated_at = now() where id = cid;
    out := out || jsonb_build_object('company', true);
  end if;
  for u in select * from jsonb_array_elements(coalesce(p_data -> 'users', '[]')) loop
    em := lower(trim(coalesce(u ->> 'email', '')));
    continue when em !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$';
    if em = me then continue; end if;                                   -- your own rights are never changed by a file
    insert into console.customer_members (customer_id, email, full_name, is_admin, roles, login_owned, created_by)
    values (cid, em, nullif(u ->> 'full_name', ''), coalesce((u ->> 'is_admin')::boolean, false), coalesce(u -> 'roles', '{}'),
            coalesce((u ->> 'login_owned')::boolean, false), me)
    on conflict (customer_id, email) do update set full_name = excluded.full_name, is_admin = excluded.is_admin, roles = excluded.roles, updated_at = now();
    begin
      perform console.sync_member(cid, em);
    exception when others then skipped := skipped + 1;                -- e.g. that login already uses another company's HRM
    end;
    n := n + 1;
  end loop;
  out := out || jsonb_build_object('users', n, 'users_partly', skipped);
  if jsonb_array_length(coalesce(p_data -> 'invoices', '[]')) > 0 then
    if not console.is_staff() then
      out := out || jsonb_build_object('invoices_skipped', true);
    else
      for i in select * from jsonb_array_elements(p_data -> 'invoices') loop
        continue when exists (select 1 from console.invoices where id = (i ->> 'id')::uuid or number = i ->> 'number');
        insert into console.invoices select * from jsonb_populate_record(null::console.invoices, (i - 'lines' - 'payments') || jsonb_build_object('customer_id', cid));
        insert into console.invoice_lines (invoice_id, sort, product_code, description, period_from, period_to, qty, unit_amount, amount)
        select (i ->> 'id')::uuid, l.sort, l.product_code, l.description, l.period_from, l.period_to, l.qty, l.unit_amount, l.amount
          from jsonb_populate_recordset(null::console.invoice_lines, coalesce(i -> 'lines', '[]')) l;
        insert into console.payments select * from jsonb_populate_recordset(null::console.payments, coalesce(i -> 'payments', '[]')) on conflict do nothing;
        get diagnostics n = row_count; np := np + n; ni := ni + 1;
      end loop;
      out := out || jsonb_build_object('invoices', ni, 'payments', np);
    end if;
  end if;
  return out;
end $$;
revoke all on function public.kmr_grand_admin_import(text, jsonb) from public, anon;
grant execute on function public.kmr_grand_admin_import(text, jsonb) to authenticated;
