-- =====================================================================
-- KMR Console — Milestone 2: Balloon Inspector + Process Documents under Console licences.
-- Run after 0001_console.sql, in the project where the tools' bi_* and pd_* tables already exist.
-- Safe to re-run. It only ADDS rules; it never loosens the tools' existing security.
--
--  • A workspace (bi_orgs / pd_orgs) is usable while its licence is trial / pilot / active and not past its end date.
--    Platform admins of the tool are never blocked.
--  • Enforced in the database with RESTRICTIVE row-level-security policies on the tools' data tables,
--    so it cannot be bypassed from the browser.
--  • Every workspace that exists today is adopted: a Console customer + an active pilot licence.
--  • Workspaces created later inside the tools (Admin → Companies) get a 30-day trial licence automatically.
--  • The licence's user limit caps the number of workspace members.
-- =====================================================================

do $$ begin
  if to_regclass('console.licences') is null then raise exception 'Run 0001_console.sql (KMR platform setup) first.'; end if;
  if to_regclass('public.bi_orgs') is null or to_regclass('public.pd_orgs') is null then
    raise exception 'Balloon Inspector / Process Documents tables (bi_orgs, pd_orgs) were not found in this project.';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- Licence state for a product + workspace (shared by policies, the tools and the HRM)
-- ---------------------------------------------------------------------
create or replace function console.access_state(p_product text, p_ref uuid)
returns table (ok boolean, status text, message text)
language sql stable security definer set search_path = console, public as $$
  select
    coalesce(l.status in ('trial','pilot','active') and (l.valid_until is null or l.valid_until >= current_date), false),
    case when l.id is null then 'none'
         when l.status in ('trial','pilot','active') and l.valid_until < current_date then 'expired'
         else l.status end,
    case when l.id is null then 'This workspace does not have a licence.'
         when l.status in ('trial','pilot','active') and l.valid_until < current_date
           then format('Your company''s %s %s ended on %s.', p.name, case when l.status = 'trial' then 'trial' else 'licence' end, to_char(l.valid_until, 'DD Mon YYYY'))
         when l.status = 'suspended' then format('Your company''s %s access is suspended.', p.name)
         when l.status in ('trial','pilot','active') then null
         else format('Your company''s %s licence is %s.', p.name, l.status) end
  from (select 1) one
  left join console.licences l on l.product_code = p_product and l.product_ref = p_ref
  left join console.products p on p.code = p_product
$$;

create or replace function console.tool_admin(p_product text) returns boolean
language plpgsql stable security definer set search_path = public as $$
begin
  if p_product = 'balloon' then return exists (select 1 from public.bi_platform_admins where user_id = auth.uid()); end if;
  if p_product = 'pd'      then return exists (select 1 from public.pd_platform_admins where user_id = auth.uid()); end if;
  return false;
end $$;

-- True when the signed-in person may use this workspace's data right now
create or replace function console.product_ok(p_product text, p_ref uuid) returns boolean
language sql stable security definer set search_path = console, public as $$
  select console.tool_admin(p_product) or coalesce((select ok from console.access_state(p_product, p_ref)), false)
$$;
grant execute on function console.product_ok(text, uuid) to authenticated;
grant execute on function console.access_state(text, uuid) to authenticated, service_role;

-- For the tools' screens: licence state of every workspace the signed-in person belongs to
create or replace function public.kmr_access(p_product text)
returns table (org_id uuid, ok boolean, status text, message text)
language plpgsql stable security definer set search_path = public, console as $$
declare em text := lower(coalesce(auth.jwt() ->> 'email', ''));
begin
  if console.tool_admin(p_product) then
    if p_product = 'balloon' then return query select o.id, true, 'admin'::text, null::text from public.bi_orgs o; end if;
    if p_product = 'pd'      then return query select o.id, true, 'admin'::text, null::text from public.pd_orgs o; end if;
    return;
  end if;
  if p_product = 'balloon' then
    return query select m.org_id, a.ok, a.status, a.message from public.bi_members m cross join lateral console.access_state('balloon', m.org_id) a where lower(m.email) = em;
  elsif p_product = 'pd' then
    return query select m.org_id, a.ok, a.status, a.message from public.pd_members m cross join lateral console.access_state('pd', m.org_id) a where lower(m.email) = em;
  end if;
end $$;
revoke all on function public.kmr_access(text) from public, anon;
grant execute on function public.kmr_access(text) to authenticated;

