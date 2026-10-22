-- ================= Internal Audit: helpers =================
create or replace function console.aud_next(p_cid uuid, p_key text) returns bigint language sql security definer set search_path = console, public as $$
  insert into console.aud_counters (customer_id, key, n) values (p_cid, p_key, 1)
  on conflict (customer_id, key) do update set n = console.aud_counters.n + 1 returning n $$;
create or replace function console.aud_me() returns text language sql stable as $$ select lower(coalesce(auth.jwt() ->> 'email', '')) $$;
create or replace function console.aud_txt(p jsonb, k text) returns text language sql immutable as $$ select nullif(trim(coalesce(p ->> k, '')), '') $$;
create or replace function console.aud_num(p jsonb, k text) returns numeric language sql immutable as $$
  select case when coalesce(p ->> k, '') ~ '^\s*-?\d+(\.\d+)?([eE][-+]?\d+)?\s*$' then (p ->> k)::numeric else null end $$;
create or replace function console.aud_date(p jsonb, k text) returns date language plpgsql immutable as $$
begin
  if coalesce(p ->> k, '') = '' then return null; end if;
  return (p ->> k)::date;
exception when others then raise exception 'The date entered (%) is not valid.', p ->> k;
end $$;
create or replace function console.aud_today() returns date language sql stable as $$ select (now() at time zone 'Asia/Kolkata')::date $$;
create or replace function console.aud_cfg(p_cid uuid) returns jsonb language sql stable security definer set search_path = console, public as $$
  select coalesce((select data from console.aud_settings where customer_id = p_cid), '{}'::jsonb) $$;
-- true when the company's subscription includes the feature (the calls below raise a plain message when it does not)
create or replace function console.aud_has(p_slug text, p_key text) returns boolean language plpgsql stable security definer set search_path = console, public as $$
begin perform console.require_feature(p_slug, 'aud', p_key); return true; exception when others then return false; end $$;

-- the next audit number: PREFIX/26-27/0001 (financial year, April to March) or PREFIX-0001, prefix set in Setup
create or replace function console.aud_number(p_cid uuid) returns text language plpgsql security definer set search_path = console, public as $$
declare cfg jsonb := console.aud_cfg(p_cid); pre text; d date := console.aud_today(); y int; fyt text; n bigint; use_fy boolean := true;
begin
  pre := upper(regexp_replace(coalesce(console.aud_txt(cfg, 'prefix'), 'AUD'), '[^A-Za-z0-9-]', '', 'g')); if pre = '' then pre := 'AUD'; end if;
  if jsonb_typeof(cfg -> 'fy_numbering') = 'boolean' then use_fy := (cfg ->> 'fy_numbering')::boolean; end if;
  if use_fy then
    y := extract(year from d)::int; if extract(month from d) < 4 then y := y - 1; end if;
    fyt := lpad((y % 100)::text, 2, '0') || '-' || lpad(((y + 1) % 100)::text, 2, '0');
    n := console.aud_next(p_cid, 'A-' || fyt);
    return pre || '/' || fyt || '/' || lpad(n::text, 4, '0');
  end if;
  n := console.aud_next(p_cid, 'A');
  return pre || '-' || lpad(n::text, 4, '0');
end $$;


-- rating values: System / Product / Supplier audits use OK, Minor, Major, Observation, NA; Process audits (VDA 6.3 style) use 10, 8, 4, 0, NA
create or replace function console.aud_ratings(p_type text) returns text[] language sql immutable as $$
  select case when p_type = 'Process' then array['10','8','4','0','NA'] else array['OK','Minor','Major','Observation','NA'] end $$;
-- a finding needs an action: Minor, Major, or a Process rating of 8, 4, 0
create or replace function console.aud_is_finding(p_rating text) returns boolean language sql immutable as $$ select p_rating in ('Minor','Major','8','4','0') $$;
-- score and grade of a Process audit: sum of ratings out of 10 per rated question; A from 90, B from 80, C below; a question rated 0 caps the grade at B
create or replace function console.aud_score(p_list jsonb, out score numeric, out grade text) language plpgsql immutable as $$
declare n int; s numeric; z int;
begin
  select count(*), coalesce(sum((x ->> 'rating')::numeric), 0), count(*) filter (where x ->> 'rating' = '0') into n, s, z
    from jsonb_array_elements(p_list) x where x ->> 'rating' in ('10','8','4','0');
  if n = 0 then score := null; grade := null; return; end if;
  score := round(s * 100 / (10 * n), 1);
  grade := case when score >= 90 then 'A' when score >= 80 then 'B' else 'C' end;
  if z > 0 and grade = 'A' then grade := 'B'; end if;
