#!/usr/bin/env python3
"""Builds supabase/migrations/0048_apqp_ppap.sql and the website's apps/qp-template.js from ONE list of APQP deliverables,
and patches the existing portal / Data Master / Grand Master functions so the two new apps join them.
Run from kmr-console/:  python3 scripts/make-qp.py [path-to-kmr-group-website]"""
import re, sys, json, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WEB = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "..", "kmr-group-website")
MIG = os.path.join(ROOT, "supabase", "migrations")

# ---------------------------------------------------------------------------------------------------------------
# APQP deliverables by phase (the five phases and the outputs listed in the AIAG APQP manual, 2nd edition).
# source = the KMR app that already holds the evidence, so it is linked, never typed again:
#   pd:<doc>  Process Documents (pfd, pfmea, cp, sop, msa, spc, sc, chars, gauges, machines)
#   bi:report Balloon Inspector    cal:gauges Calibration Hub     cap:load Capacity Planner     ops:part Operations Master
#   ppap      the PPAP app         sales:plan Sales Flow
# ---------------------------------------------------------------------------------------------------------------
T = [
 (1, "Plan and define program", [
  ("Voice of the customer (market research, warranty history, team experience)", "ops:part"),
  ("Business plan and marketing strategy", ""), ("Product / process benchmark data", ""), ("Product / process assumptions", ""),
  ("Product reliability studies", ""), ("Customer inputs", "sales:plan"), ("Design goals", ""), ("Reliability and quality goals", ""),
  ("Preliminary bill of material", "ops:part"), ("Preliminary process flow chart", "pd:pfd"),
  ("Preliminary list of special product and process characteristics", "pd:sc"), ("Product assurance plan", ""), ("Management support", "")]),
 (2, "Product design and development", [
  ("Design FMEA", ""), ("Design for manufacturability and assembly", ""), ("Design verification", ""), ("Design reviews", ""),
  ("Prototype build — control plan", ""), ("Engineering drawings (including math data)", "bi:report"), ("Engineering specifications", ""),
  ("Material specifications", "ops:part"), ("Drawing and specification changes", ""), ("New equipment, tooling and facilities requirements", "cap:load"),
  ("Special product and process characteristics", "pd:sc"), ("Gages / testing equipment requirements", "cal:gauges"),
  ("Team feasibility commitment and management support", "")]),
 (3, "Process design and development", [
  ("Packaging standards and specifications", ""), ("Product / process quality system review", ""), ("Process flow chart", "pd:pfd"),
  ("Floor plan layout", "cap:load"), ("Characteristics matrix", "pd:chars"), ("Process failure mode and effects analysis (PFMEA)", "pd:pfmea"),
  ("Pre-launch control plan", "pd:cp"), ("Process instructions", "pd:sop"), ("Measurement systems analysis plan", "pd:msa"),
  ("Preliminary process capability study plan", "pd:spc"), ("Packaging specifications", ""), ("Management support", "")]),
 (4, "Product and process validation", [
  ("Production trial run", "cap:load"), ("Measurement systems evaluation", "pd:msa"), ("Preliminary process capability study", "pd:spc"),
  ("Production part approval (PPAP)", "ppap"), ("Production validation testing", ""), ("Packaging evaluation", ""),
  ("Production control plan", "pd:cp"), ("Quality planning sign-off and management support", "")]),
 (5, "Feedback, assessment and corrective action", [
  ("Reduced variation", ""), ("Improved customer satisfaction", ""), ("Improved delivery and service", ""), ("Lessons learned / best practices", "")]),
]
TEMPLATE = []
PHASES = {}
for ph, name, items in T:
    PHASES[ph] = name
    for i, (title, src) in enumerate(items, 1):
        TEMPLATE.append({"phase": ph, "seq": i, "code": f"{ph}.{i}", "title": title, "source": src})

def q(s): return "'" + str(s).replace("'", "''") + "'"
seed = ",\n  ".join(f"({t['phase']}, {t['seq']}, {q(t['code'])}, {q(t['title'])}, {q(t['source']) if t['source'] else 'null'})" for t in TEMPLATE)

