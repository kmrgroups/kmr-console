-- ================= CRM & RFQ: helpers =================
create or replace function console.crm_next(p_cid uuid, p_key text) returns bigint language sql security definer set search_path = console, public as $$
  insert into console.crm_counters (customer_id, key, n) values (p_cid, p_key, 1)
  on conflict (customer_id, key) do update set n = console.crm_counters.n + 1 returning n $$;
create or replace function console.crm_me() returns text language sql stable as $$ select lower(coalesce(auth.jwt() ->> 'email', '')) $$;
create or replace function console.crm_txt(p jsonb, k text) returns text language sql immutable as $$ select nullif(trim(coalesce(p ->> k, '')), '') $$;
create or replace function console.crm_num(p jsonb, k text) returns numeric language sql immutable as $$
  select case when coalesce(p ->> k, '') ~ '^\s*-?\d+(\.\d+)?([eE][-+]?\d+)?\s*$' then (p ->> k)::numeric else null end $$;
create or replace function console.crm_pos(p jsonb, k text) returns numeric language sql immutable as $$ select greatest(coalesce(console.crm_num(p, k), 0), 0) $$;
create or replace function console.crm_date(p jsonb, k text) returns date language plpgsql immutable as $$
begin
  if coalesce(p ->> k, '') = '' then return null; end if;
  return (p ->> k)::date;
exception when others then raise exception 'The date entered (%) is not valid.', p ->> k;
end $$;
create or replace function console.crm_today() returns date language sql stable as $$ select (now() at time zone 'Asia/Kolkata')::date $$;
-- salary-like sensitive data here is cost and margin: only editors and administrators see it
create or replace function console.crm_money(p_cid uuid) returns boolean language sql stable security definer set search_path = console, public as $$
  select coalesce(console.qp_role(p_cid, 'crm'), '') in ('admin', 'editor') $$;
create or replace function console.crm_cfg(p_cid uuid) returns jsonb language sql stable security definer set search_path = console, public as $$
  select coalesce((select data from console.crm_settings where customer_id = p_cid), '{}'::jsonb) $$;

-- the next number: PREFIX/26-27/0001 (financial year, April to March) or PREFIX-0001, prefixes set in Setup
create or replace function console.crm_number(p_cid uuid, p_kind text) returns text language plpgsql security definer set search_path = console, public as $$
declare cfg jsonb := console.crm_cfg(p_cid); pre text; d date := console.crm_today(); y int; fyt text; n bigint; use_fy boolean := true;
begin
  pre := coalesce(console.crm_txt(cfg, case p_kind when 'LD' then 'lead_prefix' when 'RFQ' then 'rfq_prefix' else 'quote_prefix' end), p_kind);
  pre := upper(regexp_replace(pre, '[^A-Za-z0-9-]', '', 'g')); if pre = '' then pre := p_kind; end if;
  if jsonb_typeof(cfg -> 'fy_numbering') = 'boolean' then use_fy := (cfg ->> 'fy_numbering')::boolean; end if;
  if use_fy then
    y := extract(year from d)::int; if extract(month from d) < 4 then y := y - 1; end if;
    fyt := lpad((y % 100)::text, 2, '0') || '-' || lpad(((y + 1) % 100)::text, 2, '0');
    n := console.crm_next(p_cid, p_kind || '-' || fyt);
    return pre || '/' || fyt || '/' || lpad(n::text, 4, '0');
  end if;
  n := console.crm_next(p_cid, p_kind);
  return pre || '-' || lpad(n::text, 4, '0');
end $$;

-- costing sheet of one part, per piece. Inputs are never negative. The browser shows the same arithmetic (crm-calc.js).
--   material  = weight x rate x (1 + scrap %) + other material
--   process   = sum of (minutes x rate per hour / 60)
--   outsourced, tooling (tool cost / pieces it will make), packing, freight, other
--   cost      = the sum; overhead = cost x overhead %; price = (cost + overhead) x (1 + margin %), or the price typed in
create or replace function console.crm_cost(c jsonb) returns jsonb language plpgsql immutable as $$
declare mat numeric; prc numeric := 0; outs numeric := 0; tool numeric; pack numeric; frt numeric; oth numeric; cost numeric; oh numeric; base numeric; calc numeric; ov numeric; price numeric; o jsonb;
begin
  c := case when jsonb_typeof(c) = 'object' then c else '{}'::jsonb end;
  mat := console.crm_pos(c, 'mat_wt') * console.crm_pos(c, 'mat_rate') * (1 + console.crm_pos(c, 'scrap_pct') / 100) + console.crm_pos(c, 'mat_other');
  if jsonb_typeof(c -> 'ops') = 'array' then
    for o in select * from jsonb_array_elements(c -> 'ops') loop prc := prc + console.crm_pos(o, 'min') * console.crm_pos(o, 'rate') / 60; end loop;
  end if;
  if jsonb_typeof(c -> 'outs') = 'array' then
    for o in select * from jsonb_array_elements(c -> 'outs') loop outs := outs + console.crm_pos(o, 'amt'); end loop;
  end if;
  tool := case when console.crm_pos(c, 'tool_qty') > 0 then console.crm_pos(c, 'tool_cost') / console.crm_pos(c, 'tool_qty') else 0 end;
  pack := console.crm_pos(c, 'packing'); frt := console.crm_pos(c, 'freight'); oth := console.crm_pos(c, 'other');
  cost := mat + prc + outs + tool + pack + frt + oth;
  oh := cost * console.crm_pos(c, 'oh_pct') / 100; base := cost + oh;
  calc := base * (1 + console.crm_pos(c, 'margin_pct') / 100); ov := console.crm_pos(c, 'price_override');
  price := round(case when ov > 0 then ov else calc end, 2);
  return jsonb_build_object('material', round(mat, 4), 'process', round(prc, 4), 'outsourced', round(outs, 4), 'tooling', round(tool, 4), 'packing', round(pack, 4), 'freight', round(frt, 4), 'other', round(oth, 4),
    'cost', round(cost, 4), 'overhead', round(oh, 4), 'total_cost', round(base, 4), 'price_calc', round(calc, 2), 'price', price);
end $$;

-- quotation totals from its lines
create or replace function console.crm_totals(p_lines jsonb, p_tax numeric, out sub numeric, out tax numeric, out tot numeric) language plpgsql immutable as $$
begin
  select coalesce(sum(round(console.crm_pos(l, 'qty') * console.crm_pos(l, 'unit_price'), 2)), 0) into sub
    from jsonb_array_elements(case when jsonb_typeof(p_lines) = 'array' then p_lines else '[]'::jsonb end) l;
  tax := round(sub * greatest(coalesce(p_tax, 0), 0) / 100, 2); tot := sub + tax;
end $$;
revoke all on function console.crm_next(uuid, text), console.crm_money(uuid), console.crm_cfg(uuid), console.crm_number(uuid, text) from public, anon, authenticated;

create or replace function console.crm_party_json(p console.crm_parties) returns jsonb language sql stable as $$
  select jsonb_build_object('id', p.id, 'code', p.code, 'kind', p.kind, 'name', p.name, 'industry', p.industry, 'gstin', p.gstin, 'pan', p.pan, 'address', p.address, 'city', p.city, 'state', p.state,
    'country', p.country, 'pincode', p.pincode, 'website', p.website, 'payment_terms', p.payment_terms, 'credit_days', p.credit_days, 'owner', p.owner, 'status', p.status, 'notes', p.notes, 'sample', p.sample, 'updated_at', p.updated_at) $$;
create or replace function console.crm_lead_json(l console.crm_leads) returns jsonb language sql stable as $$
  select jsonb_build_object('id', l.id, 'no', l.no, 'party_id', l.party_id, 'company', l.company, 'contact_name', l.contact_name, 'designation', l.designation, 'phone', l.phone, 'email', l.email,
    'source', l.source, 'stage', l.stage, 'product_interest', l.product_interest, 'value', l.value, 'expected_close', l.expected_close, 'owner', l.owner, 'next_followup', l.next_followup,
    'lost_reason', l.lost_reason, 'notes', l.notes, 'closed_at', l.closed_at, 'sample', l.sample, 'created_at', l.created_at, 'updated_at', l.updated_at) $$;
create or replace function console.crm_act_json(a console.crm_activities) returns jsonb language sql stable as $$
  select jsonb_build_object('id', a.id, 'lead_id', a.lead_id, 'party_id', a.party_id, 'rfq_id', a.rfq_id, 'kind', a.kind, 'subject', a.subject, 'notes', a.notes, 'due_date', a.due_date,
    'done', a.done, 'done_at', a.done_at, 'owner', a.owner, 'sample', a.sample, 'created_by', a.created_by, 'created_at', a.created_at) $$;
create or replace function console.crm_item_json(i console.crm_rfq_items, p_money boolean) returns jsonb language sql stable as $$
  select jsonb_build_object('id', i.id, 'seq', i.seq, 'part_no', i.part_no, 'part_name', i.part_name, 'drawing_no', i.drawing_no, 'revision', i.revision, 'material', i.material, 'qty', i.qty,
    'annual_qty', i.annual_qty, 'uom', i.uom, 'target_price', i.target_price, 'unit_price', i.unit_price, 'remarks', i.remarks)
    || case when p_money then jsonb_build_object('cost', i.cost, 'unit_cost', i.unit_cost) else '{}'::jsonb end $$;
create or replace function console.crm_sq_json(s console.crm_supplier_quotes) returns jsonb language sql stable security definer set search_path = console, public as $$
  select jsonb_build_object('id', s.id, 'rfq_id', s.rfq_id, 'item_id', s.item_id, 'supplier_id', s.supplier_id, 'supplier_name', (select name from console.crm_parties where id = s.supplier_id),
    'supplier_code', (select code from console.crm_parties where id = s.supplier_id), 'what', s.what, 'price', s.price, 'moq', s.moq, 'lead_days', s.lead_days, 'valid_until', s.valid_until,
    'payment_terms', s.payment_terms, 'quote_ref', s.quote_ref, 'received_on', s.received_on, 'selected', s.selected, 'notes', s.notes, 'sample', s.sample) $$;
create or replace function console.crm_quote_json(q console.crm_quotes, p_full boolean) returns jsonb language sql stable security definer set search_path = console, public as $$
  select jsonb_build_object('id', q.id, 'no', q.no, 'rev', q.rev, 'rfq_id', q.rfq_id, 'rfq_no', (select no from console.crm_rfqs where id = q.rfq_id), 'party_id', q.party_id,
    'party_name', (select name from console.crm_parties where id = q.party_id), 'quote_date', q.quote_date, 'valid_until', q.valid_until, 'status', q.status, 'currency', q.currency,
    'tax_name', q.tax_name, 'tax_pct', q.tax_pct, 'subtotal', q.subtotal, 'tax_amt', q.tax_amt, 'total', q.total, 'sent_on', q.sent_on, 'decided_on', q.decided_on, 'sample', q.sample, 'updated_at', q.updated_at,
    'items', jsonb_array_length(q.lines))
    || case when p_full then jsonb_build_object('contact_id', q.contact_id, 'payment_terms', q.payment_terms, 'delivery_terms', q.delivery_terms, 'terms', q.terms, 'remarks', q.remarks, 'lines', q.lines,
        'prepared_by', q.prepared_by, 'party', (select console.crm_party_json(p) from console.crm_parties p where p.id = q.party_id),
        'contact', (select to_jsonb(c) - 'customer_id' - 'sample' from console.crm_contacts c where c.id = q.contact_id),
        'rfq_customer_ref', (select customer_ref from console.crm_rfqs where id = q.rfq_id), 'rfq_project', (select project from console.crm_rfqs where id = q.rfq_id))
      else '{}'::jsonb end $$;
