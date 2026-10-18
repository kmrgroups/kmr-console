-- ================= MSA Studies =================
create or replace function console.msa_next(p_cid uuid, p_key text) returns bigint language sql security definer set search_path = console, public as $$
  insert into console.msa_counters (customer_id, key, n) values (p_cid, p_key, 1)
  on conflict (customer_id, key) do update set n = console.msa_counters.n + 1 returning n $$;
create or replace function console.msa_me() returns text language sql stable as $$ select lower(coalesce(auth.jwt() ->> 'email', '')) $$;
create or replace function console.msa_feat(p_type text) returns text language sql immutable as $$
  select case p_type when 'grr' then 'msa.gage-r-r' when 'attribute' then 'msa.attribute-agreement' else 'msa.bias-linearity-stability' end $$;
create or replace function console.msa_num(p jsonb, k text) returns numeric language sql immutable as $$
  select case when coalesce(p ->> k, '') ~ '^\s*-?\d+(\.\d+)?([eE][-+]?\d+)?\s*$' then (p ->> k)::numeric else null end $$;
create or replace function console.msa_json(s console.msa_studies, p_full boolean) returns jsonb language sql stable security definer set search_path = console, public as $$
  select jsonb_build_object('id', s.id, 'no', s.no, 'type', s.type, 'title', s.title, 'gauge_id', s.gauge_id, 'gauge_name', s.gauge_name, 'characteristic', s.characteristic,
    'part_no', s.part_no, 'part_name', s.part_name, 'unit', s.unit, 'lsl', s.lsl, 'usl', s.usl, 'study_date', s.study_date, 'conducted_by', s.conducted_by,
    'decision', s.decision, 'status', s.status, 'finalised_by', s.finalised_by, 'finalised_at', s.finalised_at, 'notes', s.notes, 'sample', s.sample,
    'results', case when p_full then s.results else jsonb_build_object('headline', s.results ->> 'headline') end, 'updated_at', s.updated_at)
    || case when p_full then jsonb_build_object('config', s.config, 'data', s.data) else '{}'::jsonb end $$;
revoke all on function console.msa_next(uuid, text), console.msa_json(console.msa_studies, boolean), console.msa_feat(text), console.msa_num(jsonb, text) from public, anon, authenticated;

create or replace function public.kmr_msa_enabled(p_slug text) returns boolean language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  return cid is not null and console.qp_role(cid, 'msa') is not null;
end $$;

create or replace function public.kmr_msa_list(p_slug text, p jsonb default '{}') returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'msa'); q text := nullif(trim(coalesce(p ->> 'q', '')), '');
begin
  return coalesce((select jsonb_agg(console.msa_json(s, false) order by s.study_date desc nulls last, s.created_at desc) from console.msa_studies s
    where s.customer_id = cid and (nullif(p ->> 'type', '') is null or s.type = p ->> 'type') and (nullif(p ->> 'decision', '') is null or s.decision = p ->> 'decision')
      and (nullif(p ->> 'status', '') is null or s.status = p ->> 'status')
      and (q is null or s.no ilike '%' || q || '%' or coalesce(s.title, '') ilike '%' || q || '%' or coalesce(s.gauge_id, '') ilike '%' || q || '%' or coalesce(s.gauge_name, '') ilike '%' || q || '%'
           or coalesce(s.characteristic, '') ilike '%' || q || '%' or coalesce(s.part_no, '') ilike '%' || q || '%')), '[]');
end $$;

create or replace function public.kmr_msa_get(p_slug text, p_id uuid) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'msa'); s console.msa_studies;
begin
  select * into s from console.msa_studies where id = p_id and customer_id = cid;
  if s.id is null then raise exception 'Study not found.'; end if;
  return console.msa_json(s, true) || jsonb_build_object('can_edit', console.qp_role(cid, 'msa') in ('admin', 'editor'), 'is_admin', console.qp_role(cid, 'msa') = 'admin');
end $$;

