-- 0075: a KMR staff login (Console staff list) is made an administrator of the company, in every tool, the first time it opens an app.
-- Same function as before with one extra step; run after 0074.
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
    when 'hrm'      then exists (select 1 from hrm.app_users u join console.licences l on l.product_ref = u.tenant_id and l.product_code = 'hrm' where l.customer_id = cid and u.id = auth.uid() and u.active)
    else false end;
  if not ok then
    raise exception 'You have not been given access to this app. Your company administrator can add it under KMR Apps › Administration › Users & access.';
  end if;
  return 'ok';
end $$;
revoke all on function public.kmr_portal_join(text, text) from public, anon;
grant execute on function public.kmr_portal_join(text, text) to authenticated;
