-- =====================================================================
-- KMR Console — payments straight to KMR's bank account (replaces Razorpay). Needs 0018. Safe to re-run.
--  • Seller details get the bank account as separate fields (account name, number, IFSC, bank, branch, type,
--    SWIFT for customers abroad) and a UPI ID; they are frozen on each invoice when it is issued.
--  • The customer pays by NEFT / RTGS / IMPS / UPI / cheque using the details on the invoice's pay link, then
--    reports it there ("I've paid": method, UTR / reference, date, amount).
--  • KMR checks the bank statement and Confirms (invoice paid, licences renewed) or Rejects (with a reason).
--    Payments can still be recorded directly with Mark as paid.
-- =====================================================================
do $$ begin
  if to_regclass('console.invoices') is null then raise exception 'Run 0018_billing.sql first.'; end if;
end $$;

-- ---------- bank account in the seller details ----------
alter table console.billing_settings
  add column if not exists bank_account_name text,
  add column if not exists bank_account_no   text check (bank_account_no is null or bank_account_no ~ '^[0-9]{6,20}$'),
  add column if not exists bank_ifsc         text check (bank_ifsc is null or bank_ifsc ~ '^[A-Z]{4}0[A-Z0-9]{6}$'),
  add column if not exists bank_name         text,
  add column if not exists bank_branch       text,
  add column if not exists bank_account_type text,
  add column if not exists bank_swift        text check (bank_swift is null or bank_swift ~ '^[A-Z0-9]{8}([A-Z0-9]{3})?$');

-- ---------- payments: reported by the customer, confirmed or rejected by KMR ----------
alter table console.payments drop constraint if exists payments_provider_check;
alter table console.payments add constraint payments_provider_check check (provider in ('manual','bank_transfer','upi','cheque','razorpay'));
alter table console.payments drop constraint if exists payments_status_check;
alter table console.payments add constraint payments_status_check check (status in ('created','reported','paid','failed','rejected'));
alter table console.payments
  add column if not exists method        text check (method is null or method in ('neft','rtgs','imps','upi','cheque','other')),
  add column if not exists paid_on       date,
  add column if not exists payer_name    text check (payer_name is null or length(payer_name) <= 120),
  add column if not exists reject_reason text;
alter table console.payments alter column mode set default 'live';

drop function if exists console.razorpay_order_started(text, text, text, numeric, text);
drop function if exists console.razorpay_payment_verified(text, text, jsonb);

-- Issue: the bank account is frozen on the invoice with the other seller details
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
  if s.bank_account_no is null and s.upi_id is null and nullif(trim(coalesce(s.bank_details, '')), '') is null then
    raise exception 'Add your bank account (or UPI ID) under Prices & invoices › Seller details, so the customer knows where to pay.';
  end if;
  v_fy := console.fin_year(current_date);
  insert into console.invoice_counters (fy, last_no) values (v_fy, 1)
  on conflict (fy) do update set last_no = console.invoice_counters.last_no + 1 returning last_no into n;
  num := s.invoice_prefix || '/' || v_fy || '/' || lpad(n::text, 4, '0');
  update console.invoices set number = num, status = 'issued', issue_date = current_date, due_date = current_date + s.payment_days,
    seller = jsonb_build_object('legal_name', s.legal_name, 'gstin', s.gstin, 'pan', s.pan, 'address', s.address, 'city', s.city, 'state', s.state,
      'state_code', coalesce(s.state_code, left(s.gstin, 2)), 'postal_code', s.postal_code, 'email', s.email, 'phone', s.phone, 'sac_code', s.sac_code,
      'lut_no', s.lut_no, 'bank_details', s.bank_details, 'upi_id', s.upi_id, 'terms', s.terms,
      'bank_account_name', s.bank_account_name, 'bank_account_no', s.bank_account_no, 'bank_ifsc', s.bank_ifsc, 'bank_name', s.bank_name,
      'bank_branch', s.bank_branch, 'bank_account_type', s.bank_account_type, 'bank_swift', s.bank_swift),
    buyer = jsonb_build_object('code', c.code, 'name', coalesce(nullif(c.legal_name, ''), c.name), 'tax_id', c.tax_id, 'address', c.address, 'city', c.city,
      'state', c.state, 'postal_code', c.postal_code, 'country', c.country, 'contact_name', c.contact_name, 'contact_email', c.contact_email),
    updated_at = now()
   where id = p_invoice;
  return num;