end $$;
create or replace function console.aud_log(p_cid uuid, p_id uuid, p_text text, p_sample boolean) returns void language sql security definer set search_path = console, public as $$
  insert into console.aud_log (customer_id, audit_id, by, text, sample) values (p_cid, p_id, console.aud_me(), p_text, p_sample) $$;

create or replace function console.aud_row_json(r console.aud_audits, td date) returns jsonb language sql stable security definer set search_path = console, public as $$
  select jsonb_build_object('id', r.id, 'no', r.no, 'title', r.title, 'type', r.type, 'status', r.status, 'area', r.area, 'scope', r.scope, 'planned_on', r.planned_on, 'done_on', r.done_on, 'auditor', r.auditor, 'auditee', r.auditee,
    'shifts', r.shifts, 'summary', r.summary, 'score', r.score, 'grade', r.grade, 'reported_on', r.reported_on, 'closed_on', r.closed_on, 'sample', r.sample, 'updated_at', r.updated_at,
    'questions', jsonb_array_length(r.checklist), 'rated', (select count(*) from jsonb_array_elements(r.checklist) x where coalesce(x ->> 'rating', '') <> ''),
    'findings', (select count(*) from jsonb_array_elements(r.checklist) x where console.aud_is_finding(x ->> 'rating')),
    'late', r.status = 'planned' and r.planned_on is not null and r.planned_on < td,
    'actions_open', (select count(*) from console.aud_actions a where a.audit_id = r.id and a.status = 'open'),
    'actions_overdue', (select count(*) from console.aud_actions a where a.audit_id = r.id and a.status = 'open' and a.due_on is not null and a.due_on < td)) $$;
create or replace function console.aud_act_json(a console.aud_actions) returns jsonb language sql stable as $$
  select jsonb_build_object('id', a.id, 'audit_id', a.audit_id, 'q_id', a.q_id, 'text', a.text, 'owner', a.owner, 'due_on', a.due_on, 'status', a.status, 'done_on', a.done_on, 'evidence', a.evidence,
    'verified', a.verified, 'verified_on', a.verified_on, 'sample', a.sample) $$;

-- ================= load, setup =================
create or replace function public.kmr_aud_enabled(p_slug text) returns boolean language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  return cid is not null and console.qp_role(cid, 'aud') is not null;
end $$;
create or replace function public.kmr_aud_load(p_slug text) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'aud');
begin
  return jsonb_build_object('role', console.qp_role(cid, 'aud'), 'me', console.aud_me(), 'today', console.aud_today(), 'settings', console.aud_cfg(cid),
    'owners', coalesce((select jsonb_agg(distinct m.email) from console.customer_members m where m.customer_id = cid and (m.is_admin or coalesce(m.roles ->> 'aud', '') <> '')), '[]'),
    'has_findings', console.aud_has(p_slug, 'aud.findings-tracker'), 'has_scoring', console.aud_has(p_slug, 'aud.vda-6-3-scoring'));
end $$;
create or replace function public.kmr_aud_settings_save(p_slug text, p jsonb) returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'aud'); t numeric;
begin
  if console.qp_role(cid, 'aud') <> 'admin' then raise exception 'Only an administrator can change the setup.'; end if;
  if jsonb_typeof(p) <> 'object' then raise exception 'Settings must be an object.'; end if;
  if length(p::text) > 20000 then raise exception 'The settings are too large.'; end if;
  t := console.aud_num(p, 'due_days'); if t is not null and (t < 0 or t > 365) then raise exception 'Days to close a finding must be between 0 and 365.'; end if;
  if p ? 'fy_numbering' and jsonb_typeof(p -> 'fy_numbering') <> 'boolean' then raise exception 'Financial-year numbering must be on or off.'; end if;
  insert into console.aud_settings (customer_id, data) values (cid, p) on conflict (customer_id) do update set data = excluded.data, updated_at = now();
end $$;

