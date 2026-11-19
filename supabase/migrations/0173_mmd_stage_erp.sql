-- MMD Part & stage tracker: current production per part and stage, read from the ERP production history (kept only for days the app has no entry of its own).
create or replace function public.kmr_mmd_stage_erp(p_slug text, p_days integer default 60)
 returns jsonb language plpgsql stable security definer set search_path to 'console','public' as $function$
declare cid uuid := console.qp_cid(p_slug, 'mmd'); d0 date := (now() at time zone 'Asia/Kolkata')::date - (greatest(1, least(coalesce(p_days, 60), 400)) - 1);
begin
  return jsonb_build_object('since', d0, 'rows', coalesce((select jsonb_agg(jsonb_build_array(part_code, part_name, process, q, s, last, mcs, bts, rms, days) order by part_code, process) from (
    select h.part_code, max(h.part_name) part_name, upper(trim(h.process)) process, round(sum(h.qty)) q, round(sum(coalesce(h.scrap,0))) s, max(h.prod_date) last,
           string_agg(distinct h.machine, ', ') mcs, string_agg(distinct nullif(nullif(trim(h.batch),''),'0'), ', ') bts, string_agg(distinct nullif(nullif(trim(h.rm_code),''),'1'), ', ') rms, count(distinct h.prod_date) days
      from console.mmd_hist h
     where h.customer_id = cid and h.prod_date >= d0 and h.prod_date <= (now() at time zone 'Asia/Kolkata')::date and h.qty > 0 and h.part_code is not null and coalesce(h.process,'') <> '' and h.process <> 'No production'
     group by h.part_code, upper(trim(h.process))) z), '[]'::jsonb));
end $function$;
