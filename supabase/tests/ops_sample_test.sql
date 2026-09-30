-- Tests for 0017 (Operations Master sample data). Run as postgres; switches to the "authenticated" role per check.
\set ON_ERROR_STOP 1
set client_min_messages = warning;
create or replace function pg_temp.as_user(em text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claims', json_build_object('email', em, 'sub', gen_random_uuid())::text, false); end $$;
create or replace function pg_temp.ok(cond boolean, what text) returns void language plpgsql as $$
begin if not cond then raise exception 'FAIL: %', what; end if; raise warning 'PASS: %', what; end $$;
create or replace function pg_temp.fails(q text, what text) returns void language plpgsql as $$
begin begin execute q; exception when others then raise warning 'PASS: % (%)', what, sqlerrm; return; end; raise exception 'FAIL: % — it was allowed', what; end $$;

-- two companies, each with an admin; company A also has an editor and a viewer
insert into console.customers (name, slug, status) values ('Test Plant A', 'test-a', 'active'), ('Test Plant B', 'test-b', 'active');
insert into console.customer_members (customer_id, email, is_admin, roles)
select id, 'admin@a.test', true, '{}'::jsonb from console.customers where slug = 'test-a' union all
select id, 'editor@a.test', false, '{"ops":"editor"}' from console.customers where slug = 'test-a' union all
select id, 'viewer@a.test', false, '{"ops":"viewer"}' from console.customers where slug = 'test-a' union all
select id, 'admin@b.test', true, '{}' from console.customers where slug = 'test-b';
-- company A already has real data: machine CNC-T01 (same code as the sample) and its own plant standards
insert into console.ops_records (customer_id, kind, code, name, data)
select id, 'machines', 'CNC-T01', 'OUR REAL LATHE', '{"cell":"Real cell"}'::jsonb from console.customers where slug = 'test-a' union all
select id, 'plant_standards', 'MAIN', 'Our plant', '{"oee":85,"hoursPerDay":16,"weeklyOff":"Saturday & Sunday"}' from console.customers where slug = 'test-a' union all
select id, 'suppliers', 'OWN-SUP', 'Our own supplier', '{}' from console.customers where slug = 'test-a';
-- a Capacity Planner workspace for company A with a licence
insert into public.cp_orgs (id, name) values ('00000000-0000-0000-0000-00000000c0a1', 'Planner A');
insert into public.cp_members (org_id, email, role) values ('00000000-0000-0000-0000-00000000c0a1', 'admin@a.test', 'admin');
-- (creating the workspace starts a trial licence; attach it to company A and make it active)
update console.licences set customer_id = (select id from console.customers where slug = 'test-a'), status = 'active', valid_until = current_date + 365
 where product_code = 'capacity' and product_ref = '00000000-0000-0000-0000-00000000c0a1';

select pg_temp.ok(jsonb_array_length(console.ops_sample()) = 163, 'sample has 163 records');
select pg_temp.ok((select count(distinct e ->> 'kind') from jsonb_array_elements(console.ops_sample()) e) = 13, 'sample covers all 13 lists');

set role authenticated;
select pg_temp.as_user('viewer@a.test'); select pg_temp.fails($$select public.kmr_ops_sample_load('test-a')$$, 'viewer cannot load');
select pg_temp.as_user('editor@a.test'); select pg_temp.fails($$select public.kmr_ops_sample_load('test-a')$$, 'editor cannot load');
select pg_temp.as_user('editor@a.test'); select pg_temp.fails($$select public.kmr_ops_sample_flush('test-a')$$, 'editor cannot flush');
select pg_temp.as_user('admin@b.test');  select pg_temp.fails($$select public.kmr_ops_sample_load('test-a')$$, 'another company''s admin cannot load');
select pg_temp.as_user('nobody@x.test'); select pg_temp.fails($$select public.kmr_ops_sample_load('test-a')$$, 'stranger cannot load');

select pg_temp.as_user('admin@a.test');
select pg_temp.ok((select public.kmr_ops_sample_load('test-a')) = '{"added": 161, "skipped": 2}', 'admin loads: 161 added, 2 skipped (existing CNC-T01 + own plant standards)');
select pg_temp.ok((select public.kmr_ops_sample_load('test-a')) = '{"added": 0, "skipped": 163}', 'loading again adds nothing');
select pg_temp.ok((public.kmr_ops_counts('test-a') ->> '_sample')::int = 161, 'counts report 161 sample records');
select pg_temp.ok((public.kmr_ops_counts('test-a') ->> 'cycle_times')::int = 43 and (public.kmr_ops_counts('test-a') ->> 'machines')::int = 12
                  and (public.kmr_ops_counts('test-a') ->> 'suppliers')::int = 9, 'counts: 43 cycle times, 12 machines, 8+1 suppliers');
select pg_temp.ok((select e ->> 'name' from jsonb_array_elements(public.kmr_ops_list('test-a', 'machines')) e where e ->> 'code' = 'CNC-T01') = 'OUR REAL LATHE'
                  and (select (e ->> 'sample')::boolean from jsonb_array_elements(public.kmr_ops_list('test-a', 'machines')) e where e ->> 'code' = 'CNC-T01') = false,
                  'the real CNC-T01 was not overwritten and is not tagged');
select pg_temp.ok(not exists (select 1 from jsonb_array_elements(public.kmr_ops_list('test-a', 'gauges')) e, jsonb_each_text(e -> 'data') d where d.value like '@%'),
                  'all sample dates resolved to real dates');
select pg_temp.ok((select e -> 'data' ->> 'next_due' from jsonb_array_elements(public.kmr_ops_list('test-a', 'gauges')) e where e ->> 'code' = 'GA-VC-001')
                  = to_char(current_date + 140, 'YYYY-MM-DD'), 'gauge next-due date = last calibrated + 6 months');

-- the planner reads the sample masters, and keeps the company's own plant standards
select pg_temp.ok(jsonb_array_length(public.kmr_capacity_masters('00000000-0000-0000-0000-00000000c0a1') -> 'operations') = 43
              and jsonb_array_length(public.kmr_capacity_masters('00000000-0000-0000-0000-00000000c0a1') -> 'machines') = 12, 'planner sees 12 machines and 43 routings');
select pg_temp.ok((public.kmr_capacity_masters('00000000-0000-0000-0000-00000000c0a1') -> 'standards' ->> 'oee') = '85', 'planner keeps the company''s own plant standards (OEE 85)');
select pg_temp.ok((select e ->> 'partName' from jsonb_array_elements(public.kmr_capacity_masters('00000000-0000-0000-0000-00000000c0a1') -> 'operations') e
                    where e ->> 'partNo' = 'DP-1101' limit 1) = 'Drive Flange', 'routings carry part names from Parts');

-- editing and CSV-importing over sample records makes them the company's own
select pg_temp.as_user('editor@a.test');
select public.kmr_ops_save('test-a', 'tools', (select jsonb_build_array(e || '{"name":"Edited insert"}') from jsonb_array_elements(public.kmr_ops_list('test-a', 'tools')) e where e ->> 'code' = 'TL-INS-001'));
select public.kmr_ops_save('test-a', 'customers', '[{"code":"CUS-001","name":"Imported customer","data":{"city":"Hosur"}}]');
select pg_temp.ok((public.kmr_ops_counts('test-a') ->> '_sample')::int = 159, 'edited + imported records are no longer sample');

select pg_temp.as_user('admin@a.test');
select pg_temp.ok(public.kmr_ops_sample_flush('test-a') = 159, 'flush removes the 159 sample records');
select pg_temp.ok((public.kmr_ops_counts('test-a') ->> '_sample')::int = 0, 'no sample records left');
select pg_temp.ok((select string_agg(kind || ':' || code, ',' order by kind, code) from jsonb_each(public.kmr_ops_counts('test-a')) k(kind, v),
                   jsonb_array_elements(case when kind = '_sample' then '[]'::jsonb else public.kmr_ops_list('test-a', kind) end) e(x), lateral (select x ->> 'code' code) c)
                  = 'customers:CUS-001,machines:CNC-T01,plant_standards:MAIN,suppliers:OWN-SUP,tools:TL-INS-001', 'only real data remains (3 originals + edited + imported)');

-- company B loads its own copy, unaffected by A
select pg_temp.as_user('admin@b.test');
select pg_temp.ok((select public.kmr_ops_sample_load('test-b')) = '{"added": 163, "skipped": 0}', 'company B gets its own full copy (163)');
select pg_temp.ok(public.kmr_ops_sample_flush('test-b') = 163, 'company B flush removes 163');
reset role;
select pg_temp.ok((select count(*) from console.ops_records r join console.customers c on c.id = r.customer_id where c.slug = 'test-a') = 5, 'company A untouched by B''s flush');
