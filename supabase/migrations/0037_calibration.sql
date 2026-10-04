-- Calibration Hub 0037 (lean first version): instrument register, calibration records, gauge history, out-of-tolerance cases.
-- Needs 0011, 0033. Licence product "calib" (one per customer company); roles via Users & access: admin / editor / viewer. Safe to re-run.
create table if not exists console.cal_instruments (
  id uuid primary key default gen_random_uuid(), customer_id uuid not null references console.customers(id) on delete cascade,
  tag text not null, name text not null, itype text, make text, model text, serial_no text, range_text text, least_count text,
  location text, department text, custodian text, criticality text not null default 'Major', cal_source text not null default 'External', lab text,
  freq_months int not null default 12 check (freq_months > 0), tolerance text, status text not null default 'In use', last_cal date, next_due date, notes text,
  created_at timestamptz not null default now(), unique (customer_id, tag));
create table if not exists console.cal_records (
  id uuid primary key default gen_random_uuid(), customer_id uuid not null references console.customers(id) on delete cascade,
  instrument_id uuid not null references console.cal_instruments(id) on delete cascade, cal_date date not null, next_due date, kind text, lab text, accreditation text,
  cert_no text, as_found_ok boolean, result text not null default 'Pass', max_error text, uncertainty text, temp_c numeric, humidity numeric, calibrator text,
  reviewed_by text, reviewed_at timestamptz, remarks text, created_by text, created_at timestamptz not null default now());
create table if not exists console.cal_events (
  id uuid primary key default gen_random_uuid(), customer_id uuid not null references console.customers(id) on delete cascade,
  instrument_id uuid not null references console.cal_instruments(id) on delete cascade, ev_date date not null default current_date, ev_type text not null, detail text, by_email text,
  created_at timestamptz not null default now());
create table if not exists console.cal_oot (
  id uuid primary key default gen_random_uuid(), customer_id uuid not null references console.customers(id) on delete cascade,
  instrument_id uuid not null references console.cal_instruments(id) on delete cascade, record_id uuid, opened_at date not null default current_date, summary text,
  last_good date, risk text, notify text, action text, status text not null default 'Open', closed_at date);
do $$ declare t text; begin foreach t in array array['cal_instruments','cal_records','cal_events','cal_oot'] loop
  execute format('alter table console.%I enable row level security', t);
  execute format('drop policy if exists %I on console.%I', t || '_staff', t);
  execute format('create policy %I on console.%I for all to authenticated using (console.is_staff()) with check (console.is_staff())', t || '_staff', t);
end loop; end $$;

create or replace function console.cal_member(p_customer uuid, p_email text) returns boolean language sql stable security definer set search_path = console, public as $$
  select exists (select 1 from console.customer_members m where m.customer_id = p_customer and m.email = lower(p_email) and (m.is_admin or coalesce(m.roles ->> 'calib', '') <> '')) $$;
create or replace function console.cal_role(p_customer uuid) returns text language sql stable security definer set search_path = console, public as $$
  select case when not coalesce((select ok from console.access_state('calib', p_customer)), false) then null
    when console.is_customer_admin(p_customer) then 'admin'
    else (select nullif(m.roles ->> 'calib', '') from console.customer_members m where m.customer_id = p_customer and m.email = lower(coalesce(auth.jwt() ->> 'email', ''))) end $$;

create or replace function public.kmr_cal_context(p_slug text) returns jsonb language sql stable security definer set search_path = console, public as $$
  select case when console.cal_role(c.id) is null then null else jsonb_build_object('role', console.cal_role(c.id), 'company', c.name) end from console.customers c where c.slug = lower(p_slug) $$;
