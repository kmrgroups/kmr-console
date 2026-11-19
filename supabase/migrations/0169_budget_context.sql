-- KMR 0169 — Budget: context function for the app (role, company, logo).
create or replace function public.kmr_bud_context(p_slug text) returns jsonb language sql stable security definer set search_path = console, public as $$
  select case when console.qp_role(c.id, 'bud') is null then null
    else jsonb_build_object('role', console.qp_role(c.id, 'bud'), 'company', c.name, 'logo_url', c.logo_url, 'is_staff', coalesce(console.is_staff(), false)) end
  from console.customers c where c.slug = lower(p_slug) $$;
grant execute on function public.kmr_bud_context(text) to authenticated;
