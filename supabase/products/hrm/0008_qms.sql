-- =====================================================================
-- HRM Phase 5A — QMS people development (IATF 16949 7.2 / 7.3, ISO 9001 5.3, 6.2, 7.2, 9.1). Needs 0001–0007.
-- Safe to re-run.
--  • Roles & responsibilities per designation, with authority, deputy and interfaces; employees acknowledge them
--  • KPIs per designation, monthly values per employee, scorecards
--  • Competency library, required level per designation, assessed level per employee → gaps
--  • Skill matrix: operations / machines × people, levels 0–4; alerts when a line is short of qualified people
--  • Training needs (TNI) from gaps, new joiners, changes, complaints, audit findings and requests
--  • Training programmes, sessions (the plan), attendance (by ID-card scan or by hand), pre/post test, sign-off
--  • Training effectiveness by the supervisor after 30/60/90 days; not effective → retraining need
--  • On-the-job training checklists (incl. customer-specific requirements and consequences of nonconformity)
--  • Internal auditor register and audits done
-- Who sees what: HR (and company admins) everything; a reporting manager his team's records, and he assesses skills,
-- enters KPI values and evaluates training effectiveness for his team; each employee his own records.
-- Everything marked "sample" (and everything of the sample people) is sample data: the sample flush removes it.
-- =====================================================================

-- ---------- settings ----------
create table if not exists hrm.qms_settings (
  tenant_id        uuid primary key references hrm.tenants(id) on delete cascade,
  quality_policy   text check (length(quality_policy) <= 3000),
  objectives       text[] not null default '{}',             -- quality objectives employees must know
  csr              text[] not null default '{}',             -- customer-specific requirements for awareness
  min_qualified    integer not null default 2 check (min_qualified between 1 and 20),   -- per operation, level 3 or 4
  eff_days         integer not null default 30 check (eff_days in (30, 60, 90)),        -- effectiveness check after
  new_joiner_days  integer not null default 30 check (new_joiner_days between 1 and 180),
  updated_at       timestamptz not null default now()
);