-- ================= audits =================
create or replace function public.kmr_aud_audit_list(p_slug text, p jsonb default '{}') returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'aud'); td date := console.aud_today(); q text := console.aud_txt(p, 'q'); st text := coalesce(console.aud_txt(p, 'status'), 'all'); ty text := console.aud_txt(p, 'type'); yr int := console.aud_num(p, 'year')::int;
begin
  perform console.require_feature(p_slug, 'aud', 'aud.audit-programme-and-reports');
  return coalesce((select jsonb_agg(console.aud_row_json(r, td) order by r.planned_on nulls last, r.no) from (
    select * from console.aud_audits r where r.customer_id = cid and (st = 'all' or r.status = st or (st = 'open' and r.status in ('planned', 'reported'))) and (ty is null or r.type = ty)
      and (yr is null or extract(year from coalesce(r.planned_on, r.done_on, r.created_at::date))::int = yr)
      and (q is null or r.no ilike '%' || q || '%' or r.title ilike '%' || q || '%' or coalesce(r.area, '') ilike '%' || q || '%' or coalesce(r.auditor, '') ilike '%' || q || '%')
     order by r.planned_on desc nulls last limit 1000) r), '[]');
end $$;
create or replace function public.kmr_aud_audit_get(p_slug text, p_id uuid) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'aud'); td date := console.aud_today(); r console.aud_audits; hs boolean := console.aud_has(p_slug, 'aud.vda-6-3-scoring');
begin
  perform console.require_feature(p_slug, 'aud', 'aud.audit-programme-and-reports');
  select * into r from console.aud_audits where id = p_id and customer_id = cid; if r.id is null then raise exception 'Audit not found.'; end if;
  return console.aud_row_json(r, td) || jsonb_build_object('checklist', r.checklist, 'has_scoring', hs, 'score', case when hs then r.score end, 'grade', case when hs then r.grade end,
    'can_edit', console.qp_role(cid, 'aud') in ('admin', 'editor') and r.status = 'planned', 'can_act', console.qp_role(cid, 'aud') in ('admin', 'editor') and r.status in ('planned', 'reported'), 'is_admin', console.qp_role(cid, 'aud') = 'admin',
    'ratings', to_jsonb(console.aud_ratings(r.type)),
    'actions', coalesce((select jsonb_agg(console.aud_act_json(a) order by a.created_at) from console.aud_actions a where a.audit_id = r.id), '[]'),
    'log', coalesce((select jsonb_agg(jsonb_build_object('at', l.at, 'by', l.by, 'text', l.text) order by l.at desc) from (select * from console.aud_log where audit_id = r.id order by at desc limit 60) l), '[]'));
end $$;
create or replace function public.kmr_aud_audit_save(p_slug text, p jsonb) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'aud'); v_id uuid := nullif(p ->> 'id', '')::uuid; r console.aud_audits; ttl text := console.aud_txt(p, 'title'); ty text := coalesce(console.aud_txt(p, 'type'), 'System');
  pl date := console.aud_date(p, 'planned_on'); dn date := console.aud_date(p, 'done_on'); cl jsonb := p -> 'checklist'; item jsonb; out jsonb := '[]'; i int := 0; rt text; sh jsonb := coalesce(p -> 'shifts', '[]'); s text; ok text[];
