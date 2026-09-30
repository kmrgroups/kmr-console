-- =====================================================================
-- KMR Console — Milestone 4: prices, invoices and (test) payments. Needs 0001–0005. Safe to re-run.
--  • Price list: per product, per billing period (month / year) and currency — a price per user / employee
--    and a minimum number billed.
--  • Seller details (GSTIN, state, SAC, bank / UPI, invoice prefix) in console.billing_settings.
--  • Invoices: drafted from the price list, GST worked out automatically (CGST + SGST in the same state, IGST
--    across states, zero-rated export under LUT abroad, none when no GSTIN is set), numbered without gaps per
--    financial year when issued (KMR/26-27/0001). Issued invoices are never deleted — only cancelled.
--  • Payments: Razorpay Checkout through each invoice's pay link (test or live keys) or recorded by hand
--    (bank transfer, cheque…). A paid invoice renews the customer's licences: active, end date = end of the
--    paid period, limit = users / employees paid for.
-- =====================================================================
do $$ begin
  if to_regprocedure('console.console_export()') is null then raise exception 'Run 0005_data_tools.sql first.'; end if;
end $$;
create extension if not exists pgcrypto;

-- ---------- tables ----------
create table if not exists console.prices (
  id           uuid primary key default gen_random_uuid(),
  product_code text not null references console.products(code) on delete cascade,
  period       text not null check (period in ('month','year')),
  currency     text not null check (currency ~ '^[A-Z]{3}$'),
  unit_amount  numeric(12,2) not null check (unit_amount >= 0),
  min_seats    integer not null default 1 check (min_seats between 1 and 100000),
  active       boolean not null default true,
  note         text check (length(note) <= 300),
  updated_at   timestamptz not null default now(),
  unique (product_code, period, currency)
);

create table if not exists console.billing_settings (
  id             boolean primary key default true check (id),
  legal_name     text not null default 'KMR Group of Companies',
  gstin          text check (gstin is null or gstin ~ '^[0-9]{2}[A-Z0-9]{13}$'),
  pan            text,
  address        text,
  city           text,
  state          text,
  state_code     text check (state_code is null or state_code ~ '^[0-9]{2}$'),
  postal_code    text,
  email          text,
  phone          text,
  invoice_prefix text not null default 'KMR' check (invoice_prefix ~ '^[A-Z0-9-]{1,10}$'),
  sac_code       text not null default '998314',
  gst_rate       numeric(5,2) not null default 18 check (gst_rate between 0 and 40),
  lut_no         text,
  bank_details   text,
  upi_id         text,
  payment_days   integer not null default 15 check (payment_days between 0 and 120),
  terms          text,
  updated_at     timestamptz not null default now()
);
insert into console.billing_settings (id) values (true) on conflict (id) do nothing;

create table if not exists console.invoice_counters (fy text primary key, last_no integer not null default 0);

