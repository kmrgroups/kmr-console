-- Calibration Hub 0126 — the due-date mail skips every gauge whose calibration has already started, i.e. the gauge is on a Delivery Challan (DC):
--   • an issued / part-returned returnable DC (the gauge is out, or on its way back) — any age, until the GRN closes the challan
--   • a draft DC made in the last 30 days (the challan is being prepared, so the process has started)
-- Cancelled and closed challans do not count (a closed one means the gauge came back and its due date was already updated on the GRN).
-- This also covers gauges whose status is still 'In use' (ERP-imported challans, status changed by hand). Needs 0115 + 0113. Safe to re-run.
create index if not exists dcg_dcl_inst on console.dcg_dc_lines (instrument_id) where instrument_id is not null;
create or replace function public.kmr_cal_due_scan() returns jsonb language plpgsql security definer set search_path = console, public as $$
declare d0 date := (now() at time zone 'Asia/Kolkata')::date; res jsonb := '[]'; s record; rws jsonb; rcp text[];
begin
  for s in select a.customer_id, a.days_before, a.recipients, a.include_users, c.slug, c.name as company
             from console.cal_alert_settings a join console.customers c on c.id = a.customer_id where a.enabled loop
    if not coalesce((select ok from console.access_state('calib', s.customer_id)), false) then continue; end if;
    select jsonb_agg(jsonb_build_object('id', i.id, 'tag', i.tag, 'name', i.name, 'gauge_class', i.gauge_class, 'department', i.department, 'location', i.location, 'supplier', i.supplier,
                                        'next_due', i.next_due, 'days_left', i.next_due - d0) order by i.next_due, i.tag)
      into rws
      from console.cal_instruments i
     where i.customer_id = s.customer_id and i.status = 'In use' and i.next_due is not null and i.next_due >= d0 and i.next_due <= d0 + s.days_before
       and not exists (
         select 1 from console.dcg_dc_lines l join console.dcg_dc d on d.id = l.dc_id
          where l.instrument_id = i.id and d.customer_id = s.customer_id and d.kind = 'returnable'
            and (d.status in ('issued', 'part_returned') or (d.status = 'draft' and d.dc_date >= d0 - 30)));
    continue when rws is null;
    select coalesce(array_agg(distinct z.e), '{}') into rcp from (
      select lower(trim(x)) as e from regexp_split_to_table(coalesce(s.recipients, ''), '[,;[:space:]]+') as x
      union
      select m.email as e from console.customer_members m where s.include_users and m.customer_id = s.customer_id and (m.is_admin or coalesce(m.roles ->> 'calib', '') <> '')) z
     where z.e ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]{2,}$';
    continue when coalesce(array_length(rcp, 1), 0) = 0;
    res := res || jsonb_build_array(jsonb_build_object('customer_id', s.customer_id, 'slug', s.slug, 'company', s.company, 'brand', console.cal_brand(s.customer_id), 'days_before', s.days_before, 'recipients', to_jsonb(rcp), 'rows', rws));
  end loop;
  return res;
end $$;
revoke all on function public.kmr_cal_due_scan() from public, anon, authenticated;
grant execute on function public.kmr_cal_due_scan() to service_role;
