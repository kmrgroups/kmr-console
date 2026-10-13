-- =====================================================================
-- KMR platform — PLANTS (Phase 1).
-- A customer can have several plants (Plant-1, Plant-2 …). Each plant is a child customer of the main
-- company, so every app that already separates data by customer is separated by plant automatically.
--  • Plants are created and controlled in Console (customer page › Plants).
--  • Who can open which plant = that person's entry in the plant's user list (Console › customer › Plants).
--  • Company administrators of the main company are administrators of every plant.
-- Additive and safe to re-run. Customers without plants are not affected at all.
-- TAKE A DATABASE BACKUP BEFORE RUNNING.
-- =====================================================================
alter table console.customers add column if not exists parent_id  uuid references console.customers(id) on delete restrict;
alter table console.customers add column if not exists plant_code text;

do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'customers_plant_not_self') then
    alter table console.customers add constraint customers_plant_not_self check (parent_id is null or parent_id <> id);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'customers_plant_code_format') then
    alter table console.customers add constraint customers_plant_code_format check (plant_code is null or length(plant_code) between 1 and 20);
  end if;
end $$;
create unique index if not exists customers_plant_code_uq on console.customers (parent_id, lower(plant_code)) where parent_id is not null;
create index if not exists customers_parent_idx on console.customers (parent_id) where parent_id is not null;

-- A plant cannot itself have plants (one level only)
create or replace function console.customers_plant_check() returns trigger
language plpgsql set search_path = console, public as $$
begin
  if new.parent_id is not null then
    if exists (select 1 from console.customers p where p.id = new.parent_id and p.parent_id is not null) then
      raise exception 'A plant cannot have plants of its own.';
    end if;
    if exists (select 1 from console.customers c where c.parent_id = new.id) then
      raise exception 'This customer already has plants, so it cannot become a plant.';
    end if;
  end if;
  return new;
end $$;
drop trigger if exists customers_plant_check on console.customers;
create trigger customers_plant_check before insert or update of parent_id on console.customers
  for each row execute function console.customers_plant_check();

-- Create a plant under a customer (Console, KMR managers only). Copies the company details and administrators.
create or replace function console.create_plant(p_parent uuid, p_name text, p_code text, p_city text default null) returns uuid
language plpgsql security definer set search_path = console, public as $$
declare par console.customers%rowtype; pid uuid;
begin
  if not console.is_manager() then raise exception 'Only KMR managers can add plants.'; end if;
  select * into par from console.customers where id = p_parent;
  if par.id is null then raise exception 'Customer not found.'; end if;
  if par.parent_id is not null then raise exception 'Add plants to the main company, not to another plant.'; end if;
  if coalesce(trim(p_name), '') = '' or coalesce(trim(p_code), '') = '' then raise exception 'Plant name and code are required.'; end if;
  insert into console.customers (name, legal_name, country, currency, tax_id, address, city, state, postal_code, time_zone,
                                 contact_name, contact_email, contact_phone, status, source, logo_url, parent_id, plant_code, created_by)
  values (left(par.name || ' – ' || trim(p_name), 120), par.legal_name, par.country, par.currency, par.tax_id, par.address,
          coalesce(nullif(trim(p_city), ''), par.city), par.state, par.postal_code, par.time_zone,
          par.contact_name, par.contact_email, par.contact_phone, par.status, 'plant', par.logo_url, par.id, trim(p_code), auth.uid())
  returning id into pid;
  -- the main company's administrators administer every plant
  insert into console.customer_members (customer_id, email, full_name, is_admin, created_by)
  select pid, m.email, m.full_name, true, 'Main company administrator'
    from console.customer_members m where m.customer_id = par.id and m.is_admin
  on conflict (customer_id, email) do nothing;
  return pid;
end $$;
revoke all on function console.create_plant(uuid, text, text, text) from public, anon;
grant execute on function console.create_plant(uuid, text, text, text) to authenticated;

-- A new administrator of the main company becomes an administrator of every plant
create or replace function console.plant_admin_sync() returns trigger
language plpgsql security definer set search_path = console, public as $$
begin
  if new.is_admin and exists (select 1 from console.customers where parent_id = new.customer_id) then
    insert into console.customer_members (customer_id, email, full_name, is_admin, created_by)
    select c.id, new.email, new.full_name, true, 'Main company administrator'
      from console.customers c where c.parent_id = new.customer_id
    on conflict (customer_id, email) do update set is_admin = true;
  end if;
  return new;
