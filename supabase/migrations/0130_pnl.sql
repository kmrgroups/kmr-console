-- =====================================================================
-- 0130 — Profit & Loss (PNL) — a new KMR app, company / plant level
--  • The profit and loss account the way Tally shows it: sales, direct expenses (raw material, tooling, consumables, packing, job work, power, wages, calibration …),
--    gross profit, indirect expenses (maintenance, rent, admin, selling, finance, depreciation …), net profit; each line as % of sales and against budget.
--  • It PULLS the figures from the apps that already hold them: sales from Sales Invoicing, raw material from Raw Material Planning, wages from HRM payroll (final runs),
--    repairs from Maintenance, calibration cost from Calibration Hub, and every other purchase from DC & GRN, sorted into heads by keyword rules.
--    What no app holds (power, rent, tooling bought without a GRN ...) comes from Tally / ERP (ERP Bridge) or is typed / pasted; an entered head replaces the pulled one.
--  • Opening and closing stock can be entered per month so the material cost is the cost of material CONSUMED, as in Tally.
-- Needs 0129 (finance mail tables), 0118 (invoicing), 0113 (DC & GRN), 0107 (RMP), 0072 (HRM payroll), 0059 (maintenance), 0037 (calibration). Safe to re-run.
-- =====================================================================
insert into console.products (code, name, description, app_path, seat_label, current_version, sort_order) values
  ('pnl', 'Profit & Loss', 'Tally-style profit and loss with the cost split (raw material, tooling, consumables, wages ...), pulled from the other KMR apps', '/it/pnl.html', 'users', '1.0.0', 170)
on conflict (code) do update set name = excluded.name, description = excluded.description, app_path = excluded.app_path;
insert into console.releases (product_code, version, notes) values ('pnl', '1.0.0', 'Profit & Loss: Tally-style account, cost split, auto-pull from Invoicing / RMP / HRM / Maintenance / Calibration / DC & GRN, budgets, standards alignment, presentation') on conflict do nothing;
insert into console.prices (product_code, period, currency, unit_amount, min_seats, active, note)
select v.code, v.period, 'INR', v.amt, 1, true, 'Starting price list (0130) — change in Console • Billing' from (values ('pnl', 'month', 2000), ('pnl', 'year', 20000)) v(code, period, amt)
on conflict (product_code, period, currency) do nothing;
insert into public.app_listings (code, name, tagline, features, sort_order, is_active) values
  ('pnl', 'Profit & Loss', 'See profit every day: sales less raw material, tooling, consumables, wages and every other cost, pulled from your KMR apps and Tally.',
   E'Tally-style profit and loss with gross and net profit\nCost split: raw material, tooling, consumables, packing, job work, power, wages\nPulled from Sales Invoicing, Raw Material Planning, HRM, Maintenance, Calibration, DC & GRN\nBudget against actual and every cost as % of sales', 170, true)
on conflict (code) do update set name = excluded.name, tagline = coalesce(public.app_listings.tagline, excluded.tagline), features = coalesce(public.app_listings.features, excluded.features);
insert into console.app_features (product_code, name, detail, is_core, price_month, price_year, setup_fee, sort_order) values
  ('pnl', 'Profit and loss account', 'Tally-style account, cost split, percentage of sales, budget, trend', true, 2000, 0, 5000, 10),
  ('pnl', 'Tally / ERP loading', 'Expenses and income loaded from Tally or the ERP by the ERP Bridge', false, 500, 0, 3000, 20)
on conflict (product_code, name) do nothing;

-- ---------- tables ----------
create table if not exists console.pnl_heads (            -- the account heads shown in the profit and loss
  customer_id uuid not null references console.customers(id) on delete cascade,
  head text not null, grp text not null check (grp in ('income', 'direct', 'indirect')), sort int not null default 100,
  auto text check (auto in ('sales', 'rmp', 'payroll', 'maintenance', 'calibration')),   -- which app fills it automatically
  primary key (customer_id, head));