revoke all on function console.crm_party_json(console.crm_parties), console.crm_lead_json(console.crm_leads), console.crm_act_json(console.crm_activities), console.crm_item_json(console.crm_rfq_items, boolean),
  console.crm_sq_json(console.crm_supplier_quotes), console.crm_quote_json(console.crm_quotes, boolean) from public, anon, authenticated;

-- ================= access, setup =================
create or replace function public.kmr_crm_enabled(p_slug text) returns boolean language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  return cid is not null and console.qp_role(cid, 'crm') is not null;
end $$;

create or replace function public.kmr_crm_load(p_slug text) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'crm');
begin
  return jsonb_build_object('role', console.qp_role(cid, 'crm'), 'money', console.crm_money(cid), 'me', console.crm_me(), 'today', console.crm_today(), 'settings', console.crm_cfg(cid),
    'parties', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'code', p.code, 'kind', p.kind, 'name', p.name, 'status', p.status) order by p.name) from (select * from console.crm_parties where customer_id = cid order by name limit 3000) p), '[]'),
    'contacts', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'party_id', c.party_id, 'name', c.name, 'designation', c.designation, 'email', c.email, 'phone', coalesce(c.mobile, c.phone), 'is_primary', c.is_primary) order by c.name)
        from (select * from console.crm_contacts where customer_id = cid order by name limit 5000) c), '[]'),
    'owners', coalesce((select jsonb_agg(distinct m.email) from console.customer_members m where m.customer_id = cid and (m.is_admin or coalesce(m.roles ->> 'crm', '') <> '')), '[]'));
end $$;

create or replace function public.kmr_crm_settings_save(p_slug text, p jsonb) returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'crm'); t numeric;
begin
  if console.qp_role(cid, 'crm') <> 'admin' then raise exception 'Only an administrator can change the setup.'; end if;
  if jsonb_typeof(p) <> 'object' then raise exception 'Settings must be an object.'; end if;
  if length(p::text) > 60000 then raise exception 'The settings are too large.'; end if;
  t := console.crm_num(p, 'tax_pct'); if t is not null and (t < 0 or t > 100) then raise exception 'The tax percentage must be between 0 and 100.'; end if;
  if p ? 'fy_numbering' and jsonb_typeof(p -> 'fy_numbering') <> 'boolean' then raise exception 'Financial-year numbering must be on or off.'; end if;
  insert into console.crm_settings (customer_id, data) values (cid, p) on conflict (customer_id) do update set data = excluded.data, updated_at = now();
end $$;

-- ================= customers, prospects and suppliers =================
create or replace function public.kmr_crm_party_list(p_slug text, p jsonb default '{}') returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'crm'); q text := console.crm_txt(p, 'q'); k text := console.crm_txt(p, 'kind');
begin
  perform console.require_feature(p_slug, 'crm', 'crm.leads-customers');
  return coalesce((select jsonb_agg(to_jsonb(x) order by x.name) from (
    select py.id, py.code, py.kind, py.name, py.city, py.state, py.industry, py.status, py.owner, py.sample, py.gstin,
      (select count(*) from console.crm_contacts c where c.party_id = py.id) contacts,
      (select count(*) from console.crm_rfqs r where r.party_id = py.id) rfqs,
      (select count(*) from console.crm_rfqs r where r.party_id = py.id and r.status in ('Received', 'Costing', 'Quoted', 'Negotiation')) open_rfqs,
      (select c.name from console.crm_contacts c where c.party_id = py.id order by c.is_primary desc, c.created_at limit 1) contact_name,
      (select coalesce(c.mobile, c.phone) from console.crm_contacts c where c.party_id = py.id order by c.is_primary desc, c.created_at limit 1) contact_phone
     from console.crm_parties py where py.customer_id = cid and (k is null or py.kind = k) and (coalesce(p ->> 'status', '') = '' or py.status = p ->> 'status')
       and (q is null or py.name ilike '%' || q || '%' or py.code ilike '%' || q || '%' or coalesce(py.city, '') ilike '%' || q || '%' or coalesce(py.gstin, '') ilike '%' || q || '%')
     order by py.name limit 1000) x), '[]');
end $$;

create or replace function public.kmr_crm_party_get(p_slug text, p_id uuid) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'crm'); py console.crm_parties;
begin
  select * into py from console.crm_parties where id = p_id and customer_id = cid;
  if py.id is null then raise exception 'Customer not found.'; end if;
  return console.crm_party_json(py) || jsonb_build_object('can_edit', console.qp_role(cid, 'crm') in ('admin', 'editor'),
    'contacts', coalesce((select jsonb_agg(to_jsonb(c) - 'customer_id' - 'sample' order by c.is_primary desc, c.name) from console.crm_contacts c where c.party_id = py.id), '[]'),
    'rfqs', coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'no', r.no, 'customer_ref', r.customer_ref, 'status', r.status, 'received_on', r.received_on, 'due_on', r.due_on,
        'value', (select coalesce(sum(i.qty * i.unit_price), 0) from console.crm_rfq_items i where i.rfq_id = r.id)) order by r.received_on desc, r.created_at desc)
        from (select * from console.crm_rfqs where party_id = py.id order by received_on desc limit 50) r), '[]'),
    'leads', coalesce((select jsonb_agg(console.crm_lead_json(l) order by l.created_at desc) from console.crm_leads l where l.party_id = py.id), '[]'),
    'activities', coalesce((select jsonb_agg(console.crm_act_json(a) order by a.done, a.due_date nulls last, a.created_at desc) from (select * from console.crm_activities where party_id = py.id order by done, due_date nulls last, created_at desc limit 40) a), '[]'));
end $$;

create or replace function public.kmr_crm_party_save(p_slug text, p jsonb) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'crm'); v_id uuid := nullif(p ->> 'id', '')::uuid; py console.crm_parties; kd text := coalesce(console.crm_txt(p, 'kind'), 'customer'); cd int; ct jsonb := p -> 'contact'; code_ text;
begin
  perform console.require_feature(p_slug, 'crm', 'crm.leads-customers');
  if v_id is null and console.crm_txt(p, 'name') is null then raise exception 'Enter the company name.'; end if;
  if p ? 'name' and console.crm_txt(p, 'name') is null then raise exception 'Enter the company name.'; end if;
  if kd not in ('customer', 'prospect', 'supplier') then raise exception 'Choose customer, prospect or supplier.'; end if;
  if coalesce(p ->> 'status', 'active') not in ('active', 'inactive') then raise exception 'Status must be active or inactive.'; end if;
  cd := case when console.crm_txt(p, 'credit_days') is null then null else console.crm_num(p, 'credit_days')::int end;
  if cd is not null and (cd < 0 or cd > 365) then raise exception 'Credit days must be between 0 and 365.'; end if;
  begin
    if v_id is null then
      code_ := case when kd = 'supplier' then 'SUP' else 'CUS' end || '-' || lpad(console.crm_next(cid, case when kd = 'supplier' then 'SUP' else 'CUS' end)::text, 4, '0');
      insert into console.crm_parties (customer_id, code, kind, name, industry, gstin, pan, address, city, state, country, pincode, website, payment_terms, credit_days, owner, status, notes, created_by)
      values (cid, code_, kd, trim(p ->> 'name'), console.crm_txt(p, 'industry'), upper(console.crm_txt(p, 'gstin')), upper(console.crm_txt(p, 'pan')), console.crm_txt(p, 'address'), console.crm_txt(p, 'city'), console.crm_txt(p, 'state'),
        coalesce(console.crm_txt(p, 'country'), 'India'), console.crm_txt(p, 'pincode'), console.crm_txt(p, 'website'), console.crm_txt(p, 'payment_terms'), cd, console.crm_txt(p, 'owner'), coalesce(p ->> 'status', 'active'), console.crm_txt(p, 'notes'), console.crm_me())
      returning * into py;
      if jsonb_typeof(ct) = 'object' and console.crm_txt(ct, 'name') is not null then
        insert into console.crm_contacts (customer_id, party_id, name, designation, department, email, phone, mobile, is_primary)
        values (cid, py.id, trim(ct ->> 'name'), console.crm_txt(ct, 'designation'), console.crm_txt(ct, 'department'), console.crm_txt(ct, 'email'), console.crm_txt(ct, 'phone'), console.crm_txt(ct, 'mobile'), true);
      end if;
    else
      select * into py from console.crm_parties where id = v_id and customer_id = cid;
      if py.id is null then raise exception 'Customer not found.'; end if;
      update console.crm_parties set kind = kd, name = case when p ? 'name' then trim(p ->> 'name') else name end, industry = console.crm_txt(p, 'industry'), gstin = upper(console.crm_txt(p, 'gstin')), pan = upper(console.crm_txt(p, 'pan')),
        address = console.crm_txt(p, 'address'), city = console.crm_txt(p, 'city'), state = console.crm_txt(p, 'state'), country = coalesce(console.crm_txt(p, 'country'), 'India'), pincode = console.crm_txt(p, 'pincode'),
        website = console.crm_txt(p, 'website'), payment_terms = console.crm_txt(p, 'payment_terms'), credit_days = cd, owner = console.crm_txt(p, 'owner'), status = coalesce(p ->> 'status', status), notes = console.crm_txt(p, 'notes'), updated_at = now()
       where id = py.id returning * into py;
    end if;
  exception when unique_violation then raise exception '% is already in the list.', trim(p ->> 'name');
  end;
  return console.crm_party_json(py);
end $$;

create or replace function public.kmr_crm_party_delete(p_slug text, p_id uuid) returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'crm');
begin
  if not exists (select 1 from console.crm_parties where id = p_id and customer_id = cid) then raise exception 'Customer not found.'; end if;
  if exists (select 1 from console.crm_rfqs where party_id = p_id) or exists (select 1 from console.crm_quotes where party_id = p_id) or exists (select 1 from console.crm_supplier_quotes where supplier_id = p_id) then
    raise exception 'This company is used in RFQs, quotations or supplier prices, so it cannot be deleted. Mark it inactive instead.';
  end if;
  delete from console.crm_parties where id = p_id;
end $$;

create or replace function public.kmr_crm_contact_save(p_slug text, p jsonb) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'crm'); v_id uuid := nullif(p ->> 'id', '')::uuid; pid uuid := nullif(p ->> 'party_id', '')::uuid; c console.crm_contacts; prim boolean := coalesce((p ->> 'is_primary')::boolean, false);
begin
  perform console.require_feature(p_slug, 'crm', 'crm.leads-customers');
  if console.crm_txt(p, 'name') is null then raise exception 'Enter the contact''s name.'; end if;
  if v_id is not null then select * into c from console.crm_contacts where id = v_id and customer_id = cid; if c.id is null then raise exception 'Contact not found.'; end if; pid := c.party_id; end if;
  if pid is null or not exists (select 1 from console.crm_parties where id = pid and customer_id = cid) then raise exception 'Choose the company for this contact.'; end if;
  if prim then update console.crm_contacts set is_primary = false where party_id = pid and id is distinct from v_id; end if;
  if v_id is null then
    insert into console.crm_contacts (customer_id, party_id, name, designation, department, email, phone, mobile, is_primary, notes)
    values (cid, pid, trim(p ->> 'name'), console.crm_txt(p, 'designation'), console.crm_txt(p, 'department'), console.crm_txt(p, 'email'), console.crm_txt(p, 'phone'), console.crm_txt(p, 'mobile'), prim or not exists (select 1 from console.crm_contacts where party_id = pid), console.crm_txt(p, 'notes')) returning * into c;
  else
    update console.crm_contacts set name = trim(p ->> 'name'), designation = console.crm_txt(p, 'designation'), department = console.crm_txt(p, 'department'), email = console.crm_txt(p, 'email'), phone = console.crm_txt(p, 'phone'),
      mobile = console.crm_txt(p, 'mobile'), is_primary = prim, notes = console.crm_txt(p, 'notes') where id = v_id returning * into c;
  end if;
  return to_jsonb(c) - 'customer_id' - 'sample';
