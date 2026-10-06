-- ---------- numbering and the route ----------
create or replace function console.mmd_next(p_cid uuid, p_key text) returns bigint language sql security definer set search_path = console, public as $$
  insert into console.mmd_counters (customer_id, key, n) values (p_cid, p_key, 1)
  on conflict (customer_id, key) do update set n = console.mmd_counters.n + 1 returning n $$;
revoke all on function console.mmd_next(uuid, text) from public, anon, authenticated;

-- the process sequence of a part: the Process Documents process plan when the part has one (operation number, in-house or outsourced, machine);
-- otherwise the Operations Master cycle-time records ordered by their "op_no" field or the number at the end of the name (e.g. "Turning OP10")
create or replace function console.mmd_route(p_cid uuid, p_part text) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare pd_org uuid; out jsonb := '[]';
begin
  select product_ref into pd_org from console.licences where customer_id = p_cid and product_code = 'pd' and product_ref is not null limit 1;
  if pd_org is not null and to_regclass('public.pd_projects') is not null then
    select coalesce(jsonb_agg(jsonb_build_object('seq', y.rn, 'op_no', y.opn, 'name', y.nm, 'machine', y.mc, 'type', y.ty, 'supplier', null,
              'ct_sec', (select nullif(r.data ->> 'cycle_time_sec', '')::numeric from console.ops_records r where r.customer_id = p_cid and r.kind = 'cycle_times' and r.data ->> 'part_no' = p_part and lower(r.name) = lower(y.nm) limit 1)) order by y.rn), '[]'::jsonb) into out
      from (select row_number() over (order by x.opn nulls last, x.ord) rn, x.* from (
              select o.ord, o.v ->> 'name' nm, nullif(regexp_replace(coalesce(o.v ->> 'opNo', ''), '[^0-9.]', '', 'g'), '')::numeric opn, coalesce(o.v ->> 'machine', '') mc,
                     case when coalesce(o.v ->> 'inHouse', 'true') in ('false', 'f', '0') then 'supplier' else 'in' end ty
                from (select p.doc from public.pd_projects p where p.org_id = pd_org and p.part_no = p_part order by p.updated_at desc limit 1) pj,
                     jsonb_array_elements(coalesce(pj.doc -> 'plan' -> 'ops', '[]'::jsonb)) with ordinality o(v, ord)) x) y;
    if jsonb_array_length(out) > 0 then return out; end if;
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('seq', y.rn, 'op_no', y.opn, 'name', y.nm, 'machine', coalesce(y.mc, ''), 'type', y.ty, 'supplier', y.sp, 'ct_sec', y.ct) order by y.rn), '[]'::jsonb) into out
    from (select row_number() over (order by x.opn nulls last, x.code) rn, x.* from (
            select r.code, r.name nm, r.data ->> 'machine' mc,
                   case when coalesce(r.data ->> 'op_type', '') ilike 'supplier%' then 'supplier' else 'in' end ty, nullif(r.data ->> 'supplier', '') sp,
                   nullif(r.data ->> 'cycle_time_sec', '')::numeric ct,
                   coalesce(nullif(regexp_replace(coalesce(r.data ->> 'op_no', ''), '[^0-9.]', '', 'g'), '')::numeric, nullif((regexp_match(r.name, '(\d+)\s*$'))[1], '')::numeric) opn
              from console.ops_records r where r.customer_id = p_cid and r.kind = 'cycle_times' and r.active and r.data ->> 'part_no' = p_part) x) y;
  return out;
end $$;
revoke all on function console.mmd_route(uuid, text) from public, anon, authenticated;

create or replace function console.mmd_new_tag(p_cid uuid, p_me text, p_rs uuid, p_kind text, p_seq int, p_loc text, p_qty numeric, p_parent uuid, p_entry uuid, p_op_done int, p_at timestamptz, p_x jsonb default '{}')
returns uuid language plpgsql security definer set search_path = console, public as $$
declare v_id uuid; v_no text; yymm text := to_char(p_at at time zone 'Asia/Kolkata', 'YYMM');
begin
  v_no := 'TG-' || yymm || '-' || lpad(console.mmd_next(p_cid, 'TG-' || yymm)::text, 5, '0');
  insert into console.mmd_tags (customer_id, tag_no, rs_id, kind, seq, loc, qty, bal, parent_tag, entry_id, op_done, reason_code, reason, spec, actual, sample, created_by, created_at)
  values (p_cid, v_no, p_rs, p_kind, p_seq, p_loc, p_qty, p_qty, p_parent, p_entry, p_op_done, p_x ->> 'reason_code', p_x ->> 'reason', p_x ->> 'spec', p_x ->> 'actual', coalesce((p_x ->> 'sample')::boolean, false), p_me, p_at)
  returning id into v_id;
  return v_id;
