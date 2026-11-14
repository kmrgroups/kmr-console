-- =====================================================================
-- 0113 — Delivery Challan & GRN (DCG) — a new KMR app, company level
--  • Delivery Challans (DC): returnable (calibration gauges, job work, repair, rework, samples) and non-returnable (scrap, material, other)
--  • Goods Receipt Notes (GRN) against a DC (the return) or against a Purchase Order (PO), numbered per financial year: DC/26-27/0001, GRN/26-27/0001
--  • Links: a calibration DC marks the gauge 'Out for calibration' in Calibration Hub; the GRN of the returned gauge writes the calibration record,
--    next due date, quarantine on a Fail and the out-of-tolerance case; a GRN against an RMP-linked PO line updates the order and the raw material stock
-- Needs 0048 (qp_*), 0037 (calibration), 0057 (RMP), 0091/0096 (portal patch anchors). Safe to re-run.
-- =====================================================================

insert into console.products (code, name, description, app_path, seat_label, current_version, sort_order) values
  ('dcg', 'Delivery Challan & GRN', 'Returnable and non-returnable delivery challans, Goods Receipt Notes against the challan and the purchase order, linked to Calibration Hub and Raw Material Planning', '/it/dcg.html', 'users', '1.0.0', 150)
on conflict (code) do update set name = excluded.name, description = excluded.description, app_path = excluded.app_path;

insert into console.releases (product_code, version, notes) values
  ('dcg', '1.0.0', 'Delivery Challan & GRN: returnable / non-returnable DC, GRN against DC and PO, pending returns, calibration and raw material links, standards alignment, presentation')
on conflict do nothing;

insert into console.prices (product_code, period, currency, unit_amount, min_seats, active, note)
select v.code, v.period, 'INR', v.amt, 1, true, 'Starting price list (0113) — change in Console • Billing'
  from (values ('dcg', 'month', 1500), ('dcg', 'year', 15000)) v(code, period, amt)
on conflict (product_code, period, currency) do nothing;

insert into public.app_listings (code, name, tagline, features, sort_order, is_active) values
  ('dcg', 'Delivery Challan & GRN', 'Make the delivery challan, track what has not come back, and receive it with a GRN against the challan or the purchase order.',
   E'Returnable and non-returnable delivery challans with yearly numbering\nGRN against the challan (returns) and the purchase order (receipts)\nCalibration gauges go out on a DC and are calibrated on the GRN\nPending returns and overdue alerts', 150, true)
on conflict (code) do update set name = excluded.name, tagline = coalesce(public.app_listings.tagline, excluded.tagline), features = coalesce(public.app_listings.features, excluded.features);

insert into console.app_features (product_code, name, detail, is_core, price_month, price_year, setup_fee, sort_order) values
  ('dcg', 'Delivery challans and GRN', 'Returnable and non-returnable DC, GRN against DC and PO, pending returns, print', true, 1500, 0, 5000, 10),
  ('dcg', 'Calibration and raw material links', 'Gauge goes out on a DC and the calibration result is written on the GRN; receipts against RMP orders update the raw material stock', false, 500, 0, 3000, 20)
on conflict (product_code, name) do nothing;

-- ---------- tables ----------
create table if not exists console.dcg_counters (
  customer_id uuid not null references console.customers(id) on delete cascade,
  kind text not null, fy text not null, n int not null default 0,
  primary key (customer_id, kind, fy));

create table if not exists console.dcg_po (
  id uuid primary key default gen_random_uuid(), customer_id uuid not null references console.customers(id) on delete cascade,
  po_no text not null, po_date date, supplier_name text not null, supplier_gstin text, supplier_addr text,
  status text not null default 'open' check (status in ('open', 'part_received', 'closed', 'cancelled')),
  remarks text, created_by text, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique (customer_id, po_no));
create table if not exists console.dcg_po_lines (
  id uuid primary key default gen_random_uuid(), customer_id uuid not null references console.customers(id) on delete cascade,
  po_id uuid not null references console.dcg_po(id) on delete cascade, sl int not null default 1,
  item_code text, description text not null, uom text not null default 'Nos', qty numeric not null check (qty > 0), rate numeric,
  rmp_order_id uuid references console.rmp_orders(id) on delete set null, received_qty numeric not null default 0);

create table if not exists console.dcg_dc (
  id uuid primary key default gen_random_uuid(), customer_id uuid not null references console.customers(id) on delete cascade,
  dc_no text, dc_date date not null default current_date,
  kind text not null check (kind in ('returnable', 'non_returnable')),
  purpose text not null default 'other' check (purpose in ('calibration', 'job_work', 'repair', 'rework', 'sample', 'scrap', 'material', 'other')),
  party_name text not null, party_addr text, party_gstin text, vehicle_no text, mode text, expected_return date,
  po_id uuid references console.dcg_po(id) on delete set null, remarks text,
  status text not null default 'draft' check (status in ('draft', 'issued', 'part_returned', 'closed', 'cancelled')),
  issued_by text, issued_at timestamptz, cancel_reason text, created_by text, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique (customer_id, dc_no));
create table if not exists console.dcg_dc_lines (
  id uuid primary key default gen_random_uuid(), customer_id uuid not null references console.customers(id) on delete cascade,
  dc_id uuid not null references console.dcg_dc(id) on delete cascade, sl int not null default 1,
  instrument_id uuid references console.cal_instruments(id) on delete set null,
  item_code text, description text not null, uom text not null default 'Nos', qty numeric not null check (qty > 0), hsn text, value numeric,
  returned_qty numeric not null default 0, remarks text);