end $$;

create or replace function public.kmr_crm_contact_delete(p_slug text, p_id uuid) returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'crm');
begin
  if not exists (select 1 from console.crm_contacts where id = p_id and customer_id = cid) then raise exception 'Contact not found.'; end if;
  delete from console.crm_contacts where id = p_id;
end $$;

-- ================= leads and the pipeline =================
create or replace function public.kmr_crm_lead_list(p_slug text, p jsonb default '{}') returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'crm'); q text := console.crm_txt(p, 'q');
begin
  perform console.require_feature(p_slug, 'crm', 'crm.leads-customers');
  return coalesce((select jsonb_agg(console.crm_lead_json(l) order by l.next_followup nulls last, l.created_at desc) from (
    select * from console.crm_leads l where l.customer_id = cid and (console.crm_txt(p, 'stage') is null or l.stage = p ->> 'stage')
      and (coalesce(p ->> 'open', '') <> 'true' or l.stage not in ('Won', 'Lost')) and (console.crm_txt(p, 'owner') is null or lower(l.owner) = lower(p ->> 'owner'))
      and (q is null or l.no ilike '%' || q || '%' or l.company ilike '%' || q || '%' or coalesce(l.contact_name, '') ilike '%' || q || '%' or coalesce(l.product_interest, '') ilike '%' || q || '%' or coalesce(l.phone, '') ilike '%' || q || '%')
     order by l.next_followup nulls last, l.created_at desc limit 1500) l), '[]');
end $$;

create or replace function public.kmr_crm_lead_get(p_slug text, p_id uuid) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'crm'); l console.crm_leads;
begin
  select * into l from console.crm_leads where id = p_id and customer_id = cid;
  if l.id is null then raise exception 'Lead not found.'; end if;
  return console.crm_lead_json(l) || jsonb_build_object('can_edit', console.qp_role(cid, 'crm') in ('admin', 'editor'),
    'rfqs', coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'no', r.no, 'status', r.status) order by r.created_at desc) from console.crm_rfqs r where r.lead_id = l.id), '[]'),
    'activities', coalesce((select jsonb_agg(console.crm_act_json(a) order by a.done, a.due_date nulls last, a.created_at desc) from console.crm_activities a where a.lead_id = l.id), '[]'));
end $$;

create or replace function public.kmr_crm_lead_save(p_slug text, p jsonb) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'crm'); v_id uuid := nullif(p ->> 'id', '')::uuid; l console.crm_leads; st text := coalesce(console.crm_txt(p, 'stage'), 'New'); val numeric := console.crm_num(p, 'value'); pid uuid := nullif(p ->> 'party_id', '')::uuid;
begin
  perform console.require_feature(p_slug, 'crm', 'crm.leads-customers');
  if console.crm_txt(p, 'company') is null then raise exception 'Enter the company name.'; end if;
  if st not in ('New', 'Contacted', 'Qualified', 'RFQ received', 'Quoted', 'Negotiation', 'Won', 'Lost') then raise exception 'Choose a stage from the list.'; end if;
  if val is not null and val < 0 then raise exception 'The value cannot be negative.'; end if;
  if st = 'Lost' and console.crm_txt(p, 'lost_reason') is null then raise exception 'Say why the lead was lost.'; end if;
  if pid is not null and not exists (select 1 from console.crm_parties where id = pid and customer_id = cid) then raise exception 'Customer not found.'; end if;
  if v_id is null then
    insert into console.crm_leads (customer_id, no, party_id, company, contact_name, designation, phone, email, source, stage, product_interest, value, expected_close, owner, next_followup, lost_reason, notes, closed_at, created_by)
    values (cid, console.crm_number(cid, 'LD'), pid, trim(p ->> 'company'), console.crm_txt(p, 'contact_name'), console.crm_txt(p, 'designation'), console.crm_txt(p, 'phone'), console.crm_txt(p, 'email'), console.crm_txt(p, 'source'), st,
      console.crm_txt(p, 'product_interest'), val, console.crm_date(p, 'expected_close'), coalesce(console.crm_txt(p, 'owner'), console.crm_me()), console.crm_date(p, 'next_followup'),
      case when st = 'Lost' then console.crm_txt(p, 'lost_reason') end, console.crm_txt(p, 'notes'), case when st in ('Won', 'Lost') then now() end, console.crm_me()) returning * into l;
  else
    select * into l from console.crm_leads where id = v_id and customer_id = cid; if l.id is null then raise exception 'Lead not found.'; end if;
    update console.crm_leads set party_id = pid, company = trim(p ->> 'company'), contact_name = console.crm_txt(p, 'contact_name'), designation = console.crm_txt(p, 'designation'), phone = console.crm_txt(p, 'phone'),
      email = console.crm_txt(p, 'email'), source = console.crm_txt(p, 'source'), stage = st, product_interest = console.crm_txt(p, 'product_interest'), value = val, expected_close = console.crm_date(p, 'expected_close'),
      owner = console.crm_txt(p, 'owner'), next_followup = console.crm_date(p, 'next_followup'), lost_reason = case when st = 'Lost' then console.crm_txt(p, 'lost_reason') end, notes = console.crm_txt(p, 'notes'),
      closed_at = case when st in ('Won', 'Lost') then coalesce(closed_at, now()) end, updated_at = now() where id = l.id returning * into l;
  end if;
  return console.crm_lead_json(l);
end $$;

create or replace function public.kmr_crm_lead_stage(p_slug text, p_id uuid, p_stage text, p_reason text default null) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'crm'); l console.crm_leads;
begin
  perform console.require_feature(p_slug, 'crm', 'crm.leads-customers');
  if p_stage not in ('New', 'Contacted', 'Qualified', 'RFQ received', 'Quoted', 'Negotiation', 'Won', 'Lost') then raise exception 'Choose a stage from the list.'; end if;
  if p_stage = 'Lost' and nullif(trim(coalesce(p_reason, '')), '') is null then raise exception 'Say why the lead was lost.'; end if;
  update console.crm_leads set stage = p_stage, lost_reason = case when p_stage = 'Lost' then trim(p_reason) end, closed_at = case when p_stage in ('Won', 'Lost') then coalesce(closed_at, now()) end, updated_at = now()
   where id = p_id and customer_id = cid returning * into l;
  if l.id is null then raise exception 'Lead not found.'; end if;
  return console.crm_lead_json(l);
end $$;

create or replace function public.kmr_crm_lead_delete(p_slug text, p_id uuid) returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'crm');
begin
  if not exists (select 1 from console.crm_leads where id = p_id and customer_id = cid) then raise exception 'Lead not found.'; end if;
  delete from console.crm_leads where id = p_id;
end $$;

-- a lead that sent an RFQ: the company and contact become a customer (if not yet) and an RFQ is opened
create or replace function public.kmr_crm_lead_to_rfq(p_slug text, p_id uuid) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'crm'); l console.crm_leads; pid uuid; r console.crm_rfqs; cont uuid; code_ text;
begin
  perform console.require_feature(p_slug, 'crm', 'crm.rfq-costing');
  select * into l from console.crm_leads where id = p_id and customer_id = cid; if l.id is null then raise exception 'Lead not found.'; end if;
  pid := l.party_id;
  if pid is null then select id into pid from console.crm_parties where customer_id = cid and lower(name) = lower(l.company); end if;
  if pid is null then
    code_ := 'CUS-' || lpad(console.crm_next(cid, 'CUS')::text, 4, '0');
    insert into console.crm_parties (customer_id, code, kind, name, owner, created_by) values (cid, code_, 'customer', l.company, l.owner, console.crm_me()) returning id into pid;
  else
    update console.crm_parties set kind = 'customer', updated_at = now() where id = pid and kind = 'prospect';
  end if;
  if l.contact_name is not null then
    select id into cont from console.crm_contacts where party_id = pid and lower(name) = lower(l.contact_name) limit 1;
    if cont is null then
      insert into console.crm_contacts (customer_id, party_id, name, designation, email, phone, is_primary) values (cid, pid, l.contact_name, l.designation, l.email, l.phone, not exists (select 1 from console.crm_contacts where party_id = pid)) returning id into cont;
    end if;
  end if;
  insert into console.crm_rfqs (customer_id, no, party_id, contact_id, lead_id, received_on, owner, notes, created_by)
  values (cid, console.crm_number(cid, 'RFQ'), pid, cont, l.id, console.crm_today(), coalesce(l.owner, console.crm_me()), l.product_interest, console.crm_me()) returning * into r;
  update console.crm_leads set party_id = pid, stage = case when stage in ('New', 'Contacted', 'Qualified') then 'RFQ received' else stage end, updated_at = now() where id = l.id;
  return jsonb_build_object('rfq_id', r.id, 'rfq_no', r.no, 'party_id', pid);
end $$;

-- ================= follow-ups, calls and visits =================
create or replace function public.kmr_crm_act_list(p_slug text, p jsonb default '{}') returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'crm');
begin
  perform console.require_feature(p_slug, 'crm', 'crm.leads-customers');
  return coalesce((select jsonb_agg(console.crm_act_json(a) || jsonb_build_object('party_name', (select name from console.crm_parties where id = a.party_id), 'lead_company', (select company from console.crm_leads where id = a.lead_id),
      'rfq_no', (select no from console.crm_rfqs where id = a.rfq_id)) order by a.done, a.due_date nulls last, a.created_at desc) from (
    select * from console.crm_activities a where a.customer_id = cid and (coalesce(p ->> 'scope', 'open') = 'all' or not a.done)
      and (nullif(p ->> 'lead_id', '') is null or a.lead_id = (p ->> 'lead_id')::uuid) and (nullif(p ->> 'party_id', '') is null or a.party_id = (p ->> 'party_id')::uuid)
      and (nullif(p ->> 'rfq_id', '') is null or a.rfq_id = (p ->> 'rfq_id')::uuid) and (coalesce(p ->> 'mine', '') <> 'true' or lower(coalesce(a.owner, '')) = console.crm_me())
     order by a.done, a.due_date nulls last, a.created_at desc limit 400) a), '[]');
end $$;

create or replace function public.kmr_crm_act_save(p_slug text, p jsonb) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'crm'); v_id uuid := nullif(p ->> 'id', '')::uuid; a console.crm_activities; kd text := coalesce(console.crm_txt(p, 'kind'), 'call');
  lid uuid := nullif(p ->> 'lead_id', '')::uuid; pid uuid := nullif(p ->> 'party_id', '')::uuid; rid uuid := nullif(p ->> 'rfq_id', '')::uuid; dn boolean := coalesce((p ->> 'done')::boolean, false);
