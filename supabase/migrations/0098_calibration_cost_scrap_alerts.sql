-- Calibration Hub 0098 — calibration cost, scrap list, Variable / Attribute gauges, supplier name, and the "due soon" e-mail alert.
-- Needs 0037, 0038, 0039, 0040, 0042, 0043. Safe to re-run.
--   * calibration cost per calibration record (cal_records.cost)
--   * a gauge can be moved to the Scrap list at calibration (or later) and restored from it; scrapped gauges leave the regular lists
--   * every gauge is Variable (gives a reading: vernier, micrometer, dial …) or Attribute (go / no-go: plug, ring, pin, thread …), worked out from its type and editable
--   * supplier name on the gauge
--   * e-mail alert: gauges that will become overdue within N days (default 12, editable per company / plant) are mailed once, each morning, to the chosen people

alter table console.cal_records add column if not exists cost numeric(12,2);
alter table console.cal_instruments add column if not exists supplier text;
alter table console.cal_instruments add column if not exists gauge_class text;
alter table console.cal_instruments add column if not exists scrapped_on date;
alter table console.cal_instruments add column if not exists scrap_reason text;
alter table console.cal_instruments add column if not exists scrapped_by text;
alter table console.cal_instruments add column if not exists alert_sent_due date;     -- the due date already mailed about, so a gauge is mailed once per due date

-- ---------- Variable / Attribute ----------
create or replace function console.cal_class(t text) returns text language sql immutable as $$
  select case when coalesce(t, '') ~* '(^|[^a-z])(plug|ring|pin|thread|snap|limit|feeler|radius|template|go|no[ -]?go)([^a-z]|$)' then 'Attribute' else 'Variable' end $$;
create or replace function console.cal_class_trg() returns trigger language plpgsql as $$
begin
  if tg_op = 'INSERT' then
    if coalesce(new.gauge_class, '') = '' then new.gauge_class := console.cal_class(new.itype); end if;
  elsif coalesce(new.gauge_class, '') = '' or (new.itype is distinct from old.itype and new.gauge_class is not distinct from old.gauge_class) then
    new.gauge_class := console.cal_class(new.itype);
  end if;
  return new;
end $$;
drop trigger if exists cal_class_trg on console.cal_instruments;
create trigger cal_class_trg before insert or update on console.cal_instruments for each row execute function console.cal_class_trg();
update console.cal_instruments set gauge_class = console.cal_class(itype) where coalesce(gauge_class, '') = '';
alter table console.cal_instruments drop constraint if exists cal_instruments_class_chk;
alter table console.cal_instruments add constraint cal_instruments_class_chk check (gauge_class in ('Variable', 'Attribute'));
-- gauges already marked Scrapped before this version get a scrap date
update console.cal_instruments set scrapped_on = coalesce(last_cal, created_at::date) where status = 'Scrapped' and scrapped_on is null;

