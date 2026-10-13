-- =====================================================================
-- KMR platform — MOVE EXISTING DATA INTO A PLANT (needs 0061_plants.sql).
-- Console › customer › Plants › "Move existing data". Moves (not copies) the main company's Sales Flow, Calibration Hub and
-- Operations Master records into one plant; for Capacity the saved plan is copied to the plant's own Capacity workspace.
-- Refuses when the plant already holds data in that app, so nothing is overwritten. Safe to re-run.
-- =====================================================================
create or replace function console.move_to_plant(p_from uuid, p_to uuid, p_tools text[]) returns jsonb
language plpgsql security definer set search_path = console, public as $$
declare t text; tbl text; n int; res jsonb := '{}'; cnt int; src uuid; dst uuid; k text;
  groups jsonb := '{"sales":["sf_lines","sf_despatch","sf_actions"],"calib":["cal_instruments","cal_records","cal_events","cal_oot","cal_msa"],"ops":["ops_records"]}';
begin
  if not console.is_manager() then raise exception 'Only KMR managers can move data.'; end if;
  if not exists (select 1 from console.customers where id = p_to and parent_id = p_from) then raise exception 'The target must be a plant of this company.'; end if;
  foreach t in array p_tools loop
    if t = 'capacity' then
      select product_ref into src from console.licences where customer_id = p_from and product_code = 'capacity';
      select product_ref into dst from console.licences where customer_id = p_to and product_code = 'capacity';
      if dst is null then raise exception 'Switch on Capacity for the plant first (open the plant › Products).'; end if;
      if src is null then res := res || jsonb_build_object('capacity', 'nothing to copy'); continue; end if;
      if exists (select 1 from public.cp_plans where org_id = dst) then raise exception 'The plant already has a Capacity plan, so it was not overwritten.'; end if;
      insert into public.cp_plans (org_id, data, updated_by) select dst, data, 'Moved from main company' from public.cp_plans where org_id = src;
      get diagnostics n = row_count;
      res := res || jsonb_build_object('capacity', n || ' plan copied');
    elsif groups ? t then
      if t <> 'ops' and not exists (select 1 from console.licences where customer_id = p_to and product_code = t and product_ref is not null) then
        raise exception 'Switch on this app for the plant first (open the plant › Products).';
      end if;
      cnt := 0;
      for tbl in select jsonb_array_elements_text(groups -> t) loop
        if to_regclass('console.' || tbl) is null then continue; end if;
        if tbl in ('sf_lines','cal_instruments','ops_records') then
          execute format('select count(*) from console.%I where customer_id = $1', tbl) into n using p_to;
          if n > 0 then raise exception 'The plant already has data in this app, so nothing was moved.'; end if;
        end if;
        execute format('update console.%I set customer_id = $1 where customer_id = $2', tbl) using p_to, p_from;
        get diagnostics n = row_count; cnt := cnt + n;
      end loop;
      res := res || jsonb_build_object(t, cnt || ' records moved');
    else
      raise exception 'Unknown app %.', t;
    end if;
  end loop;
  return res;
end $$;
revoke all on function console.move_to_plant(uuid, uuid, text[]) from public, anon;
grant execute on function console.move_to_plant(uuid, uuid, text[]) to authenticated;