# ---------------------------------------------------------------------------------------------------------------
HEAD = r"""-- =====================================================================
-- 0048 — APQP Planner + PPAP Submissions (two new KMR Apps), linked to the existing apps so nothing is entered twice.
--  • APQP: one programme per part, the five phases and their deliverables (AIAG APQP, 2nd edition), owner / due date /
--    status per deliverable, phase gate sign-offs, custom customer deliverables.
--  • PPAP: one submission per part and revision, submission level 1–5, the 18 elements, Part Submission Warrant, disposition.
--  • Links (kmr_qp_links): the part, routing and machines from the Operations Master; flow, PFMEA, control plan, SOP, MSA, SPC,
--    special characteristics from Process Documents; ballooned drawing and measured results from Balloon Inspector;
--    gauge calibration status from Calibration Hub; demand from Sales Flow. Evidence is read from the source app, never retyped.
--  • An approved PPAP completes the APQP deliverable "Production part approval" (4.4) by itself.
--  • Joins the portal (cards, access, figures), the Data Master and the Grand Master (sample load / flush / backup).
-- Needs 0043 and 0044. Safe to re-run. Generated by scripts/make-qp.py.
-- =====================================================================
do $$ begin
  if to_regprocedure('public.kmr_grand_sample(text,text)') is null then raise exception 'Run 0043_sales_calib_masters.sql first.'; end if;
  if to_regclass('public.app_listings') is null then raise exception 'Run 0044_website_apps_pricing.sql first.'; end if;
end $$;

-- ---------- the two products ----------
insert into console.products (code, name, description, app_path, seat_label, current_version, sort_order) values
  ('apqp', 'APQP Planner', 'Advanced product quality planning: five phases, deliverables, owners, due dates and gate sign-offs — linked to your drawings, PFMEA, control plans and gauges', '/it/apqp.html', 'users', '1.0.0', 70),
  ('ppap', 'PPAP Submissions', 'Production part approval: submission level, the 18 elements and the Part Submission Warrant — assembled from your Balloon Inspector and Process Documents data', '/it/ppap.html', 'users', '1.0.0', 80)
on conflict (code) do nothing;
insert into console.releases (product_code, version, notes) values
  ('apqp', '1.0.0', 'APQP Planner: programmes, five phases, deliverables, gates, links to Process Documents, Balloon Inspector, Calibration Hub, Capacity Planner'),
  ('ppap', '1.0.0', 'PPAP Submissions: levels 1–5, 18 elements, Part Submission Warrant, links to Process Documents and Balloon Inspector') on conflict do nothing;
insert into console.prices (product_code, period, currency, unit_amount, min_seats, active, note)
select v.code, v.period, 'INR', v.amt, 1, true, 'Starting price list (0048) — change in Console › Billing'
  from (values ('apqp', 'month', 2000), ('apqp', 'year', 20000), ('ppap', 'month', 2000), ('ppap', 'year', 20000)) v(code, period, amt)
on conflict (product_code, period, currency) do nothing;
insert into public.app_listings (code, name, tagline, features, sort_order, is_active) values
  ('apqp', 'APQP Planner', 'Run every new part through the five APQP phases — with the evidence pulled from your other KMR apps.',
   E'Five phases, every deliverable, owner and due date\nPhase gates and quality-planning sign-off\nFlow, PFMEA, control plan, drawings and gauges linked live — no re-typing', 70, true),
  ('ppap', 'PPAP Submissions', 'Assemble the PPAP package and the Part Submission Warrant from data you already have.',
   E'Submission levels 1–5 with the 18 elements\nBallooned results, PFMEA, control plan and MSA linked from your apps\nPart Submission Warrant ready to print; approval closes the APQP deliverable', 80, true)
on conflict (code) do update set name = excluded.name, tagline = coalesce(public.app_listings.tagline, excluded.tagline), features = coalesce(public.app_listings.features, excluded.features);

-- ---------- the APQP deliverables (one list; the app reads it) ----------
create table if not exists console.qp_template (phase int not null check (phase between 1 and 5), seq int not null, code text primary key, title text not null, source text);
insert into console.qp_template (phase, seq, code, title, source) values
  __SEED__
on conflict (code) do update set phase = excluded.phase, seq = excluded.seq, title = excluded.title, source = excluded.source;
alter table console.qp_template enable row level security;
drop policy if exists qp_template_read on console.qp_template;
create policy qp_template_read on console.qp_template for select to authenticated using (true);

-- ---------- tables ----------
create table if not exists console.apqp_projects (
  id uuid primary key default gen_random_uuid(), customer_id uuid not null references console.customers(id) on delete cascade,
  part_code text not null, part_name text, customer_code text, customer_name text, drawing_no text, drawing_rev text, program text,
  sop_date date, annual_volume numeric, team jsonb not null default '[]', gates jsonb not null default '{}', status text not null default 'active' check (status in ('active','on_hold','closed')),
  notes text, sample boolean not null default false, created_by text, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique (customer_id, part_code));
create table if not exists console.apqp_items (
  id uuid primary key default gen_random_uuid(), project_id uuid not null references console.apqp_projects(id) on delete cascade,
  customer_id uuid not null references console.customers(id) on delete cascade, phase int not null check (phase between 1 and 5), seq int not null default 0,
  code text not null, title text not null, source text, status text not null default 'open' check (status in ('open','progress','done','na')),
  owner text, due date, done_at date, notes text, evidence text, updated_at timestamptz not null default now());
create index if not exists apqp_items_project on console.apqp_items (project_id, phase, seq);
create table if not exists console.ppap_submissions (
  id uuid primary key default gen_random_uuid(), customer_id uuid not null references console.customers(id) on delete cascade,
  apqp_id uuid references console.apqp_projects(id) on delete set null, part_code text not null, part_name text, customer_code text, customer_name text,
  drawing_no text, drawing_rev text, level int not null default 3 check (level between 1 and 5), reason text not null default 'Initial submission',
  status text not null default 'draft' check (status in ('draft','ready','submitted','approved','interim','rejected')),
  submitted_on date, decided_on date, disposition_notes text, psw jsonb not null default '{}', elements jsonb not null default '{}',
  sample boolean not null default false, created_by text, created_at timestamptz not null default now(), updated_at timestamptz not null default now());
create index if not exists ppap_customer on console.ppap_submissions (customer_id, part_code);
do $$ declare t text; begin foreach t in array array['apqp_projects','apqp_items','ppap_submissions'] loop
  execute format('alter table console.%I enable row level security', t);
  execute format('drop policy if exists %I on console.%I', t || '_staff', t);
  execute format('create policy %I on console.%I for all to authenticated using (console.is_staff()) with check (console.is_staff())', t || '_staff', t);
end loop; end $$;

-- ---------- who may use them: roles from Administration › Users & access, per app ----------
create or replace function console.qp_member(p_customer uuid, p_email text, p_code text) returns boolean language sql stable security definer set search_path = console, public as $$
  select exists (select 1 from console.customer_members m where m.customer_id = p_customer and m.email = lower(p_email) and (m.is_admin or coalesce(m.roles ->> p_code, '') <> '')) $$;
create or replace function console.qp_role(p_customer uuid, p_code text) returns text language sql stable security definer set search_path = console, public as $$
  select case when not coalesce((select ok from console.access_state(p_code, p_customer)), false) then null
    when console.is_customer_admin(p_customer) then 'admin'
    else (select nullif(m.roles ->> p_code, '') from console.customer_members m where m.customer_id = p_customer and m.email = lower(coalesce(auth.jwt() ->> 'email', ''))) end $$;
create or replace function console.qp_cid(p_slug text, p_code text) returns uuid language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or console.qp_role(cid, p_code) is null then raise exception 'You have no access to this app.'; end if;
  return cid;
end $$;
create or replace function console.qp_edit(p_slug text, p_code text) returns uuid language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or coalesce(console.qp_role(cid, p_code), '') not in ('admin', 'editor') then raise exception 'You can view this app but not change it. Ask your administrator for editor access.'; end if;
  return cid;
end $$;
create or replace function console.jlen(j jsonb) returns integer language sql immutable as $$ select case when jsonb_typeof(j) = 'array' then jsonb_array_length(j) else 0 end $$;
revoke all on function console.qp_member(uuid, text, text), console.qp_role(uuid, text), console.qp_cid(text, text), console.qp_edit(text, text) from public, anon;

create or replace function public.kmr_qp_context(p_slug text, p_code text) returns jsonb language sql stable security definer set search_path = console, public as $$
  select case when console.qp_role(c.id, p_code) is null then null else jsonb_build_object('role', console.qp_role(c.id, p_code), 'company', c.name) end
    from console.customers c where c.slug = lower(p_slug) and p_code in ('apqp', 'ppap') $$;
create or replace function public.kmr_qp_template() returns jsonb language sql stable security definer set search_path = console, public as $$
  select coalesce(jsonb_agg(to_jsonb(t) order by t.phase, t.seq), '[]') from console.qp_template t $$;

-- parts, customers and the CFT team come from the Operations Master (entered once, used everywhere)
create or replace function public.kmr_qp_parts(p_slug text) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or (console.qp_role(cid, 'apqp') is null and console.qp_role(cid, 'ppap') is null) then raise exception 'You have no access to this app.'; end if;
  return jsonb_build_object(
    'parts', coalesce((select jsonb_agg(jsonb_build_object('code', r.code, 'name', r.name) || r.data order by r.code) from console.ops_records r where r.customer_id = cid and r.kind = 'parts' and r.active), '[]'),
    'customers', coalesce((select jsonb_agg(jsonb_build_object('code', r.code, 'name', r.name) order by r.code) from console.ops_records r where r.customer_id = cid and r.kind = 'customers' and r.active), '[]'),
    'cft', coalesce((select jsonb_agg(jsonb_build_object('code', r.code, 'name', r.name, 'role', r.data ->> 'cft_role', 'function', r.data ->> 'function', 'email', r.data ->> 'email') order by r.code) from console.ops_records r where r.customer_id = cid and r.kind = 'cft' and r.active), '[]'));
end $$;

-- ---------- APQP ----------
create or replace function public.kmr_apqp_list(p_slug text) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'apqp'); today date := (now() at time zone 'Asia/Kolkata')::date;
begin
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id', p.id, 'part_code', p.part_code, 'part_name', p.part_name, 'customer_name', p.customer_name, 'program', p.program, 'sop_date', p.sop_date,
      'status', p.status, 'gates', p.gates, 'sample', p.sample, 'updated_at', p.updated_at,
      'total', (select count(*) from console.apqp_items i where i.project_id = p.id and i.status <> 'na'),
      'done', (select count(*) from console.apqp_items i where i.project_id = p.id and i.status = 'done'),
      'overdue', (select count(*) from console.apqp_items i where i.project_id = p.id and i.status in ('open', 'progress') and i.due < today),
      'phases', (select coalesce(jsonb_object_agg(x.phase::text, jsonb_build_object('total', x.t, 'done', x.d)), '{}') from
                  (select phase, count(*) filter (where status <> 'na') t, count(*) filter (where status = 'done') d from console.apqp_items i where i.project_id = p.id group by phase) x))
    order by p.part_code) from console.apqp_projects p where p.customer_id = cid), '[]');
end $$;
create or replace function public.kmr_apqp_get(p_slug text, p_id uuid) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'apqp'); out jsonb;
begin
  select jsonb_build_object('project', to_jsonb(p) - 'customer_id', 'items', coalesce((select jsonb_agg(to_jsonb(i) - 'customer_id' order by i.phase, i.seq) from console.apqp_items i where i.project_id = p.id), '[]'))
    into out from console.apqp_projects p where p.id = p_id and p.customer_id = cid;
  if out is null then raise exception 'Programme not found.'; end if;
  return out;
end $$;
create or replace function public.kmr_apqp_create(p_slug text, p jsonb) returns uuid language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'apqp'); pid uuid; pc text := trim(coalesce(p ->> 'part_code', ''));
begin
  if pc = '' then raise exception 'Choose the part.'; end if;
  if exists (select 1 from console.apqp_projects where customer_id = cid and part_code = pc) then raise exception 'There is already an APQP programme for part %.', pc; end if;
  insert into console.apqp_projects (customer_id, part_code, part_name, customer_code, customer_name, drawing_no, drawing_rev, program, sop_date, annual_volume, team, notes, created_by)
  values (cid, pc, p ->> 'part_name', p ->> 'customer_code', p ->> 'customer_name', p ->> 'drawing_no', p ->> 'drawing_rev', p ->> 'program',
          nullif(p ->> 'sop_date', '')::date, nullif(p ->> 'annual_volume', '')::numeric, coalesce(p -> 'team', '[]'), p ->> 'notes', lower(coalesce(auth.jwt() ->> 'email', '')))
  returning id into pid;
  insert into console.apqp_items (project_id, customer_id, phase, seq, code, title, source)
  select pid, cid, t.phase, t.seq, t.code, t.title, t.source from console.qp_template t order by t.phase, t.seq;
  return pid;
end $$;
create or replace function public.kmr_apqp_save(p_slug text, p jsonb) returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'apqp');
begin
  update console.apqp_projects set
    part_name = case when p ? 'part_name' then p ->> 'part_name' else part_name end, customer_name = case when p ? 'customer_name' then p ->> 'customer_name' else customer_name end,
    drawing_no = case when p ? 'drawing_no' then p ->> 'drawing_no' else drawing_no end, drawing_rev = case when p ? 'drawing_rev' then p ->> 'drawing_rev' else drawing_rev end,
    program = case when p ? 'program' then p ->> 'program' else program end, sop_date = case when p ? 'sop_date' then nullif(p ->> 'sop_date', '')::date else sop_date end,
    annual_volume = case when p ? 'annual_volume' then nullif(p ->> 'annual_volume', '')::numeric else annual_volume end,
    team = case when p ? 'team' then p -> 'team' else team end, gates = case when p ? 'gates' then p -> 'gates' else gates end,
    notes = case when p ? 'notes' then p ->> 'notes' else notes end, status = coalesce(nullif(p ->> 'status', ''), status), updated_at = now()
   where id = (p ->> 'id')::uuid and customer_id = cid;
  if not found then raise exception 'Programme not found.'; end if;
end $$;
create or replace function public.kmr_apqp_item(p_slug text, p jsonb) returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'apqp'); today date := (now() at time zone 'Asia/Kolkata')::date; pid uuid;
begin
  update console.apqp_items set
    status = coalesce(nullif(p ->> 'status', ''), status), owner = case when p ? 'owner' then p ->> 'owner' else owner end,
    due = case when p ? 'due' then nullif(p ->> 'due', '')::date else due end, notes = case when p ? 'notes' then p ->> 'notes' else notes end,
    evidence = case when p ? 'evidence' then p ->> 'evidence' else evidence end,
    done_at = case when coalesce(nullif(p ->> 'status', ''), status) = 'done' then coalesce(done_at, today) else null end, updated_at = now()
   where id = (p ->> 'id')::uuid and customer_id = cid returning project_id into pid;
  if pid is null then raise exception 'Deliverable not found.'; end if;
  update console.apqp_projects set updated_at = now() where id = pid;
end $$;
create or replace function public.kmr_apqp_item_add(p_slug text, p jsonb) returns uuid language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'apqp'); pid uuid := (p ->> 'project_id')::uuid; ph int := coalesce((p ->> 'phase')::int, 1); n int; rid uuid;
begin
  if coalesce(trim(p ->> 'title'), '') = '' then raise exception 'Enter the deliverable.'; end if;
  if not exists (select 1 from console.apqp_projects where id = pid and customer_id = cid) then raise exception 'Programme not found.'; end if;
  select count(*) + 1 into n from console.apqp_items where project_id = pid and code like 'C%';
  insert into console.apqp_items (project_id, customer_id, phase, seq, code, title, owner, due)
  values (pid, cid, ph, 100 + n, 'C' || n, trim(p ->> 'title'), p ->> 'owner', nullif(p ->> 'due', '')::date) returning id into rid;
  return rid;
end $$;
create or replace function public.kmr_apqp_item_delete(p_slug text, p_id uuid) returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'apqp');
begin
  delete from console.apqp_items where id = p_id and customer_id = cid and code like 'C%';
  if not found then raise exception 'Only the deliverables you added yourself can be removed.'; end if;
end $$;
create or replace function public.kmr_apqp_delete(p_slug text, p_id uuid) returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'apqp');
begin
  if console.qp_role(cid, 'apqp') <> 'admin' then raise exception 'Only an administrator can delete a programme.'; end if;
  delete from console.apqp_projects where id = p_id and customer_id = cid;
end $$;

-- ---------- PPAP ----------
create or replace function public.kmr_ppap_list(p_slug text) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'ppap');
begin
  return coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'apqp_id', s.apqp_id, 'part_code', s.part_code, 'part_name', s.part_name, 'customer_name', s.customer_name,
      'drawing_rev', s.drawing_rev, 'level', s.level, 'reason', s.reason, 'status', s.status, 'submitted_on', s.submitted_on, 'decided_on', s.decided_on, 'sample', s.sample, 'updated_at', s.updated_at,
      'ready', (select count(*) from jsonb_each(s.elements) e where e.value ->> 'status' in ('ready', 'done', 'na'))) order by s.part_code, s.created_at desc)
    from console.ppap_submissions s where s.customer_id = cid), '[]');
end $$;
create or replace function public.kmr_ppap_get(p_slug text, p_id uuid) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'ppap'); out jsonb;
begin
  select to_jsonb(s) - 'customer_id' into out from console.ppap_submissions s where s.id = p_id and s.customer_id = cid;
  if out is null then raise exception 'Submission not found.'; end if;
  return out;
end $$;
create or replace function public.kmr_ppap_save(p_slug text, p jsonb) returns uuid language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'ppap'); rid uuid := nullif(p ->> 'id', '')::uuid; st text := coalesce(nullif(p ->> 'status', ''), 'draft');
        ap uuid; today date := (now() at time zone 'Asia/Kolkata')::date; em text := lower(coalesce(auth.jwt() ->> 'email', ''));
begin
  if rid is null then
    if coalesce(trim(p ->> 'part_code'), '') = '' then raise exception 'Choose the part.'; end if;
    insert into console.ppap_submissions (customer_id, apqp_id, part_code, part_name, customer_code, customer_name, drawing_no, drawing_rev, level, reason, status, submitted_on, decided_on, disposition_notes, psw, elements, created_by)
    values (cid, nullif(p ->> 'apqp_id', '')::uuid, trim(p ->> 'part_code'), p ->> 'part_name', p ->> 'customer_code', p ->> 'customer_name', p ->> 'drawing_no', p ->> 'drawing_rev',
            coalesce((p ->> 'level')::int, 3), coalesce(nullif(p ->> 'reason', ''), 'Initial submission'), st, nullif(p ->> 'submitted_on', '')::date, nullif(p ->> 'decided_on', '')::date,
            p ->> 'disposition_notes', coalesce(p -> 'psw', '{}'), coalesce(p -> 'elements', '{}'), em)
    returning id, apqp_id into rid, ap;
  else
    update console.ppap_submissions set
      part_name = case when p ? 'part_name' then p ->> 'part_name' else part_name end, customer_name = case when p ? 'customer_name' then p ->> 'customer_name' else customer_name end,
      drawing_no = case when p ? 'drawing_no' then p ->> 'drawing_no' else drawing_no end, drawing_rev = case when p ? 'drawing_rev' then p ->> 'drawing_rev' else drawing_rev end,
      level = coalesce((p ->> 'level')::int, level), reason = coalesce(nullif(p ->> 'reason', ''), reason), status = st,
      submitted_on = case when p ? 'submitted_on' then nullif(p ->> 'submitted_on', '')::date else submitted_on end,
      decided_on = case when p ? 'decided_on' then nullif(p ->> 'decided_on', '')::date else decided_on end,
      disposition_notes = case when p ? 'disposition_notes' then p ->> 'disposition_notes' else disposition_notes end,
      psw = case when p ? 'psw' then p -> 'psw' else psw end, elements = case when p ? 'elements' then p -> 'elements' else elements end, updated_at = now()
     where id = rid and customer_id = cid returning apqp_id into ap;
    if not found then raise exception 'Submission not found.'; end if;
  end if;
  -- an approved (or interim-approved) PPAP completes the APQP deliverable "Production part approval"
  if st in ('approved', 'interim') and ap is not null then
    update console.apqp_items set status = 'done', done_at = coalesce(done_at, today), updated_at = now() where project_id = ap and code = '4.4' and status <> 'done';
  end if;
  return rid;
end $$;
create or replace function public.kmr_ppap_delete(p_slug text, p_id uuid) returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'ppap');
begin
  if console.qp_role(cid, 'ppap') <> 'admin' then raise exception 'Only an administrator can delete a submission.'; end if;
  delete from console.ppap_submissions where id = p_id and customer_id = cid;
end $$;

-- ---------- the links: what the other apps already hold for this part (read live, never copied) ----------
create or replace function public.kmr_qp_links(p_slug text, p_part text) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid; org uuid; out jsonb := '{}'; r record; d jsonb; today date := (now() at time zone 'Asia/Kolkata')::date;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or (console.qp_role(cid, 'apqp') is null and console.qp_role(cid, 'ppap') is null) then raise exception 'You have no access to this app.'; end if;
  -- Operations Master: the part, its routing and the machines it runs on
  select jsonb_build_object('found', true, 'name', x.name, 'data', x.data) into d from console.ops_records x where x.customer_id = cid and x.kind = 'parts' and x.code = p_part and x.active limit 1;
  out := out || jsonb_build_object('ops', coalesce(d, jsonb_build_object('found', false)),
    'routing', jsonb_build_object(
      'operations', (select count(*) from console.ops_records x where x.customer_id = cid and x.kind = 'cycle_times' and x.active and x.data ->> 'part_no' = p_part),
      'machines', coalesce((select jsonb_agg(distinct x.data ->> 'machine') from console.ops_records x where x.customer_id = cid and x.kind = 'cycle_times' and x.active and x.data ->> 'part_no' = p_part and coalesce(x.data ->> 'machine', '') <> ''), '[]')));
  -- Process Documents: the latest project for this part and what is in it
  org := console.grand_ref(cid, 'pd');
  if org is not null and to_regclass('public.pd_projects') is not null then
    select p.id, p.status, p.rev, p.updated_at, p.doc into r from public.pd_projects p where p.org_id = org and p.part_no = p_part order by p.updated_at desc limit 1;
    if r.id is not null then
      out := out || jsonb_build_object('pd', jsonb_build_object('id', r.id, 'status', r.status, 'rev', r.rev, 'updated', r.updated_at,
        'chars', console.jlen(r.doc -> 'plan' -> 'chars'), 'ops', console.jlen(r.doc -> 'plan' -> 'ops'),
        'pfd', console.jlen(r.doc -> 'docs' -> 'pfd' -> 'rows'), 'pfmea', console.jlen(r.doc -> 'docs' -> 'pfmea' -> 'rows'), 'pfmea_std', coalesce(r.doc -> 'docs' -> 'pfmea' ->> 'std', 'vda'),
        'cp', console.jlen(r.doc -> 'docs' -> 'cp' -> 'rows'), 'sop', console.jlen(r.doc -> 'docs' -> 'sop' -> 'sections'),
        'msa', console.jlen(r.doc -> 'docs' -> 'msa' -> 'studies'), 'spc', console.jlen(r.doc -> 'docs' -> 'spc' -> 'studies'),
        'sc', console.jlen(r.doc -> 'docs' -> 'sc' -> 'rows'), 'gauges', console.jlen(r.doc -> 'docs' -> 'gauges' -> 'rows'), 'machines', console.jlen(r.doc -> 'docs' -> 'machines' -> 'rows')));
    end if;
  end if;
  -- Balloon Inspector: the ballooned drawing and the measured results
  org := console.grand_ref(cid, 'balloon');
  if org is not null and to_regclass('public.bi_reports') is not null then
    select b.id, b.title, b.rev, b.status, b.updated_at, b.data into r from public.bi_reports b where b.org_id = org and b.part_no = p_part order by b.updated_at desc limit 1;
    if r.id is not null then
      out := out || jsonb_build_object('balloon', jsonb_build_object('id', r.id, 'title', r.title, 'rev', r.rev, 'status', r.status, 'updated', r.updated_at,
        'items', console.jlen(r.data -> 'items'),
        'measured', (select count(*) from jsonb_array_elements(case when jsonb_typeof(r.data -> 'items') = 'array' then r.data -> 'items' else '[]'::jsonb end) i where coalesce(i ->> 'actual', '') <> ''),
        'special', (select count(*) from jsonb_array_elements(case when jsonb_typeof(r.data -> 'items') = 'array' then r.data -> 'items' else '[]'::jsonb end) i where coalesce(i ->> 'cls', '') <> '')));
    end if;
  end if;
  -- Calibration Hub: are the instruments valid?
  if console.has_app(cid, 'calib') then
    out := out || jsonb_build_object('calib', jsonb_build_object(
      'instruments', (select count(*) from console.cal_instruments i where i.customer_id = cid and i.status = 'In use'),
      'overdue', (select count(*) from console.cal_instruments i where i.customer_id = cid and i.status = 'In use' and i.next_due < today),
      'due30', (select count(*) from console.cal_instruments i where i.customer_id = cid and i.status = 'In use' and i.next_due between today and today + 30),
      'oot_open', (select count(*) from console.cal_oot o where o.customer_id = cid and o.status = 'Open')));
  end if;
  -- Sales Flow: the latest monthly demand for the part
  if console.has_app(cid, 'sales') then
    select jsonb_build_object('month', l.month, 'demand', l.demand_qty) into d from console.sf_lines l where l.customer_id = cid and l.part_code = p_part order by l.month desc limit 1;
    if d is not null then out := out || jsonb_build_object('sales', d); end if;
  end if;
  out := out || jsonb_build_object('capacity', jsonb_build_object('has', console.has_app(cid, 'capacity')),
    'ppap', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'level', s.level, 'status', s.status) order by s.created_at desc) from console.ppap_submissions s where s.customer_id = cid and s.part_code = p_part), '[]'),
    'apqp', (select jsonb_build_object('id', a.id) from console.apqp_projects a where a.customer_id = cid and a.part_code = p_part));
  return out;
end $$;

-- ---------- sample data (linked to the Operations Master sample parts and CFT team) ----------
create or replace function console.apqp_sample(p_cid uuid, p_action text) returns integer language plpgsql security definer set search_path = console, public as $$
declare today date := (now() at time zone 'Asia/Kolkata')::date; p record; pid uuid; n int := 0; k int := 0; team jsonb;
begin
  if p_action = 'flush' then
    delete from console.apqp_projects where customer_id = p_cid and sample; get diagnostics n = row_count; return n;
  end if;
  if exists (select 1 from console.apqp_projects where customer_id = p_cid and sample) then return 0; end if;
  select coalesce(jsonb_agg(jsonb_build_object('name', r.name, 'role', coalesce(r.data ->> 'cft_role', 'CFT member'), 'function', r.data ->> 'function') order by r.code), '[]') into team
    from console.ops_records r where r.customer_id = p_cid and r.kind = 'cft' and r.sample and r.active;
  for p in select r.code, r.name, r.data, c.name cname from console.ops_records r left join console.ops_records c on c.customer_id = r.customer_id and c.kind = 'customers' and c.code = r.data ->> 'customer'
            where r.customer_id = p_cid and r.kind = 'parts' and r.sample and r.active order by r.code limit 3 loop
    k := k + 1;
    insert into console.apqp_projects (customer_id, part_code, part_name, customer_code, customer_name, drawing_no, drawing_rev, program, sop_date, annual_volume, team, gates, sample, created_by)
    values (p_cid, p.code, p.name, p.data ->> 'customer', p.cname, p.data ->> 'drawing_no', p.data ->> 'revision', 'New part launch — ' || p.name, today + 45 + k * 30,
            nullif(p.data ->> 'annual_volume', '')::numeric, team,
            case k when 1 then jsonb_build_object('1', jsonb_build_object('ok', true, 'by', 'CFT leader', 'at', today - 70), '2', jsonb_build_object('ok', true, 'by', 'CFT leader', 'at', today - 35))
                   when 2 then jsonb_build_object('1', jsonb_build_object('ok', true, 'by', 'CFT leader', 'at', today - 20)) else '{}'::jsonb end, true, 'sample')
    returning id into pid;
    n := n + 1;
    insert into console.apqp_items (project_id, customer_id, phase, seq, code, title, source, status, owner, due, done_at)
    select pid, p_cid, t.phase, t.seq, t.code, t.title, t.source,
           case when t.phase < lvl.l then 'done' when t.phase = lvl.l then (case when t.seq % 3 = 0 then 'progress' when t.seq % 2 = 0 then 'done' else 'open' end) else 'open' end,
           (select (team -> ((t.seq + k) % greatest(jsonb_array_length(team), 1))) ->> 'name'),
           today + (t.phase - lvl.l) * 21 + t.seq * 2 - 12,
           case when t.phase < lvl.l or (t.phase = lvl.l and t.seq % 3 <> 0 and t.seq % 2 = 0) then today - 60 + t.phase * 9 + t.seq end
      from console.qp_template t, (select case k when 1 then 4 when 2 then 3 else 2 end l) lvl;
  end loop;
  return n;
end $$;
create or replace function console.ppap_sample(p_cid uuid, p_action text) returns integer language plpgsql security definer set search_path = console, public as $$
declare today date := (now() at time zone 'Asia/Kolkata')::date; a record; n int := 0; k int := 0; el jsonb; i int;
begin
  if p_action = 'flush' then
    delete from console.ppap_submissions where customer_id = p_cid and sample; get diagnostics n = row_count; return n;
  end if;
  if exists (select 1 from console.ppap_submissions where customer_id = p_cid and sample) then return 0; end if;
  for a in select * from console.apqp_projects where customer_id = p_cid and sample order by part_code limit 2 loop
    k := k + 1; el := '{}'::jsonb;
    for i in 1..18 loop
      el := el || jsonb_build_object('e' || i, jsonb_build_object('status', case when k = 1 and i not in (3, 12, 13) then 'ready' when k = 2 and i in (1, 5, 6, 7) then 'ready' else 'open' end,
                                                                  'note', case when k = 1 and i = 3 then 'Customer approval awaited' else '' end));
    end loop;
    insert into console.ppap_submissions (customer_id, apqp_id, part_code, part_name, customer_code, customer_name, drawing_no, drawing_rev, level, reason, status, psw, elements, sample, created_by)
    values (p_cid, a.id, a.part_code, a.part_name, a.customer_code, a.customer_name, a.drawing_no, a.drawing_rev, case k when 1 then 3 else 3 end, 'Initial submission',
            case k when 1 then 'ready' else 'draft' end,
            jsonb_build_object('part_number', a.part_code, 'part_name', a.part_name, 'drawing_no', a.drawing_no, 'drawing_rev', a.drawing_rev, 'purchase_order', 'PO-' || (4400 + k),
                               'weight_kg', 1.8, 'org_name', (select name from console.customers where id = p_cid), 'cavities', '1', 'safety_reg', 'No'),
            el, true, 'sample');
    n := n + 1;
  end loop;
  return n;
end $$;
"""

