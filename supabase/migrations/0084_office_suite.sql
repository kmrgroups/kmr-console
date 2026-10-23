-- =====================================================================
-- 0084 — KMR Office Suite (a new KMR App, for any company: each company sees only its own files)
--  • Documents, Spreadsheets and Presentations that are written, opened and saved in the browser, with the same sign-in as the other apps.
--  • Every file is numbered (OFF-DOC/26-27/0001, OFF-XLS/..., OFF-PPT/...), keeps its last 15 revisions, and cannot be overwritten silently:
--    if two people edit the same file, the second save is refused with a plain message and nothing is lost.
--  • Rules in plain words: viewers can open files only; editors can create, change and delete their own files; an administrator can delete any file and
--    changes the Setup (number prefix, financial-year numbering, page size, report header and footer).
--  • No sample data (a file is the user's own work). Included in Data Master export, flush and restore.
-- Needs 0082 (and 0083 is not required). Safe to re-run.
-- =====================================================================
do $$ begin
  if to_regprocedure('console.aud_today()') is null then raise exception 'Run 0082_internal_audit.sql first.'; end if;
end $$;
insert into console.products (code, name, description, app_path, seat_label, current_version, sort_order) values
  ('off', 'KMR Office Suite', 'Documents, spreadsheets and presentations in the browser, saved per company with numbering, revisions and printing on the company format', '/it/office.html', 'users', '1.0.0', 18)
on conflict (code) do nothing;
insert into console.releases (product_code, version, notes) values
  ('off', '1.0.0', 'KMR Office Suite: documents, spreadsheets (formulas, charts, filters, templates) and presentations; Word, Excel and PowerPoint file import and export; revisions and printing') on conflict do nothing;
insert into console.prices (product_code, period, currency, unit_amount, min_seats, active, note)
select v.code, v.period, 'INR', v.amt, 3, true, 'Starting price list (0084) — per user, change in Console › Billing'
  from (values ('off', 'month', 60), ('off', 'year', 600)) v(code, period, amt)
 where not exists (select 1 from console.prices x where x.product_code = v.code and x.currency = 'INR' and x.period = v.period)
on conflict (product_code, period, currency) do nothing;
insert into public.app_listings (code, name, tagline, features, sort_order, is_active) values
  ('off', 'KMR Office Suite', 'Write documents, build spreadsheets and make presentations in your browser, with your files kept safely per company.',
   E'Documents with styles, tables, pictures, headers and footers, and Word file import and export\nSpreadsheets with formulas, charts, filters, sorting and ready-made templates, and Excel file import and export\nPresentations with themes, shapes, tables, notes and slide show, and PowerPoint file import and export\nNumbered files, revision history and printing on the company format', 18, true)
on conflict (code) do update set name = excluded.name, tagline = excluded.tagline, features = excluded.features, is_active = true;
insert into console.app_features (product_code, name, detail, is_core, price_month, price_year, setup_fee, sort_order) values
  ('off', 'Documents, Spreadsheets and Presentations', 'All three editors, file list, numbering, revision history, import and export of Word, Excel and PowerPoint files, printing', true, 20, 0, 5000, 10)
on conflict (product_code, name) do nothing;
delete from console.app_features f where f.product_code = 'off' and f.name = 'Core platform' and not exists (select 1 from console.invoice_lines il where il.feature_id = f.id);
update console.app_features set price_year = price_month * 10 where product_code = 'off' and price_year = 0;
select console.sync_app_price('off');

create table if not exists console.off_counters (
  customer_id uuid not null references console.customers(id) on delete cascade, key text not null, n bigint not null default 0, sample boolean not null default false, primary key (customer_id, key));
create table if not exists console.off_settings (
  customer_id uuid primary key references console.customers(id) on delete cascade, data jsonb not null default '{}', sample boolean not null default false, updated_at timestamptz not null default now());
create table if not exists console.off_files (
  id uuid primary key default gen_random_uuid(), customer_id uuid not null references console.customers(id) on delete cascade,
  kind text not null check (kind in ('doc', 'sheet', 'slide')), name text not null, no text not null, rev integer not null default 1, body jsonb not null,
  sample boolean not null default false, created_by text, created_at timestamptz not null default now(), updated_by text, updated_at timestamptz not null default now(), unique (customer_id, no));
create index if not exists off_files_list on console.off_files (customer_id, kind, updated_at desc);
create table if not exists console.off_versions (
  id uuid primary key default gen_random_uuid(), customer_id uuid not null references console.customers(id) on delete cascade,
  file_id uuid not null references console.off_files(id) on delete cascade, rev integer not null, body jsonb not null, at timestamptz not null default now(), by text,
  sample boolean not null default false, unique (file_id, rev));
create index if not exists off_versions_file on console.off_versions (file_id, rev desc);
do $$ declare t text; begin foreach t in array array['off_counters','off_settings','off_files','off_versions'] loop
  execute format('alter table console.%I enable row level security', t);
  execute format('drop policy if exists %I on console.%I', t || '_staff', t);
  execute format('create policy %I on console.%I for all to authenticated using (console.is_staff()) with check (console.is_staff())', t || '_staff', t);
end loop; end $$;

-- ================= helpers =================
create or replace function console.off_next(p_cid uuid, p_key text) returns bigint language sql security definer set search_path = console, public as $$
  insert into console.off_counters (customer_id, key, n) values (p_cid, p_key, 1)
  on conflict (customer_id, key) do update set n = console.off_counters.n + 1 returning n $$;
create or replace function console.off_cfg(p_cid uuid) returns jsonb language sql stable security definer set search_path = console, public as $$
  select coalesce((select data from console.off_settings where customer_id = p_cid), '{}'::jsonb) $$;
create or replace function console.off_txt(p jsonb, k text) returns text language sql immutable as $$ select nullif(trim(coalesce(p ->> k, '')), '') $$;

-- the next file number: PREFIX-DOC/26-27/0001 (financial year, April to March) or PREFIX-DOC-0001; DOC, XLS or PPT by kind
create or replace function console.off_number(p_cid uuid, p_kind text) returns text language plpgsql security definer set search_path = console, public as $$
declare cfg jsonb := console.off_cfg(p_cid); pre text; c text; d date := console.aud_today(); y int; fyt text; n bigint; use_fy boolean := true;
begin
  c := case p_kind when 'doc' then 'DOC' when 'sheet' then 'XLS' when 'slide' then 'PPT' else null end;
  if c is null then raise exception 'Unknown file type.'; end if;
  pre := upper(regexp_replace(coalesce(console.off_txt(cfg, 'prefix'), 'OFF'), '[^A-Za-z0-9-]', '', 'g')); if pre = '' then pre := 'OFF'; end if;
  if jsonb_typeof(cfg -> 'fy_numbering') = 'boolean' then use_fy := (cfg ->> 'fy_numbering')::boolean; end if;
  if use_fy then
    y := extract(year from d)::int; if extract(month from d) < 4 then y := y - 1; end if;
    fyt := lpad((y % 100)::text, 2, '0') || '-' || lpad(((y + 1) % 100)::text, 2, '0');
    n := console.off_next(p_cid, c || fyt);
    return pre || '-' || c || '/' || fyt || '/' || lpad(n::text, 4, '0');
  end if;
  n := console.off_next(p_cid, c);
  return pre || '-' || c || '-' || lpad(n::text, 4, '0');
end $$;
create or replace function console.off_meta(r console.off_files) returns jsonb language sql stable as $$
  select jsonb_build_object('id', r.id, 'kind', r.kind, 'name', r.name, 'no', r.no, 'rev', r.rev, 'size', pg_column_size(r.body),
    'updated_at', r.updated_at, 'updated_by', r.updated_by, 'created_by', r.created_by) $$;

-- ================= calls from the app =================
create or replace function public.kmr_off_enabled(p_slug text) returns boolean language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  return cid is not null and console.qp_role(cid, 'off') is not null;
end $$;
create or replace function public.kmr_off_load(p_slug text) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'off'); cfg jsonb := console.off_cfg(cid);
begin
  return jsonb_build_object('role', console.qp_role(cid, 'off'), 'me', console.aud_me(), 'today', console.aud_today(),
    'settings', jsonb_build_object('prefix', coalesce(console.off_txt(cfg, 'prefix'), 'OFF'), 'fy_numbering', coalesce((cfg ->> 'fy_numbering')::boolean, true),
      'page_size', coalesce(console.off_txt(cfg, 'page_size'), 'A4'), 'header', coalesce(console.off_txt(cfg, 'header'), ''), 'footer', coalesce(console.off_txt(cfg, 'footer'), '')));
