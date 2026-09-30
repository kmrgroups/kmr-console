-- Tests for 0018 + 0019 (prices, invoices, bank payments). Run as postgres inside a transaction that is rolled back.
\set ON_ERROR_STOP 1
set client_min_messages = warning;
create or replace function pg_temp.as_user(uid uuid, em text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claims', json_build_object('sub', uid, 'email', em)::text, false); end $$;
create or replace function pg_temp.ok(cond boolean, what text) returns void language plpgsql as $$
begin if not coalesce(cond, false) then raise exception 'FAIL: %', what; end if; raise warning 'PASS: %', what; end $$;
create or replace function pg_temp.fails(q text, what text) returns void language plpgsql as $$
begin begin execute q; exception when others then raise warning 'PASS: % (%)', what, sqlerrm; return; end; raise exception 'FAIL: % — it was allowed', what; end $$;

-- staff: an owner and a sales person
insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000a1', 'owner@kmr.test'), ('00000000-0000-0000-0000-0000000000a2', 'sales@kmr.test');
insert into console.staff (user_id, full_name, email, role) values ('00000000-0000-0000-0000-0000000000a1', 'Owner', 'owner@kmr.test', 'owner'),
                                                                  ('00000000-0000-0000-0000-0000000000a2', 'Sales', 'sales@kmr.test', 'sales');
-- customers: same state (Karnataka GSTIN 29…), other state (Tamil Nadu 33…), abroad (USD)
insert into console.customers (id, name, country, currency, tax_id, state, status, contact_email) values
  ('00000000-0000-0000-0000-00000000b001', 'Bengaluru Gears', 'IN', 'INR', '29AABCB1234C1Z5', 'Karnataka', 'pilot', 'admin@bg.test'),
  ('00000000-0000-0000-0000-00000000b002', 'Chennai Forge',   'IN', 'INR', '33AABCC1234C1Z5', 'Tamil Nadu', 'lead', null),
  ('00000000-0000-0000-0000-00000000b003', 'Ohio Machining',  'US', 'USD', null, 'Ohio', 'lead', null);
insert into console.licences (customer_id, product_code, status, valid_until, seats) values
  ('00000000-0000-0000-0000-00000000b001', 'hrm', 'trial', current_date + 10, 50),
  ('00000000-0000-0000-0000-00000000b001', 'balloon', 'pilot', current_date + 5, 5);

set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-0000000000a2', 'sales@kmr.test');
select pg_temp.ok((select count(*) from console.billing_settings) = 1, 'sales can read seller details');
select pg_temp.fails($$insert into console.prices (product_code, period, currency, unit_amount) values ('hrm','month','INR',1)$$, 'sales cannot set prices');
select pg_temp.fails($$select console.create_invoice('00000000-0000-0000-0000-00000000b001', 'month', current_date, '[{"product_code":"hrm","seats":40}]')$$, 'sales cannot create invoices');
select pg_temp.fails($$insert into console.invoices (customer_id, currency) values ('00000000-0000-0000-0000-00000000b001', 'INR')$$, 'nobody writes invoices directly');

select pg_temp.as_user('00000000-0000-0000-0000-0000000000a1', 'owner@kmr.test');
update console.billing_settings set gstin = '29AAACK1234K1Z5', state = 'Karnataka', state_code = '29', address = 'Shanthipura, Electronic City', city = 'Bengaluru' where id;
insert into console.prices (product_code, period, currency, unit_amount, min_seats) values
  ('hrm', 'month', 'INR', 60, 25), ('hrm', 'year', 'INR', 600, 25), ('balloon', 'month', 'INR', 999, 1), ('hrm', 'month', 'USD', 1.5, 25);
select pg_temp.fails($$select console.issue_invoice(console.create_invoice('00000000-0000-0000-0000-00000000b002', 'month', current_date, '[{"product_code":"hrm","seats":1}]'))$$, 'cannot issue without a bank account or UPI ID');
update console.billing_settings set bank_account_name = 'KMR GROUP OF COMPANIES', bank_account_no = '12345678901234', bank_ifsc = 'FDRL0001234', bank_name = 'Federal Bank', bank_branch = 'Test branch', bank_swift = 'FDRLINBBIBD' where id;
update console.billing_settings set trade_name = 'Test Traders', legal_name = 'A Person', constitution = 'Proprietorship', udyam_no = 'UDYAM-KA-03-0000001', msme_category = 'Micro',
  signatory_name = 'A Person', signatory_title = 'Proprietor', seal_path = 'seal/x.png', signature_path = 'signature/x.png' where id;
select pg_temp.fails($$update console.billing_settings set udyam_no = 'UDYAM-123' where id$$, 'malformed Udyam number refused');
select pg_temp.fails($$select console.create_invoice('00000000-0000-0000-0000-00000000b001', 'year', current_date, '[{"product_code":"balloon","seats":2}]')$$, 'no yearly Balloon price → clear error');

-- same state: CGST + SGST; minimum seats applied
create temp table t_inv (k text primary key, id uuid);
grant all on t_inv to authenticated, service_role;
insert into t_inv values ('ka', console.create_invoice('00000000-0000-0000-0000-00000000b001', 'month', current_date, '[{"product_code":"hrm","seats":40},{"product_code":"balloon","seats":3}]'));
select pg_temp.ok((select subtotal = 40*60 + 3*999 and tax_type = 'cgst_sgst' and cgst = 485.73 and sgst = 485.73 and igst = 0 and total = 5397 + 971.46
                     from console.invoices where id = (select id from t_inv where k = 'ka')), 'Karnataka customer: 5,397 + CGST 485.73 + SGST 485.73 = 6,368.46');
insert into t_inv values ('tn', console.create_invoice('00000000-0000-0000-0000-00000000b002', 'year', current_date, '[{"product_code":"hrm","seats":10}]'));
select pg_temp.ok((select subtotal = 25*600 and tax_type = 'igst' and igst = 2700 and total = 17700 from console.invoices where id = (select id from t_inv where k = 'tn')),
                  'Tamil Nadu customer, 10 employees → minimum 25 billed, IGST 18% = 17,700');
select pg_temp.ok((select period_to = (current_date + interval '1 year' - interval '1 day')::date from console.invoice_lines where invoice_id = (select id from t_inv where k = 'tn')),
                  'yearly line covers one year');
insert into t_inv values ('us', console.create_invoice('00000000-0000-0000-0000-00000000b003', 'month', current_date, '[{"product_code":"hrm","seats":30}]'));
select pg_temp.ok((select currency = 'USD' and tax_type = 'export' and total = 45 from console.invoices where id = (select id from t_inv where k = 'us')), 'US customer: USD, export, no GST (45.00)');

-- extra line on a draft, then remove it
select console.add_invoice_line((select id from t_inv where k = 'tn'), 'Onboarding and training (one day)', 1, 5000);
select pg_temp.ok((select total = round((15000 + 5000) * 1.18, 2) from console.invoices where id = (select id from t_inv where k = 'tn')), 'extra line added and taxed');
select console.remove_invoice_line((select id from t_inv where k = 'tn'), (select id from console.invoice_lines where invoice_id = (select id from t_inv where k = 'tn') and product_code is null));
select pg_temp.ok((select total = 17700 from console.invoices where id = (select id from t_inv where k = 'tn')), 'extra line removed');

-- issue: gapless numbering, frozen details, no more changes
select pg_temp.ok(console.issue_invoice((select id from t_inv where k = 'ka')) = 'KMR/' || console.fin_year(current_date) || '/0001', 'first issued invoice is KMR/<FY>/0001');
select pg_temp.ok(console.issue_invoice((select id from t_inv where k = 'tn')) = 'KMR/' || console.fin_year(current_date) || '/0002', 'second is /0002');
select pg_temp.ok((select seller ->> 'trade_name' = 'Test Traders' and seller ->> 'legal_name' = 'A Person' and seller ->> 'udyam_no' = 'UDYAM-KA-03-0000001'
                     and seller ->> 'signature_path' = 'signature/x.png' and seller ->> 'state_code' = '29' and not seller ? 'invoice_prefix'
                     from console.invoices where id = (select id from t_inv where k = 'tn')), 'trade name, legal name, Udyam and signature frozen on the invoice');
select pg_temp.ok((select seller ->> 'gstin' = '29AAACK1234K1Z5' and buyer ->> 'tax_id' = '33AABCC1234C1Z5' and due_date = current_date + 15
                     from console.invoices where id = (select id from t_inv where k = 'tn')), 'seller and buyer frozen on the invoice; due in 15 days');
select pg_temp.fails($$select console.add_invoice_line((select id from t_inv where k = 'ka'), 'x', 1, 1)$$, 'issued invoice cannot be changed');
select pg_temp.fails($$select console.discard_invoice((select id from t_inv where k = 'ka'))$$, 'issued invoice cannot be discarded');
select pg_temp.ok(console.fin_year('2027-03-31') = '26-27' and console.fin_year('2027-04-01') = '27-28', 'financial year runs April to March');

-- cancel the Tamil Nadu one; the next number continues the series
select console.cancel_invoice((select id from t_inv where k = 'tn'), 'Customer changed plan');
select pg_temp.ok(console.issue_invoice((select id from t_inv where k = 'us')) like '%/0003', 'numbering continues after a cancellation (/0003)');
select pg_temp.fails($$select console.mark_invoice_paid((select id from t_inv where k = 'tn'), 'UTR123')$$, 'cancelled invoice cannot be paid');

-- manual payment renews the licences
select console.mark_invoice_paid((select id from t_inv where k = 'ka'), 'UTR 4455667788');
select pg_temp.ok((select status = 'paid' from console.invoices where id = (select id from t_inv where k = 'ka')), 'marked paid');
select pg_temp.ok((select status = 'active' and seats = 40 and valid_until = (current_date + interval '1 month' - interval '1 day')::date
                     from console.licences where customer_id = '00000000-0000-0000-0000-00000000b001' and product_code = 'hrm'), 'HRM licence: active, 40 employees, until end of paid month');
select pg_temp.ok((select status = 'active' and seats = 3 from console.licences where customer_id = '00000000-0000-0000-0000-00000000b001' and product_code = 'balloon'), 'Balloon licence: active, 3 users');
select pg_temp.ok((select status = 'active' from console.customers where id = '00000000-0000-0000-0000-00000000b001'), 'customer became active');
select pg_temp.fails($$select console.mark_invoice_paid((select id from t_inv where k = 'ka'), 'again')$$, 'cannot be paid twice');

-- the pay-link functions are for the server only
select pg_temp.fails($$select console.invoice_for_token((select pay_token from console.invoices where id = (select id from t_inv where k = 'us')))$$, 'staff cannot call the pay-link functions directly');

-- bank payment reported by the customer on the pay link (the Console server, service role)
reset role; set role service_role;
select pg_temp.ok((console.invoice_for_token((select pay_token from console.invoices where id = (select id from t_inv where k = 'us'))) -> 'invoice' -> 'seller' ->> 'bank_account_no') = '12345678901234', 'bank account frozen on the issued invoice');
select pg_temp.ok(console.invoice_for_token('not-a-real-token-at-all-000000') is null, 'unknown token finds nothing');
select pg_temp.fails($$select console.report_payment((select pay_token from console.invoices where id = (select id from t_inv where k = 'us')), 'neft', 'X', current_date, 45)$$, 'too-short reference refused');
select pg_temp.fails($$select console.report_payment((select pay_token from console.invoices where id = (select id from t_inv where k = 'us')), 'neft', 'FDRLN26273001', current_date + 30, 45)$$, 'future date refused');
select pg_temp.fails($$select console.report_payment((select pay_token from console.invoices where id = (select id from t_inv where k = 'tn')), 'neft', 'FDRLN26273001', current_date, 45)$$, 'cannot report on a cancelled invoice');
select pg_temp.ok(console.report_payment((select pay_token from console.invoices where id = (select id from t_inv where k = 'us')), 'neft', 'fdrln 26273001', current_date, 45, 'Mike') = 'ok', 'customer reports an NEFT payment');
select pg_temp.fails($$select console.report_payment((select pay_token from console.invoices where id = (select id from t_inv where k = 'us')), 'imps', 'FDRLN 26273001', current_date, 45)$$, 'same reference cannot be reported twice');
select console.report_payment((select pay_token from console.invoices where id = (select id from t_inv where k = 'us')), 'upi', '627312345678', current_date, 45);
select pg_temp.ok((select count(*) = 2 and bool_and(status = 'reported') from console.payments where invoice_id = (select id from t_inv where k = 'us')), 'two reports waiting; invoice still issued');
select pg_temp.ok((select status = 'issued' from console.invoices where id = (select id from t_inv where k = 'us')), 'a report alone does not mark it paid');
select pg_temp.ok(jsonb_array_length(console.invoice_for_token((select pay_token from console.invoices where id = (select id from t_inv where k = 'us'))) -> 'reported') = 2, 'pay link shows the reports');
reset role;

-- KMR checks the bank: reject one, confirm the other
set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-0000000000a2', 'sales@kmr.test');
select pg_temp.fails($$select console.confirm_payment((select id from console.payments where reference = 'FDRLN 26273001'))$$, 'sales cannot confirm payments');
select pg_temp.fails($$select console.report_payment('x', 'neft', 'ABCDEF', current_date, 1)$$, 'staff cannot call report_payment directly');
select pg_temp.as_user('00000000-0000-0000-0000-0000000000a1', 'owner@kmr.test');
select pg_temp.fails($$select console.reject_payment((select id from console.payments where reference = '627312345678'), '')$$, 'rejecting needs a reason');
select console.reject_payment((select id from console.payments where reference = '627312345678'), 'Not received in the bank');
select console.confirm_payment((select id from console.payments where reference = 'FDRLN 26273001'));
select pg_temp.ok((select status = 'paid' and paid_at::date = current_date from console.invoices where id = (select id from t_inv where k = 'us')), 'confirmed → invoice paid');
select pg_temp.ok((select status = 'active' and seats = 30 from console.licences where customer_id = '00000000-0000-0000-0000-00000000b003' and product_code = 'hrm') is not false, 'licence renewed (when the customer has one)');
select pg_temp.fails($$select console.confirm_payment((select id from console.payments where reference = 'FDRLN 26273001'))$$, 'cannot confirm twice');
select pg_temp.ok((select reject_reason = 'Not received in the bank' from console.payments where reference = '627312345678'), 'rejected report keeps its reason');
reset role; set role service_role;
select pg_temp.fails($$select console.report_payment((select pay_token from console.invoices where id = (select id from t_inv where k = 'us')), 'neft', 'NEWREF1234', current_date, 45)$$, 'nothing can be reported on a paid invoice');
reset role;

-- customer portal: administrators of the company only
set role authenticated;
update console.customers set slug = 'bg' where id = '00000000-0000-0000-0000-00000000b001';
select pg_temp.as_user(gen_random_uuid(), 'admin@bg.test');
select pg_temp.ok(jsonb_array_length(public.kmr_portal_invoices('bg')) = 1, 'customer''s contact sees their 1 invoice in the portal');
select pg_temp.as_user(gen_random_uuid(), 'someone@else.test');
select pg_temp.fails($$select public.kmr_portal_invoices('bg')$$, 'others cannot see a company''s invoices');
reset role;
select pg_temp.ok((console.console_export() -> 'tables' ? 'invoices') and (console.console_export() -> 'tables' ? 'payments'), 'backups include invoices and payments');
