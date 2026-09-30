-- =====================================================================
-- KMR Apps › Data Master (company administrators): per app — record counts, JSON download, JSON upload (restore),
-- and Flush all data (the portal downloads a JSON backup first). Needs 0025 (and HRM 0005). Safe to re-run.
-- Apps: hrm · balloon · pd · capacity · ops (Operations Master). Logins, users and access are never removed;
-- Balloon Inspector drawing files are kept so a restore brings reports back complete.
-- =====================================================================
do $$ begin
  if to_regprocedure('public.kmr_ops_sample_load(text,text)') is null then raise exception 'Run 0025_ops_sample_per_list.sql first.'; end if;
end $$;

-- the customer and the app's workspace, for a company administrator only
create or replace function console.data_target(p_slug text, p_app text, out cid uuid, out ref uuid)
language plpgsql stable security definer set search_path = console, public as $$
begin
  select c.id into cid from console.customers c where c.slug = lower(p_slug);
  if cid is null or not console.is_customer_admin(cid) then raise exception 'Only your company administrator can manage app data.'; end if;
  if p_app = 'ops' then ref := cid; return; end if;
  if p_app not in ('hrm','balloon','pd','capacity') then raise exception 'Unknown app %', p_app; end if;
  select l.product_ref into ref from console.licences l where l.customer_id = cid and l.product_code = p_app and l.product_ref is not null limit 1;
  if ref is null then raise exception 'Your company does not have this app yet.'; end if;
end $$;

-- data tables of a tool workspace (everything with org_id except the workspace, its users and platform admins)
create or replace function console.data_tables(p_app text) returns text[]
language sql stable security definer set search_path = console, public as $$
  select coalesce(array_agg(c.relname::text order by c.relname), '{}')
    from pg_class c join pg_namespace s on s.oid = c.relnamespace
   where s.nspname = 'public' and c.relkind = 'r'
     and c.relname like (case p_app when 'balloon' then 'bi' when 'pd' then 'pd' when 'capacity' then 'cp' end) || '\_%'
     and c.relname !~ '_(orgs|members|platform_admins)$'
     and exists (select 1 from pg_attribute a where a.attrelid = c.oid and a.attname = 'org_id' and not a.attisdropped)
$$;

-- ---------- HRM: remove a company's data (logins and the company itself stay) ----------
create or replace function hrm.company_flush(p_tenant uuid, p_setup boolean default false) returns jsonb
language plpgsql security definer set search_path = hrm, public as $fn$
declare n int; emps int;
begin
  select count(*) into emps from hrm.employees where tenant_id = p_tenant;
  if to_regclass('hrm.loan_recoveries') is not null then
    delete from hrm.loan_recoveries where tenant_id = p_tenant; delete from hrm.payroll_lines where tenant_id = p_tenant;
    delete from hrm.payroll_runs where tenant_id = p_tenant; delete from hrm.loans where tenant_id = p_tenant;
    delete from hrm.salary_structures where tenant_id = p_tenant;
  end if;
  delete from hrm.leave_ledger where tenant_id = p_tenant;
  delete from hrm.leave_requests where tenant_id = p_tenant;
  delete from hrm.regularisation_requests where tenant_id = p_tenant;
  delete from hrm.attendance_days where tenant_id = p_tenant;
  delete from hrm.attendance_punches where tenant_id = p_tenant;
  delete from hrm.id_cards where tenant_id = p_tenant;
  delete from hrm.employee_documents where tenant_id = p_tenant;
  delete from hrm.onboarding_invites where tenant_id = p_tenant;
  delete from hrm.app_users where tenant_id = p_tenant and role = 'employee';
  update hrm.app_users set employee_id = null where tenant_id = p_tenant;
  update hrm.employees set reporting_manager_id = null where tenant_id = p_tenant;
  delete from hrm.employee_private where tenant_id = p_tenant;
  delete from hrm.employees where tenant_id = p_tenant;
  if p_setup then
    delete from hrm.attendance_devices where tenant_id = p_tenant;
    delete from hrm.notification_templates where tenant_id = p_tenant;
    delete from hrm.leave_types where tenant_id = p_tenant;
    delete from hrm.holidays where tenant_id = p_tenant;
    delete from hrm.shifts where tenant_id = p_tenant;
    delete from hrm.designations where tenant_id = p_tenant;
    delete from hrm.departments where tenant_id = p_tenant;
    delete from hrm.plants where tenant_id = p_tenant;
    if to_regclass('hrm.pay_components') is not null then
      delete from hrm.pay_components where tenant_id = p_tenant; delete from hrm.pay_settings where tenant_id = p_tenant;
    end if;
    perform hrm.seed_tenant_defaults(p_tenant);
    if to_regprocedure('hrm.seed_payroll_defaults(uuid)') is not null then perform hrm.seed_payroll_defaults(p_tenant); end if;
  end if;
  update hrm.tenants set emp_code_seq = 0 where id = p_tenant;
  delete from hrm.notifications where tenant_id = p_tenant;
  delete from hrm.audit_log where tenant_id = p_tenant;
  return jsonb_build_object('employees', emps, 'setup_reset', p_setup);