create table if not exists console.pnl_alias (            -- ledger names of Tally / the ERP -> head
  customer_id uuid not null references console.customers(id) on delete cascade,
  alias text not null, head text not null, primary key (customer_id, alias));
create table if not exists console.pnl_rules (            -- purchases received on a GRN: if the item text contains the keyword, the value goes to the head
  id uuid primary key default gen_random_uuid(), customer_id uuid not null references console.customers(id) on delete cascade,
  keyword text not null, head text not null, sort int not null default 100);
create table if not exists console.pnl_stock (
  customer_id uuid not null references console.customers(id) on delete cascade,
  month text not null check (month ~ '^\d{4}-(0[1-9]|1[0-2])$'), opening numeric, closing numeric, note text, updated_at timestamptz not null default now(),
  primary key (customer_id, month));
create table if not exists console.pnl_settings (
  customer_id uuid primary key references console.customers(id) on delete cascade,
  rm_source text not null default 'rmp' check (rm_source in ('rmp', 'purchases', 'entries')),   -- where "Raw material" comes from
  updated_at timestamptz not null default now());
do $$ declare t text; begin
  foreach t in array array['pnl_heads', 'pnl_alias', 'pnl_rules', 'pnl_stock', 'pnl_settings'] loop
    execute format('alter table console.%I enable row level security', t);
    execute format('drop policy if exists %I on console.%I', t || '_staff', t);
    execute format('create policy %I on console.%I for all to authenticated using (console.is_staff()) with check (console.is_staff())', t || '_staff', t);
  end loop;
end $$;

create or replace function console.pnl_default_heads() returns table (head text, grp text, sort int, auto text) language sql immutable as $$
  select * from (values
    ('Sales', 'income', 10, 'sales'), ('Other income', 'income', 20, null),
    ('Raw material', 'direct', 10, 'rmp'), ('Tooling', 'direct', 20, null), ('Consumables', 'direct', 30, null), ('Packing material', 'direct', 40, null),
    ('Job work / outside processing', 'direct', 50, null), ('Power & fuel', 'direct', 60, null), ('Wages & salaries', 'direct', 70, 'payroll'),
    ('Calibration', 'direct', 80, 'calibration'), ('Freight inward', 'direct', 90, null), ('Cost of poor quality (scrap, rework)', 'direct', 100, null),
    ('Repairs & maintenance', 'indirect', 10, 'maintenance'), ('Rent', 'indirect', 20, null), ('Admin & office', 'indirect', 30, null),
    ('Selling & freight outward', 'indirect', 40, null), ('Finance cost (interest, bank)', 'indirect', 50, null), ('Depreciation', 'indirect', 60, null), ('Other expenses', 'indirect', 90, null)
  ) v(head, grp, sort, auto) $$;

-- purchases received on a GRN in the period, sorted into heads by the keyword rules (head null = no rule matched)
create or replace function console.pnl_purchases(p_cid uuid, f date, t date) returns table (head text, amt numeric) language sql stable security definer set search_path = console, public as $$
  select r.head, sum(gl.accepted_qty * coalesce(pl.rate, 0))
    from console.dcg_grn_lines gl join console.dcg_grn g on g.id = gl.grn_id and g.status = 'posted' and g.gtype = 'po_receipt' and g.grn_date between f and t
    left join console.dcg_po_lines pl on pl.id = gl.po_line_id
    left join lateral (select x.head from console.pnl_rules x where x.customer_id = p_cid and position(lower(x.keyword) in lower(coalesce(gl.description, '') || ' ' || coalesce(gl.item_code, ''))) > 0 order by x.sort, x.id limit 1) r on true
   where gl.customer_id = p_cid group by r.head $$;
revoke all on function console.pnl_purchases(uuid, date, date) from public, anon, authenticated;

