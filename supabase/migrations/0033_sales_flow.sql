-- =====================================================================
-- KMR platform — Sales Flow (sales plan vs actual despatch). Needs 0011 (customer members), 0015 (Operations Master)
-- and 0029. Safe to re-run.
--  • One Sales Flow per customer company; licence product "sales" (product_ref = the customer's id).
--  • Access = the customer's user list: Administration › Users & access, role "sales" = admin / editor / viewer;
--    company administrators always have full access.
--  • Parts, customers and prices are NOT typed in: "Add parts" pulls them from the Operations Master
--    (parts + customers + the customer's rate contract valid today).
--  • A plan line = one part for one month: demand quantity + delivery schedule (specific date / daily / weekly).
--  • Actual despatch is entered per day (one figure per line per day). Pending = demand − despatched.
-- =====================================================================
do $$ begin
  if to_regclass('console.ops_records') is null then raise exception 'Run 0015_operations_master.sql first.'; end if;
  if to_regclass('console.customer_members') is null then raise exception 'Run 0011_customer_admin.sql first.'; end if;
end $$;

create table if not exists console.sf_lines (
  id            uuid primary key default gen_random_uuid(),
  customer_id   uuid not null references console.customers(id) on delete cascade,
  month         date not null check (month = date_trunc('month', month)::date),
  buyer_code    text not null default '',            -- customer code in the Operations Master (CUS-001)
  buyer_name    text not null default '',            -- customer name (copied, so history survives master changes)
  part_code     text not null check (length(trim(part_code)) > 0),
  part_name     text not null default '',
  price         numeric(14,2) not null default 0 check (price >= 0),
  currency      text not null default 'INR',
  uom           text not null default 'pcs',
  demand_qty    numeric(14,2) not null default 0 check (demand_qty >= 0),
  sched_type    text not null default 'date' check (sched_type in ('date','daily','weekly')),
  sched_date    date,                                -- sched_type = date: the delivery date
  sched_weekday smallint check (sched_weekday between 1 and 7),   -- sched_type = weekly: ISO weekday (1 = Monday)
  remarks       text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  updated_by    text,
  unique (customer_id, month, part_code, buyer_code)
);
create index if not exists sf_lines_month on console.sf_lines (customer_id, month);

create table if not exists console.sf_despatch (
  line_id       uuid not null references console.sf_lines(id) on delete cascade,
  customer_id   uuid not null references console.customers(id) on delete cascade,
  day           date not null,
  qty           numeric(14,2) not null check (qty >= 0),
  note          text,
  updated_at    timestamptz not null default now(),
  updated_by    text,
  primary key (line_id, day)
);
create index if not exists sf_despatch_day on console.sf_despatch (customer_id, day);

alter table console.sf_lines    enable row level security;
alter table console.sf_despatch enable row level security;
drop policy if exists sf_lines_staff on console.sf_lines;
create policy sf_lines_staff on console.sf_lines for all to authenticated using (console.is_staff()) with check (console.is_staff());
drop policy if exists sf_despatch_staff on console.sf_despatch;
create policy sf_despatch_staff on console.sf_despatch for all to authenticated using (console.is_staff()) with check (console.is_staff());

-- ---------- who may use it ----------
create or replace function console.sf_member(p_customer uuid, p_email text) returns boolean
language sql stable security definer set search_path = console, public as $$
  select exists (select 1 from console.customer_members m
                  where m.customer_id = p_customer and m.email = lower(p_email)
                    and (m.is_admin or coalesce(m.roles ->> 'sales', '') <> ''))
$$;

-- admin / editor / viewer / null (null also when the licence is not active)
create or replace function console.sf_role(p_customer uuid) returns text
language sql stable security definer set search_path = console, public as $$
  select case
    when not coalesce((select ok from console.access_state('sales', p_customer)), false) then null
    when console.is_customer_admin(p_customer) then 'admin'
    else (select nullif(m.roles ->> 'sales', '') from console.customer_members m
           where m.customer_id = p_customer and m.email = lower(coalesce(auth.jwt() ->> 'email', '')))
  end
$$;
grant execute on function console.sf_role(uuid) to authenticated;

create or replace function public.kmr_sf_context(p_slug text) returns jsonb
language sql stable security definer set search_path = console, public as $$
  select case when console.sf_role(c.id) is null then null
              else jsonb_build_object('role', console.sf_role(c.id), 'customer_id', c.id, 'company', c.name) end
    from console.customers c where c.slug = lower(p_slug)
$$;
grant execute on function public.kmr_sf_context(text) to authenticated;

-- ---------- "Add parts": parts + customer + price from the Operations Master ----------
-- Price = the customer's rate contract for the part that is valid today (latest valid_from); falls back to a "price"
-- or "rate" held on the part itself; 0 when none is found (the planner can then type it).
create or replace function public.kmr_sf_parts(p_slug text) returns jsonb
language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid; today date := (now() at time zone 'Asia/Kolkata')::date;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or console.sf_role(cid) is null then raise exception 'You have no access to Sales Flow.'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'part_code', p.code, 'part_name', p.name, 'drawing_no', p.data ->> 'drawing_no',
             'buyer_code', coalesce(p.data ->> 'customer', ''), 'buyer_name', coalesce(cu.name, p.data ->> 'customer', ''),
             'price', coalesce(rc.rate, nullif(p.data ->> 'price', '')::numeric, nullif(p.data ->> 'rate', '')::numeric, 0),
             'currency', coalesce(rc.currency, 'INR'), 'uom', coalesce(rc.uom, 'pcs'),
             'price_source', case when rc.rate is not null then 'rate contract ' || rc.code else null end)
           order by cu.name, p.code)
      from console.ops_records p
      left join console.ops_records cu on cu.customer_id = p.customer_id and cu.kind = 'customers' and cu.code = p.data ->> 'customer'
      left join lateral (
        select r.code, (r.data ->> 'rate')::numeric rate, coalesce(r.data ->> 'currency', 'INR') currency, coalesce(r.data ->> 'uom', 'pcs') uom
          from console.ops_records r
         where r.customer_id = p.customer_id and r.kind = 'rate_contracts' and r.active
           and r.data ->> 'party_type' = 'Customer' and r.data ->> 'item' = p.code
           and coalesce(r.data ->> 'rate', '') ~ '^[0-9.]+$'
           and (coalesce(r.data ->> 'valid_from', '') !~ '^\d{4}-\d{2}-\d{2}$' or (r.data ->> 'valid_from')::date <= today)
           and (coalesce(r.data ->> 'valid_to', '')   !~ '^\d{4}-\d{2}-\d{2}$' or (r.data ->> 'valid_to')::date   >= today)
         order by coalesce(nullif(r.data ->> 'valid_from', ''), '0000') desc limit 1) rc on true
     where p.customer_id = cid and p.kind = 'parts' and p.active), '[]');