end $fn$;
revoke all on function hrm.company_flush(uuid, boolean) from public, anon, authenticated;

-- ---------- overview: what each app holds ----------
create or replace function public.kmr_data_overview(p_slug text) returns jsonb
language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid; l record; out jsonb := '[]'::jsonb; t text; n bigint; det jsonb; tot bigint;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or not console.is_customer_admin(cid) then raise exception 'Only your company administrator can manage app data.'; end if;
  for l in select product_code, product_ref from console.licences where customer_id = cid and product_ref is not null
             and product_code in ('hrm','balloon','pd','capacity') order by array_position(array['hrm','balloon','pd','capacity'], product_code) loop
    det := '{}'; tot := 0;
    if l.product_code = 'hrm' then
      foreach t in array array['employees','attendance_days','leave_requests','payroll_runs','loans','id_cards','onboarding_invites'] loop
        if to_regclass('hrm.' || t) is null then continue; end if;
        execute format('select count(*) from hrm.%I where tenant_id = $1', t) into n using l.product_ref;
        det := det || jsonb_build_object(t, n); tot := tot + n;
      end loop;
    else
      foreach t in array console.data_tables(l.product_code) loop
        execute format('select count(*) from public.%I where org_id = $1', t) into n using l.product_ref;
        det := det || jsonb_build_object(t, n); tot := tot + n;
      end loop;
    end if;
    out := out || jsonb_build_array(jsonb_build_object('app', l.product_code, 'records', tot, 'detail', det));
  end loop;
  select count(*) into n from console.ops_records where customer_id = cid;
  out := out || jsonb_build_array(jsonb_build_object('app', 'ops', 'records', n, 'detail', jsonb_build_object('ops_records', n)));
  return out;
end $$;
grant execute on function public.kmr_data_overview(text) to authenticated;

-- ---------- JSON download ----------
create or replace function public.kmr_data_export(p_slug text, p_app text) returns jsonb
language plpgsql stable security definer set search_path = console, public as $$
declare tg record; t text; rows jsonb; tabs jsonb := '{}';
begin
  select * into tg from console.data_target(p_slug, p_app);
  if p_app = 'hrm' then
    tabs := jsonb_build_object('hrm', hrm.company_export(tg.ref));
  elsif p_app = 'ops' then
    select coalesce(jsonb_agg(to_jsonb(r) - 'customer_id' order by r.kind, r.code), '[]') into rows from console.ops_records r where r.customer_id = tg.cid;
    tabs := jsonb_build_object('ops_records', rows);
  else
    foreach t in array console.data_tables(p_app) loop
      execute format('select coalesce(jsonb_agg(to_jsonb(x)), ''[]'') from public.%I x where x.org_id = $1', t) into rows using tg.ref;
      tabs := tabs || jsonb_build_object(t, rows);
    end loop;
  end if;
  return jsonb_build_object('format', 'kmr-app-data', 'version', 1, 'app', p_app, 'company', lower(p_slug), 'exported_at', now(), 'tables', tabs);
end $$;
grant execute on function public.kmr_data_export(text, text) to authenticated;

