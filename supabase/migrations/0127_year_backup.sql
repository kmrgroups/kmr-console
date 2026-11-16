-- =====================================================================
-- 0127 — Year-wise backup & restore (Grand Master + Data Master)
--   Backup  : every app's real data is split by FINANCIAL YEAR (April–March) → App / Year / files (JSON + Excel with dashboard, analysis and raw data),
--             plus ONE overall JSON for the whole company.
--   Restore : upload the overall JSON (or one app-year JSON) → every record goes back into the right app, ADD + UPDATE only (nothing is deleted).
--   The year of a record comes from its own business date (DC date, GRN date, invoice date, work date, due date …); a record without a date follows the
--   record it belongs to (e.g. a challan line follows its challan); settings and number counters have no year and are kept under "Masters".
--   Company administrators only. Logins, users, access, invoices & payments of the platform and secrets (sessions, device tokens, push keys) are never exported.
-- Needs 0026 / 0029 / 0113 / 0118. Safe to re-run.
-- =====================================================================

-- ---------- helpers ----------
create or replace function console.yb_fy(d date) returns text language sql immutable as $$
  select case when d is null then 'Masters'
              else (extract(year from d)::int - (case when extract(month from d) < 4 then 1 else 0 end))::text || '-'
                   || lpad((((extract(year from d)::int - (case when extract(month from d) < 4 then 1 else 0 end)) + 1) % 100)::text, 2, '0') end $$;

-- who may use it: the company administrator
create or replace function console.yb_target(p_slug text) returns uuid language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or not console.is_customer_admin(cid) then raise exception 'Only your company administrator can use the year-wise backup.'; end if;
  return cid;
end $$;
revoke all on function console.yb_target(text) from public, anon, authenticated;

