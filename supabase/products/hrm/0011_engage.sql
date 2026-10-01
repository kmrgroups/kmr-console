-- =====================================================================
-- HRM 0011 — Phase 5B: employee engagement. Needs 0001–0010. Safe to re-run.
--   • Announcements — HR posts news to everybody, a department or a plant; pinned; "please acknowledge" when it
--     must be read (safety, policy); who has read / acknowledged it
--   • Recognition — a thank-you wall: managers and HR recognise people, colleagues thank each other; Employee of the
--     month; an implemented suggestion recognises its author automatically
--   • Suggestions / Kaizen — employees send ideas from their portal; the manager or HR reviews them
--     (under review → accepted → implemented with the saving, or not taken up with the reason)       IATF 16949 7.3.2
--   • Surveys — engagement, pulse, training, canteen …; anonymous by default: the answers carry no name and the
--     list of who has answered is kept apart from the answers; results by group only when 5 or more answered
-- The free AI (0010) can draft an announcement's wording and summarise survey comments; a person reviews both.
-- =====================================================================

-- ---------- announcements ----------
create table if not exists hrm.announcements (
  id              uuid primary key default gen_random_uuid(),
  tenant_id       uuid not null references hrm.tenants(id) on delete cascade,
  title           text not null check (length(title) between 2 and 160),
  body            text not null check (length(body) between 2 and 5000),
  category        text not null default 'general' check (category in ('general','safety','quality','hr','event','policy','production')),
  audience        text not null default 'all' check (audience in ('all','department','plant')),
  department_id   uuid references hrm.departments(id) on delete cascade,
  plant_id        uuid references hrm.plants(id) on delete cascade,
  pinned          boolean not null default false,
  needs_ack       boolean not null default false,                 -- each person confirms he has read it
  notify          boolean not null default true,                  -- e-mail / WhatsApp when it is published
  status          text not null default 'draft' check (status in ('draft','published','archived')),
  publish_on      date,                                           -- a later date: published by the daily job that day
  expires_on      date,                                           -- off the board after this day
  published_at    timestamptz,
  notified_at     timestamptz,
  ai_model        text,                                           -- the AI drafted the wording (HR edited / approved it)
  sample          boolean not null default false,
  created_by      uuid,
  created_by_name text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  check (audience <> 'department' or department_id is not null),
  check (audience <> 'plant' or plant_id is not null)
);
create index if not exists announcements_board on hrm.announcements (tenant_id, status, pinned desc, published_at desc);

create table if not exists hrm.announcement_reads (
  tenant_id       uuid not null references hrm.tenants(id) on delete cascade,
  announcement_id uuid not null references hrm.announcements(id) on delete cascade,
  employee_id     uuid not null references hrm.employees(id) on delete cascade,
  read_at         timestamptz not null default now(),
  acknowledged_at timestamptz,
  primary key (announcement_id, employee_id)
);

-- ---------- recognition ----------
create table if not exists hrm.recognitions (
  id                   uuid primary key default gen_random_uuid(),
  tenant_id            uuid not null references hrm.tenants(id) on delete cascade,
  employee_id          uuid not null references hrm.employees(id) on delete cascade,     -- who is recognised
  category             text not null check (category in ('safety','quality','kaizen','teamwork','customer','attendance','helping','delivery','long_service','employee_of_month')),
  message              text not null check (length(message) between 3 and 1000),
  month                text check (month ~ '^\d{4}-(0[1-9]|1[0-2])$'),                   -- Employee of the month
  given_by             uuid,                                                              -- app user
  given_by_name        text,
  given_by_employee_id uuid references hrm.employees(id) on delete set null,
  kind                 text not null default 'manager' check (kind in ('manager','hr','peer','auto')),
  suggestion_id        uuid,
  visible              boolean not null default true,                                     -- HR can take one off the wall
  sample               boolean not null default false,
  created_at           timestamptz not null default now()
);
create index if not exists recognitions_wall on hrm.recognitions (tenant_id, created_at desc);
create unique index if not exists recognitions_eom on hrm.recognitions (tenant_id, month, employee_id) where category = 'employee_of_month';