begin
  perform console.require_feature(p_slug, 'aud', 'aud.audit-programme-and-reports');
  if ttl is null then raise exception 'Give the audit a short title.'; end if;
  if ty not in ('System', 'Process', 'Product', 'Supplier') then raise exception 'Choose the audit type: system, process, product or supplier.'; end if;
  if jsonb_typeof(sh) <> 'array' then raise exception 'The shifts are not valid.'; end if;
  for s in select jsonb_array_elements_text(sh) loop if s not in ('A', 'B', 'C', 'General') then raise exception 'Shift must be A, B, C or General.'; end if; end loop;
  if v_id is not null then
    select * into r from console.aud_audits where id = v_id and customer_id = cid; if r.id is null then raise exception 'Audit not found.'; end if;
    if r.status <> 'planned' then raise exception 'This audit is % and can no longer be edited. An administrator can reopen it.', r.status; end if;
    if p ? 'type' and ty <> r.type and jsonb_array_length(r.checklist) > 0 and exists (select 1 from jsonb_array_elements(r.checklist) x where coalesce(x ->> 'rating', '') <> '') then raise exception 'The audit type cannot be changed after questions have been rated.'; end if;
  end if;
  if cl is not null then
    if jsonb_typeof(cl) <> 'array' then raise exception 'The checklist is not valid.'; end if;
    if jsonb_array_length(cl) > 200 then raise exception 'A checklist can have up to 200 questions.'; end if;
    ok := console.aud_ratings(ty);
    for item in select * from jsonb_array_elements(cl) loop
      i := i + 1;
      if jsonb_typeof(item) <> 'object' or console.aud_txt(item, 'q') is null then raise exception 'Question % is empty.', i; end if;
      rt := console.aud_txt(item, 'rating'); if rt is not null and not (rt = any (ok)) then raise exception 'Question %: the rating must be one of %.', i, array_to_string(ok, ', '); end if;
      out := out || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object('id', coalesce(console.aud_txt(item, 'id'), substr(replace(gen_random_uuid()::text, '-', ''), 1, 8)), 'q', console.aud_txt(item, 'q'), 'ref', console.aud_txt(item, 'ref'), 'rating', rt, 'note', console.aud_txt(item, 'note'))));
    end loop;
  end if;
  if v_id is null then
    insert into console.aud_audits (customer_id, no, title, type, area, scope, planned_on, done_on, auditor, auditee, shifts, checklist, summary, created_by)
    values (cid, console.aud_number(cid), ttl, ty, console.aud_txt(p, 'area'), console.aud_txt(p, 'scope'), pl, dn, console.aud_txt(p, 'auditor'), console.aud_txt(p, 'auditee'), sh, coalesce(out, '[]'), console.aud_txt(p, 'summary'), console.aud_me()) returning * into r;
    perform console.aud_log(cid, r.id, 'Audit planned.', false);
  else
    update console.aud_audits set title = ttl, type = ty, area = console.aud_txt(p, 'area'), scope = console.aud_txt(p, 'scope'), planned_on = pl, done_on = dn, auditor = console.aud_txt(p, 'auditor'), auditee = console.aud_txt(p, 'auditee'),
      shifts = sh, checklist = case when cl is null then checklist else out end, summary = console.aud_txt(p, 'summary'), updated_at = now() where id = r.id returning * into r;
  end if;
  return jsonb_build_object('id', r.id, 'no', r.no);
end $$;
-- issue the report: the rules are in plain words
create or replace function public.kmr_aud_issue(p_slug text, p_id uuid) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'aud'); r console.aud_audits; td date := console.aud_today(); n int; sc numeric; gr text;
begin
  perform console.require_feature(p_slug, 'aud', 'aud.audit-programme-and-reports');
  select * into r from console.aud_audits where id = p_id and customer_id = cid; if r.id is null then raise exception 'Audit not found.'; end if;
  if r.status <> 'planned' then raise exception 'This audit is already %.', r.status; end if;
  if r.done_on is null then raise exception 'Enter the date the audit was done.'; end if;
  if r.done_on > td then raise exception 'The audit date is in the future.'; end if;
  if coalesce(trim(r.auditor), '') = '' then raise exception 'Name the auditor.'; end if;
  if coalesce(trim(r.auditee), '') = '' then raise exception 'Name the person or area audited.'; end if;
  if lower(trim(r.auditor)) = lower(trim(r.auditee)) then raise exception 'The auditor must not audit their own work. Choose another auditor.'; end if;
  if jsonb_array_length(r.checklist) = 0 then raise exception 'Add at least one question to the checklist.'; end if;
  select count(*) into n from jsonb_array_elements(r.checklist) x where coalesce(x ->> 'rating', '') = ''; if n > 0 then raise exception 'Rate every question: % are not rated yet.', n; end if;
  select count(*) into n from jsonb_array_elements(r.checklist) x where console.aud_is_finding(x ->> 'rating')
     and not exists (select 1 from console.aud_actions a where a.audit_id = r.id and a.q_id = x ->> 'id' and coalesce(trim(a.owner), '') <> '' and a.due_on is not null);
  if n > 0 then raise exception '% finding(s) still need an action with an owner and a due date.', n; end if;
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
  update console.aud_audits set status = 'closed', closed_on = td, updated_at = now() where id = r.id returning * into r;
  perform console.aud_log(cid, r.id, 'Audit closed: all findings fixed and checked.', r.sample);
  return console.aud_row_json(r, td);
