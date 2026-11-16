-- KMR 0129 — Finance mail for top management: a SEPARATE daily mail (not the plant mail) with the money dashboards:
--   sales value, receivables (outstanding, overdue, ageing, top customers, days sales outstanding), payables (same), expenses against budget and as a % of sales
--   (raw material cost comes from Raw Material Planning), receipts and payments of the month.
-- Where the figures come from (choose in Administration › Finance mail for top management):
--   app   = typed or pasted (CSV) in the Administration screen;   tally / erp = loaded by the ERP bridge (kmr_fin_bridge below).
-- Sales value always comes from Sales Invoicing (issued invoices, credit notes less, debit notes added).
-- Recipients are typed addresses only (no "all administrators" option): the mail goes to the top management you name. Safe to re-run.

create table if not exists console.fin_settings (
  customer_id uuid primary key references console.customers(id) on delete cascade,
  enabled boolean not null default false,
  recipients text not null default '',
  send_days text not null default 'daily' check (send_days in ('daily', 'mon_sat')),
  source text not null default 'app' check (source in ('app', 'tally', 'erp')),
  sections jsonb not null default '{}',                    -- {"payables": false} switches a section off; missing = on
  targets jsonb not null default '{}',                     -- dso_target, overdue_pct_target, expense_pct_target, material_pct_target
  last_sent_on date,
  updated_at timestamptz not null default now(), updated_by text);
-- outstanding bills (a snapshot: each source replaces its own rows)
create table if not exists console.fin_open_items (
  id uuid primary key default gen_random_uuid(), customer_id uuid not null references console.customers(id) on delete cascade,
  kind text not null check (kind in ('recv', 'pay')),                      -- recv = customer owes us, pay = we owe a supplier
  source text not null default 'app' check (source in ('app', 'tally', 'erp')),
  party text not null, ref_no text not null default '', doc_date date, due_date date,
  amount numeric not null check (amount > 0),                                -- balance still outstanding, in rupees
  created_at timestamptz not null default now());
create index if not exists fin_open_items_c on console.fin_open_items (customer_id, source, kind);
-- receipts from customers, payments to suppliers, expenses
create table if not exists console.fin_entries (
  id uuid primary key default gen_random_uuid(), customer_id uuid not null references console.customers(id) on delete cascade,
  kind text not null check (kind in ('receipt', 'payment', 'expense')),
  source text not null default 'app' check (source in ('app', 'tally', 'erp')),
  entry_date date not null, party text, head text not null default '', ref_no text, amount numeric not null check (amount > 0), note text,
  created_by text, created_at timestamptz not null default now());
create index if not exists fin_entries_c on console.fin_entries (customer_id, source, kind, entry_date);
-- monthly budget per expense head; month '*' = every month
create table if not exists console.fin_budget (
  customer_id uuid not null references console.customers(id) on delete cascade,
  month text not null check (month = '*' or month ~ '^\d{4}-(0[1-9]|1[0-2])$'), head text not null, amount numeric not null check (amount >= 0),
  updated_at timestamptz not null default now(), primary key (customer_id, month, head));
do $$ declare t text; begin
  foreach t in array array['fin_settings', 'fin_open_items', 'fin_entries', 'fin_budget'] loop
    execute format('alter table console.%I enable row level security', t);
    execute format('drop policy if exists %I on console.%I', t || '_staff', t);
    execute format('create policy %I on console.%I for all to authenticated using (console.is_staff()) with check (console.is_staff())', t || '_staff', t);
  end loop;
end $$;

-- ---------- the figures ----------
create or replace function console.fin_kpis(p_cid uuid, p jsonb default '{}', p_source text default 'app') returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare
  d0 date := (now() at time zone 'Asia/Kolkata')::date;
  ms date := date_trunc('month', (now() at time zone 'Asia/Kolkata'))::date;
  pms date := (date_trunc('month', (now() at time zone 'Asia/Kolkata')) - interval '1 month')::date;
  mlen int := extract(day from (date_trunc('month', ms) + interval '1 month - 1 day'))::int;
  res jsonb := '{}'; r jsonb; ok boolean; s_mtd numeric; s_prev numeric; s_90 numeric; n bigint; mat numeric;
  mk text := to_char(ms, 'YYYY-MM');