-- ---------- suggestions / kaizen ----------
create table if not exists hrm.suggestions (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references hrm.tenants(id) on delete cascade,
  ref              text,
  employee_id      uuid not null references hrm.employees(id) on delete cascade,          -- who suggested it
  team             text check (length(team) <= 300),                                       -- others who worked on it
  title            text not null check (length(title) between 3 and 160),
  problem          text not null check (length(problem) between 3 and 2000),              -- what is wrong today
  idea             text not null check (length(idea) between 3 and 2000),                 -- what to change
  area             text check (length(area) <= 120),                                       -- line / machine / place
  category         text not null default 'productivity' check (category in ('safety','quality','productivity','cost','5s','environment','ergonomics','other')),
  status           text not null default 'submitted' check (status in ('submitted','under_review','accepted','implemented','not_taken','on_hold')),
  review_note      text check (length(review_note) <= 1000),
  benefit          text check (length(benefit) <= 1000),                                   -- what it gave (quality, safety, time …)
  saving_per_year  numeric(14,2) check (saving_per_year is null or saving_per_year >= 0),  -- rupees a year, when it saves money
  before_text      text check (length(before_text) <= 1000),
  after_text       text check (length(after_text) <= 1000),
  implemented_on   date,
  reviewed_by      uuid,
  reviewed_by_name text,
  decided_at       timestamptz,
  sample           boolean not null default false,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create index if not exists suggestions_list on hrm.suggestions (tenant_id, status, created_at desc);
create unique index if not exists suggestions_ref on hrm.suggestions (tenant_id, ref);
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'recognitions_suggestion_fk') then
    alter table hrm.recognitions add constraint recognitions_suggestion_fk foreign key (suggestion_id) references hrm.suggestions(id) on delete set null;
  end if;
end $$;

-- SG-2026-001, SG-2026-002 … per company and year
create or replace function hrm.suggestion_ref() returns trigger
language plpgsql security definer set search_path = hrm, public as $fn$
declare y text := to_char((now() at time zone 'Asia/Kolkata'), 'YYYY'); n int;
begin
  if new.ref is null then
    perform pg_advisory_xact_lock(hashtext('suggestion_ref' || new.tenant_id::text));
    select coalesce(max(substring(ref from '\d+$')::int), 0) + 1 into n from hrm.suggestions where tenant_id = new.tenant_id and ref like 'SG-' || y || '-%';
    new.ref := 'SG-' || y || '-' || lpad(n::text, 3, '0');
  end if;
  return new;
end $fn$;
drop trigger if exists suggestions_ref_set on hrm.suggestions;
create trigger suggestions_ref_set before insert on hrm.suggestions for each row execute function hrm.suggestion_ref();

-- ---------- surveys ----------
create table if not exists hrm.surveys (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references hrm.tenants(id) on delete cascade,
  title            text not null check (length(title) between 2 and 160),
  intro            text check (length(intro) <= 2000),
  kind             text not null default 'engagement' check (kind in ('engagement','pulse','training','canteen','exit','custom')),
  anonymous        boolean not null default true,
  audience         text not null default 'all' check (audience in ('all','department','plant')),
  department_id    uuid references hrm.departments(id) on delete cascade,
  plant_id         uuid references hrm.plants(id) on delete cascade,
  questions        jsonb not null default '[]',    -- [{id, text, type: rating|enps|yesno|choice|text, options[], required}]
  status           text not null default 'draft' check (status in ('draft','open','closed')),
  opens_on         date,
  closes_on        date,
  notified_at      timestamptz,
  reminded_at      timestamptz,
  ai_summary       jsonb,                          -- {themes:[{theme, count, points[]}], actions[]} — the AI's reading of the comments
  ai_model         text,
  ai_summary_at    timestamptz,
  summary_reviewed_by_name text,                   -- a person checked the summary against the comments
  summary_reviewed_at timestamptz,
  sample           boolean not null default false,
  created_by       uuid,
  created_by_name  text,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  check (jsonb_typeof(questions) = 'array'),
  check (audience <> 'department' or department_id is not null),
  check (audience <> 'plant' or plant_id is not null)
);
-- who has answered (so nobody answers twice and reminders go only to the others) — kept apart from the answers
create table if not exists hrm.survey_participants (
  tenant_id    uuid not null references hrm.tenants(id) on delete cascade,
  survey_id    uuid not null references hrm.surveys(id) on delete cascade,
  employee_id  uuid not null references hrm.employees(id) on delete cascade,
  responded_on date not null,
  primary key (survey_id, employee_id)
);
-- the answers: no name when the survey is anonymous, and only the day (not the time) it was given
create table if not exists hrm.survey_responses (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid not null references hrm.tenants(id) on delete cascade,
  survey_id     uuid not null references hrm.surveys(id) on delete cascade,
  employee_id   uuid references hrm.employees(id) on delete set null,      -- only when the survey is not anonymous
  department_id uuid references hrm.departments(id) on delete set null,    -- results by department only with 5+ answers
  plant_id      uuid references hrm.plants(id) on delete set null,
  answers       jsonb not null check (jsonb_typeof(answers) = 'object' and length(answers::text) <= 20000),
  submitted_on  date not null
);
create index if not exists survey_responses_by on hrm.survey_responses (survey_id);

