-- HRM Suite — security hardening found in the full audit. Safe to re-run.

-- 1. Functions that take a tenant id must not be callable from the browser (anon / signed-in users).
--    The app calls them only with the service key (lib/onboarding.ts) or from triggers.
do $$ declare f text; begin
  foreach f in array array['hrm.next_employee_code(uuid, uuid)','hrm.seed_tenant_defaults(uuid)'] loop
    begin
      execute format('revoke all on function %s from public, anon, authenticated', f);
      execute format('grant execute on function %s to service_role', f);
    exception when undefined_function then null; end;
  end loop;
end $$;
-- (payroll_run_final is used inside a row-security policy, so signed-in users keep it; anonymous visitors do not)
revoke all on function hrm.payroll_run_final(uuid) from public, anon;
grant execute on function hrm.payroll_run_final(uuid) to authenticated, service_role;
-- every later function is granted explicitly instead of to everybody
alter default privileges in schema hrm revoke execute on functions from anon;

-- 2. A company admin must never be able to make anyone (themselves included) a platform admin, or move a user to another company.
create or replace function hrm.guard_app_users() returns trigger language plpgsql set search_path = hrm, public as $$
begin
  if current_user in ('postgres','service_role','supabase_admin') then return new; end if;
  if tg_op = 'INSERT' then
    if new.role = 'platform_admin' then raise exception 'Not allowed.'; end if;
    return new;
  end if;
  if new.tenant_id is distinct from old.tenant_id then raise exception 'A user cannot be moved to another company.'; end if;
  if new.role = 'platform_admin' and old.role is distinct from 'platform_admin' then raise exception 'Not allowed.'; end if;
  if old.role = 'platform_admin' and new.role is distinct from old.role then raise exception 'Not allowed.'; end if;
  return new;
end $$;
drop trigger if exists app_users_guard on hrm.app_users;
create trigger app_users_guard before insert or update on hrm.app_users for each row execute function hrm.guard_app_users();

-- 3. Restore: every row in the backup must belong to the company being restored.
create or replace function hrm.company_import_safe(p_tenant uuid, p_data jsonb) returns jsonb
language plpgsql security definer set search_path = hrm, public as $fn$
declare t text; bad int; ids uuid[];
  skip text[] := array['employee_private'];
begin
  if coalesce(p_data->>'format', '') <> 'kmr-hrm-backup' then raise exception 'This file is not an HRM backup.'; end if;
  if (p_data->>'tenant_id')::uuid is distinct from p_tenant then raise exception 'This backup belongs to a different company.'; end if;
  for t in select jsonb_object_keys(coalesce(p_data->'tables', '{}'::jsonb)) loop
    if jsonb_typeof(p_data->'tables'->t) <> 'array' then continue; end if;
    if t = any (skip) then continue; end if;
    select count(*) into bad from jsonb_array_elements(p_data->'tables'->t) r
     where coalesce(r->>'tenant_id', '') <> '' and (r->>'tenant_id') <> p_tenant::text;
    if bad > 0 then raise exception 'Backup rejected: % row(s) in "%" belong to another company.', bad, t; end if;
  end loop;
  -- private (bank / statutory) rows must belong to employees inside this same backup
  select coalesce(array_agg((r->>'id')::uuid), '{}') into ids from jsonb_array_elements(coalesce(p_data->'tables'->'employees', '[]'::jsonb)) r;
  if jsonb_typeof(p_data->'tables'->'employee_private') = 'array' then
    select count(*) into bad from jsonb_array_elements(p_data->'tables'->'employee_private') r
     where not ((r->>'employee_id')::uuid = any (ids));
    if bad > 0 then raise exception 'Backup rejected: % private record(s) do not belong to an employee in this backup.', bad; end if;
  end if;
  return hrm.company_import(p_tenant, p_data);
end $fn$;
revoke all on function hrm.company_import_safe(uuid, jsonb) from public, anon, authenticated;
grant execute on function hrm.company_import_safe(uuid, jsonb) to service_role;

-- 4. Supervisors see and record only incidents of their own team (or ones they reported themselves); no deleting.
drop policy if exists incidents_mgr on hrm.incidents;
create policy incidents_mgr on hrm.incidents for select to authenticated
  using (tenant_id = hrm.current_tenant_id() and hrm.has_role('manager')
         and (reported_by_employee_id = hrm.current_employee_id() or (injured_employee_id is not null and hrm.is_in_my_team(injured_employee_id))));
drop policy if exists incidents_mgr_ins on hrm.incidents;
create policy incidents_mgr_ins on hrm.incidents for insert to authenticated
  with check (tenant_id = hrm.current_tenant_id() and hrm.has_role('manager')
         and (reported_by_employee_id = hrm.current_employee_id() or (injured_employee_id is not null and hrm.is_in_my_team(injured_employee_id))));
drop policy if exists incidents_mgr_upd on hrm.incidents;
create policy incidents_mgr_upd on hrm.incidents for update to authenticated
  using (tenant_id = hrm.current_tenant_id() and hrm.has_role('manager')
         and (reported_by_employee_id = hrm.current_employee_id() or (injured_employee_id is not null and hrm.is_in_my_team(injured_employee_id))))
  with check (tenant_id = hrm.current_tenant_id() and hrm.has_role('manager'));
