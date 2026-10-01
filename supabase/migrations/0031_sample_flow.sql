-- =====================================================================
-- Console 0031 — the sample data runs through the whole HRM flow. Run after HRM 0007_sample_flow.sql.
--  • Grand Master › Sample Data Master › Load sample data now also loads the sample hiring flow (openings, scored
--    candidates at every stage, interviews, scorecards, offers and the new joiner). Pressing it again on a company that
--    already has the sample employees adds whatever sample parts are missing.
--  • Real-data flushes keep the sample hiring flow; the sample flush removes it (HRM 0007 › hrm.demo_flush).
--  • The Data Master's full HRM flush still clears everything, sample included.
-- Safe to re-run.
-- =====================================================================

-- recruitment data of a company; p_keep_sample keeps the sample openings, candidates and job descriptions
drop function if exists hrm.recruit_flush(uuid);
create or replace function hrm.recruit_flush(p_tenant uuid, p_keep_sample boolean default false) returns integer
language plpgsql security definer set search_path = hrm, public as $fn$
declare t text; n int := 0; k int; smp boolean := p_keep_sample
  and exists (select 1 from information_schema.columns where table_schema = 'hrm' and table_name = 'requisitions' and column_name = 'sample');
begin
  if smp then
    -- real openings (with every application to them) and real candidates (with their applications to sample openings)
    delete from hrm.requisitions where tenant_id = p_tenant and not sample; get diagnostics k = row_count; n := n + k;
    delete from hrm.candidates where tenant_id = p_tenant and not sample;   get diagnostics k = row_count; n := n + k;
    delete from hrm.job_descriptions j where j.tenant_id = p_tenant and not j.sample
       and not exists (select 1 from hrm.requisitions r where r.jd_id = j.id); get diagnostics k = row_count; n := n + k;
    return n;
  end if;
  foreach t in array array['offers','interview_feedback','interviews','applications','candidates','requisitions','job_descriptions'] loop
    if to_regclass('hrm.' || t) is null then continue; end if;
    execute format('delete from hrm.%I where tenant_id = $1', t) using p_tenant;
    get diagnostics k = row_count; n := n + k;
  end loop;
  return n;
end $fn$;
revoke all on function hrm.recruit_flush(uuid, boolean) from public, anon, authenticated;

-- ---------- real-data flush (Grand Master): the sample hiring flow and the sample employees stay ----------
create or replace function hrm.real_flush(p_tenant uuid) returns integer
language plpgsql security definer set search_path = hrm, public as $fn$
declare n int; demo uuid[];
begin
  perform hrm.recruit_flush(p_tenant, true);
  select coalesce(array_agg(id), '{}') into demo from hrm.employees where tenant_id = p_tenant and coalesce(email, '') like '%@demo.kmr.test';
  if cardinality(demo) = 0 then return (hrm.company_flush(p_tenant, false) ->> 'employees')::int; end if;
  delete from hrm.app_users where tenant_id = p_tenant and role = 'employee' and (employee_id is null or not employee_id = any(demo));
  update hrm.app_users set employee_id = null where tenant_id = p_tenant and employee_id is not null and not employee_id = any(demo);
  update hrm.employees set reporting_manager_id = null where tenant_id = p_tenant and reporting_manager_id is not null and not reporting_manager_id = any(demo);
  if to_regclass('hrm.offers') is not null then
    update hrm.offers set reporting_manager_id = null where tenant_id = p_tenant and reporting_manager_id is not null and not reporting_manager_id = any(demo);
  end if;
  delete from hrm.attendance_punches where tenant_id = p_tenant and (employee_id is null or not employee_id = any(demo));
  delete from hrm.employees where tenant_id = p_tenant and not id = any(demo);       -- their attendance, leave, payroll lines, loans … go with them
  get diagnostics n = row_count;
  if to_regclass('hrm.payroll_runs') is not null then
    delete from hrm.payroll_runs r where r.tenant_id = p_tenant and not exists (select 1 from hrm.payroll_lines l where l.run_id = r.id);
  end if;
  return n;
end $fn$;
revoke all on function hrm.real_flush(uuid) from public, anon, authenticated;

