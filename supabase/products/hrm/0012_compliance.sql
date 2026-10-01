-- =====================================================================
-- HRM 0012 — Phase 5C: policies, document control and the statutory compliance register. Needs 0001–0011. Safe to re-run.
--   • Controlled documents (ISO 9001 7.5): policies, procedures, formats, work instructions, manuals — document no.,
--     revision, prepared by / approved by, effective date, review due; a new revision makes the old one obsolete;
--     master list of documents (PDF)
--   • Policies are documents people must read: each person acknowledges the current revision in his portal; a new
--     revision asks again; HR sees who has not
--   • Compliance register: statutory payments, returns, registers, notices and licences (PF, ESI, PT, TDS, Form 16,
--     LWF, Bonus, Factories Act returns, POSH report, licence renewals …) — due dates worked out by fixed rules, done
--     with the reference no. and proof, reminders before the due date, overdue flagged
-- The defaults are for Karnataka and are a starting list only: dates differ by state and change — the company checks
-- them with its consultant and edits them.
-- =====================================================================

-- ---------- controlled documents ----------
create table if not exists hrm.documents (
  id                  uuid primary key default gen_random_uuid(),
  tenant_id           uuid not null references hrm.tenants(id) on delete cascade,
  doc_no              text not null check (length(doc_no) between 1 and 40),
  title               text not null check (length(title) between 2 and 160),
  kind                text not null default 'policy' check (kind in ('policy','procedure','work_instruction','format','manual','other')),
  owner_department_id uuid references hrm.departments(id) on delete set null,
  owner_name          text check (length(owner_name) <= 120),                 -- who looks after it (a position, not a person, is best)
  employee_access     boolean not null default true,                          -- people can read it in their portal
  needs_ack           boolean not null default false,                         -- each person acknowledges each revision
  audience            text not null default 'all' check (audience in ('all','department','plant')),
  department_id       uuid references hrm.departments(id) on delete cascade,
  plant_id            uuid references hrm.plants(id) on delete cascade,
  review_months       integer not null default 12 check (review_months between 1 and 60),
  active              boolean not null default true,
  sample              boolean not null default false,
  created_by          uuid,
  created_by_name     text,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  unique (tenant_id, doc_no),
  check (audience <> 'department' or department_id is not null),
  check (audience <> 'plant' or plant_id is not null)
);

create table if not exists hrm.document_versions (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references hrm.tenants(id) on delete cascade,
  document_id      uuid not null references hrm.documents(id) on delete cascade,
  revision         integer not null check (revision >= 0),
  body             text check (length(body) <= 60000),                  -- written in the HRM …
  file_path        text,                                                -- … and / or a PDF
  file_name        text,
  change_note      text check (length(change_note) <= 1000),           -- what changed in this revision
  status           text not null default 'draft' check (status in ('draft','approved','obsolete')),
  prepared_by      uuid,
  prepared_by_name text,
  approved_by      uuid,
  approved_by_name text,
  approved_at      timestamptz,
  effective_from   date,
  review_due       date,
  review_notified_at timestamptz,
  ai_model         text,                                                -- the AI drafted the text (HR edited and approved it)
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  unique (document_id, revision)
);
create index if not exists document_versions_current on hrm.document_versions (document_id, status);

create table if not exists hrm.document_acks (
  tenant_id       uuid not null references hrm.tenants(id) on delete cascade,
  version_id      uuid not null references hrm.document_versions(id) on delete cascade,
  employee_id     uuid not null references hrm.employees(id) on delete cascade,
  acknowledged_at timestamptz not null default now(),
  primary key (version_id, employee_id)
);

