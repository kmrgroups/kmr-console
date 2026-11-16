-- Calibration Hub 0127 — the "Send test mail" list now follows the same rule as the real morning mail (0126): gauges already on a Delivery Challan (DC) are left out. Safe to re-run.
create or replace function public.kmr_cal_test_list(p_slug text) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.cal_admin(p_slug); d0 date := (now() at time zone 'Asia/Kolkata')::date; dy int; rws jsonb; cname text;
begin
  select coalesce((select days_before from console.cal_alert_settings where customer_id = cid), 12) into dy;
  select name into cname from console.customers where id = cid;
  select coalesce(jsonb_agg(jsonb_build_object('tag', i.tag, 'name', i.name, 'gauge_class', i.gauge_class, 'department', i.department, 'location', i.location, 'supplier', i.supplier,
                                               'next_due', i.next_due, 'days_left', i.next_due - d0) order by i.next_due, i.tag), '[]')
    into rws from console.cal_instruments i
   where i.customer_id = cid and i.status = 'In use' and i.next_due is not null and i.next_due >= d0 and i.next_due <= d0 + dy
     and not exists (
       select 1 from console.dcg_dc_lines l join console.dcg_dc d on d.id = l.dc_id
        where l.instrument_id = i.id and d.customer_id = cid and d.kind = 'returnable'
          and (d.status in ('issued', 'part_returned') or (d.status = 'draft' and d.dc_date >= d0 - 30)));
  return jsonb_build_object('slug', lower(p_slug), 'company', cname, 'brand', console.cal_brand(cid), 'days_before', dy, 'me', lower(coalesce(auth.jwt() ->> 'email', '')), 'rows', rws);
end $$;