create table if not exists console.invoices (
  id               uuid primary key default gen_random_uuid(),
  number           text unique,
  customer_id      uuid not null references console.customers(id) on delete restrict,
  status           text not null default 'draft' check (status in ('draft','issued','paid','cancelled')),
  period           text check (period in ('month','year')),
  currency         text not null check (currency ~ '^[A-Z]{3}$'),
  issue_date       date,
  due_date         date,
  tax_type         text not null default 'none' check (tax_type in ('cgst_sgst','igst','export','none')),
  gst_rate         numeric(5,2) not null default 0,
  subtotal         numeric(12,2) not null default 0,
  cgst             numeric(12,2) not null default 0,
  sgst             numeric(12,2) not null default 0,
  igst             numeric(12,2) not null default 0,
  total            numeric(12,2) not null default 0,
  seller           jsonb not null default '{}',
  buyer            jsonb not null default '{}',
  notes            text check (length(notes) <= 2000),
  pay_token        text not null unique default encode(gen_random_bytes(18), 'hex'),
  paid_at          timestamptz,
  cancelled_reason text,
  created_by       uuid,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create index if not exists invoices_customer on console.invoices (customer_id, created_at desc);

create table if not exists console.invoice_lines (
  id           bigserial primary key,
  invoice_id   uuid not null references console.invoices(id) on delete cascade,
  sort         integer not null default 0,
  product_code text references console.products(code),
  description  text not null check (length(description) between 1 and 300),
  period_from  date,
  period_to    date,
  qty          numeric(12,2) not null check (qty > 0),
  unit_amount  numeric(12,2) not null check (unit_amount >= 0),
  amount       numeric(12,2) not null
);
create index if not exists invoice_lines_invoice on console.invoice_lines (invoice_id, sort);

create table if not exists console.payments (
  id          uuid primary key default gen_random_uuid(),
  invoice_id  uuid not null references console.invoices(id) on delete restrict,
  provider    text not null check (provider in ('razorpay','manual')),
  mode        text not null default 'test' check (mode in ('test','live')),
  order_id    text unique,
  payment_id  text unique,
  amount      numeric(12,2) not null,
  currency    text not null,
  status      text not null default 'created' check (status in ('created','paid','failed')),
  reference   text,
  detail      jsonb,
  recorded_by uuid,
  created_at  timestamptz not null default now(),
  paid_at     timestamptz
);
create index if not exists payments_invoice on console.payments (invoice_id, created_at desc);

-- ---------- security: staff read everything; managers edit prices and seller details; all invoice and
-- payment changes go through the functions below ----------
alter table console.prices enable row level security;
alter table console.billing_settings enable row level security;
alter table console.invoice_counters enable row level security;
alter table console.invoices enable row level security;
alter table console.invoice_lines enable row level security;
alter table console.payments enable row level security;
do $$ declare t text; begin
  foreach t in array array['prices','billing_settings','invoices','invoice_lines','payments'] loop
    execute format('drop policy if exists %I on console.%I', t || '_read', t);
    execute format('create policy %I on console.%I for select to authenticated using (console.is_staff())', t || '_read', t);
  end loop;
  foreach t in array array['prices','billing_settings'] loop
    execute format('drop policy if exists %I on console.%I', t || '_write', t);
    execute format('create policy %I on console.%I for all to authenticated using (console.is_manager()) with check (console.is_manager())', t || '_write', t);
  end loop;
end $$;
revoke all on console.prices, console.billing_settings, console.invoice_counters, console.invoices, console.invoice_lines, console.payments from anon;

-- ---------- helpers ----------
-- Indian financial year of a date: 2026-09-30 → '26-27', 2027-02-01 → '26-27'
create or replace function console.fin_year(d date) returns text language sql immutable as $$
  select case when extract(month from d) >= 4
    then to_char(d, 'YY') || '-' || to_char(d + interval '1 year', 'YY')
    else to_char(d - interval '1 year', 'YY') || '-' || to_char(d, 'YY') end
$$;

create or replace function console.require_manager() returns void language plpgsql stable security definer set search_path = console, public as $$
begin
  if not console.is_manager() then raise exception 'Only an owner or administrator can do this.'; end if;
end $$;

-- Recalculate a draft's tax and totals from its lines, the customer and the seller details
create or replace function console.invoice_recalc(p_id uuid) returns void
language plpgsql security definer set search_path = console, public as $$
declare inv console.invoices; c console.customers; s console.billing_settings; sub numeric; tt text; buyer_code text; rate numeric;
begin
  select * into inv from console.invoices where id = p_id for update;
  if inv.status <> 'draft' then return; end if;
  select * into c from console.customers where id = inv.customer_id;
  select * into s from console.billing_settings where id;
  sub := coalesce((select sum(amount) from console.invoice_lines where invoice_id = p_id), 0);
  buyer_code := case when coalesce(c.tax_id, '') ~ '^[0-9]{2}[A-Z0-9]{13}$' then left(c.tax_id, 2) end;
  tt := case
    when c.country <> 'IN' then 'export'
    when s.gstin is null or s.gst_rate = 0 then 'none'
    when buyer_code is not null then case when buyer_code = coalesce(s.state_code, left(s.gstin, 2)) then 'cgst_sgst' else 'igst' end
    when nullif(trim(c.state), '') is not null and nullif(trim(s.state), '') is not null then
         case when lower(trim(c.state)) = lower(trim(s.state)) then 'cgst_sgst' else 'igst' end
    else 'cgst_sgst' end;
  rate := case when tt in ('cgst_sgst','igst') then s.gst_rate else 0 end;
  update console.invoices set subtotal = sub, tax_type = tt, gst_rate = rate,
    cgst = case when tt = 'cgst_sgst' then round(sub * rate / 200, 2) else 0 end,
    sgst = case when tt = 'cgst_sgst' then round(sub * rate / 200, 2) else 0 end,
    igst = case when tt = 'igst' then round(sub * rate / 100, 2) else 0 end,
    updated_at = now()
   where id = p_id;
  update console.invoices set total = subtotal + cgst + sgst + igst where id = p_id;
end $$;

-- ---------- invoices (owners / administrators) ----------
-- New draft from the price list. p_items = [{"product_code":"hrm","seats":40}, …]
create or replace function console.create_invoice(p_customer uuid, p_period text, p_from date, p_items jsonb, p_notes text default null) returns uuid
language plpgsql security definer set search_path = console, public as $$
declare c console.customers; it jsonb; pr console.prices; prod console.products; q numeric; inv uuid; n int := 0; pto date;
begin
  perform console.require_manager();
  select * into c from console.customers where id = p_customer;
  if c.id is null then raise exception 'Customer not found.'; end if;
  if p_period not in ('month','year') then raise exception 'Choose monthly or yearly billing.'; end if;
  if p_from is null then raise exception 'Choose the date the billed period starts.'; end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then raise exception 'Pick at least one product to bill.'; end if;
  pto := (p_from + case when p_period = 'year' then interval '1 year' else interval '1 month' end - interval '1 day')::date;
  insert into console.invoices (customer_id, period, currency, notes, created_by)
  values (c.id, p_period, c.currency, nullif(trim(coalesce(p_notes, '')), ''), auth.uid()) returning id into inv;
  for it in select * from jsonb_array_elements(p_items) loop
    select * into prod from console.products where code = it ->> 'product_code';
    if prod.code is null then raise exception 'Unknown product %.', it ->> 'product_code'; end if;
    select * into pr from console.prices where product_code = prod.code and period = p_period and currency = c.currency and active;
    if pr.id is null then
      raise exception 'There is no % price in % for %. Add it under Prices & invoices first.', case when p_period = 'year' then 'yearly' else 'monthly' end, c.currency, prod.name;
    end if;
    q := greatest(coalesce(nullif(it ->> 'seats', '')::numeric, 0), pr.min_seats);
    n := n + 1;
    insert into console.invoice_lines (invoice_id, sort, product_code, description, period_from, period_to, qty, unit_amount, amount)
    values (inv, n, prod.code, prod.name || ' — ' || case when p_period = 'year' then 'yearly' else 'monthly' end || ' subscription, ' || q::int || ' ' || prod.seat_label,
            p_from, pto, q, pr.unit_amount, round(q * pr.unit_amount, 2));
  end loop;
  perform console.invoice_recalc(inv);
  return inv;
end $$;

-- An extra line on a draft (set-up, training, discount as a negative amount is not allowed — lower the price instead)
create or replace function console.add_invoice_line(p_invoice uuid, p_description text, p_qty numeric, p_unit_amount numeric) returns void
language plpgsql security definer set search_path = console, public as $$
begin
  perform console.require_manager();
  if (select status from console.invoices where id = p_invoice) is distinct from 'draft' then raise exception 'Only a draft invoice can be changed.'; end if;
  if length(trim(coalesce(p_description, ''))) = 0 then raise exception 'Describe the line.'; end if;
  if coalesce(p_qty, 0) <= 0 or coalesce(p_unit_amount, -1) < 0 then raise exception 'Quantity must be above 0 and the rate 0 or more.'; end if;
  insert into console.invoice_lines (invoice_id, sort, description, qty, unit_amount, amount)
  values (p_invoice, coalesce((select max(sort) from console.invoice_lines where invoice_id = p_invoice), 0) + 1, trim(p_description), p_qty, p_unit_amount, round(p_qty * p_unit_amount, 2));
  perform console.invoice_recalc(p_invoice);
end $$;

create or replace function console.remove_invoice_line(p_invoice uuid, p_line bigint) returns void
language plpgsql security definer set search_path = console, public as $$
begin
  perform console.require_manager();
  if (select status from console.invoices where id = p_invoice) is distinct from 'draft' then raise exception 'Only a draft invoice can be changed.'; end if;
  delete from console.invoice_lines where id = p_line and invoice_id = p_invoice;
  perform console.invoice_recalc(p_invoice);
end $$;

create or replace function console.discard_invoice(p_invoice uuid) returns void
language plpgsql security definer set search_path = console, public as $$
begin
  perform console.require_manager();
  if (select status from console.invoices where id = p_invoice) is distinct from 'draft' then
    raise exception 'Only a draft can be discarded. Cancel an issued invoice instead — its number stays in the series.';
  end if;
  delete from console.invoices where id = p_invoice;
end $$;

-- Issue: next number in the financial year, seller and buyer details frozen on the invoice
create or replace function console.issue_invoice(p_invoice uuid) returns text
language plpgsql security definer set search_path = console, public as $$
declare inv console.invoices; c console.customers; s console.billing_settings; v_fy text; n int; num text;
begin
  perform console.require_manager();
  select * into inv from console.invoices where id = p_invoice for update;
  if inv.id is null then raise exception 'Invoice not found.'; end if;
  if inv.status <> 'draft' then raise exception 'This invoice is already %.', inv.status; end if;
  if not exists (select 1 from console.invoice_lines where invoice_id = p_invoice) then raise exception 'The invoice has no lines.'; end if;
  perform console.invoice_recalc(p_invoice);
  select * into inv from console.invoices where id = p_invoice;
  if inv.total <= 0 then raise exception 'The invoice total must be above zero.'; end if;
  select * into c from console.customers where id = inv.customer_id;
  select * into s from console.billing_settings where id;
  if nullif(trim(coalesce(s.address, '')), '') is null then raise exception 'Fill in your seller details (address) under Prices & invoices before issuing.'; end if;
  v_fy := console.fin_year(current_date);
  insert into console.invoice_counters (fy, last_no) values (v_fy, 1)
  on conflict (fy) do update set last_no = console.invoice_counters.last_no + 1 returning last_no into n;
  num := s.invoice_prefix || '/' || v_fy || '/' || lpad(n::text, 4, '0');
  update console.invoices set number = num, status = 'issued', issue_date = current_date, due_date = current_date + s.payment_days,
    seller = jsonb_build_object('legal_name', s.legal_name, 'gstin', s.gstin, 'pan', s.pan, 'address', s.address, 'city', s.city, 'state', s.state,
      'state_code', coalesce(s.state_code, left(s.gstin, 2)), 'postal_code', s.postal_code, 'email', s.email, 'phone', s.phone, 'sac_code', s.sac_code,
      'lut_no', s.lut_no, 'bank_details', s.bank_details, 'upi_id', s.upi_id, 'terms', s.terms),
    buyer = jsonb_build_object('code', c.code, 'name', coalesce(nullif(c.legal_name, ''), c.name), 'tax_id', c.tax_id, 'address', c.address, 'city', c.city,
      'state', c.state, 'postal_code', c.postal_code, 'country', c.country, 'contact_name', c.contact_name, 'contact_email', c.contact_email),
    updated_at = now()
   where id = p_invoice;
  return num;
end $$;

create or replace function console.cancel_invoice(p_invoice uuid, p_reason text) returns void
language plpgsql security definer set search_path = console, public as $$
begin
  perform console.require_manager();
  if (select status from console.invoices where id = p_invoice) is distinct from 'issued' then raise exception 'Only an issued, unpaid invoice can be cancelled.'; end if;
  if length(trim(coalesce(p_reason, ''))) < 3 then raise exception 'Give a reason for cancelling.'; end if;
  update console.invoices set status = 'cancelled', cancelled_reason = trim(p_reason), updated_at = now() where id = p_invoice;
end $$;

-- Paid: invoice closed, licences renewed for the paid period and users / employees
create or replace function console.apply_paid_invoice(p_invoice uuid, p_paid_at timestamptz) returns void
language plpgsql security definer set search_path = console, public as $$
declare inv console.invoices; ln record;
begin
  select * into inv from console.invoices where id = p_invoice for update;
  if inv.status <> 'issued' then return; end if;
  update console.invoices set status = 'paid', paid_at = p_paid_at, updated_at = now() where id = p_invoice;
  for ln in select product_code, max(period_to) period_to, max(qty) qty from console.invoice_lines
             where invoice_id = p_invoice and product_code is not null and period_to is not null group by product_code loop
    update console.licences l set status = 'active',
      valid_until = case when l.valid_until is null and l.status = 'active' then null else greatest(coalesce(l.valid_until, ln.period_to), ln.period_to) end,
      seats = ceil(ln.qty)::int, updated_at = now()
     where l.customer_id = inv.customer_id and l.product_code = ln.product_code;
  end loop;
  update console.customers set status = 'active', updated_at = now() where id = inv.customer_id and status in ('lead','pilot');
end $$;
revoke all on function console.apply_paid_invoice(uuid, timestamptz), console.invoice_recalc(uuid) from public, anon, authenticated;

-- Payment received outside Razorpay (bank transfer, cheque, UPI to the bank account…)
create or replace function console.mark_invoice_paid(p_invoice uuid, p_reference text, p_date date default current_date) returns void
language plpgsql security definer set search_path = console, public as $$
declare inv console.invoices;
begin
  perform console.require_manager();
  select * into inv from console.invoices where id = p_invoice;
  if inv.status is distinct from 'issued' then raise exception 'Only an issued, unpaid invoice can be marked paid.'; end if;
  if length(trim(coalesce(p_reference, ''))) < 3 then raise exception 'Enter the payment reference (UTR, cheque no. …).'; end if;
  insert into console.payments (invoice_id, provider, mode, amount, currency, status, reference, recorded_by, paid_at)
  values (p_invoice, 'manual', 'live', inv.total, inv.currency, 'paid', trim(p_reference), auth.uid(), coalesce(p_date, current_date)::timestamptz);
  perform console.apply_paid_invoice(p_invoice, coalesce(p_date, current_date)::timestamptz);
end $$;

-- ---------- the public pay link (called by the Console server with the service key only) ----------
create or replace function console.invoice_for_token(p_token text) returns jsonb
language sql stable security definer set search_path = console, public as $$
  select jsonb_build_object('invoice', to_jsonb(i) - 'created_by', 'lines',
           coalesce((select jsonb_agg(to_jsonb(l) order by l.sort, l.id) from console.invoice_lines l where l.invoice_id = i.id), '[]'),
           'paid_by', (select jsonb_build_object('provider', p.provider, 'mode', p.mode, 'payment_id', p.payment_id, 'reference', p.reference, 'paid_at', p.paid_at)
                         from console.payments p where p.invoice_id = i.id and p.status = 'paid' order by p.paid_at desc limit 1))
    from console.invoices i where i.pay_token = p_token and i.status in ('issued','paid','cancelled') and length(p_token) >= 20
$$;

create or replace function console.razorpay_order_started(p_token text, p_order_id text, p_mode text, p_amount numeric, p_currency text) returns void
language plpgsql security definer set search_path = console, public as $$
declare inv console.invoices;
begin
  select * into inv from console.invoices where pay_token = p_token;
  if inv.status is distinct from 'issued' then raise exception 'This invoice cannot be paid (it is %).', coalesce(inv.status, 'not found'); end if;
  if p_amount <> inv.total or p_currency <> inv.currency then raise exception 'Amount does not match the invoice.'; end if;
  insert into console.payments (invoice_id, provider, mode, order_id, amount, currency)
  values (inv.id, 'razorpay', case when p_mode = 'live' then 'live' else 'test' end, p_order_id, p_amount, p_currency);
end $$;

-- A Razorpay payment whose signature the server has verified. Safe to call twice (checkout + webhook).
create or replace function console.razorpay_payment_verified(p_order_id text, p_payment_id text, p_detail jsonb default null) returns jsonb
language plpgsql security definer set search_path = console, public as $$
declare pay console.payments;
begin
  select * into pay from console.payments where order_id = p_order_id and provider = 'razorpay' for update;
  if pay.id is null then raise exception 'Unknown Razorpay order.'; end if;
  if pay.status <> 'paid' then
    update console.payments set status = 'paid', payment_id = p_payment_id, detail = p_detail, paid_at = now() where id = pay.id;
    perform console.apply_paid_invoice(pay.invoice_id, now());
  end if;
  return jsonb_build_object('invoice_id', pay.invoice_id, 'status', (select status from console.invoices where id = pay.invoice_id));
end $$;

revoke all on function console.invoice_for_token(text), console.razorpay_order_started(text, text, text, numeric, text),
  console.razorpay_payment_verified(text, text, jsonb) from public, anon, authenticated;
grant execute on function console.invoice_for_token(text), console.razorpay_order_started(text, text, text, numeric, text),
  console.razorpay_payment_verified(text, text, jsonb) to service_role;

-- ---------- customer portal: a company's invoices, for its administrators ----------
create or replace function public.kmr_portal_invoices(p_slug text) returns jsonb
language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or not console.is_customer_admin(cid) then raise exception 'Only your company''s administrators can see invoices.'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('number', number, 'issue_date', issue_date, 'due_date', due_date, 'total', total, 'currency', currency,
            'status', status, 'pay_token', pay_token) order by issue_date desc, number desc)
          from console.invoices where customer_id = cid and status in ('issued','paid','cancelled')), '[]');
