-- ---------- the public calls (access: the "mmd" role from Administration › Users & access; changing data needs editor or admin) ----------
create or replace function public.kmr_mmd_load(p_slug text) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'mmd');
begin
  return jsonb_build_object(
    'parts', coalesce((select jsonb_agg(jsonb_build_object('code', r.code, 'name', r.name) || r.data order by r.code) from console.ops_records r where r.customer_id = cid and r.kind = 'parts' and r.active), '[]'),
    'materials', coalesce((select jsonb_agg(jsonb_build_object('code', r.code, 'name', r.name) || r.data order by r.code) from console.ops_records r where r.customer_id = cid and r.kind = 'raw_materials' and r.active), '[]'),
    'suppliers', coalesce((select jsonb_agg(jsonb_build_object('code', r.code, 'name', r.name) || r.data order by r.code) from console.ops_records r where r.customer_id = cid and r.kind = 'suppliers' and r.active), '[]'),
    'machines', coalesce((select jsonb_agg(jsonb_build_object('code', r.code, 'name', r.name) || r.data order by r.code) from console.ops_records r where r.customer_id = cid and r.kind = 'machines' and r.active), '[]'),
    'loss_codes', coalesce((select jsonb_agg(jsonb_build_object('code', r.code, 'name', r.name) || r.data order by r.code) from console.ops_records r where r.customer_id = cid and r.kind = 'loss_codes' and r.active), '[]'),
    'defect_codes', coalesce((select jsonb_agg(jsonb_build_object('code', r.code, 'name', r.name) || r.data order by r.code) from console.ops_records r where r.customer_id = cid and r.kind = 'defect_codes' and r.active), '[]'),
    'shifts', coalesce((select jsonb_agg(jsonb_build_object('code', r.code, 'name', r.name) || r.data order by r.code) from console.ops_records r where r.customer_id = cid and r.kind = 'shifts' and r.active), '[]'),
    'bom', coalesce((select jsonb_agg(jsonb_build_object('code', r.code) || r.data order by r.code) from console.ops_records r where r.customer_id = cid and r.kind = 'bom' and r.active), '[]'),
    'routes', coalesce((select jsonb_object_agg(r.code, console.mmd_route(cid, r.code)) from console.ops_records r where r.customer_id = cid and r.kind = 'parts' and r.active), '{}'),
    'plant', (select r.data from console.ops_records r where r.customer_id = cid and r.kind = 'plant_standards' and r.active order by r.code limit 1),
    'has_rmp', exists (select 1 from console.licences where customer_id = cid and product_code = 'rmp'),
    'today', (now() at time zone 'Asia/Kolkata')::date, 'now', now());
end $$;

