-- =====================================================================
-- 0118 — Sales Invoicing (INV) — a new KMR app, company / plant level
--  • Tax invoice made from the Operations Master (customers, parts, rate contracts); GST worked out from the lines (CGST + SGST inside the state, IGST outside), TCS, round-off
--  • Numbering per financial year; issue, cancel; e-invoice (IRN) details and e-way bill number kept on the invoice
--  • Files for the government e-invoice portal (JSON), the e-way bill portal (JSON) and Tally (XML sales vouchers) are made on the screen from the issued invoices
-- Needs 0048 (qp_*), 0091/0096 (portal patch anchors). Safe to re-run.
-- =====================================================================
insert into console.products (code, name, description, app_path, seat_label, current_version, sort_order) values
  ('inv', 'Sales Invoicing', 'Tax invoices with GST, e-invoice and e-way bill files, Tally sales export, linked to the Operations Master', '/it/inv.html', 'users', '1.0.0', 160)
on conflict (code) do update set name = excluded.name, description = excluded.description, app_path = excluded.app_path;
insert into console.releases (product_code, version, notes) values ('inv', '1.0.0', 'Sales Invoicing: tax invoice, GST, e-invoice JSON, e-way bill JSON, Tally XML, standards alignment, presentation') on conflict do nothing;
insert into console.prices (product_code, period, currency, unit_amount, min_seats, active, note)
select v.code, v.period, 'INR', v.amt, 1, true, 'Starting price list (0118) — change in Console • Billing' from (values ('inv', 'month', 2000), ('inv', 'year', 20000)) v(code, period, amt)
on conflict (product_code, period, currency) do nothing;
insert into public.app_listings (code, name, tagline, features, sort_order, is_active) values
  ('inv', 'Sales Invoicing', 'Make the GST tax invoice, get the e-invoice and e-way bill files, and send the sales to Tally.',
   E'Tax invoice with CGST / SGST / IGST, TCS and amount in words\nCustomers, parts and rates from the Operations Master\nE-invoice (IRN) and e-way bill files for the government portals\nTally sales voucher export', 160, true)
on conflict (code) do update set name = excluded.name, tagline = coalesce(public.app_listings.tagline, excluded.tagline), features = coalesce(public.app_listings.features, excluded.features);
insert into console.app_features (product_code, name, detail, is_core, price_month, price_year, setup_fee, sort_order) values
  ('inv', 'Tax invoicing', 'Tax invoice, GST, numbering, print, register', true, 2000, 0, 5000, 10),
  ('inv', 'E-invoice, e-way bill and Tally files', 'JSON files for the e-invoice and e-way bill portals and XML for Tally', false, 500, 0, 3000, 20)
on conflict (product_code, name) do nothing;

-- ---------- tables ----------
create table if not exists console.inv_settings (
  customer_id uuid primary key references console.customers(id) on delete cascade,
  legal_name text, trade_name text, gstin text, addr1 text, addr2 text, loc text, pin text, state_code text, phone text, email text,
  bank_name text, bank_acc text, bank_ifsc text, prefix text not null default 'INV', start_no int not null default 1,
  einv_on boolean not null default true, ewb_on boolean not null default true,
  tally_company text, tally_sales text not null default 'Sales', tally_cgst text not null default 'Output CGST', tally_sgst text not null default 'Output SGST', tally_igst text not null default 'Output IGST', tally_tcs text not null default 'TCS Receivable', tally_round text not null default 'Round Off',
  terms text, updated_at timestamptz not null default now());
