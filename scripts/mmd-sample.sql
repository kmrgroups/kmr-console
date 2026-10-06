-- ---------- sample data: route sheets in every state (finished, part-way, waiting too long, at a supplier, just issued), losses and the codes they use ----------
create or replace function console.mmd_sample(p_cid uuid, p_action text) returns integer language plpgsql security definer set search_path = console, public as $$
declare n int := 0; k int; me text := 'sample'; today date := (now() at time zone 'Asia/Kolkata')::date;
        ops_ text[] := array['R. Kumar', 'S. Mani', 'P. Selvi', 'A. Raja', 'M. Devi']; defs text[] := array['R01', 'R02', 'R05', 'R09', 'R13', 'R11'];
        specs text[] := array['Ø42.50 ±0.05', 'Ø42.50 ±0.05', '118.00 ±0.10', 'Ra 1.6 max', 'No dent / damage', 'No burr']; acts text[] := array['Ø42.63', 'Ø42.41', '118.22', 'Ra 2.8', 'Dent on flange', 'Burr at hole edge'];
        p record; rs jsonb; tg text; stage text[]; nxt text[]; i int := 0; j int; b int; part_ops jsonb; op jsonb; nops int; st text; r jsonb; q numeric; bal numeric; v_bal numeric; batch numeric; rj numeric; rw numeric; at timestamptz; base timestamptz; stop_at int;
        res jsonb; rewtag text; heat text; mat text; d int; m record; sup text; dcno text; dcq numeric; shf text;
