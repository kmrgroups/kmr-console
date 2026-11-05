-- =====================================================================
-- KMR platform — Sales Flow: automatic despatch from a customer's local ERP. Needs 0033_sales_flow.sql. Safe to re-run.
--  • A small program at the plant reads new invoices from the ERP and posts them with a key tied to ONE plant.
--  • Every invoice line is kept (sf_erp_invoice_lines), so sending an invoice again never double counts and an edited
--    or cancelled invoice corrects the figure.
--  • The day's despatch for a part = the total of that day's ERP invoices. It replaces a manual figure for that part and day.
--  • A part not in the month's plan is added as an unplanned sale (demand 0) when the Operations Master knows it for that
--    customer; otherwise the line waits on a review list and is retried on every run.
-- =====================================================================
do $$ begin
  if to_regclass('console.sf_despatch') is null then raise exception 'Run 0033_sales_flow.sql first.'; end if;
end $$;

create table if not exists console.sf_erp_keys (
  id           uuid primary key default gen_random_uuid(),
  customer_id  uuid not null references console.customers(id) on delete cascade,
  key_hash     text not null unique,
  label        text not null default '',
  active       boolean not null default true,
  created_at   timestamptz not null default now(),
  created_by   text,
  last_seen_at timestamptz,
  last_run     jsonb
);

create table if not exists console.sf_erp_invoice_lines (
  id          bigserial primary key,
  customer_id uuid not null references console.customers(id) on delete cascade,
  invno       text not null,
  invdate     date not null,
  custcode    text not null default '',
  custname    text not null default '',
  part_code   text not null,
  part_name   text not null default '',
  uom         text not null default '',
  rate        numeric(14,2) not null default 0,
  qty         numeric(14,3) not null,
  line_id     uuid references console.sf_lines(id) on delete set null,
  status      text not null default 'review' check (status in ('ok','review')),
  reason      text,
  created_at  timestamptz not null default now()
);
create index if not exists sf_erp_lines_inv on console.sf_erp_invoice_lines (customer_id, invno);
create index if not exists sf_erp_lines_date on console.sf_erp_invoice_lines (customer_id, invdate);
create index if not exists sf_erp_lines_line on console.sf_erp_invoice_lines (line_id, invdate);
create index if not exists sf_erp_lines_review on console.sf_erp_invoice_lines (customer_id) where status = 'review';

-- ERP customer code -> Operations Master customer code, set from the review list when the names do not match by themselves
create table if not exists console.sf_erp_customer_map (
  customer_id  uuid not null references console.customers(id) on delete cascade,
  erp_custcode text not null,
  buyer_code   text not null,
  updated_at   timestamptz not null default now(),
  updated_by   text,
  primary key (customer_id, erp_custcode)
);

alter table console.sf_erp_keys          enable row level security;
alter table console.sf_erp_invoice_lines enable row level security;
alter table console.sf_erp_customer_map  enable row level security;
drop policy if exists sf_erp_keys_staff on console.sf_erp_keys;
create policy sf_erp_keys_staff on console.sf_erp_keys for all to authenticated using (console.is_staff()) with check (console.is_staff());
drop policy if exists sf_erp_lines_staff on console.sf_erp_invoice_lines;
create policy sf_erp_lines_staff on console.sf_erp_invoice_lines for all to authenticated using (console.is_staff()) with check (console.is_staff());
drop policy if exists sf_erp_map_staff on console.sf_erp_customer_map;
create policy sf_erp_map_staff on console.sf_erp_customer_map for all to authenticated using (console.is_staff()) with check (console.is_staff());

-- "1003 062 025" = "1003062025" (same rule as the invoice upload in kmr-import.js)
create or replace function console.sf_erp_norm(s text) returns text
language sql immutable as $$ select upper(regexp_replace(coalesce(s, ''), '[^A-Za-z0-9]', '', 'g')) $$;

