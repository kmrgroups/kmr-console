-- Work sheet: finished-goods, final-inspection, incoming and supplier stock per part.
alter table console.rmp_partstock add column if not exists fg_qty numeric not null default 0;
alter table console.rmp_partstock add column if not exists fi_qty numeric not null default 0;
alter table console.rmp_partstock add column if not exists inc_qty numeric not null default 0;
alter table console.rmp_partstock add column if not exists sup_qty numeric not null default 0;

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
          'safety', coalesce(ps.safety_qty, 0), 'rrs', coalesce(ps.rrs_qty, 0), 'wip', coalesce(ps.wip_qty, 0), 'wip2', coalesce(ps.wip2_qty, 0), 'fg', coalesce(ps.fg_qty, 0), 'fi', coalesce(ps.fi_qty, 0), 'inc', coalesce(ps.inc_qty, 0), 'sup', coalesce(ps.sup_qty, 0), 'manual', ps.sched_manual, 'note', ps.note)
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

create or replace function public.kmr_rmp_partstock_save(p_slug text, p_month text, p_rows jsonb) returns integer
language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'rmp'); r jsonb; n int := 0; ex record; me text := lower(coalesce(auth.jwt() ->> 'email', ''));
begin
  if p_month !~ '^\d{4}-(0[1-9]|1[0-2])$' then raise exception 'Month must look like 2026-11.'; end if;
  for r in select * from jsonb_array_elements(coalesce(p_rows, '[]')) loop
    if coalesce(trim(r ->> 'part_code'), '') = '' then continue; end if;
    select * into ex from console.rmp_partstock where customer_id = cid and month = p_month and part_code = trim(r ->> 'part_code');
    insert into console.rmp_partstock (customer_id, month, part_code, safety_qty, rrs_qty, wip_qty, wip2_qty, fg_qty, fi_qty, inc_qty, sup_qty, sched_manual, note, updated_by)
    values (cid, p_month, trim(r ->> 'part_code'),
      greatest(0, coalesce(case when r ? 'safety_qty' then nullif(r ->> 'safety_qty', '')::numeric else ex.safety_qty end, 0)),
      greatest(0, coalesce(case when r ? 'rrs_qty' then nullif(r ->> 'rrs_qty', '')::numeric else ex.rrs_qty end, 0)),
      greatest(0, coalesce(case when r ? 'wip_qty' then nullif(r ->> 'wip_qty', '')::numeric else ex.wip_qty end, 0)),
      greatest(0, coalesce(case when r ? 'wip2_qty' then nullif(r ->> 'wip2_qty', '')::numeric else ex.wip2_qty end, 0)),
      greatest(0, coalesce(case when r ? 'fg_qty' then nullif(r ->> 'fg_qty', '')::numeric else ex.fg_qty end, 0)),
      greatest(0, coalesce(case when r ? 'fi_qty' then nullif(r ->> 'fi_qty', '')::numeric else ex.fi_qty end, 0)),
      greatest(0, coalesce(case when r ? 'inc_qty' then nullif(r ->> 'inc_qty', '')::numeric else ex.inc_qty end, 0)),
      greatest(0, coalesce(case when r ? 'sup_qty' then nullif(r ->> 'sup_qty', '')::numeric else ex.sup_qty end, 0)),
      case when r ? 'sched_manual' then nullif(r ->> 'sched_manual', '')::numeric else ex.sched_manual end,
      case when r ? 'note' then nullif(r ->> 'note', '') else ex.note end, me)
    on conflict (customer_id, month, part_code) do update set safety_qty = excluded.safety_qty, rrs_qty = excluded.rrs_qty, wip_qty = excluded.wip_qty,
      wip2_qty = excluded.wip2_qty, fg_qty = excluded.fg_qty, fi_qty = excluded.fi_qty, inc_qty = excluded.inc_qty, sup_qty = excluded.sup_qty, sched_manual = excluded.sched_manual, note = excluded.note, updated_by = excluded.updated_by, updated_at = now();
    n := n + 1;
  end loop;
  return n;
end $$;
grant execute on function public.kmr_rmp_partstock_save(text, text, jsonb) to authenticated;
