-- KMR 0140 — Raw Material Planning: "Actual inward" is filled automatically from the GRN (goods receipt note) data of the DC & GRN app.
--   * every posted purchase GRN line of the plant is matched to a raw material (exact name match, or a link the user made once) and added to the week it was received
--   * what is typed by hand on the screen always wins; a "Use GRN" reset hands the week back to the GRN figure
--   * GRN lines that match no material are listed on the screen so they can be linked once (or ignored), and are remembered for the next GRNs
alter table console.rmp_plan_week add column if not exists grn_qty numeric, add column if not exists received_src text;

create table if not exists console.rmp_grn_alias (
  customer_id uuid not null, grn_key text not null, material_code text not null default '', grn_text text,
  updated_by text, updated_at timestamptz not null default now(), primary key (customer_id, grn_key));
alter table console.rmp_grn_alias enable row level security;
revoke all on console.rmp_grn_alias from public, anon, authenticated;

-- 1. the plant's GRN lines of a month, each with the material it belongs to (null = not matched) and the week (1–5)
create or replace function console.rmp_grn_lines(p_plant uuid, p_month text)
returns table (grn_no text, grn_date date, party text, txt text, qty numeric, wk smallint, material_code text, ignored boolean, gkey text)
language sql stable security definer set search_path = console, public as $$
  with m0 as (select (p_month || '-01')::date d),
  mats as (
    select upper(regexp_replace(material_code, '[^A-Za-z0-9]', '', 'g')) k, material_code from console.rmp_stock where customer_id = p_plant
    union all select upper(regexp_replace(material_code, '[^A-Za-z0-9]', '', 'g')), material_code from console.rmp_bom where customer_id = p_plant
    union all select upper(regexp_replace(spec_text, '[^A-Za-z0-9]', '', 'g')), material_code from console.rmp_stock where customer_id = p_plant and coalesce(spec_text, '') <> ''),
  mk as (select k, min(material_code) material_code from mats where k <> '' group by k),
  l as (
    select g.grn_no, g.grn_date, g.party_name party, nullif(trim(x.item_code), '') ic, nullif(trim(x.description), '') ds, coalesce(x.accepted_qty, x.received_qty, 0) qty
      from console.dcg_grn g join console.dcg_grn_lines x on x.grn_id = g.id, m0
     where g.customer_id = p_plant and g.gtype = 'po_receipt' and g.status = 'posted' and g.grn_date >= m0.d and g.grn_date < (m0.d + interval '1 month')::date),
  k as (select l.*, upper(regexp_replace(coalesce(ic, ''), '[^A-Za-z0-9]', '', 'g')) k1, upper(regexp_replace(coalesce(ds, ''), '[^A-Za-z0-9]', '', 'g')) k2 from l)
  select k.grn_no, k.grn_date, k.party, coalesce(k.ic, k.ds), k.qty, least(5, ((extract(day from k.grn_date)::int - 1) / 7) + 1)::smallint,
         nullif(coalesce(al.material_code, m1.material_code, m2.material_code), ''), coalesce(al.material_code = '', false), coalesce(nullif(k.k1, ''), k.k2)
    from k
    left join console.rmp_grn_alias al on al.customer_id = p_plant and al.grn_key = coalesce(nullif(k.k1, ''), k.k2)
    left join mk m1 on m1.k = k.k1 and k.k1 <> ''
    left join mk m2 on m2.k = k.k2 and k.k2 <> ''
   where coalesce(nullif(k.k1, ''), k.k2) <> ''
$$;
revoke all on function console.rmp_grn_lines(uuid, text) from public, anon, authenticated;

