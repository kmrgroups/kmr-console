-- =====================================================================
-- KMR platform — Capacity Planner (capacity plan, takt time, machine loading) as a KMR product.
-- One workspace per customer company (cp_orgs); the whole plan is one JSON document per workspace;
-- roles admin / editor / viewer per workspace; every save kept in cp_history (last 300).
-- Access follows the customer's Console licence (product "capacity"). Safe to re-run.
-- =====================================================================
create table if not exists public.cp_orgs (
  id         uuid primary key default gen_random_uuid(),
  name       text not null check (length(name) between 2 and 120),
  settings   jsonb not null default '{}',
  created_at timestamptz not null default now()
);
create table if not exists public.cp_members (
  org_id       uuid not null references public.cp_orgs(id) on delete cascade,
  email        text not null check (email = lower(email)),
  role         text not null default 'viewer' check (role in ('admin','editor','viewer')),
  display_name text,
  login_owned  boolean not null default false,     -- the login was created by this workspace (its admin may reset the password)
  created_by   text,
  created_at   timestamptz not null default now(),
  primary key (org_id, email)
);
create index if not exists cp_members_email on public.cp_members (email);
create table if not exists public.cp_plans (
  org_id     uuid primary key references public.cp_orgs(id) on delete cascade,
  data       jsonb not null,
  updated_at timestamptz not null default now(),
  updated_by text
);
create table if not exists public.cp_history (
  id       bigserial primary key,
  org_id   uuid not null references public.cp_orgs(id) on delete cascade,
  data     jsonb,
  saved_at timestamptz not null default now(),
  saved_by text
);
create index if not exists cp_history_org on public.cp_history (org_id, id desc);

-- ---------- helpers ----------
create or replace function public.cp_my_role(p_org uuid) returns text
language sql stable security definer set search_path = public as $$
  select role from public.cp_members where org_id = p_org and email = lower(coalesce(auth.jwt() ->> 'email', ''))
$$;
grant execute on function public.cp_my_role(uuid) to authenticated;

create or replace function public.cp_my_workspaces() returns table (id uuid, name text, role text)
language sql stable security definer set search_path = public as $$
  select o.id, o.name, m.role from public.cp_members m join public.cp_orgs o on o.id = m.org_id
   where m.email = lower(coalesce(auth.jwt() ->> 'email', '')) order by o.name
$$;
grant execute on function public.cp_my_workspaces() to authenticated;

create or replace function public.cp_touch() returns trigger language plpgsql as $$ begin new.updated_at := now(); return new; end $$;
drop trigger if exists cp_touch on public.cp_plans;
create trigger cp_touch before insert or update on public.cp_plans for each row execute function public.cp_touch();

create or replace function public.cp_keep_history() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.cp_history (org_id, data, saved_by) values (old.org_id, old.data, old.updated_by);
  delete from public.cp_history where org_id = old.org_id
     and id not in (select id from public.cp_history where org_id = old.org_id order by id desc limit 300);
  return new;
end $$;
drop trigger if exists cp_history on public.cp_plans;
create trigger cp_history before update on public.cp_plans for each row execute function public.cp_keep_history();

create or replace function public.cp_protect_last_admin() returns trigger language plpgsql as $$
begin
  if (tg_op = 'DELETE' and old.role = 'admin') or (tg_op = 'UPDATE' and old.role = 'admin' and new.role <> 'admin') then
    if (select count(*) from public.cp_members where org_id = old.org_id and role = 'admin' and email <> old.email) = 0 then
      raise exception 'At least one admin must remain.';
    end if;
  end if;
  return coalesce(new, old);
end $$;
drop trigger if exists cp_last_admin on public.cp_members;
create trigger cp_last_admin before update or delete on public.cp_members for each row execute function public.cp_protect_last_admin();