create table if not exists console.dcg_grn (
  id uuid primary key default gen_random_uuid(), customer_id uuid not null references console.customers(id) on delete cascade,
  grn_no text not null, grn_date date not null default current_date,
  gtype text not null check (gtype in ('po_receipt', 'dc_return', 'other')),
  party_name text, po_id uuid references console.dcg_po(id) on delete set null, dc_id uuid references console.dcg_dc(id) on delete set null,
  party_doc_no text, party_doc_date date, vehicle_no text, remarks text,
  status text not null default 'posted' check (status in ('posted', 'cancelled')), cancel_reason text,
  created_by text, created_at timestamptz not null default now(),
  unique (customer_id, grn_no));
create table if not exists console.dcg_grn_lines (
  id uuid primary key default gen_random_uuid(), customer_id uuid not null references console.customers(id) on delete cascade,
  grn_id uuid not null references console.dcg_grn(id) on delete cascade, sl int not null default 1,
  po_line_id uuid references console.dcg_po_lines(id) on delete set null, dc_line_id uuid references console.dcg_dc_lines(id) on delete set null,
  instrument_id uuid references console.cal_instruments(id) on delete set null,
  item_code text, description text not null, uom text not null default 'Nos',
  received_qty numeric not null check (received_qty > 0), accepted_qty numeric not null default 0 check (accepted_qty >= 0), rejected_qty numeric not null default 0 check (rejected_qty >= 0),
  reject_reason text, cal_date date, cert_no text, lab text, cal_result text, as_found_ok boolean, next_due date, cost numeric, cal_record_id uuid, remarks text);

create index if not exists dcg_dc_cust on console.dcg_dc (customer_id, status);
create index if not exists dcg_grn_cust on console.dcg_grn (customer_id, grn_date);
create index if not exists dcg_dcl_dc on console.dcg_dc_lines (dc_id);
create index if not exists dcg_grnl_grn on console.dcg_grn_lines (grn_id);
create index if not exists dcg_pol_po on console.dcg_po_lines (po_id);

do $$ declare t text; begin
  foreach t in array array['dcg_counters', 'dcg_po', 'dcg_po_lines', 'dcg_dc', 'dcg_dc_lines', 'dcg_grn', 'dcg_grn_lines'] loop
    execute format('alter table console.%I enable row level security', t);
    execute format('drop policy if exists %I on console.%I', t || '_staff', t);
    execute format('create policy %I on console.%I for all to authenticated using (console.is_staff()) with check (console.is_staff())', t || '_staff', t);
  end loop;
end $$;

-- ---------- next number: DC/26-27/0001 (financial year April to March, India time) ----------
create or replace function console.dcg_next(p_cid uuid, p_kind text) returns text language plpgsql security definer set search_path = console, public as $$
declare d date := (now() at time zone 'Asia/Kolkata')::date; y int := extract(year from d)::int; v_fy text; v_n int;
begin
  if extract(month from d) < 4 then y := y - 1; end if;
  v_fy := lpad((y % 100)::text, 2, '0') || '-' || lpad(((y + 1) % 100)::text, 2, '0');
  insert into console.dcg_counters as c (customer_id, kind, fy, n) values (p_cid, p_kind, v_fy, 1)
  on conflict (customer_id, kind, fy) do update set n = c.n + 1 returning c.n into v_n;
  return upper(p_kind) || '/' || v_fy || '/' || lpad(v_n::text, 4, '0');
end $$;
revoke all on function console.dcg_next(uuid, text) from public, anon, authenticated;

-- ---------- context ----------
create or replace function public.kmr_dcg_context(p_slug text) returns jsonb language sql stable security definer set search_path = console, public as $$
  select case when console.qp_role(c.id, 'dcg') is null then null
    else jsonb_build_object('role', console.qp_role(c.id, 'dcg'), 'company', c.name, 'logo_url', c.logo_url, 'is_staff', coalesce(console.is_staff(), false),
      'has_calib', console.has_app(c.id, 'calib'), 'has_rmp', console.has_app(c.id, 'rmp')) end
  from console.customers c where c.slug = lower(p_slug) $$;

-- ---------- load everything for the screen ----------
create or replace function public.kmr_dcg_load(p_slug text) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'dcg');
begin
  return jsonb_build_object(
    'pos', coalesce((select jsonb_agg(to_jsonb(p) - 'customer_id' || jsonb_build_object('lines', coalesce((select jsonb_agg(to_jsonb(l) - 'customer_id' order by l.sl) from console.dcg_po_lines l where l.po_id = p.id), '[]'::jsonb)) order by p.po_date desc nulls last, p.created_at desc)
                     from console.dcg_po p where p.customer_id = cid), '[]'::jsonb),
    'dcs', coalesce((select jsonb_agg(to_jsonb(d) - 'customer_id' || jsonb_build_object('lines', coalesce((select jsonb_agg(to_jsonb(l) - 'customer_id' order by l.sl) from console.dcg_dc_lines l where l.dc_id = d.id), '[]'::jsonb)) order by d.dc_date desc, d.created_at desc)
                     from console.dcg_dc d where d.customer_id = cid), '[]'::jsonb),
    'grns', coalesce((select jsonb_agg(to_jsonb(g) - 'customer_id' || jsonb_build_object('lines', coalesce((select jsonb_agg(to_jsonb(l) - 'customer_id' order by l.sl) from console.dcg_grn_lines l where l.grn_id = g.id), '[]'::jsonb)) order by g.grn_date desc, g.created_at desc)
                     from console.dcg_grn g where g.customer_id = cid), '[]'::jsonb),
    'instruments', case when console.has_app(cid, 'calib') then coalesce((select jsonb_agg(jsonb_build_object('id', i.id, 'tag', i.tag, 'name', i.name, 'status', i.status, 'next_due', i.next_due, 'lab', i.lab, 'cal_source', i.cal_source) order by i.tag)
                     from console.cal_instruments i where i.customer_id = cid and i.status not in ('Scrapped', 'Scrap')), '[]'::jsonb) else '[]'::jsonb end,
    'rmp_open', case when console.has_app(cid, 'rmp') then coalesce((select count(*) from console.rmp_orders o where o.customer_id = cid and o.status in ('planned', 'ordered')
                     and not exists (select 1 from console.dcg_po_lines l where l.rmp_order_id = o.id)), 0) else 0 end);
