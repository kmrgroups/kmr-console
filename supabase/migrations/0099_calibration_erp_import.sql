-- Calibration Hub 0099 — import a plant's full gauge register from its ERP: every gauge with its status, supplier and its whole calibration history (history card), with lab, certificate and cost. Needs 0098. Safe to re-run (a calibration already there for the same gauge and date is not added twice).
-- p_rows = [{tag, name, itype, make, serial_no, range_text, least_count, location, freq_months, lab, supplier, status, scrapped_on, scrap_reason, notes, last_cal, next_due,
--            history:[{cal_date, next_due, kind, lab, cert_no, cost, remarks}]}]
create or replace function public.kmr_cal_import_erp(p_slug text, p_rows jsonb) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.cal_edit(p_slug); r jsonb; h jsonb; iid uuid; ins int := 0; upd int := 0; recs int := 0; fm int; lc date; nd date; st text; scd date; cd date;
begin
  for r in select * from jsonb_array_elements(p_rows) loop
    continue when length(trim(coalesce(r ->> 'tag', ''))) = 0 or length(trim(coalesce(r ->> 'name', ''))) = 0;
    fm := coalesce(nullif(r ->> 'freq_months', '')::int, 12); lc := nullif(r ->> 'last_cal', '')::date; nd := nullif(r ->> 'next_due', '')::date;
    st := case when r ->> 'status' in ('In use', 'Out of service', 'Quarantine', 'Scrapped') then r ->> 'status' else 'In use' end;
    scd := case when st = 'Scrapped' then coalesce(nullif(r ->> 'scrapped_on', '')::date, lc, current_date) end;
    select id into iid from console.cal_instruments where customer_id = cid and tag = trim(r ->> 'tag');
    if iid is null then
      insert into console.cal_instruments (customer_id, tag, name, itype, make, serial_no, range_text, least_count, location, cal_source, lab, freq_months, status, last_cal, next_due, supplier, notes, scrapped_on, scrap_reason, scrapped_by)
      values (cid, trim(r ->> 'tag'), trim(r ->> 'name'), r ->> 'itype', r ->> 'make', r ->> 'serial_no', r ->> 'range_text', r ->> 'least_count', r ->> 'location',
              case when coalesce(r ->> 'lab', '') ~* 'in[- ]?house|self' then 'Internal' else 'External' end, r ->> 'lab', greatest(fm, 1), st, lc, coalesce(nd, case when lc is not null then lc + (fm || ' months')::interval end),
              nullif(trim(coalesce(r ->> 'supplier', '')), ''), r ->> 'notes', scd, case when st = 'Scrapped' then coalesce(nullif(r ->> 'scrap_reason', ''), 'Scrapped in ERP') end, case when st = 'Scrapped' then 'ERP import' end)
      returning id into iid;
      ins := ins + 1;
    else
      update console.cal_instruments set name = trim(r ->> 'name'), itype = coalesce(r ->> 'itype', itype), make = coalesce(r ->> 'make', make), serial_no = coalesce(r ->> 'serial_no', serial_no),
        range_text = coalesce(r ->> 'range_text', range_text), least_count = coalesce(r ->> 'least_count', least_count), location = coalesce(r ->> 'location', location), lab = coalesce(r ->> 'lab', lab),
        freq_months = greatest(fm, 1), status = st, last_cal = coalesce(lc, last_cal), next_due = coalesce(nd, next_due), supplier = coalesce(nullif(trim(coalesce(r ->> 'supplier', '')), ''), supplier),
        notes = coalesce(r ->> 'notes', notes), scrapped_on = scd, scrap_reason = case when st = 'Scrapped' then coalesce(nullif(r ->> 'scrap_reason', ''), scrap_reason, 'Scrapped in ERP') end,
        scrapped_by = case when st = 'Scrapped' then coalesce(scrapped_by, 'ERP import') end
       where id = iid;
      upd := upd + 1;
    end if;
    for h in select * from jsonb_array_elements(coalesce(r -> 'history', '[]'::jsonb)) loop
      cd := nullif(h ->> 'cal_date', '')::date;
      continue when cd is null;
      continue when exists (select 1 from console.cal_records where instrument_id = iid and cal_date = cd);
      insert into console.cal_records (customer_id, instrument_id, cal_date, next_due, kind, lab, cert_no, result, remarks, created_by, cost)
      values (cid, iid, cd, nullif(h ->> 'next_due', '')::date, coalesce(nullif(h ->> 'kind', ''), 'External'), h ->> 'lab', h ->> 'cert_no', 'Pass', h ->> 'remarks', 'ERP import', nullif(trim(coalesce(h ->> 'cost', '')), '')::numeric);
      recs := recs + 1;
    end loop;
  end loop;
  return jsonb_build_object('inserted', ins, 'updated', upd, 'calibrations', recs);
end $$;
grant execute on function public.kmr_cal_import_erp(text, jsonb) to authenticated;
