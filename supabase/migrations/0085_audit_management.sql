-- =====================================================================
-- 0085 — Audit management upgrade (extends Internal Audit, product code 'aud')
--  • More kinds of audit: system, process (VDA 6.3 scale 10/8/6/4/0), product, layered process, document, supplier, special process (CQI), EHS, laboratory.
--  • Each checklist question keeps its clause, standard, evidence hint, weight and the auditor's answer; Major or Minor is decided by fixed rules (see aud-engine.js).
--  • Findings (nonconformities) with a full corrective-action record: problem, containment, why-why root cause, permanent action, effectiveness check, closure.
--    The database enforces the rules in plain words: a root cause must be at least three whys deep and must not stop at a person; a Major finding cannot be
--    closed with training alone; the effect is checked only after the monitoring period; a finding whose action did not work goes back to root cause as Major.
--  • Special audit points register (customer, standard or management points that are checked in audits until closed with clause, standard, evidence).
--  • Year programme generator, dashboard with findings, ageing, repeat and effectiveness, backup and restore of the new tables.
-- Needs 0082. Safe to re-run. No new priced feature: everything is part of 'Audit programme and reports'.
-- =====================================================================
do $$ begin
  if to_regprocedure('public.kmr_aud_audit_save(text, jsonb)') is null then raise exception 'Run 0082_internal_audit.sql first.'; end if;
end $$;

-- ---------- audit types, extra data on an audit ----------
alter table console.aud_audits drop constraint if exists aud_audits_type_check;
alter table console.aud_audits add constraint aud_audits_type_check check (type in ('System', 'Process', 'Product', 'Supplier', 'LPA', 'Document', 'Special', 'EHS', 'Lab'));
alter table console.aud_audits add column if not exists meta jsonb not null default '{}';

-- ---------- findings ----------
create table if not exists console.aud_ncs (
  id uuid primary key default gen_random_uuid(), customer_id uuid not null references console.customers(id) on delete cascade,
  audit_id uuid not null references console.aud_audits(id) on delete cascade, q_id text, no text not null,
  clause text, standard text, requirement text, cat text, severity text not null check (severity in ('Major', 'Minor')), rule_text text, repeat_of text, loops int not null default 0,
  problem text, evidence text, area text,
  status text not null default 'contain' check (status in ('contain', 'rca', 'action', 'monitor', 'closed', 'cancelled')),
  owner text, resp_due date,
  contain_action text, contain_owner text, contain_due date, contain_done_on date, contain_qty text,
  whys jsonb not null default '[]', root_cause text, escape_cause text, systemic text,
  atype jsonb not null default '[]', perm_action text, perm_owner text, perm_due date, perm_done_on date, perm_evidence text, horizontal text,
  mon_method text, mon_criteria text, mon_days int, mon_due date, mon_result text check (mon_result in ('effective', 'not_effective')), mon_note text, mon_on date,
  closed_on date, closed_by text, cancel_reason text,
  sample boolean not null default false, created_by text, created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique (customer_id, no));
create unique index if not exists aud_ncs_q on console.aud_ncs (audit_id, q_id) where q_id is not null;
create index if not exists aud_ncs_open on console.aud_ncs (customer_id, status);
create index if not exists aud_ncs_clause on console.aud_ncs (customer_id, clause);

-- ---------- special audit points ----------
create table if not exists console.aud_points (
  id uuid primary key default gen_random_uuid(), customer_id uuid not null references console.customers(id) on delete cascade, no text not null,
  title text not null, source text, standard text not null, clause text not null, description text, check_how text, frequency text not null default 'Every audit', applies text, owner text, due_on date,
  status text not null default 'open' check (status in ('open', 'closed')), checks jsonb not null default '[]', last_checked date, last_result text,
  closed_on date, closure_note text, evidence text,
  sample boolean not null default false, created_by text, created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique (customer_id, no));
do $$ declare t text; begin foreach t in array array['aud_ncs', 'aud_points'] loop
  execute format('alter table console.%I enable row level security', t);
  if not exists (select 1 from pg_policies where schemaname = 'console' and tablename = t and policyname = t || '_staff') then
    execute format('create policy %I on console.%I for all using (console.is_staff()) with check (console.is_staff())', t || '_staff', t);
  end if;
  execute format('revoke all on console.%I from public, anon, authenticated', t);
end loop; end $$;

-- ---------- helpers ----------
create or replace function console.aud_nc_number(p_cid uuid, p_kind text) returns text language plpgsql security definer set search_path = console, public as $$
declare cfg jsonb := console.aud_cfg(p_cid); pre text; d date := console.aud_today(); y int; fyt text; n bigint;
begin
  pre := upper(regexp_replace(coalesce(console.aud_txt(cfg, 'prefix'), 'AUD'), '[^A-Za-z0-9-]', '', 'g')); if pre = '' then pre := 'AUD'; end if;
  y := extract(year from d)::int; if extract(month from d) < 4 then y := y - 1; end if;
  fyt := lpad((y % 100)::text, 2, '0') || '-' || lpad(((y + 1) % 100)::text, 2, '0');
  n := console.aud_next(p_cid, p_kind || '-' || fyt);
  return pre || '-' || p_kind || '/' || fyt || '/' || lpad(n::text, 4, '0');
end $$;

-- VDA 6.3 scale is 10, 8, 6, 4, 0; layered process audits use OK, Minor, Major, NA
create or replace function console.aud_ratings(p_type text) returns text[] language sql immutable as $$
  select case when p_type = 'Process' then array['10','8','6','4','0','NA'] else array['OK','Minor','Major','Observation','NA'] end $$;
create or replace function console.aud_is_finding(p_rating text) returns boolean language sql immutable as $$ select p_rating in ('Minor','Major','8','6','4','0') $$;
create or replace function console.aud_score(p_list jsonb, out score numeric, out grade text) language plpgsql immutable as $$
declare n int; s numeric; z int;
begin
  select count(*), coalesce(sum((x ->> 'rating')::numeric), 0), count(*) filter (where x ->> 'rating' = '0') into n, s, z
    from jsonb_array_elements(p_list) x where x ->> 'rating' in ('10','8','6','4','0');
  if n = 0 then score := null; grade := null; return; end if;
  score := round(s * 100 / (10 * n), 1);
  grade := case when score >= 90 then 'A' when score >= 80 then 'B' else 'C' end;
  if z > 0 and grade = 'A' then grade := 'B'; end if;
end $$;

-- the root cause must be at least three whys deep, go one level deeper each time, and not stop at a person
create or replace function console.aud_nc_rca_problem(p_whys jsonb, p_root text, p_escape text, p_sys text) returns text language plpgsql immutable as $$
declare w text[]; i int; blame constant text := '\m(careless\w*|negligen\w*|forgot\w*|forget\w*|mistake|lazy|laziness|not serious|human error|operator error|did not follow|didn''t follow|not aware|lack of attention|inattent\w*|by mistake|not careful|ignored)\M';
begin
  select coalesce(array_agg(trim(x)) filter (where trim(x) <> ''), '{}') into w from jsonb_array_elements_text(case when jsonb_typeof(p_whys) = 'array' then p_whys else '[]'::jsonb end) x;
  if cardinality(w) < 3 then return 'Ask why at least three times. Now there ' || case when cardinality(w) = 1 then 'is 1 answer' else 'are ' || cardinality(w) || ' answers' end || '.'; end if;
  for i in 2..cardinality(w) loop
    if lower(regexp_replace(w[i], '[^a-zA-Z0-9]+', ' ', 'g')) = lower(regexp_replace(w[i - 1], '[^a-zA-Z0-9]+', ' ', 'g')) then return 'Why ' || i || ' repeats Why ' || (i - 1) || '. Each answer must go one level deeper.'; end if;
  end loop;
  if coalesce(trim(p_root), '') = '' then return 'Write the root cause in one sentence: the system gap that allowed the problem.'; end if;
  if p_root ~* blame or w[cardinality(w)] ~* blame then return 'The cause points to a person. A person is not a root cause. Ask one more why: why did the system allow it?'; end if;
  if coalesce(trim(p_escape), '') = '' then return 'Say why it was not detected earlier: which check should have caught it and why it did not.'; end if;
  if coalesce(trim(p_sys), '') = '' then return 'Say which system, document or process must change so it cannot happen again (for example the control plan, FMEA, work instruction or training system).'; end if;
  return null;