end $$;

-- ---------- purchase orders ----------
create or replace function public.kmr_dcg_po_save(p_slug text, p jsonb) returns uuid language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'dcg'); me text := lower(coalesce(auth.jwt() ->> 'email', '')); pid uuid := nullif(p ->> 'id', '')::uuid; ln jsonb; k int := 0; kept uuid[] := '{}'; lid uuid;
begin
  if trim(coalesce(p ->> 'po_no', '')) = '' then raise exception 'Enter the PO number.'; end if;
  if trim(coalesce(p ->> 'supplier_name', '')) = '' then raise exception 'Enter the supplier name.'; end if;
  if jsonb_typeof(p -> 'lines') is distinct from 'array' or jsonb_array_length(p -> 'lines') = 0 then raise exception 'Add at least one item.'; end if;
  if pid is null then
    if exists (select 1 from console.dcg_po where customer_id = cid and po_no = trim(p ->> 'po_no')) then raise exception 'PO % already exists.', trim(p ->> 'po_no'); end if;
    insert into console.dcg_po (customer_id, po_no, po_date, supplier_name, supplier_gstin, supplier_addr, remarks, created_by)
    values (cid, trim(p ->> 'po_no'), nullif(p ->> 'po_date', '')::date, trim(p ->> 'supplier_name'), nullif(trim(coalesce(p ->> 'supplier_gstin', '')), ''), nullif(trim(coalesce(p ->> 'supplier_addr', '')), ''), nullif(trim(coalesce(p ->> 'remarks', '')), ''), me) returning id into pid;
  else
    if not exists (select 1 from console.dcg_po where id = pid and customer_id = cid) then raise exception 'Unknown PO.'; end if;
    if exists (select 1 from console.dcg_po where id = pid and status = 'cancelled') then raise exception 'A cancelled PO cannot be changed.'; end if;
    if exists (select 1 from console.dcg_po where customer_id = cid and po_no = trim(p ->> 'po_no') and id <> pid) then raise exception 'PO % already exists.', trim(p ->> 'po_no'); end if;
    update console.dcg_po set po_no = trim(p ->> 'po_no'), po_date = nullif(p ->> 'po_date', '')::date, supplier_name = trim(p ->> 'supplier_name'), supplier_gstin = nullif(trim(coalesce(p ->> 'supplier_gstin', '')), ''),
      supplier_addr = nullif(trim(coalesce(p ->> 'supplier_addr', '')), ''), remarks = nullif(trim(coalesce(p ->> 'remarks', '')), ''), updated_at = now() where id = pid;
  end if;
  for ln in select * from jsonb_array_elements(p -> 'lines') loop
    k := k + 1;
    if trim(coalesce(ln ->> 'description', '')) = '' then raise exception 'Item % has no description.', k; end if;
    if coalesce(nullif(ln ->> 'qty', '')::numeric, 0) <= 0 then raise exception 'Item % needs a quantity above zero.', k; end if;
    lid := nullif(ln ->> 'id', '')::uuid;
    if lid is not null and exists (select 1 from console.dcg_po_lines where id = lid and po_id = pid) then
      if (select received_qty from console.dcg_po_lines where id = lid) > (ln ->> 'qty')::numeric then raise exception 'Item % already has more received than this quantity.', k; end if;
      update console.dcg_po_lines set sl = k, item_code = nullif(trim(coalesce(ln ->> 'item_code', '')), ''), description = trim(ln ->> 'description'), uom = coalesce(nullif(trim(coalesce(ln ->> 'uom', '')), ''), 'Nos'),
        qty = (ln ->> 'qty')::numeric, rate = nullif(ln ->> 'rate', '')::numeric where id = lid;
    else
      insert into console.dcg_po_lines (customer_id, po_id, sl, item_code, description, uom, qty, rate)
      values (cid, pid, k, nullif(trim(coalesce(ln ->> 'item_code', '')), ''), trim(ln ->> 'description'), coalesce(nullif(trim(coalesce(ln ->> 'uom', '')), ''), 'Nos'), (ln ->> 'qty')::numeric, nullif(ln ->> 'rate', '')::numeric) returning id into lid;
    end if;
    kept := kept || lid;
  end loop;
  if exists (select 1 from console.dcg_po_lines where po_id = pid and id <> all (kept) and (received_qty > 0 or exists (select 1 from console.dcg_grn_lines g where g.po_line_id = dcg_po_lines.id))) then
    raise exception 'An item that already has a GRN cannot be removed.'; end if;
  delete from console.dcg_po_lines where po_id = pid and id <> all (kept);
  return pid;
end $$;