create or replace function public.kmr_msa_save(p_slug text, p jsonb) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'msa'); me text := console.msa_me(); v_id uuid := nullif(p ->> 'id', '')::uuid; ty text := p ->> 'type'; s console.msa_studies; nno text; dec_ text := nullif(p ->> 'decision', '');
begin
  if v_id is null and ty is null then raise exception 'Choose the type of study.'; end if;
  if v_id is not null then select * into s from console.msa_studies where id = v_id and customer_id = cid; if s.id is null then raise exception 'Study not found.'; end if; ty := s.type; end if;
  if ty not in ('grr', 'bias', 'linearity', 'stability', 'attribute') then raise exception 'Choose the type of study.'; end if;
  perform console.require_feature(p_slug, 'msa', console.msa_feat(ty));
  if dec_ is not null and dec_ not in ('Acceptable', 'Conditional', 'Not acceptable') then dec_ := null; end if;
  if jsonb_typeof(coalesce(p -> 'data', '{}')) not in ('object', 'array') or length(coalesce(p ->> 'data', '')) > 2000000 then raise exception 'The readings are too large.'; end if;
  if v_id is null then
    nno := 'MSA-' || lpad(console.msa_next(cid, 'MSA')::text, 4, '0');
    insert into console.msa_studies (customer_id, no, type, title, gauge_id, gauge_name, characteristic, part_no, part_name, unit, lsl, usl, study_date, conducted_by, config, data, results, decision, notes, created_by)
    values (cid, nno, ty, nullif(trim(p ->> 'title'), ''), nullif(trim(p ->> 'gauge_id'), ''), nullif(trim(p ->> 'gauge_name'), ''), nullif(trim(p ->> 'characteristic'), ''), nullif(trim(p ->> 'part_no'), ''),
      nullif(trim(p ->> 'part_name'), ''), nullif(trim(p ->> 'unit'), ''), console.msa_num(p, 'lsl'), console.msa_num(p, 'usl'), coalesce(nullif(p ->> 'study_date', '')::date, (now() at time zone 'Asia/Kolkata')::date),
      nullif(trim(p ->> 'conducted_by'), ''), coalesce(p -> 'config', '{}'), coalesce(p -> 'data', '{}'), p -> 'results', dec_, nullif(trim(p ->> 'notes'), ''), me) returning * into s;
  else
    if s.status = 'final' then raise exception 'This study is final. Ask an administrator to reopen it.'; end if;
    update console.msa_studies set title = nullif(trim(p ->> 'title'), ''), gauge_id = nullif(trim(p ->> 'gauge_id'), ''), gauge_name = nullif(trim(p ->> 'gauge_name'), ''), characteristic = nullif(trim(p ->> 'characteristic'), ''),
      part_no = nullif(trim(p ->> 'part_no'), ''), part_name = nullif(trim(p ->> 'part_name'), ''), unit = nullif(trim(p ->> 'unit'), ''), lsl = console.msa_num(p, 'lsl'), usl = console.msa_num(p, 'usl'),
      study_date = coalesce(nullif(p ->> 'study_date', '')::date, study_date), conducted_by = nullif(trim(p ->> 'conducted_by'), ''), config = coalesce(p -> 'config', config), data = coalesce(p -> 'data', data),
      results = coalesce(p -> 'results', results), decision = dec_, notes = nullif(trim(p ->> 'notes'), ''), updated_at = now() where id = s.id returning * into s;
  end if;
  return console.msa_json(s, true);
end $$;

create or replace function public.kmr_msa_finalise(p_slug text, p_id uuid, p_final boolean default true) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'msa'); s console.msa_studies;
begin
  select * into s from console.msa_studies where id = p_id and customer_id = cid;
  if s.id is null then raise exception 'Study not found.'; end if;
  if p_final then
    if s.decision is null then raise exception 'Calculate the study and save it before finalising.'; end if;
    update console.msa_studies set status = 'final', finalised_by = console.msa_me(), finalised_at = now(), updated_at = now() where id = s.id returning * into s;
  else
    if console.qp_role(cid, 'msa') <> 'admin' then raise exception 'Only an administrator can reopen a final study.'; end if;
    update console.msa_studies set status = 'draft', finalised_by = null, finalised_at = null, updated_at = now() where id = s.id returning * into s;
  end if;
  return console.msa_json(s, false);