end $$;
create or replace function console.aud_nc_perm_problem(n console.aud_ncs) returns text language plpgsql immutable as $$
declare strong boolean;
begin
  if coalesce(trim(n.perm_action), '') = '' then return 'Describe the permanent action.'; end if;
  if coalesce(trim(n.contain_action), '') <> '' and lower(regexp_replace(n.perm_action, '[^a-zA-Z0-9]+', ' ', 'g')) = lower(regexp_replace(n.contain_action, '[^a-zA-Z0-9]+', ' ', 'g')) then return 'The permanent action is the same as the containment. Containment stops today''s problem; the permanent action must change the system.'; end if;
  if coalesce(trim(n.perm_owner), '') = '' then return 'Name the owner of the permanent action.'; end if;
  if n.perm_due is null then return 'Set the target date of the permanent action.'; end if;
  if jsonb_typeof(n.atype) <> 'array' or jsonb_array_length(n.atype) = 0 then return 'Choose what kind of action it is (remove the cause, mistake-proof, standardise, detect, train).'; end if;
  select exists (select 1 from jsonb_array_elements_text(n.atype) t where t not in ('train', 'remind', 'warn')) into strong;
  if n.severity = 'Major' and not strong then return 'For a Major finding, training or reminders alone are not accepted. Add a change of the system: remove the cause, mistake-proof, or standardise in the control plan or work instruction.'; end if;
  return null;
end $$;
create or replace function console.aud_nc_stage(n console.aud_ncs) returns text language sql immutable as $$
  select case when n.status in ('closed', 'cancelled') then n.status when n.contain_done_on is null then 'contain'
    when console.aud_nc_rca_problem(n.whys, n.root_cause, n.escape_cause, n.systemic) is not null then 'rca' when n.perm_done_on is null then 'action' else 'monitor' end $$;
create or replace function console.aud_nc_json(n console.aud_ncs, a console.aud_audits, td date) returns jsonb language sql stable security definer set search_path = console, public as $$
  select to_jsonb(n) - 'customer_id' || jsonb_build_object('audit_no', a.no, 'audit_title', a.title, 'audit_type', a.type, 'audit_done_on', a.done_on, 'audit_auditor', a.auditor,
    'next_due', case n.status when 'contain' then n.contain_due when 'rca' then n.resp_due when 'action' then coalesce(n.perm_due, n.resp_due) when 'monitor' then n.mon_due end,
    'overdue', n.status in ('contain', 'rca', 'action', 'monitor') and (case n.status when 'contain' then n.contain_due when 'rca' then n.resp_due when 'action' then coalesce(n.perm_due, n.resp_due) when 'monitor' then n.mon_due end) < td,
    'age', (case when n.closed_on is not null then n.closed_on else td end) - n.created_at::date) $$;

-- ---------- audit rows carry meta and finding counts; saving an audit keeps the new question fields and the new types ----------
do $patch$
declare def text; nw text;
begin
  def := pg_get_functiondef('console.aud_row_json(console.aud_audits, date)'::regprocedure); nw := def;
  if position('ncs_open' in def) = 0 then
    nw := replace(nw, $a$'sample', r.sample,$a$, $b$'meta', r.meta, 'ncs', (select count(*) from console.aud_ncs n where n.audit_id = r.id), 'ncs_open', (select count(*) from console.aud_ncs n where n.audit_id = r.id and n.status not in ('closed', 'cancelled')), 'sample', r.sample,$b$);
    if nw = def then raise exception 'aud_row_json was not updated'; end if; execute nw;
  end if;
  def := pg_get_functiondef('public.kmr_aud_audit_save(text, jsonb)'::regprocedure); nw := def;
  if position('LPA' in def) = 0 then
    nw := replace(nw, $a$ty not in ('System', 'Process', 'Product', 'Supplier')$a$, $b$ty not in ('System', 'Process', 'Product', 'Supplier', 'LPA', 'Document', 'Special', 'EHS', 'Lab')$b$);
    nw := replace(nw, $a$'rating', rt, 'note', console.aud_txt(item, 'note')$a$, $b$'rating', rt, 'note', console.aud_txt(item, 'note'), 'cl', console.aud_txt(item, 'cl'), 'std', console.aud_txt(item, 'std'), 'ev', console.aud_txt(item, 'ev'), 'cat', console.aud_txt(item, 'cat'),
        'w', case when item ->> 'w' ~ '^[0-2]$' then (item ->> 'w')::int end, 'ans', console.aud_txt(item, 'ans'), 'n', console.aud_num(item, 'n'), 'f', console.aud_num(item, 'f'), 'imp', console.aud_txt(item, 'imp'),
        'absent', case when item ->> 'absent' = 'true' then true end, 'rule', console.aud_txt(item, 'rule'), 'pt', console.aud_txt(item, 'pt')$b$);
    nw := replace(nw, $a$summary, created_by)$a$, $b$summary, created_by, meta)$b$);
    nw := replace(nw, $a$console.aud_txt(p, 'summary'), console.aud_me()) returning * into r;$a$, $b$console.aud_txt(p, 'summary'), console.aud_me(), case when jsonb_typeof(p -> 'meta') = 'object' then p -> 'meta' else '{}'::jsonb end) returning * into r;$b$);
    nw := replace(nw, $a$summary = console.aud_txt(p, 'summary'), updated_at = now() where id = r.id$a$, $b$summary = console.aud_txt(p, 'summary'), meta = case when jsonb_typeof(p -> 'meta') = 'object' then p -> 'meta' else meta end, updated_at = now() where id = r.id$b$);
    if position('''cl'', console.aud_txt' in nw) = 0 or position('summary, created_by, meta' in nw) = 0 or position('then p -> ''meta'' else ''{}''' in nw) = 0 or position('meta = case' in nw) = 0 or position('''LPA''' in nw) = 0 then raise exception 'kmr_aud_audit_save was not updated'; end if;
    execute nw;
  end if;
end $patch$;