def tail(path, start_marker):
    s = open(os.path.join(MIG, path), encoding="utf-8").read()
    i = s.index(start_marker); return s[i:]

def sub(s, old, new, count=1, must=True):
    if must: assert s.count(old) >= 1, "patch target not found: " + old[:90]
    return s.replace(old, new) if count == 0 else s.replace(old, new, count)

# ---------------- portal: cards, access, figures (patched from 0037) ----------------
portal = tail("0037_calibration.sql", "create or replace function public.kmr_portal(p_slug text)")
portal = sub(portal, "      or (l.product_code = 'calib'    and console.cal_member(l.customer_id, em))",
             "      or (l.product_code = 'calib'    and console.cal_member(l.customer_id, em))\n      or (l.product_code in ('apqp', 'ppap') and console.qp_member(l.customer_id, em, l.product_code))")
portal = sub(portal, "             when 'calib'    then console.cal_member(l.customer_id, em)\n",
             "             when 'calib'    then console.cal_member(l.customer_id, em)\n             when 'apqp'     then console.qp_member(l.customer_id, em, 'apqp')\n             when 'ppap'     then console.qp_member(l.customer_id, em, 'ppap')\n")
portal = sub(portal, "    when 'calib'    then console.cal_member(cid, em)\n",
             "    when 'calib'    then console.cal_member(cid, em)\n    when 'apqp'     then console.qp_member(cid, em, 'apqp')\n    when 'ppap'     then console.qp_member(cid, em, 'ppap')\n")