-- ---------- flush ----------
create or replace function console.data_clear(p_app text, p_cid uuid, p_ref uuid) returns bigint
language plpgsql security definer set search_path = console, public as $$
declare t text; n bigint := 0; k bigint; pass int; left_ text[];
begin
  if p_app = 'ops' then
    delete from console.ops_records where customer_id = p_cid; get diagnostics n = row_count; return n;
  end if;
  if p_app = 'balloon' and to_regclass('public.pd_projects') is not null
     and exists (select 1 from pg_attribute where attrelid = 'public.pd_projects'::regclass and attname = 'bi_report_id' and not attisdropped) then
    execute 'update public.pd_projects set bi_report_id = null where bi_report_id in (select id from public.bi_reports where org_id = $1)' using p_ref;
  end if;
  perform console.app_triggers(case p_app when 'balloon' then 'bi' when 'pd' then 'pd' else 'cp' end, false);
  left_ := console.data_tables(p_app);
  for pass in 1..4 loop                                   -- a few passes, so tables that point at each other clear in any order
    exit when cardinality(left_) = 0;
    foreach t in array left_ loop
      begin
        execute format('delete from public.%I where org_id = $1', t) using p_ref; get diagnostics k = row_count; n := n + k;
        left_ := array_remove(left_, t);
      exception when foreign_key_violation then null;
      end;
    end loop;
  end loop;
  perform console.app_triggers(case p_app when 'balloon' then 'bi' when 'pd' then 'pd' else 'cp' end, true);
  if cardinality(left_) > 0 then raise exception 'Could not clear: % (linked records elsewhere).', array_to_string(left_, ', '); end if;
  return n;
end $$;
revoke all on function console.data_clear(text, uuid, uuid) from public, anon, authenticated;

create or replace function public.kmr_data_flush(p_slug text, p_app text, p_hrm_setup boolean default false) returns jsonb
language plpgsql security definer set search_path = console, public as $$
declare tg record;
begin
  select * into tg from console.data_target(p_slug, p_app);
  if p_app = 'hrm' then return hrm.company_flush(tg.ref, coalesce(p_hrm_setup, false)); end if;
  return jsonb_build_object('removed', console.data_clear(p_app, tg.cid, tg.ref));
end $$;
grant execute on function public.kmr_data_flush(text, text, boolean) to authenticated;

-- ---------- JSON upload (restore): replaces this app's data with the file's ----------
create or replace function public.kmr_data_import(p_slug text, p_app text, p_data jsonb) returns jsonb
language plpgsql security definer set search_path = console, public as $$
declare tg record; t text; rows jsonb; n bigint; k bigint; tot bigint := 0; pass int; todo text[]; ok text[] := '{}';
begin
  select * into tg from console.data_target(p_slug, p_app);
  if p_data ->> 'format' is distinct from 'kmr-app-data' then raise exception 'This is not a KMR Data Master file.'; end if;
  if p_data ->> 'app' is distinct from p_app then raise exception 'This file is a backup of another app (%).', p_data ->> 'app'; end if;
  if p_app = 'hrm' then
    -- the HRM restore checks the backup belongs to this very company
    return jsonb_build_object('restored', hrm.company_import(tg.ref, p_data -> 'tables' -> 'hrm'));
  end if;
  perform console.data_clear(p_app, tg.cid, tg.ref);
  if p_app = 'ops' then
    rows := (select coalesce(jsonb_agg(r || jsonb_build_object('customer_id', tg.cid)), '[]') from jsonb_array_elements(coalesce(p_data -> 'tables' -> 'ops_records', '[]')) r);
    insert into console.ops_records select * from jsonb_populate_recordset(null::console.ops_records, rows) on conflict do nothing;
    get diagnostics n = row_count;
    return jsonb_build_object('restored', n);
  end if;
  perform console.app_triggers(case p_app when 'balloon' then 'bi' when 'pd' then 'pd' else 'cp' end, false);
  todo := array(select x from unnest(console.data_tables(p_app)) x where (p_data -> 'tables') ? x);
  for pass in 1..4 loop
    exit when cardinality(todo) = 0;
    foreach t in array todo loop
      -- every row is put back into THIS company's workspace, whatever the file says
      rows := (select coalesce(jsonb_agg(r || jsonb_build_object('org_id', tg.ref)), '[]') from jsonb_array_elements(p_data -> 'tables' -> t) r);
      begin
        execute format('insert into public.%I select * from jsonb_populate_recordset(null::public.%I, $1) on conflict do nothing', t, t) using rows;
        get diagnostics k = row_count; tot := tot + k; todo := array_remove(todo, t);
      exception when foreign_key_violation then null;
      end;
    end loop;
  end loop;
  perform console.app_triggers(case p_app when 'balloon' then 'bi' when 'pd' then 'pd' else 'cp' end, true);
  if cardinality(todo) > 0 then raise exception 'Could not restore: %.', array_to_string(todo, ', '); end if;
  return jsonb_build_object('restored', tot);
end $$;
grant execute on function public.kmr_data_import(text, text, jsonb) to authenticated;

revoke all on function console.data_target(text, text), console.data_tables(text) from public, anon, authenticated;