end $$;
revoke all on function console.mmd_new_tag(uuid, text, uuid, text, int, text, numeric, uuid, uuid, int, timestamptz, jsonb) from public, anon, authenticated;

-- per operation: route sheet qty, arrived, OK, rejected, sent to rework, waiting, at supplier
create or replace function console.mmd_progress(p_rs uuid) returns jsonb language sql stable security definer set search_path = console, public as $$
  select coalesce(jsonb_agg(jsonb_build_object('seq', (o.value ->> 'seq')::int, 'op_no', o.value -> 'op_no', 'name', o.value ->> 'name', 'machine', o.value ->> 'machine', 'type', o.value ->> 'type', 'supplier', o.value ->> 'supplier',
      'rs_qty', rs.qty,
      'arrived', coalesce((select sum(t.qty) from console.mmd_tags t where t.rs_id = rs.id and t.seq = (o.value ->> 'seq')::int and t.kind in ('RM', 'OK') and t.status <> 'void'), 0),
      'ok', coalesce((select sum(e.ok_qty) from console.mmd_entries e where e.rs_id = rs.id and e.seq = (o.value ->> 'seq')::int and e.status = 'ok' and e.kind in ('process', 'rework', 'grn')), 0),
      'rej', coalesce((select sum(e.rej_qty) from console.mmd_entries e where e.rs_id = rs.id and e.seq = (o.value ->> 'seq')::int and e.status = 'ok' and e.kind in ('process', 'rework', 'grn')), 0),
      'rew', coalesce((select sum(e.rew_qty) from console.mmd_entries e where e.rs_id = rs.id and e.seq = (o.value ->> 'seq')::int and e.status = 'ok' and e.kind = 'process'), 0),
      'rew_open', coalesce((select sum(t.bal) from console.mmd_tags t where t.rs_id = rs.id and t.seq = (o.value ->> 'seq')::int and t.kind = 'REW' and t.status = 'open'), 0),
      'waiting', coalesce((select sum(t.bal) from console.mmd_tags t where t.rs_id = rs.id and t.seq = (o.value ->> 'seq')::int and t.kind in ('RM', 'OK') and t.status = 'open'), 0),
      'at_supplier', coalesce((select sum(d.qty - d.received_qty) from console.mmd_dcs d where d.rs_id = rs.id and d.seq = (o.value ->> 'seq')::int and d.status in ('open', 'part')), 0)
    ) order by (o.value ->> 'seq')::int), '[]'::jsonb)
  from console.mmd_route_sheets rs, jsonb_array_elements(rs.ops) o where rs.id = p_rs $$;
revoke all on function console.mmd_progress(uuid) from public, anon, authenticated;

create or replace function console.mmd_tag_json(p_cid uuid, p_tag uuid) returns jsonb language sql stable security definer set search_path = console, public as $$
  select jsonb_build_object('tag', to_jsonb(t) - 'customer_id', 'rs', to_jsonb(rs) - 'customer_id', 'progress', console.mmd_progress(rs.id),
      'op', case when t.seq is not null then rs.ops -> (t.seq - 1) end, 'parent', (select p.tag_no from console.mmd_tags p where p.id = t.parent_tag),
      'entry', (select to_jsonb(e) - 'customer_id' from console.mmd_entries e where e.id = t.entry_id))
    from console.mmd_tags t join console.mmd_route_sheets rs on rs.id = t.rs_id where t.id = p_tag and t.customer_id = p_cid $$;
revoke all on function console.mmd_tag_json(uuid, uuid) from public, anon, authenticated;

-- a route sheet is closed when nothing of it is waiting at a process, in rework or at a supplier
create or replace function console.mmd_rs_check(p_rs uuid) returns void language plpgsql security definer set search_path = console, public as $$
declare busy boolean;
begin
  select exists (select 1 from console.mmd_tags where rs_id = p_rs and status = 'open' and bal > 0 and loc in ('op', 'rework', 'supplier'))
      or exists (select 1 from console.mmd_dcs where rs_id = p_rs and status in ('open', 'part')) into busy;
  update console.mmd_route_sheets set status = case when busy then 'open' else 'closed' end, closed_at = case when busy then null else coalesce(closed_at, now()) end
   where id = p_rs and status <> 'cancelled';
end $$;
revoke all on function console.mmd_rs_check(uuid) from public, anon, authenticated;

