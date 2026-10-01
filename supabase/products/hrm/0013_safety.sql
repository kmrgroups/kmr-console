-- =====================================================================
-- HRM 0013 — Phase 5D: safety. Needs 0001–0012. Safe to re-run.
--   • Incidents — near misses, unsafe acts / conditions (anyone reports them, employees from their portal with a photo),
--     first aid, injuries, lost-time injuries, property damage, fire, environment, dangerous occurrences; investigated
--     (why-why, root cause), corrective / preventive actions with an owner and a due date, closed by a named person
--   • Figures by fixed rules: days since the last lost-time injury, LTIFR and severity rate on the man-hours worked
--     (from attendance), near misses per injury
--   • PPE — what each department needs, what was issued to whom, when it is due for replacement; people without it
--   • Periodic medical examination register — dates only (done / next due); the HRM keeps no medical details
-- The free AI (0010) can draft the why-why and the actions for the investigator, who checks and saves them.
-- ISO 45001 9.1, 10.2 · Factories Act, 1948 (accident notice and registers — check the forms and time limits for your state).
-- =====================================================================

create table if not exists hrm.safety_settings (
  tenant_id        uuid primary key references hrm.tenants(id) on delete cascade,
  officer_name     text check (length(officer_name) <= 120),
  officer_email    text check (length(officer_email) <= 200),        -- new incidents and overdue actions are e-mailed here
  hours_per_day    numeric(4,1) not null default 8 check (hours_per_day between 1 and 24),   -- man-hours when attendance has no worked time
  ltifr_target     numeric(8,2),
  updated_at       timestamptz not null default now()
);

create table if not exists hrm.incidents (
  id                  uuid primary key default gen_random_uuid(),
  tenant_id           uuid not null references hrm.tenants(id) on delete cascade,
  ref                 text,
  kind                text not null check (kind in ('near_miss','unsafe_act','unsafe_condition','first_aid','injury','lost_time','property_damage','fire','environment','dangerous_occurrence')),
  occurred_at         timestamptz not null,
  plant_id            uuid references hrm.plants(id) on delete set null,
  department_id       uuid references hrm.departments(id) on delete set null,
  area                text check (length(area) <= 160),               -- line, machine, place
  description         text not null check (length(description) between 5 and 3000),
  immediate_action    text check (length(immediate_action) <= 2000),
  injured_employee_id uuid references hrm.employees(id) on delete set null,
  injured_other       text check (length(injured_other) <= 160),     -- a contract worker or visitor
  injury_nature       text check (length(injury_nature) <= 300),     -- e.g. cut on the left index finger
  days_lost           integer not null default 0 check (days_lost between 0 and 9999),
  potential           integer check (potential between 1 and 5),      -- how bad it could have been (1 minor … 5 fatal)
  status              text not null default 'reported' check (status in ('reported','investigating','action','closed')),
  investigator_name   text check (length(investigator_name) <= 120),
  why_why             text[] not null default '{}',
  root_cause          text check (length(root_cause) <= 2000),
  ai_model            text,                                           -- the AI drafted the why-why (the investigator checked it)
  ai_actions          jsonb,                                          -- actions the AI suggested; the investigator adds the ones he wants
  reportable          boolean not null default false,                 -- to the authority (Inspector of Factories, ESIC …)
  authority_notified_on date,
  authority_ref       text check (length(authority_ref) <= 120),
  photo_path          text,
  reported_by         uuid,
  reported_by_name    text,
  reported_by_employee_id uuid references hrm.employees(id) on delete set null,
  closed_at           timestamptz,
  closed_by_name      text,
  sample              boolean not null default false,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);
alter table hrm.incidents add column if not exists ai_actions jsonb;
create index if not exists incidents_list on hrm.incidents (tenant_id, occurred_at desc);
create unique index if not exists incidents_ref on hrm.incidents (tenant_id, ref);

create or replace function hrm.incident_ref() returns trigger
language plpgsql security definer set search_path = hrm, public as $fn$
declare y text := to_char((new.occurred_at at time zone 'Asia/Kolkata'), 'YYYY'); n int;
begin
  if new.ref is null then
    perform pg_advisory_xact_lock(hashtext('incident_ref' || new.tenant_id::text));
    select coalesce(max(substring(ref from '\d+$')::int), 0) + 1 into n from hrm.incidents where tenant_id = new.tenant_id and ref like 'INC-' || y || '-%';
    new.ref := 'INC-' || y || '-' || lpad(n::text, 3, '0');
  end if;
  return new;
