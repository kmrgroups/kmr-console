-- Sales Flow: adding a part that is already in the month's plan with a blank (0) demand no longer overwrites the demand/price already saved.
-- Safe to re-run.
create or replace function public.kmr_sf_save_lines(p_slug text, p jsonb) returns integer
language plpgsql security definer set search_path = console, public as $$
declare cid uuid; r jsonb; n integer := 0; me text := lower(coalesce(auth.jwt() ->> 'email', '')); st text; m date;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or coalesce(console.sf_role(cid), '') not in ('admin','editor') then
    raise exception 'You can view Sales Flow but not change it. Ask your administrator for editor access.';
  end if;
  for r in select * from jsonb_array_elements(case when jsonb_typeof(p) = 'array' then p else jsonb_build_array(p) end) loop
    st := coalesce(r ->> 'sched_type', 'date');
    m  := date_trunc('month', (r ->> 'month')::date)::date;
    if st = 'date' and coalesce(r ->> 'sched_date', '') = '' then raise exception 'Choose the delivery date for % (or switch to Daily / Weekly).', r ->> 'part_code'; end if;
    if st = 'date' and date_trunc('month', (r ->> 'sched_date')::date)::date <> m then raise exception 'The delivery date of % is outside the month.', r ->> 'part_code'; end if;
    if st = 'weekly' and coalesce(r ->> 'sched_weekday', '') = '' then raise exception 'Choose the weekday for the weekly delivery of %.', r ->> 'part_code'; end if;
    if r ? 'id' and (r ->> 'id') ~ '^[0-9a-f-]{36}$' then
      update console.sf_lines set price = coalesce((r ->> 'price')::numeric, price), demand_qty = coalesce((r ->> 'demand_qty')::numeric, demand_qty),
             sched_type = st, sched_date = case when st = 'date' then (r ->> 'sched_date')::date end,
             sched_weekday = case when st = 'weekly' then (r ->> 'sched_weekday')::smallint end,
             remarks = r ->> 'remarks', updated_at = now(), updated_by = me
       where id = (r ->> 'id')::uuid and customer_id = cid;
    else
      insert into console.sf_lines (customer_id, month, buyer_code, buyer_name, part_code, part_name, price, currency, uom, demand_qty,
                                    sched_type, sched_date, sched_weekday, remarks, updated_by)
      values (cid, m, coalesce(r ->> 'buyer_code', ''), coalesce(r ->> 'buyer_name', ''), trim(r ->> 'part_code'), coalesce(r ->> 'part_name', ''),
              coalesce((r ->> 'price')::numeric, 0), coalesce(r ->> 'currency', 'INR'), coalesce(r ->> 'uom', 'pcs'), coalesce((r ->> 'demand_qty')::numeric, 0),
              st, case when st = 'date' then (r ->> 'sched_date')::date end, case when st = 'weekly' then (r ->> 'sched_weekday')::smallint end,
              r ->> 'remarks', me)
      on conflict (customer_id, month, part_code, buyer_code) do update
        -- adding a part that is already in the plan must never wipe what is there: a blank (0) demand or price keeps the existing figure
        set demand_qty = case when excluded.demand_qty > 0 then excluded.demand_qty else console.sf_lines.demand_qty end,
            price = case when excluded.price > 0 then excluded.price else console.sf_lines.price end,
            sched_type = case when excluded.demand_qty > 0 then excluded.sched_type else console.sf_lines.sched_type end,
            sched_date = case when excluded.demand_qty > 0 then excluded.sched_date else console.sf_lines.sched_date end,
            sched_weekday = case when excluded.demand_qty > 0 then excluded.sched_weekday else console.sf_lines.sched_weekday end,
            remarks = coalesce(excluded.remarks, console.sf_lines.remarks), updated_at = now(), updated_by = me;
    end if;
    n := n + 1;
  end loop;
  return n;
end $$;
grant execute on function public.kmr_sf_save_lines(text, jsonb) to authenticated;