-- everything that happened lately: route sheets, open tags (where the material lies), DCs, entries, losses
create or replace function public.kmr_mmd_data(p_slug text, p_days int default 30) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'mmd'); since timestamptz := now() - make_interval(days => greatest(1, least(coalesce(p_days, 30), 400)));
begin
  return jsonb_build_object(
    'rs', coalesce((select jsonb_agg(x order by x.created_at desc) from (
        select s.id, s.rs_no, s.part_code, s.part_name, s.customer_name, s.qty, s.status, s.due_date, s.created_at, s.heat_code, s.rm_material, s.rm_kg, jsonb_array_length(s.ops) ops_n,
               coalesce((select sum(t.bal) from console.mmd_tags t where t.rs_id = s.id and t.status = 'open' and t.loc in ('op', 'rework')), 0) wip_qty,
               coalesce((select sum(d.qty - d.received_qty) from console.mmd_dcs d where d.rs_id = s.id and d.status in ('open', 'part')), 0) supplier_qty,
               coalesce((select sum(t.qty) from console.mmd_tags t where t.rs_id = s.id and t.loc in ('fg', 'dispatched') and t.status <> 'void'), 0) fg_qty,
               coalesce((select sum(q.qty) from console.mmd_defects q where q.rs_id = s.id and q.kind = 'rej' and not q.void), 0) rej_qty,
               coalesce((select sum(t.bal) from console.mmd_tags t where t.rs_id = s.id and t.kind = 'REW' and t.status = 'open'), 0) rew_open
          from console.mmd_route_sheets s where s.customer_id = cid and (s.status = 'open' or s.created_at >= since)) x), '[]'),
    'tags', coalesce((select jsonb_agg(x order by x.created_at) from (
        select t.id, t.tag_no, t.kind, t.loc, t.seq, t.qty, t.bal, t.status, t.created_at, t.reason, t.reason_code, t.spec, t.actual, t.dispo, s.rs_no, s.part_code, s.part_name, s.customer_name, s.due_date, s.ops -> (t.seq - 1) ->> 'name' op_name,
               s.ops -> (t.seq - 1) ->> 'machine' machine, s.ops -> (t.seq - 1) ->> 'type' op_type, jsonb_array_length(s.ops) ops_n
          from console.mmd_tags t join console.mmd_route_sheets s on s.id = t.rs_id
         where t.customer_id = cid and t.status <> 'void' and ((t.status = 'open' and t.bal > 0) or t.created_at >= since or (t.kind = 'REJ' and t.dispo is null))) x), '[]'),
    'dcs', coalesce((select jsonb_agg(x order by x.dispatch_at desc) from (
        select d.id, d.dc_no, d.qty, d.received_qty, d.status, d.dispatch_at, d.expected_date, d.supplier_code, d.supplier_name, d.op_name, d.vehicle, s.rs_no, s.part_code, s.part_name, s.customer_name
          from console.mmd_dcs d join console.mmd_route_sheets s on s.id = d.rs_id where d.customer_id = cid and (d.status in ('open', 'part') or d.dispatch_at >= since)) x), '[]'),
    'entries', coalesce((select jsonb_agg(x order by x.entry_at desc) from (
        select e.id, e.kind, e.seq, e.op_name, e.machine, nullif(s.ops -> (e.seq - 1) ->> 'ct_sec', '')::numeric ct_sec, e.ok_qty, e.rej_qty, e.rew_qty, e.entry_at, e.shift, e.operator, e.engineer, e.note, e.status, e.void_reason, s.rs_no, s.part_code, s.part_name,
               (select string_agg(t.tag_no, ', ' order by t.tag_no) from console.mmd_tags t where t.entry_id = e.id) out_tags
          from console.mmd_entries e join console.mmd_route_sheets s on s.id = e.rs_id where e.customer_id = cid and e.entry_at >= since order by e.entry_at desc limit 600) x), '[]'),
    'defects', coalesce((select jsonb_agg(to_jsonb(q) - 'customer_id' order by q.entry_at desc) from console.mmd_defects q where q.customer_id = cid and q.entry_at >= since and not q.void), '[]'),
    'loss', coalesce((select jsonb_agg(to_jsonb(l) - 'customer_id' order by l.loss_date desc, l.created_at desc) from console.mmd_loss l where l.customer_id = cid and l.loss_date >= (since at time zone 'Asia/Kolkata')::date and l.status = 'ok'), '[]'),
    'today', (now() at time zone 'Asia/Kolkata')::date, 'now', now());
end $$;

create or replace function public.kmr_mmd_tag(p_slug text, p_no text) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'mmd'); tg uuid; no text := upper(trim(coalesce(p_no, '')));
begin
  select id into tg from console.mmd_tags where customer_id = cid and tag_no = no;
  if tg is null then raise exception 'No tag with the number “%”.', coalesce(p_no, ''); end if;
  return console.mmd_tag_json(cid, tg);
end $$;