begin
  perform console.require_feature(p_slug, 'crm', 'crm.leads-customers');
  if console.crm_txt(p, 'subject') is null then raise exception 'Write what the call, visit or task is about.'; end if;
  if kd not in ('call', 'visit', 'email', 'meeting', 'note', 'task') then raise exception 'Choose the kind of follow-up.'; end if;
  if lid is not null and not exists (select 1 from console.crm_leads where id = lid and customer_id = cid) then raise exception 'Lead not found.'; end if;
  if pid is not null and not exists (select 1 from console.crm_parties where id = pid and customer_id = cid) then raise exception 'Customer not found.'; end if;
  if rid is not null and not exists (select 1 from console.crm_rfqs where id = rid and customer_id = cid) then raise exception 'RFQ not found.'; end if;
  if v_id is null then
    insert into console.crm_activities (customer_id, lead_id, party_id, rfq_id, kind, subject, notes, due_date, done, done_at, owner, created_by)
    values (cid, lid, pid, rid, kd, trim(p ->> 'subject'), console.crm_txt(p, 'notes'), console.crm_date(p, 'due_date'), dn, case when dn then now() end, coalesce(console.crm_txt(p, 'owner'), console.crm_me()), console.crm_me()) returning * into a;
  else
    update console.crm_activities set kind = kd, subject = trim(p ->> 'subject'), notes = console.crm_txt(p, 'notes'), due_date = console.crm_date(p, 'due_date'), owner = console.crm_txt(p, 'owner'),
      done = dn, done_at = case when dn then coalesce(done_at, now()) end where id = v_id and customer_id = cid returning * into a;
    if a.id is null then raise exception 'Follow-up not found.'; end if;
  end if;
  -- the lead's next follow-up date follows its earliest open follow-up
  if a.lead_id is not null then
    update console.crm_leads l set next_followup = (select min(x.due_date) from console.crm_activities x where x.lead_id = l.id and not x.done and x.due_date is not null), updated_at = now() where l.id = a.lead_id;
  end if;
  return console.crm_act_json(a);
end $$;

create or replace function public.kmr_crm_act_done(p_slug text, p_id uuid, p_done boolean default true) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'crm'); a console.crm_activities;
begin
  update console.crm_activities set done = coalesce(p_done, true), done_at = case when coalesce(p_done, true) then now() end where id = p_id and customer_id = cid returning * into a;
  if a.id is null then raise exception 'Follow-up not found.'; end if;
  if a.lead_id is not null then
    update console.crm_leads l set next_followup = (select min(x.due_date) from console.crm_activities x where x.lead_id = l.id and not x.done and x.due_date is not null), updated_at = now() where l.id = a.lead_id;
  end if;
  return console.crm_act_json(a);
end $$;

create or replace function public.kmr_crm_act_delete(p_slug text, p_id uuid) returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'crm'); lid uuid;
begin
  select lead_id into lid from console.crm_activities where id = p_id and customer_id = cid;
  if not found then raise exception 'Follow-up not found.'; end if;
  delete from console.crm_activities where id = p_id;
  if lid is not null then
    update console.crm_leads l set next_followup = (select min(x.due_date) from console.crm_activities x where x.lead_id = l.id and not x.done and x.due_date is not null), updated_at = now() where l.id = lid;
  end if;
end $$;

-- ================= RFQs and costing =================
create or replace function public.kmr_crm_rfq_list(p_slug text, p jsonb default '{}') returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'crm'); q text := console.crm_txt(p, 'q'); td date := console.crm_today();
begin
  perform console.require_feature(p_slug, 'crm', 'crm.rfq-costing');
  return coalesce((select jsonb_agg(to_jsonb(x) order by x.sort_open desc, x.due_on nulls last, x.received_on desc) from (
    select r.id, r.no, r.customer_ref, r.party_id, py.name party_name, py.code party_code, r.received_on, r.due_on, r.status, r.priority, r.owner, r.project, r.sample, r.currency,
      (select count(*) from console.crm_rfq_items i where i.rfq_id = r.id) items,
      (select coalesce(sum(i.qty * i.unit_price), 0) from console.crm_rfq_items i where i.rfq_id = r.id) value,
      (select count(*) from console.crm_rfq_items i where i.rfq_id = r.id and i.unit_price = 0) unpriced,
      (select max(z.no || ' Rev ' || z.rev) from console.crm_quotes z where z.rfq_id = r.id and z.rev = (select max(rev) from console.crm_quotes where rfq_id = r.id)) latest_quote,
      (r.due_on is not null and r.due_on < td and r.status in ('Received', 'Costing')) overdue,
      (r.status in ('Received', 'Costing', 'Quoted', 'Negotiation')) sort_open
     from console.crm_rfqs r join console.crm_parties py on py.id = r.party_id
     where r.customer_id = cid and (console.crm_txt(p, 'status') is null or r.status = p ->> 'status') and (nullif(p ->> 'party_id', '') is null or r.party_id = (p ->> 'party_id')::uuid)
       and (coalesce(p ->> 'open', '') <> 'true' or r.status in ('Received', 'Costing', 'Quoted', 'Negotiation'))
       and (q is null or r.no ilike '%' || q || '%' or coalesce(r.customer_ref, '') ilike '%' || q || '%' or py.name ilike '%' || q || '%' or coalesce(r.project, '') ilike '%' || q || '%'
            or exists (select 1 from console.crm_rfq_items i where i.rfq_id = r.id and (coalesce(i.part_no, '') ilike '%' || q || '%' or i.part_name ilike '%' || q || '%')))
     order by r.received_on desc limit 1500) x), '[]');
end $$;

create or replace function public.kmr_crm_rfq_get(p_slug text, p_id uuid) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'crm'); r console.crm_rfqs; mo boolean := console.crm_money(cid);
begin
  perform console.require_feature(p_slug, 'crm', 'crm.rfq-costing');
  select * into r from console.crm_rfqs where id = p_id and customer_id = cid;
  if r.id is null then raise exception 'RFQ not found.'; end if;
  return jsonb_build_object('id', r.id, 'no', r.no, 'customer_ref', r.customer_ref, 'party_id', r.party_id, 'contact_id', r.contact_id, 'lead_id', r.lead_id, 'received_on', r.received_on, 'due_on', r.due_on,
    'status', r.status, 'priority', r.priority, 'owner', r.owner, 'project', r.project, 'currency', r.currency, 'notes', r.notes, 'lost_reason', r.lost_reason, 'decided_on', r.decided_on, 'sample', r.sample,
    'party', (select console.crm_party_json(p) from console.crm_parties p where p.id = r.party_id), 'lead_no', (select no from console.crm_leads where id = r.lead_id),
    'can_edit', console.qp_role(cid, 'crm') in ('admin', 'editor'), 'is_admin', console.qp_role(cid, 'crm') = 'admin', 'money', mo,
    'items', coalesce((select jsonb_agg(console.crm_item_json(i, mo) order by i.seq) from console.crm_rfq_items i where i.rfq_id = r.id), '[]'),
    'supplier_quotes', case when mo then coalesce((select jsonb_agg(console.crm_sq_json(s) order by s.price) from console.crm_supplier_quotes s where s.rfq_id = r.id), '[]') else '[]'::jsonb end,
    'quotes', coalesce((select jsonb_agg(console.crm_quote_json(z, false) order by z.rev desc) from console.crm_quotes z where z.rfq_id = r.id), '[]'),
    'activities', coalesce((select jsonb_agg(console.crm_act_json(a) order by a.done, a.due_date nulls last, a.created_at desc) from console.crm_activities a where a.rfq_id = r.id), '[]'));
end $$;

create or replace function public.kmr_crm_rfq_save(p_slug text, p jsonb) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'crm'); v_id uuid := nullif(p ->> 'id', '')::uuid; r console.crm_rfqs; pid uuid := nullif(p ->> 'party_id', '')::uuid; ct uuid := nullif(p ->> 'contact_id', '')::uuid;
  rec date := coalesce(console.crm_date(p, 'received_on'), console.crm_today()); due date := console.crm_date(p, 'due_on'); pr text := coalesce(console.crm_txt(p, 'priority'), 'Normal');
  it jsonb; ord int := 0; iid uuid; cc jsonb; kept uuid[] := '{}'; items jsonb := coalesce(p -> 'items', null); qty_ numeric; has_items boolean := p ? 'items';
begin
  perform console.require_feature(p_slug, 'crm', 'crm.rfq-costing');
  if pid is null and v_id is null then raise exception 'Choose the customer who sent the RFQ.'; end if;
  if pr not in ('Normal', 'High', 'Urgent') then raise exception 'Choose the priority from the list.'; end if;
  if due is not null and due < rec then raise exception 'The due date is before the date the RFQ was received.'; end if;
  if pid is not null and not exists (select 1 from console.crm_parties where id = pid and customer_id = cid) then raise exception 'Customer not found.'; end if;
  if ct is not null and not exists (select 1 from console.crm_contacts where id = ct and customer_id = cid and party_id = coalesce(pid, (select party_id from console.crm_rfqs where id = v_id))) then raise exception 'That contact does not belong to this customer.'; end if;
  if has_items and (jsonb_typeof(items) <> 'array' or jsonb_array_length(items) > 300) then raise exception 'An RFQ can have up to 300 parts.'; end if;
  if has_items and length(items::text) > 3000000 then raise exception 'The RFQ is too large.'; end if;
  if v_id is null then
    insert into console.crm_rfqs (customer_id, no, customer_ref, party_id, contact_id, lead_id, received_on, due_on, priority, owner, project, currency, notes, created_by)
    values (cid, console.crm_number(cid, 'RFQ'), console.crm_txt(p, 'customer_ref'), pid, ct, nullif(p ->> 'lead_id', '')::uuid, rec, due, pr, coalesce(console.crm_txt(p, 'owner'), console.crm_me()), console.crm_txt(p, 'project'),
      coalesce(console.crm_txt(p, 'currency'), console.crm_cfg(cid) ->> 'currency', 'INR'), console.crm_txt(p, 'notes'), console.crm_me()) returning * into r;
    if r.lead_id is not null then
      update console.crm_leads set party_id = coalesce(party_id, r.party_id), stage = case when stage in ('New', 'Contacted', 'Qualified') then 'RFQ received' else stage end, updated_at = now() where id = r.lead_id and customer_id = cid;
    end if;
  else
    select * into r from console.crm_rfqs where id = v_id and customer_id = cid; if r.id is null then raise exception 'RFQ not found.'; end if;
    if r.status in ('Won', 'Lost', 'No quote') and console.qp_role(cid, 'crm') <> 'admin' then raise exception 'This RFQ is closed. Ask an administrator to reopen it.'; end if;
    update console.crm_rfqs set customer_ref = console.crm_txt(p, 'customer_ref'), party_id = coalesce(pid, party_id), contact_id = ct, received_on = rec, due_on = due, priority = pr, owner = console.crm_txt(p, 'owner'),
      project = console.crm_txt(p, 'project'), currency = coalesce(console.crm_txt(p, 'currency'), currency), notes = console.crm_txt(p, 'notes'), updated_at = now() where id = r.id returning * into r;
  end if;
  if has_items then
    update console.crm_rfq_items set seq = seq + 100000 where rfq_id = r.id;
    for it in select * from jsonb_array_elements(items) loop
      ord := ord + 1;
      if console.crm_txt(it, 'part_name') is null then raise exception 'Part % has no name.', ord; end if;
      qty_ := console.crm_num(it, 'qty'); if qty_ is null or qty_ <= 0 then raise exception 'Part % needs a quantity above zero.', ord; end if;
      if console.crm_num(it, 'target_price') < 0 or console.crm_num(it, 'annual_qty') < 0 then raise exception 'Part % has a negative target price or annual quantity.', ord; end if;
      if length(coalesce((it -> 'cost')::text, '')) > 60000 then raise exception 'The costing of part % is too large.', ord; end if;
      cc := console.crm_cost(coalesce(it -> 'cost', '{}'));
      iid := nullif(it ->> 'id', '')::uuid;
      if iid is not null and not exists (select 1 from console.crm_rfq_items where id = iid and rfq_id = r.id) then iid := null; end if;
      if iid is null then
        insert into console.crm_rfq_items (customer_id, rfq_id, seq, part_no, part_name, drawing_no, revision, material, qty, annual_qty, uom, target_price, cost, unit_cost, unit_price, remarks)
        values (cid, r.id, ord, console.crm_txt(it, 'part_no'), trim(it ->> 'part_name'), console.crm_txt(it, 'drawing_no'), console.crm_txt(it, 'revision'), console.crm_txt(it, 'material'), qty_, console.crm_num(it, 'annual_qty'),
          coalesce(console.crm_txt(it, 'uom'), 'Nos'), console.crm_num(it, 'target_price'), case when jsonb_typeof(it -> 'cost') = 'object' then it -> 'cost' else '{}'::jsonb end, (cc ->> 'total_cost')::numeric, (cc ->> 'price')::numeric, console.crm_txt(it, 'remarks')) returning id into iid;
      else
        update console.crm_rfq_items set seq = ord, part_no = console.crm_txt(it, 'part_no'), part_name = trim(it ->> 'part_name'), drawing_no = console.crm_txt(it, 'drawing_no'), revision = console.crm_txt(it, 'revision'),
          material = console.crm_txt(it, 'material'), qty = qty_, annual_qty = console.crm_num(it, 'annual_qty'), uom = coalesce(console.crm_txt(it, 'uom'), 'Nos'), target_price = console.crm_num(it, 'target_price'),
          cost = case when jsonb_typeof(it -> 'cost') = 'object' then it -> 'cost' else '{}'::jsonb end, unit_cost = (cc ->> 'total_cost')::numeric, unit_price = (cc ->> 'price')::numeric, remarks = console.crm_txt(it, 'remarks') where id = iid;
      end if;
      kept := kept || iid;
    end loop;
    delete from console.crm_rfq_items where rfq_id = r.id and not (id = any (kept));
  end if;
  return jsonb_build_object('id', r.id, 'no', r.no);
