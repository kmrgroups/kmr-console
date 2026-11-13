-- Calibration Hub 0104 — big plants (thousands of gauges, tens of thousands of calibration records) loaded too slowly ("canceling statement due to statement timeout").
-- The screen now loads the gauges with their total cost and a count summary, and only the last 14 months of calibration records; the full history of a gauge
-- is read when its history card is opened, and the whole register only when it is exported. Needs 0098 (cost). Safe to re-run.
create index if not exists cal_instruments_cust on console.cal_instruments (customer_id);
create index if not exists cal_records_cust_date on console.cal_records (customer_id, cal_date desc);
create index if not exists cal_records_inst on console.cal_records (instrument_id, cal_date desc);
create index if not exists cal_events_cust on console.cal_events (customer_id);

create or replace function public.kmr_cal_load(p_slug text) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or console.cal_role(cid) is null then raise exception 'You have no access to Calibration Hub.'; end if;
  return jsonb_build_object(
    'instruments', coalesce((select jsonb_agg((to_jsonb(i) - 'customer_id') || jsonb_build_object('cost_total', coalesce(c.t, 0), 'rec_count', coalesce(c.n, 0)) order by i.tag)
                               from console.cal_instruments i
                               left join (select instrument_id, sum(cost) t, count(*) n from console.cal_records where customer_id = cid group by instrument_id) c on c.instrument_id = i.id
                              where i.customer_id = cid), '[]'),
    'records', coalesce((select jsonb_agg(to_jsonb(r) - 'customer_id' order by r.cal_date desc) from console.cal_records r where r.customer_id = cid and r.cal_date >= current_date - 430), '[]'),
    'stats', (select jsonb_build_object('total', count(*), 'cert', count(*) filter (where nullif(cert_no, '') is not null), 'accr', count(*) filter (where nullif(accreditation, '') is not null),
                                       'cost', count(*) filter (where cost is not null)) from console.cal_records where customer_id = cid),
    'events', coalesce((select jsonb_agg(to_jsonb(e) - 'customer_id' order by e.ev_date desc, e.created_at desc) from console.cal_events e where e.customer_id = cid), '[]'),
    'oot', coalesce((select jsonb_agg(to_jsonb(o) - 'customer_id' order by o.opened_at desc) from console.cal_oot o where o.customer_id = cid), '[]'),
    'msa', coalesce((select jsonb_agg(to_jsonb(s) - 'customer_id' order by s.study_date desc) from console.cal_msa s where s.customer_id = cid), '[]'));
end $$;
grant execute on function public.kmr_cal_load(text) to authenticated;

-- every calibration record of one gauge (p_id) or, with p_id null, of the whole plant (for the export)
create or replace function public.kmr_cal_records(p_slug text, p_id uuid default null) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or console.cal_role(cid) is null then raise exception 'You have no access to Calibration Hub.'; end if;
  return coalesce((select jsonb_agg(to_jsonb(r) - 'customer_id' order by r.cal_date desc) from console.cal_records r where r.customer_id = cid and (p_id is null or r.instrument_id = p_id)), '[]');
end $$;
grant execute on function public.kmr_cal_records(text, uuid) to authenticated;
