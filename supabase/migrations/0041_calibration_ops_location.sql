-- Calibration Hub 0041 — gauge location from the Operations Master: a machine code (shown as "code · machine name") or "Gauge room · room no."
-- Operations Master › Gauges fields read: code, name, type, make, model, serial_no, range, least_count, tolerance, location (machine code or "Gauge room"),
-- gauge_room_no (only when location = Gauge room), cal_freq_months, last_calibrated, next_due, department, criticality, lab, custodian. Needs 0040. Safe to re-run.
create or replace function public.kmr_cal_ops_gauges(p_slug text) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or console.cal_role(cid) is null then raise exception 'You have no access to Calibration Hub.'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('tag', g.code, 'name', g.name, 'itype', g.data ->> 'type', 'make', g.data ->> 'make', 'range_text', g.data ->> 'range', 'least_count', g.data ->> 'least_count',
      'location', case when lower(coalesce(g.data ->> 'location', '')) like 'gauge room%' then 'Gauge room' || coalesce(' · ' || nullif(trim(g.data ->> 'gauge_room_no'), ''), '')
                       else coalesce((select m.code || ' · ' || m.name from console.ops_records m where m.customer_id = cid and m.kind = 'machines' and m.code = g.data ->> 'location' limit 1), g.data ->> 'location') end,
      'department', g.data ->> 'department', 'model', g.data ->> 'model', 'serial_no', g.data ->> 'serial_no', 'tolerance', g.data ->> 'tolerance', 'criticality', g.data ->> 'criticality', 'lab', g.data ->> 'lab', 'custodian', g.data ->> 'custodian', 'cal_source', g.data ->> 'cal_source', 'freq_months', nullif(substring(coalesce(g.data ->> 'cal_freq_months', '') from '[0-9]+'), '')::int,
      'last_cal', case when coalesce(g.data ->> 'last_calibrated', '') ~ '^\d{4}-\d{2}-\d{2}' then left(g.data ->> 'last_calibrated', 10) end,
      'next_due', case when coalesce(g.data ->> 'next_due', '') ~ '^\d{4}-\d{2}-\d{2}' then left(g.data ->> 'next_due', 10) end,
      'added', exists (select 1 from console.cal_instruments i where i.customer_id = cid and i.tag = g.code)) order by g.code)
    from console.ops_records g where g.customer_id = cid and g.kind = 'gauges' and g.active), '[]');
end $$;
grant execute on function public.kmr_cal_ops_gauges(text) to authenticated;