-- ---------- the profit and loss for a range of whole months ----------
create or replace function console.pnl_calc(p_cid uuid, p_from date, p_to date) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare
  f date := date_trunc('month', p_from)::date; t date := (date_trunc('month', p_to) + interval '1 month - 1 day')::date;
  mf text := to_char(f, 'YYYY-MM'); mt text := to_char(t, 'YYYY-MM');
  nm int := ((extract(year from t) - extract(year from f)) * 12 + extract(month from t) - extract(month from f))::int + 1;
  v_src text := coalesce((select source from console.fin_settings where customer_id = p_cid), 'app');
  v_rm text := coalesce((select rm_source from console.pnl_settings where customer_id = p_cid), 'rmp');
  ok_inv boolean := coalesce((select a.ok from console.access_state('inv', p_cid) a), false);
  ok_rmp boolean := coalesce((select a.ok from console.access_state('rmp', p_cid) a), false);
  ok_hr boolean := coalesce((select a.ok from console.access_state('hrms', p_cid) a), false);
  ok_mnt boolean := coalesce((select a.ok from console.access_state('mnt', p_cid) a), false);
  ok_cal boolean := coalesce((select a.ok from console.access_state('calib', p_cid) a), false);
  ok_dcg boolean := coalesce((select a.ok from console.access_state('dcg', p_cid) a), false);
  v_sales numeric := 0; v_rmp numeric := 0; v_pay numeric := 0; v_mnt numeric := 0; v_cal numeric := 0; v_unclass numeric := 0;
  ls jsonb; so numeric; sc numeric; has_stock boolean := false; tot jsonb; sales numeric; oth numeric; dir numeric; ind numeric; gp numeric; np numeric;