-- ---------------------------------------------------------------------
-- Adopt existing workspaces (one Console customer per company name across both tools)
-- ---------------------------------------------------------------------
do $$
declare o record; cid uuid;
begin
  for o in select 'balloon' as product, id, name from public.bi_orgs
           union all select 'pd', id, name from public.pd_orgs loop
    if exists (select 1 from console.licences where product_code = o.product and product_ref = o.id) then continue; end if;
    select id into cid from console.customers where lower(name) = lower(o.name) limit 1;
    if cid is null then
      insert into console.customers (name, status, source, notes)
      values (o.name, 'pilot', 'Existing workspace', 'Adopted from the tools when the Console was connected')
      returning id into cid;
    end if;
    if not exists (select 1 from console.licences where customer_id = cid and product_code = o.product) then
      insert into console.licences (customer_id, product_code, status, product_ref, product_slug, notes)
      values (cid, o.product, 'pilot', o.id, o.name, 'Existing workspace, adopted');
    end if;
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- New workspaces created inside the tools get a 30-day trial automatically
-- (the Console creates its own licence first, so its workspaces are skipped here)
-- ---------------------------------------------------------------------
create or replace function console.auto_trial() returns trigger
language plpgsql security definer set search_path = console, public as $$
declare product text := case tg_table_name when 'bi_orgs' then 'balloon' else 'pd' end; cid uuid;
begin
  if exists (select 1 from console.licences where product_code = product and product_ref = new.id) then return new; end if;
  select id into cid from console.customers where lower(name) = lower(new.name) limit 1;
  if cid is null then
    insert into console.customers (name, status, source) values (new.name, 'pilot', 'Created inside the tool') returning id into cid;
  end if;
  if exists (select 1 from console.licences where customer_id = cid and product_code = product) then
    -- the customer already has this product for another workspace: record this one as its own customer
    insert into console.customers (name, status, source) values (new.name || ' (' || left(new.id::text, 8) || ')', 'pilot', 'Created inside the tool') returning id into cid;
  end if;
  insert into console.licences (customer_id, product_code, status, valid_until, product_ref, product_slug, notes)
  values (cid, product, 'trial', current_date + 30, new.id, new.name, 'Created inside the tool — 30-day trial');
  return new;
end $$;
drop trigger if exists kmr_auto_trial on public.bi_orgs;
drop trigger if exists kmr_auto_trial on public.pd_orgs;
create trigger kmr_auto_trial after insert on public.bi_orgs for each row execute function console.auto_trial();
create trigger kmr_auto_trial after insert on public.pd_orgs for each row execute function console.auto_trial();

-- ---------------------------------------------------------------------
-- User limit: a workspace cannot have more members than its licence allows
-- ---------------------------------------------------------------------
create or replace function console.member_limit() returns trigger
language plpgsql security definer set search_path = console, public as $$
declare product text := case tg_table_name when 'bi_members' then 'balloon' else 'pd' end; lim int; n int;
begin
  select seats into lim from console.licences where product_code = product and product_ref = new.org_id;
  if lim is null then return new; end if;
  if tg_table_name = 'bi_members' then
    select count(*) into n from public.bi_members where org_id = new.org_id and lower(email) <> lower(new.email);
  else
    select count(*) into n from public.pd_members where org_id = new.org_id and lower(email) <> lower(new.email);
  end if;
  if n >= lim then raise exception 'Your licence covers % users for this workspace, and that limit is reached. Contact KMR to raise it.', lim; end if;
  return new;
end $$;
drop trigger if exists kmr_member_limit on public.bi_members;
drop trigger if exists kmr_member_limit on public.pd_members;
create trigger kmr_member_limit before insert on public.bi_members for each row execute function console.member_limit();
create trigger kmr_member_limit before insert on public.pd_members for each row execute function console.member_limit();

-- ---------------------------------------------------------------------
-- Enforcement: restrictive policies on the tools' data (added only where row-level security is on)
-- ---------------------------------------------------------------------
do $$
declare t record;
begin
  for t in select * from (values ('bi_reports','balloon'), ('pd_projects','pd'), ('pd_masters','pd')) v(tbl, product) loop
    if to_regclass('public.' || t.tbl) is null then raise notice 'Table % not found — skipped.', t.tbl; continue; end if;
    if not (select relrowsecurity from pg_class where oid = ('public.' || t.tbl)::regclass) then
      raise notice 'Row-level security is OFF on % — licence not enforced there. Turn it on in the tool''s own setup.', t.tbl; continue;
    end if;
    execute format('drop policy if exists kmr_licence on public.%I', t.tbl);
    execute format('create policy kmr_licence on public.%I as restrictive for all to authenticated using (console.product_ok(%L, org_id)) with check (console.product_ok(%L, org_id))', t.tbl, t.product, t.product);
  end loop;
end $$;
