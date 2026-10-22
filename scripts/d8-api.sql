-- ================= 8D Problem Solving: helpers =================
create or replace function console.d8_next(p_cid uuid, p_key text) returns bigint language sql security definer set search_path = console, public as $$
  insert into console.d8_counters (customer_id, key, n) values (p_cid, p_key, 1)
  on conflict (customer_id, key) do update set n = console.d8_counters.n + 1 returning n $$;
create or replace function console.d8_me() returns text language sql stable as $$ select lower(coalesce(auth.jwt() ->> 'email', '')) $$;
create or replace function console.d8_txt(p jsonb, k text) returns text language sql immutable as $$ select nullif(trim(coalesce(p ->> k, '')), '') $$;
create or replace function console.d8_num(p jsonb, k text) returns numeric language sql immutable as $$
  select case when coalesce(p ->> k, '') ~ '^\s*-?\d+(\.\d+)?([eE][-+]?\d+)?\s*$' then (p ->> k)::numeric else null end $$;
create or replace function console.d8_date(p jsonb, k text) returns date language plpgsql immutable as $$
begin
  if coalesce(p ->> k, '') = '' then return null; end if;
  return (p ->> k)::date;
exception when others then raise exception 'The date entered (%) is not valid.', p ->> k;
end $$;
create or replace function console.d8_today() returns date language sql stable as $$ select (now() at time zone 'Asia/Kolkata')::date $$;
create or replace function console.d8_cfg(p_cid uuid) returns jsonb language sql stable security definer set search_path = console, public as $$
  select coalesce((select data from console.d8_settings where customer_id = p_cid), '{}'::jsonb) $$;
-- true when the company's subscription includes the feature (the calls below raise a plain message when it does not)
create or replace function console.d8_has(p_slug text, p_key text) returns boolean language plpgsql stable security definer set search_path = console, public as $$
begin perform console.require_feature(p_slug, 'd8', p_key); return true; exception when others then return false; end $$;

-- the next report number: PREFIX/26-27/0001 (financial year, April to March) or PREFIX-0001, prefix set in Setup
create or replace function console.d8_number(p_cid uuid) returns text language plpgsql security definer set search_path = console, public as $$
declare cfg jsonb := console.d8_cfg(p_cid); pre text; d date := console.d8_today(); y int; fyt text; n bigint; use_fy boolean := true;
begin
  pre := upper(regexp_replace(coalesce(console.d8_txt(cfg, 'prefix'), '8D'), '[^A-Za-z0-9-]', '', 'g')); if pre = '' then pre := '8D'; end if;
  if jsonb_typeof(cfg -> 'fy_numbering') = 'boolean' then use_fy := (cfg ->> 'fy_numbering')::boolean; end if;
  if use_fy then
    y := extract(year from d)::int; if extract(month from d) < 4 then y := y - 1; end if;
    fyt := lpad((y % 100)::text, 2, '0') || '-' || lpad(((y + 1) % 100)::text, 2, '0');
    n := console.d8_next(p_cid, 'R-' || fyt);
    return pre || '/' || fyt || '/' || lpad(n::text, 4, '0');
  end if;
  n := console.d8_next(p_cid, 'R');
  return pre || '-' || lpad(n::text, 4, '0');
end $$;