end $$;

create or replace function public.kmr_msa_delete(p_slug text, p_id uuid) returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'msa'); s console.msa_studies;
begin
  select * into s from console.msa_studies where id = p_id and customer_id = cid;
  if s.id is null then raise exception 'Study not found.'; end if;
  if s.status = 'final' and console.qp_role(cid, 'msa') <> 'admin' then raise exception 'Only an administrator can delete a final study.'; end if;
  delete from console.msa_studies where id = s.id;
end $$;

create or replace function public.kmr_msa_dashboard(p_slug text) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'msa');
begin
  return jsonb_build_object(
    'total', (select count(*) from console.msa_studies where customer_id = cid),
    'draft', (select count(*) from console.msa_studies where customer_id = cid and status = 'draft'),
    'by_decision', coalesce((select jsonb_object_agg(coalesce(decision, 'Not calculated'), c) from (select decision, count(*) c from console.msa_studies where customer_id = cid group by 1) x), '{}'),
    'by_type', coalesce((select jsonb_object_agg(type, c) from (select type, count(*) c from console.msa_studies where customer_id = cid group by 1) x), '{}'),
    'attention', coalesce((select jsonb_agg(console.msa_json(s, false) order by s.study_date desc) from (select * from console.msa_studies where customer_id = cid and decision = 'Not acceptable' order by study_date desc limit 8) s), '[]'),
    'recent', coalesce((select jsonb_agg(console.msa_json(s, false) order by s.study_date desc) from (select * from console.msa_studies where customer_id = cid order by study_date desc nulls last, created_at desc limit 8) s), '[]'));
end $$;

-- ================= SPC Charts =================
create or replace function console.spc_next(p_cid uuid, p_key text) returns bigint language sql security definer set search_path = console, public as $$
  insert into console.spc_counters (customer_id, key, n) values (p_cid, p_key, 1)
  on conflict (customer_id, key) do update set n = console.spc_counters.n + 1 returning n $$;
create or replace function console.spc_me() returns text language sql stable as $$ select lower(coalesce(auth.jwt() ->> 'email', '')) $$;
create or replace function console.spc_feat(p_type text) returns text language sql immutable as $$
  select case when p_type in ('p', 'np', 'c', 'u') then 'spc.attribute-charts' else 'spc.variable-charts' end $$;
create or replace function console.spc_json(c console.spc_charts, p_full boolean) returns jsonb language sql stable security definer set search_path = console, public as $$
  select jsonb_build_object('id', c.id, 'no', c.no, 'title', c.title, 'part_no', c.part_no, 'part_name', c.part_name, 'characteristic', c.characteristic, 'process', c.process, 'unit', c.unit,
    'chart_type', c.chart_type, 'subgroup_size', c.subgroup_size, 'lsl', c.lsl, 'usl', c.usl, 'target', c.target, 'status', c.status, 'summary', c.summary, 'sample', c.sample, 'updated_at', c.updated_at,
    'points', (select count(*) from console.spc_points x where x.chart_id = c.id), 'last_at', (select max(coalesce(x.taken_at, x.created_at)) from console.spc_points x where x.chart_id = c.id))
    || case when p_full then jsonb_build_object('rules', c.rules, 'frozen', c.frozen, 'limits_from', c.limits_from, 'notes', c.notes) else '{}'::jsonb end $$;
revoke all on function console.spc_next(uuid, text), console.spc_json(console.spc_charts, boolean), console.spc_feat(text) from public, anon, authenticated;

create or replace function public.kmr_spc_enabled(p_slug text) returns boolean language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  return cid is not null and console.qp_role(cid, 'spc') is not null;
end $$;

