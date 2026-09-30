-- Tests for 0022 (hardening). Run inside a transaction that is rolled back.
\set ON_ERROR_STOP 1
set client_min_messages = warning;
create or replace function pg_temp.ok(cond boolean, what text) returns void language plpgsql as $$
begin if not coalesce(cond, false) then raise exception 'FAIL: %', what; end if; raise warning 'PASS: %', what; end $$;
create or replace function pg_temp.fails(q text, what text) returns void language plpgsql as $$
begin begin execute q; exception when others then raise warning 'PASS: % (%)', what, sqlerrm; return; end; raise exception 'FAIL: % — it was allowed', what; end $$;

-- rate limits
select pg_temp.ok(public.kmr_rate_ok('t:login:a@b.c', 3, 60) and public.kmr_rate_ok('t:login:a@b.c', 3, 60) and public.kmr_rate_ok('t:login:a@b.c', 3, 60), 'three tries allowed');
select pg_temp.ok(not public.kmr_rate_ok('t:login:a@b.c', 3, 60), 'fourth try in the window is blocked');
select pg_temp.ok((select blocked = 1 from console.rate_blocks where key = 't:login:a@b.c'), 'block is recorded');
select pg_temp.ok(public.kmr_rate_ok('t:login:other@b.c', 3, 60), 'another key is independent');
update console.rate_hits set at = now() - interval '2 minutes' where key = 't:login:a@b.c';
select pg_temp.ok(public.kmr_rate_ok('t:login:a@b.c', 3, 60), 'allowed again after the window');
set role anon;
select pg_temp.fails($$select public.kmr_rate_ok('x', 1, 60)$$, 'the public cannot call the rate limiter');
reset role;

-- activity log
select set_config('request.jwt.claims', '{"email":"owner@kmr.test","role":"authenticated"}', true);
update console.prices set unit_amount = unit_amount + 1 where id = (select id from console.prices limit 1);
select pg_temp.ok((select actor = 'owner@kmr.test' and tbl = 'console.prices' and action = 'update' and changes ? 'unit_amount'
                     from console.audit_log order by id desc limit 1), 'price change logged with who and what');
update console.prices set updated_at = now() where id = (select id from console.prices limit 1);
select pg_temp.ok((select tbl <> 'console.prices' or changes ? 'unit_amount' from console.audit_log order by id desc limit 1), 'a touch with no real change is not logged');
insert into public.legal_pages (slug, title, content) values ('audit-test', 'Audit test', 'x');
select pg_temp.ok((select action = 'insert' and tbl = 'public.legal_pages' from console.audit_log order by id desc limit 1), 'website content insert logged');
delete from public.legal_pages where slug = 'audit-test';
select pg_temp.ok((select action = 'delete' from console.audit_log order by id desc limit 1), 'delete logged');

-- error log
select pg_temp.ok(public.kmr_log_error('website', '/shop', 'Boom', 'd1', 'stack'), 'first error → alert');
select pg_temp.ok(not public.kmr_log_error('website', '/shop', 'Boom', 'd1', 'stack'), 'same error within the hour → no second alert');
select pg_temp.ok((select count = 2 from console.app_errors where message = 'Boom'), 'repeat is counted');
select pg_temp.ok(public.kmr_log_error('console', '/cms', 'Other', null, null), 'a different error → alert');

-- backups
select pg_temp.ok((select (console.console_export() -> 'tables') ?& array['console.customers','console.customer_members','public.orders','public.company_info','public.job_applications']), 'console backup covers customer users and website data');
select pg_temp.ok((select (console.apps_export() -> 'tables') ? 'console.ops_records'), 'apps backup covers the Operations Master');
select pg_temp.ok((select console.console_export() ->> 'version' = '2'), 'backup format version 2');