-- 2. write the GRN quantities into the weekly rows (typed-by-hand weeks are not touched)
create or replace function console.rmp_grn_sync(p_plant uuid, p_month text) returns int
language plpgsql security definer set search_path = console, public as $$
declare n int := 0; n2 int := 0;
begin
  if p_month !~ '^\d{4}-(0[1-9]|1[0-2])$' then return 0; end if;
  with a as materialized (select material_code mc, wk, sum(qty) q from console.rmp_grn_lines(p_plant, p_month) where material_code is not null group by 1, 2)
  insert into console.rmp_plan_week (customer_id, month, material_code, week, planned_qty, received_qty, grn_qty, received_src, updated_by)
  select p_plant, p_month, a.mc, a.wk, 0, a.q, a.q, 'grn', 'GRN' from a
  on conflict (customer_id, month, material_code, week) do update
     set grn_qty = excluded.grn_qty,
         received_qty = case when console.rmp_plan_week.received_src = 'manual' then console.rmp_plan_week.received_qty else excluded.grn_qty end,
         received_src = case when console.rmp_plan_week.received_src = 'manual' then 'manual' else 'grn' end,
         updated_by = 'GRN', updated_at = now()
   where console.rmp_plan_week.grn_qty is distinct from excluded.grn_qty
      or (console.rmp_plan_week.received_src is distinct from 'manual' and (console.rmp_plan_week.received_qty is distinct from excluded.grn_qty or console.rmp_plan_week.received_src is null));
  get diagnostics n = row_count;
  -- weeks whose GRN lines are gone (cancelled or linked elsewhere)
  with a as materialized (select material_code mc, wk from console.rmp_grn_lines(p_plant, p_month) where material_code is not null group by 1, 2)
  update console.rmp_plan_week w set grn_qty = 0, received_qty = case when w.received_src = 'manual' then w.received_qty else 0 end, updated_at = now()
   where w.customer_id = p_plant and w.month = p_month and coalesce(w.grn_qty, 0) <> 0 and not exists (select 1 from a where a.mc = w.material_code and a.wk = w.week);
  get diagnostics n2 = row_count;
  return n + n2;
end $$;
revoke all on function console.rmp_grn_sync(uuid, text) from public, anon, authenticated;

-- 3. saving a week: a typed received quantity becomes "manual"; an empty one hands the week back to the GRN figure
create or replace function public.kmr_rmp_week_save(p_slug text, p_month text, p_rows jsonb) returns integer language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'rmp'); r jsonb; n int := 0; ex record; me text := lower(coalesce(auth.jwt() ->> 'email', '')); rv numeric; src text;
begin
  if p_month !~ '^\d{4}-(0[1-9]|1[0-2])$' then raise exception 'Month must look like 2026-11.'; end if;
  for r in select * from jsonb_array_elements(coalesce(p_rows, '[]')) loop
    if coalesce(trim(r ->> 'material_code'), '') = '' or coalesce(r ->> 'week', '') !~ '^[1-5]$' then continue; end if;
    select * into ex from console.rmp_plan_week where customer_id = cid and month = p_month and material_code = trim(r ->> 'material_code') and week = (r ->> 'week')::smallint;
    rv := coalesce(ex.received_qty, 0); src := ex.received_src;
    if r ? 'received_qty' then
      if nullif(r ->> 'received_qty', '') is null then rv := coalesce(ex.grn_qty, 0); src := 'grn';
      else rv := greatest(0, (r ->> 'received_qty')::numeric); src := 'manual'; end if;
    end if;
    insert into console.rmp_plan_week (customer_id, month, material_code, week, planned_qty, received_qty, received_src, cost_amt, updated_by)
    values (cid, p_month, trim(r ->> 'material_code'), (r ->> 'week')::smallint,
      greatest(0, coalesce(case when r ? 'planned_qty' then nullif(r ->> 'planned_qty', '')::numeric else ex.planned_qty end, 0)), rv, src,
      case when r ? 'cost_amt' then greatest(0, nullif(r ->> 'cost_amt', '')::numeric) else ex.cost_amt end, me)
    on conflict (customer_id, month, material_code, week) do update set planned_qty = excluded.planned_qty, received_qty = excluded.received_qty, received_src = excluded.received_src,
      cost_amt = excluded.cost_amt, updated_by = excluded.updated_by, updated_at = now();
    n := n + 1;
  end loop;
  return n;
end $$;

