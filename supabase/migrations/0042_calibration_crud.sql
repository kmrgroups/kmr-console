-- Calibration Hub 0042 — control plan picker for MSA, machine list, and edit / delete on every screen. Needs 0037, 0039. Safe to re-run.
create or replace function console.cal_refresh(p_inst uuid) returns void language plpgsql security definer set search_path = console, public as $$
declare r record;
begin
  select cal_date, next_due into r from console.cal_records where instrument_id = p_inst and result = 'Pass' order by cal_date desc, created_at desc limit 1;
  update console.cal_instruments set last_cal = r.cal_date, next_due = r.next_due where id = p_inst;
end $$;

create or replace function public.kmr_cal_control_plan(p_slug text) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid; org uuid;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or console.cal_role(cid) is null then raise exception 'You have no access to Calibration Hub.'; end if;
  select product_ref into org from console.licences where customer_id = cid and product_code = 'pd' limit 1;
  if org is null then return '[]'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('project_id', p.id, 'part_no', p.part_no, 'part_name', p.part_name, 'rev', p.rev,
      'rows', coalesce((select jsonb_agg(jsonb_build_object('char_no', r ->> 'charNo', 'op_no', r ->> 'opNo', 'char', coalesce(nullif(r ->> 'product', ''), nullif(r ->> 'process', '')),
                                                           'spec', r ->> 'spec', 'tech', r ->> 'tech', 'cls', r ->> 'cls'))
                          from jsonb_array_elements(coalesce(p.doc #> '{docs,cp,rows}', '[]'::jsonb)) r
                         where coalesce(nullif(r ->> 'product', ''), nullif(r ->> 'process', '')) is not null), '[]')) order by p.part_no)
                     from public.pd_projects p where p.org_id = org), '[]');
end $$;

create or replace function public.kmr_cal_ops_machines(p_slug text) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or console.cal_role(cid) is null then raise exception 'You have no access to Calibration Hub.'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('code', m.code, 'name', m.name) order by m.code) from console.ops_records m where m.customer_id = cid and m.kind = 'machines' and m.active), '[]');
end $$;

create or replace function public.kmr_cal_delete_instrument(p_slug text, p_id uuid) returns text language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.cal_edit(p_slug);
begin delete from console.cal_instruments where id = p_id and customer_id = cid; return 'ok'; end $$;

create or replace function public.kmr_cal_update_record(p_slug text, p_id uuid, p jsonb) returns text language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.cal_edit(p_slug); iid uuid;
begin
  update console.cal_records set cal_date = (p ->> 'cal_date')::date, next_due = coalesce(nullif(p ->> 'next_due', '')::date, next_due), kind = p ->> 'kind', lab = p ->> 'lab', accreditation = p ->> 'accreditation',
    cert_no = p ->> 'cert_no', as_found_ok = (nullif(p ->> 'as_found_ok', ''))::boolean, result = coalesce(nullif(p ->> 'result', ''), 'Pass'), max_error = p ->> 'max_error', uncertainty = p ->> 'uncertainty',
    temp_c = nullif(p ->> 'temp_c', '')::numeric, humidity = nullif(p ->> 'humidity', '')::numeric, calibrator = p ->> 'calibrator', remarks = p ->> 'remarks'
   where id = p_id and customer_id = cid returning instrument_id into iid;
  if iid is not null then perform console.cal_refresh(iid); end if;
  return 'ok';
end $$;
create or replace function public.kmr_cal_delete_record(p_slug text, p_id uuid) returns text language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.cal_edit(p_slug); iid uuid;
begin delete from console.cal_records where id = p_id and customer_id = cid returning instrument_id into iid; if iid is not null then perform console.cal_refresh(iid); end if; return 'ok'; end $$;
create or replace function public.kmr_cal_delete_oot(p_slug text, p_id uuid) returns text language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.cal_edit(p_slug);
begin delete from console.cal_oot where id = p_id and customer_id = cid; return 'ok'; end $$;
create or replace function public.kmr_cal_delete_event(p_slug text, p_id uuid) returns text language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.cal_edit(p_slug);
begin delete from console.cal_events where id = p_id and customer_id = cid; return 'ok'; end $$;

-- MSA: save now also updates an existing study (p.id)
create or replace function public.kmr_cal_save_msa(p_slug text, p jsonb) returns uuid language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.cal_edit(p_slug); rid uuid;
begin
  if not exists (select 1 from console.cal_instruments where id = (p ->> 'instrument_id')::uuid and customer_id = cid) then raise exception 'Unknown instrument.'; end if;
  if nullif(p ->> 'id', '') is not null then
    update console.cal_msa set instrument_id = (p ->> 'instrument_id')::uuid, characteristic = p ->> 'characteristic', study_date = coalesce(nullif(p ->> 'study_date', '')::date, study_date), tolerance = nullif(p ->> 'tolerance', '')::numeric,
      appraisers = (p ->> 'appraisers')::int, parts = (p ->> 'parts')::int, trials = (p ->> 'trials')::int, data = p -> 'data', results = p -> 'results', decision = p ->> 'decision'
     where id = (p ->> 'id')::uuid and customer_id = cid returning id into rid;
  else
    insert into console.cal_msa (customer_id, instrument_id, study_type, characteristic, study_date, tolerance, appraisers, parts, trials, data, results, decision, performed_by)
    values (cid, (p ->> 'instrument_id')::uuid, coalesce(p ->> 'study_type', 'GRR'), p ->> 'characteristic', coalesce(nullif(p ->> 'study_date', '')::date, current_date), nullif(p ->> 'tolerance', '')::numeric,
            (p ->> 'appraisers')::int, (p ->> 'parts')::int, (p ->> 'trials')::int, p -> 'data', p -> 'results', p ->> 'decision', lower(coalesce(auth.jwt() ->> 'email', ''))) returning id into rid;
  end if;
  return rid;
end $$;
do $$ declare f text; begin foreach f in array array['kmr_cal_control_plan(text)','kmr_cal_ops_machines(text)','kmr_cal_delete_instrument(text,uuid)','kmr_cal_update_record(text,uuid,jsonb)','kmr_cal_delete_record(text,uuid)','kmr_cal_delete_oot(text,uuid)','kmr_cal_delete_event(text,uuid)','kmr_cal_save_msa(text,jsonb)'] loop
  execute format('grant execute on function public.%s to authenticated', f); end loop; end $$;