begin
  if p_action = 'flush' then
    delete from console.mmd_loss where customer_id = p_cid and sample; get diagnostics k = row_count; n := n + k;
    delete from console.mmd_route_sheets where customer_id = p_cid and sample; get diagnostics k = row_count; n := n + k;
    return n;
  end if;
  if exists (select 1 from console.mmd_route_sheets where customer_id = p_cid and sample) then return 0; end if;
  -- the lists the entries use (only what is missing; flagged as sample)
  insert into console.ops_records (customer_id, kind, code, name, data, sample, updated_by)
  select p_cid, 'loss_codes', v.c, v.n, jsonb_build_object('category', v.cat, 'group', v.g, 'planned', v.pl, 'owner', v.o), true, me
    from (values ('D01', 'Machine breakdown — mechanical', 'Availability', 'Breakdown', 'No', 'Maintenance'), ('D02', 'Machine breakdown — electrical / electronic', 'Availability', 'Breakdown', 'No', 'Maintenance'), ('D06', 'Set-up / changeover', 'Availability', 'Set-up & changeover', 'No', 'Production'),
                 ('D09', 'Tool breakage / unplanned tool change', 'Availability', 'Tooling', 'No', 'Tool room'), ('D12', 'No raw material', 'Availability', 'Material', 'No', 'Stores'), ('D14', 'No operator / absenteeism', 'Availability', 'Manpower', 'No', 'Production'),
                 ('D19', 'Preventive maintenance (planned)', 'Availability', 'Planned stop', 'Yes', 'Maintenance'), ('D22', 'Minor stoppage (under 5 min)', 'Performance', 'Speed', 'No', 'Production')) v(c, n, cat, g, pl, o)
  on conflict (customer_id, kind, code) do nothing;
  insert into console.ops_records (customer_id, kind, code, name, data, sample, updated_by)
  select p_cid, 'defect_codes', v.c, v.n, jsonb_build_object('type', v.t, 'category', v.cat, 'cause_class', v.cl), true, me
    from (values ('R01', 'OD oversize', 'Rework', 'Dimensional', 'Machine'), ('R02', 'OD undersize', 'Rejection', 'Dimensional', 'Method'), ('R05', 'Length / step out of tolerance', 'Either', 'Dimensional', 'Method'), ('R09', 'Surface finish out', 'Either', 'Surface', 'Tooling'),
                 ('R11', 'Burr', 'Rework', 'Surface', 'Method'), ('R13', 'Handling damage / dent', 'Rejection', 'Handling', 'Man')) v(c, n, t, cat, cl)
  on conflict (customer_id, kind, code) do nothing;
  insert into console.ops_records (customer_id, kind, code, name, data, sample, updated_by)
  select p_cid, 'shifts', v.c, v.n, jsonb_build_object('start', v.s, 'end', v.e, 'break_min', 40), true, me
    from (values ('A', 'First shift', '06:00', '14:00'), ('B', 'Second shift', '14:00', '22:00'), ('C', 'Night shift', '22:00', '06:00')) v(c, n, s, e)
  on conflict (customer_id, kind, code) do nothing;
  -- one supplier process (heat treatment) in the first sample part's routing
  select r.code into sup from console.ops_records r where r.customer_id = p_cid and r.kind = 'suppliers' and r.sample and r.data ->> 'category' = 'Outsourced process' order by r.code limit 1;
  for p in select r.code, r.name, r.data from console.ops_records r where r.customer_id = p_cid and r.kind = 'parts' and r.sample and r.active
             and exists (select 1 from console.ops_records c where c.customer_id = p_cid and c.kind = 'cycle_times' and c.data ->> 'part_no' = r.code) order by r.code limit 6 loop
    i := i + 1;
    if i in (1, 5) and sup is not null then
      insert into console.ops_records (customer_id, kind, code, name, data, sample, updated_by)
      values (p_cid, 'cycle_times', p.code || ' · Heat treatment OP30', 'Heat treatment OP30', jsonb_build_object('part_no', p.code, 'op_no', 30, 'op_type', 'Supplier process', 'supplier', sup, 'cycle_time_sec', 0), true, me) on conflict do nothing;
    end if;
    part_ops := console.mmd_route(p_cid, p.code); nops := jsonb_array_length(part_ops);
    base := ((today - (13 - i * 2)) + time '08:00') at time zone 'Asia/Kolkata'; base := least(base, now() - interval '3 days');
    mat := coalesce(p.data ->> 'material', (select r.code from console.ops_records r where r.customer_id = p_cid and r.kind = 'raw_materials' order by r.code limit 1));
    heat := 'H' || to_char(base, 'YYMM') || lpad(i::text, 3, '0') || chr(64 + i);
    q := 600 + i * 400;
    if i = 6 then base := now() - interval '20 hours'; end if;
    rs := console.mmd_issue(p_cid, me, jsonb_build_object('part_code', p.code, 'material_code', mat, 'qty', q, 'heat_code', heat, 'mill_cert', 'MTC-' || to_char(base, 'YYMM') || '-' || i, 'due_date', (today + (3 + i * 2))::text), base, true);
    n := n + 2;
    select tag_no into tg from console.mmd_tags where id = (rs ->> 'tag_id')::uuid;
    stage := array[tg];
    stop_at := case i when 4 then 2 when 5 then 99 when 6 then 0 else 99 end;
    for j in 1..nops loop
      exit when j > stop_at;
      op := part_ops -> (j - 1); nxt := '{}';
      foreach st in array stage loop
        select t0.bal into v_bal from console.mmd_tags t0 where t0.customer_id = p_cid and t0.tag_no = st;
        continue when v_bal is null or v_bal <= 0;
        at := least(base + make_interval(days => j - 1, hours => 1 + (i % 3)), now() - make_interval(days => case when i = 4 and j = 2 then 4 else 0 end, hours => 2));
        if op ->> 'type' = 'supplier' then
          if i = 5 then
            res := console.mmd_dc(p_cid, me, jsonb_build_object('tag_no', st, 'qty', v_bal, 'vehicle', 'TN 38 AB 4521', 'expected_date', (today + 1)::text, 'entry_at', (now() - interval '3 days')::text), true); n := n + 1;
            stop_at := j; exit;
          end if;
          res := console.mmd_dc(p_cid, me, jsonb_build_object('tag_no', st, 'qty', v_bal, 'vehicle', 'TN 38 AB 4521', 'expected_date', (at + interval '3 days')::date::text, 'entry_at', at::text), true); dcno := res ->> 'dc_no';
          res := console.mmd_grn(p_cid, me, jsonb_build_object('dc_no', dcno, 'ok', v_bal - 2, 'inv_no', 'INV-' || (4100 + i), 'entry_at', (at + interval '2 days')::text,
                    'rej_lines', jsonb_build_array(jsonb_build_object('code', 'R13', 'qty', 2, 'spec', 'No damage', 'actual', 'Handling dent'))), true); n := n + 3;
          for r in select x from jsonb_array_elements(res -> 'tags') t(x) where x -> 'tag' ->> 'kind' = 'OK' loop nxt := nxt || (r -> 'tag' ->> 'tag_no'); end loop;
        else
          for b in 1..(case when j = 1 then 2 else 1 end) loop
            select t0.bal into v_bal from console.mmd_tags t0 where t0.customer_id = p_cid and t0.tag_no = st;
            exit when v_bal <= 0;
            if j = 1 then batch := case when b = 1 then round(v_bal * 0.55) else v_bal end; else batch := v_bal; end if;
            rj := floor(batch * (0.4 + ((i + j + b) % 5) * 0.55) / 100); rw := floor(batch * (((i * j + b) % 4) * 0.45) / 100);
            d := 1 + ((i + j + b) % 6);
            shf := case when extract(hour from at at time zone 'Asia/Kolkata') < 14 then 'A' else 'B' end;
            res := console.mmd_entry(p_cid, me, jsonb_build_object('tag_no', st, 'ok', batch - rj - rw, 'machine', coalesce(nullif(op ->> 'machine', ''), 'BENCH'), 'operator', ops_[1 + ((i + j + b) % 5)], 'shift', shf, 'engineer', 'MMD Engineer (sample)',
                      'entry_at', (at + make_interval(hours => b * 3))::text,
                      'rej_lines', case when rj > 0 then jsonb_build_array(jsonb_build_object('code', defs[d], 'qty', rj, 'spec', specs[d], 'actual', acts[d])) else '[]'::jsonb end,
                      'rew_lines', case when rw > 0 then jsonb_build_array(jsonb_build_object('code', defs[1 + (d % 6)], 'qty', rw, 'spec', specs[1 + (d % 6)], 'actual', acts[1 + (d % 6)])) else '[]'::jsonb end), true);
            n := n + 1;
            for r in select x from jsonb_array_elements(res -> 'tags') t(x) loop
              if r -> 'tag' ->> 'kind' = 'OK' then nxt := nxt || (r -> 'tag' ->> 'tag_no');
              elsif r -> 'tag' ->> 'kind' = 'REW' then
                res := console.mmd_rework(p_cid, me, jsonb_build_object('tag_no', r -> 'tag' ->> 'tag_no', 'ok', greatest(0, (r -> 'tag' ->> 'qty')::numeric - 1), 'operator', ops_[1 + ((i + j) % 5)], 'shift', shf, 'engineer', 'MMD Engineer (sample)', 'entry_at', (at + make_interval(hours => b * 3 + 4))::text,
                          'rej_lines', case when (r -> 'tag' ->> 'qty')::numeric >= 1 then jsonb_build_array(jsonb_build_object('code', 'R02', 'qty', 1, 'spec', 'Ø42.50 ±0.05', 'actual', 'Ø42.38')) else '[]'::jsonb end), true);
                n := n + 1;
                for r in select x from jsonb_array_elements(res -> 'tags') t(x) where x -> 'tag' ->> 'kind' = 'OK' loop nxt := nxt || (r -> 'tag' ->> 'tag_no'); end loop;
              end if;
            end loop;
          end loop;
        end if;
      end loop;
      stage := nxt;
    end loop;
    -- finished goods: dispatch half of the first two
    if i in (1, 2) then
      for st in select t.tag_no from console.mmd_tags t where t.customer_id = p_cid and t.sample and t.rs_id = (rs ->> 'rs_id')::uuid and t.loc = 'fg' and t.bal > 0 loop
        perform console.mmd_dispatch(p_cid, me, jsonb_build_object('tag_no', st, 'qty', greatest(1, floor((select t0.bal from console.mmd_tags t0 where t0.customer_id = p_cid and t0.tag_no = st) / 2)), 'ref', 'INV-' || (7000 + i), 'operator', 'Dispatch', 'entry_at', (now() - interval '1 day')::text));
        update console.mmd_entries set sample = true where customer_id = p_cid and kind = 'dispatch' and not sample;
      end loop;
    end if;
  end loop;
  -- loss hours: each machine used, last 10 days
  for m in select distinct x ->> 'machine' mc from console.mmd_route_sheets s, jsonb_array_elements(s.ops) x where s.customer_id = p_cid and s.sample and coalesce(x ->> 'machine', '') <> '' loop
    for d in 0..9 loop
      continue when (ascii(right(m.mc, 1)) + d) % 3 = 0;
      insert into console.mmd_loss (customer_id, loss_date, shift, machine_code, d_code, d_name, minutes, remark, operator, sample, created_by)
      select p_cid, today - d, case when (d % 2) = 0 then 'A' else 'B' end, m.mc, c.code, c.name, 10 + ((ascii(right(m.mc, 1)) * 7 + d * 13) % 80), 'Sample entry', ops_[1 + (d % 5)], true, me
        from console.ops_records c where c.customer_id = p_cid and c.kind = 'loss_codes' and c.code = (array['D01', 'D06', 'D09', 'D12', 'D14', 'D19', 'D22', 'D02'])[1 + ((ascii(right(m.mc, 1)) + d * 3) % 8)];
      n := n + 1;
    end loop;
  end loop;
  return n;
end $$;
revoke all on function console.mmd_sample(uuid, text) from public, anon, authenticated;
