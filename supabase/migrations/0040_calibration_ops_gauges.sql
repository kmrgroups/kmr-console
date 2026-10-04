-- Calibration Hub 0040 — instruments saved with last calibration / next due (auto-calculated from the frequency), and gauges read from the Operations Master. Needs 0037, 0015. Safe to re-run.
create or replace function public.kmr_cal_save_instrument(p_slug text, p jsonb) returns uuid language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.cal_edit(p_slug); rid uuid;
begin
  if length(trim(coalesce(p ->> 'tag', ''))) = 0 or length(trim(coalesce(p ->> 'name', ''))) = 0 then raise exception 'Tag / ID and description are required.'; end if;
  if nullif(p ->> 'id', '') is not null then
    update console.cal_instruments set tag = trim(p ->> 'tag'), name = trim(p ->> 'name'), itype = p ->> 'itype', make = p ->> 'make', model = p ->> 'model', serial_no = p ->> 'serial_no',
      range_text = p ->> 'range_text', least_count = p ->> 'least_count', location = p ->> 'location', department = p ->> 'department', custodian = p ->> 'custodian',
      criticality = coalesce(nullif(p ->> 'criticality', ''), 'Major'), cal_source = coalesce(nullif(p ->> 'cal_source', ''), 'External'), lab = p ->> 'lab',
      freq_months = coalesce(nullif(p ->> 'freq_months', '')::int, 12), tolerance = p ->> 'tolerance', status = coalesce(nullif(p ->> 'status', ''), 'In use'), notes = p ->> 'notes',
      last_cal = nullif(p ->> 'last_cal', '')::date, next_due = coalesce(nullif(p ->> 'next_due', '')::date, case when nullif(p ->> 'last_cal', '') is not null then (p ->> 'last_cal')::date + (coalesce(nullif(p ->> 'freq_months', '')::int, 12) || ' months')::interval end)
     where id = (p ->> 'id')::uuid and customer_id = cid returning id into rid;
  else
    insert into console.cal_instruments (customer_id, tag, name, itype, make, model, serial_no, range_text, least_count, location, department, custodian, criticality, cal_source, lab, freq_months, tolerance, notes, last_cal, next_due)
    values (cid, trim(p ->> 'tag'), trim(p ->> 'name'), p ->> 'itype', p ->> 'make', p ->> 'model', p ->> 'serial_no', p ->> 'range_text', p ->> 'least_count', p ->> 'location', p ->> 'department',
      p ->> 'custodian', coalesce(nullif(p ->> 'criticality', ''), 'Major'), coalesce(nullif(p ->> 'cal_source', ''), 'External'), p ->> 'lab', coalesce(nullif(p ->> 'freq_months', '')::int, 12), p ->> 'tolerance', p ->> 'notes', nullif(p ->> 'last_cal', '')::date,
      coalesce(nullif(p ->> 'next_due', '')::date, case when nullif(p ->> 'last_cal', '') is not null then (p ->> 'last_cal')::date + (coalesce(nullif(p ->> 'freq_months', '')::int, 12) || ' months')::interval end))
    returning id into rid;
  end if;
  return rid;
exception when unique_violation then raise exception 'An instrument with this tag / ID already exists.';
end $$;

create or replace function public.kmr_cal_ops_gauges(p_slug text) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or console.cal_role(cid) is null then raise exception 'You have no access to Calibration Hub.'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('tag', g.code, 'name', g.name, 'itype', g.data ->> 'type', 'make', g.data ->> 'make', 'range_text', g.data ->> 'range', 'least_count', g.data ->> 'least_count',
      'location', g.data ->> 'location', 'department', g.data ->> 'department', 'freq_months', nullif(substring(coalesce(g.data ->> 'cal_freq_months', '') from '[0-9]+'), '')::int,
      'last_cal', case when coalesce(g.data ->> 'last_calibrated', '') ~ '^\d{4}-\d{2}-\d{2}' then left(g.data ->> 'last_calibrated', 10) end,
      'next_due', case when coalesce(g.data ->> 'next_due', '') ~ '^\d{4}-\d{2}-\d{2}' then left(g.data ->> 'next_due', 10) end,
      'added', exists (select 1 from console.cal_instruments i where i.customer_id = cid and i.tag = g.code)) order by g.code)
    from console.ops_records g where g.customer_id = cid and g.kind = 'gauges' and g.active), '[]');
end $$;
grant execute on function public.kmr_cal_save_instrument(text, jsonb) to authenticated;
grant execute on function public.kmr_cal_ops_gauges(text) to authenticated;