-- ---------- user management inside the planner (replaces the old "admin-users" Edge Function) ----------
-- Creating a brand-new login needs a password; an existing KMR login is simply added (it keeps its own password).
-- A workspace admin may reset only passwords of logins that this workspace created.
create or replace function public.cp_admin(p_org uuid, p_action text, p_payload jsonb default '{}') returns jsonb
language plpgsql security definer set search_path = public, auth, extensions as $$
declare
  me text := lower(coalesce(auth.jwt() ->> 'email', ''));
  em text := lower(trim(coalesce(p_payload ->> 'email', '')));
  rl text := coalesce(p_payload ->> 'role', 'viewer');
  pw text := coalesce(p_payload ->> 'password', '');
  nm text := nullif(trim(coalesce(p_payload ->> 'name', '')), '');
  uid uuid; owned boolean;
begin
  if public.cp_my_role(p_org) is distinct from 'admin' then raise exception 'Only an admin can manage users.'; end if;
  if p_action = 'list' then
    return jsonb_build_object('users', coalesce((select jsonb_agg(jsonb_build_object('email', m.email, 'role', m.role, 'name', m.display_name,
      'createdAt', m.created_at, 'createdBy', m.created_by, 'hasLogin', u.id is not null, 'lastSignIn', u.last_sign_in_at) order by m.email)
      from public.cp_members m left join auth.users u on lower(u.email) = m.email where m.org_id = p_org), '[]'::jsonb));
  end if;
  if em !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'Enter a valid e-mail address.'; end if;
  if rl not in ('admin','editor','viewer') then raise exception 'Unknown role.'; end if;
  select id into uid from auth.users where lower(email) = em limit 1;

  if p_action = 'create' then
    owned := false;
    if uid is null then
      if length(pw) < 8 then raise exception 'The password must have at least 8 characters.'; end if;
      uid := gen_random_uuid();
      insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
                              raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
                              confirmation_token, recovery_token, email_change_token_new, email_change)
      values ('00000000-0000-0000-0000-000000000000', uid, 'authenticated', 'authenticated', em, crypt(pw, gen_salt('bf')), now(),
              '{"provider":"email","providers":["email"]}', jsonb_build_object('name', coalesce(nm, '')), now(), now(), '', '', '', '');
      insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
      values (gen_random_uuid(), uid, uid::text, jsonb_build_object('sub', uid::text, 'email', em, 'email_verified', true), 'email', now(), now(), now());
      owned := true;
    end if;
    insert into public.cp_members (org_id, email, role, display_name, login_owned, created_by)
    values (p_org, em, rl, nm, owned, me)
    on conflict (org_id, email) do update set role = excluded.role, display_name = coalesce(excluded.display_name, cp_members.display_name);
    return jsonb_build_object('ok', true, 'newLogin', owned);
  elsif p_action = 'setRole' then
    update public.cp_members set role = rl, display_name = coalesce(nm, display_name) where org_id = p_org and email = em;
    return jsonb_build_object('ok', true);
  elsif p_action = 'resetPassword' then
    if length(pw) < 8 then raise exception 'The password must have at least 8 characters.'; end if;
    if not exists (select 1 from public.cp_members where org_id = p_org and email = em and login_owned) then
      raise exception 'This person uses their own KMR login. They can change the password themselves, or ask KMR support.';
    end if;
    update auth.users set encrypted_password = crypt(pw, gen_salt('bf')), updated_at = now() where id = uid;
    return jsonb_build_object('ok', true);
  elsif p_action = 'remove' then
    if em = me then raise exception 'You cannot remove yourself.'; end if;
    delete from public.cp_members where org_id = p_org and email = em;     -- the login stays (it may be used in other KMR apps)
    return jsonb_build_object('ok', true);
  end if;
  raise exception 'Unknown action.';
end $$;
revoke all on function public.cp_admin(uuid, text, jsonb) from public, anon;
grant execute on function public.cp_admin(uuid, text, jsonb) to authenticated;

-- ---------- row-level security ----------
alter table public.cp_orgs    enable row level security;
alter table public.cp_members enable row level security;
alter table public.cp_plans   enable row level security;
alter table public.cp_history enable row level security;
drop policy if exists cp_orgs_read on public.cp_orgs;
create policy cp_orgs_read on public.cp_orgs for select to authenticated using (public.cp_my_role(id) is not null);
drop policy if exists cp_members_read on public.cp_members;
create policy cp_members_read on public.cp_members for select to authenticated
  using (email = lower(coalesce(auth.jwt() ->> 'email', '')) or public.cp_my_role(org_id) = 'admin');
