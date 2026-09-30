-- Tests for 0021 (Console manages the website). Run inside a transaction that is rolled back.
\set ON_ERROR_STOP 1
set client_min_messages = warning;
create or replace function pg_temp.as_user(uid uuid, em text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claims', json_build_object('sub', uid, 'email', em, 'role', 'authenticated')::text, false); end $$;
create or replace function pg_temp.ok(cond boolean, what text) returns void language plpgsql as $$
begin if not coalesce(cond, false) then raise exception 'FAIL: %', what; end if; raise warning 'PASS: %', what; end $$;
create or replace function pg_temp.fails(q text, what text) returns void language plpgsql as $$
begin begin execute q; exception when others then raise warning 'PASS: % (%)', what, sqlerrm; return; end; raise exception 'FAIL: % — it was allowed', what; end $$;

-- staff and a company with the sample Operations Master
insert into auth.users (id, email) values ('00000000-0000-0000-0000-00000000aa01', 'owner21@kmr.test'), ('00000000-0000-0000-0000-00000000aa02', 'support21@kmr.test'), ('00000000-0000-0000-0000-00000000aa03', 'sales21@kmr.test');
insert into console.staff (user_id, full_name, email, role) values ('00000000-0000-0000-0000-00000000aa01', 'Owner', 'owner21@kmr.test', 'owner'),
  ('00000000-0000-0000-0000-00000000aa02', 'Support', 'support21@kmr.test', 'support'), ('00000000-0000-0000-0000-00000000aa03', 'Sales', 'sales21@kmr.test', 'sales');
insert into console.customers (id, name, status) values ('00000000-0000-0000-0000-00000000cc21', 'KMR Own Plant', 'active');
insert into console.ops_records (customer_id, kind, code, name, data)
select '00000000-0000-0000-0000-00000000cc21', e ->> 'kind', e ->> 'code', e ->> 'name', console.ops_sample_dates(e -> 'data') from jsonb_array_elements(console.ops_sample()) e;
insert into console.prices (product_code, period, currency, unit_amount, min_seats) values ('hrm', 'month', 'INR', 60, 25) on conflict (product_code, period, currency) do update set unit_amount = 60;

select pg_temp.ok((select jsonb_array_length(public.kmr_software_catalog()) >= 4), 'software catalogue lists the Console products');
select pg_temp.ok((select e -> 'prices' -> 0 ->> 'amount' = '60.00' from jsonb_array_elements(public.kmr_software_catalog()) e where e ->> 'code' = 'hrm'), 'with their INR prices');
set role anon;
select pg_temp.ok(jsonb_typeof(public.kmr_software_catalog()) = 'array', 'the website (anonymous) can read the software catalogue');
reset role;

set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-00000000aa02', 'support21@kmr.test');
select pg_temp.fails($$select console.publish_ops_products('00000000-0000-0000-0000-00000000cc21', array['DP-1101'])$$, 'support staff cannot publish');
select pg_temp.as_user('00000000-0000-0000-0000-00000000aa01', 'owner21@kmr.test');
select pg_temp.fails($$select console.publish_ops_products('00000000-0000-0000-0000-00000000cc21', array[]::text[])$$, 'nothing ticked → clear error');
select pg_temp.ok(console.publish_ops_products('00000000-0000-0000-0000-00000000cc21', array['DP-1101','DP-1102','DP-1106']) = '{"added": 3, "refreshed": 0}', 'owner publishes 3 parts');
reset role;
select pg_temp.ok((select price = 412 and not is_active and sku = 'DP-1101' and business = 'shop' and description like 'Part no. DP-1101 · Drawing DRG-1101-A rev C · Material EN8 bright bar Ø65 · 1.8 kg'
                     from products where ops_code = 'DP-1101' and ops_customer_id = '00000000-0000-0000-0000-00000000cc21'), 'price from the customer rate contract, material name, hidden until reviewed');
select pg_temp.ok((select price = 0 from products where ops_code = 'DP-1106'), 'no rate contract → price 0 for KMR to fill in');
update products set price = 999, stock_quantity = 7, is_active = true where ops_code = 'DP-1101';
update console.ops_records set name = 'Drive Flange (new rev)' where customer_id = '00000000-0000-0000-0000-00000000cc21' and kind = 'parts' and code = 'DP-1101';
set role authenticated; select pg_temp.as_user('00000000-0000-0000-0000-00000000aa01', 'owner21@kmr.test');
select pg_temp.ok(console.publish_ops_products('00000000-0000-0000-0000-00000000cc21', array['DP-1101'], 'trading') = '{"added": 0, "refreshed": 1}', 're-publishing refreshes');
reset role;
select pg_temp.ok((select name = 'Drive Flange (new rev)' and price = 999 and stock_quantity = 7 and is_active and business = 'shop' from products where ops_code = 'DP-1101'), 'refresh keeps KMR''s price, stock, visibility and business');

-- shop orders: Console owner / admin / sales may manage, support may not
set role service_role;
create temp table t21 (token text, id uuid); grant all on t21 to authenticated, service_role;
insert into t21 select shop_place_order((select id from products where ops_code = 'DP-1101'), 2, 'Priya', '', '9876501234', 'No 9, Nehru Street, Salem 636001') ->> 'token';
select pg_temp.fails($$select shop_place_order((select id from products where ops_code = 'DP-1102'), 1, 'Priya', '', '9876501234', 'No 9, Nehru Street, Salem 636001')$$, 'hidden product cannot be ordered');
select shop_report_payment((select token from t21), 'upi', 'UPI55512345', current_date, 1998);
reset role;
update t21 set id = (select id from orders where order_token = t21.token);
set role authenticated; select pg_temp.as_user('00000000-0000-0000-0000-00000000aa02', 'support21@kmr.test');
select pg_temp.fails($$select shop_confirm_payment((select id from t21))$$, 'Console support staff cannot confirm payments');
select pg_temp.as_user('00000000-0000-0000-0000-00000000aa03', 'sales21@kmr.test');
select pg_temp.ok(shop_confirm_payment((select id from t21)) = 'paid', 'Console sales staff confirms the payment');
reset role;
select pg_temp.ok((select stock_quantity = 5 from products where ops_code = 'DP-1101'), 'stock 7 → 5');

-- a course: no stock needed; enquiry-only items cannot be ordered
insert into products (name, price, stock_quantity, is_active, business, kind) values ('IATF 16949 Internal Auditor (2 days)', 6500, 0, true, 'training', 'course');
insert into products (name, price, stock_quantity, is_active, business, kind, enquiry_only) values ('EN8 bright bar (per tonne)', 68000, 0, true, 'trading', 'goods', true);
set role service_role;
select pg_temp.ok((shop_place_order((select id from products where name like 'IATF 16949%'), 1, 'Kavya', '', '9876543000', 'Hosur Road, Bengaluru 560100') ->> 'order_no') like 'KMR-SO-%', 'a course can be ordered without stock');
select pg_temp.fails($$select shop_place_order((select id from products where name like 'EN8 bright bar%'), 1, 'Kavya', '', '9876543000', 'Hosur Road, Bengaluru 560100')$$, 'enquiry-only item cannot be ordered');
reset role;

-- enquiries go to the Console inbox
insert into console.leads (name, email, business, product_name, quantity, message) values ('Mohan', 'mohan@x.test', 'import_export', 'EN8 bright bar', '5 tonnes', 'CIF Dubai');
select pg_temp.ok((select company is null and business = 'import_export' and status = 'new' from console.leads where email = 'mohan@x.test'), 'trade enquiry without a company is accepted');
select pg_temp.fails($$insert into console.leads (name, email, business) values ('X Y', 'a@b.test', 'crypto')$$, 'unknown business refused');