-- what must be in a step before it can be ticked (plain words; null = ready)
create or replace function console.d8_check(r console.d8_reports, s text) returns text language plpgsql stable security definer set search_path = console, public as $$
declare sec jsonb := coalesce(r.sections, '{}'); n int; m int;
begin
  if s = 'D0' then
    if coalesce(trim(sec #>> '{d0,symptom}'), '') = '' then return 'D0: describe the symptom, what the customer or the line saw.'; end if;
  elsif s = 'D1' then
    if coalesce(trim(sec #>> '{d1,leader}'), '') = '' then return 'D1: name the team leader.'; end if;
    select count(*) into n from jsonb_array_elements(case when jsonb_typeof(sec #> '{d1,members}') = 'array' then sec #> '{d1,members}' else '[]'::jsonb end) x where coalesce(trim(x ->> 'name'), '') <> '';
    if n < 2 then return 'D1: a team needs at least two named members.'; end if;
  elsif s = 'D2' then
    if coalesce(trim(sec #>> '{d2,deviation}'), '') = '' then return 'D2: say what is wrong compared with the requirement.'; end if;
    if coalesce(trim(sec #>> '{d2,where}'), '') = '' then return 'D2: say where the problem was found.'; end if;
  elsif s = 'D3' then
    if sec #>> '{d3,not_required}' = 'true' then
      if coalesce(trim(sec #>> '{d3,reason}'), '') = '' then return 'D3: give the reason why containment is not needed.'; end if;
    else
      select count(*), count(*) filter (where status = 'open') into n, m from console.d8_actions where report_id = r.id and kind = 'ICA';
      if n = 0 then return 'D3: add at least one containment action (or tick "not needed" and give the reason).'; end if;
      if m > 0 then return 'D3: ' || m || ' containment action(s) are still open.'; end if;
      if exists (select 1 from console.d8_actions where report_id = r.id and kind = 'ICA' and coalesce(trim(owner), '') = '') then return 'D3: every containment action needs an owner.'; end if;
    end if;
  elsif s = 'D4' then
    if coalesce(trim(sec #>> '{d4,occurrence,cause}'), '') = '' then return 'D4: write the root cause of how the problem occurred.'; end if;
    if coalesce(trim(sec #>> '{d4,escape,cause}'), '') = '' then return 'D4: write the root cause of why it was not detected (escape point).'; end if;
    if coalesce(sec #>> '{d4,occurrence,verified}', '') <> 'true' or coalesce(sec #>> '{d4,escape,verified}', '') <> 'true' then return 'D4: confirm that both root causes were verified, and say how.'; end if;
  elsif s = 'D5' then
    select count(*) into n from console.d8_actions where report_id = r.id and kind = 'PCA';
    if n = 0 then return 'D5: add at least one permanent corrective action.'; end if;
    if exists (select 1 from console.d8_actions where report_id = r.id and kind = 'PCA' and (coalesce(trim(owner), '') = '' or due_on is null)) then return 'D5: every corrective action needs an owner and a due date.'; end if;
  elsif s = 'D6' then
    select count(*) into n from console.d8_actions where report_id = r.id and kind = 'PCA' and status = 'open';
    if n > 0 then return 'D6: ' || n || ' corrective action(s) are still open.'; end if;
    if coalesce(trim(sec #>> '{d6,validation,result}'), '') = '' then return 'D6: write the validation result, the proof that the problem is gone.'; end if;
  elsif s = 'D7' then
    if not (exists (select 1 from console.d8_actions where report_id = r.id and kind = 'PREVENT')
            or exists (select 1 from jsonb_array_elements(case when jsonb_typeof(sec #> '{d7,docs}') = 'array' then sec #> '{d7,docs}' else '[]'::jsonb end) x where x ->> 'done' = 'true')
            or coalesce(trim(sec #>> '{d7,horizontal}'), '') <> '' or coalesce(trim(sec #>> '{d7,lessons}'), '') <> '') then
      return 'D7: record how the problem is prevented from coming back (documents updated, similar parts checked, or lessons learned).';
    end if;
  end if;
  return null;
end $$;

create or replace function console.d8_stepkeys() returns text[] language sql immutable as $$ select array['D0','D1','D2','D3','D4','D5','D6','D7','D8'] $$;

-- if the content of a ticked step no longer meets its rule, that step and the later ones are un-ticked (and the log says so)
create or replace function console.d8_revalidate(p_id uuid) returns void language plpgsql security definer set search_path = console, public as $$
declare r console.d8_reports; s text; bad text; msg text;
begin
  select * into r from console.d8_reports where id = p_id; if r.id is null then return; end if;
  foreach s in array console.d8_stepkeys() loop
    exit when not (r.steps ? s);
    msg := console.d8_check(r, s);
    if msg is not null then bad := s; exit; end if;
  end loop;
  if bad is null then return; end if;
  update console.d8_reports set steps = (select coalesce(jsonb_object_agg(k, v), '{}') from jsonb_each(steps) e(k, v) where k < bad), status = 'open', closed_on = null, closed_by = null, updated_at = now() where id = r.id;
  insert into console.d8_log (customer_id, report_id, by, text, sample) values (r.customer_id, r.id, console.d8_me(), bad || ' ticked off again because its content changed and no longer meets the step.', r.sample);
end $$;

create or replace function console.d8_row_json(r console.d8_reports, td date) returns jsonb language sql stable security definer set search_path = console, public as $$
  select jsonb_build_object('id', r.id, 'no', r.no, 'title', r.title, 'status', r.status, 'source', r.source, 'complainant', r.complainant, 'complaint_ref', r.complaint_ref, 'part_no', r.part_no, 'part_name', r.part_name,
    'lot_no', r.lot_no, 'qty_affected', r.qty_affected, 'severity', r.severity, 'opened_on', r.opened_on, 'due_on', r.due_on, 'owner', r.owner, 'closed_on', r.closed_on, 'closed_by', r.closed_by, 'notes', r.notes,
    'steps', r.steps, 'sample', r.sample, 'updated_at', r.updated_at,
    'current', (select t.s from unnest(console.d8_stepkeys()) with ordinality t(s, o) where not (r.steps ? t.s) order by t.o limit 1),
    'age_days', coalesce(r.closed_on, td) - r.opened_on, 'overdue', r.status = 'open' and r.due_on is not null and r.due_on < td,
    'actions_open', (select count(*) from console.d8_actions a where a.report_id = r.id and a.status = 'open'),
    'actions_overdue', (select count(*) from console.d8_actions a where a.report_id = r.id and a.status = 'open' and a.due_on is not null and a.due_on < td)) $$;
create or replace function console.d8_act_json(a console.d8_actions) returns jsonb language sql stable as $$
  select jsonb_build_object('id', a.id, 'report_id', a.report_id, 'kind', a.kind, 'seq', a.seq, 'text', a.text, 'owner', a.owner, 'due_on', a.due_on, 'status', a.status, 'done_on', a.done_on, 'evidence', a.evidence,
    'verified', a.verified, 'verified_on', a.verified_on, 'sample', a.sample) $$;

-- ================= load, setup =================
create or replace function public.kmr_d8_enabled(p_slug text) returns boolean language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  return cid is not null and console.qp_role(cid, 'd8') is not null;
end $$;
create or replace function public.kmr_d8_load(p_slug text) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'd8');
begin
  return jsonb_build_object('role', console.qp_role(cid, 'd8'), 'me', console.d8_me(), 'today', console.d8_today(), 'settings', console.d8_cfg(cid),
    'owners', coalesce((select jsonb_agg(distinct m.email) from console.customer_members m where m.customer_id = cid and (m.is_admin or coalesce(m.roles ->> 'd8', '') <> '')), '[]'),
    'has_analysis', console.d8_has(p_slug, 'd8.analysis'), 'has_tracker', console.d8_has(p_slug, 'd8.action-tracker'));
end $$;
create or replace function public.kmr_d8_settings_save(p_slug text, p jsonb) returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'd8'); t numeric;
begin
  if console.qp_role(cid, 'd8') <> 'admin' then raise exception 'Only an administrator can change the setup.'; end if;
  if jsonb_typeof(p) <> 'object' then raise exception 'Settings must be an object.'; end if;
  if length(p::text) > 20000 then raise exception 'The settings are too large.'; end if;
  t := console.d8_num(p, 'due_days'); if t is not null and (t < 0 or t > 365) then raise exception 'Days to complete an 8D must be between 0 and 365.'; end if;
  if p ? 'fy_numbering' and jsonb_typeof(p -> 'fy_numbering') <> 'boolean' then raise exception 'Financial-year numbering must be on or off.'; end if;
  insert into console.d8_settings (customer_id, data) values (cid, p) on conflict (customer_id) do update set data = excluded.data, updated_at = now();
end $$;

-- ================= reports =================
create or replace function public.kmr_d8_report_list(p_slug text, p jsonb default '{}') returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'd8'); td date := console.d8_today(); q text := console.d8_txt(p, 'q'); st text := coalesce(console.d8_txt(p, 'status'), 'all'); so text := console.d8_txt(p, 'source');
begin
  perform console.require_feature(p_slug, 'd8', 'd8.reports');
  return coalesce((select jsonb_agg(console.d8_row_json(r, td) order by (r.status = 'open') desc, r.due_on nulls last, r.opened_on desc) from (
    select * from console.d8_reports r where r.customer_id = cid and (st = 'all' or r.status = st) and (so is null or r.source = so)
      and (q is null or r.no ilike '%' || q || '%' or r.title ilike '%' || q || '%' or coalesce(r.part_no, '') ilike '%' || q || '%' or coalesce(r.part_name, '') ilike '%' || q || '%'
           or coalesce(r.complainant, '') ilike '%' || q || '%' or coalesce(r.complaint_ref, '') ilike '%' || q || '%')
     order by r.opened_on desc limit 1000) r), '[]');
end $$;
create or replace function public.kmr_d8_report_get(p_slug text, p_id uuid) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'd8'); td date := console.d8_today(); r console.d8_reports; ha boolean := console.d8_has(p_slug, 'd8.analysis');
begin
  perform console.require_feature(p_slug, 'd8', 'd8.reports');
  select * into r from console.d8_reports where id = p_id and customer_id = cid; if r.id is null then raise exception '8D report not found.'; end if;
  return console.d8_row_json(r, td) || jsonb_build_object('sections', r.sections, 'analysis', case when ha then r.analysis else '{}'::jsonb end, 'has_analysis', ha,
    'can_edit', console.qp_role(cid, 'd8') in ('admin', 'editor') and r.status = 'open', 'is_admin', console.qp_role(cid, 'd8') = 'admin',
    'actions', coalesce((select jsonb_agg(console.d8_act_json(a) order by a.kind, a.seq) from console.d8_actions a where a.report_id = r.id), '[]'),
    'log', coalesce((select jsonb_agg(jsonb_build_object('at', l.at, 'by', l.by, 'text', l.text) order by l.at desc) from (select * from console.d8_log where report_id = r.id order by at desc limit 60) l), '[]'));
end $$;
create or replace function public.kmr_d8_report_save(p_slug text, p jsonb) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'd8'); v_id uuid := nullif(p ->> 'id', '')::uuid; r console.d8_reports; ttl text := console.d8_txt(p, 'title'); so text := coalesce(console.d8_txt(p, 'source'), 'Customer complaint');
  sv text := coalesce(console.d8_txt(p, 'severity'), 'Major'); op date := coalesce(console.d8_date(p, 'opened_on'), console.d8_today()); du date := console.d8_date(p, 'due_on'); qa numeric := console.d8_num(p, 'qty_affected');
  sec jsonb := coalesce(p -> 'sections', '{}'::jsonb); k text; neu jsonb := '{}'; dd int;
begin
  perform console.require_feature(p_slug, 'd8', 'd8.reports');
  if ttl is null then raise exception 'Give the problem a short title.'; end if;
  if so not in ('Customer complaint', 'Internal rejection', 'Supplier problem', 'Audit finding', 'Field failure', 'Other') then raise exception 'Choose where the problem came from.'; end if;
  if sv not in ('Minor', 'Major', 'Critical') then raise exception 'Choose the severity: minor, major or critical.'; end if;
  if qa is not null and qa < 0 then raise exception 'The quantity affected cannot be negative.'; end if;
  if du is not null and du < op then raise exception 'The due date is before the date the 8D was opened.'; end if;
  if jsonb_typeof(sec) <> 'object' then raise exception 'The 8D sections are not valid.'; end if;
  if length(sec::text) > 600000 then raise exception 'The 8D report is too large.'; end if;
  foreach k in array array['d0','d1','d2','d3','d4','d5','d6','d7','d8'] loop
    if sec ? k then if jsonb_typeof(sec -> k) <> 'object' then raise exception 'Section % is not valid.', upper(k); end if; neu := neu || jsonb_build_object(k, sec -> k); end if;
  end loop;
  if v_id is null then
    dd := coalesce(console.d8_num(console.d8_cfg(cid), 'due_days'), 15)::int;
    insert into console.d8_reports (customer_id, no, title, source, complainant, complaint_ref, part_no, part_name, lot_no, qty_affected, severity, opened_on, due_on, owner, sections, notes, created_by)
    values (cid, console.d8_number(cid), ttl, so, console.d8_txt(p, 'complainant'), console.d8_txt(p, 'complaint_ref'), console.d8_txt(p, 'part_no'), console.d8_txt(p, 'part_name'), console.d8_txt(p, 'lot_no'), qa, sv, op,
      coalesce(du, case when p ? 'due_on' and coalesce(p ->> 'due_on', '') = '' then null else op + dd end), coalesce(console.d8_txt(p, 'owner'), console.d8_me()), neu, console.d8_txt(p, 'notes'), console.d8_me()) returning * into r;
    insert into console.d8_log (customer_id, report_id, by, text) values (cid, r.id, console.d8_me(), '8D opened.');
  else
    select * into r from console.d8_reports where id = v_id and customer_id = cid; if r.id is null then raise exception '8D report not found.'; end if;
    if r.status = 'closed' then raise exception 'This 8D is closed. An administrator can reopen it.'; end if;
    update console.d8_reports set title = ttl, source = so, complainant = console.d8_txt(p, 'complainant'), complaint_ref = console.d8_txt(p, 'complaint_ref'), part_no = console.d8_txt(p, 'part_no'), part_name = console.d8_txt(p, 'part_name'),
      lot_no = console.d8_txt(p, 'lot_no'), qty_affected = qa, severity = sv, opened_on = op, due_on = du, owner = console.d8_txt(p, 'owner'), notes = console.d8_txt(p, 'notes'), sections = sections || neu, updated_at = now() where id = r.id returning * into r;
    perform console.d8_revalidate(r.id);
  end if;
  return jsonb_build_object('id', r.id, 'no', r.no);
end $$;
create or replace function public.kmr_d8_step(p_slug text, p_id uuid, p_step text, p_done boolean default true) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'd8'); r console.d8_reports; i int; msg text; keys text[] := console.d8_stepkeys(); s text; td date := console.d8_today();
begin
  perform console.require_feature(p_slug, 'd8', 'd8.reports');
  select * into r from console.d8_reports where id = p_id and customer_id = cid; if r.id is null then raise exception '8D report not found.'; end if;
  i := array_position(keys, p_step); if i is null then raise exception 'Choose a step from D0 to D8.'; end if;
  if p_done then
    if r.steps ? p_step then return console.d8_row_json(r, td); end if;
    if i > 1 and not (r.steps ? keys[i - 1]) then raise exception 'Finish % first.', keys[i - 1]; end if;
    msg := console.d8_check(r, p_step); if msg is not null then raise exception '%', msg; end if;
    update console.d8_reports set steps = steps || jsonb_build_object(p_step, td::text), updated_at = now(),
      status = case when p_step = 'D8' then 'closed' else status end, closed_on = case when p_step = 'D8' then td else closed_on end, closed_by = case when p_step = 'D8' then console.d8_me() else closed_by end where id = r.id returning * into r;
    insert into console.d8_log (customer_id, report_id, by, text, sample) values (cid, r.id, console.d8_me(), case when p_step = 'D8' then 'D8 done: the 8D is closed.' else p_step || ' done.' end, r.sample);
  else
    if r.status = 'closed' and console.qp_role(cid, 'd8') <> 'admin' then raise exception 'Only an administrator can reopen a closed 8D.'; end if;
    if not (r.steps ? p_step) then return console.d8_row_json(r, td); end if;
    update console.d8_reports set steps = (select coalesce(jsonb_object_agg(k, v), '{}') from jsonb_each(steps) e(k, v) where array_position(keys, k) < i), status = 'open', closed_on = null, closed_by = null, updated_at = now() where id = r.id returning * into r;
    insert into console.d8_log (customer_id, report_id, by, text, sample) values (cid, r.id, console.d8_me(), p_step || ' opened again' || case when p_step = 'D8' then ' (reopened by administrator).' else '.' end, r.sample);
  end if;
  return console.d8_row_json(r, td);
end $$;
create or replace function public.kmr_d8_report_delete(p_slug text, p_id uuid) returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'd8'); r console.d8_reports;
begin
  select * into r from console.d8_reports where id = p_id and customer_id = cid; if r.id is null then raise exception '8D report not found.'; end if;
  if r.status = 'closed' and console.qp_role(cid, 'd8') <> 'admin' then raise exception 'A closed 8D can be deleted only by an administrator.'; end if;
  delete from console.d8_reports where id = r.id;
end $$;

-- ================= root-cause tools (Is / Is-not, 5-Why, fishbone) =================
create or replace function public.kmr_d8_analysis_save(p_slug text, p_id uuid, p jsonb) returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'd8'); r console.d8_reports;
begin
  perform console.require_feature(p_slug, 'd8', 'd8.analysis');
  select * into r from console.d8_reports where id = p_id and customer_id = cid; if r.id is null then raise exception '8D report not found.'; end if;
  if r.status = 'closed' then raise exception 'This 8D is closed. An administrator can reopen it.'; end if;
  if jsonb_typeof(p) <> 'object' then raise exception 'The analysis is not valid.'; end if;
  if length(p::text) > 200000 then raise exception 'The analysis is too large.'; end if;
  if p ? 'is_not' and (jsonb_typeof(p -> 'is_not') <> 'array' or jsonb_array_length(p -> 'is_not') > 20) then raise exception 'The Is / Is-not table can have up to 20 rows.'; end if;
  if p ? 'whys' and jsonb_typeof(p -> 'whys') <> 'object' then raise exception 'The 5-Why chains are not valid.'; end if;
  if p ? 'fishbone' and jsonb_typeof(p -> 'fishbone') <> 'object' then raise exception 'The fishbone sheet is not valid.'; end if;
  update console.d8_reports set analysis = jsonb_strip_nulls(jsonb_build_object('is_not', coalesce(p -> 'is_not', '[]'::jsonb), 'whys', coalesce(p -> 'whys', '{}'::jsonb), 'fishbone', coalesce(p -> 'fishbone', '{}'::jsonb))), updated_at = now() where id = r.id;
end $$;

-- ================= actions =================
create or replace function public.kmr_d8_act_save(p_slug text, p jsonb) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'd8'); v_id uuid := nullif(p ->> 'id', '')::uuid; r console.d8_reports; a console.d8_actions; kd text := coalesce(console.d8_txt(p, 'kind'), 'ICA'); st text := coalesce(console.d8_txt(p, 'status'), 'open');
  vf boolean := coalesce(p ->> 'verified', 'false') = 'true'; td date := console.d8_today(); rid uuid := nullif(p ->> 'report_id', '')::uuid; sq int;
begin
  perform console.require_feature(p_slug, 'd8', 'd8.reports');
  if console.d8_txt(p, 'text') is null then raise exception 'Write what the action is.'; end if;
  if kd not in ('ICA', 'PCA', 'PREVENT') then raise exception 'Choose the kind of action.'; end if;
  if st not in ('open', 'done') then raise exception 'Choose open or done.'; end if;
  if v_id is not null then select * into a from console.d8_actions where id = v_id and customer_id = cid; if a.id is null then raise exception 'Action not found.'; end if; rid := a.report_id; end if;
  select * into r from console.d8_reports where id = rid and customer_id = cid; if r.id is null then raise exception '8D report not found.'; end if;
  if r.status = 'closed' then raise exception 'This 8D is closed. An administrator can reopen it.'; end if;
  if v_id is null then
    select coalesce(max(seq), 0) + 1 into sq from console.d8_actions where report_id = r.id and kind = kd;
    insert into console.d8_actions (customer_id, report_id, kind, seq, text, owner, due_on, status, done_on, evidence, verified, verified_on, created_by)
    values (cid, r.id, kd, sq, trim(p ->> 'text'), console.d8_txt(p, 'owner'), console.d8_date(p, 'due_on'), st, case when st = 'done' then coalesce(console.d8_date(p, 'done_on'), td) end, console.d8_txt(p, 'evidence'), vf, case when vf then td end, console.d8_me()) returning * into a;
  else
    update console.d8_actions set kind = kd, text = trim(p ->> 'text'), owner = console.d8_txt(p, 'owner'), due_on = console.d8_date(p, 'due_on'), status = st,
      done_on = case when st = 'done' then coalesce(console.d8_date(p, 'done_on'), done_on, td) end, evidence = console.d8_txt(p, 'evidence'), verified = vf, verified_on = case when vf then coalesce(verified_on, td) end where id = a.id returning * into a;
  end if;
  perform console.d8_revalidate(r.id);
  return console.d8_act_json(a);
end $$;
create or replace function public.kmr_d8_act_done(p_slug text, p_id uuid, p_done boolean default true) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'd8'); a console.d8_actions; r console.d8_reports;
begin
  select * into a from console.d8_actions where id = p_id and customer_id = cid; if a.id is null then raise exception 'Action not found.'; end if;
  select * into r from console.d8_reports where id = a.report_id; if r.status = 'closed' then raise exception 'This 8D is closed. An administrator can reopen it.'; end if;
  update console.d8_actions set status = case when p_done then 'done' else 'open' end, done_on = case when p_done then coalesce(done_on, console.d8_today()) end, verified = case when p_done then verified else false end,
    verified_on = case when p_done then verified_on end where id = a.id returning * into a;
  perform console.d8_revalidate(a.report_id);
  return console.d8_act_json(a);
end $$;
create or replace function public.kmr_d8_act_delete(p_slug text, p_id uuid) returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'd8'); a console.d8_actions; r console.d8_reports;
begin
  select * into a from console.d8_actions where id = p_id and customer_id = cid; if a.id is null then raise exception 'Action not found.'; end if;
  select * into r from console.d8_reports where id = a.report_id; if r.status = 'closed' then raise exception 'This 8D is closed. An administrator can reopen it.'; end if;
  delete from console.d8_actions where id = a.id;
  perform console.d8_revalidate(a.report_id);
end $$;
-- all actions of all 8Ds (the action tracker)
create or replace function public.kmr_d8_act_list(p_slug text, p jsonb default '{}') returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'd8'); td date := console.d8_today(); st text := coalesce(console.d8_txt(p, 'status'), 'open'); ow text := console.d8_txt(p, 'owner'); q text := console.d8_txt(p, 'q');
begin
  perform console.require_feature(p_slug, 'd8', 'd8.action-tracker');
  return coalesce((select jsonb_agg(x order by x.done_flag, x.due_on nulls last) from (
    select console.d8_act_json(a) || jsonb_build_object('report_no', r.no, 'report_title', r.title, 'part_no', r.part_no, 'overdue', a.status = 'open' and a.due_on is not null and a.due_on < td) x, (a.status = 'done') done_flag, a.due_on
      from console.d8_actions a join console.d8_reports r on r.id = a.report_id
     where a.customer_id = cid and (st = 'all' or a.status = st) and (ow is null or lower(coalesce(a.owner, '')) = lower(ow)) and (coalesce(p ->> 'overdue', '') <> 'true' or (a.status = 'open' and a.due_on < td))
       and (q is null or a.text ilike '%' || q || '%' or r.no ilike '%' || q || '%' or r.title ilike '%' || q || '%') order by a.status, a.due_on nulls last limit 1000) x), '[]');
end $$;

create or replace function public.kmr_d8_dashboard(p_slug text) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'd8'); td date := console.d8_today();
begin
  return jsonb_build_object(
    'open', (select count(*) from console.d8_reports where customer_id = cid and status = 'open'),
    'overdue', (select count(*) from console.d8_reports where customer_id = cid and status = 'open' and due_on is not null and due_on < td),
    'critical_open', (select count(*) from console.d8_reports where customer_id = cid and status = 'open' and severity = 'Critical'),
    'no_containment', (select count(*) from console.d8_reports where customer_id = cid and status = 'open' and not (steps ? 'D3') and td - opened_on >= 1),
    'closed_90', (select count(*) from console.d8_reports where customer_id = cid and status = 'closed' and closed_on >= td - 90),
    'avg_days_to_close', (select round(avg(closed_on - opened_on)) from console.d8_reports where customer_id = cid and status = 'closed' and closed_on >= td - 180),
    'actions_open', (select count(*) from console.d8_actions a join console.d8_reports r on r.id = a.report_id where a.customer_id = cid and a.status = 'open' and r.status = 'open'),
    'actions_overdue', (select count(*) from console.d8_actions a join console.d8_reports r on r.id = a.report_id where a.customer_id = cid and a.status = 'open' and a.due_on is not null and a.due_on < td and r.status = 'open'),
    'by_step', coalesce((select jsonb_object_agg(cur, n) from (select (select t.s from unnest(console.d8_stepkeys()) with ordinality t(s, o) where not (r.steps ? t.s) order by t.o limit 1) cur, count(*) n
        from console.d8_reports r where r.customer_id = cid and r.status = 'open' group by 1) x where cur is not null), '{}'),
    'by_source', coalesce((select jsonb_object_agg(source, n) from (select source, count(*) n from console.d8_reports where customer_id = cid and opened_on >= td - 365 group by source) x), '{}'),
    'by_cause', coalesce((select jsonb_object_agg(cat, n) from (select coalesce(nullif(trim(sections #>> '{d4,occurrence,category}'), ''), 'Not stated') cat, count(*) n from console.d8_reports where customer_id = cid and opened_on >= td - 365 and steps ? 'D4' group by 1) x), '{}'),
    'due_soon', coalesce((select jsonb_agg(x) from (select r.id, r.no, r.title, r.due_on, r.severity, r.part_no,
        (select t.s from unnest(console.d8_stepkeys()) with ordinality t(s, o) where not (r.steps ? t.s) order by t.o limit 1) current from console.d8_reports r
        where r.customer_id = cid and r.status = 'open' order by r.due_on nulls last, r.opened_on limit 8) x), '[]'),
    'late_actions', coalesce((select jsonb_agg(x) from (select a.id, a.text, a.owner, a.due_on, a.kind, r.no report_no, r.id report_id from console.d8_actions a join console.d8_reports r on r.id = a.report_id
        where a.customer_id = cid and a.status = 'open' and a.due_on is not null and a.due_on < td and r.status = 'open' order by a.due_on limit 8) x), '[]'));
end $$;

-- ================= sample data (for trying the app; marked as sample and removed with one click) =================
create or replace function console.d8_sample(p_cid uuid, p_action text) returns integer language plpgsql security definer set search_path = console, public as $$
declare n int := 0; k int; td date := console.d8_today(); r1 uuid; r2 uuid; r3 uuid; me text := 'sample';
  st3 jsonb; st4 jsonb; st9 jsonb;
begin
  if p_action = 'flush' then
    delete from console.d8_reports where customer_id = p_cid and sample; get diagnostics k = row_count; n := n + k;
    return n;
  end if;
  if exists (select 1 from console.d8_reports where customer_id = p_cid and sample) then return 0; end if;
  if not exists (select 1 from console.d8_settings where customer_id = p_cid) then
    insert into console.d8_settings (customer_id, data, sample) values (p_cid, jsonb_build_object('prefix', '8D', 'fy_numbering', true, 'due_days', 15), true);
  end if;
  st3 := jsonb_build_object('D0', (td - 6)::text, 'D1', (td - 6)::text, 'D2', (td - 5)::text, 'D3', (td - 5)::text);
  insert into console.d8_reports (customer_id, no, title, source, complainant, complaint_ref, part_no, part_name, lot_no, qty_affected, severity, opened_on, due_on, owner, steps, sections, analysis, sample, created_by) values
    (p_cid, console.d8_number(p_cid), 'Bore diameter oversize on Drive Flange', 'Customer complaint', 'Deccan Motors Ltd', 'SCAR-2611', 'DP-1101', 'Drive flange', 'L-2610-04', 120, 'Major', td - 6, td + 9, me, st3,
     $j${"d0":{"symptom":"Customer found 14 flanges with the 42 mm bore 0.05 mm above the upper limit at incoming inspection.","era_needed":true,"era":"Stopped shipment of lot L-2610-04 and called the customer to hold the lot."},
        "d1":{"leader":"R. Venkatesh","champion":"Plant head","members":[{"name":"R. Venkatesh","role":"Leader","function":"Quality"},{"name":"K. Arun","role":"Member","function":"Production"},{"name":"M. Divya","role":"Member","function":"Engineering"},{"name":"S. Priya","role":"Member","function":"Maintenance"}]},
        "d2":{"requirement":"Bore 42.000 +0.025 / 0 mm, 100% gauged","deviation":"Bore measured 42.030 to 42.055 mm on 14 of 50 pieces checked","where":"Customer incoming inspection, lot L-2610-04","when":"First seen on the shipment of 12 days ago","who":"Customer incoming inspector","how_detected":"Air gauge at incoming inspection","how_many":"120 pieces in the lot, 14 found bad so far","repeat":false},
        "d3":{"not_required":false,"stock":[{"where":"Finished goods store","checked":300,"ng":6,"action":"Sorted 100% with air gauge"},{"where":"Customer plant","checked":120,"ng":14,"action":"Customer sorted, rejects returned"},{"where":"On the line (WIP)","checked":180,"ng":9,"action":"Sorted and scrapped"}],"result":"All stock sorted. Next three lots shipped with 100% bore gauging."},
        "d4":{"occurrence":{"category":"Machine","cause":"Boring tool wear compensation was not updated after the insert change; the tool offset drifted 0.04 mm.","verified":false,"method":""},"escape":{"category":"Measurement","cause":"","verified":false,"method":""},"systemic":{"cause":""}}}$j$::jsonb,
     $j${"is_not":[{"dim":"What","is":"Bore diameter DP-1101","is_not":"Outer diameter, thread","distinct":"Only the bored feature","change":"New boring insert fitted on machine T04"},{"dim":"Where","is":"Machine T04","is_not":"Machines T01, T02","distinct":"Only T04 was running this lot","change":"Offset sheet not updated"},{"dim":"When","is":"Second shift, lot L-2610-04","is_not":"First shift","distinct":"Shift after the insert change","change":"Insert changed at shift start"},{"dim":"How much","is":"14 of 50 sampled","is_not":"All pieces","distinct":"Increasing along the lot","change":"Tool wear over the lot"}],
        "whys":{"occurrence":["Bore oversize","Tool offset drifted","Offset not updated after insert change","No step for offset update in the changeover sheet","Changeover sheet not revised when the new insert was introduced"],"escape":[]},
        "fishbone":{"Man":["New operator on second shift"],"Machine":["Boring tool wear","Offset drift"],"Method":["Changeover sheet has no offset step"],"Material":[],"Measurement":["Sampling every 50 pieces too sparse"],"Environment":[]}}$j$::jsonb, true, me) returning id into r1;
  insert into console.d8_actions (customer_id, report_id, kind, seq, text, owner, due_on, status, done_on, evidence, sample, created_by) values
    (p_cid, r1, 'ICA', 1, 'Stop shipment of lot L-2610-04 and quarantine stock in the finished goods store', 'K. Arun', td - 5, 'done', td - 5, 'Quarantine tag photo', true, me),
    (p_cid, r1, 'ICA', 2, 'Sort 100% of stock and WIP with the air gauge', 'K. Arun', td - 4, 'done', td - 4, 'Sorting record SR-1048', true, me),
    (p_cid, r1, 'ICA', 3, 'Add 100% bore gauging on the next three lots', 'M. Divya', td - 4, 'done', td - 4, 'Control plan temporary change', true, me);
  insert into console.d8_log (customer_id, report_id, by, text, sample) values (p_cid, r1, me, '8D opened.', true), (p_cid, r1, me, 'D0 done.', true), (p_cid, r1, me, 'D1 done.', true), (p_cid, r1, me, 'D2 done.', true), (p_cid, r1, me, 'D3 done.', true);
  st4 := jsonb_build_object('D0', (td - 25)::text, 'D1', (td - 25)::text, 'D2', (td - 24)::text, 'D3', (td - 24)::text, 'D4', (td - 18)::text, 'D5', (td - 14)::text);
  insert into console.d8_reports (customer_id, no, title, source, complainant, part_no, part_name, lot_no, qty_affected, severity, opened_on, due_on, owner, steps, sections, sample, created_by) values
    (p_cid, console.d8_number(p_cid), 'Burr on locating pin found at final inspection', 'Internal rejection', 'Final inspection', 'DP-1105', 'Locating pin', 'L-2609-11', 340, 'Minor', td - 25, td - 2, me, st4,
     $j${"d0":{"symptom":"Burr on the cross hole of 340 locating pins found at final inspection.","era_needed":false,"era":""},
        "d1":{"leader":"K. Arun","champion":"Plant head","members":[{"name":"K. Arun","role":"Leader","function":"Production"},{"name":"S. Priya","role":"Member","function":"Quality"}]},
        "d2":{"requirement":"No burr on cross hole, edge break 0.1 to 0.3 mm","deviation":"Burr up to 0.4 mm at the cross hole exit","where":"Final inspection bench","when":"Lot L-2609-11","who":"Final inspector","how_detected":"Visual inspection with 5x magnifier","how_many":"340 of 2000 pieces","repeat":false},
        "d3":{"not_required":false,"stock":[{"where":"Final inspection","checked":2000,"ng":340,"action":"Reworked by hand deburring"}],"result":"All 340 reworked and re-inspected."},
        "d4":{"occurrence":{"category":"Method","cause":"Drill exit burr is not removed because the deburring operation was dropped from the routing after a layout change.","verified":true,"method":"Routing history checked and a trial lot run with and without the operation"},"escape":{"category":"Method","cause":"The control plan checks burr only once per shift on a sample of 5.","verified":true,"method":"Control plan reviewed, sample size compared with the reject rate"},"systemic":{"cause":"Routing changes are not reviewed against the control plan."}},
        "d5":{"options":[{"text":"Restore the deburring operation and add it to the routing","chosen":true,"verification":"Trial lot of 200 pieces, no burr"},{"text":"Change the drill to a through-coolant drill","chosen":false,"verification":"Not needed"}],"verification_summary":"Trial lot of 200 with the restored operation had no burr."},
        "d6":{"validation":{"method":"","result":"","date":"","ok":false},"ica_removed":{"done":false,"date":""},"monitoring":{"days":30,"until":""}},"d7":{"docs":[],"horizontal":"","lessons":""},"d8":{}}$j$::jsonb, true, me) returning id into r2;
  insert into console.d8_actions (customer_id, report_id, kind, seq, text, owner, due_on, status, done_on, evidence, sample, created_by) values
    (p_cid, r2, 'ICA', 1, 'Hand deburr and re-inspect all 340 pieces', 'K. Arun', td - 24, 'done', td - 24, 'Rework record', true, me),
    (p_cid, r2, 'PCA', 1, 'Restore the deburring operation in the routing and the work instruction', 'K. Arun', td - 10, 'done', td - 9, 'Routing rev D', true, me),
    (p_cid, r2, 'PCA', 2, 'Raise the burr check in the control plan to every hour, sample of 5', 'S. Priya', td - 3, 'open', null, null, true, me);
  insert into console.d8_log (customer_id, report_id, by, text, sample) values (p_cid, r2, me, '8D opened.', true), (p_cid, r2, me, 'D3 done.', true), (p_cid, r2, me, 'D4 done.', true), (p_cid, r2, me, 'D5 done.', true);
  st9 := jsonb_build_object('D0', (td - 60)::text, 'D1', (td - 60)::text, 'D2', (td - 59)::text, 'D3', (td - 59)::text, 'D4', (td - 52)::text, 'D5', (td - 48)::text, 'D6', (td - 40)::text, 'D7', (td - 37)::text, 'D8', (td - 35)::text);
  insert into console.d8_reports (customer_id, no, title, source, complainant, complaint_ref, part_no, part_name, lot_no, qty_affected, severity, opened_on, due_on, owner, status, steps, closed_on, closed_by, sections, sample, created_by) values
    (p_cid, console.d8_number(p_cid), 'Thread damage on gear housing caused a line stoppage', 'Customer complaint', 'Southern Auto Components', 'SAC-CMP-044', 'DP-1103', 'Gear housing', 'L-2608-02', 60, 'Critical', td - 60, td - 40, me, 'closed', st9, td - 35, me,
     $j${"d0":{"symptom":"Damaged M10 threads on 60 gear housings stopped the customer assembly line for two hours.","era_needed":true,"era":"Replacement lot air-freighted after 100% thread gauging."},
        "d1":{"leader":"R. Venkatesh","champion":"Managing director","members":[{"name":"R. Venkatesh","role":"Leader","function":"Quality"},{"name":"K. Arun","role":"Member","function":"Production"},{"name":"M. Divya","role":"Member","function":"Engineering"}]},
        "d2":{"requirement":"M10x1.5-6H thread, go / no-go gauge on 100%","deviation":"Threads torn at the start of the thread on 60 pieces","where":"Customer assembly line","when":"Lot L-2608-02","who":"Assembly operator","how_detected":"Bolt would not run in","how_many":"60 of 800","repeat":false},
        "d3":{"not_required":false,"stock":[{"where":"Customer plant","checked":800,"ng":60,"action":"Sorted by customer, replaced"},{"where":"Our stock","checked":1200,"ng":0,"action":"100% thread gauging"}],"result":"No further bad pieces found."},
        "d4":{"occurrence":{"category":"Machine","cause":"A worn tap was used past its life because tap life is not counted by the machine.","verified":true,"method":"Tap examined under a microscope, life records checked"},"escape":{"category":"Measurement","cause":"The thread gauge check was done on the first piece of the shift only.","verified":true,"method":"Control plan and check sheets reviewed"},"systemic":{"cause":"Tool life is not part of the standard for taps."}},
        "d5":{"options":[{"text":"Change taps at fixed counts and gauge every 25 pieces","chosen":true,"verification":"Three trial lots"}],"verification_summary":"Three trial lots with no thread defect."},
        "d6":{"validation":{"method":"Three consecutive lots checked at the customer","result":"No thread defect in 2400 pieces over three lots.","date":"","ok":true},"ica_removed":{"done":true,"date":""},"monitoring":{"days":60,"until":""}},
        "d7":{"docs":[{"name":"PFMEA","done":true,"ref":"Rev C"},{"name":"Control Plan","done":true,"ref":"Rev F"},{"name":"Work instruction","done":true,"ref":"WI-31 Rev B"}],"horizontal":"Same tap-life rule applied to the other tapped parts on machines T02 and T04.","lessons":"Count tool life on every threading tool, not only on drills."},
        "d8":{"recognition":"Team thanked at the monthly quality meeting.","customer_accepted":true,"customer_ref":"SAC-CMP-044 closed","note":""}}$j$::jsonb, true, me) returning id into r3;
  insert into console.d8_actions (customer_id, report_id, kind, seq, text, owner, due_on, status, done_on, evidence, verified, verified_on, sample, created_by) values
    (p_cid, r3, 'ICA', 1, '100% thread gauging of stock and replacement lot', 'K. Arun', td - 58, 'done', td - 58, 'Gauging record', false, null, true, me),
    (p_cid, r3, 'PCA', 1, 'Change taps at a fixed count; add tap-life counter to the machine program', 'M. Divya', td - 44, 'done', td - 45, 'Program rev 3', true, td - 36, true, me),
    (p_cid, r3, 'PCA', 2, 'Gauge threads every 25 pieces and record on the check sheet', 'S. Priya', td - 44, 'done', td - 44, 'Check sheet CS-12', true, td - 36, true, me),
    (p_cid, r3, 'PREVENT', 1, 'Apply the tap-life rule to all tapped parts', 'R. Venkatesh', td - 38, 'done', td - 38, 'Tool life list', false, null, true, me);
  insert into console.d8_log (customer_id, report_id, by, text, sample, at) values (p_cid, r3, me, '8D opened.', true, now() - interval '60 days'), (p_cid, r3, me, 'D8 done: the 8D is closed.', true, now() - interval '35 days');
  n := 3 + 10;
  return n;
end $$;
revoke all on function console.d8_sample(uuid, text) from public, anon, authenticated;

do $$ declare f record; begin
  for f in select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname ~ '^kmr_d8_' loop
    execute format('revoke all on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
end $$;