-- ---------- RM issue: route sheet + RM tag ----------
create or replace function console.mmd_issue(p_cid uuid, p_me text, p jsonb, p_at timestamptz default now(), p_sample boolean default false) returns jsonb
language plpgsql security definer set search_path = console, public as $$
declare pc text := trim(coalesce(p ->> 'part_code', '')); mc text := trim(coalesce(p ->> 'material_code', '')); part record; mat record; route jsonb; qty numeric := nullif(p ->> 'qty', '')::numeric;
        kgs numeric := nullif(p ->> 'rm_kg', '')::numeric; heat text := trim(coalesce(p ->> 'heat_code', '')); rs uuid; rsno text; tg uuid; cust text; yymm text := to_char(p_at at time zone 'Asia/Kolkata', 'YYMM'); bk numeric; fin numeric;
begin
  select * into part from console.ops_records where customer_id = p_cid and kind = 'parts' and code = pc and active;
  if not found then raise exception 'Part % is not in Operations Master › Parts.', pc; end if;
  if qty is null or qty <= 0 then raise exception 'Enter the quantity to be produced.'; end if;
  if mc = '' then mc := coalesce(part.data ->> 'material', ''); end if;
  select * into mat from console.ops_records where customer_id = p_cid and kind = 'raw_materials' and code = mc;
  if not found then raise exception 'Choose the raw material (Operations Master › Raw material).'; end if;
  if heat = '' then raise exception 'Enter the heat / lot code of the material (from the mill test certificate).'; end if;
  route := console.mmd_route(p_cid, pc);
  if jsonb_array_length(route) = 0 then raise exception 'Part % has no operations. Add its routing in Operations Master › Cycle times.', pc; end if;
  if kgs is null then
    select nullif(data ->> 'blank_kg', '')::numeric into bk from console.ops_records where customer_id = p_cid and kind = 'bom' and code = pc || '/' || mc and active;
    fin := nullif(part.data ->> 'weight_kg', '')::numeric;
    if coalesce(bk, fin) is not null then kgs := round(coalesce(bk, fin) * qty, 3); end if;
  end if;
  select name into cust from console.ops_records where customer_id = p_cid and kind = 'customers' and code = part.data ->> 'customer';
  rsno := 'RS-' || yymm || '-' || lpad(console.mmd_next(p_cid, 'RS-' || yymm)::text, 4, '0');
  insert into console.mmd_route_sheets (customer_id, rs_no, part_code, part_name, customer_name, qty, ops, rm_material, rm_spec, rm_size, heat_code, rm_kg, mill_cert, due_date, notes, sample, created_by, created_at)
  values (p_cid, rsno, pc, part.name, coalesce(cust, part.data ->> 'customer'), qty, route, mc, trim(both ' ·' from coalesce(mat.data ->> 'grade', '') || ' · ' || coalesce(mat.data ->> 'specification', '')), mat.data ->> 'size', heat, kgs,
          nullif(p ->> 'mill_cert', ''), nullif(p ->> 'due_date', '')::date, nullif(p ->> 'notes', ''), p_sample, p_me, p_at) returning id into rs;
  tg := console.mmd_new_tag(p_cid, p_me, rs, 'RM', 1, 'op', qty, null, null, 0, p_at, jsonb_build_object('sample', p_sample));
  -- the Raw Material Planning stock goes down by what was issued
  if kgs > 0 and not p_sample and exists (select 1 from console.licences where customer_id = p_cid and product_code = 'rmp') then
    update console.rmp_stock set on_hand_kg = greatest(0, on_hand_kg - kgs), updated_at = now(), updated_by = p_me where customer_id = p_cid and material_code = mc;
  end if;
  return jsonb_build_object('rs_id', rs, 'rs_no', rsno, 'tag_id', tg);
end $$;
revoke all on function console.mmd_issue(uuid, text, jsonb, timestamptz, boolean) from public, anon, authenticated;