begin
  if ok_inv then
    select coalesce(sum(case doc_type when 'CRN' then -taxable else taxable end), 0) into v_sales from console.inv_invoice where customer_id = p_cid and status = 'issued' and inv_date between f and t;
  end if;
  if ok_rmp then
    select coalesce(sum(coalesce(pw.cost_amt, pw.received_qty * coalesce(st.rate, 0))), 0) into v_rmp
      from console.rmp_plan_week pw left join console.rmp_stock st on st.customer_id = pw.customer_id and st.material_code = pw.material_code where pw.customer_id = p_cid and pw.month between mf and mt;
  end if;
  if ok_hr then
    select coalesce(sum(ps.gross), 0) into v_pay from console.hrms_payslips ps join console.hrms_payroll_runs r on r.id = ps.run_id
     where ps.customer_id = p_cid and not ps.sample and r.status = 'final' and r.period between mf and mt;
  end if;
  if ok_mnt then select coalesce(sum(cost), 0) into v_mnt from console.mnt_events where customer_id = p_cid and not sample and status = 'ok' and event_date between f and t; end if;
  if ok_cal then select coalesce(sum(cost), 0) into v_cal from console.cal_records where customer_id = p_cid and cal_date between f and t; end if;

  if ok_dcg then select coalesce(sum(amt), 0) into v_unclass from console.pnl_purchases(p_cid, f, t) where head is null; end if;

  with h as (
    select x.head, x.grp, x.sort, x.auto from console.pnl_heads x where x.customer_id = p_cid
    union all select d.head, d.grp, d.sort, d.auto from console.pnl_default_heads() d where not exists (select 1 from console.pnl_heads where customer_id = p_cid)),
  e0 as (select coalesce(nullif(trim(head), ''), 'Other') as hr, kind, amount from console.fin_entries where customer_id = p_cid and source = v_src and kind in ('expense', 'income') and entry_date between f and t),
  e1 as (select coalesce(h1.head, h2.head, e0.hr) as head, e0.kind, sum(e0.amount) as amt, (h1.head is null and h2.head is null) as unmapped
           from e0 left join h h1 on lower(h1.head) = lower(e0.hr) left join console.pnl_alias a on a.customer_id = p_cid and a.alias = lower(e0.hr) left join h h2 on h2.head = a.head
          group by 1, 2, 4),
  bud as (select lower(b.head) as k, sum(coalesce(sp.amount, st.amount)) as amt
            from (select distinct lower(head) as lh, head from console.fin_budget where customer_id = p_cid) b
            cross join generate_series(f, t, interval '1 month') g(m)
            left join console.fin_budget sp on sp.customer_id = p_cid and lower(sp.head) = b.lh and sp.month = to_char(g.m, 'YYYY-MM')
            left join console.fin_budget st on st.customer_id = p_cid and lower(st.head) = b.lh and st.month = '*'
           group by 1),
  m as (
    select h.head, h.grp, h.sort, h.auto, coalesce((select sum(e1.amt) from e1 where e1.head = h.head and not e1.unmapped), 0) as ent,
           case h.auto when 'sales' then v_sales when 'rmp' then (case when v_rm = 'rmp' then v_rmp else 0 end) when 'payroll' then v_pay when 'maintenance' then v_mnt when 'calibration' then v_cal else 0 end as au,
           case when h.auto = 'rmp' and v_rm <> 'purchases' then 0 else coalesce((select sum(p.amt) from console.pnl_purchases(p_cid, f, t) p where p.head = h.head and ok_dcg), 0) end as pu
      from h
    union all
    select e1.head, case e1.kind when 'income' then 'income' else 'indirect' end, 900, null, e1.amt, 0, 0 from e1 where e1.unmapped),
  l as (select m.head, m.grp, m.sort,
               case when m.ent > 0 then m.ent else m.au + m.pu end as amt,
               case when m.ent > 0 then 'entered' when m.au > 0 and m.auto = 'sales' then 'invoicing' when m.au > 0 and m.auto = 'rmp' then 'rmp' when m.au > 0 and m.auto = 'payroll' then 'payroll'
                    when m.au > 0 and m.auto = 'maintenance' then 'maintenance' when m.au > 0 and m.auto = 'calibration' then 'calibration' when m.pu > 0 then 'purchases' else null end as src,
               (m.sort = 900 and m.auto is null) as unmapped, b.amt as budget, m.auto
          from m left join bud b on b.k = lower(m.head))
  select coalesce(jsonb_agg(jsonb_build_object('head', head, 'grp', grp, 'amt', round(amt), 'src', src, 'budget', round(budget), 'unmapped', unmapped, 'auto', auto)
                  order by (case grp when 'income' then 1 when 'direct' then 2 else 3 end), sort, head), '[]') into ls from l;

  select (select opening from console.pnl_stock where customer_id = p_cid and month = mf), (select closing from console.pnl_stock where customer_id = p_cid and month = mt) into so, sc;
  has_stock := so is not null or sc is not null;
  select coalesce(sum((x ->> 'amt')::numeric) filter (where coalesce(x ->> 'auto', '') = 'sales' or (x ->> 'grp' = 'income' and x ->> 'head' = 'Sales')), 0),
         coalesce(sum((x ->> 'amt')::numeric) filter (where x ->> 'grp' = 'income' and not (coalesce(x ->> 'auto', '') = 'sales' or x ->> 'head' = 'Sales')), 0),
         coalesce(sum((x ->> 'amt')::numeric) filter (where x ->> 'grp' = 'direct'), 0),
         coalesce(sum((x ->> 'amt')::numeric) filter (where x ->> 'grp' = 'indirect'), 0)
    into sales, oth, dir, ind from jsonb_array_elements(ls) x;
  dir := dir + coalesce(so, 0) - coalesce(sc, 0);
  gp := sales - dir; np := gp + oth - ind;
  return jsonb_build_object('from', mf, 'to', mt, 'months', nm, 'source', v_src, 'rm_source', v_rm, 'lines', ls,
    'stock', jsonb_build_object('opening', so, 'closing', sc, 'entered', has_stock),
    'totals', jsonb_build_object('sales', round(sales), 'other_income', round(oth), 'direct', round(dir), 'gross_profit', round(gp), 'indirect', round(ind), 'net_profit', round(np),
      'gp_pct', case when sales > 0 then round((100 * gp / sales)::numeric, 1) end, 'np_pct', case when sales > 0 then round((100 * np / sales)::numeric, 1) end),
    'unclassified', round(v_unclass),
    'pulled', jsonb_build_object('invoicing', ok_inv, 'rmp', ok_rmp, 'payroll', ok_hr, 'maintenance', ok_mnt, 'calibration', ok_cal, 'purchases', ok_dcg));
