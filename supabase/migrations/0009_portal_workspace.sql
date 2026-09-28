-- =====================================================================
-- KMR Console — tools opened from a customer's KMR Apps page show ONLY that customer's workspace.
-- (An email that also belongs to other workspaces — e.g. KMR's own — does not see them there.)
-- Safe to re-run.
-- =====================================================================
create or replace function public.kmr_portal_workspace(p_slug text, p_product text) returns uuid
language sql stable security definer set search_path = console, public as $$
  select l.product_ref
    from console.customers c
    join console.licences l on l.customer_id = c.id and l.product_code = p_product
   where c.slug = lower(p_slug)
     and exists (select 1 from public.kmr_portal(p_slug))      -- the caller belongs to this customer
$$;
revoke all on function public.kmr_portal_workspace(text, text) from public, anon;
grant execute on function public.kmr_portal_workspace(text, text) to authenticated;
