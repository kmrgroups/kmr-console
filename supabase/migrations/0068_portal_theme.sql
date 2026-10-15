-- Home-screen theme per customer (KMR Apps portal).
-- Each customer (or plant) can have its own look for the home screen. Nothing changes for a customer until a theme is chosen
-- in the Console (Customer › Portal link › Home screen theme). A plant without its own choice follows its company.
alter table console.customers add column if not exists portal_theme text;

do $c$ begin
  if not exists (select 1 from pg_constraint where conname = 'customers_portal_theme_chk') then
    alter table console.customers add constraint customers_portal_theme_chk
      check (portal_theme is null or portal_theme in ('a','b','c','d','e','f','g','h','i','j','k','l','m','n','o','p','q','r'));
  end if;
end $c$;

-- The portal asks for the theme by link name (works before sign-in, reveals nothing else)
create or replace function public.kmr_portal_theme(p_slug text)
returns text
language sql stable security definer set search_path = console, public as $$
  select coalesce(c.portal_theme, p.portal_theme)
  from console.customers c left join console.customers p on p.id = c.parent_id
  where c.slug = lower(p_slug) and c.status <> 'inactive'
$$;
revoke all on function public.kmr_portal_theme(text) from public;
grant execute on function public.kmr_portal_theme(text) to anon, authenticated;