begin
  -- ---- sales value: issued invoices (taxable value, before GST), credit notes less
  ok := coalesce((select a.ok from console.access_state('inv', p_cid) a), false);
  if ok and exists (select 1 from console.inv_invoice where customer_id = p_cid and status = 'issued') then
    select coalesce(sum(case doc_type when 'CRN' then -taxable else taxable end) filter (where inv_date between ms and d0), 0),
           coalesce(sum(case doc_type when 'CRN' then -taxable else taxable end) filter (where inv_date >= pms and inv_date < ms), 0),
           coalesce(sum(case doc_type when 'CRN' then -total else total end) filter (where inv_date > d0 - 90 and inv_date <= d0), 0)
      into s_mtd, s_prev, s_90 from console.inv_invoice where customer_id = p_cid and status = 'issued';
    r := jsonb_build_object('mtd', round(s_mtd), 'prev_month', round(s_prev), 'gross_90', round(s_90), 'day', extract(day from d0)::int, 'days_in_month', mlen,
      'invoices_mtd', (select count(*) from console.inv_invoice where customer_id = p_cid and status = 'issued' and doc_type = 'INV' and inv_date between ms and d0),
      'last_date', (select max(inv_date) from console.inv_invoice where customer_id = p_cid and status = 'issued' and inv_date <= d0),
      'months', coalesce((select jsonb_agg(jsonb_build_object('m', to_char(g.m, 'YYYY-MM'), 'v', round(x.v)) order by g.m)
                  from generate_series(ms - interval '5 months', ms, interval '1 month') g(m)
                  left join lateral (select sum(case doc_type when 'CRN' then -taxable else taxable end) as v from console.inv_invoice
                                      where customer_id = p_cid and status = 'issued' and date_trunc('month', inv_date) = g.m) x on true), '[]'),
      'top', coalesce((select jsonb_agg(jsonb_build_object('party', t.buyer_name, 'v', round(t.v)) order by t.v desc)
                  from (select buyer_name, sum(case doc_type when 'CRN' then -taxable else taxable end) as v from console.inv_invoice
                         where customer_id = p_cid and status = 'issued' and inv_date between ms and d0 group by buyer_name order by 2 desc limit 5) t), '[]'));
    res := res || jsonb_build_object('sales', r);
  end if;

  -- ---- receivables and payables (outstanding bills from the chosen source)
  if exists (select 1 from console.fin_open_items where customer_id = p_cid and source = p_source and kind = 'recv') then
    select jsonb_build_object('total', round(sum(amount)), 'bills', count(*), 'overdue', round(coalesce(sum(amount) filter (where due_date < d0), 0)),
      'overdue_bills', count(*) filter (where due_date < d0), 'no_due_date', count(*) filter (where due_date is null),
      'b0', round(coalesce(sum(amount) filter (where due_date is null or due_date >= d0), 0)),
      'b30', round(coalesce(sum(amount) filter (where due_date < d0 and due_date >= d0 - 30), 0)),
      'b60', round(coalesce(sum(amount) filter (where due_date < d0 - 30 and due_date >= d0 - 60), 0)),
      'b90', round(coalesce(sum(amount) filter (where due_date < d0 - 60 and due_date >= d0 - 90), 0)),
      'b90p', round(coalesce(sum(amount) filter (where due_date < d0 - 90), 0)),
      'max_days', coalesce(max(d0 - due_date) filter (where due_date < d0), 0),
      'collected_mtd', (select round(coalesce(sum(amount), 0)) from console.fin_entries where customer_id = p_cid and source = p_source and kind = 'receipt' and entry_date between ms and d0),
      'top', coalesce((select jsonb_agg(jsonb_build_object('party', t.party, 'total', round(t.tot), 'overdue', round(t.od), 'days', t.dd) order by t.od desc, t.tot desc)
                  from (select party, sum(amount) as tot, coalesce(sum(amount) filter (where due_date < d0), 0) as od, coalesce(max(d0 - due_date) filter (where due_date < d0), 0) as dd
                          from console.fin_open_items where customer_id = p_cid and source = p_source and kind = 'recv' group by party order by 3 desc, 2 desc limit 5) t), '[]'))
      into r from console.fin_open_items where customer_id = p_cid and source = p_source and kind = 'recv';
    res := res || jsonb_build_object('receivables', r);
  end if;
  if exists (select 1 from console.fin_open_items where customer_id = p_cid and source = p_source and kind = 'pay') then
    select jsonb_build_object('total', round(sum(amount)), 'bills', count(*), 'overdue', round(coalesce(sum(amount) filter (where due_date < d0), 0)),
      'overdue_bills', count(*) filter (where due_date < d0), 'no_due_date', count(*) filter (where due_date is null),
      'b0', round(coalesce(sum(amount) filter (where due_date is null or due_date >= d0), 0)),
      'b30', round(coalesce(sum(amount) filter (where due_date < d0 and due_date >= d0 - 30), 0)),
      'b60', round(coalesce(sum(amount) filter (where due_date < d0 - 30 and due_date >= d0 - 60), 0)),
      'b90', round(coalesce(sum(amount) filter (where due_date < d0 - 60 and due_date >= d0 - 90), 0)),
      'b90p', round(coalesce(sum(amount) filter (where due_date < d0 - 90), 0)),
      'max_days', coalesce(max(d0 - due_date) filter (where due_date < d0), 0),
      'due_7', round(coalesce(sum(amount) filter (where due_date >= d0 and due_date <= d0 + 7), 0)),
      'paid_mtd', (select round(coalesce(sum(amount), 0)) from console.fin_entries where customer_id = p_cid and source = p_source and kind = 'payment' and entry_date between ms and d0),
      'top', coalesce((select jsonb_agg(jsonb_build_object('party', t.party, 'total', round(t.tot), 'overdue', round(t.od), 'days', t.dd) order by t.od desc, t.tot desc)
                  from (select party, sum(amount) as tot, coalesce(sum(amount) filter (where due_date < d0), 0) as od, coalesce(max(d0 - due_date) filter (where due_date < d0), 0) as dd
                          from console.fin_open_items where customer_id = p_cid and source = p_source and kind = 'pay' group by party order by 3 desc, 2 desc limit 5) t), '[]'))
      into r from console.fin_open_items where customer_id = p_cid and source = p_source and kind = 'pay';
    res := res || jsonb_build_object('payables', r);
  end if;

  -- ---- expenses against budget, and against sales value; raw material cost from Raw Material Planning (actual value of the month)
  mat := null;
  if coalesce((select a.ok from console.access_state('rmp', p_cid) a), false) and exists (select 1 from console.rmp_plan_week where customer_id = p_cid and month = mk) then
    select coalesce(sum(coalesce(pw.cost_amt, pw.received_qty * coalesce(st.rate, 0))), 0) into mat
      from console.rmp_plan_week pw left join console.rmp_stock st on st.customer_id = pw.customer_id and st.material_code = pw.material_code
     where pw.customer_id = p_cid and pw.month = mk;
  end if;
  select count(*) into n from console.fin_entries where customer_id = p_cid and source = p_source and kind = 'expense' and entry_date between ms and d0;
  if n > 0 or exists (select 1 from console.fin_budget where customer_id = p_cid and month in (mk, '*')) or mat is not null then
    r := jsonb_build_object('day', extract(day from d0)::int, 'days_in_month', mlen, 'material', case when mat is null then null else round(mat) end,
      'total', (select round(coalesce(sum(amount), 0)) from console.fin_entries where customer_id = p_cid and source = p_source and kind = 'expense' and entry_date between ms and d0),
      'prev_total', (select round(coalesce(sum(amount), 0)) from console.fin_entries where customer_id = p_cid and source = p_source and kind = 'expense' and entry_date >= pms and entry_date < ms),
      'budget_total', (select round(coalesce(sum(b.amount), 0)) from (select distinct on (head) head, amount from console.fin_budget where customer_id = p_cid and month in (mk, '*') order by head, (month = mk) desc) b));
    r := jsonb_set(r, '{heads}', coalesce((select jsonb_agg(jsonb_build_object('head', h.head, 'spent', round(h.spent), 'budget', h.budget, 'prev', round(h.prev)) order by (case when h.budget > 0 then h.spent / h.budget else 0 end) desc, h.spent desc)
                  from (select coalesce(x.head, b.head) as head, coalesce(x.spent, 0) as spent, coalesce(x.prev, 0) as prev, b.amount as budget
                          from (select coalesce(nullif(head, ''), 'Other') as head, coalesce(sum(amount) filter (where entry_date between ms and d0), 0) as spent, coalesce(sum(amount) filter (where entry_date >= pms and entry_date < ms), 0) as prev
                                  from console.fin_entries where customer_id = p_cid and source = p_source and kind = 'expense' and entry_date >= pms and entry_date <= d0 group by 1) x
                          full join (select distinct on (head) head, round(amount) as amount from console.fin_budget where customer_id = p_cid and month in (mk, '*') order by head, (month = mk) desc) b on lower(b.head) = lower(x.head)
                         where coalesce(x.spent, 0) > 0 or coalesce(b.amount, 0) > 0) h), '[]'));
    res := res || jsonb_build_object('expenses', r);
  end if;

  -- ---- cash movement of the month
  if exists (select 1 from console.fin_entries where customer_id = p_cid and source = p_source and kind in ('receipt', 'payment') and entry_date between ms and d0) then
    res := res || jsonb_build_object('cash', jsonb_build_object('receipts', (select round(coalesce(sum(amount), 0)) from console.fin_entries where customer_id = p_cid and source = p_source and kind = 'receipt' and entry_date between ms and d0),
      'payments', (select round(coalesce(sum(amount), 0)) from console.fin_entries where customer_id = p_cid and source = p_source and kind = 'payment' and entry_date between ms and d0),
      'expenses', (select round(coalesce(sum(amount), 0)) from console.fin_entries where customer_id = p_cid and source = p_source and kind = 'expense' and entry_date between ms and d0),
      'last_date', (select max(entry_date) from console.fin_entries where customer_id = p_cid and source = p_source and kind in ('receipt', 'payment') and entry_date <= d0)));
  end if;
  return res;
