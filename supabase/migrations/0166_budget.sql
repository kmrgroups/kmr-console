-- KMR 0166 — Budget (bud): monthly budget vs actual for raw material, tooling, consumables, manpower, electricity, outside processing, maintenance.
-- Actuals are pulled from the other apps: RMP (raw material bought), DC & GRN (tooling / consumables / job work bought), MMD (material issued, tool fits, consumables issued, machine run hours),
-- HRM payroll (manpower), Maintenance (repairs). Rates for tools, consumables, electricity are kept in bud_rate. Safe to re-run.
insert into console.products (code, name, description, app_path, seat_label, current_version, sort_order) values
  ('bud', 'Budget', 'Monthly budget vs actual for raw material, tooling, consumables, manpower, electricity and more, linked to the other KMR apps for intake and outward', '/it/bud.html', 'users', '1.0.0', 175)
on conflict (code) do update set name = excluded.name, description = excluded.description, app_path = excluded.app_path;
insert into console.releases (product_code, version, notes) values ('bud', '1.0.0', 'Budget: monthly budget vs actual, intake and outward, rates, auto-pull from RMP / GRN / MMD / HRM / Maintenance')
on conflict do nothing;
insert into console.prices (product_code, period, currency, unit_amount, min_seats, active, note)
select v.code, v.period, 'INR', v.amt, 1, true, 'Starting price list (0166) — change in Console • Billing' from (values ('bud', 'month', 1500), ('bud', 'year', 15000)) v(code, period, amt)
on conflict (product_code, period, currency) do nothing;
insert into public.app_listings (code, name, tagline, features, sort_order, is_active) values
  ('bud', 'Budget', 'Plan every month''s spend on raw material, tooling, consumables, manpower and power, and see actual against budget as the work happens.',
   E'Monthly budget by head with actual, variance and % used\nIntake (bought) and outward (issued / used) from RMP, GRN and MMD\nElectricity from machine run hours, manpower from payroll\nRates for tools, consumables and power kept on one screen', 175, true)
on conflict (code) do update set name = excluded.name, tagline = coalesce(public.app_listings.tagline, excluded.tagline), features = coalesce(public.app_listings.features, excluded.features);
insert into console.app_features (product_code, name, detail, is_core, price_month, price_year, setup_fee, sort_order) values
  ('bud', 'Budget vs actual', 'Monthly budget by head, actual, variance, intake and outward', true, 1500, 0, 3000, 10)
on conflict (product_code, name) do nothing;

create table if not exists console.bud_plan (
  customer_id uuid not null references console.customers(id) on delete cascade,
  month text not null check (month ~ '^\d{4}-(0[1-9]|1[0-2])$'), head text not null check (head in ('rm','tool','cons','man','pwr','out','mnt')),
  amount numeric not null default 0, note text, updated_by text, updated_at timestamptz not null default now(),
  primary key (customer_id, month, head));
create table if not exists console.bud_rate (
  customer_id uuid not null references console.customers(id) on delete cascade,
  kind text not null check (kind in ('tool','cons','power')), code text not null, rate numeric not null check (rate >= 0), updated_at timestamptz not null default now(),
  primary key (customer_id, kind, code));
do $$ declare t text; begin
  foreach t in array array['bud_plan','bud_rate'] loop
    execute format('alter table console.%I enable row level security', t);
    execute format('drop policy if exists %I on console.%I', t || '_staff', t);
    execute format('create policy %I on console.%I for all to authenticated using (console.is_staff()) with check (console.is_staff())', t || '_staff', t);
  end loop;
end $$;

-- one month: for every head the intake (bought), outward (used / issued) and the actual spend
create or replace function console.bud_month(p_cid uuid, p_m text) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare f date := (p_m || '-01')::date; t date := (date_trunc('month', (p_m || '-01')::date) + interval '1 month - 1 day')::date;
  avgr numeric; rm_in numeric := 0; rm_out numeric := 0; rm_kg numeric := 0; tl_in numeric := 0; tl_out numeric := 0; tl_n int := 0; cs_in numeric := 0; cs_out numeric := 0;
  man numeric := 0; hrs numeric := 0; kw numeric; tar numeric; oj numeric := 0; mn numeric := 0; assumed text[] := '{}'; res jsonb := '[]'::jsonb;
  tl_miss int := 0; cs_miss int := 0;
