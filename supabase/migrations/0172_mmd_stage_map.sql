-- MMD: part-wise, stage-wise material tracker. One row per lot (route sheet) with, for every stage (operation), what is waiting,
-- at a supplier, made OK, rejected, sent to rework and still under rework; plus the lot's heat code, finished goods and dispatched pieces.
create or replace function public.kmr_mmd_stage_map(p_slug text, p_days integer default 180)
 returns jsonb language plpgsql stable security definer set search_path to 'console','public' as $function$
declare cid uuid := console.qp_cid(p_slug, 'mmd'); since timestamptz := now() - make_interval(days => greatest(1, least(coalesce(p_days, 180), 800)));
begin
  return jsonb_build_object('lots', coalesce((select jsonb_agg(x order by x.created_at desc) from (
    select s.id, s.rs_no, s.part_code, s.part_name, s.customer_name, s.heat_code, s.rm_material, s.qty, s.status, s.due_date, s.created_at,
      (select coalesce(jsonb_agg(jsonb_build_object('seq', o.ord::int, 'name', o.v ->> 'name', 'machine', o.v ->> 'machine', 'type', o.v ->> 'type',
          'wait', (select coalesce(sum(t.bal),0) from console.mmd_tags t where t.rs_id = s.id and t.status = 'open' and t.kind in ('RM','OK') and t.loc = 'op' and t.seq = o.ord),
          'supplier', (select coalesce(sum(d.qty - d.received_qty),0) from console.mmd_dcs d where d.rs_id = s.id and d.status in ('open','part') and d.seq = o.ord),
          'ok', (select coalesce(sum(e.ok_qty),0) from console.mmd_entries e where e.rs_id = s.id and e.status = 'ok' and e.kind = 'process' and e.seq = o.ord),
          'rej', (select coalesce(sum(e.rej_qty),0) from console.mmd_entries e where e.rs_id = s.id and e.status = 'ok' and e.kind = 'process' and e.seq = o.ord),
          'rew', (select coalesce(sum(e.rew_qty),0) from console.mmd_entries e where e.rs_id = s.id and e.status = 'ok' and e.kind = 'process' and e.seq = o.ord),
          'rew_open', (select coalesce(sum(t.bal),0) from console.mmd_tags t where t.rs_id = s.id and t.status = 'open' and t.kind = 'REW' and t.seq = o.ord)
        ) order by o.ord), '[]'::jsonb) from jsonb_array_elements(s.ops) with ordinality o(v, ord)) ops,
      coalesce((select sum(t.qty) from console.mmd_tags t where t.rs_id = s.id and t.loc = 'fg' and t.status <> 'void'),0) fg,
      coalesce((select sum(t.qty) from console.mmd_tags t where t.rs_id = s.id and t.loc = 'dispatched' and t.status <> 'void'),0) dispatched,
      coalesce((select sum(t.bal) from console.mmd_tags t where t.rs_id = s.id and t.kind = 'REJ' and t.status = 'open' and t.dispo is null),0) rej_wait,
      coalesce((select sum(q.qty) from console.mmd_defects q where q.rs_id = s.id and q.kind = 'rej' and not q.void),0) rej_total,
      coalesce((select sum(q.qty) from console.mmd_defects q where q.rs_id = s.id and q.kind = 'rew' and not q.void),0) rew_total
    from console.mmd_route_sheets s where s.customer_id = cid and (s.status = 'open' or s.created_at >= since) order by s.created_at desc limit 500) x), '[]'::jsonb), 'today', (now() at time zone 'Asia/Kolkata')::date);
end $function$;