end $$;
grant execute on function public.kmr_sf_parts(text) to authenticated;

-- ---------- a month: plan lines + daily despatch ----------
create or replace function public.kmr_sf_month(p_slug text, p_month date) returns jsonb
language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid; m date := date_trunc('month', p_month)::date;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or console.sf_role(cid) is null then raise exception 'You have no access to Sales Flow.'; end if;
  return jsonb_build_object(
    'lines', coalesce((select jsonb_agg(to_jsonb(l) - 'customer_id' order by l.buyer_name, l.part_code)
                         from console.sf_lines l where l.customer_id = cid and l.month = m), '[]'),
    'despatch', coalesce((select jsonb_agg(jsonb_build_object('line_id', d.line_id, 'day', d.day, 'qty', d.qty, 'note', d.note))
                            from console.sf_despatch d join console.sf_lines l on l.id = d.line_id
                           where l.customer_id = cid and l.month = m), '[]'));
end $$;
grant execute on function public.kmr_sf_month(text, date) to authenticated;

-- ---------- save / delete a plan line (p: {id?, month, buyer_code, buyer_name, part_code, part_name, price, currency, uom,
--            demand_qty, sched_type, sched_date, sched_weekday, remarks}); several at once as an array ----------
create or replace function public.kmr_sf_save_lines(p_slug text, p jsonb) returns integer
language plpgsql security definer set search_path = console, public as $$
declare cid uuid; r jsonb; n integer := 0; me text := lower(coalesce(auth.jwt() ->> 'email', '')); st text; m date;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or coalesce(console.sf_role(cid), '') not in ('admin','editor') then
    raise exception 'You can view Sales Flow but not change it. Ask your administrator for editor access.';
  end if;
  for r in select * from jsonb_array_elements(case when jsonb_typeof(p) = 'array' then p else jsonb_build_array(p) end) loop
    st := coalesce(r ->> 'sched_type', 'date');
    m  := date_trunc('month', (r ->> 'month')::date)::date;
    if st = 'date' and coalesce(r ->> 'sched_date', '') = '' then raise exception 'Choose the delivery date for % (or switch to Daily / Weekly).', r ->> 'part_code'; end if;
    if st = 'date' and date_trunc('month', (r ->> 'sched_date')::date)::date <> m then raise exception 'The delivery date of % is outside the month.', r ->> 'part_code'; end if;
    if st = 'weekly' and coalesce(r ->> 'sched_weekday', '') = '' then raise exception 'Choose the weekday for the weekly delivery of %.', r ->> 'part_code'; end if;
    if r ? 'id' and (r ->> 'id') ~ '^[0-9a-f-]{36}$' then
      update console.sf_lines set price = coalesce((r ->> 'price')::numeric, price), demand_qty = coalesce((r ->> 'demand_qty')::numeric, demand_qty),
             sched_type = st, sched_date = case when st = 'date' then (r ->> 'sched_date')::date end,
             sched_weekday = case when st = 'weekly' then (r ->> 'sched_weekday')::smallint end,
             remarks = r ->> 'remarks', updated_at = now(), updated_by = me
       where id = (r ->> 'id')::uuid and customer_id = cid;
    else
      insert into console.sf_lines (customer_id, month, buyer_code, buyer_name, part_code, part_name, price, currency, uom, demand_qty,
                                    sched_type, sched_date, sched_weekday, remarks, updated_by)
      values (cid, m, coalesce(r ->> 'buyer_code', ''), coalesce(r ->> 'buyer_name', ''), trim(r ->> 'part_code'), coalesce(r ->> 'part_name', ''),
              coalesce((r ->> 'price')::numeric, 0), coalesce(r ->> 'currency', 'INR'), coalesce(r ->> 'uom', 'pcs'), coalesce((r ->> 'demand_qty')::numeric, 0),
              st, case when st = 'date' then (r ->> 'sched_date')::date end, case when st = 'weekly' then (r ->> 'sched_weekday')::smallint end,
              r ->> 'remarks', me)
      on conflict (customer_id, month, part_code, buyer_code) do update
        set demand_qty = excluded.demand_qty, price = excluded.price, sched_type = excluded.sched_type, sched_date = excluded.sched_date,
            sched_weekday = excluded.sched_weekday, remarks = excluded.remarks, updated_at = now(), updated_by = me;
    end if;
    n := n + 1;
  end loop;
  return n;
