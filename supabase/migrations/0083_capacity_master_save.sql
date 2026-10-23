-- 0083 · Capacity Planner › Process Master: save a part's process flow (process -> machines -> cycle time per machine)
-- straight into the Operations Master, so Capacity Planner and every other KMR app read the same routing.
-- Needs 0016 (capacity masters). Safe to run again.
create or replace function public.kmr_capacity_master_save(p_org uuid, p_part jsonb) returns jsonb
language plpgsql security definer set search_path = console, public as $$
declare
  cid uuid; pn text; pname text; st jsonb; mc jsonb; i int := 0; first_m text; first_ct numeric; alts text; seqn int; who text;
begin
  if coalesce(public.cp_my_role(p_org), '') not in ('admin', 'editor') or not console.product_ok('capacity', p_org) then
    raise exception 'You need editor access to change the process master.';
  end if;
  select customer_id into cid from console.licences where product_code = 'capacity' and product_ref = p_org;
  if cid is null then raise exception 'This planner is not linked to a KMR customer.'; end if;
  pn := trim(coalesce(p_part ->> 'partNo', ''));
  if pn = '' then raise exception 'Part number is required.'; end if;
  pname := trim(coalesce(p_part ->> 'partName', ''));
  who := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'email', 'capacity-planner');
  delete from console.ops_records where customer_id = cid and kind = 'cycle_times' and data ->> 'part_no' = pn;
  if coalesce((p_part ->> 'delete')::boolean, false) then
    update console.ops_records set active = false, updated_at = now(), updated_by = who where customer_id = cid and kind = 'parts' and code = pn;
    return jsonb_build_object('ok', true, 'deleted', pn);
  end if;
  insert into console.ops_records (customer_id, kind, code, name, data, updated_by)
  values (cid, 'parts', pn, left(pname, 200), '{"status":"Production"}', who)
  on conflict (customer_id, kind, code) do update set name = case when excluded.name <> '' then excluded.name else console.ops_records.name end, active = true, updated_at = now(), updated_by = who;
  for st in select * from jsonb_array_elements(coalesce(p_part -> 'steps', '[]')) loop
    i := i + 1; first_m := null; first_ct := null; alts := ''; seqn := 0;
    for mc in select * from jsonb_array_elements(coalesce(st -> 'machines', '[]')) loop
      continue when trim(coalesce(mc ->> 'code', '')) = '';
      seqn := seqn + 1;
      if seqn = 1 then first_m := trim(mc ->> 'code'); first_ct := nullif(mc ->> 'ct', '')::numeric;
      else alts := alts || case when alts = '' then '' else ', ' end || trim(mc ->> 'code') || coalesce('=' || nullif(mc ->> 'ct', ''), ''); end if;
      insert into console.ops_records (customer_id, kind, code, name, data, updated_by)
      values (cid, 'machines', trim(mc ->> 'code'), trim(mc ->> 'code'), jsonb_build_object('cell', trim(regexp_replace(trim(mc ->> 'code'), '[-\s]*\d+$', ''))), who)
      on conflict (customer_id, kind, code) do nothing;
    end loop;
    insert into console.ops_records (customer_id, kind, code, name, data, updated_by)
    values (cid, 'cycle_times', left(pn || ' · ' || lpad(i::text, 2, '0') || ' ' || trim(coalesce(st ->> 'process', 'Process')), 80), trim(coalesce(st ->> 'process', 'Process')),
            jsonb_strip_nulls(jsonb_build_object('part_no', pn, 'machine', coalesce(first_m, ''), 'cycle_time_sec', coalesce(first_ct, 0), 'alternates', nullif(alts, ''),
              'op_type', case when st ->> 'source' = 'Supplier' then 'Supplier' end, 'sequence', i)), who);
  end loop;
  return jsonb_build_object('ok', true, 'part', pn, 'steps', i);
end $$;
revoke all on function public.kmr_capacity_master_save(uuid, jsonb) from public, anon;
grant execute on function public.kmr_capacity_master_save(uuid, jsonb) to authenticated;

-- Capacity masters now also return the supplier (outside) steps of a routing, flagged "supplier": true, so the Process Master shows the whole flow and
-- stock held at a supplier can be netted off. They carry no machine and load no days.
create or replace function public.kmr_capacity_masters(p_org uuid) returns jsonb
language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid; hrm_ref uuid; std jsonb; hol jsonb; names jsonb;
begin
  if public.cp_my_role(p_org) is null or not console.product_ok('capacity', p_org) then raise exception 'No access to this planner.'; end if;
  select customer_id into cid from console.licences where product_code = 'capacity' and product_ref = p_org;
  if cid is null then return null; end if;
  select data into std from console.ops_records where customer_id = cid and kind = 'plant_standards' and active order by updated_at desc limit 1;
  select product_ref into hrm_ref from console.licences where customer_id = cid and product_code = 'hrms' and product_ref is not null;   -- HRM & Payroll (0072)
  if hrm_ref is not null then
    select coalesce(jsonb_agg(to_char(hdate, 'YYYY-MM-DD') order by hdate), '[]'), coalesce(jsonb_object_agg(to_char(hdate, 'YYYY-MM-DD'), name), '{}')
      into hol, names from console.hrms_holidays where customer_id = cid;
  end if;
  return jsonb_build_object(
    'machines', coalesce((select jsonb_agg(jsonb_build_object('code', r.code, 'cell', coalesce(r.data ->> 'cell', r.data ->> 'type', ''),
        'availDays', nullif(r.data ->> 'available_days', '')::numeric, 'hoursPerDay', nullif(r.data ->> 'hours_per_day', '')::numeric,
        'remarks', coalesce(r.data ->> 'remarks', ''), 'active', r.active) order by r.code)
      from console.ops_records r where r.customer_id = cid and r.kind = 'machines'), '[]'),
    'operations', coalesce((select jsonb_agg(jsonb_build_object('id', row_number, 'partNo', x.part_no, 'partName', coalesce(p.name, x.part_no),
        'process', x.name, 'machine', x.machine, 'cycleTime', x.ct, 'supplier', (coalesce(x.otype, '') ilike 'supplier%'), 'alternates',
        coalesce((select jsonb_agg(trim(a)) from unnest(string_to_array(coalesce(x.alts, ''), ',')) a where trim(a) <> ''), '[]')) order by x.part_no, x.code)
      from (select row_number() over (order by r.data ->> 'part_no', r.code) row_number, r.code, r.name, r.data ->> 'part_no' part_no, r.data ->> 'machine' machine,
                   nullif(r.data ->> 'cycle_time_sec', '')::numeric ct, r.data ->> 'alternates' alts, r.data ->> 'op_type' otype
              from console.ops_records r where r.customer_id = cid and r.kind = 'cycle_times' and r.active) x
      left join console.ops_records p on p.customer_id = cid and p.kind = 'parts' and p.code = x.part_no), '[]'),
    'parts', coalesce((select jsonb_agg(jsonb_build_object('partNo', r.code, 'abcClass', upper(coalesce(nullif(r.data ->> 'abc_class', ''), 'B')),
        'minStockDays', nullif(r.data ->> 'min_stock_days', '')::numeric) order by r.code)
      from console.ops_records r where r.customer_id = cid and r.kind = 'parts' and r.active), '[]'),
    'standards', coalesce(std, '{}'), 'holidays', coalesce(hol, '[]'), 'holidayNames', coalesce(names, '{}'),
    'has_hrm', hrm_ref is not null);
end $$;
revoke all on function public.kmr_capacity_masters(uuid) from public, anon;
grant execute on function public.kmr_capacity_masters(uuid) to authenticated;