create or replace function public.kmr_dcg_po_close(p_slug text, p_id uuid, p_status text) returns text language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'dcg');
begin
  if p_status not in ('closed', 'cancelled', 'open') then raise exception 'Unknown status.'; end if;
  if not exists (select 1 from console.dcg_po where id = p_id and customer_id = cid) then raise exception 'Unknown PO.'; end if;
  if p_status = 'cancelled' and exists (select 1 from console.dcg_po_lines where po_id = p_id and received_qty > 0) then raise exception 'This PO already has receipts; close it instead of cancelling.'; end if;
  update console.dcg_po set status = case when p_status = 'open' then (case when exists (select 1 from console.dcg_po_lines where po_id = p_id and received_qty > 0) then 'part_received' else 'open' end) else p_status end, updated_at = now() where id = p_id;
  return p_status;
end $$;

create or replace function public.kmr_dcg_po_delete(p_slug text, p_id uuid) returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'dcg');
begin
  if not exists (select 1 from console.dcg_po where id = p_id and customer_id = cid) then raise exception 'Unknown PO.'; end if;
  if exists (select 1 from console.dcg_grn g where g.po_id = p_id and g.status = 'posted') then raise exception 'This PO has a GRN; cancel the GRN first.'; end if;
  delete from console.dcg_po where id = p_id;
end $$;

-- bring the orders placed in Raw Material Planning in as POs (one PO per PO number, lines linked to the order)
create or replace function public.kmr_dcg_po_from_rmp(p_slug text) returns integer language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'dcg'); me text := lower(coalesce(auth.jwt() ->> 'email', '')); o record; pid uuid; n int := 0; pn text;
begin
  if not console.has_app(cid, 'rmp') then raise exception 'Raw Material Planning is not switched on for this company.'; end if;
  for o in select * from console.rmp_orders r where r.customer_id = cid and r.status in ('planned', 'ordered')
            and not exists (select 1 from console.dcg_po_lines l where l.rmp_order_id = r.id) order by r.po_no nulls last, r.created_at loop
    pn := coalesce(nullif(trim(o.po_no), ''), 'RMP-' || left(o.id::text, 8));
    select id into pid from console.dcg_po where customer_id = cid and po_no = pn;
    if pid is null then
      insert into console.dcg_po (customer_id, po_no, po_date, supplier_name, remarks, created_by)
      values (cid, pn, o.order_date, coalesce(nullif(trim(o.supplier_code), ''), 'Supplier'), 'Imported from Raw Material Planning', me) returning id into pid;
    end if;
    insert into console.dcg_po_lines (customer_id, po_id, sl, item_code, description, uom, qty, rate, rmp_order_id)
    values (cid, pid, coalesce((select max(sl) from console.dcg_po_lines where po_id = pid), 0) + 1, o.material_code, o.material_code, 'kg', o.qty_kg, o.rate, o.id);
    n := n + 1;
  end loop;
  return n;
end $$;

-- ---------- delivery challans ----------
create or replace function public.kmr_dcg_dc_save(p_slug text, p jsonb) returns uuid language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'dcg'); me text := lower(coalesce(auth.jwt() ->> 'email', '')); did uuid := nullif(p ->> 'id', '')::uuid; ln jsonb; k int := 0;
  kd text := coalesce(p ->> 'kind', ''); pu text := coalesce(nullif(p ->> 'purpose', ''), 'other');
begin
  if kd not in ('returnable', 'non_returnable') then raise exception 'Choose returnable or non-returnable.'; end if;
  if trim(coalesce(p ->> 'party_name', '')) = '' then raise exception 'Enter the name of the party the material goes to.'; end if;
  if pu not in ('calibration', 'job_work', 'repair', 'rework', 'sample', 'scrap', 'material', 'other') then raise exception 'Unknown purpose.'; end if;
  if kd = 'returnable' and pu in ('scrap', 'material') then raise exception 'Scrap and material go on a non-returnable DC.'; end if;
  if kd = 'non_returnable' and pu in ('calibration', 'job_work', 'repair', 'rework') then raise exception '% goes on a returnable DC.', initcap(replace(pu, '_', ' ')); end if;
  if jsonb_typeof(p -> 'lines') is distinct from 'array' or jsonb_array_length(p -> 'lines') = 0 then raise exception 'Add at least one item.'; end if;
  if did is null then
    insert into console.dcg_dc (customer_id, dc_date, kind, purpose, party_name, party_addr, party_gstin, vehicle_no, mode, expected_return, po_id, remarks, created_by)
    values (cid, coalesce(nullif(p ->> 'dc_date', '')::date, (now() at time zone 'Asia/Kolkata')::date), kd, pu, trim(p ->> 'party_name'), nullif(trim(coalesce(p ->> 'party_addr', '')), ''), nullif(trim(coalesce(p ->> 'party_gstin', '')), ''),
      nullif(trim(coalesce(p ->> 'vehicle_no', '')), ''), nullif(trim(coalesce(p ->> 'mode', '')), ''), case when kd = 'returnable' then nullif(p ->> 'expected_return', '')::date end,
      nullif(p ->> 'po_id', '')::uuid, nullif(trim(coalesce(p ->> 'remarks', '')), ''), me) returning id into did;
  else
    if not exists (select 1 from console.dcg_dc where id = did and customer_id = cid) then raise exception 'Unknown challan.'; end if;
    if not exists (select 1 from console.dcg_dc where id = did and status = 'draft') then raise exception 'An issued challan cannot be edited. Cancel it and make a new one.'; end if;
    update console.dcg_dc set dc_date = coalesce(nullif(p ->> 'dc_date', '')::date, dc_date), kind = kd, purpose = pu, party_name = trim(p ->> 'party_name'), party_addr = nullif(trim(coalesce(p ->> 'party_addr', '')), ''),
      party_gstin = nullif(trim(coalesce(p ->> 'party_gstin', '')), ''), vehicle_no = nullif(trim(coalesce(p ->> 'vehicle_no', '')), ''), mode = nullif(trim(coalesce(p ->> 'mode', '')), ''),
      expected_return = case when kd = 'returnable' then nullif(p ->> 'expected_return', '')::date end, po_id = nullif(p ->> 'po_id', '')::uuid, remarks = nullif(trim(coalesce(p ->> 'remarks', '')), ''), updated_at = now() where id = did;
    delete from console.dcg_dc_lines where dc_id = did;
  end if;
  for ln in select * from jsonb_array_elements(p -> 'lines') loop
    k := k + 1;
    if trim(coalesce(ln ->> 'description', '')) = '' then raise exception 'Item % has no description.', k; end if;
    if coalesce(nullif(ln ->> 'qty', '')::numeric, 0) <= 0 then raise exception 'Item % needs a quantity above zero.', k; end if;
    if nullif(ln ->> 'instrument_id', '') is not null and not exists (select 1 from console.cal_instruments where id = (ln ->> 'instrument_id')::uuid and customer_id = cid) then raise exception 'Item %: unknown gauge.', k; end if;
    insert into console.dcg_dc_lines (customer_id, dc_id, sl, instrument_id, item_code, description, uom, qty, hsn, value, remarks)
    values (cid, did, k, nullif(ln ->> 'instrument_id', '')::uuid, nullif(trim(coalesce(ln ->> 'item_code', '')), ''), trim(ln ->> 'description'), coalesce(nullif(trim(coalesce(ln ->> 'uom', '')), ''), 'Nos'),
      (ln ->> 'qty')::numeric, nullif(trim(coalesce(ln ->> 'hsn', '')), ''), nullif(ln ->> 'value', '')::numeric, nullif(trim(coalesce(ln ->> 'remarks', '')), ''));
  end loop;
  return did;