STATS = """  select product_ref into ref from console.licences where customer_id = c and product_code = 'apqp';
  if ref is not null then
    out := out || jsonb_build_object('apqp', jsonb_build_object(
      'Programmes', (select count(*) from console.apqp_projects where customer_id = c and status = 'active'),
      'Open deliverables', (select count(*) from console.apqp_items i join console.apqp_projects p on p.id = i.project_id where i.customer_id = c and p.status = 'active' and i.status in ('open', 'progress')),
      'Overdue', (select count(*) from console.apqp_items i join console.apqp_projects p on p.id = i.project_id where i.customer_id = c and p.status = 'active' and i.status in ('open', 'progress') and i.due < today)));
  end if;
  select product_ref into ref from console.licences where customer_id = c and product_code = 'ppap';
  if ref is not null then
    out := out || jsonb_build_object('ppap', jsonb_build_object(
      'Submissions', (select count(*) from console.ppap_submissions where customer_id = c),
      'Awaiting approval', (select count(*) from console.ppap_submissions where customer_id = c and status = 'submitted'),
      'Approved', (select count(*) from console.ppap_submissions where customer_id = c and status in ('approved', 'interim'))));
  end if;
  return out;
end $$;
revoke all on function public.kmr_portal_stats(text) from public, anon;"""
portal = sub(portal, "  return out;\nend $$;\nrevoke all on function public.kmr_portal_stats(text) from public, anon;", STATS)

