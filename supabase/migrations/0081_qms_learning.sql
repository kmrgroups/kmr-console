-- =====================================================================
-- 0081 — QMS Learning Guide (a new KMR App, for any company)
--  • A self-learning manual for ISO 9001, IATF 16949, VDA 6.3, AIAG Control Plan and the core tools (APQP, PPAP, FMEA, MSA, SPC):
--    every clause with its requirement in plain words, what it means, how to implement, documents and records, a sample example,
--    and where the clause comes from. Every page carries the watermark "Educational Purpose Only".
--  • Coverage analysis: which KMR app covers which clause, and what is still missing.
--  • The content is in the website; this migration only adds the product so it can be licensed and switched on per company.
-- Needs 0080. Safe to re-run.
-- =====================================================================
do $$ begin
  if to_regprocedure('console.d8_sample(uuid, text)') is null then raise exception 'Run 0080_d8_problem_solving.sql first.'; end if;
end $$;
insert into console.products (code, name, description, app_path, seat_label, current_version, sort_order) values
  ('qms', 'QMS Learning Guide', 'Self-learning manual of ISO 9001, IATF 16949, VDA 6.3, Control Plan and the core tools, clause by clause, with examples and a coverage analysis of the KMR apps', '/it/qms.html', 'users', '1.0.0', 16)
on conflict (code) do nothing;
insert into console.releases (product_code, version, notes) values
  ('qms', '1.0.0', 'QMS Learning Guide: ISO 9001 and IATF 16949 clause by clause, coverage analysis') on conflict do nothing;
insert into console.prices (product_code, period, currency, unit_amount, min_seats, active, note)
select v.code, v.period, 'INR', v.amt, 3, true, 'Starting price list (0081) — per user, change in Console › Billing'
  from (values ('qms', 'month', 40), ('qms', 'year', 400)) v(code, period, amt)
 where not exists (select 1 from console.prices x where x.product_code = v.code and x.currency = 'INR' and x.period = v.period)
on conflict (product_code, period, currency) do nothing;
insert into public.app_listings (code, name, tagline, features, sort_order, is_active) values
  ('qms', 'QMS Learning Guide', 'Learn ISO 9001, IATF 16949 and the core tools clause by clause, in plain words, with examples.',
   E'Every clause: the requirement, what it means, how to implement, documents and records, a sample\nSearch, filters and a learning path for beginners\nCoverage analysis: what the KMR apps already cover and what is left', 16, true)
on conflict (code) do update set name = excluded.name, tagline = excluded.tagline, features = excluded.features, is_active = true;
insert into console.app_features (product_code, name, detail, is_core, price_month, price_year, setup_fee, sort_order) values
  ('qms', 'Standards manual', 'ISO 9001 and IATF 16949 clause by clause with explanations, implementation steps, documents and records, and samples', true, 15, 0, 0, 10),
  ('qms', 'Coverage analysis', 'Which KMR app covers which clause, and the clauses still without an app', false, 5, 0, 0, 20)
on conflict (product_code, name) do nothing;
delete from console.app_features f where f.product_code = 'qms' and f.name = 'Core platform' and not exists (select 1 from console.invoice_lines il where il.feature_id = f.id);
update console.app_features set price_year = price_month * 10 where product_code = 'qms' and price_year = 0;
select console.sync_app_price('qms');

-- the app has no data of its own: access is by the company's licence and member roles, like the other company-level apps
create or replace function public.kmr_qms_enabled(p_slug text) returns boolean language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  return cid is not null and console.qp_role(cid, 'qms') is not null;
end $$;
revoke all on function public.kmr_qms_enabled(text) from public; grant execute on function public.kmr_qms_enabled(text) to authenticated;