-- ---------- compliance register ----------
create table if not exists hrm.compliance_items (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid not null references hrm.tenants(id) on delete cascade,
  code          text not null check (length(code) between 1 and 30),
  title         text not null check (length(title) between 2 and 160),
  law           text check (length(law) <= 200),
  kind          text not null default 'return' check (kind in ('payment','return','register','licence','notice','report','other')),
  frequency     text not null default 'monthly' check (frequency in ('monthly','quarterly','half_yearly','yearly','once')),
  due_months    integer[] not null default '{}',             -- the months it falls due (monthly: all)
  due_day       integer not null default 15 check (due_day between 1 and 31),   -- 31 = the month's last day
  state         text check (length(state) <= 40),
  licence_no    text check (length(licence_no) <= 80),
  valid_until   date,                                         -- licences: renewal is due renew_days before this
  renew_days    integer not null default 60 check (renew_days between 0 and 365),
  remind_days   integer not null default 7 check (remind_days between 0 and 90),
  owner_name    text check (length(owner_name) <= 120),
  owner_email   text check (length(owner_email) <= 200),     -- reminders go here (blank: the company's HR managers)
  start_on      date not null default ((now() at time zone 'Asia/Kolkata')::date),   -- no tasks before this
  notes         text check (length(notes) <= 1000),
  active        boolean not null default true,
  sample        boolean not null default false,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (tenant_id, code)
);

create table if not exists hrm.compliance_tasks (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid not null references hrm.tenants(id) on delete cascade,
  item_id       uuid not null references hrm.compliance_items(id) on delete cascade,
  due_on        date not null,
  status        text not null default 'open' check (status in ('open','done','not_applicable')),
  done_on       date,
  done_by       uuid,
  done_by_name  text,
  reference     text check (length(reference) <= 120),        -- challan / acknowledgement / receipt no.
  evidence_path text,
  evidence_name text,
  note          text check (length(note) <= 1000),
  reminded_at   timestamptz,
  overdue_notified_at timestamptz,
  sample        boolean not null default false,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (item_id, due_on)
);
create index if not exists compliance_tasks_due on hrm.compliance_tasks (tenant_id, status, due_on);

-- ---------- updated_at + audit trail ----------
do $$ declare t text; begin
  foreach t in array array['documents','document_versions','compliance_items','compliance_tasks'] loop
    execute format('drop trigger if exists %I on hrm.%I', t || '_touch', t);
    execute format('create trigger %I before update on hrm.%I for each row execute function hrm.touch_updated_at()', t || '_touch', t);
    execute format('drop trigger if exists %I on hrm.%I', t || '_audit', t);
    execute format('create trigger %I after insert or update or delete on hrm.%I for each row execute function hrm.audit_row()', t || '_audit', t);
  end loop;
end $$;

-- ---------- access ----------
do $$ declare t text; begin
  foreach t in array array['documents','document_versions','document_acks','compliance_items','compliance_tasks'] loop
    execute format('alter table hrm.%I enable row level security', t);
    execute format('drop policy if exists %I on hrm.%I', t || '_hr', t);
    execute format('create policy %I on hrm.%I for all to authenticated using (tenant_id = hrm.current_tenant_id() and hrm.is_hr()) with check (tenant_id = hrm.current_tenant_id() and hrm.is_hr())', t || '_hr', t);
  end loop;
end $$;
-- payroll staff look after the statutory payments and returns too
drop policy if exists compliance_items_payroll on hrm.compliance_items;
create policy compliance_items_payroll on hrm.compliance_items for select to authenticated using (tenant_id = hrm.current_tenant_id() and hrm.has_role('payroll'));
drop policy if exists compliance_tasks_payroll on hrm.compliance_tasks;
create policy compliance_tasks_payroll on hrm.compliance_tasks for all to authenticated
  using (tenant_id = hrm.current_tenant_id() and hrm.has_role('payroll')) with check (tenant_id = hrm.current_tenant_id() and hrm.has_role('payroll'));
-- documents: managers read every one; employees read those open to them; only approved revisions leave HR
drop policy if exists documents_read on hrm.documents;
create policy documents_read on hrm.documents for select to authenticated
  using (tenant_id = hrm.current_tenant_id() and active and (hrm.has_role('manager') or (employee_access and hrm.in_audience(audience, department_id, plant_id))));
drop policy if exists document_versions_read on hrm.document_versions;
create policy document_versions_read on hrm.document_versions for select to authenticated
  using (tenant_id = hrm.current_tenant_id() and status = 'approved' and exists (select 1 from hrm.documents d where d.id = document_id));
drop policy if exists document_acks_self on hrm.document_acks;
create policy document_acks_self on hrm.document_acks for select to authenticated using (tenant_id = hrm.current_tenant_id() and employee_id = hrm.current_employee_id());
drop policy if exists document_acks_give on hrm.document_acks;
create policy document_acks_give on hrm.document_acks for insert to authenticated
  with check (tenant_id = hrm.current_tenant_id() and employee_id = hrm.current_employee_id()
    and exists (select 1 from hrm.document_versions v where v.id = version_id and v.status = 'approved'));
drop policy if exists document_acks_team on hrm.document_acks;
create policy document_acks_team on hrm.document_acks for select to authenticated
  using (tenant_id = hrm.current_tenant_id() and hrm.has_role('manager') and hrm.is_in_my_team(employee_id));

-- ---------- the AI may also draft documents ----------
alter table hrm.ai_runs drop constraint if exists ai_runs_agent_check;
alter table hrm.ai_runs add constraint ai_runs_agent_check check (agent in ('jd','sheet','programmes','quiz','qms_agent','check','announcement','survey','document'));

-- ---------- defaults: a starting compliance list (Karnataka) ----------
create or replace function hrm.seed_compliance_defaults(p_tenant uuid) returns void
language plpgsql security definer set search_path = hrm, public as $fn$
begin
  insert into hrm.compliance_items (tenant_id, code, title, law, kind, frequency, due_months, due_day, state, notes)
  select p_tenant, x.code, x.title, x.law, x.kind, x.freq, x.months, x.day, x.st, x.notes from (values
    ('PF', 'PF contribution and ECR (previous month)', 'Employees'' Provident Funds & Misc. Provisions Act, 1952', 'payment', 'monthly', '{1,2,3,4,5,6,7,8,9,10,11,12}'::int[], 15, null::text, 'Upload the ECR from Payroll › Bank & statutory files; keep the TRRN.'),
    ('ESI', 'ESI contribution (previous month)', 'Employees'' State Insurance Act, 1948', 'payment', 'monthly', '{1,2,3,4,5,6,7,8,9,10,11,12}', 15, null, 'Keep the challan no.'),
    ('PT', 'Professional tax (previous month)', 'Karnataka Tax on Professions, Trades, Callings and Employments Act, 1976', 'payment', 'monthly', '{1,2,3,4,5,6,7,8,9,10,11,12}', 20, 'Karnataka', null),
    ('TDS', 'TDS on salaries — deposit (previous month)', 'Income-tax Act — section 192', 'payment', 'monthly', '{1,2,3,4,5,6,7,8,9,10,11,12}', 7, null, 'For March the due date is 30 April.'),
    ('24Q', 'TDS return — Form 24Q (quarter)', 'Income-tax Act — section 200(3)', 'return', 'quarterly', '{5,7,10,1}', 31, null, 'Q4 by 31 May, Q1 by 31 Jul, Q2 by 31 Oct, Q3 by 31 Jan.'),
    ('F16', 'Form 16 to employees', 'Income-tax Act — section 203', 'notice', 'yearly', '{6}', 15, null, null),
    ('LWF', 'Labour Welfare Fund contribution', 'Karnataka Labour Welfare Fund Act, 1965', 'payment', 'yearly', '{1}', 15, 'Karnataka', 'For the calendar year just ended.'),
    ('BONUS', 'Bonus — annual return (Form D)', 'Payment of Bonus Act, 1965', 'return', 'yearly', '{2}', 1, null, 'Bonus itself within 8 months of the accounting year end.'),
    ('FA-Y', 'Factories Act — annual return', 'Factories Act, 1948 / Karnataka Factories Rules', 'return', 'yearly', '{1}', 31, 'Karnataka', null),
    ('FA-H', 'Factories Act — half-yearly return', 'Factories Act, 1948 / Karnataka Factories Rules', 'return', 'yearly', '{7}', 31, 'Karnataka', null),
    ('POSH', 'POSH — Internal Committee annual report', 'Sexual Harassment of Women at Workplace Act, 2013', 'report', 'yearly', '{1}', 31, null, 'To the District Officer, for the calendar year.'),
    ('MW', 'Minimum wages / VDA revision — check and apply', 'Minimum Wages Act / Code on Wages', 'other', 'half_yearly', '{4,10}', 1, 'Karnataka', 'Update salary structures if the notified rates changed.'),
    ('LIC-FAC', 'Factory licence — renewal', 'Factories Act, 1948', 'licence', 'once', '{}', 1, 'Karnataka', 'Enter the licence no. and valid-until date to get renewal reminders.'),
    ('LIC-SE', 'Shops & Establishments registration — renewal', 'Karnataka Shops & Commercial Establishments Act, 1961', 'licence', 'once', '{}', 1, 'Karnataka', 'Enter the licence no. and valid-until date to get renewal reminders.'),
    ('LIC-CL', 'Contract labour licence — renewal', 'Contract Labour (Regulation & Abolition) Act, 1970', 'licence', 'once', '{}', 1, null, 'Enter the licence no. and valid-until date to get renewal reminders.'),
    ('LIC-FIRE', 'Fire NOC — renewal', 'Karnataka Fire Force Act, 1964', 'licence', 'once', '{}', 1, 'Karnataka', 'Enter the licence no. and valid-until date to get renewal reminders.'),
    ('LIC-PCB', 'Pollution Control Board consent — renewal', 'Water Act, 1974 / Air Act, 1981', 'licence', 'once', '{}', 1, null, 'Enter the consent no. and valid-until date to get renewal reminders.')
  ) x(code, title, law, kind, freq, months, day, st, notes)
  on conflict (tenant_id, code) do nothing;
end $fn$;
revoke all on function hrm.seed_compliance_defaults(uuid) from public, anon, authenticated;
grant execute on function hrm.seed_compliance_defaults(uuid) to service_role;

create or replace function hrm.seed_new_tenant() returns trigger
language plpgsql security definer set search_path = hrm, public as $fn$
begin
  if to_regprocedure('hrm.seed_payroll_defaults(uuid)') is not null then perform hrm.seed_payroll_defaults(new.id); end if;
  if to_regprocedure('hrm.seed_recruit_defaults(uuid)') is not null then perform hrm.seed_recruit_defaults(new.id); end if;
  perform hrm.seed_qms_defaults(new.id);
  perform hrm.seed_compliance_defaults(new.id);
  return new;
end $fn$;
do $$ declare t uuid; begin for t in select id from hrm.tenants loop perform hrm.seed_compliance_defaults(t); end loop; end $$;

-- ---------- clearing ----------
-- 'all': everything; the default compliance list comes back. 'real': the company's own documents and compliance tasks
-- (the compliance list itself is company setup and stays, like plants). 'sample': sample records only.
create or replace function hrm.module_flush(p_tenant uuid, p_mode text default 'all') returns integer
language plpgsql security definer set search_path = hrm, public as $fn$
declare t text; n int := 0; k int;
  lists text[] := case when p_mode = 'real' then array['compliance_tasks','documents','recognitions','suggestions','announcements','surveys','training_sessions','ojt_templates','kpis','rr_roles','role_competencies','positions','operations']
                       else array['compliance_tasks','compliance_items','documents','recognitions','suggestions','announcements','surveys','training_sessions','ojt_templates','training_programs','kpis','rr_roles','role_competencies','positions','operations','competencies'] end;
begin
  if p_mode not in ('all','real','sample') then raise exception 'Unknown flush mode %', p_mode; end if;
  if p_mode = 'all' then
    foreach t in array array['document_acks','survey_responses','survey_participants','announcement_reads','recognitions','suggestions',
                             'auditor_audits','auditors','ojt_records','training_effectiveness','training_attendance','training_needs','kpi_values','rr_acks','skill_levels','employee_competencies'] loop
      execute format('delete from hrm.%I where tenant_id = $1', t) using p_tenant; get diagnostics k = row_count; n := n + k;
    end loop;
    delete from hrm.qms_settings where tenant_id = p_tenant;
    delete from hrm.ai_runs where tenant_id = p_tenant;
  end if;
  foreach t in array lists loop
    execute format('delete from hrm.%I where tenant_id = $1 and (%s)', t,
      case p_mode when 'all' then 'true' when 'real' then 'not sample' else 'sample' end) using p_tenant;
    get diagnostics k = row_count; n := n + k;
  end loop;
  if p_mode = 'all' then perform hrm.seed_qms_defaults(p_tenant); perform hrm.seed_compliance_defaults(p_tenant); end if;
  return n;
end $fn$;
revoke all on function hrm.module_flush(uuid, text) from public, anon, authenticated;
grant execute on function hrm.module_flush(uuid, text) to service_role;

-- ---------- backup / restore (version 7: + documents and compliance) ----------
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
    'documents','document_versions','document_acks','compliance_items','compliance_tasks'] loop
    if to_regclass('hrm.' || t) is null then continue; end if;
    if t in ('employee_private') then
      execute format('select coalesce(jsonb_agg(to_jsonb(x)), ''[]'') from hrm.%I x where x.employee_id in (select id from hrm.employees where tenant_id = $1)', t) into rows using p_tenant;
    else
      execute format('select coalesce(jsonb_agg(to_jsonb(x)), ''[]'') from hrm.%I x where x.tenant_id = $1', t) into rows using p_tenant;
    end if;
    out := out || jsonb_build_object(t, rows);
  end loop;
  return jsonb_build_object('format', 'kmr-hrm-backup', 'version', 7, 'exported_at', now(),
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
    'documents','document_versions','document_acks','compliance_items','compliance_tasks'];