create table if not exists console.inv_counters (customer_id uuid not null references console.customers(id) on delete cascade, fy text not null, n int not null default 0, primary key (customer_id, fy));
create table if not exists console.inv_invoice (
  id uuid primary key default gen_random_uuid(), customer_id uuid not null references console.customers(id) on delete cascade,
  inv_no text, inv_date date not null default current_date, doc_type text not null default 'INV' check (doc_type in ('INV', 'CRN', 'DBN')),
  supply_type text not null default 'B2B' check (supply_type in ('B2B', 'EXPWP', 'EXPWOP', 'SEZWP', 'SEZWOP')), reverse_charge boolean not null default false,
  buyer_code text, buyer_name text not null, buyer_gstin text, buyer_addr text, buyer_loc text, buyer_pin text, buyer_state text,
  po_no text, po_date date, dc_no text, dc_date date, vehicle_no text, mode text, transporter text, transporter_id text, distance_km int, delivery_terms text, pay_days int, remarks text,
  taxable numeric not null default 0, cgst numeric not null default 0, sgst numeric not null default 0, igst numeric not null default 0, tcs_pct numeric not null default 0, tcs numeric not null default 0, round_off numeric not null default 0, total numeric not null default 0,
  status text not null default 'draft' check (status in ('draft', 'issued', 'cancelled')), issued_at timestamptz, issued_by text, cancel_reason text,
  irn text, ack_no text, ack_date date, ewb_no text, ewb_date date, tally_at timestamptz, einv_at timestamptz,
  created_by text, created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique (customer_id, inv_no));
create table if not exists console.inv_lines (
  id uuid primary key default gen_random_uuid(), customer_id uuid not null references console.customers(id) on delete cascade, inv_id uuid not null references console.inv_invoice(id) on delete cascade,
  sl int not null default 1, item_code text, description text not null, hsn text, uom text not null default 'Nos', qty numeric not null check (qty > 0), rate numeric not null default 0, discount numeric not null default 0,
  gst_rate numeric not null default 18, taxable numeric not null default 0, cgst numeric not null default 0, sgst numeric not null default 0, igst numeric not null default 0, packing text);
create index if not exists inv_invoice_cust on console.inv_invoice (customer_id, inv_date);
create index if not exists inv_lines_inv on console.inv_lines (inv_id);
do $$ declare t text; begin
  foreach t in array array['inv_settings', 'inv_counters', 'inv_invoice', 'inv_lines'] loop
    execute format('alter table console.%I enable row level security', t);
    execute format('drop policy if exists %I on console.%I', t || '_staff', t);
    execute format('create policy %I on console.%I for all to authenticated using (console.is_staff()) with check (console.is_staff())', t || '_staff', t);
  end loop;
end $$;

-- ---------- numbering: INV/26-27/0001 (financial year April to March, India time); the first number of a year can be set in Settings ----------
create or replace function console.inv_next(p_cid uuid) returns text language plpgsql security definer set search_path = console, public as $$
declare d date := (now() at time zone 'Asia/Kolkata')::date; y int := extract(year from d)::int; v_fy text; v_n int; v_pre text; v_start int;
begin
  if extract(month from d) < 4 then y := y - 1; end if;
  v_fy := lpad((y % 100)::text, 2, '0') || '-' || lpad(((y + 1) % 100)::text, 2, '0');
  select coalesce(nullif(trim(prefix), ''), 'INV'), greatest(start_no, 1) into v_pre, v_start from console.inv_settings where customer_id = p_cid;
  v_pre := coalesce(v_pre, 'INV'); v_start := coalesce(v_start, 1);
  insert into console.inv_counters as c (customer_id, fy, n) values (p_cid, v_fy, v_start)
  on conflict (customer_id, fy) do update set n = c.n + 1 returning c.n into v_n;
  return v_pre || '/' || v_fy || '/' || lpad(v_n::text, 4, '0');
end $$;
revoke all on function console.inv_next(uuid) from public, anon, authenticated;

create or replace function public.kmr_inv_context(p_slug text) returns jsonb language sql stable security definer set search_path = console, public as $$
  select case when console.qp_role(c.id, 'inv') is null then null
    else jsonb_build_object('role', console.qp_role(c.id, 'inv'), 'company', c.name, 'logo_url', c.logo_url, 'is_staff', coalesce(console.is_staff(), false),
      'settings', coalesce((select to_jsonb(s) - 'customer_id' from console.inv_settings s where s.customer_id = c.id), '{}'::jsonb)) end
  from console.customers c where c.slug = lower(p_slug) $$;