end $$;
create or replace function public.kmr_off_settings_save(p_slug text, p jsonb) returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'off'); pre text; ps text;
begin
  if console.qp_role(cid, 'off') <> 'admin' then raise exception 'Only an administrator can change the setup.'; end if;
  if jsonb_typeof(p) <> 'object' then raise exception 'Settings must be an object.'; end if;
  if length(p::text) > 20000 then raise exception 'The settings are too large.'; end if;
  pre := upper(regexp_replace(coalesce(console.off_txt(p, 'prefix'), 'OFF'), '[^A-Za-z0-9-]', '', 'g')); if pre = '' then pre := 'OFF'; end if;
  if length(pre) > 12 then raise exception 'The number prefix can have at most 12 letters or digits.'; end if;
  ps := coalesce(console.off_txt(p, 'page_size'), 'A4'); if ps not in ('A4', 'A3', 'Letter', 'Legal') then raise exception 'Page size must be A4, A3, Letter or Legal.'; end if;
  if p ? 'fy_numbering' and jsonb_typeof(p -> 'fy_numbering') <> 'boolean' then raise exception 'Financial-year numbering must be on or off.'; end if;
  insert into console.off_settings (customer_id, data) values (cid, jsonb_build_object('prefix', pre, 'fy_numbering', coalesce((p ->> 'fy_numbering')::boolean, true), 'page_size', ps,
    'header', left(coalesce(console.off_txt(p, 'header'), ''), 300), 'footer', left(coalesce(console.off_txt(p, 'footer'), ''), 300)))
  on conflict (customer_id) do update set data = excluded.data, updated_at = now();