-- ---------- issue and close: findings now need a corrective-action record ----------
create or replace function public.kmr_aud_issue(p_slug text, p_id uuid) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'aud'); r console.aud_audits; td date := console.aud_today(); n int; sc numeric; gr text; cfg jsonb;
begin
  perform console.require_feature(p_slug, 'aud', 'aud.audit-programme-and-reports');
  select * into r from console.aud_audits where id = p_id and customer_id = cid; if r.id is null then raise exception 'Audit not found.'; end if;
  if r.status <> 'planned' then raise exception 'This audit is already %.', r.status; end if;
  if r.done_on is null then raise exception 'Enter the date the audit was done.'; end if;
  if r.done_on > td then raise exception 'The audit date is in the future.'; end if;
  if coalesce(trim(r.auditor), '') = '' then raise exception 'Name the auditor.'; end if;
  if coalesce(trim(r.auditee), '') = '' then raise exception 'Name the person or area audited.'; end if;
  if lower(trim(r.auditor)) = lower(trim(r.auditee)) then raise exception 'The auditor must not audit their own work. Choose another auditor.'; end if;
  cfg := console.aud_cfg(cid);
  if jsonb_typeof(cfg -> 'auditors') = 'array' and jsonb_array_length(cfg -> 'auditors') > 0 and not exists (select 1 from jsonb_array_elements(cfg -> 'auditors') a
       where lower(trim(a ->> 'name')) = lower(trim(r.auditor)) and coalesce(a ->> 'status', 'qualified') <> 'trainee' and (jsonb_typeof(a -> 'types') <> 'array' or jsonb_array_length(a -> 'types') = 0 or a -> 'types' ? r.type)
       and (nullif(a ->> 'valid_till', '') is null or (a ->> 'valid_till')::date >= td)) then
    raise exception '% is not listed as a qualified auditor for % audits, or the qualification has expired (see the auditor register in Setup).', r.auditor, r.type;
  end if;
  if jsonb_array_length(r.checklist) = 0 then raise exception 'Add at least one question to the checklist.'; end if;
  select count(*) into n from jsonb_array_elements(r.checklist) x where coalesce(x ->> 'rating', '') = ''; if n > 0 then raise exception 'Rate every question: % are not rated yet.', n; end if;
  select count(*) into n from jsonb_array_elements(r.checklist) x where console.aud_is_finding(x ->> 'rating')
     and not exists (select 1 from console.aud_actions a where a.audit_id = r.id and a.q_id = x ->> 'id' and coalesce(trim(a.owner), '') <> '' and a.due_on is not null)
     and not exists (select 1 from console.aud_ncs c where c.audit_id = r.id and c.q_id = x ->> 'id' and c.status <> 'cancelled' and coalesce(trim(c.problem), '') <> '' and coalesce(trim(c.owner), '') <> '' and c.resp_due is not null and c.contain_due is not null);
  if n > 0 then raise exception '% finding(s) still need a problem description, an owner and due dates (open the finding and fill the containment and response dates).', n; end if;
  if r.type = 'Process' and console.aud_has(p_slug, 'aud.vda-6-3-scoring') then select s.score, s.grade into sc, gr from console.aud_score(r.checklist) s; end if;
  update console.aud_audits set status = 'reported', reported_on = td, score = sc, grade = gr, updated_at = now() where id = r.id returning * into r;
  perform console.aud_log(cid, r.id, 'Audit report issued' || case when gr is not null then ': score ' || sc || '%, grade ' || gr else '' end || '.', r.sample);
  return console.aud_row_json(r, td);
end $$;
create or replace function public.kmr_aud_close(p_slug text, p_id uuid) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'aud'); r console.aud_audits; td date := console.aud_today(); n int;
begin
  perform console.require_feature(p_slug, 'aud', 'aud.audit-programme-and-reports');
  select * into r from console.aud_audits where id = p_id and customer_id = cid; if r.id is null then raise exception 'Audit not found.'; end if;
  if r.status <> 'reported' then raise exception 'Issue the report first.'; end if;
  select count(*) into n from console.aud_actions where audit_id = r.id and status = 'open'; if n > 0 then raise exception '% action(s) are still open.', n; end if;
  select count(*) into n from console.aud_actions a where a.audit_id = r.id and not a.verified; if n > 0 then raise exception '% action(s) are not yet checked for effectiveness.', n; end if;
  select count(*) into n from console.aud_ncs c where c.audit_id = r.id and c.status not in ('closed', 'cancelled'); if n > 0 then raise exception '% finding(s) are not closed yet: finish the corrective action and the effectiveness check.', n; end if;
  update console.aud_audits set status = 'closed', closed_on = td, updated_at = now() where id = r.id returning * into r;
  perform console.aud_log(cid, r.id, 'Audit closed: all findings fixed and checked.', r.sample);
  return console.aud_row_json(r, td);
end $$;

-- ================= findings =================
create or replace function public.kmr_aud_nc_save(p_slug text, p jsonb) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'aud'); me text := console.aud_me(); v_id uuid := nullif(p ->> 'id', '')::uuid; n console.aud_ncs; o console.aud_ncs; au console.aud_audits; td date := console.aud_today();
  msg text; isnew boolean := v_id is null; sv text; st text; w jsonb; t text; i int;
