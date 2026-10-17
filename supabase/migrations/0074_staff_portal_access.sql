-- 0074: KMR staff (Console staff list) can open every customer's apps page, like the company's main contact.
-- Same function as before with one extra rule; run after 0072/0073.
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
      or (l.product_code in ('apqp', 'ppap', 'rmp', 'mmd', 'mnt', 'mom', 'cad', 'hrms') and console.qp_member(l.customer_id, em, l.product_code))
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
