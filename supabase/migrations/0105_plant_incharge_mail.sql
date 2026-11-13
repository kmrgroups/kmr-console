-- 0105 — each plant (and company) has its own "in-charge" name, e-mail and phone; the footer and reply-to of its notification mails use them
-- (no longer the main company's contact copied when the plant was created). Needs 0101. Safe to re-run.
alter table console.customers add column if not exists incharge_name text;
alter table console.customers add column if not exists incharge_email text;
alter table console.customers add column if not exists incharge_phone text;
create or replace function console.cal_brand(p_customer uuid) returns jsonb language sql stable security definer set search_path = console, public as $$
  select jsonb_build_object(
    'name', coalesce(par.name, c.name),
    'plant', case when par.id is not null then coalesce(nullif(c.plant_code, ''), '') || case when nullif(c.plant_code, '') is not null and nullif(c.name, '') is not null then ' · ' else '' end || coalesce(nullif(trim(split_part(c.name, ' – ', 2)), ''), c.name) else null end,
    'logo', coalesce(nullif(c.logo_url, ''), nullif(par.logo_url, ''), ''),
    'address', concat_ws(', ', nullif(c.address, ''), nullif(c.city, ''), nullif(c.state, ''), nullif(c.postal_code, '')),
    'incharge', case when par.id is not null then coalesce(c.incharge_name, '') else coalesce(nullif(c.incharge_name, ''), c.contact_name, '') end,
    'email',    case when par.id is not null then coalesce(c.incharge_email, '') else coalesce(nullif(c.incharge_email, ''), c.contact_email, '') end,
    'phone',    case when par.id is not null then coalesce(c.incharge_phone, '') else coalesce(nullif(c.incharge_phone, ''), c.contact_phone, '') end)
  from console.customers c left join console.customers par on par.id = c.parent_id where c.id = p_customer;
$$;
revoke all on function console.cal_brand(uuid) from public, anon, authenticated;