end $$;
revoke all on function console.fin_kpis(uuid, jsonb, text) from public, anon, authenticated;

-- ---------- Administration screen (company administrators only) ----------
create or replace function console.fin_admin(p_slug text) returns uuid language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or not console.is_customer_admin(cid) then raise exception 'Only your company''s administrators can use the finance mail.'; end if;
  return cid;
end $$;
revoke all on function console.fin_admin(text) from public, anon, authenticated;

create or replace function public.kmr_fin_get(p_slug text) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.fin_admin(p_slug); s console.fin_settings;
begin
  select * into s from console.fin_settings where customer_id = cid;
  return jsonb_build_object('enabled', coalesce(s.enabled, false), 'recipients', coalesce(s.recipients, ''), 'send_days', coalesce(s.send_days, 'daily'), 'source', coalesce(s.source, 'app'),
    'sections', coalesce(s.sections, '{}'), 'targets', coalesce(s.targets, '{}'), 'last_sent_on', s.last_sent_on,
    'invoicing', coalesce((select a.ok from console.access_state('inv', cid) a), false), 'rmp', coalesce((select a.ok from console.access_state('rmp', cid) a), false),
    'counts', (select jsonb_build_object(
        'recv', (select count(*) from console.fin_open_items where customer_id = cid and kind = 'recv' and source = coalesce(s.source, 'app')),
        'pay', (select count(*) from console.fin_open_items where customer_id = cid and kind = 'pay' and source = coalesce(s.source, 'app')),
        'entries', (select count(*) from console.fin_entries where customer_id = cid and source = coalesce(s.source, 'app')),
        'budget', (select count(*) from console.fin_budget where customer_id = cid),
        'loaded_on', (select (max(created_at) at time zone 'Asia/Kolkata')::date from console.fin_open_items where customer_id = cid and source = coalesce(s.source, 'app')))),
    'me', lower(coalesce(auth.jwt() ->> 'email', '')));
