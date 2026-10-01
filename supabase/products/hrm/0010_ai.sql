-- =====================================================================
-- HRM 0010 — Free AI for the QMS. Needs 0001–0009. Safe to re-run.
-- The AI (free tiers of OpenRouter / Groq / Gemini; keys only in the server's environment) drafts and ranks;
-- people decide:
--   • job descriptions and R&R sheets it writes are marked "AI draft" until HR approves them
--   • training programmes it proposes for needs that have none wait, switched off, until a named person accepts them
--   • pre / post test questions it writes for a programme wait for acceptance before they are printed
--   • the QMS agent finds problems with fixed rules; the AI only says which to work on first
-- Every AI run is logged (what was asked about, which model answered, how long it took).
-- =====================================================================

create table if not exists hrm.ai_runs (
  id              uuid primary key default gen_random_uuid(),
  tenant_id       uuid not null references hrm.tenants(id) on delete cascade,
  agent           text not null check (agent in ('jd','sheet','programmes','quiz','qms_agent','check')),
  subject         text check (length(subject) <= 300),
  ok              boolean not null,
  provider        text,
  model           text,
  used            text check (used in ('ai','rules','none')),
  summary         text check (length(summary) <= 2000),
  output          jsonb,
  error           text check (length(error) <= 2000),
  ms              integer,
  created_by      uuid,
  created_by_name text,
  created_at      timestamptz not null default now()
);
create index if not exists ai_runs_recent on hrm.ai_runs (tenant_id, created_at desc);
alter table hrm.ai_runs enable row level security;
drop policy if exists ai_runs_hr on hrm.ai_runs;
create policy ai_runs_hr on hrm.ai_runs for select to authenticated using (tenant_id = hrm.current_tenant_id() and hrm.is_hr());

alter table hrm.job_descriptions add column if not exists ai_model text;          -- set when the AI wrote this version
alter table hrm.rr_roles add column if not exists ai_model text;
alter table hrm.training_programs add column if not exists ai_proposed boolean not null default false;
alter table hrm.training_programs add column if not exists ai_model text;
alter table hrm.training_programs add column if not exists ai_topics text[] not null default '{}';   -- the need topics an AI-proposed programme is for
alter table hrm.training_programs add column if not exists reviewed_by uuid;
alter table hrm.training_programs add column if not exists reviewed_by_name text;
alter table hrm.training_programs add column if not exists reviewed_at timestamptz;
alter table hrm.training_programs add column if not exists quiz jsonb not null default '[]';      -- [{q, options[4], answer 0-3}]
alter table hrm.training_programs add column if not exists quiz_status text check (quiz_status in ('ai_draft','accepted'));
alter table hrm.training_programs add column if not exists quiz_model text;
alter table hrm.qms_settings add column if not exists ai_enabled boolean not null default true;
alter table hrm.qms_settings add column if not exists agent_result jsonb;      -- the last QMS agent run: findings + ranking
alter table hrm.qms_settings add column if not exists agent_run_at timestamptz;

-- ---------- the full flush also clears the AI log ----------
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

notify pgrst, 'reload schema';
