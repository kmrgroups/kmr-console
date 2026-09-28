-- =====================================================================
-- KMR Console — which customer portal(s) the signed-in person belongs to.
-- Lets anyone sign in at www.kmr-groups.com/it/apps.html (or be sent there by a tool) and land on their
-- own company's KMR Apps page. Safe to re-run.
-- =====================================================================
create or replace function public.kmr_my_portals()
returns table (slug text, name text)
language sql stable security definer set search_path = console, public as $$
  select distinct c.slug, c.name
    from console.customers c
   where c.slug is not null and c.status <> 'inactive'
     and exists (select 1 from public.kmr_portal(c.slug))
   order by c.name
$$;
revoke all on function public.kmr_my_portals() from public, anon;
grant execute on function public.kmr_my_portals() to authenticated;