create or replace function public.kmr_cal_load(p_slug text) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or console.cal_role(cid) is null then raise exception 'You have no access to Calibration Hub.'; end if;
  return jsonb_build_object(
    'instruments', coalesce((select jsonb_agg(to_jsonb(i) - 'customer_id' order by i.tag) from console.cal_instruments i where i.customer_id = cid), '[]'),
    'records', coalesce((select jsonb_agg(to_jsonb(r) - 'customer_id' order by r.cal_date desc) from console.cal_records r where r.customer_id = cid), '[]'),
    'events', coalesce((select jsonb_agg(to_jsonb(e) - 'customer_id' order by e.ev_date desc, e.created_at desc) from console.cal_events e where e.customer_id = cid), '[]'),
    'oot', coalesce((select jsonb_agg(to_jsonb(o) - 'customer_id' order by o.opened_at desc) from console.cal_oot o where o.customer_id = cid), '[]'));
end $$;
create or replace function console.cal_edit(p_slug text) returns uuid language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or coalesce(console.cal_role(cid), '') not in ('admin','editor') then raise exception 'You can view Calibration Hub but not change it. Ask your administrator for editor access.'; end if;
  return cid;
end $$;
-- instrument: p = {id?, tag, name, itype, make, model, serial_no, range_text, least_count, location, department, custodian, criticality, cal_source, lab, freq_months, tolerance, status, notes}
create or replace function public.kmr_cal_save_instrument(p_slug text, p jsonb) returns uuid language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.cal_edit(p_slug); rid uuid;
begin
  if length(trim(coalesce(p ->> 'tag', ''))) = 0 or length(trim(coalesce(p ->> 'name', ''))) = 0 then raise exception 'Tag / ID and description are required.'; end if;
  if nullif(p ->> 'id', '') is not null then
    update console.cal_instruments set tag = trim(p ->> 'tag'), name = trim(p ->> 'name'), itype = p ->> 'itype', make = p ->> 'make', model = p ->> 'model', serial_no = p ->> 'serial_no',
      range_text = p ->> 'range_text', least_count = p ->> 'least_count', location = p ->> 'location', department = p ->> 'department', custodian = p ->> 'custodian',
      criticality = coalesce(nullif(p ->> 'criticality', ''), 'Major'), cal_source = coalesce(nullif(p ->> 'cal_source', ''), 'External'), lab = p ->> 'lab',
      freq_months = coalesce(nullif(p ->> 'freq_months', '')::int, 12), tolerance = p ->> 'tolerance', status = coalesce(nullif(p ->> 'status', ''), 'In use'), notes = p ->> 'notes'
     where id = (p ->> 'id')::uuid and customer_id = cid returning id into rid;
  else
    insert into console.cal_instruments (customer_id, tag, name, itype, make, model, serial_no, range_text, least_count, location, department, custodian, criticality, cal_source, lab, freq_months, tolerance, notes)
    values (cid, trim(p ->> 'tag'), trim(p ->> 'name'), p ->> 'itype', p ->> 'make', p ->> 'model', p ->> 'serial_no', p ->> 'range_text', p ->> 'least_count', p ->> 'location', p ->> 'department',
      p ->> 'custodian', coalesce(nullif(p ->> 'criticality', ''), 'Major'), coalesce(nullif(p ->> 'cal_source', ''), 'External'), p ->> 'lab', coalesce(nullif(p ->> 'freq_months', '')::int, 12), p ->> 'tolerance', p ->> 'notes')
    returning id into rid;
  end if;
  return rid;
