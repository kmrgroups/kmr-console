-- 0094 — Daily Work Management: its own sign-in context (role, company, logo), like Layout Studio.
-- The shared kmr_qp_context only answers for the apps in its fixed list, so DWM was refused ("You do not have access to this app").
-- Needs 0091. Safe to re-run.
create or replace function public.kmr_dwm_context(p_slug text) returns jsonb language sql stable security definer set search_path = console, public as $$
  select case when console.qp_role(c.id, 'dwm') is null then null
    else jsonb_build_object('role', console.qp_role(c.id, 'dwm'), 'company', c.name, 'logo_url', c.logo_url, 'is_staff', coalesce(console.is_staff(), false)) end
  from console.customers c where c.slug = lower(p_slug) $$;
revoke all on function public.kmr_dwm_context(text) from public, anon;
grant execute on function public.kmr_dwm_context(text) to authenticated;