-- ---------- gauge save: supplier, Variable / Attribute, scrap date ----------
create or replace function public.kmr_cal_save_instrument(p_slug text, p jsonb) returns uuid language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.cal_edit(p_slug); rid uuid; stt text := coalesce(nullif(p ->> 'status', ''), 'In use');
begin
  if length(trim(coalesce(p ->> 'tag', ''))) = 0 or length(trim(coalesce(p ->> 'name', ''))) = 0 then raise exception 'Tag / ID and description are required.'; end if;
  if coalesce(p ->> 'gauge_class', '') not in ('', 'Variable', 'Attribute') then raise exception 'Gauge class must be Variable or Attribute.'; end if;
  if nullif(p ->> 'id', '') is not null then
    update console.cal_instruments set tag = trim(p ->> 'tag'), name = trim(p ->> 'name'), itype = p ->> 'itype', make = p ->> 'make', model = p ->> 'model', serial_no = p ->> 'serial_no',
      range_text = p ->> 'range_text', least_count = p ->> 'least_count', location = p ->> 'location', department = p ->> 'department', custodian = p ->> 'custodian',
      criticality = coalesce(nullif(p ->> 'criticality', ''), 'Major'), cal_source = coalesce(nullif(p ->> 'cal_source', ''), 'External'), lab = p ->> 'lab',
      freq_months = coalesce(nullif(p ->> 'freq_months', '')::int, 12), tolerance = p ->> 'tolerance', status = stt, notes = p ->> 'notes',
      supplier = nullif(trim(coalesce(p ->> 'supplier', '')), ''), gauge_class = coalesce(nullif(p ->> 'gauge_class', ''), gauge_class),
      scrapped_on = case when stt = 'Scrapped' then coalesce(scrapped_on, current_date) else null end,
      last_cal = nullif(p ->> 'last_cal', '')::date, next_due = coalesce(nullif(p ->> 'next_due', '')::date, case when nullif(p ->> 'last_cal', '') is not null then (p ->> 'last_cal')::date + (coalesce(nullif(p ->> 'freq_months', '')::int, 12) || ' months')::interval end)
     where id = (p ->> 'id')::uuid and customer_id = cid returning id into rid;
  else
    insert into console.cal_instruments (customer_id, tag, name, itype, make, model, serial_no, range_text, least_count, location, department, custodian, criticality, cal_source, lab, freq_months, tolerance, notes, last_cal, next_due, supplier, gauge_class)
    values (cid, trim(p ->> 'tag'), trim(p ->> 'name'), p ->> 'itype', p ->> 'make', p ->> 'model', p ->> 'serial_no', p ->> 'range_text', p ->> 'least_count', p ->> 'location', p ->> 'department',
      p ->> 'custodian', coalesce(nullif(p ->> 'criticality', ''), 'Major'), coalesce(nullif(p ->> 'cal_source', ''), 'External'), p ->> 'lab', coalesce(nullif(p ->> 'freq_months', '')::int, 12), p ->> 'tolerance', p ->> 'notes', nullif(p ->> 'last_cal', '')::date,
      coalesce(nullif(p ->> 'next_due', '')::date, case when nullif(p ->> 'last_cal', '') is not null then (p ->> 'last_cal')::date + (coalesce(nullif(p ->> 'freq_months', '')::int, 12) || ' months')::interval end),
      nullif(trim(coalesce(p ->> 'supplier', '')), ''), nullif(p ->> 'gauge_class', ''))
    returning id into rid;
  end if;
  return rid;
exception when unique_violation then raise exception 'An instrument with this tag / ID already exists.';
end $$;

-- ---------- Excel / CSV import and Operations Master sync: supplier and class too ----------
create or replace function public.kmr_cal_import(p_slug text, p_rows jsonb) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.cal_edit(p_slug); r jsonb; ins int := 0; upd int := 0; fm int; lc date; nd date; ex uuid; gc text;
begin
  for r in select * from jsonb_array_elements(p_rows) loop
    continue when length(trim(coalesce(r ->> 'tag', ''))) = 0 or length(trim(coalesce(r ->> 'name', ''))) = 0;
    fm := coalesce(nullif(r ->> 'freq_months', '')::int, 12); lc := nullif(r ->> 'last_cal', '')::date;
    nd := coalesce(nullif(r ->> 'next_due', '')::date, case when lc is not null then lc + (fm || ' months')::interval end);
    gc := case when r ->> 'gauge_class' in ('Variable', 'Attribute') then r ->> 'gauge_class' end;
    select id into ex from console.cal_instruments where customer_id = cid and tag = trim(r ->> 'tag');
    if ex is null then
      insert into console.cal_instruments (customer_id, tag, name, itype, make, model, serial_no, range_text, least_count, tolerance, department, location, custodian, criticality, cal_source, lab, freq_months, last_cal, next_due, supplier, gauge_class)
      values (cid, trim(r ->> 'tag'), trim(r ->> 'name'), r ->> 'itype', r ->> 'make', r ->> 'model', r ->> 'serial_no', r ->> 'range_text', r ->> 'least_count', r ->> 'tolerance', r ->> 'department', r ->> 'location',
              r ->> 'custodian', coalesce(nullif(r ->> 'criticality', ''), 'Major'), coalesce(nullif(r ->> 'cal_source', ''), 'External'), r ->> 'lab', fm, lc, nd, nullif(trim(coalesce(r ->> 'supplier', '')), ''), gc);
      ins := ins + 1;
    else
      update console.cal_instruments set name = trim(r ->> 'name'), itype = coalesce(r ->> 'itype', itype), make = coalesce(r ->> 'make', make), model = coalesce(r ->> 'model', model), serial_no = coalesce(r ->> 'serial_no', serial_no),
        range_text = coalesce(r ->> 'range_text', range_text), least_count = coalesce(r ->> 'least_count', least_count), tolerance = coalesce(r ->> 'tolerance', tolerance), department = coalesce(r ->> 'department', department),
        location = coalesce(r ->> 'location', location), custodian = coalesce(r ->> 'custodian', custodian), lab = coalesce(r ->> 'lab', lab), freq_months = fm, last_cal = coalesce(lc, last_cal), next_due = coalesce(nd, next_due),
        supplier = coalesce(nullif(trim(coalesce(r ->> 'supplier', '')), ''), supplier), gauge_class = coalesce(gc, gauge_class)
       where id = ex;
      upd := upd + 1;
    end if;
  end loop;
  return jsonb_build_object('inserted', ins, 'updated', upd);