# ---------------- Data Master / Grand Master (patched from 0043) ----------------
masters = tail("0043_sales_calib_masters.sql", "-- ---------- export / clear / restore of the two apps")
APPS4 = "array['sales','calib','apqp','ppap']"
masters = sub(masters, "array['sales','calib']", APPS4, 0)
masters = sub(masters, "p_app in ('sales','calib')", "p_app in ('sales','calib','apqp','ppap')", 0)
masters = sub(masters, "parent := case when t in ('sf_lines','sf_actions','cal_instruments') then null when p_app = 'sales' then 'sf_lines' else 'cal_instruments' end;",
              "parent := case when t in ('sf_lines','sf_actions','cal_instruments','apqp_projects','ppap_submissions') then null when p_app = 'sales' then 'sf_lines' when p_app = 'calib' then 'cal_instruments' else 'apqp_projects' end;")
masters = sub(masters, "case when parent = 'sf_lines' then 'line_id' else 'instrument_id' end", "case parent when 'sf_lines' then 'line_id' when 'apqp_projects' then 'project_id' else 'instrument_id' end")
masters = sub(masters, "  elsif p_app = 'calib' then\n    delete from console.cal_instruments where customer_id = p_cid and (not p_real_only or not sample); get diagnostics n = row_count;\n  end if;",
              "  elsif p_app = 'calib' then\n    delete from console.cal_instruments where customer_id = p_cid and (not p_real_only or not sample); get diagnostics n = row_count;\n  elsif p_app = 'apqp' then\n    delete from console.apqp_projects where customer_id = p_cid and (not p_real_only or not sample); get diagnostics n = row_count;\n  elsif p_app = 'ppap' then\n    delete from console.ppap_submissions where customer_id = p_cid and (not p_real_only or not sample); get diagnostics n = row_count;\n  end if;")