create or replace function public.kmr_spc_list(p_slug text, p jsonb default '{}') returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'spc'); q text := nullif(trim(coalesce(p ->> 'q', '')), '');
begin
  return coalesce((select jsonb_agg(console.spc_json(c, false) order by c.status, c.updated_at desc) from console.spc_charts c
    where c.customer_id = cid and (nullif(p ->> 'status', '') is null or c.status = p ->> 'status') and (nullif(p ->> 'chart_type', '') is null or c.chart_type = p ->> 'chart_type')
      and (q is null or c.no ilike '%' || q || '%' or c.title ilike '%' || q || '%' or coalesce(c.part_no, '') ilike '%' || q || '%' or coalesce(c.characteristic, '') ilike '%' || q || '%' or coalesce(c.process, '') ilike '%' || q || '%')), '[]');
end $$;

create or replace function public.kmr_spc_get(p_slug text, p_id uuid) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'spc'); c console.spc_charts;
begin
  select * into c from console.spc_charts where id = p_id and customer_id = cid;
  if c.id is null then raise exception 'Chart not found.'; end if;
  return console.spc_json(c, true) || jsonb_build_object('can_edit', console.qp_role(cid, 'spc') in ('admin', 'editor'),
    'rows', coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'seq', x.seq, 'label', x.label, 'taken_at', x.taken_at, 'vals', x.vals, 'note', x.note, 'cause', x.cause, 'action', x.action) order by x.seq)
                        from (select * from console.spc_points where chart_id = c.id order by seq limit 5000) x), '[]'));
end $$;

create or replace function public.kmr_spc_save(p_slug text, p jsonb) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'spc'); me text := console.spc_me(); v_id uuid := nullif(p ->> 'id', '')::uuid; c console.spc_charts; ty text := p ->> 'chart_type'; n int; nno text;
begin
  if v_id is not null then select * into c from console.spc_charts where id = v_id and customer_id = cid; if c.id is null then raise exception 'Chart not found.'; end if; ty := coalesce(ty, c.chart_type); end if;
  if ty not in ('xr', 'xs', 'imr', 'p', 'np', 'c', 'u') then raise exception 'Choose a chart type.'; end if;
  perform console.require_feature(p_slug, 'spc', console.spc_feat(ty));
  if nullif(trim(coalesce(p ->> 'title', '')), '') is null then raise exception 'Give the chart a title.'; end if;
  n := case when ty = 'imr' then 1 when ty in ('xr', 'xs') then least(25, greatest(2, coalesce(console.msa_num(p, 'subgroup_size'), 5)::int)) else greatest(1, least(25, coalesce(console.msa_num(p, 'subgroup_size'), 1)::int)) end;
  if v_id is null then
    nno := 'SPC-' || lpad(console.spc_next(cid, 'SPC')::text, 4, '0');
    insert into console.spc_charts (customer_id, no, title, part_no, part_name, characteristic, process, unit, chart_type, subgroup_size, lsl, usl, target, rules, frozen, limits_from, notes, created_by)
    values (cid, nno, trim(p ->> 'title'), nullif(trim(p ->> 'part_no'), ''), nullif(trim(p ->> 'part_name'), ''), nullif(trim(p ->> 'characteristic'), ''), nullif(trim(p ->> 'process'), ''), nullif(trim(p ->> 'unit'), ''),
      ty, n, console.msa_num(p, 'lsl'), console.msa_num(p, 'usl'), console.msa_num(p, 'target'), coalesce(p -> 'rules', '{"rules":[1,2,3],"run":7,"trend":7}'), p -> 'frozen', nullif(p ->> 'limits_from', '')::int, nullif(trim(p ->> 'notes'), ''), me) returning * into c;
  else
    if c.chart_type <> ty and exists (select 1 from console.spc_points where chart_id = c.id) then raise exception 'The chart type cannot change once readings are entered. Start a new chart.'; end if;
    update console.spc_charts set title = trim(p ->> 'title'), part_no = nullif(trim(p ->> 'part_no'), ''), part_name = nullif(trim(p ->> 'part_name'), ''), characteristic = nullif(trim(p ->> 'characteristic'), ''),
      process = nullif(trim(p ->> 'process'), ''), unit = nullif(trim(p ->> 'unit'), ''), chart_type = ty, subgroup_size = n, lsl = console.msa_num(p, 'lsl'), usl = console.msa_num(p, 'usl'), target = console.msa_num(p, 'target'),
      rules = coalesce(p -> 'rules', rules), frozen = case when p ? 'frozen' then p -> 'frozen' else frozen end, limits_from = case when p ? 'limits_from' then nullif(p ->> 'limits_from', '')::int else limits_from end,
      status = case when p ->> 'status' in ('active', 'closed') then p ->> 'status' else status end, notes = nullif(trim(p ->> 'notes'), ''), updated_at = now() where id = c.id returning * into c;
  end if;
  return console.spc_json(c, true);