end $$;

-- issue: the number is given now; a calibration gauge becomes 'Out for calibration' in Calibration Hub
create or replace function public.kmr_dcg_dc_issue(p_slug text, p_id uuid) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'dcg'); me text := lower(coalesce(auth.jwt() ->> 'email', '')); d console.dcg_dc; no text; l record; ng int := 0;
begin
  select * into d from console.dcg_dc where id = p_id and customer_id = cid for update;
  if d.id is null then raise exception 'Unknown challan.'; end if;
  if d.status <> 'draft' then raise exception 'This challan is already %.', d.status; end if;
  if not exists (select 1 from console.dcg_dc_lines where dc_id = d.id) then raise exception 'Add at least one item.'; end if;
  if d.kind = 'returnable' and d.expected_return is null then raise exception 'Enter the expected return date for a returnable challan.'; end if;
  no := console.dcg_next(cid, 'dc');
  update console.dcg_dc set dc_no = no, status = 'issued', issued_by = me, issued_at = now(), updated_at = now() where id = d.id;
  if console.has_app(cid, 'calib') then
    for l in select * from console.dcg_dc_lines where dc_id = d.id and instrument_id is not null loop
      update console.cal_instruments set status = 'Out for calibration' where id = l.instrument_id and customer_id = cid and status not in ('Scrapped', 'Scrap');
      insert into console.cal_events (customer_id, instrument_id, ev_type, detail, by_email)
      values (cid, l.instrument_id, 'Sent out', 'Sent to ' || d.party_name || ' on ' || no || coalesce(' for ' || replace(d.purpose, '_', ' '), '') || coalesce(', expected back ' || to_char(d.expected_return, 'DD-Mon-YYYY'), ''), me);
      ng := ng + 1;
    end loop;
  end if;
  return jsonb_build_object('dc_no', no, 'gauges', ng);
end $$;

create or replace function public.kmr_dcg_dc_cancel(p_slug text, p_id uuid, p_reason text) returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'dcg'); me text := lower(coalesce(auth.jwt() ->> 'email', '')); d console.dcg_dc; l record;
begin
  select * into d from console.dcg_dc where id = p_id and customer_id = cid for update;
  if d.id is null then raise exception 'Unknown challan.'; end if;
  if d.status = 'cancelled' then raise exception 'Already cancelled.'; end if;
  if exists (select 1 from console.dcg_dc_lines where dc_id = d.id and returned_qty > 0) then raise exception 'Material has already come back on a GRN; cancel that GRN first.'; end if;
  if trim(coalesce(p_reason, '')) = '' and d.status <> 'draft' then raise exception 'Enter the reason for cancelling.'; end if;
  update console.dcg_dc set status = 'cancelled', cancel_reason = nullif(trim(coalesce(p_reason, '')), ''), updated_at = now() where id = d.id;
  if d.status <> 'draft' and console.has_app(cid, 'calib') then
    for l in select * from console.dcg_dc_lines where dc_id = d.id and instrument_id is not null loop
      update console.cal_instruments set status = 'In use' where id = l.instrument_id and customer_id = cid and status = 'Out for calibration';
      insert into console.cal_events (customer_id, instrument_id, ev_type, detail, by_email) values (cid, l.instrument_id, 'Challan cancelled', d.dc_no || ' cancelled; gauge back in use', me);
    end loop;
  end if;
end $$;

create or replace function public.kmr_dcg_dc_delete(p_slug text, p_id uuid) returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'dcg');
begin
  if not exists (select 1 from console.dcg_dc where id = p_id and customer_id = cid and status = 'draft') then raise exception 'Only a draft challan can be deleted. Cancel an issued one.'; end if;
  delete from console.dcg_dc where id = p_id;
end $$;

