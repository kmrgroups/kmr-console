-- =====================================================================
-- KMR platform — Balloon Inspector reads the company's gauges from the Operations Master (Gauges) so each balloon can use one or more of them.
-- Needs 0015 (Operations Master), 0051 (kmr_access). Safe to re-run.
-- =====================================================================
create or replace function public.kmr_balloon_gauges(p_org uuid) returns jsonb
language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid;
begin
  if not exists (select 1 from public.kmr_access('balloon') a where a.org_id = p_org) then raise exception 'No access to this workspace.'; end if;
  select customer_id into cid from console.licences where product_code = 'balloon' and product_ref = p_org;
  if cid is null then return null; end if;                       -- not linked to a customer: the plain instrument column stays
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id', r.code, 'name', r.name, 'type', coalesce(r.data ->> 'type', ''), 'range', coalesce(r.data ->> 'range', ''),
      'lc', coalesce(r.data ->> 'least_count', ''), 'calDue', coalesce(r.data ->> 'next_due', ''), 'location', coalesce(r.data ->> 'location', '')) order by r.code)
    from console.ops_records r where r.customer_id = cid and r.kind = 'gauges' and r.active and coalesce(r.data ->> 'status', '') not in ('Scrapped', 'Lost')), '[]'::jsonb);
end $$;
revoke all on function public.kmr_balloon_gauges(uuid) from public, anon;
grant execute on function public.kmr_balloon_gauges(uuid) to authenticated;