end $$;

create or replace function public.kmr_spc_delete(p_slug text, p_id uuid) returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'spc');
begin
  delete from console.spc_charts where id = p_id and customer_id = cid;
  if not found then raise exception 'Chart not found.'; end if;
end $$;

-- add readings (one row for typing, many for paste); each row: {label, taken_at, vals:[...], note}
create or replace function public.kmr_spc_points_add(p_slug text, p_chart uuid, p_rows jsonb) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'spc'); c console.spc_charts; r jsonb; sq int; k int := 0; me text := console.spc_me();
begin
  select * into c from console.spc_charts where id = p_chart and customer_id = cid;
  if c.id is null then raise exception 'Chart not found.'; end if;
  if c.status = 'closed' then raise exception 'This chart is closed. Reopen it to add readings.'; end if;
  perform console.require_feature(p_slug, 'spc', console.spc_feat(c.chart_type));
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) = 0 then raise exception 'There are no readings to add.'; end if;
  if jsonb_array_length(p_rows) > 500 then raise exception 'Add at most 500 rows at a time.'; end if;
  select coalesce(max(seq), 0) into sq from console.spc_points where chart_id = c.id;
  if sq + jsonb_array_length(p_rows) > 5000 then raise exception 'A chart holds up to 5000 points. Start a new chart.'; end if;
  for r in select * from jsonb_array_elements(p_rows) loop
    if jsonb_typeof(r -> 'vals') <> 'array' or jsonb_array_length(r -> 'vals') = 0 then continue; end if;
    sq := sq + 1; k := k + 1;
    insert into console.spc_points (customer_id, chart_id, seq, label, taken_at, vals, note, created_by)
    values (cid, c.id, sq, nullif(trim(r ->> 'label'), ''), nullif(r ->> 'taken_at', '')::timestamptz, r -> 'vals', nullif(trim(r ->> 'note'), ''), me);
  end loop;
  update console.spc_charts set updated_at = now() where id = c.id;
  return jsonb_build_object('added', k);
end $$;

-- change one reading row, or just its cause / action note
create or replace function public.kmr_spc_point_save(p_slug text, p jsonb) returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'spc'); x console.spc_points; c console.spc_charts;
begin
  select * into x from console.spc_points where id = nullif(p ->> 'id', '')::uuid and customer_id = cid;
  if x.id is null then raise exception 'Reading not found.'; end if;
  select * into c from console.spc_charts where id = x.chart_id;
  if c.status = 'closed' then raise exception 'This chart is closed. Reopen it to change readings.'; end if;
  update console.spc_points set label = case when p ? 'label' then nullif(trim(p ->> 'label'), '') else label end,
    vals = case when jsonb_typeof(p -> 'vals') = 'array' and jsonb_array_length(p -> 'vals') > 0 then p -> 'vals' else vals end,
    note = case when p ? 'note' then nullif(trim(p ->> 'note'), '') else note end, cause = case when p ? 'cause' then nullif(trim(p ->> 'cause'), '') else cause end,
    action = case when p ? 'action' then nullif(trim(p ->> 'action'), '') else action end where id = x.id;
  update console.spc_charts set updated_at = now() where id = x.chart_id;
