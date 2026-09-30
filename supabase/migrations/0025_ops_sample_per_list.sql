-- =====================================================================
-- Operations Master — sample data per list, and consumables by process. Needs 0024. Safe to re-run.
--  • kmr_ops_sample_load(slug, kind) / kmr_ops_sample_flush(slug, kind): load or flush ONE list's sample records
--    (the whole-master versions stay: kmr_ops_sample_load(slug) / kmr_ops_sample_flush(slug))
--  • kmr_ops_counts adds the sample count of every list ("_sample_<list>")
--  • Consumables carry "processes" (Process Documents codes such as TURN1, VMC); Process Documents lists them per process
-- =====================================================================
do $$ begin
  if to_regprocedure('public.kmr_pd_masters(uuid)') is null then raise exception 'Run 0024_ops_links.sql first.'; end if;
end $$;

-- which processes the sample consumables are used in
create or replace function console.ops_sample_processes(p_code text) returns text language sql immutable as $$
  select case p_code
    when 'CN-001' then 'TURN1, TURN2, VMC, DRILL, HOB, BROACH'
    when 'CN-002' then 'TURN1, TURN2, VMC, HOB'
    when 'CN-003' then 'TURN1, TURN2, VMC, CGRIND'
    when 'CN-004' then 'CGRIND, IGRIND, SGRIND'
    when 'CN-005' then 'TURN1, TURN2, VMC, DEBURR'
    when 'CN-006' then 'WASH, PACK'
    when 'CN-007' then 'PACK'
    when 'CN-008' then 'DEBURR, WASH, FINAL, PACK'
  end
$$;

create or replace function console.ops_sample_insert(p_customer uuid, p_kind text, p_by text) returns jsonb
language plpgsql security definer set search_path = console, public as $$
declare r jsonb; added int := 0; skipped int := 0; n int; d jsonb;
begin
  for r in select * from jsonb_array_elements(console.ops_sample()) x where p_kind is null or x ->> 'kind' = p_kind loop
    if r ->> 'kind' = 'plant_standards'
       and exists (select 1 from console.ops_records where customer_id = p_customer and kind = 'plant_standards' and not sample) then
      skipped := skipped + 1; continue;
    end if;
    d := console.ops_sample_dates(r -> 'data');
    if r ->> 'kind' = 'consumables' and console.ops_sample_processes(r ->> 'code') is not null and not (d ? 'processes') then
      d := d || jsonb_build_object('processes', console.ops_sample_processes(r ->> 'code'));
    end if;
    insert into console.ops_records (customer_id, kind, code, name, data, active, sample, updated_by)
    values (p_customer, r ->> 'kind', r ->> 'code', coalesce(r ->> 'name', ''), d, true, true, p_by)
    on conflict (customer_id, kind, code) do nothing;
    get diagnostics n = row_count;
    if n = 1 then added := added + 1; else skipped := skipped + 1; end if;
  end loop;
  return jsonb_build_object('added', added, 'skipped', skipped);
end $$;

create or replace function console.ops_admin_customer(p_slug text) returns uuid
language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or console.ops_role(cid) is distinct from 'admin' then
    raise exception 'Only an Operations Master administrator can load or flush sample data.';
  end if;
  return cid;
end $$;

-- whole master (unchanged behaviour, now with consumable processes)
create or replace function public.kmr_ops_sample_load(p_slug text) returns jsonb
language plpgsql security definer set search_path = console, public as $$
begin
  return console.ops_sample_insert(console.ops_admin_customer(p_slug), null, lower(coalesce(auth.jwt() ->> 'email', '')));
end $$;

-- one list
create or replace function public.kmr_ops_sample_load(p_slug text, p_kind text) returns jsonb
language plpgsql security definer set search_path = console, public as $$
begin
  return console.ops_sample_insert(console.ops_admin_customer(p_slug), p_kind, lower(coalesce(auth.jwt() ->> 'email', '')));
end $$;

create or replace function public.kmr_ops_sample_flush(p_slug text, p_kind text) returns integer
language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.ops_admin_customer(p_slug); n int;
begin
  delete from console.ops_records where customer_id = cid and kind = p_kind and sample;
  get diagnostics n = row_count;
  return n;
end $$;

