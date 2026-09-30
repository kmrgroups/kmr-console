-- =====================================================================
-- KMR platform — Process Documents uses the Operations Master. Needs 0015–0017. Safe to re-run.
--  • kmr_pd_masters(workspace): the customer's machines, gauges, customers and parts, in Process Documents' own format
--  • kmr_pd_push_masters(workspace, lists): one-time move of lists typed into Process Documents (fills only what is missing)
-- Customers' Operations Master data stays theirs: only members of that customer's own workspace can read it.
-- =====================================================================
do $$ begin
  if to_regclass('console.ops_records') is null then raise exception 'Run 0015_operations_master.sql first.'; end if;
end $$;

-- the signed-in person's role in a Process Documents workspace (null = not a member)
create or replace function public.kmr_pd_role(p_org uuid) returns text
language sql stable security definer set search_path = console, public as $$
  select coalesce(
    (select m.role from public.pd_members m where m.org_id = p_org and lower(m.email) = lower(coalesce(auth.jwt() ->> 'email', '')) limit 1),
    (select 'admin' from public.pd_platform_admins a where a.user_id = auth.uid() limit 1))
$$;

-- Operations Master machine type → the process codes Process Documents plans with
create or replace function console.pd_keys_for(p_type text, p_processes text) returns jsonb
language sql immutable as $$
  select case
    when coalesce(trim(p_processes), '') <> '' then
      (select coalesce(jsonb_agg(upper(trim(x))), '[]') from unnest(string_to_array(p_processes, ',')) x where trim(x) <> '')
    when p_type ilike 'cnc turning%' then '["TURN1","TURN2"]'::jsonb
    when p_type in ('VMC','HMC') then '["VMC"]'::jsonb
    when p_type ilike 'grinding%' then '["CGRIND"]'::jsonb
    when p_type ilike 'gear hobbing%' then '["HOB"]'::jsonb
    when p_type ilike 'broaching%' then '["BROACH"]'::jsonb
    when p_type ilike 'inspection%' then '["FINAL"]'::jsonb
    else '[]'::jsonb end
$$;