end $$;
revoke all on function console.pnl_calc(uuid, date, date) from public, anon, authenticated;

-- ---------- app functions (access through the usual app role) ----------
create or replace function public.kmr_pnl_context(p_slug text) returns jsonb language sql stable security definer set search_path = console, public as $$
  select case when console.qp_role(c.id, 'pnl') is null then null
    else jsonb_build_object('role', console.qp_role(c.id, 'pnl'), 'company', c.name, 'logo_url', c.logo_url, 'is_staff', coalesce(console.is_staff(), false)) end
  from console.customers c where c.slug = lower(p_slug) $$;
grant execute on function public.kmr_pnl_context(text) to authenticated;

create or replace function public.kmr_pnl_report(p_slug text, p_from date, p_to date) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'pnl');
begin
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 800 then raise exception 'Choose a period of up to 24 months.'; end if;
  return console.pnl_calc(cid, p_from, p_to);
end $$;
grant execute on function public.kmr_pnl_report(text, date, date) to authenticated;

create or replace function public.kmr_pnl_trend(p_slug text, p_months int default 6) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'pnl'); n int := greatest(2, least(coalesce(p_months, 6), 24)); d date := date_trunc('month', (now() at time zone 'Asia/Kolkata'))::date; res jsonb := '[]'; i int; r jsonb;
begin
  for i in reverse n - 1 .. 0 loop
    r := console.pnl_calc(cid, (d - make_interval(months => i))::date, (d - make_interval(months => i))::date);
    res := res || jsonb_build_array(jsonb_build_object('m', to_char(d - make_interval(months => i), 'YYYY-MM'), 'sales', r #> '{totals,sales}', 'direct', r #> '{totals,direct}', 'gross_profit', r #> '{totals,gross_profit}',
      'indirect', r #> '{totals,indirect}', 'net_profit', r #> '{totals,net_profit}', 'np_pct', r #> '{totals,np_pct}'));
  end loop;
  return res;
end $$;
grant execute on function public.kmr_pnl_trend(text, int) to authenticated;

-- everything the set-up and entry screens need (heads are made on first use)
create or replace function public.kmr_pnl_load(p_slug text) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'pnl'); src text;
begin
  if coalesce(console.qp_role(cid, 'pnl'), '') in ('admin', 'editor') and not exists (select 1 from console.pnl_heads where customer_id = cid) then
    insert into console.pnl_heads (customer_id, head, grp, sort, auto) select cid, d.head, d.grp, d.sort, d.auto from console.pnl_default_heads() d on conflict do nothing;
  end if;
  src := coalesce((select source from console.fin_settings where customer_id = cid), 'app');
  return jsonb_build_object('source', src, 'rm_source', coalesce((select rm_source from console.pnl_settings where customer_id = cid), 'rmp'),
    'heads', coalesce((select jsonb_agg(jsonb_build_object('head', head, 'grp', grp, 'sort', sort, 'auto', auto) order by (case grp when 'income' then 1 when 'direct' then 2 else 3 end), sort, head) from console.pnl_heads where customer_id = cid), '[]'),
    'aliases', coalesce((select jsonb_agg(jsonb_build_object('alias', alias, 'head', head) order by alias) from console.pnl_alias where customer_id = cid), '[]'),
    'rules', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'keyword', keyword, 'head', head, 'sort', sort) order by sort, keyword) from console.pnl_rules where customer_id = cid), '[]'),
    'stock', coalesce((select jsonb_agg(jsonb_build_object('month', month, 'opening', opening, 'closing', closing, 'note', note) order by month desc) from (select * from console.pnl_stock where customer_id = cid order by month desc limit 24) s), '[]'),
    'budget', coalesce((select jsonb_agg(jsonb_build_object('month', month, 'head', head, 'amount', amount) order by month, head) from console.fin_budget where customer_id = cid), '[]'),
    'entries', coalesce((select jsonb_agg(to_jsonb(t) order by t.entry_date desc, t.created_at desc) from (select id, kind, entry_date, party, head, amount, created_at from console.fin_entries where customer_id = cid and source = 'app' and kind in ('expense', 'income') order by entry_date desc, created_at desc limit 30) t), '[]'),
    'rmp_stock_value', (select round(sum(s.on_hand_kg * coalesce(s.rate, 0))) from console.rmp_stock s where s.customer_id = cid and not s.sample and coalesce((select a.ok from console.access_state('rmp', cid) a), false)),
    'uses', jsonb_build_object('invoicing', coalesce((select a.ok from console.access_state('inv', cid) a), false), 'rmp', coalesce((select a.ok from console.access_state('rmp', cid) a), false),
       'payroll', coalesce((select a.ok from console.access_state('hrms', cid) a), false), 'maintenance', coalesce((select a.ok from console.access_state('mnt', cid) a), false),
       'calibration', coalesce((select a.ok from console.access_state('calib', cid) a), false), 'purchases', coalesce((select a.ok from console.access_state('dcg', cid) a), false)));