-- ---------- the rejection / rework lines of an entry → defect rows + one tag per line ----------
create or replace function console.mmd_lines(p_cid uuid, p_me text, p_entry uuid, p_rs uuid, p_src uuid, p_kind text, p_lines jsonb, p_seq int, p_at timestamptz, p_part text, p_op text, p_machine text, p_operator text, p_sample boolean)
returns numeric language plpgsql security definer set search_path = console, public as $$
declare l jsonb; q numeric; tot numeric := 0; rc text; rn text; sp text; ac text; tg uuid; d uuid;
begin
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' then return 0; end if;
  for l in select * from jsonb_array_elements(p_lines) loop
    q := coalesce(nullif(l ->> 'qty', '')::numeric, 0); continue when q <= 0;
    rc := nullif(trim(coalesce(l ->> 'code', '')), '');
    rn := coalesce(nullif(trim(coalesce(l ->> 'reason', '')), ''), (select r.name from console.ops_records r where r.customer_id = p_cid and r.kind = 'defect_codes' and r.code = rc));
    sp := nullif(trim(coalesce(l ->> 'spec', '')), ''); ac := nullif(trim(coalesce(l ->> 'actual', '')), '');
    if rn is null then raise exception 'Choose the reason for every % line.', case when p_kind = 'rej' then 'rejection' else 'rework' end; end if;
    if sp is null or ac is null then raise exception 'Enter the specification and the actual value for % (%).', rn, case when p_kind = 'rej' then 'rejection' else 'rework' end; end if;
    tg := console.mmd_new_tag(p_cid, p_me, p_rs, case when p_kind = 'rej' then 'REJ' else 'REW' end, case when p_kind = 'rej' then null else p_seq end, case when p_kind = 'rej' then 'rejection' else 'rework' end,
                              q, p_src, p_entry, p_seq, p_at, jsonb_build_object('reason_code', rc, 'reason', rn, 'spec', sp, 'actual', ac, 'sample', p_sample));
    insert into console.mmd_defects (customer_id, entry_id, rs_id, tag_id, kind, reason_code, reason, qty, spec, actual, part_code, op_name, machine, operator, entry_at, sample)
    values (p_cid, p_entry, p_rs, tg, p_kind, rc, rn, q, sp, ac, p_part, p_op, p_machine, p_operator, p_at, p_sample);
    tot := tot + q;
  end loop;
  return tot;
end $$;
revoke all on function console.mmd_lines(uuid, text, uuid, uuid, uuid, text, jsonb, int, timestamptz, text, text, text, text, boolean) from public, anon, authenticated;

-- ---------- stage entry: scan the OK / RM tag of the previous process, enter this process ----------
create or replace function console.mmd_entry(p_cid uuid, p_me text, p jsonb, p_sample boolean default false) returns jsonb
language plpgsql security definer set search_path = console, public as $$
declare t console.mmd_tags%rowtype; rs console.mmd_route_sheets%rowtype; op jsonb; n int; ok numeric := greatest(0, coalesce(nullif(p ->> 'ok', '')::numeric, 0)); rej numeric; rew numeric; ent uuid; at timestamptz := coalesce(nullif(p ->> 'entry_at', '')::timestamptz, now());
        mach text; oper text := nullif(trim(coalesce(p ->> 'operator', '')), ''); outs jsonb := '[]'; okt uuid; nseq int;
begin
  select * into t from console.mmd_tags where customer_id = p_cid and tag_no = upper(trim(coalesce(p ->> 'tag_no', ''))) for update;
  if not found then raise exception 'Tag % was not found.', coalesce(p ->> 'tag_no', ''); end if;
  if t.status <> 'open' or t.bal <= 0 then raise exception 'Tag % has no quantity left.', t.tag_no; end if;
  if t.kind not in ('RM', 'OK') or t.loc <> 'op' then raise exception 'Scan the RM or OK tag of the previous process — a % tag cannot be processed here.', t.kind; end if;
  select * into rs from console.mmd_route_sheets where id = t.rs_id;
  if rs.status = 'cancelled' then raise exception 'Route sheet % is cancelled.', rs.rs_no; end if;
  n := jsonb_array_length(rs.ops); op := rs.ops -> (t.seq - 1);
  if op ->> 'type' = 'supplier' then raise exception '“%” is a supplier process — issue a delivery challan (DC) instead.', op ->> 'name'; end if;
  mach := coalesce(nullif(trim(coalesce(p ->> 'machine', '')), ''), nullif(op ->> 'machine', ''));
  if mach is null then raise exception 'Enter the machine.'; end if;
  if oper is null then raise exception 'Enter the operator name.'; end if;
  rej := coalesce((select sum(coalesce(nullif(x ->> 'qty', '')::numeric, 0)) from jsonb_array_elements(coalesce(p -> 'rej_lines', '[]')) x), 0);
  rew := coalesce((select sum(coalesce(nullif(x ->> 'qty', '')::numeric, 0)) from jsonb_array_elements(coalesce(p -> 'rew_lines', '[]')) x), 0);
  if ok + rej + rew <= 0 then raise exception 'Enter the OK, rejection or rework quantity.'; end if;
  if ok + rej + rew > t.bal then raise exception 'Only % pcs are left on tag %.', t.bal, t.tag_no; end if;
  insert into console.mmd_entries (customer_id, rs_id, tag_id, kind, seq, op_name, machine, ok_qty, rej_qty, rew_qty, entry_at, shift, operator, engineer, note, sample, created_by)
  values (p_cid, rs.id, t.id, 'process', t.seq, op ->> 'name', mach, ok, rej, rew, at, nullif(p ->> 'shift', ''), oper, coalesce(nullif(p ->> 'engineer', ''), p_me), nullif(p ->> 'note', ''), p_sample, p_me) returning id into ent;
  update console.mmd_tags set bal = bal - (ok + rej + rew), status = case when bal - (ok + rej + rew) <= 0 then 'used' else 'open' end where id = t.id;
  nseq := t.seq + 1;
  if ok > 0 then
    okt := console.mmd_new_tag(p_cid, p_me, rs.id, 'OK', case when nseq > n then null else nseq end, case when nseq > n then 'fg' else 'op' end, ok, t.id, ent, t.seq, at, jsonb_build_object('sample', p_sample));
    outs := outs || to_jsonb(okt);
  end if;
  perform console.mmd_lines(p_cid, p_me, ent, rs.id, t.id, 'rej', p -> 'rej_lines', t.seq, at, rs.part_code, op ->> 'name', mach, oper, p_sample);
  perform console.mmd_lines(p_cid, p_me, ent, rs.id, t.id, 'rew', p -> 'rew_lines', t.seq, at, rs.part_code, op ->> 'name', mach, oper, p_sample);
  perform console.mmd_rs_check(rs.id);
  return jsonb_build_object('entry_id', ent, 'tags', coalesce((select jsonb_agg(console.mmd_tag_json(p_cid, x.id) order by x.created_at, x.tag_no) from console.mmd_tags x where x.entry_id = ent), '[]'));