-- Do two customer names share a real word? "ROBERT BOSCH-NA" and "Bosch Limited" do. Same stop words as kmr-import.js.
create or replace function console.sf_erp_cust_match(a text, b text) returns boolean
language sql immutable as $$
  with t as (
    select x, y
      from regexp_split_to_table(lower(coalesce(a, '')), '[^a-z0-9]+') x, regexp_split_to_table(lower(coalesce(b, '')), '[^a-z0-9]+') y
     where x <> '' and y <> ''
       and x not in ('limited','ltd','pvt','private','llp','co','company','corp','corporation','inc','the','and','of','india','m','s','ms')
       and y not in ('limited','ltd','pvt','private','llp','co','company','corp','corporation','inc','the','and','of','india','m','s','ms'))
  select exists (select 1 from t where x = y or (length(x) >= 5 and length(y) >= 5 and left(x, 5) = left(y, 5)))
$$;

-- Find (or, for a known part not in the plan, create) the plan line for one invoice line. Never guesses between customers.
create or replace function console.sf_erp_resolve(cid uuid, p_month date, p_custcode text, p_custname text, p_part text, p_rate numeric, p_uom text,
                                                  out o_line uuid, out o_reason text, out o_created boolean)
language plpgsql set search_path = console, public as $$
declare buyer text; n integer; key text := console.sf_erp_norm(p_part); who text := coalesce(p_custcode, '') || ' ' || coalesce(p_custname, ''); first_id text;
        p_code text; p_name text; p_buyer text; p_bname text;
begin
  o_created := false;
  select m.buyer_code into buyer from console.sf_erp_customer_map m where m.customer_id = cid and lower(m.erp_custcode) = lower(p_custcode);

  select count(*), min(l.id::text) into n, first_id from console.sf_lines l
   where l.customer_id = cid and l.month = p_month and console.sf_erp_norm(l.part_code) = key
     and case when buyer is not null then l.buyer_code = buyer else console.sf_erp_cust_match(who, l.buyer_name) end;
  if n = 1 then o_line := first_id::uuid; return; end if;
  if n > 1 then o_reason := 'This part is in the plan under more than one matching customer. Choose the customer for this ERP code.'; return; end if;

  select count(*), min(p.id::text) into n, first_id from console.ops_records p
    left join console.ops_records cu on cu.customer_id = p.customer_id and cu.kind = 'customers' and cu.code = p.data ->> 'customer'
   where p.customer_id = cid and p.kind = 'parts' and p.active and console.sf_erp_norm(p.code) = key
     and case when buyer is not null then p.data ->> 'customer' = buyer else console.sf_erp_cust_match(who, coalesce(cu.name, p.data ->> 'customer', '')) end;
  if n = 0 then o_reason := 'Part not found for this customer in the plan or the Operations Master.'; return; end if;
  if n > 1 then o_reason := 'This part is in the Operations Master under more than one matching customer. Choose the customer for this ERP code.'; return; end if;

  select p.code, p.name, coalesce(p.data ->> 'customer', ''), coalesce(cu.name, p.data ->> 'customer', '') into p_code, p_name, p_buyer, p_bname
    from console.ops_records p
    left join console.ops_records cu on cu.customer_id = p.customer_id and cu.kind = 'customers' and cu.code = p.data ->> 'customer'
   where p.id::text = first_id;
  insert into console.sf_lines (customer_id, month, buyer_code, buyer_name, part_code, part_name, price, currency, uom, demand_qty, sched_type, updated_by)
  values (cid, p_month, p_buyer, p_bname, p_code, coalesce(p_name, ''), greatest(coalesce(p_rate, 0), 0), 'INR',
          case when lower(coalesce(p_uom, '')) in ('', 'nos', 'no', 'pcs') then 'pcs' else lower(p_uom) end, 0, 'daily', 'erp-sync')
  on conflict (customer_id, month, part_code, buyer_code) do update set updated_at = now()
  returning id into o_line;
  o_created := true;