exception when unique_violation then raise exception 'An instrument with this tag / ID already exists.';
end $$;
-- calibration: p = {instrument_id, cal_date, next_due?, kind, lab, accreditation, cert_no, as_found_ok, result, max_error, uncertainty, temp_c, humidity, calibrator, remarks}
-- An as-found reading out of tolerance (as_found_ok = false) opens an out-of-tolerance case automatically.
create or replace function public.kmr_cal_save_record(p_slug text, p jsonb) returns uuid language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.cal_edit(p_slug); i console.cal_instruments; rid uuid; nd date; me text := lower(coalesce(auth.jwt() ->> 'email', '')); lg date;
begin
  select * into i from console.cal_instruments where id = (p ->> 'instrument_id')::uuid and customer_id = cid;
  if i.id is null then raise exception 'Unknown instrument.'; end if;
  if coalesce(p ->> 'cal_date', '') = '' then raise exception 'Choose the calibration date.'; end if;
  nd := coalesce(nullif(p ->> 'next_due', '')::date, (p ->> 'cal_date')::date + (i.freq_months || ' months')::interval);
  select max(cal_date) into lg from console.cal_records where instrument_id = i.id and as_found_ok is not false and result = 'Pass';
  insert into console.cal_records (customer_id, instrument_id, cal_date, next_due, kind, lab, accreditation, cert_no, as_found_ok, result, max_error, uncertainty, temp_c, humidity, calibrator, remarks, created_by)
  values (cid, i.id, (p ->> 'cal_date')::date, nd, coalesce(p ->> 'kind', i.cal_source), p ->> 'lab', p ->> 'accreditation', p ->> 'cert_no', (nullif(p ->> 'as_found_ok', ''))::boolean,
    coalesce(nullif(p ->> 'result', ''), 'Pass'), p ->> 'max_error', p ->> 'uncertainty', nullif(p ->> 'temp_c', '')::numeric, nullif(p ->> 'humidity', '')::numeric, p ->> 'calibrator', p ->> 'remarks', me)
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
  return rid;
end $$;
-- history event: p = {instrument_id, ev_type, detail}; a damage report quarantines the instrument
create or replace function public.kmr_cal_event(p_slug text, p jsonb) returns text language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.cal_edit(p_slug); me text := lower(coalesce(auth.jwt() ->> 'email', ''));
begin
  if not exists (select 1 from console.cal_instruments where id = (p ->> 'instrument_id')::uuid and customer_id = cid) then raise exception 'Unknown instrument.'; end if;
  insert into console.cal_events (customer_id, instrument_id, ev_type, detail, by_email) values (cid, (p ->> 'instrument_id')::uuid, coalesce(p ->> 'ev_type', 'Note'), p ->> 'detail', me);
  if p ->> 'ev_type' = 'Damage report' then update console.cal_instruments set status = 'Quarantine' where id = (p ->> 'instrument_id')::uuid; end if;
  if p ->> 'ev_type' = 'Status change' and p ->> 'new_status' is not null then update console.cal_instruments set status = p ->> 'new_status' where id = (p ->> 'instrument_id')::uuid; end if;
  return 'ok';
end $$;
create or replace function public.kmr_cal_close_oot(p_slug text, p_id uuid, p jsonb) returns text language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.cal_edit(p_slug);
begin
  update console.cal_oot set risk = coalesce(p ->> 'risk', risk), notify = p ->> 'notify', action = p ->> 'action', status = coalesce(p ->> 'status', status),
    closed_at = case when p ->> 'status' = 'Closed' then current_date end where id = p_id and customer_id = cid;
  return 'ok';
end $$;
do $$ declare f text; begin foreach f in array array['kmr_cal_context(text)','kmr_cal_load(text)','kmr_cal_save_instrument(text,jsonb)','kmr_cal_save_record(text,jsonb)','kmr_cal_event(text,jsonb)','kmr_cal_close_oot(text,uuid,jsonb)'] loop
  execute format('grant execute on function public.%s to authenticated', f); end loop; end $$;

insert into console.products (code, name, description, app_path, seat_label, current_version, sort_order)
values ('calib', 'Calibration Hub', 'Instrument register, calibration due control, gauge history, out-of-tolerance cases, standards alignment', '/it/calibration.html', 'users', '1.0.0', 60)
on conflict (code) do nothing;
insert into console.releases (product_code, version, notes) values ('calib', '1.0.0', 'Calibration Hub: instrument register, calibration records, gauge history card, OOT cases, standards alignment') on conflict do nothing;