-- ---------- GRN ----------
-- p: { gtype, grn_date, po_id | dc_id, party_doc_no, party_doc_date, vehicle_no, remarks, lines:[{po_line_id | dc_line_id, received_qty, accepted_qty, rejected_qty, reject_reason,
--      cal_date, cert_no, lab, cal_result, as_found_ok, next_due, cost, description, item_code, uom}] }
create or replace function public.kmr_dcg_grn_save(p_slug text, p jsonb) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'dcg'); me text := lower(coalesce(auth.jwt() ->> 'email', '')); gt text := coalesce(p ->> 'gtype', '');
  d console.dcg_dc; po console.dcg_po; gid uuid; no text; ln jsonb; k int := 0; dl console.dcg_dc_lines; pl console.dcg_po_lines; i console.cal_instruments; ol console.rmp_orders;
  rq numeric; aq numeric; jq numeric; rid uuid; nd date; cres text; lg date; cd date; nrec int := 0; nrm int := 0; gdate date;
begin
  if gt not in ('po_receipt', 'dc_return', 'other') then raise exception 'Choose what this GRN is against.'; end if;
  if jsonb_typeof(p -> 'lines') is distinct from 'array' or jsonb_array_length(p -> 'lines') = 0 then raise exception 'Add at least one item.'; end if;
  gdate := coalesce(nullif(p ->> 'grn_date', '')::date, (now() at time zone 'Asia/Kolkata')::date);
  if gt = 'dc_return' then
    select * into d from console.dcg_dc where id = nullif(p ->> 'dc_id', '')::uuid and customer_id = cid for update;
    if d.id is null then raise exception 'Choose the delivery challan.'; end if;
    if d.status not in ('issued', 'part_returned') then raise exception 'Challan % is %; nothing to receive.', coalesce(d.dc_no, 'draft'), d.status; end if;
    if d.kind <> 'returnable' then raise exception 'A non-returnable challan has nothing to come back.'; end if;
  elsif gt = 'po_receipt' then
    select * into po from console.dcg_po where id = nullif(p ->> 'po_id', '')::uuid and customer_id = cid for update;
    if po.id is null then raise exception 'Choose the purchase order.'; end if;
    if po.status in ('closed', 'cancelled') then raise exception 'PO % is %.', po.po_no, po.status; end if;
  end if;
  no := console.dcg_next(cid, 'grn');
  insert into console.dcg_grn (customer_id, grn_no, grn_date, gtype, party_name, po_id, dc_id, party_doc_no, party_doc_date, vehicle_no, remarks, created_by)
  values (cid, no, gdate, gt, case gt when 'dc_return' then d.party_name when 'po_receipt' then po.supplier_name else nullif(trim(coalesce(p ->> 'party_name', '')), '') end,
    po.id, d.id, nullif(trim(coalesce(p ->> 'party_doc_no', '')), ''), nullif(p ->> 'party_doc_date', '')::date, nullif(trim(coalesce(p ->> 'vehicle_no', '')), ''), nullif(trim(coalesce(p ->> 'remarks', '')), ''), me)
  returning id into gid;
  for ln in select * from jsonb_array_elements(p -> 'lines') loop
    rq := coalesce(nullif(ln ->> 'received_qty', '')::numeric, 0);
    if rq <= 0 then continue; end if;                                 -- a line left at zero is simply not received
    k := k + 1;
    jq := coalesce(nullif(ln ->> 'rejected_qty', '')::numeric, 0);
    aq := coalesce(nullif(ln ->> 'accepted_qty', '')::numeric, rq - jq);
    if jq < 0 or aq < 0 or abs(aq + jq - rq) > 0.0001 then raise exception 'Line %: accepted plus rejected must equal the received quantity.', k; end if;
    if jq > 0 and trim(coalesce(ln ->> 'reject_reason', '')) = '' then raise exception 'Line %: enter the reason for the rejected quantity.', k; end if;
    dl := null; pl := null; i := null; rid := null;
    if gt = 'dc_return' then
      select * into dl from console.dcg_dc_lines where id = nullif(ln ->> 'dc_line_id', '')::uuid and dc_id = d.id for update;
      if dl.id is null then raise exception 'Line %: unknown challan item.', k; end if;
      if dl.returned_qty + rq > dl.qty + 0.0001 then raise exception 'Line %: only % of % is still to come back.', k, dl.qty - dl.returned_qty, dl.description; end if;
      update console.dcg_dc_lines set returned_qty = returned_qty + rq where id = dl.id;
      if dl.instrument_id is not null and console.has_app(cid, 'calib') then
        select * into i from console.cal_instruments where id = dl.instrument_id and customer_id = cid;
        if i.id is not null and d.purpose = 'calibration' then
          cd := nullif(ln ->> 'cal_date', '')::date;
          if cd is null then raise exception 'Line %: enter the calibration date shown on the certificate for gauge %.', k, i.tag; end if;
          cres := coalesce(nullif(ln ->> 'cal_result', ''), 'Pass');
          if cres not in ('Pass', 'Fail') then raise exception 'Line %: calibration result must be Pass or Fail.', k; end if;
          nd := coalesce(nullif(ln ->> 'next_due', '')::date, cd + (i.freq_months || ' months')::interval);
          select max(cal_date) into lg from console.cal_records where instrument_id = i.id and as_found_ok is not false and result = 'Pass';
          insert into console.cal_records (customer_id, instrument_id, cal_date, next_due, kind, lab, cert_no, as_found_ok, result, remarks, created_by, cost)
          values (cid, i.id, cd, nd, coalesce(i.cal_source, 'External'), coalesce(nullif(ln ->> 'lab', ''), d.party_name), nullif(ln ->> 'cert_no', ''), nullif(ln ->> 'as_found_ok', '')::boolean, cres,
            'Received back on ' || no || ' (sent on ' || coalesce(d.dc_no, '') || ')', me, nullif(ln ->> 'cost', '')::numeric) returning id into rid;
          if cres = 'Fail' then update console.cal_instruments set status = 'Quarantine' where id = i.id;
          else update console.cal_instruments set last_cal = cd, next_due = nd, status = 'In use' where id = i.id; end if;
          if (ln ->> 'as_found_ok') = 'false' then
            insert into console.cal_oot (customer_id, instrument_id, record_id, summary, last_good, risk, status)
            values (cid, i.id, rid, 'As-found out of tolerance at calibration on ' || to_char(cd, 'DD-Mon-YYYY') || ' (received on ' || no || ')', lg, 'High', 'Open');
          end if;
          insert into console.cal_events (customer_id, instrument_id, ev_type, detail, by_email)
          values (cid, i.id, 'Received back', 'Received on ' || no || ' from ' || d.party_name || ' — ' || cres || coalesce(', certificate ' || nullif(ln ->> 'cert_no', ''), ''), me);
          nrec := nrec + 1;
        elsif i.id is not null and i.status = 'Out for calibration' then
          update console.cal_instruments set status = 'In use' where id = i.id;           -- gauge back from repair / other work
        end if;
      end if;
    elsif gt = 'po_receipt' then
      select * into pl from console.dcg_po_lines where id = nullif(ln ->> 'po_line_id', '')::uuid and po_id = po.id for update;
      if pl.id is null then raise exception 'Line %: unknown PO item.', k; end if;
      if pl.received_qty + rq > pl.qty + 0.0001 then raise exception 'Line %: PO % has only % of % left to receive.', k, po.po_no, pl.qty - pl.received_qty, pl.description; end if;
      update console.dcg_po_lines set received_qty = received_qty + rq where id = pl.id;
      if pl.rmp_order_id is not null and console.has_app(cid, 'rmp') and lower(pl.uom) in ('kg', 'kgs') then
        select * into ol from console.rmp_orders where id = pl.rmp_order_id and customer_id = cid for update;
        if ol.id is not null and ol.status <> 'cancelled' then
          update console.rmp_orders set received_kg = coalesce(received_kg, 0) + aq, received_on = gdate, updated_at = now(), updated_by = me,
            status = case when pl.received_qty + rq >= pl.qty - 0.0001 then 'received' else 'ordered' end where id = ol.id;
          if aq > 0 then
            insert into console.rmp_stock (customer_id, material_code, on_hand_kg, updated_by) values (cid, ol.material_code, aq, me)
            on conflict (customer_id, material_code) do update set on_hand_kg = console.rmp_stock.on_hand_kg + aq, updated_at = now(), updated_by = excluded.updated_by;
          end if;
          nrm := nrm + 1;
        end if;
      end if;
    end if;
    insert into console.dcg_grn_lines (customer_id, grn_id, sl, po_line_id, dc_line_id, instrument_id, item_code, description, uom, received_qty, accepted_qty, rejected_qty, reject_reason,
      cal_date, cert_no, lab, cal_result, as_found_ok, next_due, cost, cal_record_id, remarks)
    values (cid, gid, k, pl.id, dl.id, dl.instrument_id,
      coalesce(dl.item_code, pl.item_code, nullif(ln ->> 'item_code', '')), coalesce(dl.description, pl.description, nullif(trim(coalesce(ln ->> 'description', '')), ''), 'Item'), coalesce(dl.uom, pl.uom, nullif(ln ->> 'uom', ''), 'Nos'),
      rq, aq, jq, nullif(trim(coalesce(ln ->> 'reject_reason', '')), ''), nullif(ln ->> 'cal_date', '')::date, nullif(ln ->> 'cert_no', ''), nullif(ln ->> 'lab', ''), nullif(ln ->> 'cal_result', ''),
      nullif(ln ->> 'as_found_ok', '')::boolean, nullif(ln ->> 'next_due', '')::date, nullif(ln ->> 'cost', '')::numeric, rid, nullif(trim(coalesce(ln ->> 'remarks', '')), ''));
  end loop;
  if k = 0 then raise exception 'Enter a received quantity for at least one item.'; end if;
  if gt = 'dc_return' then
    update console.dcg_dc set status = case when not exists (select 1 from console.dcg_dc_lines where dc_id = d.id and returned_qty < qty - 0.0001) then 'closed' else 'part_returned' end, updated_at = now() where id = d.id;
  elsif gt = 'po_receipt' then
    update console.dcg_po set status = case when not exists (select 1 from console.dcg_po_lines where po_id = po.id and received_qty < qty - 0.0001) then 'closed' else 'part_received' end, updated_at = now() where id = po.id;
  end if;
  return jsonb_build_object('id', gid, 'grn_no', no, 'calibrated', nrec, 'rmp_updated', nrm);
