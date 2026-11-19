-- KMR 0170 — Budget v2: GRN lines valued through their purchase order and sorted into heads, entered actuals (electricity bill etc.), pieces for cost per piece, item drill-down.
alter table console.bud_plan drop constraint if exists bud_plan_head_check;
alter table console.bud_plan add constraint bud_plan_head_check check (head in ('rm','tool','cons','man','pwr','out','mnt','oth'));
create table if not exists console.bud_actual (            -- actuals typed in by the user (electricity bill, a head the apps do not hold)
  customer_id uuid not null references console.customers(id) on delete cascade,
  month text not null check (month ~ '^\d{4}-(0[1-9]|1[0-2])$'), head text not null check (head in ('rm','tool','cons','man','pwr','out','mnt','oth')),
  amount numeric not null default 0, units numeric, note text, updated_by text, updated_at timestamptz not null default now(),
  primary key (customer_id, month, head));
alter table console.bud_actual enable row level security;
drop policy if exists bud_actual_staff on console.bud_actual;
create policy bud_actual_staff on console.bud_actual for all to authenticated using (console.is_staff()) with check (console.is_staff());
create index if not exists dcg_po_lines_po on console.dcg_po_lines (po_id);
create index if not exists dcg_grn_cust_date on console.dcg_grn (customer_id, grn_date) where status = 'posted';
create index if not exists dcg_grn_lines_grn on console.dcg_grn_lines (grn_id);

-- every posted GRN line of the period with its rate from the PO line and the budget head it belongs to
create or replace function console.bud_grn_lines(p_cid uuid, f date, t date) returns table (grn_no text, grn_date date, supplier text, descr text, uom text, qty numeric, rate numeric, val numeric, head text)
language sql stable security definer set search_path = console, public as $$
  select x.grn_no, x.grn_date, x.party_name, x.descr, x.uom, x.q, x.r, x.q * coalesce(x.r, 0),
    case
      when x.d ~ 'heat treat|induction|harden|temper|stress reliev|plating|anodi|coating|zinc|phosphat|painting|shot blast|job work|machining|grinding|deburr|washing|vaccum|vacuum|burnish|knurl|forging charge|laser|wire cut' then 'out'
      when x.d ~ 'repair|servic|amc |visit charge|maintenance' then 'mnt'
      when x.d ~ 'gauge|gage|fixture|jig|snap|mitutoyo|calibrat|vmc|smarturn|lmw|lathe|machine|4th axis|\mdie\M|mould|mold|rotary|chiller|compressor|furnace|tool box|storage|rack|trolley' then 'oth'
      when x.d ~ '\mal ?42|adc ?12|ck ?45|en ?1a|en ?8\M|en ?9\M|en ?19|en ?24|41cr4|\mc-? ?45|bright bar|round bar|hex bar|ismb|\mrod\M|alumin|brass|copper|stainless|mild steel|billet|ingot|wire rod|cold draw|e\+c|cr ?mo|20mncr' then 'rm'
      when x.d ~ 'endmill|end mill|drill|insert|\mtap\M|reamer|cutter|holder|collet|ccmt|cnmg|dcmt|tnmg|vbmt|tungaloy|widia|sandvik|kennametal|taegutec|iscar|boring|grooving|milling|carbide|\mhss|sleeve|\mtool|bush|sc spl|tipped|parting|thread mill|jaw|stcem|kyocera|mitsubishi|korloy' then 'tool'
      when x.d ~ 'coolant|\moil\M|grease|lubric|hycharge|axxanol|velvex|cutvel|lubgraf|mysolyte|glove|waste|cotton|wd ?40|abrasive|emery|clean|brush|tape|chemical|solvent|spray|thinner|mask|apron|shoe|carton|poly|bag|label|stationer|paper|ink|cartridge|detergent|soap|rust|vci|paint|blade|wheel|sand paper|file\M' then 'cons'
      when x.d ~ 'spare|bearing|belt|seal|contactor|pcb|electrical|hose|cylinder|motor|pump|guide way|filter|hydraulic|coupling|cable|wire|socket|stabili|relay|switch|connector|screw|nut\M|washer|bolt|clamp|cell\M|fuse|mcb|sensor|valve' then 'mnt'
      else 'oth' end
  from (select g.grn_no, g.grn_date, g.party_name, coalesce(gl.description, gl.item_code) descr, gl.uom, gl.accepted_qty q,
          lower(coalesce(gl.description, '') || ' ' || coalesce(gl.item_code, '')) d,
          coalesce(pl0.rate, pl1.rate) r
        from console.dcg_grn_lines gl join console.dcg_grn g on g.id = gl.grn_id and g.status = 'posted' and g.gtype = 'po_receipt' and g.grn_date between f and t
        left join console.dcg_po_lines pl0 on pl0.id = gl.po_line_id
        left join lateral (select pl.rate from console.dcg_po_lines pl where pl.po_id = g.po_id and gl.po_line_id is null
                            and (lower(trim(pl.description)) = lower(trim(gl.description)) or (pl.item_code is not null and pl.item_code = gl.item_code)) order by pl.sl limit 1) pl1 on true
        where gl.customer_id = p_cid) x $$;