-- ---------- portal: Sales Flow + Calibration Hub cards, access and figures ----------
drop function if exists public.kmr_portal_stats(text);
drop function if exists public.kmr_portal(text);
create or replace function public.kmr_portal(p_slug text)
returns table (product_code text, product_name text, app_path text, purchased boolean, ok boolean, status text,
               valid_until date, message text, customer_name text, logo_url text, product_slug text,
               has_access boolean, is_contact boolean)
language plpgsql stable security definer set search_path = console, public as $$
declare
  em text := lower(coalesce(auth.jwt() ->> 'email', ''));
  uid uuid := auth.uid();
  c console.customers%rowtype;
  member boolean := false;
begin
  select * into c from console.customers where slug = lower(p_slug);
  if c.id is null or em = '' then return; end if;
  select true into member from console.licences l
   where l.customer_id = c.id and (
         (l.product_code = 'balloon'  and exists (select 1 from public.bi_members m where m.org_id = l.product_ref and lower(m.email) = em))
      or (l.product_code = 'pd'       and exists (select 1 from public.pd_members m where m.org_id = l.product_ref and lower(m.email) = em))
      or (l.product_code = 'capacity' and exists (select 1 from public.cp_members m where m.org_id = l.product_ref and m.email = em))
      or (l.product_code = 'sales'    and console.sf_member(l.customer_id, em))
      or (l.product_code = 'calib'    and console.cal_member(l.customer_id, em))
      or (l.product_code = 'hrm'      and exists (select 1 from hrm.app_users u where u.tenant_id = l.product_ref and u.id = uid and u.active)))
   limit 1;
  if not coalesce(member, false) and lower(coalesce(c.contact_email, '')) <> em then return; end if;
  return query
    select p.code, p.name, p.app_path, (l.id is not null), coalesce(a.ok, false), coalesce(a.status, 'not_purchased'),
           l.valid_until, a.message, c.name, c.logo_url, l.product_slug,
           case p.code
             when 'balloon'  then exists (select 1 from public.bi_members m where m.org_id = l.product_ref and lower(m.email) = em)
             when 'pd'       then exists (select 1 from public.pd_members m where m.org_id = l.product_ref and lower(m.email) = em)
             when 'capacity' then exists (select 1 from public.cp_members m where m.org_id = l.product_ref and m.email = em)
             when 'sales'    then console.sf_member(l.customer_id, em)
             when 'calib'    then console.cal_member(l.customer_id, em)
             when 'hrm'      then exists (select 1 from hrm.app_users u where u.tenant_id = l.product_ref and u.id = uid and u.active)
             else false end,
           lower(coalesce(c.contact_email, '')) = em
      from console.products p
      left join console.licences l on l.product_code = p.code and l.customer_id = c.id
      left join lateral console.access_state(p.code, l.product_ref) a on l.id is not null
     where p.active
     order by p.sort_order;
end $$;
revoke all on function public.kmr_portal(text) from public, anon;
grant execute on function public.kmr_portal(text) to authenticated;

create or replace function public.kmr_portal_join(p_slug text, p_product text) returns text
language plpgsql security definer set search_path = console, public as $$
declare em text := lower(coalesce(auth.jwt() ->> 'email', '')); cid uuid; ok boolean;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or em = '' then raise exception 'Unknown company link.'; end if;
  if not exists (select 1 from console.licences where customer_id = cid and product_code = p_product and product_ref is not null) then
    raise exception 'This app is not set up for your company yet. Please contact KMR.';
  end if;
  if console.is_customer_admin(cid) then
    perform console.grant_admins(cid);          -- administrators: admin in every bought tool
  end if;
  perform console.sync_member(cid, em);         -- everyone: whatever Administration › Users & access says
  ok := case p_product
    when 'balloon'  then exists (select 1 from public.bi_members m join console.licences l on l.product_ref = m.org_id and l.product_code = 'balloon' where l.customer_id = cid and lower(m.email) = em)
    when 'pd'       then exists (select 1 from public.pd_members m join console.licences l on l.product_ref = m.org_id and l.product_code = 'pd' where l.customer_id = cid and lower(m.email) = em)
    when 'capacity' then exists (select 1 from public.cp_members m join console.licences l on l.product_ref = m.org_id and l.product_code = 'capacity' where l.customer_id = cid and m.email = em)
    when 'sales'    then console.sf_member(cid, em)
    when 'calib'    then console.cal_member(cid, em)
    when 'hrm'      then exists (select 1 from hrm.app_users u join console.licences l on l.product_ref = u.tenant_id and l.product_code = 'hrm' where l.customer_id = cid and u.id = auth.uid() and u.active)
    else false end;
  if not ok then
    raise exception 'You have not been given access to this app. Your company administrator can add it under KMR Apps › Administration › Users & access.';
  end if;
  return 'ok';