end $$;
grant execute on function public.kmr_pnl_load(text) to authenticated;

-- set-up changes: p = {op, ...}. op: head | head_delete | alias | alias_delete | rule | rule_delete | stock | settings
create or replace function public.kmr_pnl_save(p_slug text, p jsonb) returns text language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'pnl'); op text := coalesce(p ->> 'op', ''); hd text := trim(coalesce(p ->> 'head', '')); g text := coalesce(p ->> 'grp', ''); au text;
begin
  if op = 'head' then
    if hd = '' then raise exception 'Type the head name.'; end if;
    if g not in ('income', 'direct', 'indirect') then raise exception 'Choose where it belongs: income, direct expense or indirect expense.'; end if;
    au := (select auto from console.pnl_heads where customer_id = cid and head = hd);
    insert into console.pnl_heads (customer_id, head, grp, sort, auto) values (cid, hd, g, coalesce(nullif(p ->> 'sort', '')::int, 100), au)
    on conflict (customer_id, head) do update set grp = excluded.grp, sort = excluded.sort;
  elsif op = 'head_delete' then
    if exists (select 1 from console.pnl_heads where customer_id = cid and head = hd and auto is not null) then raise exception 'This head is filled by an app and cannot be removed.'; end if;
    delete from console.pnl_heads where customer_id = cid and head = hd; delete from console.pnl_rules where customer_id = cid and head = hd; delete from console.pnl_alias where customer_id = cid and head = hd;
  elsif op = 'alias' then
    if trim(coalesce(p ->> 'alias', '')) = '' or not exists (select 1 from console.pnl_heads where customer_id = cid and head = hd) then raise exception 'Type the Tally / ERP ledger name and choose an existing head.'; end if;
    insert into console.pnl_alias (customer_id, alias, head) values (cid, lower(trim(p ->> 'alias')), hd) on conflict (customer_id, alias) do update set head = excluded.head;
  elsif op = 'alias_delete' then delete from console.pnl_alias where customer_id = cid and alias = lower(trim(coalesce(p ->> 'alias', '')));
  elsif op = 'rule' then
    if trim(coalesce(p ->> 'keyword', '')) = '' or not exists (select 1 from console.pnl_heads where customer_id = cid and head = hd) then raise exception 'Type the word to look for in the item name and choose a head.'; end if;
    insert into console.pnl_rules (customer_id, keyword, head, sort) values (cid, trim(p ->> 'keyword'), hd, coalesce(nullif(p ->> 'sort', '')::int, 100));
  elsif op = 'rule_delete' then delete from console.pnl_rules where customer_id = cid and id = (p ->> 'id')::uuid;
  elsif op = 'stock' then
    if coalesce(p ->> 'month', '') !~ '^\d{4}-(0[1-9]|1[0-2])$' then raise exception 'Choose the month.'; end if;
    insert into console.pnl_stock (customer_id, month, opening, closing, note, updated_at) values (cid, p ->> 'month', nullif(p ->> 'opening', '')::numeric, nullif(p ->> 'closing', '')::numeric, nullif(trim(coalesce(p ->> 'note', '')), ''), now())
    on conflict (customer_id, month) do update set opening = excluded.opening, closing = excluded.closing, note = excluded.note, updated_at = now();
  elsif op = 'stock_delete' then delete from console.pnl_stock where customer_id = cid and month = p ->> 'month';
  elsif op = 'settings' then
    if coalesce(p ->> 'rm_source', '') not in ('rmp', 'purchases', 'entries') then raise exception 'Choose where raw material comes from.'; end if;
    insert into console.pnl_settings (customer_id, rm_source, updated_at) values (cid, p ->> 'rm_source', now()) on conflict (customer_id) do update set rm_source = excluded.rm_source, updated_at = now();
  else raise exception 'Unknown change.'; end if;
  return 'ok';