-- ---------- roles & responsibilities (ISO 9001 5.3) ----------
create table if not exists hrm.rr_roles (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references hrm.tenants(id) on delete cascade,
  designation_id   uuid not null references hrm.designations(id) on delete cascade,
  department_id    uuid references hrm.departments(id) on delete set null,   -- blank = the designation in every department
  purpose          text check (length(purpose) <= 1500),
  responsibilities text[] not null default '{}',
  authorities      text[] not null default '{}',             -- e.g. "Stop the line on a quality doubt"
  deputy           text check (length(deputy) <= 120),      -- who stands in when the person is away
  interfaces       text[] not null default '{}',             -- internal / external contacts
  version          integer not null default 1,
  status           text not null default 'draft' check (status in ('draft','approved')),
  approved_by      uuid,
  approved_at      timestamptz,
  sample           boolean not null default false,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create unique index if not exists rr_roles_desig on hrm.rr_roles (tenant_id, designation_id, coalesce(department_id, '00000000-0000-0000-0000-000000000000'::uuid));

create table if not exists hrm.rr_acks (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references hrm.tenants(id) on delete cascade,
  rr_id            uuid not null references hrm.rr_roles(id) on delete cascade,
  employee_id      uuid not null references hrm.employees(id) on delete cascade,
  version          integer not null,
  acknowledged_at  timestamptz not null default now(),
  unique (rr_id, employee_id, version)
);

-- ---------- KPIs (ISO 9001 6.2, 9.1) ----------
create table if not exists hrm.kpis (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references hrm.tenants(id) on delete cascade,
  designation_id   uuid references hrm.designations(id) on delete cascade,
  department_id    uuid references hrm.departments(id) on delete cascade,
  name             text not null check (length(name) between 2 and 120),
  unit             text check (length(unit) <= 20),
  target           numeric(14,3) not null,
  direction        text not null default 'higher' check (direction in ('higher','lower')),   -- higher / lower is better
  frequency        text not null default 'monthly' check (frequency in ('monthly','quarterly')),
  data_source      text check (length(data_source) <= 200),
  weight           integer not null default 1 check (weight between 1 and 5),
  active           boolean not null default true,
  sample           boolean not null default false,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create index if not exists kpis_desig on hrm.kpis (tenant_id, designation_id);

create table if not exists hrm.kpi_values (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references hrm.tenants(id) on delete cascade,
  kpi_id           uuid not null references hrm.kpis(id) on delete cascade,
  employee_id      uuid not null references hrm.employees(id) on delete cascade,
  month            text not null check (month ~ '^\d{4}-(0[1-9]|1[0-2])$'),
  actual           numeric(14,3) not null,
  note             text check (length(note) <= 300),
  entered_by       uuid,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  unique (kpi_id, employee_id, month)
);

-- ---------- competencies (IATF 7.2.1, ISO 9001 7.2) ----------
create table if not exists hrm.competencies (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references hrm.tenants(id) on delete cascade,
  name             text not null check (length(name) between 2 and 120),
  category         text not null default 'technical' check (category in ('technical','quality','safety','behavioural','management')),
  description      text check (length(description) <= 600),
  active           boolean not null default true,
  sample           boolean not null default false,
  created_at       timestamptz not null default now(),
  unique (tenant_id, name)
);

create table if not exists hrm.role_competencies (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references hrm.tenants(id) on delete cascade,
  designation_id   uuid not null references hrm.designations(id) on delete cascade,
  competency_id    uuid not null references hrm.competencies(id) on delete cascade,
  required_level   integer not null check (required_level between 1 and 4),
  sample           boolean not null default false,
  unique (designation_id, competency_id)
);

create table if not exists hrm.employee_competencies (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references hrm.tenants(id) on delete cascade,
  employee_id      uuid not null references hrm.employees(id) on delete cascade,
  competency_id    uuid not null references hrm.competencies(id) on delete cascade,
  level            integer not null check (level between 0 and 4),
  assessed_on      date not null default current_date,
  assessed_by      uuid,
  assessed_by_name text,
  method           text check (method in ('observation','test','interview','records','certificate','training')),
  note             text check (length(note) <= 300),
  updated_at       timestamptz not null default now(),
  unique (employee_id, competency_id)
);

-- ---------- skill matrix (IATF 7.2.1, 7.2.3) ----------
create table if not exists hrm.operations (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references hrm.tenants(id) on delete cascade,
  plant_id         uuid references hrm.plants(id) on delete set null,
  line             text not null check (length(line) between 1 and 80),       -- line / cell / area
  code             text not null check (length(code) between 1 and 20),       -- e.g. OP10
  name             text not null check (length(name) between 2 and 120),
  machine          text check (length(machine) <= 80),
  critical         boolean not null default false,          -- special / safety characteristic: never without a qualified person
  min_qualified    integer check (min_qualified between 1 and 20),   -- blank = the company setting
  safety_required  boolean not null default false,          -- safety training needed before working here
  sort_order       integer not null default 0,
  active           boolean not null default true,
  sample           boolean not null default false,
  created_at       timestamptz not null default now(),
  unique (tenant_id, line, code)
);

create table if not exists hrm.skill_levels (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references hrm.tenants(id) on delete cascade,
  employee_id      uuid not null references hrm.employees(id) on delete cascade,
  operation_id     uuid not null references hrm.operations(id) on delete cascade,
  level            integer not null check (level between 0 and 4),
  certified_on     date,
  valid_until      date,                                    -- re-certification due
  assessed_by      uuid,
  assessed_by_name text,
  note             text check (length(note) <= 300),
  updated_at       timestamptz not null default now(),
  unique (employee_id, operation_id)
);

-- ---------- training programmes, sessions, attendance (ISO 9001 7.2, IATF 7.2.1, 7.3) ----------
create table if not exists hrm.training_programs (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references hrm.tenants(id) on delete cascade,
  title            text not null check (length(title) between 2 and 160),
  category         text not null default 'technical' check (category in ('induction','safety','quality','technical','awareness','core_tools','behavioural','ojt')),
  competency_id    uuid references hrm.competencies(id) on delete set null,
  operation_id     uuid references hrm.operations(id) on delete set null,
  duration_hours   numeric(5,1) not null default 2 check (duration_hours > 0 and duration_hours <= 200),
  eval_method      text not null default 'observation' check (eval_method in ('test','observation','kpi','signoff')),
  eff_days         integer check (eff_days in (30, 60, 90)),          -- blank = company setting; sign-off has none
  pass_mark        integer not null default 60 check (pass_mark between 0 and 100),
  content          text check (length(content) <= 3000),
  active           boolean not null default true,
  sample           boolean not null default false,
  created_at       timestamptz not null default now(),
  unique (tenant_id, title)
);

create table if not exists hrm.training_sessions (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references hrm.tenants(id) on delete cascade,
  program_id       uuid not null references hrm.training_programs(id) on delete cascade,
  plan_month       text not null check (plan_month ~ '^\d{4}-(0[1-9]|1[0-2])$'),
  starts_at        timestamptz,                             -- blank while only planned for the month
  ends_at          timestamptz,
  venue            text check (length(venue) <= 120),
  trainer          text check (length(trainer) <= 120),
  trainer_employee_id uuid references hrm.employees(id) on delete set null,
  status           text not null default 'planned' check (status in ('planned','scheduled','done','cancelled')),
  notes            text check (length(notes) <= 1000),
  invited_at       timestamptz,
  reminded_at      timestamptz,
  completed_at     timestamptz,
  sample           boolean not null default false,
  created_by       uuid,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create index if not exists training_sessions_month on hrm.training_sessions (tenant_id, plan_month);

create table if not exists hrm.training_needs (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references hrm.tenants(id) on delete cascade,
  employee_id      uuid not null references hrm.employees(id) on delete cascade,
  program_id       uuid references hrm.training_programs(id) on delete set null,
  competency_id    uuid references hrm.competencies(id) on delete set null,
  operation_id     uuid references hrm.operations(id) on delete set null,
  topic            text not null check (length(topic) between 2 and 200),
  source           text not null check (source in ('competency_gap','skill_gap','new_joiner','process_change','customer_complaint','audit_finding','request','retraining','awareness','recertification')),
  reason           text check (length(reason) <= 500),
  priority         text not null default 'normal' check (priority in ('high','normal','low')),
  status           text not null default 'open' check (status in ('open','planned','trained','closed','cancelled')),
  target_month     text check (target_month ~ '^\d{4}-(0[1-9]|1[0-2])$'),
  session_id       uuid references hrm.training_sessions(id) on delete set null,
  raised_by        uuid,
  raised_by_name   text,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create index if not exists training_needs_open on hrm.training_needs (tenant_id, status);
-- one open need per person for the same thing (re-running "Find training needs" adds nothing twice)
create unique index if not exists training_needs_once on hrm.training_needs (employee_id, source, coalesce(competency_id, operation_id, program_id))
  where status in ('open','planned') and coalesce(competency_id, operation_id, program_id) is not null;

create table if not exists hrm.training_attendance (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references hrm.tenants(id) on delete cascade,
  session_id       uuid not null references hrm.training_sessions(id) on delete cascade,
  employee_id      uuid not null references hrm.employees(id) on delete cascade,
  need_id          uuid references hrm.training_needs(id) on delete set null,
  attended         boolean,                                 -- null = not marked yet
  method           text check (method in ('scan','manual','biometric')),
  marked_at        timestamptz,
  pre_score        integer check (pre_score between 0 and 100),
  post_score       integer check (post_score between 0 and 100),
  acknowledged_at  timestamptz,                             -- awareness sign-off by the employee
  unique (session_id, employee_id)
);

create table if not exists hrm.training_effectiveness (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references hrm.tenants(id) on delete cascade,
  attendance_id    uuid not null unique references hrm.training_attendance(id) on delete cascade,
  employee_id      uuid not null references hrm.employees(id) on delete cascade,
  session_id       uuid not null references hrm.training_sessions(id) on delete cascade,
  due_on           date not null,
  evaluator_id     uuid references hrm.employees(id) on delete set null,     -- the supervisor who evaluates
  result           text check (result in ('effective','partly','not_effective')),
  rating           integer check (rating between 1 and 5),
  evidence         text check (length(evidence) <= 600),     -- what was observed / KPI change
  evaluated_by     uuid,
  evaluated_by_name text,
  evaluated_at     timestamptz,
  retrain_need_id  uuid references hrm.training_needs(id) on delete set null,
  notified_at      timestamptz,
  created_at       timestamptz not null default now()
);
create index if not exists training_eff_due on hrm.training_effectiveness (tenant_id, due_on) where result is null;

-- ---------- on-the-job training (IATF 7.2.2) ----------
create table if not exists hrm.ojt_templates (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references hrm.tenants(id) on delete cascade,
  title            text not null check (length(title) between 2 and 160),
  designation_id   uuid references hrm.designations(id) on delete set null,
  operation_id     uuid references hrm.operations(id) on delete set null,
  items            jsonb not null default '[]',             -- [{text, kind: task | csr | nc}]
  days             integer not null default 15 check (days between 1 and 180),
  active           boolean not null default true,
  sample           boolean not null default false,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

create table if not exists hrm.ojt_records (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references hrm.tenants(id) on delete cascade,
  template_id      uuid not null references hrm.ojt_templates(id) on delete cascade,
  employee_id      uuid not null references hrm.employees(id) on delete cascade,
  trainer          text check (length(trainer) <= 120),
  started_on       date not null default current_date,
  done             jsonb not null default '[]',             -- indexes of the items completed
  status           text not null default 'in_progress' check (status in ('in_progress','completed','cancelled')),
  completed_on     date,
  signed_off_by    uuid,
  signed_off_name  text,
  remarks          text check (length(remarks) <= 500),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  unique (template_id, employee_id)
);

-- ---------- internal auditors (IATF 7.2.3) ----------
create table if not exists hrm.auditors (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references hrm.tenants(id) on delete cascade,
  employee_id      uuid not null references hrm.employees(id) on delete cascade,
  kind             text not null default 'qms' check (kind in ('qms','process','product','supplier')),
  standards        text[] not null default '{}',             -- IATF 16949, ISO 9001, VDA 6.3, ISO 14001, ISO 45001
  qualification    text check (length(qualification) <= 200),
  trained_on       date,
  certificate_no   text check (length(certificate_no) <= 60),
  valid_until      date,
  core_tools       text[] not null default '{}',             -- APQP, PPAP, FMEA, SPC, MSA
  csr_trained      boolean not null default false,
  audits_per_year  integer not null default 2 check (audits_per_year between 0 and 50),   -- to keep the qualification
  active           boolean not null default true,
  notified_at      timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  unique (employee_id, kind)
);

create table if not exists hrm.auditor_audits (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references hrm.tenants(id) on delete cascade,
  auditor_id       uuid not null references hrm.auditors(id) on delete cascade,
  audit_date       date not null,
  area             text not null check (length(area) between 2 and 160),
  audit_type       text not null default 'system' check (audit_type in ('system','process','product','supplier','layered')),
  role             text not null default 'auditor' check (role in ('lead','auditor','observer')),
  findings         integer check (findings between 0 and 500),
  created_at       timestamptz not null default now()
);

-- ---------- updated_at + audit trail ----------
do $$ declare t text; begin
  foreach t in array array['qms_settings','rr_roles','kpis','kpi_values','employee_competencies','skill_levels','training_sessions','training_needs','ojt_templates','ojt_records','auditors'] loop
    execute format('drop trigger if exists %I on hrm.%I', t || '_touch', t);
    execute format('create trigger %I before update on hrm.%I for each row execute function hrm.touch_updated_at()', t || '_touch', t);
  end loop;
  foreach t in array array['qms_settings','rr_roles','rr_acks','kpis','kpi_values','competencies','role_competencies','employee_competencies','operations','skill_levels',
    'training_programs','training_sessions','training_needs','training_attendance','training_effectiveness','ojt_templates','ojt_records','auditors','auditor_audits'] loop
    execute format('drop trigger if exists %I on hrm.%I', t || '_audit', t);
    execute format('create trigger %I after insert or update or delete on hrm.%I for each row execute function hrm.audit_row()', t || '_audit', t);
  end loop;
end $$;

-- ---------- access ----------
do $$
declare t text;
begin
  foreach t in array array['qms_settings','rr_roles','rr_acks','kpis','kpi_values','competencies','role_competencies','employee_competencies','operations','skill_levels',
    'training_programs','training_sessions','training_needs','training_attendance','training_effectiveness','ojt_templates','ojt_records','auditors','auditor_audits'] loop
    execute format('alter table hrm.%I enable row level security', t);
    execute format('drop policy if exists %I on hrm.%I', t || '_hr', t);
    execute format('create policy %I on hrm.%I for all to authenticated using (tenant_id = hrm.current_tenant_id() and hrm.is_hr()) with check (tenant_id = hrm.current_tenant_id() and hrm.is_hr())', t || '_hr', t);
  end loop;
  -- the company's libraries: everyone in the company reads them
  foreach t in array array['qms_settings','rr_roles','kpis','competencies','role_competencies','operations','training_programs','training_sessions','ojt_templates'] loop
    execute format('drop policy if exists %I on hrm.%I', t || '_read', t);
    execute format('create policy %I on hrm.%I for select to authenticated using (tenant_id = hrm.current_tenant_id())', t || '_read', t);
  end loop;
  -- each employee: his own records
  foreach t in array array['rr_acks','kpi_values','employee_competencies','skill_levels','training_needs','training_attendance','training_effectiveness','ojt_records','auditors'] loop
    execute format('drop policy if exists %I on hrm.%I', t || '_self', t);
    execute format('create policy %I on hrm.%I for select to authenticated using (tenant_id = hrm.current_tenant_id() and employee_id = hrm.current_employee_id())', t || '_self', t);
  end loop;
  -- a reporting manager: his team's records
  foreach t in array array['rr_acks','kpi_values','employee_competencies','skill_levels','training_needs','training_attendance','training_effectiveness','ojt_records'] loop
    execute format('drop policy if exists %I on hrm.%I', t || '_team', t);
    execute format('create policy %I on hrm.%I for select to authenticated using (tenant_id = hrm.current_tenant_id() and hrm.has_role(''manager'') and hrm.is_in_my_team(employee_id))', t || '_team', t);
  end loop;
  -- … and he assesses skills and competencies, enters KPI values and asks for training for his team
  foreach t in array array['kpi_values','employee_competencies','skill_levels','ojt_records'] loop
    execute format('drop policy if exists %I on hrm.%I', t || '_team_write', t);
    execute format('create policy %I on hrm.%I for insert to authenticated with check (tenant_id = hrm.current_tenant_id() and hrm.has_role(''manager'') and hrm.is_in_my_team(employee_id))', t || '_team_write', t);
    execute format('drop policy if exists %I on hrm.%I', t || '_team_edit', t);
    execute format('create policy %I on hrm.%I for update to authenticated using (tenant_id = hrm.current_tenant_id() and hrm.has_role(''manager'') and hrm.is_in_my_team(employee_id)) with check (tenant_id = hrm.current_tenant_id() and hrm.is_in_my_team(employee_id))', t || '_team_edit', t);
  end loop;
end $$;
drop policy if exists training_needs_team_write on hrm.training_needs;
create policy training_needs_team_write on hrm.training_needs for insert to authenticated
  with check (tenant_id = hrm.current_tenant_id() and hrm.has_role('manager') and hrm.is_in_my_team(employee_id) and source = 'request' and status = 'open');
drop policy if exists training_effectiveness_team_edit on hrm.training_effectiveness;
create policy training_effectiveness_team_edit on hrm.training_effectiveness for update to authenticated
  using (tenant_id = hrm.current_tenant_id() and hrm.has_role('manager') and hrm.is_in_my_team(employee_id))
  with check (tenant_id = hrm.current_tenant_id() and hrm.is_in_my_team(employee_id));
-- the audits an auditor did
drop policy if exists auditor_audits_self on hrm.auditor_audits;
create policy auditor_audits_self on hrm.auditor_audits for select to authenticated
  using (tenant_id = hrm.current_tenant_id() and exists (select 1 from hrm.auditors a where a.id = auditor_id and a.employee_id = hrm.current_employee_id()));

-- ---------- defaults for a company: a ready competency library and training programmes ----------
create or replace function hrm.seed_qms_defaults(p_tenant uuid) returns void
language plpgsql security definer set search_path = hrm, public as $fn$
begin
  insert into hrm.qms_settings (tenant_id, objectives) values (p_tenant, array[
    'Customer PPM below the target agreed with each customer',
    'On-time delivery 98% or better',
    'Every person trained and qualified before working alone on an operation'])
  on conflict do nothing;
  insert into hrm.competencies (tenant_id, name, category, description)
  select p_tenant, x.n, x.c, x.d from (values
    ('Reading drawings & GD&T', 'technical', 'Reads dimensions, tolerances, fits, GD&T and notes on the drawing'),
    ('Measuring instruments', 'technical', 'Vernier, micrometer, bore gauge, height gauge, plug / snap gauges; zero setting and care'),
    ('Machine setting & first-off approval', 'technical', 'Sets the machine as per the set-up sheet and gets the first piece approved'),
    ('CNC operation', 'technical', 'Runs CNC turning / milling as per the work instruction; offsets, tool change, alarms'),
    ('Preventive & autonomous maintenance', 'technical', 'Daily checklist, lubrication, cleaning, abnormality tagging; PM as per schedule'),
    ('Control plan & work instructions', 'quality', 'Follows the control plan, reaction plan and work instruction at the station'),
    ('Core tools — APQP & PPAP', 'quality', 'Plans a new part launch and prepares the PPAP elements'),
    ('Core tools — FMEA', 'quality', 'Builds and reviews PFMEA (AIAG-VDA), action priority'),
    ('Core tools — SPC & MSA', 'quality', 'Control charts, Cp/Cpk, GR&R, bias and linearity'),
    ('Problem solving (8D, why-why)', 'quality', 'Containment, root cause, corrective and preventive action, effectiveness'),
    ('Internal auditing', 'quality', 'Plans and conducts system / process / product audits; writes findings'),
    ('Safety rules & PPE', 'safety', 'Follows the safety rules of the shop and wears the right PPE'),
    ('Fire safety & emergency', 'safety', 'Raises the alarm, uses an extinguisher, evacuates by the route'),
    ('Lock-out tag-out & machine guarding', 'safety', 'Isolates energy before maintenance; never bypasses a guard'),
    ('5S & workplace discipline', 'behavioural', 'Sort, set in order, shine, standardise, sustain at the workplace'),
    ('Communication & teamwork', 'behavioural', 'Shift handover, reporting problems, working with other departments'),
    ('Leadership & people management', 'management', 'Plans manpower, sets targets, reviews and develops the team'),
    ('Lean & Kaizen', 'management', 'Finds waste and makes small improvements that last')
  ) x(n, c, d)
  on conflict (tenant_id, name) do nothing;
  insert into hrm.training_programs (tenant_id, title, category, competency_id, duration_hours, eval_method, eff_days, pass_mark, content)
  select p_tenant, x.t, x.c, (select id from hrm.competencies where tenant_id = p_tenant and name = x.comp), x.h, x.m, x.e, x.p, x.content from (values
    ('Induction — company, HR rules and facilities', 'induction', null, 4.0, 'signoff', null::int, 60, 'Company, products and customers; standing orders; attendance and leave; canteen, transport, first aid'),
    ('Safety induction', 'safety', 'Safety rules & PPE', 3.0, 'test', 30, 70, 'Shop safety rules, PPE, hazards, near-miss reporting, emergency exits'),
    ('Quality policy, objectives & product safety', 'awareness', null, 1.0, 'signoff', null, 60, 'The quality policy and objectives, how each person contributes, product safety (IATF 7.3)'),
    ('Customer-specific requirements', 'awareness', null, 1.0, 'signoff', null, 60, 'What each customer asks for beyond the standard, and how it applies at the workplace'),
    ('Consequences of nonconformity', 'awareness', null, 1.0, 'signoff', null, 60, 'What happens to the customer and the end user when a bad part goes out'),
    ('Measuring instruments & first-off inspection', 'technical', 'Measuring instruments', 4.0, 'observation', 30, 70, 'Instruments, zero setting, recording, first-off approval'),
    ('Reading drawings & GD&T', 'technical', 'Reading drawings & GD&T', 6.0, 'test', 60, 70, 'Views, dimensions, tolerances, fits, GD&T symbols, notes'),
    ('5S & workplace discipline', 'behavioural', '5S & workplace discipline', 2.0, 'observation', 30, 60, 'The 5 steps, red tags, audits'),
    ('Core tools — FMEA', 'core_tools', 'Core tools — FMEA', 8.0, 'test', 90, 70, 'AIAG-VDA FMEA 7 steps, action priority'),
    ('Core tools — SPC & MSA', 'core_tools', 'Core tools — SPC & MSA', 8.0, 'test', 90, 70, 'Control charts, capability, GR&R'),
    ('Problem solving — 8D', 'quality', 'Problem solving (8D, why-why)', 4.0, 'kpi', 90, 60, '8 disciplines with a real case'),
    ('IATF 16949 internal auditor', 'quality', 'Internal auditing', 16.0, 'test', 90, 70, 'Process approach, turtle diagram, audit plan, findings, CSR'),
    ('Fire safety & evacuation drill', 'safety', 'Fire safety & emergency', 2.0, 'observation', 30, 60, 'Fire classes, extinguishers, evacuation and assembly point'),
    ('Lock-out tag-out', 'safety', 'Lock-out tag-out & machine guarding', 2.0, 'observation', 30, 70, 'Energy sources, isolation, locks and tags, try-out')
  ) x(t, c, comp, h, m, e, p, content)
  on conflict (tenant_id, title) do nothing;
end $fn$;
revoke all on function hrm.seed_qms_defaults(uuid) from public, anon, authenticated;
grant execute on function hrm.seed_qms_defaults(uuid) to service_role;
-- every new company gets the payroll, recruitment and QMS defaults the moment it is created (the console's
-- "add customer", the HRM's own setup file, scripts/create-tenant.mjs) — and the companies already there get them now
create or replace function hrm.seed_new_tenant() returns trigger
language plpgsql security definer set search_path = hrm, public as $fn$
begin
  if to_regprocedure('hrm.seed_payroll_defaults(uuid)') is not null then perform hrm.seed_payroll_defaults(new.id); end if;
  if to_regprocedure('hrm.seed_recruit_defaults(uuid)') is not null then perform hrm.seed_recruit_defaults(new.id); end if;
  perform hrm.seed_qms_defaults(new.id);
  return new;
end $fn$;
drop trigger if exists tenants_seed_modules on hrm.tenants;
create trigger tenants_seed_modules after insert on hrm.tenants for each row execute function hrm.seed_new_tenant();
do $$ declare t uuid; begin for t in select id from hrm.tenants loop
  perform hrm.seed_payroll_defaults(t); perform hrm.seed_recruit_defaults(t); perform hrm.seed_qms_defaults(t);
end loop; end $$;

-- ---------- clearing: one function every flush calls (later modules add their tables here) ----------
-- p_mode 'all'    — everything (the Data Master's full HRM flush); the default library comes back
--        'real'   — the company's own records; sample records stay (Grand Master › Flush real data). The competency
--                   library and training programmes are company setup (like plants and designations) and stay.
--        'sample' — sample records only (Grand Master › Flush sample data)
-- Records of people go with the people (the flushes delete the employees); this clears the company-level lists.
create or replace function hrm.module_flush(p_tenant uuid, p_mode text default 'all') returns integer
language plpgsql security definer set search_path = hrm, public as $fn$
declare t text; n int := 0; k int;
  lists text[] := case when p_mode = 'real' then array['training_sessions','ojt_templates','kpis','rr_roles','role_competencies','operations']
                       else array['training_sessions','ojt_templates','training_programs','kpis','rr_roles','role_competencies','operations','competencies'] end;
begin
  if p_mode not in ('all','real','sample') then raise exception 'Unknown flush mode %', p_mode; end if;
  if p_mode = 'all' then
    foreach t in array array['auditor_audits','auditors','ojt_records','training_effectiveness','training_attendance','training_needs','kpi_values','rr_acks','skill_levels','employee_competencies'] loop
      execute format('delete from hrm.%I where tenant_id = $1', t) using p_tenant; get diagnostics k = row_count; n := n + k;
    end loop;
    delete from hrm.qms_settings where tenant_id = p_tenant;
  end if;
  foreach t in array lists loop
    execute format('delete from hrm.%I where tenant_id = $1 and (%s)', t,
      case p_mode when 'all' then 'true' when 'real' then 'not sample' else 'sample' end) using p_tenant;
    get diagnostics k = row_count; n := n + k;
  end loop;
  if p_mode = 'all' then perform hrm.seed_qms_defaults(p_tenant); end if;
  return n;
end $fn$;
revoke all on function hrm.module_flush(uuid, text) from public, anon, authenticated;
grant execute on function hrm.module_flush(uuid, text) to service_role;

-- ---------- backups include the QMS records ----------
create or replace function hrm.company_export(p_tenant uuid) returns jsonb
language plpgsql stable security definer set search_path = hrm, public as $fn$
declare out jsonb := '{}'::jsonb; t text; rows jsonb;
begin
  foreach t in array array['plants','departments','designations','shifts','holidays','leave_types','notification_templates',
    'employees','employee_private','onboarding_invites','employee_documents','id_cards','attendance_devices',
    'attendance_punches','attendance_days','regularisation_requests','leave_requests','leave_ledger',
    'pay_settings','pay_components','salary_structures','loans','payroll_runs','payroll_lines','loan_recoveries',
    'recruit_settings','job_descriptions','requisitions','candidates','applications','interviews','interview_feedback','offers',
    'qms_settings','competencies','operations','role_competencies','rr_roles','rr_acks','kpis','kpi_values','employee_competencies','skill_levels',
    'training_programs','training_sessions','training_needs','training_attendance','training_effectiveness','ojt_templates','ojt_records','auditors','auditor_audits'] loop
    if to_regclass('hrm.' || t) is null then continue; end if;
    if t in ('employee_private') then
      execute format('select coalesce(jsonb_agg(to_jsonb(x)), ''[]'') from hrm.%I x where x.employee_id in (select id from hrm.employees where tenant_id = $1)', t) into rows using p_tenant;
    else
      execute format('select coalesce(jsonb_agg(to_jsonb(x)), ''[]'') from hrm.%I x where x.tenant_id = $1', t) into rows using p_tenant;
    end if;
    out := out || jsonb_build_object(t, rows);
  end loop;
  return jsonb_build_object('format', 'kmr-hrm-backup', 'version', 4, 'exported_at', now(),
    'company', (select to_jsonb(x) - 'id' from hrm.tenants x where id = p_tenant), 'tenant_id', p_tenant, 'tables', out);
end $fn$;

create or replace function hrm.company_import(p_tenant uuid, p_data jsonb) returns jsonb
language plpgsql security definer set search_path = hrm, public as $fn$
declare t text; n integer; counts jsonb := '{}'::jsonb; links jsonb;
  ins text[] := array['plants','departments','designations','shifts','holidays','leave_types','notification_templates',
    'employees','employee_private','onboarding_invites','employee_documents','id_cards','attendance_devices',
    'attendance_punches','attendance_days','regularisation_requests','leave_requests','leave_ledger',
    'pay_settings','pay_components','salary_structures','loans','payroll_runs','payroll_lines','loan_recoveries',
    'recruit_settings','job_descriptions','requisitions','candidates','applications','interviews','interview_feedback','offers',
    'qms_settings','competencies','operations','role_competencies','rr_roles','rr_acks','kpis','kpi_values','employee_competencies','skill_levels',
    'training_programs','training_sessions','training_needs','training_attendance','training_effectiveness','ojt_templates','ojt_records','auditors','auditor_audits'];
begin
  if coalesce(p_data->>'format', '') <> 'kmr-hrm-backup' then raise exception 'This file is not an HRM backup.'; end if;
  if (p_data->>'tenant_id')::uuid is distinct from p_tenant then raise exception 'This backup belongs to a different company.'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'employee_id', employee_id)), '[]') into links from hrm.app_users where tenant_id = p_tenant;
  perform hrm.module_flush(p_tenant, 'all');
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
  return counts;
end $fn$;
revoke all on function hrm.company_export(uuid), hrm.company_import(uuid, jsonb) from public, anon, authenticated;
grant execute on function hrm.company_export(uuid), hrm.company_import(uuid, jsonb) to service_role;

-- =====================================================================
-- Sample data: the QMS records of the sample people, joined up with their plants, designations and the hiring flow
-- =====================================================================
create or replace function hrm.demo_qms(p_tenant uuid) returns integer
language plpgsql security definer set search_path = hrm, public as $fn$
declare
  t uuid := p_tenant; pfx text; p1 uuid; p2 uuid; rec record; i int; n int := 0;
  op_ids uuid[]; op uuid; lvl int; sess uuid; prog uuid; att uuid; tpl uuid; aud uuid; kpi uuid; m text; k int;
  d_op uuid; d_sop uuid; d_tech uuid; d_eng uuid; d_sup uuid; d_seng uuid;
  -- skill levels: rows = sample people D003…D024 (production), columns = OP10…OP60 (0 not trained … 4 trainer)
  grid int[][] := array[
    [4,3,3,2,3,1],   -- D003 Karthik
    [3,2,3,3,1,0],   -- D004 Divya
    [3,3,2,1,2,0],   -- D010 Anitha
    [4,4,3,3,3,3],   -- D011 Manoj (senior operator, trainer)
    [2,1,3,0,3,0],   -- D012 Kavya
    [3,0,2,0,3,1],   -- D015 Ganesh
    [1,0,3,0,2,0],   -- D016 Sowmya
    [2,0,1,0,3,0],   -- D020 Revathi (contract)
    [1,0,0,0,2,0],   -- D021 Naveen (contract)
    [0,0,1,0,1,0],   -- D023 Senthil (contract)
    [3,2,2,0,3,0]];  -- D024 Bhavya
  who int[] := array[3,4,10,11,12,15,16,20,21,23,24];
  emp uuid;
begin
  select emp_code_prefix into pfx from hrm.tenants where id = t;
  if not exists (select 1 from hrm.employees where tenant_id = t and email like '%@demo.kmr.test') then return 0; end if;
  if exists (select 1 from hrm.operations where tenant_id = t and sample) then return 0; end if;     -- already there
  perform hrm.seed_qms_defaults(t);
  select id into p1 from hrm.plants where tenant_id = t and code = 'DP1';
  select id into p2 from hrm.plants where tenant_id = t and code = 'DP2';
  select id into d_op from hrm.designations where tenant_id = t and name = 'Operator';
  select id into d_sop from hrm.designations where tenant_id = t and name = 'Senior Operator';
  select id into d_tech from hrm.designations where tenant_id = t and name = 'Technician';
  select id into d_eng from hrm.designations where tenant_id = t and name = 'Engineer';
  select id into d_sup from hrm.designations where tenant_id = t and name = 'Supervisor';
  select id into d_seng from hrm.designations where tenant_id = t and name = 'Senior Engineer';

  update hrm.qms_settings set quality_policy = coalesce(quality_policy,
    'We make precision machined components right the first time and deliver them on time, every time. We meet our customers'' requirements and applicable statutory and regulatory requirements, train every person for the job, and improve our processes continually.'),
    csr = case when cardinality(csr) = 0 then array['Customer A: 100% inspection of the bore for the first 3 lots after any change','Customer B: PPAP level 3 for every engineering change','Customer A: retain first-off parts for one shift'] else csr end
   where tenant_id = t;

  -- ---- operations of two lines (skill matrix) ----
  insert into hrm.operations (tenant_id, plant_id, line, code, name, machine, critical, min_qualified, safety_required, sort_order, sample) values
    (t, p1, 'Turning cell 1', 'OP10', 'CNC turning — 1st setup', 'LT-01 Ace Jobber', true, null, false, 10, true),
    (t, p1, 'Turning cell 1', 'OP20', 'CNC turning — 2nd setup', 'LT-02 Ace Jobber', false, null, false, 20, true),
    (t, p1, 'Turning cell 1', 'OP30', 'VMC drilling & tapping', 'VMC-03 BFW', false, null, false, 30, true),
    (t, p1, 'Turning cell 1', 'OP40', 'Final inspection (bore & thread)', 'Inspection table', true, 3, false, 40, true),
    (t, p1, 'Assembly',       'OP50', 'Washing & packing', 'Washer WS-1', false, null, false, 50, true),
    (t, p1, 'Assembly',       'OP60', 'Bush press-fit', 'Hydraulic press HP-20T', true, null, true, 60, true);
  select array_agg(id order by sort_order) into op_ids from hrm.operations where tenant_id = t and sample;
  for i in 1..array_length(who, 1) loop
    select id into emp from hrm.employees where tenant_id = t and employee_code = pfx || '-D' || lpad(who[i]::text, 3, '0');
    if emp is null then continue; end if;
    for k in 1..6 loop
      lvl := grid[i][k];
      if lvl = 0 then continue; end if;
      insert into hrm.skill_levels (tenant_id, employee_id, operation_id, level, certified_on, valid_until, assessed_by_name, note)
      values (t, emp, op_ids[k], lvl, case when lvl >= 3 then current_date - (60 + i * 11) end,
              case when lvl >= 3 then current_date - (60 + i * 11) + 365 + case when i = 1 and k = 1 then -320 else 0 end end,
              'Priya Sharma', case when lvl = 1 then 'Under training with Manoj' end);
      n := n + 1;
    end loop;
  end loop;

  -- ---- competencies required per designation, and assessed levels ----
  insert into hrm.role_competencies (tenant_id, designation_id, competency_id, required_level, sample)
  select t, d.id, c.id, x.lvl, true
    from (values ('Operator','Measuring instruments',3), ('Operator','Control plan & work instructions',3), ('Operator','Safety rules & PPE',3), ('Operator','5S & workplace discipline',2), ('Operator','CNC operation',2),
                 ('Senior Operator','Measuring instruments',3), ('Senior Operator','Machine setting & first-off approval',3), ('Senior Operator','CNC operation',3), ('Senior Operator','Safety rules & PPE',3), ('Senior Operator','Reading drawings & GD&T',2),
                 ('Technician','Preventive & autonomous maintenance',3), ('Technician','Lock-out tag-out & machine guarding',3), ('Technician','Measuring instruments',2), ('Technician','Safety rules & PPE',3),
                 ('Engineer','Core tools — FMEA',3), ('Engineer','Core tools — SPC & MSA',3), ('Engineer','Problem solving (8D, why-why)',3), ('Engineer','Reading drawings & GD&T',3), ('Engineer','Internal auditing',2),
                 ('Supervisor','Leadership & people management',3), ('Supervisor','Control plan & work instructions',3), ('Supervisor','Problem solving (8D, why-why)',2), ('Supervisor','Safety rules & PPE',3),
                 ('Senior Engineer','Core tools — APQP & PPAP',4), ('Senior Engineer','Core tools — FMEA',3), ('Senior Engineer','Leadership & people management',2))
         x(desig, comp, lvl)
    join hrm.designations d on d.tenant_id = t and d.name = x.desig
    join hrm.competencies c on c.tenant_id = t and c.name = x.comp
  on conflict (designation_id, competency_id) do nothing;
  -- assessed: most meet the requirement, some one level short (the gaps the TNI picks up)
  insert into hrm.employee_competencies (tenant_id, employee_id, competency_id, level, assessed_on, assessed_by_name, method)
  select t, e.id, rc.competency_id,
         greatest(0, rc.required_level - case when (abs(hashtext(e.id::text || rc.competency_id::text)) % 5) = 0 then 1 when (abs(hashtext(e.id::text || rc.competency_id::text)) % 11) = 0 then 2 else 0 end
                                        + case when (abs(hashtext(rc.competency_id::text || e.id::text)) % 7) = 0 and rc.required_level < 4 then 1 else 0 end),
         current_date - (abs(hashtext(e.id::text)) % 120), 'Arun Kumar', 'observation'
    from hrm.employees e join hrm.role_competencies rc on rc.designation_id = e.designation_id and rc.sample
   where e.tenant_id = t and e.email like '%@demo.kmr.test' and e.status = 'active'
  on conflict (employee_id, competency_id) do nothing;

  -- ---- roles & responsibilities ----
  insert into hrm.rr_roles (tenant_id, designation_id, purpose, responsibilities, authorities, deputy, interfaces, version, status, approved_at, sample) values
    (t, d_op, 'Make good parts at the planned output, safely, as per the work instruction and control plan.',
       array['Run the machine as per the work instruction and set-up sheet','Do first-off and in-process checks and record them in the check sheet','Stop and inform the supervisor on any abnormality or doubt about quality','Keep the workplace in 5S and do the daily autonomous maintenance checks','Wear PPE and follow the safety rules'],
       array['Stop the machine on a quality or safety doubt','Segregate and red-tag suspect parts'], 'Senior Operator of the cell', array['Shift supervisor','Quality inspector','Maintenance technician'], 2, 'approved', now() - interval '120 days', true),
    (t, d_sup, 'Run the shift: people, output, quality and safety of the line.',
       array['Plan manpower for the shift using the skill matrix','Release the first-off and review check sheets','Lead the daily quality and safety meeting','Raise training needs for the team and evaluate training effectiveness','Escalate abnormalities through the escalation matrix'],
       array['Stop the line on a quality, safety or delivery risk','Move people between operations within their qualification'], 'Senior Operator nominated by the Production Manager', array['Production Manager','Quality','Maintenance','PPC','Stores'], 1, 'approved', now() - interval '200 days', true),
    (t, d_eng, 'Keep processes capable and customers satisfied; lead problem solving and audits.',
       array['Maintain PFMEA, control plan and work instructions','Run SPC and MSA studies; act on out-of-control signals','Lead 8D for customer and internal complaints','Conduct internal process audits as per the audit plan','Train operators on quality requirements and customer-specific requirements'],
       array['Hold suspect material','Approve first-off on behalf of Quality in the shift'], 'Quality Engineer of the other plant', array['Customer quality','Production','Suppliers','Maintenance'], 1, 'draft', null, true);
  insert into hrm.rr_acks (tenant_id, rr_id, employee_id, version, acknowledged_at)
  select t, r.id, e.id, r.version, now() - ((abs(hashtext(e.id::text)) % 90) || ' days')::interval
    from hrm.rr_roles r join hrm.employees e on e.designation_id = r.designation_id and e.tenant_id = t and e.email like '%@demo.kmr.test'
   where r.tenant_id = t and r.sample and r.status = 'approved' and (abs(hashtext(e.id::text)) % 4) <> 0;

  -- ---- KPIs and three months of values ----
  insert into hrm.kpis (tenant_id, designation_id, name, unit, target, direction, data_source, weight, sample) values
    (t, d_op, 'Output per shift', 'parts', 420, 'higher', 'Production report', 2, true),
    (t, d_op, 'Rejection', '%', 1.0, 'lower', 'Rejection register', 2, true),
    (t, d_op, 'Check-sheet compliance', '%', 100, 'higher', 'Layered process audit', 1, true),
    (t, d_eng, 'Customer PPM', 'PPM', 50, 'lower', 'Customer scorecard', 3, true),
    (t, d_eng, '8D closure time', 'days', 30, 'lower', 'Complaint register', 1, true),
    (t, d_sup, 'OEE of the line', '%', 75, 'higher', 'OEE sheet', 2, true),
    (t, d_sup, 'Safety incidents', 'nos', 0, 'lower', 'Incident register', 2, true);
  for k in 1..3 loop
    m := to_char(date_trunc('month', current_date) - (k || ' months')::interval, 'YYYY-MM');
    insert into hrm.kpi_values (tenant_id, kpi_id, employee_id, month, actual, entered_by)
    select t, kp.id, e.id, m,
           round((kp.target * case kp.direction when 'higher' then 0.9 + (abs(hashtext(e.id::text || m || kp.id::text)) % 20) / 100.0
                                                else 0.6 + (abs(hashtext(e.id::text || m || kp.id::text)) % 90) / 100.0 end
                  + case when kp.target = 0 then (abs(hashtext(e.id::text || m)) % 3) / 2 else 0 end)::numeric, case when kp.unit in ('%','PPM') then 1 else 0 end), null
      from hrm.kpis kp join hrm.employees e on e.designation_id = kp.designation_id and e.tenant_id = t and e.email like '%@demo.kmr.test' and e.status = 'active'
     where kp.tenant_id = t and kp.sample
    on conflict do nothing;
  end loop;

  -- ---- training: three sessions done, one this week, one planned next month ----
  -- 1) quality policy awareness, 75 days ago, everybody on the production floor, signed off
  select id into prog from hrm.training_programs where tenant_id = t and title = 'Quality policy, objectives & product safety';
  insert into hrm.training_sessions (tenant_id, program_id, plan_month, starts_at, ends_at, venue, trainer, status, completed_at, sample)
  values (t, prog, to_char(current_date - 75, 'YYYY-MM'), ((current_date - 75) + time '10:00') at time zone 'Asia/Kolkata', ((current_date - 75) + time '11:00') at time zone 'Asia/Kolkata',
          'Training hall, Plant 1', 'Suresh Reddy (Quality)', 'done', (current_date - 75)::timestamptz, true) returning id into sess;
  insert into hrm.training_attendance (tenant_id, session_id, employee_id, attended, method, marked_at, acknowledged_at)
  select t, sess, e.id, e.employee_code <> pfx || '-D016', 'scan', (current_date - 75)::timestamptz, case when e.employee_code <> pfx || '-D016' then (current_date - 74)::timestamptz end
    from hrm.employees e where e.tenant_id = t and e.email like '%@demo.kmr.test' and e.department_id in (select id from hrm.departments where tenant_id = t and name in ('Production','Quality'));
  -- 2) measuring instruments & first-off, 40 days ago: pre/post test, effectiveness due (one effective, one not, rest due / overdue)
  select id into prog from hrm.training_programs where tenant_id = t and title = 'Measuring instruments & first-off inspection';
  insert into hrm.training_sessions (tenant_id, program_id, plan_month, starts_at, ends_at, venue, trainer, trainer_employee_id, status, completed_at, sample)
  values (t, prog, to_char(current_date - 40, 'YYYY-MM'), ((current_date - 40) + time '14:00') at time zone 'Asia/Kolkata', ((current_date - 40) + time '18:00') at time zone 'Asia/Kolkata',
          'Quality lab, Plant 1', 'Manoj Gowda', (select id from hrm.employees where tenant_id = t and employee_code = pfx || '-D011'), 'done', (current_date - 40)::timestamptz, true) returning id into sess;
  i := 0;
  for rec in select id, employee_code, reporting_manager_id from hrm.employees where tenant_id = t and employee_code = any(array[pfx||'-D012', pfx||'-D015', pfx||'-D016', pfx||'-D020', pfx||'-D021', pfx||'-D023']) order by employee_code loop
    i := i + 1;
    insert into hrm.training_attendance (tenant_id, session_id, employee_id, attended, method, marked_at, pre_score, post_score)
    values (t, sess, rec.id, true, 'scan', (current_date - 40)::timestamptz, 35 + i * 5, case when i = 5 then 55 else 70 + i * 4 end) returning id into att;
    insert into hrm.training_effectiveness (tenant_id, attendance_id, employee_id, session_id, due_on, evaluator_id, result, rating, evidence, evaluated_by_name, evaluated_at)
    values (t, att, rec.id, sess, current_date - 10, rec.reporting_manager_id,
            case i when 1 then 'effective' when 5 then 'not_effective' end, case i when 1 then 4 when 5 then 2 end,
            case i when 1 then 'Did first-off on OP20 alone for two weeks; all readings correct' when 5 then 'Zero setting of the micrometer still missed twice in the layered audit' end,
            case when i in (1, 5) then 'Priya Sharma' end, case when i in (1, 5) then now() - interval '6 days' end);
    if i = 5 then
      insert into hrm.training_needs (tenant_id, employee_id, program_id, competency_id, topic, source, reason, priority, status, target_month, raised_by_name)
      values (t, rec.id, prog, (select competency_id from hrm.training_programs where id = prog), 'Measuring instruments & first-off inspection (again)', 'retraining',
              'Training of ' || to_char(current_date - 40, 'DD Mon') || ' was not effective: zero setting missed', 'high', 'open', to_char(current_date + 20, 'YYYY-MM'), 'Priya Sharma');
    end if;
  end loop;
  -- 3) safety induction for the new joiners and contract workers, 20 days ago
  select id into prog from hrm.training_programs where tenant_id = t and title = 'Safety induction';
  insert into hrm.training_sessions (tenant_id, program_id, plan_month, starts_at, ends_at, venue, trainer, status, completed_at, sample)
  values (t, prog, to_char(current_date - 20, 'YYYY-MM'), ((current_date - 20) + time '09:30') at time zone 'Asia/Kolkata', ((current_date - 20) + time '12:30') at time zone 'Asia/Kolkata',
          'Training hall, Plant 1', 'Pooja Singh (EHS)', 'done', (current_date - 20)::timestamptz, true) returning id into sess;
  insert into hrm.training_attendance (tenant_id, session_id, employee_id, attended, method, marked_at, pre_score, post_score)
  select t, sess, e.id, true, 'manual', (current_date - 20)::timestamptz, 40 + (abs(hashtext(e.id::text)) % 20), 75 + (abs(hashtext(e.id::text)) % 20)
    from hrm.employees e where e.tenant_id = t and e.email like '%@demo.kmr.test' and e.employment_type = 'contract';
  insert into hrm.training_effectiveness (tenant_id, attendance_id, employee_id, session_id, due_on, evaluator_id)
  select t, a.id, a.employee_id, sess, current_date + 10, (select reporting_manager_id from hrm.employees where id = a.employee_id)
    from hrm.training_attendance a where a.session_id = sess;
  -- 4) 8D problem solving this week (scheduled, invitations sent)
  select id into prog from hrm.training_programs where tenant_id = t and title = 'Problem solving — 8D';
  insert into hrm.training_sessions (tenant_id, program_id, plan_month, starts_at, ends_at, venue, trainer, status, invited_at, sample)
  values (t, prog, to_char(current_date + 3, 'YYYY-MM'), ((current_date + 3) + time '10:00') at time zone 'Asia/Kolkata', ((current_date + 3) + time '14:00') at time zone 'Asia/Kolkata',
          'Conference room, Plant 1', 'Prakash Babu', 'scheduled', now() - interval '2 days', true) returning id into sess;
  insert into hrm.training_needs (tenant_id, employee_id, program_id, competency_id, topic, source, reason, priority, status, target_month, session_id, raised_by_name)
  select t, e.id, prog, (select competency_id from hrm.training_programs where id = prog), 'Problem solving — 8D', 'customer_complaint',
         'Customer complaint: burr in the cross hole (repeat) — 8D team', 'high', 'planned', to_char(current_date + 3, 'YYYY-MM'), sess, 'Suresh Reddy'
    from hrm.employees e where e.tenant_id = t and e.employee_code = any(array[pfx||'-D005', pfx||'-D006', pfx||'-D013', pfx||'-D011', pfx||'-D002']);
  insert into hrm.training_attendance (tenant_id, session_id, employee_id, need_id)
  select t, sess, n2.employee_id, n2.id from hrm.training_needs n2 where n2.session_id = sess;
  -- 5) planned next month: core tools FMEA for the engineers (from the competency gaps)
  select id into prog from hrm.training_programs where tenant_id = t and title = 'Core tools — FMEA';
  insert into hrm.training_sessions (tenant_id, program_id, plan_month, venue, trainer, status, sample)
  values (t, prog, to_char(current_date + 32, 'YYYY-MM'), 'Training hall, Plant 1', 'External — certified trainer', 'planned', true) returning id into sess;

  -- open needs of different kinds (the TNI list)
  insert into hrm.training_needs (tenant_id, employee_id, program_id, competency_id, operation_id, topic, source, reason, priority, status, target_month, raised_by_name)
  select t, e.id, x.prog, x.comp, x.op, x.topic, x.src, x.reason, x.pri, 'open', to_char(current_date + x.inm, 'YYYY-MM'), x.by
    from (values
      ('-D023', null::uuid, null::uuid, op_ids[1], 'OP10 CNC turning — 1st setup', 'skill_gap', 'Needed as a backup on OP10: only one other person is qualified in the shift', 'high', 15, 'Priya Sharma'),
      ('-D016', null, null, null, 'Quality policy, objectives & product safety', 'awareness', 'Was absent for the awareness session', 'normal', 10, 'Arun Kumar'),
      ('-D009', null, null, null, 'Change of process: new washing chemical (MSDS, concentration check)', 'process_change', 'Engineering change EC-118', 'normal', 20, 'Prakash Babu'),
      ('-D019', null, null, null, 'IATF 16949 internal auditor', 'request', 'Asked to become an internal auditor', 'low', 60, 'Harish Hegde'),
      ('-D007', null, null, null, 'Lock-out tag-out', 'audit_finding', 'Internal audit finding: LOTO not applied on HP-20T during die change', 'high', 7, 'Pooja Singh')
    ) x(code, prog, comp, op, topic, src, reason, pri, inm, by)
    join hrm.employees e on e.tenant_id = t and e.employee_code = pfx || x.code;
  update hrm.training_needs nd set program_id = p.id, competency_id = p.competency_id
    from hrm.training_programs p where nd.tenant_id = t and p.tenant_id = t and nd.program_id is null and p.title = nd.topic;

  -- ---- on-the-job training ----
  insert into hrm.ojt_templates (tenant_id, title, designation_id, operation_id, items, days, sample) values
    (t, 'New operator — CNC turning cell', d_op, op_ids[1], jsonb_build_array(
       jsonb_build_object('text', 'Machine start-up, warm-up and daily checklist', 'kind', 'task'),
       jsonb_build_object('text', 'Reading the work instruction and set-up sheet', 'kind', 'task'),
       jsonb_build_object('text', 'Loading / unloading and chip handling safely', 'kind', 'task'),
       jsonb_build_object('text', 'First-off and in-process checks with the instruments; recording', 'kind', 'task'),
       jsonb_build_object('text', 'Customer A: retain first-off parts for one shift; 100% bore check after a change', 'kind', 'csr'),
       jsonb_build_object('text', 'Consequences of an oversize bore reaching the customer: line stoppage, recall, safety', 'kind', 'nc'),
       jsonb_build_object('text', 'Reaction plan: stop, segregate, red-tag, inform the supervisor', 'kind', 'task'),
       jsonb_build_object('text', 'Works independently for 3 shifts under observation', 'kind', 'task')), 15, true);
  select id into tpl from hrm.ojt_templates where tenant_id = t and sample limit 1;
  insert into hrm.ojt_records (tenant_id, template_id, employee_id, trainer, started_on, done, status, completed_on, signed_off_name)
  select t, tpl, e.id, 'Manoj Gowda', current_date - 60, '[0,1,2,3,4,5,6,7]'::jsonb, 'completed', current_date - 44, 'Priya Sharma'
    from hrm.employees e where e.tenant_id = t and e.employee_code = pfx || '-D020';
  insert into hrm.ojt_records (tenant_id, template_id, employee_id, trainer, started_on, done, status)
  select t, tpl, e.id, 'Manoj Gowda', current_date - 6, '[0,1,2]'::jsonb, 'in_progress'
    from hrm.employees e where e.tenant_id = t and e.employee_code = pfx || '-D023';

  -- the new joiner from the sample hiring flow gets the joiner's needs and OJT
  for rec in select id from hrm.employees where tenant_id = t and email like '%@demo.kmr.test' and status in ('invited','onboarding','submitted','active')
            and id in (select employee_id from hrm.offers where tenant_id = t and employee_id is not null) loop
    insert into hrm.training_needs (tenant_id, employee_id, program_id, topic, source, reason, priority, status, target_month, raised_by_name)
    select t, rec.id, p.id, p.title, 'new_joiner', 'Joining on ' || to_char(current_date + 5, 'DD Mon YYYY'), 'high', 'open', to_char(current_date + 5, 'YYYY-MM'), 'HRM (new joiner)'
      from hrm.training_programs p where p.tenant_id = t and p.title in ('Induction — company, HR rules and facilities', 'Safety induction', 'Quality policy, objectives & product safety')
    on conflict do nothing;
    insert into hrm.ojt_records (tenant_id, template_id, employee_id, trainer, started_on, status) values (t, tpl, rec.id, 'Manoj Gowda', current_date + 5, 'in_progress')
    on conflict do nothing;
  end loop;

  -- ---- internal auditors ----
  insert into hrm.auditors (tenant_id, employee_id, kind, standards, qualification, trained_on, certificate_no, valid_until, core_tools, csr_trained, audits_per_year)
  select t, e.id, x.kind, x.std, x.qual, current_date - x.ago, x.cert, current_date - x.ago + x.valid, x.tools, x.csr, 2
    from (values ('-D005', 'qms', array['IATF 16949','ISO 9001'], 'IATF 16949 internal auditor (2 days, external)', 600, 'IA-2291', 1095, array['APQP','PPAP','FMEA','SPC','MSA'], true),
                 ('-D017', 'process', array['IATF 16949','VDA 6.3'], 'VDA 6.3 process auditor', 1050, 'VDA-0442', 1095, array['APQP','PPAP','FMEA'], true),
                 ('-D022', 'qms', array['ISO 45001','ISO 14001'], 'ISO 45001 internal auditor', 330, 'OHS-118', 365, array[]::text[], false))
         x(code, kind, std, qual, ago, cert, valid, tools, csr)
    join hrm.employees e on e.tenant_id = t and e.employee_code = pfx || x.code;
  insert into hrm.auditor_audits (tenant_id, auditor_id, audit_date, area, audit_type, role, findings)
  select t, a.id, current_date - x.ago, x.area, x.typ, x.role, x.f
    from hrm.auditors a join hrm.employees e on e.id = a.employee_id
    join (values ('-D005', 140, 'Production — turning cell 1', 'process', 'lead', 3), ('-D005', 40, 'Stores & dispatch', 'system', 'lead', 1),
                 ('-D017', 300, 'Assembly line', 'process', 'auditor', 2), ('-D022', 90, 'Plant 2 — EHS', 'system', 'lead', 4)) x(code, ago, area, typ, role, f)
      on e.employee_code = pfx || x.code
   where a.tenant_id = t;

  return n;