revoke all on function public.kmr_ops_sample_load(text), public.kmr_ops_sample_load(text, text), public.kmr_ops_sample_flush(text, text) from public, anon;
grant execute on function public.kmr_ops_sample_load(text), public.kmr_ops_sample_load(text, text), public.kmr_ops_sample_flush(text, text) to authenticated;
revoke all on function console.ops_sample_insert(uuid, text, text), console.ops_admin_customer(text) from public, anon, authenticated;

-- counts: records in use per list, sample records in total and per list
create or replace function public.kmr_ops_counts(p_slug text) returns jsonb
language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or console.ops_role(cid) is null then raise exception 'You have no access to the Operations Master.'; end if;
  return coalesce((select jsonb_object_agg(kind, n) from (select kind, count(*) n from console.ops_records where customer_id = cid and active group by kind) x), '{}')
      || coalesce((select jsonb_object_agg('_sample_' || kind, n) from (select kind, count(*) n from console.ops_records where customer_id = cid and sample group by kind) y), '{}')
      || jsonb_build_object('_sample', (select count(*) from console.ops_records where customer_id = cid and sample));
end $$;
grant execute on function public.kmr_ops_counts(text) to authenticated;

-- Console › Test data demo loader uses the same sample (with consumable processes)
create or replace function console.ops_demo_load(p_customer uuid) returns integer
language plpgsql security definer set search_path = console, public as $$
begin
  return (console.ops_sample_insert(p_customer, null, 'KMR demo data') ->> 'added')::int;
end $$;
revoke all on function console.ops_demo_load(uuid) from public, anon, authenticated;
grant execute on function console.ops_demo_load(uuid) to service_role;

-- sample consumables already loaded get their processes too
update console.ops_records set data = data || jsonb_build_object('processes', console.ops_sample_processes(code))
 where kind = 'consumables' and sample and not (data ? 'processes') and console.ops_sample_processes(code) is not null;

-- Process Documents: consumables grouped by process (from each consumable's "processes")
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

-- Saving (form, CSV or Excel upload): a sample record stays "sample" unless something in it actually changed,
-- so uploading a downloaded workbook unchanged does not turn every sample record into your own.
create or replace function public.kmr_ops_save(p_slug text, p_kind text, p_rows jsonb) returns integer
language plpgsql security definer set search_path = console, public as $$
declare cid uuid; r jsonb; n integer := 0; me text := lower(coalesce(auth.jwt() ->> 'email', ''));
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or coalesce(console.ops_role(cid), '') not in ('admin','editor') then
    raise exception 'You can view the Operations Master but not change it. Ask your administrator for editor access.';
  end if;
  for r in select * from jsonb_array_elements(case when jsonb_typeof(p_rows) = 'array' then p_rows else jsonb_build_array(p_rows) end) loop
    if length(trim(coalesce(r ->> 'code', ''))) = 0 then raise exception 'Every record needs a code / number.'; end if;
    if r ? 'id' and (r ->> 'id') ~ '^[0-9a-f-]{36}$' then
      update console.ops_records o set code = trim(r ->> 'code'), name = coalesce(trim(r ->> 'name'), ''),
             data = coalesce(r -> 'data', '{}'), active = coalesce((r ->> 'active')::boolean, true),
             sample = o.sample and o.code = trim(r ->> 'code') and o.name = coalesce(trim(r ->> 'name'), '') and o.data = coalesce(r -> 'data', '{}')
                      and o.active = coalesce((r ->> 'active')::boolean, true),
             updated_at = now(), updated_by = me
       where o.id = (r ->> 'id')::uuid and o.customer_id = cid and o.kind = p_kind;
    else
      insert into console.ops_records as o (customer_id, kind, code, name, data, active, updated_by)
      values (cid, p_kind, trim(r ->> 'code'), coalesce(trim(r ->> 'name'), ''), coalesce(r -> 'data', '{}'), coalesce((r ->> 'active')::boolean, true), me)
      on conflict (customer_id, kind, code) do update set name = excluded.name, data = o.data || excluded.data, active = excluded.active,
         sample = o.sample and o.name = excluded.name and o.data @> excluded.data and o.active = excluded.active,
         updated_at = now(), updated_by = me;
    end if;
    n := n + 1;
  end loop;
  return n;
end $$;
grant execute on function public.kmr_ops_save(text, text, jsonb) to authenticated;