end $$;
grant execute on function public.kmr_sf_save_lines(text, jsonb) to authenticated;

create or replace function public.kmr_sf_delete_line(p_slug text, p_id uuid) returns text
language plpgsql security definer set search_path = console, public as $$
declare cid uuid;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or coalesce(console.sf_role(cid), '') not in ('admin','editor') then raise exception 'You cannot change Sales Flow.'; end if;
  delete from console.sf_lines where id = p_id and customer_id = cid;
  return 'ok';
end $$;
grant execute on function public.kmr_sf_delete_line(text, uuid) to authenticated;

-- ---------- daily despatch: p_rows = [{line_id, day, qty, note?}]; qty 0 / empty removes the day's entry ----------
create or replace function public.kmr_sf_save_despatch(p_slug text, p_rows jsonb) returns integer
language plpgsql security definer set search_path = console, public as $$
declare cid uuid; r jsonb; n integer := 0; q numeric; me text := lower(coalesce(auth.jwt() ->> 'email', ''));
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or coalesce(console.sf_role(cid), '') not in ('admin','editor') then
    raise exception 'You can view Sales Flow but not change it. Ask your administrator for editor access.';
  end if;
  for r in select * from jsonb_array_elements(p_rows) loop
    if not exists (select 1 from console.sf_lines where id = (r ->> 'line_id')::uuid and customer_id = cid) then raise exception 'Unknown plan line.'; end if;
    q := coalesce(nullif(r ->> 'qty', '')::numeric, 0);
    if q < 0 then raise exception 'Despatch quantity cannot be negative.'; end if;
    if (r ->> 'day')::date > (now() at time zone 'Asia/Kolkata')::date then raise exception 'You cannot enter despatch for a future date.'; end if;
    if q = 0 then
      delete from console.sf_despatch where line_id = (r ->> 'line_id')::uuid and day = (r ->> 'day')::date;
    else
      insert into console.sf_despatch (line_id, customer_id, day, qty, note, updated_by)
      values ((r ->> 'line_id')::uuid, cid, (r ->> 'day')::date, q, r ->> 'note', me)
      on conflict (line_id, day) do update set qty = excluded.qty, note = excluded.note, updated_at = now(), updated_by = me;
    end if;
    n := n + 1;
  end loop;
  return n;
