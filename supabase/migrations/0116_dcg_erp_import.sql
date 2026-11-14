-- =====================================================================
-- 0116 — Delivery Challan & GRN: bulk import of the old ERP's delivery challans, GRNs and purchase orders, and a fast screen load.
--  • kmr_dcg_import(slug, {pos, dcs, grns}) adds history in batches (safe to re-run: a number already there is skipped). It does NOT touch Calibration Hub
--    or Raw Material stock — it only records what happened in the ERP.
--  • kmr_dcg_load now brings the last 3 months (plus nothing older) so the screen stays fast; p_months widens it (3, 12 or 36 months).
-- Needs 0113. Safe to re-run.
-- =====================================================================
create or replace function public.kmr_dcg_import(p_slug text, p jsonb) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'dcg'); np int := 0; nd int := 0; ng int := 0;
begin
  with src as (select * from jsonb_to_recordset(coalesce(p -> 'pos', '[]'::jsonb)) as x(po_no text, po_date date, supplier_name text, supplier_gstin text, supplier_addr text, status text, remarks text, lines jsonb)),
  ins as (insert into console.dcg_po (customer_id, po_no, po_date, supplier_name, supplier_gstin, supplier_addr, status, remarks, created_by)
          select cid, s.po_no, s.po_date, coalesce(nullif(s.supplier_name, ''), '—'), nullif(s.supplier_gstin, ''), nullif(s.supplier_addr, ''),
                 case when s.status in ('open', 'part_received', 'closed', 'cancelled') then s.status else 'closed' end, s.remarks, 'ERP import'
            from src s where coalesce(s.po_no, '') <> '' on conflict (customer_id, po_no) do nothing returning id, po_no),
  li as (insert into console.dcg_po_lines (customer_id, po_id, sl, item_code, description, uom, qty, rate, received_qty)
          select cid, i.id, l.sl, nullif(l.item_code, ''), coalesce(nullif(l.description, ''), '—'), coalesce(nullif(l.uom, ''), 'Nos'), l.qty, l.rate, coalesce(l.received_qty, 0)
            from ins i join src s on s.po_no = i.po_no cross join lateral jsonb_to_recordset(coalesce(s.lines, '[]'::jsonb)) as l(sl int, item_code text, description text, uom text, qty numeric, rate numeric, received_qty numeric)
           where l.qty > 0 returning 1)
  select count(*) into np from ins;

  with src as (select * from jsonb_to_recordset(coalesce(p -> 'dcs', '[]'::jsonb)) as x(dc_no text, dc_date date, kind text, purpose text, party_name text, party_addr text, party_gstin text, vehicle_no text, mode text, expected_return date, po_no text, remarks text, status text, lines jsonb)),
  ins as (insert into console.dcg_dc (customer_id, dc_no, dc_date, kind, purpose, party_name, party_addr, party_gstin, vehicle_no, mode, expected_return, po_id, remarks, status, issued_by, issued_at, created_by)
          select cid, s.dc_no, coalesce(s.dc_date, current_date), case when s.kind = 'returnable' then 'returnable' else 'non_returnable' end,
                 case when s.purpose in ('calibration', 'job_work', 'repair', 'rework', 'sample', 'scrap', 'material', 'other') then s.purpose else 'other' end,
                 coalesce(nullif(s.party_name, ''), '—'), nullif(s.party_addr, ''), nullif(s.party_gstin, ''), nullif(s.vehicle_no, ''), nullif(s.mode, ''), s.expected_return,
                 (select po.id from console.dcg_po po where po.customer_id = cid and po.po_no = s.po_no), nullif(s.remarks, ''),
                 case when s.status in ('draft', 'issued', 'part_returned', 'closed', 'cancelled') then s.status else 'closed' end, 'ERP import', coalesce(s.dc_date, current_date)::timestamptz, 'ERP import'
            from src s where coalesce(s.dc_no, '') <> '' on conflict (customer_id, dc_no) do nothing returning id, dc_no),
  li as (insert into console.dcg_dc_lines (customer_id, dc_id, sl, instrument_id, item_code, description, uom, qty, hsn, value, returned_qty, remarks)
          select cid, i.id, l.sl, (select ci.id from console.cal_instruments ci where ci.customer_id = cid and ci.tag = l.item_code), nullif(l.item_code, ''),
                 coalesce(nullif(l.description, ''), nullif(l.item_code, ''), '—'), coalesce(nullif(l.uom, ''), 'Nos'), l.qty, nullif(l.hsn, ''), l.value, least(coalesce(l.returned_qty, 0), l.qty), nullif(l.remarks, '')
            from ins i join src s on s.dc_no = i.dc_no cross join lateral jsonb_to_recordset(coalesce(s.lines, '[]'::jsonb)) as l(sl int, item_code text, description text, uom text, qty numeric, hsn text, value numeric, returned_qty numeric, remarks text)
           where l.qty > 0 returning 1)
  select count(*) into nd from ins;

  with src as (select * from jsonb_to_recordset(coalesce(p -> 'grns', '[]'::jsonb)) as x(grn_no text, grn_date date, gtype text, party_name text, po_no text, dc_no text, party_doc_no text, party_doc_date date, remarks text, lines jsonb)),
  ins as (insert into console.dcg_grn (customer_id, grn_no, grn_date, gtype, party_name, po_id, dc_id, party_doc_no, party_doc_date, remarks, status, created_by)
          select cid, s.grn_no, coalesce(s.grn_date, current_date), case when s.gtype in ('po_receipt', 'dc_return', 'other') then s.gtype else 'other' end, nullif(s.party_name, ''),
                 (select po.id from console.dcg_po po where po.customer_id = cid and po.po_no = s.po_no),
                 (select d.id from console.dcg_dc d where d.customer_id = cid and d.dc_no = s.dc_no), nullif(s.party_doc_no, ''), s.party_doc_date, nullif(s.remarks, ''), 'posted', 'ERP import'
            from src s where coalesce(s.grn_no, '') <> '' on conflict (customer_id, grn_no) do nothing returning id, grn_no),
  li as (insert into console.dcg_grn_lines (customer_id, grn_id, sl, item_code, description, uom, received_qty, accepted_qty, rejected_qty, reject_reason, remarks)
          select cid, i.id, l.sl, nullif(l.item_code, ''), coalesce(nullif(l.description, ''), nullif(l.item_code, ''), '—'), coalesce(nullif(l.uom, ''), 'Nos'), l.received_qty,
                 greatest(coalesce(l.accepted_qty, l.received_qty), 0), greatest(coalesce(l.rejected_qty, 0), 0), nullif(l.reject_reason, ''), nullif(l.remarks, '')
            from ins i join src s on s.grn_no = i.grn_no cross join lateral jsonb_to_recordset(coalesce(s.lines, '[]'::jsonb)) as l(sl int, item_code text, description text, uom text, received_qty numeric, accepted_qty numeric, rejected_qty numeric, reject_reason text, remarks text)
           where l.received_qty > 0 returning 1)
  select count(*) into ng from ins;
  return jsonb_build_object('pos', np, 'dcs', nd, 'grns', ng);
