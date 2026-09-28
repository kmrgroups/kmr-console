-- =====================================================================
-- KMR Console — Customer portal ("My KMR Apps").
-- Each customer gets ONE link: www.kmr-groups.com/it/app/<slug>. After signing in, the portal shows the
-- products the customer has bought (from Console licences); the rest can be tried with sample data only.
-- Safe to re-run.
-- =====================================================================
alter table console.customers add column if not exists slug text;
alter table console.customers add column if not exists logo_url text;
update console.customers
   set slug = trim(both '-' from left(regexp_replace(lower(name), '[^a-z0-9]+', '-', 'g'), 40)) || '-' || lower(code)
 where slug is null;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'customers_slug_key') then
    alter table console.customers add constraint customers_slug_key unique (slug);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'customers_slug_format') then
    alter table console.customers add constraint customers_slug_format check (slug ~ '^[a-z0-9][a-z0-9-]{1,60}$');
  end if;
end $$;

create or replace function console.customer_slug() returns trigger
language plpgsql set search_path = console, public as $$
begin
  if new.slug is null or new.slug = '' then
    new.slug := trim(both '-' from left(regexp_replace(lower(new.name), '[^a-z0-9]+', '-', 'g'), 40)) || '-' || lower(new.code);
  end if;
  return new;
end $$;
drop trigger if exists customers_slug on console.customers;
create trigger customers_slug before insert on console.customers for each row execute function console.customer_slug();

-- Public logo bucket for customer logos shown on their portal
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('kmr-public', 'kmr-public', true, 1048576, array['image/png','image/jpeg','image/webp','image/svg+xml'])
on conflict (id) do nothing;

-- Before sign-in: the customer's name and logo for their portal page (nothing else is revealed)
create or replace function public.kmr_portal_brand(p_slug text)
returns table (name text, logo_url text)
language sql stable security definer set search_path = console, public as $$
  select c.name, c.logo_url from console.customers c where c.slug = lower(p_slug) and c.status <> 'inactive'
$$;
revoke all on function public.kmr_portal_brand(text) from public;
grant execute on function public.kmr_portal_brand(text) to anon, authenticated;

-- After sign-in: which products this person's company has (the full version is in 0007_portal_access.sql).
-- Created here only when no version exists yet, so this file is safe to re-run after 0006 / 0007.
do $guard$ begin
  if to_regprocedure('public.kmr_portal(text)') is null then
    execute $fn$create or replace function public.kmr_portal(p_slug text)
returns table (product_code text, product_name text, app_path text, purchased boolean, ok boolean, status text,
               valid_until date, message text, customer_name text, logo_url text)
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
         (l.product_code = 'balloon' and exists (select 1 from public.bi_members m where m.org_id = l.product_ref and lower(m.email) = em))
      or (l.product_code = 'pd'      and exists (select 1 from public.pd_members m where m.org_id = l.product_ref and lower(m.email) = em))
      or (l.product_code = 'hrm'     and exists (select 1 from hrm.app_users u where u.tenant_id = l.product_ref and u.id = uid and u.active)))
   limit 1;
  if not coalesce(member, false) and lower(coalesce(c.contact_email, '')) <> em then return; end if;
  return query
    select p.code, p.name, p.app_path, (l.id is not null), coalesce(a.ok, false), coalesce(a.status, 'not_purchased'),
           l.valid_until, a.message, c.name, c.logo_url
      from console.products p
      left join console.licences l on l.product_code = p.code and l.customer_id = c.id
      left join lateral console.access_state(p.code, l.product_ref) a on l.id is not null
     where p.active
     order by p.sort_order;
end $$;$fn$;
    revoke all on function public.kmr_portal(text) from public, anon;
    grant execute on function public.kmr_portal(text) to authenticated;
  end if;
end $guard$;