end $$;
grant execute on function public.kmr_fin_get(text) to authenticated;

create or replace function public.kmr_fin_save(p_slug text, p jsonb) returns text language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.fin_admin(p_slug); en boolean := coalesce(p ->> 'enabled', '') in ('true', 't', '1');
  rc text := lower(trim(coalesce(p ->> 'recipients', ''))); sd text := coalesce(nullif(p ->> 'send_days', ''), 'daily'); src text := coalesce(nullif(p ->> 'source', ''), 'app');
  tg jsonb := coalesce(p -> 'targets', '{}'); k text; v numeric;
begin
  if sd not in ('daily', 'mon_sat') then raise exception 'Choose every day or Monday to Saturday.'; end if;
  if src not in ('app', 'tally', 'erp') then raise exception 'Choose where the figures come from.'; end if;
  if en and rc = '' then raise exception 'Add the e-mail address of the top management who should receive it.'; end if;
  for k in select jsonb_object_keys(tg) loop
    if k not in ('dso_target', 'overdue_pct_target', 'expense_pct_target', 'material_pct_target') then raise exception 'Unknown target %.', k; end if;
    v := nullif(tg ->> k, '')::numeric;
    if v is null or v < 0 or v > 365 or (k <> 'dso_target' and v > 100) then raise exception 'Target "%" is not a valid number.', k; end if;
  end loop;
  insert into console.fin_settings (customer_id, enabled, recipients, send_days, source, sections, targets, updated_at, updated_by)
  values (cid, en, rc, sd, src, coalesce(p -> 'sections', '{}'), tg, now(), lower(coalesce(auth.jwt() ->> 'email', '')))
  on conflict (customer_id) do update set enabled = excluded.enabled, recipients = excluded.recipients, send_days = excluded.send_days, source = excluded.source,
    sections = excluded.sections, targets = excluded.targets, updated_at = now(), updated_by = excluded.updated_by;
  return 'ok';