masters = sub(masters, "case when t in ('sf_lines','sf_actions','cal_instruments') and p_real_only", "case when t in ('sf_lines','sf_actions','cal_instruments','apqp_projects','ppap_submissions') and p_real_only")
masters = sub(masters, "    if console.has_app(cid, 'calib') then out := out || jsonb_build_object('calib', console.cal_sample(cid, 'load')); end if;",
              "    if console.has_app(cid, 'calib') then out := out || jsonb_build_object('calib', console.cal_sample(cid, 'load')); end if;\n    if console.has_app(cid, 'apqp') then out := out || jsonb_build_object('apqp', console.apqp_sample(cid, 'load')); end if;\n    if console.has_app(cid, 'ppap') then out := out || jsonb_build_object('ppap', console.ppap_sample(cid, 'load')); end if;")
masters = sub(masters, "    if console.has_app(cid, 'calib') then out := out || jsonb_build_object('calib', console.cal_sample(cid, 'flush')); end if;",
              "    if console.has_app(cid, 'ppap') then out := out || jsonb_build_object('ppap', console.ppap_sample(cid, 'flush')); end if;\n    if console.has_app(cid, 'apqp') then out := out || jsonb_build_object('apqp', console.apqp_sample(cid, 'flush')); end if;\n    if console.has_app(cid, 'calib') then out := out || jsonb_build_object('calib', console.cal_sample(cid, 'flush')); end if;")
