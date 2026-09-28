-- =====================================================================
-- KMR platform — Customer Administration (Administration Master).
--  • ONE user list per customer (console.customer_members) with a role per tool; saving a person gives or
--    removes their access inside every tool automatically. Tools no longer manage users themselves.
--  • Company name, details and logo live on the customer (Console or the customer's Administration page) and
--    are pushed to every tool of that customer. Tools no longer keep their own company settings.
--  • HRM employees' own self-service logins stay with HR onboarding; HR staff roles are managed here.
-- Safe to re-run.
-- =====================================================================
create table if not exists console.customer_members (
  customer_id  uuid not null references console.customers(id) on delete cascade,
  email        text not null check (email = lower(email)),
  full_name    text,
  is_admin     boolean not null default false,          -- company administrator: Administration page, users, company details
  roles        jsonb not null default '{}',              -- {"hrm":"hr_manager","balloon":"editor","pd":"viewer","capacity":"admin"}
  login_owned  boolean not null default false,          -- login created here (admins may reset its password)
  created_by   text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  primary key (customer_id, email)
);
alter table console.customer_members enable row level security;
drop policy if exists customer_members_staff on console.customer_members;
create policy customer_members_staff on console.customer_members for all to authenticated using (console.is_staff()) with check (console.is_staff());

-- Is the signed-in person an administrator of this customer? (the recorded contact person always is)
create or replace function console.is_customer_admin(p_customer uuid) returns boolean
language sql stable security definer set search_path = console, public as $$
  select exists (select 1 from console.customer_members m where m.customer_id = p_customer and m.is_admin and m.email = lower(coalesce(auth.jwt() ->> 'email', '')))
      or exists (select 1 from console.customers c where c.id = p_customer and lower(coalesce(c.contact_email, '')) = lower(coalesce(auth.jwt() ->> 'email', '')) and coalesce(c.contact_email, '') <> '')
      or console.is_staff()
$$;
grant execute on function console.is_customer_admin(uuid) to authenticated;

-- A KMR login (created when missing; returns the user id and whether it was created now)
create or replace function console.ensure_login(p_email text, p_password text, p_name text, out uid uuid, out created boolean)
language plpgsql security definer set search_path = public, auth, extensions as $$
begin
  select id into uid from auth.users where lower(email) = lower(p_email) limit 1;
  created := false;
  if uid is not null then return; end if;
  if length(coalesce(p_password, '')) < 8 then raise exception 'A new login needs a password of at least 8 characters.'; end if;
  uid := gen_random_uuid();
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
                          created_at, updated_at, confirmation_token, recovery_token, email_change_token_new, email_change)
  values ('00000000-0000-0000-0000-000000000000', uid, 'authenticated', 'authenticated', lower(p_email), crypt(p_password, gen_salt('bf')), now(),
          '{"provider":"email","providers":["email"]}', jsonb_build_object('name', coalesce(p_name, '')), now(), now(), '', '', '', '');
  insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
  values (gen_random_uuid(), uid, uid::text, jsonb_build_object('sub', uid::text, 'email', lower(p_email), 'email_verified', true), 'email', now(), now(), now());
  created := true;
end $$;
revoke all on function console.ensure_login(text, text, text) from public, anon, authenticated;