end $$;

create or replace function public.kmr_crm_rfq_status(p_slug text, p_id uuid, p_status text, p_reason text default null) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'crm'); r console.crm_rfqs; closing boolean;
begin
  perform console.require_feature(p_slug, 'crm', 'crm.rfq-costing');
  if p_status not in ('Received', 'Costing', 'Quoted', 'Negotiation', 'Won', 'Lost', 'No quote') then raise exception 'Choose a status from the list.'; end if;
  select * into r from console.crm_rfqs where id = p_id and customer_id = cid; if r.id is null then raise exception 'RFQ not found.'; end if;
  if r.status in ('Won', 'Lost', 'No quote') and p_status <> r.status and console.qp_role(cid, 'crm') <> 'admin' then raise exception 'This RFQ is closed. Ask an administrator to reopen it.'; end if;
  if p_status in ('Lost', 'No quote') and nullif(trim(coalesce(p_reason, '')), '') is null then raise exception 'Say why (price, delivery, capacity, customer cancelled…).'; end if;
  closing := p_status in ('Won', 'Lost', 'No quote');
  update console.crm_rfqs set status = p_status, lost_reason = case when p_status in ('Lost', 'No quote') then trim(p_reason) end, decided_on = case when closing then coalesce(decided_on, console.crm_today()) end, updated_at = now()
   where id = r.id returning * into r;
  if r.lead_id is not null then
    update console.crm_leads set stage = case when p_status = 'Won' then 'Won' when p_status = 'Lost' then 'Lost' when p_status = 'Quoted' then 'Quoted' when p_status = 'Negotiation' then 'Negotiation' else stage end,
      lost_reason = case when p_status = 'Lost' then trim(p_reason) else lost_reason end, closed_at = case when p_status in ('Won', 'Lost') then coalesce(closed_at, now()) else closed_at end, updated_at = now()
     where id = r.lead_id and customer_id = cid;
  end if;
  return jsonb_build_object('id', r.id, 'status', r.status);
end $$;

create or replace function public.kmr_crm_rfq_delete(p_slug text, p_id uuid) returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'crm');
begin
  if not exists (select 1 from console.crm_rfqs where id = p_id and customer_id = cid) then raise exception 'RFQ not found.'; end if;
  if exists (select 1 from console.crm_quotes where rfq_id = p_id and status in ('sent', 'accepted')) and console.qp_role(cid, 'crm') <> 'admin' then
    raise exception 'A quotation for this RFQ has been sent. Only an administrator can delete it.';
  end if;
  delete from console.crm_rfqs where id = p_id;
end $$;

-- ================= supplier prices =================
create or replace function public.kmr_crm_sq_save(p_slug text, p jsonb) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'crm'); v_id uuid := nullif(p ->> 'id', '')::uuid; it console.crm_rfq_items; sid uuid := nullif(p ->> 'supplier_id', '')::uuid; wh text := coalesce(console.crm_txt(p, 'what'), 'Bought-out part');
  pr numeric := console.crm_num(p, 'price'); s console.crm_supplier_quotes; sn text := console.crm_txt(p, 'supplier_name'); mq numeric := console.crm_num(p, 'moq'); ld numeric := console.crm_num(p, 'lead_days');
begin
  perform console.require_feature(p_slug, 'crm', 'crm.supplier-comparison');
  if not console.crm_money(cid) then raise exception 'Supplier prices are for editors and administrators.'; end if;
  if wh not in ('Raw material', 'Bought-out part', 'Outsourced process', 'Tooling', 'Other') then raise exception 'Choose what the supplier is quoting for.'; end if;
  if pr is null or pr < 0 then raise exception 'Enter the supplier''s price per piece.'; end if;
  if mq is not null and mq < 0 then raise exception 'MOQ cannot be negative.'; end if;
  if ld is not null and (ld < 0 or ld > 3650) then raise exception 'Lead time is in days, 0 to 3650.'; end if;
  if v_id is not null then
    select * into s from console.crm_supplier_quotes where id = v_id and customer_id = cid; if s.id is null then raise exception 'Supplier price not found.'; end if;
    select * into it from console.crm_rfq_items where id = s.item_id;
  else
    select * into it from console.crm_rfq_items where id = nullif(p ->> 'item_id', '')::uuid and customer_id = cid;
    if it.id is null then raise exception 'Choose the part this price is for.'; end if;
  end if;
  if sid is null and sn is not null then
    select id into sid from console.crm_parties where customer_id = cid and lower(name) = lower(sn);
    if sid is null then insert into console.crm_parties (customer_id, code, kind, name, created_by) values (cid, 'SUP-' || lpad(console.crm_next(cid, 'SUP')::text, 4, '0'), 'supplier', sn, console.crm_me()) returning id into sid; end if;
  end if;
  if sid is null or not exists (select 1 from console.crm_parties where id = sid and customer_id = cid) then raise exception 'Choose the supplier or type a new supplier''s name.'; end if;
  if v_id is null then
    insert into console.crm_supplier_quotes (customer_id, rfq_id, item_id, supplier_id, what, price, moq, lead_days, valid_until, payment_terms, quote_ref, received_on, notes, created_by)
    values (cid, it.rfq_id, it.id, sid, wh, pr, mq, ld::int, console.crm_date(p, 'valid_until'), console.crm_txt(p, 'payment_terms'), console.crm_txt(p, 'quote_ref'), coalesce(console.crm_date(p, 'received_on'), console.crm_today()), console.crm_txt(p, 'notes'), console.crm_me()) returning * into s;
  else
    update console.crm_supplier_quotes set supplier_id = sid, what = wh, price = pr, moq = mq, lead_days = ld::int, valid_until = console.crm_date(p, 'valid_until'), payment_terms = console.crm_txt(p, 'payment_terms'),
      quote_ref = console.crm_txt(p, 'quote_ref'), received_on = coalesce(console.crm_date(p, 'received_on'), received_on), notes = console.crm_txt(p, 'notes') where id = s.id returning * into s;
    if s.selected then perform public.kmr_crm_sq_select(p_slug, s.id, true); select * into s from console.crm_supplier_quotes where id = s.id; end if;   -- the costing follows the changed price
  end if;
  return console.crm_sq_json(s);
end $$;

-- choose (or un-choose) the supplier for a part: the price goes into the part's costing as an outsourced / bought-out line
create or replace function public.kmr_crm_sq_select(p_slug text, p_id uuid, p_on boolean default true) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'crm'); s console.crm_supplier_quotes; it console.crm_rfq_items; c jsonb; outs jsonb; cc jsonb; nm text;
begin
  perform console.require_feature(p_slug, 'crm', 'crm.supplier-comparison');
  if not console.crm_money(cid) then raise exception 'Supplier prices are for editors and administrators.'; end if;
  select * into s from console.crm_supplier_quotes where id = p_id and customer_id = cid; if s.id is null then raise exception 'Supplier price not found.'; end if;
  select * into it from console.crm_rfq_items where id = s.item_id;
  c := case when jsonb_typeof(it.cost) = 'object' then it.cost else '{}'::jsonb end;
  outs := coalesce((select jsonb_agg(o) from jsonb_array_elements(case when jsonb_typeof(c -> 'outs') = 'array' then c -> 'outs' else '[]'::jsonb end) o where nullif(o ->> 'sq', '') is null), '[]'::jsonb);   -- keep typed lines, drop earlier chosen supplier
  update console.crm_supplier_quotes set selected = false where item_id = it.id;
  if coalesce(p_on, true) then
    update console.crm_supplier_quotes set selected = true where id = s.id;
    nm := s.what || ' — ' || (select name from console.crm_parties where id = s.supplier_id);
    outs := outs || jsonb_build_array(jsonb_build_object('name', nm, 'amt', s.price, 'sq', s.id));
  end if;
  c := jsonb_set(c, '{outs}', outs, true); cc := console.crm_cost(c);
  update console.crm_rfq_items set cost = c, unit_cost = (cc ->> 'total_cost')::numeric, unit_price = (cc ->> 'price')::numeric where id = it.id returning * into it;
  return console.crm_item_json(it, true);
end $$;

create or replace function public.kmr_crm_sq_delete(p_slug text, p_id uuid) returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'crm'); s console.crm_supplier_quotes;
begin
  select * into s from console.crm_supplier_quotes where id = p_id and customer_id = cid; if s.id is null then raise exception 'Supplier price not found.'; end if;
  if s.selected then perform public.kmr_crm_sq_select(p_slug, p_id, false); end if;
  delete from console.crm_supplier_quotes where id = p_id;
end $$;

-- ================= quotations =================
create or replace function public.kmr_crm_quote_list(p_slug text, p jsonb default '{}') returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'crm'); q text := console.crm_txt(p, 'q');
begin
  perform console.require_feature(p_slug, 'crm', 'crm.quotations');
  return coalesce((select jsonb_agg(console.crm_quote_json(z, false) || jsonb_build_object('latest', z.rev = (select max(rev) from console.crm_quotes where rfq_id = z.rfq_id)) order by z.quote_date desc, z.created_at desc) from (
    select * from console.crm_quotes z where z.customer_id = cid and (console.crm_txt(p, 'status') is null or z.status = p ->> 'status') and (nullif(p ->> 'rfq_id', '') is null or z.rfq_id = (p ->> 'rfq_id')::uuid)
      and (nullif(p ->> 'party_id', '') is null or z.party_id = (p ->> 'party_id')::uuid) and (coalesce(p ->> 'all', '') = 'true' or z.status <> 'superseded')
      and (q is null or z.no ilike '%' || q || '%' or exists (select 1 from console.crm_parties py where py.id = z.party_id and py.name ilike '%' || q || '%') or exists (select 1 from console.crm_rfqs r where r.id = z.rfq_id and r.no ilike '%' || q || '%'))
     order by z.quote_date desc, z.created_at desc limit 1000) z), '[]');
