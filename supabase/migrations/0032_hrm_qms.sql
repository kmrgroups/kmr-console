-- =====================================================================
-- Console 0032 — HRM QMS (Phase 5A) on the platform. Run after HRM 0008_qms.sql. Safe to re-run.
--  • The Data Master's full HRM flush and Grand Master › Flush real data also clear the QMS records
--    (skill matrix, competencies, training, R&R, KPIs, OJT, auditors) through hrm.module_flush — later HRM modules
--    plug into the same function, so these flushes keep covering everything.
--  • Flush real data keeps the sample QMS records; Flush sample data removes them (HRM 0008 › hrm.demo_flush).
--  • Grand Master › Load sample data loads the sample QMS records with the rest of the HRM flow (hrm.demo_flow).
-- =====================================================================

create or replace function hrm.company_flush(p_tenant uuid, p_setup boolean default false) returns jsonb
language plpgsql security definer set search_path = hrm, public as $fn$
declare n int; emps int;
begin
  perform hrm.recruit_flush(p_tenant);
  -- QMS and every later HRM module (setup lists like the competency library stay unless the setup is reset)
  if to_regprocedure('hrm.module_flush(uuid,text)') is not null then
    if p_setup then perform hrm.module_flush(p_tenant, 'all');
    else perform hrm.module_flush(p_tenant, 'real'); perform hrm.module_flush(p_tenant, 'sample'); end if;
  end if;
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

create or replace function hrm.real_flush(p_tenant uuid) returns integer
language plpgsql security definer set search_path = hrm, public as $fn$
declare n int; demo uuid[];
begin
  perform hrm.recruit_flush(p_tenant, true);
  if to_regprocedure('hrm.module_flush(uuid,text)') is not null then perform hrm.module_flush(p_tenant, 'real'); end if;   -- QMS and later modules
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

notify pgrst, 'reload schema';