-- the apps in the backup, in restore order (the app's workspace / company key is found in yb_key)
create or replace function console.yb_apps() returns text[] language sql immutable as $$
  select array['ops','hrm','hrms','balloon','pd','capacity','sales','calib','dcg','inv','rmp','mmd','mnt','apqp','ppap','msa','spc','crm','d8','aud','tsk','mom','cad','layout','dwm','off','connect'] $$;

-- the workspace id the app's rows are stored under (company id, or the HRM / tool workspace); null = the company does not have the app
create or replace function console.yb_ref(p_cid uuid, p_app text) returns uuid language plpgsql stable security definer set search_path = console, public as $$
declare r uuid;
begin
  if p_app = 'ops' then return p_cid; end if;
  if p_app in ('hrm', 'balloon', 'pd', 'capacity') then
    select l.product_ref into r from console.licences l where l.customer_id = p_cid and l.product_code = p_app and l.product_ref is not null limit 1;
    return r;
  end if;
  if console.has_app(p_cid, p_app) then return p_cid; end if;
  return null;
end $$;
revoke all on function console.yb_ref(uuid, text) from public, anon, authenticated;

-- tables of an app: schema, table, the column that holds the company / workspace id
create or replace function console.yb_tables(p_app text) returns table (sch text, tbl text, key text) language plpgsql stable security definer set search_path = console, public as $$
declare skip text[] := array['hrms_sessions', 'hrms_login_fails', 'hrms_devices', 'cn_devices', 'tsk_push_subs', 'passkeys', 'tenant_mail', 'tenant_domains', 'attendance_devices', 'ai_runs', 'app_users'];
begin
  if p_app = 'hrm' then
    return query select 'hrm'::text, c.relname::text, 'tenant_id'::text from pg_class c join pg_namespace s on s.oid = c.relnamespace
      where s.nspname = 'hrm' and c.relkind = 'r' and c.relname <> all (skip)
        and exists (select 1 from pg_attribute a where a.attrelid = c.oid and a.attname = 'tenant_id' and not a.attisdropped) order by c.relname;
  elsif p_app in ('balloon', 'pd', 'capacity') then
    return query select 'public'::text, x::text, 'org_id'::text from unnest(console.data_tables(p_app)) x;
  elsif p_app = 'ops' then
    return query select 'console'::text, 'ops_records'::text, 'customer_id'::text;
  elsif p_app = 'dcg' then
    return query select 'console'::text, x::text, 'customer_id'::text from unnest(array['dcg_counters', 'dcg_po', 'dcg_po_lines', 'dcg_dc', 'dcg_dc_lines', 'dcg_grn', 'dcg_grn_lines']) x;
  elsif p_app = 'inv' then
    return query select 'console'::text, x::text, 'customer_id'::text from unnest(array['inv_counters', 'inv_settings', 'inv_invoice', 'inv_lines']) x;
  elsif p_app = 'layout' then
    return query select 'console'::text, x::text, 'customer_id'::text from unnest(array['layout_counters', 'layout_projects']) x;
  elsif p_app = 'dwm' then
    return query select 'console'::text, 'dwm_docs'::text, 'customer_id'::text;
  elsif p_app = any (console.yb_apps()) then
    return query select 'console'::text, x::text, 'customer_id'::text from unnest(console.app2_tables(p_app)) x where x <> all (skip);
  end if;
end $$;
revoke all on function console.yb_tables(text) from public, anon, authenticated;

-- parents first (so a restore never meets a missing parent); tables that point at each other keep their listed order
create or replace function console.yb_sorted(p_app text) returns text[] language plpgsql stable security definer set search_path = console, public as $$
declare todo text[] := array(select sch || '.' || tbl from console.yb_tables(p_app)); res text[] := '{}'; ready text[]; t text;
begin
  while cardinality(todo) > 0 loop
    ready := array(select x from unnest(todo) x where not exists (
      select 1 from pg_constraint k where k.contype = 'f' and k.conrelid = x::regclass and k.confrelid <> k.conrelid
         and (select n.nspname || '.' || c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace where c.oid = k.confrelid) = any (todo)));
    if cardinality(ready) = 0 then ready := todo; end if;
    foreach t in array ready loop res := res || t; todo := array_remove(todo, t); end loop;
  end loop;
  return res;
end $$;
revoke all on function console.yb_sorted(text) from public, anon, authenticated;

-- the SQL expression that gives the DATE a record belongs to (alias a); null = the table has no date (kept under Masters)
create or replace function console.yb_date_expr(p_sch text, p_tbl text, p_alias text default 'x', p_depth int default 0) returns text language plpgsql stable security definer set search_path = console, public as $$
declare rel regclass := format('%I.%I', p_sch, p_tbl)::regclass; col text; ty oid; k record; sub text; own text; par text;
begin
  select a.attname, a.atttypid into col, ty
    from unnest(array['dc_date', 'grn_date', 'po_date', 'inv_date', 'work_date', 'prod_date', 'entry_at', 'cal_date', 'ev_date', 'quote_date', 'meeting_date', 'event_date', 'planned_on', 'received_on',
                      'opened_on', 'order_date', 'loss_date', 'study_date', 'taken_at', 'punched_at', 'hdate', 'holiday_date', 'entry_date', 'audit_date', 'starts_at', 'from_date', 'invdate', 'day',
                      'month', 'due_on', 'due', 'at', 'created_at']) with ordinality n(nm, o)
    join pg_attribute a on a.attrelid = rel and a.attname = n.nm and not a.attisdropped and a.atttypid in ('date'::regtype, 'timestamptz'::regtype, 'timestamp'::regtype)
   order by n.o limit 1;
  if col is not null then
    own := case ty when 'date'::regtype then format('%s.%I', p_alias, col) else format('(%s.%I at time zone ''Asia/Kolkata'')::date', p_alias, col) end;
  end if;
  -- the first record it is linked to (e.g. a challan line → its challan); used when it has no date of its own, or first for "…_lines" tables
  if p_depth < 3 and (own is null or p_tbl like '%\_lines') then
    for k in select a.attname as child_col, pc.relname as parent_tbl, pn.nspname as parent_sch, pa.attname as parent_col
               from pg_constraint c
               join pg_class pc on pc.oid = c.confrelid join pg_namespace pn on pn.oid = pc.relnamespace
               join pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
               join pg_attribute pa on pa.attrelid = c.confrelid and pa.attnum = c.confkey[1]
              where c.contype = 'f' and c.conrelid = rel and cardinality(c.conkey) = 1 and c.confrelid <> c.conrelid
                and a.attname not in ('customer_id', 'org_id', 'tenant_id') and pn.nspname in ('console', 'hrm', 'public')
                and pc.relname not in ('customers', 'bi_orgs', 'pd_orgs', 'cp_orgs', 'tenants')
              order by a.attnum loop
      sub := console.yb_date_expr(k.parent_sch, k.parent_tbl, 'p' || p_depth, p_depth + 1);
      if sub is not null then
        par := format('(select %s from %I.%I p%s where p%s.%I = %s.%I)', sub, k.parent_sch, k.parent_tbl, p_depth, p_depth, k.parent_col, p_alias, k.child_col);
        exit;
      end if;
    end loop;
  end if;
  if par is not null and own is not null then return format('coalesce(%s, %s)', par, own); end if;
  return coalesce(par, own);
end $$;
revoke all on function console.yb_date_expr(text, text, text, int) from public, anon, authenticated;

-- is (app, table) in the backup → its schema and key column (null = no); stops any other table name being used
create or replace function console.yb_check(p_app text, p_tbl text, out sch text, out tbl text, out key text) language plpgsql stable security definer set search_path = console, public as $$
begin
  select t.sch, t.tbl, t.key into sch, tbl, key from console.yb_tables(p_app) t where t.tbl = p_tbl limit 1;
  if tbl is null then raise exception 'Unknown table % for app %.', p_tbl, p_app; end if;
end $$;
revoke all on function console.yb_check(text, text) from public, anon, authenticated;

-- ---------- 1. plan: which apps the company has, their tables in restore order, and how many records fall in each financial year ----------
create or replace function public.kmr_yb_plan(p_slug text) returns jsonb language plpgsql stable security definer set search_path = console, public set statement_timeout = '110s' as $$
declare cid uuid := console.yb_target(p_slug); a text; ref uuid; tl jsonb; s text; t text; k record; ex text; by_fy jsonb; n bigint; smp text; res jsonb := '[]';
begin
  foreach a in array console.yb_apps() loop
    ref := console.yb_ref(cid, a);
    if ref is null then continue; end if;
    tl := '[]';
    foreach s in array console.yb_sorted(a) loop
      select * into k from console.yb_check(a, split_part(s, '.', 2));
      ex := console.yb_date_expr(k.sch, k.tbl, 'x');
      smp := case when exists (select 1 from pg_attribute where attrelid = s::regclass and attname = 'sample' and not attisdropped and atttypid = 'boolean'::regtype) then ' and not coalesce(x.sample, false)' else '' end;
      execute format('select coalesce(jsonb_object_agg(fy, n), ''{}''), coalesce(sum(n), 0) from (select %s as fy, count(*) as n from %I.%I x where x.%I = $1%s group by 1) q',
                     case when ex is null then '''Masters''' else format('console.yb_fy(%s)', ex) end, k.sch, k.tbl, k.key, smp) into by_fy, n using ref;
      if n > 0 then tl := tl || jsonb_build_array(jsonb_build_object('t', k.tbl, 'rows', n, 'fy', by_fy)); end if;
    end loop;
    if jsonb_array_length(tl) > 0 then res := res || jsonb_build_array(jsonb_build_object('app', a, 'tables', tl)); end if;
  end loop;
  return jsonb_build_object('company', lower(p_slug), 'basis', 'Apr-Mar', 'apps', res);
end $$;
revoke all on function public.kmr_yb_plan(text) from public, anon;
grant execute on function public.kmr_yb_plan(text) to authenticated;

-- ---------- 2. export: one page of one table (every row carries its financial year as _fy and its date as _d; the portal removes them from the files) ----------
create or replace function public.kmr_yb_export(p_slug text, p_app text, p_table text, p_offset int, p_limit int) returns jsonb
language plpgsql stable security definer set search_path = console, public set statement_timeout = '110s' as $$
declare cid uuid := console.yb_target(p_slug); ref uuid := console.yb_ref(cid, p_app); k record; ex text; pk text; smp text; rows jsonb;
begin
  if ref is null then raise exception 'Your company does not have this app.'; end if;
  select * into k from console.yb_check(p_app, p_table);
  ex := console.yb_date_expr(k.sch, k.tbl, 'x');
  select string_agg(format('x.%I', a.attname), ', ' order by array_position(i.indkey::int[], a.attnum::int)) into pk
    from pg_index i join pg_attribute a on a.attrelid = i.indrelid and a.attnum = any (i.indkey) where i.indrelid = format('%I.%I', k.sch, k.tbl)::regclass and i.indisprimary;
  smp := case when exists (select 1 from pg_attribute where attrelid = format('%I.%I', k.sch, k.tbl)::regclass and attname = 'sample' and not attisdropped and atttypid = 'boolean'::regtype) then ' and not coalesce(x.sample, false)' else '' end;
  execute format('select coalesce(jsonb_agg(to_jsonb(x) - %L || jsonb_build_object(''_fy'', %s, ''_d'', %s)), ''[]'') from (select * from %I.%I x where x.%I = $1%s order by %s offset $2 limit $3) x',
                 k.key, case when ex is null then '''Masters''' else format('console.yb_fy(%s)', ex) end, case when ex is null then 'null' else format('to_char(%s, ''YYYY-MM-DD'')', ex) end,
                 k.sch, k.tbl, k.key, smp, coalesce(pk, 'x.ctid')) into rows using ref, greatest(p_offset, 0), least(greatest(p_limit, 1), 5000);
  return rows;
end $$;
revoke all on function public.kmr_yb_export(text, text, text, int, int) from public, anon;
grant execute on function public.kmr_yb_export(text, text, text, int, int) to authenticated;

-- ---------- 3. import: add + update only. Every row goes into THIS company's workspace whatever the file says; nothing is deleted. ----------
create or replace function public.kmr_yb_import(p_slug text, p_app text, p_table text, p_rows jsonb) returns jsonb
language plpgsql security definer set search_path = console, public set statement_timeout = '110s' as $$
declare cid uuid := console.yb_target(p_slug); ref uuid := console.yb_ref(cid, p_app); k record; rel regclass; cols text; upd text; pk text; n bigint := 0; rws jsonb; mode text := 'replica';
begin
  if ref is null then raise exception 'Your company does not have this app.'; end if;
  if jsonb_typeof(p_rows) <> 'array' then raise exception 'No rows.'; end if;
  select * into k from console.yb_check(p_app, p_table);
  rel := format('%I.%I', k.sch, k.tbl)::regclass;
  -- every row into this company / workspace
  rws := (select coalesce(jsonb_agg((r - '_fy' - '_d') || jsonb_build_object(k.key, ref)), '[]') from jsonb_array_elements(p_rows) r);
  select string_agg(format('%I', a.attname), ', ' order by a.attnum) into cols from pg_attribute a
   where a.attrelid = rel and a.attnum > 0 and not a.attisdropped and a.attgenerated = '' and a.attidentity = '';
  select string_agg(format('%I', a.attname), ', ' order by array_position(i.indkey::int[], a.attnum::int)) into pk
    from pg_index i join pg_attribute a on a.attrelid = i.indrelid and a.attnum = any (i.indkey) where i.indrelid = rel and i.indisprimary;
  select string_agg(format('%1$I = excluded.%1$I', a.attname), ', ') into upd from pg_attribute a
   where a.attrelid = rel and a.attnum > 0 and not a.attisdropped and a.attgenerated = '' and a.attidentity = ''
     and not exists (select 1 from pg_index i where i.indrelid = rel and i.indisprimary and a.attnum = any (i.indkey));
  begin set local session_replication_role = replica; exception when others then mode := 'ordered'; end;   -- parents come first anyway
  execute format('insert into %s (%s) select %s from jsonb_populate_recordset(null::%s, $1) %s', rel, cols, cols, rel,
                 case when pk is not null and upd is not null then format('on conflict (%s) do update set %s', pk, upd) else 'on conflict do nothing' end) using rws;
  get diagnostics n = row_count;
  return jsonb_build_object('rows', n, 'mode', mode);
end $$;
revoke all on function public.kmr_yb_import(text, text, text, jsonb) from public, anon;
grant execute on function public.kmr_yb_import(text, text, text, jsonb) to authenticated;
