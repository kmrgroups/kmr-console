-- KMR 0174 — Production plan (ppl): customer schedule (Sales Flow) + supermarket qty + stage stock netted back through the route, stage by stage.
-- Two views: part / process wise quantity and machine wise parts / process / quantity. Auto-pulled from Sales Flow (schedule, despatched), MMD / ERP (stage stock, routes, cycle times), RMP (supermarket qty).
-- Every figure can also be typed in by hand. A published plan feeds Machine loading plan, Raw material plan, Capacity and the budget plans. Safe to re-run.
insert into console.products (code, name, description, app_path, seat_label, current_version, sort_order) values
  ('ppl', 'Production plan', 'Customer schedule less stock at every stage, plus supermarket quantity, gives the quantity to make at each process and on each machine', '/it/ppl.html', 'users', '1.0.0', 176)
on conflict (code) do update set name = excluded.name, description = excluded.description, app_path = excluded.app_path;
insert into console.releases (product_code, version, notes) values ('ppl', '1.0.0', 'Production plan: stage-wise netting, part/process and machine views, auto-pull from Sales Flow / MMD / RMP, manual entry, publish')
on conflict do nothing;
insert into console.prices (product_code, period, currency, unit_amount, min_seats, active, note)
select v.code, v.period, 'INR', v.amt, 1, true, 'Starting price list (0174) — change in Console • Billing' from (values ('ppl', 'month', 1500), ('ppl', 'year', 15000)) v(code, period, amt)
on conflict (product_code, period, currency) do nothing;
insert into public.app_listings (code, name, tagline, features, sort_order, is_active) values
  ('ppl', 'Production plan', 'Turn the customer schedule into what to make at every process and on every machine, after counting the stock already in each stage.',
   E'Customer schedule from Sales Flow, less despatched\nSupermarket quantity and stage stock, typed in or pulled from MMD\nPart and process wise quantity, machine wise quantity and hours\nPublished plan feeds Machine loading, Raw material, Capacity and budgets', 176, true)
on conflict (code) do update set name = excluded.name, tagline = coalesce(public.app_listings.tagline, excluded.tagline), features = coalesce(public.app_listings.features, excluded.features);
insert into console.app_features (product_code, name, detail, is_core, price_month, price_year, setup_fee, sort_order) values
  ('ppl', 'Stage-wise production plan', 'Schedule less stage stock, supermarket quantity, part/process and machine views', true, 1500, 0, 3000, 10)
on conflict (product_code, name) do nothing;

create table if not exists console.ppl_super (customer_id uuid not null references console.customers(id) on delete cascade, part_code text not null, qty numeric not null default 0 check (qty >= 0), updated_by text, updated_at timestamptz not null default now(), primary key (customer_id, part_code));
create table if not exists console.ppl_stock (customer_id uuid not null references console.customers(id) on delete cascade, part_code text not null, seq int not null, qty numeric not null default 0 check (qty >= 0), updated_by text, updated_at timestamptz not null default now(), primary key (customer_id, part_code, seq));
create table if not exists console.ppl_demand (id uuid primary key default gen_random_uuid(), customer_id uuid not null references console.customers(id) on delete cascade, month text not null check (month ~ '^\d{4}-(0[1-9]|1[0-2])$'),
  part_code text not null, part_name text, qty numeric not null default 0 check (qty >= 0), due date, note text, updated_by text, updated_at timestamptz not null default now());
create table if not exists console.ppl_cfg (customer_id uuid not null references console.customers(id) on delete cascade, k text not null, v numeric not null, primary key (customer_id, k));
create table if not exists console.ppl_plan (id uuid primary key default gen_random_uuid(), customer_id uuid not null references console.customers(id) on delete cascade, month text not null, version int not null,
  rows jsonb not null default '[]', summary jsonb not null default '{}', published_by text, published_at timestamptz not null default now(), unique (customer_id, month, version));
do $$ declare t text; begin
  foreach t in array array['ppl_super','ppl_stock','ppl_demand','ppl_cfg','ppl_plan'] loop
    execute format('alter table console.%I enable row level security', t);
    execute format('drop policy if exists %I on console.%I', t || '_staff', t);
    execute format('create policy %I on console.%I for all to authenticated using (console.is_staff()) with check (console.is_staff())', t || '_staff', t);
  end loop;
end $$;