begin
  perform console.require_feature(p_slug, 'aud', 'aud.audit-programme-and-reports');
  if isnew then
    select * into au from console.aud_audits where id = nullif(p ->> 'audit_id', '')::uuid and customer_id = cid; if au.id is null then raise exception 'Audit not found.'; end if;
    if au.status not in ('planned', 'reported') then raise exception 'This audit is %. An administrator can reopen it.', au.status; end if;
    n.id := gen_random_uuid(); n.customer_id := cid; n.audit_id := au.id; n.q_id := console.aud_txt(p, 'q_id'); n.no := console.aud_nc_number(cid, 'NC'); n.created_by := me; n.sample := false; n.loops := 0;
    n.whys := '[]'; n.atype := '[]'; n.status := 'contain'; n.severity := console.aud_txt(p, 'severity');
    if n.severity is null or n.severity not in ('Major', 'Minor') then raise exception 'The finding must be Major or Minor.'; end if;
    n.rule_text := console.aud_txt(p, 'rule_text'); n.repeat_of := console.aud_txt(p, 'repeat_of'); n.created_at := now();
    if n.q_id is not null and exists (select 1 from console.aud_ncs c where c.audit_id = au.id and c.q_id = n.q_id and c.status <> 'cancelled') then raise exception 'This question already has a finding.'; end if;
  else
    select * into n from console.aud_ncs where id = v_id and customer_id = cid; if n.id is null then raise exception 'Finding not found.'; end if;
    if n.status in ('closed', 'cancelled') then raise exception 'This finding is %. An administrator can reopen it.', n.status; end if;
    select * into au from console.aud_audits where id = n.audit_id; o := n;
    if au.status not in ('planned', 'reported') then raise exception 'This audit is %. An administrator can reopen it.', au.status; end if;
    if p ? 'severity' and console.aud_txt(p, 'severity') is distinct from n.severity then
      sv := console.aud_txt(p, 'severity'); if sv not in ('Major', 'Minor') then raise exception 'The finding must be Major or Minor.'; end if;
      if console.aud_txt(p, 'sev_reason') is null then raise exception 'Give the reason for changing the severity from % to %.', n.severity, sv; end if;
      perform console.aud_log(cid, au.id, n.no || ': severity changed from ' || n.severity || ' to ' || sv || '. Reason: ' || console.aud_txt(p, 'sev_reason'), n.sample);
      n.severity := sv;
    end if;
  end if;
  if p ? 'clause' then n.clause := console.aud_txt(p, 'clause'); end if;
  if p ? 'standard' then n.standard := console.aud_txt(p, 'standard'); end if;
  if p ? 'requirement' then n.requirement := console.aud_txt(p, 'requirement'); end if;
  if p ? 'cat' then n.cat := console.aud_txt(p, 'cat'); end if;
  if p ? 'problem' then n.problem := console.aud_txt(p, 'problem'); end if;
  if p ? 'evidence' then n.evidence := console.aud_txt(p, 'evidence'); end if;
  if p ? 'area' then n.area := console.aud_txt(p, 'area'); end if;
  if p ? 'owner' then n.owner := console.aud_txt(p, 'owner'); end if;
  if p ? 'resp_due' then n.resp_due := console.aud_date(p, 'resp_due'); end if;
  if p ? 'contain_action' then n.contain_action := console.aud_txt(p, 'contain_action'); end if;
  if p ? 'contain_owner' then n.contain_owner := console.aud_txt(p, 'contain_owner'); end if;
  if p ? 'contain_due' then n.contain_due := console.aud_date(p, 'contain_due'); end if;
  if p ? 'contain_qty' then n.contain_qty := console.aud_txt(p, 'contain_qty'); end if;
  if p ? 'contain_done_on' then n.contain_done_on := console.aud_date(p, 'contain_done_on'); end if;
  if p ? 'whys' then
    w := p -> 'whys'; if jsonb_typeof(w) <> 'array' or jsonb_array_length(w) > 7 then raise exception 'Up to seven whys can be written.'; end if;
    n.whys := coalesce((select jsonb_agg(left(trim(x), 500)) from jsonb_array_elements_text(w) x where trim(x) <> ''), '[]');
  end if;
  if p ? 'root_cause' then n.root_cause := console.aud_txt(p, 'root_cause'); end if;
  if p ? 'escape_cause' then n.escape_cause := console.aud_txt(p, 'escape_cause'); end if;
  if p ? 'systemic' then n.systemic := console.aud_txt(p, 'systemic'); end if;
  if p ? 'atype' then
    if jsonb_typeof(p -> 'atype') <> 'array' then raise exception 'The kind of action is not valid.'; end if;
    for t in select jsonb_array_elements_text(p -> 'atype') loop if t not in ('remove', 'proof', 'standard', 'detect', 'train', 'remind', 'warn') then raise exception 'The kind of action is not valid.'; end if; end loop;
    n.atype := p -> 'atype';
  end if;
  if p ? 'perm_action' then n.perm_action := console.aud_txt(p, 'perm_action'); end if;
  if p ? 'perm_owner' then n.perm_owner := console.aud_txt(p, 'perm_owner'); end if;
  if p ? 'perm_due' then n.perm_due := console.aud_date(p, 'perm_due'); end if;
  if p ? 'perm_evidence' then n.perm_evidence := console.aud_txt(p, 'perm_evidence'); end if;
  if p ? 'horizontal' then n.horizontal := console.aud_txt(p, 'horizontal'); end if;
  if p ? 'perm_done_on' then n.perm_done_on := console.aud_date(p, 'perm_done_on'); end if;
  if p ? 'mon_method' then n.mon_method := console.aud_txt(p, 'mon_method'); end if;
  if p ? 'mon_criteria' then n.mon_criteria := console.aud_txt(p, 'mon_criteria'); end if;
  if p ? 'mon_days' then n.mon_days := console.aud_num(p, 'mon_days')::int; if n.mon_days is not null and (n.mon_days < 1 or n.mon_days > 365) then raise exception 'The monitoring period must be between 1 and 365 days.'; end if; end if;
  -- rules, in plain words
  if coalesce(trim(n.problem), '') = '' then raise exception 'Describe the problem: what was found, where and when.'; end if;
  if coalesce(trim(n.owner), '') = '' then raise exception 'Name the person who owns the response to this finding.'; end if;
  if n.resp_due is null then raise exception 'Set the date by which the root cause and the permanent action are due.'; end if;
  if n.contain_due is null then raise exception 'Set the date by which the containment must be done.'; end if;
  if n.contain_done_on is not null then
    if n.contain_done_on > td then raise exception 'The containment date is in the future.'; end if;
    if coalesce(trim(n.contain_action), '') = '' or coalesce(trim(n.contain_owner), '') = '' then raise exception 'Describe the containment and name who did it before marking it done.'; end if;
  end if;
  if n.perm_done_on is not null then
    if n.contain_done_on is null then raise exception 'Finish the containment first.'; end if;
    if n.perm_done_on > td then raise exception 'The date the permanent action was done is in the future.'; end if;
    msg := console.aud_nc_rca_problem(n.whys, n.root_cause, n.escape_cause, n.systemic); if msg is not null then raise exception 'The root cause is not complete. %', msg; end if;
    msg := console.aud_nc_perm_problem(n); if msg is not null then raise exception '%', msg; end if;
    if coalesce(trim(n.perm_evidence), '') = '' then raise exception 'Add the evidence that the permanent action was done (record, photo, revised document number).'; end if;
    if coalesce(trim(n.mon_method), '') = '' or coalesce(trim(n.mon_criteria), '') = '' then raise exception 'Say how the effect will be checked and what result shows that it worked.'; end if;
    if n.mon_days is null then n.mon_days := case when n.severity = 'Major' then 60 else 90 end; end if;
    n.mon_due := n.perm_done_on + n.mon_days;
  else n.mon_due := null; end if;
  st := console.aud_nc_stage(n); n.status := st; n.updated_at := now();
  if isnew then
    insert into console.aud_ncs select n.*;
    perform console.aud_log(cid, au.id, n.no || ' raised: ' || n.severity || case when n.clause is not null then ', clause ' || n.clause else '' end || '.', n.sample);
  else
    update console.aud_ncs set clause = n.clause, standard = n.standard, requirement = n.requirement, cat = n.cat, severity = n.severity, problem = n.problem, evidence = n.evidence, area = n.area, status = n.status,
      owner = n.owner, resp_due = n.resp_due, contain_action = n.contain_action, contain_owner = n.contain_owner, contain_due = n.contain_due, contain_done_on = n.contain_done_on, contain_qty = n.contain_qty,
      whys = n.whys, root_cause = n.root_cause, escape_cause = n.escape_cause, systemic = n.systemic, atype = n.atype, perm_action = n.perm_action, perm_owner = n.perm_owner, perm_due = n.perm_due,
      perm_done_on = n.perm_done_on, perm_evidence = n.perm_evidence, horizontal = n.horizontal, mon_method = n.mon_method, mon_criteria = n.mon_criteria, mon_days = n.mon_days, mon_due = n.mon_due, updated_at = now()
     where id = n.id;
    if o.status is distinct from n.status then perform console.aud_log(cid, au.id, n.no || ': now at step ' || n.status || '.', n.sample); end if;
  end if;
  select * into n from console.aud_ncs where id = n.id;
  return console.aud_nc_json(n, au, td);
end $$;

create or replace function public.kmr_aud_nc_get(p_slug text, p_id uuid) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'aud'); n console.aud_ncs; au console.aud_audits; td date := console.aud_today();
begin
  perform console.require_feature(p_slug, 'aud', 'aud.audit-programme-and-reports');
  select * into n from console.aud_ncs where id = p_id and customer_id = cid; if n.id is null then raise exception 'Finding not found.'; end if;
  select * into au from console.aud_audits where id = n.audit_id;
  return console.aud_nc_json(n, au, td) || jsonb_build_object('can_edit', console.qp_role(cid, 'aud') in ('admin', 'editor') and n.status not in ('closed', 'cancelled') and au.status in ('planned', 'reported'), 'is_admin', console.qp_role(cid, 'aud') = 'admin',
    'log', coalesce((select jsonb_agg(jsonb_build_object('at', l.at, 'by', l.by, 'text', l.text) order by l.at desc) from (select * from console.aud_log where audit_id = au.id and text like n.no || '%' order by at desc limit 60) l), '[]'));