create or replace function public.kmr_inv_load(p_slug text, p_months int default 6) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'inv'); since date := (current_date - make_interval(months => greatest(1, least(coalesce(p_months, 6), 36))))::date;
begin
  return jsonb_build_object(
    'settings', coalesce((select to_jsonb(s) - 'customer_id' from console.inv_settings s where s.customer_id = cid), '{}'::jsonb),
    'invoices', coalesce((select jsonb_agg(jsonb_strip_nulls(to_jsonb(i) - 'customer_id' || jsonb_build_object('lines', coalesce((select jsonb_agg(to_jsonb(l) - 'customer_id' order by l.sl) from console.inv_lines l where l.inv_id = i.id), '[]'::jsonb))) order by i.inv_date desc, i.created_at desc)
                     from console.inv_invoice i where i.customer_id = cid and (i.inv_date >= since or i.status = 'draft')), '[]'::jsonb),
    'older', (select count(*) from console.inv_invoice i where i.customer_id = cid and i.inv_date < since and i.status <> 'draft'));
end $$;

-- customers, parts and customer rates from the Operations Master
create or replace function public.kmr_inv_masters(p_slug text) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'inv');
begin
  return jsonb_build_object(
    'customers', coalesce((select jsonb_agg(jsonb_build_object('code', r.code, 'name', r.name, 'gstin', coalesce(r.data ->> 'gstin', ''), 'addr', concat_ws(', ', nullif(r.data ->> 'address', ''), nullif(r.data ->> 'city', '')),
              'state', coalesce(r.data ->> 'state_code', ''), 'pin', coalesce(r.data ->> 'pin', '')) order by r.name) from console.ops_records r where r.customer_id = cid and r.active and r.kind = 'customers'), '[]'::jsonb),
    'parts', coalesce((select jsonb_agg(jsonb_build_object('code', r.code, 'name', r.name, 'hsn', coalesce(r.data ->> 'hsn', r.data ->> 'hsn_code', ''), 'uom', coalesce(nullif(r.data ->> 'uom', ''), 'Nos')) order by r.code)
              from console.ops_records r where r.customer_id = cid and r.active and r.kind = 'parts'), '[]'::jsonb),
    'rates', coalesce((select jsonb_agg(jsonb_build_object('party', r.name, 'item', r.data ->> 'item', 'rate', r.data ->> 'rate', 'valid_to', r.data ->> 'valid_to') order by r.name)
              from console.ops_records r where r.customer_id = cid and r.active and r.kind = 'rate_contracts' and lower(coalesce(r.data ->> 'party_type', '')) = 'customer'), '[]'::jsonb));
end $$;

create or replace function public.kmr_inv_settings_save(p_slug text, p jsonb) returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'inv');
begin
  if console.qp_role(cid, 'inv') <> 'admin' then raise exception 'Only an administrator can change the invoicing settings.'; end if;
  insert into console.inv_settings (customer_id, legal_name, trade_name, gstin, addr1, addr2, loc, pin, state_code, phone, email, bank_name, bank_acc, bank_ifsc, prefix, start_no, einv_on, ewb_on,
      tally_company, tally_sales, tally_cgst, tally_sgst, tally_igst, tally_tcs, tally_round, terms)
  values (cid, p ->> 'legal_name', p ->> 'trade_name', upper(trim(p ->> 'gstin')), p ->> 'addr1', p ->> 'addr2', p ->> 'loc', p ->> 'pin', p ->> 'state_code', p ->> 'phone', p ->> 'email', p ->> 'bank_name', p ->> 'bank_acc', p ->> 'bank_ifsc',
      coalesce(nullif(trim(p ->> 'prefix'), ''), 'INV'), greatest(coalesce(nullif(p ->> 'start_no', '')::int, 1), 1), coalesce((p ->> 'einv_on')::boolean, true), coalesce((p ->> 'ewb_on')::boolean, true),
      p ->> 'tally_company', coalesce(nullif(p ->> 'tally_sales', ''), 'Sales'), coalesce(nullif(p ->> 'tally_cgst', ''), 'Output CGST'), coalesce(nullif(p ->> 'tally_sgst', ''), 'Output SGST'), coalesce(nullif(p ->> 'tally_igst', ''), 'Output IGST'),
      coalesce(nullif(p ->> 'tally_tcs', ''), 'TCS Receivable'), coalesce(nullif(p ->> 'tally_round', ''), 'Round Off'), p ->> 'terms')
  on conflict (customer_id) do update set legal_name = excluded.legal_name, trade_name = excluded.trade_name, gstin = excluded.gstin, addr1 = excluded.addr1, addr2 = excluded.addr2, loc = excluded.loc, pin = excluded.pin,
      state_code = excluded.state_code, phone = excluded.phone, email = excluded.email, bank_name = excluded.bank_name, bank_acc = excluded.bank_acc, bank_ifsc = excluded.bank_ifsc, prefix = excluded.prefix, start_no = excluded.start_no,
      einv_on = excluded.einv_on, ewb_on = excluded.ewb_on, tally_company = excluded.tally_company, tally_sales = excluded.tally_sales, tally_cgst = excluded.tally_cgst, tally_sgst = excluded.tally_sgst, tally_igst = excluded.tally_igst,
      tally_tcs = excluded.tally_tcs, tally_round = excluded.tally_round, terms = excluded.terms, updated_at = now();