end $$;
drop trigger if exists customer_members_plant_admin on console.customer_members;
create trigger customer_members_plant_admin after insert or update of is_admin on console.customer_members
  for each row execute function console.plant_admin_sync();

-- Plants the signed-in person may open from a company link (empty when the company has no plants).
-- The main company itself is listed first as the "main" entry when the person has access to it.
create or replace function public.kmr_plants(p_slug text)
returns table (slug text, name text, plant_code text, is_main boolean, is_admin boolean, is_all boolean)
language plpgsql stable security definer set search_path = console, public as $$
declare em text := lower(coalesce(auth.jwt() ->> 'email', '')); par console.customers%rowtype; allp boolean;
begin
  select c.* into par from console.customers c where c.slug = lower(p_slug);
  if par.id is null or em = '' then return; end if;
  if par.parent_id is not null then select c.* into par from console.customers c where c.id = par.parent_id; end if;
  if not exists (select 1 from console.customers c where c.parent_id = par.id) then return; end if;
  allp := console.is_customer_admin(par.id);
  return query
    select c.slug, c.name, coalesce(c.plant_code, 'Main'), (c.id = par.id), console.is_customer_admin(c.id), allp
      from console.customers c
     where (c.id = par.id or c.parent_id = par.id)
       and (allp
            or exists (select 1 from console.customer_members m where m.customer_id = c.id and m.email = em)
            or lower(coalesce(c.contact_email, '')) = em and c.id <> par.id)
     order by (c.id = par.id) desc, c.plant_code;
end $$;
revoke all on function public.kmr_plants(text) from public, anon;
grant execute on function public.kmr_plants(text) to authenticated;

-- Console: plants of a customer with their tools and number of people
create or replace function console.plant_overview(p_parent uuid)
returns table (id uuid, slug text, name text, plant_code text, city text, status text, tools text[], people int)
language sql stable security definer set search_path = console, public as $$
  select c.id, c.slug, c.name, c.plant_code, c.city, c.status,
         coalesce((select array_agg(l.product_code order by l.product_code) from console.licences l where l.customer_id = c.id and l.product_ref is not null), '{}'),
         (select count(*)::int from console.customer_members m where m.customer_id = c.id)
    from console.customers c
   where c.parent_id = p_parent and console.is_staff()
   order by c.plant_code
$$;
revoke all on function console.plant_overview(uuid) from public, anon;
grant execute on function console.plant_overview(uuid) to authenticated;

-- Sales Flow: one month across every plant the person may see (read-only summary for the all-plants dashboard).
-- Each line and despatch row is tagged with its plant.
create or replace function public.kmr_sf_month_all(p_slug text, p_month date) returns jsonb
language plpgsql stable security definer set search_path = console, public as $$
declare c console.customers%rowtype; m date := date_trunc('month', p_month)::date; ids uuid[];
begin
  select * into c from console.customers where slug = lower(p_slug);
  if c.id is null then raise exception 'Unknown company link.'; end if;
  if c.parent_id is not null then select * into c from console.customers where id = c.parent_id; end if;
  select coalesce(array_agg(x.id), '{}') into ids
    from console.customers x
   where (x.id = c.id or x.parent_id = c.id) and console.sf_role(x.id) is not null;
  if coalesce(array_length(ids, 1), 0) = 0 then raise exception 'You have no access to Sales Flow in any plant.'; end if;
  return jsonb_build_object(
    'company', c.name,
    'plants', (select jsonb_agg(jsonb_build_object('slug', x.slug, 'code', coalesce(x.plant_code, 'Main'), 'name', x.name) order by (x.id = c.id) desc, x.plant_code)
                 from console.customers x where x.id = any(ids)),
    'lines', coalesce((select jsonb_agg(to_jsonb(l) - 'customer_id' || jsonb_build_object('plant_code', coalesce(x.plant_code, 'Main'), 'plant_slug', x.slug) order by x.plant_code, l.buyer_name, l.part_code)
                         from console.sf_lines l join console.customers x on x.id = l.customer_id where l.customer_id = any(ids) and l.month = m), '[]'),
    'despatch', coalesce((select jsonb_agg(jsonb_build_object('line_id', d.line_id, 'day', d.day, 'qty', d.qty, 'note', d.note))
                            from console.sf_despatch d join console.sf_lines l on l.id = d.line_id
                           where l.customer_id = any(ids) and l.month = m), '[]'));
end $$;
revoke all on function public.kmr_sf_month_all(text, date) from public, anon;
grant execute on function public.kmr_sf_month_all(text, date) to authenticated;
