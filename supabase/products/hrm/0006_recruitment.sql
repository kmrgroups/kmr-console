-- =====================================================================
-- HRM Phase 4 — Recruitment + Offer. Needs 0001–0005. Safe to re-run.
--  • Manpower requisitions (raised by HR or a department manager, approved by HR)
--  • Job descriptions (written from the requisition, edited and approved by HR, reused for the next opening)
--  • Candidates and their applications to a requisition, with the match score, its evidence and HR's decision
--  • Interviews with a panel, the candidate's confirm / reschedule link, and each panellist's scorecard
--  • Offers with the CTC breakup, the candidate's accept / decline link; accepting creates the employee
-- Who sees what: HR (and company admins) see everything; a manager sees the requisitions they raised;
-- an interviewer sees only the interviews they sit on (with that candidate) and writes only their own scorecard.
-- Everything runs without any paid AI service.
-- =====================================================================

-- ---------- settings ----------
create table if not exists hrm.recruit_settings (
  tenant_id          uuid primary key references hrm.tenants(id) on delete cascade,
  careers_enabled    boolean not null default true,       -- public careers page with the open roles
  careers_intro      text check (length(careers_intro) <= 2000),
  req_approval       boolean not null default true,       -- a manager's requisition waits for HR approval
  suitable_score     integer not null default 70 check (suitable_score between 1 and 100),
  hold_score         integer not null default 50 check (hold_score between 0 and 99),
  regret_auto        boolean not null default true,       -- courteous regret message to declined candidates
  regret_delay_days  integer not null default 3 check (regret_delay_days between 0 and 30),
  offer_valid_days   integer not null default 7 check (offer_valid_days between 1 and 60),
  gratuity_in_ctc    boolean not null default true,       -- show gratuity (4.81% of basic) as part of CTC
  offer_signatory    text check (length(offer_signatory) <= 120),
  offer_terms        text check (length(offer_terms) <= 6000),
  updated_at         timestamptz not null default now()
);