end $$;

-- save a draft (or change one): the amounts are worked out here from the lines
create or replace function public.kmr_inv_save(p_slug text, p jsonb) returns uuid language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'inv'); me text := lower(coalesce(auth.jwt() ->> 'email', '')); iid uuid := nullif(p ->> 'id', '')::uuid; ln jsonb; k int := 0;
  sst text; bst text; intra boolean; tx numeric; c numeric; s numeric; g numeric; gr numeric; q numeric; rt numeric; ds numeric; tt numeric := 0; tc numeric := 0; ts numeric := 0; ti numeric := 0; tcsp numeric; tcsv numeric; raw numeric; ttl numeric;
begin
  if trim(coalesce(p ->> 'buyer_name', '')) = '' then raise exception 'Choose or enter the customer.'; end if;
  if jsonb_array_length(coalesce(p -> 'lines', '[]'::jsonb)) = 0 then raise exception 'Add at least one item.'; end if;
  select state_code into sst from console.inv_settings where customer_id = cid;
  bst := coalesce(nullif(substr(trim(coalesce(p ->> 'buyer_gstin', '')), 1, 2), ''), nullif(trim(p ->> 'buyer_state'), ''), sst);
  intra := coalesce(nullif(p ->> 'supply_type', ''), 'B2B') = 'B2B' and coalesce(bst, '') = coalesce(sst, '') and coalesce(sst, '') <> '';
  tcsp := coalesce(nullif(p ->> 'tcs_pct', '')::numeric, 0);
  if iid is null then
    insert into console.inv_invoice (customer_id, inv_date, doc_type, supply_type, reverse_charge, buyer_name, created_by) values (cid, coalesce(nullif(p ->> 'inv_date', '')::date, current_date), 'INV', 'B2B', false, p ->> 'buyer_name', me) returning id into iid;
  else
    if not exists (select 1 from console.inv_invoice where id = iid and customer_id = cid and status = 'draft') then raise exception 'Only a draft invoice can be changed.'; end if;
    delete from console.inv_lines where inv_id = iid;
  end if;
  for ln in select * from jsonb_array_elements(p -> 'lines') loop
    q := coalesce(nullif(ln ->> 'qty', '')::numeric, 0); rt := coalesce(nullif(ln ->> 'rate', '')::numeric, 0); ds := coalesce(nullif(ln ->> 'discount', '')::numeric, 0); gr := coalesce(nullif(ln ->> 'gst_rate', '')::numeric, 18);
    continue when q <= 0 or trim(coalesce(ln ->> 'description', '')) = '';
    k := k + 1; tx := round(q * rt - ds, 2);
    if (p ->> 'supply_type') in ('EXPWOP', 'SEZWOP') then gr := 0; end if;
    if intra then c := round(tx * gr / 200, 2); s := c; g := 0; else c := 0; s := 0; g := round(tx * gr / 100, 2); end if;
    insert into console.inv_lines (customer_id, inv_id, sl, item_code, description, hsn, uom, qty, rate, discount, gst_rate, taxable, cgst, sgst, igst, packing)
    values (cid, iid, k, ln ->> 'item_code', ln ->> 'description', ln ->> 'hsn', coalesce(nullif(ln ->> 'uom', ''), 'Nos'), q, rt, ds, gr, tx, c, s, g, ln ->> 'packing');
    tt := tt + tx; tc := tc + c; ts := ts + s; ti := ti + g;
  end loop;
  if k = 0 then raise exception 'Add at least one item with a quantity.'; end if;
  tcsv := round((tt + tc + ts + ti) * tcsp / 100, 2); raw := tt + tc + ts + ti + tcsv; ttl := round(raw, 0);
  update console.inv_invoice set inv_date = coalesce(nullif(p ->> 'inv_date', '')::date, current_date), doc_type = coalesce(nullif(p ->> 'doc_type', ''), 'INV'), supply_type = coalesce(nullif(p ->> 'supply_type', ''), 'B2B'),
    reverse_charge = coalesce((p ->> 'reverse_charge')::boolean, false), buyer_code = p ->> 'buyer_code', buyer_name = trim(p ->> 'buyer_name'), buyer_gstin = upper(nullif(trim(coalesce(p ->> 'buyer_gstin', '')), '')),
    buyer_addr = p ->> 'buyer_addr', buyer_loc = p ->> 'buyer_loc', buyer_pin = p ->> 'buyer_pin', buyer_state = bst, po_no = p ->> 'po_no', po_date = nullif(p ->> 'po_date', '')::date, dc_no = p ->> 'dc_no', dc_date = nullif(p ->> 'dc_date', '')::date,
    vehicle_no = p ->> 'vehicle_no', mode = p ->> 'mode', transporter = p ->> 'transporter', transporter_id = p ->> 'transporter_id', distance_km = nullif(p ->> 'distance_km', '')::int, delivery_terms = p ->> 'delivery_terms',
    pay_days = nullif(p ->> 'pay_days', '')::int, remarks = p ->> 'remarks', taxable = tt, cgst = tc, sgst = ts, igst = ti, tcs_pct = tcsp, tcs = tcsv, round_off = ttl - raw, total = ttl, updated_at = now()
   where id = iid;
  return iid;