end $$;
revoke all on function console.mmd_entry(uuid, text, jsonb, boolean) from public, anon, authenticated;

-- ---------- rework result: scan the REW tag, enter how many came out good / were rejected ----------
create or replace function console.mmd_rework(p_cid uuid, p_me text, p jsonb, p_sample boolean default false) returns jsonb
language plpgsql security definer set search_path = console, public as $$
declare t console.mmd_tags%rowtype; rs console.mmd_route_sheets%rowtype; op jsonb; n int; ok numeric := greatest(0, coalesce(nullif(p ->> 'ok', '')::numeric, 0)); rej numeric; ent uuid; at timestamptz := coalesce(nullif(p ->> 'entry_at', '')::timestamptz, now());
        mach text; oper text := nullif(trim(coalesce(p ->> 'operator', '')), ''); nseq int;
begin
  select * into t from console.mmd_tags where customer_id = p_cid and tag_no = upper(trim(coalesce(p ->> 'tag_no', ''))) for update;
  if not found then raise exception 'Tag % was not found.', coalesce(p ->> 'tag_no', ''); end if;
  if t.kind <> 'REW' or t.status <> 'open' or t.bal <= 0 then raise exception 'Tag % is not an open rework tag.', t.tag_no; end if;
  select * into rs from console.mmd_route_sheets where id = t.rs_id;
  n := jsonb_array_length(rs.ops); op := rs.ops -> (t.seq - 1);
  mach := coalesce(nullif(trim(coalesce(p ->> 'machine', '')), ''), nullif(op ->> 'machine', ''), 'Rework bench');
  if oper is null then raise exception 'Enter the operator name.'; end if;
  rej := coalesce((select sum(coalesce(nullif(x ->> 'qty', '')::numeric, 0)) from jsonb_array_elements(coalesce(p -> 'rej_lines', '[]')) x), 0);
  if ok + rej <= 0 then raise exception 'Enter the OK or rejected quantity after rework.'; end if;
  if ok + rej > t.bal then raise exception 'Only % pcs are left on tag %.', t.bal, t.tag_no; end if;
  insert into console.mmd_entries (customer_id, rs_id, tag_id, kind, seq, op_name, machine, ok_qty, rej_qty, entry_at, shift, operator, engineer, note, sample, created_by)
  values (p_cid, rs.id, t.id, 'rework', t.seq, op ->> 'name', mach, ok, rej, at, nullif(p ->> 'shift', ''), oper, coalesce(nullif(p ->> 'engineer', ''), p_me), nullif(p ->> 'note', ''), p_sample, p_me) returning id into ent;
  update console.mmd_tags set bal = bal - (ok + rej), status = case when bal - (ok + rej) <= 0 then 'used' else 'open' end where id = t.id;
  nseq := t.seq + 1;
  if ok > 0 then perform console.mmd_new_tag(p_cid, p_me, rs.id, 'OK', case when nseq > n then null else nseq end, case when nseq > n then 'fg' else 'op' end, ok, t.id, ent, t.seq, at, jsonb_build_object('sample', p_sample)); end if;
  perform console.mmd_lines(p_cid, p_me, ent, rs.id, t.id, 'rej', p -> 'rej_lines', t.seq, at, rs.part_code, op ->> 'name', mach, oper, p_sample);
  perform console.mmd_rs_check(rs.id);
  return jsonb_build_object('entry_id', ent, 'tags', coalesce((select jsonb_agg(console.mmd_tag_json(p_cid, x.id) order by x.created_at, x.tag_no) from console.mmd_tags x where x.entry_id = ent), '[]'));
