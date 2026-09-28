-- =====================================================================
-- KMR platform — Operations Master (M7): one set of master data per customer, shared by all tools.
-- Lists: parts, customers, suppliers, machines, gauges, tools, consumables, raw_materials, rate_contracts,
--        cycle_times, cft (CFT team & key contacts), documents (policies, procedures, manuals, records… with a file).
-- Access through KMR Apps › Administration › Users & access: role "ops" = admin / editor / viewer;
-- company administrators always have full access. Needs 0011. Safe to re-run.
-- =====================================================================
do $$ begin
  if to_regclass('console.customer_members') is null then raise exception 'Run 0011_customer_admin.sql first.'; end if;
end $$;

create table if not exists console.ops_records (
  id          uuid primary key default gen_random_uuid(),
  customer_id uuid not null references console.customers(id) on delete cascade,
  kind        text not null check (kind in ('parts','customers','suppliers','machines','gauges','tools','consumables',
                                             'raw_materials','rate_contracts','cycle_times','cft','documents')),
  code        text not null check (length(trim(code)) between 1 and 80),
  name        text not null default '' check (length(name) <= 200),
  data        jsonb not null default '{}',
  active      boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  updated_by  text,
  unique (customer_id, kind, code)
);
create index if not exists ops_records_list on console.ops_records (customer_id, kind, code);
alter table console.ops_records enable row level security;
drop policy if exists ops_records_staff on console.ops_records;
create policy ops_records_staff on console.ops_records for all to authenticated using (console.is_staff()) with check (console.is_staff());

-- The signed-in person's Operations Master role for a customer: admin / editor / viewer / null
create or replace function console.ops_role(p_customer uuid) returns text
language sql stable security definer set search_path = console, public as $$
  select case
    when console.is_customer_admin(p_customer) then 'admin'
    else (select nullif(m.roles ->> 'ops', '') from console.customer_members m
           where m.customer_id = p_customer and m.email = lower(coalesce(auth.jwt() ->> 'email', '')))
  end
$$;
grant execute on function console.ops_role(uuid) to authenticated;

create or replace function public.kmr_ops_role(p_slug text) returns text
language sql stable security definer set search_path = console, public as $$
  select console.ops_role(id) from console.customers where slug = lower(p_slug)
$$;
grant execute on function public.kmr_ops_role(text) to authenticated;

create or replace function public.kmr_ops_counts(p_slug text) returns jsonb
language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or console.ops_role(cid) is null then raise exception 'You have no access to the Operations Master.'; end if;
  return coalesce((select jsonb_object_agg(kind, n) from (select kind, count(*) n from console.ops_records where customer_id = cid and active group by kind) x), '{}');
end $$;
grant execute on function public.kmr_ops_counts(text) to authenticated;

create or replace function public.kmr_ops_list(p_slug text, p_kind text) returns jsonb
language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or console.ops_role(cid) is null then raise exception 'You have no access to the Operations Master.'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', id, 'code', code, 'name', name, 'data', data, 'active', active,
            'updated_at', updated_at, 'updated_by', updated_by) order by code)
          from console.ops_records where customer_id = cid and kind = p_kind), '[]');
end $$;
grant execute on function public.kmr_ops_list(text, text) to authenticated;