end $$;

create or replace function public.kmr_inv_issue(p_slug text, p_id uuid) returns text language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'inv'); me text := lower(coalesce(auth.jwt() ->> 'email', '')); i record; st record; no text;
begin
  select * into i from console.inv_invoice where id = p_id and customer_id = cid for update;
  if i.id is null or i.status <> 'draft' then raise exception 'Only a draft invoice can be issued.'; end if;
  select * into st from console.inv_settings where customer_id = cid;
  if st.customer_id is null or coalesce(st.gstin, '') = '' or coalesce(st.state_code, '') = '' then raise exception 'Fill in the seller details (GSTIN, state code, address) in Settings first.'; end if;
  if i.supply_type = 'B2B' and coalesce(length(i.buyer_gstin), 0) <> 15 then raise exception 'A B2B invoice needs the customer''s 15-character GSTIN.'; end if;
  no := console.inv_next(cid);
  update console.inv_invoice set inv_no = no, status = 'issued', issued_at = now(), issued_by = me, updated_at = now() where id = p_id;
  return no;
end $$;

create or replace function public.kmr_inv_cancel(p_slug text, p_id uuid, p_reason text) returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'inv');
begin
  if trim(coalesce(p_reason, '')) = '' then raise exception 'Give the reason for cancelling.'; end if;
  update console.inv_invoice set status = 'cancelled', cancel_reason = trim(p_reason), updated_at = now() where id = p_id and customer_id = cid and status = 'issued';
  if not found then raise exception 'Only an issued invoice can be cancelled.'; end if;
end $$;