end $$;
grant execute on function public.kmr_fin_save(text, jsonb) to authenticated;

-- typed / pasted data. kind: recv | pay (outstanding bills, replaces the old list), entry (receipt / payment / expense lines, added), budget (per head and month, replaced for those heads)
create or replace function public.kmr_fin_import(p_slug text, p_kind text, p_rows jsonb) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.fin_admin(p_slug); x jsonb; n int := 0; amt numeric; dt date; dd date; k text; hd text; mo text;
begin
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) = 0 then raise exception 'There are no rows to save.'; end if;
  if jsonb_array_length(p_rows) > 5000 then raise exception 'Please load at most 5000 rows at a time.'; end if;
  if p_kind in ('recv', 'pay') then
    delete from console.fin_open_items where customer_id = cid and source = 'app' and kind = p_kind;
    for x in select * from jsonb_array_elements(p_rows) loop
      amt := nullif(regexp_replace(coalesce(x ->> 'amount', ''), '[^0-9.\-]', '', 'g'), '')::numeric;
      if amt is null or amt <= 0 or coalesce(trim(x ->> 'party'), '') = '' then continue; end if;
      dt := nullif(x ->> 'doc_date', '')::date; dd := nullif(x ->> 'due_date', '')::date;
      insert into console.fin_open_items (customer_id, kind, source, party, ref_no, doc_date, due_date, amount) values (cid, p_kind, 'app', trim(x ->> 'party'), coalesce(trim(x ->> 'ref_no'), ''), dt, dd, amt);
      n := n + 1;
    end loop;
  elsif p_kind = 'entry' then
    for x in select * from jsonb_array_elements(p_rows) loop
      k := lower(coalesce(x ->> 'kind', ''));
      amt := nullif(regexp_replace(coalesce(x ->> 'amount', ''), '[^0-9.\-]', '', 'g'), '')::numeric;
      if k not in ('receipt', 'payment', 'expense') or amt is null or amt <= 0 then continue; end if;
      dt := nullif(x ->> 'entry_date', '')::date; if dt is null then continue; end if;
      insert into console.fin_entries (customer_id, kind, source, entry_date, party, head, ref_no, amount, note, created_by)
      values (cid, k, 'app', dt, nullif(trim(x ->> 'party'), ''), coalesce(trim(x ->> 'head'), ''), nullif(trim(x ->> 'ref_no'), ''), amt, nullif(trim(x ->> 'note'), ''), lower(coalesce(auth.jwt() ->> 'email', '')));
      n := n + 1;
    end loop;
  elsif p_kind = 'budget' then
    for x in select * from jsonb_array_elements(p_rows) loop
      hd := trim(coalesce(x ->> 'head', '')); mo := coalesce(nullif(trim(x ->> 'month'), ''), '*');
      amt := nullif(regexp_replace(coalesce(x ->> 'amount', ''), '[^0-9.]', '', 'g'), '')::numeric;
      if hd = '' or amt is null or (mo <> '*' and mo !~ '^\d{4}-(0[1-9]|1[0-2])$') then continue; end if;
      delete from console.fin_budget where customer_id = cid and month = mo and lower(head) = lower(hd);
      insert into console.fin_budget (customer_id, month, head, amount) values (cid, mo, hd, amt);
      n := n + 1;
    end loop;
  else raise exception 'Unknown data type.'; end if;
  if n = 0 then raise exception 'No valid row found. Check the date format (YYYY-MM-DD) and the amount.'; end if;
  return jsonb_build_object('saved', n, 'skipped', jsonb_array_length(p_rows) - n);
