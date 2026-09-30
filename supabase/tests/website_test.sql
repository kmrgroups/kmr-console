-- Tests for 0021 (Console manages the website). Run inside a transaction that is rolled back.
\set ON_ERROR_STOP 1
set client_min_messages = warning;
create or replace function pg_temp.as_user(uid uuid, em text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claims', json_build_object('sub', uid, 'email', em, 'role', 'authenticated')::text, false); end $$;
create or replace function pg_temp.ok(cond boolean, what text) returns void language plpgsql as $$
begin if not coalesce(cond, false) then raise exception 'FAIL: %', what; end if; raise warning 'PASS: %', what; end $$;
create or replace function pg_temp.fails(q text, what text) returns void language plpgsql as $$
begin begin execute q; exception when others then raise warning 'PASS: % (%)', what, sqlerrm; return; end; raise exception 'FAIL: % — it was allowed', what; end $$;

-- staff
insert into auth.users (id, email) values ('00000000-0000-0000-0000-00000000aa01', 'owner21@kmr.test'), ('00000000-0000-0000-0000-00000000aa02', 'support21@kmr.test'), ('00000000-0000-0000-0000-00000000aa03', 'sales21@kmr.test');
insert into console.staff (user_id, full_name, email, role) values ('00000000-0000-0000-0000-00000000aa01', 'Owner', 'owner21@kmr.test', 'owner'),
  ('00000000-0000-0000-0000-00000000aa02', 'Support', 'support21@kmr.test', 'support'), ('00000000-0000-0000-0000-00000000aa03', 'Sales', 'sales21@kmr.test', 'sales');
insert into console.prices (product_code, period, currency, unit_amount, min_seats) values ('hrm', 'month', 'INR', 60, 25) on conflict (product_code, period, currency) do update set unit_amount = 60;

select pg_temp.ok((select jsonb_array_length(public.kmr_software_catalog()) >= 4), 'software catalogue lists the Console products');
select pg_temp.ok((select e -> 'prices' -> 0 ->> 'amount' = '60.00' from jsonb_array_elements(public.kmr_software_catalog()) e where e ->> 'code' = 'hrm'), 'with their INR prices');
set role anon;
select pg_temp.ok(jsonb_typeof(public.kmr_software_catalog()) = 'array', 'the website (anonymous) can read the software catalogue');
reset role;

select pg_temp.ok(to_regprocedure('console.publish_ops_products(uuid,text[],text)') is null, 'customer Operations Master data cannot be copied to the website (no publish function)');
insert into products (name, sku, price, stock_quantity, is_active, business, kind) values ('Test Flange', 'TF-1', 999, 7, true, 'shop', 'goods'), ('Hidden Hub', 'TF-2', 500, 3, false, 'shop', 'goods');

-- shop orders: Console owner / admin / sales may manage, support may not
set role service_role;
create temp table t21 (token text, id uuid); grant all on t21 to authenticated, service_role;
insert into t21 select shop_place_order((select id from products where sku = 'TF-1'), 2, 'Priya', '', '9876501234', 'No 9, Nehru Street, Salem 636001') ->> 'token';
select pg_temp.fails($$select shop_place_order((select id from products where sku = 'TF-2'), 1, 'Priya', '', '9876501234', 'No 9, Nehru Street, Salem 636001')$$, 'hidden product cannot be ordered');
select shop_report_payment((select token from t21), 'upi', 'UPI55512345', current_date, 1998);
reset role;
update t21 set id = (select id from orders where order_token = t21.token);
set role authenticated; select pg_temp.as_user('00000000-0000-0000-0000-00000000aa02', 'support21@kmr.test');
select pg_temp.fails($$select shop_confirm_payment((select id from t21))$$, 'Console support staff cannot confirm payments');
select pg_temp.as_user('00000000-0000-0000-0000-00000000aa03', 'sales21@kmr.test');
select pg_temp.ok(shop_confirm_payment((select id from t21)) = 'paid', 'Console sales staff confirms the payment');
reset role;
select pg_temp.ok((select stock_quantity = 5 from products where sku = 'TF-1'), 'stock 7 → 5');

-- a course: no stock needed; enquiry-only items cannot be ordered
insert into products (name, price, stock_quantity, is_active, business, kind) values ('IATF 16949 Internal Auditor (2 days)', 6500, 0, true, 'training', 'course');
insert into products (name, price, stock_quantity, is_active, business, kind, enquiry_only) values ('EN8 bright bar (per tonne)', 68000, 0, true, 'trading', 'goods', true);
set role service_role;
select pg_temp.ok((shop_place_order((select id from products where name = 'IATF 16949 Internal Auditor (2 days)'), 1, 'Kavya', '', '9876543000', 'Hosur Road, Bengaluru 560100') ->> 'order_no') like 'KMR-SO-%', 'a course can be ordered without stock');
select pg_temp.fails($$select shop_place_order((select id from products where name = 'EN8 bright bar (per tonne)'), 1, 'Kavya', '', '9876543000', 'Hosur Road, Bengaluru 560100')$$, 'enquiry-only item cannot be ordered');
reset role;

-- enquiries go to the Console inbox
insert into console.leads (name, email, business, product_name, quantity, message) values ('Mohan', 'mohan@x.test', 'import_export', 'EN8 bright bar', '5 tonnes', 'CIF Dubai');
select pg_temp.ok((select company is null and business = 'import_export' and status = 'new' from console.leads where email = 'mohan@x.test'), 'trade enquiry without a company is accepted');
select pg_temp.fails($$insert into console.leads (name, email, business) values ('X Y', 'a@b.test', 'crypto')$$, 'unknown business refused');
