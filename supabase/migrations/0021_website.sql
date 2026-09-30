-- =====================================================================
-- KMR Console — manages the website (replaces the website's own /admin). Needs 0020. Safe to re-run.
-- Publishing to the website needs the website's supabase/add-multi-business.sql (run it before or after this file).
--  • Enquiries: the "Pilot requests" inbox now takes every enquiry from the website — software pilots, training,
--    import & export, trading, distribution and shop questions — with the business and product it is about.
--  • Software catalogue for the website: the Console's products with their INR prices (public, read-only).
--  • Publish from Operations Master: chosen parts of a company's Operations Master become website products
--    (hidden until KMR checks price, stock and image). Re-publishing refreshes the name and details only.
-- =====================================================================
do $$ begin
  if to_regprocedure('console.seller_snapshot()') is null then raise exception 'Run 0020_seller_identity.sql first.'; end if;
end $$;

-- ---------- enquiries ----------
alter table console.leads drop constraint if exists leads_company_check;
alter table console.leads alter column company drop not null;
alter table console.leads
  add column if not exists business     text not null default 'software',
  add column if not exists product_name text,
  add column if not exists quantity     text,
  add column if not exists notes        text;
alter table console.leads drop constraint if exists leads_business_check;
alter table console.leads add constraint leads_business_check check (business in ('software','shop','training','import_export','trading','distribution','general'));
alter table console.leads drop constraint if exists leads_status_check;
alter table console.leads add constraint leads_status_check check (status in ('new','contacted','quoted','converted','dropped'));

-- ---------- software catalogue (website Software page) ----------
create or replace function public.kmr_software_catalog() returns jsonb
language sql stable security definer set search_path = console, public as $$
  select coalesce(jsonb_agg(jsonb_build_object('code', p.code, 'name', p.name, 'description', p.description, 'app_path', p.app_path,
           'seat_label', p.seat_label, 'version', p.current_version,
           'prices', coalesce((select jsonb_agg(jsonb_build_object('period', x.period, 'amount', x.unit_amount, 'min', x.min_seats) order by x.period)
                                from console.prices x where x.product_code = p.code and x.active and x.currency = 'INR'), '[]'))
         order by p.sort_order), '[]')
    from console.products p where p.active
$$;
grant execute on function public.kmr_software_catalog() to anon, authenticated;

-- ---------- publish Operations Master parts to the website ----------
create or replace function console.publish_ops_products(p_customer uuid, p_codes text[], p_business text default 'shop') returns jsonb
language plpgsql security definer set search_path = console, public as $$
declare r console.ops_records; added int := 0; refreshed int := 0; mat text; price numeric; descr text;
begin
  perform console.require_manager();
  if p_business not in ('shop','training','import_export','trading','distribution') then raise exception 'Choose where the products go.'; end if;
  if coalesce(array_length(p_codes, 1), 0) = 0 then raise exception 'Tick at least one part.'; end if;
  for r in select * from console.ops_records where customer_id = p_customer and kind = 'parts' and code = any(p_codes) loop
    select coalesce(m.name, r.data ->> 'material') into mat from (select 1) one
      left join console.ops_records m on m.customer_id = p_customer and m.kind = 'raw_materials' and m.code = r.data ->> 'material';
    select max(nullif(c.data ->> 'rate', '')::numeric) into price from console.ops_records c
     where c.customer_id = p_customer and c.kind = 'rate_contracts' and c.active and c.data ->> 'party_type' = 'Customer'
       and c.data ->> 'item' = r.code and coalesce(c.data ->> 'currency', 'INR') = 'INR';
    descr := concat_ws(' · ', 'Part no. ' || r.code,
               case when r.data ->> 'drawing_no' is not null then 'Drawing ' || (r.data ->> 'drawing_no') || coalesce(' rev ' || (r.data ->> 'revision'), '') end,
               case when mat is not null then 'Material ' || mat end,
               case when r.data ->> 'weight_kg' is not null then (r.data ->> 'weight_kg') || ' kg' end);
    if exists (select 1 from public.products where ops_customer_id = p_customer and ops_code = r.code) then
      update public.products set name = r.name, description = descr, updated_at = now() where ops_customer_id = p_customer and ops_code = r.code;
      refreshed := refreshed + 1;
    else
      insert into public.products (name, sku, category, description, price, stock_quantity, is_active, business, kind, unit, ops_customer_id, ops_code, enquiry_only)
      values (coalesce(nullif(r.name, ''), r.code), r.code || case when exists (select 1 from public.products where sku = r.code) then '-' || left(p_customer::text, 4) else '' end,
              coalesce(r.data ->> 'status', 'Parts'), descr, coalesce(price, 0), 0, false, p_business, 'goods', 'nos', p_customer, r.code,
              p_business not in ('shop','training'));
      added := added + 1;
    end if;
  end loop;
  return jsonb_build_object('added', added, 'refreshed', refreshed);
end $$;
revoke all on function console.publish_ops_products(uuid, text[], text) from public, anon;
grant execute on function console.publish_ops_products(uuid, text[], text) to authenticated;

-- ---------- private storage for compliance documents (Console › Website › Compliance) ----------
insert into storage.buckets (id, name, public, file_size_limit) values ('kmr-records', 'kmr-records', false, 10485760) on conflict (id) do nothing;