end $$;
create or replace function public.kmr_aud_reopen(p_slug text, p_id uuid) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'aud'); r console.aud_audits; td date := console.aud_today();
begin
  if console.qp_role(cid, 'aud') <> 'admin' then raise exception 'Only an administrator can reopen an audit.'; end if;
  select * into r from console.aud_audits where id = p_id and customer_id = cid; if r.id is null then raise exception 'Audit not found.'; end if;
  if r.status = 'closed' then update console.aud_audits set status = 'reported', closed_on = null, updated_at = now() where id = r.id returning * into r;
  elsif r.status in ('reported', 'cancelled') then update console.aud_audits set status = 'planned', reported_on = null, score = null, grade = null, updated_at = now() where id = r.id returning * into r;
  else raise exception 'This audit is not issued yet.'; end if;
  perform console.aud_log(cid, r.id, 'Audit reopened by administrator (now ' || r.status || ').', r.sample);
  return console.aud_row_json(r, td);
end $$;
create or replace function public.kmr_aud_cancel(p_slug text, p_id uuid, p_reason text default null) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'aud'); r console.aud_audits; td date := console.aud_today();
begin
  select * into r from console.aud_audits where id = p_id and customer_id = cid; if r.id is null then raise exception 'Audit not found.'; end if;
  if r.status <> 'planned' then raise exception 'Only a planned audit can be cancelled.'; end if;
  if coalesce(trim(p_reason), '') = '' then raise exception 'Give the reason for cancelling the audit.'; end if;
  update console.aud_audits set status = 'cancelled', updated_at = now() where id = r.id returning * into r;
  perform console.aud_log(cid, r.id, 'Audit cancelled: ' || trim(p_reason), r.sample);
  return console.aud_row_json(r, td);
end $$;
create or replace function public.kmr_aud_audit_delete(p_slug text, p_id uuid) returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'aud'); r console.aud_audits;
begin
  select * into r from console.aud_audits where id = p_id and customer_id = cid; if r.id is null then raise exception 'Audit not found.'; end if;
  if r.status in ('reported', 'closed') and console.qp_role(cid, 'aud') <> 'admin' then raise exception 'An issued audit can be deleted only by an administrator.'; end if;
  delete from console.aud_audits where id = r.id;
end $$;

-- ================= actions =================
create or replace function public.kmr_aud_act_save(p_slug text, p jsonb) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'aud'); v_id uuid := nullif(p ->> 'id', '')::uuid; r console.aud_audits; a console.aud_actions; st text := coalesce(console.aud_txt(p, 'status'), 'open'); td date := console.aud_today();
  vf boolean := coalesce(p ->> 'verified', 'false') = 'true'; rid uuid := nullif(p ->> 'audit_id', '')::uuid; qid text := console.aud_txt(p, 'q_id');
begin
  perform console.require_feature(p_slug, 'aud', 'aud.audit-programme-and-reports');
  if console.aud_txt(p, 'text') is null then raise exception 'Write what the action is.'; end if;
  if st not in ('open', 'done') then raise exception 'Choose open or done.'; end if;
  if v_id is not null then select * into a from console.aud_actions where id = v_id and customer_id = cid; if a.id is null then raise exception 'Action not found.'; end if; rid := a.audit_id; end if;
  select * into r from console.aud_audits where id = rid and customer_id = cid; if r.id is null then raise exception 'Audit not found.'; end if;
  if r.status not in ('planned', 'reported') then raise exception 'This audit is %. An administrator can reopen it.', r.status; end if;
  if vf and st <> 'done' then raise exception 'An action can be checked for effectiveness only after it is done.'; end if;
  if v_id is null then
    insert into console.aud_actions (customer_id, audit_id, q_id, text, owner, due_on, status, done_on, evidence, verified, verified_on, created_by)
    values (cid, r.id, qid, trim(p ->> 'text'), console.aud_txt(p, 'owner'), console.aud_date(p, 'due_on'), st, case when st = 'done' then coalesce(console.aud_date(p, 'done_on'), td) end, console.aud_txt(p, 'evidence'), vf, case when vf then td end, console.aud_me()) returning * into a;
  else
    update console.aud_actions set q_id = coalesce(qid, q_id), text = trim(p ->> 'text'), owner = console.aud_txt(p, 'owner'), due_on = console.aud_date(p, 'due_on'), status = st,
      done_on = case when st = 'done' then coalesce(console.aud_date(p, 'done_on'), done_on, td) end, evidence = console.aud_txt(p, 'evidence'), verified = vf, verified_on = case when vf then coalesce(verified_on, td) end where id = a.id returning * into a;
  end if;
  return console.aud_act_json(a);
