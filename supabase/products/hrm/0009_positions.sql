-- =====================================================================
-- HRM 0009 — Positions: the QMS runs on Position + Role + Department, never on a designation or a person.
-- Needs 0001–0008. Safe to re-run.
--   Requisition (HR enters Position, Role, Department, competencies needed)
--     → Job description of the position (drafted by the HRM, edited and approved by HR, reused for the next opening)
--       → Roles, Responsibilities, Authority, Competency & KPI sheet of the position (no names; landscape PDF with the
--         company logo and ISO 9001 / IATF 16949 clauses)
--         → Competency mapping of each person holding the position (name + designation) → training needs
--           → training calendar → attendance → effectiveness
--         → KPI sheet of each person: KPI, target, review frequency, review method, actual
-- Each employee has a Position; a new joiner gets it from the requisition he was hired for.
-- =====================================================================

-- ---------- positions ----------
create table if not exists hrm.positions (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null references hrm.tenants(id) on delete cascade,
  title          text not null check (length(title) between 2 and 120),      -- Production Head, Calibration Incharge …
  role           text check (length(role) <= 160),                          -- Shopfloor handling, Manpower handling …
  department_id  uuid references hrm.departments(id) on delete set null,
  family         text,
  active         boolean not null default true,
  sample         boolean not null default false,
  created_by     uuid,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create unique index if not exists positions_key on hrm.positions (tenant_id, lower(title), lower(coalesce(role, '')), coalesce(department_id, '00000000-0000-0000-0000-000000000000'::uuid));

alter table hrm.job_descriptions add column if not exists position_id uuid references hrm.positions(id) on delete set null;
create index if not exists job_descriptions_position on hrm.job_descriptions (position_id, version desc);
alter table hrm.requisitions add column if not exists position_id uuid references hrm.positions(id) on delete set null;
alter table hrm.employees add column if not exists position_id uuid references hrm.positions(id) on delete set null;
create index if not exists employees_position on hrm.employees (tenant_id, position_id);

-- the R&R sheet of a position (rr_roles), its competencies (role_competencies) and KPIs (kpis) hang on the position
alter table hrm.rr_roles alter column designation_id drop not null;
alter table hrm.rr_roles add column if not exists position_id uuid references hrm.positions(id) on delete cascade;
alter table hrm.rr_roles add column if not exists roles text[] not null default '{}';
alter table hrm.rr_roles add column if not exists jd_id uuid references hrm.job_descriptions(id) on delete set null;
alter table hrm.rr_roles add column if not exists doc_no text check (length(doc_no) <= 40);
drop index if exists hrm.rr_roles_desig;
create unique index if not exists rr_roles_position on hrm.rr_roles (position_id) where position_id is not null;

alter table hrm.role_competencies alter column designation_id drop not null;
alter table hrm.role_competencies add column if not exists position_id uuid references hrm.positions(id) on delete cascade;
create unique index if not exists role_competencies_position on hrm.role_competencies (position_id, competency_id) where position_id is not null;

alter table hrm.kpis add column if not exists position_id uuid references hrm.positions(id) on delete cascade;
alter table hrm.kpis add column if not exists review_method text check (length(review_method) <= 200);
alter table hrm.kpis add column if not exists sort_order integer not null default 0;
alter table hrm.kpis alter column target drop not null;
alter table hrm.kpis drop constraint if exists kpis_frequency_check;
alter table hrm.kpis add constraint kpis_frequency_check check (frequency in ('daily','weekly','monthly','quarterly','half_yearly','yearly'));
create index if not exists kpis_position on hrm.kpis (position_id);

drop trigger if exists positions_touch on hrm.positions;
create trigger positions_touch before update on hrm.positions for each row execute function hrm.touch_updated_at();
drop trigger if exists positions_audit on hrm.positions;
create trigger positions_audit after insert or update or delete on hrm.positions for each row execute function hrm.audit_row();
alter table hrm.positions enable row level security;
drop policy if exists positions_hr on hrm.positions;
create policy positions_hr on hrm.positions for all to authenticated using (tenant_id = hrm.current_tenant_id() and hrm.is_hr()) with check (tenant_id = hrm.current_tenant_id() and hrm.is_hr());
drop policy if exists positions_read on hrm.positions;
create policy positions_read on hrm.positions for select to authenticated using (tenant_id = hrm.current_tenant_id());

-- ---------- what was written per designation before becomes a position of that name ----------
do $$
declare r record; pid uuid;
begin
  for r in
    select x.tenant_id, x.designation_id, d.name, bool_and(x.sample) as sample
      from (select tenant_id, designation_id, sample from hrm.rr_roles where position_id is null and designation_id is not null
            union all select tenant_id, designation_id, sample from hrm.role_competencies where position_id is null and designation_id is not null
            union all select tenant_id, designation_id, sample from hrm.kpis where position_id is null and designation_id is not null) x
      join hrm.designations d on d.id = x.designation_id
     where not x.sample
     group by x.tenant_id, x.designation_id, d.name
  loop
    insert into hrm.positions (tenant_id, title, role) values (r.tenant_id, r.name, null)
    on conflict do nothing;
    select id into pid from hrm.positions where tenant_id = r.tenant_id and lower(title) = lower(r.name) and role is null and department_id is null;
    update hrm.rr_roles set position_id = pid where tenant_id = r.tenant_id and designation_id = r.designation_id and position_id is null and not sample;
    update hrm.role_competencies set position_id = pid where tenant_id = r.tenant_id and designation_id = r.designation_id and position_id is null and not sample;
    update hrm.kpis set position_id = pid where tenant_id = r.tenant_id and designation_id = r.designation_id and position_id is null and not sample;
    update hrm.employees set position_id = pid where tenant_id = r.tenant_id and designation_id = r.designation_id and position_id is null and email not like '%@demo.kmr.test';
  end loop;
end $$;
-- several R&R versions per designation and department can now meet on one position: keep the newest
delete from hrm.rr_roles a using hrm.rr_roles b where a.position_id = b.position_id and a.position_id is not null and a.created_at < b.created_at;

-- ---------- clearing: positions join the lists ----------
create or replace function hrm.module_flush(p_tenant uuid, p_mode text default 'all') returns integer
language plpgsql security definer set search_path = hrm, public as $fn$
declare t text; n int := 0; k int;
  lists text[] := case when p_mode = 'real' then array['training_sessions','ojt_templates','kpis','rr_roles','role_competencies','positions','operations']
                       else array['training_sessions','ojt_templates','training_programs','kpis','rr_roles','role_competencies','positions','operations','competencies'] end;
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

-- ---------- backups include the positions ----------
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
    'training_programs','training_sessions','training_needs','training_attendance','training_effectiveness','ojt_templates','ojt_records','auditors','auditor_audits'] loop
    if to_regclass('hrm.' || t) is null then continue; end if;
    if t in ('employee_private') then
      execute format('select coalesce(jsonb_agg(to_jsonb(x)), ''[]'') from hrm.%I x where x.employee_id in (select id from hrm.employees where tenant_id = $1)', t) into rows using p_tenant;
    else
      execute format('select coalesce(jsonb_agg(to_jsonb(x)), ''[]'') from hrm.%I x where x.tenant_id = $1', t) into rows using p_tenant;
    end if;
    out := out || jsonb_build_object(t, rows);
  end loop;
  return jsonb_build_object('format', 'kmr-hrm-backup', 'version', 5, 'exported_at', now(),
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

-- =====================================================================
-- Sample positions (written by the HRM's own job-description writer and R&R-sheet generator)
-- =====================================================================
create or replace function hrm.demo_positions(p_tenant uuid) returns integer
language plpgsql security definer set search_path = hrm, public as $fn$
declare
  t uuid := p_tenant; pfx text; x jsonb; c jsonb; k jsonb; h text; pid uuid; jid uuid; rid uuid; cid uuid; m text; n int := 0; i int;
  spec jsonb := $spec$[{"title": "CNC Operator", "role": "Machine operation", "dept": "Production", "family": "operator", "holders": ["D003", "D004", "D010", "D011", "D012", "D015", "D016", "D020", "D021", "D023", "D024"], "status": "approved", "jd": {"purpose": "Operate and set machines safely to produce good parts to the drawing and work instruction. The role covers machine operation.", "responsibilities": ["Operate the machine as per the work instruction and set-up sheet", "Do first-off and in-process checks and record them", "Do the daily autonomous-maintenance checks", "Operate and set the machine as per the work instruction", "Do first-off and in-process checks with gauges; record them", "Report abnormalities and stop on doubt", "Maintain 5S and do autonomous maintenance checks"], "kpis": ["Output per shift", "Rejection %"], "must_have": [{"name": "CNC machining", "weight": 3}, {"name": "Inspection & metrology", "weight": 2}, {"name": "Shop-floor discipline (5S, SOP, check sheets)", "weight": 2}], "good_to_have": [{"name": "Lean / continuous improvement", "weight": 1}, {"name": "TPM / maintenance excellence", "weight": 1}, {"name": "Welding / fabrication", "weight": 1}], "qualifications": "ITI / 10th / 12th", "experience": "1–4 years", "reporting_to": "Operator / technician Manager", "context": "Automotive / engineering manufacturing plant working to IATF 16949 / ISO 9001", "outcomes": ["Right-first-time parts at the planned output"]}, "sheet": {"purpose": "Operate and set machines safely to produce good parts to the drawing and work instruction. The role covers machine operation.", "roles": ["Machine operation", "Operator / technician"], "responsibilities": ["Operate the machine as per the work instruction and set-up sheet", "Do first-off and in-process checks and record them", "Do the daily autonomous-maintenance checks", "Operate and set the machine as per the work instruction", "Do first-off and in-process checks with gauges; record them", "Report abnormalities and stop on doubt", "Maintain 5S and do autonomous maintenance checks"], "authorities": ["Stop the machine on a quality or safety doubt", "Stop work on a safety doubt"], "competencies": [{"name": "CNC machining", "level": 3, "category": "technical"}, {"name": "Inspection & metrology", "level": 2, "category": "quality"}, {"name": "Shop-floor discipline (5S, SOP, check sheets)", "level": 2, "category": "behavioural"}], "kpis": [{"name": "Output per shift", "unit": "parts", "target": 420, "direction": "higher", "frequency": "daily", "review_method": "Shift production report; monthly summary", "data_source": "Production report"}, {"name": "Rejection %", "unit": "%", "target": 1, "direction": "lower", "frequency": "monthly", "review_method": "Rejection register reviewed in the daily meeting and monthly review", "data_source": "Rejection register"}]}}, {"title": "Production Supervisor", "role": "Shopfloor & manpower handling", "dept": "Production", "family": "production", "holders": ["D002"], "status": "approved", "jd": {"purpose": "Deliver the daily production plan of the Production line safely, on time and right first time, with the agreed manpower and machine capacity. The role covers shopfloor handling, manpower handling.", "responsibilities": ["Run the shift / line to the production plan: output, quality, delivery and safety", "Release the set-up and first-off; review check sheets every shift", "Hold the daily start-of-shift meeting on yesterday's quality, safety and output", "Escalate abnormalities through the escalation matrix within the agreed time", "Plan manpower for each shift using the skill matrix; no one works alone on an operation he is not qualified for", "Raise training needs for the team and evaluate training effectiveness on the job", "Maintain attendance, discipline and morale; resolve grievances early", "Develop backups for key operations and people", "Run the shift or line to the daily production plan; report output, rejections and downtime", "Allocate manpower and machines; balance the line to the takt time", "Ensure work instructions, set-up approval and first-off inspection are followed", "Drive productivity, OEE and cycle-time improvement with kaizens", "Lead and develop the team; set targets, review performance and build backups for key skills"], "kpis": ["Plan vs actual output", "OEE", "Absenteeism %", "Skill matrix coverage %"], "must_have": [{"name": "Production / shop-floor management", "weight": 3}, {"name": "Shop-floor discipline (5S, SOP, check sheets)", "weight": 3}, {"name": "People leadership", "weight": 3}, {"name": "Communication & documentation", "weight": 2}, {"name": "Lean / continuous improvement", "weight": 1}], "good_to_have": [{"name": "Production planning & control", "weight": 1}, {"name": "TPM / maintenance excellence", "weight": 1}, {"name": "CNC machining", "weight": 1}, {"name": "ERP (SAP / Oracle / Tally)", "weight": 1}, {"name": "Health, safety & environment", "weight": 1}], "qualifications": "B.E / B.Tech or Diploma (Mechanical / Production)", "experience": "5–10 years", "reporting_to": "Plant Head", "context": "Automotive / engineering manufacturing plant working to IATF 16949 / ISO 9001", "outcomes": ["Meet the daily plan with first-time-right quality", "Raise OEE and productivity on the line", "Zero safety incidents"]}, "sheet": {"purpose": "Deliver the daily production plan of the Production line safely, on time and right first time, with the agreed manpower and machine capacity. The role covers shopfloor handling, manpower handling.", "roles": ["Shopfloor handling", "Manpower handling", "Production"], "responsibilities": ["Run the shift / line to the production plan: output, quality, delivery and safety", "Release the set-up and first-off; review check sheets every shift", "Hold the daily start-of-shift meeting on yesterday's quality, safety and output", "Escalate abnormalities through the escalation matrix within the agreed time", "Plan manpower for each shift using the skill matrix; no one works alone on an operation he is not qualified for", "Raise training needs for the team and evaluate training effectiveness on the job", "Maintain attendance, discipline and morale; resolve grievances early", "Develop backups for key operations and people", "Run the shift or line to the daily production plan; report output, rejections and downtime", "Allocate manpower and machines; balance the line to the takt time", "Ensure work instructions, set-up approval and first-off inspection are followed", "Drive productivity, OEE and cycle-time improvement with kaizens", "Lead and develop the team; set targets, review performance and build backups for key skills"], "authorities": ["Stop the line on a quality, safety or delivery risk", "Hold and red-tag suspect material", "Allocate people to operations within their qualification", "Recommend leave, overtime and permission for the team", "Segregate and rework as per the reaction plan", "Stop work on a safety doubt"], "competencies": [{"name": "Production / shop-floor management", "level": 3, "category": "management"}, {"name": "Shop-floor discipline (5S, SOP, check sheets)", "level": 3, "category": "behavioural"}, {"name": "People leadership", "level": 3, "category": "management"}, {"name": "Communication & documentation", "level": 2, "category": "behavioural"}, {"name": "Lean / continuous improvement", "level": 1, "category": "technical"}], "kpis": [{"name": "Plan vs actual output", "unit": "%", "target": 98, "direction": "higher", "frequency": "daily", "review_method": "Daily production meeting; monthly summary", "data_source": "Production report"}, {"name": "OEE", "unit": "%", "target": 75, "direction": "higher", "frequency": "monthly", "review_method": "OEE sheet reviewed monthly", "data_source": "OEE sheet"}, {"name": "Absenteeism %", "unit": "%", "target": 3, "direction": "lower", "frequency": "monthly", "review_method": "Attendance report review", "data_source": "HRM attendance"}, {"name": "Skill matrix coverage %", "unit": "%", "target": 100, "direction": "higher", "frequency": "monthly", "review_method": "Skill matrix review", "data_source": "HRM skill matrix"}]}}, {"title": "Quality Engineer", "role": "Customer quality & audits", "dept": "Quality", "family": "quality", "holders": ["D005", "D013"], "status": "approved", "jd": {"purpose": "Make sure every part the Quality team ships meets the customer's requirements, and drive down rejections and customer complaints across the plant. The role covers quality control.", "responsibilities": ["Inspect as per the control plan; record results and act on out-of-tolerance readings", "Handle complaints with 8D; verify that corrective actions work", "Run layered process audits and follow up the findings", "Run incoming, in-process and final inspection as per the control plan and inspection standards", "Handle customer complaints end to end with 8D / root-cause analysis and verify corrective actions", "Prepare and maintain PPAP, APQP, PFMEA and control-plan documents for new and changed parts", "Monitor process capability with SPC (Cp/Cpk) and MSA studies; act on out-of-control signals"], "kpis": ["Customer PPM", "Internal rejection %"], "must_have": [{"name": "Problem solving (8D, RCA, CAPA)", "weight": 3}, {"name": "Core tools (APQP, PPAP, FMEA, SPC, MSA)", "weight": 2}, {"name": "Quality improvement", "weight": 1}, {"name": "Inspection & metrology", "weight": 1}, {"name": "IATF 16949 / ISO 9001", "weight": 1}], "good_to_have": [{"name": "Customer quality / OEM interface", "weight": 1}, {"name": "Supplier quality development", "weight": 1}, {"name": "Internal / process audits", "weight": 1}, {"name": "Six Sigma", "weight": 1}, {"name": "Statistical analysis (SPC, Cpk, MSA)", "weight": 1}], "qualifications": "Diploma or B.E / B.Tech (Mechanical / Production)", "experience": "3–6 years", "reporting_to": "Quality Manager", "context": "Automotive / engineering manufacturing plant working to IATF 16949 / ISO 9001", "outcomes": ["Bring customer PPM down and hold it", "Close customer complaints with effective, verified corrective action", "Keep the plant audit-ready for IATF 16949"]}, "sheet": {"purpose": "Make sure every part the Quality team ships meets the customer's requirements, and drive down rejections and customer complaints across the plant. The role covers quality control.", "roles": ["Quality control"], "responsibilities": ["Inspect as per the control plan; record results and act on out-of-tolerance readings", "Handle complaints with 8D; verify that corrective actions work", "Run layered process audits and follow up the findings", "Run incoming, in-process and final inspection as per the control plan and inspection standards", "Handle customer complaints end to end with 8D / root-cause analysis and verify corrective actions", "Prepare and maintain PPAP, APQP, PFMEA and control-plan documents for new and changed parts", "Monitor process capability with SPC (Cp/Cpk) and MSA studies; act on out-of-control signals"], "authorities": ["Hold, segregate and reject non-conforming product", "Stop dispatch of suspect lots", "Accept or reject product against the specification", "Hold dispatch of suspect product", "Raise a corrective action request on any department or supplier", "Stop work on a safety doubt"], "competencies": [{"name": "Problem solving (8D, RCA, CAPA)", "level": 3, "category": "quality"}, {"name": "Core tools (APQP, PPAP, FMEA, SPC, MSA)", "level": 2, "category": "quality"}, {"name": "Quality improvement", "level": 1, "category": "quality"}, {"name": "Inspection & metrology", "level": 1, "category": "quality"}, {"name": "IATF 16949 / ISO 9001", "level": 1, "category": "quality"}], "kpis": [{"name": "Customer PPM", "unit": "PPM", "target": 50, "direction": "lower", "frequency": "monthly", "review_method": "Customer scorecard reviewed in the monthly quality review", "data_source": "Customer scorecard / complaint register"}, {"name": "Internal rejection %", "unit": "%", "target": 1, "direction": "lower", "frequency": "monthly", "review_method": "Rejection register reviewed in the daily meeting and monthly review", "data_source": "Rejection register"}]}}, {"title": "Calibration Incharge", "role": "Calibration & gauge control", "dept": "Quality", "family": "quality", "holders": ["D006"], "status": "approved", "jd": {"purpose": "Make sure every part the Quality team ships meets the customer's requirements, and drive down rejections and customer complaints across the plant. The role covers calibration & gauge control.", "responsibilities": ["Maintain the calibration plan and history of every gauge and measuring instrument", "Calibrate in-house as per the procedure, or through an accredited (NABL / ISO 17025) laboratory", "Run MSA (GR&R, bias, linearity) for the gauges in the control plan", "Assess the effect on product when a gauge is found out of calibration, and inform Quality", "Keep gauges identified, stored and protected; withdraw damaged gauges", "Run incoming, in-process and final inspection as per the control plan and inspection standards", "Handle customer complaints end to end with 8D / root-cause analysis and verify corrective actions", "Prepare and maintain PPAP, APQP, PFMEA and control-plan documents for new and changed parts", "Monitor process capability with SPC (Cp/Cpk) and MSA studies; act on out-of-control signals", "Lead and develop the team; set targets, review performance and build backups for key skills"], "kpis": ["Calibration plan adherence %", "Gauges overdue for calibration", "Customer PPM", "Internal rejection %"], "must_have": [{"name": "Inspection & metrology", "weight": 3}, {"name": "Statistical analysis (SPC, Cpk, MSA)", "weight": 2}, {"name": "IATF 16949 / ISO 9001", "weight": 2}, {"name": "Core tools (APQP, PPAP, FMEA, SPC, MSA)", "weight": 2}, {"name": "Problem solving (8D, RCA, CAPA)", "weight": 2}, {"name": "Quality improvement", "weight": 1}, {"name": "People leadership", "weight": 2}], "good_to_have": [{"name": "Customer quality / OEM interface", "weight": 1}, {"name": "Supplier quality development", "weight": 1}, {"name": "Internal / process audits", "weight": 1}, {"name": "Six Sigma", "weight": 1}], "qualifications": "B.E / B.Tech (Mechanical / Production / Automobile); IATF internal-auditor training preferred", "experience": "3–8 years", "reporting_to": "Plant Head", "context": "Automotive / engineering manufacturing plant working to IATF 16949 / ISO 9001", "outcomes": ["Bring customer PPM down and hold it", "Close customer complaints with effective, verified corrective action", "Keep the plant audit-ready for IATF 16949"]}, "sheet": {"purpose": "Make sure every part the Quality team ships meets the customer's requirements, and drive down rejections and customer complaints across the plant. The role covers calibration & gauge control.", "roles": ["Calibration & gauge control", "Quality"], "responsibilities": ["Maintain the calibration plan and history of every gauge and measuring instrument", "Calibrate in-house as per the procedure, or through an accredited (NABL / ISO 17025) laboratory", "Run MSA (GR&R, bias, linearity) for the gauges in the control plan", "Assess the effect on product when a gauge is found out of calibration, and inform Quality", "Keep gauges identified, stored and protected; withdraw damaged gauges", "Run incoming, in-process and final inspection as per the control plan and inspection standards", "Handle customer complaints end to end with 8D / root-cause analysis and verify corrective actions", "Prepare and maintain PPAP, APQP, PFMEA and control-plan documents for new and changed parts", "Monitor process capability with SPC (Cp/Cpk) and MSA studies; act on out-of-control signals", "Lead and develop the team; set targets, review performance and build backups for key skills"], "authorities": ["Withdraw an out-of-calibration or damaged gauge from use", "Reject a calibration certificate that does not meet the requirement", "Accept or reject product against the specification", "Hold dispatch of suspect product", "Raise a corrective action request on any department or supplier", "Stop work on a safety doubt"], "competencies": [{"name": "Inspection & metrology", "level": 4, "category": "quality"}, {"name": "Statistical analysis (SPC, Cpk, MSA)", "level": 2, "category": "quality"}, {"name": "IATF 16949 / ISO 9001", "level": 2, "category": "quality"}, {"name": "Core tools (APQP, PPAP, FMEA, SPC, MSA)", "level": 2, "category": "quality"}, {"name": "Problem solving (8D, RCA, CAPA)", "level": 2, "category": "quality"}, {"name": "Quality improvement", "level": 1, "category": "quality"}, {"name": "People leadership", "level": 2, "category": "management"}], "kpis": [{"name": "Calibration plan adherence %", "unit": "%", "target": 100, "direction": "higher", "frequency": "monthly", "review_method": "Plan vs actual reviewed monthly", "data_source": "PM / calibration plan"}, {"name": "Gauges overdue for calibration", "unit": "nos", "target": 0, "direction": "lower", "frequency": "monthly", "review_method": "Calibration status check, monthly", "data_source": "Calibration plan"}, {"name": "Customer PPM", "unit": "PPM", "target": 50, "direction": "lower", "frequency": "monthly", "review_method": "Customer scorecard reviewed in the monthly quality review", "data_source": "Customer scorecard / complaint register"}, {"name": "Internal rejection %", "unit": "%", "target": 1, "direction": "lower", "frequency": "monthly", "review_method": "Rejection register reviewed in the daily meeting and monthly review", "data_source": "Rejection register"}]}}, {"title": "Maintenance Technician", "role": "Maintenance", "dept": "Maintenance", "family": "maintenance", "holders": ["D007", "D014"], "status": "draft", "jd": {"purpose": "Keep plant machines and utilities available and reliable through planned maintenance and quick, lasting breakdown repair. The role covers maintenance.", "responsibilities": ["Attend breakdowns and find the root cause so they do not repeat", "Carry out preventive maintenance as per the PM plan", "Keep critical spares and the machine history card up to date", "Attend breakdowns quickly and find the root cause so they do not repeat", "Plan and carry out preventive and predictive maintenance as per the PM schedule", "Maintain hydraulic, pneumatic, electrical and PLC-controlled systems", "Keep critical spares and the maintenance history up to date"], "kpis": ["MTBF", "MTTR", "PM adherence %", "Machine availability %"], "must_have": [{"name": "TPM / maintenance excellence", "weight": 3}, {"name": "Mechanical maintenance", "weight": 2}, {"name": "Electrical maintenance", "weight": 2}], "good_to_have": [{"name": "Health, safety & environment", "weight": 1}, {"name": "CNC machining", "weight": 1}, {"name": "ERP (SAP / Oracle / Tally)", "weight": 1}, {"name": "Lean / continuous improvement", "weight": 1}], "qualifications": "Diploma or ITI (Fitter / Electrician)", "experience": "2–5 years", "reporting_to": "Maintenance Manager", "context": "Automotive / engineering manufacturing plant working to IATF 16949 / ISO 9001", "outcomes": ["Raise machine availability and MTBF", "Cut repeat breakdowns"]}, "sheet": {"purpose": "Keep plant machines and utilities available and reliable through planned maintenance and quick, lasting breakdown repair. The role covers maintenance.", "roles": ["Maintenance"], "responsibilities": ["Attend breakdowns and find the root cause so they do not repeat", "Carry out preventive maintenance as per the PM plan", "Keep critical spares and the machine history card up to date", "Attend breakdowns quickly and find the root cause so they do not repeat", "Plan and carry out preventive and predictive maintenance as per the PM schedule", "Maintain hydraulic, pneumatic, electrical and PLC-controlled systems", "Keep critical spares and the maintenance history up to date"], "authorities": ["Take a machine out of production for safety or repair", "Apply lock-out tag-out and permit to work", "Stop work on a safety doubt"], "competencies": [{"name": "TPM / maintenance excellence", "level": 3, "category": "behavioural"}, {"name": "Mechanical maintenance", "level": 2, "category": "technical"}, {"name": "Electrical maintenance", "level": 2, "category": "technical"}], "kpis": [{"name": "MTBF", "unit": "hours", "target": 200, "direction": "higher", "frequency": "monthly", "review_method": "Breakdown analysis in the monthly review", "data_source": "Machine history card"}, {"name": "MTTR", "unit": "hours", "target": 2, "direction": "lower", "frequency": "monthly", "review_method": "Breakdown analysis in the monthly review", "data_source": "Breakdown register"}, {"name": "PM adherence %", "unit": "%", "target": 100, "direction": "higher", "frequency": "monthly", "review_method": "Plan vs actual reviewed monthly", "data_source": "PM / calibration plan"}, {"name": "Machine availability %", "unit": "%", "target": 95, "direction": "higher", "frequency": "monthly", "review_method": "Breakdown analysis in the monthly review", "data_source": "Breakdown register"}]}}]$spec$::jsonb;
begin
  select emp_code_prefix into pfx from hrm.tenants where id = t;
  if not exists (select 1 from hrm.employees where tenant_id = t and email like '%@demo.kmr.test') then return 0; end if;
  if exists (select 1 from hrm.positions where tenant_id = t and sample) then return 0; end if;
  for x in select * from jsonb_array_elements(spec) loop
    insert into hrm.positions (tenant_id, title, role, department_id, family, sample)
    values (t, x->>'title', x->>'role', (select id from hrm.departments where tenant_id = t and name = x->>'dept'), x->>'family', true)
    on conflict do nothing returning id into pid;
    if pid is null then continue; end if;
    n := n + 1;
    -- the job description of the position: the sample hiring flow's JD of the same title becomes version 1 (archived),
    -- the position's JD (written with the Role) is version 2, approved
    update hrm.job_descriptions set position_id = pid, status = case when status = 'approved' then 'archived' else status end
     where tenant_id = t and sample and title = x->>'title' and position_id is null;
    insert into hrm.job_descriptions (tenant_id, position_id, title, family, purpose, responsibilities, kpis, must_have, good_to_have, qualifications, experience, reporting_to,
                                      context, outcomes, version, status, approved_at, sample)
    values (t, pid, x->>'title', x->>'family', x->'jd'->>'purpose', array(select jsonb_array_elements_text(x->'jd'->'responsibilities')),
            array(select jsonb_array_elements_text(x->'jd'->'kpis')), x->'jd'->'must_have', x->'jd'->'good_to_have', x->'jd'->>'qualifications',
            x->'jd'->>'experience', x->'jd'->>'reporting_to', x->'jd'->>'context', array(select jsonb_array_elements_text(x->'jd'->'outcomes')),
            coalesce((select max(version) from hrm.job_descriptions where position_id = pid), 0) + 1, 'approved', now() - interval '150 days', true)
    returning id into jid;
    update hrm.requisitions set position_id = pid where tenant_id = t and sample and title = x->>'title';
    -- the R&R sheet
    insert into hrm.rr_roles (tenant_id, position_id, department_id, purpose, roles, responsibilities, authorities, interfaces, version, status, approved_at, jd_id, doc_no, sample)
    values (t, pid, (select department_id from hrm.positions where id = pid), x->'sheet'->>'purpose', array(select jsonb_array_elements_text(x->'sheet'->'roles')),
            array(select jsonb_array_elements_text(x->'sheet'->'responsibilities')), array(select jsonb_array_elements_text(x->'sheet'->'authorities')),
            array['Production','Quality','Maintenance','HR'], 1, x->>'status', case when x->>'status' = 'approved' then now() - interval '140 days' end, jid,
            'HR-RR-' || lpad(n::text, 3, '0'), true)
    returning id into rid;
    i := 0;
    for c in select * from jsonb_array_elements(x->'sheet'->'competencies') loop
      insert into hrm.competencies (tenant_id, name, category, sample) values (t, c->>'name', c->>'category', true) on conflict (tenant_id, name) do nothing;
      select id into cid from hrm.competencies where tenant_id = t and name = c->>'name';
      insert into hrm.role_competencies (tenant_id, position_id, competency_id, required_level, sample) values (t, pid, cid, (c->>'level')::int, true) on conflict do nothing;
    end loop;
    for k in select * from jsonb_array_elements(x->'sheet'->'kpis') loop
      i := i + 1;
      insert into hrm.kpis (tenant_id, position_id, department_id, name, unit, target, direction, frequency, review_method, data_source, weight, sort_order, sample)
      values (t, pid, null, k->>'name', k->>'unit', (k->>'target')::numeric, k->>'direction', k->>'frequency', k->>'review_method', k->>'data_source',
              case when i <= 2 then 2 else 1 end, i, true);
    end loop;
    -- the people who hold the position
    for h in select jsonb_array_elements_text(x->'holders') loop
      update hrm.employees set position_id = pid where tenant_id = t and employee_code = pfx || '-' || h;
    end loop;
  end loop;
  -- the sample new joiner holds the position he was hired for
  update hrm.employees e set position_id = r.position_id
    from hrm.offers o join hrm.applications a on a.id = o.application_id join hrm.requisitions r on r.id = a.requisition_id
   where o.employee_id = e.id and e.tenant_id = t and e.email like '%@demo.kmr.test' and r.position_id is not null and e.position_id is null;

  -- competency mapping: most people meet the need, some are one or two levels short (the gaps the TNI picks up)
  insert into hrm.employee_competencies (tenant_id, employee_id, competency_id, level, assessed_on, assessed_by_name, method)
  select t, e.id, rc.competency_id,
         greatest(0, least(4, rc.required_level - case when (abs(hashtext(e.id::text || rc.competency_id::text)) % 5) = 0 then 1 when (abs(hashtext(e.id::text || rc.competency_id::text)) % 11) = 0 then 2 else 0 end
                                        + case when (abs(hashtext(rc.competency_id::text || e.id::text)) % 7) = 0 then 1 else 0 end)),
         current_date - (abs(hashtext(e.id::text)) % 120), 'Arun Kumar', 'observation'
    from hrm.employees e join hrm.role_competencies rc on rc.position_id = e.position_id and rc.sample
   where e.tenant_id = t and e.email like '%@demo.kmr.test' and e.status = 'active'
  on conflict (employee_id, competency_id) do nothing;
  -- R&R acknowledged by most holders
  insert into hrm.rr_acks (tenant_id, rr_id, employee_id, version, acknowledged_at)
  select t, r.id, e.id, r.version, now() - ((abs(hashtext(e.id::text)) % 90) || ' days')::interval
    from hrm.rr_roles r join hrm.employees e on e.position_id = r.position_id and e.email like '%@demo.kmr.test' and e.status = 'active'
   where r.tenant_id = t and r.sample and r.status = 'approved' and (abs(hashtext(e.id::text)) % 4) <> 0
  on conflict do nothing;
  -- KPI sheets: three months of actuals
  for i in 1..3 loop
    m := to_char(date_trunc('month', current_date) - (i || ' months')::interval, 'YYYY-MM');
    insert into hrm.kpi_values (tenant_id, kpi_id, employee_id, month, actual)
    select t, kp.id, e.id, m,
           round((case when kp.target = 0 then (abs(hashtext(e.id::text || m || kp.id::text)) % 3) / 2.0
                       when kp.direction = 'higher' then kp.target * (0.88 + (abs(hashtext(e.id::text || m || kp.id::text)) % 20) / 100.0)
                       else kp.target * (0.6 + (abs(hashtext(e.id::text || m || kp.id::text)) % 90) / 100.0) end)::numeric,
                 case when kp.unit in ('%', 'Cpk', 'hours') then 1 else 0 end)
      from hrm.kpis kp join hrm.employees e on e.position_id = kp.position_id and e.email like '%@demo.kmr.test' and e.status = 'active'
     where kp.tenant_id = t and kp.sample and kp.target is not null
    on conflict do nothing;
  end loop;
  return n;
end $fn$;

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

  -- ---- positions: job description → R&R sheet (roles, responsibilities, authority, competency, KPI) → people ----
  perform hrm.demo_positions(t);

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

revoke all on function hrm.demo_positions(uuid), hrm.demo_qms(uuid) from public, anon, authenticated;
grant execute on function hrm.demo_positions(uuid), hrm.demo_qms(uuid) to service_role;

-- companies with the sample people: the old per-designation sample R&R, competencies and KPIs make way for the positions
do $$ declare r uuid; begin
  for r in select distinct tenant_id from hrm.employees where email like '%@demo.kmr.test' loop
    delete from hrm.rr_roles where tenant_id = r and sample and position_id is null;
    delete from hrm.role_competencies where tenant_id = r and sample and position_id is null;
    delete from hrm.kpis where tenant_id = r and sample and position_id is null;
    delete from hrm.employee_competencies ec using hrm.employees e where e.id = ec.employee_id and e.tenant_id = r and e.email like '%@demo.kmr.test';
    perform hrm.demo_positions(r);
  end loop;
end $$;

notify pgrst, 'reload schema';