end $$;
revoke all on function public.kmr_portal_invoices(text) from public, anon;
grant execute on function public.kmr_portal_invoices(text) to authenticated;

-- ---------- backups include billing ----------
create or replace function console.console_export() returns jsonb
language plpgsql stable security definer set search_path = console, public as $fn$
declare out jsonb := '{}'::jsonb; t text; rows jsonb;
begin
  foreach t in array array['products','customers','licences','licence_events','releases','tickets','ticket_messages','leads','staff',
                           'prices','billing_settings','invoice_counters','invoices','invoice_lines','payments'] loop
    execute format('select coalesce(jsonb_agg(to_jsonb(x)), ''[]'') from console.%I x', t) into rows;
    out := out || jsonb_build_object(t, rows);
  end loop;
  return jsonb_build_object('format', 'kmr-console-backup', 'version', 1, 'exported_at', now(), 'tables', out);
end $fn$;
revoke all on function console.console_export() from public, anon, authenticated;
grant execute on function console.console_export() to service_role;

-- ---------- Console sample data: flushing the demo customers also removes their invoices and payments ----------
create or replace function console.demo_flush() returns integer
language plpgsql security definer set search_path = console, public as $fn$
declare n integer;
begin
  delete from console.payments where invoice_id in (select i.id from console.invoices i join console.customers c on c.id = i.customer_id where c.source = 'KMR demo data');
  delete from console.invoices where customer_id in (select id from console.customers where source = 'KMR demo data');
  delete from console.tickets where raised_by_email like '%demo.kmr.test';
  delete from console.leads where email like '%demo.kmr.test';
  delete from console.customers where source = 'KMR demo data';
  get diagnostics n = row_count;
  return n;
end $fn$;
revoke all on function console.demo_flush() from public, anon, authenticated;
grant execute on function console.demo_flush() to service_role;
