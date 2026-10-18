-- 0078: the "Sample data" button inside every app, for the KMR developer login only.
-- kmr_is_staff()   -> true only for a KMR staff login (Console staff list); the apps show the button only then.
-- kmr_app_sample() -> loads or removes the sample data of ONE app for ONE company. Refuses everyone who is not KMR staff.
-- Run after 0077. Safe to run again.
create or replace function public.kmr_is_staff() returns boolean
language sql stable security definer set search_path = console, public as $$ select coalesce(console.is_staff(), false) $$;
revoke all on function public.kmr_is_staff() from public, anon;
grant execute on function public.kmr_is_staff() to authenticated;

create or replace function public.kmr_app_sample(p_slug text, p_app text, p_action text) returns jsonb
language plpgsql security definer set search_path = console, public as $$
declare cid uuid; r uuid; out jsonb := '{}'; n int;
begin
  if not coalesce(console.is_staff(), false) then raise exception 'Only the KMR developer login can load or remove sample data here.'; end if;
  if p_action not in ('load', 'flush') then raise exception 'Unknown action.'; end if;
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null then raise exception 'Unknown company link.'; end if;
  if p_app = 'hrm' then p_app := 'hrms'; end if;
  if not console.has_app(cid, p_app) then raise exception 'This company does not have that app.'; end if;
  if p_app in ('sales', 'calib') and p_action = 'load' then
    perform public.kmr_ops_sample_load(p_slug);                 -- built from the Operations Master sample parts, contracts and gauges
  end if;
  if p_app = 'balloon' then out := jsonb_build_object('balloon', public.kmr_ops_sample_drawing(p_slug, p_action));
  elsif p_app in ('pd', 'capacity') then
    if p_action = 'load' then out := jsonb_build_object('operations_master', (public.kmr_ops_sample_load(p_slug) ->> 'added')::int);
    else out := jsonb_build_object('operations_master', public.kmr_ops_sample_flush(p_slug)); end if;
  elsif p_app = 'sales' then out := jsonb_build_object('sales', console.sf_sample(cid, p_action));
  elsif p_app = 'calib' then out := jsonb_build_object('calib', console.cal_sample(cid, p_action));
  elsif p_app = 'apqp' then out := jsonb_build_object('apqp', console.apqp_sample(cid, p_action));
  elsif p_app = 'ppap' then out := jsonb_build_object('ppap', console.ppap_sample(cid, p_action));
  elsif p_app = 'rmp' then out := jsonb_build_object('rmp', console.rmp_sample(cid, p_action));
  elsif p_app = 'mmd' then out := jsonb_build_object('mmd', console.mmd_sample(cid, p_action));
  elsif p_app = 'mnt' then out := jsonb_build_object('mnt', console.mnt_sample(cid, p_action));
  elsif p_app = 'mom' then out := jsonb_build_object('mom', console.mom_sample(cid, p_action));
  elsif p_app = 'cad' then out := jsonb_build_object('cad', console.cad_sample(cid, p_action));
  elsif p_app = 'hrms' then out := jsonb_build_object('hrms', console.hrms_sample(cid, p_action));
  elsif p_app = 'tsk' then out := jsonb_build_object('tsk', console.tsk_sample(cid, p_action));
  elsif p_app = 'msa' then out := jsonb_build_object('msa', console.msa_sample(cid, p_action));
  elsif p_app = 'spc' then out := jsonb_build_object('spc', console.spc_sample(cid, p_action));
  else raise exception 'No sample data is defined for this app.'; end if;
  return out;
end $$;
revoke all on function public.kmr_app_sample(text, text, text) from public, anon;
grant execute on function public.kmr_app_sample(text, text, text) to authenticated;
