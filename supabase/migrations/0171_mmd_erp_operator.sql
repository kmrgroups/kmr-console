-- MMD: ERP production rows now carry the operator, so operator efficiency can be shown. Same rules as before otherwise.
create or replace function public.kmr_mmd_erp(p_slug text, p_days integer default 30)
 returns jsonb language plpgsql stable security definer set search_path to 'console','public' as $function$
declare cid uuid := console.qp_cid(p_slug,'mmd'); d0 date := (now() at time zone 'Asia/Kolkata')::date - (greatest(1,least(coalesce(p_days,30),400)) - 1);
begin
  return (with h as (
      select x.prod_date, x.machine, x.operator, x.part_code, x.process, x.hours, x.qty, x.scrap, x.cycle_time, x.idle_hrs, x.reasons
        from console.mmd_hist x
       where x.customer_id = cid and x.prod_date >= d0 and x.machine is not null
         and not exists (select 1 from console.mmd_entries e where e.customer_id = cid and e.machine = x.machine and (e.entry_at at time zone 'Asia/Kolkata')::date = x.prod_date and e.status = 'ok')),
    prod as (select prod_date, machine, coalesce(nullif(upper(trim(operator)),''),'NOT GIVEN') op, round(sum(qty),0) q, round(sum(coalesce(scrap,0)),0) s, round(sum(qty*coalesce(cycle_time,0)/3600.0),3) sh, round(sum(hours),2) oh from h where coalesce(process,'') <> 'No production' and qty > 0 group by 1,2,3),
    idle as (select prod_date, machine, coalesce(nullif(upper(trim(reasons)),''),'NOT GIVEN') r, round(sum(idle_hrs),2) hh from h where idle_hrs > 0 group by 1,2,3)
  select jsonb_build_object(
    'rows', (select count(*) from h), 'last', (select max(prod_date) from h),
    'prod', coalesce((select jsonb_agg(jsonb_build_array(prod_date, machine, q, s, sh, oh, op) order by prod_date, machine) from prod), '[]'),
    'idle', coalesce((select jsonb_agg(jsonb_build_array(prod_date, machine, r, hh) order by prod_date, machine) from idle), '[]'),
    'parts', coalesce((select jsonb_agg(jsonb_build_object('part', part_code, 'qty', qty) order by qty desc) from (select part_code, sum(qty) qty from h where coalesce(process,'')<>'No production' group by 1 order by 2 desc limit 15) z), '[]')));
end $function$;