end $$;
grant execute on function public.kmr_cal_import(text, jsonb) to authenticated;

-- ---------- scrap ----------
create or replace function console.cal_do_scrap(p_inst uuid, p_cid uuid, p_date date, p_reason text, p_by text) returns void language plpgsql security definer set search_path = console, public as $$
begin
  update console.cal_instruments set status = 'Scrapped', scrapped_on = coalesce(p_date, current_date), scrap_reason = nullif(trim(coalesce(p_reason, '')), ''), scrapped_by = p_by where id = p_inst and customer_id = p_cid;
  insert into console.cal_events (customer_id, instrument_id, ev_date, ev_type, detail, by_email)
  values (p_cid, p_inst, coalesce(p_date, current_date), 'Scrapped', coalesce(nullif(trim(coalesce(p_reason, '')), ''), 'Moved to the scrap list'), p_by);
end $$;
revoke all on function console.cal_do_scrap(uuid, uuid, date, text, text) from public, anon, authenticated;

-- scrap a gauge from the lists / gauge card: p = {date?, reason?}
create or replace function public.kmr_cal_scrap(p_slug text, p_id uuid, p jsonb) returns text language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.cal_edit(p_slug); me text := lower(coalesce(auth.jwt() ->> 'email', ''));
begin
  if not exists (select 1 from console.cal_instruments where id = p_id and customer_id = cid) then raise exception 'Unknown instrument.'; end if;
  perform console.cal_do_scrap(p_id, cid, nullif(p ->> 'date', '')::date, p ->> 'reason', me);
  return 'ok';
end $$;
-- bring a scrapped gauge back to the regular list (status In use)
create or replace function public.kmr_cal_restore(p_slug text, p_id uuid) returns text language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.cal_edit(p_slug); me text := lower(coalesce(auth.jwt() ->> 'email', ''));
begin
  update console.cal_instruments set status = 'In use', scrapped_on = null, scrap_reason = null, scrapped_by = null where id = p_id and customer_id = cid and status = 'Scrapped';
  if not found then raise exception 'This gauge is not in the scrap list.'; end if;
  insert into console.cal_events (customer_id, instrument_id, ev_type, detail, by_email) values (cid, p_id, 'Restored from scrap', 'Moved back to the regular list', me);
  return 'ok';
end $$;

-- ---------- calibration record: cost + optional "move this gauge to scrap" ----------
-- p = {instrument_id, cal_date, next_due?, kind, lab, accreditation, cert_no, as_found_ok, result, max_error, uncertainty, temp_c, humidity, calibrator, remarks, cost?, scrap?, scrap_reason?}
create or replace function public.kmr_cal_save_record(p_slug text, p jsonb) returns uuid language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.cal_edit(p_slug); i console.cal_instruments; rid uuid; nd date; me text := lower(coalesce(auth.jwt() ->> 'email', '')); lg date;
  cst numeric := nullif(trim(coalesce(p ->> 'cost', '')), '')::numeric; sc boolean := coalesce(p ->> 'scrap', '') in ('true', 't', '1', 'yes');