-- Give / remove one person's access inside every tool of the customer, from their roles
create or replace function console.sync_member(p_customer uuid, p_email text) returns void
language plpgsql security definer set search_path = console, public, auth as $$
declare m console.customer_members%rowtype; l record; r text; uid uuid;
begin
  select * into m from console.customer_members where customer_id = p_customer and email = lower(p_email);
  select id into uid from auth.users where lower(email) = lower(p_email) limit 1;
  for l in select product_code, product_ref from console.licences where customer_id = p_customer and product_ref is not null loop
    r := case when m.email is null then null else nullif(m.roles ->> l.product_code, '') end;
    if l.product_code = 'balloon' then
      if r is null then delete from public.bi_members where org_id = l.product_ref and lower(email) = lower(p_email);
      else insert into public.bi_members (org_id, email, role) values (l.product_ref, lower(p_email), r)
           on conflict (org_id, email) do update set role = excluded.role; end if;
    elsif l.product_code = 'pd' then
      if r is null then delete from public.pd_members where org_id = l.product_ref and lower(email) = lower(p_email);
      else insert into public.pd_members (org_id, email, role) values (l.product_ref, lower(p_email), r)
           on conflict (org_id, email) do update set role = excluded.role; end if;
    elsif l.product_code = 'capacity' then
      if r is null then delete from public.cp_members where org_id = l.product_ref and email = lower(p_email);
      else insert into public.cp_members (org_id, email, role, display_name, created_by) values (l.product_ref, lower(p_email), r, m.full_name, 'KMR Apps')
           on conflict (org_id, email) do update set role = excluded.role, display_name = coalesce(excluded.display_name, cp_members.display_name); end if;
    elsif l.product_code = 'hrm' and uid is not null then
      if r is null then
        update hrm.app_users set active = false where id = uid and tenant_id = l.product_ref and role <> 'employee';
      else
        if exists (select 1 from hrm.app_users where id = uid and tenant_id <> l.product_ref) then
          raise exception '% already uses the HRM of another company, so it cannot get HRM access here.', p_email;
        end if;
        insert into hrm.app_users (id, tenant_id, role, full_name, email, must_change_password, active)
        values (uid, l.product_ref, r, coalesce(m.full_name, split_part(p_email, '@', 1)), lower(p_email), false, true)
        on conflict (id) do update set role = excluded.role, full_name = excluded.full_name, active = true;
      end if;
    end if;
  end loop;
end $$;
revoke all on function console.sync_member(uuid, text) from public, anon, authenticated;

-- Existing access becomes the starting user list (tool members, HRM staff, the contact person)
insert into console.customer_members (customer_id, email, full_name, is_admin, roles, created_by)
select x.customer_id, x.email, max(x.name), bool_or(x.adm), jsonb_object_agg(x.product_code, x.role), 'Imported'
  from (
    select l.customer_id, lower(m.email) email, null::text name, m.role = 'admin' adm, 'balloon' product_code, m.role from console.licences l join public.bi_members m on m.org_id = l.product_ref where l.product_code = 'balloon'
    union all select l.customer_id, lower(m.email), null, m.role = 'admin', 'pd', m.role from console.licences l join public.pd_members m on m.org_id = l.product_ref where l.product_code = 'pd'
    union all select l.customer_id, m.email, m.display_name, m.role = 'admin', 'capacity', m.role from console.licences l join public.cp_members m on m.org_id = l.product_ref where l.product_code = 'capacity'
    union all select l.customer_id, lower(u.email), u.full_name, u.role = 'company_admin', 'hrm', u.role from console.licences l join hrm.app_users u on u.tenant_id = l.product_ref
      where l.product_code = 'hrm' and u.role <> 'employee' and u.active
  ) x
 group by x.customer_id, x.email
on conflict (customer_id, email) do nothing;
insert into console.customer_members (customer_id, email, full_name, is_admin, created_by)
select id, lower(contact_email), contact_name, true, 'Contact person' from console.customers where coalesce(contact_email, '') <> ''
on conflict (customer_id, email) do update set is_admin = true;

-- ---------- the customer's Administration page (company administrators) ----------
create or replace function public.kmr_admin_role(p_slug text) returns text
language sql stable security definer set search_path = console, public as $$
  select case when console.is_customer_admin(c.id) then 'admin' when exists (select 1 from public.kmr_portal(p_slug)) then 'member' end
    from console.customers c where c.slug = lower(p_slug)
$$;
grant execute on function public.kmr_admin_role(text) to authenticated;

