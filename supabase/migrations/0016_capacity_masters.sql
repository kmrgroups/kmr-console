-- =====================================================================
-- KMR platform — the Capacity Planner uses the Operations Master (M7b). Needs 0010, 0011, 0015. Safe to re-run.
--  Machines → Operations Master › Machines · Parts & routings → › Parts + › Cycle times
--  Plant standards → Operations Master › Plant standards (new) · Working days: weekly off (Plant standards)
--  and the customer's HRM holiday calendar. The planner keeps only its monthly plans.
-- =====================================================================
alter table console.ops_records drop constraint if exists ops_records_kind_check;
alter table console.ops_records add constraint ops_records_kind_check check (kind in ('parts','customers','suppliers','machines','gauges','tools',
  'consumables','raw_materials','rate_contracts','cycle_times','cft','documents','plant_standards'));

-- The planner's masters, in the planner's own format, for one workspace (people with access to that planner)
create or replace function public.kmr_capacity_masters(p_org uuid) returns jsonb
language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid; hrm_ref uuid; std jsonb; hol jsonb; names jsonb;
begin
  if public.cp_my_role(p_org) is null or not console.product_ok('capacity', p_org) then raise exception 'No access to this planner.'; end if;
  select customer_id into cid from console.licences where product_code = 'capacity' and product_ref = p_org;
  if cid is null then return null; end if;
  select data into std from console.ops_records where customer_id = cid and kind = 'plant_standards' and active order by updated_at desc limit 1;
  select product_ref into hrm_ref from console.licences where customer_id = cid and product_code = 'hrm' and product_ref is not null;
  if hrm_ref is not null then
    select coalesce(jsonb_agg(to_char(holiday_date, 'YYYY-MM-DD') order by holiday_date), '[]'), coalesce(jsonb_object_agg(to_char(holiday_date, 'YYYY-MM-DD'), name), '{}')
      into hol, names from hrm.holidays where tenant_id = hrm_ref;
  end if;
  return jsonb_build_object(
    'machines', coalesce((select jsonb_agg(jsonb_build_object('code', r.code, 'cell', coalesce(r.data ->> 'cell', r.data ->> 'type', ''),
        'availDays', nullif(r.data ->> 'available_days', '')::numeric, 'hoursPerDay', nullif(r.data ->> 'hours_per_day', '')::numeric,
        'remarks', coalesce(r.data ->> 'remarks', ''), 'active', r.active) order by r.code)
      from console.ops_records r where r.customer_id = cid and r.kind = 'machines'), '[]'),
    'operations', coalesce((select jsonb_agg(jsonb_build_object('id', row_number, 'partNo', x.part_no, 'partName', coalesce(p.name, x.part_no),
        'process', x.name, 'machine', x.machine, 'cycleTime', x.ct, 'alternates',
        coalesce((select jsonb_agg(trim(a)) from unnest(string_to_array(coalesce(x.alts, ''), ',')) a where trim(a) <> ''), '[]')) order by x.part_no, x.code)
      from (select row_number() over (order by r.data ->> 'part_no', r.code) row_number, r.code, r.name, r.data ->> 'part_no' part_no, r.data ->> 'machine' machine,
                   nullif(r.data ->> 'cycle_time_sec', '')::numeric ct, r.data ->> 'alternates' alts
              from console.ops_records r where r.customer_id = cid and r.kind = 'cycle_times' and r.active) x
      left join console.ops_records p on p.customer_id = cid and p.kind = 'parts' and p.code = x.part_no), '[]'),
    'standards', coalesce(std, '{}'), 'holidays', coalesce(hol, '[]'), 'holidayNames', coalesce(names, '{}'),
    'has_hrm', hrm_ref is not null);
end $$;
revoke all on function public.kmr_capacity_masters(uuid) from public, anon;
grant execute on function public.kmr_capacity_masters(uuid) to authenticated;

-- One-time move: masters typed into the planner go to the Operations Master (planner admins; only fills what is missing)
create or replace function public.kmr_capacity_push_masters(p_org uuid, p jsonb) returns jsonb
language plpgsql security definer set search_path = console, public as $$
declare cid uuid; me text := lower(coalesce(auth.jwt() ->> 'email', '')); m jsonb; o jsonb; nm int := 0; np int := 0; nc int := 0;
begin
  if public.cp_my_role(p_org) is distinct from 'admin' then raise exception 'Only a planner administrator can move the masters.'; end if;
  select customer_id into cid from console.licences where product_code = 'capacity' and product_ref = p_org;
  for m in select * from jsonb_array_elements(coalesce(p -> 'machines', '[]')) loop
    insert into console.ops_records (customer_id, kind, code, name, data, active, updated_by)
    values (cid, 'machines', m ->> 'code', m ->> 'code', jsonb_strip_nulls(jsonb_build_object('cell', m ->> 'cell', 'available_days', m ->> 'availDays',
            'hours_per_day', m ->> 'hoursPerDay', 'remarks', nullif(m ->> 'remarks', ''))), coalesce((m ->> 'active')::boolean, true), me)
    on conflict (customer_id, kind, code) do nothing;
    nm := nm + 1;
  end loop;
  for o in select * from jsonb_array_elements(coalesce(p -> 'operations', '[]')) loop
    insert into console.ops_records (customer_id, kind, code, name, data, updated_by)
    values (cid, 'parts', o ->> 'partNo', coalesce(o ->> 'partName', ''), '{}', me) on conflict (customer_id, kind, code) do nothing;
    insert into console.ops_records (customer_id, kind, code, name, data, updated_by)
    values (cid, 'cycle_times', left((o ->> 'partNo') || ' · ' || (o ->> 'process'), 80), coalesce(o ->> 'process', ''),
            jsonb_strip_nulls(jsonb_build_object('part_no', o ->> 'partNo', 'machine', o ->> 'machine', 'cycle_time_sec', o ->> 'cycleTime',
              'alternates', nullif(array_to_string(array(select jsonb_array_elements_text(coalesce(o -> 'alternates', '[]'))), ', '), ''))), me)
    on conflict (customer_id, kind, code) do nothing;
    nc := nc + 1;
  end loop;
  select count(distinct o2 ->> 'partNo') into np from jsonb_array_elements(coalesce(p -> 'operations', '[]')) o2;
  if p ? 'standards' then
    insert into console.ops_records (customer_id, kind, code, name, data, updated_by)
    values (cid, 'plant_standards', 'PLANT', 'Plant standards', p -> 'standards', me) on conflict (customer_id, kind, code) do nothing;
  end if;
  return jsonb_build_object('machines', nm, 'parts', np, 'cycle_times', nc);
end $$;
revoke all on function public.kmr_capacity_push_masters(uuid, jsonb) from public, anon;
grant execute on function public.kmr_capacity_push_masters(uuid, jsonb) to authenticated;