end $$;

-- cancel a GRN: quantities on the DC / PO and the raw material stock are put back. A calibration record written by it stays in Calibration Hub (delete it there).
create or replace function public.kmr_dcg_grn_cancel(p_slug text, p_id uuid, p_reason text) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'dcg'); me text := lower(coalesce(auth.jwt() ->> 'email', '')); g console.dcg_grn; l record; pl console.dcg_po_lines; ol console.rmp_orders; kept int := 0;
begin
  select * into g from console.dcg_grn where id = p_id and customer_id = cid for update;
  if g.id is null then raise exception 'Unknown GRN.'; end if;
  if g.status = 'cancelled' then raise exception 'Already cancelled.'; end if;
  if trim(coalesce(p_reason, '')) = '' then raise exception 'Enter the reason for cancelling.'; end if;
  for l in select * from console.dcg_grn_lines where grn_id = g.id loop
    if l.dc_line_id is not null then update console.dcg_dc_lines set returned_qty = greatest(0, returned_qty - l.received_qty) where id = l.dc_line_id; end if;
    if l.cal_record_id is not null then kept := kept + 1; end if;
    if l.po_line_id is not null then
      select * into pl from console.dcg_po_lines where id = l.po_line_id for update;
      update console.dcg_po_lines set received_qty = greatest(0, received_qty - l.received_qty) where id = l.po_line_id;
      if pl.rmp_order_id is not null and console.has_app(cid, 'rmp') and lower(pl.uom) in ('kg', 'kgs') then
        select * into ol from console.rmp_orders where id = pl.rmp_order_id and customer_id = cid for update;
        if ol.id is not null then
          update console.rmp_orders set received_kg = nullif(greatest(0, coalesce(received_kg, 0) - l.accepted_qty), 0), status = case when status = 'received' then 'ordered' else status end,
            received_on = case when greatest(0, coalesce(received_kg, 0) - l.accepted_qty) = 0 then null else received_on end, updated_at = now(), updated_by = me where id = ol.id;
          update console.rmp_stock set on_hand_kg = greatest(0, on_hand_kg - l.accepted_qty), updated_at = now(), updated_by = me where customer_id = cid and material_code = ol.material_code;
        end if;
      end if;
    end if;
  end loop;
  update console.dcg_grn set status = 'cancelled', cancel_reason = trim(p_reason) where id = g.id;
  if g.dc_id is not null then
    update console.dcg_dc set status = case when not exists (select 1 from console.dcg_dc_lines where dc_id = g.dc_id and returned_qty > 0) then 'issued'
      when not exists (select 1 from console.dcg_dc_lines where dc_id = g.dc_id and returned_qty < qty - 0.0001) then 'closed' else 'part_returned' end, updated_at = now() where id = g.dc_id and status <> 'cancelled';
    -- a gauge that had not been calibrated yet goes back to 'Out for calibration' only if no calibration record exists for the GRN
    if console.has_app(cid, 'calib') then
      update console.cal_instruments i set status = 'Out for calibration' from console.dcg_grn_lines l
       where l.grn_id = g.id and l.instrument_id = i.id and l.cal_record_id is null and i.status = 'In use';
    end if;
  end if;
  if g.po_id is not null then
    update console.dcg_po set status = case when not exists (select 1 from console.dcg_po_lines where po_id = g.po_id and received_qty > 0) then 'open'
      when not exists (select 1 from console.dcg_po_lines where po_id = g.po_id and received_qty < qty - 0.0001) then 'closed' else 'part_received' end where id = g.po_id and status <> 'cancelled';
  end if;
  return jsonb_build_object('cal_records_kept', kept);