end $$;

-- p_key  : the plant's sync key.  p_from : start of the window the program read.
-- p_rows : [{invno, invdate, custcode, custname, part_code, part_name, uom, rate, qty}] for every live invoice since p_from,
--          or null when nothing changed (then only the review list is retried).
-- p_dry  : work everything out, report it, save nothing.
create or replace function public.kmr_sf_erp_ingest(p_key text, p_from date, p_rows jsonb, p_dry boolean default false, p_force boolean default false) returns jsonb
language plpgsql security definer set search_path = console, public as $$
declare
  cid uuid; kid uuid; today date := (now() at time zone 'Asia/Kolkata')::date; res jsonb;
  inv record; r jsonb; rv record; a text; q numeric; invs text; ld uuid; dy date; res1 record;
  aff text[] := '{}'; existing integer; incoming integer; old_sig text;
  n_changed integer := 0; n_removed integer := 0; n_created integer := 0; n_written integer := 0;
begin
  select k.id, k.customer_id into kid, cid from console.sf_erp_keys k
   where k.key_hash = encode(sha256(convert_to(coalesce(p_key, ''), 'UTF8')), 'hex') and k.active;
  if cid is null then raise exception 'Unknown sync key.' using errcode = 'KM403'; end if;
  if not coalesce((select ok from console.access_state('sales', cid)), false) then raise exception 'The Sales Flow licence is not active.' using errcode = 'KM403'; end if;
  perform pg_advisory_xact_lock(hashtextextended('sf_erp:' || cid::text, 0));

  if p_rows is not null then
    if jsonb_typeof(p_rows) <> 'array' or p_from is null then raise exception 'Rows and a start date are required.' using errcode = 'KM400'; end if;
    -- A broken read at the plant must not wipe a month of despatch.
    select count(distinct invno) into existing from console.sf_erp_invoice_lines where customer_id = cid and invdate >= p_from;
    select count(distinct e ->> 'invno') into incoming from jsonb_array_elements(p_rows) e;
    if existing >= 20 and incoming < existing / 2 and not p_force then
      raise exception 'Refused: % invoices sent but % are already held for this period.', incoming, existing using errcode = 'KM409';
    end if;
  end if;

  begin
    if p_rows is not null then
      -- invoices no longer in the ERP window (deleted or cancelled)
      for rv in select distinct l.line_id, l.invdate from console.sf_erp_invoice_lines l
                 where l.customer_id = cid and l.invdate >= p_from and l.line_id is not null
                   and not exists (select 1 from jsonb_array_elements(p_rows) e where e ->> 'invno' = l.invno) loop
        aff := aff || (rv.line_id::text || '|' || rv.invdate::text);
      end loop;
      with gone as (delete from console.sf_erp_invoice_lines l
                     where l.customer_id = cid and l.invdate >= p_from
                       and not exists (select 1 from jsonb_array_elements(p_rows) e where e ->> 'invno' = l.invno) returning l.invno)
      select count(distinct invno) into n_removed from gone;

      -- new or changed invoices only, so a part someone removed from the plan is not brought back by an unrelated invoice
      for inv in select e ->> 'invno' as invno, jsonb_agg(e) as lines,
                        string_agg(concat_ws('|', e ->> 'part_code', round((e ->> 'qty')::numeric, 3)::text, (e ->> 'invdate')::date::text, e ->> 'custcode'), ';'
                                   order by concat_ws('|', e ->> 'part_code', round((e ->> 'qty')::numeric, 3)::text, (e ->> 'invdate')::date::text, e ->> 'custcode')) as sig
                   from jsonb_array_elements(p_rows) e group by 1 loop
        select string_agg(concat_ws('|', l.part_code, round(l.qty, 3)::text, l.invdate::text, l.custcode), ';'
                          order by concat_ws('|', l.part_code, round(l.qty, 3)::text, l.invdate::text, l.custcode))
          into old_sig from console.sf_erp_invoice_lines l where l.customer_id = cid and l.invno = inv.invno;
        continue when old_sig is not distinct from inv.sig;
        n_changed := n_changed + 1;
        for rv in select distinct l.line_id, l.invdate from console.sf_erp_invoice_lines l where l.customer_id = cid and l.invno = inv.invno and l.line_id is not null loop
          aff := aff || (rv.line_id::text || '|' || rv.invdate::text);
        end loop;
        delete from console.sf_erp_invoice_lines l where l.customer_id = cid and l.invno = inv.invno;
        for r in select * from jsonb_array_elements(inv.lines) loop
          insert into console.sf_erp_invoice_lines (customer_id, invno, invdate, custcode, custname, part_code, part_name, uom, rate, qty, status, reason)
          values (cid, inv.invno, (r ->> 'invdate')::date, coalesce(r ->> 'custcode', ''), coalesce(r ->> 'custname', ''), trim(r ->> 'part_code'),
                  coalesce(r ->> 'part_name', ''), coalesce(r ->> 'uom', ''), coalesce((r ->> 'rate')::numeric, 0), (r ->> 'qty')::numeric, 'review', 'Waiting');
        end loop;
      end loop;
    end if;

    -- everything waiting (just added, or still unmatched from an earlier run)
    for rv in select * from console.sf_erp_invoice_lines l where l.customer_id = cid and l.status = 'review' order by l.invdate, l.invno, l.id loop
      if rv.invdate > today then
        update console.sf_erp_invoice_lines set reason = 'Invoice date is in the future.' where id = rv.id;
        continue;
      end if;
      select * into res1 from console.sf_erp_resolve(cid, date_trunc('month', rv.invdate)::date, rv.custcode, rv.custname, rv.part_code, rv.rate, rv.uom);
      if res1.o_line is null then
        update console.sf_erp_invoice_lines set reason = res1.o_reason where id = rv.id;
      else
        update console.sf_erp_invoice_lines set line_id = res1.o_line, status = 'ok', reason = null where id = rv.id;
        aff := aff || (res1.o_line::text || '|' || rv.invdate::text);
        if res1.o_created then n_created := n_created + 1; end if;
      end if;
    end loop;

    -- the day's figure = the total of that day's invoices
    foreach a in array (select coalesce(array_agg(distinct x), '{}') from unnest(aff) x) loop
      ld := split_part(a, '|', 1)::uuid; dy := split_part(a, '|', 2)::date;
      select sum(l.qty), string_agg(distinct l.invno, ', ') into q, invs from console.sf_erp_invoice_lines l
       where l.customer_id = cid and l.line_id = ld and l.invdate = dy and l.status = 'ok';
      if coalesce(q, 0) > 0 then
        insert into console.sf_despatch (line_id, customer_id, day, qty, note, updated_by)
        values (ld, cid, dy, q, left('ERP invoice: ' || invs, 200), 'erp-sync')
        on conflict (line_id, day) do update set qty = excluded.qty, note = excluded.note, updated_at = now(), updated_by = 'erp-sync';
        n_written := n_written + 1;
      else
        delete from console.sf_despatch d where d.line_id = ld and d.day = dy and d.updated_by = 'erp-sync';
      end if;
    end loop;

    res := jsonb_build_object('ok', true, 'dry', p_dry, 'invoices_changed', n_changed, 'invoices_removed', n_removed,
      'plan_lines_added', n_created, 'despatch_written', n_written,
      'lines_ok', (select count(*) from console.sf_erp_invoice_lines where customer_id = cid and status = 'ok'),
      'lines_review', (select count(*) from console.sf_erp_invoice_lines where customer_id = cid and status = 'review'));
    if p_dry then
      res := res || jsonb_build_object('review', coalesce((select jsonb_agg(x) from (
               select custcode, part_code, reason, count(*) as lines, sum(qty) as qty from console.sf_erp_invoice_lines
                where customer_id = cid and status = 'review' group by 1, 2, 3 order by 1, 2 limit 200) x), '[]'));
      raise exception 'dry run' using errcode = 'KM001';   -- undoes everything in this block; res keeps the report
    end if;
    update console.sf_erp_keys set last_seen_at = now(), last_run = res where id = kid;
  exception when sqlstate 'KM001' then null;
  end;
  return res;
