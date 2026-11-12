-- Sales Flow 0102 — invoices pulled from the ERP are ADDED to what was typed by hand for the same part, customer and day (they no longer replace it).
-- sf_despatch.erp_qty = the part of the day's quantity that came from ERP invoices; the rest was typed by hand. Needs 0097. Safe to re-run.
alter table console.sf_despatch add column if not exists erp_qty numeric(14,2) not null default 0;
-- rows already there: the ERP part is what the stored ERP invoices add up to (never more than the day's quantity)
update console.sf_despatch d set erp_qty = least(d.qty, e.q)
  from (select line_id, invdate, sum(qty) q from console.sf_erp_invoice_lines where status = 'ok' and line_id is not null group by 1, 2) e
 where e.line_id = d.line_id and e.invdate = d.day and d.erp_qty = 0;

create or replace function public.kmr_sf_erp_ingest(p_key text, p_from date, p_rows jsonb, p_dry boolean default false, p_force boolean default false) returns jsonb
language plpgsql security definer set search_path = console, public as $$
declare
  cid uuid; kid uuid; today date := (now() at time zone 'Asia/Kolkata')::date; res jsonb;
  inv record; r jsonb; rv record; a text; q numeric; invs text; ld uuid; dy date; res1 record;
  aff text[] := '{}'; existing integer; incoming integer; old_sig text;
  manual numeric; n_changed integer := 0; n_removed integer := 0; n_created integer := 0; n_written integer := 0;
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

    -- the day's despatch = what was typed by hand + the total of that day's ERP invoices (erp_qty remembers the ERP part, so it is never counted twice and never wipes a manual entry)
    foreach a in array (select coalesce(array_agg(distinct x), '{}') from unnest(aff) x) loop
      ld := split_part(a, '|', 1)::uuid; dy := split_part(a, '|', 2)::date;
      select sum(l.qty), string_agg(distinct l.invno, ', ') into q, invs from console.sf_erp_invoice_lines l
       where l.customer_id = cid and l.line_id = ld and l.invdate = dy and l.status = 'ok';
      select greatest(d.qty - d.erp_qty, 0) into manual from console.sf_despatch d where d.line_id = ld and d.day = dy;
      manual := coalesce(manual, 0);
      if coalesce(q, 0) + manual > 0 then
        insert into console.sf_despatch (line_id, customer_id, day, qty, erp_qty, note, updated_by)
        values (ld, cid, dy, manual + coalesce(q, 0), coalesce(q, 0), left(case when coalesce(q, 0) > 0 then 'ERP invoice: ' || invs else null end, 200), 'erp-sync')
        on conflict (line_id, day) do update set qty = excluded.qty, erp_qty = excluded.erp_qty, note = excluded.note, updated_at = now(),
              updated_by = case when excluded.erp_qty > 0 then 'erp-sync' else console.sf_despatch.updated_by end;
        n_written := n_written + 1;
      else
        delete from console.sf_despatch d where d.line_id = ld and d.day = dy;
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

create or replace function public.kmr_sf_save_despatch(p_slug text, p_rows jsonb) returns integer
language plpgsql security definer set search_path = console, public as $$
declare cid uuid; r jsonb; n integer := 0; q numeric; me text := lower(coalesce(auth.jwt() ->> 'email', ''));
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or coalesce(console.sf_role(cid), '') not in ('admin','editor') then
    raise exception 'You can view Sales Flow but not change it. Ask your administrator for editor access.';
  end if;
  for r in select * from jsonb_array_elements(p_rows) loop
    if not exists (select 1 from console.sf_lines where id = (r ->> 'line_id')::uuid and customer_id = cid) then raise exception 'Unknown plan line.'; end if;
    q := coalesce(nullif(r ->> 'qty', '')::numeric, 0);
    if q < 0 then raise exception 'Despatch quantity cannot be negative.'; end if;
    if (r ->> 'day')::date > (now() at time zone 'Asia/Kolkata')::date then raise exception 'You cannot enter despatch for a future date.'; end if;
    if q = 0 then
      delete from console.sf_despatch where line_id = (r ->> 'line_id')::uuid and day = (r ->> 'day')::date;
    else
      insert into console.sf_despatch (line_id, customer_id, day, qty, note, updated_by)
      values ((r ->> 'line_id')::uuid, cid, (r ->> 'day')::date, q, r ->> 'note', me)
      on conflict (line_id, day) do update set qty = excluded.qty, erp_qty = least(console.sf_despatch.erp_qty, excluded.qty), note = excluded.note, updated_at = now(), updated_by = me;
    end if;
    n := n + 1;
  end loop;
  return n;
end $$;
grant execute on function public.kmr_sf_save_despatch(text, jsonb) to authenticated;