revoke all on function console.bud_grn_lines(uuid, date, date) from public, anon, authenticated;

create or replace function console.bud_month(p_cid uuid, p_m text) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare f date := (p_m || '-01')::date; t date := (date_trunc('month', (p_m || '-01')::date) + interval '1 month - 1 day')::date;
  avgr numeric; rm_rmp numeric := 0; rm_out numeric := 0; rm_kg numeric := 0; tl_out numeric := 0; tl_n int := 0; cs_out numeric := 0; man numeric := 0; hrs numeric := 0; pcs numeric := 0;
  kw numeric; tar numeric; mn numeric := 0; assumed text[] := '{}'; tl_miss int := 0; cs_miss int := 0; res jsonb := '[]'::jsonb;
  g jsonb; gh text; h text; i numeric; o numeric; a numeric; b text; ent record; est numeric; ngrn int;
begin
  select avg(rate) into avgr from console.rmp_stock where customer_id = p_cid and rate > 0;
  select coalesce(jsonb_object_agg(q.head, jsonb_build_object('v', q.v, 'n', q.n)), '{}'::jsonb) into g from (select head, round(sum(val)) v, count(*) n from console.bud_grn_lines(p_cid, f, t) group by head) q;
  select coalesce(sum(coalesce(pw.cost_amt, pw.received_qty * coalesce(st.rate, 0))), 0) into rm_rmp
    from console.rmp_plan_week pw left join console.rmp_stock st on st.customer_id = pw.customer_id and st.material_code = pw.material_code where pw.customer_id = p_cid and pw.month = p_m;
  select coalesce(sum(rs.rm_kg * coalesce(st.rate, avgr, 0)), 0), coalesce(sum(rs.rm_kg), 0) into rm_out, rm_kg
    from console.mmd_route_sheets rs left join console.rmp_stock st on st.customer_id = rs.customer_id and lower(st.material_code) = lower(rs.rm_material)
   where rs.customer_id = p_cid and not rs.sample and rs.created_at::date between f and t;
  select count(*), coalesce(sum(coalesce(r.rate, d.rate, 0)), 0), count(*) filter (where r.rate is null and d.rate is null) into tl_n, tl_out, tl_miss
    from console.mmd_tool_fit tf left join console.bud_rate r on r.customer_id = tf.customer_id and r.kind = 'tool' and r.code = tf.tool_code
    left join console.bud_rate d on d.customer_id = tf.customer_id and d.kind = 'tool' and d.code = '*'
   where tf.customer_id = p_cid and tf.removed_at is not null and tf.removed_at::date between f and t;
  select coalesce(sum(ci.qty * coalesce(r.rate, d.rate, 0)), 0), count(*) filter (where r.rate is null and d.rate is null) into cs_out, cs_miss
    from console.mmd_cons_issue ci left join console.bud_rate r on r.customer_id = ci.customer_id and r.kind = 'cons' and r.code = ci.code
    left join console.bud_rate d on d.customer_id = ci.customer_id and d.kind = 'cons' and d.code = '*'
   where ci.customer_id = p_cid and ci.issued_at::date between f and t;
  select coalesce(sum(ps.gross), 0) into man from console.hrms_payslips ps join console.hrms_payroll_runs r on r.id = ps.run_id where ps.customer_id = p_cid and not ps.sample and r.status = 'final' and r.period = p_m;
  select coalesce(sum(mc_hrs), 0), coalesce(sum(qty), 0) into hrs, pcs from console.mmd_hist where customer_id = p_cid and prod_date between f and t;
  select rate into kw from console.bud_rate where customer_id = p_cid and kind = 'power' and code = 'kw';
  select rate into tar from console.bud_rate where customer_id = p_cid and kind = 'power' and code = 'tariff';
  if kw is null then kw := 15; assumed := array_append(assumed, 'average machine load 15 kW'::text); end if;
  if tar is null then tar := 8; assumed := array_append(assumed, 'tariff Rs 8 per kWh'::text); end if;
  select coalesce(sum(cost), 0) into mn from console.mnt_events where customer_id = p_cid and not sample and status = 'ok' and event_date between f and t;
  est := hrs * kw * tar;
  foreach h in array array['rm','tool','cons','man','pwr','out','mnt','oth'] loop
    gh := coalesce(g -> h ->> 'v', '0'); ngrn := coalesce((g -> h ->> 'n')::int, 0); i := gh::numeric; o := 0; b := 'none';
    if h = 'rm' then if i = 0 and rm_rmp > 0 then i := rm_rmp; b := 'bought (RMP)'; elsif i > 0 then b := 'bought (GRN)'; end if; o := rm_out; if i = 0 and o > 0 then b := 'issued'; end if;
    elsif h = 'tool' then o := tl_out; b := case when i > 0 then 'bought (GRN)' when o > 0 then 'used' else 'none' end;
    elsif h = 'cons' then o := cs_out; b := case when i > 0 then 'bought (GRN)' when o > 0 then 'used' else 'none' end;
    elsif h = 'man' then i := man; o := man; b := case when man > 0 then 'payroll' else 'none' end;
    elsif h = 'pwr' then i := est; o := est; b := case when est > 0 then 'estimate (run hours)' else 'none' end;
    elsif h = 'mnt' then i := i + mn; o := i; b := case when i > 0 then 'GRN + maintenance log' else 'none' end;
    else o := i; b := case when i > 0 then 'bought (GRN)' else 'none' end; end if;
    a := case when i > 0 then i else o end;
    select * into ent from console.bud_actual e where e.customer_id = p_cid and e.month = p_m and e.head = h;
    if found then a := ent.amount; b := 'entered'; end if;
    res := res || jsonb_build_object('head', h, 'intake', round(i), 'outward', round(o), 'actual', round(a), 'basis', b, 'grn_lines', ngrn, 'estimate', case when h = 'pwr' then round(est) end,
      'entered', case when ent.month is not null then true else false end, 'units', ent.units, 'pieces', round(pcs), 'hours', case when h = 'pwr' then round(hrs) end,
      'qty', case when h = 'rm' then round(rm_kg, 1) when h = 'tool' then tl_n when h = 'pwr' then round(hrs * kw) end,
      'unit', case when h = 'rm' then 'kg issued' when h = 'tool' then 'tool changes' when h = 'pwr' then 'kWh (estimate)' end,
      'missing_rate', case when h = 'tool' then tl_miss when h = 'cons' then cs_miss end, 'assumed', case when h = 'pwr' and ent.month is null then to_jsonb(assumed) end);
  end loop;
  return res;
