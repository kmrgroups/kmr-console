-- KMR 0132 — Profit & Loss is for selected top management only: a company administrator does NOT get it automatically; only people given an access level for it in Users (and KMR staff). Safe to re-run.
create or replace function console.qp_role(p_customer uuid, p_code text) returns text language sql stable security definer set search_path = console, public as $$
  select case when not coalesce((select ok from console.access_state(p_code, p_customer)), false) then null
    when p_code = 'pnl' then (case when console.is_staff() then 'admin'
         else (select nullif(m.roles ->> p_code, '') from console.customer_members m where m.customer_id = p_customer and m.email = lower(coalesce(auth.jwt() ->> 'email', ''))) end)
    when console.is_customer_admin(p_customer) then 'admin'
    else (select nullif(m.roles ->> p_code, '') from console.customer_members m where m.customer_id = p_customer and m.email = lower(coalesce(auth.jwt() ->> 'email', ''))) end $$;
create or replace function console.qp_member(p_customer uuid, p_email text, p_code text) returns boolean language sql stable security definer set search_path = console, public as $$
  select exists (select 1 from console.customer_members m where m.customer_id = p_customer and m.email = lower(p_email) and ((m.is_admin and p_code <> 'pnl') or coalesce(m.roles ->> p_code, '') <> '')) $$;