masters = sub(masters, "    real_ := real_ || jsonb_build_object('calib', n); smp := smp || jsonb_build_object('calib', k);\n  end if;",
              "    real_ := real_ || jsonb_build_object('calib', n); smp := smp || jsonb_build_object('calib', k);\n  end if;\n  if console.has_app(cid, 'apqp') then\n    select count(*) filter (where not sample), count(*) filter (where sample) into n, k from console.apqp_projects where customer_id = cid;\n    real_ := real_ || jsonb_build_object('apqp', n); smp := smp || jsonb_build_object('apqp', k);\n  end if;\n  if console.has_app(cid, 'ppap') then\n    select count(*) filter (where not sample), count(*) filter (where sample) into n, k from console.ppap_submissions where customer_id = cid;\n    real_ := real_ || jsonb_build_object('ppap', n); smp := smp || jsonb_build_object('ppap', k);\n  end if;")
masters = sub(masters, "    perform console.app2_clear('calib', cid, true); out := out || jsonb_build_object('calib', n);\n  end if;",
              "    perform console.app2_clear('calib', cid, true); out := out || jsonb_build_object('calib', n);\n  end if;\n  if console.has_app(cid, 'apqp') then\n    select count(*) into n from console.apqp_projects where customer_id = cid and not sample;\n    perform console.app2_clear('apqp', cid, true); out := out || jsonb_build_object('apqp', n);\n  end if;\n  if console.has_app(cid, 'ppap') then\n    select count(*) into n from console.ppap_submissions where customer_id = cid and not sample;\n    perform console.app2_clear('ppap', cid, true); out := out || jsonb_build_object('ppap', n);\n  end if;")