create or replace function public.kmr_inv_delete(p_slug text, p_id uuid) returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'inv');
begin
  delete from console.inv_invoice where id = p_id and customer_id = cid and status = 'draft';
  if not found then raise exception 'Only a draft invoice can be deleted.'; end if;
end $$;

-- the IRN / acknowledgement from the e-invoice portal and the e-way bill number are written back on the invoice
create or replace function public.kmr_inv_gov_save(p_slug text, p_id uuid, p jsonb) returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'inv');
begin
  update console.inv_invoice set irn = coalesce(nullif(trim(p ->> 'irn'), ''), irn), ack_no = coalesce(nullif(trim(p ->> 'ack_no'), ''), ack_no), ack_date = coalesce(nullif(p ->> 'ack_date', '')::date, ack_date),
    einv_at = case when nullif(trim(p ->> 'irn'), '') is not null then now() else einv_at end,
    ewb_no = coalesce(nullif(trim(p ->> 'ewb_no'), ''), ewb_no), ewb_date = coalesce(nullif(p ->> 'ewb_date', '')::date, ewb_date), updated_at = now()
   where id = p_id and customer_id = cid and status = 'issued';
  if not found then raise exception 'Invoice not found or not issued.'; end if;
end $$;

create or replace function public.kmr_inv_tally_mark(p_slug text, p_ids jsonb) returns int language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'inv'); n int;
begin
  update console.inv_invoice set tally_at = now() where customer_id = cid and id in (select value::uuid from jsonb_array_elements_text(p_ids));
  get diagnostics n = row_count; return n;
end $$;

-- ---------- platform functions: Data Master, clear-data, apps list in the portal ----------
do $wrap$ begin
  if to_regprocedure('console.app2_tables_inv_base(text)') is null then
    alter function console.app2_tables(text) rename to app2_tables_inv_base;
    create function console.app2_tables(p_app text) returns text[] language sql immutable as 'select case when p_app = ''inv'' then array[''inv_invoice''] else console.app2_tables_inv_base(p_app) end';
    revoke all on function console.app2_tables(text) from public, anon, authenticated;
  end if;
  if to_regprocedure('console.app2_clear_inv_base(text,uuid,boolean)') is null then
    alter function console.app2_clear(text, uuid, boolean) rename to app2_clear_inv_base;
    create function console.app2_clear(p_app text, p_cid uuid, p_real_only boolean) returns bigint language plpgsql security definer set search_path = console, public as $f$
    declare n bigint := 0; m bigint;
    begin
      if p_app = 'inv' then
        if p_real_only then return 0; end if;
        delete from console.inv_invoice where customer_id = p_cid; get diagnostics m = row_count; n := n + m;
        delete from console.inv_counters where customer_id = p_cid;
        return n;
      end if;
      return console.app2_clear_inv_base(p_app, p_cid, p_real_only);
    end $f$;
    revoke all on function console.app2_clear(text, uuid, boolean) from public, anon, authenticated;
    revoke all on function console.app2_clear_inv_base(text, uuid, boolean) from public, anon, authenticated;
  end if;
end $wrap$;

do $patch$
declare rec record; def text; nw text; n int := 0;
begin
  for rec in select p.oid, p.proname from pg_proc p join pg_namespace s on s.oid = p.pronamespace where s.nspname = 'public' and p.proname in ('kmr_portal', 'kmr_portal_join') loop
    def := pg_get_functiondef(rec.oid); nw := def;
    if position('''inv''' in def) = 0 then
      nw := regexp_replace(nw, $re$(\n\s*)(when 'dwm'\s+then console\.qp_member\(([a-z_.]+), em, 'dwm'\))$re$, E'\\1when ''inv'' then console.qp_member(\\3, em, ''inv'')\\1\\2');
    end if;
    if nw <> def then execute nw; n := n + 1; end if;
  end loop;
  raise notice 'INV: % portal functions updated', n;
end $patch$;

do $$ declare f record; begin
  for f in select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname ~ '^kmr_inv_' loop
    execute format('revoke all on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
end $$;
