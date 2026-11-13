-- Match Sales Flow part codes to the BOM ignoring spaces, dashes and case; list Sales Flow parts that have no BOM entry.
-- ---------- one call = everything the Monthly plan screen needs (one entry per plant) ----------
create or replace function public.kmr_rmp_month(p_slug text, p_month text) returns jsonb
language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'rmp'); m0 date; pl record; out jsonb := '[]'; isco boolean;
begin
  if p_month !~ '^\d{4}-(0[1-9]|1[0-2])$' then raise exception 'Month must look like 2026-11.'; end if;
  m0 := (p_month || '-01')::date;
  isco := exists (select 1 from console.customers where parent_id = cid);
  for pl in select id, name, coalesce(plant_code, '') code from console.customers where (parent_id = cid) or (id = cid and not isco) order by plant_code nulls first, name loop
    out := out || jsonb_build_array(jsonb_build_object('id', pl.id, 'name', pl.name, 'code', pl.code,
      'lines', coalesce((select jsonb_agg(jsonb_build_object(
          'part_code', b.part_code, 'part_name', coalesce(pr.name, ''), 'material_code', b.material_code,
          'factor', round(coalesce(b.rm_kg, case when coalesce(pr.data ->> 'weight_kg', '') ~ '^[0-9]+(\.[0-9]+)?$' then (pr.data ->> 'weight_kg')::numeric end, 0) * (1 + b.loss_pct / 100), 6),
          'sales', sa.q, 'buyers', sa.buyers, 'despatched', coalesce(de.q, 0),
          'safety', coalesce(ps.safety_qty, 0), 'rrs', coalesce(ps.rrs_qty, 0), 'wip', coalesce(ps.wip_qty, 0), 'wip2', coalesce(ps.wip2_qty, 0), 'manual', ps.sched_manual, 'note', ps.note)
          order by b.part_code, b.material_code)
        from console.rmp_bom b
        left join console.ops_records pr on pr.customer_id = pl.id and pr.kind = 'parts' and pr.code = b.part_code
        left join lateral (select sum(l.demand_qty) q, string_agg(distinct nullif(l.buyer_name, ''), ', ') buyers from console.sf_lines l
                            where l.customer_id = pl.id and l.month = m0 and upper(regexp_replace(l.part_code, '[^A-Za-z0-9]', '', 'g')) = upper(regexp_replace(b.part_code, '[^A-Za-z0-9]', '', 'g'))) sa on true
        left join lateral (select sum(d.qty) q from console.sf_despatch d join console.sf_lines l on l.id = d.line_id
                            where l.customer_id = pl.id and l.month = m0 and upper(regexp_replace(l.part_code, '[^A-Za-z0-9]', '', 'g')) = upper(regexp_replace(b.part_code, '[^A-Za-z0-9]', '', 'g'))
                              and d.day <= (now() at time zone 'Asia/Kolkata')::date) de on true
        left join console.rmp_partstock ps on ps.customer_id = pl.id and ps.month = p_month and ps.part_code = b.part_code
        where b.customer_id = pl.id), '[]'),
      'unmatched', coalesce((select jsonb_agg(jsonb_build_object('part_code', x.pc, 'qty', x.q) order by x.pc) from (select max(l.part_code) pc, sum(l.demand_qty) q from console.sf_lines l where l.customer_id = pl.id and l.month = m0
          and not exists (select 1 from console.rmp_bom b where b.customer_id = pl.id and upper(regexp_replace(b.part_code, '[^A-Za-z0-9]', '', 'g')) = upper(regexp_replace(l.part_code, '[^A-Za-z0-9]', '', 'g')))
          group by upper(regexp_replace(l.part_code, '[^A-Za-z0-9]', '', 'g'))) x), '[]'),
      'materials', coalesce((select jsonb_agg(jsonb_build_object(
          'code', mc.code, 'name', coalesce(o.name, ''), 'on_hand', coalesce(s.on_hand_kg, 0), 'rate', coalesce(s.rate, case when coalesce(o.data ->> 'rate_per_kg', '') ~ '^[0-9]+(\.[0-9]+)?$' then (o.data ->> 'rate_per_kg')::numeric end),
          'gst', coalesce(s.gst_pct, 18), 'unit', coalesce(s.unit, 'kg'), 'supplier', coalesce(nullif(s.supplier_text, ''), o.data ->> 'supplier', ''), 'spec', coalesce(s.spec_text, ''),
          'weeks', coalesce((select jsonb_agg(jsonb_build_object('w', w.week, 'p', w.planned_qty, 'r', w.received_qty) order by w.week)
                               from console.rmp_plan_week w where w.customer_id = pl.id and w.month = p_month and w.material_code = mc.code), '[]'))
          order by mc.code)
        from (select material_code code from console.rmp_bom where customer_id = pl.id
              union select material_code from console.rmp_stock where customer_id = pl.id
              union select material_code from console.rmp_plan_week where customer_id = pl.id and month = p_month) mc
        left join console.rmp_stock s on s.customer_id = pl.id and s.material_code = mc.code
        left join console.ops_records o on o.customer_id = pl.id and o.kind = 'raw_materials' and o.code = mc.code), '[]')));
  end loop;
  return jsonb_build_object('month', p_month, 'company', isco, 'plants', out, 'today', (now() at time zone 'Asia/Kolkata')::date);