drop policy if exists cp_plans_read on public.cp_plans;
create policy cp_plans_read on public.cp_plans for select to authenticated using (public.cp_my_role(org_id) is not null);
drop policy if exists cp_plans_insert on public.cp_plans;
create policy cp_plans_insert on public.cp_plans for insert to authenticated with check (public.cp_my_role(org_id) in ('admin','editor'));
drop policy if exists cp_plans_update on public.cp_plans;
create policy cp_plans_update on public.cp_plans for update to authenticated
  using (public.cp_my_role(org_id) in ('admin','editor')) with check (public.cp_my_role(org_id) in ('admin','editor'));
drop policy if exists cp_history_read on public.cp_history;
create policy cp_history_read on public.cp_history for select to authenticated using (public.cp_my_role(org_id) = 'admin');
-- the Console licence: restrictive, on top of the rules above
drop policy if exists kmr_licence on public.cp_plans;
create policy kmr_licence on public.cp_plans as restrictive for all to authenticated
  using (console.product_ok('capacity', org_id)) with check (console.product_ok('capacity', org_id));
drop policy if exists kmr_licence on public.cp_history;
create policy kmr_licence on public.cp_history as restrictive for all to authenticated using (console.product_ok('capacity', org_id));

-- ---------- product in the Console ----------
insert into console.products (code, name, description, app_path, seat_label, current_version, sort_order)
values ('capacity', 'Capacity Planner', 'Capacity plan, takt time and machine loading', '/it/capacity.html', 'users', '4.1.0', 40)
on conflict (code) do nothing;
insert into console.releases (product_code, version, notes)
values ('capacity', '4.1.0', 'Capacity Planner on the KMR platform: one workspace per customer, KMR Apps sign-in, Console licences')
on conflict do nothing;

-- workspaces created without the Console get a 30-day trial; the user limit counts members
create or replace function console.auto_trial() returns trigger
language plpgsql security definer set search_path = console, public as $$
declare product text := case tg_table_name when 'bi_orgs' then 'balloon' when 'cp_orgs' then 'capacity' else 'pd' end; cid uuid;
begin
  if exists (select 1 from console.licences where product_code = product and product_ref = new.id) then return new; end if;
  select id into cid from console.customers where lower(name) = lower(new.name) limit 1;
  if cid is null then insert into console.customers (name, status, source) values (new.name, 'pilot', 'Created inside the tool') returning id into cid; end if;
  if exists (select 1 from console.licences where customer_id = cid and product_code = product) then
    insert into console.customers (name, status, source) values (new.name || ' (' || left(new.id::text, 8) || ')', 'pilot', 'Created inside the tool') returning id into cid;
  end if;
  insert into console.licences (customer_id, product_code, status, valid_until, product_ref, product_slug, notes)
  values (cid, product, 'trial', current_date + 30, new.id, new.name, 'Created inside the tool — 30-day trial');
  return new;
end $$;
drop trigger if exists kmr_auto_trial on public.cp_orgs;
create trigger kmr_auto_trial after insert on public.cp_orgs for each row execute function console.auto_trial();

create or replace function console.member_limit() returns trigger
language plpgsql security definer set search_path = console, public as $$
declare product text := case tg_table_name when 'bi_members' then 'balloon' when 'cp_members' then 'capacity' else 'pd' end; lim int; n int;
begin
  select seats into lim from console.licences where product_code = product and product_ref = new.org_id;
  if lim is null then return new; end if;
  if tg_table_name = 'bi_members' then select count(*) into n from public.bi_members where org_id = new.org_id and lower(email) <> lower(new.email);
  elsif tg_table_name = 'cp_members' then select count(*) into n from public.cp_members where org_id = new.org_id and email <> lower(new.email);
  else select count(*) into n from public.pd_members where org_id = new.org_id and lower(email) <> lower(new.email); end if;
  if n >= lim then raise exception 'Your licence covers % users for this workspace, and that limit is reached. Contact KMR to raise it.', lim; end if;
  return new;
end $$;
drop trigger if exists kmr_member_limit on public.cp_members;
create trigger kmr_member_limit before insert on public.cp_members for each row execute function console.member_limit();