end $$;
create or replace function public.kmr_off_list(p_slug text, p jsonb default '{}') returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'off'); k text := console.off_txt(p, 'kind'); q text := lower(coalesce(console.off_txt(p, 'q'), ''));
begin
  return jsonb_build_object('files', coalesce((select jsonb_agg(console.off_meta(f) order by f.updated_at desc) from (
    select * from console.off_files x where x.customer_id = cid and (k is null or x.kind = k) and (q = '' or lower(x.name || ' ' || x.no) like '%' || q || '%')
     order by x.updated_at desc limit 500) f), '[]'));
end $$;
create or replace function public.kmr_off_get(p_slug text, p_id uuid) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'off'); r console.off_files;
begin
  select * into r from console.off_files where id = p_id and customer_id = cid; if r.id is null then raise exception 'File not found.'; end if;
  return console.off_meta(r) || jsonb_build_object('body', r.body, 'can_edit', coalesce(console.qp_role(cid, 'off'), '') in ('admin', 'editor'));
end $$;
create or replace function public.kmr_off_save(p_slug text, p jsonb) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'off'); me text := console.aud_me(); r console.off_files; k text := console.off_txt(p, 'kind'); nm text := left(coalesce(console.off_txt(p, 'name'), 'Untitled'), 120);
        pid uuid; prev integer;
begin
  if jsonb_typeof(p -> 'body') is distinct from 'object' then raise exception 'Nothing to save.'; end if;
  if length((p -> 'body')::text) > 14 * 1048576 then raise exception 'This file is too large to save (limit 14 MB). Remove large pictures and try again.'; end if;
  if coalesce(p ->> 'id', '') = '' then
    if k is null or k not in ('doc', 'sheet', 'slide') then raise exception 'Unknown file type.'; end if;
    insert into console.off_files (customer_id, kind, name, no, rev, body, created_by, updated_by) values (cid, k, nm, console.off_number(cid, k), 1, p -> 'body', me, me) returning * into r;
    insert into console.off_versions (customer_id, file_id, rev, body, by) values (cid, r.id, 1, r.body, me);
    return jsonb_build_object('id', r.id, 'no', r.no, 'rev', r.rev);
  end if;
  pid := (p ->> 'id')::uuid;
  select * into r from console.off_files where id = pid and customer_id = cid for update; if r.id is null then raise exception 'File not found.'; end if;
  if coalesce(p ->> 'rev', '') <> '' and (p ->> 'rev')::integer <> r.rev then
    raise exception 'This file was changed by % at % while you were editing. Reload the file to see their changes.', coalesce(r.updated_by, 'someone'), to_char(r.updated_at at time zone 'Asia/Kolkata', 'HH24:MI');
  end if;
  prev := r.rev;
  update console.off_files set name = nm, body = p -> 'body', rev = rev + 1, updated_at = now(), updated_by = me where id = r.id returning * into r;
  insert into console.off_versions (customer_id, file_id, rev, body, by) values (cid, r.id, r.rev, r.body, me);
  delete from console.off_versions where file_id = r.id and rev <= r.rev - 15;
  return jsonb_build_object('id', r.id, 'no', r.no, 'rev', r.rev);