end $$;
grant execute on function public.kmr_rmp_month(text, text) to authenticated;

-- ---------- entries (the in-charge types; only the fields sent are changed) ----------
create or replace function public.kmr_rmp_partstock_save(p_slug text, p_month text, p_rows jsonb) returns integer
language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'rmp'); r jsonb; n int := 0; ex record; me text := lower(coalesce(auth.jwt() ->> 'email', ''));
begin
  if p_month !~ '^\d{4}-(0[1-9]|1[0-2])$' then raise exception 'Month must look like 2026-11.'; end if;
  for r in select * from jsonb_array_elements(coalesce(p_rows, '[]')) loop
    if coalesce(trim(r ->> 'part_code'), '') = '' then continue; end if;
    select * into ex from console.rmp_partstock where customer_id = cid and month = p_month and part_code = trim(r ->> 'part_code');
    insert into console.rmp_partstock (customer_id, month, part_code, safety_qty, rrs_qty, wip_qty, wip2_qty, sched_manual, note, updated_by)
    values (cid, p_month, trim(r ->> 'part_code'),
      greatest(0, coalesce(case when r ? 'safety_qty' then nullif(r ->> 'safety_qty', '')::numeric else ex.safety_qty end, 0)),
      greatest(0, coalesce(case when r ? 'rrs_qty' then nullif(r ->> 'rrs_qty', '')::numeric else ex.rrs_qty end, 0)),
      greatest(0, coalesce(case when r ? 'wip_qty' then nullif(r ->> 'wip_qty', '')::numeric else ex.wip_qty end, 0)),
      greatest(0, coalesce(case when r ? 'wip2_qty' then nullif(r ->> 'wip2_qty', '')::numeric else ex.wip2_qty end, 0)),
      case when r ? 'sched_manual' then nullif(r ->> 'sched_manual', '')::numeric else ex.sched_manual end,
      case when r ? 'note' then nullif(r ->> 'note', '') else ex.note end, me)
    on conflict (customer_id, month, part_code) do update set safety_qty = excluded.safety_qty, rrs_qty = excluded.rrs_qty, wip_qty = excluded.wip_qty,
      wip2_qty = excluded.wip2_qty, sched_manual = excluded.sched_manual, note = excluded.note, updated_by = excluded.updated_by, updated_at = now();
    n := n + 1;
  end loop;
  return n;
end $$;
grant execute on function public.kmr_rmp_partstock_save(text, text, jsonb) to authenticated;