end $$;
revoke all on function console.mmd_rework(uuid, text, jsonb, boolean) from public, anon, authenticated;

-- ---------- supplier process: delivery challan (DC) and goods receipt (GRN) ----------
create or replace function console.mmd_dc(p_cid uuid, p_me text, p jsonb, p_sample boolean default false) returns jsonb
language plpgsql security definer set search_path = console, public as $$
declare t console.mmd_tags%rowtype; rs console.mmd_route_sheets%rowtype; op jsonb; q numeric := coalesce(nullif(p ->> 'qty', '')::numeric, 0); at timestamptz := coalesce(nullif(p ->> 'entry_at', '')::timestamptz, now());
        sup text; supn text; dc uuid; dcno text; yymm text; ent uuid;
begin
  select * into t from console.mmd_tags where customer_id = p_cid and tag_no = upper(trim(coalesce(p ->> 'tag_no', ''))) for update;
  if not found then raise exception 'Tag % was not found.', coalesce(p ->> 'tag_no', ''); end if;
  if t.status <> 'open' or t.bal <= 0 or t.kind not in ('RM', 'OK') or t.loc <> 'op' then raise exception 'Tag % cannot be sent to a supplier.', t.tag_no; end if;
  select * into rs from console.mmd_route_sheets where id = t.rs_id; op := rs.ops -> (t.seq - 1);
  if op ->> 'type' <> 'supplier' then raise exception '“%” is done in-house — enter it as a stage entry.', op ->> 'name'; end if;
  if q <= 0 or q > t.bal then raise exception 'Enter a quantity up to % pcs.', t.bal; end if;
  sup := coalesce(nullif(trim(coalesce(p ->> 'supplier_code', '')), ''), nullif(op ->> 'supplier', ''));
  if sup is null then raise exception 'Choose the supplier for “%”.', op ->> 'name'; end if;
  select name into supn from console.ops_records where customer_id = p_cid and kind = 'suppliers' and code = sup;
  yymm := to_char(at at time zone 'Asia/Kolkata', 'YYMM'); dcno := 'DC-' || yymm || '-' || lpad(console.mmd_next(p_cid, 'DC-' || yymm)::text, 4, '0');
  insert into console.mmd_dcs (customer_id, dc_no, rs_id, tag_id, seq, op_name, supplier_code, supplier_name, qty, vehicle, dispatch_at, expected_date, note, sample, created_by, created_at)
  values (p_cid, dcno, rs.id, t.id, t.seq, op ->> 'name', sup, supn, q, nullif(p ->> 'vehicle', ''), at, nullif(p ->> 'expected_date', '')::date, nullif(p ->> 'note', ''), p_sample, p_me, at) returning id into dc;
  insert into console.mmd_entries (customer_id, rs_id, tag_id, dc_id, kind, seq, op_name, machine, entry_at, shift, operator, engineer, note, sample, created_by)
  values (p_cid, rs.id, t.id, dc, 'dc', t.seq, op ->> 'name', coalesce(supn, sup), at, nullif(p ->> 'shift', ''), nullif(p ->> 'operator', ''), coalesce(nullif(p ->> 'engineer', ''), p_me), nullif(p ->> 'note', ''), p_sample, p_me) returning id into ent;
  update console.mmd_tags set bal = bal - q, status = case when bal - q <= 0 then 'used' else 'open' end where id = t.id;
  perform console.mmd_rs_check(rs.id);
  return jsonb_build_object('dc_id', dc, 'dc_no', dcno);
end $$;
revoke all on function console.mmd_dc(uuid, text, jsonb, boolean) from public, anon, authenticated;