end $$;
create or replace function public.kmr_off_delete(p_slug text, p_id uuid) returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'off'); r console.off_files;
begin
  select * into r from console.off_files where id = p_id and customer_id = cid; if r.id is null then raise exception 'File not found.'; end if;
  if console.qp_role(cid, 'off') <> 'admin' and lower(coalesce(r.created_by, '')) <> console.aud_me() then raise exception 'Only the person who created a file, or an administrator, can delete it.'; end if;
  delete from console.off_files where id = r.id;
end $$;
create or replace function public.kmr_off_versions(p_slug text, p_id uuid) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'off');
begin
  if not exists (select 1 from console.off_files where id = p_id and customer_id = cid) then raise exception 'File not found.'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('rev', v.rev, 'at', v.at, 'by', v.by) order by v.rev desc) from console.off_versions v where v.file_id = p_id and v.customer_id = cid), '[]');
end $$;
create or replace function public.kmr_off_restore(p_slug text, p_id uuid, p_rev integer) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'off'); me text := console.aud_me(); r console.off_files; v console.off_versions;
begin
  select * into r from console.off_files where id = p_id and customer_id = cid for update; if r.id is null then raise exception 'File not found.'; end if;
  select * into v from console.off_versions where file_id = r.id and rev = p_rev; if v.id is null then raise exception 'That revision is no longer kept.'; end if;
  update console.off_files set body = v.body, rev = rev + 1, updated_at = now(), updated_by = me where id = r.id returning * into r;
  insert into console.off_versions (customer_id, file_id, rev, body, by) values (cid, r.id, r.rev, r.body, me);
  delete from console.off_versions where file_id = r.id and rev <= r.rev - 15;
  return jsonb_build_object('id', r.id, 'rev', r.rev);