end $$;

create or replace function public.kmr_aud_nc_list(p_slug text, p jsonb default '{}') returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'aud'); td date := console.aud_today(); st text := coalesce(console.aud_txt(p, 'status'), 'open'); sv text := console.aud_txt(p, 'severity'); q text := console.aud_txt(p, 'q');
  aid uuid := nullif(p ->> 'audit_id', '')::uuid; ow text := console.aud_txt(p, 'owner'); cl text := console.aud_txt(p, 'clause');
begin
  perform console.require_feature(p_slug, 'aud', 'aud.audit-programme-and-reports');
  return coalesce((select jsonb_agg(console.aud_nc_json(c, a, td) order by c.created_at desc)
    from console.aud_ncs c join console.aud_audits a on a.id = c.audit_id
     where c.customer_id = cid and a.status <> 'cancelled' and c.status <> 'cancelled' and (aid is null or c.audit_id = aid)
       and (st = 'all' or c.status = st or (st = 'open' and c.status in ('contain', 'rca', 'action', 'monitor')))
       and (sv is null or c.severity = sv) and (ow is null or lower(coalesce(c.owner, '')) = lower(ow) or lower(coalesce(c.perm_owner, '')) = lower(ow) or lower(coalesce(c.contain_owner, '')) = lower(ow))
       and (cl is null or c.clause = cl)
       and (coalesce(p ->> 'overdue', '') <> 'true' or (c.status in ('contain', 'rca', 'action', 'monitor') and (case c.status when 'contain' then c.contain_due when 'rca' then c.resp_due when 'action' then coalesce(c.perm_due, c.resp_due) when 'monitor' then c.mon_due end) < td))
       and (q is null or c.no ilike '%' || q || '%' or coalesce(c.problem, '') ilike '%' || q || '%' or coalesce(c.clause, '') ilike '%' || q || '%' or coalesce(c.area, '') ilike '%' || q || '%')), '[]');
end $$;

-- earlier findings, used to spot a repeat: the same clause in the same area in the last 12 months
create or replace function public.kmr_aud_nc_history(p_slug text, p jsonb default '{}') returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'aud'); td date := console.aud_today();
begin
  return coalesce((select jsonb_agg(jsonb_build_object('no', c.no, 'audit_id', c.audit_id, 'clause', c.clause, 'area', c.area, 'severity', c.severity, 'status', c.status, 'raised_on', c.created_at::date) order by c.created_at desc)
    from console.aud_ncs c where c.customer_id = cid and c.status <> 'cancelled' and c.created_at::date >= td - 365), '[]');
end $$;

create or replace function public.kmr_aud_nc_close(p_slug text, p_id uuid, p_result text, p_note text default null, p_early boolean default false) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'aud'); me text := console.aud_me(); n console.aud_ncs; au console.aud_audits; td date := console.aud_today(); admin boolean := console.qp_role(cid, 'aud') = 'admin';
begin
  perform console.require_feature(p_slug, 'aud', 'aud.audit-programme-and-reports');
  select * into n from console.aud_ncs where id = p_id and customer_id = cid; if n.id is null then raise exception 'Finding not found.'; end if;
  select * into au from console.aud_audits where id = n.audit_id;
  if n.status <> 'monitor' then raise exception 'The effect can be checked only after the permanent action is done and recorded.'; end if;
  if p_result not in ('effective', 'not_effective') then raise exception 'Choose effective or not effective.'; end if;
  if console.aud_txt(jsonb_build_object('t', p_note), 't') is null then raise exception 'Write what was checked and what was found (records, re-audit result, data).'; end if;
  if n.mon_due > td then
    if not (admin and p_early) then raise exception 'The effect can be checked on or after %. The monitoring period is not over yet.', to_char(n.mon_due, 'DD Mon YYYY'); end if;
  end if;
  if p_result = 'effective' then
    update console.aud_ncs set status = 'closed', mon_result = 'effective', mon_note = trim(p_note), mon_on = td, closed_on = td, closed_by = me, updated_at = now() where id = n.id returning * into n;
    perform console.aud_log(cid, au.id, n.no || ': closed. The action was effective. ' || trim(p_note), n.sample);
  else
    update console.aud_ncs set status = 'rca', severity = 'Major', loops = loops + 1, mon_result = null, mon_note = null, mon_on = null, mon_due = null, perm_done_on = null, perm_evidence = null, perm_action = null, perm_due = null, atype = '[]',
      rule_text = coalesce(rule_text || E'\n', '') || 'Raised to Major on ' || to_char(td, 'DD Mon YYYY') || ': the permanent action was not effective. Earlier root cause: ' || coalesce(root_cause, '-') || '. Earlier action: ' || coalesce(perm_action, '-') || '. Result of the check: ' || trim(p_note),
      whys = '[]', root_cause = null, escape_cause = null, systemic = null, updated_at = now() where id = n.id returning * into n;
    perform console.aud_log(cid, au.id, n.no || ': the action was NOT effective, so the finding is Major again and goes back to root cause. ' || trim(p_note), n.sample);
  end if;
  return console.aud_nc_json(n, au, td);
end $$;

create or replace function public.kmr_aud_nc_reopen(p_slug text, p_id uuid, p_reason text default null) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'aud'); n console.aud_ncs; au console.aud_audits; td date := console.aud_today();
begin
  if console.qp_role(cid, 'aud') <> 'admin' then raise exception 'Only an administrator can reopen a finding.'; end if;
  select * into n from console.aud_ncs where id = p_id and customer_id = cid; if n.id is null then raise exception 'Finding not found.'; end if;
  if n.status not in ('closed', 'cancelled') then raise exception 'This finding is still open.'; end if;
  if coalesce(trim(p_reason), '') = '' then raise exception 'Give the reason for reopening.'; end if;
  update console.aud_ncs set status = 'monitor', mon_result = null, mon_on = null, closed_on = null, closed_by = null, cancel_reason = null, updated_at = now() where id = n.id returning * into n;
  update console.aud_ncs set status = console.aud_nc_stage(n) where id = n.id returning * into n;
  select * into au from console.aud_audits where id = n.audit_id;
  if au.status = 'closed' then update console.aud_audits set status = 'reported', closed_on = null, updated_at = now() where id = au.id returning * into au; end if;
  perform console.aud_log(cid, au.id, n.no || ': reopened by administrator. ' || trim(p_reason), n.sample);
  return console.aud_nc_json(n, au, td);
end $$;

create or replace function public.kmr_aud_nc_cancel(p_slug text, p_id uuid, p_reason text) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'aud'); n console.aud_ncs; au console.aud_audits; td date := console.aud_today();
begin
  if console.qp_role(cid, 'aud') <> 'admin' then raise exception 'Only an administrator can cancel a finding.'; end if;
  select * into n from console.aud_ncs where id = p_id and customer_id = cid; if n.id is null then raise exception 'Finding not found.'; end if;
  if n.status in ('closed', 'cancelled') then raise exception 'This finding is already %.', n.status; end if;
  if coalesce(trim(p_reason), '') = '' then raise exception 'Give the reason: for example the finding was raised by mistake or the auditee showed the requirement is met.'; end if;
  update console.aud_ncs set status = 'cancelled', cancel_reason = trim(p_reason), updated_at = now() where id = n.id returning * into n;
  select * into au from console.aud_audits where id = n.audit_id;
  perform console.aud_log(cid, au.id, n.no || ': cancelled by administrator. ' || trim(p_reason), n.sample);
  return console.aud_nc_json(n, au, td);