begin
  select avg(rate) into avgr from console.rmp_stock where customer_id = p_cid and rate > 0;
  select coalesce(sum(coalesce(pw.cost_amt, pw.received_qty * coalesce(st.rate, 0))), 0) into rm_in
    from console.rmp_plan_week pw left join console.rmp_stock st on st.customer_id = pw.customer_id and st.material_code = pw.material_code where pw.customer_id = p_cid and pw.month = p_m;
  select coalesce(sum(rs.rm_kg * coalesce(st.rate, avgr, 0)), 0), coalesce(sum(rs.rm_kg), 0) into rm_out, rm_kg
    from console.mmd_route_sheets rs left join console.rmp_stock st on st.customer_id = rs.customer_id and lower(st.material_code) = lower(rs.rm_material)
   where rs.customer_id = p_cid and not rs.sample and rs.created_at::date between f and t;
  select coalesce(sum(amt), 0) into tl_in from console.pnl_purchases(p_cid, f, t) where head = 'Tooling';
  select coalesce(sum(amt), 0) into cs_in from console.pnl_purchases(p_cid, f, t) where head = 'Consumables';
  select coalesce(sum(amt), 0) into oj from console.pnl_purchases(p_cid, f, t) where head = 'Job work / outside processing';
  select count(*), coalesce(sum(coalesce(r.rate, d.rate, 0)), 0), count(*) filter (where r.rate is null and d.rate is null) into tl_n, tl_out, tl_miss
    from console.mmd_tool_fit tf left join console.bud_rate r on r.customer_id = tf.customer_id and r.kind = 'tool' and r.code = tf.tool_code
    left join console.bud_rate d on d.customer_id = tf.customer_id and d.kind = 'tool' and d.code = '*'
   where tf.customer_id = p_cid and tf.removed_at is not null and tf.removed_at::date between f and t;
  select coalesce(sum(ci.qty * coalesce(r.rate, d.rate, 0)), 0), count(*) filter (where r.rate is null and d.rate is null) into cs_out, cs_miss
    from console.mmd_cons_issue ci left join console.bud_rate r on r.customer_id = ci.customer_id and r.kind = 'cons' and r.code = ci.code
    left join console.bud_rate d on d.customer_id = ci.customer_id and d.kind = 'cons' and d.code = '*'
   where ci.customer_id = p_cid and ci.issued_at::date between f and t;
  select coalesce(sum(ps.gross), 0) into man from console.hrms_payslips ps join console.hrms_payroll_runs r on r.id = ps.run_id
   where ps.customer_id = p_cid and not ps.sample and r.status = 'final' and r.period = p_m;
  select coalesce(sum(mc_hrs), 0) into hrs from console.mmd_hist where customer_id = p_cid and prod_date between f and t;
  select rate into kw from console.bud_rate where customer_id = p_cid and kind = 'power' and code = 'kw';
  select rate into tar from console.bud_rate where customer_id = p_cid and kind = 'power' and code = 'tariff';
  if kw is null then kw := 15; assumed := assumed || 'average machine load 15 kW'; end if;
  if tar is null then tar := 8; assumed := assumed || 'tariff Rs 8 per kWh'; end if;
  select coalesce(sum(cost), 0) into mn from console.mnt_events where customer_id = p_cid and not sample and status = 'ok' and event_date between f and t;
  res := jsonb_build_array(
    jsonb_build_object('head','rm','intake',round(rm_in),'outward',round(rm_out),'actual',round(case when rm_in > 0 then rm_in else rm_out end),'basis',case when rm_in > 0 then 'bought' when rm_out > 0 then 'issued' else 'none' end,'qty',round(rm_kg,1),'unit','kg issued'),
    jsonb_build_object('head','tool','intake',round(tl_in),'outward',round(tl_out),'actual',round(case when tl_in > 0 then tl_in else tl_out end),'basis',case when tl_in > 0 then 'bought' when tl_out > 0 then 'used' else 'none' end,'qty',tl_n,'unit','tool changes','missing_rate',tl_miss),
    jsonb_build_object('head','cons','intake',round(cs_in),'outward',round(cs_out),'actual',round(case when cs_in > 0 then cs_in else cs_out end),'basis',case when cs_in > 0 then 'bought' when cs_out > 0 then 'used' else 'none' end,'missing_rate',cs_miss),
    jsonb_build_object('head','man','intake',round(man),'outward',round(man),'actual',round(man),'basis',case when man > 0 then 'payroll' else 'none' end),
    jsonb_build_object('head','pwr','intake',round(hrs * kw * tar),'outward',round(hrs * kw * tar),'actual',round(hrs * kw * tar),'basis',case when hrs > 0 then 'run hours' else 'none' end,'qty',round(hrs * kw),'unit','kWh','hours',round(hrs),'assumed',to_jsonb(assumed)),
    jsonb_build_object('head','out','intake',round(oj),'outward',round(oj),'actual',round(oj),'basis',case when oj > 0 then 'bought' else 'none' end),
    jsonb_build_object('head','mnt','intake',round(mn),'outward',round(mn),'actual',round(mn),'basis',case when mn > 0 then 'recorded' else 'none' end));
  return res;