end $$;
grant execute on function public.kmr_pnl_save(text, jsonb) to authenticated;

-- typed / pasted expenses, income and budgets (same store as the finance mail)
create or replace function public.kmr_pnl_import(p_slug text, p_kind text, p_rows jsonb) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'pnl');
begin
  if p_kind not in ('entry', 'budget') then raise exception 'Unknown data type.'; end if;
  return console.fin_import_core(cid, p_kind, p_rows);
end $$;
grant execute on function public.kmr_pnl_import(text, text, jsonb) to authenticated;
create or replace function public.kmr_pnl_delete(p_slug text, p_what text, p_id text, p_month text default null) returns text language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'pnl');
begin
  if p_what = 'entry' then delete from console.fin_entries where customer_id = cid and source = 'app' and id = p_id::uuid;
  elsif p_what = 'budget' then delete from console.fin_budget where customer_id = cid and month = coalesce(p_month, '*') and head = p_id;
  else raise exception 'Unknown data type.'; end if;
  return 'ok';
end $$;
grant execute on function public.kmr_pnl_delete(text, text, text, text) to authenticated;

-- the finance mail gets a Profit & Loss block (month to date) when the Profit & Loss app is in the plan: fin_kpis calls this
create or replace function console.fin_pnl_block(p_cid uuid) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare ms date := date_trunc('month', (now() at time zone 'Asia/Kolkata'))::date; pm date := (ms - interval '1 month')::date; r jsonb; pr jsonb;
begin
  if not coalesce((select a.ok from console.access_state('pnl', p_cid) a), false) then return null; end if;
  r := console.pnl_calc(p_cid, ms, ms); pr := console.pnl_calc(p_cid, pm, pm);
  if coalesce((r #>> '{totals,sales}')::numeric, 0) = 0 and coalesce((r #>> '{totals,direct}')::numeric, 0) = 0 then return null; end if;
  return jsonb_build_object('totals', r -> 'totals', 'prev', pr -> 'totals', 'stock', r -> 'stock', 'unclassified', r -> 'unclassified',
    'lines', (select coalesce(jsonb_agg(x), '[]') from jsonb_array_elements(r -> 'lines') x where (x ->> 'amt')::numeric > 0 and x ->> 'grp' <> 'income'));
end $$;
revoke all on function console.fin_pnl_block(uuid) from public, anon, authenticated;

create or replace function console.fin_kpis(p_cid uuid, p jsonb default '{}', p_source text default 'app') returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare r jsonb; b jsonb;
begin
  r := console.fin_kpis_base(p_cid, p, p_source); b := console.fin_pnl_block(p_cid);
  if b is not null then r := r || jsonb_build_object('pnl', b); end if;
  return r;
end $$;
revoke all on function console.fin_kpis(uuid, jsonb, text) from public, anon, authenticated;
