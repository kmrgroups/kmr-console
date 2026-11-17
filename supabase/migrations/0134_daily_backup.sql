-- KMR 0134 — Daily backup of EVERY customer / plant: every app's data, masters and settings, one file per app, mailed (download links) to the people the company names.
-- Replaces the old single "apps_export" query, which timed out. The Console reads the data page by page with the functions below (service role only).
-- Safe to re-run.
create table if not exists console.backup_settings (
  customer_id uuid primary key references console.customers(id) on delete cascade,
  enabled boolean not null default true,
  recipients text not null default '',
  keep_days int not null default 30 check (keep_days between 7 and 365),
  last_run_on date, last_status text, last_detail jsonb,
  updated_at timestamptz not null default now(), updated_by text);
alter table console.backup_settings enable row level security;
drop policy if exists backup_settings_staff on console.backup_settings;
create policy backup_settings_staff on console.backup_settings for all to authenticated using (console.is_staff()) with check (console.is_staff());

-- tables of one app for one company ('settings' = company details, plants link, users & access, licences, mail settings, budgets, finance entries, P&L set-up)
create or replace function console.bk_app_tables(p_cid uuid, p_app text) returns table (sch text, tbl text, key text, ref uuid) language plpgsql stable security definer set search_path = console, public as $$
declare r uuid;
begin
  if p_app = 'settings' then
    return query select 'console'::text, 'customers'::text, 'id'::text, p_cid;
    return query select 'console'::text, x::text, 'customer_id'::text, p_cid from unnest(array['customer_members','licences','digest_settings','fin_settings','cal_alert_settings','backup_settings',
      'pnl_heads','pnl_alias','pnl_rules','pnl_stock','pnl_settings','fin_budget','fin_open_items','fin_entries']) x;
    return;
  end if;
  if not (p_app = any (console.yb_apps())) then return; end if;
  r := console.yb_ref(p_cid, p_app);
  if r is null then return; end if;
  return query select t.sch, t.tbl, t.key, r from console.yb_tables(p_app) t;
  -- tables the year backup does not list but that hold real data (production history, rosters, ERP invoice lines, RMP weekly plan ...)
  return query select 'console'::text, x::text, 'customer_id'::text, r from unnest(case p_app
      when 'mmd' then array['mmd_hist'] when 'hrms' then array['hrms_roster'] when 'sales' then array['sf_erp_invoice_lines', 'sf_erp_customer_map']
      when 'rmp' then array['rmp_partstock', 'rmp_plan_week', 'rmp_settings'] when 'calib' then array['cal_files'] else array[]::text[] end) x
    where not exists (select 1 from console.yb_tables(p_app) t2 where t2.tbl = x);
end $$;
revoke all on function console.bk_app_tables(uuid, text) from public, anon, authenticated;

create or replace function console.bk_smp(p_sch text, p_tbl text) returns text language sql stable as $$
  select case when exists (select 1 from pg_attribute where attrelid = format('%I.%I', p_sch, p_tbl)::regclass and attname = 'sample' and not attisdropped and atttypid = 'boolean'::regtype) then ' and not coalesce(x.sample, false)' else '' end $$;
revoke all on function console.bk_smp(text, text) from public, anon, authenticated;

-- 1. plan: which apps / tables have records for this company
create or replace function public.kmr_bk_plan(p_cid uuid) returns jsonb language plpgsql stable security definer set search_path = console, public set statement_timeout = '120s' as $$
declare a text; k record; n bigint; tl jsonb; res jsonb := '[]';
begin
  foreach a in array (console.yb_apps() || array['settings']) loop
    tl := '[]';
    for k in select * from console.bk_app_tables(p_cid, a) loop
      begin
        execute format('select count(*) from %I.%I x where x.%I = $1%s', k.sch, k.tbl, k.key, console.bk_smp(k.sch, k.tbl)) into n using k.ref;
      exception when undefined_table or undefined_column then n := 0; end;
      if n > 0 then tl := tl || jsonb_build_array(jsonb_build_object('t', k.tbl, 'rows', n)); end if;
    end loop;
    if jsonb_array_length(tl) > 0 then res := res || jsonb_build_array(jsonb_build_object('app', a, 'tables', tl)); end if;
  end loop;
  return res;
end $$;
revoke all on function public.kmr_bk_plan(uuid) from public, anon, authenticated;
grant execute on function public.kmr_bk_plan(uuid) to service_role;

