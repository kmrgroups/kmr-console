-- 0121 — ERP purchase masters into the Operations Master (no duplicates) and ERP production history in MMD
-- Needs 0015 (Operations Master) and 0058 (MMD). Safe to re-run.

create index if not exists ops_records_normcode on console.ops_records (customer_id, kind, (regexp_replace(lower(code), '[^a-z0-9]', '', 'g')));

-- add many records to the Operations Master: a record whose code (ignoring case, spaces and dashes) or name is already there is skipped; blank fields of an existing record are filled, nothing typed by a person is overwritten
create or replace function public.kmr_ops_bulk(p_slug text, p_rows jsonb) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid; r jsonb; k text; c text; nm text; nc text; nn text; ex uuid; added int := 0; skipped int := 0; filled int := 0; me text := lower(coalesce(auth.jwt() ->> 'email', ''));
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or coalesce(console.ops_role(cid), '') not in ('admin', 'editor') then raise exception 'You can view the Operations Master but not change it. Ask your administrator for editor access.'; end if;
  for r in select * from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) loop
    k := r ->> 'kind'; c := left(trim(coalesce(r ->> 'code', '')), 80); nm := left(trim(coalesce(nullif(r ->> 'name', ''), c)), 200);
    if c = '' or k is null then continue; end if;
    nc := regexp_replace(lower(c), '[^a-z0-9]', '', 'g'); nn := regexp_replace(lower(nm), '[^a-z0-9]', '', 'g');
    select id into ex from console.ops_records where customer_id = cid and kind = k and (regexp_replace(lower(code), '[^a-z0-9]', '', 'g') = nc or (length(nn) > 6 and regexp_replace(lower(name), '[^a-z0-9]', '', 'g') = nn)) limit 1;
    if ex is null then
      insert into console.ops_records (customer_id, kind, code, name, data, active, updated_by) values (cid, k, c, nm, coalesce(r -> 'data', '{}'::jsonb), coalesce((r ->> 'active')::boolean, true), me) on conflict (customer_id, kind, code) do nothing;
      if found then added := added + 1; else skipped := skipped + 1; end if;
    else
      update console.ops_records o set data = coalesce(r -> 'data', '{}'::jsonb) || o.data, updated_at = now() where o.id = ex and not (coalesce(r -> 'data', '{}'::jsonb) <@ o.data);
      if found then filled := filled + 1; else skipped := skipped + 1; end if;
    end if;
  end loop;
  return jsonb_build_object('added', added, 'skipped', skipped, 'filled', filled);
end $$;

-- ---------- ERP production history (MMD) ----------
create table if not exists console.mmd_hist (
  id bigserial primary key, customer_id uuid not null references console.customers(id) on delete cascade,
  ref text not null, prod_date date not null, shift text, machine text, operator text, part_code text, part_name text, process text, rm_code text, batch text,
  hours numeric, qty numeric, cycle_time numeric, bars numeric, scrap numeric, eff numeric, idle_hrs numeric, mc_hrs numeric, plan_hrs numeric, d_codes text, reasons text,
  unique (customer_id, ref));
create index if not exists mmd_hist_date on console.mmd_hist (customer_id, prod_date);
create index if not exists mmd_hist_mc on console.mmd_hist (customer_id, machine, prod_date);
create index if not exists mmd_hist_part on console.mmd_hist (customer_id, part_code, prod_date);
alter table console.mmd_hist enable row level security;
drop policy if exists mmd_hist_staff on console.mmd_hist;
create policy mmd_hist_staff on console.mmd_hist for all to authenticated using (console.is_staff()) with check (console.is_staff());