end $$;
create or replace function public.kmr_aud_act_done(p_slug text, p_id uuid, p_done boolean default true) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'aud'); a console.aud_actions; r console.aud_audits;
begin
  select * into a from console.aud_actions where id = p_id and customer_id = cid; if a.id is null then raise exception 'Action not found.'; end if;
  select * into r from console.aud_audits where id = a.audit_id; if r.status not in ('planned', 'reported') then raise exception 'This audit is %. An administrator can reopen it.', r.status; end if;
  update console.aud_actions set status = case when p_done then 'done' else 'open' end, done_on = case when p_done then coalesce(done_on, console.aud_today()) end, verified = case when p_done then verified else false end,
    verified_on = case when p_done then verified_on end where id = a.id returning * into a;
  return console.aud_act_json(a);
end $$;
create or replace function public.kmr_aud_act_delete(p_slug text, p_id uuid) returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'aud'); a console.aud_actions; r console.aud_audits;
begin
  select * into a from console.aud_actions where id = p_id and customer_id = cid; if a.id is null then raise exception 'Action not found.'; end if;
  select * into r from console.aud_audits where id = a.audit_id; if r.status <> 'planned' then raise exception 'Actions of an issued audit cannot be removed. Mark the action done instead.'; end if;
  delete from console.aud_actions where id = a.id;
end $$;
create or replace function public.kmr_aud_act_list(p_slug text, p jsonb default '{}') returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'aud'); td date := console.aud_today(); st text := coalesce(console.aud_txt(p, 'status'), 'open'); ow text := console.aud_txt(p, 'owner'); q text := console.aud_txt(p, 'q');
begin
  perform console.require_feature(p_slug, 'aud', 'aud.findings-tracker');
  return coalesce((select jsonb_agg(x order by x.done_flag, x.due_on nulls last) from (
    select console.aud_act_json(a) || jsonb_build_object('audit_no', r.no, 'audit_title', r.title, 'audit_type', r.type, 'overdue', a.status = 'open' and a.due_on is not null and a.due_on < td) x, (a.status = 'done') done_flag, a.due_on
      from console.aud_actions a join console.aud_audits r on r.id = a.audit_id
     where a.customer_id = cid and r.status <> 'cancelled' and (st = 'all' or a.status = st) and (ow is null or lower(coalesce(a.owner, '')) = lower(ow)) and (coalesce(p ->> 'overdue', '') <> 'true' or (a.status = 'open' and a.due_on < td))
       and (q is null or a.text ilike '%' || q || '%' or r.no ilike '%' || q || '%' or r.title ilike '%' || q || '%') order by a.status, a.due_on nulls last limit 1000) x), '[]');
end $$;