create or replace function public.kmr_qp_context(p_slug text, p_code text) returns jsonb language sql stable security definer set search_path = console, public as $$
  select case when console.qp_role(c.id, p_code) is null then null else jsonb_build_object('role', console.qp_role(c.id, p_code), 'company', c.name) end
    from console.customers c where c.slug = lower(p_slug) and p_code in ('apqp', 'ppap', 'rmp', 'mmd', 'mnt', 'mom', 'cad', 'hrms', 'tsk', 'msa', 'spc', 'crm', 'd8', 'qms') $$;


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
      or (l.product_code = 'calib'    and console.cal_member(l.customer_id, em))
      or (l.product_code in ('apqp', 'ppap', 'rmp', 'mmd', 'mnt', 'mom', 'cad', 'hrms', 'tsk', 'msa', 'spc', 'crm', 'd8', 'qms') and console.qp_member(l.customer_id, em, l.product_code))
      or (l.product_code = 'hrm'      and exists (select 1 from hrm.app_users u where u.tenant_id = l.product_ref and u.id = uid and u.active)))
   limit 1;
  if not coalesce(member, false) and lower(coalesce(c.contact_email, '')) <> em and not console.is_staff() then return; end if;
  return query
    select p.code, p.name, p.app_path, (l.id is not null), coalesce(a.ok, false), coalesce(a.status, 'not_purchased'),
           l.valid_until, a.message, c.name, c.logo_url, l.product_slug,
           case p.code
             when 'balloon'  then exists (select 1 from public.bi_members m where m.org_id = l.product_ref and lower(m.email) = em)
             when 'pd'       then exists (select 1 from public.pd_members m where m.org_id = l.product_ref and lower(m.email) = em)
             when 'capacity' then exists (select 1 from public.cp_members m where m.org_id = l.product_ref and m.email = em)
             when 'sales'    then console.sf_member(l.customer_id, em)
             when 'calib'    then console.cal_member(l.customer_id, em)
             when 'apqp'     then console.qp_member(l.customer_id, em, 'apqp')
             when 'ppap'     then console.qp_member(l.customer_id, em, 'ppap')
             when 'rmp'      then console.qp_member(l.customer_id, em, 'rmp')
             when 'mmd'      then console.qp_member(l.customer_id, em, 'mmd')
             when 'mnt'      then console.qp_member(l.customer_id, em, 'mnt')
             when 'mom'      then console.qp_member(l.customer_id, em, 'mom')
             when 'cad'      then console.qp_member(l.customer_id, em, 'cad')
             when 'hrms'      then console.qp_member(l.customer_id, em, 'hrms')
             when 'tsk'        then console.qp_member(l.customer_id, em, 'tsk')
             when 'msa'        then console.qp_member(l.customer_id, em, 'msa')
             when 'spc'        then console.qp_member(l.customer_id, em, 'spc')
             when 'crm'        then console.qp_member(l.customer_id, em, 'crm')
             when 'd8'        then console.qp_member(l.customer_id, em, 'd8')
             when 'qms'        then console.qp_member(l.customer_id, em, 'qms')
             when 'hrm'      then exists (select 1 from hrm.app_users u where u.tenant_id = l.product_ref and u.id = uid and u.active)
             else false end,
           (lower(coalesce(c.contact_email, '')) = em or console.is_staff())
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
declare em text := lower(coalesce(auth.jwt() ->> 'email', '')); cid uuid; ok boolean; uid_ uuid := auth.uid();
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or em = '' then raise exception 'Unknown company link.'; end if;
  if not exists (select 1 from console.licences where customer_id = cid and product_code = p_product and product_ref is not null) then
    raise exception 'This app is not set up for your company yet. Please contact KMR.';
  end if;
  if console.is_staff() then                   -- KMR staff (developer admin): administrator of every company, in every tool
    insert into console.customer_members (customer_id, email, full_name, is_admin, created_by)
    values (cid, em, coalesce((select full_name from console.staff where user_id = uid_), 'KMR Developer Admin'), true, 'KMR staff')
    on conflict (customer_id, email) do update set is_admin = true;
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
    when 'calib'    then console.cal_member(cid, em)
    when 'apqp'     then console.qp_member(cid, em, 'apqp')
    when 'ppap'     then console.qp_member(cid, em, 'ppap')
    when 'rmp'      then console.qp_member(cid, em, 'rmp')
    when 'mmd'      then console.qp_member(cid, em, 'mmd')
    when 'mnt'      then console.qp_member(cid, em, 'mnt')
    when 'mom'      then console.qp_member(cid, em, 'mom')
    when 'cad'      then console.qp_member(cid, em, 'cad')
    when 'hrms'      then console.qp_member(cid, em, 'hrms')
    when 'tsk'        then console.qp_member(cid, em, 'tsk')
    when 'msa'        then console.qp_member(cid, em, 'msa')
    when 'spc'        then console.qp_member(cid, em, 'spc')
    when 'crm'        then console.qp_member(cid, em, 'crm')
    when 'd8'        then console.qp_member(cid, em, 'd8')
    when 'qms'        then console.qp_member(cid, em, 'qms')
    when 'hrm'      then exists (select 1 from hrm.app_users u join console.licences l on l.product_ref = u.tenant_id and l.product_code = 'hrm' where l.customer_id = cid and u.id = auth.uid() and u.active)
    else false end;
  if not ok then
    raise exception 'You have not been given access to this app. Your company administrator can add it under KMR Apps › Administration › Users & access.';
  end if;
  return 'ok';
end $$;
revoke all on function public.kmr_portal_join(text, text) from public, anon;
grant execute on function public.kmr_portal_join(text, text) to authenticated;