create or replace function console.mmd_grn(p_cid uuid, p_me text, p jsonb, p_sample boolean default false) returns jsonb
language plpgsql security definer set search_path = console, public as $$
declare d console.mmd_dcs%rowtype; rs console.mmd_route_sheets%rowtype; n int; ok numeric := greatest(0, coalesce(nullif(p ->> 'ok', '')::numeric, 0)); rej numeric; at timestamptz := coalesce(nullif(p ->> 'entry_at', '')::timestamptz, now());
        ent uuid; grn uuid; grno text; yymm text; nseq int; src uuid;
begin
  select * into d from console.mmd_dcs where customer_id = p_cid and dc_no = upper(trim(coalesce(p ->> 'dc_no', ''))) for update;
  if not found then raise exception 'DC % was not found.', coalesce(p ->> 'dc_no', ''); end if;
  if d.status not in ('open', 'part') then raise exception 'DC % is already %.', d.dc_no, d.status; end if;
  select * into rs from console.mmd_route_sheets where id = d.rs_id; n := jsonb_array_length(rs.ops);
  rej := coalesce((select sum(coalesce(nullif(x ->> 'qty', '')::numeric, 0)) from jsonb_array_elements(coalesce(p -> 'rej_lines', '[]')) x), 0);
  if ok + rej <= 0 then raise exception 'Enter the quantity received.'; end if;
  if ok + rej > d.qty - d.received_qty then raise exception 'Only % pcs are pending on DC %.', d.qty - d.received_qty, d.dc_no; end if;
  insert into console.mmd_entries (customer_id, rs_id, tag_id, dc_id, kind, seq, op_name, machine, ok_qty, rej_qty, entry_at, shift, operator, engineer, note, sample, created_by)
  values (p_cid, rs.id, d.tag_id, d.id, 'grn', d.seq, d.op_name, coalesce(d.supplier_name, d.supplier_code), ok, rej, at, nullif(p ->> 'shift', ''), nullif(p ->> 'operator', ''), coalesce(nullif(p ->> 'engineer', ''), p_me), nullif(p ->> 'note', ''), p_sample, p_me) returning id into ent;
  yymm := to_char(at at time zone 'Asia/Kolkata', 'YYMM'); grno := 'GRN-' || yymm || '-' || lpad(console.mmd_next(p_cid, 'GRN-' || yymm)::text, 4, '0');
  insert into console.mmd_grns (customer_id, grn_no, dc_id, rs_id, entry_id, ok_qty, rej_qty, inv_no, received_at, note, sample, created_by, created_at)
  values (p_cid, grno, d.id, rs.id, ent, ok, rej, nullif(p ->> 'inv_no', ''), at, nullif(p ->> 'note', ''), p_sample, p_me, at) returning id into grn;
  update console.mmd_dcs set received_qty = received_qty + ok + rej, status = case when received_qty + ok + rej >= qty then 'closed' else 'part' end where id = d.id;
  nseq := d.seq + 1;
  if ok > 0 then perform console.mmd_new_tag(p_cid, p_me, rs.id, 'OK', case when nseq > n then null else nseq end, case when nseq > n then 'fg' else 'op' end, ok, d.tag_id, ent, d.seq, at, jsonb_build_object('sample', p_sample)); end if;
  perform console.mmd_lines(p_cid, p_me, ent, rs.id, d.tag_id, 'rej', p -> 'rej_lines', d.seq, at, rs.part_code, d.op_name, coalesce(d.supplier_name, d.supplier_code), coalesce(d.supplier_name, d.supplier_code), p_sample);
  perform console.mmd_rs_check(rs.id);
  return jsonb_build_object('grn_id', grn, 'grn_no', grno, 'entry_id', ent, 'tags', coalesce((select jsonb_agg(console.mmd_tag_json(p_cid, x.id) order by x.created_at, x.tag_no) from console.mmd_tags x where x.entry_id = ent), '[]'));
end $$;
revoke all on function console.mmd_grn(uuid, text, jsonb, boolean) from public, anon, authenticated;

-- ---------- finished goods dispatch, rejection disposition, voiding a wrong entry ----------
create or replace function console.mmd_dispatch(p_cid uuid, p_me text, p jsonb) returns void language plpgsql security definer set search_path = console, public as $$
declare t console.mmd_tags%rowtype; q numeric := coalesce(nullif(p ->> 'qty', '')::numeric, 0);
begin
  select * into t from console.mmd_tags where customer_id = p_cid and tag_no = upper(trim(coalesce(p ->> 'tag_no', ''))) for update;
  if not found or t.loc <> 'fg' or t.status <> 'open' then raise exception 'Tag % is not in finished goods.', coalesce(p ->> 'tag_no', ''); end if;
  if q <= 0 or q > t.bal then raise exception 'Enter a quantity up to % pcs.', t.bal; end if;
  insert into console.mmd_entries (customer_id, rs_id, tag_id, kind, ok_qty, entry_at, shift, operator, engineer, note, created_by)
  values (p_cid, t.rs_id, t.id, 'dispatch', q, coalesce(nullif(p ->> 'entry_at', '')::timestamptz, now()), nullif(p ->> 'shift', ''), nullif(p ->> 'operator', ''), coalesce(nullif(p ->> 'engineer', ''), p_me), nullif(p ->> 'ref', ''), p_me);
  update console.mmd_tags set bal = bal - q, status = case when bal - q <= 0 then 'used' else 'open' end, loc = case when bal - q <= 0 then 'dispatched' else loc end where id = t.id;