create or replace function public.kmr_admin_company(p_slug text) returns jsonb
language plpgsql stable security definer set search_path = console, public as $$
declare c console.customers%rowtype;
begin
  select * into c from console.customers where slug = lower(p_slug);
  if c.id is null or not console.is_customer_admin(c.id) then raise exception 'Only your company''s administrators can open Administration.'; end if;
  return jsonb_build_object('id', c.id, 'name', c.name, 'legal_name', c.legal_name, 'tax_id', c.tax_id, 'address', c.address, 'city', c.city,
    'state', c.state, 'postal_code', c.postal_code, 'country', c.country, 'contact_name', c.contact_name, 'contact_email', c.contact_email,
    'contact_phone', c.contact_phone, 'logo_url', c.logo_url,
    'tools', (select coalesce(jsonb_agg(jsonb_build_object('code', p.code, 'name', p.name) order by p.sort_order), '[]')
                from console.licences l join console.products p on p.code = l.product_code where l.customer_id = c.id and l.product_ref is not null));
end $$;
grant execute on function public.kmr_admin_company(text) to authenticated;

create or replace function public.kmr_admin_save_company(p_slug text, p jsonb) returns text
language plpgsql security definer set search_path = console, public as $$
declare cid uuid;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or not console.is_customer_admin(cid) then raise exception 'Only your company''s administrators can change company details.'; end if;
  if length(trim(coalesce(p ->> 'name', ''))) < 2 then raise exception 'Company name is required.'; end if;
  update console.customers set
    name = trim(p ->> 'name'), legal_name = nullif(trim(coalesce(p ->> 'legal_name', '')), ''), tax_id = nullif(trim(coalesce(p ->> 'tax_id', '')), ''),
    address = nullif(trim(coalesce(p ->> 'address', '')), ''), city = nullif(trim(coalesce(p ->> 'city', '')), ''), state = nullif(trim(coalesce(p ->> 'state', '')), ''),
    postal_code = nullif(trim(coalesce(p ->> 'postal_code', '')), ''), contact_phone = nullif(trim(coalesce(p ->> 'contact_phone', '')), ''),
    logo_url = case when p ? 'logo_url' then nullif(p ->> 'logo_url', '') else logo_url end, updated_at = now()
   where id = cid;
  return 'ok';
end $$;
grant execute on function public.kmr_admin_save_company(text, jsonb) to authenticated;

create or replace function public.kmr_admin_users(p_slug text) returns jsonb
language plpgsql stable security definer set search_path = console, public, auth as $$
declare cid uuid;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or not console.is_customer_admin(cid) then raise exception 'Only your company''s administrators can manage users.'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('email', m.email, 'name', m.full_name, 'is_admin', m.is_admin, 'roles', m.roles,
      'login_owned', m.login_owned, 'has_login', u.id is not null, 'last_sign_in', u.last_sign_in_at) order by m.is_admin desc, m.email)
    from console.customer_members m left join auth.users u on lower(u.email) = m.email where m.customer_id = cid), '[]'::jsonb);
end $$;
grant execute on function public.kmr_admin_users(text) to authenticated;