end $$;

do $$ declare f record; begin
  for f in select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname ~ '^kmr_dcg_' loop
    execute format('revoke all on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
end $$;

-- ---------- platform functions: Data Master, clear-data, apps list in the portal ----------
do $wrap$ begin
  if to_regprocedure('console.app2_tables_dcg_base(text)') is null then
    alter function console.app2_tables(text) rename to app2_tables_dcg_base;
    create function console.app2_tables(p_app text) returns text[] language sql immutable as 'select case when p_app = ''dcg'' then array[''dcg_po'',''dcg_dc'',''dcg_grn''] else console.app2_tables_dcg_base(p_app) end';
    revoke all on function console.app2_tables(text) from public, anon, authenticated;
  end if;
  if to_regprocedure('console.app2_clear_dcg_base(text,uuid,boolean)') is null then
    alter function console.app2_clear(text, uuid, boolean) rename to app2_clear_dcg_base;
    create function console.app2_clear(p_app text, p_cid uuid, p_real_only boolean) returns bigint language plpgsql security definer set search_path = console, public as $f$
    declare n bigint := 0; m bigint;
    begin
      if p_app = 'dcg' then
        if p_real_only then return 0; end if;          -- there is no sample data: only a full clear removes the documents
        delete from console.dcg_grn where customer_id = p_cid; get diagnostics m = row_count; n := n + m;
        delete from console.dcg_dc where customer_id = p_cid; get diagnostics m = row_count; n := n + m;
        delete from console.dcg_po where customer_id = p_cid; get diagnostics m = row_count; n := n + m;
        delete from console.dcg_counters where customer_id = p_cid;
        return n;
      end if;
      return console.app2_clear_dcg_base(p_app, p_cid, p_real_only);
    end $f$;
    revoke all on function console.app2_clear(text, uuid, boolean) from public, anon, authenticated;
    revoke all on function console.app2_clear_dcg_base(text, uuid, boolean) from public, anon, authenticated;
  end if;
end $wrap$;

-- the apps a person may open (portal): same text patch as the other apps; a function that already has the change is left alone
do $patch$
declare rec record; def text; nw text; n int := 0;
begin
  for rec in
    select p.oid, p.proname from pg_proc p join pg_namespace s on s.oid = p.pronamespace
     where s.nspname = 'public' and p.proname in ('kmr_portal', 'kmr_portal_join')
  loop
    def := pg_get_functiondef(rec.oid); nw := def;
    if position('''dcg''' in def) = 0 then
      nw := regexp_replace(nw, $re$(\n\s*)(when 'dwm'\s+then console\.qp_member\(([a-z_.]+), em, 'dwm'\))$re$, E'\\1when ''dcg'' then console.qp_member(\\3, em, ''dcg'')\\1\\2');
    end if;
    if nw <> def then execute nw; n := n + 1; end if;
  end loop;
  raise notice 'DCG: % portal functions updated', n;
end $patch$;