end $$;
revoke all on function console.mmd_dispatch(uuid, text, jsonb) from public, anon, authenticated;

create or replace function console.mmd_dispose(p_cid uuid, p_me text, p_tag text, p_action text, p_note text) returns void language plpgsql security definer set search_path = console, public as $$
declare t console.mmd_tags%rowtype;
begin
  if p_action not in ('Scrapped', 'Returned to supplier', 'Accepted under concession', 'Sorted / regraded') then raise exception 'Choose the disposition.'; end if;
  select * into t from console.mmd_tags where customer_id = p_cid and tag_no = upper(trim(coalesce(p_tag, ''))) for update;
  if not found or t.kind <> 'REJ' then raise exception 'Tag % is not a rejection tag.', coalesce(p_tag, ''); end if;
  if t.dispo is not null then raise exception 'Tag % already has a disposition (%).', t.tag_no, t.dispo; end if;
  if p_action = 'Accepted under concession' and coalesce(trim(p_note), '') = '' then raise exception 'A concession needs the customer / authority reference in the note.'; end if;
  update console.mmd_tags set dispo = p_action, dispo_by = p_me, dispo_at = now(), dispo_note = nullif(trim(coalesce(p_note, '')), ''), status = 'used', bal = 0, loc = 'closed' where id = t.id;
end $$;
revoke all on function console.mmd_dispose(uuid, text, text, text, text) from public, anon, authenticated;

create or replace function console.mmd_void(p_cid uuid, p_me text, p_entry uuid, p_reason text) returns void language plpgsql security definer set search_path = console, public as $$
declare e console.mmd_entries%rowtype; x record; tot numeric;
begin
  if coalesce(trim(p_reason), '') = '' then raise exception 'Give the reason for voiding the entry.'; end if;
  select * into e from console.mmd_entries where id = p_entry and customer_id = p_cid for update;
  if not found then raise exception 'Entry not found.'; end if;
  if e.status = 'void' then raise exception 'This entry is already void.'; end if;
  if e.kind = 'dispatch' then raise exception 'A dispatch cannot be voided here.'; end if;
  for x in select * from console.mmd_tags where entry_id = e.id loop
    if x.status <> 'open' or x.bal <> x.qty then raise exception 'Cannot void: pieces of tag % have already moved on or been dispositioned.', x.tag_no; end if;
  end loop;
  if e.kind = 'dc' and exists (select 1 from console.mmd_entries g where g.dc_id = e.dc_id and g.kind = 'grn' and g.status = 'ok') then raise exception 'Cannot void a DC that has receipts. Void the GRN first.'; end if;
  update console.mmd_tags set status = 'void', bal = 0 where entry_id = e.id;
  update console.mmd_defects set void = true where entry_id = e.id;
  update console.mmd_entries set status = 'void', void_reason = trim(p_reason), void_by = p_me, void_at = now() where id = e.id;
  tot := e.ok_qty + e.rej_qty + e.rew_qty;
  if e.kind in ('process', 'rework') then
    update console.mmd_tags set bal = bal + tot, status = 'open' where id = e.tag_id;
  elsif e.kind = 'grn' then
    update console.mmd_dcs set received_qty = greatest(0, received_qty - tot), status = case when received_qty - tot <= 0 then 'open' else 'part' end where id = e.dc_id;
    update console.mmd_grns set ok_qty = 0, rej_qty = 0 where entry_id = e.id;
  elsif e.kind = 'dc' then
    update console.mmd_dcs set status = 'cancelled' where id = e.dc_id;
    update console.mmd_tags set bal = bal + (select qty from console.mmd_dcs where id = e.dc_id), status = 'open' where id = e.tag_id;
  end if;
  perform console.mmd_rs_check(e.rs_id);
end $$;
revoke all on function console.mmd_void(uuid, text, uuid, text) from public, anon, authenticated;