end $$;
grant execute on function public.kmr_fin_import(text, text, jsonb) to authenticated;

-- latest lines typed in the app (to correct a mistake) and delete
create or replace function public.kmr_fin_recent(p_slug text) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.fin_admin(p_slug);
begin
  return jsonb_build_object(
    'entries', coalesce((select jsonb_agg(to_jsonb(t) order by t.entry_date desc, t.created_at desc) from (select id, kind, entry_date, party, head, ref_no, amount, created_at from console.fin_entries where customer_id = cid and source = 'app' order by entry_date desc, created_at desc limit 25) t), '[]'),
    'budget', coalesce((select jsonb_agg(to_jsonb(b) order by b.month, b.head) from (select month, head, amount from console.fin_budget where customer_id = cid order by month, head limit 60) b), '[]'));
end $$;
grant execute on function public.kmr_fin_recent(text) to authenticated;
create or replace function public.kmr_fin_delete(p_slug text, p_what text, p_id text, p_month text default null) returns text language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.fin_admin(p_slug);
begin
  if p_what = 'entry' then delete from console.fin_entries where customer_id = cid and source = 'app' and id = p_id::uuid;
  elsif p_what = 'budget' then delete from console.fin_budget where customer_id = cid and month = coalesce(p_month, '*') and head = p_id;
  elsif p_what in ('recv', 'pay') then delete from console.fin_open_items where customer_id = cid and source = 'app' and kind = p_what;
  else raise exception 'Unknown data type.'; end if;
  return 'ok';
