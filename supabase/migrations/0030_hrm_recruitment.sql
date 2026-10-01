-- =====================================================================
-- KMR platform — HRM recruitment (HRM migration 0006) on the platform. Needs 0029. Safe to re-run, before or after HRM 0006.
--  • KMR Apps › Users & access can give the HRM role "Interviewer" (sits on interview panels, fills in scorecards)
--  • Data Master / Grand Master flushes of HRM also clear recruitment: requisitions, job descriptions, candidates,
--    applications, interviews, scorecards and offers. Resume files stay in storage, so a restore brings them back.
-- =====================================================================
do $$ begin
  if to_regprocedure('hrm.real_flush(uuid)') is null then raise exception 'Run 0029_grand_master.sql first.'; end if;
end $$;

create or replace function public.kmr_admin_save_user(p_slug text, p jsonb) returns jsonb
language plpgsql security definer set search_path = console, public, auth as $$
declare cid uuid; em text := lower(trim(coalesce(p ->> 'email', ''))); lg record; rl jsonb := '{}'; k text; v text; me text := lower(coalesce(auth.jwt() ->> 'email', ''));
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or not console.is_customer_admin(cid) then raise exception 'Only your company''s administrators can manage users.'; end if;
  if em !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'Enter a valid e-mail address.'; end if;
  for k, v in select * from jsonb_each_text(coalesce(p -> 'roles', '{}')) loop
    if v = '' then continue; end if;
    if k = 'hrm' and v not in ('company_admin','hr_manager','hr_executive','manager','payroll','interviewer') then raise exception 'Unknown HRM role %.', v; end if;
    if k <> 'hrm' and v not in ('admin','editor','viewer') then raise exception 'Unknown role % for %.', v, k; end if;
    rl := rl || jsonb_build_object(k, v);
  end loop;
  if em = me and coalesce((p ->> 'is_admin')::boolean, false) = false and console.is_customer_admin(cid) and not console.is_staff() then
    raise exception 'You cannot remove your own administrator rights.';
  end if;
  select * into lg from console.ensure_login(em, p ->> 'password', p ->> 'name');
  insert into console.customer_members (customer_id, email, full_name, is_admin, roles, login_owned, created_by)
  values (cid, em, nullif(trim(coalesce(p ->> 'name', '')), ''), coalesce((p ->> 'is_admin')::boolean, false), rl, lg.created, me)
  on conflict (customer_id, email) do update set full_name = coalesce(excluded.full_name, customer_members.full_name), is_admin = excluded.is_admin,
    roles = excluded.roles, updated_at = now();
  perform console.sync_member(cid, em);
  return jsonb_build_object('ok', true, 'new_login', lg.created);
end $$;
grant execute on function public.kmr_admin_save_user(text, jsonb) to authenticated;

-- recruitment data of a company (nothing when HRM 0006 is not installed yet)
create or replace function hrm.recruit_flush(p_tenant uuid) returns integer
language plpgsql security definer set search_path = hrm, public as $fn$
declare t text; n int := 0; k int;
begin
  foreach t in array array['offers','interview_feedback','interviews','applications','candidates','requisitions','job_descriptions'] loop
    if to_regclass('hrm.' || t) is null then continue; end if;
    execute format('delete from hrm.%I where tenant_id = $1', t) using p_tenant;
    get diagnostics k = row_count; n := n + k;
  end loop;
  return n;
end $fn$;
revoke all on function hrm.recruit_flush(uuid) from public, anon, authenticated;

-- ---------- HRM flush (Data Master) now includes recruitment ----------
create or replace function hrm.company_flush(p_tenant uuid, p_setup boolean default false) returns jsonb
language plpgsql security definer set search_path = hrm, public as $fn$
declare n int; emps int;
begin
  perform hrm.recruit_flush(p_tenant);
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

-- ---------- real-data flush (Grand Master) now includes recruitment ----------
create or replace function hrm.real_flush(p_tenant uuid) returns integer
language plpgsql security definer set search_path = hrm, public as $fn$
declare n int; demo uuid[];
begin
  perform hrm.recruit_flush(p_tenant);                 -- recruitment (requisitions, candidates, offers) is real data
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