end $$;
revoke all on function public.kmr_sf_erp_ingest(text, date, jsonb, boolean, boolean) from public, anon, authenticated;
grant execute on function public.kmr_sf_erp_ingest(text, date, jsonb, boolean, boolean) to service_role;
revoke all on function console.sf_erp_resolve(uuid, date, text, text, text, numeric, text) from public, anon, authenticated;

-- ---------- for the Daily despatch screen ----------
create or replace function public.kmr_sf_erp_status(p_slug text) returns jsonb
language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or console.sf_role(cid) is null then raise exception 'You have no access to Sales Flow.'; end if;
  return jsonb_build_object(
    'connected', exists (select 1 from console.sf_erp_keys k where k.customer_id = cid and k.active),
    'last_seen', (select max(k.last_seen_at) from console.sf_erp_keys k where k.customer_id = cid and k.active),
    'review', coalesce((select jsonb_agg(x) from (
        select l.custcode, l.custname, l.part_code, l.part_name, l.reason, count(*) as lines, sum(l.qty) as qty, min(l.invdate) as first_day, max(l.invdate) as last_day
          from console.sf_erp_invoice_lines l where l.customer_id = cid and l.status = 'review'
         group by 1, 2, 3, 4, 5 order by 1, 3 limit 200) x), '[]'));