-- ---------- is this person in the audience? ----------
create or replace function hrm.in_audience(p_aud text, p_dept uuid, p_plant uuid) returns boolean
language sql stable security definer set search_path = hrm, public as $fn$
  select case p_aud when 'all' then true
    when 'department' then exists (select 1 from hrm.employees e where e.id = hrm.current_employee_id() and e.department_id = p_dept)
    when 'plant' then exists (select 1 from hrm.employees e where e.id = hrm.current_employee_id() and e.plant_id = p_plant)
    else false end
$fn$;
grant execute on function hrm.in_audience(text, uuid, uuid) to authenticated;

-- ---------- answering a survey: the one way in (checks it is open, for him, and not answered yet) ----------
create or replace function hrm.submit_survey(p_survey uuid, p_answers jsonb) returns void
language plpgsql security definer set search_path = hrm, public as $fn$
declare me uuid := hrm.current_employee_id(); s hrm.surveys; e hrm.employees; today date := (now() at time zone 'Asia/Kolkata')::date;
  q jsonb; v jsonb;
begin
  if me is null then raise exception 'Only employees can answer surveys.'; end if;
  select * into s from hrm.surveys where id = p_survey and tenant_id = hrm.current_tenant_id();
  if s.id is null or s.status <> 'open' or (s.opens_on is not null and s.opens_on > today) or (s.closes_on is not null and s.closes_on < today) then
    raise exception 'This survey is not open.'; end if;
  if not hrm.in_audience(s.audience, s.department_id, s.plant_id) then raise exception 'This survey is not for you.'; end if;
  if exists (select 1 from hrm.survey_participants where survey_id = s.id and employee_id = me) then raise exception 'You have already answered this survey. Thank you!'; end if;
  if jsonb_typeof(p_answers) <> 'object' or length(p_answers::text) > 20000 then raise exception 'The answers could not be read.'; end if;
  -- every answer must belong to a question and fit its type; required questions must be answered
  for q in select * from jsonb_array_elements(s.questions) loop
    v := p_answers -> (q->>'id');
    if v is null or v = 'null'::jsonb or v = '""'::jsonb then
      if coalesce((q->>'required')::boolean, false) then raise exception 'Please answer: %', q->>'text'; end if;
      continue;
    end if;
    if q->>'type' = 'rating' and not (jsonb_typeof(v) = 'number' and (v::text)::numeric between 1 and 5) then raise exception 'Invalid answer: %', q->>'text'; end if;
    if q->>'type' = 'enps' and not (jsonb_typeof(v) = 'number' and (v::text)::numeric between 0 and 10) then raise exception 'Invalid answer: %', q->>'text'; end if;
    if q->>'type' = 'yesno' and v not in ('"yes"'::jsonb, '"no"'::jsonb) then raise exception 'Invalid answer: %', q->>'text'; end if;
    if q->>'type' = 'choice' and not (coalesce(q->'options', '[]'::jsonb) ? (v #>> '{}')) then raise exception 'Invalid answer: %', q->>'text'; end if;
    if q->>'type' = 'text' and not (jsonb_typeof(v) = 'string' and length(v #>> '{}') <= 2000) then raise exception 'Invalid answer: %', q->>'text'; end if;
  end loop;
  if exists (select 1 from jsonb_object_keys(p_answers) k where not exists (select 1 from jsonb_array_elements(s.questions) q2 where q2->>'id' = k)) then
    raise exception 'The answers could not be read.'; end if;
  select * into e from hrm.employees where id = me;
  insert into hrm.survey_participants (tenant_id, survey_id, employee_id, responded_on) values (s.tenant_id, s.id, me, today);
  insert into hrm.survey_responses (tenant_id, survey_id, employee_id, department_id, plant_id, answers, submitted_on)
    values (s.tenant_id, s.id, case when s.anonymous then null else me end, e.department_id, e.plant_id, p_answers, today);
end $fn$;
revoke all on function hrm.submit_survey(uuid, jsonb) from public, anon;
grant execute on function hrm.submit_survey(uuid, jsonb) to authenticated;

-- ---------- updated_at + audit trail (never on survey answers or who answered: that would undo the anonymity) ----------
do $$ declare t text; begin
  foreach t in array array['announcements','suggestions','surveys'] loop
    execute format('drop trigger if exists %I on hrm.%I', t || '_touch', t);
    execute format('create trigger %I before update on hrm.%I for each row execute function hrm.touch_updated_at()', t || '_touch', t);
  end loop;
  foreach t in array array['announcements','recognitions','suggestions','surveys'] loop
    execute format('drop trigger if exists %I on hrm.%I', t || '_audit', t);
    execute format('create trigger %I after insert or update or delete on hrm.%I for each row execute function hrm.audit_row()', t || '_audit', t);
  end loop;
end $$;

-- ---------- access ----------
do $$ declare t text; begin
  foreach t in array array['announcements','announcement_reads','recognitions','suggestions','surveys','survey_participants','survey_responses'] loop
    execute format('alter table hrm.%I enable row level security', t);
    execute format('drop policy if exists %I on hrm.%I', t || '_hr', t);
    execute format('create policy %I on hrm.%I for all to authenticated using (tenant_id = hrm.current_tenant_id() and hrm.is_hr()) with check (tenant_id = hrm.current_tenant_id() and hrm.is_hr())', t || '_hr', t);
  end loop;
end $$;
-- answers are written only through hrm.submit_survey; HR reads them
drop policy if exists survey_responses_hr on hrm.survey_responses;
create policy survey_responses_hr on hrm.survey_responses for select to authenticated using (tenant_id = hrm.current_tenant_id() and hrm.is_hr());
drop policy if exists survey_participants_hr on hrm.survey_participants;
create policy survey_participants_hr on hrm.survey_participants for select to authenticated using (tenant_id = hrm.current_tenant_id() and hrm.is_hr());
drop policy if exists survey_participants_self on hrm.survey_participants;
create policy survey_participants_self on hrm.survey_participants for select to authenticated using (tenant_id = hrm.current_tenant_id() and employee_id = hrm.current_employee_id());

-- announcements and surveys: everybody they are meant for reads them once published / open
drop policy if exists announcements_read on hrm.announcements;
create policy announcements_read on hrm.announcements for select to authenticated
  using (tenant_id = hrm.current_tenant_id() and status = 'published' and (publish_on is null or publish_on <= (now() at time zone 'Asia/Kolkata')::date)
    and (hrm.has_role('manager') or hrm.in_audience(audience, department_id, plant_id)));
drop policy if exists surveys_read on hrm.surveys;
create policy surveys_read on hrm.surveys for select to authenticated
  using (tenant_id = hrm.current_tenant_id() and status in ('open','closed') and hrm.in_audience(audience, department_id, plant_id));

-- reading / acknowledging: each person his own; a manager sees his team's
drop policy if exists announcement_reads_self on hrm.announcement_reads;
create policy announcement_reads_self on hrm.announcement_reads for all to authenticated
  using (tenant_id = hrm.current_tenant_id() and employee_id = hrm.current_employee_id())
  with check (tenant_id = hrm.current_tenant_id() and employee_id = hrm.current_employee_id());
drop policy if exists announcement_reads_team on hrm.announcement_reads;
create policy announcement_reads_team on hrm.announcement_reads for select to authenticated
  using (tenant_id = hrm.current_tenant_id() and hrm.has_role('manager') and hrm.is_in_my_team(employee_id));

-- recognition: the wall is for everybody; anyone thanks a colleague (not himself); managers recognise their team;
-- Employee of the month is HR's
drop policy if exists recognitions_wall on hrm.recognitions;
create policy recognitions_wall on hrm.recognitions for select to authenticated
  using (tenant_id = hrm.current_tenant_id() and (visible or employee_id = hrm.current_employee_id()));
drop policy if exists recognitions_give on hrm.recognitions;
create policy recognitions_give on hrm.recognitions for insert to authenticated
  with check (tenant_id = hrm.current_tenant_id() and given_by = auth.uid() and category <> 'employee_of_month' and kind in ('peer','manager')
    and employee_id is distinct from hrm.current_employee_id()
    and (kind = 'peer' or (hrm.has_role('manager') and hrm.is_in_my_team(employee_id))));

-- suggestions: an employee sends his own and can change it until it is picked up; the manager reviews his team's;
-- implemented ones are on the Kaizen board for everybody
drop policy if exists suggestions_self on hrm.suggestions;
create policy suggestions_self on hrm.suggestions for select to authenticated
  using (tenant_id = hrm.current_tenant_id() and (employee_id = hrm.current_employee_id() or status = 'implemented'));
drop policy if exists suggestions_send on hrm.suggestions;
create policy suggestions_send on hrm.suggestions for insert to authenticated
  with check (tenant_id = hrm.current_tenant_id() and employee_id = hrm.current_employee_id() and status = 'submitted' and reviewed_by is null);
drop policy if exists suggestions_edit_own on hrm.suggestions;
create policy suggestions_edit_own on hrm.suggestions for update to authenticated
  using (tenant_id = hrm.current_tenant_id() and employee_id = hrm.current_employee_id() and status = 'submitted')
  with check (tenant_id = hrm.current_tenant_id() and employee_id = hrm.current_employee_id() and status = 'submitted' and reviewed_by is null);
drop policy if exists suggestions_team on hrm.suggestions;
create policy suggestions_team on hrm.suggestions for select to authenticated
  using (tenant_id = hrm.current_tenant_id() and hrm.has_role('manager') and hrm.is_in_my_team(employee_id));
drop policy if exists suggestions_team_edit on hrm.suggestions;
create policy suggestions_team_edit on hrm.suggestions for update to authenticated
  using (tenant_id = hrm.current_tenant_id() and hrm.has_role('manager') and hrm.is_in_my_team(employee_id))
  with check (tenant_id = hrm.current_tenant_id() and hrm.is_in_my_team(employee_id));

-- ---------- the AI may also draft announcements and summarise survey comments ----------
alter table hrm.ai_runs drop constraint if exists ai_runs_agent_check;
alter table hrm.ai_runs add constraint ai_runs_agent_check check (agent in ('jd','sheet','programmes','quiz','qms_agent','check','announcement','survey'));

-- ---------- clearing: engagement joins the module flush ----------
-- (recognitions and suggestions also go with their person; the sample / real flushes clear them by their own flag too,
--  so a re-load of the sample never meets the old ones)
create or replace function hrm.module_flush(p_tenant uuid, p_mode text default 'all') returns integer
language plpgsql security definer set search_path = hrm, public as $fn$
declare t text; n int := 0; k int;
  lists text[] := case when p_mode = 'real' then array['recognitions','suggestions','announcements','surveys','training_sessions','ojt_templates','kpis','rr_roles','role_competencies','positions','operations']
                       else array['recognitions','suggestions','announcements','surveys','training_sessions','ojt_templates','training_programs','kpis','rr_roles','role_competencies','positions','operations','competencies'] end;
begin
  if p_mode not in ('all','real','sample') then raise exception 'Unknown flush mode %', p_mode; end if;
  if p_mode = 'all' then
    foreach t in array array['survey_responses','survey_participants','announcement_reads','recognitions','suggestions',
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
  if p_mode = 'all' then perform hrm.seed_qms_defaults(p_tenant); end if;
  return n;
end $fn$;
revoke all on function hrm.module_flush(uuid, text) from public, anon, authenticated;
grant execute on function hrm.module_flush(uuid, text) to service_role;

-- ---------- backup / restore (version 6: + engagement) ----------
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
    'announcements','announcement_reads','suggestions','recognitions','surveys','survey_participants','survey_responses'] loop
    if to_regclass('hrm.' || t) is null then continue; end if;
    if t in ('employee_private') then
      execute format('select coalesce(jsonb_agg(to_jsonb(x)), ''[]'') from hrm.%I x where x.employee_id in (select id from hrm.employees where tenant_id = $1)', t) into rows using p_tenant;
    else
      execute format('select coalesce(jsonb_agg(to_jsonb(x)), ''[]'') from hrm.%I x where x.tenant_id = $1', t) into rows using p_tenant;
    end if;
    out := out || jsonb_build_object(t, rows);
  end loop;
  return jsonb_build_object('format', 'kmr-hrm-backup', 'version', 6, 'exported_at', now(),
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
    'announcements','announcement_reads','suggestions','recognitions','surveys','survey_participants','survey_responses'];
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
  return counts;
end $fn$;
revoke all on function hrm.company_export(uuid), hrm.company_import(uuid, jsonb) from public, anon, authenticated;
grant execute on function hrm.company_export(uuid), hrm.company_import(uuid, jsonb) to service_role;

-- ---------- sample data: engagement among the sample people (deliberately imperfect) ----------
create or replace function hrm.demo_engage(p_tenant uuid) returns integer
language plpgsql security definer set search_path = hrm, public as $fn$
declare t uuid := p_tenant; pfx text; n int := 0; i int; a1 uuid; a2 uuid; a3 uuid; s1 uuid; s2 uuid; sg uuid; p1 uuid;
  people uuid[]; depts uuid[]; plants uuid[]; e uuid; today date := (now() at time zone 'Asia/Kolkata')::date;
  emp_q jsonb := '[
    {"id":"q1","text":"How likely are you to recommend us as a place to work to a friend or relative?","type":"enps","required":true},
    {"id":"q2","text":"I know what is expected of me at work","type":"rating","required":true},
    {"id":"q3","text":"I have the machines, tools and materials to do my job well","type":"rating","required":true},
    {"id":"q4","text":"My supervisor cares about me and my safety","type":"rating","required":true},
    {"id":"q5","text":"I received the training I need for my job","type":"rating","required":true},
    {"id":"q6","text":"Someone recognised my good work in the last month","type":"rating","required":true},
    {"id":"q7","text":"My suggestions are listened to and acted on","type":"rating","required":true},
    {"id":"q8","text":"I feel safe at my workplace","type":"rating","required":true},
    {"id":"q9","text":"I understand our quality policy and how my work affects the customer","type":"rating","required":true},
    {"id":"q10","text":"Do you see yourself working here two years from now?","type":"yesno","required":true},
    {"id":"q11","text":"What is one thing we should improve?","type":"text","required":false},
    {"id":"q12","text":"What do you like most about working here?","type":"text","required":false}]';
  pulse_q jsonb := '[
    {"id":"q1","text":"Quality and taste of canteen food","type":"rating","required":true},
    {"id":"q2","text":"Cleanliness of the canteen and washrooms","type":"rating","required":true},
    {"id":"q3","text":"Company bus timing","type":"choice","options":["Good","Sometimes late","Often late","I do not use the bus"],"required":true},
    {"id":"q4","text":"Anything else we should know?","type":"text","required":false}]';
  improve text[] := array['The shop floor is very hot in the afternoon; please add more fans or coolers near the CNC line',
    'Overtime is told at the last minute; please inform one day before', 'More training on new machines before we are put on them',
    'Canteen food is the same every day, please change the menu', 'Bus comes late on the second shift, we reach home very late',
    'Supervisors should explain the reason when a suggestion is not taken', 'Drinking water point is far from the assembly line',
    'Please fix the leaking roof near stores before the rains', 'Need more safety shoes in all sizes', 'Recognise good work more often, not only at the year end'];
  likes text[] := array['Good team and helpful seniors', 'Salary is paid on time every month', 'I learn new machines here',
    'Supervisor listens to us', 'Safe workplace and clean shop floor', 'Training is given properly', 'Company bus and canteen facility'];
begin
  select emp_code_prefix into pfx from hrm.tenants where id = t;
  select array_agg(id order by employee_code), array_agg(department_id order by employee_code), array_agg(plant_id order by employee_code)
    into people, depts, plants from hrm.employees where tenant_id = t and email like '%@demo.kmr.test' and status = 'active';
  if coalesce(array_length(people, 1), 0) < 12 then return 0; end if;
  if exists (select 1 from hrm.announcements where tenant_id = t and sample) then return 0; end if;    -- already there
  select id into p1 from hrm.plants where tenant_id = t and code = 'DP1';

  -- announcements
  insert into hrm.announcements (tenant_id, title, body, category, audience, pinned, needs_ack, notify, status, publish_on, published_at, notified_at, sample, created_by_name)
  values (t, 'Safety first: safety shoes and goggles are a must in the grinding and paint areas',
    'From Monday, nobody enters the grinding or paint area without safety shoes and goggles. Supervisors will stop work if PPE is missing. New shoes in all sizes are in stores — collect yours with your ID card.' || chr(10) || chr(10) || 'Please acknowledge that you have read this.',
    'safety', 'all', true, true, true, 'published', today - 6, now() - interval '6 days', now() - interval '6 days', true, 'HR (sample)') returning id into a1;
  insert into hrm.announcements (tenant_id, title, body, category, audience, notify, status, publish_on, expires_on, published_at, notified_at, sample, created_by_name)
  values (t, 'Ayudha Pooja: holiday and plant shutdown', 'The plant is closed for Ayudha Pooja. Machines will be cleaned and decorated the day before; pooja at 10 AM in front of the main shop. Sweets for everybody after the pooja.',
    'hr', 'all', true, 'published', today - 2, today + 20, now() - interval '2 days', now() - interval '2 days', true, 'HR (sample)') returning id into a2;
  insert into hrm.announcements (tenant_id, title, body, category, audience, plant_id, notify, status, publish_on, published_at, notified_at, sample, created_by_name)
  values (t, 'Customer audit next week — keep your area audit-ready',
    'Our customer''s quality team visits the plant next week. Keep work instructions at the machine, check sheets filled on time, 5S in your area and your ID card on. If an auditor asks you something you do not know, call your supervisor.',
    'quality', case when p1 is null then 'all' else 'plant' end, p1, true, 'published', today - 1, now() - interval '1 day', now() - interval '1 day', true, 'HR (sample)') returning id into a3;
  insert into hrm.announcements (tenant_id, title, body, category, audience, status, sample, created_by_name)
  values (t, 'Blood donation camp (draft)', 'A blood donation camp with the district hospital. Date to be fixed.', 'event', 'all', 'draft', true, 'HR (sample)');
  n := n + 4;
  -- 14 of the people have read the safety notice, 10 acknowledged it (not everybody — something for HR to chase)
  for i in 1..14 loop
    insert into hrm.announcement_reads (tenant_id, announcement_id, employee_id, read_at, acknowledged_at)
    values (t, a1, people[i], now() - make_interval(days => 6 - (i % 5)), case when i <= 10 then now() - make_interval(days => 6 - (i % 5)) end) on conflict do nothing;
    if i <= 9 then insert into hrm.announcement_reads (tenant_id, announcement_id, employee_id, read_at) values (t, a2, people[i + 3], now() - interval '1 day') on conflict do nothing; end if;
  end loop;

  -- suggestions (D003 … in turn), from fresh to implemented
  insert into hrm.suggestions (tenant_id, employee_id, title, problem, idea, area, category, status, review_note, benefit, saving_per_year, before_text, after_text, implemented_on, reviewed_by_name, decided_at, sample, created_at)
  values
   (t, people[3], 'Poka-yoke pin on the drilling fixture', 'Parts were sometimes loaded the wrong way round; 2–3 rejections a week', 'Add a fool-proof pin so the part fits only one way',
    'Line 1 · OP30 drilling', 'quality', 'implemented', 'Good idea, done by maintenance', 'Wrong loading is now impossible; zero rejections for this defect since', 48000,
    'Part could be loaded either way', 'Part fits only the right way', today - 40, 'Priya (sample)', now() - interval '40 days', true, now() - interval '60 days'),
   (t, people[11], 'Quick-change tool holder on the CNC lathe', 'Tool change takes 12 minutes', 'Use quick-change tool holders for the 4 most used tools',
    'Line 1 · CNC lathe', 'productivity', 'implemented', 'Approved; holders bought', 'Tool change 12 → 4 minutes; about 40 minutes more production per shift', 120000,
    '12 min tool change', '4 min tool change', today - 20, 'Priya (sample)', now() - interval '20 days', true, now() - interval '45 days'),
   (t, people[14], 'Coolant leak tray under the hydraulic pack', 'Oil drips on the floor; slipping risk', 'Fix a drip tray with a drain to the waste oil drum',
    'Maintenance · press shop', 'safety', 'implemented', null, 'No more oil on the floor near the press', 15000, 'Oil on floor', 'Dry floor', today - 10, 'Rahul (sample)', now() - interval '10 days', true, now() - interval '25 days'),
   (t, people[6], 'Colour-coded gauge stand', 'Gauges are mixed up between shifts', 'A shadow board with colour codes for each machine', 'Quality lab', '5s', 'accepted', 'Accepted — maintenance to make the board this month', null, null, null, null, null, 'Suresh (sample)', now() - interval '5 days', true, now() - interval '15 days'),
   (t, people[8], 'Bin labels in Tamil and English', 'New helpers pick the wrong bins', 'Labels in both languages with the part photo', 'Stores', 'quality', 'under_review', 'Checking label printer cost', null, null, null, null, null, 'HR (sample)', null, true, now() - interval '9 days'),
   (t, people[12], 'Second water cooler near the assembly line', 'Long walk to drink water in the afternoon heat', 'Put one water cooler near assembly', 'Assembly', 'ergonomics', 'submitted', null, null, null, null, null, null, null, null, true, now() - interval '12 days'),
   (t, people[16], 'Reuse packing cartons from suppliers', 'We buy new cartons while supplier cartons are thrown away', 'Collect good cartons in stores and reuse them for internal movement', 'Stores · dispatch', 'cost', 'submitted', null, null, null, null, null, null, null, null, true, now() - interval '2 days'),
   (t, people[20], 'Music on the shop floor', 'Work is boring in the night shift', 'Play music on speakers', 'Production', 'other', 'not_taken', 'Not taken: speakers would hide alarms and horns on the shop floor. Thank you for the idea — FM in the canteen is being arranged.', null, null, null, null, null, 'Priya (sample)', now() - interval '3 days', true, now() - interval '8 days');
  n := n + 8;

  -- recognition (an implemented suggestion recognises its author)
  for sg, e in select id, employee_id from hrm.suggestions where tenant_id = t and sample and status = 'implemented' loop
    insert into hrm.recognitions (tenant_id, employee_id, category, message, given_by_name, kind, suggestion_id, sample, created_at)
    select t, e, 'kaizen', 'Kaizen implemented: ' || s.title || coalesce(' — saves ₹' || to_char(s.saving_per_year, 'FM99,99,99,990') || ' a year', ''), 'KMR HRM', 'auto', sg, true, s.decided_at
      from hrm.suggestions s where s.id = sg;
    n := n + 1;
  end loop;
  insert into hrm.recognitions (tenant_id, employee_id, category, message, month, given_by_name, kind, sample, created_at)
  values (t, people[11], 'employee_of_month', 'Trained 4 new operators on the CNC line and kept zero rejections all month.', to_char(today - 30, 'YYYY-MM'), 'HR (sample)', 'hr', true, now() - interval '25 days')
  on conflict do nothing;
  insert into hrm.recognitions (tenant_id, employee_id, category, message, given_by_name, given_by_employee_id, kind, sample, created_at) values
   (t, people[5], 'customer', 'Handled the customer complaint over the weekend and sent the containment report on time.', 'Priya (sample)', people[2], 'manager', true, now() - interval '12 days'),
   (t, people[22], 'safety', 'Stopped a forklift reversing without a banksman — prevented an accident.', 'HR (sample)', null, 'hr', true, now() - interval '7 days'),
   (t, people[4], 'helping', 'Thank you for staying back to help me finish the urgent dispatch!', 'Karthik (sample)', people[3], 'peer', true, now() - interval '4 days'),
   (t, people[7], 'delivery', 'Repaired the spindle overnight; the line started on time next morning.', 'Priya (sample)', people[2], 'manager', true, now() - interval '2 days');
  n := n + 5;

  -- a closed engagement survey with 18 anonymous answers (so results by department show only where 5+ answered)
  insert into hrm.surveys (tenant_id, title, intro, kind, anonymous, audience, questions, status, opens_on, closes_on, notified_at, sample, created_by_name, created_at)
  values (t, 'Employee engagement survey', 'Your answers are anonymous: they carry no name, and results are shown only for groups of 5 or more. About 5 minutes.',
    'engagement', true, 'all', emp_q, 'closed', today - 30, today - 16, now() - interval '30 days', true, 'HR (sample)', now() - interval '31 days') returning id into s1;
  for i in 1..18 loop
    insert into hrm.survey_participants (tenant_id, survey_id, employee_id, responded_on) values (t, s1, people[i], today - 30 + (i % 10));
    insert into hrm.survey_responses (tenant_id, survey_id, department_id, plant_id, answers, submitted_on)
    values (t, s1, depts[i], plants[i], jsonb_build_object(
      'q1', (array[9,10,8,7,9,6,10,8,5,9,7,10,4,8,9,3,7,9])[i],
      'q2', 3 + (i % 3), 'q3', 2 + ((i * 7) % 3), 'q4', 3 + ((i * 5) % 3), 'q5', 2 + ((i * 3) % 4),
      'q6', 1 + ((i * 11) % 4), 'q7', 2 + ((i * 13) % 3), 'q8', 3 + ((i * 2) % 3), 'q9', 3 + ((i * 17) % 3),
      'q10', case when i in (9, 13, 16) then 'no' else 'yes' end,
      'q11', case when i % 6 = 0 then '' else improve[1 + (i % array_length(improve, 1))] end,
      'q12', case when i % 4 = 0 then '' else likes[1 + (i % array_length(likes, 1))] end), today - 30 + (i % 10));
  end loop;
  -- an open pulse survey: 6 have answered; the rest (including the sample employee who signs in) still can
  insert into hrm.surveys (tenant_id, title, intro, kind, anonymous, audience, questions, status, opens_on, closes_on, notified_at, sample, created_by_name, created_at)
  values (t, 'Canteen and transport — quick pulse', 'Four quick questions. Anonymous.', 'canteen', true, 'all', pulse_q, 'open', today - 3, today + 7, now() - interval '3 days', true, 'HR (sample)', now() - interval '3 days') returning id into s2;
  for i in 1..6 loop
    insert into hrm.survey_participants (tenant_id, survey_id, employee_id, responded_on) values (t, s2, people[i], today - 2);
    insert into hrm.survey_responses (tenant_id, survey_id, department_id, plant_id, answers, submitted_on)
    values (t, s2, depts[i], plants[i], jsonb_build_object('q1', 2 + (i % 3), 'q2', 3 + (i % 2),
      'q3', (array['Good','Sometimes late','Often late','Often late','Good','I do not use the bus'])[i],
      'q4', (array['Please add a vegetable variety','','Second shift bus is late most days','','More chairs in the canteen',''])[i]), today - 2);
  end loop;
  n := n + 2;
  return n;
end $fn$;

create or replace function hrm.demo_flow(p_tenant uuid) returns jsonb
language plpgsql security definer set search_path = hrm, public as $fn$
declare r int; q int; g int;
begin
  r := hrm.demo_recruit(p_tenant);
  q := hrm.demo_qms(p_tenant);
  g := hrm.demo_engage(p_tenant);
  return jsonb_build_object('recruitment', r, 'qms', q, 'engagement', g);
end $fn$;
revoke all on function hrm.demo_engage(uuid), hrm.demo_flow(uuid) from public, anon, authenticated;
grant execute on function hrm.demo_engage(uuid), hrm.demo_flow(uuid) to service_role;

-- companies that already hold the sample people get the sample engagement records now
do $$ declare r uuid; begin
  for r in select distinct tenant_id from hrm.employees where email like '%@demo.kmr.test' loop perform hrm.demo_engage(r); end loop;
end $$;

notify pgrst, 'reload schema';
