-- =====================================================================
-- KMR platform — the Capacity Planner pulls its work from the other apps:
--   part · process · machine  ← Process Documents › Process plan (the latest project of each part; machines are Operations Master machine codes)
--   cycle time per operation  ← Operations Master › Cycle times
--   sales quantity + date      ← Sales Flow (monthly plan: demand per part)
-- Needs 0015, 0016, 0033. Safe to re-run.
-- =====================================================================
create or replace function public.kmr_capacity_pull(p_org uuid, p_month date default null) returns jsonb
language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid; pd_org uuid; m date := date_trunc('month', coalesce(p_month, current_date))::date; v_plan jsonb := '[]'; v_sales jsonb := '[]';
begin
  if public.cp_my_role(p_org) is null or not console.product_ok('capacity', p_org) then raise exception 'No access to this planner.'; end if;
  select customer_id into cid from console.licences where product_code = 'capacity' and product_ref = p_org;
  if cid is null then return null; end if;
  select product_ref into pd_org from console.licences where customer_id = cid and product_code = 'pd' and product_ref is not null limit 1;
  if pd_org is not null then
    select coalesce(jsonb_agg(s.x order by s.x ->> 'partNo'), '[]') into v_plan from (
      select distinct on (p.part_no) jsonb_build_object('partNo', p.part_no, 'partName', coalesce(p.part_name, ''), 'rev', coalesce(p.rev, ''), 'updated', p.updated_at,
          'ops', coalesce((select jsonb_agg(jsonb_build_object('opNo', o ->> 'opNo', 'name', o ->> 'name', 'key', o ->> 'key',
                      'inHouse', coalesce((o ->> 'inHouse')::boolean, true), 'machineId', coalesce(o ->> 'machineId', ''), 'machine', coalesce(o ->> 'machine', ''))
                      order by coalesce(nullif(o ->> 'opNo', '')::numeric, 0))
                    from jsonb_array_elements(coalesce(p.doc -> 'plan' -> 'ops', '[]'::jsonb)) o), '[]')) as x
        from public.pd_projects p where p.org_id = pd_org and coalesce(p.part_no, '') <> '' order by p.part_no, p.updated_at desc) s;
  end if;
  if to_regclass('console.sf_lines') is not null then
    select coalesce(jsonb_agg(jsonb_build_object('partNo', t.part_code, 'qty', t.q, 'due', t.d)), '[]') into v_sales from (
      select l.part_code, sum(l.demand_qty) q, min(case when l.sched_type = 'date' then l.sched_date end) d
        from console.sf_lines l where l.customer_id = cid and l.month = m group by l.part_code) t;
  end if;
  return jsonb_build_object('hasPd', pd_org is not null, 'plan', v_plan, 'sales', v_sales,
    'cycleTimes', coalesce((select jsonb_agg(jsonb_build_object('partNo', r.data ->> 'part_no', 'machine', coalesce(r.data ->> 'machine', ''), 'process', r.name,
        'ct', nullif(r.data ->> 'cycle_time_sec', '')::numeric, 'alternates', coalesce(r.data ->> 'alternates', '')))
      from console.ops_records r where r.customer_id = cid and r.kind = 'cycle_times' and r.active), '[]'));
end $$;
revoke all on function public.kmr_capacity_pull(uuid, date) from public, anon;
grant execute on function public.kmr_capacity_pull(uuid, date) to authenticated;