end $$;

create or replace function public.kmr_spc_point_delete(p_slug text, p_id uuid) returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'spc'); x console.spc_points; c console.spc_charts;
begin
  select * into x from console.spc_points where id = p_id and customer_id = cid;
  if x.id is null then raise exception 'Reading not found.'; end if;
  select * into c from console.spc_charts where id = x.chart_id;
  if c.status = 'closed' then raise exception 'This chart is closed. Reopen it to delete readings.'; end if;
  delete from console.spc_points where id = x.id;
  update console.spc_charts set updated_at = now() where id = x.chart_id;
end $$;

-- the screen stores the latest result so the register and dashboard can show it without recalculating
create or replace function public.kmr_spc_summary(p_slug text, p_chart uuid, p_summary jsonb) returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'spc');
begin
  if p_summary ? 'cap' then perform console.require_feature(p_slug, 'spc', 'spc.capability-analysis'); end if;
  update console.spc_charts set summary = p_summary where id = p_chart and customer_id = cid;
end $$;

create or replace function public.kmr_spc_dashboard(p_slug text) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'spc');
begin
  return jsonb_build_object(
    'charts', (select count(*) from console.spc_charts where customer_id = cid),
    'active', (select count(*) from console.spc_charts where customer_id = cid and status = 'active'),
    'signals', (select count(*) from console.spc_charts where customer_id = cid and status = 'active' and coalesce((summary ->> 'signals')::int, 0) > 0),
    'low_cpk', (select count(*) from console.spc_charts where customer_id = cid and status = 'active' and (summary ->> 'cpk') ~ '^-?\d' and (summary ->> 'cpk')::numeric < 1.33),
    'attention', coalesce((select jsonb_agg(console.spc_json(c, false) order by c.updated_at desc) from (select * from console.spc_charts where customer_id = cid and status = 'active'
        and (coalesce((summary ->> 'signals')::int, 0) > 0 or ((summary ->> 'cpk') ~ '^-?\d' and (summary ->> 'cpk')::numeric < 1.33)) order by updated_at desc limit 8) c), '[]'),
    'recent', coalesce((select jsonb_agg(console.spc_json(c, false) order by c.updated_at desc) from (select * from console.spc_charts where customer_id = cid order by updated_at desc limit 8) c), '[]'));
end $$;