-- everything the screens need. part codes are matched ignoring the ERP revision tail ("-01")
create or replace function console.ppl_data(cid uuid, p_month text) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare m0 date := (p_month || '-01')::date; out jsonb; d0 date := (now() at time zone 'Asia/Kolkata')::date - 59;
begin
  if p_month !~ '^\d{4}-(0[1-9]|1[0-2])$' then raise exception 'Month must look like 2026-11.'; end if;
  with dem as (
    select l.part_code, max(l.part_name) part_name, sum(l.demand_qty) demand, coalesce(sum((select sum(d.qty) from console.sf_despatch d where d.line_id = l.id)), 0) despatched, min(l.sched_date) due, 'Sales Flow'::text src
      from console.sf_lines l where l.customer_id = cid and l.month = m0 group by l.part_code
    union all
    select d.part_code, max(d.part_name), sum(d.qty), 0, min(d.due), 'Manual' from console.ppl_demand d where d.customer_id = cid and d.month = p_month group by d.part_code),
  parts as (select part_code, max(part_name) part_name, sum(demand) demand, sum(despatched) despatched, min(due) due, string_agg(distinct src, ' + ') src from dem group by part_code),
  rt as (select p.part_code, console.mmd_route(cid, p.part_code) r from parts p),
  erp as (select regexp_replace(h.part_code, '-[0-9A-Za-z]{1,2}$', '') pc, upper(trim(h.process)) pr, round(sum(h.qty)) q,
                 (array_agg(h.machine order by h.prod_date desc) filter (where coalesce(h.machine, '') <> ''))[1] mc
            from console.mmd_hist h where h.customer_id = cid and h.prod_date >= d0 and h.qty > 0 and coalesce(h.process, '') <> '' and h.process <> 'No production' group by 1, 2)
  select jsonb_build_object(
    'month', p_month,
    'parts', coalesce((select jsonb_agg(jsonb_build_object('part', p.part_code, 'name', p.part_name, 'demand', p.demand, 'despatched', p.despatched, 'due', p.due, 'src', p.src,
        'route', coalesce(rt.r, '[]'::jsonb),
        'erp', coalesce((select jsonb_object_agg(e.pr, e.q) from erp e where e.pc = regexp_replace(p.part_code, '-[0-9A-Za-z]{1,2}$', '')), '{}'::jsonb),
        'erp_mc', coalesce((select jsonb_object_agg(e.pr, e.mc) from erp e where e.pc = regexp_replace(p.part_code, '-[0-9A-Za-z]{1,2}$', '') and e.mc is not null), '{}'::jsonb)) order by p.part_code)
        from parts p join rt on rt.part_code = p.part_code), '[]'::jsonb),
    'super', coalesce((select jsonb_object_agg(part_code, qty) from console.ppl_super where customer_id = cid), '{}'::jsonb),
    'rmp_super', coalesce((select jsonb_object_agg(part_code, rrs_qty) from console.rmp_partstock where customer_id = cid and month = p_month and rrs_qty > 0), '{}'::jsonb),
    'stock', coalesce((select jsonb_agg(jsonb_build_object('part', part_code, 'seq', seq, 'qty', qty)) from console.ppl_stock where customer_id = cid), '[]'::jsonb),
    'manual', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'part', part_code, 'name', part_name, 'qty', qty, 'due', due, 'note', note) order by part_code) from console.ppl_demand where customer_id = cid and month = p_month), '[]'::jsonb),
    'cfg', coalesce((select jsonb_object_agg(k, v) from console.ppl_cfg where customer_id = cid), '{}'::jsonb),
    'last', (select jsonb_build_object('version', version, 'at', published_at, 'by', published_by, 'summary', summary) from console.ppl_plan where customer_id = cid and month = p_month order by version desc limit 1)
  ) into out;
  return out;
end $$;
revoke all on function console.ppl_data(uuid, text) from public, anon, authenticated;

create or replace function public.kmr_ppl_context(p_slug text) returns jsonb language sql stable security definer set search_path = console, public as $$
  select case when console.qp_role(c.id, 'ppl') is null then null
    else jsonb_build_object('role', console.qp_role(c.id, 'ppl'), 'company', c.name, 'logo_url', c.logo_url, 'is_staff', coalesce(console.is_staff(), false)) end
  from console.customers c where c.slug = lower(p_slug) $$;
grant execute on function public.kmr_ppl_context(text) to authenticated;

create or replace function public.kmr_ppl_data(p_slug text, p_month text) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
begin return console.ppl_data(console.qp_cid(p_slug, 'ppl'), p_month); end $$;
grant execute on function public.kmr_ppl_data(text, text) to authenticated;