begin
  if coalesce(p_data->>'format', '') <> 'kmr-hrm-backup' then raise exception 'This file is not an HRM backup.'; end if;
  if (p_data->>'tenant_id')::uuid is distinct from p_tenant then raise exception 'This backup belongs to a different company.'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'employee_id', employee_id)), '[]') into links from hrm.app_users where tenant_id = p_tenant;
  perform hrm.module_flush(p_tenant, 'all');
  delete from hrm.compliance_items where tenant_id = p_tenant;
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
  return counts;
end $fn$;
revoke all on function hrm.company_export(uuid), hrm.company_import(uuid, jsonb) from public, anon, authenticated;
grant execute on function hrm.company_export(uuid), hrm.company_import(uuid, jsonb) to service_role;

-- ---------- sample data (deliberately imperfect: a review overdue, a policy not everybody has read, a late filing,
--            a licence close to expiry) ----------
create or replace function hrm.demo_compliance(p_tenant uuid) returns integer
language plpgsql security definer set search_path = hrm, public as $fn$
declare t uuid := p_tenant; n int := 0; people uuid[]; hrd uuid; d1 uuid; d2 uuid; d3 uuid; d4 uuid; d5 uuid; v uuid; i int; k int;
  today date := (now() at time zone 'Asia/Kolkata')::date; m date; it record;