end $$;
revoke all on function public.kmr_sf_erp_status(text) from public, anon;
grant execute on function public.kmr_sf_erp_status(text) to authenticated;

-- Shown once; only its hash is kept. A new key switches off the plant's old one.
create or replace function public.kmr_sf_erp_new_key(p_slug text, p_label text default 'ERP sync') returns text
language plpgsql security definer set search_path = console, public as $$
declare cid uuid; raw text := 'sfk_' || replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or coalesce(console.sf_role(cid), '') <> 'admin' then raise exception 'Only a Sales Flow administrator can create the ERP sync key.'; end if;
  update console.sf_erp_keys set active = false where customer_id = cid;
  insert into console.sf_erp_keys (customer_id, key_hash, label, created_by)
  values (cid, encode(sha256(convert_to(raw, 'UTF8')), 'hex'), coalesce(p_label, ''), lower(coalesce(auth.jwt() ->> 'email', '')));
  return raw;
end $$;
revoke all on function public.kmr_sf_erp_new_key(text, text) from public, anon;
grant execute on function public.kmr_sf_erp_new_key(text, text) to authenticated;

-- Which Operations Master customer an ERP customer code means. The next run (within minutes) retries the waiting lines.
create or replace function public.kmr_sf_erp_map(p_slug text, p_custcode text, p_buyer_code text) returns text
language plpgsql security definer set search_path = console, public as $$
declare cid uuid;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or coalesce(console.sf_role(cid), '') not in ('admin','editor') then raise exception 'You cannot change Sales Flow.'; end if;
  insert into console.sf_erp_customer_map (customer_id, erp_custcode, buyer_code, updated_by)
  values (cid, p_custcode, p_buyer_code, lower(coalesce(auth.jwt() ->> 'email', '')))
  on conflict (customer_id, erp_custcode) do update set buyer_code = excluded.buyer_code, updated_at = now(), updated_by = excluded.updated_by;
  return 'ok';
end $$;
revoke all on function public.kmr_sf_erp_map(text, text, text) from public, anon;
grant execute on function public.kmr_sf_erp_map(text, text, text) to authenticated;