begin
  select * into i from console.cal_instruments where id = (p ->> 'instrument_id')::uuid and customer_id = cid;
  if i.id is null then raise exception 'Unknown instrument.'; end if;
  if coalesce(p ->> 'cal_date', '') = '' then raise exception 'Choose the calibration date.'; end if;
  if cst is not null and cst < 0 then raise exception 'Calibration cost cannot be negative.'; end if;
  nd := coalesce(nullif(p ->> 'next_due', '')::date, (p ->> 'cal_date')::date + (i.freq_months || ' months')::interval);
  select max(cal_date) into lg from console.cal_records where instrument_id = i.id and as_found_ok is not false and result = 'Pass';
  insert into console.cal_records (customer_id, instrument_id, cal_date, next_due, kind, lab, accreditation, cert_no, as_found_ok, result, max_error, uncertainty, temp_c, humidity, calibrator, remarks, created_by, cost)
  values (cid, i.id, (p ->> 'cal_date')::date, nd, coalesce(p ->> 'kind', i.cal_source), p ->> 'lab', p ->> 'accreditation', p ->> 'cert_no', (nullif(p ->> 'as_found_ok', ''))::boolean,
    coalesce(nullif(p ->> 'result', ''), 'Pass'), p ->> 'max_error', p ->> 'uncertainty', nullif(p ->> 'temp_c', '')::numeric, nullif(p ->> 'humidity', '')::numeric, p ->> 'calibrator', p ->> 'remarks', me, cst)
  returning id into rid;
  if coalesce(p ->> 'result', 'Pass') = 'Fail' then
    update console.cal_instruments set status = 'Quarantine' where id = i.id;
  else
    update console.cal_instruments set last_cal = (p ->> 'cal_date')::date, next_due = nd, status = case when status in ('Quarantine','Out of service') then 'In use' else status end where id = i.id;
  end if;
  if (p ->> 'as_found_ok') = 'false' then
    insert into console.cal_oot (customer_id, instrument_id, record_id, summary, last_good, risk, status)
    values (cid, i.id, rid, 'As-found out of tolerance at calibration on ' || (p ->> 'cal_date') || coalesce(' (max error ' || (p ->> 'max_error') || ')', ''), lg, 'High', 'Open');
  end if;
  if sc then
    perform console.cal_do_scrap(i.id, cid, (p ->> 'cal_date')::date, coalesce(nullif(trim(coalesce(p ->> 'scrap_reason', '')), ''), nullif(trim(coalesce(p ->> 'remarks', '')), ''), 'Scrapped at calibration'), me);
  end if;
  return rid;
end $$;

create or replace function public.kmr_cal_update_record(p_slug text, p_id uuid, p jsonb) returns text language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.cal_edit(p_slug); iid uuid; cst numeric := nullif(trim(coalesce(p ->> 'cost', '')), '')::numeric;
begin
  if cst is not null and cst < 0 then raise exception 'Calibration cost cannot be negative.'; end if;
  update console.cal_records set cal_date = (p ->> 'cal_date')::date, next_due = coalesce(nullif(p ->> 'next_due', '')::date, next_due), kind = p ->> 'kind', lab = p ->> 'lab', accreditation = p ->> 'accreditation',
    cert_no = p ->> 'cert_no', as_found_ok = (nullif(p ->> 'as_found_ok', ''))::boolean, result = coalesce(nullif(p ->> 'result', ''), 'Pass'), max_error = p ->> 'max_error', uncertainty = p ->> 'uncertainty',
    temp_c = nullif(p ->> 'temp_c', '')::numeric, humidity = nullif(p ->> 'humidity', '')::numeric, calibrator = p ->> 'calibrator', remarks = p ->> 'remarks', cost = cst
   where id = p_id and customer_id = cid returning instrument_id into iid;
  if iid is not null then perform console.cal_refresh(iid); end if;
  return 'ok';
end $$;

-- ---------- due-soon e-mail alert: settings ----------
create table if not exists console.cal_alert_settings (
  customer_id uuid primary key references console.customers(id) on delete cascade,
  enabled boolean not null default false,
  days_before int not null default 12 check (days_before between 1 and 365),
  recipients text not null default '',
  include_users boolean not null default false,
  updated_at timestamptz not null default now(), updated_by text);
alter table console.cal_alert_settings enable row level security;
drop policy if exists cal_alert_settings_staff on console.cal_alert_settings;
create policy cal_alert_settings_staff on console.cal_alert_settings for all to authenticated using (console.is_staff()) with check (console.is_staff());