-- manual entry: supermarket qty, stage stock, extra demand lines, working time
create or replace function public.kmr_ppl_save(p_slug text, p_month text, p_super jsonb, p_stock jsonb, p_demand jsonb, p_cfg jsonb) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'ppl'); r jsonb; kv record; me text := lower(coalesce(auth.jwt() ->> 'email', ''));
begin
  if p_super is not null then
    delete from console.ppl_super where customer_id = cid;
    for r in select * from jsonb_array_elements(p_super) loop
      insert into console.ppl_super (customer_id, part_code, qty, updated_by) values (cid, r ->> 'part', greatest(0, coalesce(nullif(r ->> 'qty', '')::numeric, 0)), me);
    end loop;
  end if;
  if p_stock is not null then
    delete from console.ppl_stock where customer_id = cid;
    for r in select * from jsonb_array_elements(p_stock) loop
      insert into console.ppl_stock (customer_id, part_code, seq, qty, updated_by) values (cid, r ->> 'part', (r ->> 'seq')::int, greatest(0, coalesce(nullif(r ->> 'qty', '')::numeric, 0)), me)
      on conflict (customer_id, part_code, seq) do update set qty = excluded.qty;
    end loop;
  end if;
  if p_demand is not null then
    delete from console.ppl_demand where customer_id = cid and month = p_month;
    for r in select * from jsonb_array_elements(p_demand) loop
      if coalesce(trim(r ->> 'part'), '') <> '' then
        insert into console.ppl_demand (customer_id, month, part_code, part_name, qty, due, note, updated_by)
        values (cid, p_month, trim(r ->> 'part'), nullif(r ->> 'name', ''), greatest(0, coalesce(nullif(r ->> 'qty', '')::numeric, 0)), nullif(r ->> 'due', '')::date, nullif(r ->> 'note', ''), me);
      end if;
    end loop;
  end if;
  if p_cfg is not null then
    for kv in select key k, value v from jsonb_each_text(p_cfg) where value ~ '^-?[0-9.]+$' loop
      insert into console.ppl_cfg (customer_id, k, v) values (cid, kv.k, kv.v::numeric) on conflict (customer_id, k) do update set v = excluded.v;
    end loop;
  end if;
  return console.ppl_data(cid, p_month);
end $$;
grant execute on function public.kmr_ppl_save(text, text, jsonb, jsonb, jsonb, jsonb) to authenticated;

-- publish: freezes the netted plan as a new version. Machine loading, RMP, Capacity and the budget apps read the latest one.
create or replace function public.kmr_ppl_publish(p_slug text, p_month text, p_rows jsonb, p_summary jsonb) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'ppl'); v int;
begin
  select coalesce(max(version), 0) + 1 into v from console.ppl_plan where customer_id = cid and month = p_month;
  insert into console.ppl_plan (customer_id, month, version, rows, summary, published_by) values (cid, p_month, v, coalesce(p_rows, '[]'), coalesce(p_summary, '{}'), lower(coalesce(auth.jwt() ->> 'email', '')));
  return jsonb_build_object('version', v);
end $$;
grant execute on function public.kmr_ppl_publish(text, text, jsonb, jsonb) to authenticated;

create or replace function console.ppl_latest(cid uuid, p_month text) returns jsonb language sql stable security definer set search_path = console, public as $$
  select coalesce((select jsonb_build_object('version', version, 'at', published_at, 'rows', rows, 'summary', summary) from console.ppl_plan where customer_id = cid and month = p_month order by version desc limit 1), 'null'::jsonb) $$;
revoke all on function console.ppl_latest(uuid, text) from public, anon, authenticated;
create or replace function public.kmr_ppl_latest(p_slug text, p_month text) returns jsonb language sql stable security definer set search_path = console, public as $$
  select console.ppl_latest(console.qp_cid(p_slug, 'ppl'), p_month) $$;
grant execute on function public.kmr_ppl_latest(text, text) to authenticated;

do $patch$
declare rec record; def text; nw text; n int := 0;
begin
  for rec in select p.oid from pg_proc p join pg_namespace s on s.oid = p.pronamespace where s.nspname = 'public' and p.proname in ('kmr_portal', 'kmr_portal_join') loop
    def := pg_get_functiondef(rec.oid); nw := def;
    if position('''ppl''' in def) = 0 then
      nw := regexp_replace(nw, $re$(\n\s*)(when 'bud'\s+then console\.qp_member\(([a-z_.]+), em, 'bud'\))$re$, E'\\1when ''ppl'' then console.qp_member(\\3, em, ''ppl'')\\1\\2');
    end if;
    if nw <> def then execute nw; n := n + 1; end if;
  end loop;
  raise notice 'PPL: % portal functions updated', n;
end $patch$;
do $yb$ declare def text; begin
  def := pg_get_functiondef('console.yb_apps()'::regprocedure);
  if position('''ppl''' in def) = 0 then execute replace(def, '''bud'']', '''bud'',''ppl'']'); end if;
end $yb$;