-- ================= sample data =================
create or replace function console.msa_sample(p_cid uuid, p_action text) returns integer language plpgsql security definer set search_path = console, public as $$
declare n int := 0; k int; today date := (now() at time zone 'Asia/Kolkata')::date; r record; nno text;
begin
  if p_action = 'flush' then delete from console.msa_studies where customer_id = p_cid and sample; get diagnostics k = row_count; return k; end if;
  if exists (select 1 from console.msa_studies where customer_id = p_cid and sample) then return 0; end if;
  for r in select * from (values
    (1, 'grr', 'Bore gauge BG-12 — Gage R&R', 'BG-12', 'Dial bore gauge', 'Bore diameter', 'mm', 'Marco Silva', -20,
       '{"appraisers":["A","B","C"],"parts":10,"trials":3,"k":6,"tol":null}'::jsonb, '{"d":@@GRR_D@@}'::jsonb,
       '{"headline":"%GRR 26.7% · 5 distinct categories","pctGRR":26.68,"ndc":5,"EV":0.20188,"AV":0.22963,"GRR":0.30575}'::jsonb, 'Conditional'),
    (2, 'bias', 'Micrometer MC-04 — bias against master 6.000', 'MC-04', 'Outside micrometer 0-25', 'Shaft diameter', 'mm', 'Priya Nair', -12,
       '{"reference":6,"tol":0.1}'::jsonb, '{"readings":[5.998,6.002,6.001,5.999,6.000,6.003,5.998,6.001]}'::jsonb, '{"headline":"Bias 0.0003 mm · zero inside the 95% interval","bias":0.0003}'::jsonb, 'Acceptable'),
    (3, 'linearity', 'Height gauge HG-02 — linearity', 'HG-02', 'Digital height gauge', 'Height', 'mm', 'Ravi Kumar', -8,
       '{"processVariation":0.6}'::jsonb, '{"rows":[{"ref":2,"readings":[1.99,2.01,2.00,1.98,2.02]},{"ref":4,"readings":[3.97,3.99,3.98,3.97,3.99]},{"ref":6,"readings":[5.96,5.95,5.97,5.96,5.94]},{"ref":8,"readings":[7.93,7.94,7.92,7.94,7.93]},{"ref":10,"readings":[9.91,9.92,9.90,9.92,9.91]}]}'::jsonb,
       '{"headline":"Bias grows with size — linearity not acceptable"}'::jsonb, 'Not acceptable'),
    (4, 'attribute', 'Go / no-go gauge GN-07 — attribute agreement', 'GN-07', 'Thread plug gauge', 'Thread fit', null, 'Anil Shah', -4,
       '{"appraisers":["A","B","C"],"parts":10,"trials":2,"labels":["Reject","Accept"]}'::jsonb,
       '{"ref":[1,1,0,0,1,0,1,0,1,0],"d":[[[1,1],[1,1],[0,0],[0,0],[1,1],[0,0],[1,1],[0,0],[1,1],[0,0]],[[1,1],[1,1],[0,0],[1,0],[1,1],[0,0],[1,1],[0,0],[1,1],[0,0]],[[1,1],[1,1],[0,0],[0,0],[1,1],[0,0],[1,1],[0,0],[1,1],[0,0]]]}'::jsonb,
       '{"headline":"Effectiveness 95% to 100% · one miss in 10 checks of bad parts"}'::jsonb, 'Conditional'),
    (5, 'stability', 'Master check on CMM — weekly stability', 'CMM-01', 'Coordinate measuring machine', 'Master ring 25.000', 'mm', 'Marco Silva', -2,
       '{"reference":25,"subgroup":1}'::jsonb, '{"readings":[25.001,24.999,25.000,25.002,24.998,25.001,25.000,24.999,25.001,25.000,25.002,24.999,25.000,25.001,24.998,25.000]}'::jsonb,
       '{"headline":"In control — no signals over 16 weekly checks"}'::jsonb, 'Acceptable')) v(i, ty, ttl, gid, gname, ch, un, who, off, cfg, dat, res, dec)
  loop
    nno := 'MSA-' || lpad(console.msa_next(p_cid, 'MSA')::text, 4, '0');
    insert into console.msa_studies (customer_id, no, type, title, gauge_id, gauge_name, characteristic, unit, study_date, conducted_by, config, data, results, decision, status, sample, part_no, part_name)
    values (p_cid, nno, r.ty, r.ttl, r.gid, r.gname, r.ch, r.un, today + r.off, r.who, r.cfg, r.dat, r.res, r.dec, case when r.i in (1, 2) then 'final' else 'draft' end, true, 'KMR-' || (1000 + r.i), 'Sample part ' || r.i);
    n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function console.msa_sample(uuid, text) from public, anon, authenticated;