create or replace function public.kmr_mmd_dc_get(p_slug text, p_no text) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'mmd'); d console.mmd_dcs%rowtype;
begin
  select * into d from console.mmd_dcs where customer_id = cid and dc_no = upper(trim(coalesce(p_no, '')));
  if not found then raise exception 'No DC with the number “%”.', coalesce(p_no, ''); end if;
  return jsonb_build_object('dc', to_jsonb(d) - 'customer_id', 'rs', (select to_jsonb(s) - 'customer_id' from console.mmd_route_sheets s where s.id = d.rs_id), 'progress', console.mmd_progress(d.rs_id),
    'grns', coalesce((select jsonb_agg(to_jsonb(g) - 'customer_id' order by g.received_at) from console.mmd_grns g where g.dc_id = d.id and g.ok_qty + g.rej_qty > 0), '[]'));
end $$;

create or replace function public.kmr_mmd_issue(p_slug text, p jsonb) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'mmd'); r jsonb;
begin
  r := console.mmd_issue(cid, lower(coalesce(auth.jwt() ->> 'email', '')), p);
  return console.mmd_tag_json(cid, (r ->> 'tag_id')::uuid);
end $$;
create or replace function public.kmr_mmd_entry(p_slug text, p jsonb) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'mmd');
begin return console.mmd_entry(cid, lower(coalesce(auth.jwt() ->> 'email', '')), p); end $$;
create or replace function public.kmr_mmd_rework(p_slug text, p jsonb) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'mmd');
begin return console.mmd_rework(cid, lower(coalesce(auth.jwt() ->> 'email', '')), p); end $$;
create or replace function public.kmr_mmd_dc_create(p_slug text, p jsonb) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'mmd');
begin perform console.require_feature(p_slug, 'mmd', 'mmd.supplier-dc-grn'); return console.mmd_dc(cid, lower(coalesce(auth.jwt() ->> 'email', '')), p); end $$;
create or replace function public.kmr_mmd_grn(p_slug text, p jsonb) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'mmd');
begin perform console.require_feature(p_slug, 'mmd', 'mmd.supplier-dc-grn'); return console.mmd_grn(cid, lower(coalesce(auth.jwt() ->> 'email', '')), p); end $$;
create or replace function public.kmr_mmd_dispatch(p_slug text, p jsonb) returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'mmd');
begin perform console.mmd_dispatch(cid, lower(coalesce(auth.jwt() ->> 'email', '')), p); end $$;
create or replace function public.kmr_mmd_dispose(p_slug text, p_tag text, p_action text, p_note text) returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'mmd');
begin perform console.mmd_dispose(cid, lower(coalesce(auth.jwt() ->> 'email', '')), p_tag, p_action, p_note); end $$;
create or replace function public.kmr_mmd_void(p_slug text, p_entry uuid, p_reason text) returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'mmd');
begin perform console.mmd_void(cid, lower(coalesce(auth.jwt() ->> 'email', '')), p_entry, p_reason); end $$;
create or replace function public.kmr_mmd_rs_cancel(p_slug text, p_rs uuid, p_reason text) returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'mmd');
begin
  if coalesce(trim(p_reason), '') = '' then raise exception 'Give the reason for cancelling the route sheet.'; end if;
  if exists (select 1 from console.mmd_entries where rs_id = p_rs and customer_id = cid and status = 'ok') then raise exception 'Entries exist on this route sheet — void them first, or let it run to completion.'; end if;
  update console.mmd_route_sheets set status = 'cancelled', notes = coalesce(notes || E'\n', '') || 'Cancelled: ' || trim(p_reason), closed_at = now() where id = p_rs and customer_id = cid;
  update console.mmd_tags set status = 'void', bal = 0 where rs_id = p_rs and customer_id = cid;
end $$;