end $$;
revoke all on function console.bud_month(uuid, text) from public, anon, authenticated;

create or replace function public.kmr_bud_actual_save(p_slug text, p_rows jsonb) returns int language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'bud'); r jsonb; n int := 0;
begin
  for r in select * from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) loop
    if nullif(r ->> 'amount', '') is null then delete from console.bud_actual where customer_id = cid and month = r ->> 'month' and head = r ->> 'head';
    else insert into console.bud_actual (customer_id, month, head, amount, units, note, updated_by) values (cid, r ->> 'month', r ->> 'head', (r ->> 'amount')::numeric, nullif(r ->> 'units', '')::numeric, nullif(r ->> 'note', ''), lower(coalesce(auth.jwt() ->> 'email', '')))
      on conflict (customer_id, month, head) do update set amount = excluded.amount, units = excluded.units, note = excluded.note, updated_by = excluded.updated_by, updated_at = now(); end if;
    n := n + 1;
  end loop;
  return n;
end $$;
grant execute on function public.kmr_bud_actual_save(text, jsonb) to authenticated;

-- the GRN lines behind a head (drill-down)
create or replace function public.kmr_bud_items(p_slug text, p_from text, p_to text, p_head text) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'bud');
begin
  return coalesce((select jsonb_agg(to_jsonb(z)) from (select l.grn_no, l.grn_date, l.supplier, l.descr, l.uom, l.qty, l.rate, round(l.val) val from console.bud_grn_lines(cid, (p_from || '-01')::date, (date_trunc('month', (p_to || '-01')::date) + interval '1 month - 1 day')::date) l
      where l.head = p_head order by l.val desc nulls last limit 300) z), '[]'::jsonb);
end $$;
grant execute on function public.kmr_bud_items(text, text, text, text) to authenticated;

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
  return jsonb_build_object('months', to_jsonb(ms), 'rows', rows, 'today', to_char(now() at time zone 'Asia/Kolkata', 'YYYY-MM-DD'));
end $$;
grant execute on function public.kmr_bud_data(text, text, text) to authenticated;