create or replace function console.spc_sample(p_cid uuid, p_action text) returns integer language plpgsql security definer set search_path = console, public as $$
declare n int := 0; k int; c1 uuid; c2 uuid; c3 uuid; i int; vals jsonb; today date := (now() at time zone 'Asia/Kolkata')::date;
begin
  if p_action = 'flush' then
    delete from console.spc_points where customer_id = p_cid and sample; get diagnostics k = row_count; n := n + k;
    delete from console.spc_charts where customer_id = p_cid and sample; get diagnostics k = row_count; return n + k;
  end if;
  if exists (select 1 from console.spc_charts where customer_id = p_cid and sample) then return 0; end if;
  -- 1: X-bar R, shaft diameter, 25 subgroups of 5; one point jumps out at subgroup 17
  insert into console.spc_charts (customer_id, no, title, part_no, part_name, characteristic, process, unit, chart_type, subgroup_size, lsl, usl, target, sample, summary)
  values (p_cid, 'SPC-' || lpad(console.spc_next(p_cid, 'SPC')::text, 4, '0'), 'Shaft diameter — turning', 'KMR-2001', 'Drive shaft', 'Diameter 20.00 ±0.10', 'CNC turning', 'mm', 'xr', 5, 19.90, 20.10, 20.00, true,
          '{"signals":1,"cpk":1.21,"cap":true,"headline":"1 point beyond the limit at subgroup 17"}') returning id into c1;
  for i in 1..25 loop
    select jsonb_agg(round((20.00 + 0.018 * ((('x' || substr(md5(i || '-' || g.j), 1, 6))::bit(24)::int % 2001) - 1000) / 1000.0 * 1.7 + case when i = 17 then 0.075 else 0 end)::numeric, 3) order by g.j) into vals from generate_series(1, 5) g(j);
    insert into console.spc_points (customer_id, chart_id, seq, label, taken_at, vals, cause, action, sample)
    values (p_cid, c1, i, 'S' || i, (today - (26 - i))::timestamptz + interval '9 hours', vals, case when i = 17 then 'Insert replaced mid-shift; first part after the change ran large' end, case when i = 17 then 'Offset corrected; next 5 parts checked' end, true);
  end loop;
  -- 2: I-MR, torque, 24 readings with a slow upward drift at the end
  insert into console.spc_charts (customer_id, no, title, part_no, part_name, characteristic, process, unit, chart_type, subgroup_size, lsl, usl, target, sample, summary)
  values (p_cid, 'SPC-' || lpad(console.spc_next(p_cid, 'SPC')::text, 4, '0'), 'Tightening torque — station 3', 'KMR-2002', 'Housing bolt', 'Torque 45 ±5', 'Assembly', 'Nm', 'imr', 1, 40, 50, 45, true,
          '{"signals":1,"cpk":1.52,"cap":true,"headline":"7 points rising at the end"}') returning id into c2;
  for i in 1..24 loop
    insert into console.spc_points (customer_id, chart_id, seq, label, taken_at, vals, sample)
    values (p_cid, c2, i, '#' || i, (today - (25 - i))::timestamptz + interval '10 hours',
            jsonb_build_array(round((45 + 0.9 * ((('x' || substr(md5('t' || i), 1, 6))::bit(24)::int % 2001) - 1000) / 1000.0 + case when i > 17 then (i - 17) * 0.35 else 0 end)::numeric, 2)), true);
  end loop;
  -- 3: p chart, daily rejection, 20 days
  insert into console.spc_charts (customer_id, no, title, part_no, part_name, characteristic, process, unit, chart_type, subgroup_size, sample, summary)
  values (p_cid, 'SPC-' || lpad(console.spc_next(p_cid, 'SPC')::text, 4, '0'), 'Final inspection — daily rejection', 'KMR-2003', 'Cover plate', 'Rejected parts', 'Final inspection', null, 'p', 1, true,
          '{"signals":0,"headline":"In control — average 3.1% rejected"}') returning id into c3;
  for i in 1..20 loop
    insert into console.spc_points (customer_id, chart_id, seq, label, taken_at, vals, sample)
    values (p_cid, c3, i, 'D' || i, (today - (21 - i))::timestamptz + interval '17 hours',
            jsonb_build_array(2 + (('x' || substr(md5('p' || i), 1, 4))::bit(16)::int % 5), 100 + (('x' || substr(md5('n' || i), 1, 4))::bit(16)::int % 21)), true);
  end loop;
  return 3 + 25 + 24 + 20;
end $$;
revoke all on function console.spc_sample(uuid, text) from public, anon, authenticated;