-- loss hours against a D code
create or replace function public.kmr_mmd_loss_save(p_slug text, p jsonb) returns uuid language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'mmd'); dn text; v_id uuid; mc text := trim(coalesce(p ->> 'machine_code', '')); dc text := trim(coalesce(p ->> 'd_code', '')); m numeric := nullif(p ->> 'minutes', '')::numeric;
begin
  perform console.require_feature(p_slug, 'mmd', 'mmd.loss-hours-d-codes');
  if mc = '' then raise exception 'Choose the machine.'; end if;
  select name into dn from console.ops_records where customer_id = cid and kind = 'loss_codes' and code = dc;
  if dn is null then raise exception 'Choose a loss code (Operations Master › Loss codes).'; end if;
  if m is null or m <= 0 or m > 1440 then raise exception 'Enter the loss in minutes (1–1440).'; end if;
  insert into console.mmd_loss (customer_id, loss_date, shift, machine_code, d_code, d_name, minutes, rs_id, part_code, op_name, remark, operator, created_by)
  values (cid, coalesce(nullif(p ->> 'loss_date', '')::date, (now() at time zone 'Asia/Kolkata')::date), nullif(p ->> 'shift', ''), mc, dc, dn, m, nullif(p ->> 'rs_id', '')::uuid, nullif(p ->> 'part_code', ''), nullif(p ->> 'op_name', ''),
          nullif(p ->> 'remark', ''), nullif(p ->> 'operator', ''), lower(coalesce(auth.jwt() ->> 'email', ''))) returning mmd_loss.id into v_id;
  return v_id;
end $$;
create or replace function public.kmr_mmd_loss_void(p_slug text, p_id uuid, p_reason text) returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'mmd');
begin
  perform console.require_feature(p_slug, 'mmd', 'mmd.loss-hours-d-codes');
  if coalesce(trim(p_reason), '') = '' then raise exception 'Give the reason for voiding the entry.'; end if;
  if exists (select 1 from console.mmd_loss where id = p_id and customer_id = cid and ref is not null) then raise exception 'This loss came from a Maintenance breakdown — void the breakdown in the Maintenance app.'; end if;
  update console.mmd_loss set status = 'void', void_reason = trim(p_reason) where id = p_id and customer_id = cid;
end $$;

-- traceability: heat code, route sheet, tag, DC or part → the whole chain
create or replace function public.kmr_mmd_trace(p_slug text, p_q text) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'mmd'); q text := upper(trim(coalesce(p_q, ''))); ids uuid[];
begin
  perform console.require_feature(p_slug, 'mmd', 'mmd.traceability-iatf-records');
  if q = '' then raise exception 'Enter a heat code, route sheet, tag, DC or part number.'; end if;
  select array_agg(distinct id) into ids from (
    select s.id from console.mmd_route_sheets s where s.customer_id = cid and (upper(s.rs_no) = q or upper(s.heat_code) = q or upper(s.part_code) = q or upper(coalesce(s.mill_cert, '')) = q)
    union select t.rs_id from console.mmd_tags t where t.customer_id = cid and upper(t.tag_no) = q
    union select d.rs_id from console.mmd_dcs d where d.customer_id = cid and upper(d.dc_no) = q
    union select g.rs_id from console.mmd_grns g where g.customer_id = cid and upper(g.grn_no) = q) x limit 12;
  if ids is null then raise exception 'Nothing found for “%”.', p_q; end if;
  return jsonb_build_object('rs', coalesce((select jsonb_agg(jsonb_build_object('rs', to_jsonb(s) - 'customer_id', 'progress', console.mmd_progress(s.id),
      'tags', (select coalesce(jsonb_agg(to_jsonb(t) - 'customer_id' order by t.created_at, t.tag_no), '[]') from console.mmd_tags t where t.rs_id = s.id),
      'entries', (select coalesce(jsonb_agg(to_jsonb(e) - 'customer_id' order by e.entry_at), '[]') from console.mmd_entries e where e.rs_id = s.id),
      'dcs', (select coalesce(jsonb_agg(to_jsonb(d) - 'customer_id' order by d.dispatch_at), '[]') from console.mmd_dcs d where d.rs_id = s.id),
      'grns', (select coalesce(jsonb_agg(to_jsonb(g) - 'customer_id' order by g.received_at), '[]') from console.mmd_grns g where g.rs_id = s.id)) order by s.created_at desc)
    from console.mmd_route_sheets s where s.id = any (ids)), '[]'));
end $$;