create or replace function public.kmr_rmp_week_save(p_slug text, p_month text, p_rows jsonb) returns integer
language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'rmp'); r jsonb; n int := 0; ex record; me text := lower(coalesce(auth.jwt() ->> 'email', ''));
begin
  if p_month !~ '^\d{4}-(0[1-9]|1[0-2])$' then raise exception 'Month must look like 2026-11.'; end if;
  for r in select * from jsonb_array_elements(coalesce(p_rows, '[]')) loop
    if coalesce(trim(r ->> 'material_code'), '') = '' or coalesce(r ->> 'week', '') !~ '^[1-5]$' then continue; end if;
    select * into ex from console.rmp_plan_week where customer_id = cid and month = p_month and material_code = trim(r ->> 'material_code') and week = (r ->> 'week')::smallint;
    insert into console.rmp_plan_week (customer_id, month, material_code, week, planned_qty, received_qty, updated_by)
    values (cid, p_month, trim(r ->> 'material_code'), (r ->> 'week')::smallint,
      greatest(0, coalesce(case when r ? 'planned_qty' then nullif(r ->> 'planned_qty', '')::numeric else ex.planned_qty end, 0)),
      greatest(0, coalesce(case when r ? 'received_qty' then nullif(r ->> 'received_qty', '')::numeric else ex.received_qty end, 0)), me)
    on conflict (customer_id, month, material_code, week) do update set planned_qty = excluded.planned_qty, received_qty = excluded.received_qty, updated_by = excluded.updated_by, updated_at = now();
    n := n + 1;
  end loop;
  return n;
end $$;
grant execute on function public.kmr_rmp_week_save(text, text, jsonb) to authenticated;

-- stock, rate, GST and unit of a material (extends the 0057 function; only the fields sent are changed)
create or replace function public.kmr_rmp_stock_save(p_slug text, p jsonb) returns uuid
language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'rmp'); rid uuid; mc text := trim(coalesce(p ->> 'material_code', ''));
begin
  if not exists (select 1 from console.ops_records where customer_id = cid and kind = 'raw_materials' and code = mc) then raise exception 'Material % is not in Operations Master › Raw material.', mc; end if;
  insert into console.rmp_stock (customer_id, material_code, on_hand_kg, safety_kg, lead_days, moq_kg, pack_kg, rate, gst_pct, unit, supplier_text, spec_text, updated_by)
  values (cid, mc, coalesce(nullif(p ->> 'on_hand_kg', '')::numeric, 0), coalesce(nullif(p ->> 'safety_kg', '')::numeric, 0), nullif(p ->> 'lead_days', '')::int,
          nullif(p ->> 'moq_kg', '')::numeric, nullif(p ->> 'pack_kg', '')::numeric, nullif(p ->> 'rate', '')::numeric, coalesce(nullif(p ->> 'gst_pct', '')::numeric, 18),
          case when p ->> 'unit' in ('kg', 'nos') then p ->> 'unit' else 'kg' end, nullif(p ->> 'supplier_text', ''), nullif(p ->> 'spec_text', ''), lower(coalesce(auth.jwt() ->> 'email', '')))
  on conflict (customer_id, material_code) do update set
    on_hand_kg = case when p ? 'on_hand_kg' then excluded.on_hand_kg else console.rmp_stock.on_hand_kg end,
    safety_kg = case when p ? 'safety_kg' then excluded.safety_kg else console.rmp_stock.safety_kg end,
    lead_days = case when p ? 'lead_days' then excluded.lead_days else console.rmp_stock.lead_days end,
    moq_kg = case when p ? 'moq_kg' then excluded.moq_kg else console.rmp_stock.moq_kg end,
    pack_kg = case when p ? 'pack_kg' then excluded.pack_kg else console.rmp_stock.pack_kg end,
    rate = case when p ? 'rate' then excluded.rate else console.rmp_stock.rate end,
    gst_pct = case when p ? 'gst_pct' then excluded.gst_pct else console.rmp_stock.gst_pct end,
    unit = case when p ? 'unit' then excluded.unit else console.rmp_stock.unit end,
    supplier_text = case when p ? 'supplier_text' then excluded.supplier_text else console.rmp_stock.supplier_text end,
    spec_text = case when p ? 'spec_text' then excluded.spec_text else console.rmp_stock.spec_text end,
    updated_by = excluded.updated_by, updated_at = now(), sample = false
  returning id into rid;
  return rid;
end $$;
grant execute on function public.kmr_rmp_stock_save(text, jsonb) to authenticated;

-- Schedules that came from the Excel sheet are not part of the Sales Flow plan: remove them so only Sales Flow parts show.
-- (Stock, safety, RRS and WIP figures stay.) Parts added by hand on the screen are not touched.
update console.rmp_partstock set sched_manual = null where updated_by = 'rm-sheet-import';