-- 2. one page of one table
create or replace function public.kmr_bk_page(p_cid uuid, p_app text, p_table text, p_offset int, p_limit int) returns jsonb language plpgsql stable security definer set search_path = console, public set statement_timeout = '120s' as $$
declare k record; pk text; rows jsonb;
begin
  select * into k from console.bk_app_tables(p_cid, p_app) t where t.tbl = p_table limit 1;
  if k.tbl is null then return '[]'; end if;
  select string_agg(format('x.%I', a.attname), ', ' order by array_position(i.indkey::int[], a.attnum::int)) into pk
    from pg_index i join pg_attribute a on a.attrelid = i.indrelid and a.attnum = any (i.indkey) where i.indrelid = format('%I.%I', k.sch, k.tbl)::regclass and i.indisprimary;
  execute format('select coalesce(jsonb_agg(to_jsonb(x)), ''[]'') from (select * from %I.%I x where x.%I = $1%s order by %s offset $2 limit $3) x',
                 k.sch, k.tbl, k.key, console.bk_smp(k.sch, k.tbl), coalesce(pk, 'x.ctid')) into rows using k.ref, greatest(p_offset, 0), least(greatest(p_limit, 1), 5000);
  return rows;
end $$;
revoke all on function public.kmr_bk_page(uuid, text, text, int, int) from public, anon, authenticated;
grant execute on function public.kmr_bk_page(uuid, text, text, int, int) to service_role;

-- 3. the companies / plants to back up and who gets the mail
create or replace function public.kmr_bk_scan() returns jsonb language plpgsql stable security definer set search_path = console, public as $$
begin
  return coalesce((select jsonb_agg(jsonb_build_object('customer_id', c.id, 'slug', c.slug, 'name', c.name, 'brand', console.cal_brand(c.id), 'enabled', coalesce(s.enabled, true),
            'recipients', coalesce(s.recipients, ''), 'keep_days', coalesce(s.keep_days, 30), 'last_run_on', s.last_run_on) order by c.slug)
          from console.customers c left join console.backup_settings s on s.customer_id = c.id
         where exists (select 1 from console.licences l where l.customer_id = c.id)), '[]');
end $$;
revoke all on function public.kmr_bk_scan() from public, anon, authenticated;
grant execute on function public.kmr_bk_scan() to service_role;

create or replace function public.kmr_bk_mark(p_cid uuid, p_status text, p_detail jsonb) returns void language sql security definer set search_path = console, public as $$
  insert into console.backup_settings (customer_id, last_run_on, last_status, last_detail) values (p_cid, (now() at time zone 'Asia/Kolkata')::date, p_status, p_detail)
  on conflict (customer_id) do update set last_run_on = excluded.last_run_on, last_status = excluded.last_status, last_detail = excluded.last_detail
$$;
revoke all on function public.kmr_bk_mark(uuid, text, jsonb) from public, anon, authenticated;
grant execute on function public.kmr_bk_mark(uuid, text, jsonb) to service_role;

-- 4. Administration screen (company administrators)
create or replace function console.bk_admin(p_slug text) returns uuid language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or not console.is_customer_admin(cid) then raise exception 'Only your company''s administrators can use the backup mail.'; end if;
  return cid;
end $$;
revoke all on function console.bk_admin(text) from public, anon, authenticated;
create or replace function public.kmr_bk_get(p_slug text) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.bk_admin(p_slug); s console.backup_settings;
begin
  select * into s from console.backup_settings where customer_id = cid;
  return jsonb_build_object('enabled', coalesce(s.enabled, true), 'recipients', coalesce(s.recipients, ''), 'keep_days', coalesce(s.keep_days, 30), 'last_run_on', s.last_run_on, 'last_status', s.last_status,
    'last_detail', coalesce(s.last_detail, '{}'), 'me', lower(coalesce(auth.jwt() ->> 'email', '')));
end $$;
grant execute on function public.kmr_bk_get(text) to authenticated;
create or replace function public.kmr_bk_save(p_slug text, p jsonb) returns text language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.bk_admin(p_slug); kd int := coalesce(nullif(p ->> 'keep_days', '')::int, 30);
begin
  if kd < 7 or kd > 365 then raise exception 'Keep the backups between 7 and 365 days.'; end if;
  insert into console.backup_settings (customer_id, enabled, recipients, keep_days, updated_at, updated_by)
  values (cid, coalesce(p ->> 'enabled', '') in ('true', 't', '1'), lower(trim(coalesce(p ->> 'recipients', ''))), kd, now(), lower(coalesce(auth.jwt() ->> 'email', '')))
  on conflict (customer_id) do update set enabled = excluded.enabled, recipients = excluded.recipients, keep_days = excluded.keep_days, updated_at = now(), updated_by = excluded.updated_by;
  return 'ok';
end $$;
grant execute on function public.kmr_bk_save(text, jsonb) to authenticated;

-- first recipients: Esbee's three plants
insert into console.backup_settings (customer_id, enabled, recipients)
select c.id, true, 'rishab.b@nerigroup.in,ravi.bk@nerigroup.in,info@kmr-groups.com' from console.customers c where right(c.slug, 5) in ('c0021', 'c0023', 'c0024')
on conflict (customer_id) do update set recipients = excluded.recipients, enabled = true where console.backup_settings.recipients = '';