end $$;
grant execute on function public.kmr_fin_delete(text, text, text, text) to authenticated;

-- ---------- ERP bridge (Tally / ERP): replaces that source's rows. p = {source, open_items:[{kind,party,ref_no,doc_date,due_date,amount}], entries:[{kind,entry_date,party,head,ref_no,amount}], from_date} ----------
create or replace function public.kmr_fin_bridge(p_slug text, p jsonb) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.fin_admin(p_slug); src text := coalesce(p ->> 'source', ''); x jsonb; n1 int := 0; n2 int := 0; amt numeric; fd date := nullif(p ->> 'from_date', '')::date;
begin
  if src not in ('tally', 'erp') then raise exception 'Unknown source.'; end if;
  if p ? 'open_items' then
    delete from console.fin_open_items where customer_id = cid and source = src;
    for x in select * from jsonb_array_elements(p -> 'open_items') loop
      amt := (x ->> 'amount')::numeric;
      if amt is null or amt <= 0 or coalesce(x ->> 'kind', '') not in ('recv', 'pay') or coalesce(trim(x ->> 'party'), '') = '' then continue; end if;
      insert into console.fin_open_items (customer_id, kind, source, party, ref_no, doc_date, due_date, amount)
      values (cid, x ->> 'kind', src, left(trim(x ->> 'party'), 120), left(coalesce(x ->> 'ref_no', ''), 60), nullif(x ->> 'doc_date', '')::date, nullif(x ->> 'due_date', '')::date, amt);
      n1 := n1 + 1;
    end loop;
  end if;
  if p ? 'entries' then
    delete from console.fin_entries where customer_id = cid and source = src and entry_date >= coalesce(fd, date '1900-01-01');
    for x in select * from jsonb_array_elements(p -> 'entries') loop
      amt := (x ->> 'amount')::numeric;
      if amt is null or amt <= 0 or coalesce(x ->> 'kind', '') not in ('receipt', 'payment', 'expense') or nullif(x ->> 'entry_date', '') is null then continue; end if;
      insert into console.fin_entries (customer_id, kind, source, entry_date, party, head, ref_no, amount, created_by)
      values (cid, x ->> 'kind', src, (x ->> 'entry_date')::date, left(nullif(trim(x ->> 'party'), ''), 120), left(coalesce(trim(x ->> 'head'), ''), 80), left(nullif(trim(x ->> 'ref_no'), ''), 60), amt, 'bridge');
      n2 := n2 + 1;
    end loop;
  end if;
  return jsonb_build_object('open_items', n1, 'entries', n2);
end $$;
revoke all on function public.kmr_fin_bridge(text, jsonb) from public, anon, authenticated;
grant execute on function public.kmr_fin_bridge(text, jsonb) to service_role;

-- ---------- test mail, morning run ----------
create or replace function public.kmr_fin_test(p_slug text) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.fin_admin(p_slug); s console.fin_settings; c console.customers;
begin
  select * into s from console.fin_settings where customer_id = cid; select * into c from console.customers where id = cid;
  return jsonb_build_object('customer_id', cid, 'slug', c.slug, 'company', c.name, 'brand', console.cal_brand(cid), 'sections', coalesce(s.sections, '{}'), 'targets', coalesce(s.targets, '{}'),
    'kpis', console.fin_kpis(cid, coalesce(s.targets, '{}'), coalesce(s.source, 'app')), 'me', lower(coalesce(auth.jwt() ->> 'email', '')));
end $$;
grant execute on function public.kmr_fin_test(text) to authenticated;