-- Add or change a person: {email, name, is_admin, roles:{tool:role}, password (only for a brand-new login)}
create or replace function public.kmr_admin_save_user(p_slug text, p jsonb) returns jsonb
language plpgsql security definer set search_path = console, public, auth as $$
declare cid uuid; em text := lower(trim(coalesce(p ->> 'email', ''))); lg record; rl jsonb := '{}'; k text; v text; me text := lower(coalesce(auth.jwt() ->> 'email', ''));
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or not console.is_customer_admin(cid) then raise exception 'Only your company''s administrators can manage users.'; end if;
  if em !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'Enter a valid e-mail address.'; end if;
  for k, v in select * from jsonb_each_text(coalesce(p -> 'roles', '{}')) loop
    if v = '' then continue; end if;
    if k = 'hrm' and v not in ('company_admin','hr_manager','hr_executive','manager','payroll') then raise exception 'Unknown HRM role %.', v; end if;
    if k <> 'hrm' and v not in ('admin','editor','viewer') then raise exception 'Unknown role % for %.', v, k; end if;
    rl := rl || jsonb_build_object(k, v);
  end loop;
  if em = me and coalesce((p ->> 'is_admin')::boolean, false) = false and console.is_customer_admin(cid) and not console.is_staff() then
    raise exception 'You cannot remove your own administrator rights.';
  end if;
  select * into lg from console.ensure_login(em, p ->> 'password', p ->> 'name');
  insert into console.customer_members (customer_id, email, full_name, is_admin, roles, login_owned, created_by)
  values (cid, em, nullif(trim(coalesce(p ->> 'name', '')), ''), coalesce((p ->> 'is_admin')::boolean, false), rl, lg.created, me)
  on conflict (customer_id, email) do update set full_name = coalesce(excluded.full_name, customer_members.full_name), is_admin = excluded.is_admin,
    roles = excluded.roles, updated_at = now();
  perform console.sync_member(cid, em);
  return jsonb_build_object('ok', true, 'new_login', lg.created);
end $$;
grant execute on function public.kmr_admin_save_user(text, jsonb) to authenticated;

create or replace function public.kmr_admin_reset_password(p_slug text, p_email text, p_password text) returns text
language plpgsql security definer set search_path = console, public, auth, extensions as $$
declare cid uuid;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or not console.is_customer_admin(cid) then raise exception 'Only your company''s administrators can reset passwords.'; end if;
  if length(coalesce(p_password, '')) < 8 then raise exception 'The password must have at least 8 characters.'; end if;
  if not exists (select 1 from console.customer_members where customer_id = cid and email = lower(p_email) and login_owned) then
    raise exception 'This person uses their own KMR login. They can change it themselves, or ask KMR support.';
  end if;
  update auth.users set encrypted_password = crypt(p_password, gen_salt('bf')), updated_at = now() where lower(email) = lower(p_email);
  return 'ok';
end $$;
grant execute on function public.kmr_admin_reset_password(text, text, text) to authenticated;

create or replace function public.kmr_admin_remove_user(p_slug text, p_email text) returns text
language plpgsql security definer set search_path = console, public as $$
declare cid uuid;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or not console.is_customer_admin(cid) then raise exception 'Only your company''s administrators can manage users.'; end if;
  if lower(p_email) = lower(coalesce(auth.jwt() ->> 'email', '')) then raise exception 'You cannot remove yourself.'; end if;
  if exists (select 1 from console.customers where id = cid and lower(coalesce(contact_email, '')) = lower(p_email)) then
    raise exception 'This is your company''s main contact. Ask KMR to change the contact person first.';
  end if;
  delete from console.customer_members where customer_id = cid and email = lower(p_email);
  perform console.sync_member(cid, p_email);      -- removes their access in every tool (the login itself stays)
  return 'ok';
end $$;
grant execute on function public.kmr_admin_remove_user(text, text) to authenticated;

-- ---------- company name, details and logo pushed to every tool of the customer ----------
create or replace function console.push_branding() returns trigger
language plpgsql security definer set search_path = console, public as $$
declare l record;
begin
  for l in select product_code, product_ref from console.licences where customer_id = new.id and product_ref is not null loop
    if l.product_code = 'balloon' then update public.bi_orgs set name = new.name, logo = coalesce(new.logo_url, logo) where id = l.product_ref;
    elsif l.product_code = 'pd' then update public.pd_orgs set name = new.name, logo = coalesce(new.logo_url, logo),
           settings = coalesce(settings, '{}'::jsonb) || jsonb_build_object('companyName', new.name) where id = l.product_ref;
    elsif l.product_code = 'capacity' then update public.cp_orgs set name = new.name,
           settings = coalesce(settings, '{}'::jsonb) || jsonb_build_object('companyName', new.name, 'logo', coalesce(new.logo_url, '')) where id = l.product_ref;
    elsif l.product_code = 'hrm' then update hrm.tenants set name = new.name, legal_name = coalesce(new.legal_name, legal_name),
           address = coalesce(nullif(concat_ws(', ', new.address, new.city, new.state, new.postal_code), ''), address),
           phone = coalesce(new.contact_phone, phone), logo_path = coalesce(new.logo_url, logo_path) where id = l.product_ref;
    end if;
  end loop;
  return new;