begin
  select array_agg(id order by employee_code) into people from hrm.employees where tenant_id = t and email like '%@demo.kmr.test' and status = 'active';
  if coalesce(array_length(people, 1), 0) < 12 then return 0; end if;
  if exists (select 1 from hrm.documents where tenant_id = t and sample) then return 0; end if;
  perform hrm.seed_compliance_defaults(t);
  select id into hrd from hrm.departments where tenant_id = t and name ilike 'Human Resources%' limit 1;

  insert into hrm.documents (tenant_id, doc_no, title, kind, owner_department_id, owner_name, employee_access, needs_ack, review_months, sample, created_by_name)
  values (t, 'S-HR-POL-01', 'Code of conduct', 'policy', hrd, 'HR Manager', true, true, 24, true, 'HR (sample)') returning id into d1;
  insert into hrm.document_versions (tenant_id, document_id, revision, body, change_note, status, prepared_by_name, approved_by_name, approved_at, effective_from, review_due)
  values (t, d1, 0, '1. Purpose' || chr(10) || 'To set out how everybody at the company is expected to behave at work.' || chr(10) || chr(10) ||
    '2. Scope' || chr(10) || 'All employees, trainees, contract workers and visitors.' || chr(10) || chr(10) ||
    '3. What we expect' || chr(10) || '- Treat everybody with respect; no abuse, harassment or discrimination.' || chr(10) || '- Follow the safety rules and wear the PPE of your area.' || chr(10) ||
    '- Report quality problems at once; never pass a doubtful part.' || chr(10) || '- No alcohol or drugs at work; no smoking outside the smoking zone.' || chr(10) ||
    '- Do not accept gifts or money from suppliers or customers.' || chr(10) || '- Keep company and customer information confidential.' || chr(10) || chr(10) ||
    '4. If the code is broken' || chr(10) || 'Tell your supervisor or HR. Action is taken as per the certified standing orders.',
    'First issue', 'approved', 'HR Executive (sample)', 'HR Manager (sample)', now() - interval '200 days', today - 200, today + 530) returning id into v;
  for i in 1..15 loop insert into hrm.document_acks (tenant_id, version_id, employee_id, acknowledged_at) values (t, v, people[i], now() - make_interval(days => 190 - i)); end loop;

  insert into hrm.documents (tenant_id, doc_no, title, kind, owner_department_id, owner_name, employee_access, needs_ack, sample, created_by_name)
  values (t, 'S-HR-POL-02', 'Prevention of sexual harassment (POSH) policy', 'policy', hrd, 'HR Manager', true, true, true, 'HR (sample)') returning id into d2;
  insert into hrm.document_versions (tenant_id, document_id, revision, body, change_note, status, prepared_by_name, approved_by_name, approved_at, effective_from, review_due)
  values (t, d2, 1, '1. Purpose' || chr(10) || 'A workplace free of sexual harassment, as required by the POSH Act, 2013.' || chr(10) || chr(10) ||
    '2. Internal Committee' || chr(10) || 'The Internal Committee (names on the notice board) receives and enquires into complaints. A complaint can be made in writing within 3 months of the incident.' || chr(10) || chr(10) ||
    '3. Confidentiality' || chr(10) || 'The complaint, the names and the enquiry are kept confidential.' || chr(10) || chr(10) ||
    '4. No retaliation' || chr(10) || 'Nobody is punished for making a complaint in good faith.',
    'Internal Committee members updated', 'approved', 'HR Executive (sample)', 'Plant Head (sample)', now() - interval '40 days', today - 40, today + 325) returning id into v;
  for i in 1..9 loop insert into hrm.document_acks (tenant_id, version_id, employee_id, acknowledged_at) values (t, v, people[i], now() - make_interval(days => 39 - i)); end loop;

  insert into hrm.documents (tenant_id, doc_no, title, kind, owner_department_id, owner_name, employee_access, needs_ack, review_months, sample, created_by_name)
  values (t, 'S-HR-P-01', 'Recruitment and selection procedure', 'procedure', hrd, 'HR Manager', false, false, 12, true, 'HR (sample)') returning id into d3;
  insert into hrm.document_versions (tenant_id, document_id, revision, body, change_note, status, prepared_by_name, approved_by_name, approved_at, effective_from, review_due)
  values (t, d3, 1, 'Requisition → job description → sourcing → screening → interview → offer → joining, as in the HRM.', 'Old revision', 'obsolete', 'HR (sample)', 'Plant Head (sample)', now() - interval '700 days', today - 700, today - 335),
         (t, d3, 2, '1. Requisition: the department raises it in the HRM with the position, role and department.' || chr(10) || '2. Job description: written for the position and approved by HR.' || chr(10) ||
          '3. Screening: resumes scored against the must-have competencies.' || chr(10) || '4. Interview: a panel of at least two; scorecards in the HRM.' || chr(10) || '5. Offer and joining: offer letter, acceptance, self-onboarding, induction.',
          'Now done in the HRM', 'approved', 'HR (sample)', 'Plant Head (sample)', now() - interval '380 days', today - 380, today - 15);
  insert into hrm.documents (tenant_id, doc_no, title, kind, owner_department_id, owner_name, employee_access, needs_ack, sample, created_by_name)
  values (t, 'S-HR-P-02', 'Competence, training and awareness procedure', 'procedure', hrd, 'HR Manager', false, false, true, 'HR (sample)') returning id into d4;
  insert into hrm.document_versions (tenant_id, document_id, revision, body, change_note, status, prepared_by_name, approved_by_name, approved_at, effective_from, review_due)
  values (t, d4, 0, 'Skill matrix, competency mapping, training needs, training plan, effectiveness and on-the-job training are kept in HRM › QMS & training (IATF 16949 7.2, 7.3).', 'First issue', 'approved', 'HR (sample)', 'Plant Head (sample)', now() - interval '90 days', today - 90, today + 275);
  insert into hrm.documents (tenant_id, doc_no, title, kind, owner_department_id, owner_name, employee_access, needs_ack, sample, created_by_name)
  values (t, 'S-HR-POL-03', 'Leave policy', 'policy', hrd, 'HR Manager', true, true, true, 'HR (sample)') returning id into d5;
  insert into hrm.document_versions (tenant_id, document_id, revision, body, change_note, status, prepared_by_name)
  values (t, d5, 0, 'Draft: casual, sick and earned leave as set in HRM › Leave policy. How to apply, who approves, carry forward and encashment.', 'First issue', 'draft', 'HR (sample)');
  n := n + 5;

  -- compliance: the last three months of the monthly items (one filed late, one still open), a licence near expiry
  insert into hrm.compliance_items (tenant_id, code, title, law, kind, frequency, due_day, state, licence_no, valid_until, renew_days, owner_name, sample, notes)
  values (t, 'S-LIC-BOILER', 'Boiler certificate — renewal (sample)', 'Boilers Act, 1923', 'licence', 'once', 1, 'Karnataka', 'KA/BLR/BC/2025/0098', today + 40, 60, 'Maintenance Head', true, 'Sample licence close to its renewal date.')
  on conflict (tenant_id, code) do nothing;
  for it in select id, code, due_day from hrm.compliance_items where tenant_id = t and code in ('PF','ESI','PT','TDS') loop
    k := 0;
    for i in 0..4 loop
      m := (date_trunc('month', today) - make_interval(months => i))::date;
      m := m + (least(it.due_day, extract(day from (m + interval '1 month - 1 day'))::int) - 1);
      if m > today or k >= 3 then continue; end if;
      k := k + 1;                                   -- k = 1 is the latest one that has fallen due
      insert into hrm.compliance_tasks (tenant_id, item_id, due_on, status, done_on, done_by_name, reference, note, sample)
      values (t, it.id, m, case when it.code = 'PT' and k = 1 then 'open' else 'done' end,
        case when it.code = 'PT' and k = 1 then null when it.code = 'ESI' and k = 2 then m + 3 else m - 2 end,
        case when it.code = 'PT' and k = 1 then null else 'Payroll (sample)' end,
        case when it.code = 'PT' and k = 1 then null else it.code || '/' || to_char(m, 'YYYYMM') || '/S' || k end,
        case when it.code = 'ESI' and k = 2 then 'Paid 3 days late — portal was down' end, true)
      on conflict (item_id, due_on) do nothing;
      n := n + 1;
    end loop;
  end loop;
  return n;
end $fn$;

create or replace function hrm.demo_flow(p_tenant uuid) returns jsonb
language plpgsql security definer set search_path = hrm, public as $fn$
declare r int; q int; g int; c int;
begin
  r := hrm.demo_recruit(p_tenant);
  q := hrm.demo_qms(p_tenant);
  g := hrm.demo_engage(p_tenant);
  c := hrm.demo_compliance(p_tenant);
  return jsonb_build_object('recruitment', r, 'qms', q, 'engagement', g, 'compliance', c);
end $fn$;
revoke all on function hrm.demo_compliance(uuid), hrm.demo_flow(uuid) from public, anon, authenticated;
grant execute on function hrm.demo_compliance(uuid), hrm.demo_flow(uuid) to service_role;

do $$ declare r uuid; begin
  for r in select distinct tenant_id from hrm.employees where email like '%@demo.kmr.test' loop perform hrm.demo_compliance(r); end loop;
end $$;

notify pgrst, 'reload schema';