end $$;
grant execute on function public.kmr_sf_save_despatch(text, jsonb) to authenticated;

-- ---------- the product in the Console ----------
insert into console.products (code, name, description, app_path, seat_label, current_version, sort_order)
values ('sales', 'Sales Flow', 'Monthly sales plan vs actual despatch, daily tracking and dashboards', '/it/sales.html', 'users', '1.0.0', 50)
on conflict (code) do nothing;
insert into console.releases (product_code, version, notes)
values ('sales', '1.0.0', 'Sales Flow: monthly plan from the Operations Master, delivery schedule, daily despatch, pending and dashboards')
on conflict do nothing;

-- ---------- portal: Sales Flow card, access and figures ----------
drop function if exists public.kmr_portal_stats(text);
drop function if exists public.kmr_portal(text);
create or replace function public.kmr_portal(p_slug text)
returns table (product_code text, product_name text, app_path text, purchased boolean, ok boolean, status text,
               valid_until date, message text, customer_name text, logo_url text, product_slug text,
               has_access boolean, is_contact boolean)
language plpgsql stable security definer set search_path = console, public as $$
declare
  em text := lower(coalesce(auth.jwt() ->> 'email', ''));
  uid uuid := auth.uid();
  c console.customers%rowtype;
  member boolean := false;
begin
  select * into c from console.customers where slug = lower(p_slug);
  if c.id is null or em = '' then return; end if;
  select true into member from console.licences l
   where l.customer_id = c.id and (
         (l.product_code = 'balloon'  and exists (select 1 from public.bi_members m where m.org_id = l.product_ref and lower(m.email) = em))
      or (l.product_code = 'pd'       and exists (select 1 from public.pd_members m where m.org_id = l.product_ref and lower(m.email) = em))
      or (l.product_code = 'capacity' and exists (select 1 from public.cp_members m where m.org_id = l.product_ref and m.email = em))
      or (l.product_code = 'sales'    and console.sf_member(l.customer_id, em))
      or (l.product_code = 'hrm'      and exists (select 1 from hrm.app_users u where u.tenant_id = l.product_ref and u.id = uid and u.active)))
   limit 1;
  if not coalesce(member, false) and lower(coalesce(c.contact_email, '')) <> em then return; end if;
  return query
    select p.code, p.name, p.app_path, (l.id is not null), coalesce(a.ok, false), coalesce(a.status, 'not_purchased'),
           l.valid_until, a.message, c.name, c.logo_url, l.product_slug,
           case p.code
             when 'balloon'  then exists (select 1 from public.bi_members m where m.org_id = l.product_ref and lower(m.email) = em)
             when 'pd'       then exists (select 1 from public.pd_members m where m.org_id = l.product_ref and lower(m.email) = em)
             when 'capacity' then exists (select 1 from public.cp_members m where m.org_id = l.product_ref and m.email = em)
             when 'sales'    then console.sf_member(l.customer_id, em)
             when 'hrm'      then exists (select 1 from hrm.app_users u where u.tenant_id = l.product_ref and u.id = uid and u.active)
             else false end,
           lower(coalesce(c.contact_email, '')) = em
      from console.products p
      left join console.licences l on l.product_code = p.code and l.customer_id = c.id
      left join lateral console.access_state(p.code, l.product_ref) a on l.id is not null
     where p.active
     order by p.sort_order;
end $$;
revoke all on function public.kmr_portal(text) from public, anon;
grant execute on function public.kmr_portal(text) to authenticated;

