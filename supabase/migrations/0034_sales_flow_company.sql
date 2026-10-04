-- Sales Flow 0034 — lets /it/sales.html find the signed-in person's company when it is opened without ?co=
-- (e.g. from the KMR Apps card). Needs 0033. Safe to re-run.
create or replace function public.kmr_sf_my_companies() returns jsonb
language sql stable security definer set search_path = console, public as $$
  select coalesce(jsonb_agg(jsonb_build_object('slug', c.slug, 'name', c.name) order by c.name), '[]')
    from console.customers c
   where c.slug is not null and console.sf_role(c.id) is not null
$$;
revoke all on function public.kmr_sf_my_companies() from public, anon;
grant execute on function public.kmr_sf_my_companies() to authenticated;