-- Save one record ({id?, code, name, data, active}) or many (p_rows = array; import from CSV: matched by code)
create or replace function public.kmr_ops_save(p_slug text, p_kind text, p_rows jsonb) returns integer
language plpgsql security definer set search_path = console, public as $$
declare cid uuid; r jsonb; n integer := 0; me text := lower(coalesce(auth.jwt() ->> 'email', ''));
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or coalesce(console.ops_role(cid), '') not in ('admin','editor') then
    raise exception 'You can view the Operations Master but not change it. Ask your administrator for editor access.';
  end if;
  for r in select * from jsonb_array_elements(case when jsonb_typeof(p_rows) = 'array' then p_rows else jsonb_build_array(p_rows) end) loop
    if length(trim(coalesce(r ->> 'code', ''))) = 0 then raise exception 'Every record needs a code / number.'; end if;
    if r ? 'id' and (r ->> 'id') ~ '^[0-9a-f-]{36}$' then
      update console.ops_records set code = trim(r ->> 'code'), name = coalesce(trim(r ->> 'name'), ''),
             data = coalesce(r -> 'data', '{}'), active = coalesce((r ->> 'active')::boolean, true), updated_at = now(), updated_by = me
       where id = (r ->> 'id')::uuid and customer_id = cid and kind = p_kind;
    else
      insert into console.ops_records (customer_id, kind, code, name, data, active, updated_by)
      values (cid, p_kind, trim(r ->> 'code'), coalesce(trim(r ->> 'name'), ''), coalesce(r -> 'data', '{}'), coalesce((r ->> 'active')::boolean, true), me)
      on conflict (customer_id, kind, code) do update set name = excluded.name, data = console.ops_records.data || excluded.data,
         active = excluded.active, updated_at = now(), updated_by = me;
    end if;
    n := n + 1;
  end loop;
  return n;
end $$;
grant execute on function public.kmr_ops_save(text, text, jsonb) to authenticated;

create or replace function public.kmr_ops_delete(p_slug text, p_kind text, p_id uuid) returns text
language plpgsql security definer set search_path = console, public as $$
declare cid uuid;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or coalesce(console.ops_role(cid), '') not in ('admin','editor') then raise exception 'You cannot change the Operations Master.'; end if;
  delete from console.ops_records where id = p_id and customer_id = cid and kind = p_kind;
  return 'ok';
end $$;
grant execute on function public.kmr_ops_delete(text, text, uuid) to authenticated;

-- User management: "ops" is a role like a tool's (admin / editor / viewer)
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

-- Documents (policies, procedures, manuals, records…): private files, customers/<customer id>/documents/...
insert into storage.buckets (id, name, public, file_size_limit) values ('kmr-docs', 'kmr-docs', false, 26214400) on conflict (id) do nothing;
do $$ begin
  if to_regclass('storage.objects') is not null then
    execute 'drop policy if exists kmr_docs_read on storage.objects';
    execute $p$create policy kmr_docs_read on storage.objects for select to authenticated using (
      bucket_id = 'kmr-docs' and (storage.foldername(name))[1] = 'customers' and (storage.foldername(name))[2] ~ '^[0-9a-f-]{36}$'
      and console.ops_role(((storage.foldername(name))[2])::uuid) is not null)$p$;
    execute 'drop policy if exists kmr_docs_write on storage.objects';
    execute $p$create policy kmr_docs_write on storage.objects for insert to authenticated with check (
      bucket_id = 'kmr-docs' and (storage.foldername(name))[1] = 'customers' and (storage.foldername(name))[2] ~ '^[0-9a-f-]{36}$'
      and console.ops_role(((storage.foldername(name))[2])::uuid) in ('admin','editor'))$p$;
    execute 'drop policy if exists kmr_docs_delete on storage.objects';
    execute $p$create policy kmr_docs_delete on storage.objects for delete to authenticated using (
      bucket_id = 'kmr-docs' and (storage.foldername(name))[1] = 'customers' and (storage.foldername(name))[2] ~ '^[0-9a-f-]{36}$'
      and console.ops_role(((storage.foldername(name))[2])::uuid) in ('admin','editor'))$p$;
  end if;
end $$;

-- The signed-in person's Operations Master context (role + the customer reference used for document files)
create or replace function public.kmr_ops_context(p_slug text) returns jsonb
language sql stable security definer set search_path = console, public as $$
  select case when console.ops_role(c.id) is null then null
              else jsonb_build_object('role', console.ops_role(c.id), 'customer_id', c.id) end
    from console.customers c where c.slug = lower(p_slug)
$$;
grant execute on function public.kmr_ops_context(text) to authenticated;