end $$;
revoke all on function console.bud_month(uuid, text) from public, anon, authenticated;

-- budget vs actual for a range of months
create or replace function public.kmr_bud_data(p_slug text, p_from text, p_to text) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'bud'); ms text[]; m text; rows jsonb := '[]'::jsonb; bp jsonb;
begin
  select array_agg(to_char(g, 'YYYY-MM') order by g) into ms from generate_series((p_from || '-01')::date, (p_to || '-01')::date, interval '1 month') g;
  if ms is null or array_length(ms, 1) > 24 then raise exception 'Choose at most 24 months.'; end if;
  foreach m in array ms loop
    select coalesce(jsonb_agg(a || jsonb_build_object('month', m, 'budget', coalesce(b.amount, 0), 'note', b.note)), '[]'::jsonb) into bp
      from jsonb_array_elements(console.bud_month(cid, m)) a left join console.bud_plan b on b.customer_id = cid and b.month = m and b.head = a ->> 'head';
    rows := rows || bp;
  end loop;
  return jsonb_build_object('months', to_jsonb(ms), 'rows', rows, 'rates', (select coalesce(jsonb_object_agg(kind || ':' || code, rate), '{}'::jsonb) from console.bud_rate where customer_id = cid));
end $$;
grant execute on function public.kmr_bud_data(text, text, text) to authenticated;

create or replace function public.kmr_bud_save(p_slug text, p_rows jsonb) returns int language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'bud'); r jsonb; n int := 0;
begin
  for r in select * from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) loop
    insert into console.bud_plan (customer_id, month, head, amount, note, updated_by) values (cid, r ->> 'month', r ->> 'head', coalesce(nullif(r ->> 'amount', '')::numeric, 0), nullif(r ->> 'note', ''), lower(coalesce(auth.jwt() ->> 'email', '')))
    on conflict (customer_id, month, head) do update set amount = excluded.amount, note = excluded.note, updated_by = excluded.updated_by, updated_at = now();
    n := n + 1;
  end loop;
  return n;
end $$;
grant execute on function public.kmr_bud_save(text, jsonb) to authenticated;

