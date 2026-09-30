-- =====================================================================
-- KMR Console — seller identity on invoices. Needs 0019. Safe to re-run.
--  • Seller details: trade name (the name invoices lead with) and legal name, constitution, Udyam (MSME)
--    number and category, website, authorised signatory, and the company seal + signature images.
--  • Seal and signature files live in a PRIVATE storage bucket (kmr-billing); invoices show them through
--    short-lived links only.
--  • MSME note on invoices (MSMED Act, 2006 — payment within the agreed period, at most 45 days), switchable.
--  • Issued invoices now freeze the complete seller details, so every field added here reaches them.
-- =====================================================================
do $$ begin
  if to_regprocedure('console.report_payment(text, text, text, date, numeric, text)') is null then raise exception 'Run 0019_bank_payments.sql first.'; end if;
end $$;

alter table console.billing_settings
  add column if not exists trade_name      text,
  add column if not exists constitution    text,
  add column if not exists udyam_no        text check (udyam_no is null or udyam_no ~ '^UDYAM-[A-Z]{2}-[0-9]{2}-[0-9]{7}$'),
  add column if not exists msme_category   text check (msme_category is null or msme_category in ('Micro','Small','Medium')),
  add column if not exists website         text,
  add column if not exists signatory_name  text,
  add column if not exists signatory_title text,
  add column if not exists seal_path       text,
  add column if not exists signature_path  text,
  add column if not exists show_seal       boolean not null default true,
  add column if not exists show_msme_note  boolean not null default true;

-- Private files: seal and signature (uploaded by the Console server after checking the staff member)
insert into storage.buckets (id, name, public, file_size_limit) values ('kmr-billing', 'kmr-billing', false, 2097152) on conflict (id) do nothing;

-- Everything an invoice needs to show about the seller, frozen when it is issued
create or replace function console.seller_snapshot() returns jsonb
language sql stable security definer set search_path = console, public as $$
  select (to_jsonb(s) - 'id' - 'updated_at' - 'invoice_prefix' - 'payment_days' - 'gst_rate')
         || jsonb_build_object('state_code', coalesce(s.state_code, left(s.gstin, 2)))
    from console.billing_settings s where s.id
$$;
revoke all on function console.seller_snapshot() from public, anon, authenticated;

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
    seller = console.seller_snapshot(),
    buyer = jsonb_build_object('code', c.code, 'name', coalesce(nullif(c.legal_name, ''), c.name), 'tax_id', c.tax_id, 'address', c.address, 'city', c.city,
      'state', c.state, 'postal_code', c.postal_code, 'country', c.country, 'contact_name', c.contact_name, 'contact_email', c.contact_email),
    updated_at = now()
   where id = p_invoice;
  return num;
end $$;