create or replace function public.kmr_cal_alert_get(p_slug text) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid; s console.cal_alert_settings;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or console.cal_role(cid) is null then raise exception 'You have no access to Calibration Hub.'; end if;
  select * into s from console.cal_alert_settings where customer_id = cid;
  return jsonb_build_object('enabled', coalesce(s.enabled, false), 'days_before', coalesce(s.days_before, 12), 'recipients', coalesce(s.recipients, ''), 'include_users', coalesce(s.include_users, false),
    'users', coalesce((select jsonb_agg(m.email order by m.email) from console.customer_members m where m.customer_id = cid and m.email is not null and (m.is_admin or coalesce(m.roles ->> 'calib', '') <> '')), '[]'),
    'me', lower(coalesce(auth.jwt() ->> 'email', '')));
end $$;
create or replace function public.kmr_cal_alert_save(p_slug text, p jsonb) returns text language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.cal_edit(p_slug); d int := coalesce(nullif(p ->> 'days_before', '')::int, 12); en boolean := coalesce(p ->> 'enabled', '') in ('true', 't', '1');
  iu boolean := coalesce(p ->> 'include_users', '') in ('true', 't', '1'); rc text := lower(trim(coalesce(p ->> 'recipients', '')));
begin
  if d < 1 or d > 365 then raise exception 'Days before due must be between 1 and 365.'; end if;
  if en and rc = '' and not iu then raise exception 'Add at least one e-mail address, or tick "all Calibration Hub users".'; end if;
  insert into console.cal_alert_settings (customer_id, enabled, days_before, recipients, include_users, updated_at, updated_by)
  values (cid, en, d, rc, iu, now(), lower(coalesce(auth.jwt() ->> 'email', '')))
  on conflict (customer_id) do update set enabled = excluded.enabled, days_before = excluded.days_before, recipients = excluded.recipients, include_users = excluded.include_users, updated_at = now(), updated_by = excluded.updated_by;
  return 'ok';
end $$;

-- ---------- due-soon e-mail alert: used by the daily job (service role only) ----------
-- Returns, per company / plant with the alert on, the gauges whose next due date is within the chosen number of days (and not yet overdue) that have not been mailed for that due date yet.
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
       and i.alert_sent_due is distinct from i.next_due;
    continue when rws is null;
    select coalesce(array_agg(distinct z.e), '{}') into rcp from (
      select lower(trim(x)) as e from regexp_split_to_table(coalesce(s.recipients, ''), '[,;[:space:]]+') as x
      union
      select m.email as e from console.customer_members m where s.include_users and m.customer_id = s.customer_id and (m.is_admin or coalesce(m.roles ->> 'calib', '') <> '')) z
     where z.e ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]{2,}$';
    continue when coalesce(array_length(rcp, 1), 0) = 0;
    res := res || jsonb_build_array(jsonb_build_object('customer_id', s.customer_id, 'slug', s.slug, 'company', s.company, 'days_before', s.days_before, 'recipients', to_jsonb(rcp), 'rows', rws));
  end loop;
  return res;
end $$;
-- after the mail went out, remember the due date mailed for each gauge
create or replace function public.kmr_cal_due_mark(p_ids jsonb) returns integer language plpgsql security definer set search_path = console, public as $$
declare n int;
begin
  update console.cal_instruments set alert_sent_due = next_due where id in (select value::uuid from jsonb_array_elements_text(p_ids));
  get diagnostics n = row_count; return n;
end $$;
revoke all on function public.kmr_cal_due_scan(), public.kmr_cal_due_mark(jsonb) from public, anon, authenticated;
grant execute on function public.kmr_cal_due_scan(), public.kmr_cal_due_mark(jsonb) to service_role;

do $$ declare f text; begin foreach f in array array['kmr_cal_save_instrument(text,jsonb)','kmr_cal_save_record(text,jsonb)','kmr_cal_update_record(text,uuid,jsonb)','kmr_cal_scrap(text,uuid,jsonb)','kmr_cal_restore(text,uuid)','kmr_cal_alert_get(text)','kmr_cal_alert_save(text,jsonb)'] loop
  execute format('grant execute on function public.%s to authenticated', f); end loop; end $$;