-- ---------- portal: access, first use, figures (now including the Capacity Planner) ----------
create or replace function public.kmr_access(p_product text)
returns table (org_id uuid, ok boolean, status text, message text)
language plpgsql stable security definer set search_path = public, console as $$
declare em text := lower(coalesce(auth.jwt() ->> 'email', ''));
begin
  if console.tool_admin(p_product) then
    if p_product = 'balloon' then return query select o.id, true, 'admin'::text, null::text from public.bi_orgs o; end if;
    if p_product = 'pd'      then return query select o.id, true, 'admin'::text, null::text from public.pd_orgs o; end if;
    return;
  end if;
  if p_product = 'balloon' then
    return query select m.org_id, a.ok, a.status, a.message from public.bi_members m cross join lateral console.access_state('balloon', m.org_id) a where lower(m.email) = em;
  elsif p_product = 'pd' then
    return query select m.org_id, a.ok, a.status, a.message from public.pd_members m cross join lateral console.access_state('pd', m.org_id) a where lower(m.email) = em;
  elsif p_product = 'capacity' then
    return query select m.org_id, a.ok, a.status, a.message from public.cp_members m cross join lateral console.access_state('capacity', m.org_id) a where m.email = em;
  end if;
end $$;

drop function if exists public.kmr_portal_stats(text);
drop function if exists public.kmr_portal(text);
create or replace function public.kmr_portal(p_slug text)
returns table (product_code text, product_name text, app_path text, purchased boolean, ok boolean, status text,
               valid_until date, message text, customer_name text, logo_url text, product_slug text,
               has_access boolean, is_contact boolean)
language plpgsql stable security definer set search_path = console, public as $$
declare
  em text := lower(coalesce(auth.jwt() ->> 'email', ''));
  uid uuid := auth.uid();
  c console.customers%rowtype;
  member boolean := false;
begin
  select * into c from console.customers where slug = lower(p_slug);
  if c.id is null or em = '' then return; end if;
  select true into member from console.licences l
   where l.customer_id = c.id and (
         (l.product_code = 'balloon'  and exists (select 1 from public.bi_members m where m.org_id = l.product_ref and lower(m.email) = em))
      or (l.product_code = 'pd'       and exists (select 1 from public.pd_members m where m.org_id = l.product_ref and lower(m.email) = em))
      or (l.product_code = 'capacity' and exists (select 1 from public.cp_members m where m.org_id = l.product_ref and m.email = em))
      or (l.product_code = 'hrm'      and exists (select 1 from hrm.app_users u where u.tenant_id = l.product_ref and u.id = uid and u.active)))
   limit 1;
  if not coalesce(member, false) and lower(coalesce(c.contact_email, '')) <> em then return; end if;
  return query
    select p.code, p.name, p.app_path, (l.id is not null), coalesce(a.ok, false), coalesce(a.status, 'not_purchased'),
           l.valid_until, a.message, c.name, c.logo_url, l.product_slug,
           case p.code
             when 'balloon'  then exists (select 1 from public.bi_members m where m.org_id = l.product_ref and lower(m.email) = em)
             when 'pd'       then exists (select 1 from public.pd_members m where m.org_id = l.product_ref and lower(m.email) = em)
             when 'capacity' then exists (select 1 from public.cp_members m where m.org_id = l.product_ref and m.email = em)
             when 'hrm'      then exists (select 1 from hrm.app_users u where u.tenant_id = l.product_ref and u.id = uid and u.active)
             else false end,
           lower(coalesce(c.contact_email, '')) = em
      from console.products p
      left join console.licences l on l.product_code = p.code and l.customer_id = c.id
      left join lateral console.access_state(p.code, l.product_ref) a on l.id is not null
     where p.active
     order by p.sort_order;
end $$;
revoke all on function public.kmr_portal(text) from public, anon;
grant execute on function public.kmr_portal(text) to authenticated;

create or replace function public.kmr_portal_join(p_slug text, p_product text) returns text
language plpgsql security definer set search_path = console, public as $$
declare
  em text := lower(coalesce(auth.jwt() ->> 'email', ''));
  uid uuid := auth.uid();
  c console.customers%rowtype; l console.licences%rowtype; nm text;