end $$;

create or replace function public.kmr_crm_quote_get(p_slug text, p_id uuid) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'crm'); z console.crm_quotes;
begin
  perform console.require_feature(p_slug, 'crm', 'crm.quotations');
  select * into z from console.crm_quotes where id = p_id and customer_id = cid; if z.id is null then raise exception 'Quotation not found.'; end if;
  return console.crm_quote_json(z, true) || jsonb_build_object('can_edit', console.qp_role(cid, 'crm') in ('admin', 'editor'), 'is_admin', console.qp_role(cid, 'crm') = 'admin', 'settings', console.crm_cfg(cid),
    'revisions', coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'rev', x.rev, 'status', x.status, 'quote_date', x.quote_date, 'total', x.total) order by x.rev desc) from console.crm_quotes x where x.rfq_id = z.rfq_id and x.no = z.no), '[]'));
end $$;

-- a quotation (or its next revision) from the priced parts of an RFQ
create or replace function public.kmr_crm_quote_make(p_slug text, p_rfq uuid) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'crm'); r console.crm_rfqs; cfg jsonb := console.crm_cfg(cid); lines jsonb; last_ console.crm_quotes; z console.crm_quotes; nno text; rv int := 0; tt record; vd int; tx numeric;
begin
  perform console.require_feature(p_slug, 'crm', 'crm.quotations');
  select * into r from console.crm_rfqs where id = p_rfq and customer_id = cid; if r.id is null then raise exception 'RFQ not found.'; end if;
  if r.status in ('Lost', 'No quote') then raise exception 'This RFQ is closed (%). Reopen it before quoting.', lower(r.status); end if;
  select * into z from console.crm_quotes where rfq_id = r.id and status = 'draft' order by rev desc limit 1;
  if z.id is not null then return console.crm_quote_json(z, false) || jsonb_build_object('existing', true); end if;
  select coalesce(jsonb_agg(jsonb_build_object('seq', i.seq, 'part_no', i.part_no, 'part_name', i.part_name, 'drawing_no', i.drawing_no, 'revision', i.revision, 'qty', i.qty, 'uom', i.uom, 'unit_price', i.unit_price,
      'lead_days', null, 'remarks', i.remarks) order by i.seq), '[]') into lines from console.crm_rfq_items i where i.rfq_id = r.id and i.unit_price > 0;
  if jsonb_array_length(lines) = 0 then raise exception 'Price at least one part in the RFQ (costing sheet) before making a quotation.'; end if;
  select * into last_ from console.crm_quotes where rfq_id = r.id order by rev desc limit 1;
  if last_.id is not null then nno := last_.no; rv := last_.rev + 1; update console.crm_quotes set status = 'superseded', updated_at = now() where rfq_id = r.id and status in ('sent', 'rejected'); else nno := console.crm_number(cid, 'QTN'); end if;
  vd := coalesce(console.crm_num(cfg, 'validity_days'), 30)::int; tx := coalesce(console.crm_num(cfg, 'tax_pct'), 0);
  select * into tt from console.crm_totals(lines, tx);
  insert into console.crm_quotes (customer_id, no, rev, rfq_id, party_id, contact_id, quote_date, valid_until, currency, tax_name, tax_pct, payment_terms, delivery_terms, terms, lines, subtotal, tax_amt, total, prepared_by)
  values (cid, nno, rv, r.id, r.party_id, r.contact_id, console.crm_today(), console.crm_today() + vd, r.currency, coalesce(console.crm_txt(cfg, 'tax_name'), 'GST'), tx,
    coalesce(console.crm_txt(cfg, 'payment_terms'), (select payment_terms from console.crm_parties where id = r.party_id)), console.crm_txt(cfg, 'delivery_terms'), console.crm_txt(cfg, 'terms'), lines, tt.sub, tt.tax, tt.tot, console.crm_me()) returning * into z;
  update console.crm_rfqs set status = 'Costing', updated_at = now() where id = r.id and status = 'Received';
  return console.crm_quote_json(z, false);
end $$;

create or replace function public.kmr_crm_quote_save(p_slug text, p jsonb) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'crm'); z console.crm_quotes; lines jsonb := p -> 'lines'; ln jsonb; tt record; tx numeric := console.crm_num(p, 'tax_pct'); ct uuid := nullif(p ->> 'contact_id', '')::uuid; clean jsonb := '[]'; n int := 0;
begin
  perform console.require_feature(p_slug, 'crm', 'crm.quotations');
  select * into z from console.crm_quotes where id = nullif(p ->> 'id', '')::uuid and customer_id = cid; if z.id is null then raise exception 'Quotation not found.'; end if;
  if z.status <> 'draft' then raise exception 'This quotation is % and cannot be edited. Make a new revision instead.', z.status; end if;
  if tx is null or tx < 0 or tx > 100 then raise exception 'The tax percentage must be between 0 and 100.'; end if;
  if ct is not null and not exists (select 1 from console.crm_contacts where id = ct and customer_id = cid and party_id = z.party_id) then raise exception 'That contact does not belong to this customer.'; end if;
  if lines is null then lines := z.lines; end if;
  if jsonb_typeof(lines) <> 'array' or jsonb_array_length(lines) = 0 then raise exception 'A quotation needs at least one line.'; end if;
  if jsonb_array_length(lines) > 300 then raise exception 'A quotation can have up to 300 lines.'; end if;
  for ln in select * from jsonb_array_elements(lines) loop
    n := n + 1;
    if console.crm_txt(ln, 'part_name') is null then raise exception 'Line % has no part name.', n; end if;
    if console.crm_pos(ln, 'qty') <= 0 then raise exception 'Line % needs a quantity above zero.', n; end if;
    if console.crm_num(ln, 'unit_price') is null or console.crm_num(ln, 'unit_price') < 0 then raise exception 'Line % needs a price.', n; end if;
    clean := clean || jsonb_build_array(jsonb_build_object('seq', n, 'part_no', console.crm_txt(ln, 'part_no'), 'part_name', trim(ln ->> 'part_name'), 'drawing_no', console.crm_txt(ln, 'drawing_no'), 'revision', console.crm_txt(ln, 'revision'),
      'qty', console.crm_pos(ln, 'qty'), 'uom', coalesce(console.crm_txt(ln, 'uom'), 'Nos'), 'unit_price', console.crm_pos(ln, 'unit_price'), 'lead_days', console.crm_num(ln, 'lead_days'), 'remarks', console.crm_txt(ln, 'remarks')));
  end loop;
  select * into tt from console.crm_totals(clean, tx);
  update console.crm_quotes set contact_id = ct, quote_date = coalesce(console.crm_date(p, 'quote_date'), quote_date), valid_until = console.crm_date(p, 'valid_until'), tax_name = coalesce(console.crm_txt(p, 'tax_name'), 'GST'), tax_pct = tx,
    payment_terms = console.crm_txt(p, 'payment_terms'), delivery_terms = console.crm_txt(p, 'delivery_terms'), terms = console.crm_txt(p, 'terms'), remarks = console.crm_txt(p, 'remarks'), lines = clean,
    subtotal = tt.sub, tax_amt = tt.tax, total = tt.tot, updated_at = now() where id = z.id returning * into z;
  return console.crm_quote_json(z, true);
end $$;

create or replace function public.kmr_crm_quote_status(p_slug text, p_id uuid, p_status text) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'crm'); z console.crm_quotes; adm boolean;
begin
  perform console.require_feature(p_slug, 'crm', 'crm.quotations');
  adm := console.qp_role(cid, 'crm') = 'admin';
  select * into z from console.crm_quotes where id = p_id and customer_id = cid; if z.id is null then raise exception 'Quotation not found.'; end if;
  if not ((z.status = 'draft' and p_status = 'sent') or (z.status = 'sent' and p_status in ('accepted', 'rejected')) or (z.status in ('accepted', 'rejected') and p_status = 'sent' and adm)) then
    raise exception 'A % quotation cannot be changed to %.', z.status, p_status;
  end if;
  if p_status = 'sent' and (jsonb_array_length(z.lines) = 0 or z.total <= 0) then raise exception 'Add prices before the quotation is marked as sent.'; end if;
  update console.crm_quotes set status = p_status, sent_on = case when p_status = 'sent' then coalesce(sent_on, console.crm_today()) else sent_on end,
    decided_on = case when p_status in ('accepted', 'rejected') then console.crm_today() else null end, updated_at = now() where id = z.id returning * into z;
  if p_status = 'sent' then
    update console.crm_rfqs set status = case when status in ('Received', 'Costing') then 'Quoted' else status end, updated_at = now() where id = z.rfq_id;
    update console.crm_leads set stage = 'Quoted', updated_at = now() where id = (select lead_id from console.crm_rfqs where id = z.rfq_id) and stage in ('New', 'Contacted', 'Qualified', 'RFQ received');
  elsif p_status = 'accepted' then
    update console.crm_rfqs set status = 'Won', decided_on = console.crm_today(), lost_reason = null, updated_at = now() where id = z.rfq_id;
    update console.crm_leads set stage = 'Won', closed_at = coalesce(closed_at, now()), updated_at = now() where id = (select lead_id from console.crm_rfqs where id = z.rfq_id);
  end if;
  return console.crm_quote_json(z, false);
end $$;

create or replace function public.kmr_crm_quote_delete(p_slug text, p_id uuid) returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'crm'); z console.crm_quotes;
begin
  select * into z from console.crm_quotes where id = p_id and customer_id = cid; if z.id is null then raise exception 'Quotation not found.'; end if;
  if z.status <> 'draft' and console.qp_role(cid, 'crm') <> 'admin' then raise exception 'Only an administrator can delete a quotation that has been sent.'; end if;
  if z.status = 'accepted' then raise exception 'An accepted quotation cannot be deleted. Change its status first.'; end if;
  delete from console.crm_quotes where id = p_id;
end $$;