end $fn$;
drop trigger if exists incidents_ref_set on hrm.incidents;
create trigger incidents_ref_set before insert on hrm.incidents for each row execute function hrm.incident_ref();

create table if not exists hrm.incident_actions (
  id                uuid primary key default gen_random_uuid(),
  tenant_id         uuid not null references hrm.tenants(id) on delete cascade,
  incident_id       uuid not null references hrm.incidents(id) on delete cascade,
  action            text not null check (length(action) between 3 and 1000),
  kind              text not null default 'corrective' check (kind in ('corrective','preventive')),
  owner_employee_id uuid references hrm.employees(id) on delete set null,
  owner_name        text check (length(owner_name) <= 120),
  due_on            date not null,
  status            text not null default 'open' check (status in ('open','done')),
  done_on           date,
  done_note         text check (length(done_note) <= 1000),
  notified_at       timestamptz,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);
create index if not exists incident_actions_open on hrm.incident_actions (tenant_id, status, due_on);

create table if not exists hrm.ppe_items (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null references hrm.tenants(id) on delete cascade,
  name           text not null check (length(name) between 2 and 80),
  life_months    integer not null default 12 check (life_months between 1 and 120),   -- replace after
  for_all        boolean not null default false,            -- everybody must have it …
  departments    uuid[] not null default '{}',             -- … or the people of these departments
  sizes          text check (length(sizes) <= 200),
  active         boolean not null default true,
  created_at     timestamptz not null default now(),
  unique (tenant_id, name)
);
alter table hrm.ppe_items add column if not exists for_all boolean not null default false;
create table if not exists hrm.ppe_issues (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null references hrm.tenants(id) on delete cascade,
  employee_id    uuid not null references hrm.employees(id) on delete cascade,
  item_id        uuid not null references hrm.ppe_items(id) on delete cascade,
  issued_on      date not null,
  qty            integer not null default 1 check (qty between 1 and 100),
  size           text check (length(size) <= 20),
  next_due       date not null,
  issued_by_name text,
  note           text check (length(note) <= 300),
  sample         boolean not null default false,
  created_at     timestamptz not null default now()
);
create index if not exists ppe_issues_person on hrm.ppe_issues (employee_id, item_id, issued_on desc);