end $$;
do $$ declare f text; begin
  foreach f in array array['kmr_off_enabled(text)', 'kmr_off_load(text)', 'kmr_off_settings_save(text, jsonb)', 'kmr_off_list(text, jsonb)', 'kmr_off_get(text, uuid)', 'kmr_off_save(text, jsonb)',
                           'kmr_off_delete(text, uuid)', 'kmr_off_versions(text, uuid)', 'kmr_off_restore(text, uuid, integer)'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;

-- ---------- platform functions: switch the new app on in the portal, access, Data Master and demo workspace ----------
-- Each function is read back from the database, the new app is added to its list of apps, and it is re-created. A function that already has it is left alone.
do $patch$
declare
  rec record; def text; nw text; n int := 0;
  list_pat constant text := $re$'d8',\s*('qms',\s*)?'aud'(?!\s*,\s*'off')$re$;
begin
  for rec in
    select p.oid, p.proname from pg_proc p join pg_namespace s on s.oid = p.pronamespace
     where (s.nspname = 'console' and p.proname in ('data_target', 'app2_tables', 'app2_clear', 'app2_export', 'demo_refresh'))
        or (s.nspname = 'public' and p.proname in ('kmr_qp_context', 'kmr_portal', 'kmr_portal_join', 'kmr_data_overview', 'kmr_data_export', 'kmr_data_flush', 'kmr_data_import',
                                                   'kmr_grand_overview', 'kmr_grand_real_export', 'kmr_grand_real_flush', 'kmr_grand_real_import', 'kmr_app_sample'))
  loop
    def := pg_get_functiondef(rec.oid); nw := def;
    -- the list of apps:  'd8', 'aud'  ->  'd8', 'aud', 'off'
    nw := regexp_replace(nw, list_pat, '\&, ''off''', 'g');
    if rec.proname = 'app2_tables' and position('off_files' in def) = 0 then
      nw := replace(nw, $a$'aud_log'] end$a$, $b$'aud_log'] when 'off' then array['off_counters','off_settings','off_files','off_versions'] end$b$);
    elsif rec.proname = 'app2_clear' and position('off_files' in def) = 0 then
      nw := replace(nw, $a$elsif p_app = 'aud' then$a$, $b$elsif p_app = 'off' then
    delete from console.off_versions where customer_id = p_cid and (not p_real_only or sample); get diagnostics k = row_count; n := n + k;
    delete from console.off_files where customer_id = p_cid and (not p_real_only or sample); get diagnostics k = row_count; n := n + k;
    if not p_real_only then delete from console.off_settings where customer_id = p_cid; delete from console.off_counters where customer_id = p_cid; end if;
  elsif p_app = 'aud' then$b$);
    elsif rec.proname = 'app2_export' and position('off\_%' in def) = 0 then
      nw := replace(nw, $a$t like 'aud\_%'$a$, $b$t like 'aud\_%' or t like 'off\_%'$b$);
    elsif rec.proname in ('kmr_portal', 'kmr_portal_join') and position('''off''' in def) = 0 then
      nw := regexp_replace(nw, $re$(\n\s*when 'aud'\s+then console\.qp_member\(([a-z_.]+), em, 'aud'\))$re$, E'\\1\n     when ''off'' then console.qp_member(\\2, em, ''off'')', 'g');
    elsif rec.proname = 'kmr_app_sample' and position('''off''' in def) = 0 then
      nw := replace(nw, $a$elsif p_app = 'aud' then$a$, $b$elsif p_app = 'off' then out := jsonb_build_object('off', 0);
  elsif p_app = 'aud' then$b$);
    elsif rec.proname = 'kmr_grand_overview' and position('off_files' in def) = 0 then
      nw := replace(nw, $a$real_ := real_ || jsonb_build_object('aud', n); smp := smp || jsonb_build_object('aud', k);$a$,
        $b$real_ := real_ || jsonb_build_object('aud', n); smp := smp || jsonb_build_object('aud', k);
  end if;
  if console.has_app(cid, 'off') then
    select count(*) filter (where not sample), count(*) filter (where sample) into n, k from console.off_files where customer_id = cid;
    real_ := real_ || jsonb_build_object('off', n); smp := smp || jsonb_build_object('off', k);$b$);
    elsif rec.proname = 'kmr_grand_real_flush' and position('off_files' in def) = 0 then
      nw := replace(nw, $a$perform console.app2_clear('aud', cid, true); out := out || jsonb_build_object('aud', n);$a$,
        $b$perform console.app2_clear('aud', cid, true); out := out || jsonb_build_object('aud', n);
  end if;
  if console.has_app(cid, 'off') then
    select count(*) into n from console.off_files where customer_id = cid and not sample;
    perform console.app2_clear('off', cid, true); out := out || jsonb_build_object('off', n);$b$);
    elsif rec.proname = 'kmr_grand_real_import' and position('off_files' in def) = 0 then
      nw := replace(nw, $a$else select count(*) into n from console.aud_audits where customer_id = cid and not sample; end if;$a$,
        $b$elsif t = 'off' then select count(*) into n from console.off_files where customer_id = cid and not sample;
    else select count(*) into n from console.aud_audits where customer_id = cid and not sample; end if;$b$);
    end if;
    if nw <> def then execute nw; n := n + 1; end if;
  end loop;
  raise notice 'Office Suite: % platform functions updated', n;
end $patch$;
-- the checks below stop the migration when a platform function was not changed as expected (nothing is left half done)
do $$ begin
  if position('''off''' in pg_get_functiondef('console.data_target(text,text)'::regprocedure)) = 0 then raise exception 'data_target was not updated'; end if;
  if position('off_files' in pg_get_functiondef('console.app2_tables(text)'::regprocedure)) = 0 then raise exception 'app2_tables was not updated'; end if;
  if position('off_files' in pg_get_functiondef('console.app2_clear(text,uuid,boolean)'::regprocedure)) = 0 then raise exception 'app2_clear was not updated'; end if;
  if position('''off''' in pg_get_functiondef('public.kmr_qp_context(text,text)'::regprocedure)) = 0 then raise exception 'kmr_qp_context was not updated'; end if;
  if position('''off''' in pg_get_functiondef('public.kmr_portal(text)'::regprocedure)) = 0 then raise exception 'kmr_portal was not updated'; end if;
end $$;