end $$;
revoke all on function public.kmr_portal_join(text, text) from public, anon;
grant execute on function public.kmr_portal_join(text, text) to authenticated;

create or replace function public.kmr_portal_stats(p_slug text) returns jsonb
language plpgsql stable security definer set search_path = console, public as $$
declare c uuid; out jsonb := '{}'; ref uuid; today date := (now() at time zone 'Asia/Kolkata')::date;
begin
  if not exists (select 1 from public.kmr_portal(p_slug)) then return out; end if;
  select id into c from console.customers where slug = lower(p_slug);
  select product_ref into ref from console.licences where customer_id = c and product_code = 'hrm';
  if ref is not null then
    out := out || jsonb_build_object('hrm', jsonb_build_object(
      'Employees', (select count(*) from hrm.employees where tenant_id = ref and status = 'active'),
      'In today', (select count(*) from hrm.attendance_days where tenant_id = ref and work_date = today and status in ('present','half_day','missed_punch')),
      'Awaiting approval', (select count(*) from hrm.leave_requests where tenant_id = ref and status = 'pending')
                          + (select count(*) from hrm.regularisation_requests where tenant_id = ref and status = 'pending')));
  end if;
  select product_ref into ref from console.licences where customer_id = c and product_code = 'balloon';
  if ref is not null then
    out := out || jsonb_build_object('balloon', jsonb_build_object(
      'Reports', (select count(*) from public.bi_reports where org_id = ref),
      'Users', (select count(*) from public.bi_members where org_id = ref)));
  end if;
  select product_ref into ref from console.licences where customer_id = c and product_code = 'pd';
  if ref is not null then
    out := out || jsonb_build_object('pd', jsonb_build_object(
      'Projects', (select count(*) from public.pd_projects where org_id = ref),
      'Users', (select count(*) from public.pd_members where org_id = ref)));
  end if;
  select product_ref into ref from console.licences where customer_id = c and product_code = 'capacity';
  if ref is not null then
    out := out || jsonb_build_object('capacity', jsonb_build_object(
      'Users', (select count(*) from public.cp_members where org_id = ref),
      'Saved versions', (select count(*) from public.cp_history where org_id = ref) + (select count(*) from public.cp_plans where org_id = ref)));
  end if;
  select product_ref into ref from console.licences where customer_id = c and product_code = 'sales';
  if ref is not null then
    out := out || jsonb_build_object('sales', jsonb_build_object(
      'Users', (select count(*) from console.customer_members m where m.customer_id = c and coalesce(m.roles ->> 'sales', '') <> ''),
      'Parts planned', (select count(*) from console.sf_lines where customer_id = c and month = date_trunc('month', today)::date)));
  end if;
  select product_ref into ref from console.licences where customer_id = c and product_code = 'calib';
  if ref is not null then
    out := out || jsonb_build_object('calib', jsonb_build_object(
      'Instruments', (select count(*) from console.cal_instruments where customer_id = c and status = 'In use'),
      'Overdue', (select count(*) from console.cal_instruments where customer_id = c and status = 'In use' and next_due < (now() at time zone 'Asia/Kolkata')::date)));
  end if;
  return out;
end $$;
revoke all on function public.kmr_portal_stats(text) from public, anon;
grant execute on function public.kmr_portal_stats(text) to authenticated;