masters = sub(masters, "    if t = 'sales' then select count(*) into n from console.sf_lines where customer_id = cid and not sample;\n    else select count(*) into n from console.cal_instruments where customer_id = cid and not sample; end if;",
              "    if t = 'sales' then select count(*) into n from console.sf_lines where customer_id = cid and not sample;\n    elsif t = 'calib' then select count(*) into n from console.cal_instruments where customer_id = cid and not sample;\n    elsif t = 'apqp' then select count(*) into n from console.apqp_projects where customer_id = cid and not sample;\n    else select count(*) into n from console.ppap_submissions where customer_id = cid and not sample; end if;")

TABLES = """
-- ---------- the Data Master / Grand Master know the two new apps ----------
create or replace function console.app2_tables(p_app text) returns text[] language sql immutable as $$
  select case p_app when 'sales' then array['sf_lines','sf_despatch','sf_actions']
                    when 'calib' then array['cal_instruments','cal_records','cal_events','cal_oot','cal_msa']
                    when 'apqp'  then array['apqp_projects','apqp_items']
                    when 'ppap'  then array['ppap_submissions'] end
$$;
"""
GRANTS = """
do $$ declare f record; begin
  for f in select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname ~ '^kmr_(apqp|ppap|qp)_' loop
    execute format('revoke all on function %s from public, anon', f.sig); execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
end $$;
"""
out = HEAD.replace("__SEED__", seed) + "\n-- ---------- portal: cards, access and figures for all apps ----------\n" + portal + TABLES + "\n" + masters + GRANTS
with open(os.path.join(MIG, "0048_apqp_ppap.sql"), "w", encoding="utf-8") as f: f.write(out)

js = "/* APQP deliverables by phase — generated by kmr-console/scripts/make-qp.py (same list as the database seed). */\nwindow.QP_PHASES = " + json.dumps(PHASES) + ";\nwindow.QP_TEMPLATE = " + json.dumps(TEMPLATE, ensure_ascii=False) + ";\n"
with open(os.path.join(WEB, "public", "it", "apps", "qp-template.js"), "w", encoding="utf-8") as f: f.write(js)
print("0048 written:", len(out.splitlines()), "lines;", len(TEMPLATE), "deliverables")