end $$;

-- ================= special audit points =================
create or replace function console.aud_point_json(x console.aud_points, td date) returns jsonb language sql stable as $$
  select to_jsonb(x) - 'customer_id' || jsonb_build_object('overdue', x.status = 'open' and x.due_on is not null and x.due_on < td) $$;
create or replace function public.kmr_aud_point_list(p_slug text, p jsonb default '{}') returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'aud'); td date := console.aud_today(); st text := coalesce(console.aud_txt(p, 'status'), 'open'); q text := console.aud_txt(p, 'q');
begin
  perform console.require_feature(p_slug, 'aud', 'aud.audit-programme-and-reports');
  return coalesce((select jsonb_agg(console.aud_point_json(x, td) order by x.status, x.due_on nulls last, x.no) from (
    select * from console.aud_points x where x.customer_id = cid and (st = 'all' or x.status = st)
      and (q is null or x.no ilike '%' || q || '%' or x.title ilike '%' || q || '%' or x.clause ilike '%' || q || '%' or x.standard ilike '%' || q || '%') order by x.status, x.due_on nulls last limit 1000) x), '[]');
end $$;
create or replace function public.kmr_aud_point_save(p_slug text, p jsonb) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'aud'); me text := console.aud_me(); v_id uuid := nullif(p ->> 'id', '')::uuid; x console.aud_points; td date := console.aud_today(); fq text := coalesce(console.aud_txt(p, 'frequency'), 'Every audit');
begin
  perform console.require_feature(p_slug, 'aud', 'aud.audit-programme-and-reports');
  if console.aud_txt(p, 'title') is null then raise exception 'Write the point to be checked.'; end if;
  if console.aud_txt(p, 'standard') is null then raise exception 'Name the standard or requirement this point comes from (for example IATF 16949 or the customer''s name).'; end if;
  if console.aud_txt(p, 'clause') is null then raise exception 'Give the clause or requirement number of the point.'; end if;
  if fq not in ('Every audit', 'Monthly', 'Quarterly', 'Half-yearly', 'Yearly', 'One time') then raise exception 'Choose how often the point is checked.'; end if;
  if v_id is null then
    insert into console.aud_points (customer_id, no, title, source, standard, clause, description, check_how, frequency, applies, owner, due_on, created_by)
    values (cid, console.aud_nc_number(cid, 'SP'), console.aud_txt(p, 'title'), console.aud_txt(p, 'source'), console.aud_txt(p, 'standard'), console.aud_txt(p, 'clause'), console.aud_txt(p, 'description'), console.aud_txt(p, 'check_how'), fq,
            console.aud_txt(p, 'applies'), console.aud_txt(p, 'owner'), console.aud_date(p, 'due_on'), me) returning * into x;
  else
    select * into x from console.aud_points where id = v_id and customer_id = cid; if x.id is null then raise exception 'Point not found.'; end if;
    if x.status = 'closed' then raise exception 'This point is closed. An administrator can reopen it.'; end if;
    update console.aud_points set title = console.aud_txt(p, 'title'), source = console.aud_txt(p, 'source'), standard = console.aud_txt(p, 'standard'), clause = console.aud_txt(p, 'clause'), description = console.aud_txt(p, 'description'),
      check_how = console.aud_txt(p, 'check_how'), frequency = fq, applies = console.aud_txt(p, 'applies'), owner = console.aud_txt(p, 'owner'), due_on = console.aud_date(p, 'due_on'), updated_at = now() where id = x.id returning * into x;
  end if;
  return console.aud_point_json(x, td);
end $$;
create or replace function public.kmr_aud_point_check(p_slug text, p_id uuid, p jsonb) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'aud'); me text := console.aud_me(); x console.aud_points; td date := console.aud_today(); res text := console.aud_txt(p, 'result');
begin
  select * into x from console.aud_points where id = p_id and customer_id = cid; if x.id is null then raise exception 'Point not found.'; end if;
  if x.status = 'closed' then raise exception 'This point is closed.'; end if;
  if res not in ('ok', 'not_ok') then raise exception 'Choose OK or not OK.'; end if;
  if res = 'not_ok' and console.aud_txt(p, 'note') is null then raise exception 'Write what was found when the point is not OK.'; end if;
  update console.aud_points set checks = (jsonb_build_array(jsonb_build_object('on', td, 'by', me, 'result', res, 'note', console.aud_txt(p, 'note'), 'audit', console.aud_txt(p, 'audit'))) || checks), last_checked = td, last_result = res, updated_at = now()
   where id = x.id returning * into x;
  update console.aud_points set checks = (select coalesce(jsonb_agg(c), '[]') from (select c from jsonb_array_elements(checks) c limit 50) z) where id = x.id returning * into x;
  return console.aud_point_json(x, td);
end $$;
create or replace function public.kmr_aud_point_close(p_slug text, p_id uuid, p jsonb) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'aud'); x console.aud_points; td date := console.aud_today();
begin
  select * into x from console.aud_points where id = p_id and customer_id = cid; if x.id is null then raise exception 'Point not found.'; end if;
  if x.status = 'closed' then raise exception 'This point is already closed.'; end if;
  if x.last_result is distinct from 'ok' then raise exception 'Check the point and record the result OK before closing it.'; end if;
  if console.aud_txt(p, 'closure_note') is null then raise exception 'Write why the point can be closed (what was done and what was seen).'; end if;
  if console.aud_txt(p, 'evidence') is null then raise exception 'Add the evidence for closure: record number, document, photo or customer confirmation.'; end if;
  update console.aud_points set status = 'closed', closed_on = td, closure_note = console.aud_txt(p, 'closure_note'), evidence = console.aud_txt(p, 'evidence'), updated_at = now() where id = x.id returning * into x;
  return console.aud_point_json(x, td);
end $$;
create or replace function public.kmr_aud_point_reopen(p_slug text, p_id uuid) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'aud'); x console.aud_points; td date := console.aud_today();
begin
  if console.qp_role(cid, 'aud') <> 'admin' then raise exception 'Only an administrator can reopen a point.'; end if;
  update console.aud_points set status = 'open', closed_on = null, updated_at = now() where id = p_id and customer_id = cid returning * into x; if x.id is null then raise exception 'Point not found.'; end if;
  return console.aud_point_json(x, td);
end $$;
create or replace function public.kmr_aud_point_delete(p_slug text, p_id uuid) returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'aud');
begin
  if console.qp_role(cid, 'aud') <> 'admin' then raise exception 'Only an administrator can delete a point.'; end if;
  delete from console.aud_points where id = p_id and customer_id = cid;
end $$;