create or replace function public.kmr_pd_masters(p_org uuid) returns jsonb
language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid;
begin
  if public.kmr_pd_role(p_org) is null then raise exception 'No access to this workspace.'; end if;
  select customer_id into cid from console.licences where product_code = 'pd' and product_ref = p_org;
  if cid is null then return null; end if;                       -- a workspace not linked to a customer keeps its own lists
  return jsonb_build_object(
    'machines', coalesce((select jsonb_agg(jsonb_build_object(
        'id', r.code, 'name', r.name, 'make', coalesce(r.data ->> 'make', ''), 'model', coalesce(r.data ->> 'model', ''),
        'capacity', coalesce(r.data ->> 'capacity', ''), 'keys', console.pd_keys_for(r.data ->> 'type', r.data ->> 'processes'),
        'maxDia', nullif(r.data ->> 'max_size_mm', '')::numeric, 'cap', nullif(r.data ->> 'capability_mm', '')::numeric,
        'location', coalesce(nullif(r.data ->> 'cell', ''), r.data ->> 'location', ''), 'pm', coalesce(r.data ->> 'pm_frequency', '')) order by r.code)
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
    'parts', coalesce((select jsonb_agg(jsonb_build_object(
        'partNo', r.code, 'partName', r.name, 'drawingNo', coalesce(r.data ->> 'drawing_no', ''), 'rev', coalesce(r.data ->> 'revision', ''),
        'material', coalesce(r.data ->> 'material', ''), 'customer', coalesce(r.data ->> 'customer', '')) order by r.code)
      from console.ops_records r where r.customer_id = cid and r.kind = 'parts' and r.active), '[]'));
end $$;
revoke all on function public.kmr_pd_masters(uuid) from public, anon;
grant execute on function public.kmr_pd_masters(uuid) to authenticated;

-- One-time move: lists typed into Process Documents go to the Operations Master (workspace admins; fills only what is missing)
create or replace function public.kmr_pd_push_masters(p_org uuid, p jsonb) returns jsonb
language plpgsql security definer set search_path = console, public as $$
declare cid uuid; me text := lower(coalesce(auth.jwt() ->> 'email', '')); x jsonb; nm int := 0; ng int := 0; nc int := 0; k int; v_code text;
begin
  if public.kmr_pd_role(p_org) is distinct from 'admin' then raise exception 'Only a workspace administrator can move the lists.'; end if;
  select customer_id into cid from console.licences where product_code = 'pd' and product_ref = p_org;
  if cid is null then raise exception 'This workspace is not linked to a KMR customer.'; end if;
  for x in select * from jsonb_array_elements(coalesce(p -> 'machines', '[]')) loop
    v_code := left(coalesce(nullif(trim(x ->> 'id'), ''), nullif(trim(x ->> 'name'), '')), 80);
    continue when v_code is null;
    insert into console.ops_records (customer_id, kind, code, name, data, updated_by)
    values (cid, 'machines', v_code, left(coalesce(x ->> 'name', v_code), 200), jsonb_strip_nulls(jsonb_build_object(
      'make', nullif(x ->> 'make', ''), 'model', nullif(x ->> 'model', ''), 'capacity', nullif(x ->> 'capacity', ''),
      'processes', nullif(case when jsonb_typeof(x -> 'keys') = 'array' then array_to_string(array(select jsonb_array_elements_text(x -> 'keys')), ', ') else x ->> 'keys' end, ''),
      'max_size_mm', nullif(x ->> 'maxDia', ''), 'capability_mm', nullif(x ->> 'cap', ''), 'cell', nullif(x ->> 'location', ''), 'pm_frequency', nullif(x ->> 'pm', ''))), me)
    on conflict (customer_id, kind, code) do nothing;
    get diagnostics k = row_count; nm := nm + k;
  end loop;
  for x in select * from jsonb_array_elements(coalesce(p -> 'gauges', '[]')) loop
    v_code := left(coalesce(nullif(trim(x ->> 'id'), ''), nullif(trim(x ->> 'name'), '')), 80);
    continue when v_code is null;
    insert into console.ops_records (customer_id, kind, code, name, data, updated_by)
    values (cid, 'gauges', v_code, left(coalesce(x ->> 'name', v_code), 200), jsonb_strip_nulls(jsonb_build_object(
      'range', nullif(x ->> 'range', ''), 'least_count', nullif(x ->> 'lc', ''), 'location', nullif(x ->> 'location', ''),
      'next_due', case when (x ->> 'calDue') ~ '^\d{4}-\d{2}-\d{2}$' then x ->> 'calDue' end,
      'cal_freq_months', nullif(substring(coalesce(x ->> 'calFreq', '') from '(\d+)'), ''))), me)
    on conflict (customer_id, kind, code) do nothing;
    get diagnostics k = row_count; ng := ng + k;
  end loop;
  for x in select * from jsonb_array_elements(coalesce(p -> 'customers', '[]')) loop
    v_code := left(upper(regexp_replace(coalesce(nullif(trim(x ->> 'name'), ''), ''), '[^A-Za-z0-9]+', '-', 'g')), 40);
    continue when coalesce(v_code, '') = '';
    insert into console.ops_records (customer_id, kind, code, name, data, updated_by)
    values (cid, 'customers', v_code, left(x ->> 'name', 200), jsonb_strip_nulls(jsonb_build_object(
      'supplier_code', nullif(x ->> 'code', ''), 'address', nullif(x ->> 'address', ''), 'contact', nullif(x ->> 'contact', ''),
      'cc_symbol', nullif(x ->> 'ccSym', ''), 'sc_symbol', nullif(x ->> 'scSym', ''), 'approval', nullif(x ->> 'approval', ''))), me)
    on conflict (customer_id, kind, code) do nothing;
    get diagnostics k = row_count; nc := nc + k;
  end loop;
  return jsonb_build_object('machines', nm, 'gauges', ng, 'customers', nc);
end $$;
revoke all on function public.kmr_pd_push_masters(uuid, jsonb) from public, anon;
grant execute on function public.kmr_pd_push_masters(uuid, jsonb) to authenticated;
revoke all on function public.kmr_pd_role(uuid) from public, anon;
grant execute on function public.kmr_pd_role(uuid) to authenticated;