create table if not exists hrm.medical_checks (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null references hrm.tenants(id) on delete cascade,
  employee_id    uuid not null references hrm.employees(id) on delete cascade,
  kind           text not null default 'periodic' check (kind in ('pre_employment','periodic','hearing','vision','lung_function','other')),
  done_on        date,
  next_due       date,
  doctor         text check (length(doctor) <= 160),       -- the certifying surgeon / clinic
  certificate_path text,                                    -- the certificate (PDF), kept private
  note           text check (length(note) <= 300),          -- no medical findings here
  sample         boolean not null default false,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create index if not exists medical_checks_due on hrm.medical_checks (tenant_id, next_due);

-- ---------- man-hours worked in a period (attendance worked time; present days × hours a day when not recorded) ----------
create or replace function hrm.man_hours(p_from date, p_to date) returns numeric
language sql stable security definer set search_path = hrm, public as $fn$
  select coalesce(sum(case when a.worked_minutes > 0 then a.worked_minutes / 60.0 else a.present_days * coalesce(s.hours_per_day, 8) end), 0)
    from hrm.attendance_days a left join hrm.safety_settings s on s.tenant_id = a.tenant_id
   where a.tenant_id = hrm.current_tenant_id() and (hrm.is_hr() or hrm.has_role('manager')) and a.work_date between p_from and p_to
$fn$;
grant execute on function hrm.man_hours(date, date) to authenticated;

-- ---------- updated_at + audit trail ----------
do $$ declare t text; begin
  foreach t in array array['safety_settings','incidents','incident_actions','medical_checks'] loop
    execute format('drop trigger if exists %I on hrm.%I', t || '_touch', t);
    execute format('create trigger %I before update on hrm.%I for each row execute function hrm.touch_updated_at()', t || '_touch', t);
  end loop;
  foreach t in array array['safety_settings','incidents','incident_actions','ppe_items','ppe_issues','medical_checks'] loop
    execute format('drop trigger if exists %I on hrm.%I', t || '_audit', t);
    execute format('create trigger %I after insert or update or delete on hrm.%I for each row execute function hrm.audit_row()', t || '_audit', t);
  end loop;
end $$;

-- ---------- access ----------
do $$ declare t text; begin
  foreach t in array array['safety_settings','incidents','incident_actions','ppe_items','ppe_issues','medical_checks'] loop
    execute format('alter table hrm.%I enable row level security', t);
    execute format('drop policy if exists %I on hrm.%I', t || '_hr', t);
    execute format('create policy %I on hrm.%I for all to authenticated using (tenant_id = hrm.current_tenant_id() and hrm.is_hr()) with check (tenant_id = hrm.current_tenant_id() and hrm.is_hr())', t || '_hr', t);
  end loop;
end $$;
-- supervisors (managers) run safety on the floor: they see and record incidents and actions, and issue PPE to their team
drop policy if exists incidents_mgr on hrm.incidents;
create policy incidents_mgr on hrm.incidents for all to authenticated
  using (tenant_id = hrm.current_tenant_id() and hrm.has_role('manager')) with check (tenant_id = hrm.current_tenant_id() and hrm.has_role('manager'));
drop policy if exists incident_actions_mgr on hrm.incident_actions;
create policy incident_actions_mgr on hrm.incident_actions for all to authenticated
  using (tenant_id = hrm.current_tenant_id() and hrm.has_role('manager')) with check (tenant_id = hrm.current_tenant_id() and hrm.has_role('manager'));
-- employees: report near misses and unsafe acts / conditions, see their own reports and the actions given to them
drop policy if exists incidents_report on hrm.incidents;
create policy incidents_report on hrm.incidents for insert to authenticated
  with check (tenant_id = hrm.current_tenant_id() and reported_by_employee_id = hrm.current_employee_id() and reported_by = auth.uid()
    and kind in ('near_miss','unsafe_act','unsafe_condition') and status = 'reported' and injured_employee_id is null);
drop policy if exists incidents_self on hrm.incidents;
create policy incidents_self on hrm.incidents for select to authenticated
  using (tenant_id = hrm.current_tenant_id() and (reported_by_employee_id = hrm.current_employee_id() or injured_employee_id = hrm.current_employee_id()));
drop policy if exists incident_actions_self on hrm.incident_actions;
create policy incident_actions_self on hrm.incident_actions for select to authenticated
  using (tenant_id = hrm.current_tenant_id() and owner_employee_id = hrm.current_employee_id());
drop policy if exists ppe_items_read on hrm.ppe_items;
create policy ppe_items_read on hrm.ppe_items for select to authenticated using (tenant_id = hrm.current_tenant_id());
drop policy if exists ppe_issues_self on hrm.ppe_issues;
create policy ppe_issues_self on hrm.ppe_issues for select to authenticated using (tenant_id = hrm.current_tenant_id() and employee_id = hrm.current_employee_id());
drop policy if exists ppe_issues_team on hrm.ppe_issues;
create policy ppe_issues_team on hrm.ppe_issues for select to authenticated using (tenant_id = hrm.current_tenant_id() and hrm.has_role('manager') and hrm.is_in_my_team(employee_id));
drop policy if exists ppe_issues_team_give on hrm.ppe_issues;
create policy ppe_issues_team_give on hrm.ppe_issues for insert to authenticated with check (tenant_id = hrm.current_tenant_id() and hrm.has_role('manager') and hrm.is_in_my_team(employee_id));
drop policy if exists medical_checks_self on hrm.medical_checks;
create policy medical_checks_self on hrm.medical_checks for select to authenticated using (tenant_id = hrm.current_tenant_id() and employee_id = hrm.current_employee_id());

-- ---------- the AI may also draft the why-why of an incident ----------
alter table hrm.ai_runs drop constraint if exists ai_runs_agent_check;
alter table hrm.ai_runs add constraint ai_runs_agent_check check (agent in ('jd','sheet','programmes','quiz','qms_agent','check','announcement','survey','document','safety'));

-- ---------- defaults: a starting PPE list ----------
create or replace function hrm.seed_safety_defaults(p_tenant uuid) returns void
language plpgsql security definer set search_path = hrm, public as $fn$
begin
  insert into hrm.safety_settings (tenant_id) values (p_tenant) on conflict do nothing;
  insert into hrm.ppe_items (tenant_id, name, life_months, sizes)
  select p_tenant, x.n, x.m, x.s from (values
    ('Safety shoes', 12, '6,7,8,9,10,11'), ('Safety goggles', 6, null), ('Hand gloves', 1, 'M,L,XL'), ('Ear plugs', 1, null),
    ('Safety helmet', 24, null), ('Apron / coverall', 12, 'M,L,XL,XXL'), ('Dust mask', 1, null)
  ) x(n, m, s)
  on conflict (tenant_id, name) do nothing;
end $fn$;
revoke all on function hrm.seed_safety_defaults(uuid) from public, anon, authenticated;
grant execute on function hrm.seed_safety_defaults(uuid) to service_role;

create or replace function hrm.seed_new_tenant() returns trigger
language plpgsql security definer set search_path = hrm, public as $fn$
begin
  if to_regprocedure('hrm.seed_payroll_defaults(uuid)') is not null then perform hrm.seed_payroll_defaults(new.id); end if;
  if to_regprocedure('hrm.seed_recruit_defaults(uuid)') is not null then perform hrm.seed_recruit_defaults(new.id); end if;
  perform hrm.seed_qms_defaults(new.id);
  perform hrm.seed_compliance_defaults(new.id);
  perform hrm.seed_safety_defaults(new.id);
  return new;
end $fn$;
do $$ declare t uuid; begin for t in select id from hrm.tenants loop perform hrm.seed_safety_defaults(t); end loop; end $$;

-- ---------- clearing ('real' keeps the PPE list and safety settings — company setup, like plants) ----------
create or replace function hrm.module_flush(p_tenant uuid, p_mode text default 'all') returns integer
language plpgsql security definer set search_path = hrm, public as $fn$
declare t text; n int := 0; k int;
  lists text[] := case when p_mode = 'real' then array['incidents','ppe_issues','medical_checks','compliance_tasks','documents','recognitions','suggestions','announcements','surveys','training_sessions','ojt_templates','kpis','rr_roles','role_competencies','positions','operations']
                       else array['incidents','ppe_issues','medical_checks','compliance_tasks','compliance_items','documents','recognitions','suggestions','announcements','surveys','training_sessions','ojt_templates','training_programs','kpis','rr_roles','role_competencies','positions','operations','competencies'] end;
begin
  if p_mode not in ('all','real','sample') then raise exception 'Unknown flush mode %', p_mode; end if;
  if p_mode = 'all' then
    foreach t in array array['document_acks','survey_responses','survey_participants','announcement_reads','recognitions','suggestions',
                             'auditor_audits','auditors','ojt_records','training_effectiveness','training_attendance','training_needs','kpi_values','rr_acks','skill_levels','employee_competencies'] loop
      execute format('delete from hrm.%I where tenant_id = $1', t) using p_tenant; get diagnostics k = row_count; n := n + k;
    end loop;
    delete from hrm.qms_settings where tenant_id = p_tenant;
    delete from hrm.ai_runs where tenant_id = p_tenant;
    delete from hrm.ppe_items where tenant_id = p_tenant;
    delete from hrm.safety_settings where tenant_id = p_tenant;
  end if;
  foreach t in array lists loop
    execute format('delete from hrm.%I where tenant_id = $1 and (%s)', t,
      case p_mode when 'all' then 'true' when 'real' then 'not sample' else 'sample' end) using p_tenant;
    get diagnostics k = row_count; n := n + k;
  end loop;
  if p_mode = 'all' then perform hrm.seed_qms_defaults(p_tenant); perform hrm.seed_compliance_defaults(p_tenant); perform hrm.seed_safety_defaults(p_tenant); end if;
  return n;
end $fn$;
revoke all on function hrm.module_flush(uuid, text) from public, anon, authenticated;
grant execute on function hrm.module_flush(uuid, text) to service_role;

-- ---------- backup / restore (version 8: + safety) ----------
create or replace function hrm.company_export(p_tenant uuid) returns jsonb
language plpgsql stable security definer set search_path = hrm, public as $fn$
declare out jsonb := '{}'::jsonb; t text; rows jsonb;
begin
  foreach t in array array['plants','departments','designations','positions','shifts','holidays','leave_types','notification_templates',
    'employees','employee_private','onboarding_invites','employee_documents','id_cards','attendance_devices',
    'attendance_punches','attendance_days','regularisation_requests','leave_requests','leave_ledger',
    'pay_settings','pay_components','salary_structures','loans','payroll_runs','payroll_lines','loan_recoveries',
    'recruit_settings','job_descriptions','requisitions','candidates','applications','interviews','interview_feedback','offers',
    'qms_settings','competencies','operations','role_competencies','rr_roles','rr_acks','kpis','kpi_values','employee_competencies','skill_levels',
    'training_programs','training_sessions','training_needs','training_attendance','training_effectiveness','ojt_templates','ojt_records','auditors','auditor_audits',
    'announcements','announcement_reads','suggestions','recognitions','surveys','survey_participants','survey_responses',
    'documents','document_versions','document_acks','compliance_items','compliance_tasks',
    'safety_settings','ppe_items','ppe_issues','incidents','incident_actions','medical_checks'] loop
    if to_regclass('hrm.' || t) is null then continue; end if;
    if t in ('employee_private') then
      execute format('select coalesce(jsonb_agg(to_jsonb(x)), ''[]'') from hrm.%I x where x.employee_id in (select id from hrm.employees where tenant_id = $1)', t) into rows using p_tenant;
    else
      execute format('select coalesce(jsonb_agg(to_jsonb(x)), ''[]'') from hrm.%I x where x.tenant_id = $1', t) into rows using p_tenant;
    end if;
    out := out || jsonb_build_object(t, rows);
  end loop;
  return jsonb_build_object('format', 'kmr-hrm-backup', 'version', 8, 'exported_at', now(),
    'company', (select to_jsonb(x) - 'id' from hrm.tenants x where id = p_tenant), 'tenant_id', p_tenant, 'tables', out);
end $fn$;

create or replace function hrm.company_import(p_tenant uuid, p_data jsonb) returns jsonb
language plpgsql security definer set search_path = hrm, public as $fn$
declare t text; n integer; counts jsonb := '{}'::jsonb; links jsonb;
  ins text[] := array['plants','departments','designations','positions','shifts','holidays','leave_types','notification_templates',
    'employees','employee_private','onboarding_invites','employee_documents','id_cards','attendance_devices',
    'attendance_punches','attendance_days','regularisation_requests','leave_requests','leave_ledger',
    'pay_settings','pay_components','salary_structures','loans','payroll_runs','payroll_lines','loan_recoveries',
    'recruit_settings','job_descriptions','requisitions','candidates','applications','interviews','interview_feedback','offers',
    'qms_settings','competencies','operations','role_competencies','rr_roles','rr_acks','kpis','kpi_values','employee_competencies','skill_levels',
    'training_programs','training_sessions','training_needs','training_attendance','training_effectiveness','ojt_templates','ojt_records','auditors','auditor_audits',
    'announcements','announcement_reads','suggestions','recognitions','surveys','survey_participants','survey_responses',
    'documents','document_versions','document_acks','compliance_items','compliance_tasks',
    'safety_settings','ppe_items','ppe_issues','incidents','incident_actions','medical_checks'];
begin
  if coalesce(p_data->>'format', '') <> 'kmr-hrm-backup' then raise exception 'This file is not an HRM backup.'; end if;
  if (p_data->>'tenant_id')::uuid is distinct from p_tenant then raise exception 'This backup belongs to a different company.'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'employee_id', employee_id)), '[]') into links from hrm.app_users where tenant_id = p_tenant;
  perform hrm.module_flush(p_tenant, 'all');
  delete from hrm.compliance_items where tenant_id = p_tenant;
  delete from hrm.ppe_items where tenant_id = p_tenant;
  delete from hrm.safety_settings where tenant_id = p_tenant;
  delete from hrm.qms_settings where tenant_id = p_tenant;
  delete from hrm.competencies where tenant_id = p_tenant;
  delete from hrm.training_programs where tenant_id = p_tenant;
  delete from hrm.offers where tenant_id = p_tenant;
  delete from hrm.interview_feedback where tenant_id = p_tenant;
  delete from hrm.interviews where tenant_id = p_tenant;
  delete from hrm.applications where tenant_id = p_tenant;
  delete from hrm.candidates where tenant_id = p_tenant;
  delete from hrm.requisitions where tenant_id = p_tenant;
  delete from hrm.job_descriptions where tenant_id = p_tenant;
  delete from hrm.recruit_settings where tenant_id = p_tenant;
  delete from hrm.loan_recoveries where tenant_id = p_tenant;
  delete from hrm.payroll_lines where tenant_id = p_tenant;
  delete from hrm.payroll_runs where tenant_id = p_tenant;
  delete from hrm.loans where tenant_id = p_tenant;
  delete from hrm.salary_structures where tenant_id = p_tenant;
  delete from hrm.pay_components where tenant_id = p_tenant;
  delete from hrm.pay_settings where tenant_id = p_tenant;
  delete from hrm.leave_ledger where tenant_id = p_tenant;
  delete from hrm.leave_requests where tenant_id = p_tenant;
  delete from hrm.regularisation_requests where tenant_id = p_tenant;
  delete from hrm.attendance_days where tenant_id = p_tenant;
  delete from hrm.attendance_punches where tenant_id = p_tenant;
  delete from hrm.attendance_devices where tenant_id = p_tenant;
  delete from hrm.id_cards where tenant_id = p_tenant;
  delete from hrm.employee_documents where tenant_id = p_tenant;
  delete from hrm.onboarding_invites where tenant_id = p_tenant;
  update hrm.app_users set employee_id = null where tenant_id = p_tenant;
  update hrm.employees set reporting_manager_id = null where tenant_id = p_tenant;
  delete from hrm.employees where tenant_id = p_tenant;
  delete from hrm.notification_templates where tenant_id = p_tenant;
  delete from hrm.leave_types where tenant_id = p_tenant;
  delete from hrm.holidays where tenant_id = p_tenant;
  delete from hrm.shifts where tenant_id = p_tenant;
  delete from hrm.positions where tenant_id = p_tenant;
  delete from hrm.designations where tenant_id = p_tenant;
  delete from hrm.departments where tenant_id = p_tenant;
  delete from hrm.plants where tenant_id = p_tenant;
  foreach t in array ins loop
    if jsonb_typeof(p_data->'tables'->t) <> 'array' then continue; end if;
    execute format('insert into hrm.%I select * from jsonb_populate_recordset(null::hrm.%I, $1)', t, t) using p_data->'tables'->t;
    get diagnostics n = row_count; counts := counts || jsonb_build_object(t, n);
  end loop;
  update hrm.app_users u set employee_id = (l->>'employee_id')::uuid
    from jsonb_array_elements(links) l
   where u.id = (l->>'id')::uuid and (l->>'employee_id') is not null and exists (select 1 from hrm.employees e where e.id = (l->>'employee_id')::uuid);
  update hrm.tenants set settings = coalesce(p_data->'company'->'settings', settings),
         legal_name = coalesce(p_data->'company'->>'legal_name', legal_name),
         address = coalesce(p_data->'company'->>'address', address)
   where id = p_tenant;
  perform hrm.seed_payroll_defaults(p_tenant);
  perform hrm.seed_recruit_defaults(p_tenant);
  perform hrm.seed_qms_defaults(p_tenant);
  perform hrm.seed_compliance_defaults(p_tenant);
  perform hrm.seed_safety_defaults(p_tenant);
  return counts;