-- ================= programme: the audits of the year, made in one step =================
create or replace function public.kmr_aud_programme_make(p_slug text, p jsonb) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'aud'); it jsonb; n int := 0; r jsonb;
begin
  perform console.require_feature(p_slug, 'aud', 'aud.audit-programme-and-reports');
  if jsonb_typeof(p -> 'items') <> 'array' then raise exception 'The programme is not valid.'; end if;
  if jsonb_array_length(p -> 'items') > 400 then raise exception 'At most 400 audits can be made at once.'; end if;
  for it in select * from jsonb_array_elements(p -> 'items') loop
    r := public.kmr_aud_audit_save(p_slug, jsonb_build_object('title', it ->> 'title', 'type', it ->> 'type', 'area', it ->> 'area', 'scope', it ->> 'scope', 'planned_on', it ->> 'planned_on', 'auditor', it ->> 'auditor', 'auditee', it ->> 'auditee',
      'shifts', coalesce(it -> 'shifts', '[]'), 'checklist', coalesce(it -> 'checklist', '[]'), 'meta', coalesce(it -> 'meta', '{}')));
    n := n + 1;
  end loop;
  return jsonb_build_object('made', n);
end $$;

-- ================= dashboard of findings =================
create or replace function public.kmr_aud_dash2(p_slug text, p_year int default null) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'aud'); td date := console.aud_today(); res jsonb;
begin
  perform console.require_feature(p_slug, 'aud', 'aud.audit-programme-and-reports');
  with c as (select n.*, a.type atype_, (case n.status when 'contain' then n.contain_due when 'rca' then n.resp_due when 'action' then coalesce(n.perm_due, n.resp_due) when 'monitor' then n.mon_due end) nd
               from console.aud_ncs n join console.aud_audits a on a.id = n.audit_id where n.customer_id = cid and n.status <> 'cancelled' and a.status <> 'cancelled')
  select jsonb_build_object(
    'raised', (select count(*) from c), 'open', (select count(*) from c where status <> 'closed'), 'closed', (select count(*) from c where status = 'closed'),
    'major_open', (select count(*) from c where status <> 'closed' and severity = 'Major'), 'minor_open', (select count(*) from c where status <> 'closed' and severity = 'Minor'),
    'overdue', (select count(*) from c where status <> 'closed' and nd < td),
    'repeat', (select count(*) from c where repeat_of is not null or loops > 0),
    'by_stage', coalesce((select jsonb_object_agg(status, k) from (select status, count(*) k from c where status <> 'closed' group by status) z), '{}'),
    'avg_days_to_close', (select round(avg(closed_on - created_at::date), 0) from c where status = 'closed' and closed_on is not null),
    'on_time_pct', (select case when count(*) = 0 then null else round(100.0 * count(*) filter (where perm_done_on <= coalesce(perm_due, resp_due)) / count(*)) end from c where perm_done_on is not null),
    'effective_pct', (select case when count(*) = 0 then null else round(100.0 * count(*) filter (where mon_result = 'effective') / count(*)) end from c where mon_result is not null)
        ,
    'effectiveness_checks', (select count(*) from c where mon_result is not null),
    'ageing', jsonb_build_object('d30', (select count(*) from c where status <> 'closed' and td - created_at::date <= 30), 'd60', (select count(*) from c where status <> 'closed' and td - created_at::date between 31 and 60),
        'd90', (select count(*) from c where status <> 'closed' and td - created_at::date between 61 and 90), 'over90', (select count(*) from c where status <> 'closed' and td - created_at::date > 90)),
    'by_standard', coalesce((select jsonb_agg(jsonb_build_object('k', s, 'n', k) order by k desc) from (select coalesce(standard, 'Other') s, count(*) k from c where created_at::date >= td - 365 group by 1 order by 2 desc limit 8) z), '[]'),
    'top_clauses', coalesce((select jsonb_agg(jsonb_build_object('k', s, 'n', k) order by k desc) from (select coalesce(standard || ' ' || clause, 'Other') s, count(*) k from c where created_at::date >= td - 365 group by 1 order by 2 desc limit 8) z), '[]'),
    'by_area', coalesce((select jsonb_agg(jsonb_build_object('k', s, 'n', k) order by k desc) from (select coalesce(nullif(area, ''), 'Not stated') s, count(*) k from c where created_at::date >= td - 365 group by 1 order by 2 desc limit 8) z), '[]'),
    'by_type', coalesce((select jsonb_agg(jsonb_build_object('k', s, 'n', k) order by k desc) from (select atype_ s, count(*) k from c where created_at::date >= td - 365 group by 1) z), '[]'),
    'trend', coalesce((select jsonb_agg(jsonb_build_object('m', to_char(m, 'YYYY-MM'), 'raised', (select count(*) from c where date_trunc('month', created_at)::date = m), 'closed', (select count(*) from c where date_trunc('month', closed_on)::date = m)) order by m)
        from generate_series(date_trunc('month', td)::date - interval '11 months', date_trunc('month', td)::date, interval '1 month') m2(m)), '[]'),
    'oldest', coalesce((select jsonb_agg(x) from (select id, no, severity, status, clause, standard, problem, owner, created_at::date raised_on, nd next_due from c where status <> 'closed' order by created_at limit 8) x), '[]'),
    'late', coalesce((select jsonb_agg(x) from (select id, no, severity, status, clause, problem, owner, nd next_due from c where status <> 'closed' and nd < td order by nd limit 8) x), '[]'),
    'points_open', (select count(*) from console.aud_points where customer_id = cid and status = 'open'),
    'points_overdue', (select count(*) from console.aud_points where customer_id = cid and status = 'open' and due_on is not null and due_on < td),
    'points_notok', (select count(*) from console.aud_points where customer_id = cid and status = 'open' and last_result = 'not_ok'),
    'audited_areas', (select count(distinct lower(area)) from console.aud_audits where customer_id = cid and status in ('reported', 'closed') and done_on >= td - 365 and area is not null),
    'audited_types', coalesce((select jsonb_agg(distinct type) from console.aud_audits where customer_id = cid and status in ('reported', 'closed') and done_on >= td - 365), '[]')
  ) into res;
  return res;
end $$;

-- ================= sample data and housekeeping =================
do $$ begin
  if to_regprocedure('console.aud_sample1(uuid, text)') is null then alter function console.aud_sample(uuid, text) rename to aud_sample1; end if;
