-- Sales Flow 0035 — finds more prices in the Operations Master. Needs 0033. Safe to re-run.
-- Price for a part = the customer's rate contract for it (item = part number OR part name, spelling/spaces ignored):
--   1. the contract of that customer that is valid today, 2. else any customer contract valid today,
--   3. else the latest contract even if it has expired (marked "expired" in the picker), 4. else a price held on the part itself
--   (price / rate / selling_price / sale_price / unit_price). When nothing is found the price is 0 and can be typed in the plan.
create or replace function public.kmr_sf_parts(p_slug text) returns jsonb
language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid; today date := (now() at time zone 'Asia/Kolkata')::date;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or console.sf_role(cid) is null then raise exception 'You have no access to Sales Flow.'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'part_code', p.code, 'part_name', p.name, 'drawing_no', p.data ->> 'drawing_no',
             'buyer_code', coalesce(cu.code, p.data ->> 'customer', ''), 'buyer_name', coalesce(cu.name, p.data ->> 'customer', ''),
             'price', coalesce(rc.rate, pp.rate, 0),
             'currency', coalesce(rc.currency, 'INR'), 'uom', coalesce(rc.uom, 'pcs'),
             'price_source', case when rc.rate is not null then 'rate contract ' || rc.code || case when rc.valid then '' else ' (expired)' end
                                  when pp.rate is not null then 'part master' else null end)
           order by coalesce(cu.name, p.data ->> 'customer', ''), p.code)
      from console.ops_records p
      left join lateral (
        select c.code, c.name from console.ops_records c
         where c.customer_id = p.customer_id and c.kind = 'customers'
           and (c.code = p.data ->> 'customer' or lower(trim(c.name)) = lower(trim(coalesce(p.data ->> 'customer', '')))) limit 1) cu on true
      left join lateral (
        select r.code, rr.rate, coalesce(nullif(r.data ->> 'currency', ''), 'INR') currency, coalesce(nullif(r.data ->> 'uom', ''), 'pcs') uom,
               ((coalesce(r.data ->> 'valid_from', '') !~ '^\d{4}-\d{2}-\d{2}$' or (r.data ->> 'valid_from')::date <= today)
                and (coalesce(r.data ->> 'valid_to', '') !~ '^\d{4}-\d{2}-\d{2}$' or (r.data ->> 'valid_to')::date >= today)) as valid
          from console.ops_records r
          cross join lateral (select substring(replace(coalesce(r.data ->> 'rate', ''), ',', '') from '[0-9]+(\.[0-9]+)?')::numeric as rate) rr
         where r.customer_id = p.customer_id and r.kind = 'rate_contracts' and r.active and rr.rate is not null
           and coalesce(r.data ->> 'party_type', 'Customer') ilike 'customer%'
           and lower(trim(coalesce(r.data ->> 'item', ''))) in (lower(trim(p.code)), lower(trim(p.name)))
         order by (lower(trim(r.name)) = lower(trim(coalesce(cu.name, p.data ->> 'customer', '')))) desc,
                  ((coalesce(r.data ->> 'valid_from', '') !~ '^\d{4}-\d{2}-\d{2}$' or (r.data ->> 'valid_from')::date <= today)
                   and (coalesce(r.data ->> 'valid_to', '') !~ '^\d{4}-\d{2}-\d{2}$' or (r.data ->> 'valid_to')::date >= today)) desc,
                  coalesce(nullif(r.data ->> 'valid_from', ''), '0000') desc limit 1) rc on true
      left join lateral (
        select substring(replace(coalesce(nullif(p.data ->> 'price', ''), nullif(p.data ->> 'rate', ''), nullif(p.data ->> 'selling_price', ''),
                                          nullif(p.data ->> 'sale_price', ''), nullif(p.data ->> 'unit_price', ''), ''), ',', '') from '[0-9]+(\.[0-9]+)?')::numeric as rate) pp on true
     where p.customer_id = cid and p.kind = 'parts' and p.active), '[]');
end $$;
grant execute on function public.kmr_sf_parts(text) to authenticated;