end $fn$;

-- sample data runs through every module: hiring and QMS now (more modules join here)
create or replace function hrm.demo_flow(p_tenant uuid) returns jsonb
language plpgsql security definer set search_path = hrm, public as $fn$
declare r int; q int;
begin
  r := hrm.demo_recruit(p_tenant);
  q := hrm.demo_qms(p_tenant);
  return jsonb_build_object('recruitment', r, 'qms', q);
end $fn$;

-- the sample flush also clears the sample QMS lists (the people's records go with the sample people)
create or replace function hrm.demo_flush(p_tenant uuid) returns integer
language plpgsql security definer set search_path = hrm, public as $fn$
declare n integer;
begin
  perform hrm.demo_recruit_flush(p_tenant);
  update hrm.employees set reporting_manager_id = null
   where tenant_id = p_tenant and reporting_manager_id in (select id from hrm.employees where tenant_id = p_tenant and email like '%@demo.kmr.test');
  update hrm.offers set reporting_manager_id = null
   where tenant_id = p_tenant and reporting_manager_id in (select id from hrm.employees where tenant_id = p_tenant and email like '%@demo.kmr.test');
  delete from hrm.employees where tenant_id = p_tenant and email like '%@demo.kmr.test';
  get diagnostics n = row_count;
  perform hrm.module_flush(p_tenant, 'sample');
  delete from hrm.plants p where p.tenant_id = p_tenant and p.code in ('DP1','DP2') and not exists (select 1 from hrm.employees e where e.plant_id = p.id)
     and not exists (select 1 from hrm.operations o where o.plant_id = p.id);
  return n;
end $fn$;

revoke all on function hrm.demo_qms(uuid), hrm.demo_flow(uuid), hrm.demo_flush(uuid) from public, anon, authenticated;
grant execute on function hrm.demo_qms(uuid), hrm.demo_flow(uuid), hrm.demo_flush(uuid) to service_role;

-- companies that already hold the sample people get the sample QMS records now
do $$ declare r uuid; begin
  for r in select distinct tenant_id from hrm.employees where email like '%@demo.kmr.test' loop perform hrm.demo_qms(r); end loop;
end $$;

notify pgrst, 'reload schema';