-- ---------- Sample Data Master: load fills every HRM module, not only employees ----------
create or replace function public.kmr_grand_sample(p_slug text, p_action text) returns jsonb
language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.grand_customer(p_slug); out jsonb := '{}'; r uuid; n int; k int; flow jsonb;
begin
  if p_action not in ('load','flush') then raise exception 'Unknown action.'; end if;
  r := console.grand_ref(cid, 'hrm');
  if r is not null then
    if p_action = 'load' then
      if exists (select 1 from hrm.employees where tenant_id = r and email like '%@demo.kmr.test') then n := 0;
      else n := hrm.demo_load(r); perform hrm.demo_payroll(r); end if;
      -- the rest of the HRM flow follows the sample employees (recruitment now; more modules join hrm.demo_flow)
      if to_regprocedure('hrm.demo_flow(uuid)') is not null then
        flow := hrm.demo_flow(r);
        out := out || jsonb_build_object('hrm_flow', flow);
      end if;
    else
      if exists (select 1 from information_schema.columns where table_schema = 'hrm' and table_name = 'candidates' and column_name = 'sample') then
        execute 'select count(*) from hrm.candidates where tenant_id = $1 and sample' into k using r;
        out := out || jsonb_build_object('hrm_candidates', k);
      end if;
      n := hrm.demo_flush(r);
    end if;
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

-- ---------- overview: the sample count of HRM includes the sample candidates ----------
create or replace function public.kmr_grand_overview(p_slug text) returns jsonb
language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.grand_customer(p_slug); r uuid; real_ jsonb := '{}'; smp jsonb := '{}'; t text; n bigint; k bigint; c console.customers%rowtype;
begin
  r := console.grand_ref(cid, 'hrm');
  if r is not null then
    select count(*) filter (where coalesce(email, '') not like '%@demo.kmr.test'), count(*) filter (where coalesce(email, '') like '%@demo.kmr.test')
      into n, k from hrm.employees where tenant_id = r;
    real_ := real_ || jsonb_build_object('hrm', n); smp := smp || jsonb_build_object('hrm', k);
    if exists (select 1 from information_schema.columns where table_schema = 'hrm' and table_name = 'candidates' and column_name = 'sample') then
      execute 'select count(*) filter (where not sample), count(*) filter (where sample) from hrm.candidates where tenant_id = $1' into n, k using r;
      real_ := real_ || jsonb_build_object('hrm_candidates', n); smp := smp || jsonb_build_object('hrm_candidates', k);
    end if;
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


-- ---------- real-data messages name the real candidates too, and count only real people ----------
create or replace function console.grand_hrm_real_candidates(p_tenant uuid) returns integer
language plpgsql stable security definer set search_path = hrm, public as $fn$
declare k int := 0;
begin
  if p_tenant is null or to_regclass('hrm.candidates') is null then return 0; end if;
  if exists (select 1 from information_schema.columns where table_schema = 'hrm' and table_name = 'candidates' and column_name = 'sample') then
    execute 'select count(*) from hrm.candidates where tenant_id = $1 and not sample' into k using p_tenant;
  else select count(*) into k from hrm.candidates where tenant_id = p_tenant; end if;
  return k;
end $fn$;
revoke all on function console.grand_hrm_real_candidates(uuid) from public, anon, authenticated;

create or replace function public.kmr_grand_real_flush(p_slug text) returns jsonb
language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.grand_customer(p_slug); out jsonb := '{}'; r uuid; t text; n int;
begin
  r := console.grand_ref(cid, 'hrm');
  if r is not null then
    out := out || jsonb_build_object('hrm_candidates', console.grand_hrm_real_candidates(r));
    out := out || jsonb_build_object('hrm', hrm.real_flush(r));
  end if;
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
    if t = 'hrm' then
      -- the backup also carries the sample people as they were; the message counts only the company's own
      select count(*) into n from hrm.employees where tenant_id = console.grand_ref(cid, 'hrm') and coalesce(email, '') not like '%@demo.kmr.test';
      out := out || jsonb_build_object('hrm', n, 'hrm_candidates', console.grand_hrm_real_candidates(console.grand_ref(cid, 'hrm')));
    end if;
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


notify pgrst, 'reload schema';
