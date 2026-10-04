-- =====================================================================
-- 0043 — Sales Flow + Calibration Hub join the Data Master, the Grand Master and the sample-data flow.
-- Needs 0031 (sample flow), 0036 (Sales Flow actions), 0039 (Calibration MSA), 0042. Safe to re-run.
--
--  • Sample data, linked to the Operations Master sample (KMR Apps › Grand Master › Sample Data Master › Load):
--      Sales Flow       — last month and this month: one plan line per sample part (customer + price from the
--                         customer's sample rate contract), daily despatch up to yesterday, loss reasons on the
--                         lines that fell short, three action plans.
--      Calibration Hub  — one instrument per Operations Master sample gauge (same ID, location, frequency and dates),
--                         two calibration records each, one damage event, one open out-of-tolerance case, one MSA study.
--    Sample rows carry sample = true; "Flush sample data" removes only them. Real data is never touched.
--  • Data Master (per app): record counts, JSON download, JSON upload (restore) and flush for Sales Flow and
--    Calibration Hub, exactly like the other apps.
--  • Grand Master: real-data counts / download / upload / flush and sample counts include both apps.
-- =====================================================================
do $$ begin
  if to_regclass('console.sf_actions') is null then raise exception 'Run 0036_sales_flow_loss.sql first.'; end if;
  if to_regclass('console.cal_msa') is null then raise exception 'Run 0039_calibration_msa.sql first.'; end if;
  if to_regprocedure('public.kmr_grand_sample(text,text)') is null then raise exception 'Run 0031_sample_flow.sql first.'; end if;
end $$;

alter table console.sf_lines        add column if not exists sample boolean not null default false;
alter table console.sf_actions      add column if not exists sample boolean not null default false;
alter table console.cal_instruments add column if not exists sample boolean not null default false;

-- the tables of each app, parents first (restore order); children of a sample parent are sample too
create or replace function console.app2_tables(p_app text) returns text[] language sql immutable as $$
  select case p_app when 'sales' then array['sf_lines','sf_despatch','sf_actions']
                    when 'calib' then array['cal_instruments','cal_records','cal_events','cal_oot','cal_msa'] end
$$;

-- does the customer have the app (any licence, sample mode included)?
create or replace function console.has_app(p_cid uuid, p_app text) returns boolean language sql stable security definer set search_path = console, public as $$
  select exists (select 1 from console.licences where customer_id = p_cid and product_code = p_app)
$$;
revoke all on function console.has_app(uuid, text), console.app2_tables(text) from public, anon, authenticated;

-- ---------- Sales Flow sample ----------
create or replace function console.sf_sample(p_cid uuid, p_action text) returns integer
language plpgsql security definer set search_path = console, public as $$
declare
  today date := (now() at time zone 'Asia/Kolkata')::date;
  m date; p record; lid uuid; n int := 0; k int := 0; d date; days int; per numeric; f numeric; got numeric; reasons text[] :=
    array['Raw Material Issue','Machine Break Down','Customer No Pull','Manpower Absenteeism','Inspection Delay','Lack of Tool'];
begin
  if p_action = 'flush' then
    delete from console.sf_actions where customer_id = p_cid and sample;
    delete from console.sf_lines where customer_id = p_cid and sample; get diagnostics n = row_count;
    return n;
  end if;
  if exists (select 1 from console.sf_lines where customer_id = p_cid and sample) then return 0; end if;
  foreach m in array array[(date_trunc('month', today) - interval '1 month')::date, date_trunc('month', today)::date] loop
    k := 0;
    for p in
      select pr.code, pr.name, coalesce(pr.data ->> 'customer', '') buyer, coalesce(cu.name, '') buyer_name,
             coalesce(nullif(rc.data ->> 'rate', '')::numeric, 0) rate, coalesce(rc.data ->> 'currency', 'INR') cur, coalesce(rc.data ->> 'uom', 'pcs') uom
        from console.ops_records pr
        left join console.ops_records cu on cu.customer_id = pr.customer_id and cu.kind = 'customers' and cu.code = pr.data ->> 'customer'
        left join lateral (select r.data from console.ops_records r where r.customer_id = pr.customer_id and r.kind = 'rate_contracts'
                             and r.data ->> 'party_type' = 'Customer' and r.data ->> 'item' = pr.code and coalesce(r.data ->> 'rate', '') ~ '^[0-9.]+$'
                           order by r.sample desc limit 1) rc on true
       where pr.customer_id = p_cid and pr.kind = 'parts' and pr.sample and pr.active
       order by pr.code
    loop
      k := k + 1;
      insert into console.sf_lines (customer_id, month, buyer_code, buyer_name, part_code, part_name, price, currency, uom, demand_qty,
                                    sched_type, sched_date, sched_weekday, remarks, updated_by, sample)
      values (p_cid, m, p.buyer, p.buyer_name, p.code, p.name, p.rate, p.cur, p.uom, 300 + (k * 137 % 9) * 100,
              (array['daily','weekly','date'])[1 + k % 3],
              case when k % 3 = 2 then m + 19 end, case when k % 3 = 1 then 1 + k % 6 end, 'Sample plan', 'sample', true)
      on conflict (customer_id, month, part_code, buyer_code) do nothing
      returning id into lid;
      continue when lid is null;
      n := n + 1;
      -- despatch on working days (Mon–Sat) up to yesterday; each part runs at its own fulfilment level
      days := (select count(*) from generate_series(m, (m + interval '1 month - 1 day')::date, '1 day') x where extract(isodow from x) < 7);
      per := (300 + (k * 137 % 9) * 100)::numeric / greatest(days, 1);
      f := (array[1.05, 0.98, 0.92, 0.85, 0.74, 1.0, 0.66])[1 + k % 7];
      for d in select x::date from generate_series(m, least((m + interval '1 month - 1 day')::date, today - 1), '1 day') x where extract(isodow from x) < 7 loop
        insert into console.sf_despatch (line_id, customer_id, day, qty, updated_by)
        values (lid, p_cid, d, greatest(0, round(per * f * (0.8 + ((extract(day from d)::int * 7 + k) % 5) * 0.1))), 'sample')
        on conflict do nothing;
      end loop;
      -- a short line in a finished month gets a loss reason
      if m < date_trunc('month', today)::date and f < 0.9 then
        update console.sf_lines set loss_reason = reasons[1 + k % array_length(reasons, 1)] where id = lid;
      end if;
    end loop;
  end loop;
  -- three action plans on the short lines of last month
  insert into console.sf_actions (customer_id, month, line_id, buyer_name, part_code, part_name, issue, brief, immediate_action, permanent_action,
                                  responsible, target_date, status, created_by, updated_by, sample)
  select p_cid, l.month, l.id, l.buyer_name, l.part_code, l.part_name, l.loss_reason,
         'Despatch short of plan for ' || l.part_name || ' (sample)',
         (array['Arranged material from alternate stock','Shifted the job to a standby machine','Added an overtime shift'])[rn],
         (array['Second source approved for the bar size','Preventive maintenance plan revised','Skill matrix updated; operators cross-trained'])[rn],
         (array['Purchase head','Maintenance head','Production head'])[rn], today + (rn::int) * 7,
         (array['Opened','Under progress','Closed'])[rn], 'sample', 'sample', true
    from (select l.*, row_number() over (order by l.part_code)::int rn from console.sf_lines l
           where l.customer_id = p_cid and l.sample and l.loss_reason is not null) l
   where rn <= 3;
  return n;
end $$;
revoke all on function console.sf_sample(uuid, text) from public, anon, authenticated;

-- ---------- Calibration Hub sample ----------
create or replace function console.cal_sample(p_cid uuid, p_action text) returns integer
language plpgsql security definer set search_path = console, public as $$
declare
  today date := (now() at time zone 'Asia/Kolkata')::date;
  g record; iid uuid; n int := 0; fm int; lc date; first_id uuid; rec uuid;
begin
  if p_action = 'flush' then
    delete from console.cal_instruments where customer_id = p_cid and sample; get diagnostics n = row_count;   -- records, events, OOT and MSA follow
    return n;
  end if;
  if exists (select 1 from console.cal_instruments where customer_id = p_cid and sample) then return 0; end if;
  for g in select * from console.ops_records where customer_id = p_cid and kind = 'gauges' and sample and active order by code loop
    fm := coalesce(nullif(regexp_replace(coalesce(g.data ->> 'cal_freq_months', ''), '\D', '', 'g'), '')::int, 12);
    lc := case when coalesce(g.data ->> 'last_calibrated', '') ~ '^\d{4}-\d{2}-\d{2}$' then (g.data ->> 'last_calibrated')::date else today - 40 end;
    insert into console.cal_instruments (customer_id, tag, name, itype, make, model, serial_no, range_text, least_count, location, department, custodian,
                                         criticality, cal_source, lab, freq_months, tolerance, status, last_cal, next_due, notes, sample)
    values (p_cid, g.code, g.name, g.data ->> 'type', g.data ->> 'make', g.data ->> 'model', g.data ->> 'serial_no', g.data ->> 'range', g.data ->> 'least_count',
            coalesce(g.data ->> 'location', 'Gauge room'), coalesce(g.data ->> 'department', 'Quality'), 'QA inspector',
            case when g.data ->> 'type' in ('CMM','Bore gauge','Plug gauge') then 'Critical' else 'Major' end,
            case when g.data ->> 'type' in ('Plug gauge','Ring gauge') then 'In-house' else 'External' end, 'NABL lab (sample)',
            fm, g.data ->> 'tolerance', 'In use', lc, coalesce(case when coalesce(g.data ->> 'next_due', '') ~ '^\d{4}-\d{2}-\d{2}$' then (g.data ->> 'next_due')::date end, (lc + (fm || ' months')::interval)::date),
            'Sample instrument (from the Operations Master sample gauge)', true)
    on conflict (customer_id, tag) do nothing
    returning id into iid;
    continue when iid is null;
    n := n + 1; first_id := coalesce(first_id, iid);
    insert into console.cal_records (customer_id, instrument_id, cal_date, next_due, kind, lab, accreditation, cert_no, as_found_ok, result, max_error, uncertainty, temp_c, humidity, calibrator, created_by)
    values (p_cid, iid, (lc - (fm || ' months')::interval)::date, lc, 'Periodic', 'NABL lab (sample)', 'NABL', 'CAL/' || g.code || '/1', true, 'Pass', '0.002', '0.001', 20, 50, 'Lab engineer', 'sample'),
           (p_cid, iid, lc, (lc + (fm || ' months')::interval)::date, 'Periodic', 'NABL lab (sample)', 'NABL', 'CAL/' || g.code || '/2', true, 'Pass', '0.002', '0.001', 20, 50, 'Lab engineer', 'sample');
  end loop;
  if first_id is not null then
    insert into console.cal_events (customer_id, instrument_id, ev_date, ev_type, detail, by_email)
    values (p_cid, first_id, today - 3, 'Issued', 'Issued to CNC turning cell (sample)', 'sample');
    -- one out-of-tolerance case on the second instrument
    select id into iid from console.cal_instruments where customer_id = p_cid and sample and id <> first_id order by tag limit 1;
    if iid is not null then
      insert into console.cal_records (customer_id, instrument_id, cal_date, next_due, kind, lab, cert_no, as_found_ok, result, max_error, remarks, created_by)
      values (p_cid, iid, today - 2, null, 'Unscheduled', 'NABL lab (sample)', 'CAL/OOT/1', false, 'Fail', '0.018', 'Found out of tolerance after a drop (sample)', 'sample')
      returning id into rec;
      insert into console.cal_oot (customer_id, instrument_id, record_id, opened_at, summary, last_good, risk, notify, action, status)
      values (p_cid, iid, rec, today - 2, 'As-found error 0.018 mm beyond tolerance (sample)', today - 40, 'Parts measured since the last good calibration may be affected',
              'Quality head; customer if parts were despatched', 'Recall check of lots measured since last good calibration', 'Open');
      update console.cal_instruments set status = 'Quarantine' where id = iid;
    end if;
    insert into console.cal_msa (customer_id, instrument_id, study_type, characteristic, study_date, tolerance, appraisers, parts, trials, decision, performed_by)
    values (p_cid, first_id, 'GRR', 'Ø40 +0.025/0 bore (sample)', today - 20, 0.025, 3, 10, 3, 'Acceptable', 'QA engineer');
  end if;
  return n;
end $$;
revoke all on function console.cal_sample(uuid, text) from public, anon, authenticated;

-- ---------- export / clear / restore of the two apps (real_only: the Grand Master's real-data card) ----------
create or replace function console.app2_export(p_app text, p_cid uuid, p_real_only boolean) returns jsonb
language plpgsql stable security definer set search_path = console, public as $$
declare t text; rows jsonb; tabs jsonb := '{}'; parent text;
begin
  foreach t in array console.app2_tables(p_app) loop
    parent := case when t in ('sf_lines','sf_actions','cal_instruments') then null when p_app = 'sales' then 'sf_lines' else 'cal_instruments' end;
    if not p_real_only then
      execute format('select coalesce(jsonb_agg(to_jsonb(x) - ''customer_id''), ''[]'') from console.%I x where x.customer_id = $1', t) into rows using p_cid;
    elsif parent is null then
      execute format('select coalesce(jsonb_agg(to_jsonb(x) - ''customer_id''), ''[]'') from console.%I x where x.customer_id = $1 and not x.sample', t) into rows using p_cid;
    else
      execute format('select coalesce(jsonb_agg(to_jsonb(x) - ''customer_id''), ''[]'') from console.%I x join console.%I p on p.id = x.%I where x.customer_id = $1 and not p.sample',
                     t, parent, case when parent = 'sf_lines' then 'line_id' else 'instrument_id' end) into rows using p_cid;
    end if;
    tabs := tabs || jsonb_build_object(t, rows);
  end loop;
  return tabs;
end $$;

create or replace function console.app2_clear(p_app text, p_cid uuid, p_real_only boolean) returns bigint
language plpgsql security definer set search_path = console, public as $$
declare n bigint := 0; k bigint;
begin
  if p_app = 'sales' then
    delete from console.sf_actions where customer_id = p_cid and (not p_real_only or not sample); get diagnostics k = row_count; n := n + k;
    delete from console.sf_lines where customer_id = p_cid and (not p_real_only or not sample); get diagnostics k = row_count; n := n + k;
  elsif p_app = 'calib' then
    delete from console.cal_instruments where customer_id = p_cid and (not p_real_only or not sample); get diagnostics n = row_count;
  end if;
  return n;
end $$;

create or replace function console.app2_restore(p_app text, p_cid uuid, p_tables jsonb, p_real_only boolean) returns bigint
language plpgsql security definer set search_path = console, public as $$
declare t text; rows jsonb; tot bigint := 0; k bigint;
begin
  perform console.app2_clear(p_app, p_cid, p_real_only);
  foreach t in array console.app2_tables(p_app) loop
    -- every row goes back into THIS company, whatever the file says; restored real data is never marked sample
    rows := (select coalesce(jsonb_agg(r || jsonb_build_object('customer_id', p_cid)
                       || case when t in ('sf_lines','sf_actions','cal_instruments') and p_real_only then '{"sample":false}'::jsonb else '{}'::jsonb end), '[]')
               from jsonb_array_elements(coalesce(p_tables -> t, '[]')) r);
    execute format('insert into console.%I select * from jsonb_populate_recordset(null::console.%I, $1) on conflict do nothing', t, t) using rows;
    get diagnostics k = row_count; tot := tot + k;
  end loop;
  return tot;
end $$;
revoke all on function console.app2_export(text, uuid, boolean), console.app2_clear(text, uuid, boolean), console.app2_restore(text, uuid, jsonb, boolean) from public, anon, authenticated;

-- =====================================================================
-- Data Master: the two apps next to the others
-- =====================================================================
create or replace function console.data_target(p_slug text, p_app text, out cid uuid, out ref uuid)
language plpgsql stable security definer set search_path = console, public as $$
begin
  select c.id into cid from console.customers c where c.slug = lower(p_slug);
  if cid is null or not console.is_customer_admin(cid) then raise exception 'Only your company administrator can manage app data.'; end if;
  if p_app = 'ops' then ref := cid; return; end if;
  if p_app in ('sales','calib') then
    if not console.has_app(cid, p_app) then raise exception 'Your company does not have this app yet.'; end if;
    ref := cid; return;
  end if;
  if p_app not in ('hrm','balloon','pd','capacity') then raise exception 'Unknown app %', p_app; end if;
  select l.product_ref into ref from console.licences l where l.customer_id = cid and l.product_code = p_app and l.product_ref is not null limit 1;
  if ref is null then raise exception 'Your company does not have this app yet.'; end if;
end $$;
revoke all on function console.data_target(text, text) from public, anon, authenticated;

create or replace function public.kmr_data_overview(p_slug text) returns jsonb
language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid; l record; out jsonb := '[]'::jsonb; t text; n bigint; det jsonb; tot bigint; a text;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or not console.is_customer_admin(cid) then raise exception 'Only your company administrator can manage app data.'; end if;
  for l in select product_code, product_ref from console.licences where customer_id = cid and product_ref is not null
             and product_code in ('hrm','balloon','pd','capacity') order by array_position(array['hrm','balloon','pd','capacity'], product_code) loop
    det := '{}'; tot := 0;
    if l.product_code = 'hrm' then
      foreach t in array array['employees','attendance_days','leave_requests','payroll_runs','loans','id_cards','onboarding_invites'] loop
        if to_regclass('hrm.' || t) is null then continue; end if;
        execute format('select count(*) from hrm.%I where tenant_id = $1', t) into n using l.product_ref;
        det := det || jsonb_build_object(t, n); tot := tot + n;
      end loop;
    else
      foreach t in array console.data_tables(l.product_code) loop
        execute format('select count(*) from public.%I where org_id = $1', t) into n using l.product_ref;
        det := det || jsonb_build_object(t, n); tot := tot + n;
      end loop;
    end if;
    out := out || jsonb_build_array(jsonb_build_object('app', l.product_code, 'records', tot, 'detail', det));
  end loop;
  foreach a in array array['sales','calib'] loop
    continue when not console.has_app(cid, a);
    det := '{}'; tot := 0;
    foreach t in array console.app2_tables(a) loop
      execute format('select count(*) from console.%I where customer_id = $1', t) into n using cid;
      det := det || jsonb_build_object(t, n); tot := tot + n;
    end loop;
    out := out || jsonb_build_array(jsonb_build_object('app', a, 'records', tot, 'detail', det));
  end loop;
  select count(*) into n from console.ops_records where customer_id = cid;
  out := out || jsonb_build_array(jsonb_build_object('app', 'ops', 'records', n, 'detail', jsonb_build_object('ops_records', n)));
  return out;
end $$;
grant execute on function public.kmr_data_overview(text) to authenticated;

create or replace function public.kmr_data_export(p_slug text, p_app text) returns jsonb
language plpgsql stable security definer set search_path = console, public as $$
declare tg record; t text; rows jsonb; tabs jsonb := '{}';
begin
  select * into tg from console.data_target(p_slug, p_app);
  if p_app = 'hrm' then
    tabs := jsonb_build_object('hrm', hrm.company_export(tg.ref));
  elsif p_app = 'ops' then
    select coalesce(jsonb_agg(to_jsonb(r) - 'customer_id' order by r.kind, r.code), '[]') into rows from console.ops_records r where r.customer_id = tg.cid;
    tabs := jsonb_build_object('ops_records', rows);
  elsif p_app in ('sales','calib') then
    tabs := console.app2_export(p_app, tg.cid, false);
  else
    foreach t in array console.data_tables(p_app) loop
      execute format('select coalesce(jsonb_agg(to_jsonb(x)), ''[]'') from public.%I x where x.org_id = $1', t) into rows using tg.ref;
      tabs := tabs || jsonb_build_object(t, rows);
    end loop;
  end if;
  return jsonb_build_object('format', 'kmr-app-data', 'version', 1, 'app', p_app, 'company', lower(p_slug), 'exported_at', now(), 'tables', tabs);
end $$;
grant execute on function public.kmr_data_export(text, text) to authenticated;

create or replace function public.kmr_data_flush(p_slug text, p_app text, p_hrm_setup boolean default false) returns jsonb
language plpgsql security definer set search_path = console, public as $$
declare tg record;
begin
  select * into tg from console.data_target(p_slug, p_app);
  if p_app = 'hrm' then return hrm.company_flush(tg.ref, coalesce(p_hrm_setup, false)); end if;
  if p_app in ('sales','calib') then return jsonb_build_object('removed', console.app2_clear(p_app, tg.cid, false)); end if;
  return jsonb_build_object('removed', console.data_clear(p_app, tg.cid, tg.ref));
end $$;
grant execute on function public.kmr_data_flush(text, text, boolean) to authenticated;

create or replace function public.kmr_data_import(p_slug text, p_app text, p_data jsonb) returns jsonb
language plpgsql security definer set search_path = console, public as $$
declare tg record; t text; rows jsonb; n bigint; k bigint; tot bigint := 0; pass int; todo text[];
begin
  select * into tg from console.data_target(p_slug, p_app);
  if p_data ->> 'format' is distinct from 'kmr-app-data' then raise exception 'This is not a KMR Data Master file.'; end if;
  if p_data ->> 'app' is distinct from p_app then raise exception 'This file is a backup of another app (%).', p_data ->> 'app'; end if;
  if p_app = 'hrm' then
    return jsonb_build_object('restored', hrm.company_import(tg.ref, p_data -> 'tables' -> 'hrm'));
  end if;
  if p_app in ('sales','calib') then
    return jsonb_build_object('restored', console.app2_restore(p_app, tg.cid, p_data -> 'tables', false));
  end if;
  perform console.data_clear(p_app, tg.cid, tg.ref);
  if p_app = 'ops' then
    rows := (select coalesce(jsonb_agg(r || jsonb_build_object('customer_id', tg.cid)), '[]') from jsonb_array_elements(coalesce(p_data -> 'tables' -> 'ops_records', '[]')) r);
    insert into console.ops_records select * from jsonb_populate_recordset(null::console.ops_records, rows) on conflict do nothing;
    get diagnostics n = row_count;
    return jsonb_build_object('restored', n);
  end if;
  perform console.app_triggers(case p_app when 'balloon' then 'bi' when 'pd' then 'pd' else 'cp' end, false);
  todo := array(select x from unnest(console.data_tables(p_app)) x where (p_data -> 'tables') ? x);
  for pass in 1..4 loop
    exit when cardinality(todo) = 0;
    foreach t in array todo loop
      rows := (select coalesce(jsonb_agg(r || jsonb_build_object('org_id', tg.ref)), '[]') from jsonb_array_elements(p_data -> 'tables' -> t) r);
      begin
        execute format('insert into public.%I select * from jsonb_populate_recordset(null::public.%I, $1) on conflict do nothing', t, t) using rows;
        get diagnostics k = row_count; tot := tot + k; todo := array_remove(todo, t);
      exception when foreign_key_violation then null;
      end;
    end loop;
  end loop;
  perform console.app_triggers(case p_app when 'balloon' then 'bi' when 'pd' then 'pd' else 'cp' end, true);
  if cardinality(todo) > 0 then raise exception 'Could not restore: %.', array_to_string(todo, ', '); end if;
  return jsonb_build_object('restored', tot);
end $$;
grant execute on function public.kmr_data_import(text, text, jsonb) to authenticated;

-- =====================================================================
-- Grand Master
-- =====================================================================
create or replace function public.kmr_grand_sample(p_slug text, p_action text) returns jsonb
language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.grand_customer(p_slug); out jsonb := '{}'; r uuid; n int; k int; flow jsonb;
begin
  if p_action not in ('load','flush') then raise exception 'Unknown action.'; end if;
  r := console.grand_ref(cid, 'hrm');
  if r is not null then
    if p_action = 'load' then
      if exists (select 1 from hrm.employees where tenant_id = r and email like '%@demo.kmr.test') then n := 0;
      else n := hrm.demo_load(r); perform hrm.demo_payroll(r); end if;
      if to_regprocedure('hrm.demo_flow(uuid)') is not null then
        flow := hrm.demo_flow(r);
        out := out || jsonb_build_object('hrm_flow', flow);
      end if;
    else
      if exists (select 1 from information_schema.columns where table_schema = 'hrm' and table_name = 'candidates' and column_name = 'sample') then
        execute 'select count(*) from hrm.candidates where tenant_id = $1 and sample' into k using r;
        out := out || jsonb_build_object('hrm_candidates', k);
      end if;
      n := hrm.demo_flush(r);
    end if;
    out := out || jsonb_build_object('hrm', n, 'hrm_tenant', r);
  end if;
  if console.grand_ref(cid, 'balloon') is not null and to_regclass('public.bi_reports') is not null then
    out := out || jsonb_build_object('balloon', public.kmr_ops_sample_drawing(p_slug, p_action));
  end if;
  if p_action = 'load' then
    -- the Operations Master first: Sales Flow and Calibration Hub are built from its sample parts, rate contracts and gauges
    out := out || jsonb_build_object('ops', (public.kmr_ops_sample_load(p_slug) ->> 'added')::int);
    if console.has_app(cid, 'sales') then out := out || jsonb_build_object('sales', console.sf_sample(cid, 'load')); end if;
    if console.has_app(cid, 'calib') then out := out || jsonb_build_object('calib', console.cal_sample(cid, 'load')); end if;
  else
    if console.has_app(cid, 'sales') then out := out || jsonb_build_object('sales', console.sf_sample(cid, 'flush')); end if;
    if console.has_app(cid, 'calib') then out := out || jsonb_build_object('calib', console.cal_sample(cid, 'flush')); end if;
    out := out || jsonb_build_object('ops', public.kmr_ops_sample_flush(p_slug));
  end if;
  return out;
end $$;
revoke all on function public.kmr_grand_sample(text, text) from public, anon;
grant execute on function public.kmr_grand_sample(text, text) to authenticated;

create or replace function public.kmr_grand_overview(p_slug text) returns jsonb
language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.grand_customer(p_slug); r uuid; real_ jsonb := '{}'; smp jsonb := '{}'; t text; n bigint; k bigint; c console.customers%rowtype;
begin
  r := console.grand_ref(cid, 'hrm');
  if r is not null then
    select count(*) filter (where coalesce(email, '') not like '%@demo.kmr.test'), count(*) filter (where coalesce(email, '') like '%@demo.kmr.test')
      into n, k from hrm.employees where tenant_id = r;
    real_ := real_ || jsonb_build_object('hrm', n); smp := smp || jsonb_build_object('hrm', k);
    if exists (select 1 from information_schema.columns where table_schema = 'hrm' and table_name = 'candidates' and column_name = 'sample') then
      execute 'select count(*) filter (where not sample), count(*) filter (where sample) from hrm.candidates where tenant_id = $1' into n, k using r;
      real_ := real_ || jsonb_build_object('hrm_candidates', n); smp := smp || jsonb_build_object('hrm_candidates', k);
    end if;
  end if;
  r := console.grand_ref(cid, 'balloon');
  if r is not null and to_regclass('public.bi_reports') is not null then
    execute 'select count(*) filter (where coalesce(file_path, '''') not like ''static:%''), count(*) filter (where file_path like ''static:%'') from public.bi_reports where org_id = $1'
      into n, k using r;
    real_ := real_ || jsonb_build_object('balloon', n); smp := smp || jsonb_build_object('balloon', k);
  end if;
  foreach t in array array['pd','capacity'] loop
    r := console.grand_ref(cid, t);
    if r is null then continue; end if;
    n := 0;
    declare tb text; m bigint; begin
      foreach tb in array console.data_tables(t) loop
        execute format('select count(*) from public.%I where org_id = $1', tb) into m using r; n := n + m;
      end loop;
    end;
    real_ := real_ || jsonb_build_object(t, n);
  end loop;
  if console.has_app(cid, 'sales') then
    select count(*) filter (where not sample), count(*) filter (where sample) into n, k from console.sf_lines where customer_id = cid;
    real_ := real_ || jsonb_build_object('sales', n); smp := smp || jsonb_build_object('sales', k);
  end if;
  if console.has_app(cid, 'calib') then
    select count(*) filter (where not sample), count(*) filter (where sample) into n, k from console.cal_instruments where customer_id = cid;
    real_ := real_ || jsonb_build_object('calib', n); smp := smp || jsonb_build_object('calib', k);
  end if;
  select count(*) filter (where not sample), count(*) filter (where sample) into n, k from console.ops_records where customer_id = cid;
  real_ := real_ || jsonb_build_object('ops', n); smp := smp || jsonb_build_object('ops', k);
  select * into c from console.customers where id = cid;
  return jsonb_build_object('real', real_, 'sample', smp, 'staff', console.is_staff(),
    'admin', jsonb_build_object(
      'company', c.name, 'logo', coalesce(c.logo_url, '') <> '',
      'details', (select count(*) from unnest(array[c.legal_name, c.tax_id, c.address, c.city, c.state, c.postal_code, c.contact_phone]) v where coalesce(v, '') <> ''),
      'users', (select count(*) from console.customer_members where customer_id = cid),
      'invoices', (select count(*) from console.invoices where customer_id = cid),
      'payments', (select count(*) from console.payments p join console.invoices i on i.id = p.invoice_id where i.customer_id = cid)));
end $$;
revoke all on function public.kmr_grand_overview(text) from public, anon;
grant execute on function public.kmr_grand_overview(text) to authenticated;

create or replace function public.kmr_grand_real_export(p_slug text) returns jsonb
language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.grand_customer(p_slug); apps jsonb := '{}'; t text;
begin
  foreach t in array array['hrm','pd','capacity'] loop
    if console.grand_ref(cid, t) is not null then apps := apps || jsonb_build_object(t, public.kmr_data_export(p_slug, t)); end if;
  end loop;
  if console.grand_ref(cid, 'balloon') is not null and to_regclass('public.bi_reports') is not null then
    apps := apps || jsonb_build_object('balloon', public.kmr_balloon_own_export(p_slug));
  end if;
  foreach t in array array['sales','calib'] loop
    if console.has_app(cid, t) then apps := apps || jsonb_build_object(t, jsonb_build_object('format', 'kmr-app-real', 'tables', console.app2_export(t, cid, true))); end if;
  end loop;
  apps := apps || jsonb_build_object('ops', jsonb_build_object('format', 'kmr-ops-own', 'records',
    coalesce((select jsonb_agg(jsonb_build_object('kind', r.kind, 'code', r.code, 'name', r.name, 'data', r.data, 'active', r.active) order by r.kind, r.code)
                from console.ops_records r where r.customer_id = cid and not r.sample), '[]')));
  return jsonb_build_object('format', 'kmr-real-data', 'version', 1, 'company', lower(p_slug), 'exported_at', now(), 'apps', apps);
end $$;
revoke all on function public.kmr_grand_real_export(text) from public, anon;
grant execute on function public.kmr_grand_real_export(text) to authenticated;

create or replace function public.kmr_grand_real_flush(p_slug text) returns jsonb
language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.grand_customer(p_slug); out jsonb := '{}'; r uuid; t text; n int;
begin
  r := console.grand_ref(cid, 'hrm');
  if r is not null then
    out := out || jsonb_build_object('hrm_candidates', console.grand_hrm_real_candidates(r));
    out := out || jsonb_build_object('hrm', hrm.real_flush(r));
  end if;
  if console.grand_ref(cid, 'balloon') is not null and to_regclass('public.bi_reports') is not null then
    out := out || jsonb_build_object('balloon', public.kmr_balloon_own_flush(p_slug));
  end if;
  foreach t in array array['pd','capacity'] loop
    r := console.grand_ref(cid, t);
    if r is not null then out := out || jsonb_build_object(t, console.data_clear(t, cid, r)); end if;
  end loop;
  -- Sales Flow / Calibration Hub: count the parent records (plan lines, instruments) removed, sample ones stay
  if console.has_app(cid, 'sales') then
    select count(*) into n from console.sf_lines where customer_id = cid and not sample;
    perform console.app2_clear('sales', cid, true); out := out || jsonb_build_object('sales', n);
  end if;
  if console.has_app(cid, 'calib') then
    select count(*) into n from console.cal_instruments where customer_id = cid and not sample;
    perform console.app2_clear('calib', cid, true); out := out || jsonb_build_object('calib', n);
  end if;
  delete from console.ops_records where customer_id = cid and not sample; get diagnostics n = row_count;
  return out || jsonb_build_object('ops', n);
end $$;
revoke all on function public.kmr_grand_real_flush(text) from public, anon;
grant execute on function public.kmr_grand_real_flush(text) to authenticated;

create or replace function public.kmr_grand_real_import(p_slug text, p_data jsonb) returns jsonb
language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.grand_customer(p_slug); out jsonb := '{}'; t text; a jsonb; n int; me text := lower(coalesce(auth.jwt() ->> 'email', ''));
begin
  if p_data ->> 'format' is distinct from 'kmr-real-data' then raise exception 'This is not a Grand Master real-data file.'; end if;
  if lower(coalesce(p_data ->> 'company', '')) <> lower(p_slug) then
    raise exception 'This file is a backup of another company (%).', p_data ->> 'company';
  end if;
  foreach t in array array['hrm','pd','capacity'] loop
    a := p_data -> 'apps' -> t;
    if a is null or console.grand_ref(cid, t) is null then continue; end if;
    out := out || jsonb_build_object(t, public.kmr_data_import(p_slug, t, a) -> 'restored');
    if t = 'hrm' then
      select count(*) into n from hrm.employees where tenant_id = console.grand_ref(cid, 'hrm') and coalesce(email, '') not like '%@demo.kmr.test';
      out := out || jsonb_build_object('hrm', n, 'hrm_candidates', console.grand_hrm_real_candidates(console.grand_ref(cid, 'hrm')));
    end if;
  end loop;
  a := p_data -> 'apps' -> 'balloon';
  if a is not null and console.grand_ref(cid, 'balloon') is not null then
    perform public.kmr_balloon_own_flush(p_slug);
    if jsonb_array_length(coalesce(a -> 'tables' -> 'bi_reports', '[]')) > 0 then
      out := out || jsonb_build_object('balloon', public.kmr_balloon_own_load(p_slug, a));
    else out := out || jsonb_build_object('balloon', 0); end if;
  end if;
  -- Operations Master before Sales Flow / Calibration Hub (they point at its parts and gauges by code)
  a := p_data -> 'apps' -> 'ops';
  if a is not null then
    delete from console.ops_records where customer_id = cid and not sample;
    insert into console.ops_records (customer_id, kind, code, name, data, active, sample, updated_by)
    select cid, x ->> 'kind', x ->> 'code', coalesce(x ->> 'name', x ->> 'code'), coalesce(x -> 'data', '{}'), coalesce((x ->> 'active')::boolean, true), false, me
      from jsonb_array_elements(coalesce(a -> 'records', '[]')) x
     where coalesce(x ->> 'kind', '') <> '' and coalesce(x ->> 'code', '') <> ''
    on conflict (customer_id, kind, code) do update set name = excluded.name, data = excluded.data, active = excluded.active, sample = false, updated_by = me;
    get diagnostics n = row_count; out := out || jsonb_build_object('ops', n);
  end if;
  foreach t in array array['sales','calib'] loop
    a := p_data -> 'apps' -> t;
    if a is null or not console.has_app(cid, t) then continue; end if;
    perform console.app2_restore(t, cid, a -> 'tables', true);
    if t = 'sales' then select count(*) into n from console.sf_lines where customer_id = cid and not sample;
    else select count(*) into n from console.cal_instruments where customer_id = cid and not sample; end if;
    out := out || jsonb_build_object(t, n);
  end loop;
  return out;
end $$;
revoke all on function public.kmr_grand_real_import(text, jsonb) from public, anon;
grant execute on function public.kmr_grand_real_import(text, jsonb) to authenticated;