-- rates: every tool and consumable known to MMD plus the power rates
create or replace function public.kmr_bud_rates(p_slug text) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'bud');
begin
  return jsonb_build_object(
    'tools', coalesce((select jsonb_agg(jsonb_build_object('code', c.code, 'rate', r.rate) order by c.code) from (select tool_code code from console.mmd_tools where customer_id = cid union select tool_code from console.mmd_tool_plan where customer_id = cid) c left join console.bud_rate r on r.customer_id = cid and r.kind = 'tool' and r.code = c.code), '[]'::jsonb),
    'cons', coalesce((select jsonb_agg(jsonb_build_object('code', c.code, 'rate', r.rate) order by c.code) from (select code from console.mmd_cons where customer_id = cid) c left join console.bud_rate r on r.customer_id = cid and r.kind = 'cons' and r.code = c.code), '[]'::jsonb),
    'power', coalesce((select jsonb_object_agg(code, rate) from console.bud_rate where customer_id = cid and kind = 'power'), '{}'::jsonb),
    'dflt', coalesce((select jsonb_object_agg(kind, rate) from console.bud_rate where customer_id = cid and code = '*'), '{}'::jsonb));
end $$;
grant execute on function public.kmr_bud_rates(text) to authenticated;

create or replace function public.kmr_bud_rate_save(p_slug text, p_rows jsonb) returns int language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'bud'); r jsonb; n int := 0;
begin
  for r in select * from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) loop
    if nullif(r ->> 'rate', '') is null then
      delete from console.bud_rate where customer_id = cid and kind = r ->> 'kind' and code = r ->> 'code';
    else
      insert into console.bud_rate (customer_id, kind, code, rate) values (cid, r ->> 'kind', r ->> 'code', (r ->> 'rate')::numeric)
      on conflict (customer_id, kind, code) do update set rate = excluded.rate, updated_at = now();
    end if;
    n := n + 1;
  end loop;
  return n;
end $$;
grant execute on function public.kmr_bud_rate_save(text, jsonb) to authenticated;

-- platform lists (same pattern as 0131)
do $wrap$ begin
  if to_regprocedure('console.app2_tables_bud_base(text)') is null then
    alter function console.app2_tables(text) rename to app2_tables_bud_base;
    create function console.app2_tables(p_app text) returns text[] language sql immutable as $f$ select case when p_app = 'bud' then array['bud_plan','bud_rate'] else console.app2_tables_bud_base(p_app) end $f$;
    revoke all on function console.app2_tables(text) from public, anon, authenticated;
  end if;
  if to_regprocedure('console.app2_clear_bud_base(text,uuid,boolean)') is null then
    alter function console.app2_clear(text, uuid, boolean) rename to app2_clear_bud_base;
    create function console.app2_clear(p_app text, p_cid uuid, p_real_only boolean) returns bigint language plpgsql security definer set search_path = console, public as $f$
    declare n bigint := 0; m bigint;
    begin
      if p_app = 'bud' then
        if p_real_only then return 0; end if;
        delete from console.bud_plan where customer_id = p_cid; get diagnostics m = row_count; n := n + m;
        delete from console.bud_rate where customer_id = p_cid; get diagnostics m = row_count; n := n + m;
        return n;
      end if;
      return console.app2_clear_bud_base(p_app, p_cid, p_real_only);
    end $f$;
    revoke all on function console.app2_clear(text, uuid, boolean) from public, anon, authenticated;
    revoke all on function console.app2_clear_bud_base(text, uuid, boolean) from public, anon, authenticated;
  end if;
end $wrap$;
do $patch$
declare rec record; def text; nw text; n int := 0;
begin
  for rec in select p.oid from pg_proc p join pg_namespace s on s.oid = p.pronamespace where s.nspname = 'public' and p.proname in ('kmr_portal', 'kmr_portal_join') loop
    def := pg_get_functiondef(rec.oid); nw := def;
    if position('''bud''' in def) = 0 then
      nw := regexp_replace(nw, $re$(\n\s*)(when 'pnl'\s+then console\.qp_member\(([a-z_.]+), em, 'pnl'\))$re$, E'\\1when ''bud'' then console.qp_member(\\3, em, ''bud'')\\1\\2');
    end if;
    if nw <> def then execute nw; n := n + 1; end if;
  end loop;
  raise notice 'BUD: % portal functions updated', n;
end $patch$;
do $yb$ declare def text; begin
  def := pg_get_functiondef('console.yb_apps()'::regprocedure);
  if position('''bud''' in def) = 0 then execute replace(def, '''pnl'']', '''pnl'',''bud'']'); end if;
end $yb$;