begin
  select * into c from console.customers where slug = lower(p_slug);
  if c.id is null or em = '' or lower(coalesce(c.contact_email, '')) <> em then
    raise exception 'Only your company''s administrator can give you access to this app. Please ask them to add you.';
  end if;
  select * into l from console.licences where customer_id = c.id and product_code = p_product;
  if l.id is null or l.product_ref is null then raise exception 'This app is not set up for your company yet. Please contact KMR.'; end if;
  if not (select ok from console.access_state(p_product, l.product_ref)) then raise exception 'Your subscription for this app is not active.'; end if;
  nm := coalesce(nullif(c.contact_name, ''), split_part(em, '@', 1));
  if p_product = 'balloon' then
    insert into public.bi_members (org_id, email, role) values (l.product_ref, em, 'admin') on conflict do nothing;
  elsif p_product = 'pd' then
    insert into public.pd_members (org_id, email, role) values (l.product_ref, em, 'admin') on conflict do nothing;
  elsif p_product = 'capacity' then
    insert into public.cp_members (org_id, email, role, display_name, created_by) values (l.product_ref, em, 'admin', nm, 'KMR Apps') on conflict do nothing;
  elsif p_product = 'hrm' then
    if exists (select 1 from hrm.app_users where id = uid and tenant_id <> l.product_ref) then
      raise exception 'This login is already used for another company''s HRM. Please use a different email.';
    end if;
    insert into hrm.app_users (id, tenant_id, role, full_name, email, must_change_password)
    values (uid, l.product_ref, 'company_admin', nm, em, false) on conflict (id) do update set active = true;
  else
    raise exception 'Unknown app.';
  end if;
  return 'ok';
end $$;
revoke all on function public.kmr_portal_join(text, text) from public, anon;
grant execute on function public.kmr_portal_join(text, text) to authenticated;

-- (portal figures, now with the Capacity Planner)
create or replace function public.kmr_portal_stats(p_slug text) returns jsonb
language plpgsql stable security definer set search_path = console, public as $$
declare c uuid; out jsonb := '{}'; ref uuid; today date := (now() at time zone 'Asia/Kolkata')::date;
begin
  if not exists (select 1 from public.kmr_portal(p_slug)) then return out; end if;
  select id into c from console.customers where slug = lower(p_slug);
  select product_ref into ref from console.licences where customer_id = c and product_code = 'hrm';
  if ref is not null then
    out := out || jsonb_build_object('hrm', jsonb_build_object(
      'Employees', (select count(*) from hrm.employees where tenant_id = ref and status = 'active'),
      'In today', (select count(*) from hrm.attendance_days where tenant_id = ref and work_date = today and status in ('present','half_day','missed_punch')),
      'Awaiting approval', (select count(*) from hrm.leave_requests where tenant_id = ref and status = 'pending')
                          + (select count(*) from hrm.regularisation_requests where tenant_id = ref and status = 'pending')));
  end if;
  select product_ref into ref from console.licences where customer_id = c and product_code = 'balloon';
  if ref is not null then
    out := out || jsonb_build_object('balloon', jsonb_build_object(
      'Reports', (select count(*) from public.bi_reports where org_id = ref),
      'Users', (select count(*) from public.bi_members where org_id = ref)));
  end if;
  select product_ref into ref from console.licences where customer_id = c and product_code = 'pd';
  if ref is not null then
    out := out || jsonb_build_object('pd', jsonb_build_object(
      'Projects', (select count(*) from public.pd_projects where org_id = ref),
      'Users', (select count(*) from public.pd_members where org_id = ref)));
  end if;
  select product_ref into ref from console.licences where customer_id = c and product_code = 'capacity';
  if ref is not null then
    out := out || jsonb_build_object('capacity', jsonb_build_object(
      'Users', (select count(*) from public.cp_members where org_id = ref),
      'Saved versions', (select count(*) from public.cp_history where org_id = ref) + (select count(*) from public.cp_plans where org_id = ref)));
  end if;
  return out;
end $$;
revoke all on function public.kmr_portal_stats(text) from public, anon;
grant execute on function public.kmr_portal_stats(text) to authenticated;
