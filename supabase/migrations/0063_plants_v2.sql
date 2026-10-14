-- =====================================================================
-- KMR platform — PLANTS v2 (needs 0061_plants.sql).
--  • The company itself is NOT a plant once it has plants: the plant list holds only the real plants.
--  • The all-plants Sales Flow summary adds up the real plants only.
--  • Tells the apps page whether the opened link is the company link (then the person chooses a plant after signing in).
-- Safe to re-run.
-- =====================================================================
drop function if exists public.kmr_plants(text);
create or replace function public.kmr_plants(p_slug text)
returns table (slug text, name text, plant_code text, is_main boolean, is_admin boolean, is_all boolean, at_parent boolean)
language plpgsql stable security definer set search_path = console, public as $$
declare em text := lower(coalesce(auth.jwt() ->> 'email', '')); cur console.customers%rowtype; par console.customers%rowtype; allp boolean;
begin
  select c.* into cur from console.customers c where c.slug = lower(p_slug);
  if cur.id is null or em = '' then return; end if;
  par := cur;
  if cur.parent_id is not null then select c.* into par from console.customers c where c.id = cur.parent_id; end if;
  if not exists (select 1 from console.customers c where c.parent_id = par.id) then return; end if;
  allp := console.is_customer_admin(par.id);
  return query
    select c.slug, c.name, coalesce(c.plant_code, ''), false, console.is_customer_admin(c.id), allp, (cur.id = par.id)
      from console.customers c
     where c.parent_id = par.id
       and (allp
            or exists (select 1 from console.customer_members m where m.customer_id = c.id and m.email = em)
            or lower(coalesce(c.contact_email, '')) = em)
     order by c.plant_code;
end $$;
revoke all on function public.kmr_plants(text) from public, anon;
grant execute on function public.kmr_plants(text) to authenticated;

create or replace function public.kmr_sf_month_all(p_slug text, p_month date) returns jsonb
language plpgsql stable security definer set search_path = console, public as $$
declare c console.customers%rowtype; m date := date_trunc('month', p_month)::date; ids uuid[];
begin
  select * into c from console.customers where slug = lower(p_slug);
  if c.id is null then raise exception 'Unknown company link.'; end if;
  if c.parent_id is not null then select * into c from console.customers where id = c.parent_id; end if;
  select coalesce(array_agg(x.id), '{}') into ids
    from console.customers x
   where (x.parent_id = c.id or (x.id = c.id and not exists (select 1 from console.customers y where y.parent_id = c.id)))
     and console.sf_role(x.id) is not null;
  if coalesce(array_length(ids, 1), 0) = 0 then raise exception 'You have no access to Sales Flow in any plant.'; end if;
  return jsonb_build_object(
    'company', c.name,
    'plants', (select jsonb_agg(jsonb_build_object('slug', x.slug, 'code', coalesce(x.plant_code, 'Main'), 'name', x.name) order by x.plant_code)
                 from console.customers x where x.id = any(ids)),
    'lines', coalesce((select jsonb_agg(to_jsonb(l) - 'customer_id' || jsonb_build_object('plant_code', coalesce(x.plant_code, 'Main'), 'plant_slug', x.slug) order by x.plant_code, l.buyer_name, l.part_code)
                         from console.sf_lines l join console.customers x on x.id = l.customer_id where l.customer_id = any(ids) and l.month = m), '[]'),
    'despatch', coalesce((select jsonb_agg(jsonb_build_object('line_id', d.line_id, 'day', d.day, 'qty', d.qty, 'note', d.note))
                            from console.sf_despatch d join console.sf_lines l on l.id = d.line_id
                           where l.customer_id = any(ids) and l.month = m), '[]'));
end $$;
revoke all on function public.kmr_sf_month_all(text, date) from public, anon;
grant execute on function public.kmr_sf_month_all(text, date) to authenticated;