end $fn$;
revoke all on function hrm.company_export(uuid), hrm.company_import(uuid, jsonb) from public, anon, authenticated;
grant execute on function hrm.company_export(uuid), hrm.company_import(uuid, jsonb) to service_role;

-- ---------- sample data (deliberately imperfect: an action overdue, a report nobody has looked at, PPE overdue,
--            people never issued shoes, a medical check overdue) ----------
create or replace function hrm.demo_safety(p_tenant uuid) returns integer
language plpgsql security definer set search_path = hrm, public as $fn$
declare t uuid := p_tenant; n int := 0; people uuid[]; depts uuid[]; plants uuid[]; i int; inc uuid; prod uuid; it record;
  today date := (now() at time zone 'Asia/Kolkata')::date; ts timestamptz;
begin
  select array_agg(id order by employee_code), array_agg(department_id order by employee_code), array_agg(plant_id order by employee_code)
    into people, depts, plants from hrm.employees where tenant_id = t and email like '%@demo.kmr.test' and status = 'active';
  if coalesce(array_length(people, 1), 0) < 22 then return 0; end if;
  if exists (select 1 from hrm.incidents where tenant_id = t and sample) then return 0; end if;
  perform hrm.seed_safety_defaults(t);
  update hrm.safety_settings set officer_name = coalesce(officer_name, 'Safety Officer (sample)') where tenant_id = t;
  select id into prod from hrm.departments where tenant_id = t and name = 'Production';
  -- production must have shoes, goggles, gloves and ear plugs (the company sets the rest)
  update hrm.ppe_items set departments = array[prod] where tenant_id = t and prod is not null and name in ('Safety shoes','Safety goggles','Hand gloves','Ear plugs') and departments = '{}' and not for_all;

  -- 1. a lost-time injury 75 days ago, investigated and closed, reported to the authority
  ts := (today - 75) + time '10:40';
  insert into hrm.incidents (tenant_id, kind, occurred_at, plant_id, department_id, area, description, immediate_action, injured_employee_id, injury_nature, days_lost, potential, status,
    investigator_name, why_why, root_cause, reportable, authority_notified_on, authority_ref, reported_by_name, closed_at, closed_by_name, sample)
  values (t, 'lost_time', ts, plants[15], depts[15], 'Press shop · 63 T power press', 'While removing a stuck part the operator''s hand entered the die area; the press stroked once.',
    'Press stopped and locked out; first aid; taken to the ESI hospital.', people[15], 'Crush injury to two fingers of the left hand', 4, 4, 'closed', 'Production Head (sample)',
    array['Why did the hand enter the die? — to remove a stuck part', 'Why was the part stuck? — worn ejector pin', 'Why did the press stroke? — two-hand control bypassed with a wedge',
      'Why was it bypassed? — operators found two-hand operation slow', 'Why was it not seen? — no daily check of safety devices'],
    'Two-hand control bypassed and no daily check of press safety devices.', true, today - 74, 'Form 18 / KA-FAC-2026-118', 'Supervisor (sample)', now() - interval '40 days', 'Plant Head (sample)', true)
  returning id into inc;
  insert into hrm.incident_actions (tenant_id, incident_id, action, kind, owner_name, due_on, status, done_on, done_note) values
    (t, inc, 'Remove the wedge; tamper-proof two-hand control fitted', 'corrective', 'Maintenance Head', today - 70, 'done', today - 72, 'Done the same week'),
    (t, inc, 'Daily press safety-device check added to the start-up checklist', 'preventive', 'Production Head', today - 60, 'done', today - 61, null),
    (t, inc, 'Press safety training for all press operators', 'preventive', 'HR', today - 50, 'done', today - 45, 'Done late — trainer not available');
  -- 2. first aid 30 days ago, closed
  insert into hrm.incidents (tenant_id, kind, occurred_at, plant_id, department_id, area, description, immediate_action, injured_employee_id, injury_nature, potential, status, investigator_name, root_cause, reported_by_name, closed_at, closed_by_name, sample)
  values (t, 'first_aid', (today - 30) + time '15:20', plants[16], depts[16], 'Deburring table', 'Small cut on the finger while deburring without gloves.', 'Cleaned and dressed at the first-aid box.',
    people[16], 'Small cut, right finger', 2, 'closed', 'Supervisor (sample)', 'Gloves not worn; cut-resistant gloves not issued at this table.', 'Supervisor (sample)', now() - interval '25 days', 'Safety Officer (sample)', true);
  -- 3. near miss 7 days ago (the forklift), actions — one overdue
  insert into hrm.incidents (tenant_id, kind, occurred_at, plant_id, area, description, immediate_action, potential, status, investigator_name, reported_by_name, reported_by_employee_id, sample)
  values (t, 'near_miss', (today - 7) + time '11:05', plants[22], 'Dispatch bay', 'Forklift reversed without a banksman; a helper walking behind stepped aside just in time.', 'Forklift stopped; driver counselled.',
    4, 'action', 'Safety Officer (sample)', 'Pooja (sample)', people[22], true) returning id into inc;
  insert into hrm.incident_actions (tenant_id, incident_id, action, kind, owner_employee_id, owner_name, due_on, status) values
    (t, inc, 'Reverse alarm and blue spot light on both forklifts', 'corrective', people[7], null, today - 2, 'open'),
    (t, inc, 'Marked pedestrian walkway in the dispatch bay', 'preventive', people[2], null, today + 10, 'open');
  -- 4. an unsafe condition reported from the portal 3 days ago — nobody has looked at it yet
  insert into hrm.incidents (tenant_id, kind, occurred_at, plant_id, area, description, potential, status, reported_by_name, reported_by_employee_id, sample)
  values (t, 'unsafe_condition', (today - 3) + time '09:30', plants[14], 'Maintenance store', 'Oil leaking from the compressor; floor slippery near the store door.', 3, 'reported', 'Deepa (sample)', people[14], true);
  -- 5. an unsafe act being investigated
  insert into hrm.incidents (tenant_id, kind, occurred_at, plant_id, area, description, immediate_action, potential, status, investigator_name, reported_by_name, sample)
  values (t, 'unsafe_act', (today - 2) + time '16:45', plants[12], 'Grinding', 'Operator grinding without goggles.', 'Work stopped; goggles issued.', 3, 'investigating', 'Supervisor (sample)', 'Supervisor (sample)', true);
  -- 6. property damage 15 days ago
  insert into hrm.incidents (tenant_id, kind, occurred_at, plant_id, area, description, potential, status, reported_by_name, sample)
  values (t, 'property_damage', (today - 15) + time '20:10', plants[8], 'Stores · rack B4', 'Forklift fork hit rack B4; one upright bent.', 3, 'reported', 'Stores (sample)', true);
  n := n + 6;

  -- PPE: production people got shoes / gloves at different times; some overdue, a few never issued
  for i in 1..24 loop
    if depts[i] is distinct from prod then continue; end if;
    for it in select id, name, life_months from hrm.ppe_items where tenant_id = t and name in ('Safety shoes','Hand gloves','Safety goggles') loop
      if it.name = 'Safety shoes' and i in (20, 21, 23) then continue; end if;          -- contract workers never issued shoes
      insert into hrm.ppe_issues (tenant_id, employee_id, item_id, issued_on, qty, next_due, issued_by_name, sample)
      values (t, people[i], it.id, today - (case it.name when 'Safety shoes' then 200 + i * 9 when 'Hand gloves' then 10 + i else 60 + i * 5 end),
        case when it.name = 'Hand gloves' then 2 else 1 end,
        (today - (case it.name when 'Safety shoes' then 200 + i * 9 when 'Hand gloves' then 10 + i else 60 + i * 5 end)) + make_interval(months => it.life_months), 'Stores (sample)', true);
      n := n + 1;
    end loop;
  end loop;
  -- periodic medical examination (dates only)
  for i in 1..24 loop
    if depts[i] is distinct from prod then continue; end if;
    insert into hrm.medical_checks (tenant_id, employee_id, kind, done_on, next_due, doctor, sample)
    values (t, people[i], 'periodic', today - (300 + i * 4), today - (300 + i * 4) + 365, 'Certifying surgeon (sample)', true);
    n := n + 1;
  end loop;
  return n;
end $fn$;

create or replace function hrm.demo_flow(p_tenant uuid) returns jsonb
language plpgsql security definer set search_path = hrm, public as $fn$
declare r int; q int; g int; c int; s int;
begin
  r := hrm.demo_recruit(p_tenant);
  q := hrm.demo_qms(p_tenant);
  g := hrm.demo_engage(p_tenant);
  c := hrm.demo_compliance(p_tenant);
  s := hrm.demo_safety(p_tenant);
  return jsonb_build_object('recruitment', r, 'qms', q, 'engagement', g, 'compliance', c, 'safety', s);
end $fn$;
revoke all on function hrm.demo_safety(uuid), hrm.demo_flow(uuid) from public, anon, authenticated;
grant execute on function hrm.demo_safety(uuid), hrm.demo_flow(uuid) to service_role;

do $$ declare r uuid; begin
  for r in select distinct tenant_id from hrm.employees where email like '%@demo.kmr.test' loop perform hrm.demo_safety(r); end loop;
end $$;

notify pgrst, 'reload schema';