end $$;
drop trigger if exists customers_push_branding on console.customers;
create trigger customers_push_branding after update of name, legal_name, logo_url, address, city, state, postal_code, contact_phone on console.customers
  for each row execute function console.push_branding();

-- Branding for tools that read it directly (the Capacity Planner): the customer's name and logo for a workspace
create or replace function public.kmr_workspace_brand(p_product text, p_org uuid) returns jsonb
language sql stable security definer set search_path = console, public as $$
  select jsonb_build_object('name', c.name, 'logo', c.logo_url) from console.licences l join console.customers c on c.id = l.customer_id
   where l.product_code = p_product and l.product_ref = p_org and console.product_ok(p_product, p_org)
$$;
grant execute on function public.kmr_workspace_brand(text, uuid) to authenticated;

-- Customer administrators may upload their company logo (kmr-public/customers/<customer id>/...)
do $$ begin
  if to_regclass('storage.objects') is not null then
    execute 'drop policy if exists kmr_customer_logo_insert on storage.objects';
    execute $p$create policy kmr_customer_logo_insert on storage.objects for insert to authenticated with check (
      bucket_id = 'kmr-public' and (storage.foldername(name))[1] = 'customers'
      and (storage.foldername(name))[2] ~ '^[0-9a-f-]{36}$' and console.is_customer_admin(((storage.foldername(name))[2])::uuid))$p$;
  end if;
end $$;

-- ---------- keep the one user list in step, however access is given (Console switch-on, first use, tools) ----------
create or replace function console.track_member() returns trigger
language plpgsql security definer set search_path = console, public as $$
declare product text; j jsonb; org uuid; em text; rl text; cid uuid; nm text;
begin
  product := case tg_table_name when 'bi_members' then 'balloon' when 'pd_members' then 'pd' when 'cp_members' then 'capacity' else 'hrm' end;
  j := to_jsonb(case when tg_op = 'DELETE' then old else new end);    -- the row as JSON: works for all four tables
  org := coalesce(j ->> 'org_id', j ->> 'tenant_id')::uuid; em := lower(j ->> 'email');
  select customer_id into cid from console.licences where product_code = product and product_ref = org;
  if cid is null or em is null then return coalesce(new, old); end if;
  if tg_op = 'DELETE' then
    update console.customer_members set roles = roles - product, updated_at = now() where customer_id = cid and email = em;
    return old;
  end if;
  rl := j ->> 'role'; nm := coalesce(j ->> 'full_name', j ->> 'display_name');
  if tg_table_name = 'app_users' then
    if rl = 'employee' then return new; end if;                      -- employees' self-service logins stay with HR onboarding
    if not coalesce((j ->> 'active')::boolean, true) then rl := null; end if;
  end if;
  insert into console.customer_members (customer_id, email, full_name, is_admin, roles, created_by)
  values (cid, em, nm, false, case when rl is null then '{}'::jsonb else jsonb_build_object(product, rl) end, 'Tool')
  on conflict (customer_id, email) do update
    set roles = case when rl is null then customer_members.roles - product else customer_members.roles || jsonb_build_object(product, rl) end,
        full_name = coalesce(customer_members.full_name, excluded.full_name), updated_at = now();
  return new;
end $$;
do $$
declare t text;
begin
  foreach t in array array['public.bi_members','public.pd_members','public.cp_members','hrm.app_users'] loop
    if to_regclass(t) is null then continue; end if;
    execute format('drop trigger if exists kmr_track_member on %s', t);
    execute format('create trigger kmr_track_member after insert or update or delete on %s for each row execute function console.track_member()', t);
  end loop;
end $$;