-- ---------- job descriptions (reusable per designation, version-controlled) ----------
create table if not exists hrm.job_descriptions (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references hrm.tenants(id) on delete cascade,
  designation_id   uuid references hrm.designations(id) on delete set null,
  title            text not null check (length(title) between 2 and 120),
  family           text,                                  -- quality, production, maintenance … (drives the template)
  purpose          text check (length(purpose) <= 2000),
  responsibilities text[] not null default '{}',
  kpis             text[] not null default '{}',
  must_have        jsonb not null default '[]',          -- [{name, weight 1–3}] competencies the role cannot do without
  good_to_have     jsonb not null default '[]',
  qualifications   text check (length(qualifications) <= 1000),
  experience       text check (length(experience) <= 300),
  reporting_to     text check (length(reporting_to) <= 120),
  context          text check (length(context) <= 600),  -- operating context: industry, plant type, standards
  outcomes         text[] not null default '{}',          -- results the role must deliver
  version          integer not null default 1,
  status           text not null default 'draft' check (status in ('draft','approved','archived')),
  approved_by      uuid,
  approved_at      timestamptz,
  created_by       uuid,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create index if not exists job_descriptions_desig on hrm.job_descriptions (tenant_id, designation_id, version desc);

-- ---------- requisitions ----------
create table if not exists hrm.requisitions (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references hrm.tenants(id) on delete cascade,
  ref_no           text not null,
  title            text not null check (length(title) between 2 and 120),
  designation_id   uuid references hrm.designations(id) on delete set null,
  department_id    uuid references hrm.departments(id) on delete set null,
  plant_id         uuid references hrm.plants(id) on delete set null,
  headcount        integer not null default 1 check (headcount between 1 and 500),
  grade            text check (length(grade) <= 40),
  ctc_min          numeric(12,2) check (ctc_min >= 0),     -- yearly, rupees
  ctc_max          numeric(12,2) check (ctc_max >= 0),
  exp_min          numeric(4,1) check (exp_min >= 0),
  exp_max          numeric(4,1) check (exp_max >= 0),
  reason           text not null default 'new' check (reason in ('new','replacement','project')),
  replacement_for  text check (length(replacement_for) <= 120),
  required_by      date,
  location         text check (length(location) <= 120),
  notice_max_days  integer check (notice_max_days between 0 and 365),
  jd_id            uuid references hrm.job_descriptions(id) on delete set null,
  status           text not null default 'draft' check (status in ('draft','pending','approved','open','on_hold','closed','cancelled')),
  published        boolean not null default false,        -- shown on the careers page while open
  raised_by        uuid,
  raised_by_name   text,
  approved_by      uuid,
  approved_at      timestamptz,
  closed_at        timestamptz,
  notes            text check (length(notes) <= 2000),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  unique (tenant_id, ref_no)
);
create index if not exists requisitions_status on hrm.requisitions (tenant_id, status, created_at desc);

-- ---------- candidates (one per person per company; duplicates merged by e-mail / mobile) ----------
create table if not exists hrm.candidates (
  id                  uuid primary key default gen_random_uuid(),
  tenant_id           uuid not null references hrm.tenants(id) on delete cascade,
  full_name           text not null check (length(full_name) between 1 and 120),
  email               text check (email = lower(email)),
  phone               text,
  location            text,
  current_company     text,
  current_designation text,
  total_exp           numeric(4,1),
  current_ctc         numeric(12,2),                     -- yearly, rupees
  expected_ctc        numeric(12,2),
  notice_days         integer,
  education           text,
  skills              text[] not null default '{}',
  resume_path         text,
  resume_name         text,
  resume_text         text,
  parse_status        text not null default 'manual' check (parse_status in ('parsed','scanned','failed','manual')),
  source              text not null default 'upload' check (source in ('upload','careers','referral','manual','import')),
  consent_at          timestamptz,                         -- careers page: consent to process the resume (DPDP Act)
  created_by          uuid,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);
create unique index if not exists candidates_email on hrm.candidates (tenant_id, email) where email is not null;
create unique index if not exists candidates_phone on hrm.candidates (tenant_id, phone) where phone is not null;

-- ---------- applications: a candidate for a requisition ----------
create table if not exists hrm.applications (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references hrm.tenants(id) on delete cascade,
  requisition_id   uuid not null references hrm.requisitions(id) on delete cascade,
  candidate_id     uuid not null references hrm.candidates(id) on delete cascade,
  score            integer check (score between 0 and 100),
  breakdown        jsonb not null default '[]',          -- [{key, label, points, max, note}]
  evidence         jsonb not null default '[]',          -- [{competency, line}]
  flags            text[] not null default '{}',          -- hard constraints not met (notice, CTC, location …)
  recommendation   text check (recommendation in ('suitable','hold','not_suitable')),
  status           text not null default 'new' check (status in ('new','shortlisted','on_hold','declined','interview','selected','offered','joined','withdrawn')),
  decision_by      uuid,
  decision_at      timestamptz,
  decision_reason  text check (length(decision_reason) <= 500),
  overridden       boolean not null default false,        -- HR's decision differs from the recommendation
  regret_due       date,
  regret_sent_at   timestamptz,
  source           text,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  unique (requisition_id, candidate_id)
);
create index if not exists applications_req on hrm.applications (requisition_id, score desc nulls last);
create index if not exists applications_cand on hrm.applications (candidate_id);

-- ---------- interviews and scorecards ----------
create table if not exists hrm.interviews (
  id                 uuid primary key default gen_random_uuid(),
  tenant_id          uuid not null references hrm.tenants(id) on delete cascade,
  application_id     uuid not null references hrm.applications(id) on delete cascade,
  round              integer not null default 1 check (round between 1 and 9),
  title              text not null default 'Interview' check (length(title) <= 80),
  mode               text not null default 'in_person' check (mode in ('in_person','video','phone')),
  starts_at          timestamptz not null,
  duration_min       integer not null default 45 check (duration_min between 10 and 480),
  venue              text check (length(venue) <= 300),
  video_link         text check (length(video_link) <= 500),
  bring              text check (length(bring) <= 500),   -- documents to bring
  panel              uuid[] not null default '{}',        -- app_users ids
  panel_names        text[] not null default '{}',
  status             text not null default 'scheduled' check (status in ('scheduled','confirmed','reschedule_requested','done','cancelled','no_show')),
  token_hash         text,                                 -- candidate's confirm / reschedule link
  candidate_note     text check (length(candidate_note) <= 500),
  reminded_day_before boolean not null default false,
  reminded_same_day  boolean not null default false,
  created_by         uuid,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);
create index if not exists interviews_when on hrm.interviews (tenant_id, starts_at);
create index if not exists interviews_app on hrm.interviews (application_id);
create index if not exists interviews_token on hrm.interviews (token_hash) where token_hash is not null;

create table if not exists hrm.interview_feedback (
  id              uuid primary key default gen_random_uuid(),
  tenant_id       uuid not null references hrm.tenants(id) on delete cascade,
  interview_id    uuid not null references hrm.interviews(id) on delete cascade,
  panelist_id     uuid not null,
  panelist_name   text,
  scores          jsonb not null default '{}',            -- {competency: 1–5}
  overall         integer check (overall between 1 and 5),
  recommendation  text check (recommendation in ('strong_hire','hire','hold','no_hire')),
  strengths       text check (length(strengths) <= 1500),
  concerns        text check (length(concerns) <= 1500),
  submitted_at    timestamptz not null default now(),
  unique (interview_id, panelist_id)
);

-- ---------- offers ----------
create table if not exists hrm.offers (
  id                    uuid primary key default gen_random_uuid(),
  tenant_id             uuid not null references hrm.tenants(id) on delete cascade,
  application_id        uuid not null references hrm.applications(id) on delete cascade,
  ref_no                text not null,
  designation_id        uuid references hrm.designations(id) on delete set null,
  department_id         uuid references hrm.departments(id) on delete set null,
  plant_id              uuid references hrm.plants(id) on delete set null,
  reporting_manager_id  uuid references hrm.employees(id) on delete set null,
  employment_type       text not null default 'probation' check (employment_type in ('permanent','probation','fixed_term','trainee','apprentice','contract')),
  category              text not null default 'staff' check (category in ('staff','workman','management')),
  date_of_joining       date not null,
  annual_ctc            numeric(12,2) not null check (annual_ctc > 0),
  monthly_gross         numeric(12,2) not null check (monthly_gross > 0),
  breakup               jsonb not null default '{}',     -- earnings, employer contributions, deductions, net, ctc
  pf_applicable         boolean not null default true,
  include_gratuity      boolean not null default true,
  valid_until           date not null,
  status                text not null default 'draft' check (status in ('draft','sent','accepted','declined','expired','withdrawn')),
  token_hash            text,
  sent_at               timestamptz,
  viewed_at             timestamptz,
  responded_at          timestamptz,
  accepted_name         text check (length(accepted_name) <= 120),   -- typed name as the candidate's signature
  decline_reason        text check (length(decline_reason) <= 500),
  employee_id           uuid references hrm.employees(id) on delete set null,
  terms                 text check (length(terms) <= 6000),
  created_by            uuid,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  unique (tenant_id, ref_no)
);
create index if not exists offers_app on hrm.offers (application_id);
create index if not exists offers_token on hrm.offers (token_hash) where token_hash is not null;

-- ---------- updated_at ----------
do $$ declare t text; begin
  foreach t in array array['recruit_settings','job_descriptions','requisitions','candidates','applications','interviews','offers'] loop
    execute format('drop trigger if exists %I on hrm.%I', t || '_touch', t);
    execute format('create trigger %I before update on hrm.%I for each row execute function hrm.touch_updated_at()', t || '_touch', t);
  end loop;
end $$;

-- ---------- access ----------
-- helpers read past row-level security, so the policies below do not call each other in a loop
create or replace function hrm.on_panel(p_application uuid) returns boolean
language sql stable security definer set search_path = hrm, public as $$
  select exists (select 1 from hrm.interviews i where i.application_id = p_application and auth.uid() = any(i.panel))
$$;
create or replace function hrm.on_panel_for_candidate(p_candidate uuid) returns boolean
language sql stable security definer set search_path = hrm, public as $$
  select exists (select 1 from hrm.interviews i join hrm.applications a on a.id = i.application_id
                  where a.candidate_id = p_candidate and auth.uid() = any(i.panel))
$$;
create or replace function hrm.on_panel_for_requisition(p_req uuid) returns boolean
language sql stable security definer set search_path = hrm, public as $$
  select exists (select 1 from hrm.interviews i join hrm.applications a on a.id = i.application_id
                  where a.requisition_id = p_req and auth.uid() = any(i.panel))
$$;
create or replace function hrm.raised_by_me(p_req uuid) returns boolean
language sql stable security definer set search_path = hrm, public as $$
  select exists (select 1 from hrm.requisitions r where r.id = p_req and r.raised_by = auth.uid())
$$;

do $$
declare t text;
begin
  foreach t in array array['recruit_settings','job_descriptions','requisitions','candidates','applications','interviews','interview_feedback','offers'] loop
    execute format('alter table hrm.%I enable row level security', t);
    execute format('drop policy if exists %I on hrm.%I', t || '_hr', t);
    execute format('create policy %I on hrm.%I for all to authenticated using (tenant_id = hrm.current_tenant_id() and hrm.is_hr()) with check (tenant_id = hrm.current_tenant_id() and hrm.is_hr())', t || '_hr', t);
  end loop;
end $$;

-- staff read the company's recruitment rules and approved job descriptions
drop policy if exists recruit_settings_read on hrm.recruit_settings;
create policy recruit_settings_read on hrm.recruit_settings for select to authenticated using (tenant_id = hrm.current_tenant_id());
drop policy if exists job_descriptions_staff on hrm.job_descriptions;
create policy job_descriptions_staff on hrm.job_descriptions for select to authenticated
  using (tenant_id = hrm.current_tenant_id() and hrm.has_role('manager','interviewer'));

-- a manager raises requisitions and follows the ones they raised
drop policy if exists requisitions_manager_read on hrm.requisitions;
create policy requisitions_manager_read on hrm.requisitions for select to authenticated
  using (tenant_id = hrm.current_tenant_id() and (raised_by = auth.uid() or hrm.on_panel_for_requisition(id)));
drop policy if exists requisitions_manager_add on hrm.requisitions;
create policy requisitions_manager_add on hrm.requisitions for insert to authenticated
  with check (tenant_id = hrm.current_tenant_id() and hrm.has_role('manager') and raised_by = auth.uid() and status in ('draft','pending'));
drop policy if exists requisitions_manager_edit on hrm.requisitions;
create policy requisitions_manager_edit on hrm.requisitions for update to authenticated
  using (tenant_id = hrm.current_tenant_id() and raised_by = auth.uid() and status in ('draft','pending'))
  with check (tenant_id = hrm.current_tenant_id() and raised_by = auth.uid() and status in ('draft','pending'));
-- the manager who raised it sees who applied
drop policy if exists applications_manager on hrm.applications;
create policy applications_manager on hrm.applications for select to authenticated
  using (tenant_id = hrm.current_tenant_id() and (hrm.raised_by_me(requisition_id) or hrm.on_panel(id)));

-- interviewers: the interviews they sit on, that candidate, and their own scorecard
drop policy if exists interviews_panel on hrm.interviews;
create policy interviews_panel on hrm.interviews for select to authenticated
  using (tenant_id = hrm.current_tenant_id() and auth.uid() = any(panel));
drop policy if exists candidates_panel on hrm.candidates;
create policy candidates_panel on hrm.candidates for select to authenticated
  using (tenant_id = hrm.current_tenant_id() and hrm.on_panel_for_candidate(id));
drop policy if exists feedback_own on hrm.interview_feedback;
create policy feedback_own on hrm.interview_feedback for all to authenticated
  using (tenant_id = hrm.current_tenant_id() and panelist_id = auth.uid())
  with check (tenant_id = hrm.current_tenant_id() and panelist_id = auth.uid()
              and exists (select 1 from hrm.interviews i where i.id = interview_id and auth.uid() = any(i.panel)));

-- ---------- audit trail ----------
do $$ declare t text; begin
  foreach t in array array['recruit_settings','job_descriptions','requisitions','candidates','applications','interviews','interview_feedback','offers'] loop
    execute format('drop trigger if exists %I on hrm.%I', t || '_audit', t);
    execute format('create trigger %I after insert or update or delete on hrm.%I for each row execute function hrm.audit_row()', t || '_audit', t);
  end loop;
end $$;
-- recruit_settings has no id column: the audit entry uses tenant_id (audit_row falls back to employee_id, which is null here)

-- ---------- resumes: private bucket, reached only through short-lived signed links ----------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('hrm-resumes', 'hrm-resumes', false, 5242880,
   array['application/pdf','application/vnd.openxmlformats-officedocument.wordprocessingml.document','application/msword','text/plain','image/png','image/jpeg'])
on conflict (id) do nothing;

-- ---------- defaults for a company ----------
create or replace function hrm.seed_recruit_defaults(p_tenant uuid) returns void
language plpgsql security definer set search_path = hrm, public as $fn$
begin
  insert into hrm.recruit_settings (tenant_id, offer_terms) values (p_tenant,
'1. This offer is subject to satisfactory verification of your documents, background and references, and to your being medically fit.
2. You will be on probation for six months from the date of joining; on successful completion you will be confirmed in writing.
3. Your salary details are confidential. Statutory deductions (PF, ESI, Professional Tax, Income Tax) are made as per law.
4. Either party may end the employment with the notice period stated in the company''s service rules, or salary in lieu of notice.
5. You will follow the company''s policies, standing orders, safety rules and code of conduct as amended from time to time.')
  on conflict do nothing;
end $fn$;
revoke all on function hrm.seed_recruit_defaults(uuid) from public, anon, authenticated;
grant execute on function hrm.seed_recruit_defaults(uuid) to service_role;
do $$ declare t uuid; begin for t in select id from hrm.tenants loop perform hrm.seed_recruit_defaults(t); end loop; end $$;

-- ---------- backups include recruitment ----------
create or replace function hrm.company_export(p_tenant uuid) returns jsonb
language plpgsql stable security definer set search_path = hrm, public as $fn$
declare out jsonb := '{}'::jsonb; t text; rows jsonb;
begin
  foreach t in array array['plants','departments','designations','shifts','holidays','leave_types','notification_templates',
    'employees','employee_private','onboarding_invites','employee_documents','id_cards','attendance_devices',
    'attendance_punches','attendance_days','regularisation_requests','leave_requests','leave_ledger',
    'pay_settings','pay_components','salary_structures','loans','payroll_runs','payroll_lines','loan_recoveries',
    'recruit_settings','job_descriptions','requisitions','candidates','applications','interviews','interview_feedback','offers'] loop
    if to_regclass('hrm.' || t) is null then continue; end if;
    if t in ('employee_private') then
      execute format('select coalesce(jsonb_agg(to_jsonb(x)), ''[]'') from hrm.%I x where x.employee_id in (select id from hrm.employees where tenant_id = $1)', t) into rows using p_tenant;
    else
      execute format('select coalesce(jsonb_agg(to_jsonb(x)), ''[]'') from hrm.%I x where x.tenant_id = $1', t) into rows using p_tenant;
    end if;
    out := out || jsonb_build_object(t, rows);
  end loop;
  return jsonb_build_object('format', 'kmr-hrm-backup', 'version', 3, 'exported_at', now(),
    'company', (select to_jsonb(x) - 'id' from hrm.tenants x where id = p_tenant), 'tenant_id', p_tenant, 'tables', out);
end $fn$;

create or replace function hrm.company_import(p_tenant uuid, p_data jsonb) returns jsonb
language plpgsql security definer set search_path = hrm, public as $fn$
declare t text; n integer; counts jsonb := '{}'::jsonb; links jsonb;
  ins text[] := array['plants','departments','designations','shifts','holidays','leave_types','notification_templates',
    'employees','employee_private','onboarding_invites','employee_documents','id_cards','attendance_devices',
    'attendance_punches','attendance_days','regularisation_requests','leave_requests','leave_ledger',
    'pay_settings','pay_components','salary_structures','loans','payroll_runs','payroll_lines','loan_recoveries',
    'recruit_settings','job_descriptions','requisitions','candidates','applications','interviews','interview_feedback','offers'];
begin
  if coalesce(p_data->>'format', '') <> 'kmr-hrm-backup' then raise exception 'This file is not an HRM backup.'; end if;
  if (p_data->>'tenant_id')::uuid is distinct from p_tenant then raise exception 'This backup belongs to a different company.'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'employee_id', employee_id)), '[]') into links from hrm.app_users where tenant_id = p_tenant;
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
  return counts;
end $fn$;
revoke all on function hrm.company_export(uuid), hrm.company_import(uuid, jsonb) from public, anon, authenticated;
grant execute on function hrm.company_export(uuid), hrm.company_import(uuid, jsonb) to service_role;