create or replace function public.kmr_aud_dashboard(p_slug text, p_year int default null) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'aud'); td date := console.aud_today(); yr int := coalesce(p_year, extract(year from console.aud_today())::int); pl int; dn int;
begin
  select count(*) filter (where status <> 'cancelled'), count(*) filter (where status in ('reported', 'closed')) into pl, dn from console.aud_audits
    where customer_id = cid and extract(year from coalesce(planned_on, done_on, created_at::date))::int = yr;
  return jsonb_build_object('year', yr, 'planned', pl, 'done', dn, 'completion', case when pl = 0 then null else round(dn * 100.0 / pl) end,
    'late_audits', (select count(*) from console.aud_audits where customer_id = cid and status = 'planned' and planned_on is not null and planned_on < td),
    'open_actions', (select count(*) from console.aud_actions a join console.aud_audits r on r.id = a.audit_id where a.customer_id = cid and a.status = 'open' and r.status <> 'cancelled'),
    'overdue_actions', (select count(*) from console.aud_actions a join console.aud_audits r on r.id = a.audit_id where a.customer_id = cid and a.status = 'open' and a.due_on is not null and a.due_on < td and r.status <> 'cancelled'),
    'unchecked', (select count(*) from console.aud_actions a join console.aud_audits r on r.id = a.audit_id where a.customer_id = cid and a.status = 'done' and not a.verified and r.status <> 'cancelled'),
    'by_type', coalesce((select jsonb_object_agg(type, jsonb_build_object('planned', p, 'done', d)) from (select type, count(*) filter (where status <> 'cancelled') p, count(*) filter (where status in ('reported', 'closed')) d from console.aud_audits
        where customer_id = cid and extract(year from coalesce(planned_on, done_on, created_at::date))::int = yr group by type) x), '{}'),
    'shifts', coalesce((select jsonb_agg(distinct s) from console.aud_audits r, jsonb_array_elements_text(r.shifts) s where r.customer_id = cid and r.status in ('reported', 'closed') and extract(year from coalesce(r.done_on, r.planned_on))::int = yr), '[]'),
    'avg_score', (select round(avg(score), 1) from console.aud_audits where customer_id = cid and type = 'Process' and status in ('reported', 'closed') and score is not null and done_on >= td - 365),
    'upcoming', coalesce((select jsonb_agg(x) from (select id, no, title, type, area, planned_on, auditor from console.aud_audits where customer_id = cid and status = 'planned' order by planned_on nulls last limit 8) x), '[]'),
    'late_actions', coalesce((select jsonb_agg(x) from (select a.id, a.text, a.owner, a.due_on, r.no audit_no, r.id audit_id from console.aud_actions a join console.aud_audits r on r.id = a.audit_id
        where a.customer_id = cid and a.status = 'open' and a.due_on is not null and a.due_on < td and r.status <> 'cancelled' order by a.due_on limit 8) x), '[]'),
    'recent', coalesce((select jsonb_agg(x) from (select id, no, title, type, score, grade, done_on from console.aud_audits where customer_id = cid and status in ('reported', 'closed') order by done_on desc nulls last limit 6) x), '[]'));
end $$;