create or replace function public.kmr_fin_scan() returns jsonb language plpgsql security definer set search_path = console, public as $$
declare d0 date := (now() at time zone 'Asia/Kolkata')::date; res jsonb := '[]'; s record; rcp text[];
begin
  for s in select a.customer_id, a.recipients, a.send_days, a.sections, a.targets, a.source, c.slug, c.name as company
             from console.fin_settings a join console.customers c on c.id = a.customer_id
            where a.enabled and (a.last_sent_on is null or a.last_sent_on < d0) loop
    if s.send_days = 'mon_sat' and extract(isodow from d0) = 7 then continue; end if;
    select coalesce(array_agg(distinct z.e), '{}') into rcp from (select lower(trim(x)) as e from regexp_split_to_table(coalesce(s.recipients, ''), '[,;[:space:]]+') as x) z
     where z.e ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]{2,}$';
    continue when coalesce(array_length(rcp, 1), 0) = 0;
    res := res || jsonb_build_array(jsonb_build_object('customer_id', s.customer_id, 'slug', s.slug, 'company', s.company, 'brand', console.cal_brand(s.customer_id),
      'recipients', to_jsonb(rcp), 'sections', s.sections, 'targets', s.targets, 'kpis', console.fin_kpis(s.customer_id, s.targets, s.source)));
  end loop;
  return res;
end $$;
revoke all on function public.kmr_fin_scan() from public, anon, authenticated;
grant execute on function public.kmr_fin_scan() to service_role;
create or replace function public.kmr_fin_mark(p_cid uuid) returns void language sql security definer set search_path = console, public as $$
  update console.fin_settings set last_sent_on = (now() at time zone 'Asia/Kolkata')::date where customer_id = p_cid
$$;
revoke all on function public.kmr_fin_mark(uuid) from public, anon, authenticated;
grant execute on function public.kmr_fin_mark(uuid) to service_role;

-- the ERP bridge may now also call kmr_fin_bridge
create or replace function public.kmr_bridge_run(p_key text, p_fn text, p_args jsonb, p_kind text, p_rows integer default 0) returns jsonb
language plpgsql security definer set search_path = console, public as $$
declare cid uuid; sl text; uid uuid; res jsonb;
begin
  if p_fn not in ('kmr_inv_import', 'kmr_mmd_hist_import', 'kmr_dcg_import', 'kmr_cal_import_erp', 'kmr_ops_bulk', 'kmr_fin_bridge') then raise exception 'Not allowed.' using errcode = 'KM403'; end if;
  select k.customer_id into cid from console.sf_erp_keys k where k.key_hash = encode(sha256(convert_to(coalesce(p_key, ''), 'UTF8')), 'hex') and k.active;
  if cid is null then raise exception 'Unknown sync key.' using errcode = 'KM403'; end if;
  select slug into sl from console.customers where id = cid;
  select u.id into uid from auth.users u join console.staff s on s.user_id = u.id and s.active where lower(u.email) = 'info@kmr-groups.com' limit 1;
  if uid is null then raise exception 'The developer login is not set up as KMR staff.' using errcode = 'KM403'; end if;
  perform set_config('request.jwt.claims', jsonb_build_object('role', 'authenticated', 'sub', uid, 'email', 'info@kmr-groups.com')::text, true);
  perform pg_advisory_xact_lock(hashtextextended('bridge:' || cid::text || ':' || p_kind, 0));
  begin
    execute format('select to_jsonb(public.%I($1, $2))', p_fn) into res using sl, p_args;
    insert into console.bridge_runs (customer_id, kind, ok, rows, summary) values (cid, p_kind, true, coalesce(p_rows, 0), coalesce(res, '{}'));
  exception when others then
    insert into console.bridge_runs (customer_id, kind, ok, rows, summary) values (cid, p_kind, false, coalesce(p_rows, 0), jsonb_build_object('error', sqlerrm));
    raise;
  end;
  return coalesce(res, '{}'::jsonb);
end $$;
revoke all on function public.kmr_bridge_run(text, text, jsonb, text, integer) from public, anon, authenticated;
grant execute on function public.kmr_bridge_run(text, text, jsonb, text, integer) to service_role;