-- ================= dashboard =================
create or replace function public.kmr_crm_dashboard(p_slug text) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'crm'); td date := console.crm_today(); won int; lost int;
begin
  select count(*) filter (where status = 'Won'), count(*) filter (where status = 'Lost') into won, lost from console.crm_rfqs where customer_id = cid;
  return jsonb_build_object(
    'leads_open', (select count(*) from console.crm_leads where customer_id = cid and stage not in ('Won', 'Lost')),
    'pipeline_value', (select coalesce(sum(value), 0) from console.crm_leads where customer_id = cid and stage not in ('Won', 'Lost')),
    'by_stage', coalesce((select jsonb_object_agg(stage, jsonb_build_object('n', n, 'value', v)) from (select stage, count(*) n, coalesce(sum(value), 0) v from console.crm_leads where customer_id = cid group by stage) x), '{}'),
    'followups_due', (select count(*) from console.crm_activities where customer_id = cid and not done and due_date is not null and due_date <= td),
    'followups_overdue', (select count(*) from console.crm_activities where customer_id = cid and not done and due_date is not null and due_date < td),
    'rfq_open', (select count(*) from console.crm_rfqs where customer_id = cid and status in ('Received', 'Costing', 'Quoted', 'Negotiation')),
    'rfq_to_quote', (select count(*) from console.crm_rfqs where customer_id = cid and status in ('Received', 'Costing')),
    'rfq_overdue', (select count(*) from console.crm_rfqs where customer_id = cid and status in ('Received', 'Costing') and due_on is not null and due_on < td),
    'quotes_out_value', (select coalesce(sum(total), 0) from console.crm_quotes where customer_id = cid and status = 'sent'),
    'quotes_out', (select count(*) from console.crm_quotes where customer_id = cid and status = 'sent'),
    'won_value_90', (select coalesce(sum(total), 0) from console.crm_quotes where customer_id = cid and status = 'accepted' and decided_on >= td - 90),
    'win_rate', case when won + lost > 0 then round(won * 100.0 / (won + lost), 0) end, 'won', won, 'lost', lost,
    'due_soon', coalesce((select jsonb_agg(x) from (select r.id, r.no, py.name party_name, r.due_on, r.status, r.priority from console.crm_rfqs r join console.crm_parties py on py.id = r.party_id
        where r.customer_id = cid and r.status in ('Received', 'Costing') order by r.due_on nulls last, r.received_on limit 8) x), '[]'),
    'next_actions', coalesce((select jsonb_agg(x) from (select a.id, a.kind, a.subject, a.due_date, a.owner, (select name from console.crm_parties where id = a.party_id) party_name, (select company from console.crm_leads where id = a.lead_id) lead_company,
        a.lead_id, a.party_id, a.rfq_id from console.crm_activities a where a.customer_id = cid and not a.done order by a.due_date nulls last, a.created_at limit 8) x), '[]'),
    'lost_reasons', coalesce((select jsonb_object_agg(reason, n) from (select coalesce(lost_reason, 'Not stated') reason, count(*) n from console.crm_rfqs where customer_id = cid and status in ('Lost', 'No quote') group by 1) x), '{}'));
end $$;

-- ================= sample data (for trying the app; marked as sample and removed with one click) =================
create or replace function console.crm_sample(p_cid uuid, p_action text) returns integer language plpgsql security definer set search_path = console, public as $$
declare n int := 0; k int; td date := console.crm_today(); c1 uuid; c2 uuid; c3 uuid; c4 uuid; s1 uuid; s2 uuid; l1 uuid; l2 uuid; l3 uuid; l4 uuid; l5 uuid; l6 uuid; r1 uuid; r2 uuid; r3 uuid; r4 uuid; i1 uuid; i2 uuid; i3 uuid; i4 uuid; i5 uuid;
  k1 uuid; k2 uuid; k3 uuid; q1 uuid; cc jsonb; cst jsonb; sq1 uuid; sq2 uuid; sq3 uuid; lines jsonb; tt record; no_ text; me text := 'sample';
