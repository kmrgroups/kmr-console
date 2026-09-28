-- =====================================================================
-- KMR platform — ACCESS REPAIR (safe to run any time, as often as needed).
-- Brings access up to date for every customer and ends with a report of who can use which tool.
--  • the main contact and every company administrator are admin in every tool the customer has
--  • any administrator (not only the main contact) gets access automatically when opening a bought tool
--  • tools switched on later give administrators access straight away
-- Needs 0011_customer_admin.sql (the one user list). If that is missing this file says so and stops.
-- =====================================================================
do $$ begin
  if to_regclass('console.customer_members') is null or to_regprocedure('console.sync_member(uuid,text)') is null then
    raise exception 'Run 0011_customer_admin.sql first (it creates the one user list), then run this file again.';
  end if;
end $$;

create or replace function console.grant_admins(p_customer uuid) returns void
language plpgsql security definer set search_path = console, public as $$
declare m record; l record; r jsonb;
begin
  -- the main contact is always a company administrator
  insert into console.customer_members (customer_id, email, full_name, is_admin, created_by)
  select c.id, lower(c.contact_email), c.contact_name, true, 'Contact person' from console.customers c
   where c.id = p_customer and coalesce(c.contact_email, '') <> ''
  on conflict (customer_id, email) do update set is_admin = true;
  for m in select * from console.customer_members where customer_id = p_customer and is_admin loop
    r := m.roles;
    for l in select product_code from console.licences where customer_id = p_customer and product_ref is not null loop
      if coalesce(r ->> l.product_code, '') = '' then
        r := r || jsonb_build_object(l.product_code, case when l.product_code = 'hrm' then 'company_admin' else 'admin' end);
      end if;
    end loop;
    if r <> m.roles then
      update console.customer_members set roles = r, updated_at = now() where customer_id = p_customer and email = m.email;
    end if;
    begin
      perform console.sync_member(p_customer, m.email);
    exception when others then
      raise notice 'Could not give % access in every tool: %', m.email, sqlerrm;   -- e.g. the email already uses another company's HRM
    end;
  end loop;
end $$;

create or replace function console.licence_grant_admins() returns trigger
language plpgsql security definer set search_path = console, public as $$
begin
  if new.product_ref is not null then perform console.grant_admins(new.customer_id); end if;
  return new;
end $$;
drop trigger if exists licences_grant_admins on console.licences;
create trigger licences_grant_admins after insert or update of product_ref, customer_id on console.licences
  for each row execute function console.licence_grant_admins();


-- First open of a bought tool: give access to the main contact and to company administrators
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
    when 'hrm'      then exists (select 1 from hrm.app_users u join console.licences l on l.product_ref = u.tenant_id and l.product_code = 'hrm' where l.customer_id = cid and u.id = auth.uid() and u.active)
    else false end;
  if not ok then
    raise exception 'You have not been given access to this app. Your company administrator can add it under KMR Apps › Administration › Users & access.';
  end if;
  return 'ok';
end $$;
revoke all on function public.kmr_portal_join(text, text) from public, anon;
grant execute on function public.kmr_portal_join(text, text) to authenticated;

-- KMR staff: "Repair access" button on the Console customer page
create or replace function public.kmr_console_repair_access(p_customer uuid) returns text
language plpgsql security definer set search_path = console, public as $$
begin
  if not console.is_staff() then raise exception 'KMR staff only.'; end if;
  perform console.grant_admins(p_customer);
  return 'ok';
end $$;
revoke all on function public.kmr_console_repair_access(uuid) from public, anon;
grant execute on function public.kmr_console_repair_access(uuid) to authenticated;

-- apply to every customer now
do $$ declare c uuid; begin for c in select id from console.customers loop perform console.grant_admins(c); end loop; end $$;

-- REPORT: who can use which tool (check this after running)
select c.name as customer, p.name as tool, l.status as licence,
       coalesce((select string_agg(m.email || ' (' || (m.roles ->> l.product_code) || ')', ', ' order by m.email)
                   from console.customer_members m where m.customer_id = c.id and coalesce(m.roles ->> l.product_code, '') <> ''), '— nobody —') as people_with_access,
       lower(coalesce(c.contact_email, '')) as main_contact
  from console.licences l join console.customers c on c.id = l.customer_id join console.products p on p.code = l.product_code
 where l.product_ref is not null
 order by c.name, p.sort_order;