-- ================= sample data (for trying the app; marked as sample and removed with one click) =================
create or replace function console.aud_sample(p_cid uuid, p_action text) returns integer language plpgsql security definer set search_path = console, public as $$
declare n int := 0; k int; td date := console.aud_today(); a1 uuid; a2 uuid; a3 uuid; a4 uuid; me text := 'sample'; cl jsonb; sc numeric; gr text;
begin
  if p_action = 'flush' then
    delete from console.aud_audits where customer_id = p_cid and sample; get diagnostics k = row_count; n := n + k;
    return n;
  end if;
  if exists (select 1 from console.aud_audits where customer_id = p_cid and sample) then return 0; end if;
  if not exists (select 1 from console.aud_settings where customer_id = p_cid) then
    insert into console.aud_settings (customer_id, data, sample) values (p_cid, jsonb_build_object('prefix', 'AUD', 'fy_numbering', true), true);
  end if;
  -- 1. closed system audit
  cl := $j$[{"id":"s1","q":"Is the quality policy known to the people in the area?","ref":"ISO 9001 5.2","rating":"OK"},
            {"id":"s2","q":"Are the current versions of procedures available where the work is done?","ref":"ISO 9001 7.5.3","rating":"Minor","note":"Two old copies of the inspection procedure on the notice board."},
            {"id":"s3","q":"Are calibration stickers valid on all gauges in use?","ref":"ISO 9001 7.1.5","rating":"OK"},
            {"id":"s4","q":"Are nonconforming parts identified and kept apart?","ref":"ISO 9001 8.7","rating":"OK"}]$j$::jsonb;
  insert into console.aud_audits (customer_id, no, title, type, status, area, scope, planned_on, done_on, auditor, auditee, shifts, checklist, summary, reported_on, closed_on, sample, created_by)
  values (p_cid, console.aud_number(p_cid), 'Document control and calibration, Final Inspection', 'System', 'closed', 'Final Inspection', 'Clauses 7.1.5, 7.5.3, 8.7', td - 70, td - 70, 'M. Divya', 'S. Priya', '["A"]', cl,
    'System works. One minor finding on old copies of a procedure; fixed and checked.', td - 69, td - 55, true, me) returning id into a1;
  insert into console.aud_actions (customer_id, audit_id, q_id, text, owner, due_on, status, done_on, evidence, verified, verified_on, sample, created_by)
  values (p_cid, a1, 's2', 'Remove old copies from the notice board and review the document list weekly', 'S. Priya', td - 60, 'done', td - 62, 'Photo of the board; weekly check added to the 5S sheet', true, td - 55, true, me);
  insert into console.aud_log (customer_id, audit_id, by, text, sample) values (p_cid, a1, me, 'Audit planned.', true), (p_cid, a1, me, 'Audit report issued.', true), (p_cid, a1, me, 'Audit closed: all findings fixed and checked.', true);
  -- 2. reported process audit with score
  cl := $j$[{"id":"p1","q":"Is the work instruction at the machine and does it match the control plan?","ref":"VDA 6.3 P6.1","rating":"10"},
            {"id":"p2","q":"Is the first-piece approval recorded for every setup?","ref":"VDA 6.3 P6.2","rating":"8","note":"Record missing on 2 of 10 setups checked."},
            {"id":"p3","q":"Are gauges at the machine calibrated and suitable for the tolerance?","ref":"VDA 6.3 P6.4","rating":"10"},
            {"id":"p4","q":"Are rejected parts stopped and tagged immediately?","ref":"VDA 6.3 P6.5","rating":"4","note":"Red bin not emptied; two rejects mixed with good parts."},
            {"id":"p5","q":"Is the reaction plan known to the operator?","ref":"VDA 6.3 P6.6","rating":"10"},
            {"id":"p6","q":"Is the tool life monitored and recorded?","ref":"VDA 6.3 P6.3","rating":"NA"}]$j$::jsonb;
  select s.score, s.grade into sc, gr from console.aud_score(cl) s;
  insert into console.aud_audits (customer_id, no, title, type, status, area, scope, planned_on, done_on, auditor, auditee, shifts, checklist, summary, score, grade, reported_on, sample, created_by)
  values (p_cid, console.aud_number(p_cid), 'Process audit, Boring operation T04', 'Process', 'reported', 'Machining T04', 'Process steps P6 of VDA 6.3', td - 20, td - 20, 'R. Venkatesh', 'K. Arun', '["B"]', cl,
    'Good discipline on gauges and instructions. Setup records and handling of rejects need attention.', sc, gr, td - 18, true, me) returning id into a2;
  insert into console.aud_actions (customer_id, audit_id, q_id, text, owner, due_on, status, done_on, evidence, verified, sample, created_by) values
    (p_cid, a2, 'p2', 'Make the setup approval sheet a mandatory step before the first lot is released', 'K. Arun', td - 6, 'done', td - 8, 'Revised changeover sheet CS-04 rev 02', false, true, me),
    (p_cid, a2, 'p4', 'Fix a locked red bin at the machine and train all three shifts on the rule', 'K. Arun', td - 3, 'open', null, null, false, true, me);
  insert into console.aud_log (customer_id, audit_id, by, text, sample) values (p_cid, a2, me, 'Audit planned.', true), (p_cid, a2, me, 'Audit report issued: score ' || sc || '%, grade ' || gr || '.', true);
  -- 3. late planned process audit on shift C
  insert into console.aud_audits (customer_id, no, title, type, status, area, scope, planned_on, auditor, auditee, shifts, sample, created_by)
  values (p_cid, console.aud_number(p_cid), 'Process audit, Night shift grinding', 'Process', 'planned', 'Grinding', 'Night shift practice', td - 5, 'M. Divya', 'P. Kumar', '["C"]', true, me) returning id into a3;
  insert into console.aud_log (customer_id, audit_id, by, text, sample) values (p_cid, a3, me, 'Audit planned.', true);
  -- 4. upcoming product audit
  insert into console.aud_audits (customer_id, no, title, type, status, area, scope, planned_on, auditor, auditee, shifts, sample, created_by)
  values (p_cid, console.aud_number(p_cid), 'Product audit, Drive Flange DP-1101', 'Product', 'planned', 'Final Inspection', 'Dimensions and appearance of 5 finished pieces', td + 12, 'S. Priya', 'R. Venkatesh', '["A"]', true, me) returning id into a4;
  insert into console.aud_log (customer_id, audit_id, by, text, sample) values (p_cid, a4, me, 'Audit planned.', true);
  n := 4;
  return n;
end $$;
revoke all on function console.aud_sample(uuid, text) from public, anon, authenticated;

do $$ declare f record; begin
  for f in select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname ~ '^kmr_aud_' loop
    execute format('revoke all on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
end $$;