drop policy if exists incident_actions_mgr on hrm.incident_actions;
create policy incident_actions_mgr on hrm.incident_actions for select to authenticated
  using (tenant_id = hrm.current_tenant_id() and hrm.has_role('manager')
         and exists (select 1 from hrm.incidents i where i.id = incident_id and (i.reported_by_employee_id = hrm.current_employee_id() or (i.injured_employee_id is not null and hrm.is_in_my_team(i.injured_employee_id)))));
drop policy if exists incident_actions_mgr_upd on hrm.incident_actions;
create policy incident_actions_mgr_upd on hrm.incident_actions for update to authenticated
  using (tenant_id = hrm.current_tenant_id() and hrm.has_role('manager')
         and exists (select 1 from hrm.incidents i where i.id = incident_id and (i.reported_by_employee_id = hrm.current_employee_id() or (i.injured_employee_id is not null and hrm.is_in_my_team(i.injured_employee_id)))))
  with check (tenant_id = hrm.current_tenant_id() and hrm.has_role('manager'));
drop policy if exists incident_actions_mgr_ins on hrm.incident_actions;
create policy incident_actions_mgr_ins on hrm.incident_actions for insert to authenticated
  with check (tenant_id = hrm.current_tenant_id() and hrm.has_role('manager')
         and exists (select 1 from hrm.incidents i where i.id = incident_id and (i.reported_by_employee_id = hrm.current_employee_id() or (i.injured_employee_id is not null and hrm.is_in_my_team(i.injured_employee_id)))));

-- 5. The audit log can only ever be added to (IATF 7.5.3 / ISO 9001 7.5.3: records are protected from alteration).
revoke update, delete, truncate on hrm.audit_log from anon, authenticated;
create or replace function hrm.audit_immutable() returns trigger language plpgsql set search_path = hrm, public as $$
begin raise exception 'The audit log cannot be changed or deleted.'; end $$;
drop trigger if exists audit_log_no_change on hrm.audit_log;
create trigger audit_log_no_change before update or delete on hrm.audit_log for each row execute function hrm.audit_immutable();

-- 6. An employee who has payroll or leave history cannot be deleted (statutory records are kept for years); mark them left instead.
create or replace function hrm.guard_employee_delete() returns trigger language plpgsql set search_path = hrm, public as $$
begin
  if current_user in ('postgres','service_role','supabase_admin') then return old; end if;
  if exists (select 1 from hrm.payroll_lines where employee_id = old.id) or exists (select 1 from hrm.leave_ledger where employee_id = old.id)
     or exists (select 1 from hrm.salary_structures where employee_id = old.id) then
    raise exception 'This employee has payroll or leave history and cannot be deleted. Change the status to left instead.';
  end if;
  return old;
end $$;
drop trigger if exists employees_guard_delete on hrm.employees;
create trigger employees_guard_delete before delete on hrm.employees for each row execute function hrm.guard_employee_delete();

-- 7. Indexes on the columns every manager / payroll screen filters by.
do $$ declare r record; begin
  for r in select * from (values
    ('employees','reporting_manager_id'),('employees','department_id'),('employees','plant_id'),('employees','designation_id'),('employees','shift_id'),
    ('app_users','employee_id'),('attendance_punches','employee_id'),('loans','employee_id'),('medical_checks','employee_id'),('kpi_values','employee_id'),
    ('suggestions','employee_id'),('survey_participants','employee_id'),('training_attendance','employee_id'),('training_effectiveness','employee_id'),('training_needs','employee_id'),
    ('incidents','injured_employee_id'),('incidents','reported_by_employee_id'),('leave_ledger','request_id'),('leave_ledger','leave_type_id'),('leave_requests','leave_type_id'),
    ('payroll_lines','tenant_id'),('leave_ledger','tenant_id'),('salary_structures','tenant_id'),('survey_responses','tenant_id')
  ) as v(tb, col) loop
    begin
      execute format('create index if not exists %I on hrm.%I (%I)', 'ix_' || r.tb || '_' || r.col, r.tb, r.col);
    exception when undefined_table or undefined_column then null; end;
  end loop;
end $$;

-- 8. Money and days can never be negative.
do $$ declare r record; begin
  for r in select * from (values
    ('payroll_lines','gross'),('payroll_lines','net_pay'),('payroll_lines','paid_days'),('payroll_lines','lop_days'),('payroll_lines','ot_hours'),
    ('loans','balance')
  ) as v(tb, col) loop
    begin
      execute format('alter table hrm.%I add constraint %I check (%I >= 0) not valid', r.tb, 'ck_' || r.tb || '_' || r.col || '_nonneg', r.col);
    exception when duplicate_object or undefined_table or undefined_column then null; end;
  end loop;
end $$;

-- 9. Public branding bucket: images only, no SVG (an SVG can carry script).
do $$ begin
  update storage.buckets set allowed_mime_types = array['image/png','image/jpeg','image/webp'] where id = 'hrm-branding';
exception when others then null; end $$;
