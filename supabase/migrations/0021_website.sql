-- =====================================================================
-- KMR Console — manages the website (replaces the website's own /admin). Needs 0020. Safe to re-run.
--  • Enquiries: the "Pilot requests" inbox now takes every enquiry from the website — software pilots, training,
--    import & export, trading, distribution and shop questions — with the business and product it is about.
--  • Software catalogue for the website: the Console's products with their INR prices (public, read-only).
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

-- Customer Operations Master data is the customer's confidential data: it is never copied to the website.
drop function if exists console.publish_ops_products(uuid, text[], text);

-- ---------- private storage for compliance documents (Console › Website › Compliance) ----------
insert into storage.buckets (id, name, public, file_size_limit) values ('kmr-records', 'kmr-records', false, 10485760) on conflict (id) do nothing;