end $$;
create or replace function console.aud_sample(p_cid uuid, p_action text) returns integer language plpgsql security definer set search_path = console, public as $$
declare n int := 0; k int; a2 uuid; a1 uuid; td date := console.aud_today(); c1 uuid;
begin
  if p_action = 'flush' then
    delete from console.aud_points where customer_id = p_cid and sample; get diagnostics k = row_count; n := n + k;
    return n + console.aud_sample1(p_cid, p_action);
  end if;
  n := console.aud_sample1(p_cid, p_action);
  if n > 0 and not exists (select 1 from console.aud_ncs where customer_id = p_cid and sample) then
    select id into a1 from console.aud_audits where customer_id = p_cid and sample and title like 'Document control%' limit 1;
    select id into a2 from console.aud_audits where customer_id = p_cid and sample and title like 'Process audit, Boring%' limit 1;
    if a1 is not null then
      insert into console.aud_ncs (customer_id, audit_id, q_id, no, clause, standard, requirement, cat, severity, rule_text, problem, evidence, area, status, owner, resp_due, contain_action, contain_owner, contain_due, contain_done_on,
        whys, root_cause, escape_cause, systemic, atype, perm_action, perm_owner, perm_due, perm_done_on, perm_evidence, horizontal, mon_method, mon_criteria, mon_days, mon_due, mon_result, mon_note, mon_on, closed_on, closed_by, sample, created_by, created_at)
      values (p_cid, a1, 's2', console.aud_nc_number(p_cid, 'NC'), '7.5.3', 'ISO 9001:2015', 'Current versions of procedures are available where the work is done.', 'doc', 'Minor', 'Classified Minor: partly met, isolated, no customer effect.',
        'Two old copies of the inspection procedure were on the notice board in Final Inspection.', 'Photo of the notice board', 'Final Inspection', 'closed', 'S. Priya', td - 55,
        'Old copies removed the same day; all procedures on the board checked against the master list.', 'S. Priya', td - 68, td - 69,
        '["The old copy stayed on the board","Nobody removes a copy when a new revision is issued","The release of a revision has no step to withdraw the old copy","There is no owner for the notice board"]', 'The release of a new revision does not include withdrawing the old copy at the point of use.',
        'The weekly 5S check does not include the document list.', 'Document release procedure and 5S check list', '["standard","detect"]', 'Add a withdrawal step to the document release and add the document list to the weekly 5S check.', 'S. Priya', td - 64, td - 66,
        'Revised document release procedure rev 03; 5S sheet rev 02', 'All other notice boards and the dispatch area', 'reaudit', 'No old copy found in the next audit and two layered checks', 7, td - 59, 'effective', 'Re-audit on ' || to_char(td - 58, 'DD Mon') || ': no old copies found.', td - 58, td - 58, 'sample', true, 'sample', now() - interval '70 days');
    end if;
    if a2 is not null then
      insert into console.aud_ncs (customer_id, audit_id, q_id, no, clause, standard, requirement, cat, severity, rule_text, problem, evidence, area, status, owner, resp_due, contain_action, contain_owner, contain_due, contain_done_on,
        whys, root_cause, escape_cause, systemic, atype, perm_action, perm_owner, perm_due, horizontal, sample, created_by, created_at)
      values (p_cid, a2, 'p4', console.aud_nc_number(p_cid, 'NC'), 'P6 Work content', 'VDA 6.3:2016', 'Nonconforming product is identified, separated and recorded at the process step.', 'ncp', 'Major',
        'Rated 4 on a question that matters for the product. A critical requirement (suspect product) was not met.', 'The red bin at the boring machine was not emptied and two rejected parts were mixed with good parts.', 'Photo of the bin; 2 rejects found in the good-parts container', 'Machining T04', 'action', 'K. Arun', td - 6,
        'Whole lot sorted 100%; two more rejects found and scrapped; bin emptied and tagged.', 'K. Arun', td - 19, td - 20,
        '["Rejects were put into the good-parts container","The red bin was full and there was no other place to put rejects","Nobody empties the red bin at a set time","The bin is not part of the shift start check"]', 'The red bin has no defined emptying time and is not part of the shift start check, so a full bin leads to mixing.',
        'The layered process audit does not look at the bin.', 'Control plan, work instruction and layered process audit sheet', '["proof","standard"]', 'Fit a locked reject container with a counter and add it to the shift start check and the layered process audit.', 'K. Arun', td - 2, 'All other machines of the same line and the other two shifts', true, 'sample', now() - interval '19 days');
    end if;
    insert into console.aud_points (customer_id, no, title, source, standard, clause, description, check_how, frequency, applies, owner, due_on, status, checks, last_checked, last_result, sample, created_by)
    values (p_cid, console.aud_nc_number(p_cid, 'SP'), 'Customer audit: confirm the mistake-proofing of the bore diameter is tested at every shift start', 'Customer', 'IATF 16949:2016', '10.2.4', 'Raised in the customer''s last process audit.', 'Check the test record and run the master piece', 'Every audit', 'Machining', 'K. Arun', td + 20, 'open',
        jsonb_build_array(jsonb_build_object('on', td - 10, 'by', 'sample', 'result', 'not_ok', 'note', 'The test record for shift C was missing.')), td - 10, 'not_ok', true, 'sample'),
      (p_cid, console.aud_nc_number(p_cid, 'SP'), 'Certification body: show that the three-year audit plan covers all shifts', 'Certification body', 'IATF 16949:2016', '9.2.2.3', 'Open point from the last surveillance audit.', 'Show the programme and the completed audits by shift', 'Quarterly', 'Quality', 'M. Divya', td + 45, 'open', '[]', null, null, true, 'sample');
    n := n + 4;
  end if;
  return n;
end $$;
revoke all on function console.aud_sample(uuid, text) from public, anon, authenticated;
revoke all on function console.aud_sample1(uuid, text) from public, anon, authenticated;

-- ---------- platform: backup, restore and clearing include the new tables ----------
do $patch$
declare rec record; def text; nw text; n int := 0;
begin
  for rec in select p.oid, p.proname from pg_proc p join pg_namespace s on s.oid = p.pronamespace where s.nspname = 'console' and p.proname in ('app2_tables', 'app2_clear') loop
    def := pg_get_functiondef(rec.oid); nw := def;
    if position('aud_ncs' in def) = 0 then
      if rec.proname = 'app2_tables' then
        nw := replace(nw, $a$'aud_actions','aud_log']$a$, $b$'aud_actions','aud_log','aud_ncs','aud_points']$b$);
      else
        nw := replace(nw, $a$delete from console.aud_log where customer_id = p_cid and (not p_real_only or sample); get diagnostics k = row_count; n := n + k;$a$,
          $b$delete from console.aud_ncs where customer_id = p_cid and (not p_real_only or sample); get diagnostics k = row_count; n := n + k;
    delete from console.aud_points where customer_id = p_cid and (not p_real_only or sample); get diagnostics k = row_count; n := n + k;
    delete from console.aud_log where customer_id = p_cid and (not p_real_only or sample); get diagnostics k = row_count; n := n + k;$b$);
      end if;
      if nw = def then raise exception '% was not updated', rec.proname; end if;
      execute nw; n := n + 1;
    end if;
  end loop;
  raise notice 'Audit management: % platform functions updated', n;
end $patch$;
do $$ begin
  if position('aud_ncs' in pg_get_functiondef('console.app2_tables(text)'::regprocedure)) = 0 then raise exception 'app2_tables was not updated'; end if;
  if position('aud_ncs' in pg_get_functiondef('console.app2_clear(text,uuid,boolean)'::regprocedure)) = 0 then raise exception 'app2_clear was not updated'; end if;
end $$;

-- ---------- product listing ----------
update console.products set current_version = '1.1.0', description = 'Audit programme and reports for system, process (VDA 6.3), product, layered process, document, supplier, special process, EHS and laboratory audits, with clause-by-clause checklists, automatic Major or Minor classification, corrective-action records with why-why root cause and effectiveness check, and dashboards' where code = 'aud';
insert into console.releases (product_code, version, notes) values
  ('aud', '1.1.0', 'Audit management: clause library for every audit type, automatic Major or Minor rules, findings with containment, why-why, permanent action and effectiveness check, special audit points, programme generator, findings dashboard, VDA 6.3 scale 10/8/6/4/0') on conflict do nothing;
update public.app_listings set tagline = 'Plan the year of audits from risk, check clause by clause, and see every finding through to a verified fix.',
  features = E'Clause-by-clause checklists: ISO 9001, IATF 16949, VDA 6.3 and 6.5, layered process, document, supplier, special process\nMajor or Minor decided by fixed rules; recommended actions filled in\nContainment, why-why root cause, permanent action and effectiveness check on one screen\nSpecial audit points, programme generator and dashboards' where code = 'aud';

-- ---------- permissions ----------
do $$ declare f regprocedure; begin
  for f in select p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname ~ '^kmr_aud_' loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;