end $$;

-- Payment recorded directly by KMR (bank statement, cheque …)
drop function if exists console.mark_invoice_paid(uuid, text, date);
create or replace function console.mark_invoice_paid(p_invoice uuid, p_reference text, p_date date default current_date, p_method text default 'neft') returns void
language plpgsql security definer set search_path = console, public as $$
declare inv console.invoices; m text := coalesce(nullif(p_method, ''), 'neft');
begin
  perform console.require_manager();
  select * into inv from console.invoices where id = p_invoice;
  if inv.status is distinct from 'issued' then raise exception 'Only an issued, unpaid invoice can be marked paid.'; end if;
  if length(trim(coalesce(p_reference, ''))) < 3 then raise exception 'Enter the payment reference (UTR, cheque no. …).'; end if;
  if m not in ('neft','rtgs','imps','upi','cheque','other') then raise exception 'Unknown payment method.'; end if;
  if coalesce(p_date, current_date) > current_date then raise exception 'The payment date cannot be in the future.'; end if;
  insert into console.payments (invoice_id, provider, mode, amount, currency, status, reference, method, paid_on, recorded_by, paid_at)
  values (p_invoice, case m when 'upi' then 'upi' when 'cheque' then 'cheque' else 'bank_transfer' end, 'live', inv.total, inv.currency, 'paid',
          trim(p_reference), m, coalesce(p_date, current_date), auth.uid(), coalesce(p_date, current_date)::timestamptz);
  update console.payments set status = 'rejected', reject_reason = 'Invoice paid — recorded separately' where invoice_id = p_invoice and status = 'reported';
  perform console.apply_paid_invoice(p_invoice, coalesce(p_date, current_date)::timestamptz);
end $$;

-- The customer reports a payment on the pay link (called by the Console server with the service key only)
create or replace function console.report_payment(p_token text, p_method text, p_reference text, p_paid_on date, p_amount numeric, p_payer text default null) returns text
language plpgsql security definer set search_path = console, public as $$
declare inv console.invoices; ref text := upper(regexp_replace(trim(coalesce(p_reference, '')), '\s+', ' ', 'g'));
begin
  select * into inv from console.invoices where pay_token = p_token and length(p_token) >= 20;
  if inv.id is null then raise exception 'Invoice not found.'; end if;
  if inv.status <> 'issued' then raise exception 'This invoice is %, so no payment can be reported.', inv.status; end if;
  if coalesce(p_method, '') not in ('neft','rtgs','imps','upi','cheque','other') then raise exception 'Choose how you paid.'; end if;
  if length(ref) not between 4 and 60 then raise exception 'Enter the UTR / transaction reference from your bank (4 to 60 characters).'; end if;
  if p_paid_on is null or p_paid_on > current_date + 1 or p_paid_on < current_date - 180 then raise exception 'Enter the date you paid.'; end if;
  if coalesce(p_amount, 0) <= 0 or p_amount > inv.total * 2 then raise exception 'Enter the amount you paid.'; end if;
  if exists (select 1 from console.payments where invoice_id = inv.id and upper(reference) = ref and status in ('reported','paid')) then
    raise exception 'This reference has already been reported for this invoice. KMR will confirm it shortly.';
  end if;
  if (select count(*) from console.payments where invoice_id = inv.id and status = 'reported') >= 5 then
    raise exception 'Several payments are already waiting for confirmation. Please contact KMR.';
  end if;
  insert into console.payments (invoice_id, provider, mode, amount, currency, status, reference, method, paid_on, payer_name)
  values (inv.id, case p_method when 'upi' then 'upi' when 'cheque' then 'cheque' else 'bank_transfer' end, 'live', round(p_amount, 2), inv.currency,
          'reported', ref, p_method, p_paid_on, nullif(left(trim(coalesce(p_payer, '')), 120), ''));
  return 'ok';