create or replace function public.kmr_portal_join(p_slug text, p_product text) returns text
language plpgsql security definer set search_path = console, public as $$
declare em text := lower(coalesce(auth.jwt() ->> 'email', '')); cid uuid; ok boolean;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or em = '' then raise exception 'Unknown company link.'; end if;
  if not exists (select 1 from console.licences where customer_id = cid and product_code = p_product and product_ref is not null) then
    raise exception 'This app is not set up for your company yet. Please contact KMR.';
  end if;
  if console.is_customer_admin(cid) then
    perform console.grant_admins(cid);          -- administrators: admin in every bought tool
  end if;
  perform console.sync_member(cid, em);         -- everyone: whatever Administration › Users & access says
  ok := case p_product
    when 'balloon'  then exists (select 1 from public.bi_members m join console.licences l on l.product_ref = m.org_id and l.product_code = 'balloon' where l.customer_id = cid and lower(m.email) = em)
    when 'pd'       then exists (select 1 from public.pd_members m join console.licences l on l.product_ref = m.org_id and l.product_code = 'pd' where l.customer_id = cid and lower(m.email) = em)
    when 'capacity' then exists (select 1 from public.cp_members m join console.licences l on l.product_ref = m.org_id and l.product_code = 'capacity' where l.customer_id = cid and m.email = em)
    when 'sales'    then console.sf_member(cid, em)
    when 'hrm'      then exists (select 1 from hrm.app_users u join console.licences l on l.product_ref = u.tenant_id and l.product_code = 'hrm' where l.customer_id = cid and u.id = auth.uid() and u.active)
    else false end;
  if not ok then
    raise exception 'You have not been given access to this app. Your company administrator can add it under KMR Apps › Administration › Users & access.';
  end if;
  return 'ok';
end $$;
revoke all on function public.kmr_portal_join(text, text) from public, anon;
grant execute on function public.kmr_portal_join(text, text) to authenticated;

create or replace function public.kmr_portal_stats(p_slug text) returns jsonb
language plpgsql stable security definer set search_path = console, public as $$
declare c uuid; out jsonb := '{}'; ref uuid; today date := (now() at time zone 'Asia/Kolkata')::date;
begin
  if not exists (select 1 from public.kmr_portal(p_slug)) then return out; end if;
  select id into c from console.customers where slug = lower(p_slug);
  select product_ref into ref from console.licences where customer_id = c and product_code = 'hrm';
  if ref is not null then
    out := out || jsonb_build_object('hrm', jsonb_build_object(
      'Employees', (select count(*) from hrm.employees where tenant_id = ref and status = 'active'),
      'In today', (select count(*) from hrm.attendance_days where tenant_id = ref and work_date = today and status in ('present','half_day','missed_punch')),
      'Awaiting approval', (select count(*) from hrm.leave_requests where tenant_id = ref and status = 'pending')
                          + (select count(*) from hrm.regularisation_requests where tenant_id = ref and status = 'pending')));
  end if;
  select product_ref into ref from console.licences where customer_id = c and product_code = 'balloon';
  if ref is not null then
    out := out || jsonb_build_object('balloon', jsonb_build_object(
      'Reports', (select count(*) from public.bi_reports where org_id = ref),
      'Users', (select count(*) from public.bi_members where org_id = ref)));
  end if;
  select product_ref into ref from console.licences where customer_id = c and product_code = 'pd';
  if ref is not null then
    out := out || jsonb_build_object('pd', jsonb_build_object(
      'Projects', (select count(*) from public.pd_projects where org_id = ref),
      'Users', (select count(*) from public.pd_members where org_id = ref)));
  end if;
  select product_ref into ref from console.licences where customer_id = c and product_code = 'capacity';
  if ref is not null then
    out := out || jsonb_build_object('capacity', jsonb_build_object(
      'Users', (select count(*) from public.cp_members where org_id = ref),
      'Saved versions', (select count(*) from public.cp_history where org_id = ref) + (select count(*) from public.cp_plans where org_id = ref)));
  end if;
  select product_ref into ref from console.licences where customer_id = c and product_code = 'sales';
  if ref is not null then
    out := out || jsonb_build_object('sales', jsonb_build_object(
      'Users', (select count(*) from console.customer_members m where m.customer_id = c and coalesce(m.roles ->> 'sales', '') <> ''),
      'Parts planned', (select count(*) from console.sf_lines where customer_id = c and month = date_trunc('month', today)::date)));
  end if;
  return out;
end $$;
revoke all on function public.kmr_portal_stats(text) from public, anon;
grant execute on function public.kmr_portal_stats(text) to authenticated;