-- 4. link a GRN description to a raw material once (material '' = not a raw material, ignore; null = remove the link)
create or replace function public.kmr_rmp_grn_link(p_slug text, p_plant uuid, p_month text, p_key text, p_txt text, p_material text) returns text
language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'rmp');
begin
  if not exists (select 1 from console.customers where id = p_plant and (id = cid or parent_id = cid)) then raise exception 'This plant does not belong to your company.'; end if;
  if coalesce(trim(p_key), '') = '' then raise exception 'Nothing to link.'; end if;
  if p_material is null then delete from console.rmp_grn_alias where customer_id = p_plant and grn_key = p_key;
  else
    if trim(p_material) <> '' and not exists (select 1 from console.rmp_stock where customer_id = p_plant and material_code = trim(p_material))
       and not exists (select 1 from console.rmp_bom where customer_id = p_plant and material_code = trim(p_material)) then raise exception 'Choose a material of this plant.'; end if;
    insert into console.rmp_grn_alias (customer_id, grn_key, material_code, grn_text, updated_by) values (p_plant, p_key, trim(p_material), left(p_txt, 200), lower(coalesce(auth.jwt() ->> 'email', '')))
    on conflict (customer_id, grn_key) do update set material_code = excluded.material_code, grn_text = excluded.grn_text, updated_by = excluded.updated_by, updated_at = now();
  end if;
  perform console.rmp_grn_sync(p_plant, p_month);
  return 'ok';
end $$;
revoke all on function public.kmr_rmp_grn_link(text, uuid, text, text, text, text) from public, anon;
grant execute on function public.kmr_rmp_grn_link(text, uuid, text, text, text, text) to authenticated;

-- 5. the month screen: sync first, then send the GRN figures, the GRN lines of each material and the lines that match no material
do $do$
declare def text; n1 text := 'out := out || jsonb_build_array(jsonb_build_object(''id'', pl.id, ''name'', pl.name, ''code'', pl.code,';
begin
  def := pg_get_functiondef('public.kmr_rmp_month(text,text)'::regprocedure);
  if position(n1 in def) = 0 or position('''materials'', coalesce((select jsonb_agg(jsonb_build_object(' in def) = 0 then raise exception 'anchor not found'; end if;
  if position('grn_unmatched' in def) > 0 then return; end if;
  def := replace(def, 'STABLE SECURITY DEFINER', 'SECURITY DEFINER');
  def := replace(def, n1, 'perform console.rmp_grn_sync(pl.id, p_month);' || chr(10) || '    ' || n1);
  def := replace(def, '''materials'', coalesce((select jsonb_agg(jsonb_build_object(',
    '''grn_unmatched'', coalesce((select jsonb_agg(jsonb_build_object(''key'', u.gkey, ''txt'', u.txt, ''q'', u.q, ''n'', u.n, ''parties'', u.parties) order by u.q desc) from (select gkey, max(txt) txt, sum(qty) q, count(*) n, string_agg(distinct left(party, 22), '', '') parties from console.rmp_grn_lines(pl.id, p_month) where material_code is null and not ignored group by gkey order by sum(qty) desc limit 40) u), ''[]''),' || chr(10) || '      ''materials'', coalesce((select jsonb_agg(jsonb_build_object(');
  def := replace(def, '''spec'', coalesce(s.spec_text, ''''),',
    '''spec'', coalesce(s.spec_text, ''''), ''grn'', coalesce((select jsonb_agg(jsonb_build_object(''no'', g.grn_no, ''d'', g.grn_date, ''party'', g.party, ''txt'', g.txt, ''q'', g.qty, ''w'', g.wk) order by g.grn_date, g.grn_no) from console.rmp_grn_lines(pl.id, p_month) g where g.material_code = mc.code), ''[]''),');
  def := replace(def, 'jsonb_build_object(''w'', w.week, ''p'', w.planned_qty, ''r'', w.received_qty, ''c'', w.cost_amt)', 'jsonb_build_object(''w'', w.week, ''p'', w.planned_qty, ''r'', w.received_qty, ''c'', w.cost_amt, ''g'', w.grn_qty, ''s'', w.received_src)');
  execute def;
end $do$;

-- 6. keep the figures fresh even when nobody opens the screen: every hour for this and last month
create or replace function console.rmp_grn_sync_all() returns int language plpgsql security definer set search_path = console, public as $$
declare p record; m text; n int := 0;
begin
  for p in select distinct customer_id from (select customer_id from console.rmp_stock union select customer_id from console.rmp_bom) x loop
    foreach m in array array[to_char(now() at time zone 'Asia/Kolkata', 'YYYY-MM'), to_char((now() at time zone 'Asia/Kolkata') - interval '1 month', 'YYYY-MM')] loop
      n := n + console.rmp_grn_sync(p.customer_id, m);
    end loop;
  end loop;
  return n;
end $$;
revoke all on function console.rmp_grn_sync_all() from public, anon, authenticated;
select cron.schedule('kmr-rmp-grn-hourly', '7 * * * *', $$select console.rmp_grn_sync_all()$$);
