-- Process Documents: each machine now carries its CNC control system (set in Operations Master > Machines).
create or replace function public.kmr_pd_masters(p_org uuid) returns jsonb
language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid;
begin
  if public.kmr_pd_role(p_org) is null then raise exception 'No access to this workspace.'; end if;
  select customer_id into cid from console.licences where product_code = 'pd' and product_ref = p_org;
  if cid is null then return null; end if;
  return jsonb_build_object(
    'machines', coalesce((select jsonb_agg(jsonb_build_object(
        'id', r.code, 'name', r.name, 'make', coalesce(r.data ->> 'make', ''), 'model', coalesce(r.data ->> 'model', ''),
        'capacity', coalesce(r.data ->> 'capacity', ''), 'keys', console.pd_keys_for(r.data ->> 'type', r.data ->> 'processes'),
        'maxDia', nullif(r.data ->> 'max_size_mm', '')::numeric, 'cap', nullif(r.data ->> 'capability_mm', '')::numeric,
        'location', coalesce(nullif(r.data ->> 'cell', ''), r.data ->> 'location', ''), 'pm', coalesce(r.data ->> 'pm_frequency', ''), 'control', coalesce(r.data ->> 'control', '')) order by r.code)
      from console.ops_records r where r.customer_id = cid and r.kind = 'machines' and r.active and coalesce(r.data ->> 'status', '') <> 'Scrapped'), '[]'),
    'gauges', coalesce((select jsonb_agg(jsonb_build_object(
        'id', r.code, 'name', r.name, 'range', coalesce(r.data ->> 'range', ''), 'lc', coalesce(r.data ->> 'least_count', ''),
        'calFreq', case when coalesce(r.data ->> 'cal_freq_months', '') <> '' then (r.data ->> 'cal_freq_months') || ' months' else '' end,
        'calDue', coalesce(r.data ->> 'next_due', ''), 'location', coalesce(r.data ->> 'location', '')) order by r.code)
      from console.ops_records r where r.customer_id = cid and r.kind = 'gauges' and r.active), '[]'),
    'customers', coalesce((select jsonb_agg(jsonb_build_object(
        'name', r.name, 'code', coalesce(r.data ->> 'supplier_code', ''),
        'address', concat_ws(', ', nullif(r.data ->> 'address', ''), nullif(r.data ->> 'city', ''), nullif(r.data ->> 'country', '')),
        'contact', concat_ws(' / ', nullif(r.data ->> 'contact', ''), nullif(r.data ->> 'email', '')),
        'ccSym', coalesce(r.data ->> 'cc_symbol', ''), 'scSym', coalesce(r.data ->> 'sc_symbol', ''), 'approval', coalesce(r.data ->> 'approval', '')) order by r.name)
      from console.ops_records r where r.customer_id = cid and r.kind = 'customers' and r.active), '[]'),
    'consumables', coalesce((select jsonb_agg(jsonb_build_object('key', k, 'items', items) order by k) from (
        select upper(trim(p)) k, string_agg(r.name, E'\n' order by r.name) items
          from console.ops_records r, unnest(string_to_array(coalesce(r.data ->> 'processes', ''), ',')) p
         where r.customer_id = cid and r.kind = 'consumables' and r.active and trim(p) <> '' group by 1) c), '[]'),
    'parts', coalesce((select jsonb_agg(jsonb_build_object(
        'partNo', r.code, 'partName', r.name, 'drawingNo', coalesce(r.data ->> 'drawing_no', ''), 'rev', coalesce(r.data ->> 'revision', ''),
        'material', coalesce(r.data ->> 'material', ''), 'customer', coalesce(r.data ->> 'customer', '')) order by r.code)
      from console.ops_records r where r.customer_id = cid and r.kind = 'parts' and r.active), '[]'));
end $$;
revoke all on function public.kmr_pd_masters(uuid) from public, anon;
grant execute on function public.kmr_pd_masters(uuid) to authenticated;
