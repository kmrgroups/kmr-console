-- 0177: Production plan reads / writes the same stage stocks as the Raw Material Plan work sheet (rmp_partstock: minimum stock, supermarket, FG, FI, WIP, WIP stage 2, incoming, supplier),
-- and plans only parts that have a Sales Flow schedule (or a manual demand line) for the month.
drop function if exists public.kmr_ppl_save(text, text, jsonb, jsonb, jsonb, jsonb);
create or replace function console.ppl_data(cid uuid, p_month text) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare m0 date := (p_month || '-01')::date; out jsonb; d0 date := (now() at time zone 'Asia/Kolkata')::date - 59;
begin
  if p_month !~ '^\d{4}-(0[1-9]|1[0-2])$' then raise exception 'Month must look like 2026-11.'; end if;
  with dem as (
    select l.part_code, max(l.part_name) part_name, sum(l.demand_qty) demand, coalesce(sum((select sum(d.qty) from console.sf_despatch d where d.line_id = l.id)), 0) despatched, min(l.sched_date) due, 'Sales Flow'::text src
      from console.sf_lines l where l.customer_id = cid and l.month = m0 group by l.part_code
    union all
    select d.part_code, max(d.part_name), sum(d.qty), 0, min(d.due), 'Manual' from console.ppl_demand d where d.customer_id = cid and d.month = p_month group by d.part_code),
  parts as (select part_code, max(part_name) part_name, sum(demand) demand, sum(despatched) despatched, min(due) due, string_agg(distinct src, ' + ') src from dem group by part_code having sum(demand) > 0),
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
    'ps', coalesce((select jsonb_object_agg(upper(regexp_replace(part_code, '[^A-Za-z0-9]', '', 'g')), jsonb_build_object('safety', safety_qty, 'rrs', rrs_qty, 'wip', wip_qty, 'wip2', wip2_qty, 'fg', fg_qty, 'fi', fi_qty, 'inc', inc_qty, 'sup', sup_qty))
                      from console.rmp_partstock where customer_id = cid and month = p_month), '{}'::jsonb),
    'stock', coalesce((select jsonb_agg(jsonb_build_object('part', part_code, 'seq', seq, 'qty', qty)) from console.ppl_stock where customer_id = cid), '[]'::jsonb),
    'manual', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'part', part_code, 'name', part_name, 'qty', qty, 'due', due, 'note', note) order by part_code) from console.ppl_demand where customer_id = cid and month = p_month), '[]'::jsonb),
    'cfg', coalesce((select jsonb_object_agg(k, v) from console.ppl_cfg where customer_id = cid), '{}'::jsonb),
    'last', (select jsonb_build_object('version', version, 'at', published_at, 'by', published_by, 'summary', summary) from console.ppl_plan where customer_id = cid and month = p_month order by version desc limit 1)
  ) into out;
  return out;
end $$;
revoke all on function console.ppl_data(uuid, text) from public, anon, authenticated;

create or replace function public.kmr_ppl_save(p_slug text, p_month text, p_ps jsonb, p_stock jsonb, p_demand jsonb, p_cfg jsonb) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'ppl'); r jsonb; kv record; me text := lower(coalesce(auth.jwt() ->> 'email', '')); pc text; f text; col text;
begin
  if p_ps is not null then
    for r in select * from jsonb_array_elements(p_ps) loop
      pc := coalesce((select part_code from console.rmp_partstock where customer_id = cid and month = p_month and upper(regexp_replace(part_code, '[^A-Za-z0-9]', '', 'g')) = upper(regexp_replace(r ->> 'part', '[^A-Za-z0-9]', '', 'g')) limit 1),
                     (select part_code from console.rmp_bom where customer_id = cid and upper(regexp_replace(part_code, '[^A-Za-z0-9]', '', 'g')) = upper(regexp_replace(r ->> 'part', '[^A-Za-z0-9]', '', 'g')) limit 1), r ->> 'part');
      insert into console.rmp_partstock (customer_id, month, part_code, updated_by) values (cid, p_month, pc, me) on conflict (customer_id, month, part_code) do nothing;
      foreach f in array array['safety', 'rrs', 'wip', 'wip2', 'fg', 'fi', 'inc', 'sup'] loop
        if r ? f then
          col := f || '_qty';
          execute format('update console.rmp_partstock set %I = $1, updated_by = $2, updated_at = now() where customer_id = $3 and month = $4 and part_code = $5', col)
            using greatest(0, coalesce(nullif(r ->> f, '')::numeric, 0)), me, cid, p_month, pc;
        end if;
      end loop;
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
