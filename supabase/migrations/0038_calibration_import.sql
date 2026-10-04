-- Calibration Hub 0038 — bulk import of an existing gauge register (upsert by tag). Needs 0037. Safe to re-run.
-- p_rows = [{tag, name, itype, make, model, serial_no, range_text, least_count, tolerance, department, location, custodian, criticality, cal_source, lab, freq_months, last_cal, next_due}]
create or replace function public.kmr_cal_import(p_slug text, p_rows jsonb) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.cal_edit(p_slug); r jsonb; ins int := 0; upd int := 0; fm int; lc date; nd date; ex uuid;
begin
  for r in select * from jsonb_array_elements(p_rows) loop
    continue when length(trim(coalesce(r ->> 'tag', ''))) = 0 or length(trim(coalesce(r ->> 'name', ''))) = 0;
    fm := coalesce(nullif(r ->> 'freq_months', '')::int, 12); lc := nullif(r ->> 'last_cal', '')::date;
    nd := coalesce(nullif(r ->> 'next_due', '')::date, case when lc is not null then lc + (fm || ' months')::interval end);
    select id into ex from console.cal_instruments where customer_id = cid and tag = trim(r ->> 'tag');
    if ex is null then
      insert into console.cal_instruments (customer_id, tag, name, itype, make, model, serial_no, range_text, least_count, tolerance, department, location, custodian, criticality, cal_source, lab, freq_months, last_cal, next_due)
      values (cid, trim(r ->> 'tag'), trim(r ->> 'name'), r ->> 'itype', r ->> 'make', r ->> 'model', r ->> 'serial_no', r ->> 'range_text', r ->> 'least_count', r ->> 'tolerance', r ->> 'department', r ->> 'location',
              r ->> 'custodian', coalesce(nullif(r ->> 'criticality', ''), 'Major'), coalesce(nullif(r ->> 'cal_source', ''), 'External'), r ->> 'lab', fm, lc, nd);
      ins := ins + 1;
    else
      update console.cal_instruments set name = trim(r ->> 'name'), itype = coalesce(r ->> 'itype', itype), make = coalesce(r ->> 'make', make), model = coalesce(r ->> 'model', model), serial_no = coalesce(r ->> 'serial_no', serial_no),
        range_text = coalesce(r ->> 'range_text', range_text), least_count = coalesce(r ->> 'least_count', least_count), tolerance = coalesce(r ->> 'tolerance', tolerance), department = coalesce(r ->> 'department', department),
        location = coalesce(r ->> 'location', location), custodian = coalesce(r ->> 'custodian', custodian), lab = coalesce(r ->> 'lab', lab), freq_months = fm, last_cal = coalesce(lc, last_cal), next_due = coalesce(nd, next_due)
       where id = ex;
      upd := upd + 1;
    end if;
  end loop;
  return jsonb_build_object('inserted', ins, 'updated', upd);
end $$;
grant execute on function public.kmr_cal_import(text, jsonb) to authenticated;
