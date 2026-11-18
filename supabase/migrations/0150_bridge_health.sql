-- 0150: bridge health for the dashboard. For every plant that has an active ERP sync key: when the bridge PC last called in,
-- the last result of each kind of data it sends (invoice, material movement, PO/DC/GRN, masters, ops master, calibration),
-- failures in the last 24 hours, and the attendance machines (HRM). Staff only.
create or replace function public.kmr_bridge_health() returns jsonb language sql stable security definer set search_path = console, public as $$
  select case when not coalesce(console.is_staff(), false) then '[]'::jsonb else coalesce((
    select jsonb_agg(p order by p->>'name') from (
      select jsonb_build_object(
        'slug', c.slug, 'name', c.name, 'now', now(), 'unit', c.plant_code, 'code', c.code, 'city', c.city, 'incharge', c.incharge_name, 'phone', c.incharge_phone, 'status', c.status,
        'pc_last_seen', (select max(k.last_seen_at) from console.sf_erp_keys k where k.customer_id = c.id and k.active),
        'kinds', coalesce((select jsonb_agg(jsonb_build_object('kind', x.kind, 'at', x.at, 'ok', x.ok, 'rows', x.rows, 'error', x.summary->>'error',
                   'last_ok', (select max(b2.at) from console.bridge_runs b2 where b2.customer_id = c.id and b2.kind = x.kind and b2.ok),
                   'fails_24h', (select count(*) from console.bridge_runs b3 where b3.customer_id = c.id and b3.kind = x.kind and not b3.ok and b3.at > now() - interval '24 hours')) order by x.kind)
              from (select distinct on (b.kind) b.kind, b.at, b.ok, b.rows, b.summary from console.bridge_runs b where b.customer_id = c.id order by b.kind, b.at desc) x), '[]'::jsonb),
        'devices', coalesce((select jsonb_agg(jsonb_build_object('name', d.name, 'last_seen', d.last_seen, 'last_punch', d.last_punch) order by d.name) from console.hrms_devices d where d.customer_id = c.id), '[]'::jsonb)
      ) p
      from console.customers c
      where coalesce(c.kind, 'customer') <> 'demo' and exists (select 1 from console.sf_erp_keys k where k.customer_id = c.id and k.active)
    ) q), '[]'::jsonb) end $$;
revoke all on function public.kmr_bridge_health() from public, anon;
grant execute on function public.kmr_bridge_health() to authenticated;