end $$;

-- KMR found the money in the bank: invoice paid, licences renewed
create or replace function console.confirm_payment(p_payment uuid) returns void
language plpgsql security definer set search_path = console, public as $$
declare pay console.payments;
begin
  perform console.require_manager();
  select * into pay from console.payments where id = p_payment for update;
  if pay.status is distinct from 'reported' then raise exception 'Only a reported payment can be confirmed.'; end if;
  if (select status from console.invoices where id = pay.invoice_id) <> 'issued' then raise exception 'The invoice is no longer waiting for payment.'; end if;
  update console.payments set status = 'paid', recorded_by = auth.uid(), paid_at = coalesce(pay.paid_on, current_date)::timestamptz where id = p_payment;
  update console.payments set status = 'rejected', reject_reason = 'Invoice paid — another payment was confirmed'
   where invoice_id = pay.invoice_id and status = 'reported' and id <> p_payment;
  perform console.apply_paid_invoice(pay.invoice_id, coalesce(pay.paid_on, current_date)::timestamptz);
end $$;

create or replace function console.reject_payment(p_payment uuid, p_reason text) returns void
language plpgsql security definer set search_path = console, public as $$
begin
  perform console.require_manager();
  if (select status from console.payments where id = p_payment) is distinct from 'reported' then raise exception 'Only a reported payment can be rejected.'; end if;
  if length(trim(coalesce(p_reason, ''))) < 3 then raise exception 'Give a reason, e.g. "not received in the bank".'; end if;
  update console.payments set status = 'rejected', reject_reason = trim(p_reason), recorded_by = auth.uid() where id = p_payment;
end $$;

-- The pay link now also shows payments the customer reported
create or replace function console.invoice_for_token(p_token text) returns jsonb
language sql stable security definer set search_path = console, public as $$
  select jsonb_build_object('invoice', to_jsonb(i) - 'created_by', 'lines',
           coalesce((select jsonb_agg(to_jsonb(l) order by l.sort, l.id) from console.invoice_lines l where l.invoice_id = i.id), '[]'),
           'paid_by', (select jsonb_build_object('provider', p.provider, 'method', p.method, 'reference', p.reference, 'paid_at', p.paid_at)
                         from console.payments p where p.invoice_id = i.id and p.status = 'paid' order by p.paid_at desc limit 1),
           'reported', coalesce((select jsonb_agg(jsonb_build_object('method', p.method, 'reference', p.reference, 'amount', p.amount, 'paid_on', p.paid_on,
                         'status', p.status, 'reject_reason', p.reject_reason, 'created_at', p.created_at) order by p.created_at desc)
                         from console.payments p where p.invoice_id = i.id and p.status in ('reported','rejected') and p.created_at > now() - interval '60 days'), '[]'))
    from console.invoices i where i.pay_token = p_token and i.status in ('issued','paid','cancelled') and length(p_token) >= 20
$$;

revoke all on function console.invoice_for_token(text), console.report_payment(text, text, text, date, numeric, text) from public, anon, authenticated;
grant execute on function console.invoice_for_token(text), console.report_payment(text, text, text, date, numeric, text) to service_role;

-- Customer portal: show when a payment is waiting for KMR's confirmation
create or replace function public.kmr_portal_invoices(p_slug text) returns jsonb
language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or not console.is_customer_admin(cid) then raise exception 'Only your company''s administrators can see invoices.'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('number', i.number, 'issue_date', i.issue_date, 'due_date', i.due_date, 'total', i.total, 'currency', i.currency,
            'status', i.status, 'pay_token', i.pay_token,
            'reported', exists (select 1 from console.payments p where p.invoice_id = i.id and p.status = 'reported')) order by i.issue_date desc, i.number desc)
          from console.invoices i where i.customer_id = cid and i.status in ('issued','paid','cancelled')), '[]');
end $$;
revoke all on function public.kmr_portal_invoices(text) from public, anon;
grant execute on function public.kmr_portal_invoices(text) to authenticated;
