-- Calibration Hub 0039 — MSA studies (Gage R&R, average & range method; computed in the app, stored with the data). Needs 0037. Safe to re-run.
create table if not exists console.cal_msa (
  id uuid primary key default gen_random_uuid(), customer_id uuid not null references console.customers(id) on delete cascade,
  instrument_id uuid not null references console.cal_instruments(id) on delete cascade, study_type text not null default 'GRR',
  characteristic text, study_date date not null default current_date, tolerance numeric, appraisers int, parts int, trials int,
  data jsonb, results jsonb, decision text, performed_by text, created_at timestamptz not null default now());
alter table console.cal_msa enable row level security;
drop policy if exists cal_msa_staff on console.cal_msa;
create policy cal_msa_staff on console.cal_msa for all to authenticated using (console.is_staff()) with check (console.is_staff());
create or replace function public.kmr_cal_load(p_slug text) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or console.cal_role(cid) is null then raise exception 'You have no access to Calibration Hub.'; end if;
  return jsonb_build_object(
    'instruments', coalesce((select jsonb_agg(to_jsonb(i) - 'customer_id' order by i.tag) from console.cal_instruments i where i.customer_id = cid), '[]'),
    'records', coalesce((select jsonb_agg(to_jsonb(r) - 'customer_id' order by r.cal_date desc) from console.cal_records r where r.customer_id = cid), '[]'),
    'events', coalesce((select jsonb_agg(to_jsonb(e) - 'customer_id' order by e.ev_date desc, e.created_at desc) from console.cal_events e where e.customer_id = cid), '[]'),
    'oot', coalesce((select jsonb_agg(to_jsonb(o) - 'customer_id' order by o.opened_at desc) from console.cal_oot o where o.customer_id = cid), '[]'),
    'msa', coalesce((select jsonb_agg(to_jsonb(s) - 'customer_id' order by s.study_date desc) from console.cal_msa s where s.customer_id = cid), '[]'));
end $$;

create or replace function public.kmr_cal_save_msa(p_slug text, p jsonb) returns uuid language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.cal_edit(p_slug); rid uuid;
begin
  if not exists (select 1 from console.cal_instruments where id = (p ->> 'instrument_id')::uuid and customer_id = cid) then raise exception 'Unknown instrument.'; end if;
  insert into console.cal_msa (customer_id, instrument_id, study_type, characteristic, study_date, tolerance, appraisers, parts, trials, data, results, decision, performed_by)
  values (cid, (p ->> 'instrument_id')::uuid, coalesce(p ->> 'study_type', 'GRR'), p ->> 'characteristic', coalesce(nullif(p ->> 'study_date', '')::date, current_date), nullif(p ->> 'tolerance', '')::numeric,
          (p ->> 'appraisers')::int, (p ->> 'parts')::int, (p ->> 'trials')::int, p -> 'data', p -> 'results', p ->> 'decision', lower(coalesce(auth.jwt() ->> 'email', ''))) returning id into rid;
  return rid;
end $$;
create or replace function public.kmr_cal_delete_msa(p_slug text, p_id uuid) returns text language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.cal_edit(p_slug);
begin delete from console.cal_msa where id = p_id and customer_id = cid; return 'ok'; end $$;
grant execute on function public.kmr_cal_load(text) to authenticated;
grant execute on function public.kmr_cal_save_msa(text, jsonb) to authenticated;
grant execute on function public.kmr_cal_delete_msa(text, uuid) to authenticated;