create or replace function public.kmr_mmd_hist_import(p_slug text, p_rows jsonb) returns int language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'mmd'); n int;
begin
  if console.qp_role(cid, 'mmd') <> 'admin' then raise exception 'Only an administrator can import the ERP production history.'; end if;
  insert into console.mmd_hist (customer_id, ref, prod_date, shift, machine, operator, part_code, part_name, process, rm_code, batch, hours, qty, cycle_time, bars, scrap, eff, idle_hrs, mc_hrs, plan_hrs, d_codes, reasons)
  select cid, v ->> 0, (v ->> 1)::date, nullif(v ->> 2, ''), nullif(v ->> 3, ''), nullif(v ->> 4, ''), nullif(v ->> 5, ''), nullif(v ->> 6, ''), nullif(v ->> 7, ''), nullif(v ->> 8, ''), nullif(v ->> 9, ''),
    (v ->> 10)::numeric, (v ->> 11)::numeric, (v ->> 12)::numeric, (v ->> 13)::numeric, (v ->> 14)::numeric, (v ->> 15)::numeric, (v ->> 16)::numeric, (v ->> 17)::numeric, (v ->> 18)::numeric, nullif(v ->> 19, ''), nullif(v ->> 20, '')
  from jsonb_array_elements(p_rows) v on conflict (customer_id, ref) do nothing;
  get diagnostics n = row_count; return n;
end $$;

-- lists for the filter dropdowns
create or replace function public.kmr_mmd_hist_facets(p_slug text) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'mmd');
begin
  return jsonb_build_object('machines', coalesce((select jsonb_agg(x order by x) from (select distinct machine x from console.mmd_hist where customer_id = cid and machine is not null) z), '[]'::jsonb),
    'parts', coalesce((select jsonb_agg(x order by x) from (select distinct part_code x from console.mmd_hist where customer_id = cid and part_code is not null) z), '[]'::jsonb),
    'operators', coalesce((select jsonb_agg(x order by x) from (select distinct operator x from console.mmd_hist where customer_id = cid and operator is not null) z), '[]'::jsonb),
    'shifts', coalesce((select jsonb_agg(x order by x) from (select distinct shift x from console.mmd_hist where customer_id = cid and shift is not null) z), '[]'::jsonb),
    'total', (select count(*) from console.mmd_hist where customer_id = cid), 'first', (select min(prod_date) from console.mmd_hist where customer_id = cid), 'last', (select max(prod_date) from console.mmd_hist where customer_id = cid));
end $$;

-- search by period and (several) machines, parts, operators, shifts
create or replace function public.kmr_mmd_hist_find(p_slug text, p_from date, p_to date, p_machines text[] default null, p_parts text[] default null, p_operators text[] default null, p_shifts text[] default null, p_q text default null, p_limit int default 2000) returns jsonb
language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'mmd'); q text := nullif(trim(coalesce(p_q, '')), ''); lim int := greatest(100, least(coalesce(p_limit, 2000), 5000));
begin
  return (with f as (select * from console.mmd_hist h where h.customer_id = cid and (p_from is null or h.prod_date >= p_from) and (p_to is null or h.prod_date <= p_to)
      and (coalesce(cardinality(p_machines), 0) = 0 or h.machine = any (p_machines)) and (coalesce(cardinality(p_parts), 0) = 0 or h.part_code = any (p_parts))
      and (coalesce(cardinality(p_operators), 0) = 0 or h.operator = any (p_operators)) and (coalesce(cardinality(p_shifts), 0) = 0 or h.shift = any (p_shifts))
      and (q is null or concat_ws(' ', h.machine, h.operator, h.part_code, h.part_name, h.process, h.reasons) ilike '%' || q || '%'))
    select jsonb_build_object('rows', coalesce((select jsonb_agg(jsonb_build_array(ref, prod_date, shift, machine, operator, part_code, part_name, process, rm_code, batch, hours, qty, cycle_time, scrap, eff, idle_hrs, plan_hrs, d_codes, reasons)) from (select * from f order by prod_date desc, ref desc limit lim) z), '[]'::jsonb),
      'total', (select count(*) from f), 'qty', (select coalesce(sum(qty), 0) from f), 'hours', (select coalesce(sum(hours), 0) from f), 'idle', (select coalesce(sum(idle_hrs), 0) from f),
      'scrap', (select coalesce(sum(scrap), 0) from f), 'eff', (select round(avg(nullif(eff, 0)), 1) from f where qty > 0)));
end $$;

do $$ declare f record; begin
  for f in select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and (p.proname = 'kmr_ops_bulk' or p.proname ~ '^kmr_mmd_hist_') loop
    execute format('revoke all on function %s from public, anon', f.sig); execute format('grant execute on function %s to authenticated', f.sig);
  end loop; end $$;