end $$;

-- the screen loads the last 3 months only (older records stay saved; the screen offers 12 and 36 months)
drop function if exists public.kmr_dcg_load(text);
drop function if exists public.kmr_dcg_load(text, boolean);
create or replace function public.kmr_dcg_load(p_slug text, p_months int default 3) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'dcg'); since date := (current_date - make_interval(months => greatest(1, least(coalesce(p_months, 3), 36))))::date;
begin
  return jsonb_build_object(
    'pos', coalesce((select jsonb_agg(jsonb_strip_nulls(to_jsonb(p) - 'customer_id' || jsonb_build_object('lines', coalesce((select jsonb_agg(to_jsonb(l) - 'customer_id' order by l.sl) from console.dcg_po_lines l where l.po_id = p.id), '[]'::jsonb))) order by p.po_date desc nulls last, p.created_at desc)
                     from console.dcg_po p where p.customer_id = cid and (p.po_date is null or p.po_date >= since)), '[]'::jsonb),
    'dcs', coalesce((select jsonb_agg(jsonb_strip_nulls(to_jsonb(d) - 'customer_id' || jsonb_build_object('lines', coalesce((select jsonb_agg(to_jsonb(l) - 'customer_id' order by l.sl) from console.dcg_dc_lines l where l.dc_id = d.id), '[]'::jsonb))) order by d.dc_date desc, d.created_at desc)
                     from console.dcg_dc d where d.customer_id = cid and d.dc_date >= since), '[]'::jsonb),
    'grns', coalesce((select jsonb_agg(jsonb_strip_nulls(to_jsonb(g) - 'customer_id' || jsonb_build_object('lines', coalesce((select jsonb_agg(to_jsonb(l) - 'customer_id' order by l.sl) from console.dcg_grn_lines l where l.grn_id = g.id), '[]'::jsonb))) order by g.grn_date desc, g.created_at desc)
                     from console.dcg_grn g where g.customer_id = cid and g.grn_date >= since), '[]'::jsonb),
    'older', jsonb_build_object(
      'dcs', (select count(*) from console.dcg_dc d where d.customer_id = cid and d.dc_date < since),
      'grns', (select count(*) from console.dcg_grn g where g.customer_id = cid and g.grn_date < since),
      'pos', (select count(*) from console.dcg_po p where p.customer_id = cid and p.po_date < since),
      'open_dcs', (select count(*) from console.dcg_dc d where d.customer_id = cid and d.dc_date < since and d.status in ('issued', 'part_returned') and d.kind = 'returnable')),
    'instruments', case when console.has_app(cid, 'calib') then coalesce((select jsonb_agg(jsonb_build_object('id', i.id, 'tag', i.tag, 'name', i.name, 'status', i.status, 'next_due', i.next_due, 'lab', i.lab, 'cal_source', i.cal_source) order by i.tag)
                     from console.cal_instruments i where i.customer_id = cid and i.status not in ('Scrapped', 'Scrap')), '[]'::jsonb) else '[]'::jsonb end,
    'rmp_open', case when console.has_app(cid, 'rmp') then coalesce((select count(*) from console.rmp_orders o where o.customer_id = cid and o.status in ('planned', 'ordered')
                     and not exists (select 1 from console.dcg_po_lines l where l.rmp_order_id = o.id)), 0) else 0 end);
end $$;

create index if not exists dcg_dc_date on console.dcg_dc (customer_id, dc_date);

do $$ declare f record; begin
  for f in select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in ('kmr_dcg_import', 'kmr_dcg_load') loop
    execute format('revoke all on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
end $$;