begin
  if p_action = 'flush' then
    delete from console.crm_activities where customer_id = p_cid and sample; get diagnostics k = row_count; n := n + k;
    delete from console.crm_quotes where customer_id = p_cid and sample; get diagnostics k = row_count; n := n + k;
    delete from console.crm_supplier_quotes where customer_id = p_cid and sample; get diagnostics k = row_count; n := n + k;
    delete from console.crm_rfqs where customer_id = p_cid and sample; get diagnostics k = row_count; n := n + k;
    delete from console.crm_leads where customer_id = p_cid and sample; get diagnostics k = row_count; n := n + k;
    delete from console.crm_parties y where y.customer_id = p_cid and y.sample and not exists (select 1 from console.crm_rfqs r where r.party_id = y.id) and not exists (select 1 from console.crm_quotes z where z.party_id = y.id)
      and not exists (select 1 from console.crm_supplier_quotes q where q.supplier_id = y.id); get diagnostics k = row_count; n := n + k;   -- a sample company that real work now uses is kept
    return n;
  end if;
  if exists (select 1 from console.crm_parties where customer_id = p_cid and sample) then return 0; end if;
  if not exists (select 1 from console.crm_settings where customer_id = p_cid) then
    insert into console.crm_settings (customer_id, data, sample) values (p_cid, jsonb_build_object('currency', 'INR', 'tax_name', 'GST', 'tax_pct', 18, 'validity_days', 30, 'fy_numbering', true,
      'payment_terms', '30 days from invoice date', 'delivery_terms', 'Ex-works, packing included', 'terms', E'1. Prices are per piece in Indian rupees and exclusive of tax unless stated.\n2. Delivery as per the lead time shown, from receipt of a confirmed purchase order and approved drawing.\n3. Raw material price variation beyond 3% is passed on at actuals.\n4. Tooling, if any, is charged separately as agreed.'), false);
  end if;
  insert into console.crm_parties (customer_id, code, kind, name, industry, gstin, address, city, state, pincode, payment_terms, credit_days, owner, sample, created_by) values
    (p_cid, 'CUS-' || lpad(console.crm_next(p_cid, 'CUS')::text, 4, '0'), 'customer', 'Deccan Motors Ltd', 'Automotive', '33AABCD1234E1Z5', '14, Industrial Estate, Ambattur', 'Chennai', 'Tamil Nadu', '600058', '45 days from invoice', 45, me, true, me) returning id into c1;
  insert into console.crm_parties (customer_id, code, kind, name, industry, gstin, address, city, state, pincode, payment_terms, credit_days, owner, sample, created_by) values
    (p_cid, 'CUS-' || lpad(console.crm_next(p_cid, 'CUS')::text, 4, '0'), 'customer', 'Southern Auto Components', 'Automotive', '29AAECS5678F1Z2', 'Plot 22, Peenya 2nd Stage', 'Bengaluru', 'Karnataka', '560058', '30 days from invoice', 30, me, true, me) returning id into c2;
  insert into console.crm_parties (customer_id, code, kind, name, industry, gstin, address, city, state, pincode, payment_terms, credit_days, owner, sample, created_by) values
    (p_cid, 'CUS-' || lpad(console.crm_next(p_cid, 'CUS')::text, 4, '0'), 'customer', 'Precision Pumps India', 'Pumps and valves', '27AAGCP9012H1Z8', 'Bhosari MIDC', 'Pune', 'Maharashtra', '411026', '30 days from invoice', 30, me, true, me) returning id into c3;
  insert into console.crm_parties (customer_id, code, kind, name, industry, city, state, owner, sample, created_by) values
    (p_cid, 'CUS-' || lpad(console.crm_next(p_cid, 'CUS')::text, 4, '0'), 'prospect', 'Western Hydraulics', 'Hydraulics', 'Coimbatore', 'Tamil Nadu', me, true, me) returning id into c4;
  insert into console.crm_parties (customer_id, code, kind, name, industry, gstin, city, state, payment_terms, sample, created_by) values
    (p_cid, 'SUP-' || lpad(console.crm_next(p_cid, 'SUP')::text, 4, '0'), 'supplier', 'Shree Steels', 'Steel bars and forgings', '33AAACS3456K1Z1', 'Chennai', 'Tamil Nadu', '15 days', true, me) returning id into s1;
  insert into console.crm_parties (customer_id, code, kind, name, industry, gstin, city, state, payment_terms, sample, created_by) values
    (p_cid, 'SUP-' || lpad(console.crm_next(p_cid, 'SUP')::text, 4, '0'), 'supplier', 'Anand Heat Treatments', 'Heat treatment and plating', '33AABCA7890M1Z6', 'Hosur', 'Tamil Nadu', '30 days', true, me) returning id into s2;
  n := 6;
  insert into console.crm_contacts (customer_id, party_id, name, designation, email, mobile, is_primary, sample) values
    (p_cid, c1, 'R. Venkatesh', 'Purchase Manager', 'venkatesh@deccan-motors.example', '98400 11111', true, true) returning id into k1;
  insert into console.crm_contacts (customer_id, party_id, name, designation, email, mobile, is_primary, sample) values
    (p_cid, c2, 'S. Priya', 'Senior Buyer', 'priya@southern-auto.example', '98450 22222', true, true) returning id into k2;
  insert into console.crm_contacts (customer_id, party_id, name, designation, email, mobile, is_primary, sample) values
    (p_cid, c3, 'M. Kulkarni', 'Head - Sourcing', 'kulkarni@precision-pumps.example', '98220 33333', true, true) returning id into k3;
  insert into console.crm_contacts (customer_id, party_id, name, designation, mobile, is_primary, sample) values (p_cid, c4, 'A. Ramesh', 'Proprietor', '98430 44444', true, true), (p_cid, s1, 'K. Mohan', 'Sales', '98400 55555', true, true), (p_cid, s2, 'P. Anand', 'Works manager', '98430 66666', true, true);
  n := n + 6;
  -- leads
  insert into console.crm_leads (customer_id, no, party_id, company, contact_name, phone, source, stage, product_interest, value, expected_close, owner, next_followup, notes, sample, created_by)
  values (p_cid, console.crm_number(p_cid, 'LD'), c4, 'Western Hydraulics', 'A. Ramesh', '98430 44444', 'Trade fair', 'Qualified', 'Hydraulic manifold blocks, 500 per month', 1800000, td + 45, me, td + 2, 'Met at the trade fair. Sent our capability profile.', true, me) returning id into l1;
  insert into console.crm_leads (customer_id, no, company, contact_name, phone, source, stage, product_interest, value, expected_close, owner, next_followup, sample, created_by)
  values (p_cid, console.crm_number(p_cid, 'LD'), 'Kaveri Gearworks', 'T. Selvam', '98410 77777', 'Website enquiry', 'New', 'Gear blanks, annual 60,000', 950000, td + 60, me, td, true, me) returning id into l2;
  insert into console.crm_leads (customer_id, no, company, contact_name, phone, source, stage, product_interest, value, expected_close, owner, next_followup, sample, created_by)
  values (p_cid, console.crm_number(p_cid, 'LD'), 'Nilgiri Tractors', 'D. Joseph', '98420 88888', 'Reference', 'Contacted', 'Hubs and flanges', 2400000, td + 75, me, td - 3, true, me) returning id into l3;
  insert into console.crm_leads (customer_id, no, party_id, company, contact_name, phone, source, stage, product_interest, value, expected_close, owner, sample, created_by)
  values (p_cid, console.crm_number(p_cid, 'LD'), c1, 'Deccan Motors Ltd', 'R. Venkatesh', '98400 11111', 'Existing customer', 'Quoted', 'Drive flange DP-1101', 3100000, td + 20, me, true, me) returning id into l4;
  insert into console.crm_leads (customer_id, no, party_id, company, contact_name, phone, source, stage, product_interest, value, owner, closed_at, sample, created_by)
  values (p_cid, console.crm_number(p_cid, 'LD'), c2, 'Southern Auto Components', 'S. Priya', '98450 22222', 'Existing customer', 'Won', 'Wheel hub DP-1102', 1750000, me, now() - interval '12 days', true, me) returning id into l5;
  insert into console.crm_leads (customer_id, no, company, contact_name, source, stage, product_interest, value, lost_reason, owner, closed_at, sample, created_by)
  values (p_cid, console.crm_number(p_cid, 'LD'), 'Coastal Marine Pumps', 'B. Fernandes', 'Cold call', 'Lost', 'Impeller castings', 600000, 'Customer wanted castings, we machine only', me, now() - interval '30 days', true, me) returning id into l6;
  n := n + 6;
  -- RFQs with costing sheets (the same arithmetic as the app: crm_cost)
  insert into console.crm_rfqs (customer_id, no, customer_ref, party_id, contact_id, lead_id, received_on, due_on, status, priority, owner, project, notes, sample, created_by)
  values (p_cid, console.crm_number(p_cid, 'RFQ'), 'DM/RFQ/2641', c1, k1, l4, td - 9, td + 3, 'Quoted', 'High', me, 'Drive train 2027 programme', 'Annual volume 99,600. Drawing DRG-1101-A rev C.', true, me) returning id into r1;
  insert into console.crm_rfqs (customer_id, no, customer_ref, party_id, contact_id, received_on, due_on, status, priority, owner, project, sample, created_by)
  values (p_cid, console.crm_number(p_cid, 'RFQ'), 'SAC-Q-118', c2, k2, td - 3, td + 6, 'Costing', 'Normal', me, 'Wheel hub and bracket', true, me) returning id into r2;
  insert into console.crm_rfqs (customer_id, no, customer_ref, party_id, contact_id, received_on, due_on, status, priority, owner, sample, created_by)
  values (p_cid, console.crm_number(p_cid, 'RFQ'), 'PPI/SRC/0912', c3, k3, td - 1, td - 1, 'Received', 'Urgent', me, true, me) returning id into r3;
  insert into console.crm_rfqs (customer_id, no, customer_ref, party_id, contact_id, lead_id, received_on, due_on, status, priority, owner, project, decided_on, sample, created_by)
  values (p_cid, console.crm_number(p_cid, 'RFQ'), 'SAC-Q-097', c2, k2, l5, td - 40, td - 30, 'Won', 'Normal', me, 'Wheel hub DP-1102', td - 12, true, me) returning id into r4;
  n := n + 4;
  cst := '{"mat_wt":1.85,"mat_rate":78,"scrap_pct":6,"mat_other":0,"ops":[{"name":"Turning (CNC)","min":4.5,"rate":650},{"name":"Drilling and tapping","min":1.8,"rate":520},{"name":"Deburring and wash","min":0.6,"rate":300}],"outs":[],"tool_cost":120000,"tool_qty":100000,"packing":4.5,"freight":3,"other":0,"oh_pct":10,"margin_pct":12}';
  cc := console.crm_cost(cst::jsonb);
  insert into console.crm_rfq_items (customer_id, rfq_id, seq, part_no, part_name, drawing_no, revision, material, qty, annual_qty, uom, target_price, cost, unit_cost, unit_price, sample)
  values (p_cid, r1, 1, 'DP-1101', 'Drive flange', 'DRG-1101-A', 'C', 'EN8 forged', 8300, 99600, 'Nos', 410, cst::jsonb, (cc ->> 'total_cost')::numeric, (cc ->> 'price')::numeric, true) returning id into i1;
  cst := '{"mat_wt":0.62,"mat_rate":92,"scrap_pct":5,"ops":[{"name":"VMC machining","min":3.2,"rate":720},{"name":"Drilling","min":0.9,"rate":480}],"outs":[],"packing":2.5,"freight":2,"oh_pct":10,"margin_pct":14}';
  cc := console.crm_cost(cst::jsonb);
  insert into console.crm_rfq_items (customer_id, rfq_id, seq, part_no, part_name, drawing_no, revision, material, qty, annual_qty, uom, target_price, cost, unit_cost, unit_price, sample)
  values (p_cid, r1, 2, 'DP-1105', 'Locating pin', 'DRG-1105-A', 'B', 'EN24', 8300, 99600, 'Nos', 105, cst::jsonb, (cc ->> 'total_cost')::numeric, (cc ->> 'price')::numeric, true) returning id into i2;
  cst := '{"mat_wt":3.4,"mat_rate":74,"scrap_pct":7,"ops":[{"name":"CNC turning","min":6,"rate":650},{"name":"VMC milling","min":5.5,"rate":720}],"outs":[],"packing":6,"freight":4,"oh_pct":10,"margin_pct":12}';
  cc := console.crm_cost(cst::jsonb);
  insert into console.crm_rfq_items (customer_id, rfq_id, seq, part_no, part_name, drawing_no, revision, material, qty, annual_qty, uom, target_price, cost, unit_cost, unit_price, sample)
  values (p_cid, r2, 1, 'DP-1102', 'Wheel hub', 'DRG-1102-A', 'B', 'SG iron casting', 5600, 67200, 'Nos', null, cst::jsonb, (cc ->> 'total_cost')::numeric, (cc ->> 'price')::numeric, true) returning id into i3;
  insert into console.crm_rfq_items (customer_id, rfq_id, seq, part_no, part_name, drawing_no, revision, material, qty, annual_qty, uom, sample)
  values (p_cid, r2, 2, 'DP-1108', 'Bracket', 'DRG-1108-A', 'A', 'IS 2062 plate', 3000, 36000, 'Nos', true) returning id into i4;
  insert into console.crm_rfq_items (customer_id, rfq_id, seq, part_no, part_name, drawing_no, revision, material, qty, annual_qty, uom, sample)
  values (p_cid, r3, 1, 'PP-7710', 'Pump shaft', 'PPI-7710', 'D', 'SS 410', 1200, 14400, 'Nos', true);
  cst := '{"mat_wt":3.4,"mat_rate":74,"scrap_pct":7,"ops":[{"name":"CNC turning","min":6,"rate":650},{"name":"VMC milling","min":5.5,"rate":720}],"packing":6,"freight":4,"oh_pct":10,"margin_pct":12}';
  cc := console.crm_cost(cst::jsonb);
  insert into console.crm_rfq_items (customer_id, rfq_id, seq, part_no, part_name, drawing_no, revision, material, qty, annual_qty, uom, cost, unit_cost, unit_price, sample)
  values (p_cid, r4, 1, 'DP-1102', 'Wheel hub', 'DRG-1102-A', 'B', 'SG iron casting', 5600, 67200, 'Nos', cst::jsonb, (cc ->> 'total_cost')::numeric, (cc ->> 'price')::numeric, true) returning id into i5;
  n := n + 6;
  -- supplier prices for the locating pin heat treatment, and for the bracket plate
  insert into console.crm_supplier_quotes (customer_id, rfq_id, item_id, supplier_id, what, price, moq, lead_days, valid_until, payment_terms, quote_ref, received_on, selected, sample, created_by)
  values (p_cid, r1, i2, s2, 'Outsourced process', 6.2, 5000, 7, td + 20, '30 days', 'AHT/0412', td - 6, true, true, me) returning id into sq1;
  insert into console.crm_supplier_quotes (customer_id, rfq_id, item_id, supplier_id, what, price, moq, lead_days, valid_until, payment_terms, quote_ref, received_on, sample, created_by)
  values (p_cid, r1, i2, s1, 'Outsourced process', 7.1, 2000, 5, td + 15, '15 days', 'SS/HT/77', td - 5, true, me);
  insert into console.crm_supplier_quotes (customer_id, rfq_id, item_id, supplier_id, what, price, moq, lead_days, valid_until, payment_terms, received_on, sample, created_by)
  values (p_cid, r2, i4, s1, 'Raw material', 48.5, 3000, 10, td + 12, '15 days', td - 2, true, me);
  insert into console.crm_supplier_quotes (customer_id, rfq_id, item_id, supplier_id, what, price, moq, lead_days, valid_until, payment_terms, received_on, sample, created_by)
  values (p_cid, r2, i4, s2, 'Raw material', 46.8, 6000, 14, td + 10, '30 days', td - 2, true, me);
  -- the lowest heat-treatment price is chosen: it goes into the locating pin's costing
  cst := (select cost from console.crm_rfq_items where id = i2);
  cst := jsonb_set(cst, '{outs}', jsonb_build_array(jsonb_build_object('name', 'Outsourced process — Anand Heat Treatments', 'amt', 6.2, 'sq', sq1)), true);
  cc := console.crm_cost(cst);
  update console.crm_rfq_items set cost = cst, unit_cost = (cc ->> 'total_cost')::numeric, unit_price = (cc ->> 'price')::numeric where id = i2;
  n := n + 4;
  -- a sent quotation, and the accepted one for the won RFQ
  select coalesce(jsonb_agg(jsonb_build_object('seq', i.seq, 'part_no', i.part_no, 'part_name', i.part_name, 'drawing_no', i.drawing_no, 'revision', i.revision, 'qty', i.qty, 'uom', i.uom, 'unit_price', i.unit_price, 'lead_days', 28) order by i.seq), '[]')
    into lines from console.crm_rfq_items i where i.rfq_id = r1;
  select * into tt from console.crm_totals(lines, 18);
  no_ := console.crm_number(p_cid, 'QTN');
  insert into console.crm_quotes (customer_id, no, rev, rfq_id, party_id, contact_id, quote_date, valid_until, status, tax_pct, payment_terms, delivery_terms, terms, lines, subtotal, tax_amt, total, prepared_by, sent_on, sample)
  values (p_cid, no_, 0, r1, c1, k1, td - 2, td + 28, 'sent', 18, '45 days from invoice', 'Ex-works, packing included', E'1. Prices are per piece in Indian rupees and exclusive of tax.\n2. Delivery as per lead time from a confirmed purchase order.\n3. Tooling charged separately as agreed.', lines, tt.sub, tt.tax, tt.tot, me, td - 2, true);
  select coalesce(jsonb_agg(jsonb_build_object('seq', i.seq, 'part_no', i.part_no, 'part_name', i.part_name, 'drawing_no', i.drawing_no, 'revision', i.revision, 'qty', i.qty, 'uom', i.uom, 'unit_price', i.unit_price, 'lead_days', 21) order by i.seq), '[]')
    into lines from console.crm_rfq_items i where i.rfq_id = r4;
  select * into tt from console.crm_totals(lines, 18);
  insert into console.crm_quotes (customer_id, no, rev, rfq_id, party_id, contact_id, quote_date, valid_until, status, tax_pct, payment_terms, delivery_terms, lines, subtotal, tax_amt, total, prepared_by, sent_on, decided_on, sample)
  values (p_cid, console.crm_number(p_cid, 'QTN'), 0, r4, c2, k2, td - 38, td - 8, 'accepted', 18, '30 days from invoice', 'Ex-works', lines, tt.sub, tt.tax, tt.tot, me, td - 38, td - 12, true);
  n := n + 2;
  insert into console.crm_activities (customer_id, lead_id, party_id, rfq_id, kind, subject, notes, due_date, done, done_at, owner, sample, created_by) values
    (p_cid, l1, c4, null, 'call', 'Call about the manifold block drawings', 'Ask for the 3D model and the expected annual volume.', td + 2, false, null, me, true, me),
    (p_cid, l2, null, null, 'email', 'Send company profile and rate card', null, td, false, null, me, true, me),
    (p_cid, l3, null, null, 'visit', 'Plant visit — Nilgiri Tractors', 'Overdue — reschedule with D. Joseph.', td - 3, false, null, me, true, me),
    (p_cid, null, c1, r1, 'call', 'Chase the quotation response', 'Buyer said the commercial review is next week.', td + 4, false, null, me, true, me),
    (p_cid, null, c2, r2, 'task', 'Get heat-treatment price for the bracket', null, td + 1, false, null, me, true, me),
    (p_cid, l5, c2, r4, 'meeting', 'Kick-off meeting after order', 'Agreed schedule and first delivery.', td - 12, true, now() - interval '12 days', me, true, me);
  n := n + 6;
  return n;
end $$;
revoke all on function console.crm_sample(uuid, text) from public, anon, authenticated;

do $$ declare f record; begin
  for f in select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname ~ '^kmr_crm_' loop
    execute format('revoke all on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
end $$;
